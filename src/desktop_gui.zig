const sys = @import("sys.zig");
const gfx = @import("render.zig");
const gui_mod = @import("gui.zig");
const gui_ext = @import("gui_ext.zig");
const display_mod = @import("display.zig");
const mouse_mod = @import("mouse.zig");

const W: u32 = 1280;
const H: u32 = 800;

const StyleInfo = struct { name: []const u8, style: gui_mod.Style };
const TabInfo = struct { name: []const u8, color: u32 };
const Metric = struct { name: []const u8, value: i32, total: i32 };

fn allStyles() []const StyleInfo {
    return &[_]StyleInfo{
        .{ .name = "Modern Dark", .style = gui_mod.style_modern_dark },
        .{ .name = "Modern Light", .style = gui_mod.style_modern_light },
        .{ .name = "Dark", .style = gui_mod.style_dark },
        .{ .name = "Light", .style = gui_mod.style_light },
        .{ .name = "One Dark", .style = gui_mod.style_one_dark },
        .{ .name = "GitHub Light", .style = gui_mod.style_github_light },
        .{ .name = "Tokyo Night", .style = gui_mod.style_tokyo_night },
        .{ .name = "Nord", .style = gui_mod.style_nord },
        .{ .name = "Diamond", .style = gui_mod.style_diamond },
    };
}

fn copyText(dst: []u8, src: []const u8) usize {
    var i: usize = 0;
    while (i < src.len and i + 1 < dst.len) : (i += 1) dst[i] = src[i];
    if (i < dst.len) dst[i] = 0;
    return i;
}

fn appendText(dst: []u8, start: usize, src: []const u8) usize {
    var i = start;
    var j: usize = 0;
    while (j < src.len and i + 1 < dst.len) : (j += 1) {
        dst[i] = src[j];
        i += 1;
    }
    if (i < dst.len) dst[i] = 0;
    return i;
}

fn appendInt(dst: []u8, start: usize, value: i32) usize {
    var buf: [24]u8 = undefined;
    var len: usize = 0;
    var v = value;
    if (v < 0) {
        if (start < dst.len) {
            dst[start] = '-';
        }
        return appendInt(dst, start + 1, -v);
    }
    if (v == 0) {
        if (start < dst.len) dst[start] = '0';
        return start + 1;
    }
    while (v > 0) : (v = @divTrunc(v, 10)) {
        buf[len] = @as(u8, @intCast('0' + @rem(v, 10)));
        len += 1;
    }
    var i = len;
    var pos = start;
    while (i > 0 and pos + 1 < dst.len) : (i -= 1) {
        dst[pos] = buf[i - 1];
        pos += 1;
    }
    if (pos < dst.len) dst[pos] = 0;
    return pos;
}

fn clampf(v: f32, lo: f32, hi: f32) f32 {
    return if (v < lo) lo else if (v > hi) hi else v;
}

fn writeErr(msg: []const u8) void {
    _ = sys.write(2, msg.ptr, msg.len);
}

fn isEscapeKey(mode: u8, key: u8) bool {
    return (mode == 1 and key == 9) or (mode == 10 and key == 1) or (mode == 20 and key == 27);
}

fn isShiftKey(mode: u8, key: u8) bool {
    return (mode == 1 and (key == 50 or key == 62)) or
        (mode == 10 and (key == 42 or key == 54)) or
        (mode == 20 and (key == 16 or key == 160 or key == 161));
}

fn isBackspaceKey(mode: u8, key: u8) bool {
    return (mode == 1 and key == 22) or (mode == 10 and key == 14) or (mode == 20 and key == 8);
}

fn letterAscii(key: u8, first: u8, last: u8, table: []const u8, shift: bool) ?u8 {
    if (key < first or key > last) return null;
    const ch = table[key - first];
    if (shift and ch >= 'a' and ch <= 'z') return ch - 32;
    return ch;
}

