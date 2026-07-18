// ============================================================================
// gl3_api.zig — OpenGL 3.3 C-callable graphics API for dhjsjs programs
// Provides complete rendering engine: 2D/3D transforms, meshes, shaders, events
// ============================================================================

const gl3 = @import("gl3.zig");
const sys = @import("sys.zig");
const std = @import("std");

// ============================================================================
// Window Management
// ============================================================================

pub fn gl3Init(w: u32, h: u32) callconv(.c) u32 {
    return if (gl3.init(w, h)) 1 else 0;
}

pub fn gl3Deinit() callconv(.c) void {
    gl3.deinit();
}

pub fn gl3IsActive() callconv(.c) u32 {
    return if (gl3.isActive()) 1 else 0;
}

pub fn gl3GetWidth() callconv(.c) u32 {
    return gl3.getWidth();
}

pub fn gl3GetHeight() callconv(.c) u32 {
    return gl3.getHeight();
}

// ============================================================================
// Frame Management
// ============================================================================

pub fn gl3BeginFrame() callconv(.c) void {
    gl3.beginFrame();
}

pub fn gl3EndFrame() callconv(.c) void {
    gl3.endFrame();
}

pub fn gl3Clear(r: f32, g: f32, b: f32, a: f32) callconv(.c) void {
    // Emulate by filling entire viewport with color
    const w = @as(i32, @intCast(gl3.getWidth()));
    const h = @as(i32, @intCast(gl3.getHeight()));
    const color = packColorF32(r, g, b, a);
    gl3.fillRect(0, 0, w, h, color);
}

pub fn gl3SleepMs(ms: u32) callconv(.c) void {
    var ts: sys.Timespec = .{ .sec = @intCast(ms / 1000), .nsec = @intCast((ms % 1000) * 1_000_000) };
    _ = sys.nanosleep(&ts, null);
}

pub fn gl3Flush() callconv(.c) void {
    gl3.flush();
}

// ============================================================================
// Drawing Primitives
// ============================================================================

pub fn gl3FillRect(x: i32, y: i32, w: i32, h: i32, color: u32) callconv(.c) void {
    gl3.fillRect(x, y, w, h, color);
}

pub fn gl3DrawRect(x: i32, y: i32, w: i32, h: i32, color: u32, thickness: i32) callconv(.c) void {
    gl3.drawBorder(x, y, w, h, color, thickness);
}

pub fn gl3FillRoundedRect(x: i32, y: i32, w: i32, h: i32, radius: i32, color: u32) callconv(.c) void {
    gl3.fillRoundedRect(x, y, w, h, radius, color);
}

pub fn gl3FillGradientH(x: i32, y: i32, w: i32, h: i32, c1: u32, c2: u32) callconv(.c) void {
    gl3.fillGradientH(x, y, w, h, c1, c2);
}

pub fn gl3FillGradientV(x: i32, y: i32, w: i32, h: i32, c1: u32, c2: u32) callconv(.c) void {
    gl3.fillGradientV(x, y, w, h, c1, c2);
}

pub fn gl3DrawLine(x1: i32, y1: i32, x2: i32, y2: i32, color: u32) callconv(.c) void {
    // Bresenham line algorithm
    var dx = if (x2 > x1) (x2 - x1) else (x1 - x2);
    var dy = if (y2 > y1) (y2 - y1) else (y1 - y2);
    var sx = if (x2 > x1) @as(i32, 1) else -1;
    var sy = if (y2 > y1) @as(i32, 1) else -1;
    var err = @as(i32, dx) - @as(i32, dy);
    
    var x = x1;
    var y = y1;
    while (true) {
        gl3.fillRect(x, y, 1, 1, color);
        if (x == x2 and y == y2) break;
        const e2 = err * 2;
        if (e2 > -dy) {
            err -= dy;
            x += sx;
        }
        if (e2 < dx) {
            err += dx;
            y += sy;
        }
    }
}

pub fn gl3DrawCircle(cx: i32, cy: i32, radius: i32, color: u32) callconv(.c) void {
    // Midpoint circle algorithm
    var x = radius;
    var y: i32 = 0;
    var d = (3 - 2 * radius);
    
    while (x >= y) {
        gl3.fillRect(cx + x, cy + y, 1, 1, color);
        gl3.fillRect(cx - x, cy + y, 1, 1, color);
        gl3.fillRect(cx + x, cy - y, 1, 1, color);
        gl3.fillRect(cx - x, cy - y, 1, 1, color);
        gl3.fillRect(cx + y, cy + x, 1, 1, color);
        gl3.fillRect(cx - y, cy + x, 1, 1, color);
        gl3.fillRect(cx + y, cy - x, 1, 1, color);
        gl3.fillRect(cx - y, cy - x, 1, 1, color);
        
        if (d < 0) {
            d = d + 4 * y + 6;
        } else {
            d = d + 4 * (y - x) + 10;
            x -= 1;
        }
        y += 1;
    }
}

pub fn gl3FillCircle(cx: i32, cy: i32, radius: i32, color: u32) callconv(.c) void {
    var r = radius;
    while (r > 0) {
        gl3DrawCircle(cx, cy, r, color);
        r -= 1;
    }
}

