const sys = @import("sys.zig");

fn write16(buf: []u8, off: usize, val: u16) void {
    buf[off + 0] = @as(u8, @truncate(val));
    buf[off + 1] = @as(u8, @truncate(val >> 8));
}

fn write32(buf: []u8, off: usize, val: u32) void {
    buf[off + 0] = @as(u8, @truncate(val));
    buf[off + 1] = @as(u8, @truncate(val >> 8));
    buf[off + 2] = @as(u8, @truncate(val >> 16));
    buf[off + 3] = @as(u8, @truncate(val >> 24));
}

fn read16(buf: []const u8, off: usize) u16 {
    return @as(u16, buf[off + 0]) | (@as(u16, buf[off + 1]) << 8);
}

fn read16BE(buf: []const u8, off: usize) u16 {
    return @as(u16, buf[off + 1]) | (@as(u16, buf[off + 0]) << 8);
}

fn read32(buf: []const u8, off: usize) u32 {
    return @as(u32, buf[off + 0]) | (@as(u32, buf[off + 1]) << 8) | (@as(u32, buf[off + 2]) << 16) | (@as(u32, buf[off + 3]) << 24);
}

fn writeAll(fd: i32, data: []const u8) void {
    var off: usize = 0;
    while (off < data.len) {
        const n = sys.write(fd, data.ptr + off, data.len - off);
        if (n <= 0) break;
        off += @as(usize, @intCast(n));
    }
}

fn readExact(fd: i32, buf: []u8) bool {
    var off: usize = 0;
    while (off < buf.len) {
        const n = sys.read(fd, buf.ptr + off, buf.len - off);
        if (n <= 0) return false;
        off += @as(usize, @intCast(n));
    }
    return true;
}

fn intToStr(n: i32, buf: []u8) usize {
    if (n == 0) { buf[0] = '0'; return 1; }
    var tmp: [16]u8 = undefined;
    var i: usize = 0;
    var v = n;
    while (v != 0) : (v = @divTrunc(v, 10)) {
        tmp[i] = @as(u8, @intCast(@rem(v, 10))) + '0';
        i += 1;
    }
    var j: usize = 0;
    while (j < i) : (j += 1) buf[j] = tmp[i - 1 - j];
    return i;
}

const XAUTH_FAMILY_LOCAL: u16 = 0;
const XAUTH_FAMILY_WILD: u16 = 1;

const AuthInfo = struct { name: [32]u8, name_len: u16, data: [32]u8, data_len: u16 };

fn findAuth(display_num: i32, home: []const u8) ?AuthInfo {
    var path: [512]u8 = undefined;
    var pi: usize = 0;
    for (home) |c| { path[pi] = c; pi += 1; if (pi >= 500) break; }
    const suffix = "/.Xauthority";
    for (suffix) |c| { path[pi] = c; pi += 1; if (pi >= 510) break; }
    path[pi] = 0;

    const fd = sys.open(&path, 0, 0);
    if (fd < 0) return null;
    defer sys.close(fd);

    var file: [4096]u8 = undefined;
    var flen: usize = 0;
    while (flen < file.len) {
        const n = sys.read(fd, file[flen..].ptr, file.len - flen);
        if (n <= 0) break;
        flen += @as(usize, @intCast(n));
    }
    if (flen < 8) return null;

    const family_be = read16BE(&file, 0);
    const family_le = read16(&file, 0);
    const alen_be = read16BE(&file, 2);
    const alen_le = read16(&file, 2);

    const big_endian = blk: {
        if (family_be == 0 or family_be == 1 or family_be == 256 or family_be == 65535) {
            if (alen_be < 256) break :blk true;
        }
        if (family_le == 0 or family_le == 1 or family_le == 256 or family_le == 65535) {
            if (alen_le < 256) break :blk false;
        }
        break :blk false;
    };

    var off: usize = 0;
    while (off + 6 <= flen) {
        const family = if (big_endian) read16BE(&file, off) else read16(&file, off); off += 2;
        const addr_len = if (big_endian) read16BE(&file, off) else read16(&file, off); off += 2;
        if (off + addr_len > flen) return null;
        off += addr_len;

        if (off + 2 > flen) return null;
        const disp_len = if (big_endian) read16BE(&file, off) else read16(&file, off); off += 2;
        if (off + disp_len > flen) return null;
        const disp = file[off..off + disp_len]; off += disp_len;

        if (off + 2 > flen) return null;
        const name_len = if (big_endian) read16BE(&file, off) else read16(&file, off); off += 2;
        if (off + name_len > flen) return null;
        const name = file[off..off + name_len]; off += name_len;

        if (off + 2 > flen) return null;
        const data_len = if (big_endian) read16BE(&file, off) else read16(&file, off); off += 2;
        if (off + data_len > flen) return null;
        const auth_data = file[off..off + data_len]; off += data_len;

        if (family == XAUTH_FAMILY_WILD or family == XAUTH_FAMILY_LOCAL or family == 256) {
            var disp_str: [16]u8 = undefined;
            const di = intToStr(display_num, &disp_str);
            if (disp.len == di) {
                var match = true;
                var mi: usize = 0;
                while (mi < di) : (mi += 1) {
                    if (disp[mi] != disp_str[mi]) { match = false; break; }
                }
                if (match and name.len <= 32 and auth_data.len <= 32) {
                    var result: AuthInfo = undefined;
                    result.name_len = @as(u16, @intCast(name.len));
                    result.data_len = @as(u16, @intCast(auth_data.len));
                    var k: usize = 0;
                    while (k < name.len) : (k += 1) result.name[k] = name[k];
                    k = 0;
                    while (k < auth_data.len) : (k += 1) result.data[k] = auth_data[k];
                    return result;
                }
            }
        }
    }
    return null;
}

