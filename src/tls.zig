const crypto = @import("crypto.zig");
const sys = @import("sys.zig");

pub var tls_response_data: [65536]u8 = undefined;
pub var tls_response_len: usize = 0;

const CT_CHANGE_CIPHER_SPEC = 20;
const CT_ALERT = 21;
const CT_HANDSHAKE = 22;
const CT_APPLICATION_DATA = 23;

const HS_CLIENT_HELLO = 1;
const HS_SERVER_HELLO = 2;
const HS_ENCRYPTED_EXTENSIONS = 8;
const HS_CERTIFICATE = 11;
const HS_CERTIFICATE_VERIFY = 15;
const HS_FINISHED = 20;

const AEAD_KEY_LEN = 16;
const AEAD_IV_LEN = 12;
const AEAD_TAG_LEN = 16;

const TlsCipherState = struct {
    key: [AEAD_KEY_LEN]u8 = [_]u8{0} ** AEAD_KEY_LEN,
    iv: [AEAD_IV_LEN]u8 = [_]u8{0} ** AEAD_IV_LEN,
    seq_num: u64 = 0,
};

pub const TlsConnection = struct {
    fd: i32,
    server_hs: TlsCipherState = TlsCipherState{},
    client_hs: TlsCipherState = TlsCipherState{},
    server_ap: TlsCipherState = TlsCipherState{},
    client_ap: TlsCipherState = TlsCipherState{},
    transcript: [4096]u8 = undefined,
    transcript_len: usize = 0,
    hello_hash: [32]u8 = undefined,
    server_pk: [32]u8 = undefined,

    pub fn connect(host: []const u8, port: u16, out_response: *Response) bool {
        _ = sys.socketInit();
        var ip: u32 = 0;
        {
            var octets: [4]u8 = undefined;
            var oi: usize = 0;
            var hi: usize = 0;
            while (oi < 4 and hi < host.len) : (oi += 1) {
                var val: u32 = 0;
                while (hi < host.len and host[hi] >= '0' and host[hi] <= '9') : (hi += 1) val = val * 10 + (host[hi] - '0');
                octets[oi] = @as(u8, @intCast(val));
                if (oi < 3 and hi < host.len and host[hi] == '.') hi += 1;
            }
            if (oi == 4 and hi == host.len) {
                ip = @as(u32, octets[0]) | (@as(u32, octets[1]) << 8) | (@as(u32, octets[2]) << 16) | (@as(u32, octets[3]) << 24);
            } else {
                var host_buf: [256]u8 = undefined;
                var hc: usize = 0;
                while (hc < host.len and hc < 255) : (hc += 1) host_buf[hc] = host[hc];
                host_buf[hc] = 0;
                ip = sys.resolveHostname(host_buf[0..hc]);
                if (ip == 0) return false;
            }
        }

        const fd = sys.socket(sys.AF_INET, sys.SOCK_STREAM, 0);
        if (fd < 0) return false;

        var addr: sys.SockAddrIn = undefined;
        addr.family = @as(u16, @intCast(sys.AF_INET));
        addr.port = sys.htons(port);
        addr.addr = ip;
        addr.zero = [_]u8{0} ** 8;

        if (sys.connect(fd, @as([*]const u8, @ptrCast(&addr)), @sizeOf(sys.SockAddrIn)) < 0) {
            _ = sys.closeSocket(fd);
            return false;
        }

        var self = TlsConnection{ .fd = fd };
        if (!self.doHandshake(host)) {
            _ = sys.closeSocket(fd);
            return false;
        }

        var req_buf: [4096]u8 = undefined;
        var rp: usize = 0;
        const method = "GET";
        const path = out_response.path;
        const body = out_response.body;
        for (method) |c| { if (rp < 4086) { req_buf[rp] = c; rp += 1; } }
        req_buf[rp] = ' '; rp += 1;
        var pi: usize = 0;
        while (pi < path.len and rp < 4086) : (pi += 1) { req_buf[rp] = path[pi]; rp += 1; }
        req_buf[rp] = ' '; rp += 1;
        const ver = "HTTP/1.0\r\n";
        for (ver) |c| { if (rp < 4086) { req_buf[rp] = c; rp += 1; } }
        const hdr = "Host: ";
        for (hdr) |c| { if (rp < 4086) { req_buf[rp] = c; rp += 1; } }
        for (host) |c| { if (rp < 4086) { req_buf[rp] = c; rp += 1; } }
        req_buf[rp] = '\r'; rp += 1; req_buf[rp] = '\n'; rp += 1;
        if (body.len > 0) {
            const cl = "Content-Length: ";
            for (cl) |c| { if (rp < 4086) { req_buf[rp] = c; rp += 1; } }
            var tmp = body.len;
            var digits: [16]u8 = undefined;
            var dc: usize = 0;
            while (tmp > 0) { digits[dc] = @as(u8, @intCast('0' + (tmp % 10))); tmp /= 10; dc += 1; }
            var di = dc;
            while (di > 0) { di -= 1; if (rp < 4086) { req_buf[rp] = digits[di]; rp += 1; } }
            req_buf[rp] = '\r'; rp += 1; req_buf[rp] = '\n'; rp += 1;
            const ct = "Content-Type: application/x-www-form-urlencoded\r\n";
            for (ct) |c| { if (rp < 4086) { req_buf[rp] = c; rp += 1; } }
        }
        req_buf[rp] = '\r'; rp += 1; req_buf[rp] = '\n'; rp += 1;
        for (body) |c| { if (rp < 4086) { req_buf[rp] = c; rp += 1; } }

        _ = sys.write(2, "DBG: about to send HTTP\n", 24);
        if (!self.sendAppData(req_buf[0..rp])) {
            _ = sys.write(2, "DBG: send HTTP failed\n", 22);
            return false;
        }
        _ = sys.write(2, "DBG: sent HTTP OK\n", 18);

        // Read response
        var resp: [65536]u8 = undefined;
        var total: usize = 0;
        while (total < resp.len) {
            const n = self.recvAppData(resp[total..]);
            if (n <= 0) break;
            total += @as(usize, @intCast(n));
        }

        out_response.data_len = total;
        if (total > 0) {
            @memcpy(out_response.data[0..total], resp[0..total]);
        }
        _ = sys.closeSocket(fd);
        return true;
    }

    fn appendTranscript(self: *TlsConnection, msg: []const u8) void {
        if (self.transcript_len + msg.len <= self.transcript.len) {
            @memcpy(self.transcript[self.transcript_len..][0..msg.len], msg);
            self.transcript_len += msg.len;
        }
    }

    fn doHandshake(self: *TlsConnection, host: []const u8) bool {
        // 1. Generate X25519 keypair
        var sk: [32]u8 = undefined;
        crypto.x25519Keypair(&sk, &self.server_pk);
        // Keep server_pk as our client's public key (we reuse the field)

        // 2. Build and send ClientHello
        var hello_buf: [512]u8 = undefined;
        var hp: usize = 0;
        // legacy_version
        hello_buf[hp] = 0x03; hp += 1; hello_buf[hp] = 0x03; hp += 1;
        // random (32 bytes)
        var random: [32]u8 = undefined;
        const fd = sys.open("/dev/urandom\x00", 0, 0);
        if (fd >= 0) {
            _ = sys.read(fd, &random, 32);
            sys.close(fd);
        }
        @memcpy(hello_buf[hp..][0..32], &random);
        hp += 32;
        // legacy_session_id (empty)
        hello_buf[hp] = 0; hp += 1;
        // cipher_suites
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x02; hp += 1; // length = 2
        hello_buf[hp] = 0x13; hp += 1; hello_buf[hp] = 0x01; hp += 1; // TLS_AES_128_GCM_SHA256
        // legacy_compression_methods
        hello_buf[hp] = 0x01; hp += 1; // length = 1
        hello_buf[hp] = 0x00; hp += 1; // null compression

        // Extensions
        const ext_start = hp;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x00; hp += 1; // placeholder for ext length

        // supported_versions (0x002b)
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x2b; hp += 1;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x03; hp += 1; // length = 3
        hello_buf[hp] = 0x02; hp += 1; // version list length = 2
        hello_buf[hp] = 0x03; hp += 1; hello_buf[hp] = 0x04; hp += 1; // TLS 1.3

        // supported_groups (0x000a)
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x0a; hp += 1;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x04; hp += 1; // length = 4
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x02; hp += 1; // list length = 2
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x1d; hp += 1; // x25519

        // signature_algorithms (0x000d)
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x0d; hp += 1;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x08; hp += 1; // length = 8
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x06; hp += 1; // list length = 6
        hello_buf[hp] = 0x08; hp += 1; hello_buf[hp] = 0x04; hp += 1; // rsa_pss_rsae_sha256
        hello_buf[hp] = 0x08; hp += 1; hello_buf[hp] = 0x05; hp += 1; // rsa_pss_rsae_sha384
        hello_buf[hp] = 0x08; hp += 1; hello_buf[hp] = 0x06; hp += 1; // rsa_pss_rsae_sha512

        // key_share (0x0033)
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x33; hp += 1;
        const ks_ext_len_pos = hp;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x00; hp += 1; // placeholder for ext body length
        // client_shares list length
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x00; hp += 1; // placeholder for list length
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x1d; hp += 1; // x25519 group
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x20; hp += 1; // key length = 32
        @memcpy(hello_buf[hp..][0..32], &self.server_pk);
        {
            _ = sys.write(2, "DBG: CLIENT_PK = ", 17);
            var hexbuf2: [64]u8 = undefined;
            var hx2: usize = 0;
            for (self.server_pk) |b| { const hi = b >> 4; const lo = b & 15; hexbuf2[hx2] = @as(u8, if (hi < 10) '0' + hi else 'a' + hi - 10); hx2 += 1; hexbuf2[hx2] = @as(u8, if (lo < 10) '0' + lo else 'a' + lo - 10); hx2 += 1; }
            _ = sys.write(2, &hexbuf2, hx2);
            _ = sys.write(2, "\n", 1);
        }
        hp += 32;
        const ks_list_len: u16 = @as(u16, @intCast(2 + 2 + 32)); // group + key_len + key
        hello_buf[ks_ext_len_pos + 2] = @as(u8, @intCast(ks_list_len >> 8));
        hello_buf[ks_ext_len_pos + 3] = @as(u8, @intCast(ks_list_len));
        const ks_ext_len: u16 = @as(u16, @intCast(2 + 2 + 2 + 32)); // list_len + group + key_len + key
        hello_buf[ks_ext_len_pos] = @as(u8, @intCast(ks_ext_len >> 8));
        hello_buf[ks_ext_len_pos + 1] = @as(u8, @intCast(ks_ext_len));

        // server_name (0x0000)
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x00; hp += 1;
        const sni_ext_len_pos = hp;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x00; hp += 1; // placeholder for ext body length
        // ServerNameList length
        const sni_list_len_pos = hp;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x00; hp += 1; // placeholder for list length
        hello_buf[hp] = 0x00; hp += 1; // server name type = host_name
        const sni_len_pos = hp;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x00; hp += 1; // placeholder for name length
        var sni_i: usize = 0;
        while (sni_i < host.len and hp < 500) : (sni_i += 1) {
            hello_buf[hp] = host[sni_i]; hp += 1;
        }
        const name_len: u16 = @as(u16, @intCast(host.len));
        hello_buf[sni_len_pos] = @as(u8, @intCast(name_len >> 8));
        hello_buf[sni_len_pos + 1] = @as(u8, @intCast(name_len));
        const sni_list_body_len: u16 = @as(u16, @intCast(3 + host.len)); // type(1) + length(2) + name
        hello_buf[sni_list_len_pos] = @as(u8, @intCast(sni_list_body_len >> 8));
        hello_buf[sni_list_len_pos + 1] = @as(u8, @intCast(sni_list_body_len));
        const sni_ext_body_len: u16 = @as(u16, @intCast(2 + 3 + host.len)); // list_len(2) + type(1) + length(2) + name
        hello_buf[sni_ext_len_pos] = @as(u8, @intCast(sni_ext_body_len >> 8));
        hello_buf[sni_ext_len_pos + 1] = @as(u8, @intCast(sni_ext_body_len));

        const ext_len: u16 = @as(u16, @intCast(hp - ext_start - 2));
        hello_buf[ext_start] = @as(u8, @intCast(ext_len >> 8));
        hello_buf[ext_start + 1] = @as(u8, @intCast(ext_len));

        // Construct handshake message
        var msg_buf: [512]u8 = undefined;
        var mp: usize = 0;
        msg_buf[mp] = HS_CLIENT_HELLO; mp += 1;
        msg_buf[mp] = 0x00; mp += 1; msg_buf[mp] = 0x00; mp += 1; msg_buf[mp] = @as(u8, @intCast(hp)); mp += 1;
        @memcpy(msg_buf[mp..][0..hp], hello_buf[0..hp]);
        mp += hp;

        // Send plaintext handshake record
        {
            _ = sys.write(2, "DBG: CH body: ", 14);
            var ci: usize = 0;
            while (ci < mp) : (ci += 1) { const b = msg_buf[ci]; var hex: [2]u8 = undefined; hex[0] = @as(u8, if (b>>4 < 10) '0' + (b>>4) else 'a' + (b>>4) - 10); hex[1] = @as(u8, if ((b&15) < 10) '0' + (b&15) else 'a' + ((b&15)) - 10); _ = sys.write(2, &hex, 2); }
            _ = sys.write(2, "\n", 1);
        }
        if (!self.writePlainRecord(CT_HANDSHAKE, msg_buf[0..mp])) return false;
        self.appendTranscript(msg_buf[0..mp]);

        // 3. Read ServerHello
        var sh_buf: [512]u8 = undefined;
        const sh_len = self.readPlainRecord(CT_HANDSHAKE, sh_buf[0..]) orelse {
            return false;
        };
        {
            _ = sys.write(2, "DBG: ServerHello raw: ", 22);
            var si: usize = 0;
            while (si < @min(sh_len, 128)) : (si += 1) { const b = sh_buf[si]; var hex: [2]u8 = undefined; hex[0] = @as(u8, if (b>>4 < 10) '0' + (b>>4) else 'a' + (b>>4) - 10); hex[1] = @as(u8, if ((b&15) < 10) '0' + (b&15) else 'a' + ((b&15)) - 10); _ = sys.write(2, &hex, 2); }
            _ = sys.write(2, "\n", 1);
        }
        var shp: usize = 0;
        // Skip handshake header (type + 3-byte length)
        if (sh_len < 4) return false;
        _ = sh_buf[shp]; shp += 1; // handshake type
        const sh_body_len = @as(usize, sh_buf[shp]) << 16 | @as(usize, sh_buf[shp + 1]) << 8 | @as(usize, sh_buf[shp + 2]);
        shp += 3;
        if (shp + sh_body_len > sh_len) return false;
        const sh_body = sh_buf[shp..][0..sh_body_len];
        var ssp: usize = 0;
        _ = sh_body[ssp]; ssp += 1; _ = sh_body[ssp]; ssp += 1; // version (0x0303)
        ssp += 32; // random
        _ = sh_body[ssp]; ssp += 1; // session_id length (likely 0)
        const sh_cs0 = sh_body[ssp]; ssp += 1; const sh_cs1 = sh_body[ssp]; ssp += 1;
        if (sh_cs0 != 0x13 or sh_cs1 != 0x01) return false; // check TLS_AES_128_GCM_SHA256
        _ = sh_body[ssp]; ssp += 1; // compression_method = 0
        // Parse extensions to find key_share
        const sh_ext_len = (@as(usize, sh_body[ssp]) << 8) | @as(usize, sh_body[ssp + 1]);
        ssp += 2;
        var found_key_share = false;
        const sh_ext_end = ssp + sh_ext_len;
        while (ssp + 4 <= sh_ext_end) {
            const ext_type = (@as(usize, sh_body[ssp]) << 8) | @as(usize, sh_body[ssp + 1]);
            ssp += 2;
            const ext_len_val = (@as(usize, sh_body[ssp]) << 8) | @as(usize, sh_body[ssp + 1]);
            ssp += 2;
            if (ext_type == 0x0033) { // key_share
                if (ext_len_val < 4) return false;
                _ = sh_body[ssp]; ssp += 1; _ = sh_body[ssp]; ssp += 1; // group (x25519 = 0x001d)
                const pk_len = (@as(usize, sh_body[ssp]) << 8) | @as(usize, sh_body[ssp + 1]);
                ssp += 2;
                if (pk_len != 32) return false;
                @memcpy(self.server_pk[0..32], sh_body[ssp..][0..32]);
                ssp += 32;
                found_key_share = true;
            } else {
                ssp += ext_len_val;
            }
        }
        if (!found_key_share) return false;
        self.appendTranscript(sh_buf[0..sh_len]);

        // 4. Compute handshake keys
        var hello_hash_buf: [4096]u8 = undefined;
        @memcpy(hello_hash_buf[0..self.transcript_len], self.transcript[0..self.transcript_len]);
        crypto.sha256(hello_hash_buf[0..self.transcript_len], &self.hello_hash);

        var dh_shared: [32]u8 = undefined;
        crypto.x25519(&dh_shared, &sk, &self.server_pk);

        _ = sys.write(2, "DBG: dh_shared = ", 17);
        {
            var hexbuf: [64]u8 = undefined;
            var hx: usize = 0;
            for (dh_shared) |b| { const hi = b >> 4; const lo = b & 15; hexbuf[hx] = @as(u8, if (hi < 10) '0' + hi else 'a' + hi - 10); hx += 1; hexbuf[hx] = @as(u8, if (lo < 10) '0' + lo else 'a' + lo - 10); hx += 1; }
            _ = sys.write(2, &hexbuf, hx);
        }
        _ = sys.write(2, "\n", 1);

        var empty_salt: [32]u8 = [_]u8{0} ** 32;
        var early_secret: [32]u8 = undefined;
        crypto.hkdfExtract(&empty_salt, &empty_salt, &early_secret);

        _ = sys.write(2, "DBG: early_secret = ", 20);
        {
            var hexbuf: [64]u8 = undefined;
            var hx: usize = 0;
            for (early_secret) |b| { const hi = b >> 4; const lo = b & 15; hexbuf[hx] = @as(u8, if (hi < 10) '0' + hi else 'a' + hi - 10); hx += 1; hexbuf[hx] = @as(u8, if (lo < 10) '0' + lo else 'a' + lo - 10); hx += 1; }
            _ = sys.write(2, &hexbuf, hx);
        }
        _ = sys.write(2, "\n", 1);

        var empty_hash: [32]u8 = undefined;
        crypto.sha256(&[_]u8{}, &empty_hash);

        _ = sys.write(2, "DBG: empty_hash = ", 18);
        {
            var hexbuf: [64]u8 = undefined;
            var hx: usize = 0;
            for (empty_hash) |b| { const hi = b >> 4; const lo = b & 15; hexbuf[hx] = @as(u8, if (hi < 10) '0' + hi else 'a' + hi - 10); hx += 1; hexbuf[hx] = @as(u8, if (lo < 10) '0' + lo else 'a' + lo - 10); hx += 1; }
            _ = sys.write(2, &hexbuf, hx);
        }
        _ = sys.write(2, "\n", 1);

        var derived_1: [32]u8 = undefined;
        crypto.deriveSecret(&early_secret, "derived", &empty_hash, &derived_1);

        _ = sys.write(2, "DBG: derived_1 = ", 17);
        {
            var hexbuf: [64]u8 = undefined;
            var hx: usize = 0;
            for (derived_1) |b| { const hi = b >> 4; const lo = b & 15; hexbuf[hx] = @as(u8, if (hi < 10) '0' + hi else 'a' + hi - 10); hx += 1; hexbuf[hx] = @as(u8, if (lo < 10) '0' + lo else 'a' + lo - 10); hx += 1; }
            _ = sys.write(2, &hexbuf, hx);
        }
        _ = sys.write(2, "\n", 1);

        var handshake_secret: [32]u8 = undefined;
        crypto.hkdfExtract(&derived_1, &dh_shared, &handshake_secret);

        var server_hs_traffic: [32]u8 = undefined;
        crypto.deriveSecret(&handshake_secret, "s hs traffic", &self.hello_hash, &server_hs_traffic);
        var client_hs_traffic: [32]u8 = undefined;
        crypto.deriveSecret(&handshake_secret, "c hs traffic", &self.hello_hash, &client_hs_traffic);

        _ = sys.write(2, "DBG: hello_hash = ", 18);
        {
            var hexbuf: [64]u8 = undefined;
            var hx: usize = 0;
            for (self.hello_hash) |b| { const hi = b >> 4; const lo = b & 15; hexbuf[hx] = @as(u8, if (hi < 10) '0' + hi else 'a' + hi - 10); hx += 1; hexbuf[hx] = @as(u8, if (lo < 10) '0' + lo else 'a' + lo - 10); hx += 1; }
            _ = sys.write(2, &hexbuf, hx);
        }
        _ = sys.write(2, "\n", 1);

        crypto.hkdfExpandLabel(&server_hs_traffic, "key", "", self.server_hs.key[0..]);
        crypto.hkdfExpandLabel(&server_hs_traffic, "iv", "", self.server_hs.iv[0..]);
        self.server_hs.seq_num = 0;

        crypto.hkdfExpandLabel(&client_hs_traffic, "key", "", self.client_hs.key[0..]);
        crypto.hkdfExpandLabel(&client_hs_traffic, "iv", "", self.client_hs.iv[0..]);
        self.client_hs.seq_num = 0;

        _ = sys.write(2, "DBG: server_hs key = ", 21);
        {
            var hexbuf: [32]u8 = undefined;
            var hx: usize = 0;
            for (self.server_hs.key) |b| { const hi = b >> 4; const lo = b & 15; hexbuf[hx] = @as(u8, if (hi < 10) '0' + hi else 'a' + hi - 10); hx += 1; hexbuf[hx] = @as(u8, if (lo < 10) '0' + lo else 'a' + lo - 10); hx += 1; }
            _ = sys.write(2, &hexbuf, hx);
        }
        _ = sys.write(2, "\n", 1);
        _ = sys.write(2, "DBG: server_hs iv  = ", 21);
        {
            var hexbuf: [24]u8 = undefined;
            var hx: usize = 0;
            for (self.server_hs.iv) |b| { const hi = b >> 4; const lo = b & 15; hexbuf[hx] = @as(u8, if (hi < 10) '0' + hi else 'a' + hi - 10); hx += 1; hexbuf[hx] = @as(u8, if (lo < 10) '0' + lo else 'a' + lo - 10); hx += 1; }
            _ = sys.write(2, &hexbuf, hx);
        }
        _ = sys.write(2, "\n", 1);

        // 5. Read encrypted records (EncryptedExtensions, Certificate, CertificateVerify, Finished)
        // readEncryptedHs skips ChangeCipherSpec automatically

        _ = sys.write(2, "DBG: about to read EE\n", 22);

        var rec_buf: [16384]u8 = undefined;
        var rec_ct: u8 = undefined;
        var rec_len: usize = undefined;
        if (!self.readEncryptedHs(&rec_buf, &rec_ct, &rec_len)) {
            _ = sys.write(2, "DBG: readEncryptedHs failed\n", 29);
            return false;
        }
        _ = sys.write(2, "DBG: got encrypted hs record\n", 29);

        // Parse all handshake messages from the single decrypted record
        var offset: usize = 0;
        var got_ee = false;
        var got_cert = false;
        var got_cv = false;
        var got_finished = false;
        var cert_n: crypto.BigInt = undefined;
        var cert_e: crypto.BigInt = undefined;

        while (offset + 4 <= rec_len) {
            const hs_type = rec_buf[offset];
            const hs_len = (@as(usize, rec_buf[offset + 1]) << 16) |
                           (@as(usize, rec_buf[offset + 2]) << 8) |
                           @as(usize, rec_buf[offset + 3]);
            if (offset + 4 + hs_len > rec_len) return false;
            const hs_body = rec_buf[offset + 4 .. offset + 4 + hs_len];

            _ = sys.write(2, "DBG: hs_type=", 13);
            {
                var dbg_hs: [2]u8 = undefined;
                dbg_hs[0] = @as(u8, if (hs_type>>4 < 10) '0'+(hs_type>>4) else 'a'+(hs_type>>4)-10);
                dbg_hs[1] = @as(u8, if ((hs_type&15) < 10) '0'+(hs_type&15) else 'a'+(hs_type&15)-10);
                _ = sys.write(2, &dbg_hs, 2);
            }
            _ = sys.write(2, "\n", 1);

            switch (hs_type) {
                HS_ENCRYPTED_EXTENSIONS => {
                    got_ee = true;
                    self.appendTranscript(rec_buf[offset .. offset + 4 + hs_len]);
                },
                HS_CERTIFICATE => {
                    got_cert = true;
                    self.appendTranscript(rec_buf[offset .. offset + 4 + hs_len]);
                    if (!parseCertRSAPublicKey(hs_body, &cert_n, &cert_e)) {
                        _ = sys.write(2, "DBG: parseCert failed\n", 22);
                        return false;
                    }
                },
                HS_CERTIFICATE_VERIFY => {
                    got_cv = true;
                    // Compute transcript hash BEFORE appending CertificateVerify
                    var transcript_hash: [32]u8 = undefined;
                    crypto.sha256(self.transcript[0..self.transcript_len], &transcript_hash);
                    self.appendTranscript(rec_buf[offset .. offset + 4 + hs_len]);
                    _ = sys.write(2, "DBG: sig verify...\n", 20);
                    if (!verifyRsaPssSignature(rec_buf[offset .. offset + 4 + hs_len], cert_n, cert_e, &transcript_hash)) {
                        _ = sys.write(2, "DBG: sig verify failed\n", 23);
                        return false;
                    }
                    _ = sys.write(2, "DBG: sig verify OK\n", 19);
                },
                HS_FINISHED => {
                    got_finished = true;
                    var transcript_hash_fin: [32]u8 = undefined;
                    crypto.sha256(self.transcript[0..self.transcript_len], &transcript_hash_fin);
                    self.appendTranscript(rec_buf[offset .. offset + 4 + hs_len]);
                    var server_finished_key: [32]u8 = undefined;
                    crypto.hkdfExpandLabel(&server_hs_traffic, "finished", "", server_finished_key[0..]);
                    var expected_sf: [32]u8 = undefined;
                    crypto.hmacSha256(&server_finished_key, &transcript_hash_fin, &expected_sf);
                    if (hs_len < 32) {
                        _ = sys.write(2, "DBG: sf too short\n", 18);
                        return false;
                    }
                    for (0..32) |i| { if (hs_body[i] != expected_sf[i]) {
                        _ = sys.write(2, "DBG: sf mismatch\n", 17);
                        return false;
                    } }
                    _ = sys.write(2, "DBG: sf verify OK\n", 18);
                },
                else => {
                    _ = sys.write(2, "DBG: unknown hs type\n", 21);
                    return false;
                },
            }

            offset += 4 + hs_len;
        }

        if (!got_ee or !got_cert or !got_cv or !got_finished) {
            _ = sys.write(2, "DBG: missing hs msg\n", 20);
            return false;
        }

        // 6. Compute master secret and application keys
        var derived_2: [32]u8 = undefined;
        crypto.deriveSecret(&handshake_secret, "derived", &empty_hash, &derived_2);

        var master_secret: [32]u8 = undefined;
        crypto.hkdfExtract(&derived_2, &empty_salt, &master_secret);

        var all_hash: [32]u8 = undefined;
        crypto.sha256(self.transcript[0..self.transcript_len], &all_hash);

        var server_ap_traffic: [32]u8 = undefined;
        crypto.deriveSecret(&master_secret, "s ap traffic", &all_hash, &server_ap_traffic);
        var client_ap_traffic: [32]u8 = undefined;
        crypto.deriveSecret(&master_secret, "c ap traffic", &all_hash, &client_ap_traffic);

        crypto.hkdfExpandLabel(&server_ap_traffic, "key", "", self.server_ap.key[0..]);
        crypto.hkdfExpandLabel(&server_ap_traffic, "iv", "", self.server_ap.iv[0..]);
        self.server_ap.seq_num = 0;
        crypto.hkdfExpandLabel(&client_ap_traffic, "key", "", self.client_ap.key[0..]);
        crypto.hkdfExpandLabel(&client_ap_traffic, "iv", "", self.client_ap.iv[0..]);
        self.client_ap.seq_num = 0;

        // 7. Send Client Finished
        var client_finished_key: [32]u8 = undefined;
        crypto.hkdfExpandLabel(&client_hs_traffic, "finished", "", client_finished_key[0..]);
        var cf_transcript: [32]u8 = undefined;
        crypto.sha256(self.transcript[0..self.transcript_len], &cf_transcript);
        var cf_data: [32]u8 = undefined;
        crypto.hmacSha256(&client_finished_key, &cf_transcript, &cf_data);

        var cf_msg: [4 + 32]u8 = undefined;
        cf_msg[0] = HS_FINISHED;
        cf_msg[1] = 0x00; cf_msg[2] = 0x00; cf_msg[3] = 0x20;
        @memcpy(cf_msg[4..][0..32], &cf_data);
        _ = sys.write(2, "DBG: about to send CF\n", 22);
        if (!self.writeEncryptedRecord(&self.client_hs, cf_msg[0..])) {
            _ = sys.write(2, "DBG: send CF failed\n", 20);
            return false;
        }
        _ = sys.write(2, "DBG: sent CF OK\n", 16);

        return true;
    }

    fn writePlainRecord(self: *TlsConnection, content_type: u8, data: []const u8) bool {
        var header: [5]u8 = undefined;
        header[0] = content_type;
        header[1] = 0x03; header[2] = 0x03;
        header[3] = @as(u8, @intCast(data.len >> 8));
        header[4] = @as(u8, @intCast(data.len));
        if (!sys.sendAll(self.fd, &header, 5)) return false;
        if (!sys.sendAll(self.fd, data.ptr, data.len)) return false;
        return true;
    }

    fn readPlainRecord(self: *TlsConnection, expected_type: u8, buf: []u8) ?usize {
        var header: [5]u8 = .{0} ** 5;
        var off: usize = 0;
        while (off < 5) {
            const n = sys.recv(self.fd, @as([*]u8, &header) + off, 5 - off, 0);
            if (n <= 0) return null;
            off += @as(usize, @intCast(n));
        }
        if (header[0] != expected_type) {
            // Read alert body for diagnostics
            const alert_len = (@as(usize, header[3]) << 8) | @as(usize, header[4]);
            if (header[0] == CT_ALERT and alert_len >= 2) {
                var alert_buf: [2]u8 = undefined;
                _ = sys.recv(self.fd, @as([*]u8, &alert_buf), 2, 0);
                // alert_buf[0] = level (1=warning, 2=fatal)
                // alert_buf[1] = description
            }
            return null;
        }
        const len = (@as(usize, header[3]) << 8) | @as(usize, header[4]);
        if (len > buf.len) return null;
        off = 0;
        while (off < len) {
            const n = sys.recv(self.fd, buf.ptr + off, len - off, 0);
            if (n <= 0) return null;
            off += @as(usize, @intCast(n));
        }
        return len;
    }

    fn recvRecord(self: *TlsConnection, buf: []u8) usize {
        var header: [5]u8 = .{0} ** 5;
        var off: usize = 0;
        while (off < 5) {
            const n = sys.recv(self.fd, @as([*]u8, &header) + off, 5 - off, 0);
            if (n <= 0) return 0;
            off += @as(usize, @intCast(n));
        }
        const content_type = header[0];
        const len = (@as(usize, header[3]) << 8) | @as(usize, header[4]);
        if (len > buf.len) return 0;
        off = 0;
        while (off < len) {
            const n = sys.recv(self.fd, buf.ptr + off, len - off, 0);
            if (n <= 0) return 0;
            off += @as(usize, @intCast(n));
        }
        buf[0] = content_type;
        return 1 + len;
    }

    fn decryptRecord(state: *TlsCipherState, payload: []const u8, out: []u8) ?usize {
        if (payload.len < AEAD_TAG_LEN) return null;
        const ct_len = payload.len - AEAD_TAG_LEN;
        const ct = payload[0..ct_len];
        const tag = payload[ct_len..];
        var nonce: [12]u8 = undefined;
        @memcpy(nonce[0..12], state.iv[0..12]);
        var seq_be: [8]u8 = undefined;
        var seq = state.seq_num;
        var si: usize = 8;
        while (si > 0) {
            si -= 1;
            seq_be[si] = @as(u8, @truncate(seq));
            seq >>= 8;
        }
        for (0..8) |i| nonce[4 + i] ^= seq_be[i];
        state.seq_num +%= 1;
        var aad: [5]u8 = undefined;
        aad[0] = 23;
        aad[1] = 0x03; aad[2] = 0x03;
        const full_len: u16 = @as(u16, @intCast(payload.len));
        aad[3] = @as(u8, @intCast(full_len >> 8));
        aad[4] = @as(u8, @truncate(full_len));
        if (!crypto.gcmDecrypt(&state.key, &nonce, &aad, ct, @as(*const [16]u8, @ptrCast(tag.ptr)), out)) {
            _ = sys.write(2, "DBG: gcmDecrypt failed\n", 23);
            return null;
        }
        // Strip TLS 1.3 padding: trailing zeros || content_type
        var pt_len: usize = ct_len;
        while (pt_len > 0) {
            pt_len -= 1;
            if (out[pt_len] != 0) break;
        }
        if (pt_len == 0 and ct_len > 0) return null;
        return pt_len;
    }

    fn encryptRecord(state: *TlsCipherState, content_type: u8, data: []const u8, out: []u8) ?usize {
        // Inner plaintext: data || content_type
        var pt: [16384]u8 = undefined;
        @memcpy(pt[0..data.len], data);
        pt[data.len] = content_type;
        const pt_len = data.len + 1;

        var nonce: [12]u8 = undefined;
        @memcpy(nonce[0..12], state.iv[0..12]);
        var seq_be: [8]u8 = undefined;
        var seq = state.seq_num;
        var si: usize = 8;
        while (si > 0) {
            si -= 1;
            seq_be[si] = @as(u8, @truncate(seq));
            seq >>= 8;
        }
        for (0..8) |i| nonce[4 + i] ^= seq_be[i];
        state.seq_num +%= 1;
        var aad: [5]u8 = undefined;
        aad[0] = 23;
        aad[1] = 0x03; aad[2] = 0x03;
        const full_len: u16 = @as(u16, @intCast(pt_len + 16));
        aad[3] = @as(u8, @intCast(full_len >> 8));
        aad[4] = @as(u8, @truncate(full_len));
        var tag: [16]u8 = undefined;
        crypto.gcmEncrypt(&state.key, &nonce, &aad, pt[0..pt_len], out, &tag);
        @memcpy(out[pt_len..][0..16], &tag);
        return pt_len + 16;
    }

    fn readEncryptedHs(self: *TlsConnection, buf: []u8, content_type: *u8, out_len: *usize) bool {
        var header: [5]u8 = .{0} ** 5;
        var off: usize = 0;
        while (off < 5) {
            const n = sys.recv(self.fd, @as([*]u8, &header) + off, 5 - off, 0);
            if (n <= 0) { _ = sys.write(2, "DBG: header recv failed\n", 24); return false; }
            off += @as(usize, @intCast(n));
        }
        if (header[0] != CT_APPLICATION_DATA) {
            if (header[0] == CT_CHANGE_CIPHER_SPEC) {
                const ccs_len = (@as(usize, header[3]) << 8) | @as(usize, header[4]);
                var ccs_skip: [64]u8 = .{0} ** 64;
                off = 0;
                while (off < ccs_len) {
                    const n = sys.recv(self.fd, @as([*]u8, &ccs_skip) + off, ccs_len - off, 0);
                    if (n <= 0) return false;
                    off += @as(usize, @intCast(n));
                }
                return self.readEncryptedHs(buf, content_type, out_len);
            }
            _ = sys.write(2, "DBG: unexpected header type\n", 28);
            return false;
        }
        const ct_len = (@as(usize, header[3]) << 8) | @as(usize, header[4]);
        if (ct_len > 16384 + 16) { return false; }
        var ct_buf: [16384 + 16]u8 = .{0} ** (16384 + 16);
        off = 0;
        while (off < ct_len) {
            const n = sys.recv(self.fd, @as([*]u8, &ct_buf) + off, ct_len - off, 0);
            if (n <= 0) { return false; }
            off += @as(usize, @intCast(n));
        }
        {
            _ = sys.write(2, "DBG: ct_buf[0..32] = ", 21);
            var hexbuf: [64]u8 = undefined;
            var hx: usize = 0;
            var cti: usize = 0;
            while (cti < 32 and cti < ct_len) : (cti += 1) { const b = ct_buf[cti]; const hi = b >> 4; const lo = b & 15; hexbuf[hx] = @as(u8, if (hi < 10) '0' + hi else 'a' + hi - 10); hx += 1; hexbuf[hx] = @as(u8, if (lo < 10) '0' + lo else 'a' + lo - 10); hx += 1; }
            _ = sys.write(2, &hexbuf, hx);
            _ = sys.write(2, "\n", 1);
        }
        var plaintext: [16384]u8 = undefined;
        {
            var dbg_aad: [13]u8 = undefined;
            var dbg_seq_be: [8]u8 = undefined;
            var dbg_seq = self.server_hs.seq_num;
            var dsi: usize = 8;
            while (dsi > 0) { dsi -= 1; dbg_seq_be[dsi] = @as(u8, @truncate(dbg_seq)); dbg_seq >>= 8; }
            @memcpy(dbg_aad[0..8], &dbg_seq_be);
            dbg_aad[8] = 23;
            dbg_aad[9] = 0x03; dbg_aad[10] = 0x03;
            dbg_aad[11] = @as(u8, @intCast((ct_len - 16) >> 8));
            dbg_aad[12] = @as(u8, @truncate(ct_len - 16));
            _ = sys.write(2, "DBG: key = ", 11);
            for (self.server_hs.key) |b| { var hex: [2]u8 = undefined; hex[0] = @as(u8, if (b>>4 < 10) '0' + (b>>4) else 'a' + (b>>4) - 10); hex[1] = @as(u8, if ((b&15) < 10) '0' + (b&15) else 'a' + ((b&15)) - 10); _ = sys.write(2, &hex, 2); }
            _ = sys.write(2, "\nDBG: iv  = ", 12);
            for (self.server_hs.iv) |b| { var hex: [2]u8 = undefined; hex[0] = @as(u8, if (b>>4 < 10) '0' + (b>>4) else 'a' + (b>>4) - 10); hex[1] = @as(u8, if ((b&15) < 10) '0' + (b&15) else 'a' + ((b&15)) - 10); _ = sys.write(2, &hex, 2); }
            _ = sys.write(2, "\nDBG: aad = ", 12);
            for (dbg_aad) |b| { var hex: [2]u8 = undefined; hex[0] = @as(u8, if (b>>4 < 10) '0' + (b>>4) else 'a' + (b>>4) - 10); hex[1] = @as(u8, if ((b&15) < 10) '0' + (b&15) else 'a' + ((b&15)) - 10); _ = sys.write(2, &hex, 2); }
            _ = sys.write(2, "\nDBG: full ct = ", 16);
            var cti: usize = 0;
            while (cti < ct_len) : (cti += 1) { const b = ct_buf[cti]; var hex: [2]u8 = undefined; hex[0] = @as(u8, if (b>>4 < 10) '0' + (b>>4) else 'a' + (b>>4) - 10); hex[1] = @as(u8, if ((b&15) < 10) '0' + (b&15) else 'a' + ((b&15)) - 10); _ = sys.write(2, &hex, 2); }
            for (ct_buf[ct_len-16..][0..16]) |b| { var hex: [2]u8 = undefined; hex[0] = @as(u8, if (b>>4 < 10) '0' + (b>>4) else 'a' + (b>>4) - 10); hex[1] = @as(u8, if ((b&15) < 10) '0' + (b&15) else 'a' + ((b&15)) - 10); _ = sys.write(2, &hex, 2); }
            _ = sys.write(2, "\n", 1);
        }
        const pt_len = decryptRecord(&self.server_hs, ct_buf[0..ct_len], &plaintext) orelse {
            _ = sys.write(2, "DBG: decryptRecord failed\n", 26);
            return false;
        };
        _ = sys.write(2, "DBG: decrypted OK\n", 18);
        if (pt_len < 4) return false;
        content_type.* = plaintext[0];
        out_len.* = pt_len;
        @memcpy(buf[0..pt_len], plaintext[0..pt_len]);
        return true;
    }

    fn writeEncryptedRecord(self: *TlsConnection, state: *TlsCipherState, data: []const u8) bool {
        var encrypted: [16384]u8 = undefined;
        const encrypted_len = encryptRecord(state, CT_HANDSHAKE, data, &encrypted) orelse return false;
        var header: [5]u8 = undefined;
        header[0] = CT_APPLICATION_DATA;
        header[1] = 0x03; header[2] = 0x03;
        header[3] = @as(u8, @intCast(encrypted_len >> 8));
        header[4] = @as(u8, @intCast(encrypted_len));
        if (!sys.sendAll(self.fd, &header, 5)) return false;
        if (!sys.sendAll(self.fd, &encrypted, encrypted_len)) return false;
        return true;
    }

    pub fn sendAppData(self: *TlsConnection, data: []const u8) bool {
        var encrypted: [16384]u8 = undefined;
        const encrypted_len = encryptRecord(&self.client_ap, CT_APPLICATION_DATA, data, &encrypted) orelse return false;
        var header: [5]u8 = undefined;
        header[0] = CT_APPLICATION_DATA;
        header[1] = 0x03; header[2] = 0x03;
        header[3] = @as(u8, @intCast(encrypted_len >> 8));
        header[4] = @as(u8, @intCast(encrypted_len));
        if (!sys.sendAll(self.fd, &header, 5)) return false;
        if (!sys.sendAll(self.fd, &encrypted, encrypted_len)) return false;
        return true;
    }

    pub fn recvAppData(self: *TlsConnection, buf: []u8) usize {
        var header: [5]u8 = .{0} ** 5;
        var off: usize = 0;
        while (off < 5) {
            const n = sys.recv(self.fd, @as([*]u8, &header) + off, 5 - off, 0);
            if (n <= 0) return 0;
            off += @as(usize, @intCast(n));
        }
        if (header[0] != CT_APPLICATION_DATA) return 0;
        const ct_len = (@as(usize, header[3]) << 8) | @as(usize, header[4]);
        if (ct_len > 65536 + 16) return 0;
        var ct_buf: [65536 + 16]u8 = .{0} ** (65536 + 16);
        off = 0;
        while (off < ct_len) {
            const n = sys.recv(self.fd, @as([*]u8, &ct_buf) + off, ct_len - off, 0);
            if (n <= 0) return 0;
            off += @as(usize, @intCast(n));
        }
        var plaintext: [65536]u8 = .{0} ** 65536;
        const pt_len = decryptRecord(&self.server_ap, ct_buf[0..ct_len], &plaintext) orelse return 0;
        @memcpy(buf[0..pt_len], plaintext[0..pt_len]);
        return pt_len;
    }
};

