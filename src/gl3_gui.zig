// ============================================================================
// gl3_gui.zig — GPU-accelerated GUI demo using OpenGL 3.3
// Demonstrates full GL3 batch renderer with themed widgets
// ============================================================================

const gl3 = @import("gl3.zig");
const sys = @import("sys.zig");

// ---------------------------------------------------------------------------
// Theme colors (ARGB format: 0xAARRGGBB)
// ---------------------------------------------------------------------------
const BG_COLOR: u32 = 0xFF1E1E2E;
const PANEL_COLOR: u32 = 0xFF2A2A3C;
const BUTTON_COLOR: u32 = 0xFF3E8EAD;
const BUTTON_HOVER: u32 = 0xFF5BAFD4;
const BUTTON_ACTIVE: u32 = 0xFF2D7A96;
const TEXT_COLOR: u32 = 0xFFCDD6F4;
const TEXT_DIM: u32 = 0xFF6C7086;
const ACCENT: u32 = 0xFFF38BA8;
const ACCENT2: u32 = 0xFFA6E3A1;
const BORDER_COLOR: u32 = 0xFF45475A;
const INPUT_BG: u32 = 0xFF181825;
const SCROLLBAR_BG: u32 = 0xFF313244;
const SCROLLBAR_FG: u32 = 0xFF585B70;
const SEPARATOR: u32 = 0xFF585B70;
const SLIDER_TRACK: u32 = 0xFF45475A;
const SLIDER_FILL: u32 = 0xFF89B4FA;
const CHECK_ON: u32 = 0xFFA6E3A1;
const CHECK_OFF: u32 = 0xFF585B70;
const WIN_HEADER: u32 = 0xFF11111B;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
var mouse_x: i32 = 0;
var mouse_y: i32 = 0;
var mouse_down: bool = false;
var shift_held: bool = false;
var running = true;
var frame: u64 = 0;

// Widget state
var slider_val: f32 = 0.5;
var check_1: bool = true;
var check_2: bool = false;
var check_3: bool = true;
var tab_selected: u32 = 0;
var scroll_y: i32 = 0;
var btn_clicks: u32 = 0;
var progress: f32 = 0.3;

// Layout constants
const WIN_X: i32 = 80;
const WIN_Y: i32 = 60;
const WIN_W: i32 = 900;
const WIN_H: i32 = 600;
const HEADER_H: i32 = 48;
const SIDEBAR_W: i32 = 240;
const FOOTER_H: i32 = 36;
const PAD: i32 = 16;
const RADIUS: i32 = 10;

// ---------------------------------------------------------------------------
// Widget helpers
// ---------------------------------------------------------------------------

fn hitRect(x: i32, y: i32, w: i32, h: i32) bool {
    return mouse_x >= x and mouse_x < x + w and mouse_y >= y and mouse_y < y + h;
}

fn lerpColor(c1: u32, c2: u32, t: f32) u32 {
    const a1: f32 = @floatFromInt(c1 >> 24);
    const r1: f32 = @floatFromInt((c1 >> 16) & 0xFF);
    const g1: f32 = @floatFromInt((c1 >> 8) & 0xFF);
    const b1: f32 = @floatFromInt(c1 & 0xFF);
    const a2: f32 = @floatFromInt(c2 >> 24);
    const r2: f32 = @floatFromInt((c2 >> 16) & 0xFF);
    const g2: f32 = @floatFromInt((c2 >> 8) & 0xFF);
    const b2: f32 = @floatFromInt(c2 & 0xFF);
    const a = a1 + (a2 - a1) * t;
    const r = r1 + (r2 - r1) * t;
    const g = g1 + (g2 - g1) * t;
    const b = b1 + (b2 - b1) * t;
    return @as(u32, @intFromFloat(a)) << 24 | @as(u32, @intFromFloat(r)) << 16 | @as(u32, @intFromFloat(g)) << 8 | @as(u32, @intFromFloat(b));
}

