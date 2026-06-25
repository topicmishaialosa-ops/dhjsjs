const gfx = @import("render.zig");
const mouse_mod = @import("mouse.zig");

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
    scrollbar_bg: u32,
    scrollbar_thumb: u32,
    rounding: u32,
    window_rounding: u32,
    shadow: u8,
    spacing: u32,
    padding: u32,
};

pub const style_dark = Style{
    .bg = 0xFF12141C,
    .panel_bg = 0xFF1A1D28,
    .button_bg = 0xFF2D3148,
    .button_hover = 0xFF3E4360,
    .button_active = 0xFF4378E0,
    .button_text = 0xFFECF0FA,
    .text = 0xFFECF0FA,
    .text_dim = 0xFF8F96B8,
    .accent = 0xFF5B8DEF,
    .accent_hover = 0xFF7AA3F2,
    .input_bg = 0xFF14161F,
    .input_border = 0xFF2D3148,
    .input_text = 0xFFECF0FA,
    .border = 0xFF2A2E40,
    .slider_track = 0xFF282C3E,
    .slider_thumb = 0xFF5B8DEF,
    .separator = 0xFF262A3A,
    .header_bg = 0xFF1A2140,
    .header_text = 0xFFECF0FA,
    .title_bg = 0xFF181C2C,
    .title_text = 0xFFECF0FA,
    .check_bg = 0xFF202336,
    .check_mark = 0xFF5BD88A,
    .scrollbar_bg = 0xFF1E2232,
    .scrollbar_thumb = 0xFF5B8DEF,
    .rounding = 8,
    .window_rounding = 12,
    .shadow = 22,
    .spacing = 6,
    .padding = 6,
};

pub const style_light = Style{
    .bg = 0xFFF2F4F9,
    .panel_bg = 0xFFFFFFFF,
    .button_bg = 0xFFDCE1EC,
    .button_hover = 0xFFC9D0DF,
    .button_active = 0xFF306CC3,
    .button_text = 0xFF1C2030,
    .text = 0xFF1C2030,
    .text_dim = 0xFF6A7490,
    .accent = 0xFF2A58A8,
    .accent_hover = 0xFF1E4A94,
    .input_bg = 0xFFFFFFFF,
    .input_border = 0xFFD2D8E4,
    .input_text = 0xFF1C2030,
    .border = 0xFFC8CEDC,
    .slider_track = 0xFFD6DBE6,
    .slider_thumb = 0xFF3268C0,
    .separator = 0xFFD6DBE6,
    .header_bg = 0xFF204480,
    .header_text = 0xFFFFFFFF,
    .title_bg = 0xFFE8EBF2,
    .title_text = 0xFF1C2030,
    .check_bg = 0xFFFFFFFF,
    .check_mark = 0xFF269658,
    .scrollbar_bg = 0xFFE4E7EF,
    .scrollbar_thumb = 0xFF3A78D0,
    .rounding = 6,
    .window_rounding = 10,
    .shadow = 20,
    .spacing = 6,
    .padding = 6,
};

pub const style_modern_dark = style_dark;
pub const style_modern_light = style_light;

pub const style_diamond = Style{
    .bg = 0xFF0B0D14,
    .panel_bg = 0xFF131620,
    .button_bg = 0xFF22263A,
    .button_hover = 0xFF2E3350,
    .button_active = 0xFFAA56F0,
    .button_text = 0xFFEEF0FA,
    .text = 0xFFEEF0FA,
    .text_dim = 0xFF7C84AA,
    .accent = 0xFFAA56F0,
    .accent_hover = 0xFFC47AF2,
    .input_bg = 0xFF0D0F18,
    .input_border = 0xFF22263A,
    .input_text = 0xFFEEF0FA,
    .border = 0xFF1D2134,
    .slider_track = 0xFF1D2134,
    .slider_thumb = 0xFFAA56F0,
    .separator = 0xFF1A1E30,
    .header_bg = 0xFF2A1440,
    .header_text = 0xFFEEF0FA,
    .title_bg = 0xFF10141E,
    .title_text = 0xFFD4A0F8,
    .check_bg = 0xFF181C2E,
    .check_mark = 0xFF56E0C4,
    .scrollbar_bg = 0xFF161A28,
    .scrollbar_thumb = 0xFFAA56F0,
    .rounding = 8,
    .window_rounding = 12,
    .shadow = 30,
    .spacing = 8,
    .padding = 8,
};

