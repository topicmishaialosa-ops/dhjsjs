const gfx = @import("render.zig");
const utils = @import("utils.zig");

const MAX_FILENAME = 256;
const MAX_CONTENT = 65536;
const MAX_CONSOLE = 8192;

// ── Arduino IDE-inspired palette (dark) ──
const MENU_BG = gfx.rgb(51, 51, 51);
const MENU_TEXT = gfx.rgb(200, 200, 200);
const TOOL_BG = gfx.rgb(60, 60, 60);
const TOOL_TEXT = gfx.rgb(180, 200, 180);
const TAB_BG = gfx.rgb(45, 45, 45);
const TAB_ACTIVE = gfx.rgb(30, 30, 30);
const TAB_ACCENT = gfx.rgb(0, 151, 157);
const EDITOR_BG = gfx.rgb(30, 30, 30);
const GUTTER_BG = gfx.rgb(38, 38, 38);
const GUTTER_LINE = gfx.rgb(50, 50, 50);
const CUR_LINE_BG = gfx.rgb(44, 44, 44);
const CONSOLE_BG = gfx.rgb(24, 24, 24);
const CONSOLE_TEXT = gfx.rgb(120, 190, 130);
const STATUS_BG = gfx.rgb(51, 51, 51);
const STATUS_TEXT = gfx.rgb(160, 160, 160);
const TEXT_COL = gfx.rgb(230, 230, 230);
const NUML_COL = gfx.rgb(100, 100, 100);
const NUML_CUR = gfx.rgb(200, 200, 200);
const SCROLL_THUMB = gfx.rgb(70, 70, 70);
const MODIFIED_COL = gfx.rgb(255, 180, 50);

fn isKw(s: []const u8) bool {
    const words = [_][]const u8{ "fn", "let", "if", "else", "return", "while", "activity", "compose", "state", "viewmodel", "true", "false", "null", "int", "string", "bool", "void" };
    for (words) |w| { if (utils.sliceEql(s, w)) return true; }
    return false;
}

const HL_KEYWORD: u8 = 0;
const HL_STRING: u8 = 1;
const HL_NUMBER: u8 = 2;
const HL_COMMENT: u8 = 3;
const HL_NORMAL: u8 = 4;
const HL_FUNC: u8 = 5;

fn fontScale(w: u32) u32 {
    const raw = @divFloor(@min(w, 3600), 600);
    if (raw < 1) return 1;
    if (raw > 3) return 3;
    return raw;
}

fn highlightLine(line: []const u8, buf: []u8) void {
    var i: usize = 0;
    while (i < line.len and i < buf.len) {
        if (line[i] == '"') {
            buf[i] = HL_STRING;
            i += 1;
            while (i < line.len and line[i] != '"') : (i += 1) buf[i] = HL_STRING;
            if (i < line.len) { buf[i] = HL_STRING; i += 1; }
        } else if (line[i] == '/' and i + 1 < line.len and line[i + 1] == '/') {
            while (i < line.len and i < buf.len) : (i += 1) buf[i] = HL_COMMENT;
        } else if (utils.isAlpha(line[i]) or line[i] == '_') {
            const start = i;
            while (i < line.len and utils.isAlphaNum(line[i])) : (i += 1) {}
            const t = isKw(line[start..i]);
            var k = start;
            while (k < i and k < buf.len) : (k += 1) buf[k] = if (t) HL_KEYWORD else HL_FUNC;
        } else if (utils.isDigit(line[i])) {
            buf[i] = HL_NUMBER;
            i += 1;
        } else {
            buf[i] = HL_NORMAL;
            i += 1;
        }
    }
}

fn fmtU32(val: u32, buf: []u8) []const u8 {
    var tmp: [16]u8 = undefined;
    var i: usize = 0;
    var n = val;
    if (n == 0) {
        buf[0] = '0';
        return buf[0..1];
    }
    while (n > 0) : (n /= 10) {
        tmp[i] = @as(u8, @intCast(n % 10)) + '0';
        i += 1;
    }
    var j: usize = 0;
    while (j < i) : (j += 1) {
        buf[j] = tmp[i - 1 - j];
    }
    return buf[0..i];
}

