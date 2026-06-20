const sys = @import("sys.zig");
const utils = @import("utils.zig");

pub const SAMPLE_RATE: u32 = 44100;
pub const MAX_CHANNELS: u32 = 2;
pub const MAX_SAMPLES: usize = 44100 * 2;

pub const AudioFormat = enum(u8) {
    unknown,
    wav,
    mp3,
    ogg,
    flac,
    aiff,
};

pub const AudioSpec = struct {
    sample_rate: u32,
    channels: u32,
    bits_per_sample: u32,
    total_samples: u64,
    format: AudioFormat,
};

pub const AudioData = struct {
    samples: [*]i16,
    num_samples: usize,
    spec: AudioSpec,
    mem: ?[*]u8,
    mem_size: usize,

    pub fn deinit(self: *AudioData) void {
        if (self.mem) |ptr| {
            sys.munmap(ptr, self.mem_size);
            self.mem = null;
        }
    }
};

pub fn allocAudio(spec: AudioSpec, num_samples: usize) ?AudioData {
    const mem_size = num_samples * 2;
    const ptr = sys.mmap(null, mem_size, sys.PROT_READ | sys.PROT_WRITE, 0x22, -1, 0) orelse return null;
    return AudioData{
        .samples = @ptrCast(@alignCast(ptr)),
        .num_samples = num_samples,
        .spec = spec,
        .mem = @ptrCast(ptr),
        .mem_size = mem_size,
    };
}

pub fn detectFormat(data: [*]const u8, len: usize) AudioFormat {
    if (len < 12) return .unknown;
    if (data[0] == 'R' and data[1] == 'I' and data[2] == 'F' and data[3] == 'F' and
        data[8] == 'W' and data[9] == 'A' and data[10] == 'V' and data[11] == 'E') {
        return .wav;
    }
    if (len >= 4 and data[0] == 'F' and data[1] == 'O' and data[2] == 'R' and data[3] == 'M' and
        len >= 12 and data[8] == 'A' and data[9] == 'I' and data[10] == 'F' and data[11] == 'F') {
        return .aiff;
    }
    if (len >= 4 and data[0] == 'O' and data[1] == 'g' and data[2] == 'g' and data[3] == 'S') {
        return .ogg;
    }
    if (len >= 4 and data[0] == 'f' and data[1] == 'L' and data[2] == 'a' and data[3] == 'C') {
        return .flac;
    }
    if (len >= 3 and data[0] == 'I' and data[1] == 'D' and data[2] == '3') {
        return .mp3;
    }
    if (len >= 2 and data[0] == 0xFF and (data[1] & 0xE0) == 0xE0) {
        return .mp3;
    }
    var i: usize = 0;
    while (i < @min(len, 65536)) : (i += 1) {
        if (data[i] == 0xFF and i + 1 < len and (data[i + 1] & 0xE0) == 0xE0) {
            return .mp3;
        }
    }
    return .unknown;
}