pub const STYLE_BG: u32 = 0;
pub const STYLE_PANEL_BG: u32 = 1;
pub const STYLE_BUTTON_BG: u32 = 2;
pub const STYLE_BUTTON_HOVER: u32 = 3;
pub const STYLE_TEXT: u32 = 4;
pub const STYLE_ACCENT: u32 = 5;
pub const STYLE_BORDER: u32 = 6;
pub const STYLE_CHECK_MARK: u32 = 7;
pub const STYLE_INPUT_BG: u32 = 8;
pub const STYLE_SEPARATOR: u32 = 9;
pub const STYLE_BUTTON_ACTIVE: u32 = 10;
pub const STYLE_BUTTON_TEXT: u32 = 11;
pub const STYLE_TEXT_DIM: u32 = 12;
pub const STYLE_ACCENT_HOVER: u32 = 13;
pub const STYLE_INPUT_BORDER: u32 = 14;
pub const STYLE_INPUT_TEXT: u32 = 15;
pub const STYLE_SLIDER_TRACK: u32 = 16;
pub const STYLE_SLIDER_THUMB: u32 = 17;
pub const STYLE_HEADER_BG: u32 = 18;
pub const STYLE_HEADER_TEXT: u32 = 19;
pub const STYLE_TITLE_BG: u32 = 20;
pub const STYLE_TITLE_TEXT: u32 = 21;
pub const STYLE_CHECK_BG: u32 = 22;
pub const STYLE_SCROLLBAR_BG: u32 = 23;
pub const STYLE_SCROLLBAR_THUMB: u32 = 24;
pub const STYLE_ROUNDING: u32 = 25;
pub const STYLE_WINDOW_ROUNDING: u32 = 26;
pub const STYLE_SHADOW: u32 = 27;
pub const STYLE_SPACING: u32 = 28;
pub const STYLE_PADDING: u32 = 29;

fn normalizeColor(color: u32) u32 {
    return if ((color & 0xFF000000) == 0) 0xFF000000 | color else color;
}

pub const StyleBuilder = struct {
    style: Style,

    pub fn init(base: Style) StyleBuilder {
        return StyleBuilder{ .style = base };
    }

    pub fn bg(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.bg = c;
        return self;
    }
    pub fn panelBg(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.panel_bg = c;
        return self;
    }
    pub fn buttonBg(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.button_bg = c;
        return self;
    }
    pub fn buttonHover(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.button_hover = c;
        return self;
    }
    pub fn buttonActive(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.button_active = c;
        return self;
    }
    pub fn buttonText(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.button_text = c;
        return self;
    }
    pub fn text(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.text = c;
        return self;
    }
    pub fn textDim(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.text_dim = c;
        return self;
    }
    pub fn accent(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.accent = c;
        return self;
    }
    pub fn accentHover(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.accent_hover = c;
        return self;
    }
    pub fn inputBg(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.input_bg = c;
        return self;
    }
    pub fn inputBorder(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.input_border = c;
        return self;
    }
    pub fn inputText(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.input_text = c;
        return self;
    }
    pub fn border(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.border = c;
        return self;
    }
    pub fn sliderTrack(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.slider_track = c;
        return self;
    }
    pub fn sliderThumb(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.slider_thumb = c;
        return self;
    }
    pub fn separator(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.separator = c;
        return self;
    }
    pub fn headerBg(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.header_bg = c;
        return self;
    }
    pub fn headerText(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.header_text = c;
        return self;
    }
    pub fn titleBg(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.title_bg = c;
        return self;
    }
    pub fn titleText(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.title_text = c;
        return self;
    }
    pub fn checkBg(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.check_bg = c;
        return self;
    }
    pub fn checkMark(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.check_mark = c;
        return self;
    }
    pub fn scrollbarBg(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.scrollbar_bg = c;
        return self;
    }
    pub fn scrollbarThumb(self: *StyleBuilder, c: u32) *StyleBuilder {
        self.style.scrollbar_thumb = c;
        return self;
    }
    pub fn rounding(self: *StyleBuilder, r: u32) *StyleBuilder {
        self.style.rounding = r;
        return self;
    }
    pub fn windowRounding(self: *StyleBuilder, r: u32) *StyleBuilder {
        self.style.window_rounding = r;
        return self;
    }
    pub fn shadow(self: *StyleBuilder, v: u8) *StyleBuilder {
        self.style.shadow = v;
        return self;
    }
    pub fn spacing(self: *StyleBuilder, v: u32) *StyleBuilder {
        self.style.spacing = v;
        return self;
    }
    pub fn padding(self: *StyleBuilder, v: u32) *StyleBuilder {
        self.style.padding = v;
        return self;
    }
    pub fn build(self: *StyleBuilder) Style {
        return self.style;
    }
};

