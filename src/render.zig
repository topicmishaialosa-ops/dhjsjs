const sys = @import("sys.zig");
const x11_mod = @import("x11.zig");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
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
    clip_x: i32,
    clip_y: i32,
    clip_w: u32,
    clip_h: u32,
    clip_active: bool,

    pub fn init(width: u32, height: u32) ?Framebuffer {
        const size = @as(usize, width) * @as(usize, height) * 4;
        const ptr = sys.mmap(null, size, 3, 34, -1, 0) orelse return null;
        return Framebuffer{
            .pixels = @ptrCast(@alignCast(ptr)),
            .width = width,
            .height = height,
            .stride = width,
            .clip_x = 0,
            .clip_y = 0,
            .clip_w = width,
            .clip_h = height,
            .clip_active = false,
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
        var x1: i32 = @max(0, x);
        var y1: i32 = @max(0, y);
        var x2: i32 = @min(@as(i32, @intCast(self.width)), x + @as(i32, @intCast(w)));
        var y2: i32 = @min(@as(i32, @intCast(self.height)), y + @as(i32, @intCast(h)));
        if (self.clip_active) {
            x1 = @max(x1, self.clip_x);
            y1 = @max(y1, self.clip_y);
            x2 = @min(x2, self.clip_x + @as(i32, @intCast(self.clip_w)));
            y2 = @min(y2, self.clip_y + @as(i32, @intCast(self.clip_h)));
        }
        if (x2 <= x1 or y2 <= y1) return;
        const uw = @as(usize, @intCast(x2 - x1));
        var yi = y1;
        while (yi < y2) : (yi += 1) {
            const row = @as(usize, @intCast(yi)) * self.stride + @as(usize, @intCast(x1));
            @memset(self.pixels[row .. row + uw], val);
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
        if (rr == 0) {
            self.fillRect4(x, y, w, h, c);
            return;
        }

        const x1 = x + rr_i;
        const x2 = x + @as(i32, @intCast(w)) - rr_i;
        const y1 = y + rr_i;
        const y2 = y + @as(i32, @intCast(h)) - rr_i;

        self.fillRect4(x1, y, w - rr * 2, h, c);
        self.fillRect4(x, y1, rr, h - rr * 2, c);
        self.fillRect4(x2, y1, rr, h - rr * 2, c);

        const rs = rr_i - 1;
        const r2 = rs * rs;
        var i: i32 = 0;
        const val = colorToU32(c);
        while (i <= rs) : (i += 1) {
            const di = rs - i;
            const di2 = di * di;
            const max_j2 = r2 - di2;
            var j: i32 = 0;
            while (j <= rs) : (j += 1) {
                const dj = rs - j;
                if (dj * dj <= max_j2) {
                    const x1j = @as(usize, @intCast(x1 - 1 - j));
                    const x2j = @as(usize, @intCast(x2 + j));
                    const y1i = @as(usize, @intCast(y1 - 1 - i));
                    const y2i = @as(usize, @intCast(y2 + i));
                    var row = y1i * self.stride;
                    self.pixels[row + x1j] = val;
                    self.pixels[row + x2j] = val;
                    row = y2i * self.stride;
                    self.pixels[row + x1j] = val;
                    self.pixels[row + x2j] = val;
                }
            }
        }
    }

    pub fn setClip(self: *Framebuffer, x: i32, y: i32, w: u32, h: u32) void {
        self.clip_x = x;
        self.clip_y = y;
        self.clip_w = w;
        self.clip_h = h;
        self.clip_active = true;
    }

    pub fn clearClip(self: *Framebuffer) void {
        self.clip_active = false;
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
        const dx: i32 = if (x2 >= x1) x2 - x1 else x1 - x2;
        const dy: i32 = -@as(i32, if (y2 >= y1) y2 - y1 else y1 - y2);
        const sx: i32 = if (x1 < x2) 1 else -1;
        const sy: i32 = if (y1 < y2) 1 else -1;
        var err = dx + dy;
        var cx = x1;
        var cy = y1;
        while (true) {
            self.setPixel(cx, cy, c);
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

    pub fn drawTriangleFilled(self: *Framebuffer, x1: i32, y1: i32, x2: i32, y2: i32, x3: i32, y3: i32, c: Color) void {
        const min_x = @max(0, @min(x1, @min(x2, x3)));
        const min_y = @max(0, @min(y1, @min(y2, y3)));
        const max_x = @min(@as(i32, @intCast(self.width - 1)), @max(x1, @max(x2, x3)));
        const max_y = @min(@as(i32, @intCast(self.height - 1)), @max(y1, @max(y2, y3)));
        if (min_x > max_x or min_y > max_y) return;
        const val = colorToU32(c);
        var y = min_y;
        while (y <= max_y) : (y += 1) {
            const row = @as(usize, @intCast(y)) * self.stride;
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const w0 = edge(x1, y1, x2, y2, x, y);
                const w1 = edge(x2, y2, x3, y3, x, y);
                const w2 = edge(x3, y3, x1, y1, x, y);
                if (w0 >= 0 and w1 >= 0 and w2 >= 0) {
                    self.pixels[row + @as(usize, @intCast(x))] = val;
                }
            }
        }
    }

    pub fn drawQuadBezier(self: *Framebuffer, x0: i32, y0: i32, x1: i32, y1: i32, x2: i32, y2: i32, c: Color, steps: u32) void {
        const s = @max(steps, 1);
        var px = x0;
        var py = y0;
        var i: u32 = 1;
        while (i <= s) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(s));
            const one_t = 1.0 - t;
            const nx = @as(i32, @intFromFloat(one_t * one_t * @as(f32, @floatFromInt(x0)) + 2.0 * one_t * t * @as(f32, @floatFromInt(x1)) + t * t * @as(f32, @floatFromInt(x2))));
            const ny = @as(i32, @intFromFloat(one_t * one_t * @as(f32, @floatFromInt(y0)) + 2.0 * one_t * t * @as(f32, @floatFromInt(y1)) + t * t * @as(f32, @floatFromInt(y2))));
            self.drawLine(px, py, nx, ny, c);
            px = nx;
            py = ny;
        }
    }

    pub fn fillRectGradientDir(self: *Framebuffer, x: i32, y: i32, w: u32, h: u32, c1: Color, c2: Color, dir: u8) void {
        if (w == 0 or h == 0) return;
        const r1 = @as(u32, c1.r) << 16 | @as(u32, c1.g) << 8 | @as(u32, c1.b);
        const r2 = @as(u32, c2.r) << 16 | @as(u32, c2.g) << 8 | @as(u32, c2.b);
        const wa = if (dir <= 1) @as(u32, if (dir == 0) h else w) else w + h;
        if (wa == 0) return;
        var yi: i32 = 0;
        while (yi < @as(i32, @intCast(h))) : (yi += 1) {
            var xi: i32 = 0;
            while (xi < @as(i32, @intCast(w))) : (xi += 1) {
                const num: u32 = switch (dir) {
                    0 => @as(u32, @intCast(yi)),
                    1 => @as(u32, @intCast(xi)),
                    2 => @as(u32, @intCast(xi + yi)),
                    3 => @as(u32, @intCast(yi)) + (w -| @as(u32, @intCast(xi))),
                    else => @as(u32, @intCast(yi)),
                };
                const ft = @min(wa, num) * 255 / wa;
                const inv = 255 - ft;
                const rr = ((r1 >> 16) & 0xFF) * inv + ((r2 >> 16) & 0xFF) * ft;
                const gg = ((r1 >> 8) & 0xFF) * inv + ((r2 >> 8) & 0xFF) * ft;
                const bb = (r1 & 0xFF) * inv + (r2 & 0xFF) * ft;
                const val = ((rr / 255) << 16) | ((gg / 255) << 8) | (bb / 255) | 0xFF000000;
                const y_abs = y + yi;
                const x_abs = x + xi;
                if (y_abs < 0 or y_abs >= @as(i32, @intCast(self.height))) continue;
                if (x_abs < 0 or x_abs >= @as(i32, @intCast(self.width))) continue;
                self.pixels[@as(usize, @intCast(y_abs)) * self.stride + @as(usize, @intCast(x_abs))] = val;
            }
        }
    }

    pub fn blendPixel(self: *Framebuffer, x: i32, y: i32, src: Color) void {
        if (x < 0 or y < 0) return;
        const ux = @as(u32, @intCast(x));
        const uy = @as(u32, @intCast(y));
        if (ux >= self.width or uy >= self.height) return;
        const dst = self.pixels[@as(usize, uy) * self.stride + ux];
        self.pixels[@as(usize, uy) * self.stride + ux] = blendU32(dst, colorToU32(src));
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
        const clip_l = if (self.clip_active) self.clip_x else @as(i32, 0);
        const clip_t = if (self.clip_active) self.clip_y else @as(i32, 0);
        const clip_r = if (self.clip_active) self.clip_x + @as(i32, @intCast(self.clip_w)) else @as(i32, @intCast(self.width));
        const clip_b = if (self.clip_active) self.clip_y + @as(i32, @intCast(self.clip_h)) else @as(i32, @intCast(self.height));
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
                        if (px >= clip_l and py >= clip_t and px < clip_r and py < clip_b and
                            px < @as(i32, @intCast(self.width)) and py < @as(i32, @intCast(self.height)))
                        {
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

pub const Canvas = struct {
    fb: *Framebuffer,
    xconn: ?*x11_mod.X11Conn,
    dirty_x1: i32,
    dirty_y1: i32,
    dirty_x2: i32,
    dirty_y2: i32,
    clip_x: i32,
    clip_y: i32,
    clip_w: u32,
    clip_h: u32,
    clip_active: bool,

    pub fn init(fb: *Framebuffer) Canvas {
        return Canvas{
            .fb = fb,
            .xconn = null,
            .dirty_x1 = @as(i32, @intCast(fb.width)),
            .dirty_y1 = @as(i32, @intCast(fb.height)),
            .dirty_x2 = 0,
            .dirty_y2 = 0,
            .clip_x = 0,
            .clip_y = 0,
            .clip_w = fb.width,
            .clip_h = fb.height,
            .clip_active = false,
        };
    }

    pub fn setNative(self: *Canvas, conn: *x11_mod.X11Conn) void {
        self.xconn = conn;
    }

    pub fn setClip(self: *Canvas, x: i32, y: i32, w: u32, h: u32) void {
        self.clip_x = x;
        self.clip_y = y;
        self.clip_w = w;
        self.clip_h = h;
        self.clip_active = true;
    }

    pub fn clearClip(self: *Canvas) void {
        self.clip_active = false;
    }

    pub fn markDirty(self: *Canvas, x: i32, y: i32, w: u32, h: u32) void {
        if (w == 0 or h == 0) return;
        const x2 = x + @as(i32, @intCast(w));
        const y2 = y + @as(i32, @intCast(h));
        if (x < self.dirty_x1) self.dirty_x1 = x;
        if (y < self.dirty_y1) self.dirty_y1 = y;
        if (x2 > self.dirty_x2) self.dirty_x2 = x2;
        if (y2 > self.dirty_y2) self.dirty_y2 = y2;
    }

    pub fn resetDirty(self: *Canvas) void {
        self.dirty_x1 = @as(i32, @intCast(self.fb.width));
        self.dirty_y1 = @as(i32, @intCast(self.fb.height));
        self.dirty_x2 = 0;
        self.dirty_y2 = 0;
    }

    fn clipBounds(self: *Canvas, x: i32, y: i32, w: u32, h: u32, out_x1: *i32, out_y1: *i32, out_x2: *i32, out_y2: *i32) void {
        var x1: i32 = @max(0, x);
        var y1: i32 = @max(0, y);
        var x2: i32 = @min(@as(i32, @intCast(self.fb.width)), x + @as(i32, @intCast(w)));
        var y2: i32 = @min(@as(i32, @intCast(self.fb.height)), y + @as(i32, @intCast(h)));
        if (self.clip_active) {
            x1 = @max(x1, self.clip_x);
            y1 = @max(y1, self.clip_y);
            x2 = @min(x2, self.clip_x + @as(i32, @intCast(self.clip_w)));
            y2 = @min(y2, self.clip_y + @as(i32, @intCast(self.clip_h)));
        }
        out_x1.* = x1;
        out_y1.* = y1;
        out_x2.* = x2;
        out_y2.* = y2;
    }

    fn fillRectSoft(self: *Canvas, x: i32, y: i32, w: u32, h: u32, color: u32) void {
        if (w == 0 or h == 0) return;
        var x1: i32 = undefined;
        var y1: i32 = undefined;
        var x2: i32 = undefined;
        var y2: i32 = undefined;
        self.clipBounds(x, y, w, h, &x1, &y1, &x2, &y2);
        if (x2 <= x1 or y2 <= y1) return;
        const uw = @as(usize, @intCast(x2 - x1));
        var yi = y1;
        while (yi < y2) : (yi += 1) {
            const row = @as(usize, @intCast(yi)) * self.fb.stride + @as(usize, @intCast(x1));
            @memset(self.fb.pixels[row .. row + uw], color);
        }
    }

    fn putPixel(self: *Canvas, x: i32, y: i32, color: u32) void {
        if (x < 0 or y < 0) return;
        if (self.clip_active) {
            if (x < self.clip_x or y < self.clip_y) return;
            if (x >= self.clip_x + @as(i32, @intCast(self.clip_w))) return;
            if (y >= self.clip_y + @as(i32, @intCast(self.clip_h))) return;
        }
        const ux = @as(u32, @intCast(x));
        const uy = @as(u32, @intCast(y));
        if (ux >= self.fb.width or uy >= self.fb.height) return;
        self.fb.pixels[@as(usize, uy) * self.fb.stride + ux] = color;
        if (x < self.dirty_x1) self.dirty_x1 = x;
        if (y < self.dirty_y1) self.dirty_y1 = y;
        if (x + 1 > self.dirty_x2) self.dirty_x2 = x + 1;
        if (y + 1 > self.dirty_y2) self.dirty_y2 = y + 1;
    }

    pub fn fillRect(self: *Canvas, x: i32, y: i32, w: u32, h: u32, color: u32) void {
        if (w == 0 or h == 0) return;
        const can_native = self.xconn != null and !self.clip_active and (color >> 24) == 0xFF;
        if (can_native) {
            const x1: i32 = @max(0, x);
            const y1: i32 = @max(0, y);
            const x2: i32 = @min(@as(i32, @intCast(self.fb.width)), x + @as(i32, @intCast(w)));
            const y2: i32 = @min(@as(i32, @intCast(self.fb.height)), y + @as(i32, @intCast(h)));
            if (x2 <= x1 or y2 <= y1) return;
            const conn = self.xconn.?;
            conn.setFillColor(color);
            conn.fillRect(@as(i16, @intCast(x1)), @as(i16, @intCast(y1)), @as(u16, @intCast(x2 - x1)), @as(u16, @intCast(y2 - y1)));
            return;
        }
        self.fillRectSoft(x, y, w, h, color);
        self.markDirty(x, y, w, h);
    }

    pub fn fillRoundedRect(self: *Canvas, x: i32, y: i32, w: u32, h: u32, r: u32, color: u32) void {
        if (r == 0 or w < r * 2 or h < r * 2) {
            self.fillRect(x, y, w, h, color);
            return;
        }
        const rr = @min(r, @min(w, h) / 2);
        const rr_i = @as(i32, @intCast(rr));
        const x1 = x + rr_i;
        const y1 = y + rr_i;
        const x2 = x + @as(i32, @intCast(w)) - rr_i;
        const y2 = y + @as(i32, @intCast(h)) - rr_i;
        self.fillRect(x1, y, w - rr * 2, h, color);
        self.fillRect(x, y1, rr, @as(u32, @intCast(y2 - y1)), color);
        self.fillRect(x2, y1, rr, @as(u32, @intCast(y2 - y1)), color);
        const rr1 = rr_i - 1;
        if (rr1 <= 0) return;
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
                    const px2 = x + @as(i32, @intCast(w)) - rr_i + dx;
                    const py1 = y + rr1 - dy;
                    const py2 = y + @as(i32, @intCast(h)) - rr_i + dy;
                    self.putPixel(px1, py1, color);
                    self.putPixel(px2, py1, color);
                    self.putPixel(px1, py2, color);
                    self.putPixel(px2, py2, color);
                }
            }
        }
    }

    pub fn drawBorder(self: *Canvas, x: i32, y: i32, w: u32, h: u32, color: u32) void {
        if (w < 2 or h < 2) {
            self.fillRect(x, y, w, h, color);
            return;
        }
        self.fillRect(x, y, w, 1, color);
        self.fillRect(x, y + @as(i32, @intCast(h)) - 1, w, 1, color);
        self.fillRect(x, y, 1, h, color);
        self.fillRect(x + @as(i32, @intCast(w)) - 1, y, 1, h, color);
    }

    pub fn drawInsetBorder(self: *Canvas, x: i32, y: i32, w: u32, h: u32, light: u32, dark: u32) void {
        if (w < 2 or h < 2) return;
        self.fillRect(x, y, w - 1, 1, light);
        self.fillRect(x, y, 1, h - 1, light);
        self.fillRect(x + @as(i32, @intCast(w)) - 1, y, 1, h, dark);
        self.fillRect(x, y + @as(i32, @intCast(h)) - 1, w, 1, dark);
    }

    pub fn drawLine(self: *Canvas, x1: i32, y1: i32, x2: i32, y2: i32, color: u32) void {
        const dx: i32 = if (x2 >= x1) x2 - x1 else x1 - x2;
        const dy_abs: i32 = if (y2 >= y1) y2 - y1 else y1 - y2;
        const dy: i32 = -dy_abs;
        const sx: i32 = if (x1 < x2) 1 else -1;
        const sy: i32 = if (y1 < y2) 1 else -1;
        var err = dx + dy;
        var cx = x1;
        var cy = y1;
        while (true) {
            self.putPixel(cx, cy, color);
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
        const min_x = if (x1 < x2) x1 else x2;
        const min_y = if (y1 < y2) y1 else y2;
        const max_x = if (x1 > x2) x1 else x2;
        const max_y = if (y1 > y2) y1 else y2;
        self.markDirty(min_x, min_y, @as(u32, @intCast(max_x - min_x + 1)), @as(u32, @intCast(max_y - min_y + 1)));
    }

    pub fn drawCircle(self: *Canvas, cx: i32, cy: i32, r: i32, color: u32) void {
        var dy = -r;
        while (dy <= r) : (dy += 1) {
            var dx = -r;
            while (dx <= r) : (dx += 1) {
                if (dx * dx + dy * dy <= r * r) self.putPixel(cx + dx, cy + dy, color);
            }
        }
        self.markDirty(cx - r, cy - r, @as(u32, @intCast(r * 2 + 1)), @as(u32, @intCast(r * 2 + 1)));
    }

    pub fn drawTriangleFilled(self: *Canvas, x1: i32, y1: i32, x2: i32, y2: i32, x3: i32, y3: i32, color: u32) void {
        var min_y = @min(y1, @min(y2, y3));
        var max_y = @max(y1, @max(y2, y3));
        if (self.clip_active) {
            min_y = @max(min_y, self.clip_y);
            max_y = @min(max_y, self.clip_y + @as(i32, @intCast(self.clip_h)) - 1);
        }
        min_y = @max(min_y, 0);
        max_y = @min(max_y, @as(i32, @intCast(self.fb.height)) - 1);
        if (min_y > max_y) return;

        var py = min_y;
        while (py <= max_y) : (py += 1) {
            var xs: [3]i32 = undefined;
            var count: usize = 0;
            const segs = [_][4]i32{
                .{ x1, y1, x2, y2 },
                .{ x2, y2, x3, y3 },
                .{ x3, y3, x1, y1 },
            };
            for (segs) |seg| {
                const ax = seg[0];
                const ay = seg[1];
                const bx = seg[2];
                const by = seg[3];
                if (ay == by) continue;
                if ((py < ay and py < by) or (py > ay and py > by)) continue;
                if (count < xs.len) {
                    xs[count] = ax + @divFloor((py - ay) * (bx - ax), by - ay);
                    count += 1;
                }
            }
            if (count < 2) continue;
            if (xs[0] > xs[1]) {
                const tmp = xs[0];
                xs[0] = xs[1];
                xs[1] = tmp;
            }
            var px = xs[0];
            while (px <= xs[1]) : (px += 1) {
                self.putPixel(px, py, color);
            }
        }
    }

    pub fn drawQuadBezier(self: *Canvas, x0: i32, y0: i32, x1: i32, y1: i32, x2: i32, y2: i32, color: u32, steps: u32) void {
        const s = @max(steps, 1);
        var px = x0;
        var py = y0;
        var i: u32 = 1;
        while (i <= s) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(s));
            const one_t = 1.0 - t;
            const nx = @as(i32, @intFromFloat(one_t * one_t * @as(f32, @floatFromInt(x0)) + 2.0 * one_t * t * @as(f32, @floatFromInt(x1)) + t * t * @as(f32, @floatFromInt(x2))));
            const ny = @as(i32, @intFromFloat(one_t * one_t * @as(f32, @floatFromInt(y0)) + 2.0 * one_t * t * @as(f32, @floatFromInt(y1)) + t * t * @as(f32, @floatFromInt(y2))));
            self.drawLine(px, py, nx, ny, color);
            px = nx;
            py = ny;
        }
    }

    pub fn drawText(self: *Canvas, text: []const u8, x: i32, y: i32, color: u32, size: u32) void {
        const scale = if (size >= 8) @as(u32, @intCast(@divFloor(size, 8))) else 1;
        var cx = x;
        var cy = y;
        for (text) |ch| {
            if (ch == '\n') {
                cy += @as(i32, @intCast(scale * 8 + 2));
                cx = x;
                continue;
            }
            const glyph = getGlyph(ch);
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
                                self.putPixel(bx + @as(i32, @intCast(sx)), by + @as(i32, @intCast(sy)), color);
                            }
                        }
                    }
                }
            }
            cx += @as(i32, @intCast(scale * 8 + 2));
        }
        self.markDirty(x, y, @as(u32, @intCast(text.len * 10 + 2)), size + 4);
    }

    pub fn drawShadow(self: *Canvas, x: i32, y: i32, w: u32, h: u32, intensity: u8, r: u32) void {
        if (intensity < 10) return;
        const a1 = intensity / 3;
        const a2 = intensity / 5;
        const a3 = intensity / 9;
        const c1: u32 = 0xFF000000 | (@as(u32, a1) << 16) | (@as(u32, a1) << 8) | @as(u32, a1);
        const c2: u32 = 0xFF000000 | (@as(u32, a2) << 16) | (@as(u32, a2) << 8) | @as(u32, a2);
        const c3: u32 = 0xFF000000 | (@as(u32, a3) << 16) | (@as(u32, a3) << 8) | @as(u32, a3);
        const sr1 = if (r > 2) r - 2 else 0;
        const sr2 = if (r > 3) r - 3 else 0;
        self.fillRoundedRect(x + 1, y + 2, w, h, sr2, c3);
        self.fillRoundedRect(x + 2, y + 2, w, h, sr1, c2);
        self.fillRoundedRect(x + 3, y + 3, w, h, r - 1, c1);
    }

    pub fn drawShadowSoft(self: *Canvas, x: i32, y: i32, w: u32, h: u32, intensity: u8, r: u32) void {
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
        self.fillRoundedRect(x + 1, y + 2, w, h, sr3, c3);
        self.fillRoundedRect(x + 2, y + 2, w, h, sr2, c2);
        self.fillRoundedRect(x + 3, y + 3, w, h, sr1, c1);
    }

    pub fn fillRectGradientDir(self: *Canvas, x: i32, y: i32, w: u32, h: u32, c1: u32, c2: u32, dir: u8) void {
        self.fb.fillRectGradientDir(
            x,
            y,
            w,
            h,
            rgba(@as(u8, @intCast((c1 >> 16) & 0xFF)), @as(u8, @intCast((c1 >> 8) & 0xFF)), @as(u8, @intCast(c1 & 0xFF)), @as(u8, @intCast((c1 >> 24) & 0xFF))),
            rgba(@as(u8, @intCast((c2 >> 16) & 0xFF)), @as(u8, @intCast((c2 >> 8) & 0xFF)), @as(u8, @intCast(c2 & 0xFF)), @as(u8, @intCast((c2 >> 24) & 0xFF))),
            dir,
        );
        self.markDirty(x, y, w, h);
    }

    pub fn fillRoundedRectGradV(self: *Canvas, x: i32, y: i32, w: u32, h: u32, r: u32, top: u32, bot: u32) void {
        self.fillRoundedRect(x, y, w, h, r, bot);
        if (h < 4 or w < 4) return;
        const shine_h = h / 2 + r;
        self.fillRectGradientDir(x + @as(i32, @intCast(r)), y, w -| @as(u32, r) * 2, @as(u32, @intCast(shine_h)), top, bot, 0);
        self.fillRectGradientDir(x, y + @as(i32, @intCast(r)), r, @as(u32, @intCast(@max(0, @as(i32, @intCast(shine_h)) - @as(i32, @intCast(r))))), top, bot, 0);
        self.fillRectGradientDir(x + @as(i32, @intCast(w)) - @as(i32, @intCast(r)), y + @as(i32, @intCast(r)), r, @as(u32, @intCast(@max(0, @as(i32, @intCast(shine_h)) - @as(i32, @intCast(r))))), top, bot, 0);
    }

    pub fn fillRoundedRectGlow(self: *Canvas, x: i32, y: i32, w: u32, h: u32, r: u32, color: u32, glow: u8) void {
        if (glow < 4) return;
        const glow_color = mixU32(color, 0xFFFFFFFF, glow);
        const glow_r = if (r > 2) r - 2 else 0;
        self.fillRoundedRect(x - 2, y - 1, w + 4, h + 2, @max(glow_r, 1), mixU32(glow_color, color, 160));
        self.fillRoundedRect(x - 1, y, w + 2, h, @max(glow_r, 1), mixU32(glow_color, color, 200));
    }

    pub fn flush(self: *Canvas) void {
        if (self.xconn) |conn| {
            if (self.dirty_x2 > self.dirty_x1 and self.dirty_y2 > self.dirty_y1) {
                if (self.dirty_x1 >= 0 and self.dirty_y1 >= 0) {
                    const dx = @as(u32, @intCast(self.dirty_x1));
                    const dy = @as(u32, @intCast(self.dirty_y1));
                    const dw = @as(u32, @intCast(self.dirty_x2 - self.dirty_x1));
                    const dh = @as(u32, @intCast(self.dirty_y2 - self.dirty_y1));
                    conn.putImageRegion(self.fb.pixels, self.fb.stride, dx, dy, dw, dh, @as(i16, @intCast(self.dirty_x1)), @as(i16, @intCast(self.dirty_y1)));
                }
                self.resetDirty();
            }
        }
    }
};