fn drawButton(x: i32, y: i32, w: i32, h: i32, label: []const u8, id: u32) bool {
    _ = id;
    const hovered = hitRect(x, y, w, h);
    const pressed = hovered and mouse_down;
    const bg = if (pressed) BUTTON_ACTIVE else if (hovered) BUTTON_HOVER else BUTTON_COLOR;
    gl3.fillRoundedRect(x, y, w, h, RADIUS, bg);
    // Highlight line at top
    gl3.fillRect(x + RADIUS, y, w - RADIUS * 2, 1, 0x80FFFFFF);
    // Shadow at bottom
    gl3.fillRect(x + RADIUS, y + h - 1, w - RADIUS * 2, 1, 0x40000000);
    // Text centered
    const tw = @as(i32, @intCast(label.len)) * 8; // approx char width
    const tx = x + @divTrunc(w - tw, 2);
    const ty = y + @divTrunc(h - 10, 2);
    gl3.drawText(tx, ty, label, TEXT_COLOR, 1.0);
    return hovered and !mouse_down; // clicked on release
}

fn drawSlider(x: i32, y: i32, w: i32, h: i32, val: *f32) void {
    const track_h: i32 = 6;
    const track_y = y + @divTrunc(h - track_h, 2);
    // Track
    gl3.fillRoundedRect(x, track_y, w, track_h, 3, SLIDER_TRACK);
    // Fill
    const fill_w = @as(i32, @intFromFloat(val.* * @as(f32, @floatFromInt(w))));
    if (fill_w > 0) {
        gl3.fillRoundedRect(x, track_y, fill_w, track_h, 3, SLIDER_FILL);
    }
    // Thumb
    const thumb_x = x + fill_w - 8;
    const thumb_y = y + @divTrunc(h - 20, 2);
    gl3.fillRoundedRect(thumb_x, thumb_y, 16, 20, 8, 0xFFFFFFFF);

    // Interaction
    if (mouse_down and hitRect(x - 8, y, w + 16, h)) {
        const t = @as(f32, @floatFromInt(@max(0, @min(w, mouse_x - x)))) / @as(f32, @floatFromInt(w));
        val.* = @max(0, @min(1, t));
    }
}

fn drawCheckbox(x: i32, y: i32, checked: *bool, label: []const u8) void {
    const size: i32 = 20;
    // Box
    const bg = if (checked.*) CHECK_ON else CHECK_OFF;
    gl3.fillRoundedRect(x, y, size, size, 4, bg);
    if (checked.*) {
        // Checkmark (simple V shape with two lines)
        gl3.fillRect(x + 4, y + 10, 3, 3, 0xFFFFFFFF);
        gl3.fillRect(x + 7, y + 13, 3, 3, 0xFFFFFFFF);
        gl3.fillRect(x + 10, y + 10, 3, 3, 0xFFFFFFFF);
        gl3.fillRect(x + 13, y + 7, 3, 3, 0xFFFFFFFF);
    }
    // Label
    gl3.drawText(x + size + 10, y + 4, label, TEXT_COLOR, 1.0);
    // Click
    if (mouse_down and hitRect(x, y, size + @as(i32, @intCast(label.len)) * 8 + 10, size)) {
        // toggle on release — simple: just toggle when clicked inside
        checked.* = !checked.*;
    }
}

fn drawProgressBar(x: i32, y: i32, w: i32, h: i32, val: f32) void {
    gl3.fillRoundedRect(x, y, w, h, @divTrunc(h, 2), SLIDER_TRACK);
    const fw = @as(i32, @intFromFloat(val * @as(f32, @floatFromInt(w))));
    if (fw > 0) {
        gl3.fillRoundedRect(x, y, fw, h, @divTrunc(h, 2), SLIDER_FILL);
    }
}

fn drawSeparator(x: i32, y: i32, w: i32) void {
    gl3.fillRect(x, y, w, 1, SEPARATOR);
}

// ---------------------------------------------------------------------------
// Drawing functions for each section
// ---------------------------------------------------------------------------