pub const Renderer = struct {
    canvas: *gfx.Canvas,
    style: Style,

    pub fn init(canvas: *gfx.Canvas) Renderer {
        return Renderer{
            .canvas = canvas,
            .style = style_dark,
        };
    }

    pub fn setStyle(self: *Renderer, style: Style) void {
        self.style = style;
    }

    pub fn setStyleColor(self: *Renderer, field_id: u32, color_raw: u32) void {
        const c = normalizeColor(color_raw);
        switch (field_id) {
            0 => self.style.bg = c,
            1 => self.style.panel_bg = c,
            2 => self.style.button_bg = c,
            3 => self.style.button_hover = c,
            4 => self.style.text = c,
            5 => self.style.accent = c,
            6 => self.style.border = c,
            7 => self.style.check_mark = c,
            8 => self.style.input_bg = c,
            9 => self.style.separator = c,
            10 => self.style.button_active = c,
            11 => self.style.button_text = c,
            12 => self.style.text_dim = c,
            13 => self.style.accent_hover = c,
            14 => self.style.input_border = c,
            15 => self.style.input_text = c,
            16 => self.style.slider_track = c,
            17 => self.style.slider_thumb = c,
            18 => self.style.header_bg = c,
            19 => self.style.header_text = c,
            20 => self.style.title_bg = c,
            21 => self.style.title_text = c,
            22 => self.style.check_bg = c,
            23 => self.style.scrollbar_bg = c,
            24 => self.style.scrollbar_thumb = c,
            else => {},
        }
    }

    pub fn setRounding(self: *Renderer, rounding: u32) void {
        self.style.rounding = rounding;
    }

    pub fn setStyleField(self: *Renderer, field_id: u32, value: u32) void {
        switch (field_id) {
            STYLE_BG => self.style.bg = normalizeColor(value),
            STYLE_PANEL_BG => self.style.panel_bg = normalizeColor(value),
            STYLE_BUTTON_BG => self.style.button_bg = normalizeColor(value),
            STYLE_BUTTON_HOVER => self.style.button_hover = normalizeColor(value),
            STYLE_TEXT => self.style.text = normalizeColor(value),
            STYLE_ACCENT => self.style.accent = normalizeColor(value),
            STYLE_BORDER => self.style.border = normalizeColor(value),
            STYLE_CHECK_MARK => self.style.check_mark = normalizeColor(value),
            STYLE_INPUT_BG => self.style.input_bg = normalizeColor(value),
            STYLE_SEPARATOR => self.style.separator = normalizeColor(value),
            STYLE_BUTTON_ACTIVE => self.style.button_active = normalizeColor(value),
            STYLE_BUTTON_TEXT => self.style.button_text = normalizeColor(value),
            STYLE_TEXT_DIM => self.style.text_dim = normalizeColor(value),
            STYLE_ACCENT_HOVER => self.style.accent_hover = normalizeColor(value),
            STYLE_INPUT_BORDER => self.style.input_border = normalizeColor(value),
            STYLE_INPUT_TEXT => self.style.input_text = normalizeColor(value),
            STYLE_SLIDER_TRACK => self.style.slider_track = normalizeColor(value),
            STYLE_SLIDER_THUMB => self.style.slider_thumb = normalizeColor(value),
            STYLE_HEADER_BG => self.style.header_bg = normalizeColor(value),
            STYLE_HEADER_TEXT => self.style.header_text = normalizeColor(value),
            STYLE_TITLE_BG => self.style.title_bg = normalizeColor(value),
            STYLE_TITLE_TEXT => self.style.title_text = normalizeColor(value),
            STYLE_CHECK_BG => self.style.check_bg = normalizeColor(value),
            STYLE_SCROLLBAR_BG => self.style.scrollbar_bg = normalizeColor(value),
            STYLE_SCROLLBAR_THUMB => self.style.scrollbar_thumb = normalizeColor(value),
            STYLE_ROUNDING => self.style.rounding = value,
            STYLE_WINDOW_ROUNDING => self.style.window_rounding = value,
            STYLE_SHADOW => self.style.shadow = @as(u8, @intCast(@min(value, 255))),
            STYLE_SPACING => self.style.spacing = value,
            STYLE_PADDING => self.style.padding = value,
            else => {},
        }
    }

    pub fn clear(self: *Renderer) void {
        self.canvas.fillRect(0, 0, self.canvas.fb.width, self.canvas.fb.height, self.style.bg);
    }

    pub fn resetDirty(self: *Renderer) void {
        self.canvas.resetDirty();
    }

    pub fn rect(self: *Renderer, x: i32, y: i32, w: u32, h: u32, color: u32) void {
        self.canvas.fillRect(x, y, w, h, color);
    }

    pub fn roundedRect(self: *Renderer, x: i32, y: i32, w: u32, h: u32, radius: u32, color: u32) void {
        self.canvas.fillRoundedRect(x, y, w, h, radius, color);
    }

    pub fn gradient(self: *Renderer, x: i32, y: i32, w: u32, h: u32, c1: u32, c2: u32, vertical: bool) void {
        if (w == 0 or h == 0) return;
        const steps = if (vertical) h else w;
        if (steps <= 1) {
            self.canvas.fillRect(x, y, w, h, c1);
            return;
        }
        const dr = @as(i32, @as(i8, @intCast(((c2 >> 16) & 0xFF) - ((c1 >> 16) & 0xFF))));
        const dg = @as(i32, @as(i8, @intCast(((c2 >> 8) & 0xFF) - ((c1 >> 8) & 0xFF))));
        const db = @as(i32, @as(i8, @intCast((c2 & 0xFF) - (c1 & 0xFF))));
        const da = @as(i32, @as(i8, @intCast(((c2 >> 24) & 0xFF) - ((c1 >> 24) & 0xFF))));
        const r0 = @as(i32, @as(u8, @intCast((c1 >> 16) & 0xFF)));
        const g0 = @as(i32, @as(u8, @intCast((c1 >> 8) & 0xFF)));
        const b0 = @as(i32, @as(u8, @intCast(c1 & 0xFF)));
        const a0 = @as(i32, @as(u8, @intCast((c1 >> 24) & 0xFF)));
        const step_scale = 65536 / steps;
        var i: u32 = 0;
        while (i < steps) : (i += 1) {
            const t = @as(i32, @intCast(i * step_scale));
            const r = @as(u32, @intCast(@max(0, @min(255, r0 + @divTrunc(dr * t, 65536)))));
            const g = @as(u32, @intCast(@max(0, @min(255, g0 + @divTrunc(dg * t, 65536)))));
            const b = @as(u32, @intCast(@max(0, @min(255, b0 + @divTrunc(db * t, 65536)))));
            const a = @as(u32, @intCast(@max(0, @min(255, a0 + @divTrunc(da * t, 65536)))));
            const col = (a << 24) | (r << 16) | (g << 8) | b;
            if (vertical) {
                self.canvas.fillRect(x, y + @as(i32, @intCast(i)), w, 1, col);
            } else {
                self.canvas.fillRect(x + @as(i32, @intCast(i)), y, 1, h, col);
            }
        }
        self.canvas.markDirty(x, y, w, h);
    }

    pub fn gradientU32(self: *Renderer, x: i32, y: i32, w: u32, h: u32, c1: u32, c2: u32, dir: u8) void {
        self.canvas.fillRectGradientDir(x, y, w, h, c1, c2, dir);
    }

    pub fn line(self: *Renderer, x1: i32, y1: i32, x2: i32, y2: i32, color: u32) void {
        self.canvas.drawLine(x1, y1, x2, y2, color);
    }

    pub fn circle(self: *Renderer, cx: i32, cy: i32, r: u32, color: u32) void {
        self.canvas.drawCircle(cx, cy, @as(i32, @intCast(r)), color);
    }

    pub fn triangle(self: *Renderer, x1: i32, y1: i32, x2: i32, y2: i32, x3: i32, y3: i32, color: u32) void {
        self.canvas.drawTriangleFilled(x1, y1, x2, y2, x3, y3, color);
    }

    pub fn bezier(self: *Renderer, x0: i32, y0: i32, x1: i32, y1: i32, x2: i32, y2: i32, color: u32) void {
        self.canvas.drawQuadBezier(x0, y0, x1, y1, x2, y2, color, 32);
    }

    pub fn setClip(self: *Renderer, x: i32, y: i32, w: u32, h: u32) void {
        self.canvas.setClip(x, y, w, h);
    }

    pub fn clearClip(self: *Renderer) void {
        self.canvas.clearClip();
    }

    pub fn text(self: *Renderer, x: i32, y: i32, label: []const u8, color: u32, size: u32) void {
        self.canvas.drawText(label, x, y, color, size);
    }

    pub fn panel(self: *Renderer, x: i32, y: i32, w: u32, h: u32) void {
        self.canvas.drawShadowSoft(x, y, w, h, self.style.shadow, self.style.window_rounding);
        self.softBox(x, y, w, h, self.style.panel_bg, self.style.border, false);
    }

    pub fn glassPanel(self: *Renderer, x: i32, y: i32, w: u32, h: u32, bg: u32, border: u32) void {
        self.canvas.fillRoundedRect(x, y, w, h, self.style.window_rounding, gfx.blendU32(bg, 0x40FFFFFF));
        self.canvas.drawBorder(x, y, w, h, border);
        self.canvas.fillRect(x + @as(i32, @intCast(self.style.window_rounding)), y, w - self.style.window_rounding * 2, 1, lightenColor(bg, 30));
    }

    pub fn button(self: *Renderer, x: i32, y: i32, w: u32, h: u32, label: []const u8, hovered: bool, active: bool) void {
        const raw_bg = if (active) self.style.button_active else if (hovered) self.style.button_hover else self.style.button_bg;
        const r = @min(self.style.rounding, @as(u32, @intCast(@min(w, h) / 2)));

        if (hovered or active) {
            self.canvas.drawShadowSoft(x, y, w, h, self.style.shadow, r);
        }
        self.canvas.fillRoundedRect(x, y, w, h, r, darkenColor(raw_bg, 10));
        self.canvas.fillRoundedRectGradV(x, y, w, h, r, raw_bg, darkenColor(raw_bg, 10));
        if (h > 6 and w > 6) {
            self.canvas.fillRect(x + 2, y + 1, w - 4, 1, lightenColor(raw_bg, 36));
        }
        if (active and w > r * 2 + 2) {
            self.canvas.fillRect(x + @as(i32, @intCast(r)), y + @as(i32, @intCast(h)) - 3, w - r * 2, 3, lightenColor(self.style.accent, 20));
        } else if (hovered and w > r * 2 + 2) {
            self.canvas.fillRect(x + @as(i32, @intCast(r)) + 6, y + @as(i32, @intCast(h)) - 2, w - r * 2 - 12, 2, mixColor(self.style.accent, raw_bg, 120));
        }
        const border = if (active) lightenColor(self.style.accent, 30) else if (hovered) self.style.accent else lightenColor(self.style.border, 10);
        self.canvas.drawBorder(x, y, w, h, border);
        if (active) {
            self.canvas.fillRect(x + 1, y + 1, w -| 2, 1, lightenColor(raw_bg, 14));
            self.canvas.fillRect(x + 1, y + 1, 1, h -| 2, lightenColor(raw_bg, 14));
            self.canvas.fillRect(x + 1, y + @as(i32, @intCast(h)) - 2, w -| 2, 1, darkenColor(raw_bg, 30));
            self.canvas.fillRect(x + @as(i32, @intCast(w)) - 2, y + 1, 1, h -| 2, darkenColor(raw_bg, 30));
        }

        const tw = @as(u32, @intCast(label.len * 8));
        self.canvas.drawText(
            label,
            x + @divTrunc(@as(i32, @intCast(w)) - @as(i32, @intCast(tw)), 2),
            y + @divTrunc(@as(i32, @intCast(h)) - 8, 2) + (if (active) @as(i32, 1) else @as(i32, 0)),
            if (active) lightenColor(self.style.button_text, 20) else self.style.button_text,
            8,
        );
    }

    pub fn slider(self: *Renderer, x: i32, y: i32, w: u32, value: f64, label: []const u8, hovered: bool) void {
        const sy = y + 16;
        const v = if (value < 0.0) 0.0 else if (value > 1.0) 1.0 else value;
        const track_h: u32 = 8;
        const thumb_w: u32 = 14;
        const thumb_h: u32 = 18;
        const fill_w = @as(u32, @intFromFloat(@as(f64, @floatFromInt(w)) * v));
        const thumb_x = x + @as(i32, @intCast(fill_w));
        const tr = @min(self.style.rounding, @as(u32, 4));

        self.canvas.drawShadowSoft(x - 1, sy + 1, w + 2, track_h, 8, tr);
        self.canvas.fillRoundedRect(x, sy, w, track_h, tr, darkenColor(self.style.slider_track, 24));
        self.canvas.fillRoundedRectGradV(x, sy, w, track_h, tr, darkenColor(self.style.slider_track, 10), darkenColor(self.style.slider_track, 24));
        if (fill_w > 0) {
            self.canvas.fillRoundedRect(x, sy, fill_w, track_h, tr, darkenColor(self.style.accent, 12));
            self.canvas.fillRoundedRectGradV(x, sy, fill_w, track_h, tr, lightenColor(self.style.accent, 18), darkenColor(self.style.accent, 12));
            self.canvas.fillRect(x + 2, sy + 1, fill_w -| 4, 1, lightenColor(self.style.accent, 32));
        }
        const hx = thumb_x - @divTrunc(@as(i32, @intCast(thumb_w)), 2);
        const hy = sy - @divTrunc(@as(i32, @intCast(thumb_h - track_h)), 2);
        self.canvas.drawShadowSoft(hx, hy, thumb_w, thumb_h, if (hovered) self.style.shadow else 12, tr + 2);
        self.canvas.fillRoundedRect(hx, hy, thumb_w, thumb_h, tr + 2, darkenColor(self.style.slider_thumb, 12));
        self.canvas.fillRoundedRectGradV(hx, hy, thumb_w, thumb_h, tr + 2, self.style.slider_thumb, darkenColor(self.style.slider_thumb, 12));
        self.canvas.fillRect(hx + 2, hy + 2, thumb_w - 4, 1, lightenColor(self.style.slider_thumb, 40));
        self.canvas.drawBorder(hx, hy, thumb_w, thumb_h, if (hovered) self.style.accent_hover else lightenColor(self.style.border, 8));

        self.canvas.drawText(label, x, y, if (hovered) self.style.text else self.style.text_dim, 8);
    }

    pub fn checkbox(self: *Renderer, x: i32, y: i32, label: []const u8, checked: bool, hovered: bool) void {
        const cw: u32 = 20;
        const ch: u32 = 20;
        const r = @min(self.style.rounding, @as(u32, 4));
        const box_bg = if (checked) mixColor(self.style.check_bg, self.style.accent, 160) else if (hovered) lightenColor(self.style.check_bg, 28) else self.style.check_bg;

        if (checked) {
            self.canvas.drawShadowSoft(x, y, cw, ch, 8, r);
        }
        self.canvas.fillRoundedRect(x, y, cw, ch, r, darkenColor(box_bg, 10));
        self.canvas.fillRoundedRectGradV(x, y, cw, ch, r, box_bg, darkenColor(box_bg, 10));
        self.canvas.fillRect(x + 2, y + 1, cw - 4, 1, lightenColor(box_bg, 30));
        const border = if (checked) lightenColor(self.style.accent, 16) else if (hovered) self.style.accent else self.style.border;
        self.canvas.drawBorder(x, y, cw, ch, border);

        if (checked) {
            const mark = lightenColor(self.style.check_mark, 18);
            self.canvas.drawLine(x + 5, y + 10, x + 8, y + 13, mark);
            self.canvas.drawLine(x + 6, y + 10, x + 9, y + 13, mark);
            self.canvas.drawLine(x + 8, y + 13, x + 15, y + 5, mark);
            self.canvas.drawLine(x + 9, y + 13, x + 16, y + 5, mark);
        }
        self.canvas.drawText(label, x + @as(i32, @intCast(cw)) + 6, y + (@as(i32, @intCast(ch)) - 8) / 2, if (hovered) self.style.text else self.style.text_dim, 8);
    }

    pub fn softBox(self: *Renderer, x: i32, y: i32, w: u32, h: u32, bg: u32, border: u32, accent: bool) void {
        const r = self.style.window_rounding;
        if (r > 0 and w >= r * 2 and h >= r * 2) {
            self.canvas.fillRoundedRect(x, y, w, h, r, darkenColor(bg, 8));
            self.canvas.fillRoundedRectGradV(x, y, w, h, r, bg, darkenColor(bg, 8));
            self.canvas.fillRect(x + @as(i32, @intCast(r)) + 2, y + 1, w - r * 2 - 4, 1, lightenColor(bg, 22));
            if (accent and w > 12) {
                self.canvas.fillRect(x + @as(i32, @intCast(r)) + 4, y + @as(i32, @intCast(h)) - 3, w - r * 2 - 8, 3, lightenColor(self.style.accent, 20));
            }
        } else {
            self.canvas.fillRoundedRectGradV(x, y, w, h, 0, bg, darkenColor(bg, 8));
            self.canvas.fillRect(x + 2, y + 1, w - 4, 1, lightenColor(bg, 22));
            if (accent and w > 12) {
                self.canvas.fillRect(x + 4, y + @as(i32, @intCast(h)) - 3, w - 8, 3, lightenColor(self.style.accent, 20));
            }
        }
        self.canvas.drawBorder(x, y, w, h, border);
        self.canvas.fillRect(x + 1, y + 1, w -| 2, 1, lightenColor(bg, 18));
        self.canvas.fillRect(x + 1, y + 1, 1, h -| 2, lightenColor(bg, 18));
        self.canvas.fillRect(x + 1, y + @as(i32, @intCast(h)) - 2, w -| 2, 1, darkenColor(bg, 38));
        self.canvas.fillRect(x + @as(i32, @intCast(w)) - 2, y + 1, 1, h -| 2, darkenColor(bg, 38));
    }

    pub fn drawBorder(self: *Renderer, x: i32, y: i32, w: u32, h: u32, color: u32) void {
        self.canvas.drawBorder(x, y, w, h, color);
    }

    pub fn shadow(self: *Renderer, x: i32, y: i32, w: u32, h: u32, intensity: u8) void {
        self.canvas.drawShadowSoft(x, y, w, h, intensity, @min(self.style.rounding, 4));
    }
};

