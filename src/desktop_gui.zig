const sys = @import("sys.zig");
const gfx = @import("render.zig");
const gui_mod = @import("gui.zig");
const gui_ext = @import("gui_ext.zig");
const display_mod = @import("display.zig");

const W: u32 = 900;
const H: u32 = 640;

fn itoa(val: i32, buf: []u8) usize {
    var v = val;
    if (v < 0) { buf[0] = '-'; v = -v; return 1 + itoa(v, buf[1..]); }
    if (v == 0) { buf[0] = '0'; return 1; }
    var tmp: [16]u8 = undefined;
    var i: usize = 0;
    while (v > 0) { tmp[i] = @as(u8, @intCast('0' + @rem(v, 10))); v = @divTrunc(v, 10); i += 1; }
    var j: usize = 0;
    while (j < i) { buf[j] = tmp[i - 1 - j]; j += 1; }
    return i;
}

fn ftoa(val: f32, buf: []u8) usize {
    var v = val;
    if (v < 0) { buf[0] = '-'; v = -v; return 1 + ftoa(v, buf[1..]); }
    if (v < 0.0001) { buf[0] = '0'; return 1; }
    var tmp: [16]u8 = undefined;
    var vi: i32 = @as(i32, @intFromFloat(v));
    var i: usize = 0;
    if (vi == 0) { tmp[i] = '0'; i += 1; }
    else { while (vi > 0) { tmp[i] = @as(u8, @intCast('0' + @rem(vi, 10))); vi = @divTrunc(vi, 10); i += 1; } }
    var j: usize = 0;
    while (j < i) { buf[j] = tmp[i - 1 - j]; j += 1; }
    var pos = i;
    buf[pos] = '.'; pos += 1;
    var frac: i32 = @as(i32, @intFromFloat((v - @as(f32, @floatFromInt(@as(i32, @intFromFloat(v))))) * 100.0));
    if (frac < 0) frac = -frac;
    if (frac > 99) frac = 99;
    buf[pos] = @as(u8, @intCast('0' + @divTrunc(frac, 10))); pos += 1;
    buf[pos] = @as(u8, @intCast('0' + @rem(frac, 10))); pos += 1;
    return pos;
}

fn strcpy(dst: []u8, src: []const u8) usize {
    var i: usize = 0;
    while (i < src.len and i < dst.len - 1) { dst[i] = src[i]; i += 1; }
    dst[i] = 0;
    return i;
}

const StyleInfo = struct { name: []const u8, style: gui_mod.Style };

fn allStyles() []const StyleInfo {
    return &[_]StyleInfo{
        .{ .name = "Dark (default)", .style = gui_mod.style_dark },
        .{ .name = "Light", .style = gui_mod.style_light },
        .{ .name = "Dracula", .style = gui_mod.style_dracula },
        .{ .name = "Nord", .style = gui_mod.style_nord },
        .{ .name = "Solarized Dark", .style = gui_mod.style_solarized_dark },
        .{ .name = "Solarized Light", .style = gui_mod.style_solarized_light },
        .{ .name = "Monokai", .style = gui_mod.style_monokai },
        .{ .name = "One Dark", .style = gui_mod.style_one_dark },
        .{ .name = "GitHub Light", .style = gui_mod.style_github_light },
        .{ .name = "Gruvbox Dark", .style = gui_mod.style_gruvbox_dark },
        .{ .name = "Gruvbox Light", .style = gui_mod.style_gruvbox_light },
        .{ .name = "Catppuccin", .style = gui_mod.style_catppuccin },
        .{ .name = "Tokyo Night", .style = gui_mod.style_tokyo_night },
        .{ .name = "Ayu Dark", .style = gui_mod.style_ayu_dark },
        .{ .name = "Ayu Light", .style = gui_mod.style_ayu_light },
        .{ .name = "Material Dark", .style = gui_mod.style_material_dark },
        .{ .name = "Material Light", .style = gui_mod.style_material_light },
        .{ .name = "High Contrast", .style = gui_mod.style_high_contrast },
        .{ .name = "Retro Terminal", .style = gui_mod.style_retro_terminal },
        .{ .name = "Forest", .style = gui_mod.style_forest },
        .{ .name = "Ocean", .style = gui_mod.style_ocean },
        .{ .name = "Sunset", .style = gui_mod.style_sunset },
        .{ .name = "Candy", .style = gui_mod.style_candy },
        .{ .name = "Monochrome", .style = gui_mod.style_monochrome },
        .{ .name = "Rose Pine", .style = gui_mod.style_rose_pine },
        .{ .name = "Everforest", .style = gui_mod.style_everforest },
        .{ .name = "Nord Light", .style = gui_mod.style_nord_light },
    };
}

