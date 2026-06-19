const utils = @import("utils.zig");
const sys = @import("sys.zig");

// ============================== SHA-256 ==============================

const K = [_]u32{
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

fn rotR(x: u32, n: u32) u32 { return (x >> @as(u5, @intCast(n))) | (x << @as(u5, @intCast(32 - n))); }
fn ch(x: u32, y: u32, z: u32) u32 { return (x & y) ^ (~x & z); }
fn maj(x: u32, y: u32, z: u32) u32 { return (x & y) ^ (x & z) ^ (y & z); }
fn s0(x: u32) u32 { return rotR(x, 2) ^ rotR(x, 13) ^ rotR(x, 22); }
fn s1(x: u32) u32 { return rotR(x, 6) ^ rotR(x, 11) ^ rotR(x, 25); }
fn w0(x: u32) u32 { return rotR(x, 7) ^ rotR(x, 18) ^ (x >> 3); }
fn w1(x: u32) u32 { return rotR(x, 17) ^ rotR(x, 19) ^ (x >> 10); }

fn w32be(buf: []u8, pos: usize, v: u32) void {
    buf[pos + 0] = @as(u8, @truncate(v >> 24));
    buf[pos + 1] = @as(u8, @truncate(v >> 16));
    buf[pos + 2] = @as(u8, @truncate(v >> 8));
    buf[pos + 3] = @as(u8, @truncate(v));
}

fn r32be(buf: []const u8, pos: usize) u32 {
    return (@as(u32, buf[pos]) << 24) | (@as(u32, buf[pos + 1]) << 16) | (@as(u32, buf[pos + 2]) << 8) | @as(u32, buf[pos + 3]);
}

pub fn sha256(data: []const u8, out: *[32]u8) void {
    var h: [8]u32 = [8]u32{
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    };
    const bit_len: u64 = @as(u64, data.len) * 8;
    var buf: [64]u8 = undefined;
    var i: usize = 0;
    while (i < data.len) {
        const chunk_end = @min(i + 64, data.len);
        const chunk_len = chunk_end - i;
        if (chunk_len == 64) {
            sha256Block(&h, data[i..][0..64]);
            i += 64;
        } else {
            utils.memcpy(&buf, data.ptr + i, chunk_len);
            buf[chunk_len] = 0x80;
            var j: usize = chunk_len + 1;
            while (j < 56) { buf[j] = 0; j += 1; }
            if (chunk_len >= 56) {
                while (j < 64) { buf[j] = 0; j += 1; }
                sha256Block(&h, &buf);
                j = 0;
                while (j < 56) { buf[j] = 0; j += 1; }
            }
            w32be(&buf, 56, @as(u32, @truncate(bit_len >> 32)));
            w32be(&buf, 60, @as(u32, @truncate(bit_len)));
            sha256Block(&h, &buf);
            break;
        }
    }
    if (data.len % 64 == 0) {
        var j: usize = 0;
        while (j < 56) { buf[j] = 0; j += 1; }
        buf[0] = 0x80;
        w32be(&buf, 56, @as(u32, @truncate(bit_len >> 32)));
        w32be(&buf, 60, @as(u32, @truncate(bit_len)));
        sha256Block(&h, &buf);
    }
    for (h, 0..) |hv, idx| w32be(out, idx * 4, hv);
}

fn sha256Block(h: *[8]u32, block: *const [64]u8) void {
    var w: [64]u32 = undefined;
    for (0..16) |t| w[t] = r32be(block, t * 4);
    for (16..64) |t| {
        w[t] = w1(w[t - 2]) +% w[t - 7] +% w0(w[t - 15]) +% w[t - 16];
    }
    var a = h[0]; var b = h[1]; var c = h[2]; var d = h[3];
    var e = h[4]; var f = h[5]; var g = h[6]; var hh = h[7];
    for (0..64) |t| {
        const t1 = hh +% s1(e) +% ch(e, f, g) +% K[t] +% w[t];
        const t2 = s0(a) +% maj(a, b, c);
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    }
    h[0] +%= a; h[1] +%= b; h[2] +%= c; h[3] +%= d;
    h[4] +%= e; h[5] +%= f; h[6] +%= g; h[7] +%= hh;
}

// ============================== BigInt ==============================

const LIMB = u32;
const MAX_LIMBS = 64;

pub const BigInt = struct {
    limbs: [MAX_LIMBS]LIMB = [_]LIMB{0} ** MAX_LIMBS,
    len: usize = 0,
};

fn biNorm(a: *BigInt) void {
    while (a.len > 0 and a.limbs[a.len - 1] == 0) a.len -= 1;
}

fn biSet(a: *BigInt, v: u32) void {
    a.limbs[0] = v;
    a.len = if (v == 0) 0 else 1;
}

fn biCopy(a: *const BigInt, out: *BigInt) void {
    out.len = a.len;
    var i: usize = 0;
    while (i < a.len) : (i += 1) out.limbs[i] = a.limbs[i];
}

pub fn biFromBytes(bytes: []const u8) BigInt {
    var r = BigInt{};
    var i: usize = 0;
    while (i < bytes.len) {
        const idx = @as(usize, @intCast((bytes.len - 1 - i) / 4));
        if (idx >= MAX_LIMBS) break;
        r.limbs[idx] = (r.limbs[idx] << 8) | @as(u32, bytes[bytes.len - 1 - i]);
        i += 1;
    }
    r.len = (bytes.len + 3) / 4;
    biNorm(&r);
    return r;
}

pub fn biToBytes(a: *const BigInt, out: []u8) void {
    var i: usize = 0;
    while (i < out.len) : (i += 1) out[i] = 0;
    var j: usize = 0;
    while (j < a.len) : (j += 1) {
        const v = a.limbs[j];
        const base = (out.len - 1) - j * 4;
        if (base < out.len) out[base] = @as(u8, @truncate(v));
        if (base + 1 < out.len) out[base + 1] = @as(u8, @truncate(v >> 8));
        if (base + 2 < out.len) out[base + 2] = @as(u8, @truncate(v >> 16));
        if (base + 3 < out.len) out[base + 3] = @as(u8, @truncate(v >> 24));
    }
}

fn biAdd(a: *const BigInt, b: *const BigInt, out: *BigInt) void {
    var carry: u64 = 0;
    const max_len = @max(a.len, b.len);
    var i: usize = 0;
    while (i < max_len or carry > 0) : (i += 1) {
        var s: u64 = carry;
        if (i < a.len) s += a.limbs[i];
        if (i < b.len) s += b.limbs[i];
        out.limbs[i] = @as(LIMB, @truncate(s));
        carry = s >> 32;
    }
    out.len = i;
    biNorm(out);
}

fn biSub(a: *const BigInt, b: *const BigInt, out: *BigInt) void {
    var borrow: u64 = 0;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        const av: u64 = a.limbs[i];
        const bv: u64 = if (i < b.len) b.limbs[i] else 0;
        if (av >= bv + borrow) {
            out.limbs[i] = @as(LIMB, @truncate(av - bv - borrow));
            borrow = 0;
        } else {
            out.limbs[i] = @as(LIMB, @truncate(av +% 0x100000000 -% bv -% borrow));
            borrow = 1;
        }
    }
    out.len = a.len;
    biNorm(out);
}