pub fn colorR(c: u32) u8 {
    return @as(u8, @intCast((c >> 16) & 0xFF));
}
pub fn colorG(c: u32) u8 {
    return @as(u8, @intCast((c >> 8) & 0xFF));
}
pub fn colorB(c: u32) u8 {
    return @as(u8, @intCast(c & 0xFF));
}
pub fn colorA(c: u32) u8 {
    return @as(u8, @intCast((c >> 24) & 0xFF));
}

pub fn blendU32(dst: u32, src: u32) u32 {
    const sa = (src >> 24) & 0xFF;
    if (sa == 255) return src;
    if (sa == 0) return dst;
    const da = (dst >> 24) & 0xFF;
    const out_a = sa + da * (255 - sa) / 255;
    if (out_a == 0) return 0;
    const sr = (src >> 16) & 0xFF;
    const sg = (src >> 8) & 0xFF;
    const sb = src & 0xFF;
    const dr = (dst >> 16) & 0xFF;
    const dg = (dst >> 8) & 0xFF;
    const db = dst & 0xFF;
    const r = (sr * sa * 255 + dr * da * (255 - sa)) / (out_a * 255);
    const g = (sg * sa * 255 + dg * da * (255 - sa)) / (out_a * 255);
    const b = (sb * sa * 255 + db * da * (255 - sa)) / (out_a * 255);
    return (out_a << 24) | (r << 16) | (g << 8) | b;
}