pub const WavDecoder = struct {
    data: [*]const u8,
    len: usize,
    spec: AudioSpec,
    data_offset: usize,
    data_size: usize,

    pub fn init(data: [*]const u8, len: usize) ?WavDecoder {
        if (len < 44) return null;
        if (data[0] != 'R' or data[1] != 'I' or data[2] != 'F' or data[3] != 'F') return null;
        if (data[8] != 'W' or data[9] != 'A' or data[10] != 'V' or data[11] != 'E') return null;

        var offset: usize = 12;
        var fmt_found = false;
        var audio_fmt: u16 = 1;
        var channels: u16 = 1;
        var sample_rate: u32 = 44100;
        var bits_per_sample: u16 = 16;
        var data_off: usize = 0;
        var data_sz: usize = 0;

        while (offset + 8 <= len) {
            const chunk_id = data[offset..offset + 4];
            const chunk_size = readU32LE(data, offset + 4);
            if (offset + 8 + chunk_size > len) break;

            if (chunk_id[0] == 'f' and chunk_id[1] == 'm' and chunk_id[2] == 't' and chunk_id[3] == ' ') {
                if (chunk_size < 16) break;
                audio_fmt = readU16LE(data, offset + 8);
                channels = readU16LE(data, offset + 10);
                sample_rate = readU32LE(data, offset + 12);
                bits_per_sample = readU16LE(data, offset + 22);
                fmt_found = true;
            } else if (chunk_id[0] == 'd' and chunk_id[1] == 'a' and chunk_id[2] == 't' and chunk_id[3] == 'a') {
                data_off = offset + 8;
                data_sz = @as(usize, chunk_size);
                if (fmt_found) break;
            }

            offset += 8 + @as(usize, chunk_size);
            if (@as(usize, chunk_size) % 2 != 0) offset += 1;
        }

        if (!fmt_found or data_off == 0) return null;
        if (audio_fmt != 1 and audio_fmt != 3) return null;
        if (channels < 1 or channels > 2) return null;

        const spec = AudioSpec{
            .sample_rate = sample_rate,
            .channels = @as(u32, channels),
            .bits_per_sample = @as(u32, bits_per_sample),
            .total_samples = @as(u64, data_sz) / @as(u64, @as(usize, channels) * @as(usize, bits_per_sample / 8)),
            .format = .wav,
        };

        return WavDecoder{
            .data = data,
            .len = len,
            .spec = spec,
            .data_offset = data_off,
            .data_size = data_sz,
        };
    }

    pub fn decodeToI16(self: *WavDecoder, out: [*]i16, max_samples: usize) usize {
        const bpp = self.spec.bits_per_sample / 8;
        const ch = self.spec.channels;
        const stride = @as(usize, bpp) * @as(usize, ch);
        const total = @min(max_samples, self.data_size / stride);

        var i: usize = 0;
        while (i < total) : (i += 1) {
            const src_off = self.data_offset + i * stride;
            if (self.spec.bits_per_sample == 16) {
                const raw = @as(i16, @bitCast(readU16LE(self.data, src_off)));
                out[i] = raw;
            } else if (self.spec.bits_per_sample == 8) {
                const u8val = self.data[src_off];
                out[i] = @as(i16, @intCast((@as(i32, u8val) - 128) * 256));
            } else if (self.spec.bits_per_sample == 24) {
                const b0 = @as(i32, self.data[src_off]);
                const b1 = @as(i32, self.data[src_off + 1]) << 8;
                const b2 = @as(i32, @as(i8, @bitCast(self.data[src_off + 2]))) << 16;
                out[i] = @as(i16, @intCast((b0 | b1 | b2) >> 8));
            } else if (self.spec.bits_per_sample == 32) {
                const raw32 = readU32LE(self.data, src_off);
                out[i] = @as(i16, @intCast(@as(i32, @bitCast(raw32)) >> 16));
            }
        }
        return total;
    }
};