pub const Response = struct {
    success: bool = false,
    path: []const u8 = "/",
    body: []const u8 = "",
    data: [65536]u8 = [_]u8{0} ** 65536,
    data_len: usize = 0,
};

fn tlsStrlen(ptr: [*:0]const u8) usize {
    var i: usize = 0;
    while (ptr[i] != 0) : (i += 1) {}
    return i;
}

pub export fn httpsGetPacked(host: [*:0]const u8, path: [*:0]const u8) u64 {
    const h = host[0..tlsStrlen(host)];
    const p = path[0..tlsStrlen(path)];
    var resp = Response{ .path = p };
    const ok = TlsConnection.connect(h, 443, &resp);
    if (!ok) return 0;
    const len = @min(resp.data_len, 65536);
    @memcpy(tls_response_data[0..len], resp.data[0..len]);
    tls_response_len = len;
    return (@as(u64, 1) << 32) | @as(u64, len);
}

pub export fn httpsPostPacked(host: [*:0]const u8, path: [*:0]const u8, body: [*:0]const u8) u64 {
    const h = host[0..tlsStrlen(host)];
    const p = path[0..tlsStrlen(path)];
    const b = body[0..tlsStrlen(body)];
    var resp = Response{ .path = p, .body = b };
    const ok = TlsConnection.connect(h, 443, &resp);
    if (!ok) return 0;
    const len = @min(resp.data_len, 65536);
    @memcpy(tls_response_data[0..len], resp.data[0..len]);
    tls_response_len = len;
    return (@as(u64, 1) << 32) | @as(u64, len);
}

