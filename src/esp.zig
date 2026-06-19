const sys = @import("sys.zig");
const utils = @import("utils.zig");

const O_RDWR: i32 = 2;
const O_NOCTTY: i32 = 0x100;

const CBAUD: u32 = 0x100F;
const B115200: u32 = 0x1002;
const CREAD: u32 = 0x80;
const CLOCAL: u32 = 0x800;
const CSIZE: u32 = 0x30;
const CS8: u32 = 0x30;
const PARENB: u32 = 0x200;
const CSTOPB: u32 = 0x40;
const HUPCL: u32 = 0x400;
const IGNBRK: u32 = 0x1;
const BRKINT: u32 = 0x2;
const PARMRK: u32 = 0x8;
const ISTRIP: u32 = 0x20;
const INLCR: u32 = 0x40;
const IGNCR: u32 = 0x80;
const ICRNL: u32 = 0x100;
const IXON: u32 = 0x400;
const OPOST: u32 = 0x1;
const ECHO: u32 = 0x8;
const ECHONL: u32 = 0x40;
const ICANON: u32 = 0x2;
const ISIG: u32 = 0x1;
const IEXTEN: u32 = 0x8000;

const VMIN_IX: usize = 6;
const VTIME_IX: usize = 5;

const SLIP_END: u8 = 0xC0;
const SLIP_ESC: u8 = 0xDB;
const SLIP_ESC_END: u8 = 0xDC;
const SLIP_ESC_ESC: u8 = 0xDD;

const CMD_SYNC: u8 = 0x08;
const CMD_FLASH_BEGIN: u8 = 0x02;
const CMD_FLASH_DATA: u8 = 0x03;
const CMD_FLASH_END: u8 = 0x04;

const MAX_PKT_SIZE: u32 = 4096;
const SYNC_RETRIES: u32 = 15;

const PT_LOAD: u32 = 1;
const ELF_MAGIC: u32 = 0x464C457F;

fn serialOpen(port: []const u8) i32 {
    var np: [256]u8 = @splat(0);
    var i: usize = 0;
    while (i < port.len and i < 255) : (i += 1) np[i] = port[i];
    const fd = sys.open(&np, O_RDWR | O_NOCTTY, 0);
    if (fd < 0) return fd;

    var t: sys.Termios = undefined;
    if (sys.tcgetattr(fd, &t) < 0) { sys.close(fd); return -1; }

    t.cflag &= ~(CBAUD | CSIZE | PARENB | CSTOPB | HUPCL);
    t.cflag |= CREAD | CLOCAL | CS8 | B115200;

    t.iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
    t.oflag &= ~OPOST;
    t.lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);

    t.cc[VMIN_IX] = 1;
    t.cc[VTIME_IX] = 0;

    if (sys.tcsetattr(fd, &t) < 0) { sys.close(fd); return -1; }
    return fd;
}

fn readByteT(fd: i32, ms: i32) ?u8 {
    var pfd = [_]sys.PollFd{.{ .fd = fd, .events = sys.POLLIN, .revents = 0 }};
    return if (sys.poll(&pfd, 1, ms) > 0) blk: {
        var b: [1]u8 = undefined;
        break :blk if (sys.read(fd, &b, 1) == 1) b[0] else null;
    } else null;
}

fn slipSend(fd: i32, data: []const u8) bool {
    var enc: [32768]u8 = undefined;
    var pos: usize = 0;
    enc[pos] = SLIP_END; pos += 1;
    for (data) |b| {
        if (b == SLIP_END) { enc[pos] = SLIP_ESC; pos += 1; enc[pos] = SLIP_ESC_END; pos += 1; }
        else if (b == SLIP_ESC) { enc[pos] = SLIP_ESC; pos += 1; enc[pos] = SLIP_ESC_ESC; pos += 1; }
        else { enc[pos] = b; pos += 1; }
    }
    enc[pos] = SLIP_END; pos += 1;
    return sys.write(fd, &enc, pos) == @as(isize, @intCast(pos));
}

