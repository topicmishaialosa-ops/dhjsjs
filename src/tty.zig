const sys = @import("sys.zig");
const gfx = @import("render.zig");

const ESC: u8 = 0x1B;

fn ansi(fd: i32, code: []const u8) void {
    _ = sys.write(fd, code.ptr, code.len);
}

fn cursorPos(fd: i32, row: u32, col: u32) void {
    var buf: [16]u8 = undefined;
    var i: usize = 0;
    buf[i] = ESC; i += 1;
    buf[i] = '['; i += 1;
    i += fmtU32(row, buf[i..]);
    buf[i] = ';'; i += 1;
    i += fmtU32(col, buf[i..]);
    buf[i] = 'H'; i += 1;
    _ = sys.write(fd, buf[0..i].ptr, i);
}

fn fmtU32(n: u32, buf: []u8) usize {
    if (n == 0) { buf[0] = '0'; return 1; }
    var tmp: [16]u8 = undefined;
    var i: usize = 0;
    var v = n;
    while (v > 0) : (v /= 10) { tmp[i] = @as(u8, @intCast(v % 10)) + '0'; i += 1; }
    var j: usize = 0;
    while (j < i) : (j += 1) buf[j] = tmp[i - 1 - j];
    return i;
}

fn setFg(fd: i32, c: gfx.Color) void {
    const r = @as(u32, c.r) * 5 / 255;
    const g = @as(u32, c.g) * 5 / 255;
    const b = @as(u32, c.b) * 5 / 255;
    var buf: [16]u8 = undefined;
    var i: usize = 0;
    buf[i] = ESC; i += 1;
    buf[i] = '['; i += 1;
    buf[i] = '3'; i += 1;
    buf[i] = '8'; i += 1;
    buf[i] = ';'; i += 1;
    buf[i] = '5'; i += 1;
    buf[i] = ';'; i += 1;
    const idx: u8 = 16 + r * 36 + g * 6 + b;
    i += fmtU32(idx, buf[i..]);
    buf[i] = 'm'; i += 1;
    _ = sys.write(fd, buf[0..i].ptr, i);
}

fn setBg(fd: i32, c: gfx.Color) void {
    const r = @as(u32, c.r) * 5 / 255;
    const g = @as(u32, c.g) * 5 / 255;
    const b = @as(u32, c.b) * 5 / 255;
    var buf: [16]u8 = undefined;
    var i: usize = 0;
    buf[i] = ESC; i += 1;
    buf[i] = '['; i += 1;
    buf[i] = '4'; i += 1;
    buf[i] = '8'; i += 1;
    buf[i] = ';'; i += 1;
    buf[i] = '5'; i += 1;
    buf[i] = ';'; i += 1;
    const idx: u8 = 16 + r * 36 + g * 6 + b;
    i += fmtU32(idx, buf[i..]);
    buf[i] = 'm'; i += 1;
    _ = sys.write(fd, buf[0..i].ptr, i);
}

fn resetStyle(fd: i32) void {
    const s = [_]u8{ ESC, '[', '0', 'm' };
    _ = sys.write(fd, &s, 4);
}