pub fn mixU32(a: u32, b: u32, amount_b: u8) u32 {
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

pub fn blendU32(dst: u32, src: u32) u32 {
    const sa = (src >> 24) & 0xFF;
    if (sa == 0) return dst;
    if (sa == 255) return src;
    const da = 255 - sa;
    const sr = (src >> 16) & 0xFF;
    const sg = (src >> 8) & 0xFF;
    const sb = src & 0xFF;
    const dr = (dst >> 16) & 0xFF;
    const dg = (dst >> 8) & 0xFF;
    const db = dst & 0xFF;
    const r = (@as(u32, sr) * @as(u32, sa) + @as(u32, dr) * @as(u32, da)) / 255;
    const g = (@as(u32, sg) * @as(u32, sa) + @as(u32, dg) * @as(u32, da)) / 255;
    const b = (@as(u32, sb) * @as(u32, sa) + @as(u32, db) * @as(u32, da)) / 255;
    const a = sa + @as(u32, da) - (@as(u32, sa) * @as(u32, da)) / 255;
    return (a << 24) | (r << 16) | (g << 8) | b;
}

fn edge(ax: i32, ay: i32, bx: i32, by: i32, cx: i32, cy: i32) i32 {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}

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
        .{ 0x24, 0x24, 0xFE, 0x24, 0xFE, 0x24, 0x24, 0x00 },
        // 36: $
        .{ 0x10, 0x3C, 0x50, 0x38, 0x14, 0x78, 0x10, 0x00 },
        // 37: %
        .{ 0x62, 0x64, 0x08, 0x10, 0x20, 0x46, 0x8E, 0x00 },
        // 38: &
        .{ 0x30, 0x48, 0x48, 0x30, 0x4A, 0x44, 0x3A, 0x00 },
        // 39: '
        .{ 0x30, 0x30, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00 },
        // 40: (
        .{ 0x04, 0x0C, 0x18, 0x18, 0x18, 0x0C, 0x04, 0x00 },
        // 41: )
        .{ 0x40, 0x60, 0x30, 0x30, 0x30, 0x60, 0x40, 0x00 },
        // 42: *
        .{ 0x00, 0x24, 0x18, 0x7E, 0x18, 0x24, 0x00, 0x00 },
        // 43: +
        .{ 0x00, 0x10, 0x10, 0x7C, 0x10, 0x10, 0x00, 0x00 },
        // 44: ,
        .{ 0x00, 0x00, 0x00, 0x00, 0x38, 0x18, 0x08, 0x30 },
        // 45: -
        .{ 0x00, 0x00, 0x00, 0x7C, 0x00, 0x00, 0x00, 0x00 },
        // 46: .
        .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x30, 0x00 },
        // 47: /
        .{ 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x00 },
        // 48: 0
        .{ 0x3C, 0x42, 0x46, 0x4A, 0x52, 0x62, 0x42, 0x3C },
        // 49: 1
        .{ 0x10, 0x30, 0x10, 0x10, 0x10, 0x10, 0x7C, 0x00 },
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
        .{ 0x00, 0x30, 0x30, 0x00, 0x00, 0x38, 0x18, 0x30 },
        // 60: <
        .{ 0x04, 0x08, 0x10, 0x20, 0x10, 0x08, 0x04, 0x00 },
        // 61: =
        .{ 0x00, 0x00, 0x7E, 0x00, 0x7E, 0x00, 0x00, 0x00 },
        // 62: >
        .{ 0x40, 0x20, 0x10, 0x08, 0x10, 0x20, 0x40, 0x00 },
        // 63: ?
        .{ 0x3C, 0x42, 0x02, 0x0C, 0x10, 0x00, 0x18, 0x00 },
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
        .{ 0x3C, 0x42, 0x40, 0x5E, 0x42, 0x42, 0x3C, 0x00 },
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
        .{ 0x42, 0x66, 0x5A, 0x5A, 0x42, 0x42, 0x42, 0x00 },
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
        .{ 0x42, 0x42, 0x42, 0x5A, 0x5A, 0x66, 0x42, 0x00 },
        // 88: X
        .{ 0x42, 0x42, 0x24, 0x18, 0x24, 0x42, 0x42, 0x00 },
        // 89: Y
        .{ 0x42, 0x42, 0x24, 0x18, 0x18, 0x18, 0x18, 0x00 },
        // 90: Z
        .{ 0x7E, 0x04, 0x08, 0x10, 0x20, 0x40, 0x7E, 0x00 },
        // 91: [
        .{ 0x3C, 0x20, 0x20, 0x20, 0x20, 0x20, 0x3C, 0x00 },
        // 92: backslash
        .{ 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x00 },
        // 93: ]
        .{ 0x78, 0x08, 0x08, 0x08, 0x08, 0x08, 0x78, 0x00 },
        // 94: ^
        .{ 0x10, 0x28, 0x44, 0x00, 0x00, 0x00, 0x00, 0x00 },
        // 95: _
        .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFE, 0x00 },
        // 96: `
        .{ 0x20, 0x10, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00 },
        // 97: a
        .{ 0x00, 0x00, 0x3C, 0x02, 0x3E, 0x42, 0x3E, 0x00 },
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
        .{ 0x10, 0x00, 0x18, 0x10, 0x10, 0x10, 0x1C, 0x00 },
        // 106: j
        .{ 0x08, 0x00, 0x0C, 0x08, 0x08, 0x08, 0x48, 0x30 },
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
        .{ 0x00, 0x00, 0x42, 0x42, 0x5A, 0x5A, 0x24, 0x00 },
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

