pub fn isAlpha(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z');
}

pub fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

pub fn isAlphaNum(ch: u8) bool {
    return isAlpha(ch) or isDigit(ch) or ch == '_';
}

pub fn memcpy(dest: [*]u8, src: [*]const u8, len: usize) void {
    var i: usize = 0;
    while (i < len) : (i += 1) {
        dest[i] = src[i];
    }
}

pub fn strlen(s: [*]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

pub fn sliceEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

pub fn formatU32(val: u32, buf: [*]u8) usize {
    var tmp: [32]u8 = undefined;
    var i: usize = 0;
    var n = val;
    if (n == 0) {
        buf[0] = '0';
        return 1;
    }
    while (n > 0) : (n /= 10) {
        tmp[i] = @as(u8, @intCast(n % 10)) + '0';
        i += 1;
    }
    var j: usize = 0;
    while (j < i) : (j += 1) {
        buf[j] = tmp[i - 1 - j];
    }
    return i;
}

pub fn formatI32(val: i32, buf: [*]u8) usize {
    if (val < 0) {
        buf[0] = '-';
        const mag = @as(u32, @bitCast(~val +% 1));
        return 1 + formatU32(mag, buf + 1);
    }
    return formatU32(@as(u32, @bitCast(val)), buf);
}
