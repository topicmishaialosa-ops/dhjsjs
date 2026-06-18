const sys = @import("sys.zig");
const gfx = @import("render.zig");
const ide_mod = @import("ide.zig");
const lexer_mod = @import("lexer.zig");
const parser_mod = @import("parser.zig");
const compiler_mod = @import("compiler.zig");
const codegen_mod = @import("codegen.zig");
const codegen_arm = @import("codegen_arm.zig");
const x11_mod = @import("x11.zig");
const wl_mod = @import("wayland.zig");

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;

const MODE_X11: u8 = 1;
const MODE_FBDEV: u8 = 2;
const MODE_PPM: u8 = 3;
const MODE_WAYLAND: u8 = 10;

fn savePpm(fb: *gfx.Framebuffer, path: [*]const u8) void {
    const fd = sys.open(path, sys.O_RDWR | 0x40 | 0x200, 0x1A4);
    if (fd < 0) return;
    const hs = "P6\n800 600\n255\n";
    _ = sys.write(fd, @as([*]const u8, @ptrCast(&hs)), 14);
    const total = @as(usize, fb.stride) * fb.height;
    var pi: usize = 0;
    while (pi < total) : (pi += 1) {
        const px = fb.pixels[pi];
        const rgb = [_]u8{ @as(u8, @intCast((px >> 16) & 0xFF)), @as(u8, @intCast((px >> 8) & 0xFF)), @as(u8, @intCast(px & 0xFF)) };
        _ = sys.write(fd, &rgb, 3);
    }
    sys.close(fd);
}

fn writeFile(path: [*]const u8, data: []const u8) void {
    const fd = sys.open(path, sys.O_RDWR | 0x40 | 0x200, 0x1A4);
    if (fd < 0) return;
    _ = sys.write(fd, @as([*]const u8, @ptrCast(&data[0])), data.len);
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
    const src = ide.content[0..ide.clen];
    var lex = lexer_mod.Lexer.init(@as([*]const u8, @ptrCast(&src[0])), src.len);
    while (true) { const t = lex.next(); if (t.kind == .eof) break; }
    var parser = parser_mod.Parser.init(@as([*]const u8, @ptrCast(&src[0])), src.len);
    _ = parser.parse();
    var cgen = compiler_mod.Compiler.init(&parser.pool);
    cgen.compileAsm();
    writeFile("/home/krasava2/dhjsjs/out.asm\x00", cgen.getOutput());

    var cb = codegen_mod.CodeBuffer.init();
    cb.movRImm64(codegen_mod.RAX, 60);
    cb.xorRR(codegen_mod.RDI, codegen_mod.RDI);
    cb.syscall();
    codegen_mod.buildElf64(&cb);
    writeFile("/home/krasava2/dhjsjs/out.bin\x00", cb.get());

    var cb_arm = codegen_arm.CodeBuffer.init();
    cb_arm.movRImm64(codegen_arm.X0, 93);
    cb_arm.movRImm64(codegen_arm.X8, 93);
    cb_arm.svc(0);
    cb_arm.buildElf64();
    writeFile("/home/krasava2/dhjsjs/out_arm64.bin\x00", cb_arm.get());

    ide.setStatus("built: x86_64 ELF + ARM64 ELF");
}

pub fn main() void {
    var fb = (gfx.Framebuffer.init(WIDTH, HEIGHT)) orelse {
        sys.writeStr(2, "Failed to init framebuffer\n", 28);
        sys.exit(1);
    };
    defer fb.deinit();

    var ide = ide_mod.IdeState.init();
    const source = "fn main() {\n    let x = 42;\n    let name = \"dhjsjs\";\n    return x;\n}\n\n/* Ctrl+S save | Ctrl+O open | F5 build */\n";
    ide.setContent(source);
    ide.setStatus("F5 build | arrows | Esc exit");

    var xconn: x11_mod.X11Conn = undefined;
    var wlconn: wl_mod.WlConn = undefined;
    var have_x11 = false;
    var have_wl = false;

    const conn = x11_mod.x11Open(0);
    if (conn) |c| {
        xconn = c;
        have_x11 = true;
        xconn.createWindow(0, 0, @as(u16, @intCast(WIDTH)), @as(u16, @intCast(HEIGHT)));
        xconn.setTitle("dhjsjs IDE");
        xconn.createGC();
        xconn.mapWindow();
    }
    if (!have_x11) {
        const wmo = wl_mod.WlConn.open(0);
        if (wmo) |c| {
            wlconn = c;
            if (wlconn.createSurface(WIDTH, HEIGHT)) {
                have_wl = true;
            }
        }
    }

    var running = true;
    var shift = false;
    var filepath_buf: [256]u8 = undefined;
    var filepath_len: usize = 0;

    if (have_x11) {
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
                        if (k == 9) { running = false; break; }
                        if (k == 22 or k == 119) ide.deleteChar();
                        if (k == 36) ide.insertChar('\n');
                        if (k == 65) ide.insertChar(' ');
                        if (k == 23) ide.insertChar('\t');
                        if (k == 111) ide.cursorUp();
                        if (k == 116) ide.cursorDown();
                        if (k == 113) ide.cursorLeft();
                        if (k == 114) ide.cursorRight();
                        if (k == 97) ide.cursorHome();
                        if (k == 103) ide.cursorEnd();
                        if (k == 50 or k == 62) shift = true;
                        if (k == 77) buildProject(&ide);
                        if (k == 37 and shift) { if (ide.flen > 0) ide.saveFile(); }
                        if (k == 32 and shift) { if (filepath_len > 0) { ide.openFile(filepath_buf[0..filepath_len]); filepath_len = 0; } }
                        const ch = if (shift) kcUpper(k) else kcLower(k);
                        if (ch >= ' ' and ch <= '~') ide.insertChar(ch);
                    }
                    if (e.type == 3) shift = false;
                    if (e.type == 33) { running = false; break; }
                    if (e.type == 12) {}
                }
            }
        }
        xconn.close();
    } else if (have_wl) {
        while (running) {
            ide.paint(&fb);
            wlconn.putImage(fb.pixels, WIDTH, HEIGHT);
            wlconn.commit();
            wlconn.dispatchEvents();
            if (!wlconn.running) break;
            var pfd: [1]sys.PollFd = undefined;
            pfd[0] = sys.PollFd{ .fd = wlconn.fd, .events = sys.POLLIN, .revents = 0 };
            if (sys.poll(&pfd, 1, 16) > 0 and (pfd[0].revents & sys.POLLIN) != 0) {
                wlconn.dispatchEvents();
                if (!wlconn.running) break;
            }
        }
        wlconn.close();
    } else {
        const ffd = sys.open("/dev/fb0\x00", sys.O_RDWR, 0);
        if (ffd >= 0) {
            sys.close(ffd);
            const sz = @as(usize, WIDTH) * @as(usize, HEIGHT) * 4;
            const ff = sys.open("/dev/fb0\x00", sys.O_RDWR, 0);
            if (ff >= 0) {
                const p = sys.mmap(null, sz, sys.PROT_READ | sys.PROT_WRITE, sys.MAP_SHARED, ff, 0);
                if (p) |rp| {
                    const d = @as([*]u8, @ptrCast(rp));
                    const s = @as([*]u8, @ptrCast(fb.pixels));
                    var i: usize = 0; while (i < sz) : (i += 1) d[i] = s[i];
                    sys.munmap(rp, sz);
                }
                sys.close(ff);
            }
        }
        ide.paint(&fb);
        savePpm(&fb, "/home/krasava2/dhjsjs.ppm\x00");
    }

    sys.exit(0);
}