pub export fn drawFillRoundRect(pixels: [*]u32, width: u32, height: u32, x: i32, y: i32, w: u32, h: u32, rad: u32, color: u32) void {
    var fb = Framebuffer{
        .pixels = pixels,
        .width = width,
        .height = height,
        .stride = width,
        .clip_x = 0,
        .clip_y = 0,
        .clip_w = width,
        .clip_h = height,
        .clip_active = false,
    };
    fb.fillRoundRect4(x, y, w, h, rad, Color{
        .r = @as(u8, @truncate((color >> 16) & 0xFF)),
        .g = @as(u8, @truncate((color >> 8) & 0xFF)),
        .b = @as(u8, @truncate(color & 0xFF)),
        .a = @as(u8, @truncate((color >> 24) & 0xFF)),
    });
}

pub export fn drawFillGradient(pixels: [*]u32, width: u32, height: u32, x: i32, y: i32, w: u32, h: u32, c1: u32, c2: u32, vertical: u32) void {
    var fb = Framebuffer{
        .pixels = pixels,
        .width = width,
        .height = height,
        .stride = width,
        .clip_x = 0, .clip_y = 0,
        .clip_w = width, .clip_h = height,
        .clip_active = false,
    };
    fb.fillRectGradient(x, y, w, h, colorFromU32(c1), colorFromU32(c2), vertical != 0);
}

