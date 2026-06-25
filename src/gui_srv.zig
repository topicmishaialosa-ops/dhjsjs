const sys = @import("sys.zig");
const gfx = @import("render.zig");
const display_mod = @import("display.zig");
const mouse_mod = @import("mouse.zig");
const gr = @import("gui_render.zig");

const W: u32 = 800;
const H: u32 = 600;
const MAX_WIDGETS: usize = 2048;
const MAX_LABEL: usize = 32;

const CMD_QUIT: u8 = 0;
const CMD_BUTTON: u8 = 1;
const CMD_SLIDER: u8 = 2;
const CMD_LABEL: u8 = 3;
const CMD_CHECKBOX: u8 = 4;
const CMD_FRAME: u8 = 5;
const CMD_PIXEL: u8 = 6;
const CMD_FILL_RECT: u8 = 7;
const CMD_DRAW_LINE: u8 = 8;
const CMD_FILL_CIRCLE: u8 = 9;
const CMD_FILL_GRADIENT_H: u8 = 10;
const CMD_FILL_GRADIENT_V: u8 = 11;
const CMD_WAIT: u8 = 12;
const CMD_SET_THEME: u8 = 13;
const CMD_SET_STYLE_COLOR: u8 = 14;
const CMD_SET_STYLE_ROUNDING: u8 = 15;
const CMD_HOTSPOT: u8 = 16;
const CMD_PANEL: u8 = 17;
const CMD_TEXT: u8 = 18;
const CMD_TRIANGLE: u8 = 19;
const CMD_GLASS_PANEL: u8 = 20;
const CMD_SHADOW: u8 = 21;
const CMD_SET_STYLE_FIELD: u8 = 22;
const CMD_CANVAS_CLEAR: u8 = 23;
const CMD_ROUND_RECT: u8 = 24;
const CMD_BORDER: u8 = 25;
const CMD_GRADIENT: u8 = 26;
const CMD_BEZIER: u8 = 27;
const CMD_SET_CLIP: u8 = 28;
const CMD_CLEAR_CLIP: u8 = 29;

const Widget = struct {
    type: u8,
    id: u32,
    x: i32,
    y: i32,
    w: u32,
    h: u32,
    label: [MAX_LABEL]u8,
    label_len: usize,
    val: f64,
    val_bits: u64,
};

fn readExact(fd: i32, buf: []u8) bool {
    var pos: usize = 0;
    while (pos < buf.len) {
        const n = sys.read(fd, buf.ptr + pos, buf.len - pos);
        if (n <= 0) return false;
        pos += @as(usize, @intCast(n));
    }
    return true;
}

fn writeExact(fd: i32, buf: []const u8) bool {
    var pos: usize = 0;
    while (pos < buf.len) {
        const n = sys.write(fd, buf.ptr + pos, buf.len - pos);
        if (n <= 0) return false;
        pos += @as(usize, @intCast(n));
    }
    return true;
}

fn readLe32(buf: []const u8, off: usize) u32 {
    return @as(u32, buf[off]) |
        (@as(u32, buf[off + 1]) << 8) |
        (@as(u32, buf[off + 2]) << 16) |
        (@as(u32, buf[off + 3]) << 24);
}

fn readLe64(buf: []const u8, off: usize) u64 {
    return @as(u64, buf[off]) |
        (@as(u64, buf[off + 1]) << 8) |
        (@as(u64, buf[off + 2]) << 16) |
        (@as(u64, buf[off + 3]) << 24) |
        (@as(u64, buf[off + 4]) << 32) |
        (@as(u64, buf[off + 5]) << 40) |
        (@as(u64, buf[off + 6]) << 48) |
        (@as(u64, buf[off + 7]) << 56);
}

fn readCmd(fd: i32, w: *Widget) bool {
    var bytes: [61]u8 = undefined;
    if (!readExact(fd, &bytes)) return false;
    w.type = bytes[0];
    w.id = readLe32(bytes[0..], 1);
    w.x = @as(i32, @bitCast(readLe32(bytes[0..], 5)));
    w.y = @as(i32, @bitCast(readLe32(bytes[0..], 9)));
    w.w = readLe32(bytes[0..], 13);
    w.h = readLe32(bytes[0..], 17);
    w.val_bits = readLe64(bytes[0..], 21);
    w.val = @as(f64, @bitCast(w.val_bits));
    w.label_len = 0;
    var li: usize = 0;
    while (li < MAX_LABEL) : (li += 1) {
        w.label[li] = bytes[29 + li];
        if (w.label_len == li and bytes[29 + li] != 0) {
            w.label_len += 1;
        }
    }
    return true;
}