pub const X11Conn = struct {
    fd: i32,
    root: u32,
    white_pixel: u32,
    black_pixel: u32,
    w: u32,
    h: u32,
    depth: u8,
    wid: u32,
    gc: u32,

    pub fn createWindow(self: *X11Conn, x: i16, y: i16, w: u16, h: u16) void {
        var buf: [40]u8 = undefined;
        buf[0] = 1; buf[1] = 0;
        write16(&buf, 2, 10);
        write32(&buf, 4, self.wid);
        write32(&buf, 8, self.root);
        write16(&buf, 12, @as(u16, @bitCast(x))); write16(&buf, 14, @as(u16, @bitCast(y)));
        write16(&buf, 16, w); write16(&buf, 18, h);
        write16(&buf, 20, 0); write16(&buf, 22, 1);
        buf[24] = 0; buf[25] = 0; buf[26] = 0; buf[27] = 0;
        write32(&buf, 28, 2 | 2048);
        write32(&buf, 32, self.black_pixel);
        write32(&buf, 36, 0x28003);
        writeAll(self.fd, &buf);
    }

    pub fn selectInput(self: *X11Conn, mask: u32) void {
        var buf: [16]u8 = undefined;
        buf[0] = 2; buf[1] = 0;
        write16(&buf, 2, 4);
        write32(&buf, 4, self.wid);
        write32(&buf, 8, 2048);
        write32(&buf, 12, mask);
        writeAll(self.fd, &buf);
    }

    pub fn mapWindow(self: *X11Conn) void {
        var buf: [8]u8 = undefined;
        buf[0] = 8; buf[1] = 0;
        write16(&buf, 2, 2);
        write32(&buf, 4, self.wid);
        writeAll(self.fd, &buf);
    }

    fn internAtom(self: *X11Conn, name: []const u8) u32 {
        const pad = (4 - (name.len % 4)) & 3;
        const req_len: u16 = @as(u16, @intCast(2 + (name.len + pad) / 4));
        var buf: [8]u8 = undefined;
        buf[0] = 16; buf[1] = 0;
        write16(&buf, 2, req_len);
        write16(&buf, 4, @as(u16, @intCast(name.len)));
        buf[6] = 0; buf[7] = 0;
        writeAll(self.fd, &buf);
        writeAll(self.fd, name);
        if (pad > 0) {
            var p: [4]u8 = undefined;
            writeAll(self.fd, p[0..pad]);
        }
        var resp: [8]u8 = undefined;
        if (!readExact(self.fd, &resp)) return 0;
        if (resp[0] != 1) return 0;
        var reply: [24]u8 = undefined;
        if (!readExact(self.fd, &reply)) return 0;
        return read32(&reply, 4);
    }

    fn changeProp(self: *X11Conn, prop: u32, typ: u32, fmt: u8, data: []const u8) void {
        const pad = (4 - (data.len % 4)) & 3;
        const hdr_len: u16 = @as(u16, @intCast(6 + (data.len + pad) / 4));
        var hdr: [24]u8 = undefined;
        hdr[0] = 18; hdr[1] = 0;
        write16(&hdr, 2, hdr_len);
        write32(&hdr, 4, self.wid);
        write32(&hdr, 8, prop);
        write32(&hdr, 12, typ);
        hdr[16] = fmt;
        write32(&hdr, 20, @as(u32, @intCast(data.len)));
        writeAll(self.fd, &hdr);
        writeAll(self.fd, data);
        if (pad > 0) {
            var p: [4]u8 = undefined;
            writeAll(self.fd, p[0..pad]);
        }
    }

    pub fn setTitle(self: *X11Conn, title: []const u8) void {
        self.changeProp(39, 31, 8, title);
        const net_wm_name = self.internAtom("_NET_WM_NAME");
        if (net_wm_name != 0) {
            const utf8_str = self.internAtom("UTF8_STRING");
            if (utf8_str != 0) self.changeProp(net_wm_name, utf8_str, 8, title);
        }
    }

    pub fn createGC(self: *X11Conn) void {
        var buf: [16]u8 = undefined;
        buf[0] = 55; buf[1] = 0;
        write16(&buf, 2, 4);
        write32(&buf, 4, self.gc);
        write32(&buf, 8, self.wid);
        write32(&buf, 12, 0);
        writeAll(self.fd, &buf);
    }

    pub fn putImage(self: *X11Conn, pixels: [*]u32, w: u32, h: u32) void {
        const row_pad = @as(u32, @intCast(@as(i32, -@as(i32, @intCast(w * 4))) & 3));
        const row_bytes = w * 4 + row_pad;
        const hdr_bytes: u32 = 24;
        const max_units: u32 = 65535;
        const max_rows_per_req = (max_units * 4 - hdr_bytes) / row_bytes;
        var y: u32 = 0;

        while (y < h) {
            const batch_h = if (h - y > max_rows_per_req) max_rows_per_req else h - y;
            const total = row_bytes * batch_h;
            const units: u16 = @as(u16, @intCast((hdr_bytes + total + 3) / 4));

            var hdr: [24]u8 = undefined;
            hdr[0] = 72; hdr[1] = 2;
            write16(&hdr, 2, units);
            write32(&hdr, 4, self.wid);
            write32(&hdr, 8, self.gc);
            write16(&hdr, 12, @as(u16, @intCast(w)));
            write16(&hdr, 14, @as(u16, @intCast(batch_h)));
            write16(&hdr, 16, 0); write16(&hdr, 18, @as(u16, @intCast(y)));
            hdr[20] = 0; hdr[21] = @as(u8, @intCast(self.depth));
            hdr[22] = 0; hdr[23] = 0;
            writeAll(self.fd, &hdr);

            var row: u32 = 0;
            while (row < batch_h) : (row += 1) {
                const src = pixels + ((y + row) * w);
                writeAll(self.fd, @as([*]u8, @ptrCast(src))[0..(w * 4)]);
                if (row_pad > 0) {
                    var pad: [4]u8 = undefined;
                    writeAll(self.fd, pad[0..row_pad]);
                }
            }
            y += batch_h;
        }
    }

    pub fn nextEvent(self: *X11Conn) ?XEvent {
        var buf: [32]u8 = undefined;
        if (!readExact(self.fd, &buf)) return null;
        const t = buf[0];
        if (t == 12) return XEvent{ .type = 12, .keycode = 0, .width = read16(&buf, 4), .height = read16(&buf, 6), .detail = 0, .event_x = 0, .event_y = 0 };
        if (t == 2) return XEvent{ .type = 2, .keycode = buf[1], .width = 0, .height = 0, .detail = 0, .event_x = 0, .event_y = 0 };
        if (t == 3) return XEvent{ .type = 3, .keycode = buf[1], .width = 0, .height = 0, .detail = 0, .event_x = 0, .event_y = 0 };
        if (t == 33) return XEvent{ .type = 33, .keycode = 0, .width = 0, .height = 0, .detail = 0, .event_x = 0, .event_y = 0 };
        if (t == 4 or t == 5) return XEvent{ .type = t, .keycode = 0, .width = 0, .height = 0, .detail = buf[1], .event_x = readI16(&buf, 24), .event_y = readI16(&buf, 26) };
        if (t == 6) return XEvent{ .type = 6, .keycode = 0, .width = 0, .height = 0, .detail = buf[1], .event_x = readI16(&buf, 24), .event_y = readI16(&buf, 26) };
        return null;
    }

    pub fn close(self: *X11Conn) void {
        sys.close(self.fd);
    }
};

