const crypto = @import("crypto.zig");
const sys = @import("sys.zig");

fn hex_out(data: []const u8) void {
    for (data) |b| {
        var h: [2]u8 = undefined;
        h[0] = @as(u8, if (b>>4 < 10) '0' + (b>>4) else 'a' + (b>>4) - 10);
        h[1] = @as(u8, if ((b&15) < 10) '0' + (b&15) else 'a' + ((b&15)) - 10);
        _ = sys.write(1, &h, 2);
    }
}

pub fn main() void {
    // Test from our GCM test (with NIST key)
    var key: [16]u8 = .{0xfe, 0xff, 0xe9, 0x92, 0x86, 0x65, 0x73, 0x1c, 0x6d, 0x6a, 0x8f, 0x94, 0x67, 0x30, 0x83, 0x08};
    var nonce: [12]u8 = .{0xca, 0xfe, 0xba, 0xbe, 0xfa, 0xce, 0xdb, 0xad, 0xde, 0xca, 0xf8, 0x88};
    var pt: [5]u8 = .{ 'h', 'e', 'l', 'l', 'o' };
    
    var ct: [5]u8 = undefined;
    var tag: [16]u8 = undefined;
    crypto.gcmEncrypt(&key, &nonce, &[_]u8{}, pt[0..], ct[0..], &tag);
    
    _ = sys.write(1, "ct: ", 4);
    hex_out(ct[0..]);
    _ = sys.write(1, "\ntag: ", 6);
    hex_out(tag[0..]);
    _ = sys.write(1, "\n", 1);
    _ = sys.write(1, "exp_ct: f3d7408bb6\nexp_tag: b6351cb8ffde4b6a9429ac5111b9985c\n", 56);
    
    // Also test decrypt
    var pt2: [5]u8 = undefined;
    const ok = crypto.gcmDecrypt(&key, &nonce, &[_]u8{}, ct[0..], &tag, pt2[0..]);
    _ = sys.write(1, if (ok) "decrypt ok\n" else "decrypt FAILED\n", 13);
}