pub const TtyRender = struct {
    cols: u32,
    rows: u32,
    fg: gfx.Color,
    bg: gfx.Color,
    buf: [65536]u8,
    blen: usize,

    pub fn init() TtyRender {
        return TtyRender{
            .cols = 80, .rows = 24,
            .fg = gfx.rgb(210, 210, 210),
            .bg = gfx.rgb(28, 28, 28),
            .buf = undefined, .blen = 0,
        };
    }

    pub fn detectSize(self: *TtyRender) void {
        if (sys.getWinsize(sys.STDIN)) |ws| {
            self.cols = ws.ws_col;
            self.rows = ws.ws_row;
        }
    }

    pub fn clearScreen(_: *TtyRender) void {
        const s = [_]u8{ ESC, '[', '2', 'J', ESC, '[', 'H' };
        _ = sys.write(sys.STDOUT, &s, 7);
    }

    fn flush(self: *TtyRender) void {
        if (self.blen > 0) {
            _ = sys.write(sys.STDOUT, &self.buf, self.blen);
            self.blen = 0;
        }
    }

    fn put(self: *TtyRender, b: u8) void {
        if (self.blen < self.buf.len) {
            self.buf[self.blen] = b;
            self.blen += 1;
        }
    }

    fn ansiBuf(self: *TtyRender, s: []const u8) void {
        for (s) |b| self.put(b);
    }

    fn cursorPosBuf(self: *TtyRender, row: u32, col: u32) void {
        self.put(ESC); self.put('[');
        var i = self.blen;
        i += fmtU32(row, self.buf[i..]);
        self.blen = i;
        self.put(';');
        i = self.blen;
        i += fmtU32(col, self.buf[i..]);
        self.blen = i;
        self.put('H');
    }

    fn setFgBuf(self: *TtyRender, c: gfx.Color) void {
        const r = @as(u32, c.r) * 5 / 255;
        const g = @as(u32, c.g) * 5 / 255;
        const b = @as(u32, c.b) * 5 / 255;
        const idx = @as(u8, @intCast(16 + r * 36 + g * 6 + b));
        self.put(ESC); self.put('[');
        self.put('3'); self.put('8'); self.put(';'); self.put('5'); self.put(';');
        var i = self.blen;
        i += fmtU32(idx, self.buf[i..]);
        self.blen = i;
        self.put('m');
    }

    fn setBgBuf(self: *TtyRender, c: gfx.Color) void {
        const r = @as(u32, c.r) * 5 / 255;
        const g = @as(u32, c.g) * 5 / 255;
        const b = @as(u32, c.b) * 5 / 255;
        const idx = @as(u8, @intCast(16 + r * 36 + g * 6 + b));
        self.put(ESC); self.put('[');
        self.put('4'); self.put('8'); self.put(';'); self.put('5'); self.put(';');
        var i = self.blen;
        i += fmtU32(idx, self.buf[i..]);
        self.blen = i;
        self.put('m');
    }

    fn resetStyleBuf(self: *TtyRender) void {
        self.ansiBuf(&[_]u8{ ESC, '[', '0', 'm' });
    }

    pub fn paint(self: *TtyRender, ide: *const @import("ide.zig").IdeState) void {
        self.blen = 0;
        self.cursorPosBuf(1, 1);
        self.setBgBuf(gfx.rgb(55, 55, 55));
        var title_col: u32 = 0;
        while (title_col < self.cols) : (title_col += 1) self.put(' ');
        self.cursorPosBuf(1, 1);
        self.setFgBuf(gfx.rgb(240, 240, 240));
        if (ide.flen > 0) {
            var ti: usize = 0;
            while (ti < ide.flen and ti < @as(usize, self.cols - 2)) : (ti += 1) self.put(ide.filename[ti]);
        } else {
            self.ansiBuf("untitled.dhjsjs");
        }
        self.resetStyleBuf();

        var y: u32 = 2;
        var line: usize = 0;
        var i: usize = 0;
        var line_start: usize = 0;

        while (i <= ide.clen and y < self.rows) : (i += 1) {
            if (i == ide.clen or ide.content[i] == '\n') {
                line += 1;
                if (line > 1) {
                    self.cursorPosBuf(y, 1);
                    self.setFgBuf(gfx.rgb(180, 180, 180));
                    var lb: [16]u8 = undefined;
                    const ln = fmtU32(@as(u32, @intCast(line)), &lb);
                    self.ansiBuf(lb[0..ln]);
                    self.setFgBuf(gfx.rgb(210, 210, 210));
                    self.put(' ');

                    const line_text = ide.content[line_start..i];
                    var ci: usize = 0;
                    while (ci < line_text.len and ci + 5 < self.cols) : (ci += 1) {
                        const ch = line_text[ci];
                        if (ch == '\t') {
                            var ti: u32 = 0;
                            while (ti < 4) : (ti += 1) self.put(' ');
                        } else if (ch >= 32 and ch < 127) {
                            self.put(ch);
                        } else {
                            self.put('?');
                        }
                    }
                    while (ci + 5 < self.cols) : (ci += 1) self.put(' ');
                }
                y += 1;
                line_start = i + 1;
            }
        }

        while (y <= self.rows) : (y += 1) {
            self.cursorPosBuf(y, 1);
            var ci: u32 = 0;
            while (ci < self.cols) : (ci += 1) self.put(' ');
        }

        const cursor_row = @as(u32, @intCast(ide.cy)) + 2;
        const cursor_col = @as(u32, @intCast(ide.cx)) + 5;
        if (cursor_row <= self.rows and cursor_col <= self.cols) {
            self.cursorPosBuf(cursor_row, cursor_col);
        }

        self.cursorPosBuf(self.rows, 1);
        self.setBgBuf(gfx.rgb(40, 40, 40));
        var sb: u32 = 0;
        while (sb < self.cols) : (sb += 1) self.put(' ');
        self.cursorPosBuf(self.rows, 1);
        self.setFgBuf(gfx.rgb(140, 140, 140));
        self.ansiBuf(" Ln:");
        var lb2: [16]u8 = undefined;
        const ln2 = fmtU32(@as(u32, @intCast(ide.cy + 1)), &lb2);
        self.ansiBuf(lb2[0..ln2]);
        if (ide.status_len > 0) {
            self.setFgBuf(gfx.rgb(160, 220, 160));
            self.put(' ');
            self.ansiBuf(ide.status[0..ide.status_len]);
        }
        self.resetStyleBuf();
        self.flush();
    }

    pub fn deinit(self: *TtyRender) void {
        _ = self;
        const s = [_]u8{ ESC, '[', '?', '2', '5', 'h', ESC, '[', '2', 'J', ESC, '[', 'H' };
        _ = sys.write(sys.STDOUT, &s, 13);
    }
};