pub fn mixColor(a: u32, b: u32, amount_b: u8) u32 {
    const ib = @as(u32, amount_b);
    const ia = 255 - ib;
    const ar = (a >> 16) & 0xFF;
    const ag = (a >> 8) & 0xFF;
    const ab = a & 0xFF;
    const aa = (a >> 24) & 0xFF;
    const br = (b >> 16) & 0xFF;
    const bg = (b >> 8) & 0xFF;
    const bb = b & 0xFF;
    const ba = (b >> 24) & 0xFF;
    const r = (ar * ia + br * ib) / 255;
    const g = (ag * ia + bg * ib) / 255;
    const bl = (ab * ia + bb * ib) / 255;
    const al = (aa * ia + ba * ib) / 255;
    return (al << 24) | (r << 16) | (g << 8) | bl;
}

pub fn lightenColor(c: u32, amount: u8) u32 {
    return mixColor(c, 0xFFFFFFFF, amount);
}
pub fn darkenColor(c: u32, amount: u8) u32 {
    return mixColor(c, 0xFF000000, amount);
}

pub fn fillRect(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, color: u32) void {
    if (w == 0 or h == 0) return;
    const raw_x2 = x + @as(i32, @intCast(w));
    const raw_y2 = y + @as(i32, @intCast(h));
    if (raw_x2 <= 0 or raw_y2 <= 0) return;
    const x1: u32 = if (x < 0) 0 else @intCast(x);
    const y1: u32 = if (y < 0) 0 else @intCast(y);
    const x2: u32 = @min(@as(u32, @intCast(raw_x2)), fb.width);
    const y2: u32 = @min(@as(u32, @intCast(raw_y2)), fb.height);
    if (x2 <= x1 or y2 <= y1) return;
    const uw = x2 - x1;
    var yi = y1;
    while (yi < y2) : (yi += 1) {
        const row = @as(usize, yi) * fb.stride + x1;
        @memset(fb.pixels[row .. row + uw], color);
    }
}

