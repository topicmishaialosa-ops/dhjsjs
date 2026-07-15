const parser_mod = @import("parser.zig");
const compiler_mod = @import("compiler.zig");
const compiler_rv = @import("compiler_rv.zig");
const compiler_arm = @import("compiler_arm.zig");
const codegen_mod = @import("codegen.zig");
const codegen_arm = @import("codegen_arm.zig");
const codegen_rv = @import("codegen_rv.zig");
const compiler_avr = @import("compiler_avr.zig");
const codegen_avr = @import("codegen_avr.zig");
const compiler_xtensa = @import("compiler_xtensa.zig");
const crypto = @import("crypto.zig");
const sys = @import("sys.zig");
const utils = @import("utils.zig");
const errors_mod = @import("errors.zig");
const esp = @import("esp.zig");
const axml = @import("axml.zig");
const zip = @import("zip.zig");
const media_player = @import("media_player.zig");
const gl3_server = @import("gl3_server.zig");
const gui_srv = @import("gui_srv.zig");
const http_client = @import("http_client.zig");
const tls_client = @import("tls_client.zig");

const Target = enum { x86_64, aarch64, riscv32, avr, xtensa, apk, raw, native, windows };

fn hostTarget() Target {
    var buf: [390]u8 = @splat(0);
    const SYS_UNAME: usize = 63;
    _ = sys.syscall1(SYS_UNAME, @intFromPtr(&buf));
    const machine = buf[260..];
    if (machine[0] == 'a' and machine[1] == 'a' and machine[2] == 'r' and machine[3] == 'c' and machine[4] == 'h' and machine[5] == '6' and machine[6] == '4') return .aarch64;
    if (machine[0] == 'x' and machine[1] == '8' and machine[2] == '6' and machine[3] == '_' and machine[4] == '6' and machine[5] == '4') return .x86_64;
    return .x86_64;
}

const BUFSIZE = 65536;
const DEFAULT_SRC = "src/main.dhjsjs";
const DEFAULT_OUT = "output/out.bin";

fn readFile(path: []const u8, buf: []u8) ?[]u8 {
    var p: [256]u8 = undefined;
    var pi: usize = 0;
    while (pi < path.len and pi < 255) : (pi += 1) p[pi] = path[pi];
    p[pi] = 0;
    const fd = sys.open(&p, 0, 0);
    if (fd < 0) return null;
    defer sys.close(fd);
    var total: usize = 0;
    while (total < buf.len) {
        const n = sys.read(fd, buf[total..].ptr, buf.len - total);
        if (n <= 0) break;
        total += @as(usize, @intCast(n));
    }
    return buf[0..total];
}

fn writeFile(path: []const u8, data: []const u8) bool {
    var p: [256]u8 = undefined;
    var pi: usize = 0;
    while (pi < path.len and pi < 255) : (pi += 1) p[pi] = path[pi];
    p[pi] = 0;
    const fd = sys.open(&p, sys.O_RDWR | 0x40 | 0x200, 0x1A4);
    if (fd < 0) return false;
    defer sys.close(fd);
    _ = sys.write(fd, data.ptr, data.len);
    return true;
}

fn strEql(a: []const u8, b: []const u8) bool {
    return utils.sliceEql(a, b);
}

fn parseInt(s: []const u8) u32 {
    var v: u32 = 0;
    for (s) |c| { if (c >= '0' and c <= '9') v = v * 10 + (c - '0'); }
    return v;
}

fn parseTarget(s: []const u8) ?Target {
    if (strEql(s, "x86_64")) return .x86_64;
    if (strEql(s, "aarch64")) return .aarch64;
    if (strEql(s, "raw")) return .raw;
    if (strEql(s, "native")) return .native;
    if (strEql(s, "riscv32") or strEql(s, "esp32") or strEql(s, "esp32c3")) return .riscv32;
    if (strEql(s, "avr") or strEql(s, "arduino") or strEql(s, "uno") or strEql(s, "nano") or strEql(s, "mega")) return .avr;
    if (strEql(s, "xtensa") or strEql(s, "esp8266") or strEql(s, "esp32s2") or strEql(s, "esp32s3")) return .xtensa;
    if (strEql(s, "apk") or strEql(s, "android")) return .apk;
    if (strEql(s, "windows") or strEql(s, "win") or strEql(s, "exe")) return .windows;
    return null;
}

fn compileSource(src: []const u8, target: Target, out_path: []const u8) bool {
    var errs = errors_mod.ErrorList.init(src.ptr, src.len);
    var parser = parser_mod.Parser.init(src.ptr, src.len, &errs);
    const prog = parser.parse();
    if (errs.hasErrors()) {
        errs.printAll();
        return false;
    }
    const SYS_CHMOD: usize = 90;
    const effective = if (target == .native) hostTarget() else target;
    switch (effective) {
        .x86_64 => {
            var cb = compiler_mod.compile(prog, &parser.pool, &errs);
            if (errs.hasErrors()) { errs.printAll(); return false; }
            cb.buildElf64();
            if (!writeFile(out_path, cb.get())) return false;
        },
        .aarch64 => {
            var cb = compiler_arm.compile(prog, &parser.pool);
            cb.buildElf64();
            if (!writeFile(out_path, cb.get())) return false;
        },
        .riscv32 => {
            var cb = compiler_rv.compile(prog, &parser.pool);
            cb.buildElf32();
            if (!writeFile(out_path, cb.get())) return false;
        },
        .avr => {
            var cb = compiler_avr.compile(prog, &parser.pool);
            cb.buildHex(0);
            if (!writeFile(out_path, cb.get())) return false;
        },
        .xtensa => {
            var cb = compiler_xtensa.compile(prog, &parser.pool);
            cb.buildElf32();
            if (!writeFile(out_path, cb.get())) return false;
        },
        .apk => {
            var cb = compiler_arm.compileEx(prog, &parser.pool, true);
            cb.buildElf64Dyn();
            return writeFile(out_path, cb.get());
        },
        .windows => {
            var cb = compiler_mod.compile(prog, &parser.pool, &errs);
            if (errs.hasErrors()) { errs.printAll(); return false; }
            cb.buildPe64();
            if (!writeFile(out_path, cb.get())) return false;
        },
        .raw => {
            var cb = compiler_arm.compile(prog, &parser.pool);
            if (!writeFile(out_path, cb.get())) return false;
        },
        .native => unreachable,
    }
    _ = sys.syscall2(SYS_CHMOD, @intFromPtr(out_path.ptr), 0x1ED);
    return true;
}