fn digitAscii(idx: u8, shift: bool) u8 {
    const plain = "1234567890";
    const shifted = "!@#$%^&*()";
    return if (shift) shifted[idx] else plain[idx];
}

fn punctAscii(plain: u8, shifted: u8, shift: bool) u8 {
    return if (shift) shifted else plain;
}

fn mapKeyToAscii(mode: u8, key: u8, shift: bool) ?u8 {
    if (mode == 1) {
        if (key >= 10 and key <= 19) return digitAscii(key - 10, shift);
        if (letterAscii(key, 24, 33, "qwertyuiop", shift)) |c| return c;
        if (letterAscii(key, 38, 46, "asdfghjkl", shift)) |c| return c;
        if (letterAscii(key, 52, 58, "zxcvbnm", shift)) |c| return c;
        return switch (key) {
            20 => punctAscii('-', '_', shift),
            21 => punctAscii('=', '+', shift),
            34 => punctAscii('[', '{', shift),
            35 => punctAscii(']', '}', shift),
            47 => punctAscii(';', ':', shift),
            48 => punctAscii('\'', '"', shift),
            49 => punctAscii('`', '~', shift),
            51 => punctAscii('\\', '|', shift),
            59 => punctAscii(',', '<', shift),
            60 => punctAscii('.', '>', shift),
            61 => punctAscii('/', '?', shift),
            65 => ' ',
            else => null,
        };
    }
    if (mode == 10) {
        if (key >= 2 and key <= 11) return digitAscii(key - 2, shift);
        if (letterAscii(key, 16, 25, "qwertyuiop", shift)) |c| return c;
        if (letterAscii(key, 30, 38, "asdfghjkl", shift)) |c| return c;
        if (letterAscii(key, 44, 50, "zxcvbnm", shift)) |c| return c;
        return switch (key) {
            12 => punctAscii('-', '_', shift),
            13 => punctAscii('=', '+', shift),
            26 => punctAscii('[', '{', shift),
            27 => punctAscii(']', '}', shift),
            39 => punctAscii(';', ':', shift),
            40 => punctAscii('\'', '"', shift),
            41 => punctAscii('`', '~', shift),
            43 => punctAscii('\\', '|', shift),
            51 => punctAscii(',', '<', shift),
            52 => punctAscii('.', '>', shift),
            53 => punctAscii('/', '?', shift),
            57 => ' ',
            else => null,
        };
    }
    if (mode == 20) {
        if (key >= '0' and key <= '9') return if (shift) digitAscii(if (key == '0') 9 else key - '1', true) else key;
        if (key >= 'A' and key <= 'Z') return if (shift) key else key + 32;
        return switch (key) {
            32 => ' ',
            186 => punctAscii(';', ':', shift),
            187 => punctAscii('=', '+', shift),
            188 => punctAscii(',', '<', shift),
            189 => punctAscii('-', '_', shift),
            190 => punctAscii('.', '>', shift),
            191 => punctAscii('/', '?', shift),
            192 => punctAscii('`', '~', shift),
            219 => punctAscii('[', '{', shift),
            220 => punctAscii('\\', '|', shift),
            221 => punctAscii(']', '}', shift),
            222 => punctAscii('\'', '"', shift),
            else => null,
        };
    }
    return null;
}

const App = struct {
    styles: []const StyleInfo,
    tabs: []const TabInfo,
    current_style: usize,
    current_tab: usize,
    toggle_1: bool,
    toggle_2: bool,
    toggle_3: bool,
    volume: f32,
    balance: f32,
    brightness: f32,
    progress: f32,
    selected_item: usize,
    search_buf: [128]u8,
    command_buf: [96]u8,
    editor_buf: [256]u8,
    notes_buf: [256]u8,
    item_a: bool,
    item_b: bool,
    item_c: bool,
    click_count: u32,
    layout_mode: u32,
    now_frame: u64,
    metrics: [4]Metric,
};