pub fn fillRoundedRect(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, radius: u32, color: u32) void {
    if (radius == 0 or w < radius * 2 or h < radius * 2) {
        fillRect(fb, x, y, w, h, color);
        return;
    }
    const r = @min(radius, @min(w, h) / 2);
    fillRect(fb, x + @as(i32, @intCast(r)), y, w - r * 2, h, color);
    fillRect(fb, x, y + @as(i32, @intCast(r)), r, h - r * 2, color);
    fillRect(fb, x + @as(i32, @intCast(w - r)), y + @as(i32, @intCast(r)), r, h - r * 2, color);
    const rr = @as(i32, @intCast(r));
    const rr1 = rr - 1;
    const r2 = rr1 * rr1;
    var dy: i32 = 0;
    while (dy <= rr1) : (dy += 1) {
        const ody = rr1 - dy;
        const ody2 = ody * ody;
        var dx: i32 = 0;
        while (dx <= rr1) : (dx += 1) {
            const odx = rr1 - dx;
            if (odx * odx + ody2 <= r2) {
                const px1 = x + rr1 - dx;
                const px2 = x + @as(i32, @intCast(w)) - rr + dx;
                const py1 = y + rr1 - dy;
                const py2 = y + @as(i32, @intCast(h)) - rr + dy;
                putPixel(fb, px1, py1, color);
                putPixel(fb, px2, py1, color);
                putPixel(fb, px1, py2, color);
                putPixel(fb, px2, py2, color);
            }
        }
    }
}