fn loadBuiltin(name: []const u8, buf: []u8) []const u8 {
    var path_buf: [256]u8 = undefined;
    var pi: usize = 0;
    for ("src/") |c| { if (pi < 255) { path_buf[pi] = c; pi += 1; } }
    for (name) |c| { if (pi < 255) { path_buf[pi] = c; pi += 1; } }
    for (".dhjsjs") |c| { if (pi < 255) { path_buf[pi] = c; pi += 1; } }
    path_buf[pi] = 0;
    const fd = sys.open(&path_buf, 0, 0);
    if (fd < 0) {
        sys.writeStr(2, "error: builtin '", 18);
        sys.writeStr(2, name.ptr, name.len);
        sys.writeStr(2, "' not found\n", 14);
        return buf[0..0];
    }
    const file_len = sys.read(fd, buf.ptr, buf.len - 1);
    sys.close(fd);
    if (file_len > 0) buf[@as(usize, @intCast(file_len))] = 0;
    return buf[0..@as(usize, @intCast(file_len))];
}

fn preprocessSource(src: []const u8, buf: []u8, lib_dir: []const u8) []const u8 {
    var dp: usize = 0;
    var sp: usize = 0;

    // Check if source is a single keyword that expands to built-in code
    if (src.len >= 8 and src.len <= 9 and src[0] == 's' and src[1] == 'e' and src[2] == 'l' and src[3] == 'f' and src[4] == 'h' and src[5] == 'o' and src[6] == 's' and src[7] == 't') {
        return loadBuiltin("selfhost", buf);
    }
    if (src.len >= 3 and src.len <= 4 and src[0] == 'g' and src[1] == 'u' and src[2] == 'i') {
        return loadBuiltin("gui", buf);
    }
    if (src.len >= 2 and src.len <= 3 and src[0] == 'v' and src[1] == 'k') {
        return loadBuiltin("vk", buf);
    }
    if (src.len >= 3 and src.len <= 4 and src[0] == 'm' and src[1] == 'p' and src[2] == '3') {
        return loadBuiltin("mp3_full", buf);
    }
    if (src.len >= 3 and src.len <= 4 and src[0] == 'o' and src[1] == 'g' and src[2] == 'g') {
        return loadBuiltin("ogg_full", buf);
    }
    if (src.len >= 4 and src.len <= 5 and src[0] == 'f' and src[1] == 'l' and src[2] == 'a' and src[3] == 'c') {
        return loadBuiltin("flac_full", buf);
    }
    if (src.len >= 3 and src.len <= 4 and src[0] == 'i' and src[1] == 'd' and src[2] == 'e') {
        return loadBuiltin("ide", buf);
    }

    while (sp < src.len and dp + 10 < buf.len) {
        // Check for #include "filename"
        if (src.len - sp >= 10 and
            src[sp] == '#' and
            src[sp+1] == 'i' and
            src[sp+2] == 'n' and
            src[sp+3] == 'c' and
            src[sp+4] == 'l' and
            src[sp+5] == 'u' and
            src[sp+6] == 'd' and
            src[sp+7] == 'e' and
            src[sp+8] == ' ')
        {
            sp += 9;
            // skip spaces
            while (sp < src.len and src[sp] == ' ') sp += 1;
            if (sp < src.len and src[sp] == '"') {
                sp += 1;
                const fn_start = sp;
                while (sp < src.len and src[sp] != '"') sp += 1;
                const fname = src[fn_start..sp];
                if (sp < src.len) sp += 1; // skip closing "
                // skip to end of line
                while (sp < src.len and src[sp] != '\n') sp += 1;
                // Read the included file
                var path_buf: [256]u8 = undefined;
                var pi: usize = 0;
                for (lib_dir) |c| {
                    if (pi < 255) {
                        // Normalize path separators
                        path_buf[pi] = if (c == '/' and sys.is_windows) '\\' else c;
                        pi += 1;
                    }
                }
                for (fname) |c| { if (pi < 255) { path_buf[pi] = c; pi += 1; } }
                path_buf[pi] = 0;
                const fd = sys.open(&path_buf, 0, 0);
                if (fd >= 0) {
                    const file_len = sys.read(fd, buf.ptr + dp, buf.len - dp - 1);
                    sys.close(fd);
                    if (file_len > 0) dp += @as(usize, @intCast(file_len));
                }
                // skip newline
                if (sp < src.len and src[sp] == '\n') sp += 1;
            } else {
                // Just copy as-is
                while (sp < src.len and src[sp] != '\n') {
                    buf[dp] = src[sp]; dp += 1; sp += 1;
                }
            }
        } else {
            buf[dp] = src[sp]; dp += 1; sp += 1;
        }
    }
    buf[dp] = 0;
    return buf[0..dp];
}

fn signApk(apk_path: []const u8, _: bool) bool {
    // Generate RSA key on first use, persist as raw binary
    var key_path_buf: [512]u8 = undefined;
    var kp: usize = 0;
    var home_val: [256]u8 = undefined;
    const home = sys.getenv("HOME", home_val[0..]);
    if (home) |h| {
        @memcpy(key_path_buf[0..h.len], h);
        kp = h.len;
    } else {
        @memcpy(key_path_buf[0..4], "/tmp");
        kp = 4;
    }
    const ks_suffix = "/.dhjsjs-key.raw\x00";
    @memcpy(key_path_buf[kp..kp + ks_suffix.len], ks_suffix);
    kp += ks_suffix.len - 1;

    var key: crypto.RsaPrivateKey = undefined;
    const ksfd = sys.open(&key_path_buf, 0, 0);
    if (ksfd >= 0) {
        // Load existing key
        var key_buf: [2048]u8 = undefined;
        const nread = sys.read(ksfd, &key_buf, key_buf.len);
        sys.close(ksfd);
        if (nread >= 256) {
            key.n = crypto.biFromBytes(key_buf[0..256]);
            key.e = crypto.biFromBytes(key_buf[256..258]);
            key.d = crypto.biFromBytes(key_buf[258..514]);
            key.p = crypto.biFromBytes(key_buf[514..642]);
            key.q = crypto.biFromBytes(key_buf[642..770]);
            key.dp = crypto.biFromBytes(key_buf[770..898]);
            key.dq = crypto.biFromBytes(key_buf[898..1026]);
            key.qinv = crypto.biFromBytes(key_buf[1026..1154]);
        } else {
            crypto.rsaGenerateKey(&key);
        }
    } else {
        crypto.rsaGenerateKey(&key);
        // Save key
        var key_buf: [2048]u8 = undefined;
        crypto.biToBytes(&key.n, key_buf[0..256]);
        crypto.biToBytes(&key.e, key_buf[256..258]);
        crypto.biToBytes(&key.d, key_buf[258..514]);
        crypto.biToBytes(&key.p, key_buf[514..642]);
        crypto.biToBytes(&key.q, key_buf[642..770]);
        crypto.biToBytes(&key.dp, key_buf[770..898]);
        crypto.biToBytes(&key.dq, key_buf[898..1026]);
        crypto.biToBytes(&key.qinv, key_buf[1026..1154]);
        const kfd = sys.open(&key_path_buf, sys.O_RDWR | 0x40 | 0x200, 0x1A4);
        if (kfd >= 0) { _ = sys.write(kfd, &key_buf, 1154); sys.close(kfd); }
    }

    // Read APK into memory
    var apk_buf: [262144]u8 = undefined;
    var apk_data: []const u8 = undefined;
    {
        // Open the apk file
        var p: [256]u8 = undefined;
        var pi: usize = 0;
        while (pi < apk_path.len and pi < 255) : (pi += 1) p[pi] = apk_path[pi];
        p[pi] = 0;
        const apk_fd = sys.open(&p, 0, 0);
        if (apk_fd < 0) return false;
        var total: usize = 0;
        while (total < apk_buf.len) {
            const n = sys.read(apk_fd, apk_buf[total..].ptr, apk_buf.len - total);
            if (n <= 0) break;
            total += @as(usize, @intCast(n));
        }
        sys.close(apk_fd);
        apk_data = apk_buf[0..total];
    }

    // Sign
    var out_buf: [262144 + 16384]u8 = undefined;
    const out_len = crypto.apkSign(apk_data, &out_buf, &key);
    if (out_len == 0) return false;

    // Write signed APK
    var p: [256]u8 = undefined;
    var pi: usize = 0;
    while (pi < apk_path.len and pi < 255) : (pi += 1) p[pi] = apk_path[pi];
    p[pi] = 0;
    const out_fd = sys.open(&p, sys.O_RDWR | 0x40 | 0x200, 0x1A4);
    if (out_fd < 0) return false;
    _ = sys.write(out_fd, &out_buf, out_len);
    sys.close(out_fd);
    return true;
}

