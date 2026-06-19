const utils = @import("utils.zig");
const sys = @import("sys.zig");

const MAX_ENTRIES = 16;

fn w16(buf: []u8, pos: usize, v: u16) void {
    buf[pos + 0] = @as(u8, @truncate(v));
    buf[pos + 1] = @as(u8, @truncate(v >> 8));
}

fn w32(buf: []u8, pos: usize, v: u32) void {
    buf[pos + 0] = @as(u8, @truncate(v));
    buf[pos + 1] = @as(u8, @truncate(v >> 8));
    buf[pos + 2] = @as(u8, @truncate(v >> 16));
    buf[pos + 3] = @as(u8, @truncate(v >> 24));
}

fn crc32Tab() [256]u32 {
    var tab: [256]u32 = undefined;
    var i: u32 = 0;
    while (i < 256) : (i += 1) {
        var c: u32 = i;
        var j: u32 = 0;
        while (j < 8) : (j += 1) {
            if (c & 1 != 0) c = 0xEDB88320 ^ (c >> 1) else c >>= 1;
        }
        tab[@as(usize, @intCast(i))] = c;
    }
    return tab;
}

fn crc32Bytes(tab: [256]u32, data: []const u8) u32 {
    var c: u32 = 0xFFFFFFFF;
    for (data) |b| {
        c = tab[@as(usize, @intCast((c ^ @as(u32, b)) & 0xFF))] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFF;
}

pub fn buildApk(entries: []const []const u8, names: []const []const u8, buf: []u8) usize {
    var cd_off: [MAX_ENTRIES]u32 = undefined;
    var cd_sizes: [MAX_ENTRIES]u32 = undefined;
    var data_sizes: [MAX_ENTRIES]u32 = undefined;
    var crcs: [MAX_ENTRIES]u32 = undefined;
    var pos: usize = 0;
    const tab = crc32Tab();

    var ei: usize = 0;
    while (ei < entries.len) : (ei += 1) {
        const name = names[ei];
        const data = entries[ei];
        const crc = crc32Bytes(tab, data);

        cd_off[ei] = @as(u32, @intCast(pos));
        crcs[ei] = crc;
        data_sizes[ei] = @as(u32, @intCast(data.len));

        // align data offset to 4 bytes
        const hdr_sz: u32 = 30 + @as(u32, @intCast(name.len));
        const pad = (4 - (hdr_sz % 4)) % 4;
        const local_total = hdr_sz + pad + @as(u32, @intCast(data.len));
        cd_sizes[ei] = local_total;

        // local file header
        w32(buf, pos, 0x04034b50);
        w16(buf, pos + 4, 20);
        w16(buf, pos + 6, 0);
        w16(buf, pos + 8, 0);
        w16(buf, pos + 10, 0);
        w16(buf, pos + 12, 0);
        w32(buf, pos + 14, crc);
        w32(buf, pos + 18, @as(u32, @intCast(data.len)));
        w32(buf, pos + 22, @as(u32, @intCast(data.len)));
        w16(buf, pos + 26, @as(u16, @intCast(name.len)));
        w16(buf, pos + 28, @as(u16, @intCast(pad)));
        pos += 30;
        // name
        var j: usize = 0;
        while (j < name.len) : (j += 1) buf[pos + j] = name[j];
        pos += name.len;
        // padding
        j = 0;
        while (j < pad) : (j += 1) buf[pos + j] = 0;
        pos += pad;
        // data
        j = 0;
        while (j < data.len) : (j += 1) buf[pos + j] = data[j];
        pos += data.len;
    }

    const cd_start = pos;

    // central directory
    ei = 0;
    while (ei < entries.len) : (ei += 1) {
        const name = names[ei];
        w32(buf, pos, 0x02014b50);
        w16(buf, pos + 4, 20);
        w16(buf, pos + 6, 20);
        w16(buf, pos + 8, 0);
        w16(buf, pos + 10, 0);
        w16(buf, pos + 12, 0);
        w16(buf, pos + 14, 0);
        w32(buf, pos + 16, crcs[ei]);
        w32(buf, pos + 20, data_sizes[ei]);
        w32(buf, pos + 24, data_sizes[ei]);
        w16(buf, pos + 28, @as(u16, @intCast(name.len)));
        w16(buf, pos + 30, 0);
        w16(buf, pos + 32, 0);
        w16(buf, pos + 34, 0);
        w16(buf, pos + 36, 0);
        w32(buf, pos + 38, 0);
        w32(buf, pos + 42, cd_off[ei]);
        pos += 46;
        // name
        var j: usize = 0;
        while (j < name.len) : (j += 1) buf[pos + j] = name[j];
        pos += name.len;
    }

    const cd_end = pos;
    const cd_size = cd_end - cd_start;

    // EOCD
    w32(buf, pos, 0x06054b50);
    w16(buf, pos + 4, 0);
    w16(buf, pos + 6, 0);
    w16(buf, pos + 8, @as(u16, @intCast(entries.len)));
    w16(buf, pos + 10, @as(u16, @intCast(entries.len)));
    w32(buf, pos + 12, @as(u32, @intCast(cd_size)));
    w32(buf, pos + 16, @as(u32, @intCast(cd_start)));
    w16(buf, pos + 20, 0);
    pos += 22;

    return pos;
}
