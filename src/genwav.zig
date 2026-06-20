const std = @import("std");

pub fn main() !void {
    var file = try std.fs.cwd().createFile("test.wav", .{});
    defer file.close();

    const sample_rate: u32 = 44100;
    const channels: u16 = 1;
    const bits_per_sample: u16 = 16;
    const duration_sec: u32 = 3;
    const num_samples = sample_rate * duration_sec;
    const data_size = num_samples * channels * (bits_per_sample / 8);

    try file.writeAll("RIFF");
    try file.writeAll(&std.mem.toBytes(@as(u32, @intCast(36 + data_size))));
    try file.writeAll("WAVE");

    try file.writeAll("fmt ");
    try file.writeAll(&std.mem.toBytes(@as(u32, @intCast(16))));
    try file.writeAll(&std.mem.toBytes(@as(u16, @intCast(1))));
    try file.writeAll(&std.mem.toBytes(channels));
    try file.writeAll(&std.mem.toBytes(sample_rate));
    try file.writeAll(&std.mem.toBytes(@as(u32, @intCast(sample_rate * channels * (bits_per_sample / 8)))));
    try file.writeAll(&std.mem.toBytes(@as(u16, @intCast(channels * (bits_per_sample / 8)))));
    try file.writeAll(&std.mem.toBytes(bits_per_sample));

    try file.writeAll("data");
    try file.writeAll(&std.mem.toBytes(@as(u32, @intCast(data_size))));

    var i: u32 = 0;
    while (i < num_samples) : (i += 1) {
        const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(sample_rate));
        const freq = 440.0;
        const amp = 16000.0;
        const val = @as(i16, @intFromFloat(@sin(t * 2.0 * std.math.pi * freq) * amp));
        try file.writeAll(&std.mem.toBytes(val));
    }
}
