const gfx = @import("render.zig");
const comp = @import("compositor.zig");
const utils = @import("utils.zig");
const sys = @import("sys.zig");

const MAX_FILENAME = 256;
const MAX_CONTENT = 65536;

fn isKw(s: []const u8) bool {
    const words = [_][]const u8{ "fn", "let", "if", "else", "return", "while", "activity", "compose", "state", "viewmodel", "true", "false", "null", "int", "string", "bool", "void" };
    for (words) |w| { if (utils.sliceEql(s, w)) return true; }
    return false;
}

fn isNum(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| { if (c < '0' or c > '9') return false; }
    return true;
}

const HL_KEYWORD: u8 = 0;
const HL_STRING: u8 = 1;
const HL_NUMBER: u8 = 2;
const HL_COMMENT: u8 = 3;
const HL_NORMAL: u8 = 4;

fn highlightLine(line: []const u8, buf: []u8) void {
    var i: usize = 0;
    while (i < line.len and i < buf.len) {
        if (line[i] == '"') {
            buf[i] = HL_STRING;
            i += 1;
            while (i < line.len and line[i] != '"') : (i += 1) { buf[i] = HL_STRING; }
            if (i < line.len) { buf[i] = HL_STRING; i += 1; }
        } else if (line[i] == '/' and i + 1 < line.len and line[i + 1] == '/') {
            while (i < line.len) : (i += 1) { buf[i] = HL_COMMENT; if (i >= buf.len) break; }
        } else if ((line[i] >= 'a' and line[i] <= 'z') or (line[i] >= 'A' and line[i] <= 'Z') or line[i] == '_') {
            const start = i;
            while (i < line.len and ((line[i] >= 'a' and line[i] <= 'z') or (line[i] >= 'A' and line[i] <= 'Z') or (line[i] >= '0' and line[i] <= '9') or line[i] == '_')) : (i += 1) {}
            if (isKw(line[start..i])) {
                var k = start;
                while (k < i and k < buf.len) : (k += 1) buf[k] = HL_KEYWORD;
            } else {
                var k = start;
                while (k < i and k < buf.len) : (k += 1) buf[k] = HL_NORMAL;
            }
        } else if (line[i] >= '0' and line[i] <= '9') {
            buf[i] = HL_NUMBER;
            i += 1;
        } else {
            buf[i] = HL_NORMAL;
            i += 1;
        }
    }
}

