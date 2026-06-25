const crypto = @import("crypto.zig");
const sys = @import("sys.zig");

pub fn main() void {
    // Test SHA-256 with empty input
    var out: [32]u8 = undefined;
    crypto.sha256(&[_]u8{}, &out);
    _ = sys.write(1, "sha256(empty): ", 15);
    for (out) |b| { var h: [2]u8 = undefined; h[0] = @as(u8, if (b>>4 < 10) '0' + (b>>4) else 'a' + (b>>4) - 10); h[1] = @as(u8, if ((b&15) < 10) '0' + (b&15) else 'a' + ((b&15)) - 10); _ = sys.write(1, &h, 2); }
    _ = sys.write(1, "\n", 1);
    _ = sys.write(1, "expected: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n", 72);
    
    // Test SHA-256 with "abc"
    crypto.sha256("abc", &out);
    _ = sys.write(1, "sha256(\"abc\"): ", 15);
    for (out) |b| { var h: [2]u8 = undefined; h[0] = @as(u8, if (b>>4 < 10) '0' + (b>>4) else 'a' + (b>>4) - 10); h[1] = @as(u8, if ((b&15) < 10) '0' + (b&15) else 'a' + ((b&15)) - 10); _ = sys.write(1, &h, 2); }
    _ = sys.write(1, "\n", 1);
    _ = sys.write(1, "expected: ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\n", 72);
}
