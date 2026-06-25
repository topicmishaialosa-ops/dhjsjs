const crypto = @import("crypto.zig");
const sys = @import("sys.zig");

pub fn main() void {
    // Key, IV, AAD, CT, TAG from the last TLS handshake
    var key: [16]u8 = .{0x10, 0xb2, 0xbd, 0x9c, 0x05, 0x44, 0x51, 0xdb, 0x74, 0x4a, 0x07, 0x75, 0x0b, 0x44, 0xda, 0xd3};
    var iv: [12]u8 = .{0x4f, 0x58, 0x59, 0x0d, 0xdd, 0x06, 0xb1, 0x5c, 0xde, 0x72, 0x37, 0x14};
    // AAD = 00000000000000001703031894 
    var aad: [13]u8 = .{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x17, 0x03, 0x03, 0x18, 0x94};
    // Full ciphertext (from debug output, need the full payload)
    // First 64 bytes: 6e65b75c5c1e806fc68bd25f452a1b31bff9a55f7e6f5fd34f780d61ac520bdd38fd9c3b232e707a5a925dc31ef74a8be1dcb5ed8d40ffe7973891c34083a105
    // Tag: 2d60ce8c5e4c2007bee0f2210fbdf724
    // ct_len = 0x1894 = 6292, tag at the end
    
    // We don't have the full ct from the last run, so let's just do a round-trip test
    // Encrypt then decrypt with the TLS parameters
    var pt: [100]u8 = .{8, 0, 0, 0x60} ++ .{0x00} ** 96;
    var ct: [100]u8 = undefined;
    var tag: [16]u8 = undefined;
    crypto.gcmEncrypt(&key, &iv, &aad, pt[0..], ct[0..], &tag);
    
    var pt2: [100]u8 = undefined;
    const ok = crypto.gcmDecrypt(&key, &iv, &aad, ct[0..], &tag, pt2[0..]);
    _ = sys.write(1, if (ok) "round-trip OK\n" else "round-trip FAILED\n", 16);
    
    // Now test with Python reference by printing encrypted output
    _ = sys.write(1, "ct: ", 4);
    for (ct) |b| { var h: [2]u8 = undefined; h[0] = @as(u8, if (b>>4 < 10) '0' + (b>>4) else 'a' + (b>>4) - 10); h[1] = @as(u8, if ((b&15) < 10) '0' + (b&15) else 'a' + ((b&15)) - 10); _ = sys.write(1, &h, 2); }
    _ = sys.write(1, "\ntag: ", 6);
    for (tag) |b| { var h: [2]u8 = undefined; h[0] = @as(u8, if (b>>4 < 10) '0' + (b>>4) else 'a' + (b>>4) - 10); h[1] = @as(u8, if ((b&15) < 10) '0' + (b&15) else 'a' + ((b&15)) - 10); _ = sys.write(1, &h, 2); }
    _ = sys.write(1, "\n", 1);
}
