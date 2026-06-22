const sys = @import("sys.zig");
const gfx = @import("render.zig");
const ide_mod = @import("ide.zig");
const parser_mod = @import("parser.zig");
const compiler_mod = @import("compiler.zig");
const errors_mod = @import("errors.zig");
const codegen_mod = @import("codegen.zig");
const codegen_arm = @import("codegen_arm.zig");
const x11_mod = @import("x11.zig");
const wl_mod = @import("wayland.zig");
const tty_mod = @import("tty.zig");

var WIDTH: u32 = 800;
var HEIGHT: u32 = 600;

fn writeFile(path: [*]const u8, data: []const u8) void {
    const fd = sys.open(path, sys.O_RDWR | 0x40 | 0x200, 0x1A4);
    if (fd < 0) return;
    _ = sys.write(fd, data.ptr, data.len);
    sys.close(fd);
}

fn kcLower(kc: u8) u8 {
    return switch (kc) {
        24 => 'q', 25 => 'w', 26 => 'e', 27 => 'r', 28 => 't', 29 => 'y',
        30 => 'u', 31 => 'i', 32 => 'o', 33 => 'p', 34 => '[', 35 => ']',
        38 => 'a', 39 => 's', 40 => 'd', 41 => 'f', 42 => 'g', 43 => 'h',
        44 => 'j', 45 => 'k', 46 => 'l', 47 => ';', 48 => '\'',
        52 => 'z', 53 => 'x', 54 => 'c', 55 => 'v', 56 => 'b', 57 => 'n',
        58 => 'm', 59 => ',', 60 => '.', 61 => '/',
        10 => '1', 11 => '2', 12 => '3', 13 => '4', 14 => '5', 15 => '6',
        16 => '7', 17 => '8', 18 => '9', 19 => '0', 20 => '-', 21 => '=',
        65 => ' ',
        else => 0,
    };
}

fn kcUpper(kc: u8) u8 {
    return switch (kc) {
        24 => 'Q', 25 => 'W', 26 => 'E', 27 => 'R', 28 => 'T', 29 => 'Y',
        30 => 'U', 31 => 'I', 32 => 'O', 33 => 'P', 34 => '{', 35 => '}',
        38 => 'A', 39 => 'S', 40 => 'D', 41 => 'F', 42 => 'G', 43 => 'H',
        44 => 'J', 45 => 'K', 46 => 'L', 47 => ':', 48 => '"',
        52 => 'Z', 53 => 'X', 54 => 'C', 55 => 'V', 56 => 'B', 57 => 'N',
        58 => 'M', 59 => '<', 60 => '>', 61 => '?',
        10 => '!', 11 => '@', 12 => '#', 13 => '$', 14 => '%', 15 => '^',
        16 => '&', 17 => '*', 18 => '(', 19 => ')', 20 => '_', 21 => '+',
        65 => ' ',
        else => 0,
    };
}

fn buildProject(ide: *ide_mod.IdeState) void {
    _ = sys.mkdir("output\x00", 0x1C0);

    const src = ide.content[0..ide.clen];
    var errs = errors_mod.ErrorList.init(src.ptr, src.len);
    var parser = parser_mod.Parser.init(src.ptr, src.len, &errs);
    const prog = parser.parse();

    if (errs.hasErrors()) {
        errs.printAll();
        ide.setStatus("build failed - check errors");
        return;
    }

    var cb = compiler_mod.compile(prog, &parser.pool, &errs);
    if (errs.hasErrors()) {
        errs.printAll();
        ide.setStatus("build failed - check errors");
        return;
    }
    cb.buildElf64();
    writeFile("output/out.bin\x00", cb.get());

    var cb_arm = codegen_arm.CodeBuffer.init();
    cb_arm.movRImm64(codegen_arm.X0, 93);
    cb_arm.movRImm64(codegen_arm.X8, 93);
    cb_arm.svc(0);
    cb_arm.buildElf64();
    writeFile("output/out_arm64.bin\x00", cb_arm.get());

    ide.setStatus("built: x86_64 ELF + ARM64 ELF");
    ide.addConsole("Build OK: out.bin (x86) + out_arm64.bin (ARM)\n");
}

fn parseEnv() void {
    var buf: [16]u8 = undefined;
    if (sys.getenv("DHJSJS_W", &buf)) |v| {
        var n: u32 = 0;
        for (v) |c| { if (c >= '0' and c <= '9') n = n * 10 + (c - '0'); }
        if (n > 0) WIDTH = n;
    }
    if (sys.getenv("DHJSJS_H", &buf)) |v| {
        var n: u32 = 0;
        for (v) |c| { if (c >= '0' and c <= '9') n = n * 10 + (c - '0'); }
        if (n > 0) HEIGHT = n;
    }
}