fn initApp() App {
    var app = App{
        .styles = allStyles(),
        .tabs = &[_]TabInfo{
            .{ .name = "Overview", .color = 0xFF6EA5FF },
            .{ .name = "Inspector", .color = 0xFF50D282 },
            .{ .name = "Settings", .color = 0xFFF29668 },
            .{ .name = "Themes", .color = 0xFFEBBCBA },
            .{ .name = "Logs", .color = 0xFF9CCFD8 },
        },
        .current_style = 0,
        .current_tab = 0,
        .toggle_1 = true,
        .toggle_2 = false,
        .toggle_3 = true,
        .volume = 0.62,
        .balance = 0.15,
        .brightness = 0.74,
        .progress = 0.38,
        .selected_item = 1,
        .search_buf = [_]u8{0} ** 128,
        .command_buf = [_]u8{0} ** 96,
        .editor_buf = [_]u8{0} ** 256,
        .notes_buf = [_]u8{0} ** 256,
        .item_a = true,
        .item_b = false,
        .item_c = true,
        .click_count = 0,
        .layout_mode = 0,
        .now_frame = 0,
        .metrics = .{
            .{ .name = "Tasks", .value = 17, .total = 24 },
            .{ .name = "Sync", .value = 9, .total = 12 },
            .{ .name = "Cache", .value = 4, .total = 8 },
            .{ .name = "Queue", .value = 11, .total = 16 },
        },
    };
    _ = copyText(app.search_buf[0..], "Search");
    _ = copyText(app.command_buf[0..], "build --target x86_64");
    _ = copyText(app.editor_buf[0..], "Project notes:\n- review GUI\n- tighten layout\n- keep raw backends");
    _ = copyText(app.notes_buf[0..], "Status: native GUI, no std, no builtin, no external toolkit.");
    return app;
}

pub fn main() void {
    var fb = gfx.Framebuffer.init(W, H) orelse {
        writeErr("desktop_gui: framebuffer allocation failed\n");
        sys.exit(1);
    };
    defer fb.deinit();

    var disp = display_mod.DisplayBackend.init(&fb);
    if (disp.mode == 3) {
        writeErr("desktop_gui: no supported display backend found\n");
        disp.close();
        return;
    }

    var gui = gui_mod.Gui.init(&fb);
    if (disp.getX11Conn()) |conn| {
        gui.canvas.setNative(conn);
    }
    var app = initApp();
    var mouse = mouse_mod.State.init();
    var key_state: [gui_mod.MAX_KEY]bool = [_]bool{false} ** gui_mod.MAX_KEY;
    var shift_down = false;
    var running = true;

    while (running) {
        mouse.beginFrame();
        var keys_pressed: [gui_mod.MAX_KEY]bool = [_]bool{false} ** gui_mod.MAX_KEY;
        var text_input: [16]u8 = [_]u8{0} ** 16;
        var text_len: usize = 0;

        while (disp.pollEvent()) |event| {
            switch (event) {
                .key_press => |kc| {
                    if (isEscapeKey(disp.mode, kc)) running = false;
                    if (isShiftKey(disp.mode, kc)) shift_down = true;
                    if (kc < gui_mod.MAX_KEY) {
                        key_state[kc] = true;
                        keys_pressed[kc] = true;
                    }
                    if (isBackspaceKey(disp.mode, kc)) keys_pressed[8] = true;
                    if (text_len < text_input.len) {
                        if (mapKeyToAscii(disp.mode, kc, shift_down)) |ch| {
                            text_input[text_len] = ch;
                            text_len += 1;
                        }
                    }
                },
                .key_release => |kc| {
                    if (isShiftKey(disp.mode, kc)) shift_down = false;
                    if (kc < gui_mod.MAX_KEY) key_state[kc] = false;
                },
                .mouse_move, .mouse_down, .mouse_up, .scroll => mouse.applyEvent(event),
                .close => running = false,
                .resize => |r| { _ = r; },
                .expose => {},
            }
        }
        mouse.endFrame();

        const input = gui_mod.InputState.fromMouse(
            mouse,
            key_state,
            keys_pressed,
            text_input,
            text_len,
        );

        gui.setStyle(app.styles[app.current_style].style);
        gui.beginFrame(&fb, input);
        app.now_frame +%= 1;

        drawTopBar(&gui, &fb, &app, mouse.x, mouse.y, mouse.primary_pressed);
        drawSidebar(&gui, &fb, &app, mouse.x, mouse.y, mouse.primary_pressed);
        drawMain(&gui, &fb, &app, mouse.x, mouse.y, mouse.primary_pressed);
        drawFooter(&gui, &fb, &app);

        gui.endFrame();
        gui.canvas.flush();
        if (gui.canvas.xconn == null) {
            disp.present();
        }
    }

    disp.close();
}