fn biMul(a: *const BigInt, b: *const BigInt, out: *BigInt) void {
    var tmp: [MAX_LIMBS * 2]LIMB = [_]LIMB{0} ** (MAX_LIMBS * 2);
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        var carry: u64 = 0;
        var j: usize = 0;
        while (j < b.len) : (j += 1) {
            const prod = @as(u64, a.limbs[i]) * @as(u64, b.limbs[j]) + @as(u64, tmp[i + j]) + carry;
            tmp[i + j] = @as(LIMB, @truncate(prod));
            carry = prod >> 32;
        }
        if (carry > 0) tmp[i + b.len] = @as(LIMB, @truncate(carry));
    }
    var k: usize = MAX_LIMBS * 2 - 1;
    while (k > 0 and tmp[k - 1] == 0) k -= 1;
    @memcpy(out.limbs[0..k], tmp[0..k]);
    out.len = k;
    biNorm(out);
}

fn biShl1(a: *const BigInt, out: *BigInt) void {
    var carry: u32 = 0;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        const v = a.limbs[i];
        out.limbs[i] = (v << 1) | carry;
        carry = v >> 31;
    }
    out.len = a.len;
    if (carry > 0) { out.limbs[out.len] = carry; out.len += 1; }
    biNorm(out);
}

fn biShr1(a: *const BigInt, out: *BigInt) void {
    var carry: u32 = 0;
    var i: usize = a.len;
    while (i > 0) {
        i -= 1;
        const v = a.limbs[i];
        out.limbs[i] = (v >> 1) | (carry << 31);
        carry = v & 1;
    }
    out.len = a.len;
    biNorm(out);
}

fn biCmp(a: *const BigInt, b: *const BigInt) i8 {
    if (a.len != b.len) return if (a.len > b.len) 1 else -1;
    var i: usize = a.len;
    while (i > 0) {
        i -= 1;
        if (a.limbs[i] != b.limbs[i]) return if (a.limbs[i] > b.limbs[i]) 1 else -1;
    }
    return 0;
}

fn biIsZero(a: *const BigInt) bool { return a.len == 0; }
fn biIsOne(a: *const BigInt) bool { return a.len == 1 and a.limbs[0] == 1; }
fn biIsOdd(a: *const BigInt) bool { return a.len > 0 and (a.limbs[0] & 1) == 1; }
fn biEq(a: *const BigInt, b: *const BigInt) bool { return biCmp(a, b) == 0; }

fn biSub1(out: *BigInt, v: u32) void {
    var borrow: u64 = v;
    var i: usize = 0;
    while (i < out.len and borrow > 0) : (i += 1) {
        if (out.limbs[i] >= borrow) {
            out.limbs[i] -%= @as(LIMB, @truncate(borrow));
            borrow = 0;
        } else {
            out.limbs[i] = @as(LIMB, @truncate((@as(u64, out.limbs[i]) +% 0x100000000 -% borrow)));
            borrow = 1;
        }
    }
    biNorm(out);
}

fn biAdd1(out: *BigInt, v: u32) void {
    var carry: u64 = v;
    var i: usize = 0;
    while (carry > 0) : (i += 1) {
        if (i >= out.len) { out.len = i + 1; out.limbs[i] = 0; }
        const s = @as(u64, out.limbs[i]) + carry;
        out.limbs[i] = @as(LIMB, @truncate(s));
        carry = s >> 32;
    }
    biNorm(out);
}