pub const IdeState = struct {
    filename: [MAX_FILENAME]u8,
    flen: usize,
    content: [MAX_CONTENT]u8,
    clen: usize,
    cx: usize,
    cy: usize,
    scroll_x: usize,
    scroll_y: usize,
    modified: bool,
    cursor_on: bool,
    frame_count: usize,
    menu: [4]u8,
    menu_len: usize,
    status: [64]u8,
    status_len: usize,
    asm_out: [65536]u8,
    asm_len: usize,
    bin_out: [65536]u8,
    bin_len: usize,

    pub fn init() IdeState {
        return IdeState{
            .filename = undefined,
            .flen = 0,
            .content = undefined,
            .clen = 0,
            .cx = 0,
            .cy = 0,
            .scroll_x = 0,
            .scroll_y = 0,
            .modified = false,
            .cursor_on = true,
            .frame_count = 0,
            .menu = undefined,
            .menu_len = 0,
            .status = undefined,
            .status_len = 0,
            .asm_out = undefined,
            .asm_len = 0,
            .bin_out = undefined,
            .bin_len = 0,
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

    pub fn openFile(self: *IdeState, filepath: []const u8) void {
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
        if (total == 0) { self.setStatus("empty file"); return; }
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
        if (self.flen == 0) { self.setStatus("no filename"); return; }
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

    pub fn paint(self: *IdeState, fb: *gfx.Framebuffer) void {
        self.frame_count +%= 1;
        self.cursor_on = (self.frame_count / 15) % 2 == 0;
        fb.fill(gfx.rgb(28, 28, 28));
        self.drawTitle(fb);
        self.drawLines(fb);
        self.drawCursor(fb);
        self.drawStatus(fb);
    }

    fn drawTitle(self: *IdeState, fb: *gfx.Framebuffer) void {
        const title = if (self.flen > 0) self.filename[0..self.flen] else "untitled.dhjsjs";
        fb.fillRect(gfx.Rect{ .x = 0, .y = 0, .w = fb.width, .h = 26 }, gfx.rgb(55, 55, 55));
        fb.drawText(title, 8, 6, gfx.rgb(240, 240, 240), 14);
        fb.drawText(" [File: Ctrl+O Save: Ctrl+S Build: F5]", @intCast(fb.width - 280), 6, gfx.rgb(180, 220, 180), 14);
    }

    fn colorForHL(h: u8) gfx.Color {
        return switch (h) {
            HL_KEYWORD => gfx.rgb(86, 156, 214),
            HL_STRING => gfx.rgb(206, 145, 120),
            HL_NUMBER => gfx.rgb(181, 206, 168),
            HL_COMMENT => gfx.rgb(106, 153, 85),
            else => gfx.rgb(210, 210, 210),
        };
    }

    fn drawLines(self: *IdeState, fb: *gfx.Framebuffer) void {
        const text_x: u32 = 50;
        var y: u32 = 30;
        var line: usize = 0;
        var i: usize = 0;
        var line_start: usize = 0;

        while (i <= self.clen and y < fb.height - 20) : (i += 1) {
            if (i == self.clen or self.content[i] == '\n') {
                line += 1;
                if (line > self.scroll_y + 1) {
                    var num_buf: [16]u8 = undefined;
                    const nlen = utils.formatU32(@as(u32, @intCast(line)), &num_buf);
                    fb.drawText(num_buf[0..nlen], 4, @intCast(y), gfx.rgb(100, 100, 100), 14);
                }

                const end = i;
                const text = self.content[line_start..end];
                if (text.len > 0 and line > self.scroll_y) {
                    const vis = if (text.len > 120) text[0..120] else text;
                    var hl_buf: [120]u8 = undefined;
                    const hl_len = if (vis.len > 120) 120 else vis.len;
                    highlightLine(vis, hl_buf[0..hl_len]);

                    var cx_pix: i32 = @intCast(text_x);
                    var ci: usize = 0;
                    while (ci < hl_len) : (ci += 1) {
                        const col = colorForHL(hl_buf[ci]);
                        const ch = vis[ci];
                        const glyph = getGlyph(ch);
                        var gy: u32 = 0;
                        while (gy < 8) : (gy += 1) {
                            var gx: u32 = 0;
                            while (gx < 8) : (gx += 1) {
                                if ((glyph[gy] & (@as(u8, 1) << @intCast(gx))) != 0) {
                                    const px = cx_pix + @as(i32, @intCast(gx));
                                    const py = @as(i32, @intCast(y)) + @as(i32, @intCast(gy));
                                    if (px >= 0 and py >= 0 and px < @as(i32, @intCast(fb.width)) and py < @as(i32, @intCast(fb.height))) {
                                        fb.pixels[@as(usize, @intCast(py)) * fb.stride + @as(usize, @intCast(px))] = gfx.colorToU32(col);
                                    }
                                }
                            }
                        }
                        cx_pix += 8;
                    }
                }
                y += 16;
                line_start = i + 1;
            }
        }
    }

    fn drawCursor(self: *IdeState, fb: *gfx.Framebuffer) void {
        if (!self.cursor_on) return;
        const x = 50 + @as(i32, @intCast(self.cx)) * 8;
        const y = 30 + @as(i32, @intCast(self.cy)) * 16;
        if (y < @as(i32, @intCast(fb.height)) - 20) {
            fb.fillRect(gfx.Rect{ .x = x, .y = y, .w = 8, .h = 16 }, gfx.rgb(255, 200, 50));
        }
    }

    fn drawStatus(self: *IdeState, fb: *gfx.Framebuffer) void {
        fb.fillRect(gfx.Rect{ .x = 0, .y = @as(i32, @intCast(fb.height)) - 18, .w = fb.width, .h = 18 }, gfx.rgb(40, 40, 40));
        fb.drawText(" Ln:", 4, @as(i32, @intCast(fb.height)) - 15, gfx.rgb(140, 140, 140), 12);
        var lb: [16]u8 = undefined;
        const ln = utils.formatU32(@as(u32, @intCast(self.cy + 1)), &lb);
        fb.drawText(lb[0..ln], 24, @as(i32, @intCast(fb.height)) - 15, gfx.rgb(200, 200, 200), 12);

        if (self.modified) {
            fb.drawText(" *", 50, @as(i32, @intCast(fb.height)) - 15, gfx.rgb(255, 180, 60), 12);
        }
        if (self.status_len > 0) {
            fb.drawText(self.status[0..self.status_len], 80, @as(i32, @intCast(fb.height)) - 15, gfx.rgb(160, 220, 160), 12);
        }
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
        const line_len = self.getLineLen(self.cy);
        if (self.cx < line_len) { self.cx += 1; }
        else {
            const end = self.getLineEnd(self.cy);
            if (end < self.clen) { self.cy += 1; self.cx = 0; }
        }
    }

    pub fn cursorUp(self: *IdeState) void {
        if (self.cy > 0) { self.cy -= 1; const ll = self.getLineLen(self.cy); if (self.cx > ll) self.cx = ll; }
    }

    pub fn cursorDown(self: *IdeState) void {
        const test_line = self.cy + 1;
        const line_start = self.getLineStart(test_line);
        if (line_start < self.clen) { self.cy += 1; const ll = self.getLineLen(self.cy); if (self.cx > ll) self.cx = ll; }
    }

    pub fn cursorHome(self: *IdeState) void { self.cx = 0; }
    pub fn cursorEnd(self: *IdeState) void { self.cx = self.getLineLen(self.cy); }
};

fn getGlyph(ch: u8) [8]u8 {
    return switch (ch) {
        'A' => .{ 0x7C, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0x00 },
        'B' => .{ 0xFC, 0xC6, 0xC6, 0xFC, 0xC6, 0xC6, 0xFC, 0x00 },
        'C' => .{ 0x7C, 0xC6, 0xC0, 0xC0, 0xC0, 0xC6, 0x7C, 0x00 },
        'D' => .{ 0xF8, 0xCC, 0xC6, 0xC6, 0xC6, 0xCC, 0xF8, 0x00 },
        'E' => .{ 0xFE, 0xC0, 0xC0, 0xF8, 0xC0, 0xC0, 0xFE, 0x00 },
        'F' => .{ 0xFE, 0xC0, 0xC0, 0xF8, 0xC0, 0xC0, 0xC0, 0x00 },
        'G' => .{ 0x7C, 0xC6, 0xC0, 0xCE, 0xC6, 0xC6, 0x7C, 0x00 },
        'H' => .{ 0xC6, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0x00 },
        'I' => .{ 0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00 },
        'J' => .{ 0x06, 0x06, 0x06, 0x06, 0x06, 0xC6, 0x7C, 0x00 },
        'K' => .{ 0xC6, 0xCC, 0xD8, 0xF0, 0xD8, 0xCC, 0xC6, 0x00 },
        'L' => .{ 0xC0, 0xC0, 0xC0, 0xC0, 0xC0, 0xC0, 0xFE, 0x00 },
        'M' => .{ 0xC6, 0xEE, 0xFE, 0xD6, 0xC6, 0xC6, 0xC6, 0x00 },
        'N' => .{ 0xC6, 0xE6, 0xF6, 0xDE, 0xCE, 0xC6, 0xC6, 0x00 },
        'O' => .{ 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00 },
        'P' => .{ 0xFC, 0xC6, 0xC6, 0xFC, 0xC0, 0xC0, 0xC0, 0x00 },
        'Q' => .{ 0x7C, 0xC6, 0xC6, 0xC6, 0xD6, 0xCC, 0x76, 0x00 },
        'R' => .{ 0xFC, 0xC6, 0xC6, 0xFC, 0xD8, 0xCC, 0xC6, 0x00 },
        'S' => .{ 0x7C, 0xC6, 0xC0, 0x7C, 0x06, 0xC6, 0x7C, 0x00 },
        'T' => .{ 0xFE, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00 },
        'U' => .{ 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00 },
        'V' => .{ 0xC6, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x10, 0x00 },
        'W' => .{ 0xC6, 0xC6, 0xC6, 0xD6, 0xFE, 0xEE, 0xC6, 0x00 },
        'X' => .{ 0xC6, 0xC6, 0x6C, 0x38, 0x6C, 0xC6, 0xC6, 0x00 },
        'Y' => .{ 0xC6, 0xC6, 0x6C, 0x38, 0x18, 0x18, 0x18, 0x00 },
        'Z' => .{ 0xFE, 0x06, 0x0C, 0x18, 0x30, 0x60, 0xFE, 0x00 },
        'a' => .{ 0x00, 0x00, 0x7C, 0x06, 0x7E, 0xC6, 0x7E, 0x00 },
        'b' => .{ 0xC0, 0xC0, 0xFC, 0xC6, 0xC6, 0xC6, 0xFC, 0x00 },
        'c' => .{ 0x00, 0x00, 0x7C, 0xC6, 0xC0, 0xC6, 0x7C, 0x00 },
        'd' => .{ 0x06, 0x06, 0x7E, 0xC6, 0xC6, 0xC6, 0x7E, 0x00 },
        'e' => .{ 0x00, 0x00, 0x7C, 0xC6, 0xFE, 0xC0, 0x7C, 0x00 },
        'f' => .{ 0x1C, 0x36, 0x30, 0x7C, 0x30, 0x30, 0x30, 0x00 },
        'g' => .{ 0x00, 0x00, 0x7E, 0xC6, 0xC6, 0x7E, 0x06, 0x7C },
        'h' => .{ 0xC0, 0xC0, 0xFC, 0xC6, 0xC6, 0xC6, 0xC6, 0x00 },
        'i' => .{ 0x18, 0x00, 0x38, 0x18, 0x18, 0x18, 0x3C, 0x00 },
        'j' => .{ 0x06, 0x00, 0x06, 0x06, 0x06, 0x06, 0xC6, 0x7C },
        'k' => .{ 0xC0, 0xC0, 0xCC, 0xD8, 0xF0, 0xD8, 0xCC, 0x00 },
        'l' => .{ 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00 },
        'm' => .{ 0x00, 0x00, 0xEC, 0xFE, 0xD6, 0xC6, 0xC6, 0x00 },
        'n' => .{ 0x00, 0x00, 0xFC, 0xC6, 0xC6, 0xC6, 0xC6, 0x00 },
        'o' => .{ 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0x7C, 0x00 },
        'p' => .{ 0x00, 0x00, 0xFC, 0xC6, 0xC6, 0xFC, 0xC0, 0xC0 },
        'q' => .{ 0x00, 0x00, 0x7E, 0xC6, 0xC6, 0x7E, 0x06, 0x06 },
        'r' => .{ 0x00, 0x00, 0xDC, 0xE6, 0xC0, 0xC0, 0xC0, 0x00 },
        's' => .{ 0x00, 0x00, 0x7E, 0xC0, 0x7C, 0x06, 0xFC, 0x00 },
        't' => .{ 0x30, 0x30, 0x7C, 0x30, 0x30, 0x36, 0x1C, 0x00 },
        'u' => .{ 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0xCE, 0x76, 0x00 },
        'v' => .{ 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x00 },
        'w' => .{ 0x00, 0x00, 0xC6, 0xC6, 0xD6, 0xFE, 0x6C, 0x00 },
        'x' => .{ 0x00, 0x00, 0xC6, 0x6C, 0x38, 0x6C, 0xC6, 0x00 },
        'y' => .{ 0x00, 0x00, 0xC6, 0xC6, 0xCE, 0x76, 0x06, 0x7C },
        'z' => .{ 0x00, 0x00, 0xFE, 0x0C, 0x38, 0x60, 0xFE, 0x00 },
        '0' => .{ 0x7C, 0xC6, 0xCE, 0xD6, 0xE6, 0xC6, 0x7C, 0x00 },
        '1' => .{ 0x18, 0x38, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00 },
        '2' => .{ 0x7C, 0xC6, 0x06, 0x1C, 0x30, 0x60, 0xFE, 0x00 },
        '3' => .{ 0x7C, 0xC6, 0x06, 0x3C, 0x06, 0xC6, 0x7C, 0x00 },
        '4' => .{ 0x0C, 0x1C, 0x3C, 0x6C, 0xFE, 0x0C, 0x0C, 0x00 },
        '5' => .{ 0xFE, 0xC0, 0xFC, 0x06, 0x06, 0xC6, 0x7C, 0x00 },
        '6' => .{ 0x7C, 0xC6, 0xC0, 0xFC, 0xC6, 0xC6, 0x7C, 0x00 },
        '7' => .{ 0xFE, 0x06, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0x00 },
        '8' => .{ 0x7C, 0xC6, 0xC6, 0x7C, 0xC6, 0xC6, 0x7C, 0x00 },
        '9' => .{ 0x7C, 0xC6, 0xC6, 0x7E, 0x06, 0xC6, 0x7C, 0x00 },
        ' ' => .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        '.' => .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00 },
        ',' => .{ 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x30, 0x00 },
        ':' => .{ 0x00, 0x18, 0x18, 0x00, 0x18, 0x18, 0x00, 0x00 },
        ';' => .{ 0x00, 0x18, 0x18, 0x00, 0x18, 0x18, 0x30, 0x00 },
        '(' => .{ 0x0C, 0x18, 0x30, 0x30, 0x30, 0x18, 0x0C, 0x00 },
        ')' => .{ 0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x18, 0x30, 0x00 },
        '[' => .{ 0x3C, 0x30, 0x30, 0x30, 0x30, 0x30, 0x3C, 0x00 },
        ']' => .{ 0x3C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x3C, 0x00 },
        '{' => .{ 0x1C, 0x30, 0x30, 0x60, 0x30, 0x30, 0x1C, 0x00 },
        '}' => .{ 0x70, 0x30, 0x30, 0x1C, 0x30, 0x30, 0x70, 0x00 },
        '+' => .{ 0x00, 0x18, 0x18, 0x7E, 0x18, 0x18, 0x00, 0x00 },
        '-' => .{ 0x00, 0x00, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x00 },
        '*' => .{ 0x00, 0x66, 0x3C, 0x18, 0x3C, 0x66, 0x00, 0x00 },
        '/' => .{ 0x02, 0x06, 0x0C, 0x18, 0x30, 0x60, 0x40, 0x00 },
        '=' => .{ 0x00, 0x00, 0x7E, 0x00, 0x7E, 0x00, 0x00, 0x00 },
        '!' => .{ 0x18, 0x18, 0x18, 0x18, 0x00, 0x00, 0x18, 0x00 },
        '@' => .{ 0x7C, 0xC6, 0xDE, 0xAA, 0xBA, 0xC0, 0x7C, 0x00 },
        '#' => .{ 0x36, 0x36, 0x7F, 0x36, 0x7F, 0x36, 0x36, 0x00 },
        '$' => .{ 0x18, 0x3E, 0x60, 0x3C, 0x06, 0x7C, 0x18, 0x00 },
        '_' => .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7E, 0x00 },
        '<' => .{ 0x0C, 0x18, 0x30, 0x60, 0x30, 0x18, 0x0C, 0x00 },
        '>' => .{ 0x30, 0x18, 0x0C, 0x06, 0x0C, 0x18, 0x30, 0x00 },
        '?' => .{ 0x7C, 0xC6, 0x06, 0x1C, 0x18, 0x00, 0x18, 0x00 },
        else => .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
    };
}