fn drawHeader() void {
    // Header bar
    gl3.fillGradientH(WIN_X, WIN_Y, WIN_W, HEADER_H, 0xFF181825, 0xFF1E1E2E);
    gl3.drawText(WIN_X + PAD, WIN_Y + 16, "dhjsjs GPU — OpenGL 3.3", ACCENT, 1.5);

    // Tab buttons
    const tabs = [_][]const u8{ "Overview", "Widgets", "Themes", "About" };
    var tx = WIN_X + 300;
    for (tabs, 0..) |tab, i| {
        const tw = @as(i32, @intCast(tab.len)) * 8 + 24;
        const selected = tab_selected == i;
        const bg: u32 = if (selected) PANEL_COLOR else 0;
        gl3.fillRoundedRect(tx, WIN_Y + 8, tw, HEADER_H - 16, 6, bg);
        gl3.drawText(tx + 12, WIN_Y + 18, tab, if (selected) TEXT_COLOR else TEXT_DIM, 1.0);
        if (hitRect(tx, WIN_Y + 8, tw, HEADER_H - 16) and !mouse_down) {
            tab_selected = @intCast(i);
        }
        tx += tw + 4;
    }

    drawSeparator(WIN_X, WIN_Y + HEADER_H, WIN_W);
}

fn drawSidebar() void {
    const sx = WIN_X;
    const sy = WIN_Y + HEADER_H + 1;

    gl3.fillRect(sx, sy, SIDEBAR_W, WIN_H - HEADER_H - FOOTER_H - 1, PANEL_COLOR);
    drawSeparator(sx + SIDEBAR_W, sy, 1);

    var py = sy + PAD;

    // Controls section
    gl3.drawText(sx + PAD, py, "Controls", ACCENT2, 1.0);
    py += 30;

    // Button
    if (drawButton(sx + PAD, py, SIDEBAR_W - PAD * 2, 36, "Click Me", 0)) {
        btn_clicks += 1;
        progress = @min(1.0, progress + 0.1);
    }
    py += 44;
    gl3.drawText(sx + PAD, py, "Clicks: ", TEXT_DIM, 1.0);
    // Draw click count as digits
    var buf: [16]u8 = undefined;
    const num_str = u32ToStr(btn_clicks, &buf);
    gl3.drawText(sx + PAD + 56, py, num_str, ACCENT, 1.0);
    py += 30;

    // Slider
    gl3.drawText(sx + PAD, py, "Volume", TEXT_COLOR, 1.0);
    py += 22;
    drawSlider(sx + PAD, py, SIDEBAR_W - PAD * 2, 28, &slider_val);
    py += 36;

    // Checkboxes
    drawCheckbox(sx + PAD, py, &check_1, "VSync");
    py += 28;
    drawCheckbox(sx + PAD, py, &check_2, "Wireframe");
    py += 28;
    drawCheckbox(sx + PAD, py, &check_3, "Shadows");
    py += 36;

    // Progress
    gl3.drawText(sx + PAD, py, "Loading", TEXT_COLOR, 1.0);
    py += 22;
    drawProgressBar(sx + PAD, py, SIDEBAR_W - PAD * 2, 10, progress);
    py += 24;
    // Percentage text
    var pct_buf: [8]u8 = undefined;
    const pct_str = f32ToStr(progress * 100.0, &pct_buf);
    gl3.drawText(sx + PAD, py, pct_str, TEXT_DIM, 1.0);
}