fn cmpNumLimbs(num: []const LIMB, b: []const LIMB) i8 {
    if (num.len != b.len) return if (num.len > b.len) 1 else -1;
    var i: usize = num.len;
    while (i > 0) {
        i -= 1;
        if (num[i] != b[i]) return if (num[i] > b[i]) 1 else -1;
    }
    return 0;
}

fn biDiv(a: *const BigInt, b: *const BigInt, q: *BigInt, r: *BigInt) void {
    if (biIsZero(b)) return;
    if (biCmp(a, b) < 0) { biCopy(a, r); biSet(q, 0); return; }
    if (b.len == 1) {
        var rem: u64 = 0;
        var i: usize = a.len;
        while (i > 0) {
            i -= 1;
            const cur = (rem << 32) | @as(u64, a.limbs[i]);
            q.limbs[i] = @as(LIMB, @truncate(cur / @as(u64, b.limbs[0])));
            rem = cur % @as(u64, b.limbs[0]);
        }
        q.len = a.len; biNorm(q);
        biSet(r, @as(u32, @truncate(rem)));
        return;
    }
    // Long division (schoolbook)
    var num: [MAX_LIMBS + 1]LIMB = [_]LIMB{0} ** (MAX_LIMBS + 1);
    @memcpy(num[0..a.len], a.limbs[0..a.len]);
    var num_len: usize = a.len;
    var quot: [MAX_LIMBS]LIMB = [_]LIMB{0} ** MAX_LIMBS;
    while (num_len >= b.len and (num_len > b.len or cmpNumLimbs(num[0..num_len], b.limbs[0..b.len]) >= 0)) {
        var shift = num_len - b.len;
        var guess: u64 = @as(u64, num[num_len - 1]) / (@as(u64, b.limbs[b.len - 1]) + 1);
        if (guess == 0) {
            guess = ((@as(u64, num[num_len - 1]) << 32) | @as(u64, num[num_len - 2])) / (@as(u64, b.limbs[b.len - 1]) + 1);
            if (shift > 0) shift -= 1;
        }
        if (guess == 0) { guess = 1; }
        if (guess > 0x100000000) guess = 0xFFFFFFFF;
        var sub: BigInt = undefined;
        biSet(&sub, 0);
        sub.len = b.len + 1;
        var carry: u64 = 0;
        for (0..b.len) |j| {
            const prod = guess * @as(u64, b.limbs[j]) + carry;
            sub.limbs[j] = @as(LIMB, @truncate(prod));
            carry = prod >> 32;
        }
        sub.limbs[b.len] = @as(LIMB, @truncate(carry));
        biNorm(&sub);
        var num_sub: BigInt = undefined;
        num_sub.len = num_len + 1;
        @memcpy(num_sub.limbs[0..num_len], num[0..num_len]);
        num_sub.limbs[num_len] = 0;
        if (biCmp(&num_sub, &sub) < 0) {
            if (guess > 1) {
                guess -= 1;
                carry = 0;
                for (0..b.len) |j| {
                    const prod = guess * @as(u64, b.limbs[j]) + carry;
                    sub.limbs[j] = @as(LIMB, @truncate(prod));
                    carry = prod >> 32;
                }
                sub.limbs[b.len] = @as(LIMB, @truncate(carry));
                biNorm(&sub);
            }
        }
        num_sub.len = num_len + 1;
        @memcpy(num_sub.limbs[0..num_len], num[0..num_len]);
        num_sub.limbs[num_len] = 0;
        biSub(&num_sub, &sub, &num_sub);
        biNorm(&num_sub);
        num_len = num_sub.len;
        @memcpy(num[0..num_len], num_sub.limbs[0..num_len]);
        quot[shift] +%= @as(LIMB, @truncate(guess));
        while (num_len > 0 and num[num_len - 1] == 0) num_len -= 1;
    }
    @memcpy(q.limbs[0..a.len], quot[0..a.len]);
    q.len = a.len;
    biNorm(q);
    @memcpy(r.limbs[0..num_len], num[0..num_len]);
    r.len = num_len;
    biNorm(r);
}

fn biMod(a: *const BigInt, m: *const BigInt, out: *BigInt) void {
    if (biCmp(a, m) < 0) { biCopy(a, out); return; }
    var q: BigInt = undefined;
    biDiv(a, m, &q, out);
}

fn biModExp(base: *const BigInt, exp: *const BigInt, mod: *const BigInt, out: *BigInt) void {
    var result = BigInt{}; result.limbs[0] = 1; result.len = 1;
    var base_m: BigInt = undefined; biMod(base, mod, &base_m);
    var i: usize = exp.len;
    while (i > 0) {
        i -= 1;
        var bit: u32 = 0x80000000;
        while (bit > 0) {
            var tmp: BigInt = undefined;
            biMul(&result, &base_m, &tmp);
            biMod(&tmp, mod, &result);
            bit >>= 1;
            if ((exp.limbs[i] & bit) == 0 and bit > 0) {
                var tmp2: BigInt = undefined;
                biMul(&base_m, &base_m, &tmp2);
                biMod(&tmp2, mod, &base_m);
                bit >>= 1;
                if (bit == 0) break;
            }
            if (bit == 0) break;
            if ((exp.limbs[i] & bit) != 0) {
                var tmp2: BigInt = undefined;
                biMul(&result, &base_m, &tmp2);
                biMod(&tmp2, mod, &result);
                bit >>= 1;
            } else {
                bit >>= 1;
            }
            if (bit > 0) {
                var tmp2: BigInt = undefined;
                biMul(&base_m, &base_m, &tmp2);
                biMod(&tmp2, mod, &base_m);
            }
        }
        if (i > 0) {
            var j: u32 = 0;
            while (j < 32) : (j += 1) {
                var tmp: BigInt = undefined;
                biMul(&base_m, &base_m, &tmp);
                biMod(&tmp, mod, &base_m);
            }
        }
    }
    biCopy(&result, out);
}

