const std = @import("std");
const sys = @import("sys.zig");
const gfx = @import("render.zig");
const display_mod = @import("display.zig");
const gui_mod = @import("gui.zig");

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

    var running = true;
    while (running) {
        var input = gui_mod.InputState{
            .mouse_x = 0, .mouse_y = 0,
            .mouse_down = false, .mouse_clicked = false, .mouse_released = false,
            .scroll = 0,
            .keys = [_]bool{false} ** gui_mod.MAX_KEY,
            .keys_pressed = [_]bool{false} ** gui_mod.MAX_KEY,
            .text_input = [_]u8{0} ** 16,
            .text_len = 0,
        };

        while (disp.pollEvent()) |ev| {
            if (ev == 0xFF) {
                running = false;
            } else if (ev == 0xFE) {
                // key release - track if needed
            } else if (ev == 0xFD) {
                // expose
            } else if (ev == 9) { // Escape
                running = false;
            } else {
                if (ev < gui_mod.MAX_KEY) {
                    input.keys[ev] = true;
                    input.keys_pressed[ev] = true;
                }
            }
        }

        gui.beginFrame(&fb, input);
        _ = gui.beginWindow("GUI Demo", 20, 20, 360, 500, true);

        gui.label("Welcome to dhjsjs GUI!");
        gui.separator();

        if (gui.button("Click me!")) {
            click_count += 1;
        }

        {
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            const cnt_str = "Clicked: ";
            for (cnt_str) |c| { if (len < 62) { buf[len] = c; len += 1; } }
            var tmp = click_count;
            var digits: [16]u8 = undefined;
            var dc: usize = 0;
            if (tmp == 0) { digits[dc] = '0'; dc += 1; }
            else { while (tmp > 0) { digits[dc] = @as(u8, @intCast('0' + @mod(tmp, 10))); tmp /= 10; dc += 1; } }
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
            var buf: [32]u8 = undefined;
            var len: usize = 0;
            const prefix = "Checkbox: ";
            for (prefix) |c| { if (len < 30) { buf[len] = c; len += 1; } }
            if (checkbox_val) {
                const t = "ON";
                for (t) |c| { if (len < 30) { buf[len] = c; len += 1; } }
            } else {
                const t = "OFF";
                for (t) |c| { if (len < 30) { buf[len] = c; len += 1; } }
            }
            gui.label(buf[0..len]);
        }

        gui.separator();
        _ = gui.slider("Volume", &slider_val, 0.0, 1.0);
        gui.separator();

        if (gui.collapsible("Advanced Settings", &collapsible_open)) {
            gui.label("  Text input below:");
            _ = gui.textInput("Input", text_buf[0..]);
            gui.label("  More settings here...");
        }

        gui.endWindow();

        _ = gui.beginWindow("Info", 420, 20, 340, 200, false);
        gui.label("Framebuffer size: 800x600");
        gui.label("GUI Demo - dhjsjs UI Toolkit");
        gui.label("Widgets supported:");
        gui.label("  - Button");
        gui.label("  - Label / Colored label");
        gui.label("  - Text input");
        gui.label("  - Checkbox");
        gui.label("  - Slider");
        gui.label("  - Collapsible section");
        gui.label("  - Separator");
        gui.label("  - Window (draggable, resizable)");
        gui.endWindow();

        gui.endFrame();
        disp.present();
    }

    disp.close();
}
