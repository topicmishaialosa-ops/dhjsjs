const sys = @import("sys.zig");
const gfx = @import("render.zig");
const gui_mod = @import("gui.zig");
const gui_ext = @import("gui_ext.zig");
const display_mod = @import("display.zig");
const player_mod = @import("player.zig");
const audio = @import("audio.zig");
const mouse_mod = @import("mouse.zig");

const W: u32 = 800;
const H: u32 = 600;

const MAX_TRACKS: usize = 64;
const MAX_PATH_LEN: usize = 256;

const CustomEditorState = struct {
    active_field: u32 = 0,
    mode: enum { fields, adjust } = .fields,
};

var editor_state: CustomEditorState = .{};

const Track = struct {
    path: [MAX_PATH_LEN]u8,
    path_len: usize,
    name: [64]u8,
    name_len: usize,
    format: audio.AudioFormat,
    duration: f32,
};

fn copyStr(dst: []u8, src: []const u8) usize {
    const len = @min(src.len, dst.len - 1);
    var i: usize = 0;
    while (i < len) : (i += 1) dst[i] = src[i];
    dst[len] = 0;
    return len;
}

fn extractName(path: []const u8) []const u8 {
    var last_slash: usize = 0;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        if (path[i] == '/') last_slash = i + 1;
    }
    var end = path.len;
    while (end > last_slash and path[end - 1] != '.') : (end -= 1) {}
    if (end <= last_slash) return path[last_slash..];
    return path[last_slash..end];
}

fn formatTime(seconds: f32, buf: []u8) usize {
    const total_secs = @as(i32, @intFromFloat(seconds));
    const mins = @divTrunc(total_secs, 60);
    const secs = @rem(total_secs, 60);
    var len: usize = 0;
    if (mins == 0) { buf[len] = '0'; len += 1; }
    else {
        var tmp = mins;
        var digits: [8]u8 = undefined;
        var dc: usize = 0;
        while (tmp > 0) { digits[dc] = @as(u8, @intCast('0' + @rem(tmp, 10))); tmp = @divTrunc(tmp, 10); dc += 1; }
        var di = dc;
        while (di > 0) { di -= 1; if (len < buf.len) { buf[len] = digits[di]; len += 1; } }
    }
    if (len < buf.len) { buf[len] = ':'; len += 1; }
    const s1 = @divTrunc(secs, 10);
    const s2 = @rem(secs, 10);
    if (len < buf.len) { buf[len] = @as(u8, @intCast('0' + s1)); len += 1; }
    if (len < buf.len) { buf[len] = @as(u8, @intCast('0' + s2)); len += 1; }
    return len;
}

pub fn main() void {
    var fb = gfx.Framebuffer.init(W, H) orelse {
        _ = sys.write(2, "Failed to allocate framebuffer\n", 31);
        sys.exit(1);
    };
    defer fb.deinit();

    var disp = display_mod.DisplayBackend.init(&fb);

    var gui = gui_mod.Gui.init(&fb);
    gui.setStyle(gui_mod.style_dark);

    var player = player_mod.Player.init();

    var tracks: [MAX_TRACKS]Track = undefined;
    var track_count: usize = 0;
    var current_track: i32 = -1;
    var tree = gui_ext.initTreeView();
    var tab_bar = gui_ext.initTabBar();
    gui_ext.addTab(&tab_bar, "Player");
    gui_ext.addTab(&tab_bar, "Library");
    gui_ext.addTab(&tab_bar, "Settings");
    var scroll = gui_ext.initScrollArea();
    var menu_bar = gui_ext.initMenuBar();
    gui_ext.addMenu(&menu_bar, "File");
    gui_ext.addMenu(&menu_bar, "View");
    gui_ext.addMenu(&menu_bar, "Help");

    var mouse = mouse_mod.State.init();
    var key_state: [gui_mod.MAX_KEY]bool = [_]bool{false} ** gui_mod.MAX_KEY;

    var volume: f32 = 0.8;
    var show_visualizer = true;
    var loop_mode = false;
    var shuffle_mode = false;

    var running = true;
    while (running) {
        mouse.beginFrame();

        while (disp.pollEvent()) |event| {
            switch (event) {
                .key_press => |kc| {
                    if (kc == 9) running = false;
                    if (kc < gui_mod.MAX_KEY) key_state[kc] = true;
                    if (kc == 65) {
                        if (player.state == .playing) player.pause() else _ = player.play();
                    }
                    if (kc == 22) {
                        if (current_track > 0) {
                            current_track -= 1;
                            player.stop();
                            player.unload();
                            if (player.loadFile(&tracks[@as(usize, @intCast(current_track))].path)) {
                                _ = player.play();
                            }
                        }
                    }
                    if (kc == 114) {
                        if (current_track < @as(i32, @intCast(track_count)) - 1) {
                            current_track += 1;
                            player.stop();
                            player.unload();
                            if (player.loadFile(&tracks[@as(usize, @intCast(current_track))].path)) {
                                _ = player.play();
                            }
                        }
                    }
                },
                .key_release => |kc| {
                    if (kc < gui_mod.MAX_KEY) key_state[kc] = false;
                },
                .mouse_move, .mouse_down, .mouse_up, .scroll => mouse.applyEvent(event),
                .close => running = false,
                .expose => {},
                .resize => |r| { _ = r; },
            }
        }
        mouse.endFrame();

        const input = gui_mod.InputState.fromMouse(
            mouse,
            key_state,
            [_]bool{false} ** gui_mod.MAX_KEY,
            [_]u8{0} ** 16,
            0,
        );

        if (player.state == .playing) {
            _ = player.update();
        }

        gui.beginFrame(&fb, input);

        gui_ext.drawMenuBar(&fb, 0, 0, W, 24, &menu_bar, &gui.style, mouse.x, mouse.y, mouse.primary_pressed);

        _ = gui_ext.drawTabBar(&fb, 0, 24, W, 28, &tab_bar, &gui.style, mouse.x, mouse.y, mouse.primary_pressed);

        if (tab_bar.active_tab == 0) {
            drawPlayerView(&fb, &gui, &player, &tracks, track_count, &current_track,
                &volume, &show_visualizer, &loop_mode, &shuffle_mode,
                mouse.x, mouse.y, mouse.primary_pressed);
        } else if (tab_bar.active_tab == 1) {
            drawLibraryView(&fb, &gui, &player, &tracks, &track_count, &current_track, &tree, &scroll,
                mouse.x, mouse.y, mouse.primary_pressed);
        } else {
            drawSettingsView(&fb, &gui, &volume, &show_visualizer, &loop_mode, &shuffle_mode,
                mouse.x, mouse.y, mouse.primary_pressed);
        }

        gui.endFrame();
        disp.present();
    }

    player.unload();
    disp.close();
}