fn biGCD(a: *const BigInt, b: *const BigInt, out: *BigInt) void {
    var aa: BigInt = undefined; biCopy(a, &aa);
    var bb: BigInt = undefined; biCopy(b, &bb);
    while (!biIsZero(&bb)) {
        var r: BigInt = undefined;
        biMod(&aa, &bb, &r);
        biCopy(&bb, &aa);
        biCopy(&r, &bb);
    }
    biCopy(&aa, out);
}

fn biModInv(a: *const BigInt, m: *const BigInt, out: *BigInt) void {
    var t: BigInt = undefined; var newt: BigInt = undefined;
    var r: BigInt = undefined; var newr: BigInt = undefined;
    biCopy(m, &r); biCopy(a, &newr);
    biSet(&t, 0); biSet(&newt, 1);
    while (!biIsZero(&newr)) {
        var q: BigInt = undefined;
        var rr: BigInt = undefined;
        biDiv(&r, &newr, &q, &rr);
        var q_newt: BigInt = undefined; biMul(&q, &newt, &q_newt);
        if (biCmp(&t, &q_newt) >= 0) biSub(&t, &q_newt, &t) else {
            var tmp: BigInt = undefined; biSub(&q_newt, &t, &tmp); biSub(m, &tmp, &t);
        }
        var tmp2: BigInt = undefined; biCopy(&newt, &tmp2); biCopy(&t, &newt); biCopy(&tmp2, &t);
        biCopy(&newr, &r); biCopy(&rr, &newr);
    }
    if (biCmp(&t, m) >= 0) { var tmp: BigInt = undefined; biSub(&t, m, &tmp); biCopy(&tmp, out); }
    else biCopy(&t, out);
}

fn biRand(bits: u32, out: *BigInt) void {
    var buf: [256]u8 = undefined;
    const fd = sys.open("/dev/urandom", 0, 0);
    if (fd < 0) { biSet(out, 1); return; }
    const nbytes = (bits + 7) / 8;
    _ = sys.read(fd, &buf, nbytes);
    sys.close(fd);
    if (bits % 8 != 0) buf[0] &= @as(u8, @intCast((@as(u32, 1) << @as(u5, @intCast(bits % 8))) - 1));
    buf[0] |= @as(u8, 1) << @as(u3, @intCast((bits - 1) % 8));
    var tmp_bn: BigInt = biFromBytes(buf[0..nbytes]);
    biCopy(&tmp_bn, out);
}

fn biMillerRabin(n: *const BigInt) bool {
    if (biIsZero(n) or biIsOne(n)) return false;
    if (!biIsOdd(n)) return n.limbs[0] == 2;
    if (n.len == 1 and n.limbs[0] < 64) {
        const small = [_]u32{ 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61 };
        for (small) |p| { if (n.limbs[0] == p) return true; if (n.limbs[0] % p == 0) return false; }
        return true;
    }
    var nm1: BigInt = undefined; biCopy(n, &nm1); biSub1(&nm1, 1);
    var d: BigInt = undefined; biCopy(&nm1, &d);
    var s: u32 = 0;
    while (!biIsOdd(&d)) { biShr1(&d, &d); s += 1; }
    const witnesses = [_]u32{ 2, 3, 5, 7, 11, 13 };
    for (witnesses) |w| {
        if (@as(u32, w) >= n.limbs[0] and n.len == 1) continue;
        var a: BigInt = undefined; biSet(&a, w);
        if (biCmp(&a, &nm1) >= 0) break;
        var x: BigInt = undefined; biModExp(&a, &d, n, &x);
        if (biIsOne(&x) or biEq(&x, &nm1)) continue;
        var composite: bool = true;
        var rr: u32 = 0;
        while (rr < s - 1) : (rr += 1) {
            var tmp: BigInt = undefined; biMul(&x, &x, &tmp); biMod(&tmp, n, &x);
            if (biEq(&x, &nm1)) { composite = false; break; }
        }
        if (composite) return false;
    }
    return true;
}

fn biNextPrime(candidate: *BigInt) void {
    if (!biIsOdd(candidate)) biAdd1(candidate, 1);
    while (true) {
        if (biMillerRabin(candidate)) return;
        biAdd1(candidate, 2);
    }
}

// ============================== RSA ==============================

pub const RSA_KEY_BYTES = 256;

pub const RsaPrivateKey = struct {
    n: BigInt, e: BigInt, d: BigInt,
    p: BigInt, q: BigInt,
    dp: BigInt, dq: BigInt, qinv: BigInt,
};