fn getLibDir() []const u8 {
    if (sys.is_windows) {
        // On Windows, try to find lib/ relative to executable
        // Fall back to current directory
        return ".\\lib\\";
    }
    return "/home/krasava/dhjsjs/lib/";
}

fn cmdBuild(args: []const []const u8) void {
    var src_file: []const u8 = DEFAULT_SRC;
    var out_file: []const u8 = DEFAULT_OUT;
    var target: Target = .native;
    var manifest = axml.ManifestConfig{};
    var release_mode = false;
    var no_sign = false;
    var perm_list: [32][]const u8 = undefined;
    var perm_count: usize = 0;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (strEql(a, "-o") or strEql(a, "--output")) {
            i += 1;
            if (i < args.len) out_file = args[i];
        } else if (strEql(a, "--target")) {
            i += 1;
            if (i < args.len) {
                target = parseTarget(args[i]) orelse {
                    sys.writeStr(2, "error: unknown target '", 24);
                    sys.writeStr(2, args[i].ptr, args[i].len);
                    sys.writeStr(2, "'\n", 2);
                    sys.exit(1);
                };
            }
        } else if (strEql(a, "--package")) {
            i += 1;
            if (i < args.len) manifest.package = args[i];
        } else if (strEql(a, "--app-name")) {
            i += 1;
            if (i < args.len) manifest.app_name = args[i];
        } else if (strEql(a, "--permission")) {
            i += 1;
            if (i < args.len and perm_count < 32) {
                perm_list[perm_count] = args[i];
                perm_count += 1;
            }
        } else if (strEql(a, "--min-sdk")) {
            i += 1;
            if (i < args.len) manifest.min_sdk = parseInt(args[i]);
        } else if (strEql(a, "--version")) {
            i += 1;
            if (i < args.len) manifest.version_code = parseInt(args[i]);
        } else if (strEql(a, "--version-name")) {
            i += 1;
            if (i < args.len) manifest.version_name = args[i];
        } else if (strEql(a, "--release")) {
            release_mode = true;
            manifest.debuggable = false;
        } else if (strEql(a, "--no-sign")) {
            no_sign = true;
        } else if (a.len > 0 and a[0] != '-') {
            src_file = a;
        }
    }

    if (target == .native) target = hostTarget();
    if (target == .apk and strEql(out_file, DEFAULT_OUT)) out_file = "output/app.apk";
    if (target == .windows and strEql(out_file, DEFAULT_OUT)) out_file = "output/out.exe";

    var buf: [BUFSIZE]u8 = undefined;
    const src = readFile(src_file, buf[0..]) orelse {
        sys.writeStr(2, "error: cannot read '", 20);
        sys.writeStr(2, src_file.ptr, src_file.len);
        sys.writeStr(2, "'\n", 2);
        sys.exit(1);
    };
    var ppbuf: [BUFSIZE]u8 = undefined;
    const processed = preprocessSource(src, &ppbuf, getLibDir());

    if (target == .apk) {
        manifest.permissions = perm_list[0..perm_count];

        var errs = errors_mod.ErrorList.init(processed.ptr, processed.len);
        var parser = parser_mod.Parser.init(processed.ptr, processed.len, &errs);
        const prog = parser.parse();
        if (errs.hasErrors()) { errs.printAll(); sys.exit(1); }

        var cb = compiler_arm.compileEx(prog, &parser.pool, true);
        cb.buildElf64Dyn();
        const elf_data = cb.get();

        var axml_buf: [4096]u8 = undefined;
        const axml_len = axml.buildManifest(manifest, &axml_buf);

        var lib_path_buf: [128]u8 = undefined;
        const lib_prefix = "lib/arm64-v8a/lib";
        const lib_suffix = ".so";
        var lpi: usize = 0;
        @memcpy(lib_path_buf[0..lib_prefix.len], lib_prefix);
        lpi += lib_prefix.len;
        @memcpy(lib_path_buf[lpi..lpi + manifest.lib_name.len], manifest.lib_name);
        lpi += manifest.lib_name.len;
        @memcpy(lib_path_buf[lpi..lpi + lib_suffix.len], lib_suffix);
        lpi += lib_suffix.len;
        const lib_path = lib_path_buf[0..lpi];
        var apk_buf: [131072]u8 = undefined;
        var names = [_][]const u8{ "AndroidManifest.xml", lib_path };
        var datas = [_][]const u8{ axml_buf[0..axml_len], elf_data };
        const apk_len = zip.buildApk(&datas, &names, &apk_buf);

        if (!writeFile(out_file, apk_buf[0..apk_len])) {
            sys.writeStr(2, "error: write APK failed\n", 24);
            sys.exit(1);
        }

        if (!no_sign) {
            sys.writeStr(1, "signing...\n", 11);
            if (!signApk(out_file, release_mode)) {
                sys.writeStr(2, "warning: signing failed, APK is unsigned\n", 42);
            } else {
                sys.writeStr(1, "signed: ", 8);
                sys.writeStr(1, out_file.ptr, out_file.len);
                sys.writeStr(1, "\n", 1);
            }
        }
    } else if (!compileSource(processed, target, out_file)) {
        sys.writeStr(2, "error: compilation failed\n", 26);
        sys.exit(1);
    }

    sys.writeStr(1, "built: ", 7);
    sys.writeStr(1, out_file.ptr, out_file.len);
    sys.writeStr(1, "\n", 1);
}