fn drawPlayerView(fb: *gfx.Framebuffer, gui: *gui_mod.Gui, player: *player_mod.Player,
    tracks: []Track, track_count: usize, current_track: *i32,
    volume: *f32, show_viz: *bool, loop_mode: *bool, shuffle_mode: *bool,
    mx: i32, my: i32, clicked: bool) void {

    const panel_x: i32 = 10;
    const panel_y: i32 = 60;
    const panel_w: u32 = W - 20;
    const panel_h: u32 = H - 70;

    fillRect(fb, panel_x, panel_y, panel_w, panel_h, gui.style.panel_bg);
    drawRectBorder(fb, panel_x, panel_y, panel_w, panel_h, gui.style.border);

    const title_y = panel_y + 10;
    if (current_track.* >= 0 and @as(usize, @intCast(current_track.*)) < track_count) {
        const track = &tracks[@as(usize, @intCast(current_track.*))];
        drawText(fb, track.name[0..track.name_len], panel_x + 20, title_y, gui.style.text, 16);
    } else {
        drawText(fb, "No track loaded", panel_x + 20, title_y, gui.style.text_dim, 16);
    }

    const format_name = player.getFormatName();
    const state_name = player.getStateName();
    drawText(fb, format_name, panel_x + 20, title_y + 24, gui.style.accent, 8);
    drawText(fb, state_name, panel_x + 60, title_y + 24, gui.style.text_dim, 8);

    const sr_buf = "SampleRate: ";
    drawText(fb, sr_buf, panel_x + 120, title_y + 24, gui.style.text_dim, 8);
    var sr_num: [16]u8 = undefined;
    var sr_len: usize = 0;
    var sr_tmp = player.sample_rate;
    if (sr_tmp == 0) { sr_num[0] = '0'; sr_len = 1; }
    else {
        var digits: [16]u8 = undefined;
        var dc: usize = 0;
        while (sr_tmp > 0) { digits[dc] = @as(u8, @intCast('0' + @rem(sr_tmp, 10))); sr_tmp = @divTrunc(sr_tmp, 10); dc += 1; }
        var di = dc;
        while (di > 0) { di -= 1; if (sr_len < 16) { sr_num[sr_len] = digits[di]; sr_len += 1; } }
    }
    drawText(fb, sr_num[0..sr_len], panel_x + 190, title_y + 24, gui.style.text, 8);

    const progress_y = panel_y + 70;
    const progress_x = panel_x + 20;
    const progress_w = panel_w - 40;
    const progress_h: u32 = 12;

    gui_ext.drawProgressBar(fb, progress_x, progress_y, progress_w, progress_h,
        player.getPosition(), gui.style.slider_track, gui.style.accent, gui.style.border);

    const cur_time = player.getCurrentSeconds();
    var time_buf: [32]u8 = undefined;
    const cur_len = formatTime(cur_time, &time_buf);
    drawText(fb, time_buf[0..cur_len], progress_x, progress_y + 16, gui.style.text_dim, 8);

    const dur = player.getDurationSeconds();
    var dur_buf: [32]u8 = undefined;
    const dur_len = formatTime(dur, &dur_buf);
    drawText(fb, dur_buf[0..dur_len], progress_x + @as(i32, @intCast(progress_w)) - 40, progress_y + 16, gui.style.text_dim, 8);

    if (clicked and my >= progress_y and my < progress_y + @as(i32, @intCast(progress_h)) and
        mx >= progress_x and mx < progress_x + @as(i32, @intCast(progress_w))) {
        const pos = @as(f32, @floatFromInt(mx - progress_x)) / @as(f32, @floatFromInt(progress_w));
        player.seek(pos);
    }

    const btn_y = panel_y + 110;
    const btn_h: u32 = 36;
    const btn_w: u32 = 60;
    const center_x = panel_x + @divTrunc(@as(i32, @intCast(panel_w)), 2);

    const prev_x = center_x - @as(i32, @intCast(btn_w * 2 + 20));
    const play_x = center_x - @as(i32, @intCast(@divTrunc(btn_w, 2)));
    const next_x = center_x + @as(i32, @intCast(btn_w + 20));

    const prev_hover = mx >= prev_x and mx < prev_x + @as(i32, @intCast(btn_w)) and
        my >= btn_y and my < btn_y + @as(i32, @intCast(btn_h));
    if (prev_hover) fillRect(fb, prev_x, btn_y, btn_w, btn_h, gui.style.button_hover)
    else fillRect(fb, prev_x, btn_y, btn_w, btn_h, gui.style.button_bg);
    drawRectBorder(fb, prev_x, btn_y, btn_w, btn_h, gui.style.border);
    drawText(fb, "<<", prev_x + 16, btn_y + 10, gui.style.text, 16);
    if (prev_hover and clicked and current_track.* > 0) {
        current_track.* -= 1;
        player.stop();
        player.unload();
        if (player.loadFile(&tracks[@as(usize, @intCast(current_track.*))].path)) {
            _ = player.play();
        }
    }

    const play_hover = mx >= play_x and mx < play_x + @as(i32, @intCast(btn_w)) and
        my >= btn_y and my < btn_y + @as(i32, @intCast(btn_h));
    if (play_hover) fillRect(fb, play_x, btn_y, btn_w, btn_h, gui.style.button_hover)
    else fillRect(fb, play_x, btn_y, btn_w, btn_h, gui.style.button_bg);
    drawRectBorder(fb, play_x, btn_y, btn_w, btn_h, gui.style.border);
    const play_label = if (player.state == .playing) "||" else ">";
    drawText(fb, play_label, play_x + 16, btn_y + 10, gui.style.text, 16);
    if (play_hover and clicked) {
        if (player.state == .playing) player.pause() else _ = player.play();
    }

    const next_hover = mx >= next_x and mx < next_x + @as(i32, @intCast(btn_w)) and
        my >= btn_y and my < btn_y + @as(i32, @intCast(btn_h));
    if (next_hover) fillRect(fb, next_x, btn_y, btn_w, btn_h, gui.style.button_hover)
    else fillRect(fb, next_x, btn_y, btn_w, btn_h, gui.style.button_bg);
    drawRectBorder(fb, next_x, btn_y, btn_w, btn_h, gui.style.border);
    drawText(fb, ">>", next_x + 16, btn_y + 10, gui.style.text, 16);
    if (next_hover and clicked and current_track.* < @as(i32, @intCast(track_count)) - 1) {
        current_track.* += 1;
        player.stop();
        player.unload();
        if (player.loadFile(&tracks[@as(usize, @intCast(current_track.*))].path)) {
            _ = player.play();
        }
    }

    const vol_x = panel_x + 20;
    const vol_y = btn_y + 50;
    const vol_w: u32 = 200;
    drawText(fb, "Volume:", vol_x, vol_y, gui.style.text_dim, 8);
    gui_ext.drawProgressBar(fb, vol_x + 60, vol_y, vol_w, 12, volume.*,
        gui.style.slider_track, gui.style.slider_thumb, gui.style.border);
    if (clicked and my >= vol_y and my < vol_y + 12 and
        mx >= vol_x + 60 and mx < vol_x + 60 + @as(i32, @intCast(vol_w))) {
        volume.* = @as(f32, @floatFromInt(mx - (vol_x + 60))) / @as(f32, @floatFromInt(vol_w));
        player.setVolume(volume.*);
    }

    const loop_x = vol_x + @as(i32, @intCast(vol_w)) + 100;
    const loop_hover = mx >= loop_x and mx < loop_x + 60 and my >= vol_y and my < vol_y + 20;
    if (loop_hover) fillRect(fb, loop_x, vol_y, 60, 20, gui.style.button_hover)
    else fillRect(fb, loop_x, vol_y, 60, 20, gui.style.button_bg);
    drawRectBorder(fb, loop_x, vol_y, 60, 20, gui.style.border);
    const loop_label = if (loop_mode.*) "LOOP" else "loop";
    drawText(fb, loop_label, loop_x + 8, vol_y + 4, if (loop_mode.*) gui.style.accent else gui.style.text_dim, 8);
    if (loop_hover and clicked) {
        loop_mode.* = !loop_mode.*;
        player.loop_enabled = loop_mode.*;
    }

    const viz_x = panel_x + 20;
    const viz_y = vol_y + 40;
    const viz_w = panel_w - 40;
    const viz_h: u32 = 120;

    if (show_viz.*) {
        fillRect(fb, viz_x, viz_y, viz_w, viz_h, gui.style.bg);
        drawRectBorder(fb, viz_x, viz_y, viz_w, viz_h, gui.style.border);

        if (player.state == .playing) {
            const bars: u32 = 64;
            const bar_w = viz_w / bars;
            var bi: u32 = 0;
            while (bi < bars) : (bi += 1) {
                const t = @as(f32, @floatFromInt(bi)) / @as(f32, @floatFromInt(bars));
                const height = @as(f32, @floatFromInt(viz_h)) * (0.3 + 0.7 * simpleSin(t * 6.28 * 3.0 + @as(f32, @floatFromInt(bi)) * 0.5));
                const bar_h: u32 = @intFromFloat(height);
                const bar_x = viz_x + @as(i32, @intCast(bi * bar_w));
                const bar_y2 = viz_y + @as(i32, @intCast(viz_h)) - @as(i32, @intCast(bar_h));
                const color = @as(u32, @intFromFloat(@as(f64, t) * 200.0));
                fillRect(fb, bar_x + 1, bar_y2, @max(1, bar_w - 2), bar_h,
                    (0xFF << 24) | (color << 16) | (0x80 << 8) | 0x40);
            }
        } else {
            drawText(fb, "Visualizer", viz_x + 10, viz_y + 50, gui.style.text_dim, 8);
        }
    }

    const viz_toggle_x = panel_x + @as(i32, @intCast(panel_w)) - 80;
    const viz_toggle_hover = mx >= viz_toggle_x and mx < viz_toggle_x + 70 and
        my >= viz_y - 20 and my < viz_y;
    if (viz_toggle_hover) fillRect(fb, viz_toggle_x, viz_y - 20, 70, 18, gui.style.button_hover)
    else fillRect(fb, viz_toggle_x, viz_y - 20, 70, 18, gui.style.button_bg);
    drawRectBorder(fb, viz_toggle_x, viz_y - 20, 70, 18, gui.style.border);
    const viz_label = if (show_viz.*) "Hide Viz" else "Show Viz";
    drawText(fb, viz_label, viz_toggle_x + 4, viz_y - 18, gui.style.text, 8);
    if (viz_toggle_hover and clicked) show_viz.* = !show_viz.*;

    _ = shuffle_mode;
}