pub fn rsaGenerateKey(key: *RsaPrivateKey) void {
    biSet(&key.e, 65537);
    biRand(1024, &key.p); biNextPrime(&key.p);
    biRand(1024, &key.q); biNextPrime(&key.q);
    var attempts: u32 = 0;
    while (biEq(&key.p, &key.q) and attempts < 100) : (attempts += 1) {
        biRand(1024, &key.q); biNextPrime(&key.q);
    }
    biMul(&key.p, &key.q, &key.n);
    var pm1: BigInt = undefined; biCopy(&key.p, &pm1); biSub1(&pm1, 1);
    var qm1: BigInt = undefined; biCopy(&key.q, &qm1); biSub1(&qm1, 1);
    var phi: BigInt = undefined; biMul(&pm1, &qm1, &phi);
    biModInv(&key.e, &phi, &key.d);
    biMod(&key.d, &pm1, &key.dp);
    biMod(&key.d, &qm1, &key.dq);
    biModInv(&key.q, &key.p, &key.qinv);
}

pub fn rsaSignHash(key: *const RsaPrivateKey, hash: *const [32]u8, signature: *[RSA_KEY_BYTES]u8) void {
    const digest_info_prefix = [_]u8{ 0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20 };
    var padded: [RSA_KEY_BYTES]u8 = [_]u8{0} ** RSA_KEY_BYTES;
    padded[0] = 0x00; padded[1] = 0x01;
    const di_size = digest_info_prefix.len + 32;
    const pad_len = RSA_KEY_BYTES - 3 - di_size;
    var i: usize = 2;
    while (i < 2 + pad_len) : (i += 1) padded[i] = 0xFF;
    padded[i] = 0x00; i += 1;
    @memcpy(padded[i..][0..digest_info_prefix.len], &digest_info_prefix);
    i += digest_info_prefix.len;
    @memcpy(padded[i..][0..32], hash);
    var m: BigInt = biFromBytes(&padded);
    var s1_res: BigInt = undefined; biModExp(&m, &key.dp, &key.p, &s1_res);
    var s2_res: BigInt = undefined; biModExp(&m, &key.dq, &key.q, &s2_res);
    var diff: BigInt = undefined;
    if (biCmp(&s1_res, &s2_res) >= 0) biSub(&s1_res, &s2_res, &diff) else {
        biSub(&s2_res, &s1_res, &diff); var tmp: BigInt = undefined; biSub(&key.p, &diff, &tmp); biCopy(&tmp, &diff);
    }
    var h_res: BigInt = undefined; biMul(&diff, &key.qinv, &h_res); biMod(&h_res, &key.p, &h_res);
    var s_res: BigInt = undefined; var qh: BigInt = undefined; biMul(&key.q, &h_res, &qh); biAdd(&s2_res, &qh, &s_res);
    if (biCmp(&s_res, &key.n) >= 0) { var tmp2: BigInt = undefined; biSub(&s_res, &key.n, &tmp2); biCopy(&tmp2, &s_res); }
    for (0..RSA_KEY_BYTES) |j| signature[j] = 0;
    biToBytes(&s_res, signature[0..RSA_KEY_BYTES]);
}

// ============================== APK v2 Signing ==============================

fn w32le(buf: []u8, pos: usize, v: u32) void {
    buf[pos + 0] = @as(u8, @truncate(v));
    buf[pos + 1] = @as(u8, @truncate(v >> 8));
    buf[pos + 2] = @as(u8, @truncate(v >> 16));
    buf[pos + 3] = @as(u8, @truncate(v >> 24));
}

fn w64le(buf: []u8, pos: usize, v: u64) void {
    w32le(buf, pos, @as(u32, @truncate(v)));
    w32le(buf, pos + 4, @as(u32, @truncate(v >> 32)));
}

fn r32le(buf: []const u8, pos: usize) u32 {
    return @as(u32, buf[pos]) | (@as(u32, buf[pos + 1]) << 8) | (@as(u32, buf[pos + 2]) << 16) | (@as(u32, buf[pos + 3]) << 24);
}

fn r64le(buf: []const u8, pos: usize) u64 {
    return @as(u64, r32le(buf, pos)) | (@as(u64, r32le(buf, pos + 4)) << 32);
}

