// ============================================================================
// gl3_api.zig — C-callable GL3 functions for dhjsjs language integration
// These are called by compiled dhjsjs programs via inline x86-64 codegen
// ============================================================================

const gl3 = @import("gl3.zig");

// All functions use callconv(.c) so they can be called from dhjsjs codegen

pub fn gl3Init(w: u32, h: u32) callconv(.c) u32 {
    return if (gl3.init(w, h)) 1 else 0;
}

pub fn gl3Deinit() callconv(.c) void {
    gl3.deinit();
}

pub fn gl3BeginFrame() callconv(.c) void {
    gl3.beginFrame();
}

pub fn gl3EndFrame() callconv(.c) void {
    gl3.endFrame();
}

pub fn gl3PollEvent() callconv(.c) i64 {
    // Returns encoded event: type in high 32, data in low 32
    // type 0=none, 1=key_press, 2=key_release, 3=mouse_down, 4=mouse_up, 5=mouse_move, 6=close
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

pub fn gl3IsActive() callconv(.c) u32 {
    return if (gl3.isActive()) 1 else 0;
}

pub fn gl3GetWidth() callconv(.c) u32 {
    return gl3.getWidth();
}

pub fn gl3GetHeight() callconv(.c) u32 {
    return gl3.getHeight();
}

pub fn gl3FillRect(x: i32, y: i32, w: i32, h: i32, color: u32) callconv(.c) void {
    gl3.fillRect(x, y, w, h, color);
}

pub fn gl3FillGradientH(x: i32, y: i32, w: i32, h: i32, c1: u32, c2: u32) callconv(.c) void {
    gl3.fillGradientH(x, y, w, h, c1, c2);
}

pub fn gl3FillGradientV(x: i32, y: i32, w: i32, h: i32, c1: u32, c2: u32) callconv(.c) void {
    gl3.fillGradientV(x, y, w, h, c1, c2);
}

pub fn gl3DrawBorder(x: i32, y: i32, w: i32, h: i32, color: u32, thickness: i32) callconv(.c) void {
    gl3.drawBorder(x, y, w, h, color, thickness);
}

pub fn gl3FillRoundedRect(x: i32, y: i32, w: i32, h: i32, r: i32, color: u32) callconv(.c) void {
    gl3.fillRoundedRect(x, y, w, h, r, color);
}

pub fn gl3DrawText(x: i32, y: i32, text_ptr: [*]const u8, text_len: u32, color: u32, scale: f32) callconv(.c) void {
    gl3.drawText(x, y, text_ptr[0..text_len], color, scale);
}

pub fn gl3Flush() callconv(.c) void {
    gl3.flush();
}

pub fn gl3SleepMs(ms: u32) callconv(.c) void {
    var ts: sys.Timespec = .{ .sec = @intCast(ms / 1000), .nsec = @intCast((ms % 1000) * 1_000_000) };
    _ = sys.nanosleep(&ts, null);
}

const sys = @import("sys.zig");