fn drawLibraryView(fb: *gfx.Framebuffer, gui: *gui_mod.Gui, player: *player_mod.Player,
    tracks: []Track, track_count: *usize, current_track: *i32, tree: *gui_ext.TreeView, scroll: *gui_ext.ScrollArea,
    mx: i32, my: i32, clicked: bool) void {

    const panel_x: i32 = 10;
    const panel_y: i32 = 60;
    const panel_w: u32 = W - 20;
    const panel_h: u32 = H - 70;

    fillRect(fb, panel_x, panel_y, panel_w, panel_h, gui.style.panel_bg);
    drawRectBorder(fb, panel_x, panel_y, panel_w, panel_h, gui.style.border);

    drawText(fb, "Track Library", panel_x + 10, panel_y + 8, gui.style.text, 16);

    const list_x = panel_x + 10;
    const list_y = panel_y + 34;
    const list_w = panel_w - 20;
    const list_h = panel_h - 44;

    scroll.content_h = @as(u32, @intCast(tree.node_count)) * 24 + 10;
    gui_ext.drawScrollArea(fb, list_x, list_y, list_w, list_h, scroll, &gui.style, mx, my, 0);

    fillRect(fb, list_x, list_y, list_w, list_h, gui.style.bg);
    drawRectBorder(fb, list_x, list_y, list_w, list_h, gui.style.border);

    var row_y = list_y - scroll.scroll_y;
    var i: usize = 0;
    while (i < tree.node_count) : (i += 1) {
        if (row_y + 22 < list_y) { row_y += 22; continue; }
        if (row_y > list_y + @as(i32, @intCast(list_h))) break;

        const node = &tree.nodes[i];
        const is_hovered = mx >= list_x and mx < list_x + @as(i32, @intCast(list_w)) and
            my >= row_y and my < row_y + 22;

        if (is_hovered) {
            fillRect(fb, list_x + 1, row_y, list_w - 2, 22, gui.style.button_hover);
        }
        if (@as(i32, @intCast(i)) == current_track.*) {
            fillRect(fb, list_x + 1, row_y, list_w - 2, 22, gui.style.accent);
        }

        const label = node.label[0..node.label_len];
        drawText(fb, label, list_x + 8, row_y + 4, if (is_hovered or @as(i32, @intCast(i)) == current_track.*) gui.style.text else gui.style.text_dim, 8);

        if (is_hovered and clicked) {
            current_track.* = @as(i32, @intCast(i));
            player.stop();
            player.unload();
            if (i < track_count.*) {
                if (player.loadFile(&tracks[i].path)) {
                    _ = player.play();
                }
            }
        }

        row_y += 22;
    }
}

