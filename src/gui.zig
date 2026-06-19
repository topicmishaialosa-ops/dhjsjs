const gfx = @import("render.zig");

pub const MAX_ID_STACK: usize = 64;
pub const MAX_LAYOUT_STACK: usize = 64;
pub const MAX_WINDOW_STACK: usize = 16;
pub const MAX_STATE_ITEMS: usize = 128;
pub const MAX_KEY: usize = 256;

pub const Style = struct {
    bg: u32,
    panel_bg: u32,
    button_bg: u32,
    button_hover: u32,
    button_active: u32,
    button_text: u32,
    text: u32,
    text_dim: u32,
    accent: u32,
    accent_hover: u32,
    input_bg: u32,
    input_border: u32,
    input_text: u32,
    border: u32,
    slider_track: u32,
    slider_thumb: u32,
    separator: u32,
    header_bg: u32,
    header_text: u32,
    title_bg: u32,
    title_text: u32,
    check_bg: u32,
    check_mark: u32,
};

pub const style_dark = Style{
    .bg = 0xFF1E1E1E,
    .panel_bg = 0xFF252526,
    .button_bg = 0xFF3C3C3C,
    .button_hover = 0xFF505050,
    .button_active = 0xFF2D2D2D,
    .button_text = 0xFFCCCCCC,
    .text = 0xFFCCCCCC,
    .text_dim = 0xFF888888,
    .accent = 0xFF0E639C,
    .accent_hover = 0xFF1177BB,
    .input_bg = 0xFF1E1E1E,
    .input_border = 0xFF3C3C3C,
    .input_text = 0xFFCCCCCC,
    .border = 0xFF3C3C3C,
    .slider_track = 0xFF3C3C3C,
    .slider_thumb = 0xFF0E639C,
    .separator = 0xFF3C3C3C,
    .header_bg = 0xFF2D2D2D,
    .header_text = 0xFFCCCCCC,
    .title_bg = 0xFF2D2D2D,
    .title_text = 0xFFCCCCCC,
    .check_bg = 0xFF1E1E1E,
    .check_mark = 0xFFCCCCCC,
};

pub const style_light = Style{
    .bg = 0xFFF0F0F0,
    .panel_bg = 0xFFFAFAFA,
    .button_bg = 0xFFE0E0E0,
    .button_hover = 0xFFD0D0D0,
    .button_active = 0xFFC0C0C0,
    .button_text = 0xFF222222,
    .text = 0xFF222222,
    .text_dim = 0xFF888888,
    .accent = 0xFF0078D4,
    .accent_hover = 0xFF106EBE,
    .input_bg = 0xFFFFFFFF,
    .input_border = 0xFFCCCCCC,
    .input_text = 0xFF222222,
    .border = 0xFFCCCCCC,
    .slider_track = 0xFFCCCCCC,
    .slider_thumb = 0xFF0078D4,
    .separator = 0xFFCCCCCC,
    .header_bg = 0xFFE8E8E8,
    .header_text = 0xFF222222,
    .title_bg = 0xFFE8E8E8,
    .title_text = 0xFF222222,
    .check_bg = 0xFFFFFFFF,
    .check_mark = 0xFF222222,
};

pub const WidgetStateType = enum(u8) {
    none,
    text_input,
    slider_drag,
    collapsed,
};

pub const WidgetState = struct {
    id: u32,
    t: WidgetStateType,
    text_buf: [256]u8,
    text_len: usize,
    text_cursor: usize,
    float_val: f32,
    bool_val: bool,
};

pub const LayoutMode = enum(u8) {
    vertical,
    horizontal,
};

pub const LayoutFrame = struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
    cursor_x: i32,
    cursor_y: i32,
    max_x: i32,
    max_y: i32,
    mode: LayoutMode,
    spacing: i32,
    indent: i32,
};

pub const WindowState = struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
    title_h: i32,
    dragging: bool,
    drag_off_x: i32,
    drag_off_y: i32,
    id: u32,
};

pub const InputState = struct {
    mouse_x: i32,
    mouse_y: i32,
    mouse_down: bool,
    mouse_clicked: bool,
    mouse_released: bool,
    scroll: i32,
    keys: [MAX_KEY]bool,
    keys_pressed: [MAX_KEY]bool,
    text_input: [16]u8,
    text_len: usize,
};