fn cmdRun(args: []const []const u8) void {
    var src_file: []const u8 = DEFAULT_SRC;
    var target: Target = .native;
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (strEql(a, "--target")) {
            i += 1;
            if (i < args.len) {
                target = parseTarget(args[i]) orelse {
                    sys.writeStr(2, "error: unknown target\n", 22);
                    sys.exit(1);
                };
            }
        } else if (a.len > 0 and a[0] != '-') {
            src_file = a;
        }
    }
    if (target == .native) target = hostTarget();
    if (target != .x86_64) { sys.writeStr(2, "error: run only supports x86_64 target\n", 39); sys.exit(1); }
    var buf: [BUFSIZE]u8 = undefined;
    const src = readFile(src_file, buf[0..]) orelse {
        sys.writeStr(2, "error: cannot read '", 20); sys.writeStr(2, src_file.ptr, src_file.len); sys.writeStr(2, "'\n", 2); sys.exit(1);
    };
    var ppbuf: [BUFSIZE]u8 = undefined;
    const processed = preprocessSource(src, &ppbuf, getLibDir());
    var errs = errors_mod.ErrorList.init(processed.ptr, processed.len);
    var parser = parser_mod.Parser.init(processed.ptr, processed.len, &errs);
    const prog = parser.parse();
    if (errs.hasErrors()) { errs.printAll(); sys.exit(1); }
    var cb = compiler_mod.compile(prog, &parser.pool, &errs);
    if (errs.hasErrors()) { errs.printAll(); sys.exit(1); }

    if (sys.is_windows) {
        // Windows: write PE64 exe and inform user
        cb.buildPe64();
        var tmppath: [260]u8 = undefined;
        const tmp_env = sys.getenv("TEMP", tmppath[0..]) orelse sys.getenv("TMP", tmppath[0..]);
        var tp_len: usize = 0;
        if (tmp_env) |te| {
            while (tp_len < te.len and tp_len < 240) : (tp_len += 1) tmppath[tp_len] = te[tp_len];
        } else {
            @memcpy(tmppath[0..3], "C:\\");
            tp_len = 3;
        }
        const fname = "\\dhjsjs_run.exe";
        var fi: usize = 0;
        while (fi < fname.len) : (fi += 1) {
            if (tp_len + fi < 259) tmppath[tp_len + fi] = fname[fi];
        }
        tp_len += fname.len;
        tmppath[tp_len] = 0;
        const tmpfd = sys.open(tmppath[0..tp_len + 1 :0], sys.O_RDWR | 0x40, 0x1A4);
        if (tmpfd < 0) { sys.writeStr(2, "error: cannot create temp file\n", 31); sys.exit(1); }
        _ = sys.write(tmpfd, cb.get().ptr, cb.get().len);
        sys.close(tmpfd);
        sys.writeStr(1, "built: ", 7);
        sys.writeStr(1, tmppath[0..tp_len]);
        sys.writeStr(1, "\nrun with: ", 11);
        sys.writeStr(1, tmppath[0..tp_len]);
        sys.writeStr(1, "\n", 1);
    } else {
        // Linux: write ELF64 and execve
        cb.buildElf64();
        var tmppath: [32]u8 = @splat(0);
        const tpl = "/tmp/dhjsjs_run_XXXXXX";
        @memcpy(tmppath[0..tpl.len], tpl);
        {
            const urandom_fd = sys.open("/dev/urandom\x00", 0, 0);
            if (urandom_fd >= 0) {
                var rand: [6]u8 = undefined;
                _ = sys.read(urandom_fd, &rand, rand.len);
                sys.close(urandom_fd);
                const hex = "0123456789abcdef";
                var j: usize = 0;
                while (j < 6) : (j += 1) tmppath[tpl.len - 6 + j] = hex[rand[j] % 16];
            }
        }
        const tmpfd = sys.open(&tmppath, sys.O_RDWR | 0x40, 0x1A4);
        if (tmpfd < 0) { sys.writeStr(2, "error: cannot create temp file\n", 31); sys.exit(1); }
        _ = sys.write(tmpfd, cb.get().ptr, cb.get().len);
        sys.close(tmpfd);
        const SYS_CHMOD: usize = 90;
        _ = sys.syscall2(SYS_CHMOD, @intFromPtr(tmppath[0..].ptr), 0x1ED);
        const SYS_EXECVE: usize = 59;
        _ = sys.syscall3(SYS_EXECVE, @intFromPtr(&tmppath), 0, 0);
        sys.writeStr(2, "error: exec failed\n", 19);
        sys.exit(1);
    }
}

fn cmdNew(args: []const []const u8) void {
    if (args.len < 3) { sys.writeStr(2, "error: project name required\n", 29); sys.exit(1); }
    const name = args[2];
    _ = sys.mkdir(name.ptr, 0x1C0);
    var src_dir: [256]u8 = @splat(0);
    var di: usize = 0;
    for (name) |c| { src_dir[di] = c; di += 1; }
    const suffix = "/src\x00";
    for (suffix) |c| { src_dir[di] = c; di += 1; }
    _ = sys.mkdir(&src_dir, 0x1C0);
    var main_path: [256]u8 = @splat(0);
    var mi: usize = 0;
    for (name) |c| { main_path[mi] = c; mi += 1; }
    const msuffix = "/src/main.dhjsjs\x00";
    for (msuffix) |c| { main_path[mi] = c; mi += 1; }
    const template = "fn main() int {\n    hui x = 42;\n    return x;\n}\n";
    const fd = sys.open(&main_path, sys.O_RDWR | 0x40 | 0x200, 0x1A4);
    if (fd >= 0) { _ = sys.write(fd, template.ptr, template.len); sys.close(fd); }
    sys.writeStr(1, "created project '", 17);
    sys.writeStr(1, name.ptr, name.len);
    sys.writeStr(1, "'\n", 2);
}

fn cmdHelp() void {
    const help =
        \\dhjsjs compiler v0.3
        \\
        \\Usage:
        \\  dhjsjs_cc build [file] [-o output] [--target x86_64|aarch64|riscv32|esp32|native|windows|apk]
        \\  dhjsjs_cc run [file]
        \\  dhjsjs_cc new <project>
        \\  dhjsjs_cc flash [file] --target esp32 [--port /dev/ttyUSB0]
        \\  dhjsjs_cc transpile [file] [-o output]
        \\  dhjsjs_cc from <file.zig|rs|cpp|py> [-o output.dhjsjs]
        \\  dhjsjs_cc gui <board> [-o output.dhjsjs]
        \\  dhjsjs_cc --runtime <media-player|gui-srv|http-client|tls-client> ...
        \\
        \\Targets:
        \\  x86_64   - Linux x86_64
        \\  aarch64  - Linux ARM64
        \\  riscv32  - RISC-V 32-bit (ESP32-C3/C6)
        \\  xtensa   - Xtensa 32-bit (ESP8266/ESP32-S2/S3)
        \\  avr      - AVR 8-bit (Arduino Uno/Nano/Mega)
        \\  windows  - Windows x86_64 (.exe)
        \\  native   - auto-detect host architecture (default)
        \\  apk      - Android APK (aarch64)
        \\
        \\Transpile (other languages → dhjsjs):
        \\  dhjsjs_cc from file.zig    — Zig → dhjsjs
        \\  dhjsjs_cc from file.rs     — Rust → dhjsjs
        \\  dhjsjs_cc from file.cpp    — C++ → dhjsjs
        \\  dhjsjs_cc from file.py     — Python → dhjsjs
        \\
        \\Board GUI generation:
        \\  dhjsjs_cc gui esp32-s3    — ESP32-S3 with SPI TFT display
        \\  dhjsjs_cc gui stm32-f4    — STM32-F4 with FSMC parallel LCD
        \\  dhjsjs_cc gui rp2040      — RP2040 Pico with ST7789 SPI
        \\
        \\Cross-compilation:
        \\  dhjsjs_cc can cross-compile to any target from any host.
        \\  Windows .exe files can be built on Linux/macOS and run on Windows.
        \\
        \\APK build flags:
        \\  --package <name>       package name (default: com.dhjsjs.app)
        \\  --app-name <name>      application label (default: dhjsjs)
        \\  --permission <perm>    add permission (e.g. android.permission.INTERNET)
        \\  --min-sdk <num>        minimum SDK version (default: 26)
        \\  --version <num>        version code (default: 1)
        \\  --version-name <str>   version name (default: 1.0)
        \\  --release              release mode (no debuggable)
        \\  --no-sign              skip APK signing
        ;
    sys.writeStr(1, help.ptr, help.len);
}