pub const XEvent = struct {
    type: u8,
    keycode: u32,
    width: u32,
    height: u32,
    detail: u8,
    event_x: i32,
    event_y: i32,
};

fn readI16(buf: []const u8, off: usize) i16 {
    return @as(i16, @bitCast(@as(u16, read16(buf, off))));
}

pub fn x11Open(display_num: i32) ?X11Conn {
    var path: [32]u8 = undefined;
    var pi: usize = 0;
    const prefix = "/tmp/.X11-unix/X";
    var ci: usize = 0;
    while (ci < prefix.len) : (ci += 1) { path[pi] = prefix[ci]; pi += 1; }
    pi += intToStr(display_num, path[pi..]);
    path[pi] = 0; pi += 1;

    const fd = sys.socket(sys.AF_UNIX, sys.SOCK_STREAM, 0);
    if (fd < 0) return null;

    var addr: [110]u8 = undefined;
    addr[0] = @as(u8, @intCast(sys.AF_UNIX));
    addr[1] = 0;
    var si: usize = 0;
    while (si < pi) : (si += 1) addr[2 + si] = path[si];
    const addr_len: u32 = @as(u32, @intCast(2 + pi));

    if (sys.connect(fd, &addr, addr_len) < 0) {
        sys.close(fd);
        return null;
    }

    var auth_name: [32]u8 = undefined;
    var auth_data: [32]u8 = undefined;
    var auth_name_len: u16 = 0;
    var auth_data_len: u16 = 0;
    var have_auth = false;

    var home_buf: [256]u8 = undefined;
    if (sys.getenv("HOME", &home_buf)) |home| {
        if (findAuth(display_num, home)) |a| {
            auth_name = a.name;
            auth_data = a.data;
            auth_name_len = a.name_len;
            auth_data_len = a.data_len;
            have_auth = true;
        }
    }

    var conn_req: [12]u8 = undefined;
    conn_req[0] = 0x6C;
    conn_req[1] = 0;
    write16(&conn_req, 2, 11);
    write16(&conn_req, 4, 0);
    write16(&conn_req, 6, auth_name_len);
    write16(&conn_req, 8, auth_data_len);
    conn_req[10] = 0; conn_req[11] = 0;
    writeAll(fd, &conn_req);

    if (have_auth) {
        writeAll(fd, auth_name[0..auth_name_len]);
        var apad: [4]u8 = undefined;
        const name_pad = (4 - (auth_name_len % 4)) & 3;
        if (name_pad > 0) writeAll(fd, apad[0..name_pad]);
        writeAll(fd, auth_data[0..auth_data_len]);
        const data_pad = (4 - (auth_data_len % 4)) & 3;
        if (data_pad > 0) writeAll(fd, apad[0..data_pad]);
    }

    var resp: [8]u8 = undefined;
    if (!readExact(fd, &resp)) { sys.close(fd); return null; }
    if (resp[0] != 1) { sys.close(fd); return null; }

    const additional = read16(&resp, 6);
    var data: [8192]u8 = undefined;
    const data_len = @as(usize, additional) * 4;
    if (data_len > data.len) { sys.close(fd); return null; }
    if (!readExact(fd, data[0..data_len])) { sys.close(fd); return null; }

    const id_base = read32(&data, 4);
    const vendor_len = read16(&data, 16);
    const num_formats = data[21];

    var off: usize = 32;
    off += @as(usize, vendor_len);
    off = (off + 3) & ~@as(usize, 3);
    off += @as(usize, num_formats) * 8;
    off = (off + 3) & ~@as(usize, 3);

    if (off + 40 > data_len) { sys.close(fd); return null; }
    const root = read32(&data, off);
    const white = read32(&data, off + 8);
    const black = read32(&data, off + 12);
    const ww = read16(&data, off + 20);
    const hh = read16(&data, off + 22);
    const depth = data[off + 38];

    return X11Conn{
        .fd = fd, .root = root, .white_pixel = white, .black_pixel = black,
        .w = ww, .h = hh, .depth = depth, .wid = id_base + 1, .gc = id_base + 2,
    };
}
