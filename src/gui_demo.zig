const std = @import("std");
const sys = @import("sys.zig");
const gfx = @import("render.zig");
const display_mod = @import("display.zig");
const gui_mod = @import("gui.zig");

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
    const W: u32 = 800;
    const H: u32 = 600;

    var fb = gfx.Framebuffer.init(W, H) orelse {
        _ = sys.write(2, "Failed to allocate framebuffer\n", 31);
        sys.exit(1);
    };
    defer fb.deinit();

    var disp = display_mod.DisplayBackend.init(&fb);

    var gui = gui_mod.Gui.init(&fb);

    var checkbox_val = false;
    var slider_val: f32 = 0.5;
    var collapsible_open = true;
    var text_buf: [256]u8 = [_]u8{0} ** 256;
    text_buf[0] = 'h'; text_buf[1] = 'e'; text_buf[2] = 'l'; text_buf[3] = 'l'; text_buf[4] = 'o';
    var click_count: u32 = 0;
    var combo_idx: usize = 0;

    const styles = allStyles();
    var style_idx: usize = 0;
    var mouse_x: i32 = 0;
    var mouse_y: i32 = 0;
    var mouse_down = false;
    var mouse_clicked = false;
    var mouse_released = false;

    var key_state: [gui_mod.MAX_KEY]bool = [_]bool{false} ** gui_mod.MAX_KEY;

    var running = true;
    while (running) {
        mouse_clicked = false;
        mouse_released = false;

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
                .mouse_down => |m| {
                    mouse_x = m.x; mouse_y = m.y;
                    mouse_down = true;
                    mouse_clicked = true;
                },
                .mouse_up => |m| {
                    mouse_x = m.x; mouse_y = m.y;
                    mouse_down = false;
                    mouse_released = true;
                },
                .close => running = false,
                .expose => {},
                .resize => |r| { _ = r; },
            }
        }

        const input = gui_mod.InputState{
            .mouse_x = mouse_x,
            .mouse_y = mouse_y,
            .mouse_down = mouse_down,
            .mouse_clicked = mouse_clicked,
            .mouse_released = mouse_released,
            .scroll = 0,
            .keys = key_state,
            .keys_pressed = [_]bool{false} ** gui_mod.MAX_KEY,
            .text_input = [_]u8{0} ** 16,
            .text_len = 0,
        };

        gui.beginFrame(&fb, input);
        _ = gui.beginWindow("Widgets Demo", 10, 10, 350, 540, true);

        gui.label("Click button (mouse works now!):");
        if (gui.button("Click me!")) {
            click_count += 1;
        }

        {
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            const cnt_str = "Clicked: ";
            for (cnt_str) |c| { if (len < 62) { buf[len] = c; len += 1; } }
            var tmp: i32 = @as(i32, @intCast(click_count));
            var digits: [16]u8 = undefined;
            var dc: usize = 0;
            if (tmp == 0) { digits[dc] = '0'; dc += 1; }
            else { while (tmp > 0) { digits[dc] = @as(u8, @intCast('0' + @rem(tmp, 10))); tmp = @divTrunc(tmp, 10); dc += 1; } }
            var di2: usize = dc;
            while (di2 > 0) {
                di2 -= 1;
                if (len < 62) { buf[len] = digits[di2]; len += 1; }
            }
            gui.label(buf[0..len]);
        }

        gui.separator();
        gui.checkbox("Enable feature", &checkbox_val);

        {
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            const mx: i32 = mouse_x;
            const my: i32 = mouse_y;
            const ms = "Mouse: ";
            for (ms) |c| { if (len < 60) { buf[len] = c; len += 1; } }
            var mxt = mx;
            var mdig: [16]u8 = undefined;
            var mdc: usize = 0;
            if (mxt == 0) { mdig[mdc] = '0'; mdc += 1; }
            else { while (mxt > 0) { mdig[mdc] = @as(u8, @intCast('0' + @rem(mxt, 10))); mxt = @divTrunc(mxt, 10); mdc += 1; } }
            var mdi: usize = mdc;
            while (mdi > 0) { mdi -= 1; if (len < 60) { buf[len] = mdig[mdi]; len += 1; } }
            const comma = ", ";
            for (comma) |c| { if (len < 60) { buf[len] = c; len += 1; } }
            var myt = my;
            mdc = 0;
            if (myt == 0) { mdig[mdc] = '0'; mdc += 1; }
            else { while (myt > 0) { mdig[mdc] = @as(u8, @intCast('0' + @rem(myt, 10))); myt = @divTrunc(myt, 10); mdc += 1; } }
            mdi = mdc;
            while (mdi > 0) { mdi -= 1; if (len < 60) { buf[len] = mdig[mdi]; len += 1; } }
            gui.label(buf[0..len]);
        }

        gui.separator();
        _ = gui.slider("Volume", &slider_val, 0.0, 1.0);
        gui.separator();

        if (gui.collapsible("Text Input", &collapsible_open)) {
            gui.label("  Type something:");
            _ = gui.textInput("Input", text_buf[0..]);
        }

        gui.separator();
        const combo_items = [_][]const u8{ "Option A", "Option B", "Option C", "Option D" };
        if (gui.comboBox("Combo", combo_items[0..], &combo_idx)) {
            var buf2: [64]u8 = undefined;
            var len2: usize = 0;
            const sel = "Selected: ";
            for (sel) |c| { if (len2 < 60) { buf2[len2] = c; len2 += 1; } }
            for (combo_items[combo_idx]) |c| { if (len2 < 60) { buf2[len2] = c; len2 += 1; } }
            gui.label(buf2[0..len2]);
        }

        gui.endWindow();

        _ = gui.beginWindow("Style Switcher", 380, 10, 410, 540, true);
        gui.label("Pick a theme:");
        gui.separator();

        const per_col: usize = 2;
        var si: usize = 0;
        while (si < styles.len) {
            gui.beginHorizontal();
            var ci: usize = 0;
            while (ci < per_col and si < styles.len) : (ci += 1) {
                const s = styles[si];
                if (gui.button(s.name)) {
                    style_idx = si;
                    gui.setStyle(s.style);
                }
                si += 1;
            }
            gui.endHorizontal();
        }

        gui.separator();
        {
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            const cur = "Current: ";
            for (cur) |c| { if (len < 60) { buf[len] = c; len += 1; } }
            for (styles[style_idx].name) |c| { if (len < 60) { buf[len] = c; len += 1; } }
            gui.label(buf[0..len]);
        }
        gui.labelColored("Custom: define your own Style{}", gui.style.accent);
        gui.endWindow();

        gui.endFrame();
        disp.present();
    }

    disp.close();
}