fn cmdRuntime(args: []const []const u8) void {
    if (args.len < 3) {
        sys.writeStr(2, "error: runtime name required\n", 29);
        sys.exit(1);
    }
    const name = args[2];
    if (strEql(name, "media-player") or strEql(name, "media_player") or strEql(name, "media")) {
        media_player.main();
        return;
    }
    if (strEql(name, "gui-srv") or strEql(name, "gui_srv") or strEql(name, "gui")) {
        gui_srv.main();
        return;
    }
    if (strEql(name, "gl3-server") or strEql(name, "gl3_server") or strEql(name, "gl3")) {
        gl3_server.main() catch {};
        return;
    }
    if (strEql(name, "http-client") or strEql(name, "http_client") or strEql(name, "http")) {
        http_client.main();
        return;
    }
    if (strEql(name, "tls-client") or strEql(name, "tls_client") or strEql(name, "tls")) {
        tls_client.main();
        return;
    }
    sys.writeStr(2, "error: unknown runtime\n", 23);
    sys.exit(1);
}

fn dispatchHelperArgv0(name: []const u8) bool {
    if (strEql(name, "media_player")) {
        media_player.main();
        return true;
    }
    if (strEql(name, "gui_srv")) {
        gui_srv.main();
        return true;
    }
    if (strEql(name, "gl3_server")) {
        gl3_server.main() catch {};
        return true;
    }
    if (strEql(name, "http_client")) {
        http_client.main();
        return true;
    }
    if (strEql(name, "tls_client")) {
        tls_client.main();
        return true;
    }
    return false;
}

fn cmdGui(args: []const []const u8) void {
    if (args.len < 3) {
        sys.writeStr(1, "usage: dhjsjs_cc gui <board> [-o output]\n", 42);
        sys.writeStr(1, "boards: esp32-s3, stm32-f4, rp2040, esp8266\n", 44);
        sys.exit(0);
    }
    const board = args[2];
    var out_file: []const u8 = "output/gui_app.dhjsjs";
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (strEql(a, "-o") or strEql(a, "--output")) { i += 1; if (i < args.len) out_file = args[i]; }
    }

    var buf: [8192]u8 = undefined;
    var pos: usize = 0;
    pos += genStr("// Auto-generated GUI for ", &buf, pos);
    pos += genStr(board.ptr[0..board.len], &buf, pos);
    pos += genStr("\n\n", &buf, pos);

    // Board-specific display init
    if (strEql(board, "esp32-s3")) {
        pos += genStr("hui SPI_CS = 5;\nhui SPI_DC = 2;\nhui SPI_RST = 4;\nhui DISPLAY_W = 320;\nhui DISPLAY_H = 240;\n\n", &buf, pos);
        pos += genStr("fn spiWriteByte(b) {\n    syscall(0, SPI_CS, 0);\n    syscall(0, SPI_DC, 1);\n    syscall(0, SPI_CS, 1);\n}\n\n", &buf, pos);
    } else if (strEql(board, "stm32-f4")) {
        pos += genStr("hui DISPLAY_W = 320;\nhui DISPLAY_H = 240;\nhui FSMC_BASE = 0x60000000;\n\n", &buf, pos);
    } else if (strEql(board, "rp2040")) {
        pos += genStr("hui SPI_SCK = 18;\nhui SPI_MOSI = 19;\nhui SPI_CS = 5;\nhui DISPLAY_W = 240;\nhui DISPLAY_H = 240;\n\n", &buf, pos);
    } else {
        pos += genStr("hui DISPLAY_W = 160;\nhui DISPLAY_H = 128;\n\n", &buf, pos);
    }

    // Display driver
    pos += genStr("hui fb_ptr = 0;\n\n", &buf, pos);
    pos += genStr("fn displayInit() {\n    fb_ptr = mmap(0, DISPLAY_W * DISPLAY_H * 2, 3, 34, -1, 0);\n}\n\n", &buf, pos);
    pos += genStr("fn setPixel(x, y, color) {\n    if (x >= 0 and x < DISPLAY_W and y >= 0 and y < DISPLAY_H) {\n        hui off = (y * DISPLAY_W + x) * 2;\n        *(fb_ptr + off) = (color >> 8) & 0xFF;\n        *(fb_ptr + off + 1) = color & 0xFF;\n    }\n}\n\n", &buf, pos);
    pos += genStr("fn fillRect(x, y, w, h, color) {\n    hui j = y;\n    while (j < y + h) {\n        hui i = x;\n        while (i < x + w) {\n            setPixel(i, j, color);\n            i = i + 1;\n        }\n        j = j + 1;\n    }\n}\n\n", &buf, pos);

    // Widgets
    pos += genStr("fn drawButton(x, y, w, h, label, color) {\n    fillRect(x, y, w, h, color);\n}\n\n", &buf, pos);
    pos += genStr("fn drawLabel(x, y, text, color) {\n    hui i = 0;\n    while (i < strlen(text)) {\n        setPixel(x + i * 6, y, color);\n        i = i + 1;\n    }\n}\n\n", &buf, pos);
    pos += genStr("fn drawProgressBar(x, y, w, h, value, color) {\n    fillRect(x, y, w, h, 0x424242);\n    fillRect(x, y, w * value / 100, h, color);\n}\n\n", &buf, pos);
    pos += genStr("fn drawSlider(x, y, w, value, color) {\n    fillRect(x, y + 8, w, 4, 0x424242);\n    fillRect(x + w * value / 100 - 4, y, 8, 20, color);\n}\n\n", &buf, pos);
    pos += genStr("fn drawCheckbox(x, y, checked, color) {\n    fillRect(x, y, 16, 16, 0x424242);\n    if (checked) { fillRect(x + 3, y + 3, 10, 10, color); }\n}\n\n", &buf, pos);

    // Touch handler
    pos += genStr("fn handleTouch(x, y, pressed) {\n    if (pressed) { setPixel(x, y, 0xFFFF); }\n}\n\n", &buf, pos);

    // Main
    pos += genStr("fn main() {\n    displayInit();\n    fillRect(0, 0, DISPLAY_W, DISPLAY_H, 0x1A1A2E);\n    drawButton(20, 20, 120, 40, \"Click\", 0x4CAF50);\n    drawLabel(20, 70, \"Hello ", &buf, pos);
    pos += genStr(board.ptr[0..board.len], &buf, pos);
    pos += genStr("\", 0xFFFFFF);\n    drawProgressBar(20, 100, 200, 12, 65, 0x2196F3);\n    drawSlider(20, 130, 200, 50, 0xFF9800);\n    drawCheckbox(20, 160, 1, 0x4CAF50);\n    return 0;\n}\n", &buf, pos);

    if (!writeFile(out_file, buf[0..pos])) { sys.writeStr(2, "error: write failed\n", 20); sys.exit(1); }
    sys.writeStr(1, "gui generated: ", 15);
    sys.writeStr(1, out_file.ptr, out_file.len);
    sys.writeStr(1, "\n", 1);
}