pub export fn httpsGetToFile(host: [*:0]const u8, path: [*:0]const u8, filename: [*:0]const u8) u64 {
    const h = host[0..tlsStrlen(host)];
    const p = path[0..tlsStrlen(path)];
    var resp = Response{ .path = p };
    const ok = TlsConnection.connect(h, 443, &resp);
    if (!ok) return 0;
    const O_WRONLY: i32 = 1;
    const O_CREAT: i32 = 0x40;
    const O_TRUNC: i32 = 0x200;
    const fd = sys.open(filename, O_WRONLY | O_CREAT | O_TRUNC, 0o644);
    if (fd < 0) return 0;
    var off: usize = 0;
    while (off < resp.data_len) {
        const n = sys.write(fd, resp.data[off..].ptr, resp.data_len - off);
        if (n <= 0) { _ = sys.close(fd); return 0; }
        off += @as(usize, @intCast(n));
    }
    _ = sys.close(fd);
    return 1;
}

pub fn httpsGet(host: []const u8, path: []const u8) Response {
    var resp = Response{ .path = path };
    resp.success = TlsConnection.connect(host, 443, &resp);
    return resp;
}

pub fn httpsPost(host: []const u8, path: []const u8, body: []const u8) Response {
    var resp = Response{ .path = path, .body = body };
    resp.success = TlsConnection.connect(host, 443, &resp);
    return resp;
}