fn buildSubjectPublicKeyInfo(key: *const BigInt, e: *const BigInt, buf: []u8) usize {
    var pos: usize = 0;
    var rsa_seq_pos: usize = 0;
    var rsa_seq_start: usize = 0;
    var n_bytes: [257]u8 = undefined;
    for (0..257) |j| n_bytes[j] = 0;
    biToBytes(key, n_bytes[0..]);
    // e bytes (big-endian, 5 bytes for 65537 = 0x010001 → 00 01 00 01)
    var e_bytes: [5]u8 = undefined;
    for (0..5) |j| e_bytes[j] = 0;
    biToBytes(e, e_bytes[0..]);
    // RSAPublicKey SEQUENCE header
    rsa_seq_start = pos;
    buf[pos] = 0x30; pos += 1;
    buf[pos] = 0x82; pos += 1;
    rsa_seq_pos = pos; pos += 2;
    // n INTEGER
    buf[pos] = 0x02; pos += 1;
    buf[pos] = 0x82; pos += 1;
    buf[pos] = 0x01; pos += 1;
    buf[pos] = 0x01; pos += 1;
    @memcpy(buf[pos..][0..257], &n_bytes);
    pos += 257;
    // e INTEGER (variable length)
    var e_der_len: u8 = 5;
    while (e_der_len > 1 and e_bytes[5 - e_der_len] == 0) e_der_len -= 1;
    buf[pos] = 0x02; pos += 1;
    buf[pos] = e_der_len; pos += 1;
    @memcpy(buf[pos..][0..e_der_len], e_bytes[5 - e_der_len .. 5]);
    pos += e_der_len;
    const rsa_seq_len: u16 = @as(u16, @intCast(pos - rsa_seq_start - 4));
    buf[rsa_seq_pos] = @as(u8, @truncate(rsa_seq_len >> 8));
    buf[rsa_seq_pos + 1] = @as(u8, @truncate(rsa_seq_len));
    // SubjectPublicKeyInfo - move RSAPublicKey to body buffer
    const body_len = pos - rsa_seq_start;
    var spki_body: [1024]u8 = undefined;
    @memcpy(spki_body[0..body_len], buf[rsa_seq_start..pos]);
    pos = 0;
    buf[pos] = 0x30; pos += 1; buf[pos] = 0x82; pos += 1;
    const spki_seq_len_pos = pos; pos += 2;
    // AlgorithmIdentifier
    buf[pos] = 0x30; pos += 1; buf[pos] = 0x0D; pos += 1;
    buf[pos] = 0x06; pos += 1; buf[pos] = 0x09; pos += 1;
    buf[pos] = 0x2A; pos += 1; buf[pos] = 0x86; pos += 1; buf[pos] = 0x48; pos += 1;
    buf[pos] = 0x86; pos += 1; buf[pos] = 0xF7; pos += 1; buf[pos] = 0x0D; pos += 1;
    buf[pos] = 0x01; pos += 1; buf[pos] = 0x01; pos += 1; buf[pos] = 0x01; pos += 1;
    buf[pos] = 0x05; pos += 1; buf[pos] = 0x00; pos += 1;
    // BIT STRING wrapping RSAPublicKey
    buf[pos] = 0x03; pos += 1; buf[pos] = 0x82; pos += 1;
    const bs_len_pos = pos; pos += 2;
    buf[pos] = 0x00; pos += 1;
    @memcpy(buf[pos..][0..body_len], spki_body[0..body_len]);
    pos += body_len;
    const bs_len: u16 = @as(u16, @intCast(pos - bs_len_pos - 2));
    buf[bs_len_pos] = @as(u8, @truncate(bs_len >> 8));
    buf[bs_len_pos + 1] = @as(u8, @truncate(bs_len));
    const total_len: u16 = @as(u16, @intCast(pos - spki_seq_len_pos - 2));
    buf[spki_seq_len_pos] = @as(u8, @truncate(total_len >> 8));
    buf[spki_seq_len_pos + 1] = @as(u8, @truncate(total_len));
    return pos;
}

