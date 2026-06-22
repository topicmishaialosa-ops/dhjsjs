const sys = @import("sys.zig");
const gfx = @import("render.zig");
const display_mod = @import("display.zig");
const mouse_mod = @import("mouse.zig");

const W: u32 = 800;
const H: u32 = 600;
const MAX_WIDGETS: usize = 64;
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

var BG: u32 = 0xFF1E1E1E;
var PANEL_BG: u32 = 0xFF2D2D2D;
var BTN_BG: u32 = 0xFF3C3C3C;
var BTN_HOVER: u32 = 0xFF4A4A4A;
var TEXT_COL: u32 = 0xFFD4D4D4;
var ACCENT: u32 = 0xFF569CD6;
var BORDER: u32 = 0xFF555555;
var CHECK_MARK: u32 = 0xFF4EC9B0;
var INPUT_BG: u32 = 0xFF1E1E1E;
var SEPARATOR: u32 = 0xFF333333;

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

fn readCmd(fd: i32, w: *Widget) bool {
    var header: [21]u8 = undefined;
    if (!readExact(fd, &header)) return false;
    w.type = header[0];
    w.id = @as(u32, @intCast(header[1])) |
           (@as(u32, @intCast(header[2])) << 8) |
           (@as(u32, @intCast(header[3])) << 16) |
           (@as(u32, @intCast(header[4])) << 24);
    w.x = @as(i32, @intCast(@as(u32, @intCast(header[5])) |
           (@as(u32, @intCast(header[6])) << 8) |
           (@as(u32, @intCast(header[7])) << 16) |
           (@as(u32, @intCast(header[8])) << 24)));
    w.y = @as(i32, @intCast(@as(u32, @intCast(header[9])) |
           (@as(u32, @intCast(header[10])) << 8) |
           (@as(u32, @intCast(header[11])) << 16) |
           (@as(u32, @intCast(header[12])) << 24)));
    w.w = @as(u32, @intCast(header[13])) |
          (@as(u32, @intCast(header[14])) << 8) |
          (@as(u32, @intCast(header[15])) << 16) |
          (@as(u32, @intCast(header[16])) << 24);
    w.h = @as(u32, @intCast(header[17])) |
          (@as(u32, @intCast(header[18])) << 8) |
          (@as(u32, @intCast(header[19])) << 16) |
          (@as(u32, @intCast(header[20])) << 24);
    var val_bytes: [8]u8 = undefined;
    if (!readExact(fd, &val_bytes)) return false;
    w.val = @as(f64, @bitCast(@as(u64, @intCast(val_bytes[0])) |
           (@as(u64, @intCast(val_bytes[1])) << 8) |
           (@as(u64, @intCast(val_bytes[2])) << 16) |
           (@as(u64, @intCast(val_bytes[3])) << 24) |
           (@as(u64, @intCast(val_bytes[4])) << 32) |
           (@as(u64, @intCast(val_bytes[5])) << 40) |
           (@as(u64, @intCast(val_bytes[6])) << 48) |
           (@as(u64, @intCast(val_bytes[7])) << 56)));
    var label_bytes: [MAX_LABEL]u8 = undefined;
    if (!readExact(fd, &label_bytes)) return false;
    w.label_len = 0;
    while (w.label_len < MAX_LABEL and label_bytes[w.label_len] != 0) {
        w.label[w.label_len] = label_bytes[w.label_len];
        w.label_len += 1;
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

fn colorR(c: u32) u8 { return @as(u8, @intCast((c >> 16) & 0xFF)); }
fn colorG(c: u32) u8 { return @as(u8, @intCast((c >> 8) & 0xFF)); }
fn colorB(c: u32) u8 { return @as(u8, @intCast(c & 0xFF)); }
fn colorA(c: u32) u8 { return @as(u8, @intCast((c >> 24) & 0xFF)); }

fn mixColor(a: u32, b: u32, amount_b: u8) u32 {
    const ia = @as(u32, 255 - amount_b);
    const ib = @as(u32, amount_b);
    const r = (@as(u32, colorR(a)) * ia + @as(u32, colorR(b)) * ib) / 255;
    const g = (@as(u32, colorG(a)) * ia + @as(u32, colorG(b)) * ib) / 255;
    const bl = (@as(u32, colorB(a)) * ia + @as(u32, colorB(b)) * ib) / 255;
    const al = (@as(u32, colorA(a)) * ia + @as(u32, colorA(b)) * ib) / 255;
    return (al << 24) | (r << 16) | (g << 8) | bl;
}

fn lightenColor(c: u32, amount: u8) u32 { return mixColor(c, 0xFFFFFFFF, amount); }
fn darkenColor(c: u32, amount: u8) u32 { return mixColor(c, 0xFF000000, amount); }

fn fillRect(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, color: u32) void {
    if (w == 0 or h == 0) return;
    const x1: u32 = if (x < 0) 0 else @intCast(x);
    const y1: u32 = if (y < 0) 0 else @intCast(y);
    const raw_x2 = x + @as(i32, @intCast(w));
    const raw_y2 = y + @as(i32, @intCast(h));
    if (raw_x2 <= 0 or raw_y2 <= 0) return;
    const x2: u32 = @min(@as(u32, @intCast(raw_x2)), fb.width);
    const y2: u32 = @min(@as(u32, @intCast(raw_y2)), fb.height);
    if (x2 <= x1 or y2 <= y1) return;
    var yi = y1;
    while (yi < y2) : (yi += 1) {
        const row = @as(usize, yi) * fb.stride;
        var xi = x1;
        while (xi < x2) : (xi += 1) {
            fb.pixels[row + xi] = color;
        }
    }
}

fn drawLineRaw(fb: *gfx.Framebuffer, x1: i32, y1: i32, x2: i32, y2: i32, color: u32) void {
    const dx: i32 = if (x2 >= x1) x2 - x1 else x1 - x2;
    const dy_abs: i32 = if (y2 >= y1) y2 - y1 else y1 - y2;
    const dy: i32 = -dy_abs;
    const sx: i32 = if (x1 < x2) 1 else -1;
    const sy: i32 = if (y1 < y2) 1 else -1;
    var err = dx + dy;
    var cx = x1;
    var cy = y1;
    while (true) {
        if (cx >= 0 and cy >= 0 and cx < @as(i32, @intCast(fb.width)) and cy < @as(i32, @intCast(fb.height))) {
            fb.pixels[@as(usize, @intCast(cy)) * fb.stride + @as(usize, @intCast(cx))] = color;
        }
        if (cx == x2 and cy == y2) break;
        const e2 = 2 * err;
        if (e2 >= dy) { err += dy; cx += sx; }
        if (e2 <= dx) { err += dx; cy += sy; }
    }
}

fn drawShadow(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, intensity: u8) void {
    if (intensity == 0) return;
    fillRect(fb, x + 2, y + 3, w, h, darkenColor(BG, intensity));
    fillRect(fb, x + 1, y + 2, w, h, darkenColor(BG, intensity / 2));
}

fn drawBox(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, bg: u32, border: u32, accent: bool) void {
    fillRect(fb, x, y, w, h, bg);
    if (w > 4 and h > 4) {
        fillRect(fb, x + 1, y + 1, w - 2, 1, lightenColor(bg, 28));
        fillRect(fb, x + 1, y + @as(i32, @intCast(h)) - 2, w - 2, 1, darkenColor(bg, 44));
    }
    if (accent and w > 8) {
        fillRect(fb, x + 3, y + @as(i32, @intCast(h)) - 3, w - 6, 2, ACCENT);
    }
    fillRect(fb, x, y, w, 1, border);
    fillRect(fb, x, y + @as(i32, @intCast(h)) - 1, w, 1, border);
    fillRect(fb, x, y, 1, h, border);
    fillRect(fb, x + @as(i32, @intCast(w)) - 1, y, 1, h, border);
}

fn drawBtn(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, label: []const u8, hovered: bool) void {
    if (hovered) drawShadow(fb, x, y, w, h, 38);
    drawBox(fb, x, y, w, h, if (hovered) BTN_HOVER else BTN_BG, if (hovered) ACCENT else BORDER, hovered);
    const tw = @as(u32, @intCast(label.len)) * 8;
    drawText(fb, label, x + @divTrunc(@as(i32, @intCast(w)) - @as(i32, @intCast(tw)), 2), y + @divTrunc(@as(i32, @intCast(h)) - 8, 2), if (hovered) 0xFFFFFFFF else TEXT_COL, 8);
}

fn drawSlider(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, _: u32, val: f64, label: []const u8, hovered: bool) void {
    drawText(fb, label, x, y, if (hovered) TEXT_COL else mixColor(TEXT_COL, BG, 80), 8);
    const sx = x;
    const sy = y + 16;
    const sw = w;
    const sh: u32 = 9;
    const v = if (val < 0.0) 0.0 else if (val > 1.0) 1.0 else val;
    fillRect(fb, sx, sy, sw, sh, darkenColor(SEPARATOR, 25));
    fillRect(fb, sx + 1, sy + 1, sw -| 2, 1, lightenColor(SEPARATOR, 30));
    const fill_w = @as(u32, @intFromFloat(@as(f64, @floatFromInt(sw)) * v));
    fillRect(fb, sx, sy, fill_w, sh, if (hovered) ACCENT else 0xFF3E7AB5);
    if (fill_w > 4) fillRect(fb, sx + 1, sy + 1, fill_w - 2, 1, lightenColor(ACCENT, 32));
    const thumb_x = sx + @as(i32, @intCast(fill_w));
    drawShadow(fb, thumb_x - 5, sy - 4, 10, 17, if (hovered) 45 else 22);
    drawBox(fb, thumb_x - 5, sy - 4, 10, 17, if (hovered) lightenColor(ACCENT, 20) else ACCENT, BORDER, false);
    fillRect(fb, sx, sy, sw, 1, BORDER);
    fillRect(fb, sx, sy + @as(i32, @intCast(sh)) - 1, sw, 1, BORDER);
}

fn drawLabel(fb: *gfx.Framebuffer, x: i32, y: i32, label: []const u8) void {
    drawText(fb, label, x, y, TEXT_COL, 8);
}

fn drawCheckbox(fb: *gfx.Framebuffer, x: i32, y: i32, label: []const u8, checked: bool, hovered: bool) void {
    const bg = if (checked) mixColor(INPUT_BG, ACCENT, 120) else if (hovered) BTN_HOVER else INPUT_BG;
    drawBox(fb, x, y, 16, 16, bg, if (hovered or checked) ACCENT else BORDER, false);
    if (checked) {
        drawLineRaw(fb, x + 4, y + 8, x + 7, y + 11, CHECK_MARK);
        drawLineRaw(fb, x + 5, y + 8, x + 8, y + 11, CHECK_MARK);
        drawLineRaw(fb, x + 7, y + 11, x + 13, y + 4, CHECK_MARK);
        drawLineRaw(fb, x + 8, y + 11, x + 14, y + 4, CHECK_MARK);
    }
    drawText(fb, label, x + 22, y + 4, if (hovered) TEXT_COL else mixColor(TEXT_COL, BG, 70), 8);
}

fn drawText(fb: *gfx.Framebuffer, text: []const u8, x: i32, y: i32, color: u32, size: u32) void {
    const scale = if (size >= 8) @as(u32, @intCast(@divFloor(size, 8))) else 1;
    var cx = x;
    var cy = y;
    for (text) |ch| {
        if (ch == '\n') { cy += @as(i32, @intCast(scale * 8 + 2)); cx = x; continue; }
        const glyph = gfx.getGlyph(ch);
        var gy: u32 = 0;
        while (gy < 8) : (gy += 1) {
            var gx: u32 = 0;
            while (gx < 8) : (gx += 1) {
                if ((glyph[gy] & (@as(u8, 1) << @intCast(7 - gx))) != 0) {
                    const bx = cx + @as(i32, @intCast(gx * scale));
                    const by = cy + @as(i32, @intCast(gy * scale));
                    var sy: u32 = 0;
                    while (sy < scale) : (sy += 1) {
                        var sx: u32 = 0;
                        while (sx < scale) : (sx += 1) {
                            const px = bx + @as(i32, @intCast(sx));
                            const py = by + @as(i32, @intCast(sy));
                            if (px >= 0 and py >= 0 and px < @as(i32, @intCast(fb.width)) and py < @as(i32, @intCast(fb.height))) {
                                fb.pixels[@as(usize, @intCast(py)) * fb.stride + @as(usize, @intCast(px))] = color;
                            }
                        }
                    }
                }
            }
        }
        cx += @as(i32, @intCast(scale * 8 + 2));
    }
}

fn valAsBytes(v: f64, buf: []u8) void {
    const bits = @as(u64, @bitCast(v));
    if (buf.len >= 8) {
        var i: usize = 0;
        while (i < 8) : (i += 1) {
            buf[i] = @as(u8, @intCast((bits >> @as(u6, @intCast(i * 8))) & 0xFF));
        }
    }
}

fn u32ToColor(c: u32) gfx.Color {
    return gfx.rgba(
        @as(u8, @intCast((c >> 16) & 0xFF)),
        @as(u8, @intCast((c >> 8) & 0xFF)),
        @as(u8, @intCast(c & 0xFF)),
        @as(u8, @intCast((c >> 24) & 0xFF)),
    );
}

fn demoMode(fb: *gfx.Framebuffer, disp: *display_mod.DisplayBackend) void {
    var mouse = mouse_mod.State.init();
    var click_count: u32 = 0;
    var slider_val: f64 = 0.5;
    var check_val = false;
    var running = true;

    while (running) {
        mouse.beginFrame();
        while (disp.pollEvent()) |ev| {
            switch (ev) {
                .key_press => |kc| { if (kc == 9) running = false; },
                .key_release => {},
                .mouse_move, .mouse_down, .mouse_up, .scroll => mouse.applyEvent(ev),
                .close => running = false,
                .expose => {},
                .resize => {},
            }
        }
        mouse.endFrame();

        fillRect(fb, 0, 0, W, H, BG);

        // Title
        drawText(fb, "dhjsjs GUI Demo", 20, 16, ACCENT, 16);

        // Button
        const bx: i32 = 20;
        const by: i32 = 50;
        const bw: u32 = 120;
        const bh: u32 = 30;
        const btn_hovered = mouse.hit(mouse_mod.rect(bx, by, bw, bh));
        drawBtn(fb, bx, by, bw, bh, "Click me!", btn_hovered);
        if (btn_hovered and mouse.primary_pressed) click_count += 1;

        var cnt_buf: [32]u8 = undefined;
        var cnt_pos: usize = 0;
        var tmp = click_count;
        if (tmp == 0) { cnt_buf[0] = '0'; cnt_pos = 1; }
        else {
            var digits: [16]u8 = undefined;
            var dc: usize = 0;
            while (tmp > 0) { digits[dc] = @as(u8, @intCast('0' + @rem(tmp, 10))); tmp = @divTrunc(tmp, 10); dc += 1; }
            var di = dc;
            while (di > 0) { di -= 1; cnt_buf[cnt_pos] = digits[di]; cnt_pos += 1; }
        }
        drawText(fb, "Clicks: ", 20, 90, TEXT_COL, 8);
        drawText(fb, cnt_buf[0..cnt_pos], 70, 90, ACCENT, 8);

        // Slider
        const slider_hovered = mouse.hit(mouse_mod.rect(20, 134, 200, 8));
        drawSlider(fb, 20, 120, 200, 12, slider_val, "Volume", slider_hovered);
        if (mouse.primary_down and slider_hovered) {
            slider_val = @as(f64, @floatFromInt(mouse.x - 20)) / 200.0;
            if (slider_val < 0.0) slider_val = 0.0;
            if (slider_val > 1.0) slider_val = 1.0;
        }

        // Checkbox
        const chk_hovered = mouse.hit(mouse_mod.rect(20, 156, 230, 14));
        drawCheckbox(fb, 20, 156, "Enable feature", check_val, chk_hovered);
        if (chk_hovered and mouse.primary_pressed) check_val = !check_val;

        // Info
        drawLabel(fb, 20, 200, "Press Escape to close");
        drawLabel(fb, 20, 218, "GUI framework: dhjsjs");

        disp.present();
    }
}

pub fn main() void {
    var fb = gfx.Framebuffer.init(W, H) orelse {
        _ = sys.write(2, "gui_srv: framebuffer alloc failed\n", 35);
        sys.exit(1);
    };
    defer fb.deinit();

    var disp = display_mod.DisplayBackend.init(&fb);

    var pfd: [1]sys.PollFd = undefined;
    pfd[0] = sys.PollFd{ .fd = 0, .events = sys.POLLIN, .revents = 0 };
    const has_input = sys.poll(&pfd, 1, 3000) > 0 and (pfd[0].revents & sys.POLLIN) != 0;

    if (!has_input) {
        demoMode(&fb, &disp);
        disp.close();
        sys.exit(0);
    }

    var widgets: [MAX_WIDGETS]Widget = undefined;

    var mouse = mouse_mod.State.init();
    var key_state: [256]bool = [_]bool{false} ** 256;

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
                            .key_press => |kc| { if (kc == 9) { waiting = false; running = false; } },
                            .close => { waiting = false; running = false; },
                            else => {},
                        }
                    }
                }
                continue;
            }
            if (cmd.type == CMD_SET_STYLE_COLOR) {
                const field_id = @as(u32, @intCast(cmd.id));
                const color = @as(u32, @intCast(@as(u64, @bitCast(cmd.val))));
                switch (field_id) {
                    0 => BG = 0xFF000000 | color,
                    1 => PANEL_BG = 0xFF000000 | color,
                    2 => BTN_BG = 0xFF000000 | color,
                    3 => BTN_HOVER = 0xFF000000 | color,
                    4 => TEXT_COL = 0xFF000000 | color,
                    5 => ACCENT = 0xFF000000 | color,
                    6 => BORDER = 0xFF000000 | color,
                    7 => CHECK_MARK = 0xFF000000 | color,
                    8 => INPUT_BG = 0xFF000000 | color,
                    9 => SEPARATOR = 0xFF000000 | color,
                    else => {},
                }
                continue;
            }
            if (cmd.type == CMD_SET_STYLE_ROUNDING) {
                // Stub — rounding not used in gui_srv's simple renderer
                continue;
            }
            if (cmd.type == CMD_SET_THEME) {
                // Apply theme based on theme id in cmd.id
                switch (cmd.id) {
                    0 => { // dark
                        BG = 0xFF1E1E1E;
                        PANEL_BG = 0xFF2D2D2D;
                        BTN_BG = 0xFF3C3C3C;
                        BTN_HOVER = 0xFF4A4A4A;
                        TEXT_COL = 0xFFD4D4D4;
                        ACCENT = 0xFF569CD6;
                        BORDER = 0xFF555555;
                        CHECK_MARK = 0xFF4EC9B0;
                        INPUT_BG = 0xFF1E1E1E;
                        SEPARATOR = 0xFF333333;
                    },
                    1 => { // light
                        BG = 0xFFF0F0F0;
                        PANEL_BG = 0xFFFFFFFF;
                        BTN_BG = 0xFFE0E0E0;
                        BTN_HOVER = 0xFFD0D0D0;
                        TEXT_COL = 0xFF202020;
                        ACCENT = 0xFF007ACC;
                        BORDER = 0xFFB0B0B0;
                        CHECK_MARK = 0xFF4EC9B0;
                        INPUT_BG = 0xFFFFFFFF;
                        SEPARATOR = 0xFFD8D8D8;
                    },
                    2 => { // modern dark
                        BG = 0xFF161820;
                        PANEL_BG = 0xFF222532;
                        BTN_BG = 0xFF3A3E52;
                        BTN_HOVER = 0xFF484C66;
                        TEXT_COL = 0xFFE8EBF8;
                        ACCENT = 0xFF6EA5FF;
                        BORDER = 0xFF363A4A;
                        CHECK_MARK = 0xFF50D282;
                        INPUT_BG = 0xFF1C1E2A;
                        SEPARATOR = 0xFF323648;
                    },
                    3 => { // modern light
                        BG = 0xFFF2F4F9;
                        PANEL_BG = 0xFFFFFFFF;
                        BTN_BG = 0xFFDCE1EC;
                        BTN_HOVER = 0xFFC9D0DF;
                        TEXT_COL = 0xFF1C2030;
                        ACCENT = 0xFF2A58A8;
                        BORDER = 0xFFC8CEDC;
                        CHECK_MARK = 0xFF269658;
                        INPUT_BG = 0xFFFFFFFF;
                        SEPARATOR = 0xFFD6DBE6;
                    },
                    else => {},
                }
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
                    if (kc < 256) key_state[kc] = true;
                },
                .key_release => |kc| { if (kc < 256) key_state[kc] = false; },
                .mouse_move, .mouse_down, .mouse_up, .scroll => mouse.applyEvent(ev),
                .close => running = false,
                .expose => {},
                .resize => |r| { _ = r; },
            }
        }
        mouse.endFrame();

        fillRect(&fb, 0, 0, W, H, BG);

        var result_count: u16 = 0;
        var results_buf: [2 + 12 * MAX_WIDGETS]u8 = undefined;

        var i: usize = 0;
        while (i < wc) : (i += 1) {
            const w = &widgets[i];
            const label = w.label[0..w.label_len];
            const hovered = mouse.hit(mouse_mod.rect(w.x, w.y, w.w, w.h));
            const clicked = hovered and mouse.primary_pressed;

            switch (w.type) {
                CMD_BUTTON => {
                    drawBtn(&fb, w.x, w.y, w.w, w.h, label, hovered);
                    if (clicked) {
                        const ri = 2 + result_count * 12;
                        if (ri + 12 <= results_buf.len) {
                            var id_le: [4]u8 = undefined;
                            id_le[0] = @as(u8, @intCast(w.id & 0xFF));
                            id_le[1] = @as(u8, @intCast((w.id >> 8) & 0xFF));
                            id_le[2] = @as(u8, @intCast((w.id >> 16) & 0xFF));
                            id_le[3] = @as(u8, @intCast((w.id >> 24) & 0xFF));
                            var vi: usize = 0;
                            while (vi < 4) : (vi += 1) results_buf[ri + vi] = id_le[vi];
                            valAsBytes(1.0, results_buf[ri + 4 .. ri + 12]);
                            result_count += 1;
                        }
                    }
                },
                CMD_SLIDER => {
                    drawSlider(&fb, w.x, w.y, w.w, w.h, w.val, label, hovered);
                    if (mouse.primary_down and hovered) {
                        var new_val = @as(f64, @floatFromInt(mouse.x - w.x)) / @as(f64, @floatFromInt(w.w));
                        if (new_val < 0.0) new_val = 0.0;
                        if (new_val > 1.0) new_val = 1.0;
                        const ri = 2 + result_count * 12;
                        if (ri + 12 <= results_buf.len) {
                            var id_le: [4]u8 = undefined;
                            id_le[0] = @as(u8, @intCast(w.id & 0xFF));
                            id_le[1] = @as(u8, @intCast((w.id >> 8) & 0xFF));
                            id_le[2] = @as(u8, @intCast((w.id >> 16) & 0xFF));
                            id_le[3] = @as(u8, @intCast((w.id >> 24) & 0xFF));
                            var vi: usize = 0;
                            while (vi < 4) : (vi += 1) results_buf[ri + vi] = id_le[vi];
                            valAsBytes(new_val, results_buf[ri + 4 .. ri + 12]);
                            result_count += 1;
                        }
                    }
                },
                CMD_LABEL => {
                    drawLabel(&fb, w.x, w.y, label);
                },
                CMD_CHECKBOX => {
                    var checked = w.val != 0.0;
                    if (clicked) checked = !checked;
                    drawCheckbox(&fb, w.x, w.y, label, checked, hovered);
                    const ri = 2 + result_count * 12;
                    if (ri + 12 <= results_buf.len) {
                        var id_le: [4]u8 = undefined;
                        id_le[0] = @as(u8, @intCast(w.id & 0xFF));
                        id_le[1] = @as(u8, @intCast((w.id >> 8) & 0xFF));
                        id_le[2] = @as(u8, @intCast((w.id >> 16) & 0xFF));
                        id_le[3] = @as(u8, @intCast((w.id >> 24) & 0xFF));
                        var vi: usize = 0;
                        while (vi < 4) : (vi += 1) results_buf[ri + vi] = id_le[vi];
                        valAsBytes(if (checked) 1.0 else 0.0, results_buf[ri + 4 .. ri + 12]);
                        result_count += 1;
                    }
                },
                else => {},
            }
        }

        disp.present();

        results_buf[0] = @as(u8, @intCast(result_count & 0xFF));
        results_buf[1] = @as(u8, @intCast((result_count >> 8) & 0xFF));
        _ = writeExact(1, results_buf[0 .. 2 + result_count * 12]);
    }

    disp.close();
    sys.exit(0);
}