pub fn fillRoundedRectGradV(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, r: u32, top: u32, bot: u32) void {
    fillRoundedRect(fb, x, y, w, h, r, bot);
    if (h < 4 or w < 4) return;
    const shine_h = h / 2 + r;
    fillRectGradientDir(fb, x + @as(i32, @intCast(r)), y, w -| r * 2, shine_h, top, bot, 0);
    fillRectGradientDir(fb, x, y + @as(i32, @intCast(r)), @as(u32, @intCast(r)), @as(u32, @intCast(@max(0, @as(i32, @intCast(shine_h)) - @as(i32, @intCast(r))))), top, bot, 0);
    fillRectGradientDir(fb, x + @as(i32, @intCast(w)) - @as(i32, @intCast(r)), y + @as(i32, @intCast(r)), @as(u32, @intCast(r)), @as(u32, @intCast(@max(0, @as(i32, @intCast(shine_h)) - @as(i32, @intCast(r))))), top, bot, 0);
}

pub fn drawShadowSoft(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, intensity: u8, r: u32) void {
    if (intensity < 6) return;
    const a1 = intensity / 3;
    const a2 = intensity / 5;
    const a3 = intensity / 9;
    const c1: u32 = (@as(u32, a1) << 24) | (@as(u32, a1 / 3) << 16) | (@as(u32, a1 / 4) << 8) | @as(u32, a1 / 6);
    const c2: u32 = (@as(u32, a2) << 24) | (@as(u32, a2 / 3) << 16) | (@as(u32, a2 / 4) << 8) | @as(u32, a2 / 6);
    const c3: u32 = (@as(u32, a3) << 24) | (@as(u32, a3 / 3) << 16) | (@as(u32, a3 / 4) << 8) | @as(u32, a3 / 6);
    const sr1 = if (r > 1) r - 1 else 0;
    const sr2 = if (r > 2) r - 2 else 0;
    const sr3 = if (r > 3) r - 3 else 0;
    fillRoundedRect(fb, x + 1, y + 2, w, h, sr3, c3);
    fillRoundedRect(fb, x + 2, y + 2, w, h, sr2, c2);
    fillRoundedRect(fb, x + 3, y + 3, w, h, sr1, c1);
}

pub fn drawInsetBorder(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, light: u32, dark: u32) void {
    if (w < 2 or h < 2) return;
    fillRect(fb, x, y, w -| 1, 1, light);
    fillRect(fb, x, y, 1, h -| 1, light);
    fillRect(fb, x + @as(i32, @intCast(w)) - 1, y, 1, h, dark);
    fillRect(fb, x, y + @as(i32, @intCast(h)) - 1, w, 1, dark);
}

pub fn drawLineRaw(fb: *gfx.Framebuffer, x1: i32, y1: i32, x2: i32, y2: i32, color: u32) void {
    const dx: i32 = if (x2 >= x1) x2 - x1 else x1 - x2;
    const dy_abs: i32 = if (y2 >= y1) y2 - y1 else y1 - y2;
    const dy: i32 = -dy_abs;
    const sx: i32 = if (x1 < x2) 1 else -1;
    const sy: i32 = if (y1 < y2) 1 else -1;
    var err = dx + dy;
    var cx = x1;
    var cy = y1;
    while (true) {
        putPixel(fb, cx, cy, color);
        if (cx == x2 and cy == y2) break;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            cx += sx;
        }
        if (e2 <= dx) {
            err += dx;
            cy += sy;
        }
    }
}