pub const Gui = struct {
    style: Style,
    fb: *gfx.Framebuffer,
    input: InputState,

    id_stack: [MAX_ID_STACK]u32,
    id_depth: usize,

    layout_stack: [MAX_LAYOUT_STACK]LayoutFrame,
    layout_depth: usize,

    window_stack: [MAX_WINDOW_STACK]WindowState,
    window_depth: usize,

    state_items: [MAX_STATE_ITEMS]WidgetState,
    state_count: usize,

    hot_id: u32,
    active_id: u32,
    focus_id: u32,
    last_active_id: u32,
    next_id_counter: u32,
    frame_count: u64,
    clip_rect: gfx.Rect,

    pub fn init(fb: *gfx.Framebuffer) Gui {
        return Gui{
            .style = style_dark,
            .fb = fb,
            .input = InputState{
                .mouse_x = 0, .mouse_y = 0,
                .mouse_down = false, .mouse_clicked = false, .mouse_released = false,
                .scroll = 0,
                .keys = [_]bool{false} ** MAX_KEY,
                .keys_pressed = [_]bool{false} ** MAX_KEY,
                .text_input = [_]u8{0} ** 16,
                .text_len = 0,
            },
            .id_stack = [_]u32{0} ** MAX_ID_STACK,
            .id_depth = 0,
            .layout_stack = [_]LayoutFrame{LayoutFrame{
                .x = 0, .y = 0, .w = 0, .h = 0,
                .cursor_x = 0, .cursor_y = 0,
                .max_x = 0, .max_y = 0,
                .mode = .vertical, .spacing = 4, .indent = 0,
            }} ** MAX_LAYOUT_STACK,
            .layout_depth = 0,
            .window_stack = [_]WindowState{undefined} ** MAX_WINDOW_STACK,
            .window_depth = 0,
            .state_items = [_]WidgetState{WidgetState{
                .id = 0, .t = .none,
                .text_buf = [_]u8{0} ** 256,
                .text_len = 0, .text_cursor = 0,
                .float_val = 0, .bool_val = false,
            }} ** MAX_STATE_ITEMS,
            .state_count = 0,
            .hot_id = 0,
            .active_id = 0,
            .focus_id = 0,
            .last_active_id = 0,
            .next_id_counter = 1,
            .frame_count = 0,
            .clip_rect = gfx.Rect{ .x = 0, .y = 0, .w = 0, .h = 0 },
        };
    }

    pub fn setStyle(self: *Gui, s: Style) void {
        self.style = s;
    }

    pub fn beginFrame(self: *Gui, fb: *gfx.Framebuffer, input: InputState) void {
        self.fb = fb;
        self.input = input;
        self.frame_count += 1;
        self.hot_id = 0;
        self.next_id_counter = 1;
        self.id_depth = 0;
        self.layout_depth = 0;
        self.window_depth = 0;
        self.state_count = 0;
        self.clip_rect = gfx.Rect{ .x = 0, .y = 0, .w = fb.width, .h = fb.height };
        self.fb.fill(gfx.rgb(
            @as(u8, @truncate((self.style.bg >> 16) & 0xFF)),
            @as(u8, @truncate((self.style.bg >> 8) & 0xFF)),
            @as(u8, @truncate(self.style.bg & 0xFF)),
        ));
    }

    pub fn endFrame(self: *Gui) void {
        if (self.active_id != 0 and !self.input.mouse_down) {
            self.active_id = 0;
        }
    }

    fn nextId(self: *Gui) u32 {
        const id = self.next_id_counter;
        self.next_id_counter += 1;
        return id;
    }

    fn getOrCreateState(self: *Gui, id: u32, t: WidgetStateType) *WidgetState {
        var i: usize = 0;
        while (i < self.state_count) : (i += 1) {
            if (self.state_items[i].id == id) return &self.state_items[i];
        }
        if (self.state_count < MAX_STATE_ITEMS) {
            const idx = self.state_count;
            self.state_count += 1;
            self.state_items[idx] = WidgetState{
                .id = id, .t = t,
                .text_buf = [_]u8{0} ** 256,
                .text_len = 0, .text_cursor = 0,
                .float_val = 0, .bool_val = false,
            };
            return &self.state_items[idx];
        }
        return &self.state_items[0];
    }

    fn isHot(self: *Gui, id: u32) bool { return self.hot_id == id; }
    fn isActive(self: *Gui, id: u32) bool { return self.active_id == id; }
    fn isFocused(self: *Gui, id: u32) bool { return self.focus_id == id; }

    fn testHot(self: *Gui, id: u32, x: i32, y: i32, w: u32, h: u32) bool {
        if (self.input.mouse_x >= x and self.input.mouse_x < x + @as(i32, @intCast(w)) and
            self.input.mouse_y >= y and self.input.mouse_y < y + @as(i32, @intCast(h)))
        {
            self.hot_id = id;
            return true;
        }
        return false;
    }

    fn getContentRegion(self: *Gui) gfx.Rect {
        if (self.layout_depth > 0) {
            const l = &self.layout_stack[self.layout_depth - 1];
            return gfx.Rect{ .x = l.cursor_x, .y = l.cursor_y, .w = 0, .h = 0 };
        }
        return gfx.Rect{ .x = 0, .y = 0, .w = self.fb.width, .h = self.fb.height };
    }

    pub fn button(self: *Gui, label_text: []const u8) bool {
        const id = self.nextId();
        var area = self.allocSpace(@as(u32, @intCast(label_text.len * 10 + 20)), 28);
        if (area.w < 10) area.w = 80;

        const hovered = self.testHot(id, area.x, area.y, area.w, area.h);
        var clicked = false;

        if (hovered and self.input.mouse_clicked) {
            self.active_id = id;
        }
        if (self.isActive(id) and self.input.mouse_released) {
            if (hovered) clicked = true;
            self.active_id = 0;
        }

        const bg = if (self.isActive(id)) self.style.button_active
            else if (hovered) self.style.button_hover
            else self.style.button_bg;

        fillRect(self.fb, area.x, area.y, area.w, area.h, bg);
        drawRectBorder(self.fb, area.x, area.y, area.w, area.h, self.style.border);
        const tw = @as(i32, @intCast(label_text.len * 8));
        drawTextAt(self.fb, label_text,
            area.x + @divTrunc(@as(i32, @intCast(area.w)), 2) - @divTrunc(tw, 2),
            area.y + 6,
            self.style.button_text, 8);

        return clicked;
    }

    pub fn label(self: *Gui, text: []const u8) void {
        _ = self.nextId();
        const th: u32 = 16;
        const tw = @as(u32, @intCast(text.len * 8));
        const area = self.allocSpace(tw + 4, th);
        drawTextAt(self.fb, text, area.x + 2, area.y + 2, self.style.text, 8);
    }

    pub fn labelColored(self: *Gui, text: []const u8, color: u32) void {
        _ = self.nextId();
        const th: u32 = 16;
        const tw = @as(u32, @intCast(text.len * 8));
        const area = self.allocSpace(tw + 4, th);
        drawTextAt(self.fb, text, area.x + 2, area.y + 2, color, 8);
    }

    pub fn textInput(self: *Gui, label_text: []const u8, buf: []u8) bool {
        const id = self.nextId();
        const widget_id = id;
        const state = self.getOrCreateState(widget_id, .text_input);

        _ = label_text;
        const ih: u32 = 24;
        const iw: u32 = @max(160, @as(u32, @intCast(self.fb.width)) - 40);
        var area = self.allocSpace(iw, ih);
        if (area.w < 20) area.w = iw;

        const hovered = self.testHot(widget_id, area.x, area.y, area.w, area.h);
        var changed = false;

        if (hovered and self.input.mouse_clicked) {
            self.active_id = widget_id;
            self.focus_id = widget_id;
        }

        const is_focused = self.isFocused(widget_id);

        if (is_focused and self.active_id == widget_id and !self.input.mouse_down) {
            self.active_id = 0;
        }

        if (is_focused) {
            if (self.input.keys_pressed[8] or self.input.keys_pressed[46]) {
                if (state.text_len > 0) {
                    if (state.text_cursor > 0) {
                        state.text_cursor -= 1;
                        var k: usize = state.text_cursor;
                        while (k < state.text_len) : (k += 1) {
                            state.text_buf[k] = state.text_buf[k + 1];
                        }
                        state.text_len -= 1;
                        changed = true;
                    }
                }
            }
            if (self.input.text_len > 0) {
                var ti: usize = 0;
                while (ti < self.input.text_len and state.text_len < 255) : (ti += 1) {
                    const ch = self.input.text_input[ti];
                    if (ch >= 32 and ch < 127) {
                        var k: usize = state.text_len;
                        while (k > state.text_cursor) : (k -= 1) {
                            state.text_buf[k] = state.text_buf[k - 1];
                        }
                        state.text_buf[state.text_cursor] = ch;
                        state.text_cursor += 1;
                        state.text_len += 1;
                        changed = true;
                    }
                }
            }
        }

        const bg = self.style.input_bg;
        const border = if (is_focused) self.style.accent else self.style.input_border;

        fillRect(self.fb, area.x, area.y, area.w, area.h, bg);
        drawRectBorder(self.fb, area.x, area.y, area.w, area.h, border);

        var display_buf: [257]u8 = undefined;
        const display_len: usize = state.text_len;
        var di: usize = 0;
        while (di < display_len) : (di += 1) {
            display_buf[di] = state.text_buf[di];
        }
        display_buf[display_len] = 0;

        const txt_x = area.x + 4;
        const txt_y = area.y + 4;
        drawTextAt(self.fb, display_buf[0..display_len], txt_x, txt_y, self.style.input_text, 8);

        if (is_focused and (self.frame_count / 30) % 2 == 0) {
            const cx = txt_x + @as(i32, @intCast(state.text_cursor * 8));
            fillRect(self.fb, cx, txt_y, 2, 16, self.style.accent);
        }

        if (changed and buf.len >= state.text_len) {
            var ci: usize = 0;
            while (ci < state.text_len) : (ci += 1) buf[ci] = state.text_buf[ci];
            if (state.text_len < buf.len) buf[state.text_len] = 0;
        }

        return changed;
    }

    pub fn checkbox(self: *Gui, label_text: []const u8, checked: *bool) void {
        const id = self.nextId();
        const widget_id = id;

        const ch: u32 = 20;
        const cw: u32 = 20;
        const area = self.allocSpace(cw + @as(u32, @intCast(label_text.len * 8 + 8)), ch + 4);

        const hovered = self.testHot(widget_id, area.x, area.y, area.w, area.h);

        if (hovered and self.input.mouse_clicked) {
            checked.* = !checked.*;
            self.active_id = widget_id;
        }
        if (self.isActive(widget_id) and self.input.mouse_released) {
            self.active_id = 0;
        }

        const bx = area.x;
        const by = area.y + 2;
        const border = if (hovered) self.style.accent else self.style.border;
        fillRect(self.fb, bx, by, cw, ch, self.style.check_bg);
        drawRectBorder(self.fb, bx, by, cw, ch, border);

        if (checked.*) {
            drawTextAt(self.fb, "X", bx + 4, by + 2, self.style.check_mark, 8);
        }

        drawTextAt(self.fb, label_text, bx + @as(i32, @intCast(cw)) + 6, by + 1, self.style.text, 8);
    }

    pub fn slider(self: *Gui, label_text: []const u8, value: *f32, min: f32, max: f32) bool {
        const id = self.nextId();
        const widget_id = id;

        const sh: u32 = 20;
        const sw: u32 = @max(120, @as(u32, @intCast(self.fb.width - 40)));
        var area = self.allocSpace(sw, sh + 16);
        if (area.w < 20) area.w = sw;

        const track_h: u32 = 6;
        const thumb_r: u32 = 6;
        const track_x = area.x;
        const track_y = area.y + @as(i32, @intCast(sh - track_h)) / 2;
        const track_w = area.w;

        const range = max - min;
        const norm = if (range != 0) (value.* - min) / range else 0.0;
        const thumb_x = track_x + @as(i32, @intFromFloat(@as(f64, norm) * @as(f64, @floatFromInt(track_w))));

        const hovered = self.testHot(widget_id, thumb_x - @as(i32, @intCast(thumb_r)) - 4, track_y - @as(i32, @intCast(thumb_r)) - 2,
            thumb_r * 2 + 8, track_h + thumb_r * 2 + 4);
        _ = hovered;

        var changed = false;

        if (self.testHot(widget_id, track_x, track_y - 4, track_w, track_h + 8) and self.input.mouse_clicked) {
            self.active_id = widget_id;
        }

        if (self.isActive(widget_id)) {
            const rel_x = self.input.mouse_x - track_x;
            const new_norm = @min(1.0, @max(0.0, @as(f32, @floatFromInt(rel_x)) / @as(f32, @floatFromInt(track_w))));
            const new_val = min + new_norm * range;
            if (new_val != value.*) {
                value.* = new_val;
                changed = true;
            }
            if (!self.input.mouse_down) {
                self.active_id = 0;
            }
        }

        const is_active = self.isActive(widget_id);
        const thumb_fill = if (is_active) self.style.accent_hover else self.style.slider_thumb;

        fillRect(self.fb, track_x, track_y, track_w, track_h, self.style.slider_track);

        const fill_w: u32 = @intCast(@max(0, thumb_x - track_x));
        if (fill_w > 0) {
            fillRect(self.fb, track_x, track_y, fill_w, track_h, self.style.accent);
        }

        const fr = @as(i32, @intCast(thumb_r));
        fillRect(self.fb, thumb_x - fr, track_y - 2, fr * 2, track_h + 4, thumb_fill);
        drawRectBorder(self.fb, thumb_x - fr, track_y - 2, fr * 2, track_h + 4, self.style.border);

        var lbl_buf: [32]u8 = undefined;
        var lbl_len: usize = 0;
        if (label_text.len > 0) {
            for (label_text) |ch| { if (lbl_len < 30) { lbl_buf[lbl_len] = ch; lbl_len += 1; } }
            lbl_buf[lbl_len] = ' '; lbl_len += 1;
            lbl_buf[lbl_len] = ':'; lbl_len += 1;
            lbl_buf[lbl_len] = ' '; lbl_len += 1;
        }
        const ival = @as(i32, @intFromFloat(value.*));
        var num_buf: [16]u8 = undefined;
        var num_len: usize = 0;
        if (ival == 0 and value.* < 0) {
            if (num_len < 15) { num_buf[num_len] = '-'; num_len += 1; }
        }
        const tmp = @abs(value.*);
        const int_part = @as(i32, @intFromFloat(tmp));
        var tmp2 = int_part;
        var digits: [16]u8 = undefined;
        var dc: usize = 0;
        if (tmp2 == 0) { digits[dc] = '0'; dc += 1; }
        else { while (tmp2 > 0) { digits[dc] = @as(u8, @intCast('0' + @mod(tmp2, 10))); tmp2 = @divTrunc(tmp2, 10); dc += 1; } }
        var di2: usize = dc;
        while (di2 > 0) {
            di2 -= 1;
            if (num_len < 15) { num_buf[num_len] = digits[di2]; num_len += 1; }
        }
        const frac = @as(i32, @intFromFloat((tmp - @as(f32, @floatFromInt(int_part))) * 100));
        if (num_len < 15) { num_buf[num_len] = '.'; num_len += 1; }
        const f1 = @abs(frac) / 10;
        const f2 = @abs(frac) % 10;
        if (num_len < 15) { num_buf[num_len] = @as(u8, @intCast('0' + @as(u8, @intCast(f1)))); num_len += 1; }
        if (num_len < 15) { num_buf[num_len] = @as(u8, @intCast('0' + @as(u8, @intCast(f2)))); num_len += 1; }

        for (num_buf[0..num_len]) |ch| {
            if (lbl_len < 30) { lbl_buf[lbl_len] = ch; lbl_len += 1; }
        }

        drawTextAt(self.fb, lbl_buf[0..lbl_len], area.x, area.y + @as(i32, @intCast(sh)) - 14, self.style.text_dim, 8);
        return changed;
    }

    pub fn collapsible(self: *Gui, label_text: []const u8, open: *bool) bool {
        const id = self.nextId();
        const widget_id = id;

        const h: u32 = 24;
        const tw = @as(u32, @intCast(label_text.len * 8));
        const area = self.allocSpace(tw + 40, h);

        const hovered = self.testHot(widget_id, area.x, area.y, area.w, area.h);
        var opened_this_frame = false;

        if (hovered and self.input.mouse_clicked) {
            open.* = !open.*;
            opened_this_frame = true;
            self.active_id = widget_id;
        }
        if (self.isActive(widget_id) and self.input.mouse_released) {
            self.active_id = 0;
        }

        const bg = if (hovered) self.style.button_hover else self.style.header_bg;
        fillRect(self.fb, area.x, area.y, area.w, area.h, bg);
        drawRectBorder(self.fb, area.x, area.y, area.w, area.h, self.style.border);

        const arrow = if (open.*) "v" else ">";
        drawTextAt(self.fb, arrow, area.x + 4, area.y + 4, self.style.header_text, 8);
        drawTextAt(self.fb, label_text, area.x + 20, area.y + 4, self.style.header_text, 8);

        if (open.*) {
            const indent = self.style.button_bg;
            _ = indent;
            self.addSpace(0, 2);
        }

        return open.*;
    }

    pub fn separator(self: *Gui) void {
        const id = self.nextId();
        _ = id;
        const area = self.allocSpace(10, 6);
        const cy = area.y + 2;
        const cw = if (self.layout_depth > 0) self.layout_stack[self.layout_depth - 1].w else @as(u32, @intCast(self.fb.width));
        fillRect(self.fb, area.x, cy, cw, 2, self.style.separator);
    }

    pub fn sameLine(self: *Gui, spacing: i32) void {
        if (self.layout_depth > 0) {
            const l = &self.layout_stack[self.layout_depth - 1];
            if (l.mode == .vertical) {
                l.cursor_x = l.max_x + spacing;
                l.max_x = l.cursor_x;
            }
        }
    }

    pub fn addSpace(self: *Gui, w: u32, h: u32) void {
        _ = self.nextId();
        _ = self.allocSpace(w, h);
    }

    pub fn beginVertical(self: *Gui) void {
        const id = self.nextId();
        const pos = self.getContentRegion();
        if (self.layout_depth < MAX_LAYOUT_STACK) {
            self.layout_stack[self.layout_depth] = LayoutFrame{
                .x = pos.x, .y = pos.y, .w = 0, .h = 0,
                .cursor_x = pos.x, .cursor_y = pos.y,
                .max_x = pos.x, .max_y = pos.y,
                .mode = .vertical, .spacing = 4, .indent = 0,
            };
            self.layout_depth += 1;
        }
        _ = id;
    }

    pub fn endVertical(self: *Gui) void {
        if (self.layout_depth > 0) {
            self.layout_depth -= 1;
            const l = self.layout_stack[self.layout_depth];
            self.addSpace(@as(u32, @intCast(@max(0, l.max_x - l.x))),
                @as(u32, @intCast(@max(0, l.max_y - l.y))));
        }
    }

    pub fn beginHorizontal(self: *Gui) void {
        const id = self.nextId();
        const pos = self.getContentRegion();
        if (self.layout_depth < MAX_LAYOUT_STACK) {
            self.layout_stack[self.layout_depth] = LayoutFrame{
                .x = pos.x, .y = pos.y, .w = 0, .h = 0,
                .cursor_x = pos.x, .cursor_y = pos.y,
                .max_x = pos.x, .max_y = pos.y,
                .mode = .horizontal, .spacing = 4, .indent = 0,
            };
            self.layout_depth += 1;
        }
        _ = id;
    }

    pub fn endHorizontal(self: *Gui) void {
        if (self.layout_depth > 0) {
            self.layout_depth -= 1;
            const l = self.layout_stack[self.layout_depth];
            self.addSpace(@as(u32, @intCast(@max(0, l.max_x - l.x))),
                @as(u32, @intCast(@max(0, l.max_y - l.y))));
        }
    }

    pub fn beginWindow(self: *Gui, title: []const u8, x: i32, y: i32, w: u32, h: u32, resizable: bool) bool {
        const id = self.nextId();
        const title_h: i32 = 28;
        var win_x = x;
        var win_y = y;
        var win_w = w;
        var win_h = h;

        if (self.window_depth < MAX_WINDOW_STACK) {
            var ws = WindowState{
                .x = win_x, .y = win_y, .w = win_w, .h = win_h,
                .title_h = title_h,
                .dragging = false, .drag_off_x = 0, .drag_off_y = 0,
                .id = id,
            };

            const drag_h = title_h;
            const drag_id = id + 0x1000;
            const hover_title = self.testHot(drag_id, win_x, win_y, win_w, @as(u32, @intCast(drag_h)));

            if (hover_title and self.input.mouse_clicked) {
                self.active_id = drag_id;
                ws.dragging = true;
                ws.drag_off_x = self.input.mouse_x - win_x;
                ws.drag_off_y = self.input.mouse_y - win_y;
            }

            if (ws.dragging and self.isActive(drag_id)) {
                win_x = self.input.mouse_x - ws.drag_off_x;
                win_y = self.input.mouse_y - ws.drag_off_y;
                ws.x = win_x;
                ws.y = win_y;
                if (!self.input.mouse_down) {
                    ws.dragging = false;
                    self.active_id = 0;
                }
            }

            self.window_stack[self.window_depth] = ws;
            self.window_depth += 1;
        }

        fillRect(self.fb, win_x, win_y, win_w, @as(u32, @intCast(title_h)), self.style.title_bg);
        drawRectBorder(self.fb, win_x, win_y, win_w, @as(u32, @intCast(title_h)), self.style.border);
        drawTextAt(self.fb, title, win_x + 8, win_y + 6, self.style.title_text, 8);

        const client_y = win_y + title_h;
        const client_h = win_h - @as(u32, @intCast(title_h));
        fillRect(self.fb, win_x, client_y, win_w, client_h, self.style.panel_bg);
        drawRectBorder(self.fb, win_x, client_y, win_w, client_h, self.style.border);

        if (resizable) {
            const resize_id = id + 0x2000;
            const rs: i32 = 12;
            _ = self.testHot(resize_id, win_x + @as(i32, @intCast(win_w)) - rs, win_y + @as(i32, @intCast(win_h)) - rs, @as(u32, @intCast(rs)), @as(u32, @intCast(rs)));
            if (self.isHot(resize_id) and self.input.mouse_clicked) {
                self.active_id = resize_id;
            }
            if (self.isActive(resize_id)) {
                const new_w = @max(100, self.input.mouse_x - win_x);
                const new_h = @max(60, self.input.mouse_y - win_y);
                if (self.window_depth > 0) {
                    self.window_stack[self.window_depth - 1].w = @as(u32, @intCast(new_w));
                    self.window_stack[self.window_depth - 1].h = @as(u32, @intCast(new_h));
                }
                win_w = @as(u32, @intCast(new_w));
                win_h = @as(u32, @intCast(new_h));
                if (!self.input.mouse_down) {
                    self.active_id = 0;
                }
            }
        }

        if (self.layout_depth < MAX_LAYOUT_STACK) {
            self.layout_stack[self.layout_depth] = LayoutFrame{
                .x = win_x + 8, .y = client_y + 4, .w = win_w - 16, .h = client_h - 8,
                .cursor_x = win_x + 8, .cursor_y = client_y + 4,
                .max_x = win_x + 8, .max_y = client_y + 4,
                .mode = .vertical, .spacing = 4, .indent = 0,
            };
            self.layout_depth += 1;
        }

        return true;
    }

    pub fn endWindow(self: *Gui) void {
        if (self.layout_depth > 0) {
            self.layout_depth -= 1;
        }
    }

    fn allocSpace(self: *Gui, w: u32, h: u32) gfx.Rect {
        if (self.layout_depth == 0) {
            return gfx.Rect{ .x = 0, .y = 0, .w = w, .h = h };
        }
        const l = &self.layout_stack[self.layout_depth - 1];
        const rx = l.cursor_x;
        const ry = l.cursor_y;

        if (l.mode == .vertical) {
            l.cursor_y += @as(i32, @intCast(h)) + l.spacing;
            l.cursor_x = l.x;
            if (w > @as(u32, @intCast(l.max_x - l.x))) {
                l.max_x = l.x + @as(i32, @intCast(w));
            }
            if (l.cursor_y > l.max_y) {
                l.max_y = l.cursor_y;
            }
            if (w < 1) {
                l.cursor_x = l.x;
            }
            const lw: u32 = @as(u32, @intCast(@max(0, l.max_x - l.x)));
            _ = lw;
            return gfx.Rect{ .x = rx, .y = ry, .w = if (w > 0) w else @as(u32, @intCast(@max(0, l.w))), .h = h };
        } else {
            l.cursor_x += @as(i32, @intCast(w)) + l.spacing;
            if (l.cursor_x > l.max_x) l.max_x = l.cursor_x;
            const lh: u32 = @as(u32, @intCast(@max(0, l.max_y - l.y)));
            _ = lh;
            return gfx.Rect{ .x = rx, .y = ry, .w = w, .h = if (h > 0) h else 20 };
        }
    }
};

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

fn drawRectBorder(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, color: u32) void {
    if (w < 2 or h < 2) {
        fillRect(fb, x, y, w, h, color);
        return;
    }
    fillRect(fb, x, y, w, 1, color);
    fillRect(fb, x, y + @as(i32, @intCast(h)) - 1, w, 1, color);
    fillRect(fb, x, y, 1, h, color);
    fillRect(fb, x + @as(i32, @intCast(w)) - 1, y, 1, h, color);
}

fn drawTextAt(fb: *gfx.Framebuffer, text: []const u8, x: i32, y: i32, color: u32, size: u32) void {
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