fn adjustField(s: *gui_mod.Style, idx: u32, comp: u32, delta: i32) void {
    var c: u32 = 0;
    switch (idx) {
        0 => c = s.bg, 1 => c = s.panel_bg, 2 => c = s.accent,
        3 => c = s.text, 4 => c = s.button_bg, 5 => c = s.border,
        6 => c = s.button_hover, 7 => c = s.text_dim,
        else => return,
    }
    var r: u32 = (c >> 16) & 0xFF;
    var g: u32 = (c >> 8) & 0xFF;
    var b: u32 = c & 0xFF;
    if (comp == 0) r = @min(255, @max(0, @as(i32, @intCast(r)) + delta));
    if (comp == 1) g = @min(255, @max(0, @as(i32, @intCast(g)) + delta));
    if (comp == 2) b = @min(255, @max(0, @as(i32, @intCast(b)) + delta));
    c = (0xFF << 24) | (r << 16) | (g << 8) | b;
    switch (idx) {
        0 => s.bg = c, 1 => s.panel_bg = c, 2 => s.accent = c,
        3 => s.text = c, 4 => s.button_bg = c, 5 => s.border = c,
        6 => s.button_hover = c, 7 => s.text_dim = c,
        else => {},
    }
}

fn drawBtn(fb: *gfx.Framebuffer, bx: i32, by: i32, bw: u32, bh: u32, label: []const u8, style: *const gui_mod.Style, mx: i32, my: i32, clicked: bool) bool {
    const hvr = mx >= bx and mx < bx + @as(i32, @intCast(bw)) and my >= by and my < by + @as(i32, @intCast(bh));
    if (hvr) fillRect(fb, bx, by, bw, bh, style.button_hover)
    else fillRect(fb, bx, by, bw, bh, style.button_bg);
    drawRectBorder(fb, bx, by, bw, bh, style.border);
    const tw = @as(u32, @intCast(label.len)) * 8;
    drawText(fb, label, bx + @divTrunc(@as(i32, @intCast(bw)) - @as(i32, @intCast(tw)), 2), by + 3, style.text, 8);
    return hvr and clicked;
}