// ============================== X.509 DER Parsing ==============================

fn derSkipTLV(data: []const u8, pos: *usize) bool {
    if (pos.* >= data.len) return false;
    const tag = data[pos.*];
    _ = tag;
    pos.* += 1;
    if (pos.* >= data.len) return false;
    if (data[pos.*] & 0x80 != 0) {
        const num_len = data[pos.*] & 0x7F;
        pos.* += 1;
        if (num_len == 0 or pos.* + num_len > data.len) return false;
        var len: usize = 0;
        for (0..num_len) |i| {
            len = (len << 8) | @as(usize, data[pos.* + i]);
        }
        pos.* += num_len;
        pos.* += len;
    } else {
        pos.* += data[pos.*] + 1;
    }
    return true;
}

fn derGetValue(data: []const u8, pos: *usize) ?[]const u8 {
    if (pos.* >= data.len) return null;
    pos.* += 1;
    if (pos.* >= data.len) return null;
    var len: usize = 0;
    if (data[pos.*] & 0x80 != 0) {
        const num_len = data[pos.*] & 0x7F;
        pos.* += 1;
        if (num_len == 0 or pos.* + num_len > data.len) return null;
        for (0..num_len) |i| {
            len = (len << 8) | @as(usize, data[pos.* + i]);
        }
        pos.* += num_len;
    } else {
        len = data[pos.*];
        pos.* += 1;
    }
    if (pos.* + len > data.len) return null;
    const val = data[pos.* .. pos.* + len];
    pos.* += len;
    return val;
}