fn cmdFrom(args: []const []const u8) void {
    if (args.len < 3) {
        sys.writeStr(1, "usage: dhjsjs_cc from <file.zig|rs|cpp|py> [-o output]\n", 52);
        sys.exit(0);
    }
    const src_file = args[2];
    var out_file: []const u8 = "output/out.dhjsjs";
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (strEql(a, "-o") or strEql(a, "--output")) { i += 1; if (i < args.len) out_file = args[i]; }
    }
    var buf: [BUFSIZE]u8 = undefined;
    const src = readFile(src_file, buf[0..]) orelse {
        sys.writeStr(2, "error: cannot read '", 20); sys.writeStr(2, src_file.ptr, src_file.len);
        sys.writeStr(2, "'\n", 2); sys.exit(1);
    };
    var obuf: [BUFSIZE * 2]u8 = undefined;
    var opos: usize = 0;
    opos += genStr("// Transpiled to dhjsjs\n\n", &obuf, opos);
    // Detect language by content
    var lang: u8 = 0; // 0=zig, 1=rust, 2=cpp, 3=python
    if (src.len > 2 and src[0] == 'f' and src[1] == 'n') lang = 0;
    if (src.len > 2 and src[0] == 'l' and src[1] == 'e') lang = 1;
    if (src.len > 1 and src[0] == '#' and src[1] == 'i') lang = 2;
    if (src.len > 2 and src[0] == 'd' and src[1] == 'e' and src[2] == 'f') lang = 3;
    if (src.len > 0 and src[0] == 'p') lang = 1;
    if (src.len > 0 and src[0] == 'c') lang = 2;
    // Transpile
    var si: usize = 0;
    while (si < src.len) : (si += 1) {
        const c = src[si];
        // Zig: const/var → hui, else → uebok, strip pub, strip types, println → print
        if (lang == 0) {
            if (si + 3 < src.len and src[si] == 'p' and src[si+1] == 'u' and src[si+2] == 'b') { si += 3; continue; }
            if (si + 4 < src.len and src[si] == 'c' and src[si+1] == 'o' and src[si+2] == 'n' and src[si+3] == 's') { opos += genStr("hui ", &obuf, opos); si += 4; continue; }
            if (si + 2 < src.len and src[si] == 'v' and src[si+1] == 'a' and src[si+2] == 'r') { opos += genStr("hui ", &obuf, opos); si += 3; continue; }
            if (si + 3 < src.len and src[si] == 'e' and src[si+1] == 'l' and src[si+2] == 's' and src[si+3] == 'e') { opos += genStr("uebok ", &obuf, opos); si += 4; continue; }
            if (si + 6 < src.len and src[si] == 'p' and src[si+1] == 'r' and src[si+2] == 'i' and src[si+3] == 'n' and src[si+4] == 't' and src[si+5] == 'l') { opos += genStr("print", &obuf, opos); si += 7; continue; }
            // Strip type annotations
            if (c == ':') { si += 1; while (si < src.len and ((src[si] >= 'a' and src[si] <= 'z') or (src[si] >= 'A' and src[si] <= 'Z') or (src[si] >= '0' and src[si] <= '9') or src[si] == '_')) { si += 1; } continue; }
            // Skip @attributes
            if (c == '@') { while (si < src.len and src[si] != '\n' and src[si] != '(') { si += 1; } continue; }
        }
        // Rust: let → hui, strip mut, else → uebok, println → print
        if (lang == 1) {
            if (si + 2 < src.len and src[si] == 'l' and src[si+1] == 'e' and src[si+2] == 't') { opos += genStr("hui ", &obuf, opos); si += 3; while (si < src.len and src[si] == ' ') { si += 1; } if (si + 2 < src.len and src[si] == 'm' and src[si+1] == 'u' and src[si+2] == 't') { si += 4; } continue; }
            if (si + 3 < src.len and src[si] == 'e' and src[si+1] == 'l' and src[si+2] == 's' and src[si+3] == 'e') { opos += genStr("uebok ", &obuf, opos); si += 4; continue; }
            if (si + 6 < src.len and src[si] == 'p' and src[si+1] == 'r' and src[si+2] == 'i') { opos += genStr("print", &obuf, opos); si += 7; continue; }
        }
        // C++: strip #include, type keywords → hui, else → uebok, nullptr → 0
        if (lang == 2) {
            if (c == '#' and si + 6 < src.len and src[si+1] == 'i') { while (si < src.len and src[si] != '\n') { si += 1; } continue; }
            if (si + 3 < src.len and src[si] == 'i' and src[si+1] == 'n' and src[si+2] == 't') { opos += genStr("hui ", &obuf, opos); si += 3; while (si < src.len and ((src[si] >= 'a' and src[si] <= 'z') or (src[si] >= 'A' and src[si] <= 'Z') or (src[si] >= '0' and src[si] <= '9') or src[si] == '_')) { si += 1; } continue; }
            if (si + 4 < src.len and src[si] == 'e' and src[si+1] == 'l' and src[si+2] == 's' and src[si+3] == 'e') { opos += genStr("uebok ", &obuf, opos); si += 4; continue; }
            if (si + 6 < src.len and src[si] == 'n' and src[si+1] == 'u') { opos += genStr("0", &obuf, opos); si += 7; continue; }
        }
        // Python: def → fn, True/False/None → 1/0/0, elif → uebok if, len → strlen
        if (lang == 3) {
            if (c == '#') { opos += genStr("//", &obuf, opos); si += 1; while (si < src.len and src[si] != '\n') { opos += genStr(&.{src[si]}, &obuf, opos); si += 1; } continue; }
            if (si + 2 < src.len and src[si] == 'd' and src[si+1] == 'e' and src[si+2] == 'f') { opos += genStr("fn ", &obuf, opos); si += 3; continue; }
            if (si + 3 < src.len and src[si] == 'e' and src[si+1] == 'l' and src[si+2] == 'i' and src[si+3] == 'f') { opos += genStr("uebok if ", &obuf, opos); si += 4; continue; }
            if (si + 3 < src.len and src[si] == 'l' and src[si+1] == 'e' and src[si+2] == 'n') { opos += genStr("strlen", &obuf, opos); si += 3; continue; }
        }
        obuf[opos] = c; opos += 1;
    }
    if (opos > 0) obuf[opos] = 0;
    if (!writeFile(out_file, obuf[0..opos])) { sys.writeStr(2, "error: write failed\n", 20); sys.exit(1); }
    sys.writeStr(1, "transpiled: ", 12);
    sys.writeStr(1, out_file.ptr, out_file.len);
    sys.writeStr(1, "\n", 1);
}