pub const IdeState = struct {
    filename: [MAX_FILENAME]u8,
    flen: usize,
    content: [MAX_CONTENT]u8,
    clen: usize,
    cx: usize,
    cy: usize,
    modified: bool,
    cursor_on: bool,
    frame_count: usize,
    status: [64]u8,
    status_len: usize,
    console: [MAX_CONSOLE]u8,
    con_len: usize,
    request_build: bool,
    input_mode: bool,
    input_action: u8, // 'o'=open, 's'=save
    input_buf: [256]u8,
    input_len: usize,

    pub fn init() IdeState {
        return IdeState{
            .filename = undefined,
            .flen = 0,
            .content = undefined,
            .clen = 0,
            .cx = 0,
            .cy = 0,
            .modified = false,
            .cursor_on = true,
            .frame_count = 0,
            .status = undefined,
            .status_len = 0,
            .console = undefined,
            .con_len = 0,
            .request_build = false,
            .input_mode = false,
            .input_action = 0,
            .input_buf = undefined,
            .input_len = 0,
        };
    }

    pub fn setContent(self: *IdeState, src: []const u8) void {
        var i: usize = 0;
        while (i < src.len and i < MAX_CONTENT) : (i += 1) self.content[i] = src[i];
        self.clen = src.len;
        self.cx = 0;
        self.cy = 0;
        self.modified = false;
    }

    pub fn setStatus(self: *IdeState, msg: []const u8) void {
        var i: usize = 0;
        while (i < msg.len and i < 63) : (i += 1) self.status[i] = msg[i];
        self.status_len = msg.len;
    }

    pub fn addConsole(self: *IdeState, msg: []const u8) void {
        var i: usize = 0;
        while (i < msg.len and self.con_len < MAX_CONSOLE - 1) : (i += 1) {
            self.console[self.con_len] = msg[i];
            self.con_len += 1;
        }
    }

    pub fn openFile(self: *IdeState, filepath: []const u8) void {
        const sys = @import("sys.zig");
        var path: [MAX_FILENAME]u8 = undefined;
        var pi: usize = 0;
        while (pi < filepath.len and pi < MAX_FILENAME - 1) : (pi += 1) path[pi] = filepath[pi];
        path[pi] = 0;
        const fd = sys.open(&path, 0, 0);
        if (fd < 0) { self.setStatus("open failed"); return; }
        var total: usize = 0;
        while (total < MAX_CONTENT) {
            const n = sys.read(fd, self.content[total..].ptr, MAX_CONTENT - total);
            if (n <= 0) break;
            total += @as(usize, @intCast(n));
        }
        sys.close(fd);
        if (total == 0) { self.setStatus("empty"); return; }
        self.clen = total;
        self.cx = 0;
        self.cy = 0;
        self.modified = false;
        var fi: usize = 0;
        while (fi < filepath.len and fi < MAX_FILENAME - 1) : (fi += 1) self.filename[fi] = filepath[fi];
        self.flen = filepath.len;
        self.setStatus("opened");
    }

    pub fn saveFile(self: *IdeState) void {
        if (self.flen == 0) {
            self.startInput("save");
            return;
        }
        const sys = @import("sys.zig");
        var path: [MAX_FILENAME]u8 = undefined;
        var pi: usize = 0;
        while (pi < self.flen and pi < MAX_FILENAME - 1) : (pi += 1) path[pi] = self.filename[pi];
        path[pi] = 0;
        const fd = sys.open(&path, sys.O_RDWR | 0x40 | 0x200, 0x1A4);
        if (fd < 0) { self.setStatus("save failed"); return; }
        _ = sys.write(fd, @as([*]const u8, &self.content), self.clen);
        sys.close(fd);
        self.modified = false;
        self.setStatus("saved");
    }

    // ── layout ─────────────────────────────────────────────
    fn Layout(T: type) type {
        return struct {
            sc: T,
            ch_w: T,
            ch_h: T,
            menu_h: T,
            tool_h: T,
            tab_h: T,
            gutter_w: T,
            margin_x: T,
            top_y: T,
            con_h: T,
            status_h: T,
            ed_h: T,
        };
    }

    fn layout(fb: *const gfx.Framebuffer) Layout(u32) {
        const sc = fontScale(fb.width);
        const ch_w = sc * 8;
        const ch_h = sc * 8 + 4;
        const menu_h = ch_h;
        const tool_h = ch_h;
        const tab_h = ch_h;
        const gutter_w = ch_w * 5 + 14;
        const margin_x = gutter_w;
        const top_y = menu_h + tool_h + tab_h;
        const status_h = ch_h;
        const avail = if (fb.height > top_y + status_h) fb.height - top_y - status_h else 0;
        const con_h = avail / 4;
        const ed_h = if (avail > con_h) avail - con_h else 0;
        return .{ .sc = sc, .ch_w = ch_w, .ch_h = ch_h, .menu_h = menu_h, .tool_h = tool_h, .tab_h = tab_h, .gutter_w = gutter_w, .margin_x = margin_x, .top_y = top_y, .con_h = con_h, .status_h = status_h, .ed_h = ed_h };
    }

    // ── paint ───────────────────────────────────────────────
    pub fn paint(self: *IdeState, fb: *gfx.Framebuffer) void {
        self.frame_count +%= 1;
        const blink_rate = if (fontScale(fb.width) >= 2) @as(usize, 30) else @as(usize, 15);
        self.cursor_on = (self.frame_count / blink_rate) % 2 == 0;
        fb.fill(EDITOR_BG);
        self.drawMenu(fb);
        self.drawToolbar(fb);
        self.drawTabBar(fb);
        self.drawGutter(fb);
        self.drawLines(fb);
        self.drawCursor(fb);
        if (self.input_mode) self.drawInputPrompt(fb);
        self.drawConsole(fb);
        self.drawStatus(fb);
    }

    fn drawMenu(_: *IdeState, fb: *gfx.Framebuffer) void {
        const L = layout(fb);
        fb.fillRect(gfx.Rect{ .x = 0, .y = 0, .w = fb.width, .h = L.menu_h }, MENU_BG);
        fb.fillRect(gfx.Rect{ .x = 0, .y = @as(i32, @intCast(L.menu_h - 1)), .w = fb.width, .h = 1 }, GUTTER_LINE);
        fb.drawText("File  Edit  Sketch  Tools  Help", 8, @as(i32, @intCast((L.menu_h - L.ch_h) / 2)), MENU_TEXT, L.ch_w);
    }

    fn drawToolbar(_: *IdeState, fb: *gfx.Framebuffer) void {
        const L = layout(fb);
        const y0 = @as(i32, @intCast(L.menu_h));
        fb.fillRect(gfx.Rect{ .x = 0, .y = y0, .w = fb.width, .h = L.tool_h }, TOOL_BG);
        fb.fillRect(gfx.Rect{ .x = 0, .y = y0 + @as(i32, @intCast(L.tool_h - 1)), .w = fb.width, .h = 1 }, GUTTER_LINE);
        fb.drawText(" [Verify]  [Upload]  [New]  [Open]  [Save] ", 8, y0 + @as(i32, @intCast((L.tool_h - L.ch_h) / 2)), TOOL_TEXT, L.ch_w);
    }

    fn drawTabBar(self: *IdeState, fb: *gfx.Framebuffer) void {
        const L = layout(fb);
        const y0 = @as(i32, @intCast(L.menu_h + L.tool_h));
        fb.fillRect(gfx.Rect{ .x = 0, .y = y0, .w = fb.width, .h = L.tab_h }, TAB_BG);
        fb.fillRect(gfx.Rect{ .x = 0, .y = y0 + @as(i32, @intCast(L.tab_h - 1)), .w = fb.width, .h = 1 }, GUTTER_LINE);

        const title = if (self.flen > 0) self.filename[0..self.flen] else "untitled.dhjsjs";
        const tab_w = @as(u32, @intCast(@min(@as(usize, L.ch_w * 20), @as(usize, L.ch_w * 2 + @as(u32, @intCast(title.len)) * L.ch_w))));

        fb.fillRect(gfx.Rect{ .x = 0, .y = y0, .w = tab_w, .h = L.tab_h }, TAB_ACTIVE);
        fb.fillRect(gfx.Rect{ .x = 0, .y = y0 + @as(i32, @intCast(L.tab_h - 2)), .w = tab_w, .h = 2 }, TAB_ACCENT);

        const ty2 = y0 + @as(i32, @intCast((L.tab_h - L.ch_h) / 2));
        var xp: i32 = 8;
        if (self.modified) {
            fb.drawText("\xE2\x97\x8B", xp, ty2, MODIFIED_COL, L.ch_w);
            xp += @as(i32, @intCast(L.ch_w));
        }
        const max_chars = (tab_w - @as(u32, @intCast(xp))) / L.ch_w;
        const display = if (title.len > max_chars) title[0..max_chars] else title;
        fb.drawText(display, xp, ty2, TEXT_COL, L.ch_w);
    }

    fn colorForHL(h: u8) gfx.Color {
        return switch (h) {
            HL_KEYWORD => gfx.rgb(86, 156, 214),
            HL_STRING => gfx.rgb(206, 145, 120),
            HL_NUMBER => gfx.rgb(181, 206, 168),
            HL_COMMENT => gfx.rgb(106, 153, 85),
            HL_FUNC => gfx.rgb(220, 220, 170),
            else => TEXT_COL,
        };
    }

    fn drawGutter(_: *IdeState, fb: *gfx.Framebuffer) void {
        const L = layout(fb);
        const con_top = @as(i32, @intCast(L.top_y + L.ed_h));
        fb.fillRect(gfx.Rect{ .x = 0, .y = @as(i32, @intCast(L.top_y)), .w = L.gutter_w, .h = L.ed_h }, GUTTER_BG);
        fb.fillRect(gfx.Rect{ .x = @as(i32, @intCast(L.gutter_w - 1)), .y = @as(i32, @intCast(L.top_y)), .w = 1, .h = @as(u32, @intCast(con_top - @as(i32, @intCast(L.top_y)))) }, GUTTER_LINE);
    }

    fn drawLines(self: *IdeState, fb: *gfx.Framebuffer) void {
        const L = layout(fb);
        var y: u32 = L.top_y;
        var line: usize = 0;
        var i: usize = 0;
        var line_start: usize = 0;

        while (i <= self.clen and y + L.ch_h <= L.top_y + L.ed_h) : (i += 1) {
            if (i == self.clen or self.content[i] == '\n') {
                line += 1;
                if (line > 0) {
                    const is_current = line == self.cy + 1;
                    if (is_current) {
                        fb.fillRect(gfx.Rect{ .x = @as(i32, @intCast(L.margin_x)), .y = @as(i32, @intCast(y)), .w = fb.width - L.margin_x, .h = L.ch_h }, CUR_LINE_BG);
                    }
                    var nb: [16]u8 = undefined;
                    const ns = fmtU32(@as(u32, @intCast(line)), nb[0..]);
                    fb.drawText(ns, @as(i32, @intCast(L.margin_x - L.ch_w * 4 - 8)), @as(i32, @intCast(y)), if (is_current) NUML_CUR else NUML_COL, L.ch_w);
                }
                const text = self.content[line_start..i];
                if (text.len > 0) {
                    const max_vis = @as(usize, @intCast((fb.width - L.margin_x) / L.ch_w));
                    const vis = if (text.len > max_vis) text[0..max_vis] else text;
                    var hl: [512]u8 = undefined;
                    const hl_len = @min(vis.len, hl.len);
                    highlightLine(vis, hl[0..hl_len]);
                    var cx: i32 = @as(i32, @intCast(L.margin_x));
                    var ci: usize = 0;
                    while (ci < hl_len) : (ci += 1) {
                        const g = gfx.getGlyph(vis[ci]);
                        if (vis[ci] == '\t') {
                            cx += @as(i32, @intCast(L.ch_w)) * 3;
                        } else if (vis[ci] >= 32) {
                            fb.drawGlyphScaled(g, cx, @as(i32, @intCast(y)), gfx.colorToU32(colorForHL(hl[ci])), L.sc);
                            cx += @as(i32, @intCast(L.ch_w));
                        } else {
                            cx += @as(i32, @intCast(L.ch_w));
                        }
                    }
                }
                y += L.ch_h;
                line_start = i + 1;
            }
        }

        const total = @as(u32, @intCast(self.totalLines()));
        if (total > 0 and L.ed_h > L.ch_h) {
            const vis_lines = L.ed_h / L.ch_h;
            const thumb_h = @max(@as(u32, 6), L.ed_h * vis_lines / total);
            const thumb_y = L.top_y + L.ed_h * @as(u32, @intCast(self.cy)) / total;
            fb.fillRect(gfx.Rect{ .x = @as(i32, @intCast(fb.width - 5)), .y = @as(i32, @intCast(thumb_y)), .w = 5, .h = @min(thumb_h, L.ed_h) }, SCROLL_THUMB);
        }
    }

    fn drawCursor(self: *IdeState, fb: *gfx.Framebuffer) void {
        if (!self.cursor_on or self.input_mode) return;
        const L = layout(fb);
        const x = @as(i32, @intCast(L.margin_x)) + @as(i32, @intCast(self.cx)) * @as(i32, @intCast(L.ch_w));
        const y = @as(i32, @intCast(L.top_y)) + @as(i32, @intCast(self.cy)) * @as(i32, @intCast(L.ch_h));
        if (y + @as(i32, @intCast(L.ch_h)) <= @as(i32, @intCast(L.top_y + L.ed_h))) {
            fb.fillRect(gfx.Rect{ .x = x, .y = y, .w = @as(u32, @intCast(@max(@as(i32, @intCast(L.sc)), 2))), .h = L.ch_h }, TEXT_COL);
        }
    }

    fn drawInputPrompt(self: *IdeState, fb: *gfx.Framebuffer) void {
        const L = layout(fb);
        const y = @as(i32, @intCast(L.top_y + L.ed_h - L.ch_h));
        fb.fillRect(gfx.Rect{ .x = @as(i32, @intCast(L.margin_x)), .y = y, .w = fb.width - L.margin_x, .h = L.ch_h }, gfx.rgb(20, 40, 45));
        const prompt = if (self.input_action == 's') "Save: " else "Open: ";
        const plen: i32 = if (self.input_action == 's') 6 else 6;
        fb.drawText(prompt, @as(i32, @intCast(L.margin_x + 4)), y, TAB_ACCENT, L.ch_w);
        const path = self.input_buf[0..self.input_len];
        const maxc = @as(usize, @intCast((fb.width - L.margin_x - 4) / L.ch_w - @as(u32, @intCast(plen))));
        const display = if (path.len > maxc) path[path.len - maxc ..] else path;
        fb.drawText(display, @as(i32, @intCast(L.margin_x + 4)) + @as(i32, @intCast(L.ch_w * @as(u32, @intCast(plen)))), y, TEXT_COL, L.ch_w);
        if (self.cursor_on) {
            fb.fillRect(gfx.Rect{ .x = @as(i32, @intCast(L.margin_x + 4)) + @as(i32, @intCast(L.ch_w * @as(u32, @intCast(plen)))) + @as(i32, @intCast(display.len * L.ch_w)), .y = y, .w = 2, .h = L.ch_h }, TEXT_COL);
        }
    }

    fn drawConsole(self: *IdeState, fb: *gfx.Framebuffer) void {
        const L = layout(fb);
        const con_top = L.top_y + L.ed_h;
        fb.fillRect(gfx.Rect{ .x = 0, .y = @as(i32, @intCast(con_top)), .w = fb.width, .h = L.con_h }, CONSOLE_BG);
        fb.fillRect(gfx.Rect{ .x = 0, .y = @as(i32, @intCast(con_top - 1)), .w = fb.width, .h = 1 }, GUTTER_LINE);

        const max_lines = if (L.ch_h > 0) L.con_h / L.ch_h else 1;
        const total = self.conLines();
        const skip = if (total > max_lines) total - max_lines else @as(usize, 0);

        var line_idx: usize = 0;
        var pos = self.findConLineStart(skip);
        while (pos < self.con_len and line_idx < max_lines) {
            var end = pos;
            while (end < self.con_len and self.console[end] != '\n') : (end += 1) {}
            if (end > pos) {
                const maxc = @as(usize, @intCast((fb.width - 4) / L.ch_w));
                const seg = self.console[pos..end];
                fb.drawText(if (seg.len > maxc) seg[0..maxc] else seg, 4, @as(i32, @intCast(con_top + 2 + line_idx * L.ch_h)), CONSOLE_TEXT, L.ch_w);
            }
            line_idx += 1;
            pos = end + 1;
        }
    }

    fn drawStatus(self: *IdeState, fb: *gfx.Framebuffer) void {
        const L = layout(fb);
        const sy = @as(i32, @intCast(L.top_y + L.ed_h + L.con_h));
        fb.fillRect(gfx.Rect{ .x = 0, .y = sy, .w = fb.width, .h = L.status_h }, STATUS_BG);
        fb.fillRect(gfx.Rect{ .x = 0, .y = sy - 1, .w = fb.width, .h = 1 }, GUTTER_LINE);

        const sty = sy + @as(i32, @intCast((L.status_h - L.ch_h) / 2));
        var lb: [16]u8 = undefined;
        fb.drawText(fmtU32(@as(u32, @intCast(self.cy + 1)), lb[0..]), 8, sty, TEXT_COL, L.ch_w);
        fb.drawText(":", 8 + @as(i32, @intCast(L.ch_w)), sty, NUML_COL, L.ch_w);
        var cb: [16]u8 = undefined;
        fb.drawText(fmtU32(@as(u32, @intCast(self.cx + 1)), cb[0..]), 8 + @as(i32, @intCast(L.ch_w + L.ch_w / 2 + 2)), sty, TEXT_COL, L.ch_w);

        if (self.modified) fb.drawText("  \xE2\x97\x8B", @as(i32, @intCast(L.ch_w * 3)), sty, MODIFIED_COL, L.ch_w);
        if (self.status_len > 0) fb.drawText(self.status[0..self.status_len], @as(i32, @intCast(L.ch_w * 5)), sty, STATUS_TEXT, L.ch_w);
        fb.drawText("dhjsjs  UTF-8", @as(i32, @intCast(fb.width)) - @as(i32, @intCast(L.ch_w * 8)), sty, STATUS_TEXT, L.ch_w);
    }

    // ── mouse ───────────────────────────────────────────────
    pub fn handleMouseClick(self: *IdeState, mx: i32, my: i32, fbw: u32, fbh: u32) void {
        _ = fbh;
        const sc = fontScale(fbw);
        const ch_w = sc * 8;
        const ch_h = sc * 8 + 4;
        const gutter_w = ch_w * 5 + 14;
        const top_y = (ch_h) * 3;

        if (my < @as(i32, @intCast(top_y))) {
            // menu bar
            if (my < @as(i32, @intCast(ch_h))) {
                const mc = @divFloor(@max(mx - 8, 0), @as(i32, @intCast(ch_w)));
                const menu_status = if (mc < 5) "File: Ctrl+S Save | Ctrl+O Open | New" else if (mc < 10) "Edit: Cut | Copy | Paste (not yet)" else if (mc < 16) "Sketch: Verify/Upload (F5)" else if (mc < 21) "Tools: terminal | settings (not yet)" else if (mc < 26) "Help: dhjsjs IDE v0.1" else "";
                if (menu_status.len > 0) self.setStatus(menu_status);
                return;
            }
            // toolbar: [Verify]=0, [Upload]=1, [New]=2, [Open]=3, [Save]=4
            if (my >= @as(i32, @intCast(ch_h)) and my < @as(i32, @intCast(ch_h * 2))) {
                const rel_x = @as(i32, mx - 8);
                const btn_w = @as(i32, @intCast(ch_w * 5));
                const spacing = @as(i32, @intCast(ch_w));
                const idx = @divFloor(rel_x, btn_w + spacing);
                if (idx == 2) { self.clen = 0; self.cx = 0; self.cy = 0; self.modified = false; }
                if (idx == 3) self.startInput("open");
                if (idx == 4) self.saveFile();
                if (idx == 0 or idx == 1) self.request_build = true;
            }
            return;
        }
        const rel_y = @as(u32, @intCast(@max(my - @as(i32, @intCast(top_y)), 0)));
        const rel_x = @as(u32, @intCast(@max(mx - @as(i32, @intCast(gutter_w)), 0)));
        const new_cy = rel_y / ch_h;
        const new_cx = rel_x / ch_w;
        self.cy = @min(new_cy, self.totalLines() - 1);
        self.cx = @min(new_cx, self.getLineLen(self.cy));
    }

    pub fn startInput(self: *IdeState, action: []const u8) void {
        self.input_mode = true;
        self.input_len = 0;
        self.input_action = if (action.len > 0) action[0] else 'o';
        if (action.len > 0 and action[0] == 's') {
            self.setStatus("Save as: type path, Enter to save, Esc to cancel");
        } else {
            self.setStatus("Open: type path, Enter to open, Esc to cancel");
        }
    }

    pub fn cancelInput(self: *IdeState) void {
        self.input_mode = false;
        self.input_len = 0;
        self.setStatus("cancelled");
    }

    pub fn confirmInput(self: *IdeState) void {
        if (self.input_len > 0) {
            const path = self.input_buf[0..self.input_len];
            if (self.input_action == 's') {
                var fi: usize = 0;
                while (fi < path.len and fi < MAX_FILENAME - 1) : (fi += 1) self.filename[fi] = path[fi];
                self.flen = path.len;
                self.saveFile();
            } else {
                self.openFile(path);
            }
        }
        self.input_mode = false;
        self.input_len = 0;
    }

    pub fn inputChar(self: *IdeState, ch: u8) bool {
        if (!self.input_mode) return false;
        switch (ch) {
            '\n', '\r' => self.confirmInput(),
            0x1b => self.cancelInput(),
            0x7f, 0x08 => { if (self.input_len > 0) self.input_len -= 1; },
            else => {
                if (ch >= 32 and ch < 127 and self.input_len < 255) {
                    self.input_buf[self.input_len] = ch;
                    self.input_len += 1;
                }
            },
        }
        return true;
    }

    // ── helpers ─────────────────────────────────────────────
    fn conLines(self: *IdeState) usize {
        var n: usize = 0;
        for (self.console[0..self.con_len]) |c| { if (c == '\n') n += 1; }
        return if (self.con_len > 0 and self.console[self.con_len - 1] != '\n') n + 1 else n;
    }

    fn findConLineStart(self: *IdeState, line: usize) usize {
        var ln: usize = 0;
        var i: usize = 0;
        while (i < self.con_len and ln < line) : (i += 1) { if (self.console[i] == '\n') ln += 1; }
        return if (i < self.con_len) i + 1 else self.con_len;
    }

    fn totalLines(self: *IdeState) usize {
        var n: usize = 1;
        for (self.content[0..self.clen]) |c| { if (c == '\n') n += 1; }
        return n;
    }

    fn getLineStart(self: *IdeState, line: usize) usize {
        var ln: usize = 0;
        var i: usize = 0;
        while (i < self.clen and ln < line) : (i += 1) { if (self.content[i] == '\n') ln += 1; }
        return i;
    }

    fn getLineEnd(self: *IdeState, line: usize) usize {
        var start = self.getLineStart(line);
        while (start < self.clen and self.content[start] != '\n') : (start += 1) {}
        return start;
    }

    fn getLineLen(self: *IdeState, line: usize) usize {
        return self.getLineEnd(line) - self.getLineStart(line);
    }

    pub fn insertChar(self: *IdeState, ch: u8) void {
        if (self.input_mode) {
            _ = self.inputChar(ch);
            return;
        }
        if (self.clen >= MAX_CONTENT) return;
        var pos = self.getLineStart(self.cy) + self.cx;
        if (pos > self.clen) pos = self.clen;
        var i = self.clen;
        while (i > pos) : (i -= 1) self.content[i] = self.content[i - 1];
        self.content[pos] = ch;
        self.clen += 1;
        self.cx += 1;
        if (ch == '\n') { self.cx = 0; self.cy += 1; }
        self.modified = true;
    }

    pub fn deleteChar(self: *IdeState) void {
        if (self.input_mode) {
            if (self.input_len > 0) self.input_len -= 1;
            return;
        }
        var pos = self.getLineStart(self.cy) + self.cx;
        if (pos == 0 or self.clen == 0) return;
        if (pos > self.clen) pos = self.clen;
        var i = pos - 1;
        while (i < self.clen - 1) : (i += 1) self.content[i] = self.content[i + 1];
        self.clen -= 1;
        if (self.cx > 0) {
            self.cx -= 1;
        } else if (self.cy > 0) {
            self.cy -= 1;
            self.cx = self.getLineLen(self.cy);
        }
        self.modified = true;
    }

    pub fn cursorLeft(self: *IdeState) void {
        if (self.cx > 0) { self.cx -= 1; }
        else if (self.cy > 0) { self.cy -= 1; self.cx = self.getLineLen(self.cy); }
    }

    pub fn cursorRight(self: *IdeState) void {
        if (self.cx < self.getLineLen(self.cy)) { self.cx += 1; }
        else if (self.getLineEnd(self.cy) < self.clen) { self.cy += 1; self.cx = 0; }
    }

    pub fn cursorUp(self: *IdeState) void {
        if (self.cy > 0) { self.cy -= 1; self.cx = @min(self.cx, self.getLineLen(self.cy)); }
    }

    pub fn cursorDown(self: *IdeState) void {
        if (self.getLineStart(self.cy + 1) < self.clen) { self.cy += 1; self.cx = @min(self.cx, self.getLineLen(self.cy)); }
    }

    pub fn cursorHome(self: *IdeState) void { self.cx = 0; }
    pub fn cursorEnd(self: *IdeState) void { self.cx = self.getLineLen(self.cy); }
};