fn drawMainContent() void {
    const mx = WIN_X + SIDEBAR_W + 1;
    const my = WIN_Y + HEADER_H + 1;
    const mw = WIN_W - SIDEBAR_W - 1;
    const mh = WIN_H - HEADER_H - FOOTER_H - 1;

    gl3.fillRect(mx, my, mw, mh, BG_COLOR);

    var py = my + PAD;

    switch (tab_selected) {
        0 => {
            // Overview tab
            gl3.drawText(mx + PAD, py, "OpenGL 3.3 GPU Renderer", ACCENT, 1.5);
            py += 36;
            gl3.drawText(mx + PAD, py, "Full GPU-accelerated 2D rendering", TEXT_COLOR, 1.0);
            py += 24;
            gl3.drawText(mx + PAD, py, "Batch renderer with up to 65K vertices per flush", TEXT_DIM, 1.0);
            py += 24;
            gl3.drawText(mx + PAD, py, "Font atlas texture from bitmap font data", TEXT_DIM, 1.0);
            py += 24;
            gl3.drawText(mx + PAD, py, "GLX context via raw X11 + libGL.so", TEXT_DIM, 1.0);
            py += 40;

            // Draw some demo shapes
            gl3.drawText(mx + PAD, py, "Shape Demo:", ACCENT2, 1.2);
            py += 30;

            // Gradient rectangle
            gl3.fillGradientH(mx + PAD, py, 200, 80, 0xFFF38BA8, 0xFF89B4FA);
            gl3.drawText(mx + PAD + 60, py + 32, "Gradient H", 0xFFFFFFFF, 1.0);
            py += 100;

            // Vertical gradient
            gl3.fillGradientV(mx + PAD, py, 200, 80, 0xFFA6E3A1, 0xFF89B4FA);
            gl3.drawText(mx + PAD + 50, py + 32, "Gradient V", 0xFFFFFFFF, 1.0);
            py += 100;

            // Rounded rects with different sizes
            gl3.drawText(mx + PAD, py, "Rounded Rects:", ACCENT2, 1.0);
            py += 24;
            gl3.fillRoundedRect(mx + PAD, py, 80, 40, 5, BUTTON_COLOR);
            gl3.fillRoundedRect(mx + PAD + 90, py, 80, 40, 10, ACCENT);
            gl3.fillRoundedRect(mx + PAD + 180, py, 80, 40, 20, ACCENT2);
            gl3.drawText(mx + PAD + 16, py + 14, "r=5", TEXT_COLOR, 1.0);
            gl3.drawText(mx + PAD + 106, py + 14, "r=10", TEXT_COLOR, 1.0);
            gl3.drawText(mx + PAD + 196, py + 14, "r=20", TEXT_COLOR, 1.0);
            py += 60;

            // Border demo
            gl3.drawText(mx + PAD, py, "Border:", ACCENT2, 1.0);
            py += 24;
            gl3.drawBorder(mx + PAD, py, 200, 60, ACCENT, 2);
            gl3.drawBorder(mx + PAD + 220, py, 200, 60, SLIDER_FILL, 3);
            py += 80;

            // Font scale demo
            gl3.drawText(mx + PAD, py, "Font Scales:", ACCENT2, 1.0);
            py += 24;
            gl3.drawText(mx + PAD, py, "Scale 0.5x", TEXT_COLOR, 0.5);
            py += 14;
            gl3.drawText(mx + PAD, py, "Scale 1.0x", TEXT_COLOR, 1.0);
            py += 18;
            gl3.drawText(mx + PAD, py, "Scale 1.5x", TEXT_COLOR, 1.5);
            py += 28;
            gl3.drawText(mx + PAD, py, "Scale 2.0x", TEXT_COLOR, 2.0);
            py += 40;

            // Many shapes stress test
            gl3.drawText(mx + PAD, py, "Stress Test (1000 rects):", ACCENT2, 1.0);
            py += 24;
            var i: u32 = 0;
            while (i < 1000) : (i += 1) {
                const rx = mx + PAD + @as(i32, @intCast(i % 25)) * 30;
                const ry = py + @as(i32, @intCast(i / 25)) * 12;
                const t = @as(f32, @floatFromInt(i)) / 1000.0;
                const c = lerpColor(0xFFF38BA8, 0xFF89B4FA, t);
                gl3.fillRect(rx, ry, 28, 10, c);
            }
        },
        1 => {
            // Widgets tab
            gl3.drawText(mx + PAD, py, "Widget Gallery", ACCENT, 1.5);
            py += 40;

            // Various button styles
            _ = drawButton(mx + PAD, py, 160, 40, "Primary", 1);
            _ = drawButton(mx + PAD + 170, py, 160, 40, "Secondary", 2);
            _ = drawButton(mx + PAD + 340, py, 120, 40, "Small", 3);
            py += 60;

            drawSeparator(mx + PAD, py, mw - PAD * 2);
            py += 20;

            // Slider with value display
            gl3.drawText(mx + PAD, py, "Slider Value:", TEXT_COLOR, 1.0);
            var val_buf: [8]u8 = undefined;
            const val_str = f32ToStr(slider_val * 100.0, &val_buf);
            gl3.drawText(mx + PAD + 120, py, val_str, ACCENT, 1.0);
            py += 24;
            drawSlider(mx + PAD, py, mw - PAD * 2, 32, &slider_val);
            py += 50;

            // Checkboxes
            drawCheckbox(mx + PAD, py, &check_1, "Enable Feature A");
            py += 30;
            drawCheckbox(mx + PAD, py, &check_2, "Enable Feature B");
            py += 30;
            drawCheckbox(mx + PAD, py, &check_3, "Enable Feature C");
            py += 40;

            // Progress bars
            gl3.drawText(mx + PAD, py, "Progress Bars:", TEXT_COLOR, 1.0);
            py += 24;
            drawProgressBar(mx + PAD, py, mw - PAD * 2, 12, progress);
            py += 20;
            drawProgressBar(mx + PAD, py, mw - PAD * 2, 12, 1.0 - progress);
            py += 20;
            drawProgressBar(mx + PAD, py, mw - PAD * 2, 12, slider_val);
            py += 30;

            // Auto-animate progress
            const t = @as(f32, @floatFromInt(@as(u32, @truncate(frame * 3)))) / 256.0;
            progress = (mathSin(t) + 1.0) * 0.5;
        },
        2 => {
            // Themes tab
            gl3.drawText(mx + PAD, py, "Color Palette", ACCENT, 1.5);
            py += 40;

            // Draw color swatches
            const colors = [_]struct { c: u32, name: []const u8 }{
                .{ .c = BG_COLOR, .name = "Background" },
                .{ .c = PANEL_COLOR, .name = "Panel" },
                .{ .c = BUTTON_COLOR, .name = "Button" },
                .{ .c = BUTTON_HOVER, .name = "Button Hover" },
                .{ .c = BUTTON_ACTIVE, .name = "Button Active" },
                .{ .c = ACCENT, .name = "Accent" },
                .{ .c = ACCENT2, .name = "Accent2" },
                .{ .c = TEXT_COLOR, .name = "Text" },
                .{ .c = TEXT_DIM, .name = "Text Dim" },
                .{ .c = INPUT_BG, .name = "Input BG" },
                .{ .c = SLIDER_FILL, .name = "Slider" },
                .{ .c = CHECK_ON, .name = "Check On" },
            };
            for (colors) |item| {
                gl3.fillRoundedRect(mx + PAD, py, 40, 24, 4, item.c);
                gl3.drawText(mx + PAD + 50, py + 4, item.name, TEXT_COLOR, 1.0);
                py += 32;
            }
        },
        3 => {
            // About tab
            gl3.drawText(mx + PAD, py, "dhjsjs — Zero Deps Compiler", ACCENT, 1.5);
            py += 40;
            gl3.drawText(mx + PAD, py, "OpenGL 3.3 Core Profile GPU Renderer", TEXT_COLOR, 1.2);
            py += 28;
            gl3.drawText(mx + PAD, py, "Features:", ACCENT2, 1.0);
            py += 24;
            gl3.drawText(mx + PAD + 16, py, "GLX context via X11 + libGL.so", TEXT_DIM, 1.0);
            py += 20;
            gl3.drawText(mx + PAD + 16, py, "GLSL 330 core shaders", TEXT_DIM, 1.0);
            py += 20;
            gl3.drawText(mx + PAD + 16, py, "Batch renderer (65K vertices)", TEXT_DIM, 1.0);
            py += 20;
            gl3.drawText(mx + PAD + 16, py, "Font atlas from bitmap font", TEXT_DIM, 1.0);
            py += 20;
            gl3.drawText(mx + PAD + 16, py, "Solid color, gradient, rounded rect, text", TEXT_DIM, 1.0);
            py += 20;
            gl3.drawText(mx + PAD + 16, py, "Alpha blending, scissor clipping", TEXT_DIM, 1.0);
            py += 40;
            gl3.drawText(mx + PAD, py, "Built with Zig 0.16 + raw syscalls", TEXT_DIM, 1.0);
        },
        else => {},
    }
}

