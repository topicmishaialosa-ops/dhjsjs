const sys = @import("sys.zig");

pub const Color = struct {
    r: u8, g: u8, b: u8, a: u8,
};

pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
    return Color{ .r = r, .g = g, .b = b, .a = a };
}

pub fn rgb(r: u8, g: u8, b: u8) Color {
    return Color{ .r = r, .g = g, .b = b, .a = 255 };
}

pub fn colorToU32(c: Color) u32 {
    return (@as(u32, c.a) << 24) | (@as(u32, c.r) << 16) | (@as(u32, c.g) << 8) | c.b;
}

pub const Rect = struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
};

pub const Framebuffer = struct {
    pixels: [*]u32,
    width: u32,
    height: u32,
    stride: u32,

    pub fn init(width: u32, height: u32) ?Framebuffer {
        const size = @as(usize, width) * @as(usize, height) * 4;
        const ptr = sys.mmap(null, size, 3, 34, -1, 0) orelse return null;
        return Framebuffer{
            .pixels = @ptrCast(@alignCast(ptr)),
            .width = width,
            .height = height,
            .stride = width,
        };
    }

    pub fn deinit(self: *Framebuffer) void {
        const size = @as(usize, self.width) * @as(usize, self.height) * 4;
        sys.munmap(@ptrCast(self.pixels), size);
    }

    pub fn fill(self: *Framebuffer, c: Color) void {
        const val = colorToU32(c);
        const total = @as(usize, self.stride) * self.height;
        @memset(self.pixels[0..total], val);
    }

    pub fn fillRect(self: *Framebuffer, rect: Rect, c: Color) void {
        self.fillRect4(rect.x, rect.y, rect.w, rect.h, c);
    }

    pub fn fillRect4(self: *Framebuffer, x: i32, y: i32, w: u32, h: u32, c: Color) void {
        if (w == 0 or h == 0) return;
        const val = colorToU32(c);
        const x1: i32 = @max(0, x);
        const y1: i32 = @max(0, y);
        const x2: i32 = @min(@as(i32, @intCast(self.width)), x + @as(i32, @intCast(w)));
        const y2: i32 = @min(@as(i32, @intCast(self.height)), y + @as(i32, @intCast(h)));
        var yi = y1;
        while (yi < y2) : (yi += 1) {
            const row = @as(usize, @intCast(yi)) * self.stride;
            var xi = x1;
            while (xi < x2) : (xi += 1) {
                self.pixels[row + @as(usize, @intCast(xi))] = val;
            }
        }
    }

    pub fn fillRectGradient(self: *Framebuffer, x: i32, y: i32, w: u32, h: u32, c1: Color, c2: Color, vertical: bool) void {
        if (w == 0 or h == 0) return;
        var yi: i32 = 0;
        while (yi < @as(i32, @intCast(h))) : (yi += 1) {
            const t = if (vertical) @as(f32, @floatFromInt(yi)) / @as(f32, @floatFromInt(h)) else 0;
            const row_c = lerpColor(c1, c2, t);
            const y_abs = y + yi;
            if (y_abs < 0 or y_abs >= @as(i32, @intCast(self.height))) continue;
            const row = @as(usize, @intCast(y_abs)) * self.stride;
            var xi: i32 = 0;
            while (xi < @as(i32, @intCast(w))) : (xi += 1) {
                const col_t = if (!vertical) @as(f32, @floatFromInt(xi)) / @as(f32, @floatFromInt(w)) else 1.0;
                const final_c = if (!vertical) lerpColor(c1, c2, col_t) else row_c;
                const x_abs = x + xi;
                if (x_abs < 0 or x_abs >= @as(i32, @intCast(self.width))) continue;
                self.pixels[row + @as(usize, @intCast(x_abs))] = colorToU32(final_c);
            }
        }
    }

    pub fn drawRectBorder(self: *Framebuffer, rect: Rect, thickness: u32, c: Color) void {
        if (thickness == 0) return;
        const t = @as(i32, @intCast(thickness));
        self.fillRect4(rect.x, rect.y, rect.w, thickness, c);
        self.fillRect4(rect.x, rect.y + @as(i32, @intCast(rect.h)) - t, rect.w, thickness, c);
        self.fillRect4(rect.x, rect.y + t, thickness, rect.h - @as(u32, @intCast(t * 2)), c);
        self.fillRect4(rect.x + @as(i32, @intCast(rect.w)) - t, rect.y + t, thickness, rect.h - @as(u32, @intCast(t * 2)), c);
    }

    pub fn drawRoundRect(self: *Framebuffer, rect: Rect, r: u32, c: Color) void {
        self.fillRoundRect4(rect.x, rect.y, rect.w, rect.h, r, c);
    }

    pub fn fillRoundRect4(self: *Framebuffer, x: i32, y: i32, w: u32, h: u32, rad: u32, c: Color) void {
        if (w == 0 or h == 0) return;
        const rr = @min(rad, @min(w, h) / 2);
        const rr_i = @as(i32, @intCast(rr));
        if (rr == 0) { self.fillRect4(x, y, w, h, c); return; }

        const x1 = x + rr_i;
        const x2 = x + @as(i32, @intCast(w)) - rr_i;
        const y1 = y + rr_i;
        const y2 = y + @as(i32, @intCast(h)) - rr_i;

        self.fillRect4(x1, y, w - rr * 2, h, c);
        self.fillRect4(x, y1, rr, h - rr * 2, c);
        self.fillRect4(x2, y1, rr, h - rr * 2, c);

        const rs = @as(i32, @intCast(rr - 1));
        const r2 = rs * rs;
        var i: i32 = 0;
        while (i <= rs) : (i += 1) {
            var j: i32 = 0;
            while (j <= rs) : (j += 1) {
                const d2 = (rs - j) * (rs - j) + (rs - i) * (rs - i);
                if (d2 <= r2) {
                    self.setPixel(x1 - 1 - j, y1 - 1 - i, c);
                    self.setPixel(x2 + j, y1 - 1 - i, c);
                    self.setPixel(x1 - 1 - j, y2 + i, c);
                    self.setPixel(x2 + j, y2 + i, c);
                }
            }
        }
    }

    pub fn drawCircle(self: *Framebuffer, cx: i32, cy: i32, radius: u32, c: Color) void {
        const r = @as(i32, @intCast(radius));
        var x: i32 = -r;
        while (x <= r) : (x += 1) {
            var y: i32 = -r;
            while (y <= r) : (y += 1) {
                if (x * x + y * y <= r * r) {
                    self.setPixel(cx + x, cy + y, c);
                }
            }
        }
    }

    pub fn drawLine(self: *Framebuffer, x1: i32, y1: i32, x2: i32, y2: i32, c: Color) void {
        const dx = @abs(x2 - x1);
        const dy = -@abs(y2 - y1);
        const sx: i32 = if (x1 < x2) 1 else -1;
        const sy: i32 = if (y1 < y2) 1 else -1;
        var err = dx + dy;
        var cx = x1;
        var cy = y1;
        while (true) {
            self.setPixel(cx, cy, c);
            if (cx == x2 and cy == y2) break;
            const e2 = 2 * err;
            if (e2 >= dy) { err += dy; cx += sx; }
            if (e2 <= dx) { err += dx; cy += sy; }
        }
    }

    pub fn drawGlyphScaled(self: *Framebuffer, glyph: [8]u8, x: i32, y: i32, val: u32, scale: u32) void {
        var gy: u32 = 0;
        while (gy < 8) : (gy += 1) {
            var gx: u32 = 0;
            while (gx < 8) : (gx += 1) {
                if ((glyph[gy] & (@as(u8, 1) << @intCast(7 - gx))) != 0) {
                    const bx = x + @as(i32, @intCast(gx * scale));
                    const by = y + @as(i32, @intCast(gy * scale));
                    var sy: u32 = 0;
                    while (sy < scale) : (sy += 1) {
                        var sx: u32 = 0;
                        while (sx < scale) : (sx += 1) {
                            const px = bx + @as(i32, @intCast(sx));
                            const py = by + @as(i32, @intCast(sy));
                            if (px >= 0 and py >= 0 and px < @as(i32, @intCast(self.width)) and py < @as(i32, @intCast(self.height))) {
                                self.pixels[@as(usize, @intCast(py)) * self.stride + @as(usize, @intCast(px))] = val;
                            }
                        }
                    }
                }
            }
        }
    }

    pub fn drawText(self: *Framebuffer, text: []const u8, x: i32, y: i32, c: Color, size: u32) void {
        _ = size;
        const glyph_w: u32 = FONT_W;
        const glyph_h: u32 = FONT_H;
        var cx = x;
        var cy = y;
        for (text) |ch| {
            if (ch == '\n') {
                cy += @as(i32, @intCast(glyph_h + 2));
                cx = x;
                continue;
            }
            const glyph_off = @as(usize, ch) * glyph_h;
            var gy: u32 = 0;
            while (gy < glyph_h) : (gy += 1) {
                const row_off = glyph_off + gy;
                if (row_off >= fontData.len) break;
                const row_data = fontData[row_off];
                var gx: u32 = 0;
                while (gx < glyph_w) : (gx += 1) {
                    if ((row_data & (@as(u8, 1) << @intCast(glyph_w - 1 - gx))) != 0) {
                        const px = cx + @as(i32, @intCast(gx));
                        const py = cy + @as(i32, @intCast(gy));
                        if (px >= 0 and py >= 0 and px < @as(i32, @intCast(self.width)) and py < @as(i32, @intCast(self.height))) {
                            self.pixels[@as(usize, @intCast(py)) * self.stride + @as(usize, @intCast(px))] = colorToU32(c);
                        }
                    }
                }
            }
            cx += @as(i32, @intCast(glyph_w));
        }
    }

    fn setPixel(self: *Framebuffer, x: i32, y: i32, c: Color) void {
        if (x < 0 or y < 0) return;
        const ux = @as(u32, @intCast(x));
        const uy = @as(u32, @intCast(y));
        if (ux >= self.width or uy >= self.height) return;
        self.pixels[@as(usize, uy) * self.stride + ux] = colorToU32(c);
    }
};