fn genStr(s: []const u8, buf: []u8, pos: usize) usize {
    var p = pos;
    for (s) |c| { if (p < buf.len) { buf[p] = c; p += 1; } }
    return p;
}

fn genFnC(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, buf: []u8, pos: usize) usize {
    var p = pos;
    const name = n.name_start[0..n.name_len];
    p = genStr("int64_t ", buf, p);
    p = genStr(name, buf, p);
    p = genStr("() {\n", buf, p);
    if (n.first_child != parser_mod.NO_NODE) p = genStmtC(n.first_child, pool, buf, p, &[_][]const u8{}, 0);
    p = genStr("\n}\n\n", buf, p);
    return p;
}

fn genStmtC(idx: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, buf: []u8, pos: usize, vars: []const []const u8, vc: usize) usize {
    if (idx == parser_mod.NO_NODE) return pos;
    const n = &pool[@as(usize, @intCast(idx))];
    var p = pos;
    switch (n.kind) {
        .block => {
            p = genStr("{\n", buf, p);
            var ch = n.first_child;
            while (ch != parser_mod.NO_NODE) { p = genStmtC(ch, pool, buf, p, vars, vc); ch = pool[@as(usize, @intCast(ch))].next_sibling; }
            p = genStr("}\n", buf, p);
        },
        .var_decl => {
            const vname = n.name_start[0..n.name_len];
            p = genStr("int64_t ", buf, p);
            p = genStr(vname, buf, p);
            if (n.first_child != parser_mod.NO_NODE) { p = genStr(" = ", buf, p); p = genExprC(n.first_child, pool, buf, p, vars, vc); }
            p = genStr(";\n", buf, p);
        },
        .ret_stmt => {
            p = genStr("return ", buf, p);
            if (n.first_child != parser_mod.NO_NODE) p = genExprC(n.first_child, pool, buf, p, vars, vc);
            p = genStr(";\n", buf, p);
        },
        .if_stmt => {
            const cond = n.first_child;
            const then_blk = if (cond != parser_mod.NO_NODE) pool[@as(usize, @intCast(cond))].next_sibling else parser_mod.NO_NODE;
            const else_blk = if (then_blk != parser_mod.NO_NODE) pool[@as(usize, @intCast(then_blk))].next_sibling else parser_mod.NO_NODE;
            p = genStr("if (", buf, p);
            if (cond != parser_mod.NO_NODE) p = genExprC(cond, pool, buf, p, vars, vc);
            p = genStr(") ", buf, p);
            if (then_blk != parser_mod.NO_NODE) p = genStmtC(then_blk, pool, buf, p, vars, vc);
            if (else_blk != parser_mod.NO_NODE) { p = genStr(" else ", buf, p); p = genStmtC(else_blk, pool, buf, p, vars, vc); }
        },
        .while_stmt => {
            const cond = n.first_child;
            const body = if (cond != parser_mod.NO_NODE) pool[@as(usize, @intCast(cond))].next_sibling else parser_mod.NO_NODE;
            p = genStr("while (", buf, p);
            if (cond != parser_mod.NO_NODE) p = genExprC(cond, pool, buf, p, vars, vc);
            p = genStr(") ", buf, p);
            if (body != parser_mod.NO_NODE) p = genStmtC(body, pool, buf, p, vars, vc);
        },
        .assign => {
            const aname = n.name_start[0..n.name_len];
            p = genStr(aname, buf, p); p = genStr(" = ", buf, p);
            if (n.first_child != parser_mod.NO_NODE) p = genExprC(n.first_child, pool, buf, p, vars, vc);
            p = genStr(";\n", buf, p);
        },
        else => { var ch = n.first_child; while (ch != parser_mod.NO_NODE) { p = genStmtC(ch, pool, buf, p, vars, vc); ch = pool[@as(usize, @intCast(ch))].next_sibling; } },
    }
    return p;
}

fn genExprC(idx: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, buf: []u8, pos: usize, vars: []const []const u8, vc: usize) usize {
    if (idx == parser_mod.NO_NODE) return genStr("0", buf, pos);
    const n = &pool[@as(usize, @intCast(idx))];
    var p = pos;
    switch (n.kind) {
        .int_lit => { const s = n.val_start[0..n.val_len]; for (s) |c| { if (p < buf.len) { buf[p] = c; p += 1; } } },
        .ident => { const s = n.name_start[0..n.name_len]; for (s) |c| { if (p < buf.len) { buf[p] = c; p += 1; } } },
        .binary_op => {
            const op = n.name_start[0..n.name_len];
            const left = n.first_child;
            const right = if (left != parser_mod.NO_NODE) pool[@as(usize, @intCast(left))].next_sibling else parser_mod.NO_NODE;
            p = genStr("(", buf, p);
            if (left != parser_mod.NO_NODE) p = genExprC(left, pool, buf, p, vars, vc);
            p = genStr(" ", buf, p);
            for (op) |c| { if (p < buf.len) { buf[p] = c; p += 1; } }
            p = genStr(" ", buf, p);
            if (right != parser_mod.NO_NODE) p = genExprC(right, pool, buf, p, vars, vc);
            p = genStr(")", buf, p);
        },
        .unary_op => {
            const op = n.name_start[0..n.name_len];
            const operand = n.first_child;
            p = genStr("(", buf, p);
            for (op) |c| { if (p < buf.len) { buf[p] = c; p += 1; } }
            if (operand != parser_mod.NO_NODE) p = genExprC(operand, pool, buf, p, vars, vc);
            p = genStr(")", buf, p);
        },
        .field_access => {
            const base = n.first_child;
            const field = n.name_start[0..n.name_len];
            if (base != parser_mod.NO_NODE) p = genExprC(base, pool, buf, p, vars, vc);
            p = genStr(".", buf, p);
            for (field) |c| { if (p < buf.len) { buf[p] = c; p += 1; } }
        },
        .array_index => {
            const arr2 = n.first_child;
            const idx2 = if (arr2 != parser_mod.NO_NODE) pool[@as(usize, @intCast(arr2))].next_sibling else parser_mod.NO_NODE;
            if (arr2 != parser_mod.NO_NODE) p = genExprC(arr2, pool, buf, p, vars, vc);
            p = genStr("[", buf, p);
            if (idx2 != parser_mod.NO_NODE) p = genExprC(idx2, pool, buf, p, vars, vc);
            p = genStr("]", buf, p);
        },
        .addr_of => { p = genStr("(&", buf, p); if (n.first_child != parser_mod.NO_NODE) p = genExprC(n.first_child, pool, buf, p, vars, vc); p = genStr(")", buf, p); },
        .deref => { p = genStr("(*", buf, p); if (n.first_child != parser_mod.NO_NODE) p = genExprC(n.first_child, pool, buf, p, vars, vc); p = genStr(")", buf, p); },
        .sizeof_expr => { p = genStr("sizeof(", buf, p); if (n.first_child != parser_mod.NO_NODE) p = genExprC(n.first_child, pool, buf, p, vars, vc); p = genStr(")", buf, p); },
        .call => {
            const cname = n.name_start[0..n.name_len];
            for (cname) |c| { if (p < buf.len) { buf[p] = c; p += 1; } }
            p = genStr("(", buf, p);
            var ch = n.first_child;
            var first = true;
            while (ch != parser_mod.NO_NODE) {
                if (!first) p = genStr(", ", buf, p);
                p = genExprC(ch, pool, buf, p, vars, vc);
                first = false;
                ch = pool[@as(usize, @intCast(ch))].next_sibling;
            }
            p = genStr(")", buf, p);
        },
        else => p = genStr("0", buf, p),
    }
    return p;
}