fn ttyMain(ide: *ide_mod.IdeState) void {
    var tty = tty_mod.TtyRender.init();
    tty.detectSize();

    var home_buf: [256]u8 = undefined;
    if (sys.getenv("HOME", &home_buf)) |home| {
        var pp: usize = 0;
        while (pp < ide.flen and pp < 255) : (pp += 1) {}
        if (pp == 0) {
            var fi: usize = 0;
            while (fi < home.len and fi < 200) : (fi += 1) ide.filename[fi] = home[fi];
            ide.filename[home.len] = '/';
            const def = "dhjsjs_code.txt";
            var di: usize = 0;
            while (di < def.len) : (di += 1) ide.filename[home.len + 1 + di] = def[di];
            ide.flen = home.len + 1 + def.len;
        }
    }

    const orig = (sys.setRawMode(sys.STDIN)) orelse {
        tty.paint(ide);
        _ = sys.read(sys.STDIN, @as([*]u8, undefined), 0);
        return;
    };
    defer sys.restoreMode(sys.STDIN, &orig);
    tty.clearScreen();

    var running = true;

    while (running) {
        tty.paint(ide);

        var buf: [16]u8 = undefined;
        const n = sys.read(sys.STDIN, &buf, 16);
        if (n <= 0) break;

        var i: usize = 0;
        while (i < @as(usize, @intCast(n))) : (i += 1) {
            const ch = buf[i];
            if (ch == 27) {
                if (ide.input_mode) {
                    ide.cancelInput();
                } else if (i + 2 < @as(usize, @intCast(n))) {
                    if (buf[i + 1] == '[') {
                        const c = buf[i + 2];
                        if (c == 'A') { ide.cursorUp(); i += 2; }
                        if (c == 'B') { ide.cursorDown(); i += 2; }
                        if (c == 'C') { ide.cursorRight(); i += 2; }
                        if (c == 'D') { ide.cursorLeft(); i += 2; }
                        if (c == 'H') { ide.cursorHome(); i += 2; }
                        if (c == 'F') { ide.cursorEnd(); i += 2; }
                    }
                    if (buf[i + 1] == '1' and i + 3 < @as(usize, @intCast(n)) and buf[i + 2] == '5' and buf[i + 3] == '~') {
                        buildProject(ide); i += 3;
                    }
                }
            } else if (ch == 127 or ch == 8) {
                ide.deleteChar();
            } else if (ch == '\r' or ch == '\n') {
                ide.insertChar('\n');
            } else if (ch == '\t') {
                ide.insertChar('\t');
            } else if (ch == 3) {
                running = false;
                break;
            } else if (ch == 19) {
                if (ide.flen > 0) ide.saveFile();
            } else if (ch == 15) {
                ide.startInput("open");
            } else if (ch >= 32 and ch < 127) {
                ide.insertChar(ch);
            }
        }
    }
    tty.deinit();
}