fn findRsaOid(data: []const u8) ?usize {
    const rsa_oid = [_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01 };
    if (data.len < rsa_oid.len) return null;
    var i: usize = 0;
    while (i <= data.len - rsa_oid.len) : (i += 1) {
        var match = true;
        for (0..rsa_oid.len) |j| {
            if (data[i + j] != rsa_oid[j]) { match = false; break; }
        }
        if (match) return i;
    }
    return null;
}

fn parseCertRSAPublicKey(cert_der: []const u8, n: *crypto.BigInt, e: *crypto.BigInt) bool {
    // Find the RSA OID in the certificate
    const oid_pos = findRsaOid(cert_der) orelse return false;

    // After the OID, the next SEQUENCE should be the BIT STRING with RSAPublicKey
    // Look for BIT STRING (0x03) after OID
    var pos = oid_pos + 9;
    while (pos < cert_der.len) {
        if (cert_der[pos] == 0x03) {
            // Found BIT STRING - get its value
            var bs_pos = pos;
            const bs_val = derGetValue(cert_der, &bs_pos) orelse { pos += 1; continue; };
            if (bs_val.len > 0) {
                // Skip unused bits byte
                const inner = bs_val[1..];
                // Inner should be SEQUENCE of two INTEGERs
                if (inner.len > 2 and inner[0] == 0x30) {
                    var seq_pos: usize = 0;
                    const seq_val = derGetValue(inner, &seq_pos) orelse { pos += 1; continue; };
                    // Parse n (first INTEGER)
                    var n_pos: usize = 0;
                    const n_val = derGetValue(seq_val, &n_pos) orelse return false;
                    // Parse e (second INTEGER)
                    const e_val = derGetValue(seq_val, &n_pos) orelse return false;

                    // Strip leading 0x00 sign byte if present
                    var nv = n_val;
                    if (nv.len > 1 and nv[0] == 0x00) nv = nv[1..];
                    _ = sys.write(2, "DBG: n[0..4]=", 13);
                    var ni: usize = 0;
                    while (ni < 4 and ni < nv.len) : (ni += 1) { var hx: [2]u8 = undefined; hx[0]=@as(u8,if(nv[ni]>>4<10)'0'+(nv[ni]>>4)else'a'+(nv[ni]>>4)-10);hx[1]=@as(u8,if((nv[ni]&15)<10)'0'+(nv[ni]&15)else'a'+((nv[ni]&15))-10); _ = sys.write(2,&hx,2); }
                    _ = sys.write(2, " e=", 3);
                    { var hx: [2]u8 = undefined; hx[0]=@as(u8,if(e_val[0]>>4<10)'0'+(e_val[0]>>4)else'a'+(e_val[0]>>4)-10);hx[1]=@as(u8,if((e_val[0]&15)<10)'0'+(e_val[0]&15)else'a'+((e_val[0]&15))-10); _ = sys.write(2,&hx,2); }
                    _ = sys.write(2, "\n", 1);
                    n.* = crypto.biFromBytes(nv);
                    e.* = crypto.biFromBytes(e_val);
                    return true;
                }
            }
        }
        pos += 1;
    }
    return false;
}