fn drawFooter() void {
    const fy = WIN_Y + WIN_H - FOOTER_H;
    gl3.fillRect(WIN_X, fy, WIN_W, FOOTER_H, PANEL_COLOR);
    drawSeparator(WIN_X, fy, WIN_W);

    // FPS display
    var fps_buf: [16]u8 = undefined;
    const fps_str = u32ToStr(@intCast(frame % 10000), &fps_buf);
    gl3.drawText(WIN_X + PAD, fy + 10, "Frame: ", TEXT_DIM, 1.0);
    gl3.drawText(WIN_X + PAD + 56, fy + 10, fps_str, ACCENT, 1.0);

    // Mouse position
    var mx_buf: [16]u8 = undefined;
    var my_buf: [16]u8 = undefined;
    const mx_str = i32ToStr(mouse_x, &mx_buf);
    const my_str = i32ToStr(mouse_y, &my_buf);
    gl3.drawText(WIN_X + WIN_W - 200, fy + 10, "Mouse: ", TEXT_DIM, 1.0);
    gl3.drawText(WIN_X + WIN_W - 144, fy + 10, mx_str, TEXT_COLOR, 1.0);
    gl3.drawText(WIN_X + WIN_W - 120, fy + 10, ",", TEXT_DIM, 1.0);
    gl3.drawText(WIN_X + WIN_W - 112, fy + 10, my_str, TEXT_COLOR, 1.0);

    gl3.drawText(WIN_X + WIN_W / 2 - 80, fy + 10, "OpenGL 3.3 GPU", ACCENT2, 1.0);
}

