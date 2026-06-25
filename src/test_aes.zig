const crypto = @import("crypto.zig");
const sys = @import("sys.zig");

fn hex(data: []const u8) void {
    for (data) |b| {
        var h: [2]u8 = undefined;
        h[0] = @as(u8, if (b>>4 < 10) '0' + (b>>4) else 'a' + (b>>4) - 10);
        h[1] = @as(u8, if ((b&15) < 10) '0' + (b&15) else 'a' + ((b&15)) - 10);
        _ = sys.write(1, &h, 2);
    }
}

pub fn main() void {
    var key: [16]u8 = .{0} ** 16;
    var pt: [16]u8 = .{0} ** 16;
    
    // Print key schedule
    var ks: [176]u8 = undefined;
    crypto.aes128KeySchedule(&key, &ks);
    
    _ = sys.write(1, "key_schedule (first 48 bytes):\n", 31);
    var i: usize = 0;
    while (i < 48) : (i += 16) {
        hex(ks[i..][0..16]);
        _ = sys.write(1, "\n", 1);
    }
    
    // Trace encryption rounds manually
    var state: [16]u8 = undefined;
    @memcpy(state[0..16], pt[0..16]);
    
    // We need access to the internal functions, so let's just call the public one
    var ct: [16]u8 = undefined;
    crypto.aes128Encrypt(&pt, &ks, &ct);
    
    _ = sys.write(1, "ct: ", 4);
    hex(ct[0..]);
    _ = sys.write(1, "\n", 1);
    _ = sys.write(1, "exp: 66e94bd4ef8a2c3b884cfa59ca342b2e\n", 37);
}