// ============================== RSA-PSS Signature Verification ==============================

fn mgf1(mgf_seed: []const u8, mask_len: usize, out: []u8) void {
    var counter: u32 = 0;
    var off: usize = 0;
    while (off < mask_len) : (counter += 1) {
        var input: [128]u8 = undefined;
        @memcpy(input[0..mgf_seed.len], mgf_seed);
        input[mgf_seed.len + 0] = @as(u8, @intCast(counter >> 24));
        input[mgf_seed.len + 1] = @as(u8, @intCast(counter >> 16));
        input[mgf_seed.len + 2] = @as(u8, @intCast(counter >> 8));
        input[mgf_seed.len + 3] = @as(u8, @intCast(counter));
        var hash: [32]u8 = undefined;
        crypto.sha256(input[0..mgf_seed.len + 4], &hash);
        const copy_len = @min(32, mask_len - off);
        @memcpy(out[off..][0..copy_len], hash[0..copy_len]);
        off += copy_len;
    }
}

fn verifyRsaPssSignature(cv_msg: []const u8, n: crypto.BigInt, e: crypto.BigInt, transcript_hash: *const [32]u8) bool {
    // Parse CertificateVerify: type(1) + 3-byte length + algorithm(2) + sig_len(2) + signature
    if (cv_msg.len < 8) return false;
    var pos: usize = 4;
    const algo = (@as(u16, cv_msg[pos]) << 8) | @as(u16, cv_msg[pos + 1]);
    pos += 2;
    if (algo != 0x0804) return false; // only rsa_pss_rsae_sha256 supported
    const sig_len = (@as(usize, cv_msg[pos]) << 8) | @as(usize, cv_msg[pos + 1]);
    pos += 2;
    if (pos + sig_len > cv_msg.len) return false;
    const signature = cv_msg[pos..][0..sig_len];
    if (sig_len != 256) return false; // 2048-bit RSA

    // RSA verify: EM = sig^e mod n
    var sig_bi = crypto.biFromBytes(signature);
    // Dump sig, n, e for external verification
    {
        _ = sys.write(2, "DBG: n.len=", 11);
        { var dlen = n.len; var dbg_buf: [16]u8 = undefined; var dbg_i: usize = 16; while (dbg_i > 0) { dbg_i -= 1; dbg_buf[dbg_i] = @as(u8, @truncate(dlen % 10 + '0')); dlen /= 10; if (dlen == 0) break; } _ = sys.write(2, @ptrCast(dbg_buf[dbg_i..].ptr), 16 - dbg_i); }
        _ = sys.write(2, " DBG: n.limbs[63]=", 18);
        { const v = n.limbs[63]; var hx: [8]u8 = undefined; var hi: usize = 0; while (hi < 8) : (hi += 1) { const shift: u5 = @intCast(28 - hi * 4); const nib = @as(u8, @truncate((v >> shift) & 0xf)); hx[hi] = if (nib < 10) '0' + nib else 'a' + nib - 10; } _ = sys.write(2, &hx, 8); }
        _ = sys.write(2, "\n", 1);
        var n_bytes: [256]u8 = undefined; crypto.biToBytes(&n, &n_bytes);
        var e_bytes: [3]u8 = undefined; crypto.biToBytes(&e, &e_bytes);
        _ = sys.write(2, "DBG: n=", 7);
        var ii: usize = 0; while (ii < 256) : (ii += 1) { var h: [2]u8 = undefined; h[0]=@as(u8,if(n_bytes[ii]>>4<10)'0'+(n_bytes[ii]>>4)else'a'+(n_bytes[ii]>>4)-10);h[1]=@as(u8,if((n_bytes[ii]&15)<10)'0'+(n_bytes[ii]&15)else'a'+((n_bytes[ii]&15))-10); _ = sys.write(2, &h, 2); }
        _ = sys.write(2, "\n", 1);
        _ = sys.write(2, "DBG: e=", 7);
        ii = 0; while (ii < 3) : (ii += 1) { var h: [2]u8 = undefined; h[0]=@as(u8,if(e_bytes[ii]>>4<10)'0'+(e_bytes[ii]>>4)else'a'+(e_bytes[ii]>>4)-10);h[1]=@as(u8,if((e_bytes[ii]&15)<10)'0'+(e_bytes[ii]&15)else'a'+((e_bytes[ii]&15))-10); _ = sys.write(2, &h, 2); }
        _ = sys.write(2, "\n", 1);
        _ = sys.write(2, "DBG: sig=", 9);
        ii = 0; while (ii < 256) : (ii += 1) { var h: [2]u8 = undefined; h[0]=@as(u8,if(signature[ii]>>4<10)'0'+(signature[ii]>>4)else'a'+(signature[ii]>>4)-10);h[1]=@as(u8,if((signature[ii]&15)<10)'0'+(signature[ii]&15)else'a'+((signature[ii]&15))-10); _ = sys.write(2, &h, 2); }
        _ = sys.write(2, "\n", 1);
        _ = sys.write(2, "DBG: tshash=", 12);
        ii = 0; while (ii < 32) : (ii += 1) { var h: [2]u8 = undefined; h[0]=@as(u8,if(transcript_hash[ii]>>4<10)'0'+(transcript_hash[ii]>>4)else'a'+(transcript_hash[ii]>>4)-10);h[1]=@as(u8,if((transcript_hash[ii]&15)<10)'0'+(transcript_hash[ii]&15)else'a'+((transcript_hash[ii]&15))-10); _ = sys.write(2, &h, 2); }
        _ = sys.write(2, "\n", 1);
    }
    var em_bi: crypto.BigInt = undefined;
    crypto.biModExp(&sig_bi, &e, &n, &em_bi);

    var em: [256]u8 = undefined;
    crypto.biToBytes(&em_bi, em[0..]);

    _ = sys.write(2, "DBG: em[255]=", 13);
    { var hx: [2]u8 = undefined; hx[0]=@as(u8,if(em[255]>>4<10)'0'+(em[255]>>4)else'a'+(em[255]>>4)-10);hx[1]=@as(u8,if((em[255]&15)<10)'0'+(em[255]&15)else'a'+((em[255]&15))-10); _ = sys.write(2, &hx, 2); }
    _ = sys.write(2, " em[0]=", 7);
    { var hx: [2]u8 = undefined; hx[0]=@as(u8,if(em[0]>>4<10)'0'+(em[0]>>4)else'a'+(em[0]>>4)-10);hx[1]=@as(u8,if((em[0]&15)<10)'0'+(em[0]&15)else'a'+((em[0]&15))-10); _ = sys.write(2, &hx, 2); }
    _ = sys.write(2, "\n", 1);

    // EMSA-PSS verify with SHA-256, sLen=32
    const hLen: usize = 32;
    const sLen: usize = 32;
    const emLen: usize = 256;
    const emBits: usize = 2047;

    if (em[emLen - 1] != 0xBC) {
        _ = sys.write(2, "DBG: em[255] not BC\n", 20);
        return false;
    }

    const maskedDB = em[0 .. emLen - hLen - 1];
    const H = em[emLen - hLen - 1 .. emLen - 1];
    const dbMaskLen = emLen - hLen - 1;
    var dbMask: [256]u8 = undefined;
    mgf1(H, dbMaskLen, dbMask[0..dbMaskLen]);
    var db: [256]u8 = undefined;
    for (0..dbMaskLen) |i| db[i] = maskedDB[i] ^ dbMask[i];

    const leading_bits_clear = 8 * emLen - emBits;
    if (leading_bits_clear > 0) db[0] &= @as(u8, @intCast(0xFF >> @as(u3, @intCast(leading_bits_clear))));

    const zero_pad_len = emLen - hLen - sLen - 2;
    for (0..zero_pad_len) |i| {
        if (db[i] != 0) {
            _ = sys.write(2, "DBG: db[i] not zero\n", 20);
            return false;
        }
    }
    if (db[zero_pad_len] != 0x01) {
        _ = sys.write(2, "DBG: db[zpl] not 01\n", 20);
        return false;
    }

    const salt = db[zero_pad_len + 1 .. zero_pad_len + 1 + sLen];

    var m_prime: [8 + 32 + 32]u8 = undefined;
    for (0..8) |i| m_prime[i] = 0;
    @memcpy(m_prime[8..][0..32], transcript_hash[0..32]);
    @memcpy(m_prime[40..][0..32], salt);

    var h2: [32]u8 = undefined;
    crypto.sha256(&m_prime, &h2);

    for (0..32) |i| {
        if (H[i] != h2[i]) {
            _ = sys.write(2, "DBG: H mismatch\n", 16);
            return false;
        }
    }
    return true;
}