fn drawTopBar(gui: *gui_mod.Gui, fb: *gfx.Framebuffer, app: *App, mx: i32, my: i32, clicked: bool) void {
    _ = gui.beginWindow("dhjsjs Native GUI", 0, 0, W, 56, false);
    gui.labelColored("  Native desktop GUI  |  raw syscalls  |  zero external deps", gui.style.text_dim);
    gui.endWindow();

    const tabs = app.tabs;
    const tab_w: i32 = 130;
    var i: usize = 0;
    while (i < tabs.len) : (i += 1) {
        const x = 20 + @as(i32, @intCast(i)) * tab_w;
        const y = 28;
        const w: u32 = 120;
        const h: u32 = 20;
        const hovered = mx >= x and mx < x + @as(i32, @intCast(w)) and my >= y and my < y + @as(i32, @intCast(h));
        const base = if (app.current_tab == i) gui_mod.mixColor(gui.style.button_bg, tabs[i].color, 95) else gui.style.button_bg;
        const hover = if (app.current_tab == i) gui_mod.mixColor(gui.style.button_hover, tabs[i].color, 90) else gui.style.button_hover;
        if (gui_ext.drawRoundedButton(fb, x, y, w, h, tabs[i].name, &gui.style, base, hover, mx, my, clicked)) {
            app.current_tab = i;
        }
        if (app.current_tab == i or hovered) {
            gui_mod.fillRoundedRect(fb, x + 5, y + @as(i32, @intCast(h)) - 3, w - 10, 2, 1, tabs[i].color);
        }
    }
}

fn drawSidebar(gui: *gui_mod.Gui, fb: *gfx.Framebuffer, app: *App, mx: i32, my: i32, clicked: bool) void {
    _ = mx;
    _ = my;
    _ = clicked;
    _ = gui.beginWindow("Workspace", 16, 76, 300, 700, true);

    {
        var sb = gui_mod.StyleBuilder.init(gui.style);
        _ = sb.bg(0xFF1A1A2E);
        _ = sb.text(0xFF88FF88);
        gui.beginCustomStyle(sb.build());
        defer gui.endCustomStyle();
        gui.label("Activity");
        gui_mod.drawTriangleFilled(fb, 36, 204, 44, 200, 44, 208, gui.style.accent);
        gui_mod.drawQuadBezier(fb, 36, 204, 60, 190, 70, 200, gui.style.accent_hover, 12);
    }
    gui.separator();

    var b: [128]u8 = undefined;
    var l: usize = 0;
    l = appendText(b[0..], l, "Frame: ");
    l = appendInt(b[0..], l, @as(i32, @intCast(app.now_frame)));
    gui.labelColored(b[0..l], gui.style.text_dim);

    l = 0;
    l = appendText(b[0..], l, "Clicks: ");
    l = appendInt(b[0..], l, @as(i32, @intCast(app.click_count)));
    gui.label(b[0..l]);

    gui.separator();
    gui.checkbox("Enable live preview", &app.toggle_1);
    gui.checkbox("Auto arrange", &app.toggle_2);
    gui.checkbox("Compact mode", &app.toggle_3);
    gui.separator();

    gui.label("System meters");
    gui.progressBar("Volume", app.volume);
    gui.progressBar("Balance", clampf((app.balance + 1.0) * 0.5, 0.0, 1.0));
    gui.progressBar("Brightness", app.brightness);

    gui.separator();
    gui.label("Quick list");
    const items = [_][]const u8{ "Compile", "Run", "Package", "Deploy" };
    if (gui.comboBox("Action", items[0..], &app.selected_item)) {
        app.click_count += 1;
    }

    gui.separator();
    gui.label("Search");
    _ = gui.textInput("Search", app.search_buf[0..]);
    gui.separator();
    gui.label("Command");
    _ = gui.textInput("Command", app.command_buf[0..]);
    gui.endWindow();
}