fn buildSelfSignedCert(key: *const RsaPrivateKey, buf: []u8) usize {
    // Build SubjectPublicKeyInfo first
    var spki_buf: [512]u8 = undefined;
    const spki_len = buildSubjectPublicKeyInfo(&key.n, &key.e, &spki_buf);
    // Build TBSCertificate
    var tbs: [2048]u8 = undefined;
    var pos: usize = 0;
    // Version [0] EXPLICIT INTEGER v3 = 2
    tbs[pos] = 0xA0; pos += 1; tbs[pos] = 0x03; pos += 1;
    tbs[pos] = 0x02; pos += 1; tbs[pos] = 0x01; pos += 1; tbs[pos] = 0x02; pos += 1;
    // Serial number = 1
    tbs[pos] = 0x02; pos += 1; tbs[pos] = 0x01; pos += 1; tbs[pos] = 0x01; pos += 1;
    // Signature algorithm (SHA-256 with RSA)
    tbs[pos] = 0x30; pos += 1; tbs[pos] = 0x0D; pos += 1;
    tbs[pos] = 0x06; pos += 1; tbs[pos] = 0x09; pos += 1;
    tbs[pos] = 0x2A; pos += 1; tbs[pos] = 0x86; pos += 1; tbs[pos] = 0x48; pos += 1;
    tbs[pos] = 0x86; pos += 1; tbs[pos] = 0xF7; pos += 1; tbs[pos] = 0x0D; pos += 1;
    tbs[pos] = 0x01; pos += 1; tbs[pos] = 0x01; pos += 1; tbs[pos] = 0x0B; pos += 1; // sha256WithRSAEncryption
    tbs[pos] = 0x05; pos += 1; tbs[pos] = 0x00; pos += 1;
    // Issuer name: CN=dhjsjs
    tbs[pos] = 0x31; pos += 1;
    const iss_set_len_pos = pos; pos += 1;
    tbs[pos] = 0x30; pos += 1;
    const iss_seq_len_pos = pos; pos += 1;
    tbs[pos] = 0x31; pos += 1;
    const iss_inner_len_pos = pos; pos += 1;
    tbs[pos] = 0x30; pos += 1; tbs[pos] = 0x0B; pos += 1;
    tbs[pos] = 0x06; pos += 1; tbs[pos] = 0x03; pos += 1; // OID: 2.5.4.3 = commonName
    tbs[pos] = 0x55; pos += 1; tbs[pos] = 0x04; pos += 1; tbs[pos] = 0x03; pos += 1;
    tbs[pos] = 0x0C; pos += 1; // UTF8String
    tbs[pos] = 0x06; pos += 1; // length 6
    tbs[pos] = 'd'; pos += 1; tbs[pos] = 'h'; pos += 1; tbs[pos] = 'j'; pos += 1;
    tbs[pos] = 's'; pos += 1; tbs[pos] = 'j'; pos += 1; tbs[pos] = 's'; pos += 1;
    const iss_inner_len: u8 = @as(u8, @intCast(pos - iss_inner_len_pos - 1));
    const iss_seq_len: u8 = @as(u8, @intCast(pos - iss_seq_len_pos - 1));
    const iss_set_len: u8 = @as(u8, @intCast(pos - iss_set_len_pos - 1));
    tbs[iss_inner_len_pos] = iss_inner_len;
    tbs[iss_seq_len_pos] = iss_seq_len;
    tbs[iss_set_len_pos] = iss_set_len;
    // Validity
    tbs[pos] = 0x30; pos += 1; tbs[pos] = 0x1E; pos += 1;
    tbs[pos] = 0x17; pos += 1; tbs[pos] = 0x0D; pos += 1; // UTCTime
    const notBefore = "240101000000Z";
    for (notBefore, 0..) |c, j| tbs[pos + j] = c;
    pos += notBefore.len;
    tbs[pos] = 0x17; pos += 1; tbs[pos] = 0x0D; pos += 1; // UTCTime
    const notAfter = "340101000000Z";
    for (notAfter, 0..) |c, j| tbs[pos + j] = c;
    pos += notAfter.len;
    // Subject (same as issuer)
    @memcpy(tbs[pos..][0..(iss_set_len_pos + 1 + iss_set_len - iss_set_len_pos)], tbs[iss_set_len_pos..iss_set_len_pos + 1 + iss_set_len]);
    pos += (iss_set_len_pos + 1 + iss_set_len - iss_set_len_pos);
    // SubjectPublicKeyInfo
    @memcpy(tbs[pos..][0..spki_len], spki_buf[0..spki_len]);
    pos += spki_len;
    const tbs_len: u16 = @as(u16, @intCast(pos));
    // Build full certificate
    var cert: [3072]u8 = undefined;
    var cp: usize = 0;
    cert[cp] = 0x30; cp += 1; cert[cp] = 0x82; cp += 1;
    const cert_seq_len_pos = cp; cp += 2;
    // TBSCertificate SEQUENCE
    cert[cp] = 0x30; cp += 1; cert[cp] = 0x82; cp += 1;
    const tbs_seq_len_pos = cp; cp += 2;
    @memcpy(cert[cp..][0..tbs_len], tbs[0..tbs_len]);
    cp += tbs_len;
    const tbs_seq_len: u16 = @as(u16, @intCast(cp - tbs_seq_len_pos - 2));
    cert[tbs_seq_len_pos] = @as(u8, @truncate(tbs_seq_len >> 8));
    cert[tbs_seq_len_pos + 1] = @as(u8, @truncate(tbs_seq_len));
    // Signature algorithm (same as in TBS)
    cert[cp] = 0x30; cp += 1; cert[cp] = 0x0D; cp += 1;
    cert[cp] = 0x06; cp += 1; cert[cp] = 0x09; cp += 1;
    cert[cp] = 0x2A; cp += 1; cert[cp] = 0x86; cp += 1; cert[cp] = 0x48; cp += 1;
    cert[cp] = 0x86; cp += 1; cert[cp] = 0xF7; cp += 1; cert[cp] = 0x0D; cp += 1;
    cert[cp] = 0x01; cp += 1; cert[cp] = 0x01; cp += 1; cert[cp] = 0x0B; cp += 1;
    cert[cp] = 0x05; cp += 1; cert[cp] = 0x00; cp += 1;
    // Compute signature over TBS certificate
    var tbs_hash: [32]u8 = undefined;
    sha256(cert[4..cp - 15], &tbs_hash);
    var cert_sig: [RSA_KEY_BYTES]u8 = undefined;
    rsaSignHash(key, &tbs_hash, &cert_sig);
    // BIT STRING of signature
    cert[cp] = 0x03; cp += 1; cert[cp] = 0x82; cp += 1;
    const sig_len_pos = cp; cp += 2;
    cert[cp] = 0x00; cp += 1; // 0 unused bits
    @memcpy(cert[cp..][0..RSA_KEY_BYTES], &cert_sig);
    cp += RSA_KEY_BYTES;
    const sig_bs_len: u16 = @as(u16, @intCast(cp - sig_len_pos - 2));
    cert[sig_len_pos] = @as(u8, @truncate(sig_bs_len >> 8));
    cert[sig_len_pos + 1] = @as(u8, @truncate(sig_bs_len));
    const cert_total_len: u16 = @as(u16, @intCast(cp - cert_seq_len_pos - 2));
    cert[cert_seq_len_pos] = @as(u8, @truncate(cert_total_len >> 8));
    cert[cert_seq_len_pos + 1] = @as(u8, @truncate(cert_total_len));
    @memcpy(buf[0..cp], cert[0..cp]);
    return cp;
}