pub fn drawCircle(fb: *gfx.Framebuffer, cx: i32, cy: i32, r: i32, color: u32) void {
    var dy = -r;
    while (dy <= r) : (dy += 1) {
        var dx = -r;
        while (dx <= r) : (dx += 1) {
            if (dx * dx + dy * dy <= r * r) putPixel(fb, cx + dx, cy + dy, color);
        }
    }
}

pub fn drawTriangleFilled(fb: *gfx.Framebuffer, x1: i32, y1: i32, x2: i32, y2: i32, x3: i32, y3: i32, color: u32) void {
    const min_y = @min(y1, @min(y2, y3));
    const max_y = @max(y1, @max(y2, y3));
    var py = min_y;
    while (py <= max_y) : (py += 1) {
        var intersections: [3]i32 = undefined;
        var count: u32 = 0;

        const segments = [_][4]i32{
            .{ x1, y1, x2, y2 },
            .{ x2, y2, x3, y3 },
            .{ x3, y3, x1, y1 },
        };
        for (segments) |seg| {
            const ex1 = seg[0];
            const ey1 = seg[1];
            const ex2 = seg[2];
            const ey2 = seg[3];
            if (ey1 == ey2) continue;
            if ((py < ey1 and py < ey2) or (py > ey1 and py > ey2)) continue;
            const ix = ex1 + @divFloor((py - ey1) * (ex2 - ex1), (ey2 - ey1));
            if (count < 3) {
                intersections[count] = ix;
                count += 1;
            }
        }
        if (count < 2) continue;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            var j: u32 = i + 1;
            while (j < count) : (j += 1) {
                if (intersections[i] > intersections[j]) {
                    const t = intersections[i];
                    intersections[i] = intersections[j];
                    intersections[j] = t;
                }
            }
        }
        var px = intersections[0];
        while (px <= intersections[1]) : (px += 1) {
            putPixel(fb, px, py, color);
        }
    }
}

pub fn fillRectGradientDir(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, c1: u32, c2: u32, dir: u8) void {
    if (w == 0 or h == 0) return;
    const dr = @as(i32, @as(i8, @intCast(((c2 >> 16) & 0xFF) - ((c1 >> 16) & 0xFF))));
    const dg = @as(i32, @as(i8, @intCast(((c2 >> 8) & 0xFF) - ((c1 >> 8) & 0xFF))));
    const db = @as(i32, @as(i8, @intCast((c2 & 0xFF) - (c1 & 0xFF))));
    const da = @as(i32, @as(i8, @intCast(((c2 >> 24) & 0xFF) - ((c1 >> 24) & 0xFF))));
    const r0 = @as(i32, @as(u8, @intCast((c1 >> 16) & 0xFF)));
    const g0 = @as(i32, @as(u8, @intCast((c1 >> 8) & 0xFF)));
    const b0 = @as(i32, @as(u8, @intCast(c1 & 0xFF)));
    const a0 = @as(i32, @as(u8, @intCast((c1 >> 24) & 0xFF)));
    const steps = if (dir == 0) @as(u32, h) else @as(u32, w);
    if (steps == 0) return;
    const one_div_steps = 65536 / steps;
    var si: u32 = 0;
    while (si < steps) : (si += 1) {
        const t = si * one_div_steps;
        const tr = r0 + @divTrunc(dr * @as(i32, @intCast(t)), 65536);
        const tg = g0 + @divTrunc(dg * @as(i32, @intCast(t)), 65536);
        const tb = b0 + @divTrunc(db * @as(i32, @intCast(t)), 65536);
        const ta = a0 + @divTrunc(da * @as(i32, @intCast(t)), 65536);
        const col: u32 = (@as(u32, @intCast(ta)) << 24) | (@as(u32, @intCast(tr)) << 16) | (@as(u32, @intCast(tg)) << 8) | @as(u32, @intCast(tb));
        if (dir == 0) {
            fillRect(fb, x, y + @as(i32, @intCast(si)), w, 1, col);
        } else {
            fillRect(fb, x + @as(i32, @intCast(si)), y, 1, h, col);
        }
    }
}

pub fn drawText(fb: *gfx.Framebuffer, text: []const u8, x: i32, y: i32, color: u32, size: u32) void {
    const scale = if (size >= 8) @as(u32, @intCast(@divFloor(size, 8))) else 1;
    var cx = x;
    var cy = y;
    for (text) |ch| {
        if (ch == '\n') {
            cy += @as(i32, @intCast(scale * 8 + 2));
            cx = x;
            continue;
        }
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
                            putPixel(fb, bx + @as(i32, @intCast(sx)), by + @as(i32, @intCast(sy)), color);
                        }
                    }
                }
            }
        }
        cx += @as(i32, @intCast(scale * 8 + 2));
    }
}

pub fn hit(mouse: *const mouse_mod.State, x: i32, y: i32, w: u32, h: u32) bool {
    return mouse.hit(mouse_mod.rect(x, y, w, h));
}

fn putPixel(fb: *gfx.Framebuffer, x: i32, y: i32, color: u32) void {
    if (x < 0 or y < 0) return;
    const ux = @as(u32, @intCast(x));
    const uy = @as(u32, @intCast(y));
    if (ux >= fb.width or uy >= fb.height) return;
    fb.pixels[@as(usize, uy) * fb.stride + ux] = color;
}