fn drawMain(gui: *gui_mod.Gui, fb: *gfx.Framebuffer, app: *App, mx: i32, my: i32, clicked: bool) void {
    _ = mx;
    _ = my;
    _ = clicked;
    _ = gui.beginWindow("Dashboard", 332, 76, 932, 700, true);

    gui.beginScrollable(0x5000, 900, 650);

    switch (app.current_tab) {
        0 => drawOverview(gui, fb, app),
        1 => drawInspector(gui, fb, app),
        2 => drawSettings(gui, fb, app),
        3 => drawThemes(gui, fb, app),
        4 => drawLogs(gui, fb, app),
        else => drawOverview(gui, fb, app),
    }

    gui.endScrollable(0x5000, 650);
    gui.endWindow();
}

fn drawOverview(gui: *gui_mod.Gui, fb: *gfx.Framebuffer, app: *App) void {
    gui.label("Overview");
    gui.separator();
    gui.label("A single native screen with real state, not a widget sampler.");
    gui.separator();

    var i: usize = 0;
    while (i < app.metrics.len) : (i += 1) {
        const m = app.metrics[i];
        var buf: [96]u8 = undefined;
        var len: usize = 0;
        len = appendText(buf[0..], len, m.name);
        len = appendText(buf[0..], len, ": ");
        len = appendInt(buf[0..], len, m.value);
        len = appendText(buf[0..], len, "/");
        len = appendInt(buf[0..], len, m.total);
        gui.labelColored(buf[0..len], if (i == 0) gui.style.text else gui.style.text_dim);
        const ratio = @as(f32, @floatFromInt(m.value)) / @as(f32, @floatFromInt(m.total));
        gui_ext.drawProgressBar(fb, 360, 102 + @as(i32, @intCast(i)) * 56, 420, 18, clampf(ratio, 0.0, 1.0), gui.style.bg, gui.style.accent, gui.style.border);
    }

    gui.separator();
    gui.beginHorizontal();
    gui.tooltip("Apply current settings");
    if (gui.button("Apply")) app.click_count += 1;
    gui.tooltip("Reset all values to defaults");
    if (gui.button("Reset")) {
        app.volume = 0.62;
        app.balance = 0.15;
        app.brightness = 0.74;
        app.progress = 0.38;
    }
    gui.tooltip("Export configuration to file");
    if (gui.button("Export")) app.click_count += 1;
    gui.endHorizontal();
}

fn drawInspector(gui: *gui_mod.Gui, fb: *gfx.Framebuffer, app: *App) void {
    gui.label("Inspector");
    gui.separator();
    gui.label("Tune the live values.");
    gui.separator();
    _ = gui.slider("Volume", &app.volume, 0.0, 1.0);
    _ = gui.slider("Balance", &app.balance, -1.0, 1.0);
    _ = gui.slider("Brightness", &app.brightness, 0.0, 1.0);
    gui.separator();
    if (gui.button("Increase progress")) {
        app.progress += 0.08;
        if (app.progress > 1.0) app.progress = 0.0;
    }
    gui_ext.drawProgressBar(fb, 360, 400, 430, 24, clampf(app.progress, 0.0, 1.0), gui.style.bg, gui.style.accent_hover, gui.style.border);
    gui.separator();
    gui.checkbox("Pinned notes", &app.item_a);
    gui.checkbox("Auto focus", &app.item_b);
    gui.checkbox("Suppress hints", &app.item_c);
}

