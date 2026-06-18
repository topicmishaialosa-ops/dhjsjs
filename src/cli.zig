const parser_mod = @import("parser.zig");
const compiler_mod = @import("compiler.zig");
const codegen_mod = @import("codegen.zig");
const codegen_arm = @import("codegen_arm.zig");
const codegen_rv = @import("codegen_rv.zig");
const sys = @import("sys.zig");
const utils = @import("utils.zig");

const Target = enum { x86_64, aarch64, riscv32 };

const BUFSIZE = 65536;

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

fn parseTarget(s: []const u8) ?Target {
    if (strEql(s, "x86_64")) return .x86_64;
    if (strEql(s, "aarch64")) return .aarch64;
    if (strEql(s, "riscv32") or strEql(s, "esp32") or strEql(s, "esp32c3")) return .riscv32;
    return null;
}

fn compileSource(src: []const u8, target: Target, out_path: []const u8) bool {
    var parser = parser_mod.Parser.init(src.ptr, src.len);
    const prog = parser.parse();

    switch (target) {
        .x86_64 => {
            var cb = compiler_mod.compile(prog, &parser.pool);
            cb.buildElf64();
            if (!writeFile(out_path, cb.get())) return false;
        },
        .aarch64 => {
            var cb = codegen_arm.CodeBuffer.init();
            cb.movRImm64(codegen_arm.X8, 93);
            cb.movRImm64(codegen_arm.X0, 0);
            cb.svc(0);
            cb.buildElf64();
            if (!writeFile(out_path, cb.get())) return false;
        },
        .riscv32 => {
            var cb = codegen_rv.CodeBuffer.init();
            cb.li(codegen_rv.A7, 93);
            cb.li(codegen_rv.A0, 0);
            cb.ecall();
            cb.buildElf32();
            if (!writeFile(out_path, cb.get())) return false;
        },
    }
    return true;
}

fn cmdBuild(args: []const []const u8) void {
    var src_file: []const u8 = "src/main.dhjsjs";
    var out_file: []const u8 = "output/out.bin";
    var target: Target = .x86_64;

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
        } else if (a.len > 0 and a[0] != '-') {
            src_file = a;
        }
    }

    var buf: [BUFSIZE]u8 = undefined;
    const src = readFile(src_file, buf[0..]) orelse {
        sys.writeStr(2, "error: cannot read '", 20);
        sys.writeStr(2, src_file.ptr, src_file.len);
        sys.writeStr(2, "'\n", 2);
        sys.exit(1);
    };

    if (!compileSource(src, target, out_file)) {
        sys.writeStr(2, "error: compilation failed\n", 26);
        sys.exit(1);
    }

    sys.writeStr(1, "built: ", 7);
    sys.writeStr(1, out_file.ptr, out_file.len);
    sys.writeStr(1, "\n", 1);
}

fn cmdRun(args: []const []const u8) void {
    var src_file: []const u8 = "src/main.dhjsjs";
    var target: Target = .x86_64;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (strEql(a, "--target")) {
            i += 1;
            if (i < args.len) {
                target = parseTarget(args[i]) orelse {
                    sys.writeStr(2, "error: unknown target '", 24);
                    sys.writeStr(2, args[i].ptr, args[i].len);
                    sys.writeStr(2, "'\n", 2);
                    sys.exit(1);
                };
            }
        } else if (a.len > 0 and a[0] != '-') {
            src_file = a;
        }
    }

    if (target != .x86_64) {
        sys.writeStr(2, "error: run only supports x86_64 target\n", 39);
        sys.exit(1);
    }

    var buf: [BUFSIZE]u8 = undefined;
    const src = readFile(src_file, buf[0..]) orelse {
        sys.writeStr(2, "error: cannot read '", 20);
        sys.writeStr(2, src_file.ptr, src_file.len);
        sys.writeStr(2, "'\n", 2);
        sys.exit(1);
    };

    var parser = parser_mod.Parser.init(src.ptr, src.len);
    const prog = parser.parse();

    var cb = compiler_mod.compile(prog, &parser.pool);
    cb.buildElf64();

    var tmppath: [32]u8 = undefined;
    var ti: usize = 0;
    const tmpp = "/tmp/dhjsjs_run_XXXXXX";
    while (ti < tmpp.len and tmpp[ti] != 0) : (ti += 1) tmppath[ti] = tmpp[ti];
    tmppath[ti] = 0;

    const tmpfd = sys.open(&tmppath, sys.O_RDWR | 0x40, 0x1A4);
    if (tmpfd < 0) {
        sys.writeStr(2, "error: cannot create temp file\n", 31);
        sys.exit(1);
    }
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
    if (args.len < 3) {
        sys.writeStr(2, "error: project name required\n", 29);
        sys.exit(1);
    }
    const name = args[2];

    _ = sys.mkdir(name.ptr, 0x1C0);
    var src_dir: [256]u8 = undefined;
    var di: usize = 0;
    for (name) |c| { src_dir[di] = c; di += 1; }
    const suffix = "/src\x00";
    for (suffix) |c| { src_dir[di] = c; di += 1; }

    _ = sys.mkdir(&src_dir, 0x1C0);

    var main_path: [256]u8 = undefined;
    var mi: usize = 0;
    for (name) |c| { main_path[mi] = c; mi += 1; }
    const msuffix = "/src/main.dhjsjs\x00";
    for (msuffix) |c| { main_path[mi] = c; mi += 1; }

    const template =
        \\fn main() {
        \\    let x = 42;
        \\    return x;
        \\}
        ;

    const fd = sys.open(&main_path, sys.O_RDWR | 0x40 | 0x200, 0x1A4);
    if (fd >= 0) {
        _ = sys.write(fd, template.ptr, template.len);
        sys.close(fd);
    }

    sys.writeStr(1, "created project '", 17);
    sys.writeStr(1, name.ptr, name.len);
    sys.writeStr(1, "'\n", 2);
}

fn cmdHelp() void {
    const help =
        \\dhjsjs compiler v0.1
        \\
        \\Usage:
        \\  dhjsjs_cc build [file] [-o output] [--target x86_64|aarch64|riscv32|esp32]
        \\  dhjsjs_cc run [file]
        \\  dhjsjs_cc new <project>
        \\
        \\Targets:
        \\  x86_64   - Linux x86_64 (default)
        \\  aarch64  - Linux ARM64
        \\  riscv32  - RISC-V 32-bit (ESP32-C3 and similar)
        \\  esp32    - alias for riscv32
        ;
    sys.writeStr(1, help.ptr, help.len);
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

    if (ai < 2) {
        cmdHelp();
        sys.exit(0);
    }

    const cmd = args[1];
    if (strEql(cmd, "build")) {
        cmdBuild(args[0..ai]);
    } else if (strEql(cmd, "run")) {
        cmdRun(args[0..ai]);
    } else if (strEql(cmd, "new")) {
        cmdNew(args[0..ai]);
    } else if (strEql(cmd, "--help") or strEql(cmd, "-h")) {
        cmdHelp();
    } else {
        sys.writeStr(2, "error: unknown command '", 24);
        sys.writeStr(2, cmd.ptr, cmd.len);
        sys.writeStr(2, "'\n", 2);
        sys.exit(1);
    }
}