pub fn apkSign(apk_data: []const u8, out: []u8, key: *const RsaPrivateKey) usize {
    // Find EOCD
    var eocd_pos: usize = apk_data.len;
    while (eocd_pos >= 22) {
        eocd_pos -= 1;
        if (apk_data[eocd_pos] == 0x50 and eocd_pos + 3 < apk_data.len and
            apk_data[eocd_pos + 1] == 0x4B and apk_data[eocd_pos + 2] == 0x05 and apk_data[eocd_pos + 3] == 0x06)
            break;
    }
    if (eocd_pos < 22 or eocd_pos + 22 > apk_data.len) return 0;
    // Read CD offset and size from EOCD
    const cd_offset = r32le(apk_data, eocd_pos + 16);
    const cd_size = r32le(apk_data, eocd_pos + 12);
    // Compute content hash: everything before the signing block
    // According to APK v2 spec: content from 0 to CD offset + CD
    var content_hash: [32]u8 = undefined;
    sha256(apk_data[0..cd_offset + cd_size], &content_hash);
    // Build self-signed certificate
    var cert_buf: [3072]u8 = undefined;
    const cert_len = buildSelfSignedCert(key, &cert_buf);
    // Build signed data
    var signed_data: [4096]u8 = undefined;
    var sp: usize = 0;
    // digests count = 1
    w32le(&signed_data, sp, 1); sp += 4;
    // digest[0]: algorithm = 0x0103 (SHA-256)
    w32le(&signed_data, sp, 0x0103); sp += 4;
    w32le(&signed_data, sp, 32); sp += 4; // digest length
    @memcpy(signed_data[sp..][0..32], &content_hash);
    sp += 32;
    // certificates count = 1
    w32le(&signed_data, sp, 1); sp += 4;
    w32le(&signed_data, sp, @as(u32, @intCast(cert_len))); sp += 4;
    @memcpy(signed_data[sp..][0..cert_len], cert_buf[0..cert_len]);
    sp += cert_len;
    // attributes count = 0
    w32le(&signed_data, sp, 0); sp += 4;
    const signed_data_len = sp;
    // Compute signature over signed data
    var sig_hash: [32]u8 = undefined;
    sha256(signed_data[0..signed_data_len], &sig_hash);
    var rsa_sig: [RSA_KEY_BYTES]u8 = undefined;
    rsaSignHash(key, &sig_hash, &rsa_sig);
    // Build signatures block
    var sig_block_buf: [512]u8 = undefined;
    var sb: usize = 0;
    w32le(&sig_block_buf, sb, 1); sb += 4; // 1 signature
    w32le(&sig_block_buf, sb, 0x0103); sb += 4; // algorithm
    w32le(&sig_block_buf, sb, RSA_KEY_BYTES); sb += 4;
    @memcpy(sig_block_buf[sb..][0..RSA_KEY_BYTES], &rsa_sig);
    sb += RSA_KEY_BYTES;
    // Build public key block (SubjectPublicKeyInfo)
    var pubkey_buf: [512]u8 = undefined;
    const pubkey_len = buildSubjectPublicKeyInfo(&key.n, &key.e, &pubkey_buf);
    // Build v2 block value
    var v2_value: [8192]u8 = undefined;
    var v2p: usize = 0;
    @memcpy(v2_value[v2p..][0..signed_data_len], signed_data[0..signed_data_len]);
    v2p += signed_data_len;
    @memcpy(v2_value[v2p..][0..sb], sig_block_buf[0..sb]);
    v2p += sb;
    w32le(&v2_value, v2p, @as(u32, @intCast(pubkey_len))); v2p += 4;
    @memcpy(v2_value[v2p..][0..pubkey_len], pubkey_buf[0..pubkey_len]);
    v2p += pubkey_len;
    const v2_value_len = v2p;
    // Build signing block
    var signing_block: [16384]u8 = undefined;
    var blk: usize = 0;
    blk += 8; // placeholder for first size
    // Pair: id=0x7109871a, value=v2_value
    const pair_len: u64 = @as(u64, v2_value_len) + 4;
    w64le(&signing_block, blk, pair_len); blk += 8;
    w32le(&signing_block, blk, 0x7109871a); blk += 4;
    @memcpy(signing_block[blk..][0..v2_value_len], v2_value[0..v2_value_len]);
    blk += v2_value_len;
    const block_data_len = blk - 8; // without the first size field
    // Fill in sizes
    w64le(&signing_block, 0, @as(u64, @intCast(block_data_len)));
    w64le(&signing_block, blk, @as(u64, @intCast(block_data_len))); blk += 8;
    // Magic
    const magic = "APK Sig Block 42";
    @memcpy(signing_block[blk..][0..magic.len], magic);
    blk += 16; // 16 bytes: 14 chars + 2 null bytes
    // Copy APK content before signing block
    var out_pos: usize = 0;
    @memcpy(out[0..cd_offset + cd_size], apk_data[0..cd_offset + cd_size]);
    out_pos = cd_offset + cd_size;
    // Insert signing block
    @memcpy(out[out_pos..][0..blk], signing_block[0..blk]);
    out_pos += blk;
    // Copy EOCD from original
    var eocd_buf: [22]u8 = undefined;
    @memcpy(&eocd_buf, apk_data[eocd_pos..eocd_pos + 22]);
    // But we need to preserve the comment if any
    // For simplicity, assume no comment (EOCD is exactly 22 bytes)
    // Write EOCD
    const comment_len = apk_data.len - eocd_pos - 22;
    @memcpy(out[out_pos..][0..22], &eocd_buf);
    out_pos += 22;
    if (comment_len > 0) {
        @memcpy(out[out_pos..][0..comment_len], apk_data[eocd_pos + 22..eocd_pos + 22 + comment_len]);
        out_pos += comment_len;
    }
    return out_pos;
}