fn writeU32LE(buf: []u8, off: usize, v: u32) void {
    buf[off + 0] = @as(u8, @intCast(v & 0xFF));
    buf[off + 1] = @as(u8, @intCast((v >> 8) & 0xFF));
    buf[off + 2] = @as(u8, @intCast((v >> 16) & 0xFF));
    buf[off + 3] = @as(u8, @intCast((v >> 24) & 0xFF));
}

fn writeF64LE(buf: []u8, off: usize, v: f64) void {
    const bits = @as(u64, @bitCast(v));
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        buf[off + i] = @as(u8, @intCast((bits >> @as(u6, @intCast(i * 8))) & 0xFF));
    }
}

fn appendEvent(results: []u8, count: *u16, id: u32, value: f64) void {
    const ri = 2 + @as(usize, count.*) * 12;
    if (ri + 12 > results.len) return;
    writeU32LE(results, ri, id);
    writeF64LE(results, ri + 4, value);
    count.* += 1;
}

fn rawU32(v: u64) u32 {
    return @as(u32, @intCast(v & 0xFFFFFFFF));
}

fn colorFromBits(v: u64) u32 {
    const c = rawU32(v);
    return if ((c & 0xFF000000) == 0) 0xFF000000 | c else c;
}

fn unitFromBits(v: u64) f64 {
    const raw = rawU32(v);
    if (raw <= 1) return @as(f64, @floatFromInt(raw));
    if (raw <= 100) return @as(f64, @floatFromInt(raw)) / 100.0;
    return 1.0;
}

fn packedX(v: u64) i32 {
    return @as(i32, @bitCast(rawU32(v)));
}

fn packedY(v: u64) i32 {
    return @as(i32, @bitCast(@as(u32, @intCast((v >> 32) & 0xFFFFFFFF))));
}

fn applyTheme(renderer: *gr.Renderer, id: u32) void {
    switch (id) {
        0 => renderer.setStyle(gr.style_dark),
        1 => renderer.setStyle(gr.style_light),
        2 => renderer.setStyle(gr.style_modern_dark),
        3 => renderer.setStyle(gr.style_modern_light),
        4 => renderer.setStyle(gr.style_diamond),
        else => {},
    }
}

fn demoMode(renderer: *gr.Renderer, disp: *display_mod.DisplayBackend) void {
    var mouse = mouse_mod.State.init();
    var click_count: u32 = 0;
    var slider_val: f64 = 0.5;
    var check_val = false;
    var running = true;

    renderer.setStyle(gr.style_modern_dark);
    while (running) {
        mouse.beginFrame();
        while (disp.pollEvent()) |ev| {
            switch (ev) {
                .key_press => |kc| {
                    if (kc == 9) running = false;
                },
                .key_release => {},
                .mouse_move, .mouse_down, .mouse_up, .scroll => mouse.applyEvent(ev),
                .close => running = false,
                .expose => {},
                .resize => {},
            }
        }
        mouse.endFrame();

        renderer.clear();
        renderer.text(20, 16, "dhjsjs GUI Demo", renderer.style.accent, 16);

        const btn_hovered = gr.hit(&mouse, 20, 50, 120, 30);
        renderer.button(20, 50, 120, 30, "Click me!", btn_hovered, false);
        if (btn_hovered and mouse.primary_pressed) click_count += 1;

        var cnt_buf: [32]u8 = undefined;
        var cnt_pos: usize = 0;
        var tmp = click_count;
        if (tmp == 0) {
            cnt_buf[0] = '0';
            cnt_pos = 1;
        } else {
            var digits: [16]u8 = undefined;
            var dc: usize = 0;
            while (tmp > 0) {
                digits[dc] = @as(u8, @intCast('0' + @rem(tmp, 10)));
                tmp = @divTrunc(tmp, 10);
                dc += 1;
            }
            var di = dc;
            while (di > 0) {
                di -= 1;
                cnt_buf[cnt_pos] = digits[di];
                cnt_pos += 1;
            }
        }
        renderer.text(20, 90, "Clicks: ", renderer.style.text, 8);
        renderer.text(70, 90, cnt_buf[0..cnt_pos], renderer.style.accent, 8);

        const slider_hovered = gr.hit(&mouse, 20, 134, 200, 12);
        renderer.slider(20, 120, 200, slider_val, "Volume", slider_hovered);
        if (mouse.primary_down and slider_hovered) {
            slider_val = @as(f64, @floatFromInt(mouse.x - 20)) / 200.0;
            if (slider_val < 0.0) slider_val = 0.0;
            if (slider_val > 1.0) slider_val = 1.0;
        }

        const chk_hovered = gr.hit(&mouse, 20, 156, 230, 18);
        renderer.checkbox(20, 156, "Enable feature", check_val, chk_hovered);
        if (chk_hovered and mouse.primary_pressed) check_val = !check_val;

        renderer.text(20, 210, "Press Escape to close", renderer.style.text, 8);
        disp.presentCanvas(renderer.canvas);
        renderer.resetDirty();
    }
}

