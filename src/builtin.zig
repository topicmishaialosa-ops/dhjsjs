const std = @import("builtin");

pub const Os = enum { linux, android, windows, macos, wasm, unknown };
pub const Arch = enum { x86_64, aarch64, unknown };

pub const os: Os = switch (std.target.os.tag) {
    .linux => .linux,
    .windows => .windows,
    .macos, .ios => .macos,
    .wasi => .wasm,
    else => .unknown,
};

pub const arch: Arch = switch (std.target.cpu.arch) {
    .x86_64 => .x86_64,
    .aarch64 => .aarch64,
    else => .unknown,
};

pub const is_linux = os == .linux;
pub const is_android = os == .android;
pub const is_windows = os == .windows;
pub const is_macos = os == .macos;
pub const is_x86_64 = arch == .x86_64;
pub const is_aarch64 = arch == .aarch64;
pub const page_size = std.mem.page_size;
