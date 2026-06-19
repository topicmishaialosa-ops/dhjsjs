const utils = @import("utils.zig");

const NS32 = 0xFFFFFFFF;
const NS16 = 0xFFFF;

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

fn attrStr(buf: []u8, pos: usize, ns: u32, name: u32, val: u32) void {
    w32(buf, pos + 0, ns);
    w32(buf, pos + 4, name);
    w32(buf, pos + 8, val);
    w16(buf, pos + 12, 8);
    buf[pos + 14] = 0;
    buf[pos + 15] = 3;
    w32(buf, pos + 16, val);
}

fn attrInt(buf: []u8, pos: usize, ns: u32, name: u32, val: u32, typ: u8) void {
    w32(buf, pos + 0, ns);
    w32(buf, pos + 4, name);
    w32(buf, pos + 8, NS32);
    w32(buf, pos + 12, 0);
    buf[pos + 14] = 0;
    buf[pos + 15] = typ;
    w32(buf, pos + 16, val);
}

fn utf16len(s: []const u8) usize {
    return s.len * 2;
}

fn utf16cpy(dst: []u8, s: []const u8) void {
    for (s, 0..) |c, i| {
        dst[i * 2] = c;
        dst[i * 2 + 1] = 0;
    }
}

pub fn buildManifest(pkg: []const u8, lib: []const u8, minSdk: u32, tgtSdk: u32, buf: []u8) usize {
    var str_off: [32]u32 = undefined;
    var strdata: [2048]u8 = undefined;
    var sp: usize = 0;
    var si: u32 = 0;

    const S = struct {
        fn add(idx: *u32, sd: []u8, posp: *usize, off: []u32, s: []const u8) u32 {
            const i = idx.*;
            idx.* += 1;
            off[@as(usize, @intCast(i))] = @as(u32, @intCast(posp.*));
            const ul = utf16len(s);
            utf16cpy(sd[posp.* .. posp.* + ul], s);
            posp.* += ul;
            sd[posp.*] = 0; sd[posp.* + 1] = 0; posp.* += 2;
            while (posp.* % 4 != 0) { sd[posp.*] = 0; posp.* += 1; }
            return i;
        }
    }.add;

    const a0 = S(&si, &strdata, &sp, &str_off, "android");
    const a1 = S(&si, &strdata, &sp, &str_off, "http://schemas.android.com/apk/res/android");
    const a2 = S(&si, &strdata, &sp, &str_off, "manifest");
    const a3 = S(&si, &strdata, &sp, &str_off, "package");
    const a4 = S(&si, &strdata, &sp, &str_off, "versionCode");
    const a5 = S(&si, &strdata, &sp, &str_off, "versionName");
    const a6 = S(&si, &strdata, &sp, &str_off, "uses-sdk");
    const a7 = S(&si, &strdata, &sp, &str_off, "minSdkVersion");
    const a8 = S(&si, &strdata, &sp, &str_off, "targetSdkVersion");
    const a9 = S(&si, &strdata, &sp, &str_off, "application");
    const a10 = S(&si, &strdata, &sp, &str_off, "hasCode");
    const a11 = S(&si, &strdata, &sp, &str_off, "debuggable");
    const a12 = S(&si, &strdata, &sp, &str_off, "label");
    const a13 = S(&si, &strdata, &sp, &str_off, "activity");
    const a14 = S(&si, &strdata, &sp, &str_off, "name");
    const a15 = S(&si, &strdata, &sp, &str_off, "exported");
    const a16 = S(&si, &strdata, &sp, &str_off, "meta-data");
    const a17 = S(&si, &strdata, &sp, &str_off, "value");
    const a18 = S(&si, &strdata, &sp, &str_off, "android.app.NativeActivity");
    const a19 = S(&si, &strdata, &sp, &str_off, "android.app.lib_name");
    const a20 = S(&si, &strdata, &sp, &str_off, pkg);
    const a21 = S(&si, &strdata, &sp, &str_off, "1.0");
    const a22 = S(&si, &strdata, &sp, &str_off, pkg);
    const a23 = S(&si, &strdata, &sp, &str_off, lib);

    var p: usize = 0;

    // RES_XML header (type 0x0003)
    w16(buf, p, 0x0003);
    w16(buf, p + 2, 8);
    const xml_size_pos = p + 4;
    w32(buf, p + 4, 0);
    p += 8;

    // StringPool (type 0x0001)
    w16(buf, p, 0x0001);
    w16(buf, p + 2, 28);
    const pool_size_pos = p + 4;
    w32(buf, p + 4, 0);
    w32(buf, p + 8, si);
    w32(buf, p + 12, 0);
    w32(buf, p + 16, 0);
    const str_start_off = 28 + si * 4;
    w32(buf, p + 20, str_start_off);
    w32(buf, p + 24, 0);
    // string offsets
    var i: u32 = 0;
    while (i < si) : (i += 1) {
        w32(buf, p + 28 + i * 4, str_off[@as(usize, @intCast(i))]);
    }
    // string data
    var j: usize = 0;
    while (j < sp) : (j += 1) buf[p + 28 + si * 4 + j] = strdata[j];
    const pool_size = 28 + si * 4 + @as(u32, @intCast(sp));
    w32(buf, pool_size_pos, pool_size);
    p += @as(usize, @intCast(pool_size));

    // ResourceIDs (type 0x0180)
    const res_ids = [_]u32{
        0x0101021b, // versionCode
        0x0101021c, // versionName
        0x0101020c, // minSdkVersion
        0x01010270, // targetSdkVersion
        0x010100c4, // hasCode
        0x0101000f, // debuggable
        0x01010001, // label
        0x01010003, // name
        0x010100d0, // exported
        0x01010024, // value
    };
    w16(buf, p, 0x0180);
    w16(buf, p + 2, 8);
    w32(buf, p + 4, 8 + res_ids.len * 4);
    i = 0;
    while (i < res_ids.len) : (i += 1) {
        w32(buf, p + 8 + i * 4, res_ids[@as(usize, @intCast(i))]);
    }
    p += 8 + res_ids.len * 4;

    // StartNamespace: android prefix
    w16(buf, p, 0x0100);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, 1);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, a0);
    w32(buf, p + 20, a1);
    p += 24;

    // StartTag: manifest
    w16(buf, p, 0x0102);
    w16(buf, p + 2, 32);
    const st_size_pos = p + 4;
    w32(buf, p + 4, 0);
    w32(buf, p + 8, 1);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, a2);
    w16(buf, p + 24, 32);
    w16(buf, p + 26, 20);
    w16(buf, p + 28, 3);
    w16(buf, p + 30, NS16);
    const manifest_attrs = p + 32;
    attrStr(buf, manifest_attrs, NS32, a3, a20);
    attrInt(buf, manifest_attrs + 20, a0, a4, 1, 0x10);
    attrStr(buf, manifest_attrs + 40, a0, a5, a21);
    const manifest_total: u32 = 32 + 3 * 20;
    w32(buf, st_size_pos, manifest_total);
    p += @as(usize, @intCast(manifest_total));

    // StartTag: uses-sdk
    var st_pos: usize = p;
    w16(buf, p, 0x0102);
    w16(buf, p + 2, 32);
    w32(buf, p + 8, 2);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, a6);
    w16(buf, p + 24, 32);
    w16(buf, p + 26, 20);
    w16(buf, p + 28, 2);
    w16(buf, p + 30, NS16);
    attrInt(buf, p + 32, a0, a7, minSdk, 0x10);
    attrInt(buf, p + 52, a0, a8, tgtSdk, 0x10);
    const uses_total: u32 = 32 + 2 * 20;
    w32(buf, p + 4, uses_total);
    w32(buf, st_pos + 4, uses_total);
    p += @as(usize, @intCast(uses_total));

    // EndTag: uses-sdk
    w16(buf, p, 0x0103);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, 3);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, a6);
    p += 24;

    // StartTag: application
    st_pos = p;
    w16(buf, p, 0x0102);
    w16(buf, p + 2, 32);
    const app_size_pos = p + 4;
    w32(buf, p + 4, 0);
    w32(buf, p + 8, 4);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, a9);
    w16(buf, p + 24, 32);
    w16(buf, p + 26, 20);
    w16(buf, p + 28, 3);
    w16(buf, p + 30, NS16);
    attrInt(buf, p + 32, a0, a10, 0, 0x12);
    attrInt(buf, p + 52, a0, a11, 1, 0x12);
    attrStr(buf, p + 72, a0, a12, a22);
    const app_total: u32 = 32 + 3 * 20;
    w32(buf, app_size_pos, app_total);
    p += @as(usize, @intCast(app_total));

    // StartTag: activity
    st_pos = p;
    w16(buf, p, 0x0102);
    w16(buf, p + 2, 32);
    const act_size_pos = p + 4;
    w32(buf, p + 4, 0);
    w32(buf, p + 8, 5);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, a13);
    w16(buf, p + 24, 32);
    w16(buf, p + 26, 20);
    w16(buf, p + 28, 2);
    w16(buf, p + 30, NS16);
    attrStr(buf, p + 32, a0, a14, a18);
    attrInt(buf, p + 52, a0, a15, 1, 0x12);
    const act_total: u32 = 32 + 2 * 20;
    w32(buf, act_size_pos, act_total);
    p += @as(usize, @intCast(act_total));

    // StartTag: meta-data
    st_pos = p;
    w16(buf, p, 0x0102);
    w16(buf, p + 2, 32);
    const md_size_pos = p + 4;
    w32(buf, p + 4, 0);
    w32(buf, p + 8, 6);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, a16);
    w16(buf, p + 24, 32);
    w16(buf, p + 26, 20);
    w16(buf, p + 28, 2);
    w16(buf, p + 30, NS16);
    attrStr(buf, p + 32, a0, a14, a19);
    attrStr(buf, p + 52, a0, a17, a23);
    const md_total: u32 = 32 + 2 * 20;
    w32(buf, md_size_pos, md_total);
    p += @as(usize, @intCast(md_total));

    // EndTag: meta-data
    w16(buf, p, 0x0103);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, 7);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, a16);
    p += 24;

    // EndTag: activity
    w16(buf, p, 0x0103);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, 8);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, a13);
    p += 24;

    // EndTag: application
    w16(buf, p, 0x0103);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, 9);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, a9);
    p += 24;

    // EndTag: manifest
    w16(buf, p, 0x0103);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, 10);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, a2);
    p += 24;

    // EndNamespace: android prefix
    w16(buf, p, 0x0101);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, 11);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, a0);
    w32(buf, p + 20, a1);
    p += 24;

    // Patch RES_XML total size
    w32(buf, xml_size_pos, @as(u32, @intCast(p)));

    return p;
}