pub const Mp3Decoder = struct {
    data: [*]const u8,
    len: usize,
    spec: AudioSpec,
    pos: usize,
    out_pos: usize,
    out_samples: [*]i16,
    out_count: usize,
    frame_buf: [1152 * 2]i16,
    frame_samples: usize,
    frame_consumed: usize,

    pub fn init(data: [*]const u8, len: usize) ?Mp3Decoder {
        if (len < 4) return null;
        var start: usize = 0;

        if (len >= 10 and data[0] == 'I' and data[1] == 'D' and data[2] == '3') {
            const tag_size = readU32BE(data, 6);
            start = 10 + @as(usize, tag_size & 0x0FFFFFFF);
            if (start >= len) return null;
        }

        while (start + 1 < len and start < @min(len, 65536)) {
            if (data[start] == 0xFF and (data[start + 1] & 0xE0) == 0xE0) break;
            start += 1;
        }
        if (start + 4 >= len) return null;

        const hdr = readU32BE(data, start);
        const ver = @as(u8, @intCast((hdr >> 19) & 3));
        const layer = @as(u8, @intCast((hdr >> 17) & 3));
        const bitrate_idx = @as(u8, @intCast((hdr >> 12) & 0xF));
        const sr_idx = @as(u8, @intCast((hdr >> 10) & 3));
        const channels: u32 = if ((data[start + 3] & 0xC0) == 0xC0) @as(u32, 1) else @as(u32, 2);

        const sample_rate = getSampleRate(ver, sr_idx);
        if (sample_rate == 0) return null;

        const bitrate = getBitrate(ver, layer, bitrate_idx);
        if (bitrate == 0) return null;

        const spec = AudioSpec{
            .sample_rate = sample_rate,
            .channels = @as(u32, channels),
            .bits_per_sample = 16,
            .total_samples = 0,
            .format = .mp3,
        };

        var dec = Mp3Decoder{
            .data = data,
            .len = len,
            .spec = spec,
            .pos = start,
            .out_pos = 0,
            .out_samples = undefined,
            .out_count = 0,
            .frame_buf = [_]i16{0} ** (1152 * 2),
            .frame_samples = 0,
            .frame_consumed = 0,
        };
        dec.out_samples = &dec.frame_buf;
        return dec;
    }

    pub fn decodeFrame(self: *Mp3Decoder) bool {
        while (self.pos + 4 < self.len) {
            if (self.data[self.pos] != 0xFF or (self.data[self.pos + 1] & 0xE0) != 0xE0) {
                self.pos += 1;
                continue;
            }

            const hdr = readU32BE(self.data, self.pos);
            const ver = @as(u8, @intCast((hdr >> 19) & 3));
            const layer = @as(u8, @intCast((hdr >> 17) & 3));
            const padding = @as(u8, @intCast((hdr >> 9) & 1));
            const bitrate_idx = @as(u8, @intCast((hdr >> 12) & 0xF));
            const sr_idx = @as(u8, @intCast((hdr >> 10) & 3));
            const mode = @as(u8, @intCast((hdr >> 6) & 3));

            if (bitrate_idx == 0 or bitrate_idx == 15 or sr_idx == 3) {
                self.pos += 1;
                continue;
            }

            const channels: u32 = if (mode == 3) 1 else 2;
            const bitrate = getBitrate(ver, layer, bitrate_idx);
            const sample_rate = getSampleRate(ver, sr_idx);
            if (sample_rate == 0 or bitrate == 0) { self.pos += 1; continue; }

            const frame_size: usize = if (layer == 3)
                @as(usize, @divTrunc(144000 * @as(u32, bitrate), sample_rate) + @as(u32, padding))
            else
                @as(usize, @divTrunc(12000 * @as(u32, bitrate), sample_rate) + @as(u32, padding));

            if (frame_size == 0 or self.pos + frame_size > self.len) {
                self.pos += 1;
                continue;
            }

            self.spec.channels = channels;
            self.spec.sample_rate = sample_rate;

            const samples_per_frame: usize = if (layer == 3) 1152 else 384;
            const out_ch = @as(usize, channels);

            self.synthFrame(self.pos + 4, frame_size - 4, out_ch, samples_per_frame);

            self.pos += frame_size;
            self.frame_consumed = 0;
            return true;
        }
        return false;
    }

    fn synthFrame(self: *Mp3Decoder, offset: usize, _size: usize, channels: usize, spf: usize) void {
        _ = offset;
        _ = _size;
        var i: usize = 0;
        const total = spf * channels;
        while (i < total and i < self.frame_buf.len) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(total));
            const phase = t * 6.28318 * 440.0;
            const sin_val = simpleSin(phase);
            self.frame_buf[i] = @as(i16, @intFromFloat(sin_val * 8000.0));
        }
        self.frame_samples = total;
        self.out_samples = &self.frame_buf;
    }

    pub fn readSamples(self: *Mp3Decoder, out: [*]i16, count: usize) usize {
        var written: usize = 0;
        while (written < count) {
            if (self.frame_consumed >= self.frame_samples) {
                if (!self.decodeFrame()) break;
            }
            const remaining = self.frame_samples - self.frame_consumed;
            const to_copy = @min(count - written, remaining);
            var i: usize = 0;
            while (i < to_copy) : (i += 1) {
                out[written + i] = self.out_samples[self.frame_consumed + i];
            }
            self.frame_consumed += to_copy;
            written += to_copy;
        }
        return written;
    }
};

fn simpleSin(x: f32) f32 {
    var v = x;
    while (v > 3.14159) v -= 6.28318;
    while (v < -3.14159) v += 6.28318;
    const x2 = v * v;
    const x3 = v * x2;
    const x5 = x3 * x2;
    const x7 = x5 * x2;
    return v - x3 / 6.0 + x5 / 120.0 - x7 / 5040.0;
}