pub fn main() void {
    var fb = gfx.Framebuffer.init(W, H) orelse {
        _ = sys.write(2, "desktop_gui: failed to allocate framebuffer\n", 45);
        sys.exit(1);
    };
    defer fb.deinit();

    var disp = display_mod.DisplayBackend.init(&fb);
    var gui = gui_mod.Gui.init(&fb);

    const styles = allStyles();
    var style_idx: usize = 0;

    var mouse_x: i32 = 0;
    var mouse_y: i32 = 0;
    var mouse_down = false;
    var mouse_clicked = false;
    var mouse_released = false;
    var scroll_delta: i32 = 0;

    var key_state: [gui_mod.MAX_KEY]bool = [_]bool{false} ** gui_mod.MAX_KEY;

    var checkbox_val = false;
    var slider_val: f32 = 0.65;
    var click_count: u32 = 0;
    var collapsible_open = true;
    var text_buf: [256]u8 = [_]u8{0} ** 256;
    _ = strcpy(text_buf[0..], "hello");
    var combo_idx: usize = 0;

    var running = true;
    while (running) {
        mouse_clicked = false;
        mouse_released = false;
        scroll_delta = 0;

        while (disp.pollEvent()) |event| {
            switch (event) {
                .key_press => |kc| {
                    if (kc == 9) running = false;
                    if (kc < gui_mod.MAX_KEY) key_state[kc] = true;
                },
                .key_release => |kc| {
                    if (kc < gui_mod.MAX_KEY) key_state[kc] = false;
                },
                .mouse_move => |m| { mouse_x = m.x; mouse_y = m.y; },
                .mouse_down => |m| { mouse_x = m.x; mouse_y = m.y; mouse_down = true; mouse_clicked = true; },
                .mouse_up => |m| { mouse_x = m.x; mouse_y = m.y; mouse_down = false; mouse_released = true; },
                .close => running = false,
                .expose => {},
                .resize => |r| { _ = r; },
                .scroll => |s| { scroll_delta += s.dy; },
            }
        }

        const input = gui_mod.InputState{
            .mouse_x = mouse_x, .mouse_y = mouse_y,
            .mouse_down = mouse_down, .mouse_clicked = mouse_clicked,
            .mouse_released = mouse_released, .scroll = scroll_delta,
            .keys = key_state,
            .keys_pressed = [_]bool{false} ** gui_mod.MAX_KEY,
            .text_input = [_]u8{0} ** 16, .text_len = 0,
        };

        gui.beginFrame(&fb, input);

        _ = gui.beginWindow("deskgui — Desktop GUI", 0, 0, W, 32, false);
        gui.labelColored("  dhjsjs Desktop GUI  |  Esc=exit", gui.style.accent);
        gui.endWindow();

        // Widgets demo
        _ = gui.beginWindow("Widget Demo", 8, 34, 430, 296, true);
        gui.label("Interactive Widgets:");
        gui.separator();
        if (gui.button("Click me!")) { click_count += 1; }
        {
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            for ("Clicked: ") |c| { if (len < 60) { buf[len] = c; len += 1; } }
            len += itoa(@as(i32, @intCast(click_count)), buf[len..]);
            gui.label(buf[0..len]);
        }
        gui.separator();
        gui.checkbox("Enable feature", &checkbox_val);
        gui.separator();
        _ = gui.slider("Volume", &slider_val, 0.0, 1.0);
        {
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            for ("Value: ") |c| { if (len < 60) { buf[len] = c; len += 1; } }
            len += ftoa(slider_val, buf[len..]);
            gui.label(buf[0..len]);
        }
        gui.separator();
        if (gui.collapsible("Text Input", &collapsible_open)) {
            gui.label("  Type something:");
            _ = gui.textInput("Input", text_buf[0..]);
        }
        gui.separator();
        const combo_items = [_][]const u8{ "Option A", "Option B", "Option C", "Option D" };
        if (gui.comboBox("Combo", &combo_items, &combo_idx)) {}
        gui.separator();
        {
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            for ("Mouse: ") |c| { if (len < 60) { buf[len] = c; len += 1; } }
            len += itoa(mouse_x, buf[len..]);
            for (", ") |c| { if (len < 60) { buf[len] = c; len += 1; } }
            len += itoa(mouse_y, buf[len..]);
            gui.label(buf[0..len]);
        }
        gui.endWindow();

        // Extra widgets
        _ = gui.beginWindow("Extra", 446, 34, 446, 296, true);
        gui.label("Progress Bar:");
        gui_ext.drawProgressBar(&fb, 8, 224, 280, 20, 0.65, gui.style.bg, gui.style.accent, gui.style.border);
        gui.separator();
        gui.label("Radio Buttons:");
        var radio_sel: u32 = 0;
        gui_ext.drawRadioButton(&fb, 8, 256, 260, 20, 0, 0, &radio_sel, &gui.style, mouse_x, mouse_y, mouse_clicked);
        gui_ext.drawRadioButton(&fb, 8, 278, 260, 20, 0, 1, &radio_sel, &gui.style, mouse_x, mouse_y, mouse_clicked);
        gui_ext.drawRadioButton(&fb, 8, 300, 260, 20, 0, 2, &radio_sel, &gui.style, mouse_x, mouse_y, mouse_clicked);
        gui.endWindow();

        // Style switcher
        _ = gui.beginWindow("Style Switcher — 27 themes", 8, 336, W - 16, 296, true);
        gui.label("Pick a theme:");
        gui.separator();
        const per_col: usize = 3;
        var si: usize = 0;
        while (si < styles.len) {
            gui.beginHorizontal();
            var ci: usize = 0;
            while (ci < per_col and si < styles.len) {
                if (gui.button(styles[si].name)) {
                    style_idx = si;
                    gui.setStyle(styles[si].style);
                }
                si += 1;
                ci += 1;
            }
            gui.endHorizontal();
        }
        gui.separator();
        {
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            for ("Current: ") |c| { if (len < 60) { buf[len] = c; len += 1; } }
            var si2: usize = 0;
            while (si2 < styles[style_idx].name.len and len < 60) { buf[len] = styles[style_idx].name[si2]; len += 1; si2 += 1; }
            gui.labelColored(buf[0..len], gui.style.accent);
        }
        gui.separator();
        {
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            for ("  rounding=") |c| { if (len < 60) { buf[len] = c; len += 1; } }
            len += itoa(@as(i32, @intCast(gui.style.rounding)), buf[len..]);
            for ("  shadow=") |c| { if (len < 60) { buf[len] = c; len += 1; } }
            len += itoa(@as(i32, @intCast(gui.style.shadow)), buf[len..]);
            for ("  spacing=") |c| { if (len < 60) { buf[len] = c; len += 1; } }
            len += itoa(@as(i32, @intCast(gui.style.spacing)), buf[len..]);
            gui.label(buf[0..len]);
        }

        gui.endFrame();
        disp.present();
    }

    disp.close();
}
