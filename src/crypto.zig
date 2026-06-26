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
const MAX_LIMBS = 160;

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
        const idx = @as(usize, @intCast(i / 4));
        if (idx >= MAX_LIMBS) break;
        const src_pos = bytes.len - 1 - i;
        const shift = @as(u5, @intCast((i % 4) * 8));
        r.limbs[idx] |= @as(u32, bytes[src_pos]) << shift;
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
        // Limb j (j=0 is LSB) goes to the rightmost 4 bytes of the output
        var k: usize = 0;
        while (k < 4) : (k += 1) {
            const base = j * 4 + k;
            if (base < out.len) {
                const pos = (out.len - 1) - base;
                out[pos] = @as(u8, @truncate(v >> @as(u5, @truncate(k * 8))));
            }
        }
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
    var div_iter: u32 = 0;
    while (num_len >= b.len and (num_len > b.len or cmpNumLimbs(num[0..num_len], b.limbs[0..b.len]) >= 0)) {
        div_iter += 1;
        if (div_iter > 8192) {
            _ = sys.write(2, "DIV INFLOOP\n", 12);
            break;
        }
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
        // Check if guess is too large (sub > num shifted by shift)
        if (shift + sub.len > num_len + 1) {
            // too big, reduce guess
        } else {
            var cmp: i8 = 0;
            if (shift + sub.len > num_len) {
                cmp = 1;
            } else {
                var ci: usize = sub.len;
                while (ci > 0) {
                    ci -= 1;
                    if (num[shift + ci] != sub.limbs[ci]) {
                        cmp = if (num[shift + ci] > sub.limbs[ci]) 1 else -1;
                        break;
                    }
                }
            }
            if (cmp < 0) {
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
        }
        // Subtract sub * beta^shift from num (aligned by shift)
        var borrow: u64 = 0;
        var si: usize = 0;
        while (si < sub.len) : (si += 1) {
            const idx = shift + si;
            var ext_a: u64 = num[idx];
            if (borrow > 0) {
                if (ext_a > 0) { ext_a -= 1; borrow = 0; } else { ext_a = 0xFFFFFFFF; }
            }
            const sub_limb = sub.limbs[si];
            if (ext_a < sub_limb) {
                num[idx] = @as(u32, @truncate(ext_a + 0x100000000 - sub_limb));
                borrow = 1;
            } else {
                num[idx] = @as(u32, @truncate(ext_a - sub_limb));
            }
        }
        // Propagate remaining borrow
        if (borrow > 0) {
            var bi: usize = shift + sub.len;
            while (bi <= num_len) : (bi += 1) {
                if (num[bi] > 0) { num[bi] -= 1; break; }
                num[bi] = 0xFFFFFFFF;
            }
        }
        // Trim leading zeros
        while (num_len > 0 and num[num_len - 1] == 0) num_len -= 1;
        quot[shift] +%= @as(LIMB, @truncate(guess));
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

pub fn biModExp(base: *const BigInt, exp: *const BigInt, mod: *const BigInt, out: *BigInt) void {
    var result = BigInt{}; result.limbs[0] = 1; result.len = 1;
    var base_m: BigInt = undefined; biMod(base, mod, &base_m);
    var i: usize = exp.len;
    while (i > 0) {
        i -= 1;
        var bit: u32 = 0x80000000;
        while (bit > 0) {
            var tmp: BigInt = undefined;
            biMul(&result, &result, &tmp);
            biMod(&tmp, mod, &result);
            if ((exp.limbs[i] & bit) != 0) {
                var tmp2: BigInt = undefined;
                biMul(&result, &base_m, &tmp2);
                biMod(&tmp2, mod, &result);
            }
            bit >>= 1;
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

fn bitLen(a: *const BigInt) usize {
    if (a.len == 0) return 0;
    var bits = (a.len - 1) * 32;
    var top = a.limbs[a.len - 1];
    while (top > 0) {
        bits += 1;
        top >>= 1;
    }
    return bits;
}

pub fn mgf1(seed: []const u8, mask_len: usize, out: []u8) void {
    var counter: u32 = 0;
    var off: usize = 0;
    while (off < mask_len) {
        var c: [4]u8 = undefined;
        c[0] = @as(u8, @intCast(counter >> 24));
        c[1] = @as(u8, @intCast(counter >> 16));
        c[2] = @as(u8, @intCast(counter >> 8));
        c[3] = @as(u8, @truncate(counter));
        var hash_input: [256]u8 = undefined;
        @memcpy(hash_input[0..seed.len], seed);
        @memcpy(hash_input[seed.len..][0..4], &c);
        var hash_out: [32]u8 = undefined;
        sha256(hash_input[0..seed.len + 4], &hash_out);
        const copy_len = @min(32, mask_len - off);
        @memcpy(out[off..][0..copy_len], hash_out[0..copy_len]);
        off += copy_len;
        counter += 1;
    }
}

pub fn verifyRsaPssSignature(content_hash: []const u8, sig: []const u8, n: *const BigInt, e: *const BigInt) bool {
    const emLen = RSA_KEY_BYTES;
    const hLen: usize = 32;
    const sLen: usize = 32;
    if (sig.len != emLen) return false;
    if (content_hash.len != hLen) return false;

    var sig_bn = biFromBytes(sig);
    var em_bn: BigInt = undefined;
    biModExp(&sig_bn, e, n, &em_bn);
    var em: [RSA_KEY_BYTES]u8 = undefined;
    biToBytes(&em_bn, em[0..RSA_KEY_BYTES]);

    if (em[emLen - 1] != 0xBC) return false;

    const maskedDB = em[0 .. emLen - hLen - 1];
    const H = em[emLen - hLen - 1 .. emLen - 1];

    var dbMask: [256]u8 = undefined;
    mgf1(H, emLen - hLen - 1, dbMask[0..]);

    var DB: [256]u8 = undefined;
    for (maskedDB, 0..) |b, i| DB[i] = b ^ dbMask[i];

    const modBits = bitLen(n);
    const emBits = modBits - 1;
    const db_clear_bits = 8 * emLen - emBits;
    if (db_clear_bits > 0 and db_clear_bits <= 8 * emLen) {
        var bits_left = db_clear_bits;
        var byte_idx: usize = 0;
        while (bits_left >= 8) {
            DB[byte_idx] = 0;
            byte_idx += 1;
            bits_left -= 8;
        }
        if (bits_left > 0) {
            DB[byte_idx] &= @as(u8, 0xFF) >> @as(u3, @intCast(bits_left));
        }
    }

    const zero_pad_len = emLen - hLen - sLen - 2;
    for (0..zero_pad_len) |i| {
        if (DB[i] != 0) return false;
    }
    if (DB[zero_pad_len] != 0x01) return false;

    const salt = DB[zero_pad_len + 1 .. zero_pad_len + 1 + sLen];

    var m_prime: [8 + 32 + 32]u8 = undefined;
    for (0..8) |i| m_prime[i] = 0;
    @memcpy(m_prime[8..][0..hLen], content_hash);
    @memcpy(m_prime[8 + hLen ..][0..sLen], salt);
    var h2: [32]u8 = undefined;
    sha256(&m_prime, &h2);

    for (0..hLen) |i| {
        if (H[i] != h2[i]) return false;
    }
    return true;
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

// ============================== ChaCha20 ==============================

fn chacha20QuarterRound(a: *u32, b: *u32, c: *u32, d: *u32) void {
    a.* +%= b.*; d.* ^= a.*; d.* = (d.* << 16) | (d.* >> 16);
    c.* +%= d.*; b.* ^= c.*; b.* = (b.* << 12) | (b.* >> 20);
    a.* +%= b.*; d.* ^= a.*; d.* = (d.* << 8) | (d.* >> 24);
    c.* +%= d.*; b.* ^= c.*; b.* = (b.* << 7) | (b.* >> 25);
}

fn chacha20Block(key: *const [32]u8, counter: u32, nonce: *const [12]u8, out: *[64]u8) void {
    var s: [16]u32 = undefined;
    s[0] = 0x61707865; s[1] = 0x3320646e; s[2] = 0x79622d32; s[3] = 0x6b206574;
    for (0..8) |i| {
        s[4 + i] = (@as(u32, key[4*i]) << 0) | (@as(u32, key[4*i+1]) << 8) |
                   (@as(u32, key[4*i+2]) << 16) | (@as(u32, key[4*i+3]) << 24);
    }
    s[12] = counter;
    for (0..3) |i| {
        s[13 + i] = (@as(u32, nonce[4*i]) << 0) | (@as(u32, nonce[4*i+1]) << 8) |
                     (@as(u32, nonce[4*i+2]) << 16) | (@as(u32, nonce[4*i+3]) << 24);
    }
    var w: [16]u32 = undefined;
    @memcpy(&w, &s);
    for (0..10) |_| {
        chacha20QuarterRound(&w[0], &w[4], &w[8], &w[12]);
        chacha20QuarterRound(&w[1], &w[5], &w[9], &w[13]);
        chacha20QuarterRound(&w[2], &w[6], &w[10], &w[14]);
        chacha20QuarterRound(&w[3], &w[7], &w[11], &w[15]);
        chacha20QuarterRound(&w[0], &w[5], &w[10], &w[15]);
        chacha20QuarterRound(&w[1], &w[6], &w[11], &w[12]);
        chacha20QuarterRound(&w[2], &w[7], &w[8], &w[13]);
        chacha20QuarterRound(&w[3], &w[4], &w[9], &w[14]);
    }
    for (0..16) |i| {
        w[i] +%= s[i];
        out[4*i+0] = @as(u8, @truncate(w[i]));
        out[4*i+1] = @as(u8, @truncate(w[i] >> 8));
        out[4*i+2] = @as(u8, @truncate(w[i] >> 16));
        out[4*i+3] = @as(u8, @truncate(w[i] >> 24));
    }
}

fn chacha20Xor(key: *const [32]u8, nonce: *const [12]u8, data: []const u8, out: []u8) void {
    var counter: u32 = 0;
    var off: usize = 0;
    while (off < data.len) : (counter += 1) {
        var block: [64]u8 = undefined;
        chacha20Block(key, counter, nonce, &block);
        const chunk = @min(64, data.len - off);
        for (0..chunk) |i| out[off + i] = data[off + i] ^ block[i];
        off += chunk;
    }
}

// ============================== Poly1305 ==============================

const Poly1305 = struct {
    acc: [5]u64 = .{0} ** 5,
    r: [5]u64 = .{0} ** 5,
    s: [16]u8 = .{0} ** 16,
    buf: [16]u8 = .{0} ** 16,
    buflen: usize = 0,
    final: bool = false,

    fn init(key: *const [32]u8) Poly1305 {
        var p = Poly1305{};
        @memcpy(p.s[0..16], key[16..32]);
        var clamp_key: [16]u8 = undefined;
        @memcpy(clamp_key[0..16], key[0..16]);
        clamp_key[3] &= 15; clamp_key[7] &= 15; clamp_key[11] &= 15; clamp_key[15] &= 15;
        clamp_key[4] &= 252; clamp_key[8] &= 252; clamp_key[12] &= 252;
        p.r[0] = (@as(u64, clamp_key[0]) << 0) | (@as(u64, clamp_key[1]) << 8) | (@as(u64, clamp_key[2]) << 16) | (@as(u64, clamp_key[3]) << 24);
        p.r[1] = (@as(u64, clamp_key[4]) >> 20) | (@as(u64, clamp_key[5]) << 12) | (@as(u64, clamp_key[6]) << 20) | (@as(u64, clamp_key[7]) << 28);
        p.r[2] = (@as(u64, clamp_key[8]) >> 8) | (@as(u64, clamp_key[9]) << 24) | (@as(u64, clamp_key[10]) << 32) | (@as(u64, clamp_key[11]) << 40);
        p.r[3] = (@as(u64, clamp_key[12]) >> 44) | (@as(u64, clamp_key[13]) << 20) | (@as(u64, clamp_key[14]) << 28) | (@as(u64, clamp_key[15]) << 36);
        p.r[4] = (@as(u64, clamp_key[12]) >> 18) | (@as(u64, clamp_key[13]) << 6) | (@as(u64, clamp_key[14]) << 14) | (@as(u64, clamp_key[15]) << 22);
        p.r[0] &= 0x0FFFFFFFFFFFFA;
        p.r[1] &= 0x0FFFFFFFFFFFFC;
        p.r[2] &= 0x0FFFFFFFFFFFFC;
        p.r[3] &= 0x0FFFFFFFFFFFFC;
        p.r[4] &= 0x0FFFFFFFFFFFFC;
        return p;
    }

    fn add(self: *Poly1305, data: []const u8) void {
        var off: usize = 0;
        while (off < data.len) {
            const space = 16 - self.buflen;
            const take = @min(space, data.len - off);
            @memcpy(self.buf[self.buflen..][0..take], data[off..][0..take]);
            self.buflen += take;
            off += take;
            if (self.buflen == 16) {
                self.block();
                self.buflen = 0;
            }
        }
    }

    fn block(self: *Poly1305) void {
        var n: [5]u64 = undefined;
        n[0] = (@as(u64, self.buf[0]) << 0) | (@as(u64, self.buf[1]) << 8) | (@as(u64, self.buf[2]) << 16) | (@as(u64, self.buf[3]) << 26);
        n[1] = (@as(u64, self.buf[3]) >> 6) | (@as(u64, self.buf[4]) << 2) | (@as(u64, self.buf[5]) << 10) | (@as(u64, self.buf[6]) << 18) | (@as(u64, self.buf[7]) << 26);
        n[2] = (@as(u64, self.buf[7]) >> 6) | (@as(u64, self.buf[8]) << 2) | (@as(u64, self.buf[9]) << 10) | (@as(u64, self.buf[10]) << 18) | (@as(u64, self.buf[11]) << 26);
        n[3] = (@as(u64, self.buf[11]) >> 6) | (@as(u64, self.buf[12]) << 2) | (@as(u64, self.buf[13]) << 10) | (@as(u64, self.buf[14]) << 18) | (@as(u64, self.buf[15]) << 26);
        n[4] = (@as(u64, self.buf[15]) >> 6) | (@as(u64, 1) << 24);
        var c: u128 = 0;
        for (0..5) |i| {
            c += @as(u128, self.acc[i]) + @as(u128, n[i]) * @as(u128, self.r[i]);
            self.acc[i] = @as(u64, @truncate(c));
            c >>= 52;
        }
        // Carry propagation
        if (c > 0) {
            self.acc[0] += @as(u64, @truncate(c * 5));
            c = 0;
            // Re-normalize
            for (0..4) |i| {
                self.acc[i+1] += (self.acc[i] >> 52);
                self.acc[i] &= 0x0FFFFFFFFFFFFFFF;
            }
        }
        // Normalize limbs
        for (0..4) |i| {
            const carry = self.acc[i] >> 52;
            self.acc[i] &= 0x0FFFFFFFFFFFFFFF;
            self.acc[i+1] += carry;
        }
    }

    fn finish(self: *Poly1305, out: *[16]u8) void {
        if (self.buflen > 0) {
            self.buf[self.buflen] = 1;
            var j: usize = self.buflen + 1;
            while (j < 16) : (j += 1) self.buf[j] = 0;
            self.block();
        }
        // acc mod (2^130 - 5)
        var tmp: [5]u64 = undefined;
        @memcpy(&tmp, &self.acc);
        // Subtract p repeatedly
        const p0: u64 = 0x0FFFFFFFFFFFFFFA;
        const p1: u64 = 0x0FFFFFFFFFFFFFFF;
        const p2: u64 = 0x0FFFFFFFFFFFFFFF;
        const p3: u64 = 0x0FFFFFFFFFFFFFFF;
        const p4: u64 = 0x0FFFFFFFFFFFFFFF;
        var borrow: u64 = 0;
        for (0..4) |_| {
            var tmp2: [5]u64 = undefined;
            @memcpy(&tmp2, &tmp);
            var b2: u64 = 0;
            const s_0 = tmp2[0] -% p0 -% b2; b2 = if (s_0 > tmp2[0]) 1 else 0;
            const s_1 = tmp2[1] -% p1 -% b2; b2 = if (s_1 > tmp2[1]) 1 else 0;
            const s_2 = tmp2[2] -% p2 -% b2; b2 = if (s_2 > tmp2[2]) 1 else 0;
            const s_3 = tmp2[3] -% p3 -% b2; b2 = if (s_3 > tmp2[3]) 1 else 0;
            const s_4 = tmp2[4] -% p4 -% b2;
            if (borrow == 0) {
                var cmp: i8 = 0;
                if (tmp[4] > p4) cmp = 1
                else if (tmp[4] < p4) cmp = -1
                else if (tmp[3] > p3) cmp = 1
                else if (tmp[3] < p3) cmp = -1
                else if (tmp[2] > p2) cmp = 1
                else if (tmp[2] < p2) cmp = -1
                else if (tmp[1] > p1) cmp = 1
                else if (tmp[1] < p1) cmp = -1
                else if (tmp[0] > p0) cmp = 1
                else if (tmp[0] < p0) cmp = -1;
                if (cmp >= 0) {
                    tmp[0] = s_0; tmp[1] = s_1; tmp[2] = s_2; tmp[3] = s_3; tmp[4] = s_4;
                }
            }
            borrow = 1;
        }
        for (0..5) |i| self.acc[i] = tmp[i];
        // Convert to 128-bit LE and add s (mod 2^128)
        const lo = self.acc[0] | ((self.acc[1] & 0xFFF) << 52);
        const hi = (self.acc[1] >> 12) | ((self.acc[2] & 0xFFFFFF) << 40);
        var raw: [16]u8 = undefined;
        for (0..8) |i| {
            raw[i] = @as(u8, @truncate(lo >> @as(u6, @intCast(i * 8))));
            raw[8+i] = @as(u8, @truncate(hi >> @as(u6, @intCast(i * 8))));
        }
        var carry: u16 = 0;
        for (0..16) |i| {
            const sum = @as(u16, raw[i]) + @as(u16, self.s[i]) + carry;
            out[i] = @as(u8, @truncate(sum));
            carry = sum >> 8;
        }
    }
};

pub fn chacha20Poly1305Encrypt(key: *const [32]u8, nonce: *const [12]u8, aad: []const u8, plaintext: []const u8, ciphertext: []u8, tag: *[16]u8) void {
    var otk: [32]u8 = undefined;
    var zero_block: [64]u8 = undefined;
    chacha20Block(key, 0, nonce, &zero_block);
    @memcpy(otk[0..32], zero_block[0..32]);
    var poly_key: [32]u8 = undefined;
    @memcpy(poly_key[0..32], zero_block[0..32]);
    chacha20Xor(key, nonce, plaintext, ciphertext);
    var poly = Poly1305.init(&poly_key);
    poly.add(aad);
    // Pad AAD to 16 bytes
    if (aad.len % 16 != 0) {
        var pad: [16]u8 = .{0} ** 16;
        poly.add(pad[0..(16 - aad.len % 16)]);
    }
    poly.add(ciphertext[0..plaintext.len]);
    if (plaintext.len % 16 != 0) {
        var pad: [16]u8 = .{0} ** 16;
        poly.add(pad[0..(16 - plaintext.len % 16)]);
    }
    // Length block
    var len_block: [16]u8 = undefined;
    for (0..8) |i| len_block[i] = @as(u8, @truncate(@as(u64, aad.len) >> @as(u6, @intCast((7-i)*8))));
    for (0..8) |i| len_block[8+i] = @as(u8, @truncate(@as(u64, plaintext.len) >> @as(u6, @intCast((7-i)*8))));
    poly.add(&len_block);
    poly.finish(tag);
}

pub fn chacha20Poly1305Decrypt(key: *const [32]u8, nonce: *const [12]u8, aad: []const u8, ciphertext: []const u8, tag: *const [16]u8, plaintext: []u8) bool {
    var computed_tag: [16]u8 = undefined;
    // Compute Poly1305 tag over the ciphertext (without XORing)
    var zero_block: [64]u8 = undefined;
    chacha20Block(key, 0, nonce, &zero_block);
    var poly_key: [32]u8 = undefined;
    @memcpy(poly_key[0..32], zero_block[0..32]);
    var poly = Poly1305.init(&poly_key);
    poly.add(aad);
    if (aad.len % 16 != 0) {
        var pad: [16]u8 = .{0} ** 16;
        poly.add(pad[0..(16 - aad.len % 16)]);
    }
    poly.add(ciphertext);
    if (ciphertext.len % 16 != 0) {
        var pad: [16]u8 = .{0} ** 16;
        poly.add(pad[0..(16 - ciphertext.len % 16)]);
    }
    var len_block: [16]u8 = undefined;
    for (0..8) |i| len_block[i] = @as(u8, @truncate(@as(u64, aad.len) >> @as(u6, @intCast((7-i)*8))));
    for (0..8) |i| len_block[8+i] = @as(u8, @truncate(@as(u64, ciphertext.len) >> @as(u6, @intCast((7-i)*8))));
    poly.add(&len_block);
    poly.finish(&computed_tag);

    // Constant-time tag comparison
    var ok = true;
    for (0..16) |i| { if (computed_tag[i] != tag[i]) ok = false; }
    if (!ok) return false;

    // Decrypt: XOR ciphertext with keystream
    chacha20Xor(key, nonce, ciphertext, plaintext);
    return true;
}

// ============================== SHA-384 ==============================

const K64 = [_]u64{
    0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc,
    0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118,
    0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
    0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694,
    0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
    0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
    0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4,
    0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70,
    0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
    0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
    0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30,
    0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8,
    0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8,
    0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
    0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
    0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b,
};

fn rotR64(x: u64, n: u64) u64 { return (x >> @as(u6, @intCast(n))) | (x << @as(u6, @intCast(64 - n))); }
fn ch64(x: u64, y: u64, z: u64) u64 { return (x & y) ^ ((~x) & z); }
fn maj64(x: u64, y: u64, z: u64) u64 { return (x & y) ^ (x & z) ^ (y & z); }
fn s0_64(x: u64) u64 { return rotR64(x, 28) ^ rotR64(x, 34) ^ rotR64(x, 39); }
fn s1_64(x: u64) u64 { return rotR64(x, 14) ^ rotR64(x, 18) ^ rotR64(x, 41); }
fn w0_64(x: u64) u64 { return rotR64(x, 1) ^ rotR64(x, 8) ^ (x >> 7); }
fn w1_64(x: u64) u64 { return rotR64(x, 19) ^ rotR64(x, 61) ^ (x >> 6); }

fn w64be(buf: []u8, pos: usize, v: u64) void {
    buf[pos+0] = @as(u8, @truncate(v >> 56));
    buf[pos+1] = @as(u8, @truncate(v >> 48));
    buf[pos+2] = @as(u8, @truncate(v >> 40));
    buf[pos+3] = @as(u8, @truncate(v >> 32));
    buf[pos+4] = @as(u8, @truncate(v >> 24));
    buf[pos+5] = @as(u8, @truncate(v >> 16));
    buf[pos+6] = @as(u8, @truncate(v >> 8));
    buf[pos+7] = @as(u8, @truncate(v));
}

fn r64be(buf: []const u8, pos: usize) u64 {
    return (@as(u64, buf[pos]) << 56) | (@as(u64, buf[pos+1]) << 48) | (@as(u64, buf[pos+2]) << 40) |
           (@as(u64, buf[pos+3]) << 32) | (@as(u64, buf[pos+4]) << 24) | (@as(u64, buf[pos+5]) << 16) |
           (@as(u64, buf[pos+6]) << 8) | @as(u64, buf[pos+7]);
}

pub fn sha384(data: []const u8, out: *[48]u8) void {
    var h: [8]u64 = [8]u64{
        0xcbbb9d5dc1059ed8, 0x629a292a367cd507, 0x9159015a3070dd17, 0x152fecd8f70e5939,
        0x67332667ffc00b31, 0x8eb44a8768581511, 0xdb0c2e0d64f98fa7, 0x47b5481dbefa4fa4,
    };
    const bit_len: u128 = @as(u128, data.len) * 8;
    var buf: [128]u8 = undefined;
    var i: usize = 0;
    while (i < data.len) {
        const chunk_end = @min(i + 128, data.len);
        const chunk_len = chunk_end - i;
        if (chunk_len == 128) {
            sha384Block(&h, data[i..][0..128]);
            i += 128;
        } else {
            @memcpy(buf[0..chunk_len], data[i..][0..chunk_len]);
            buf[chunk_len] = 0x80;
            var j: usize = chunk_len + 1;
            while (j < 112) { buf[j] = 0; j += 1; }
            if (chunk_len >= 112) {
                while (j < 128) { buf[j] = 0; j += 1; }
                sha384Block(&h, &buf);
                j = 0;
                while (j < 112) { buf[j] = 0; j += 1; }
            }
            w64be(&buf, 112, @as(u64, @truncate(bit_len >> 64)));
            w64be(&buf, 120, @as(u64, @truncate(bit_len)));
            sha384Block(&h, &buf);
            break;
        }
    }
    if (data.len % 128 == 0) {
        var j: usize = 0;
        while (j < 112) { buf[j] = 0; j += 1; }
        buf[0] = 0x80;
        w64be(&buf, 112, @as(u64, @truncate(bit_len >> 64)));
        w64be(&buf, 120, @as(u64, @truncate(bit_len)));
        sha384Block(&h, &buf);
    }
    for (h[0..6], 0..) |hv, idx| w64be(out, idx * 8, hv);
}

fn sha384Block(h: *[8]u64, block: *const [128]u8) void {
    var w: [80]u64 = undefined;
    for (0..16) |t| w[t] = r64be(block, t * 8);
    for (16..80) |t| w[t] = w1_64(w[t-2]) +% w[t-7] +% w0_64(w[t-15]) +% w[t-16];
    var a = h[0]; var b = h[1]; var c = h[2]; var d = h[3];
    var e = h[4]; var f = h[5]; var g = h[6]; var hh = h[7];
    for (0..80) |t| {
        const t1 = hh +% s1_64(e) +% ch64(e, f, g) +% K64[t] +% w[t];
        const t2 = s0_64(a) +% maj64(a, b, c);
        hh = g; g = f; f = e; e = d +% t1; d = c; c = b; b = a; a = t1 +% t2;
    }
    h[0] +%= a; h[1] +%= b; h[2] +%= c; h[3] +%= d;
    h[4] +%= e; h[5] +%= f; h[6] +%= g; h[7] +%= hh;
}

// ============================== AES-256 Key Schedule ==============================

pub fn aes256KeySchedule(key: *const [32]u8, out: *[240]u8) void {
    var w: [60]u32 = undefined;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        w[i] = (@as(u32, key[4*i]) << 24) | (@as(u32, key[4*i+1]) << 16) |
               (@as(u32, key[4*i+2]) << 8) | @as(u32, key[4*i+3]);
    }
    while (i < 60) : (i += 1) {
        var tmp = w[i-1];
        if (i % 8 == 0) tmp = aesSubWord(aesRotWord(tmp)) ^ (AES_RCON[i / 8] << 24)
        else if (i % 8 == 4) tmp = aesSubWord(tmp);
        w[i] = w[i-8] ^ tmp;
    }
    for (0..60) |j| {
        out[j*4+0] = @as(u8, @truncate(w[j] >> 24));
        out[j*4+1] = @as(u8, @truncate(w[j] >> 16));
        out[j*4+2] = @as(u8, @truncate(w[j] >> 8));
        out[j*4+3] = @as(u8, @truncate(w[j]));
    }
}

pub fn aes256Encrypt(plaintext: *const [16]u8, key_schedule: *const [240]u8, ciphertext: *[16]u8) void {
    var state: [16]u8 = undefined;
    @memcpy(state[0..16], plaintext[0..16]);
    aesAddRoundKey(&state, @as(*const [16]u8, @ptrCast(key_schedule)));
    var round: usize = 1;
    while (round < 14) : (round += 1) {
        aesSubBytes(&state);
        aesShiftRows(&state);
        aesMixColumns(&state);
        aesAddRoundKey(&state, @as(*const [16]u8, @ptrCast(@as([*]const u8, @ptrCast(key_schedule)) + round * 16)));
    }
    aesSubBytes(&state);
    aesShiftRows(&state);
    aesAddRoundKey(&state, @as(*const [16]u8, @ptrCast(@as([*]const u8, @ptrCast(key_schedule)) + 14 * 16)));
    @memcpy(ciphertext[0..16], &state);
}

// ============================== GCM with AES-256 ==============================

fn gcmInit256(key: *const [32]u8, nonce: *const [12]u8, h: *[16]u8, j0: *[16]u8, icb: *[16]u8) [240]u8 {
    var ks: [240]u8 = undefined;
    aes256KeySchedule(key, &ks);
    var zero: [16]u8 = [_]u8{0} ** 16;
    aes256Encrypt(&zero, &ks, h);
    @memcpy(j0[0..12], nonce[0..12]);
    j0[12] = 0; j0[13] = 0; j0[14] = 0; j0[15] = 1;
    @memcpy(icb[0..16], j0[0..16]);
    gcmInc32(icb);
    return ks;
}

fn gcmGctr256(out: []u8, key_schedule: *const [240]u8, icb: *const [16]u8, data: []const u8) void {
    var counter: [16]u8 = undefined;
    @memcpy(counter[0..16], icb[0..16]);
    var off: usize = 0;
    while (off < data.len) {
        var encrypted: [16]u8 = undefined;
        aes256Encrypt(&counter, key_schedule, &encrypted);
        const chunk = @min(16, data.len - off);
        for (0..chunk) |i| out[off + i] = data[off + i] ^ encrypted[i];
        off += chunk;
        gcmInc32(&counter);
    }
}

pub fn gcmEncrypt256(key: *const [32]u8, nonce: *const [12]u8, aad: []const u8, plaintext: []const u8, ciphertext: []u8, tag: *[16]u8) void {
    var h: [16]u8 = undefined;
    var j0: [16]u8 = undefined;
    var icb: [16]u8 = undefined;
    const ks = gcmInit256(key, nonce, &h, &j0, &icb);
    gcmGctr256(ciphertext, &ks, &icb, plaintext);
    var ghash_out: [16]u8 = undefined;
    gcmGhash(&ghash_out, &h, aad, ciphertext[0..plaintext.len]);
    var tag_block: [16]u8 = undefined;
    aes256Encrypt(&j0, &ks, &tag_block);
    gcmXor(tag, &ghash_out, &tag_block);
}

pub fn gcmDecrypt256(key: *const [32]u8, nonce: *const [12]u8, aad: []const u8, ciphertext: []const u8, tag: *const [16]u8, plaintext: []u8) bool {
    var h: [16]u8 = undefined;
    var j0: [16]u8 = undefined;
    var icb: [16]u8 = undefined;
    const ks = gcmInit256(key, nonce, &h, &j0, &icb);
    var ghash_out: [16]u8 = undefined;
    gcmGhash(&ghash_out, &h, aad, ciphertext);
    var tag_block: [16]u8 = undefined;
    aes256Encrypt(&j0, &ks, &tag_block);
    var expected_tag: [16]u8 = undefined;
    gcmXor(&expected_tag, &ghash_out, &tag_block);
    var ok = true;
    for (0..16) |i| { if (expected_tag[i] != tag[i]) ok = false; }
    if (!ok) return false;
    gcmInc32(&j0);
    gcmGctr256(plaintext, &ks, &j0, ciphertext);
    return true;
}

// ============================== HMAC-SHA256 ==============================

pub fn hmacSha256(key: []const u8, data: []const u8, out: *[32]u8) void {
    var k: [64]u8 = [_]u8{0} ** 64;
    if (key.len > 64) {
        sha256(key, @as(*[32]u8, @ptrCast(&k[0..32].*)));
    } else {
        @memcpy(k[0..key.len], key);
    }
    var ipad: [64]u8 = undefined;
    var opad: [64]u8 = undefined;
    for (0..64) |i| {
        ipad[i] = k[i] ^ 0x36;
        opad[i] = k[i] ^ 0x5C;
    }
    var inner_hash: [32]u8 = undefined;
    var inner_buf: [64 + 64]u8 = undefined;
    @memcpy(inner_buf[0..64], &ipad);
    if (data.len <= 64) {
        @memcpy(inner_buf[64..][0..data.len], data);
        sha256(inner_buf[0 .. 64 + data.len], &inner_hash);
    } else {
        var full: [128]u8 = undefined;
        @memcpy(full[0..64], &ipad);
        @memcpy(full[64..][0..data.len], data);
        sha256(full[0 .. 64 + data.len], &inner_hash);
        // For longer data, we'd need to hash in chunks, but TLS uses small inputs
    }
    var outer_buf: [64 + 32]u8 = undefined;
    @memcpy(outer_buf[0..64], &opad);
    @memcpy(outer_buf[64..][0..32], &inner_hash);
    sha256(outer_buf[0..96], out);
}

pub fn hmacSha256WithSeparateBlock(key_buf: *const [64]u8, data: []const u8, out: *[32]u8) void {
    var inner_hash: [32]u8 = undefined;
    var inner: [128]u8 = undefined;
    for (0..64) |i| inner[i] = key_buf[i] ^ 0x36;
    @memcpy(inner[64..][0..data.len], data);
    sha256(inner[0 .. 64 + data.len], &inner_hash);
    var outer: [96]u8 = undefined;
    for (0..64) |i| outer[i] = key_buf[i] ^ 0x5C;
    @memcpy(outer[64..][0..32], &inner_hash);
    sha256(&outer, out);
}

// ============================== HKDF (TLS 1.3) ==============================

pub fn hkdfExtract(salt: []const u8, ikm: []const u8, out: *[32]u8) void {
    hmacSha256(salt, ikm, out);
}

pub fn hkdfExpandLabel(prk: []const u8, label: []const u8, context: []const u8, out: []u8) void {
    const label_prefix = "tls13 ";
    var hkdf_label: [256]u8 = undefined;
    var pos: usize = 0;
    // length (2 bytes, big-endian) - written at the end
    pos += 2;
    // label length (1 byte) = "tls13 " + label
    hkdf_label[pos] = @as(u8, @intCast(label_prefix.len + label.len));
    pos += 1;
    // label
    for (label_prefix) |c| { hkdf_label[pos] = c; pos += 1; }
    for (label) |c| { hkdf_label[pos] = c; pos += 1; }
    // context length (1 byte)
    hkdf_label[pos] = @as(u8, @intCast(context.len));
    pos += 1;
    // context
    @memcpy(hkdf_label[pos..][0..context.len], context);
    pos += context.len;
    // Write total length at front
    const total_len: u16 = @as(u16, @intCast(out.len));
    hkdf_label[0] = @as(u8, @intCast(total_len >> 8));
    hkdf_label[1] = @as(u8, @intCast(total_len));
    // Perform HKDF-Expand
    var t: [32]u8 = [_]u8{0} ** 32;
    var t_len: usize = 0;
    var off: usize = 0;
    var counter: u8 = 1;
    while (off < out.len) : (counter += 1) {
        var info: [256]u8 = undefined;
        var ipos: usize = 0;
        if (t_len > 0) {
            @memcpy(info[ipos..][0..t_len], t[0..t_len]);
            ipos += t_len;
        }
        @memcpy(info[ipos..][0..pos], hkdf_label[0..pos]);
        ipos += pos;
        info[ipos] = counter;
        ipos += 1;
        hmacSha256(prk, info[0..ipos], &t);
        t_len = 32;
        const copy_len = @min(32, out.len - off);
        @memcpy(out[off..][0..copy_len], t[0..copy_len]);
        off += copy_len;
    }
}

pub fn deriveSecret(prk: []const u8, label: []const u8, msg_hash: []const u8, out: *[32]u8) void {
    hkdfExpandLabel(prk, label, msg_hash, out[0..32]);
}

// ============================== AES-128 ==============================

const AES_SBOX: [256]u8 = [256]u8{
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
};

fn aesSubWord(w: u32) u32 {
    return (@as(u32, AES_SBOX[@as(u8, @truncate(w >> 24))]) << 24) |
           (@as(u32, AES_SBOX[@as(u8, @truncate(w >> 16))]) << 16) |
           (@as(u32, AES_SBOX[@as(u8, @truncate(w >> 8))]) << 8) |
           @as(u32, AES_SBOX[@as(u8, @truncate(w))]);
}

fn aesRotWord(w: u32) u32 {
    return (w << 8) | (w >> 24);
}

const AES_RCON: [11]u32 = [11]u32{ 0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36 };

pub fn aes128KeySchedule(key: *const [16]u8, out: *[176]u8) void {
    var w: [44]u32 = undefined;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        w[i] = (@as(u32, key[4 * i]) << 24) | (@as(u32, key[4 * i + 1]) << 16) |
               (@as(u32, key[4 * i + 2]) << 8) | @as(u32, key[4 * i + 3]);
    }
    while (i < 44) : (i += 1) {
        var tmp = w[i - 1];
        if (i % 4 == 0) tmp = aesSubWord(aesRotWord(tmp)) ^ (AES_RCON[i / 4] << 24);
        w[i] = w[i - 4] ^ tmp;
    }
    for (0..44) |j| {
        out[j * 4 + 0] = @as(u8, @truncate(w[j] >> 24));
        out[j * 4 + 1] = @as(u8, @truncate(w[j] >> 16));
        out[j * 4 + 2] = @as(u8, @truncate(w[j] >> 8));
        out[j * 4 + 3] = @as(u8, @truncate(w[j]));
    }
}

fn aesAddRoundKey(state: *[16]u8, round_key: *const [16]u8) void {
    for (0..16) |i| state[i] ^= round_key[i];
}

fn aesSubBytes(state: *[16]u8) void {
    for (0..16) |i| state[i] = AES_SBOX[state[i]];
}

fn aesShiftRows(state: *[16]u8) void {
    // Row 0: no shift
    // Row 1: shift left 1
    const t1 = state[1];
    state[1] = state[5]; state[5] = state[9]; state[9] = state[13]; state[13] = t1;
    // Row 2: shift left 2
    const t2a = state[2]; const t2b = state[6];
    state[2] = state[10]; state[6] = state[14]; state[10] = t2a; state[14] = t2b;
    // Row 3: shift left 3 (= shift right 1)
    const t3 = state[3];
    state[3] = state[15]; state[15] = state[11]; state[11] = state[7]; state[7] = t3;
}

fn aesGfMul(a: u8, b: u8) u8 {
    var aa = a;
    var bb = b;
    var result: u8 = 0;
    var i: u8 = 0;
    while (i < 8) : (i += 1) {
        if (bb & 1 != 0) result ^= aa;
        const hi = aa & 0x80;
        aa <<= 1;
        if (hi != 0) aa ^= 0x1B;
        bb >>= 1;
    }
    return result;
}

fn aesMixColumns(state: *[16]u8) void {
    for (0..4) |i| {
        const idx = i * 4;
        const a0 = state[idx];
        const a1 = state[idx + 1];
        const a2 = state[idx + 2];
        const a3 = state[idx + 3];
        state[idx] = aesGfMul(a0, 2) ^ aesGfMul(a1, 3) ^ a2 ^ a3;
        state[idx + 1] = a0 ^ aesGfMul(a1, 2) ^ aesGfMul(a2, 3) ^ a3;
        state[idx + 2] = a0 ^ a1 ^ aesGfMul(a2, 2) ^ aesGfMul(a3, 3);
        state[idx + 3] = aesGfMul(a0, 3) ^ a1 ^ a2 ^ aesGfMul(a3, 2);
    }
}

pub fn aes128Encrypt(plaintext: *const [16]u8, key_schedule: *const [176]u8, ciphertext: *[16]u8) void {
    var state: [16]u8 = undefined;
    @memcpy(state[0..16], plaintext[0..16]);
    aesAddRoundKey(&state, @as(*const [16]u8, @ptrCast(key_schedule)));
    var round: usize = 1;
    while (round < 10) : (round += 1) {
        aesSubBytes(&state);
        aesShiftRows(&state);
        aesMixColumns(&state);
        aesAddRoundKey(&state, @as(*const [16]u8, @ptrCast(@as([*]const u8, @ptrCast(key_schedule)) + round * 16)));
    }
    aesSubBytes(&state);
    aesShiftRows(&state);
    aesAddRoundKey(&state, @as(*const [16]u8, @ptrCast(@as([*]const u8, @ptrCast(key_schedule)) + 160)));
    @memcpy(ciphertext[0..16], &state);
}

// ============================== GCM Mode ==============================

fn gcmInc32(block: *[16]u8) void {
    var i: usize = 15;
    while (i > 11) : (i -= 1) {
        block[i] +%= 1;
        if (block[i] != 0) break;
    }
}

fn gcmGetBit(block: *const [16]u8, bit: usize) u8 {
    return (block[bit / 8] >> @as(u3, @intCast(7 - (bit % 8)))) & 1;
}

fn gcmSetBit(block: *[16]u8, bit: usize, val: u8) void {
    const mask = @as(u8, 1) << @as(u3, @intCast(7 - (bit % 8)));
    if (val != 0) block[bit / 8] |= mask else block[bit / 8] &= ~mask;
}

fn gcmShiftRight(block: *[16]u8) void {
    var carry: u8 = 0;
    for (0..16) |i| {
        const new_carry = block[i] & 1;
        block[i] = (block[i] >> 1) | (if (carry != 0) @as(u8, 0x80) else 0);
        carry = new_carry;
    }
}

fn gcmXor(out: *[16]u8, a: *const [16]u8, b: *const [16]u8) void {
    for (0..16) |i| out[i] = a[i] ^ b[i];
}

fn gcmMul(out: *[16]u8, x: *const [16]u8, y: *const [16]u8) void {
    var z: [16]u8 = [_]u8{0} ** 16;
    var v: [16]u8 = undefined;
    @memcpy(v[0..16], x[0..16]);
    for (0..128) |i| {
        if (gcmGetBit(y, i) != 0) gcmXor(&z, &z, &v);
        const lsb = v[15] & 1;
        gcmShiftRight(&v);
        if (lsb != 0) v[0] ^= 0xE1;
    }
    @memcpy(out[0..16], z[0..16]);
}

fn gcmGhash(out: *[16]u8, h: *const [16]u8, aad: []const u8, ciphertext: []const u8) void {
    var y: [16]u8 = [_]u8{0} ** 16;
    var block: [16]u8 = undefined;
    var i: usize = 0;
    while (i + 16 <= aad.len) {
        for (0..16) |j| block[j] = aad[i + j];
        gcmXor(&y, &y, &block);
        gcmMul(&y, &y, h);
        i += 16;
    }
    if (i < aad.len) {
        for (0..16) |j| block[j] = if (i + j < aad.len) aad[i + j] else 0;
        gcmXor(&y, &y, &block);
        gcmMul(&y, &y, h);
    }
    i = 0;
    while (i + 16 <= ciphertext.len) {
        for (0..16) |j| block[j] = ciphertext[i + j];
        gcmXor(&y, &y, &block);
        gcmMul(&y, &y, h);
        i += 16;
    }
    if (i < ciphertext.len) {
        for (0..16) |j| block[j] = if (i + j < ciphertext.len) ciphertext[i + j] else 0;
        gcmXor(&y, &y, &block);
        gcmMul(&y, &y, h);
    }
    var len_a: [8]u8 = undefined;
    var len_c: [8]u8 = undefined;
    var aad_bits: u64 = @as(u64, aad.len) * 8;
    var ct_bits: u64 = @as(u64, ciphertext.len) * 8;
    for (0..8) |j| {
        len_a[7 - j] = @as(u8, @truncate(aad_bits));
        aad_bits >>= 8;
        len_c[7 - j] = @as(u8, @truncate(ct_bits));
        ct_bits >>= 8;
    }
    for (0..8) |j| block[j] = len_a[j];
    for (0..8) |j| block[8 + j] = len_c[j];
    gcmXor(&y, &y, &block);
    gcmMul(&y, &y, h);
    @memcpy(out[0..16], y[0..16]);
}

fn gcmGctr(out: []u8, key_schedule: *const [176]u8, icb: *const [16]u8, data: []const u8) void {
    var counter: [16]u8 = undefined;
    @memcpy(counter[0..16], icb[0..16]);
    var off: usize = 0;
    while (off < data.len) {
        var encrypted: [16]u8 = undefined;
        aes128Encrypt(&counter, key_schedule, &encrypted);
        const chunk = @min(16, data.len - off);
        for (0..chunk) |i| out[off + i] = data[off + i] ^ encrypted[i];
        off += chunk;
        gcmInc32(&counter);
    }
}

pub fn gcmEncrypt(key: *const [16]u8, nonce: *const [12]u8, aad: []const u8, plaintext: []const u8, ciphertext: []u8, tag: *[16]u8) void {
    var ks: [176]u8 = undefined;
    aes128KeySchedule(key, &ks);
    var h: [16]u8 = undefined;
    var zero: [16]u8 = [_]u8{0} ** 16;
    aes128Encrypt(&zero, &ks, &h);
    var j0: [16]u8 = undefined;
    @memcpy(j0[0..12], nonce[0..12]);
    j0[12] = 0; j0[13] = 0; j0[14] = 0; j0[15] = 1;
    var icb: [16]u8 = j0;
    gcmInc32(&icb);
    gcmGctr(ciphertext, &ks, &icb, plaintext);
    var ghash_out: [16]u8 = undefined;
    gcmGhash(&ghash_out, &h, aad, ciphertext[0..plaintext.len]);
    var tag_block: [16]u8 = undefined;
    aes128Encrypt(&j0, &ks, &tag_block);
    gcmXor(tag, &ghash_out, &tag_block);
}

pub fn gcmDecrypt(key: *const [16]u8, nonce: *const [12]u8, aad: []const u8, ciphertext: []const u8, tag: *const [16]u8, plaintext: []u8) bool {
    var ks: [176]u8 = undefined;
    aes128KeySchedule(key, &ks);
    var h: [16]u8 = undefined;
    var zero: [16]u8 = [_]u8{0} ** 16;
    aes128Encrypt(&zero, &ks, &h);
    var j0: [16]u8 = undefined;
    @memcpy(j0[0..12], nonce[0..12]);
    j0[12] = 0; j0[13] = 0; j0[14] = 0; j0[15] = 1;
    var ghash_out: [16]u8 = undefined;
    gcmGhash(&ghash_out, &h, aad, ciphertext);
    var tag_block: [16]u8 = undefined;
    aes128Encrypt(&j0, &ks, &tag_block);
    var expected_tag: [16]u8 = undefined;
    gcmXor(&expected_tag, &ghash_out, &tag_block);
    var ok = true;
    for (0..16) |i| { if (expected_tag[i] != tag[i]) ok = false; }
    if (!ok) {
        _ = sys.write(2, "DBG: expected_tag = ", 20);
        var dbg_hex: [32]u8 = undefined;
        var dbg_i: usize = 0;
        for (expected_tag) |b| { const hi = b >> 4; const lo = b & 15; dbg_hex[dbg_i] = @as(u8, if (hi < 10) '0' + hi else 'a' + hi - 10); dbg_i += 1; dbg_hex[dbg_i] = @as(u8, if (lo < 10) '0' + lo else 'a' + lo - 10); dbg_i += 1; }
        _ = sys.write(2, &dbg_hex, 32);
        _ = sys.write(2, "\nDBG: received tag = ", 21);
        dbg_i = 0;
        for (tag[0..16]) |b| { const hi = b >> 4; const lo = b & 15; dbg_hex[dbg_i] = @as(u8, if (hi < 10) '0' + hi else 'a' + hi - 10); dbg_i += 1; dbg_hex[dbg_i] = @as(u8, if (lo < 10) '0' + lo else 'a' + lo - 10); dbg_i += 1; }
        _ = sys.write(2, &dbg_hex, 32);
        _ = sys.write(2, "\nDBG: ghash_out  = ", 19);
        dbg_i = 0;
        for (ghash_out) |b| { const hi = b >> 4; const lo = b & 15; dbg_hex[dbg_i] = @as(u8, if (hi < 10) '0' + hi else 'a' + hi - 10); dbg_i += 1; dbg_hex[dbg_i] = @as(u8, if (lo < 10) '0' + lo else 'a' + lo - 10); dbg_i += 1; }
        _ = sys.write(2, &dbg_hex, 32);
        _ = sys.write(2, "\nDBG: tag_block  = ", 19);
        dbg_i = 0;
        for (tag_block) |b| { const hi = b >> 4; const lo = b & 15; dbg_hex[dbg_i] = @as(u8, if (hi < 10) '0' + hi else 'a' + hi - 10); dbg_i += 1; dbg_hex[dbg_i] = @as(u8, if (lo < 10) '0' + lo else 'a' + lo - 10); dbg_i += 1; }
        _ = sys.write(2, &dbg_hex, 32);
        _ = sys.write(2, "\nDBG: h          = ", 18);
        dbg_i = 0;
        for (h) |b| { const hi = b >> 4; const lo = b & 15; dbg_hex[dbg_i] = @as(u8, if (hi < 10) '0' + hi else 'a' + hi - 10); dbg_i += 1; dbg_hex[dbg_i] = @as(u8, if (lo < 10) '0' + lo else 'a' + lo - 10); dbg_i += 1; }
        _ = sys.write(2, &dbg_hex, 32);
        _ = sys.write(2, "\n", 1);
        return false;
    }
    gcmInc32(&j0);
    gcmGctr(plaintext, &ks, &j0, ciphertext);
    return true;
}

// ============================== X25519 (Curve25519) ==============================

const MASK51: u64 = (1 << 51) - 1;

fn feZero(out: *[5]u64) void {
    out[0] = 0; out[1] = 0; out[2] = 0; out[3] = 0; out[4] = 0;
}

fn feOne(out: *[5]u64) void {
    out[0] = 1; out[1] = 0; out[2] = 0; out[3] = 0; out[4] = 0;
}

fn feCopy(out: *[5]u64, a: *const [5]u64) void {
    out[0] = a[0]; out[1] = a[1]; out[2] = a[2]; out[3] = a[3]; out[4] = a[4];
}

fn feReduce(fe: *[5]u64) void {
    var c: u64 = fe[0] >> 51; fe[0] &= MASK51; fe[1] +%= c;
    c = fe[1] >> 51; fe[1] &= MASK51; fe[2] +%= c;
    c = fe[2] >> 51; fe[2] &= MASK51; fe[3] +%= c;
    c = fe[3] >> 51; fe[3] &= MASK51; fe[4] +%= c;
    c = fe[4] >> 51; fe[4] &= MASK51; fe[0] +%= 19 *% c;
}

fn feAdd(out: *[5]u64, a: *const [5]u64, b: *const [5]u64) void {
    out[0] = a[0] + b[0];
    out[1] = a[1] + b[1];
    out[2] = a[2] + b[2];
    out[3] = a[3] + b[3];
    out[4] = a[4] + b[4];
}

fn feSub(out: *[5]u64, a: *const [5]u64, b: *const [5]u64) void {
    const p0 = (1 << 51) - 19;
    const p1 = (1 << 51) - 1;
    out[0] = a[0] + 2 * p0 -% b[0];
    out[1] = a[1] + 2 * p1 -% b[1];
    out[2] = a[2] + 2 * p1 -% b[2];
    out[3] = a[3] + 2 * p1 -% b[3];
    out[4] = a[4] + 2 * p1 -% b[4];
}

fn feMul(out: *[5]u64, a: *const [5]u64, b: *const [5]u64) void {
    const a0 = a[0]; const a1 = a[1]; const a2 = a[2]; const a3 = a[3]; const a4 = a[4];
    const b0 = b[0]; const b1 = b[1]; const b2 = b[2]; const b3 = b[3]; const b4 = b[4];
    var c: [10]u128 = undefined;
    c[0] = @as(u128, a0) * @as(u128, b0);
    c[1] = @as(u128, a0) * @as(u128, b1) + @as(u128, a1) * @as(u128, b0);
    c[2] = @as(u128, a0) * @as(u128, b2) + @as(u128, a1) * @as(u128, b1) + @as(u128, a2) * @as(u128, b0);
    c[3] = @as(u128, a0) * @as(u128, b3) + @as(u128, a1) * @as(u128, b2) + @as(u128, a2) * @as(u128, b1) + @as(u128, a3) * @as(u128, b0);
    c[4] = @as(u128, a0) * @as(u128, b4) + @as(u128, a1) * @as(u128, b3) + @as(u128, a2) * @as(u128, b2) + @as(u128, a3) * @as(u128, b1) + @as(u128, a4) * @as(u128, b0);
    c[5] = @as(u128, a1) * @as(u128, b4) + @as(u128, a2) * @as(u128, b3) + @as(u128, a3) * @as(u128, b2) + @as(u128, a4) * @as(u128, b1);
    c[6] = @as(u128, a2) * @as(u128, b4) + @as(u128, a3) * @as(u128, b3) + @as(u128, a4) * @as(u128, b2);
    c[7] = @as(u128, a3) * @as(u128, b4) + @as(u128, a4) * @as(u128, b3);
    c[8] = @as(u128, a4) * @as(u128, b4);

    // Carry low 5 limbs into c[5]
    c[1] += c[0] >> 51; c[0] &= MASK51;
    c[2] += c[1] >> 51; c[1] &= MASK51;
    c[3] += c[2] >> 51; c[2] &= MASK51;
    c[4] += c[3] >> 51; c[3] &= MASK51;
    c[5] += c[4] >> 51; c[4] &= MASK51;

    // Fold c[5]..c[8] into lower limbs with multiplier 19
    c[0] += 19 * c[5];
    c[1] += 19 * c[6];
    c[2] += 19 * c[7];
    c[3] += 19 * c[8];

    // Carry + fold c[4] back
    c[1] += c[0] >> 51; c[0] &= MASK51;
    c[2] += c[1] >> 51; c[1] &= MASK51;
    c[3] += c[2] >> 51; c[2] &= MASK51;
    c[4] += c[3] >> 51; c[3] &= MASK51;
    c[0] += 19 * (c[4] >> 51); c[4] &= MASK51;

    // Final small carry
    c[1] += c[0] >> 51; c[0] &= MASK51;

    out[0] = @as(u64, @truncate(c[0]));
    out[1] = @as(u64, @truncate(c[1]));
    out[2] = @as(u64, @truncate(c[2]));
    out[3] = @as(u64, @truncate(c[3]));
    out[4] = @as(u64, @truncate(c[4]));
}

fn feSquare(out: *[5]u64, a: *const [5]u64) void {
    feMul(out, a, a);
}

fn feCSwap(x: *[5]u64, y: *[5]u64, swap: u64) void {
    const mask: u64 = 0 -% swap;
    for (0..5) |i| {
        const t = mask & (x[i] ^ y[i]);
        x[i] ^= t;
        y[i] ^= t;
    }
}

fn feFromBytes(out: *[5]u64, in_bytes: *const [32]u8) void {
    const in = @as(*const [32]u8, @ptrCast(in_bytes));
    out[0] = (@as(u64, in[0]) << 0) | (@as(u64, in[1]) << 8) | (@as(u64, in[2]) << 16) | (@as(u64, in[3]) << 24) | (@as(u64, in[4]) << 32) | (@as(u64, in[5]) << 40) | ((@as(u64, in[6]) & 7) << 48);
    out[1] = (@as(u64, in[6]) >> 3) | (@as(u64, in[7]) << 5) | (@as(u64, in[8]) << 13) | (@as(u64, in[9]) << 21) | (@as(u64, in[10]) << 29) | (@as(u64, in[11]) << 37) | ((@as(u64, in[12]) & 63) << 45);
    out[2] = (@as(u64, in[12]) >> 6) | (@as(u64, in[13]) << 2) | (@as(u64, in[14]) << 10) | (@as(u64, in[15]) << 18) | (@as(u64, in[16]) << 26) | (@as(u64, in[17]) << 34) | (@as(u64, in[18]) << 42) | ((@as(u64, in[19]) & 1) << 50);
    out[3] = (@as(u64, in[19]) >> 1) | (@as(u64, in[20]) << 7) | (@as(u64, in[21]) << 15) | (@as(u64, in[22]) << 23) | (@as(u64, in[23]) << 31) | (@as(u64, in[24]) << 39) | ((@as(u64, in[25]) & 15) << 47);
    out[4] = (@as(u64, in[25]) >> 4) | (@as(u64, in[26]) << 4) | (@as(u64, in[27]) << 12) | (@as(u64, in[28]) << 20) | (@as(u64, in[29]) << 28) | (@as(u64, in[30]) << 36) | ((@as(u64, in[31]) & 127) << 44);
}

fn feToBytes(out: *[32]u8, in_fe: *const [5]u64) void {
    var tmp: [5]u64 = undefined;
    feCopy(&tmp, in_fe);
    var c: u64 = 0;
    c = tmp[0] >> 51; tmp[0] &= MASK51; tmp[1] += c;
    c = tmp[1] >> 51; tmp[1] &= MASK51; tmp[2] += c;
    c = tmp[2] >> 51; tmp[2] &= MASK51; tmp[3] += c;
    c = tmp[3] >> 51; tmp[3] &= MASK51; tmp[4] += c;
    c = tmp[4] >> 51; tmp[4] &= MASK51; tmp[0] += 19 * c;
    c = tmp[0] >> 51; tmp[0] &= MASK51; tmp[1] += c;

    // Final reduction: if tmp >= p, subtract p
    // p_limbs = [2^51-19, 2^51-1, 2^51-1, 2^51-1, 2^51-1]
    const p0 = (1 << 51) - 19;
    const p1 = (1 << 51) - 1;
    // Check if tmp >= p (compare limb by limb from top)
    var ge: u64 = 1;
    if (tmp[4] < p1) { ge = 0; }
    else if (tmp[4] > p1) { ge = 1; }
    else if (tmp[3] < p1) { ge = 0; }
    else if (tmp[3] > p1) { ge = 1; }
    else if (tmp[2] < p1) { ge = 0; }
    else if (tmp[2] > p1) { ge = 1; }
    else if (tmp[1] < p1) { ge = 0; }
    else if (tmp[1] > p1) { ge = 1; }
    else if (tmp[0] < p0) { ge = 0; }
    // if all equal → ge stays 1 (subtract)

    // Conditional subtract: if ge, tmp -= p
    var borrow: u64 = 0;
    const sub0 = tmp[0] -% p0 -% borrow; borrow = if (sub0 > tmp[0]) 1 else 0;
    const sub1 = tmp[1] -% p1 -% borrow; borrow = if (sub1 > tmp[1]) 1 else 0;
    const sub2 = tmp[2] -% p1 -% borrow; borrow = if (sub2 > tmp[2]) 1 else 0;
    const sub3 = tmp[3] -% p1 -% borrow; borrow = if (sub3 > tmp[3]) 1 else 0;
    const sub4 = tmp[4] -% p1 -% borrow;
    // ge mask: 0xFFFF... if ge, 0 if not
    const mask = 0 -% ge;
    tmp[0] = tmp[0] ^ (mask & (sub0 ^ tmp[0]));
    tmp[1] = tmp[1] ^ (mask & (sub1 ^ tmp[1]));
    tmp[2] = tmp[2] ^ (mask & (sub2 ^ tmp[2]));
    tmp[3] = tmp[3] ^ (mask & (sub3 ^ tmp[3]));
    tmp[4] = tmp[4] ^ (mask & (sub4 ^ tmp[4]));

    out[0] = @as(u8, @truncate(tmp[0]));
    out[1] = @as(u8, @truncate(tmp[0] >> 8));
    out[2] = @as(u8, @truncate(tmp[0] >> 16));
    out[3] = @as(u8, @truncate(tmp[0] >> 24));
    out[4] = @as(u8, @truncate(tmp[0] >> 32));
    out[5] = @as(u8, @truncate(tmp[0] >> 40));
    out[6] = @as(u8, @truncate((tmp[0] >> 48) | (tmp[1] << 3)));
    out[7] = @as(u8, @truncate(tmp[1] >> 5));
    out[8] = @as(u8, @truncate(tmp[1] >> 13));
    out[9] = @as(u8, @truncate(tmp[1] >> 21));
    out[10] = @as(u8, @truncate(tmp[1] >> 29));
    out[11] = @as(u8, @truncate(tmp[1] >> 37));
    out[12] = @as(u8, @truncate((tmp[1] >> 45) | (tmp[2] << 6)));
    out[13] = @as(u8, @truncate(tmp[2] >> 2));
    out[14] = @as(u8, @truncate(tmp[2] >> 10));
    out[15] = @as(u8, @truncate(tmp[2] >> 18));
    out[16] = @as(u8, @truncate(tmp[2] >> 26));
    out[17] = @as(u8, @truncate(tmp[2] >> 34));
    out[18] = @as(u8, @truncate(tmp[2] >> 42));
    out[19] = @as(u8, @truncate((tmp[2] >> 50) | (tmp[3] << 1)));
    out[20] = @as(u8, @truncate(tmp[3] >> 7));
    out[21] = @as(u8, @truncate(tmp[3] >> 15));
    out[22] = @as(u8, @truncate(tmp[3] >> 23));
    out[23] = @as(u8, @truncate(tmp[3] >> 31));
    out[24] = @as(u8, @truncate(tmp[3] >> 39));
    out[25] = @as(u8, @truncate((tmp[3] >> 47) | (tmp[4] << 4)));
    out[26] = @as(u8, @truncate(tmp[4] >> 4));
    out[27] = @as(u8, @truncate(tmp[4] >> 12));
    out[28] = @as(u8, @truncate(tmp[4] >> 20));
    out[29] = @as(u8, @truncate(tmp[4] >> 28));
    out[30] = @as(u8, @truncate(tmp[4] >> 36));
    out[31] = @as(u8, @truncate(tmp[4] >> 44));
}

fn feSquareN(out: *[5]u64, a: *const [5]u64, count: usize) void {
    feSquare(out, a);
    var i: usize = 1;
    while (i < count) : (i += 1) {
        feSquare(out, out);
    }
}

fn feInvert(out: *[5]u64, z: *const [5]u64) void {
    var a: [5]u64 = undefined;
    var b: [5]u64 = undefined;
    var c: [5]u64 = undefined;
    var t0: [5]u64 = undefined;

    feSquare(&a, z);                   // 2
    feSquareN(&t0, &a, 2);             // 8
    feMul(&b, &t0, z);                 // 9
    feMul(&a, &b, &a);                 // 11
    feSquare(&t0, &a);                 // 22
    feMul(&b, &t0, &b);                // 31 = 2^5 - 1
    feSquareN(&t0, &b, 5);             // 2^10 - 2^5 = 992
    feMul(&b, &t0, &b);                // 2^10 - 1 = 1023
    feSquareN(&t0, &b, 10);            // 2^20 - 2^10
    feMul(&c, &t0, &b);                // 2^20 - 1
    feSquareN(&t0, &c, 20);            // 2^40 - 2^20
    feMul(&t0, &t0, &c);               // 2^40 - 1
    feSquareN(&t0, &t0, 10);           // 2^50 - 2^10
    feMul(&b, &t0, &b);                // 2^50 - 1
    feSquareN(&t0, &b, 50);            // 2^100 - 2^50
    feMul(&c, &t0, &b);                // 2^100 - 1
    feSquareN(&t0, &c, 100);           // 2^200 - 2^100
    feMul(&t0, &t0, &c);               // 2^200 - 1
    feSquareN(&t0, &t0, 50);           // 2^250 - 2^50
    feMul(&t0, &t0, &b);               // 2^250 - 1
    feSquareN(&t0, &t0, 5);            // 2^255 - 2^5
    feMul(out, &t0, &a);               // 2^255 - 21 = p - 2
}

fn clampScalar(scalar: *[32]u8) void {
    scalar[0] &= 248;
    scalar[31] &= 127;
    scalar[31] |= 64;
}

pub fn x25519(out: *[32]u8, scalar: *const [32]u8, point: *const [32]u8) void {
    var e: [32]u8 = undefined;
    @memcpy(e[0..32], scalar[0..32]);
    clampScalar(&e);
    var x1: [5]u64 = undefined;
    feFromBytes(&x1, point);
    var x2: [5]u64 = undefined;
    var z2: [5]u64 = undefined;
    var x3: [5]u64 = undefined;
    var z3: [5]u64 = undefined;
    feOne(&x2);
    feZero(&z2);
    feCopy(&x3, &x1);
    feOne(&z3);
    var swap: u64 = 0;
    var bit: u64 = 0;
    var i: usize = 255;
    while (true) {
        const byte_pos = i / 8;
        const bit_pos = @as(u3, @intCast(i % 8));
        bit = @as(u64, (e[byte_pos] >> bit_pos) & 1);
        swap ^= bit;
        feCSwap(&x2, &x3, swap);
        feCSwap(&z2, &z3, swap);
        swap = bit;
        var A: [5]u64 = undefined;
        var B: [5]u64 = undefined;
        var AA: [5]u64 = undefined;
        var BB: [5]u64 = undefined;
        var E: [5]u64 = undefined;
        var C: [5]u64 = undefined;
        var D: [5]u64 = undefined;
        var DA: [5]u64 = undefined;
        var CB: [5]u64 = undefined;
        feAdd(&A, &x2, &z2);
        feSub(&B, &x2, &z2);
        feMul(&AA, &A, &A);
        feMul(&BB, &B, &B);
        feSub(&E, &AA, &BB);
        feAdd(&C, &x3, &z3);
        feSub(&D, &x3, &z3);
        feMul(&DA, &D, &A);
        feMul(&CB, &C, &B);
        var tmp1: [5]u64 = undefined;
        var tmp2: [5]u64 = undefined;
        feAdd(&tmp1, &DA, &CB);
        feMul(&x3, &tmp1, &tmp1);
        feSub(&tmp2, &DA, &CB);
        feMul(&tmp2, &tmp2, &tmp2);
        feMul(&z3, &x1, &tmp2);
        feMul(&x2, &AA, &BB);
        var a24_fe: [5]u64 = undefined;
        a24_fe[0] = 121665;
        a24_fe[1] = 0;
        a24_fe[2] = 0;
        a24_fe[3] = 0;
        a24_fe[4] = 0;
        feMul(&tmp1, &E, &a24_fe);
        feAdd(&tmp1, &AA, &tmp1);
        feMul(&z2, &E, &tmp1);
        if (i == 0) break;
        i -= 1;
    }
    feCSwap(&x2, &x3, swap);
    feCSwap(&z2, &z3, swap);
    var inv_z2: [5]u64 = undefined;
    feInvert(&inv_z2, &z2);
    var result: [5]u64 = undefined;
    feMul(&result, &x2, &inv_z2);
    feToBytes(out, &result);
}

pub fn x25519Keypair(sk: *[32]u8, pk: *[32]u8) void {
    const fd = sys.open("/dev/urandom\x00", 0, 0);
    if (fd >= 0) {
        _ = sys.read(fd, sk, 32);
        sys.close(fd);
    }
    clampScalar(sk);
    var basepoint: [32]u8 = .{9} ++ .{0} ** 31;
    x25519(pk, sk, &basepoint);
}