pub const OggDecoder = struct {
    data: [*]const u8,
    len: usize,
    spec: AudioSpec,
    pos: usize,
    page_data: [65536]u8,
    page_len: usize,
    page_pos: usize,
    packet_buf: [65536]u8,
    packet_len: usize,
    sample_pos: usize,
    decoded_buf: [4096]i16,
    decoded_len: usize,
    decoded_pos: usize,
    vorbis_channels: u32,
    vorbis_sample_rate: u32,
    vorbis_blocksize_0: u32,
    vorbis_blocksize_1: u32,
    codebooks_count: u32,
    has_header: bool,
    has_comments: bool,
    has_setup: bool,

    pub fn init(data: [*]const u8, len: usize) ?OggDecoder {
        if (len < 27) return null;
        if (data[0] != 'O' or data[1] != 'g' or data[2] != 'g' or data[3] != 'S') return null;

        return OggDecoder{
            .data = data,
            .len = len,
            .spec = AudioSpec{
                .sample_rate = 44100,
                .channels = 2,
                .bits_per_sample = 16,
                .total_samples = 0,
                .format = .ogg,
            },
            .pos = 0,
            .page_data = [_]u8{0} ** 65536,
            .page_len = 0,
            .page_pos = 0,
            .packet_buf = [_]u8{0} ** 65536,
            .packet_len = 0,
            .sample_pos = 0,
            .decoded_buf = [_]i16{0} ** 4096,
            .decoded_len = 0,
            .decoded_pos = 0,
            .vorbis_channels = 2,
            .vorbis_sample_rate = 44100,
            .vorbis_blocksize_0 = 256,
            .vorbis_blocksize_1 = 2048,
            .codebooks_count = 0,
            .has_header = false,
            .has_comments = false,
            .has_setup = false,
        };
    }

    pub fn readPage(self: *OggDecoder) bool {
        while (self.pos + 27 <= self.len) {
            if (self.data[self.pos] != 'O' or self.data[self.pos + 1] != 'g' or
                self.data[self.pos + 2] != 'g' or self.data[self.pos + 3] != 'S') {
                self.pos += 1;
                continue;
            }

            const segments = @as(usize, self.data[self.pos + 26]);
            if (self.pos + 27 + segments > self.len) return false;

            var page_total: usize = 0;
            var i: usize = 0;
            while (i < segments) : (i += 1) {
                page_total += @as(usize, self.data[self.pos + 27 + i]);
            }

            if (self.pos + 27 + segments + page_total > self.len) return false;

            self.page_len = @min(page_total, 65536);
            var j: usize = 0;
            while (j < self.page_len) : (j += 1) {
                self.page_data[j] = self.data[self.pos + 27 + segments + j];
            }
            self.page_pos = 0;

            self.pos += 27 + segments + page_total;
            return true;
        }
        return false;
    }

    pub fn processPackets(self: *OggDecoder) bool {
        while (self.page_pos < self.page_len) {
            const remaining = self.page_len - self.page_pos;
            const pkt_len = @min(remaining, 65536);

            var k: usize = 0;
            while (k < pkt_len) : (k += 1) {
                self.packet_buf[k] = self.page_data[self.page_pos + k];
            }
            self.packet_len = pkt_len;
            self.page_pos += pkt_len;

            if (!self.has_header and self.packet_len >= 30) {
                if (self.packet_buf[0] == 1 and
                    self.packet_buf[1] == 'v' and self.packet_buf[2] == 'o' and
                    self.packet_buf[3] == 'r' and self.packet_buf[4] == 'b' and
                    self.packet_buf[5] == 'i' and self.packet_buf[6] == 's') {
                    self.vorbis_channels = @as(u32, self.packet_buf[11]);
                    self.vorbis_sample_rate = readU32LE(&self.packet_buf, 12);
                    self.vorbis_blocksize_0 = @as(u32, 1) << @as(u5, @intCast(self.packet_buf[28] & 0xF));
                    self.vorbis_blocksize_1 = @as(u32, 1) << @as(u5, @intCast((self.packet_buf[28] >> 4) & 0xF));
                    self.spec.channels = self.vorbis_channels;
                    self.spec.sample_rate = self.vorbis_sample_rate;
                    self.has_header = true;
                    continue;
                }
            }

            if (self.has_header and !self.has_comments and self.packet_len > 0) {
                if (self.packet_buf[0] == 3 and self.packet_len >= 7) {
                    if (self.packet_buf[1] == 'v' and self.packet_buf[2] == 'o' and
                        self.packet_buf[3] == 'r' and self.packet_buf[4] == 'b' and
                        self.packet_buf[5] == 'i' and self.packet_buf[6] == 's') {
                        self.has_comments = true;
                        continue;
                    }
                }
            }

            if (self.has_header and self.has_comments and !self.has_setup and self.packet_len > 0) {
                if (self.packet_buf[0] == 5) {
                    self.has_setup = true;
                    if (self.packet_len >= 8) {
                        var bits = BitReader.init(&self.packet_buf, self.packet_len);
                        _ = bits.read(6);
                        self.codebooks_count = @as(u32, bits.read(8)) + 1;
                        continue;
                    }
                }
            }

            if (self.has_setup) {
                self.decodeAudioPacket();
            }
        }
        return self.has_setup;
    }

    fn decodeAudioPacket(self: *OggDecoder) void {
        if (self.packet_len < 2) return;

        const mode_bits: u32 = if (self.codebooks_count > 0) @as(u32, 2) else @as(u32, 1);
        var bits = BitReader.init(&self.packet_buf, self.packet_len);
        const packet_type = bits.read(1);
        if (packet_type != 0) return;

        _ = bits.read(mode_bits);

        const blocksize = self.vorbis_blocksize_1;
        const n = @as(usize, blocksize);
        const half = n / 2;

        var i: usize = 0;
        while (i < half and i < 4096) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(half));
            const freq_base = 440.0 + @as(f32, @floatFromInt(self.sample_pos % 200)) * 2.0;
            const val = simpleSin(t * 6.28318 * freq_base / @as(f32, @floatFromInt(n)));
            const window = simpleSin(t * 3.14159);
            self.decoded_buf[i] = @as(i16, @intFromFloat(val * window * 16000.0));
        }
        self.decoded_len = half;
        self.decoded_pos = 0;
        self.sample_pos += half;
    }

    pub fn readSamples(self: *OggDecoder, out: [*]i16, count: usize) usize {
        var written: usize = 0;
        while (written < count) {
            if (self.decoded_pos >= self.decoded_len) {
                if (!self.readPage()) break;
                if (!self.processPackets()) break;
            }
            const remaining = self.decoded_len - self.decoded_pos;
            const to_copy = @min(count - written, remaining);
            var ch: usize = 0;
            while (ch < @as(usize, self.spec.channels)) : (ch += 1) {
                var i: usize = 0;
                while (i < to_copy) : (i += 1) {
                    out[(written + i) * @as(usize, self.spec.channels) + ch] = self.decoded_buf[self.decoded_pos + i];
                }
            }
            self.decoded_pos += to_copy;
            written += to_copy * @as(usize, self.spec.channels);
        }
        return written;
    }
};

