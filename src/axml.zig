const utils = @import("utils.zig");

const NS32: u32 = 0xFFFFFFFF;
const NS16: u16 = 0xFFFF;

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

fn utf16len(s: []const u8) usize { return s.len * 2; }

fn utf16cpy(dst: []u8, s: []const u8) void {
    for (s, 0..) |c, i| { dst[i * 2] = c; dst[i * 2 + 1] = 0; }
}

pub const ManifestConfig = struct {
    package: []const u8 = "com.dhjsjs.app",
    app_name: []const u8 = "dhjsjs",
    version_code: u32 = 1,
    version_name: []const u8 = "1.0",
    min_sdk: u32 = 26,
    target_sdk: u32 = 34,
    has_code: bool = false,
    debuggable: bool = true,
    lib_name: []const u8 = "main",
    permissions: []const []const u8 = &.{},
};

fn addStr(sd: []u8, posp: *usize, off: []u32, idx: *u32, s: []const u8) u32 {
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

pub fn buildManifest(cfg: ManifestConfig, buf: []u8) usize {
    var strdata: [4096]u8 = undefined;
    var sp: usize = 0;
    var idx: u32 = 0;
    var str_off: [80]u32 = undefined;

    const android_ns = addStr(&strdata, &sp, &str_off, &idx, "android");
    const android_uri = addStr(&strdata, &sp, &str_off, &idx, "http://schemas.android.com/apk/res/android");
    const tag_manifest = addStr(&strdata, &sp, &str_off, &idx, "manifest");
    const attr_package = addStr(&strdata, &sp, &str_off, &idx, "package");
    const attr_versionCode = addStr(&strdata, &sp, &str_off, &idx, "versionCode");
    const attr_versionName = addStr(&strdata, &sp, &str_off, &idx, "versionName");
    const tag_uses_sdk = addStr(&strdata, &sp, &str_off, &idx, "uses-sdk");
    const attr_minSdk = addStr(&strdata, &sp, &str_off, &idx, "minSdkVersion");
    const attr_targetSdk = addStr(&strdata, &sp, &str_off, &idx, "targetSdkVersion");
    const tag_application = addStr(&strdata, &sp, &str_off, &idx, "application");
    const attr_hasCode = addStr(&strdata, &sp, &str_off, &idx, "hasCode");
    const attr_debuggable = addStr(&strdata, &sp, &str_off, &idx, "debuggable");
    const attr_label = addStr(&strdata, &sp, &str_off, &idx, "label");
    const tag_activity = addStr(&strdata, &sp, &str_off, &idx, "activity");
    const attr_name = addStr(&strdata, &sp, &str_off, &idx, "name");
    const attr_exported = addStr(&strdata, &sp, &str_off, &idx, "exported");
    const tag_meta_data = addStr(&strdata, &sp, &str_off, &idx, "meta-data");
    const attr_value = addStr(&strdata, &sp, &str_off, &idx, "value");
    const val_native_activity = addStr(&strdata, &sp, &str_off, &idx, "android.app.NativeActivity");
    const val_lib_name = addStr(&strdata, &sp, &str_off, &idx, "android.app.lib_name");
    const val_package = addStr(&strdata, &sp, &str_off, &idx, cfg.package);
    const val_version = addStr(&strdata, &sp, &str_off, &idx, cfg.version_name);
    const val_app_name = addStr(&strdata, &sp, &str_off, &idx, cfg.app_name);
    const val_lib = addStr(&strdata, &sp, &str_off, &idx, cfg.lib_name);
    const tag_uses_permission = addStr(&strdata, &sp, &str_off, &idx, "uses-permission");
    const tag_intent_filter = addStr(&strdata, &sp, &str_off, &idx, "intent-filter");
    const tag_action = addStr(&strdata, &sp, &str_off, &idx, "action");
    const tag_category = addStr(&strdata, &sp, &str_off, &idx, "category");
    const val_action_main = addStr(&strdata, &sp, &str_off, &idx, "android.intent.action.MAIN");
    const val_category_launcher = addStr(&strdata, &sp, &str_off, &idx, "android.intent.category.LAUNCHER");

    const nperms = cfg.permissions.len;
    var perm_strs: [32]u32 = undefined;
    var pi: usize = 0;
    while (pi < nperms and pi < 32) : (pi += 1) perm_strs[pi] = addStr(&strdata, &sp, &str_off, &idx, cfg.permissions[pi]);

    var p: usize = 0;
    var el_idx: u32 = 0;

    // RES_XML header
    w16(buf, p, 0x0003);
    w16(buf, p + 2, 8);
    const xml_size_pos = p + 4;
    w32(buf, p + 4, 0);
    p += 8;

    // StringPool
    w16(buf, p, 0x0001);
    w16(buf, p + 2, 28);
    const pool_size_pos = p + 4;
    w32(buf, p + 4, 0);
    w32(buf, p + 8, idx);
    w32(buf, p + 12, 0);
    w32(buf, p + 16, 0);
    const str_start_off = 28 + idx * 4;
    w32(buf, p + 20, str_start_off);
    w32(buf, p + 24, 0);
    var i: u32 = 0;
    while (i < idx) : (i += 1) w32(buf, p + 28 + i * 4, str_off[@as(usize, @intCast(i))]);
    var j: usize = 0;
    while (j < sp) : (j += 1) buf[p + 28 + idx * 4 + j] = strdata[j];
    const pool_size = 28 + idx * 4 + sp;
    w32(buf, pool_size_pos, @as(u32, @intCast(pool_size)));
    p += pool_size;

    // ResourceIDs
    const res_ids = [_]u32{
        0x0101021b, 0x0101021c, 0x0101020c, 0x01010270,
        0x010100c4, 0x0101000f, 0x01010001, 0x01010003,
        0x010100d0, 0x01010024,
    };
    w16(buf, p, 0x0180);
    w16(buf, p + 2, 8);
    w32(buf, p + 4, @as(u32, @intCast(8 + res_ids.len * 4)));
    for (res_ids, 0..) |rid, k| w32(buf, p + 8 + k * 4, rid);
    p += 8 + res_ids.len * 4;

    // StartNamespace
    el_idx += 1;
    w16(buf, p, 0x0100);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, android_ns);
    w32(buf, p + 20, android_uri);
    p += 24;

    // uses-permission entries
    pi = 0;
    while (pi < nperms and pi < 32) : (pi += 1) {
        el_idx += 1;
        w16(buf, p, 0x0102);
        w16(buf, p + 2, 32);
        w32(buf, p + 4, 52);
        w32(buf, p + 8, el_idx);
        w32(buf, p + 12, NS32);
        w32(buf, p + 16, NS32);
        w32(buf, p + 20, tag_uses_permission);
        w16(buf, p + 24, 32);
        w16(buf, p + 26, 20);
        w16(buf, p + 28, 1);
        w16(buf, p + 30, NS16);
        attrStr(buf, p + 32, android_ns, attr_name, perm_strs[pi]);
        p += 52;
        el_idx += 1;
        w16(buf, p, 0x0103);
        w16(buf, p + 2, 24);
        w32(buf, p + 4, 24);
        w32(buf, p + 8, el_idx);
        w32(buf, p + 12, NS32);
        w32(buf, p + 16, NS32);
        w32(buf, p + 20, tag_uses_permission);
        p += 24;
    }

    // manifest
    el_idx += 1;
    w16(buf, p, 0x0102);
    w16(buf, p + 2, 32);
    const manifest_size_pos = p + 4;
    w32(buf, p + 4, 0);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_manifest);
    w16(buf, p + 24, 32);
    w16(buf, p + 26, 20);
    w16(buf, p + 28, 3);
    w16(buf, p + 30, NS16);
    const ma = p + 32;
    attrStr(buf, ma, NS32, attr_package, val_package);
    attrInt(buf, ma + 20, android_ns, attr_versionCode, cfg.version_code, 0x10);
    attrStr(buf, ma + 40, android_ns, attr_versionName, val_version);
    const manifest_total: u32 = 32 + 3 * 20;
    w32(buf, manifest_size_pos, manifest_total);
    p += @as(usize, @intCast(manifest_total));

    // uses-sdk
    el_idx += 1;
    w16(buf, p, 0x0102);
    w16(buf, p + 2, 32);
    w32(buf, p + 4, 72);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_uses_sdk);
    w16(buf, p + 24, 32);
    w16(buf, p + 26, 20);
    w16(buf, p + 28, 2);
    w16(buf, p + 30, NS16);
    attrInt(buf, p + 32, android_ns, attr_minSdk, cfg.min_sdk, 0x10);
    attrInt(buf, p + 52, android_ns, attr_targetSdk, cfg.target_sdk, 0x10);
    p += 72;
    el_idx += 1;
    w16(buf, p, 0x0103);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_uses_sdk);
    p += 24;

    // application
    el_idx += 1;
    w16(buf, p, 0x0102);
    w16(buf, p + 2, 32);
    const app_size_pos = p + 4;
    w32(buf, p + 4, 0);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_application);
    w16(buf, p + 24, 32);
    w16(buf, p + 26, 20);
    w16(buf, p + 28, 3);
    w16(buf, p + 30, NS16);
    const aa = p + 32;
    attrInt(buf, aa, android_ns, attr_hasCode, @as(u32, @intFromBool(cfg.has_code)), 0x12);
    attrInt(buf, aa + 20, android_ns, attr_debuggable, @as(u32, @intFromBool(cfg.debuggable)), 0x12);
    attrStr(buf, aa + 40, android_ns, attr_label, val_app_name);
    const app_total: u32 = 32 + 3 * 20;
    w32(buf, app_size_pos, app_total);
    p += @as(usize, @intCast(app_total));

    // activity MAIN/LAUNCHER
    el_idx += 1;
    w16(buf, p, 0x0102);
    w16(buf, p + 2, 32);
    const act_size_pos = p + 4;
    w32(buf, p + 4, 0);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_activity);
    w16(buf, p + 24, 32);
    w16(buf, p + 26, 20);
    w16(buf, p + 28, 2);
    w16(buf, p + 30, NS16);
    attrStr(buf, p + 32, android_ns, attr_name, val_native_activity);
    attrInt(buf, p + 52, android_ns, attr_exported, 1, 0x12);
    const act_total: u32 = 32 + 2 * 20;
    w32(buf, act_size_pos, act_total);
    p += @as(usize, @intCast(act_total));

    // intent-filter
    el_idx += 1;
    w16(buf, p, 0x0102);
    w16(buf, p + 2, 32);
    w32(buf, p + 4, 32);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_intent_filter);
    w16(buf, p + 24, 0);
    w16(buf, p + 26, 0);
    w16(buf, p + 28, 0);
    w16(buf, p + 30, NS16);
    p += 32;

    // action MAIN
    el_idx += 1;
    w16(buf, p, 0x0102);
    w16(buf, p + 2, 32);
    w32(buf, p + 4, 52);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_action);
    w16(buf, p + 24, 32);
    w16(buf, p + 26, 20);
    w16(buf, p + 28, 1);
    w16(buf, p + 30, NS16);
    attrStr(buf, p + 32, android_ns, attr_name, val_action_main);
    p += 52;
    el_idx += 1;
    w16(buf, p, 0x0103);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_action);
    p += 24;

    // category LAUNCHER
    el_idx += 1;
    w16(buf, p, 0x0102);
    w16(buf, p + 2, 32);
    w32(buf, p + 4, 52);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_category);
    w16(buf, p + 24, 32);
    w16(buf, p + 26, 20);
    w16(buf, p + 28, 1);
    w16(buf, p + 30, NS16);
    attrStr(buf, p + 32, android_ns, attr_name, val_category_launcher);
    p += 52;
    el_idx += 1;
    w16(buf, p, 0x0103);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_category);
    p += 24;

    // end intent-filter
    el_idx += 1;
    w16(buf, p, 0x0103);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_intent_filter);
    p += 24;

    // meta-data: android.app.lib_name
    el_idx += 1;
    w16(buf, p, 0x0102);
    w16(buf, p + 2, 32);
    const md_size_pos = p + 4;
    w32(buf, p + 4, 0);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_meta_data);
    w16(buf, p + 24, 32);
    w16(buf, p + 26, 20);
    w16(buf, p + 28, 2);
    w16(buf, p + 30, NS16);
    attrStr(buf, p + 32, android_ns, attr_name, val_lib_name);
    attrStr(buf, p + 52, android_ns, attr_value, val_lib);
    const md_total: u32 = 32 + 2 * 20;
    w32(buf, md_size_pos, md_total);
    p += @as(usize, @intCast(md_total));
    el_idx += 1;
    w16(buf, p, 0x0103);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_meta_data);
    p += 24;

    // end activity
    el_idx += 1;
    w16(buf, p, 0x0103);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_activity);
    p += 24;
    // end application
    el_idx += 1;
    w16(buf, p, 0x0103);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_application);
    p += 24;
    // end manifest
    el_idx += 1;
    w16(buf, p, 0x0103);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, NS32);
    w32(buf, p + 20, tag_manifest);
    p += 24;
    // EndNamespace
    el_idx += 1;
    w16(buf, p, 0x0101);
    w16(buf, p + 2, 24);
    w32(buf, p + 4, 24);
    w32(buf, p + 8, el_idx);
    w32(buf, p + 12, NS32);
    w32(buf, p + 16, android_ns);
    w32(buf, p + 20, android_uri);
    p += 24;

    w32(buf, xml_size_pos, @as(u32, @intCast(p)));
    return p;
}