fn drawSettingsView(fb: *gfx.Framebuffer, gui: *gui_mod.Gui,
    volume: *f32, show_viz: *bool, loop_mode: *bool, shuffle_mode: *bool,
    mx: i32, my: i32, clicked: bool) void {


    const panel_x: i32 = 10;
    const panel_y: i32 = 60;
    const panel_w: u32 = W - 20;
    const panel_h: u32 = H - 70;

    const r = gui.style.rounding;
    fillRoundedRect(fb, panel_x, panel_y, panel_w, panel_h, r, gui.style.panel_bg);
    drawRectBorder(fb, panel_x, panel_y, panel_w, panel_h, gui.style.border);

    drawText(fb, "Settings", panel_x + 10, panel_y + 8, gui.style.text, 16);

    var cy = panel_y + 40;

    drawText(fb, "Master Volume:", panel_x + 20, cy, gui.style.text, 8);
    gui_ext.drawProgressBar(fb, panel_x + 140, cy, 200, 12, volume.*,
        gui.style.slider_track, gui.style.slider_thumb, gui.style.border);
    if (clicked and my >= cy and my < cy + 12 and
        mx >= panel_x + 140 and mx < panel_x + 340) {
        volume.* = @as(f32, @floatFromInt(mx - (panel_x + 140))) / 200.0;
    }
    cy += 30;

    const toggleItems = [_]struct { label: []const u8, value: *bool }{
        .{ .label = "Show Visualizer", .value = show_viz },
        .{ .label = "Loop Playback", .value = loop_mode },
        .{ .label = "Shuffle Mode", .value = shuffle_mode },
    };

    for (toggleItems) |item| {
        const is_hovered = mx >= panel_x + 20 and mx < panel_x + 200 and
            my >= cy and my < cy + 20;

        if (is_hovered) fillRect(fb, panel_x + 20, cy, 180, 20, gui.style.button_hover)
        else fillRect(fb, panel_x + 20, cy, 180, 20, gui.style.button_bg);
        drawRectBorder(fb, panel_x + 20, cy, 180, 20, gui.style.border);

        drawText(fb, item.label, panel_x + 28, cy + 4, gui.style.text, 8);

        const check_x = panel_x + 160;
        fillRoundedRect(fb, check_x, cy + 2, 16, 16, 3, gui.style.check_bg);
        drawRectBorder(fb, check_x, cy + 2, 16, 16, gui.style.border);
        if (item.value.*) {
            fillRoundedRect(fb, check_x + 3, cy + 5, 10, 10, 2, gui.style.check_mark);
        }

        if (is_hovered and clicked) {
            item.value.* = !item.value.*;
        }

        cy += 28;
    }

    cy += 10;
    drawText(fb, "Theme Presets:", panel_x + 20, cy, gui.style.text, 8);

    const themes = [_]*const gui_mod.Style{
        &gui_mod.style_dark, &gui_mod.style_light, &gui_mod.style_dracula,
        &gui_mod.style_nord, &gui_mod.style_solarized_dark, &gui_mod.style_solarized_light,
        &gui_mod.style_monokai, &gui_mod.style_one_dark, &gui_mod.style_github_light,
        &gui_mod.style_gruvbox_dark, &gui_mod.style_gruvbox_light, &gui_mod.style_catppuccin,
        &gui_mod.style_tokyo_night, &gui_mod.style_ayu_dark, &gui_mod.style_ayu_light,
        &gui_mod.style_material_dark, &gui_mod.style_material_light, &gui_mod.style_high_contrast,
        &gui_mod.style_retro_terminal, &gui_mod.style_forest, &gui_mod.style_ocean,
        &gui_mod.style_sunset, &gui_mod.style_candy, &gui_mod.style_monochrome,
        &gui_mod.style_rose_pine, &gui_mod.style_everforest, &gui_mod.style_nord_light,
    };
    const theme_names = [_][]const u8{
        "Dark", "Light", "Dracula", "Nord", "Solarized Dk", "Solarized Lt",
        "Monokai", "One Dark", "GitHub Lt", "Gruvbox Dk", "Gruvbox Lt", "Catppuccin",
        "Tokyo Night", "Ayu Dark", "Ayu Light",
        "Material Dk", "Material Lt", "High Contrast",
        "Retro Term", "Forest", "Ocean",
        "Sunset", "Candy", "Monochrome",
        "Rose Pine", "Everforest", "Nord Light",
    };

    cy += 16;
    var ti: usize = 0;
    var tx = panel_x + 20;
    while (ti < themes.len) : (ti += 1) {
        const tw: u32 = 82;
        const th: u32 = 18;
        const thovered = mx >= tx and mx < tx + @as(i32, @intCast(tw)) and
            my >= cy and my < cy + @as(i32, @intCast(th));
        const tbg = if (thovered) themes[ti].button_hover else themes[ti].button_bg;
        fillRoundedRect(fb, tx, cy, tw, th, 3, tbg);
        drawRectBorder(fb, tx, cy, tw, th, themes[ti].border);

        const preview_colors = [_]u32{ themes[ti].accent, themes[ti].slider_thumb, themes[ti].check_mark };
        var pi: usize = 0;
        var px = tx + tw - 20;
        while (pi < 3) : (pi += 1) {
            fillRect(fb, px, cy + 3, 5, th - 6, preview_colors[pi]);
            px += 6;
        }

        drawText(fb, theme_names[ti], tx + 3, cy + 3, themes[ti].text, 8);

        if (thovered and clicked) {
            gui.setStyle(themes[ti].*);
        }

        tx += @as(i32, @intCast(tw)) + 6;
        if (tx + @as(i32, @intCast(tw)) > panel_x + @as(i32, @intCast(panel_w))) {
            tx = panel_x + 20;
            cy += @as(i32, @intCast(th)) + 4;
        }
    }

    cy += 30;
    drawText(fb, "Custom Theme:", panel_x + 20, cy, gui.style.text, 8);
    cy += 18;

    const field_names = [_][]const u8{ "bg", "panel", "accent", "text", "btn_bg", "border", "btn_hov", "text_dim" };
    const field_tags = [_]u32{ 0, 1, 2, 3, 4, 5, 6, 7 };
    const fw: u32 = 44;
    const fh: u32 = 16;
    var fi: usize = 0;
    var fx = panel_x + 20;
    while (fi < field_names.len) : (fi += 1) {
        const fcolor = switch (field_tags[fi]) {
            0 => gui.style.bg,
            1 => gui.style.panel_bg,
            2 => gui.style.accent,
            3 => gui.style.text,
            4 => gui.style.button_bg,
            5 => gui.style.border,
            6 => gui.style.button_hover,
            7 => gui.style.text_dim,
            else => 0xFF000000,
        };
        const fhvr = mx >= fx and mx < fx + @as(i32, @intCast(fw)) and
            my >= cy and my < cy + @as(i32, @intCast(fh));

        if (fi == editor_state.active_field) {
            drawRectBorder(fb, fx - 1, cy - 2, fw + 2, fh + 4, gui.style.accent);
        }
        if (fhvr) fillRect(fb, fx, cy, fw, fh, gui.style.button_hover);
        fillRect(fb, fx + 2, cy + 2, fw - 4, fh - 4, fcolor);
        drawRectBorder(fb, fx, cy, fw, fh, gui.style.border);
        drawText(fb, field_names[fi], fx + 2, cy + fh - 9, gui.style.text_dim, 6);

        if (fhvr and clicked) {
            editor_state.active_field = @as(u32, @intCast(fi));
        }

        fx += @as(i32, @intCast(fw)) + 3;
        if (fx + @as(i32, @intCast(fw)) > panel_x + @as(i32, @intCast(panel_w))) {
            fx = panel_x + 20;
            cy += @as(i32, @intCast(fh)) + 4;
        }
    }

    cy += @as(i32, @intCast(fh)) + 14;

    var cc: u32 = 0;
    switch (field_tags[editor_state.active_field]) {
        0 => cc = gui.style.bg,
        1 => cc = gui.style.panel_bg,
        2 => cc = gui.style.accent,
        3 => cc = gui.style.text,
        4 => cc = gui.style.button_bg,
        5 => cc = gui.style.border,
        6 => cc = gui.style.button_hover,
        7 => cc = gui.style.text_dim,
        else => cc = 0xFF000000,
    }

    const cr: u32 = (cc >> 16) & 0xFF;
    const cg: u32 = (cc >> 8) & 0xFF;
    const cb: u32 = cc & 0xFF;

    const adjv: i32 = 16;

    drawText(fb, "R:", panel_x + 20, cy, gui.style.text, 8);
    const dec = cy;
    if (drawBtn(fb, panel_x + 34, dec, 18, 16, "-", &gui.style, mx, my, clicked)) {
        adjustField(&gui.style, field_tags[editor_state.active_field], 0, -adjv);
    }
    if (drawBtn(fb, panel_x + 54, dec, 18, 16, "+", &gui.style, mx, my, clicked)) {
        adjustField(&gui.style, field_tags[editor_state.active_field], 0, adjv);
    }
    drawText(fb, "G:", panel_x + 80, cy, gui.style.text, 8);
    if (drawBtn(fb, panel_x + 96, dec, 18, 16, "-", &gui.style, mx, my, clicked)) {
        adjustField(&gui.style, field_tags[editor_state.active_field], 1, -adjv);
    }
    if (drawBtn(fb, panel_x + 116, dec, 18, 16, "+", &gui.style, mx, my, clicked)) {
        adjustField(&gui.style, field_tags[editor_state.active_field], 1, adjv);
    }
    drawText(fb, "B:", panel_x + 142, cy, gui.style.text, 8);
    if (drawBtn(fb, panel_x + 158, dec, 18, 16, "-", &gui.style, mx, my, clicked)) {
        adjustField(&gui.style, field_tags[editor_state.active_field], 2, -adjv);
    }
    if (drawBtn(fb, panel_x + 178, dec, 18, 16, "+", &gui.style, mx, my, clicked)) {
        adjustField(&gui.style, field_tags[editor_state.active_field], 2, adjv);
    }

    const preview_color = (0xFF << 24) | (cr << 16) | (cg << 8) | cb;
    fillRect(fb, panel_x + 220, dec, 40, 16, preview_color);
    drawRectBorder(fb, panel_x + 220, dec, 40, 16, gui.style.border);

    cy += 22;

    drawText(fb, "Rounding:", panel_x + 20, cy, gui.style.text, 8);
    if (drawBtn(fb, panel_x + 74, cy, 18, 16, "-", &gui.style, mx, my, clicked)) {
        gui.style.rounding = if (gui.style.rounding > 4) gui.style.rounding - 4 else 0;
    }
    if (drawBtn(fb, panel_x + 94, cy, 18, 16, "+", &gui.style, mx, my, clicked)) {
        gui.style.rounding = @min(32, gui.style.rounding + 4);
    }

    drawText(fb, "Shadow:", panel_x + 140, cy, gui.style.text, 8);
    if (drawBtn(fb, panel_x + 194, cy, 18, 16, "-", &gui.style, mx, my, clicked)) {
        gui.style.shadow = if (gui.style.shadow > 2) gui.style.shadow - 2 else 0;
    }
    if (drawBtn(fb, panel_x + 214, cy, 18, 16, "+", &gui.style, mx, my, clicked)) {
        gui.style.shadow = @min(32, gui.style.shadow + 2);
    }

    cy += 22;
    drawText(fb, "Supported Formats:", panel_x + 20, cy, gui.style.text, 8);
    var fy = cy + 16;
    drawText(fb, "WAV  - Uncompressed PCM audio", panel_x + 30, fy, gui.style.text_dim, 8);
    fy += 14;
    drawText(fb, "MP3  - MPEG Layer 3 audio", panel_x + 30, fy, gui.style.text_dim, 8);
    fy += 14;
    drawText(fb, "OGG  - Vorbis audio", panel_x + 30, fy, gui.style.text_dim, 8);
    fy += 14;
    drawText(fb, "FLAC - Free Lossless Audio", panel_x + 30, fy, gui.style.text_dim, 8);
    fy += 14;
    drawText(fb, "AIFF - Audio Interchange File", panel_x + 30, fy, gui.style.text_dim, 8);
}