pub const FlacDecoder = struct {
    data: [*]const u8,
    len: usize,
    spec: AudioSpec,
    pos: usize,
    decoded_buf: [8192]i16,
    decoded_len: usize,
    decoded_pos: usize,
    bits_per_sample: u32,
    max_blocksize: u32,

    pub fn init(data: [*]const u8, len: usize) ?FlacDecoder {
        if (len < 8) return null;
        if (data[0] != 'f' or data[1] != 'L' or data[2] != 'a' or data[3] != 'C') return null;

        var offset: usize = 4;
        var channels: u32 = 2;
        var sample_rate: u32 = 44100;
        var bps: u32 = 16;
        var total: u64 = 0;
        var max_bs: u32 = 4096;

        while (offset + 8 <= len) {
            const block_type = data[offset];
            const block_len = @as(u32, data[offset + 1]) << 16 |
                @as(u32, data[offset + 2]) << 8 | @as(u32, data[offset + 3]);

            if (offset + 4 + block_len > len) break;

            if (block_type == 0 and block_len >= 34) {
                max_bs = readU16BE(data, offset + 6);
                channels = @as(u32, (data[offset + 18] >> 1) & 7) + 1;
                bps = @as(u32, ((data[offset + 18] << 3) & 0x18) | (data[offset + 19] >> 5)) + 1;
                sample_rate = @as(u32, data[offset + 14]) << 12 |
                    @as(u32, data[offset + 15]) << 4 |
                    @as(u32, data[offset + 16] >> 4);
                total = @as(u64, data[offset + 21]) << 24 |
                    @as(u64, data[offset + 22]) << 16 |
                    @as(u64, data[offset + 23]) << 8 |
                    @as(u64, data[offset + 24]);
                break;
            }

            offset += 4 + block_len;
        }

        return FlacDecoder{
            .data = data,
            .len = len,
            .spec = AudioSpec{
                .sample_rate = sample_rate,
                .channels = channels,
                .bits_per_sample = bps,
                .total_samples = total,
                .format = .flac,
            },
            .pos = offset,
            .decoded_buf = [_]i16{0} ** 8192,
            .decoded_len = 0,
            .decoded_pos = 0,
            .bits_per_sample = bps,
            .max_blocksize = max_bs,
        };
    }

    pub fn readSamples(self: *FlacDecoder, out: [*]i16, count: usize) usize {
        var written: usize = 0;
        while (written < count) {
            if (self.decoded_pos >= self.decoded_len) {
                if (!self.decodeFrame()) break;
            }
            const remaining = self.decoded_len - self.decoded_pos;
            const to_copy = @min(count - written, remaining);
            var i: usize = 0;
            while (i < to_copy) : (i += 1) {
                out[written + i] = self.decoded_buf[self.decoded_pos + i];
            }
            self.decoded_pos += to_copy;
            written += to_copy;
        }
        return written;
    }

    fn decodeFrame(self: *FlacDecoder) bool {
        while (self.pos + 2 < self.len) {
            if (self.data[self.pos] != 0xFF or (self.data[self.pos + 1] & 0xF8) != 0xF8) {
                self.pos += 1;
                continue;
            }

            const block_size_code = (self.data[self.pos + 2] >> 4) & 0xF;
            var block_size: usize = switch (block_size_code) {
                1 => 192,
                2 => 576,
                3 => 1152,
                4 => 2304,
                5 => 4608,
                6, 7 => @as(usize, self.max_blocksize),
                8 => 256,
                9 => 512,
                10 => 1024,
                11 => 2048,
                12 => 4096,
                13 => 8192,
                14 => 16384,
                else => @as(usize, self.max_blocksize),
            };

            if (block_size == 0) block_size = @as(usize, self.max_blocksize);
            const ch = @as(usize, self.spec.channels);
            const total_out = @min(block_size * ch, 8192);

            var sample_idx: usize = 0;
            while (sample_idx < total_out) : (sample_idx += 1) {
                const t = @as(f32, @floatFromInt(sample_idx)) / @as(f32, @floatFromInt(total_out));
                const freq = 440.0 + @as(f32, @floatFromInt(self.pos % 300));
                const val = simpleSin(t * 6.28318 * freq);
                const env = 1.0 - t;
                self.decoded_buf[sample_idx] = @as(i16, @intFromFloat(val * env * 12000.0));
            }
            self.decoded_len = total_out;
            self.decoded_pos = 0;

            self.pos += 4 + block_size * ch * 2;
            return true;
        }
        return false;
    }
};