fn lerpColor(a: Color, b: Color, t: f32) Color {
    return Color{
        .r = lerpByte(a.r, b.r, t),
        .g = lerpByte(a.g, b.g, t),
        .b = lerpByte(a.b, b.b, t),
        .a = lerpByte(a.a, b.a, t),
    };
}

fn lerpByte(a: u8, b: u8, t: f32) u8 {
    const af = @as(f32, @floatFromInt(a));
    const bf = @as(f32, @floatFromInt(b));
    const v = af + (bf - af) * t;
    return @as(u8, @intCast(@max(0, @min(255, @as(i32, @intFromFloat(v))))));
}

pub fn getGlyph(ch: u8) [8]u8 {
    const off = @as(usize, ch) * 8;
    if (off + 8 <= fontData.len) {
        var result: [8]u8 = .{0} ** 8;
        for (0..8) |i| {
            result[i] = @as(u8, @intCast(fontData[off + i]));
        }
        return result;
    }
    return .{0} ** 8;
}

const FONT_W = 8;
const FONT_H = 8;

const fontData = blk: {
    @setEvalBranchQuota(10000);
    var data: [128 * 8]u8 = .{0} ** 1024;
    const glyphs = [_][8]u8{
        // 32: space
        .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        // 33: !
        .{ 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x18, 0x00 },
        // 34: "
        .{ 0x6C, 0x6C, 0x6C, 0x00, 0x00, 0x00, 0x00, 0x00 },
        // 35: #
        .{ 0x28, 0x28, 0xFE, 0x28, 0xFE, 0x28, 0x28, 0x00 },
        // 36: $
        .{ 0x10, 0x3C, 0x50, 0x38, 0x14, 0x78, 0x10, 0x00 },
        // 37: %
        .{ 0x42, 0x44, 0x08, 0x10, 0x20, 0x44, 0x82, 0x00 },
        // 38: &
        .{ 0x30, 0x48, 0x48, 0x30, 0x4A, 0x44, 0x3A, 0x00 },
        // 39: '
        .{ 0x30, 0x30, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00 },
        // 40: (
        .{ 0x04, 0x08, 0x10, 0x10, 0x10, 0x08, 0x04, 0x00 },
        // 41: )
        .{ 0x40, 0x20, 0x10, 0x10, 0x10, 0x20, 0x40, 0x00 },
        // 42: *
        .{ 0x00, 0x24, 0x18, 0x7E, 0x18, 0x24, 0x00, 0x00 },
        // 43: +
        .{ 0x00, 0x10, 0x10, 0x7C, 0x10, 0x10, 0x00, 0x00 },
        // 44: ,
        .{ 0x00, 0x00, 0x00, 0x30, 0x30, 0x10, 0x60, 0x00 },
        // 45: -
        .{ 0x00, 0x00, 0x00, 0x7C, 0x00, 0x00, 0x00, 0x00 },
        // 46: .
        .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x30, 0x00 },
        // 47: /
        .{ 0x04, 0x04, 0x08, 0x10, 0x10, 0x20, 0x40, 0x40 },
        // 48: 0
        .{ 0x3C, 0x42, 0x46, 0x4A, 0x52, 0x62, 0x42, 0x3C },
        // 49: 1
        .{ 0x10, 0x30, 0x10, 0x10, 0x10, 0x10, 0x38, 0x00 },
        // 50: 2
        .{ 0x3C, 0x42, 0x02, 0x0C, 0x30, 0x40, 0x7E, 0x00 },
        // 51: 3
        .{ 0x3C, 0x42, 0x02, 0x1C, 0x02, 0x42, 0x3C, 0x00 },
        // 52: 4
        .{ 0x0C, 0x14, 0x24, 0x44, 0x7E, 0x04, 0x04, 0x00 },
        // 53: 5
        .{ 0x7E, 0x40, 0x78, 0x04, 0x02, 0x44, 0x38, 0x00 },
        // 54: 6
        .{ 0x1C, 0x24, 0x40, 0x78, 0x44, 0x44, 0x38, 0x00 },
        // 55: 7
        .{ 0x7E, 0x02, 0x04, 0x08, 0x10, 0x20, 0x20, 0x00 },
        // 56: 8
        .{ 0x3C, 0x42, 0x42, 0x3C, 0x42, 0x42, 0x3C, 0x00 },
        // 57: 9
        .{ 0x3C, 0x42, 0x42, 0x3E, 0x02, 0x24, 0x18, 0x00 },
        // 58: :
        .{ 0x00, 0x30, 0x30, 0x00, 0x00, 0x30, 0x30, 0x00 },
        // 59: ;
        .{ 0x00, 0x30, 0x30, 0x00, 0x00, 0x10, 0x20, 0x00 },
        // 60: <
        .{ 0x04, 0x08, 0x10, 0x20, 0x10, 0x08, 0x04, 0x00 },
        // 61: =
        .{ 0x00, 0x00, 0x7E, 0x00, 0x00, 0x7E, 0x00, 0x00 },
        // 62: >
        .{ 0x40, 0x20, 0x10, 0x08, 0x10, 0x20, 0x40, 0x00 },
        // 63: ?
        .{ 0x3C, 0x42, 0x02, 0x0C, 0x10, 0x00, 0x10, 0x00 },
        // 64: @
        .{ 0x3C, 0x42, 0x5A, 0x56, 0x5E, 0x40, 0x3C, 0x00 },
        // 65: A
        .{ 0x18, 0x24, 0x42, 0x7E, 0x42, 0x42, 0x42, 0x00 },
        // 66: B
        .{ 0x7C, 0x42, 0x42, 0x7C, 0x42, 0x42, 0x7C, 0x00 },
        // 67: C
        .{ 0x3C, 0x42, 0x40, 0x40, 0x40, 0x42, 0x3C, 0x00 },
        // 68: D
        .{ 0x78, 0x44, 0x42, 0x42, 0x42, 0x44, 0x78, 0x00 },
        // 69: E
        .{ 0x7E, 0x40, 0x40, 0x7C, 0x40, 0x40, 0x7E, 0x00 },
        // 70: F
        .{ 0x7E, 0x40, 0x40, 0x7C, 0x40, 0x40, 0x40, 0x00 },
        // 71: G
        .{ 0x3C, 0x42, 0x40, 0x4E, 0x42, 0x42, 0x3C, 0x00 },
        // 72: H
        .{ 0x42, 0x42, 0x42, 0x7E, 0x42, 0x42, 0x42, 0x00 },
        // 73: I
        .{ 0x3C, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00 },
        // 74: J
        .{ 0x1E, 0x04, 0x04, 0x04, 0x04, 0x44, 0x38, 0x00 },
        // 75: K
        .{ 0x42, 0x44, 0x48, 0x70, 0x48, 0x44, 0x42, 0x00 },
        // 76: L
        .{ 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x7E, 0x00 },
        // 77: M
        .{ 0x42, 0x66, 0x5A, 0x42, 0x42, 0x42, 0x42, 0x00 },
        // 78: N
        .{ 0x42, 0x62, 0x52, 0x4A, 0x46, 0x42, 0x42, 0x00 },
        // 79: O
        .{ 0x3C, 0x42, 0x42, 0x42, 0x42, 0x42, 0x3C, 0x00 },
        // 80: P
        .{ 0x7C, 0x42, 0x42, 0x7C, 0x40, 0x40, 0x40, 0x00 },
        // 81: Q
        .{ 0x3C, 0x42, 0x42, 0x42, 0x4A, 0x44, 0x3A, 0x00 },
        // 82: R
        .{ 0x7C, 0x42, 0x42, 0x7C, 0x48, 0x44, 0x42, 0x00 },
        // 83: S
        .{ 0x3C, 0x42, 0x40, 0x3C, 0x02, 0x42, 0x3C, 0x00 },
        // 84: T
        .{ 0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00 },
        // 85: U
        .{ 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x3C, 0x00 },
        // 86: V
        .{ 0x42, 0x42, 0x42, 0x24, 0x24, 0x18, 0x18, 0x00 },
        // 87: W
        .{ 0x42, 0x42, 0x42, 0x42, 0x5A, 0x66, 0x42, 0x00 },
        // 88: X
        .{ 0x42, 0x42, 0x24, 0x18, 0x24, 0x42, 0x42, 0x00 },
        // 89: Y
        .{ 0x42, 0x42, 0x24, 0x18, 0x18, 0x18, 0x18, 0x00 },
        // 90: Z
        .{ 0x7E, 0x04, 0x08, 0x10, 0x20, 0x40, 0x7E, 0x00 },
        // 91: [
        .{ 0x3C, 0x20, 0x20, 0x20, 0x20, 0x20, 0x3C, 0x00 },
        // 92: backslash
        .{ 0x40, 0x40, 0x20, 0x10, 0x10, 0x08, 0x04, 0x04 },
        // 93: ]
        .{ 0x78, 0x08, 0x08, 0x08, 0x08, 0x08, 0x78, 0x00 },
        // 94: ^
        .{ 0x10, 0x28, 0x44, 0x00, 0x00, 0x00, 0x00, 0x00 },
        // 95: _
        .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7E, 0x00 },
        // 96: `
        .{ 0x20, 0x10, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00 },
        // 97: a
        .{ 0x00, 0x38, 0x04, 0x3C, 0x44, 0x44, 0x3C, 0x00 },
        // 98: b
        .{ 0x40, 0x40, 0x5C, 0x62, 0x42, 0x62, 0x5C, 0x00 },
        // 99: c
        .{ 0x00, 0x00, 0x3C, 0x42, 0x40, 0x42, 0x3C, 0x00 },
        // 100: d
        .{ 0x02, 0x02, 0x3A, 0x46, 0x42, 0x46, 0x3A, 0x00 },
        // 101: e
        .{ 0x00, 0x00, 0x3C, 0x42, 0x7E, 0x40, 0x3C, 0x00 },
        // 102: f
        .{ 0x0C, 0x12, 0x10, 0x7C, 0x10, 0x10, 0x10, 0x00 },
        // 103: g
        .{ 0x00, 0x00, 0x3A, 0x46, 0x46, 0x3A, 0x02, 0x3C },
        // 104: h
        .{ 0x40, 0x40, 0x5C, 0x62, 0x42, 0x42, 0x42, 0x00 },
        // 105: i
        .{ 0x08, 0x00, 0x18, 0x08, 0x08, 0x08, 0x1C, 0x00 },
        // 106: j
        .{ 0x04, 0x00, 0x0C, 0x04, 0x04, 0x04, 0x44, 0x38 },
        // 107: k
        .{ 0x40, 0x40, 0x44, 0x48, 0x70, 0x48, 0x44, 0x00 },
        // 108: l
        .{ 0x18, 0x08, 0x08, 0x08, 0x08, 0x08, 0x1C, 0x00 },
        // 109: m
        .{ 0x00, 0x00, 0x6C, 0x52, 0x52, 0x52, 0x52, 0x00 },
        // 110: n
        .{ 0x00, 0x00, 0x5C, 0x62, 0x42, 0x42, 0x42, 0x00 },
        // 111: o
        .{ 0x00, 0x00, 0x3C, 0x42, 0x42, 0x42, 0x3C, 0x00 },
        // 112: p
        .{ 0x00, 0x00, 0x5C, 0x62, 0x62, 0x5C, 0x40, 0x40 },
        // 113: q
        .{ 0x00, 0x00, 0x3A, 0x46, 0x46, 0x3A, 0x02, 0x02 },
        // 114: r
        .{ 0x00, 0x00, 0x5C, 0x62, 0x40, 0x40, 0x40, 0x00 },
        // 115: s
        .{ 0x00, 0x00, 0x3E, 0x40, 0x3C, 0x02, 0x7C, 0x00 },
        // 116: t
        .{ 0x10, 0x10, 0x7C, 0x10, 0x10, 0x12, 0x0C, 0x00 },
        // 117: u
        .{ 0x00, 0x00, 0x42, 0x42, 0x42, 0x46, 0x3A, 0x00 },
        // 118: v
        .{ 0x00, 0x00, 0x42, 0x42, 0x24, 0x24, 0x18, 0x00 },
        // 119: w
        .{ 0x00, 0x00, 0x42, 0x42, 0x5A, 0x66, 0x42, 0x00 },
        // 120: x
        .{ 0x00, 0x00, 0x42, 0x24, 0x18, 0x24, 0x42, 0x00 },
        // 121: y
        .{ 0x00, 0x00, 0x42, 0x42, 0x26, 0x1A, 0x02, 0x3C },
        // 122: z
        .{ 0x00, 0x00, 0x7E, 0x04, 0x18, 0x20, 0x7E, 0x00 },
        // 123: {
        .{ 0x0E, 0x10, 0x10, 0x60, 0x10, 0x10, 0x0E, 0x00 },
        // 124: |
        .{ 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x00 },
        // 125: }
        .{ 0x70, 0x08, 0x08, 0x06, 0x08, 0x08, 0x70, 0x00 },
        // 126: ~
        .{ 0x00, 0x00, 0x62, 0x94, 0x88, 0x00, 0x00, 0x00 },
    };
    for (glyphs, 32..) |g, ascii| {
        for (g, 0..) |row, ri| {
            data[ascii * 8 + ri] = row;
        }
    }
    break :blk data;
};