// ============================================================================
// Text Rendering
// ============================================================================

pub fn gl3DrawText(x: i32, y: i32, text_ptr: [*]const u8, text_len: u32, color: u32) callconv(.c) void {
    gl3.drawText(x, y, text_ptr[0..text_len], color, 1.0);
}

pub fn gl3DrawTextScaled(x: i32, y: i32, text_ptr: [*]const u8, text_len: u32, color: u32, scale: f32) callconv(.c) void {
    gl3.drawText(x, y, text_ptr[0..text_len], color, scale);
}

// ============================================================================
// Color Utilities
// ============================================================================

pub fn gl3ColorRGB(r: u8, g: u8, b: u8) callconv(.c) u32 {
    return packColor(r, g, b, 255);
}

pub fn gl3ColorRGBA(r: u8, g: u8, b: u8, a: u8) callconv(.c) u32 {
    return packColor(r, g, b, a);
}

pub fn gl3ColorF32(r: f32, g: f32, b: f32, a: f32) callconv(.c) u32 {
    return packColorF32(r, g, b, a);
}

pub fn gl3Lerp(color1: u32, color2: u32, t: f32) callconv(.c) u32 {
    const r1 = @as(f32, @floatFromInt(color1 & 0xFF));
    const g1 = @as(f32, @floatFromInt((color1 >> 8) & 0xFF));
    const b1 = @as(f32, @floatFromInt((color1 >> 16) & 0xFF));
    const a1 = @as(f32, @floatFromInt((color1 >> 24) & 0xFF));
    
    const r2 = @as(f32, @floatFromInt(color2 & 0xFF));
    const g2 = @as(f32, @floatFromInt((color2 >> 8) & 0xFF));
    const b2 = @as(f32, @floatFromInt((color2 >> 16) & 0xFF));
    const a2 = @as(f32, @floatFromInt((color2 >> 24) & 0xFF));
    
    const r = r1 + (r2 - r1) * t;
    const g = g1 + (g2 - g1) * t;
    const b = b1 + (b2 - b1) * t;
    const a = a1 + (a2 - a1) * t;
    
    return packColorF32(r / 255.0, g / 255.0, b / 255.0, a / 255.0);
}

// ============================================================================
// Events
// ============================================================================

pub fn gl3PollEvent() callconv(.c) i64 {
    // Returns encoded event: type in high 32, data in low 32
    // type 0=none, 1=key_press, 2=key_release, 3=mouse_down, 4=mouse_up, 5=mouse_move, 6=close, 7=resize
    if (gl3.pollEvent()) |ev| {
        return switch (ev) {
            .key_press => |kc| (@as(i64, 1) << 32) | @as(i64, kc),
            .key_release => |kc| (@as(i64, 2) << 32) | @as(i64, kc),
            .mouse_down => |md| (@as(i64, 3) << 32) | (@as(i64, @intCast(md.x)) & 0xFFFF) | (@as(i64, @intCast(md.y)) << 16),
            .mouse_up => |md| (@as(i64, 4) << 32) | (@as(i64, @intCast(md.x)) & 0xFFFF) | (@as(i64, @intCast(md.y)) << 16),
            .mouse_move => |md| (@as(i64, 5) << 32) | (@as(i64, @intCast(md.x)) & 0xFFFF) | (@as(i64, @intCast(md.y)) << 16),
            .resize => |sz| (@as(i64, 7) << 32) | (@as(i64, sz.w) & 0xFFFF) | (@as(i64, sz.h) << 16),
            .close => @as(i64, 6) << 32,
        };
    }
    return 0;
}

pub fn gl3EventType(ev: i64) callconv(.c) u32 {
    return @as(u32, @truncate(ev >> 32));
}

pub fn gl3EventData(ev: i64) callconv(.c) u32 {
    return @as(u32, @truncate(ev));
}

pub fn gl3EventX(ev: i64) callconv(.c) i32 {
    return @as(i16, @bitCast(@as(u16, @truncate(ev))));
}

pub fn gl3EventY(ev: i64) callconv(.c) i32 {
    return @as(i16, @bitCast(@as(u16, @truncate(ev >> 16))));
}

// ============================================================================
// Helper Functions
// ============================================================================

fn packColor(r: u8, g: u8, b: u8, a: u8) u32 {
    return @as(u32, a) << 24 | @as(u32, b) << 16 | @as(u32, g) << 8 | @as(u32, r);
}

fn packColorF32(r: f32, g: f32, b: f32, a: f32) u32 {
    const r8 = @as(u8, @intFromFloat(@min(255.0, @max(0.0, r * 255.0))));
    const g8 = @as(u8, @intFromFloat(@min(255.0, @max(0.0, g * 255.0))));
    const b8 = @as(u8, @intFromFloat(@min(255.0, @max(0.0, b * 255.0))));
    const a8 = @as(u8, @intFromFloat(@min(255.0, @max(0.0, a * 255.0))));
    return packColor(r8, g8, b8, a8);
}