pub fn main() void {
    var fb = gfx.Framebuffer.init(W, H) orelse {
        _ = sys.write(2, "gui_srv: framebuffer alloc failed\n", 35);
        sys.exit(1);
    };
    defer fb.deinit();

    var canvas = gfx.Canvas.init(&fb);
    var disp = display_mod.DisplayBackend.init(&fb);
    if (disp.getX11Conn()) |xconn| canvas.setNative(xconn);
    var renderer = gr.Renderer.init(&canvas);

    var pfd: [1]sys.PollFd = undefined;
    pfd[0] = sys.PollFd{ .fd = 0, .events = sys.POLLIN, .revents = 0 };
    const has_input = sys.poll(&pfd, 1, 3000) > 0 and (pfd[0].revents & sys.POLLIN) != 0;

    if (!has_input) {
        demoMode(&renderer, &disp);
        disp.close();
        sys.exit(0);
    }

    var widgets: [MAX_WIDGETS]Widget = undefined;
    var mouse = mouse_mod.State.init();
    var running = true;

    while (running) {
        var wc: usize = 0;
        var got_frame = false;

        while (wc < MAX_WIDGETS) {
            var cmd: Widget = undefined;
            if (!readCmd(0, &cmd)) {
                running = false;
                break;
            }
            if (cmd.type == CMD_QUIT) {
                running = false;
                break;
            }
            if (cmd.type == CMD_WAIT) {
                var waiting = true;
                while (waiting and running) {
                    while (disp.pollEvent()) |ev| {
                        switch (ev) {
                            .key_press => |kc| {
                                if (kc == 9) {
                                    waiting = false;
                                    running = false;
                                }
                            },
                            .close => {
                                waiting = false;
                                running = false;
                            },
                            else => {},
                        }
                    }
                }
                continue;
            }
            if (cmd.type == CMD_SET_STYLE_COLOR) {
                renderer.setStyleColor(cmd.id, rawU32(cmd.val_bits));
                continue;
            }
            if (cmd.type == CMD_SET_STYLE_ROUNDING) {
                const rounding = if (cmd.val_bits != 0) rawU32(cmd.val_bits) else cmd.id;
                renderer.setRounding(rounding);
                continue;
            }
            if (cmd.type == CMD_SET_STYLE_FIELD) {
                renderer.setStyleField(cmd.id, rawU32(cmd.val_bits));
                continue;
            }
            if (cmd.type == CMD_SET_THEME) {
                applyTheme(&renderer, cmd.id);
                continue;
            }
            if (cmd.type == CMD_FRAME) {
                got_frame = true;
                break;
            }
            widgets[wc] = cmd;
            wc += 1;
        }

        if (!got_frame or !running) {
            if (!running) break;
            continue;
        }

        mouse.beginFrame();
        while (disp.pollEvent()) |ev| {
            switch (ev) {
                .key_press => |kc| {
                    if (kc == 9) running = false;
                },
                .key_release => {},
                .mouse_move, .mouse_down, .mouse_up, .scroll => mouse.applyEvent(ev),
                .close => running = false,
                .expose => {},
                .resize => |r| {
                    _ = r;
                },
            }
        }
        mouse.endFrame();

        renderer.clear();

        var result_count: u16 = 0;
        var results_buf: [2 + 12 * MAX_WIDGETS]u8 = undefined;

        var i: usize = 0;
        while (i < wc) : (i += 1) {
            const w = &widgets[i];
            const label = w.label[0..w.label_len];
            const hovered = gr.hit(&mouse, w.x, w.y, w.w, w.h);
            const clicked = hovered and mouse.primary_pressed;

            switch (w.type) {
                CMD_BUTTON => {
                    renderer.button(w.x, w.y, w.w, w.h, label, hovered, false);
                    if (clicked) appendEvent(results_buf[0..], &result_count, w.id, 1.0);
                },
                CMD_SLIDER => {
                    renderer.slider(w.x, w.y, w.w, unitFromBits(w.val_bits), label, hovered);
                    if (mouse.primary_down and hovered and w.w > 0) {
                        var new_val = @as(f64, @floatFromInt(mouse.x - w.x)) / @as(f64, @floatFromInt(w.w));
                        if (new_val < 0.0) new_val = 0.0;
                        if (new_val > 1.0) new_val = 1.0;
                        appendEvent(results_buf[0..], &result_count, w.id, new_val);
                    }
                },
                CMD_LABEL => renderer.text(w.x, w.y, label, renderer.style.text, 8),
                CMD_CHECKBOX => {
                    var checked = w.val_bits != 0;
                    if (clicked) checked = !checked;
                    renderer.checkbox(w.x, w.y, label, checked, hovered);
                    appendEvent(results_buf[0..], &result_count, w.id, if (checked) 1.0 else 0.0);
                },
                CMD_PIXEL => renderer.rect(w.x, w.y, 1, 1, colorFromBits(w.val_bits)),
                CMD_FILL_RECT => renderer.rect(w.x, w.y, w.w, w.h, colorFromBits(w.val_bits)),
                CMD_DRAW_LINE => renderer.line(w.x, w.y, @as(i32, @intCast(w.w)), @as(i32, @intCast(w.h)), colorFromBits(w.val_bits)),
                CMD_FILL_CIRCLE => renderer.circle(w.x, w.y, w.w, colorFromBits(w.val_bits)),
                CMD_FILL_GRADIENT_H => {
                    renderer.gradient(w.x, w.y, w.w, w.h, colorFromBits(w.val_bits), colorFromBits(w.val_bits >> 32), false);
                },
                CMD_FILL_GRADIENT_V => {
                    renderer.gradient(w.x, w.y, w.w, w.h, colorFromBits(w.val_bits), colorFromBits(w.val_bits >> 32), true);
                },
                CMD_HOTSPOT => if (clicked) appendEvent(results_buf[0..], &result_count, w.id, w.val),
                CMD_PANEL => renderer.panel(w.x, w.y, w.w, w.h),
                CMD_TEXT => renderer.text(w.x, w.y, label, colorFromBits(w.val_bits), if (w.h == 0) 8 else w.h),
                CMD_TRIANGLE => {
                    const col = if (w.id == 0) renderer.style.accent else w.id;
                    renderer.triangle(w.x, w.y, @as(i32, @intCast(w.w)), @as(i32, @intCast(w.h)), packedX(w.val_bits), packedY(w.val_bits), colorFromBits(col));
                },
                CMD_GLASS_PANEL => {
                    const border = colorFromBits(w.val_bits);
                    const bg = colorFromBits(w.val_bits >> 32);
                    renderer.glassPanel(w.x, w.y, w.w, w.h, bg, border);
                },
                CMD_SHADOW => renderer.shadow(w.x, w.y, w.w, w.h, @as(u8, @intCast(@min(rawU32(w.val_bits), 255)))),
                CMD_CANVAS_CLEAR => renderer.rect(0, 0, renderer.canvas.fb.width, renderer.canvas.fb.height, colorFromBits(w.val_bits)),
                CMD_ROUND_RECT => renderer.roundedRect(w.x, w.y, w.w, w.h, w.id, colorFromBits(w.val_bits)),
                CMD_BORDER => renderer.drawBorder(w.x, w.y, w.w, w.h, colorFromBits(w.val_bits)),
                CMD_GRADIENT => renderer.gradientU32(w.x, w.y, w.w, w.h, colorFromBits(w.val_bits), colorFromBits(w.val_bits >> 32), @as(u8, @intCast(@min(w.id, 3)))),
                CMD_BEZIER => renderer.bezier(w.x, w.y, @as(i32, @intCast(w.w)), @as(i32, @intCast(w.h)), packedX(w.val_bits), packedY(w.val_bits), colorFromBits(w.id)),
                CMD_SET_CLIP => renderer.setClip(w.x, w.y, w.w, w.h),
                CMD_CLEAR_CLIP => renderer.clearClip(),
                else => {},
            }
        }

        disp.presentCanvas(&canvas);
        renderer.resetDirty();

        results_buf[0] = @as(u8, @intCast(result_count & 0xFF));
        results_buf[1] = @as(u8, @intCast((result_count >> 8) & 0xFF));
        _ = writeExact(1, results_buf[0 .. 2 + @as(usize, result_count) * 12]);
    }

    disp.close();
    sys.exit(0);
}