pub fn main() void {
    parseEnv();

    var xconn: x11_mod.X11Conn = undefined;
    var wlconn: wl_mod.WlConn = undefined;
    var have_x11 = false;
    var have_wl = false;

    const x11_avail = x11_mod.x11Open(0);
    if (x11_avail) |c| {
        xconn = c;
        have_x11 = true;
    }

    if (!have_x11 or WIDTH > 800 or HEIGHT > 600) {
        const wl = wl_mod.WlConn.open(0);
        if (wl) |c| {
            wlconn = c;
            have_wl = wlconn.createSurface(WIDTH, HEIGHT);
        }
    }

    if (have_x11) {
        var fb = (gfx.Framebuffer.init(WIDTH, HEIGHT)) orelse {
            sys.writeStr(2, "Failed to init framebuffer\n", 28);
            sys.exit(1);
        };
        defer fb.deinit();

        var ide = ide_mod.IdeState.init();
        const source = 
        \\fn main() int {
        \\    hui x = 42;
        \\    hui name = "dhjsjs";
        \\    return x;
        \\}
        ;
        ide.setContent(source);
        ide.addConsole("dhjsjs IDE ready  |  F5=Build  Ctrl+S=Save  Ctrl+O=Open\n");

        xconn.createWindow(0, 0, @as(u16, @intCast(WIDTH)), @as(u16, @intCast(HEIGHT)));
        xconn.setTitle("dhjsjs IDE");
        xconn.createGC();
        xconn.selectInput(1 | 2 | 4 | 8 | 64 | 32768 | 131072);
        xconn.mapWindow();

        var running = true;
        var shift = false;
        var ctrl = false;

        while (running) {
            ide.paint(&fb);
            xconn.putImage(fb.pixels, WIDTH, HEIGHT);

            var pfd: [1]sys.PollFd = undefined;
            pfd[0] = sys.PollFd{ .fd = xconn.fd, .events = sys.POLLIN, .revents = 0 };

            _ = sys.poll(&pfd, 1, 30);
            if ((pfd[0].revents & sys.POLLIN) != 0) {
                if (xconn.nextEvent()) |e| {
                    if (e.type == 2) {
                        const k = @as(u8, @intCast(e.keycode));

                        if (ide.input_mode) {
                            if (k == 9) { ide.cancelInput(); }
                            else if (k == 22 or k == 119) { ide.deleteChar(); }
                            else if (k == 36) { ide.insertChar('\n'); }
                            else {
                                const chh = if (shift) kcUpper(k) else kcLower(k);
                                if (chh >= ' ' and chh <= '~') ide.insertChar(chh);
                            }
                        } else {
                            if (k == 9) { running = false; break; }
                            if (k == 22 or k == 119) { ide.deleteChar(); }
                            else if (k == 36) { ide.insertChar('\n'); }
                            else if (k == 65) { ide.insertChar(' '); }
                            else if (k == 23) { ide.insertChar('\t'); }
                            else if (k == 111) { ide.cursorUp(); }
                            else if (k == 116) { ide.cursorDown(); }
                            else if (k == 113) { ide.cursorLeft(); }
                            else if (k == 114) { ide.cursorRight(); }
                            else if (k == 97) { ide.cursorHome(); }
                            else if (k == 103) { ide.cursorEnd(); }
                            else if (k == 37) { ctrl = true; }
                            else if (k == 109) { ctrl = true; }
                            else if (k == 50 or k == 62) { shift = true; }
                            else if (k == 77) { buildProject(&ide); }
                            else if (k == 39 and ctrl) { if (ide.flen > 0) ide.saveFile(); }
                            else if (k == 32 and ctrl) { ide.startInput("open"); }
                            else {
                                const chh = if (shift) kcUpper(k) else kcLower(k);
                                if (!ctrl and chh >= ' ' and chh <= '~') ide.insertChar(chh);
                            }
                        }
                    }
                    if (e.type == 3) { shift = false; ctrl = false; }
                    if (e.type == 4) {
                        if (e.detail == 1) {
                            ide.handleMouseClick(@as(i32, e.event_x), @as(i32, e.event_y), WIDTH, HEIGHT);
                            if (ide.request_build) {
                                ide.request_build = false;
                                buildProject(&ide);
                            }
                        }
                    }
                    if (e.type == 33) { running = false; break; }
                }
            }
        }
        xconn.close();
    } else if (have_wl) {
        var fb = (gfx.Framebuffer.init(WIDTH, HEIGHT)) orelse {
            sys.writeStr(2, "Failed to init framebuffer\n", 28);
            sys.exit(1);
        };
        defer fb.deinit();

        var ide = ide_mod.IdeState.init();
        const source =
    \\fn main() int {
    \\    hui x = 42;
    \\    hui name = "dhjsjs";
    \\    return x;
    \\}
;
        ide.setContent(source);
        ide.addConsole("dhjsjs IDE ready  |  F5=Build  Ctrl+S=Save  Ctrl+O=Open\n");

        while (true) {
            ide.paint(&fb);
            wlconn.putImage(fb.pixels, WIDTH, HEIGHT);
            wlconn.commit();
            while (wlconn.pollEvent()) |ev| {
                switch (ev) {
                    .key_press => |kc| { if (kc == 1) wlconn.running = false; },
                    .close => wlconn.running = false,
                    else => {},
                }
                if (!wlconn.running) break;
            }
            if (!wlconn.running) break;
        }
        wlconn.close();
    } else {
        var ide = ide_mod.IdeState.init();
        const source =
    \\fn main() int {
    \\    hui x = 42;
    \\    hui name = "dhjsjs";
    \\    return x;
    \\}
;
        ide.setContent(source);
        ide.addConsole("dhjsjs IDE ready  |  F5=Build  Ctrl+S=Save  Ctrl+O=Open\n");
        ttyMain(&ide);
    }

    sys.exit(0);
}