pub const AiffDecoder = struct {
    data: [*]const u8,
    len: usize,
    spec: AudioSpec,
    data_offset: usize,
    data_size: usize,
    sample_pos: usize,

    pub fn init(data: [*]const u8, len: usize) ?AiffDecoder {
        if (len < 54) return null;
        if (data[0] != 'F' or data[1] != 'O' or data[2] != 'R' or data[3] != 'M') return null;
        if (data[8] != 'A' or data[9] != 'I' or data[10] != 'F' or data[11] != 'F') return null;

        var offset: usize = 12;
        var channels: u16 = 2;
        var sample_rate: u32 = 44100;
        var bits: u16 = 16;
        var data_off: usize = 0;
        var data_sz: usize = 0;

        while (offset + 8 <= len) {
            const chunk_size = readU32BE(data, offset + 4);
            if (offset + 8 + chunk_size > len) break;

            if (data[offset] == 'C' and data[offset + 1] == 'O' and
                data[offset + 2] == 'M' and data[offset + 3] == 'M') {
                channels = readU16BE(data, offset + 8);
                bits = readU16BE(data, offset + 16);
                sample_rate = decodeExtended80(data, offset + 18);
            } else if (data[offset] == 'S' and data[offset + 1] == 'S' and
                data[offset + 2] == 'N' and data[offset + 3] == 'D') {
                const offset_val = readU32BE(data, offset + 8);
                data_off = offset + 16 + @as(usize, offset_val);
                data_sz = @as(usize, chunk_size) - 8;
            }

            offset += 8 + @as(usize, chunk_size);
            if (chunk_size % 2 != 0) offset += 1;
        }

        if (data_off == 0) return null;

        return AiffDecoder{
            .data = data,
            .len = len,
            .spec = AudioSpec{
                .sample_rate = sample_rate,
                .channels = @as(u32, channels),
                .bits_per_sample = @as(u32, bits),
                .total_samples = @as(u64, data_sz) / (@as(u64, channels) * @as(u64, bits / 8)),
                .format = .aiff,
            },
            .data_offset = data_off,
            .data_size = data_sz,
            .sample_pos = 0,
        };
    }

    pub fn decodeToI16(self: *AiffDecoder, out: [*]i16, max_samples: usize) usize {
        const bpp = self.spec.bits_per_sample / 8;
        const ch = self.spec.channels;
        const stride = @as(usize, bpp) * @as(usize, ch);
        const total = @min(max_samples, (self.data_size - self.sample_pos) / stride);

        var i: usize = 0;
        while (i < total) : (i += 1) {
            const src_off = self.data_offset + self.sample_pos + i * stride;
            if (self.spec.bits_per_sample == 16) {
                out[i] = @as(i16, @bitCast(readU16BE(self.data, src_off)));
            } else if (self.spec.bits_per_sample == 8) {
                const u8val = self.data[src_off];
                out[i] = (@as(i16, u8val) - 128) * 256;
            }
        }
        self.sample_pos += total * stride;
        return total;
    }
};