fn slipRecv(fd: i32, buf: []u8, ms: i32) ?usize {
    var pos: usize = 0;
    var esc = false;

    while (pos < buf.len) {
        const b = readByteT(fd, ms) orelse return if (pos > 0) pos else null;
        if (b == SLIP_END) {
            if (pos > 0) return pos;
            continue;
        }
        if (esc) {
            if (b == SLIP_ESC_END) { if (pos < buf.len) { buf[pos] = SLIP_END; pos += 1; } }
            else if (b == SLIP_ESC_ESC) { if (pos < buf.len) { buf[pos] = SLIP_ESC; pos += 1; } }
            esc = false;
        } else if (b == SLIP_ESC) {
            esc = true;
        } else {
            if (pos < buf.len) { buf[pos] = b; pos += 1; }
        }
    }
    return null;
}

fn buildCmdPkt(dir: u8, cmd: u8, data: []const u8, buf: []u8) usize {
    var pos: usize = 0;
    buf[pos] = dir; pos += 1;
    buf[pos] = cmd; pos += 1;
    buf[pos] = @as(u8, @truncate(data.len)); pos += 1;
    buf[pos] = @as(u8, @truncate(data.len >> 8)); pos += 1;
    var chk: u16 = 0;
    for (data) |b| chk +%= b;
    buf[pos] = @as(u8, @truncate(chk)); pos += 1;
    buf[pos] = @as(u8, @truncate(chk >> 8)); pos += 1;
    for (data) |b| { buf[pos] = b; pos += 1; }
    return pos;
}

fn readRespStatus(fd: i32) ?u16 {
    var resp: [256]u8 = undefined;
    const rlen = slipRecv(fd, &resp, 2000) orelse return null;
    if (rlen < 6) return null;
    if (resp[0] != 0x01) return null;
    if (rlen < 8) return null;
    return @as(u16, @intCast(resp[6])) | (@as(u16, @intCast(resp[7])) << 8);
}

fn espCmd(fd: i32, cmd: u8, data: []const u8) bool {
    var pkt: [16384]u8 = undefined;
    const plen = buildCmdPkt(0x00, cmd, data, &pkt);
    if (!slipSend(fd, pkt[0..plen])) return false;
    const st = readRespStatus(fd) orelse return false;
    return st == 0;
}

fn espSync(fd: i32) bool {
    var sync: [36]u8 = @splat(0x07);
    var pkt: [128]u8 = undefined;
    const plen = buildCmdPkt(0x00, CMD_SYNC, &sync, &pkt);

    var i: u32 = 0;
    while (i < SYNC_RETRIES) : (i += 1) {
        _ = slipSend(fd, pkt[0..plen]);
        var w: u32 = 0;
        while (w < 200) : (w += 1) {
            const st = readRespStatus(fd);
            if (st != null and st.? == 0) return true;
        }
    }
    return false;
}

fn espFlashBegin(fd: i32, size: u32, offset: u32) bool {
    const erase_size = (size + 0xFFF) & ~@as(u32, 0xFFF);
    const npkts = (size + MAX_PKT_SIZE - 1) / MAX_PKT_SIZE;
    var d: [16]u8 = undefined;
    d[0..4].* = @as([4]u8, @bitCast(erase_size));
    d[4..8].* = @as([4]u8, @bitCast(npkts));
    d[8..12].* = @as([4]u8, @bitCast(MAX_PKT_SIZE));
    d[12..16].* = @as([4]u8, @bitCast(offset));
    return espCmd(fd, CMD_FLASH_BEGIN, &d);
}

fn espFlashData(fd: i32, seq: u32, data: []const u8) bool {
    var pkt: [16384]u8 = undefined;
    pkt[0..4].* = @as([4]u8, @bitCast(seq));
    var i: usize = 0;
    while (i < data.len) : (i += 1) pkt[4 + i] = data[i];
    return espCmd(fd, CMD_FLASH_DATA, pkt[0 .. 4 + data.len]);
}

fn espFlashEnd(fd: i32, reboot: bool) bool {
    var d: [4]u8 = undefined;
    const flag: u32 = if (reboot) 0 else 1;
    d[0..4].* = @as([4]u8, @bitCast(flag));
    return espCmd(fd, CMD_FLASH_END, &d);
}

fn writeFlash(fd: i32, data: []const u8, offset: u32) bool {
    if (!espFlashBegin(fd, @as(u32, @intCast(data.len)), offset)) {
        sys.writeStr(2, "flash begin failed\n", 19);
        return false;
    }
    var pos: usize = 0;
    var seq: u32 = 0;
    while (pos < data.len) : (seq += 1) {
        const rem = data.len - pos;
        const sz = if (rem > MAX_PKT_SIZE) @as(usize, @intCast(MAX_PKT_SIZE)) else rem;
        const chunk = data[pos..][0..sz];
        if (!espFlashData(fd, seq, chunk)) {
            sys.writeStr(2, "flash data fail\n", 16);
            return false;
        }
        pos += sz;
    }
    _ = espFlashEnd(fd, true);
    return true;
}