fn cmdTranspile(args: []const []const u8) void {
    _ = args;
    cmdHelp();
    sys.exit(0);
}

fn cmdFlash(args: []const []const u8) void {
    var src_file: []const u8 = DEFAULT_SRC;
    var target: Target = .x86_64;
    var port: []const u8 = "/dev/ttyUSB0";
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (strEql(a, "--target")) { i += 1; if (i < args.len) { target = parseTarget(args[i]) orelse { sys.writeStr(2, "error: unknown target\n", 22); sys.exit(1); }; } }
        else if (strEql(a, "--port")) { i += 1; if (i < args.len) port = args[i]; }
        else if (a.len > 0 and a[0] != '-') src_file = a;
    }
    if (target != .riscv32 and target != .avr and target != .xtensa) { sys.writeStr(2, "error: flash only supports riscv32/esp32, avr/arduino, and xtensa/esp8266 targets\n", 77); sys.exit(1); }
    var buf: [BUFSIZE]u8 = undefined;
    const src = readFile(src_file, buf[0..]) orelse { sys.writeStr(2, "error: cannot read '", 20); sys.writeStr(2, src_file.ptr, src_file.len); sys.writeStr(2, "'\n", 2); sys.exit(1); };
    const hex_path = "/tmp/dhjsjs_flash.hex\x00";
    if (!compileSource(src, target, hex_path[0..hex_path.len - 1])) { sys.writeStr(2, "error: compilation failed\n", 26); sys.exit(1); }
    if (target == .riscv32 or target == .xtensa) {
        if (!esp.flashElf(port, hex_path[0 .. hex_path.len - 1 :0])) sys.exit(1);
    } else if (target == .avr) {
        sys.writeStr(1, "wrote hex: ", 11);
        sys.writeStr(1, hex_path[0..hex_path.len - 1].ptr, hex_path.len - 1);
        sys.writeStr(1, "\nflash with: avrdude -p atmega328p -c arduino -P ", 49);
        sys.writeStr(1, port.ptr, port.len);
        sys.writeStr(1, " -b 115200 -U flash:w:", 22);
        sys.writeStr(1, hex_path[0..hex_path.len - 1].ptr, hex_path.len - 1);
        sys.writeStr(1, "\n", 1);
    }
}

pub fn main() void {
    var args: [16][]const u8 = undefined;
    var ai: usize = 0;
    var cmd_buf: [4096]u8 = undefined;

    if (sys.is_windows) {
        // Windows: use GetCommandLineA
        const cl_ptr = sys.WIN32_FUNCS.GetCommandLineA();
        if (cl_ptr != 0) {
            var pos: usize = 0;
            var arg_start: usize = 0;
            const cl: [*]const u8 = cl_ptr;
            while (cl[pos] != 0 and pos < 4095) : (pos += 1) {
                cmd_buf[pos] = cl[pos];
            }
            cmd_buf[pos] = 0;
            var i: usize = 0;
            while (i < pos and ai < 16) {
                // skip whitespace
                while (i < pos and (cmd_buf[i] == ' ' or cmd_buf[i] == '\t')) i += 1;
                if (i >= pos) break;
                arg_start = i;
                if (cmd_buf[i] == '"') {
                    i += 1;
                    arg_start = i;
                    while (i < pos and cmd_buf[i] != '"') i += 1;
                } else {
                    while (i < pos and cmd_buf[i] != ' ' and cmd_buf[i] != '\t') i += 1;
                }
                if (i > arg_start) {
                    args[ai] = cmd_buf[arg_start..i];
                    ai += 1;
                }
                if (i < pos) i += 1;
            }
        }
    } else {
        // Linux: read /proc/self/cmdline
        const fd = sys.open("/proc/self/cmdline\x00", 0, 0);
        if (fd >= 0) {
            const n = sys.read(fd, &cmd_buf, cmd_buf.len);
            sys.close(fd);
            if (n > 0) {
                var pos: usize = 0;
                while (pos < @as(usize, @intCast(n)) and ai < 16) {
                    args[ai] = cmd_buf[pos..pos + utils.strlen(cmd_buf[pos..].ptr)];
                    ai += 1;
                    pos += args[ai - 1].len + 1;
                }
            }
        }
    }
    if (ai >= 1 and dispatchHelperArgv0(args[0])) return;
    if (ai < 2) { cmdHelp(); sys.exit(0); }
    const cmd = args[1];
    var matched = false;
    if (strEql(cmd, "build")) { cmdBuild(args[0..ai]); matched = true; }
    if (strEql(cmd, "run")) { cmdRun(args[0..ai]); matched = true; }
    if (strEql(cmd, "new")) { cmdNew(args[0..ai]); matched = true; }
    if (strEql(cmd, "flash")) { cmdFlash(args[0..ai]); matched = true; }
    if (strEql(cmd, "transpile")) { cmdTranspile(args[0..ai]); matched = true; }
    if (strEql(cmd, "from")) { cmdFrom(args[0..ai]); matched = true; }
    if (strEql(cmd, "gui")) { cmdGui(args[0..ai]); matched = true; }
    if (strEql(cmd, "--runtime")) { cmdRuntime(args[0..ai]); matched = true; }
    if (strEql(cmd, "--help") or strEql(cmd, "-h")) { cmdHelp(); matched = true; }
    if (!matched) { sys.writeStr(2, "error: unknown command\n", 23); sys.exit(1); }
}