pub export fn fillColor(pixels: [*]u32, width: u32, height: u32, color: u32) void {
    var fb = Framebuffer{
        .pixels = pixels,
        .width = width,
        .height = height,
        .stride = width,
        .clip_x = 0, .clip_y = 0,
        .clip_w = width, .clip_h = height,
        .clip_active = false,
    };
    fb.fill(colorFromU32(color));
}

pub export fn drawString(pixels: [*]u32, width: u32, height: u32, x: i32, y: i32, text: [*:0]const u8, color: u32, fontSize: u32) void {
    var fb = Framebuffer{
        .pixels = pixels,
        .width = width,
        .height = height,
        .stride = width,
        .clip_x = 0, .clip_y = 0,
        .clip_w = width, .clip_h = height,
        .clip_active = false,
    };
    var len: usize = 0;
    while (text[len] != 0) : (len += 1) {}
    fb.drawText(text[0..len], x, y, colorFromU32(color), fontSize);
}

pub export fn drawButton(pixels: [*]u32, width: u32, height: u32, x: i32, y: i32, w: u32, h: u32, rad: u32, bgColor: u32, textColor: u32, text: [*:0]const u8) void {
    drawFillRoundRect(pixels, width, height, x, y, w, h, rad, bgColor);
    var len: usize = 0;
    while (text[len] != 0) : (len += 1) {}
    const tx = x + @as(i32, @intCast(@divTrunc(w, 2))) - @as(i32, @intCast(@divTrunc(len * 7, 2)));
    const ty = y + @as(i32, @intCast(@divTrunc(h, 2))) - 4;
    drawString(pixels, width, height, tx, ty, text, textColor, 1);
}

fn colorFromU32(c: u32) Color {
    return Color{
        .r = @as(u8, @truncate((c >> 16) & 0xFF)),
        .g = @as(u8, @truncate((c >> 8) & 0xFF)),
        .b = @as(u8, @truncate(c & 0xFF)),
        .a = @as(u8, @truncate((c >> 24) & 0xFF)),
    };
}