fn readFile(path: []const u8, buf: []u8) ?usize {
    var np: [256]u8 = @splat(0);
    var i: usize = 0;
    while (i < path.len and i < 255) : (i += 1) np[i] = path[i];
    np[i] = 0;
    const fd = sys.open(&np, 0, 0);
    if (fd < 0) return null;
    defer sys.close(fd);
    const n = sys.read(fd, buf.ptr, buf.len);
    return if (n < 0) null else @as(usize, @intCast(n));
}

fn extractElf32Data(elf: []const u8) ?struct { offset: u32, data: []const u8, entry: u32 } {
    if (elf.len < 52) return null;
    if (@as(u32, @bitCast(elf[0..4].*)) != ELF_MAGIC) return null;
    if (elf[4] != 1) return null;
    const phoff = @as(u32, @bitCast(elf[28..32].*));
    const phnum = @as(u16, @bitCast(elf[44..46].*));
    const phent = @as(u16, @bitCast(elf[42..44].*));
    const entry = @as(u32, @bitCast(elf[24..28].*));
    if (phoff > elf.len or phnum == 0 or phent < 32) return null;
    var i: u32 = 0;
    while (i < phnum) : (i += 1) {
        const phpos = @as(usize, @intCast(phoff + i * phent));
        if (phpos + 32 > elf.len) return null;
        const p_type = @as(u32, @bitCast(elf[phpos..][0..4].*));
        if (p_type != PT_LOAD) continue;
        const p_offset = @as(u32, @bitCast(elf[phpos + 4 ..][0..4].*));
        const p_paddr = @as(u32, @bitCast(elf[phpos + 12 ..][0..4].*));
        const p_filesz = @as(u32, @bitCast(elf[phpos + 16 ..][0..4].*));
        if (p_offset + p_filesz > elf.len) return null;
        return .{ .offset = p_paddr, .data = elf[@as(usize, @intCast(p_offset))..@as(usize, @intCast(p_offset + p_filesz))], .entry = entry };
    }
    return null;
}

fn fmtHex(val: u32, buf: [*]u8) usize {
    const hex = "0123456789abcdef";
    var tmp: [8]u8 = undefined;
    var i: usize = 0;
    var v = val;
    if (v == 0) { buf[0] = '0'; return 1; }
    while (v > 0) : (v >>= 4) { tmp[i] = hex[v & 0xF]; i += 1; }
    var j: usize = 0;
    while (j < i) : (j += 1) buf[j] = tmp[i - 1 - j];
    return i;
}

pub fn flashElf(port: []const u8, elf_path: []const u8) bool {
    var elf_buf: [65536]u8 = undefined;
    const elen = readFile(elf_path, &elf_buf) orelse {
        sys.writeStr(2, "cannot read ELF\n", 16);
        return false;
    };
    const seg = extractElf32Data(elf_buf[0..elen]) orelse {
        sys.writeStr(2, "no PT_LOAD segment\n", 19);
        return false;
    };
    sys.writeStr(1, "open ", 5);
    sys.writeStr(1, port.ptr, port.len);
    sys.writeStr(1, "...\n", 4);
    const fd = serialOpen(port);
    if (fd < 0) { sys.writeStr(2, "cannot open port\n", 17); return false; }
    defer sys.close(fd);
    sys.writeStr(1, "sync...\n", 8);
    if (!espSync(fd)) { sys.writeStr(2, "sync failed\n", 12); return false; }
    sys.writeStr(1, "flash ", 6);
    var sb: [16]u8 = undefined;
    const sl = utils.formatU32(@as(u32, @intCast(seg.data.len)), &sb);
    sys.writeStr(1, &sb, sl);
    sys.writeStr(1, "b @0x", 5);
    var ob: [16]u8 = undefined;
    const ol = fmtHex(seg.offset, &ob);
    sys.writeStr(1, ob[0..ol].ptr, ol);
    sys.writeStr(1, "...\n", 4);
    if (!writeFlash(fd, seg.data, seg.offset)) return false;
    sys.writeStr(1, "ok!\n", 4);
    return true;
}