// ---------------------------------------------------------------------------
// Number to string helpers (no std)
// ---------------------------------------------------------------------------

fn u32ToStr(val: u32, buf: []u8) []const u8 {
    if (val == 0) {
        buf[0] = '0';
        return buf[0..1];
    }
    var tmp: [16]u8 = undefined;
    var v = val;
    var i: usize = 0;
    while (v > 0) : (i += 1) {
        tmp[i] = @as(u8, @intCast(v % 10)) + '0';
        v /= 10;
    }
    var j: usize = 0;
    while (j < i) : (j += 1) {
        buf[j] = tmp[i - 1 - j];
    }
    return buf[0..i];
}

fn i32ToStr(val: i32, buf: []u8) []const u8 {
    if (val < 0) {
        buf[0] = '-';
        const rest = u32ToStr(@intCast(-val), buf[1..]);
        return buf[0 .. 1 + rest.len];
    }
    return u32ToStr(@intCast(val), buf);
}

fn f32ToStr(val: f32, buf: []u8) []const u8 {
    const int_part = @as(u32, @intFromFloat(val));
    const frac = @as(u32, @intFromFloat((val - @as(f32, @floatFromInt(int_part))) * 10.0));
    const int_str = u32ToStr(int_part, buf);
    if (int_str.len >= buf.len) return int_str;
    buf[int_str.len] = '.';
    if (int_str.len + 1 >= buf.len) return buf[0 .. int_str.len + 1];
    buf[int_str.len + 1] = @as(u8, @intCast(frac % 10)) + '0';
    return buf[0 .. int_str.len + 2];
}

fn mathSin(x: f32) f32 {
    var v = x;
    const pi: f32 = 3.14159265;
    while (v > pi) v -= 2 * pi;
    while (v < -pi) v += 2 * pi;
    const v2 = v * v;
    return v - v * v2 / 6.0 + v * v2 * v2 / 120.0 - v * v2 * v2 * v2 / 5040.0;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

pub fn main() !void {
    if (!gl3.init(1024, 700)) {
        const msg = "Failed to initialize OpenGL 3.3. Check that libGL.so and libX11.so are available.\n";
        _ = sys.write(2, msg.ptr, msg.len);
        return;
    }
    defer gl3.deinit();

    while (running) {
        while (gl3.pollEvent()) |ev| {
            switch (ev) {
                .close => running = false,
                .key_press => |kc| {
                    if (kc == 9) running = false;
                    if (kc == 50) shift_held = true;
                },
                .key_release => |kc| {
                    if (kc == 50) shift_held = false;
                },
                .mouse_down => |md| {
                    mouse_x = md.x;
                    mouse_y = md.y;
                    mouse_down = true;
                },
                .mouse_up => |md| {
                    mouse_x = md.x;
                    mouse_y = md.y;
                    mouse_down = false;
                },
                .mouse_move => |md| {
                    mouse_x = md.x;
                    mouse_y = md.y;
                },
                .resize => {},
            }
        }

        gl3.beginFrame();
        drawHeader();
        drawSidebar();
        drawMainContent();
        drawFooter();
        gl3.endFrame();

        frame += 1;
        // ~60fps via nanosleep
        var ts: sys.Timespec = .{ .sec = 0, .nsec = 16_000_000 };
        _ = sys.nanosleep(&ts, null);
    }
}