fn simpleSin(x: f32) f32 {
    var v = x;
    while (v > 3.14159) v -= 6.28318;
    while (v < -3.14159) v += 6.28318;
    const x2 = v * v;
    const x3 = v * x2;
    const x5 = x3 * x2;
    const x7 = x5 * x2;
    return v - x3 / 6.0 + x5 / 120.0 - x7 / 5040.0;
}

fn fillRect(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, color: u32) void {
    const x1: u32 = if (x < 0) 0 else @intCast(x);
    const y1: u32 = if (y < 0) 0 else @intCast(y);
    const x2: u32 = @min(x1 + w, fb.width);
    const y2: u32 = @min(y1 + h, fb.height);
    var yi = y1;
    while (yi < y2) : (yi += 1) {
        const row = @as(usize, yi) * fb.stride;
        var xi = x1;
        while (xi < x2) : (xi += 1) {
            fb.pixels[row + xi] = color;
        }
    }
}

fn fillRoundedRect(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, r: u8, color: u32) void {
    if (r == 0 or w < @as(u32, @intCast(r * 2 + 2)) or h < @as(u32, @intCast(r * 2 + 2))) {
        fillRect(fb, x, y, w, h, color);
        return;
    }
    const rr = @as(u32, r);
    const x1: u32 = if (x < 0) 0 else @intCast(x);
    const y1: u32 = if (y < 0) 0 else @intCast(y);
    const x2_: u32 = @min(x1 + w, fb.width);
    const y2_: u32 = @min(y1 + h, fb.height);
    var yi = y1;
    while (yi < y2_) : (yi += 1) {
        const row = @as(usize, yi) * fb.stride;
        const local_y = yi - y1;
        var xi = x1;
        while (xi < x2_) : (xi += 1) {
            const local_x = xi - x1;
            var in_corner = false;
            if (local_x < rr and local_y < rr) {
                const dx = rr - local_x - 1;
                const dy = rr - local_y - 1;
                if (dx * dx + dy * dy > rr * rr) in_corner = true;
            } else if (local_x >= w - rr and local_y < rr) {
                const dx = local_x - (w - rr) + 1;
                const dy = rr - local_y - 1;
                if (dx * dx + dy * dy > rr * rr) in_corner = true;
            } else if (local_x < rr and local_y >= h - rr) {
                const dx = rr - local_x - 1;
                const dy = local_y - (h - rr) + 1;
                if (dx * dx + dy * dy > rr * rr) in_corner = true;
            } else if (local_x >= w - rr and local_y >= h - rr) {
                const dx = local_x - (w - rr) + 1;
                const dy = local_y - (h - rr) + 1;
                if (dx * dx + dy * dy > rr * rr) in_corner = true;
            }
            if (!in_corner) fb.pixels[row + xi] = color;
        }
    }
}

fn drawRectBorder(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, color: u32) void {
    if (w < 2 or h < 2) { fillRect(fb, x, y, w, h, color); return; }
    fillRect(fb, x, y, w, 1, color);
    fillRect(fb, x, y + @as(i32, @intCast(h)) - 1, w, 1, color);
    fillRect(fb, x, y, 1, h, color);
    fillRect(fb, x + @as(i32, @intCast(w)) - 1, y, 1, h, color);
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
