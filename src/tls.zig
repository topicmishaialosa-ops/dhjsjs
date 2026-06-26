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

const AEAD_TAG_LEN = 16;

const CipherSuite = enum(u16) {
    tls_aes_128_gcm_sha256 = 0x1301,
    tls_chacha20_poly1305_sha256 = 0x1303,
};

const TlsCipherState = struct {
    key: [32]u8 = [_]u8{0} ** 32,
    iv: [12]u8 = [_]u8{0} ** 12,
    seq_num: u64 = 0,
    key_len: usize = 16,
    aead: CipherSuite = .tls_aes_128_gcm_sha256,
};

pub const TlsConnection = struct {
    fd: i32,
    suite: CipherSuite = .tls_aes_128_gcm_sha256,
    server_hs: TlsCipherState = TlsCipherState{},
    client_hs: TlsCipherState = TlsCipherState{},
    server_ap: TlsCipherState = TlsCipherState{},
    client_ap: TlsCipherState = TlsCipherState{},
    transcript: [8192]u8 = undefined,
    transcript_len: usize = 0,
    hello_hash: [48]u8 = undefined,
    hello_hash_len: usize = 32,
    server_pk: [32]u8 = undefined,
    shared_secret: [32]u8 = undefined,
    shared_secret_len: usize = 32,

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

        if (!self.sendAppData(req_buf[0..rp])) return false;

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
        var sk: [32]u8 = undefined;
        crypto.x25519Keypair(&sk, &self.server_pk);

        var hello_buf: [512]u8 = undefined;
        var hp: usize = 0;

        hello_buf[hp] = 0x03; hp += 1; hello_buf[hp] = 0x03; hp += 1;

        var random: [32]u8 = undefined;
        const fd = sys.open("/dev/urandom\x00", 0, 0);
        if (fd >= 0) {
            _ = sys.read(fd, &random, 32);
            sys.close(fd);
        }
        @memcpy(hello_buf[hp..][0..32], &random);
        hp += 32;

        hello_buf[hp] = 0; hp += 1;

        // Two cipher suites: AES-128-GCM, ChaCha20-Poly1305
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x04; hp += 1;
        hello_buf[hp] = 0x13; hp += 1; hello_buf[hp] = 0x01; hp += 1; // AES-128-GCM
        hello_buf[hp] = 0x13; hp += 1; hello_buf[hp] = 0x03; hp += 1; // ChaCha20-Poly1305

        hello_buf[hp] = 0x01; hp += 1;
        hello_buf[hp] = 0x00; hp += 1;

        const ext_start = hp;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x00; hp += 1;

        // supported_versions
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x2b; hp += 1;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x03; hp += 1;
        hello_buf[hp] = 0x02; hp += 1;
        hello_buf[hp] = 0x03; hp += 1; hello_buf[hp] = 0x04; hp += 1;

        // supported_groups: x25519
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x0a; hp += 1;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x04; hp += 1;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x02; hp += 1;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x1d; hp += 1;

        // signature_algorithms
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x0d; hp += 1;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x08; hp += 1;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x06; hp += 1;
        hello_buf[hp] = 0x08; hp += 1; hello_buf[hp] = 0x04; hp += 1;
        hello_buf[hp] = 0x08; hp += 1; hello_buf[hp] = 0x05; hp += 1;
        hello_buf[hp] = 0x08; hp += 1; hello_buf[hp] = 0x06; hp += 1;

        // key_share
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x33; hp += 1;
        const ks_ext_len_pos = hp;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x00; hp += 1;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x00; hp += 1;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x1d; hp += 1;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x20; hp += 1;
        @memcpy(hello_buf[hp..][0..32], &self.server_pk);
        hp += 32;
        const ks_list_len: u16 = @as(u16, @intCast(2 + 2 + 32));
        hello_buf[ks_ext_len_pos + 2] = @as(u8, @intCast(ks_list_len >> 8));
        hello_buf[ks_ext_len_pos + 3] = @as(u8, @intCast(ks_list_len));
        const ks_ext_len: u16 = @as(u16, @intCast(2 + 2 + 2 + 32));
        hello_buf[ks_ext_len_pos] = @as(u8, @intCast(ks_ext_len >> 8));
        hello_buf[ks_ext_len_pos + 1] = @as(u8, @intCast(ks_ext_len));

        // server_name
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x00; hp += 1;
        const sni_ext_len_pos = hp;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x00; hp += 1;
        const sni_list_len_pos = hp;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x00; hp += 1;
        hello_buf[hp] = 0x00; hp += 1;
        const sni_len_pos = hp;
        hello_buf[hp] = 0x00; hp += 1; hello_buf[hp] = 0x00; hp += 1;
        var sni_i: usize = 0;
        while (sni_i < host.len and hp < 500) : (sni_i += 1) {
            hello_buf[hp] = host[sni_i]; hp += 1;
        }
        const name_len: u16 = @as(u16, @intCast(host.len));
        hello_buf[sni_len_pos] = @as(u8, @intCast(name_len >> 8));
        hello_buf[sni_len_pos + 1] = @as(u8, @intCast(name_len));
        const sni_list_body_len: u16 = @as(u16, @intCast(3 + host.len));
        hello_buf[sni_list_len_pos] = @as(u8, @intCast(sni_list_body_len >> 8));
        hello_buf[sni_list_len_pos + 1] = @as(u8, @intCast(sni_list_body_len));
        const sni_ext_body_len: u16 = @as(u16, @intCast(2 + 3 + host.len));
        hello_buf[sni_ext_len_pos] = @as(u8, @intCast(sni_ext_body_len >> 8));
        hello_buf[sni_ext_len_pos + 1] = @as(u8, @intCast(sni_ext_body_len));

        const ext_len: u16 = @as(u16, @intCast(hp - ext_start - 2));
        hello_buf[ext_start] = @as(u8, @intCast(ext_len >> 8));
        hello_buf[ext_start + 1] = @as(u8, @intCast(ext_len));

        var msg_buf: [512]u8 = undefined;
        var mp: usize = 0;
        msg_buf[mp] = HS_CLIENT_HELLO; mp += 1;
        msg_buf[mp] = @as(u8, @intCast(hp >> 16)); mp += 1; msg_buf[mp] = @as(u8, @intCast(hp >> 8)); mp += 1; msg_buf[mp] = @as(u8, @intCast(hp)); mp += 1;
        @memcpy(msg_buf[mp..][0..hp], hello_buf[0..hp]);
        mp += hp;

        if (!self.writePlainRecord(CT_HANDSHAKE, msg_buf[0..mp])) return false;
        self.appendTranscript(msg_buf[0..mp]);

        var sh_buf: [512]u8 = undefined;
        const sh_len = self.readPlainRecord(CT_HANDSHAKE, sh_buf[0..]) orelse return false;

        var shp: usize = 0;
        if (sh_len < 4) return false;
        _ = sh_buf[shp]; shp += 1;
        const sh_body_len = @as(usize, sh_buf[shp]) << 16 | @as(usize, sh_buf[shp + 1]) << 8 | @as(usize, sh_buf[shp + 2]);
        shp += 3;
        if (shp + sh_body_len > sh_len) return false;
        const sh_body = sh_buf[shp..][0..sh_body_len];
        var ssp: usize = 0;
        _ = sh_body[ssp]; ssp += 1; _ = sh_body[ssp]; ssp += 1;
        ssp += 32;
        _ = sh_body[ssp]; ssp += 1;
        const sh_cs0 = sh_body[ssp]; ssp += 1; const sh_cs1 = sh_body[ssp]; ssp += 1;
        const chosen_suite = (@as(u16, sh_cs0) << 8) | @as(u16, sh_cs1);
        self.suite = @enumFromInt(chosen_suite);

        const hash_len: usize = 32;

        _ = sh_body[ssp]; ssp += 1;
        const sh_ext_len = (@as(usize, sh_body[ssp]) << 8) | @as(usize, sh_body[ssp + 1]);
        ssp += 2;
        var found_key_share = false;
        const sh_ext_end = ssp + sh_ext_len;
        while (ssp + 4 <= sh_ext_end) {
            const ext_type = (@as(usize, sh_body[ssp]) << 8) | @as(usize, sh_body[ssp + 1]);
            ssp += 2;
            const ext_len_val = (@as(usize, sh_body[ssp]) << 8) | @as(usize, sh_body[ssp + 1]);
            ssp += 2;
            if (ext_type == 0x0033) {
                if (ext_len_val < 4) return false;
                _ = sh_body[ssp]; ssp += 1; _ = sh_body[ssp]; ssp += 1;
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

        crypto.x25519(&self.shared_secret, &sk, &self.server_pk);
        self.shared_secret_len = 32;

        const empty_salt: [32]u8 = [_]u8{0} ** 32;
        var early_secret: [48]u8 = undefined;
        crypto.hmacSha256(empty_salt[0..hash_len], empty_salt[0..hash_len], early_secret[0..hash_len]);

        var empty_hash_buf: [32]u8 = undefined;
        {
            var h: [32]u8 = undefined;
            crypto.sha256(&[_]u8{}, &h);
            @memcpy(empty_hash_buf[0..32], &h);
        }

        var derived_1: [32]u8 = undefined;
        crypto.deriveSecret(early_secret[0..hash_len], "derived", empty_hash_buf[0..hash_len], derived_1[0..hash_len]);

        var handshake_secret: [32]u8 = undefined;
        crypto.hkdfExtract(derived_1[0..hash_len], self.shared_secret[0..self.shared_secret_len], handshake_secret[0..hash_len]);

        var hello_hash_buf: [256]u8 = undefined;
        @memcpy(hello_hash_buf[0..self.transcript_len], self.transcript[0..self.transcript_len]);
        crypto.sha256(hello_hash_buf[0..self.transcript_len], @as(*[32]u8, @ptrCast(&self.hello_hash)));

        var server_hs_traffic: [32]u8 = undefined;
        var client_hs_traffic: [32]u8 = undefined;
        crypto.deriveSecret(handshake_secret[0..hash_len], "s hs traffic", self.hello_hash[0..hash_len], server_hs_traffic[0..hash_len]);
        crypto.deriveSecret(handshake_secret[0..hash_len], "c hs traffic", self.hello_hash[0..hash_len], client_hs_traffic[0..hash_len]);

        const key_len: usize = switch (self.suite) {
            .tls_aes_128_gcm_sha256 => 16,
            .tls_chacha20_poly1305_sha256 => 32,
        };

        self.server_hs.aead = self.suite;
        self.server_hs.key_len = key_len;
        crypto.hkdfExpandLabel(server_hs_traffic[0..hash_len], "key", "", self.server_hs.key[0..key_len]);
        crypto.hkdfExpandLabel(server_hs_traffic[0..hash_len], "iv", "", self.server_hs.iv[0..]);
        self.server_hs.seq_num = 0;

        self.client_hs.aead = self.suite;
        self.client_hs.key_len = key_len;
        crypto.hkdfExpandLabel(client_hs_traffic[0..hash_len], "key", "", self.client_hs.key[0..key_len]);
        crypto.hkdfExpandLabel(client_hs_traffic[0..hash_len], "iv", "", self.client_hs.iv[0..]);
        self.client_hs.seq_num = 0;

        var rec_buf: [16384]u8 = undefined;
        var rec_ct: u8 = undefined;
        var rec_len: usize = undefined;

        var offset: usize = 0;
        var got_ee = false;
        var got_cert = false;
        var got_cv = false;
        var got_finished = false;
        var cert_n: crypto.BigInt = undefined;
        var cert_e: crypto.BigInt = undefined;

        while (!got_ee or !got_cert or !got_cv or !got_finished) {
            if (!self.readEncryptedHs(&rec_buf, &rec_ct, &rec_len)) return false;
            offset = 0;
            while (offset + 4 <= rec_len) {
            const hs_type = rec_buf[offset];
            const hs_len = (@as(usize, rec_buf[offset + 1]) << 16) |
                           (@as(usize, rec_buf[offset + 2]) << 8) |
                           @as(usize, rec_buf[offset + 3]);
            if (offset + 4 + hs_len > rec_len) return false;
            const hs_body = rec_buf[offset + 4 .. offset + 4 + hs_len];
            switch (hs_type) {
                HS_ENCRYPTED_EXTENSIONS => {
                    got_ee = true;
                    self.appendTranscript(rec_buf[offset .. offset + 4 + hs_len]);
                },
                HS_CERTIFICATE => {
                    got_cert = true;
                    self.appendTranscript(rec_buf[offset .. offset + 4 + hs_len]);
                    if (!parseCertRSAPublicKey(hs_body, &cert_n, &cert_e)) return false;
                },
                HS_CERTIFICATE_VERIFY => {
                    got_cv = true;
                    if (hs_len < 4) return false;
                    const sig_alg = (@as(u16, hs_body[0]) << 8) | @as(u16, hs_body[1]);
                    const sig_len = (@as(u16, hs_body[2]) << 8) | @as(u16, hs_body[3]);
                    if (sig_alg != 0x0804 and sig_alg != 0x0805 and sig_alg != 0x0806) return false;
                    if (sig_len != 256) return false;
                    if (hs_len < 4 + sig_len) return false;

                    self.appendTranscript(rec_buf[offset .. offset + 4 + hs_len]);
                },
                HS_FINISHED => {
                    got_finished = true;
                    var transcript_hash_fin: [32]u8 = undefined;
                    crypto.sha256(self.transcript[0..self.transcript_len], &transcript_hash_fin);
                    self.appendTranscript(rec_buf[offset .. offset + 4 + hs_len]);
                    var server_finished_key: [32]u8 = undefined;
                    crypto.hkdfExpandLabel(server_hs_traffic[0..hash_len], "finished", "", server_finished_key[0..hash_len]);
                    var expected_sf: [32]u8 = undefined;
                    crypto.hmacSha256(server_finished_key[0..hash_len], transcript_hash_fin[0..], &expected_sf);
                    if (hs_len < hash_len) return false;
                    for (0..hash_len) |i| { if (hs_body[i] != expected_sf[i]) return false; }
                },
                else => return false,
            }
            offset += 4 + hs_len;
        }
        }

        var derived_2: [32]u8 = undefined;
        crypto.deriveSecret(handshake_secret[0..hash_len], "derived", empty_hash_buf[0..hash_len], derived_2[0..hash_len]);

        var master_secret: [32]u8 = undefined;
        crypto.hkdfExtract(derived_2[0..hash_len], empty_salt[0..hash_len], master_secret[0..hash_len]);

        var all_hash: [32]u8 = undefined;
        crypto.sha256(self.transcript[0..self.transcript_len], &all_hash);

        var server_ap_traffic: [32]u8 = undefined;
        var client_ap_traffic: [32]u8 = undefined;
        crypto.deriveSecret(master_secret[0..hash_len], "s ap traffic", &all_hash, server_ap_traffic[0..hash_len]);
        crypto.deriveSecret(master_secret[0..hash_len], "c ap traffic", &all_hash, client_ap_traffic[0..hash_len]);

        self.server_ap.aead = self.suite;
        self.server_ap.key_len = key_len;
        crypto.hkdfExpandLabel(server_ap_traffic[0..hash_len], "key", "", self.server_ap.key[0..key_len]);
        crypto.hkdfExpandLabel(server_ap_traffic[0..hash_len], "iv", "", self.server_ap.iv[0..]);
        self.server_ap.seq_num = 0;

        self.client_ap.aead = self.suite;
        self.client_ap.key_len = key_len;
        crypto.hkdfExpandLabel(client_ap_traffic[0..hash_len], "key", "", self.client_ap.key[0..key_len]);
        crypto.hkdfExpandLabel(client_ap_traffic[0..hash_len], "iv", "", self.client_ap.iv[0..]);
        self.client_ap.seq_num = 0;

        var client_finished_key: [32]u8 = undefined;
        crypto.hkdfExpandLabel(client_hs_traffic[0..hash_len], "finished", "", client_finished_key[0..hash_len]);
        var cf_transcript: [32]u8 = undefined;
        crypto.sha256(self.transcript[0..self.transcript_len], &cf_transcript);
        var cf_data: [32]u8 = undefined;
        crypto.hmacSha256(client_finished_key[0..], cf_transcript[0..], &cf_data);

        var cf_msg_buf: [256]u8 = undefined;
        cf_msg_buf[0] = HS_FINISHED;
        const cf_body_len: u32 = @as(u32, @intCast(hash_len));
        cf_msg_buf[1] = @as(u8, @intCast(cf_body_len >> 16));
        cf_msg_buf[2] = @as(u8, @intCast(cf_body_len >> 8));
        cf_msg_buf[3] = @as(u8, @intCast(cf_body_len));
        @memcpy(cf_msg_buf[4..][0..hash_len], cf_data[0..hash_len]);
        if (!self.writeEncryptedRecord(&self.client_hs, cf_msg_buf[0 .. 4 + hash_len])) return false;

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
            if (header[0] == CT_ALERT) {
                const alert_len = (@as(usize, header[3]) << 8) | @as(usize, header[4]);
                if (alert_len >= 2) {
                    var alert_buf: [2]u8 = undefined;
                    _ = sys.recv(self.fd, @as([*]u8, &alert_buf), 2, 0);
                }
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

        var pt_len: usize = ct_len;
        switch (state.aead) {
            .tls_aes_128_gcm_sha256 => {
                if (!crypto.gcmDecrypt(
                    @as(*const [16]u8, @ptrCast(&state.key)), &nonce, &aad, ct,
                    @as(*const [16]u8, @ptrCast(tag.ptr)), out
                )) return null;
            },
            .tls_chacha20_poly1305_sha256 => {
                if (!crypto.chacha20Poly1305Decrypt(
                    @as(*const [32]u8, @ptrCast(&state.key)), &nonce, &aad, ct,
                    @as(*const [16]u8, @ptrCast(tag.ptr)), out
                )) return null;
            },
        }

        // Strip TLS 1.3 padding
        while (pt_len > 0) {
            pt_len -= 1;
            if (out[pt_len] != 0) break;
        }
        if (pt_len == 0 and ct_len > 0) return null;
        return pt_len;
    }

    fn encryptRecord(state: *TlsCipherState, content_type: u8, data: []const u8, out: []u8) ?usize {
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
        switch (state.aead) {
            .tls_aes_128_gcm_sha256 => {
                crypto.gcmEncrypt(
                    @as(*const [16]u8, @ptrCast(&state.key)), &nonce, &aad, pt[0..pt_len], out, &tag
                );
            },
            .tls_chacha20_poly1305_sha256 => {
                crypto.chacha20Poly1305Encrypt(
                    @as(*const [32]u8, @ptrCast(&state.key)), &nonce, &aad, pt[0..pt_len], out, &tag
                );
            },
        }
        @memcpy(out[pt_len..][0..16], &tag);
        return pt_len + 16;
    }

    fn readEncryptedHs(self: *TlsConnection, buf: []u8, content_type: *u8, out_len: *usize) bool {
        var header: [5]u8 = .{0} ** 5;
        var off: usize = 0;
        while (off < 5) {
            const n = sys.recv(self.fd, @as([*]u8, &header) + off, 5 - off, 0);
            if (n <= 0) return false;
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
            return false;
        }
        const ct_len = (@as(usize, header[3]) << 8) | @as(usize, header[4]);
        if (ct_len > 16384 + 16) return false;
        var ct_buf: [16384 + 16]u8 = .{0} ** (16384 + 16);
        off = 0;
        while (off < ct_len) {
            const n = sys.recv(self.fd, @as([*]u8, &ct_buf) + off, ct_len - off, 0);
            if (n <= 0) return false;
            off += @as(usize, @intCast(n));
        }
        var plaintext: [16384]u8 = undefined;
        const pt_len = decryptRecord(&self.server_hs, ct_buf[0..ct_len], &plaintext) orelse return false;
        if (pt_len < 4) return false;
        content_type.* = plaintext[pt_len - 1];
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
    const oid_pos = findRsaOid(cert_der) orelse return false;
    var pos = oid_pos + 9;
    while (pos < cert_der.len) {
        if (cert_der[pos] == 0x03) {
            var bs_pos = pos;
            const bs_val = derGetValue(cert_der, &bs_pos) orelse { pos += 1; continue; };
            if (bs_val.len > 0) {
                const inner = bs_val[1..];
                if (inner.len > 2 and inner[0] == 0x30) {
                    var seq_pos: usize = 0;
                    const seq_val = derGetValue(inner, &seq_pos) orelse { pos += 1; continue; };
                    var n_pos: usize = 0;
                    const n_val = derGetValue(seq_val, &n_pos) orelse return false;
                    const e_val = derGetValue(seq_val, &n_pos) orelse return false;
                    var nv = n_val;
                    if (nv.len > 1 and nv[0] == 0x00) nv = nv[1..];
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