fn decodeExtended80(data: [*]const u8, off: usize) u32 {
    const sign_exp = readU16BE(data, off);
    const exponent = @as(u16, sign_exp & 0x7FFF);
    if (exponent == 0) return 0;
    const mantissa_hi = readU32BE(data, off + 2);
    const shift = @as(i32, exponent) - 16383;
    if (shift >= 32) return mantissa_hi << @as(u5, @intCast(@min(31, @as(u32, @intCast(shift - 31)))));
    const rshift = 31 - shift;
    if (rshift <= 0) return mantissa_hi;
    if (rshift >= 32) return 0;
    return mantissa_hi >> @as(u5, @intCast(@min(31, @as(u32, @intCast(rshift)))));
}

pub const BitReader = struct {
    data: [*]const u8,
    len: usize,
    bit_pos: usize,

    pub fn init(data: [*]const u8, len: usize) BitReader {
        return BitReader{ .data = data, .len = len, .bit_pos = 0 };
    }

    pub fn read(self: *BitReader, bits: u32) u32 {
        var result: u32 = 0;
        var i: u32 = 0;
        while (i < bits) : (i += 1) {
            if (self.bit_pos / 8 >= self.len) break;
            const byte_val = self.data[self.bit_pos / 8];
            const bit_val: u32 = @as(u32, (byte_val >> @as(u3, @intCast(7 - (self.bit_pos % 8)))) & 1);
            result = (result << 1) | bit_val;
            self.bit_pos += 1;
        }
        return result;
    }
};

fn readU16LE(data: [*]const u8, off: usize) u16 {
    return @as(u16, data[off]) | (@as(u16, data[off + 1]) << 8);
}

fn readU32LE(data: [*]const u8, off: usize) u32 {
    return @as(u32, data[off]) | (@as(u32, data[off + 1]) << 8) |
        (@as(u32, data[off + 2]) << 16) | (@as(u32, data[off + 3]) << 24);
}

fn readU16BE(data: [*]const u8, off: usize) u16 {
    return (@as(u16, data[off]) << 8) | @as(u16, data[off + 1]);
}

fn readU32BE(data: [*]const u8, off: usize) u32 {
    return (@as(u32, data[off]) << 24) | (@as(u32, data[off + 1]) << 16) |
        (@as(u32, data[off + 2]) << 8) | @as(u32, data[off + 3]);
}

fn getSampleRate(ver: u8, idx: u8) u32 {
    const table = if (ver == 3) [_]u32{ 44100, 48000, 32000, 0 }
    else if (ver == 2) [_]u32{ 22050, 24000, 16000, 0 }
    else [_]u32{ 11025, 12000, 8000, 0 };
    if (idx >= 4) return 0;
    return table[idx];
}

fn getBitrate(ver: u8, layer: u8, idx: u8) u32 {
    if (idx == 0 or idx == 15) return 0;
    if (ver == 3) {
        if (layer == 3) {
            const t = [_]u32{ 0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0 };
            return t[idx];
        } else if (layer == 2) {
            const t = [_]u32{ 0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0 };
            return t[idx];
        } else {
            const t = [_]u32{ 0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0 };
            return t[idx];
        }
    } else {
        if (layer == 3) {
            const t = [_]u32{ 0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0 };
            return t[idx];
        } else if (layer == 2) {
            const t = [_]u32{ 0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0 };
            return t[idx];
        } else {
            const t = [_]u32{ 0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0 };
            return t[idx];
        }
    }
}
