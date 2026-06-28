const parser_mod = @import("parser.zig");
const compiler_mod = @import("compiler.zig");
const compiler_rv = @import("compiler_rv.zig");
const compiler_arm = @import("compiler_arm.zig");
const codegen_mod = @import("codegen.zig");
const codegen_arm = @import("codegen_arm.zig");
const codegen_rv = @import("codegen_rv.zig");
const compiler_avr = @import("compiler_avr.zig");
const codegen_avr = @import("codegen_avr.zig");
const crypto = @import("crypto.zig");
const sys = @import("sys.zig");
const utils = @import("utils.zig");
const errors_mod = @import("errors.zig");
const esp = @import("esp.zig");
const axml = @import("axml.zig");
const zip = @import("zip.zig");
const media_player = @import("media_player.zig");
const gui_srv = @import("gui_srv.zig");
const http_client = @import("http_client.zig");
const tls_client = @import("tls_client.zig");

const Target = enum { x86_64, aarch64, riscv32, avr, apk, raw, native, windows };

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

    if (target == .apk) {
        manifest.permissions = perm_list[0..perm_count];

        var errs = errors_mod.ErrorList.init(src.ptr, src.len);
        var parser = parser_mod.Parser.init(src.ptr, src.len, &errs);
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
    } else if (!compileSource(src, target, out_file)) {
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
    var errs = errors_mod.ErrorList.init(src.ptr, src.len);
    var parser = parser_mod.Parser.init(src.ptr, src.len, &errs);
    const prog = parser.parse();
    if (errs.hasErrors()) { errs.printAll(); sys.exit(1); }
    var cb = compiler_mod.compile(prog, &parser.pool, &errs);
    if (errs.hasErrors()) { errs.printAll(); sys.exit(1); }
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
        \\dhjsjs compiler v0.2
        \\
        \\Usage:
        \\  dhjsjs_cc build [file] [-o output] [--target x86_64|aarch64|riscv32|esp32|native|apk]
        \\  dhjsjs_cc run [file]
        \\  dhjsjs_cc new <project>
        \\  dhjsjs_cc flash [file] --target esp32 [--port /dev/ttyUSB0]
        \\  dhjsjs_cc transpile [file] [-o output]
        \\  dhjsjs_cc --runtime <media-player|gui-srv|http-client|tls-client> ...
        \\
        \\Targets:
        \\  x86_64   - Linux x86_64
        \\  aarch64  - Linux ARM64
        \\  riscv32  - RISC-V 32-bit (ESP32-C3/C6)
        \\  esp32    - alias for riscv32
        \\  esp32c3  - alias for riscv32
        \\  avr      - AVR 8-bit (Arduino Uno/Nano/Mega)
        \\  arduino  - alias for avr
        \\  windows  - Windows x86_64 (.exe)
        \\  native   - auto-detect host architecture (default)
        \\  apk      - Android APK (aarch64)
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

fn cmdTranspile(args: []const []const u8) void {
    var src_file: []const u8 = DEFAULT_SRC;
    var out_file: []const u8 = "output/out.c";
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (strEql(a, "-o") or strEql(a, "--output")) { i += 1; if (i < args.len) out_file = args[i]; }
        else if (a.len > 0 and a[0] != '-') src_file = a;
    }
    var buf: [BUFSIZE]u8 = undefined;
    const src = readFile(src_file, buf[0..]) orelse { sys.writeStr(2, "error: cannot read file\n", 24); sys.exit(1); };
    var errs = errors_mod.ErrorList.init(src.ptr, src.len);
    var parser = parser_mod.Parser.init(src.ptr, src.len, &errs);
    _ = parser.parse();
    if (errs.hasErrors()) { errs.printAll(); sys.exit(1); }
    var cbuf: [BUFSIZE]u8 = undefined;
    var cpos: usize = 0;
    cpos += genStr("#include <stdlib.h>\n#include <stdio.h>\n#include <stdint.h>\n\n", &cbuf, cpos);
    var pi: usize = 0;
    while (pi < parser_mod.MAX_NODES) : (pi += 1) {
        const n = &parser.pool[pi];
        if (n.kind == .program) {
            var ch = n.first_child;
            while (ch != parser_mod.NO_NODE) {
                const cn = &parser.pool[@as(usize, @intCast(ch))];
                if (cn.kind == .fn_decl) cpos += genFnC(cn, &parser.pool, &cbuf, cpos);
                ch = cn.next_sibling;
            }
        }
    }
    if (cpos > 0) cbuf[cpos] = 0;
    if (!writeFile(out_file, cbuf[0..cpos])) { sys.writeStr(2, "error: write failed\n", 20); sys.exit(1); }
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
    if (target != .riscv32 and target != .avr) { sys.writeStr(2, "error: flash only supports riscv32/esp32 and avr/arduino targets\n", 63); sys.exit(1); }
    var buf: [BUFSIZE]u8 = undefined;
    const src = readFile(src_file, buf[0..]) orelse { sys.writeStr(2, "error: cannot read '", 20); sys.writeStr(2, src_file.ptr, src_file.len); sys.writeStr(2, "'\n", 2); sys.exit(1); };
    const hex_path = "/tmp/dhjsjs_flash.hex\x00";
    if (!compileSource(src, target, hex_path[0..hex_path.len - 1])) { sys.writeStr(2, "error: compilation failed\n", 26); sys.exit(1); }
    if (target == .riscv32) {
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
    if (ai >= 1 and dispatchHelperArgv0(args[0])) return;
    if (ai < 2) { cmdHelp(); sys.exit(0); }
    const cmd = args[1];
    var matched = false;
    if (strEql(cmd, "build")) { cmdBuild(args[0..ai]); matched = true; }
    if (strEql(cmd, "run")) { cmdRun(args[0..ai]); matched = true; }
    if (strEql(cmd, "new")) { cmdNew(args[0..ai]); matched = true; }
    if (strEql(cmd, "flash")) { cmdFlash(args[0..ai]); matched = true; }
    if (strEql(cmd, "transpile")) { cmdTranspile(args[0..ai]); matched = true; }
    if (strEql(cmd, "--runtime")) { cmdRuntime(args[0..ai]); matched = true; }
    if (strEql(cmd, "--help") or strEql(cmd, "-h")) { cmdHelp(); matched = true; }
    if (!matched) { sys.writeStr(2, "error: unknown command\n", 23); sys.exit(1); }
}