fn drawSettings(gui: *gui_mod.Gui, fb: *gfx.Framebuffer, app: *App) void {
    _ = fb;
    gui.label("Settings");
    gui.separator();
    gui.label("Editor buffer");
    gui.tooltip("Type project notes here");
    _ = gui.textInput("Editor", app.editor_buf[0..]);
    gui.separator();
    gui.label("Notes");
    _ = gui.textInput("Notes", app.notes_buf[0..]);
    gui.separator();
    gui.label("Layout mode");
    gui.radioButton("Dense", 0, &app.layout_mode);
    gui.radioButton("Balanced", 1, &app.layout_mode);
    gui.radioButton("Spacious", 2, &app.layout_mode);
    gui.separator();
    gui.label("Current layout state");
    const mode_str = [_][]const u8{ "Dense", "Balanced", "Spacious" };
    if (app.layout_mode < mode_str.len) {
        gui.labelColored(mode_str[app.layout_mode], gui.style.accent);
    }
}

fn drawThemes(gui: *gui_mod.Gui, fb: *gfx.Framebuffer, app: *App) void {
    _ = fb;
    gui.label("Themes");
    gui.separator();
    const cols: usize = 2;
    var i: usize = 0;
    while (i < app.styles.len) {
        gui.beginHorizontal();
        var c: usize = 0;
        while (c < cols and i < app.styles.len) : (c += 1) {
            if (gui.button(app.styles[i].name)) {
                app.current_style = i;
            }
            i += 1;
        }
        gui.endHorizontal();
    }
    gui.separator();
    gui.labelColored(app.styles[app.current_style].name, gui.style.accent);
    gui.label("The window uses the selected theme immediately.");
}

fn drawLogs(gui: *gui_mod.Gui, _: *gfx.Framebuffer, app: *App) void {
    gui.label("Logs");
    gui.separator();
    var line: [160]u8 = undefined;
    var len: usize = 0;
    len = appendText(line[0..], len, "frame=");
    len = appendInt(line[0..], len, @as(i32, @intCast(app.now_frame)));
    len = appendText(line[0..], len, " click=");
    len = appendInt(line[0..], len, @as(i32, @intCast(app.click_count)));
    gui.label(line[0..len]);
    gui.label("No backend libraries. Just framebuffer, input, and raw display paths.");
    gui.separator();
    gui.label("State meters");
    gui.progressBar("Progress", app.progress);
    gui.progressBar("Volume", app.volume);
    gui.progressBar("Balance", clampf((app.balance + 1.0) * 0.5, 0.0, 1.0));
    gui.separator();
    gui.label("Event log (scrollable list):");
    const log_items = [_][]const u8{
        "Frame 1: system initialized",
        "Frame 2: window created",
        "Frame 3: input handlers ready",
        "Frame 4: GPU surface present",
        "Frame 5: layout updated",
        "Frame 6: style applied",
        "Frame 7: mouse click detected",
        "Frame 8: rendering complete",
        "Frame 9: idle tick",
        "Frame 10: memory pool ok",
        "Frame 11: compositor sync",
        "Frame 12: cursor updated",
        "Frame 13: font cache hit",
        "Frame 14: scroll event",
        "Frame 15: keyboard input",
    };
    _ = gui.listBox("", log_items[0..], &app.selected_item, 6);
}

fn drawFooter(gui: *gui_mod.Gui, fb: *gfx.Framebuffer, app: *App) void {
    _ = fb;
    _ = app;
    _ = gui.beginWindow("Status", 0, @as(i32, @intCast(H - 28)), W, 28, false);
    gui.labelColored("  Esc to exit  |  Mouse and keyboard supported", gui.style.text_dim);
    gui.endWindow();
}
