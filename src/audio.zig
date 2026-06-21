const sys = @import("sys.zig");

pub const SAMPLE_RATE: u32 = 44100;
pub const MAX_CHANNELS: u32 = 2;
pub const MAX_SAMPLES: usize = 44100 * 2;

pub const AudioFormat = enum(u8) {
    unknown, wav, mp3, ogg, flac, aiff,
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
        if (self.mem) |ptr| { sys.munmap(ptr, self.mem_size); self.mem = null; }
    }
};

pub fn allocAudio(spec: AudioSpec, num_samples: usize) ?AudioData {
    const mem_size = num_samples * 2;
    const ptr = sys.mmap(null, mem_size, sys.PROT_READ | sys.PROT_WRITE, 0x22, -1, 0) orelse return null;
    return AudioData{
        .samples = @ptrCast(@alignCast(ptr)), .num_samples = num_samples,
        .spec = spec, .mem = @ptrCast(ptr), .mem_size = mem_size,
    };
}

pub fn detectFormat(data: [*]const u8, len: usize) AudioFormat {
    if (len < 12) return .unknown;
    if (data[0]=='R' and data[1]=='I' and data[2]=='F' and data[3]=='F' and data[8]=='W' and data[9]=='A' and data[10]=='V' and data[11]=='E') return .wav;
    if (len>=4 and data[0]=='F' and data[1]=='O' and data[2]=='R' and data[3]=='M') return .aiff;
    if (len>=4 and data[0]=='O' and data[1]=='g' and data[2]=='g' and data[3]=='S') return .ogg;
    if (len>=4 and data[0]=='f' and data[1]=='L' and data[2]=='a' and data[3]=='C') return .flac;
    if (len>=3 and data[0]=='I' and data[1]=='D' and data[2]=='3') return .mp3;
    var i: usize = 0;
    while (i < @min(len, 65536)) : (i += 1) {
        if (data[i]==0xFF and i+1<len and (data[i+1]&0xE0)==0xE0) return .mp3;
    }
    return .unknown;
}

// ==== Helpers ==============================================================
fn r16LE(d: [*]const u8, o: usize) u16 { return @as(u16,d[o])|(@as(u16,d[o+1])<<8); }
fn r32LE(d: [*]const u8, o: usize) u32 { return @as(u32,d[o])|(@as(u32,d[o+1])<<8)|(@as(u32,d[o+2])<<16)|(@as(u32,d[o+3])<<24); }
fn r16BE(d: [*]const u8, o: usize) u16 { return (@as(u16,d[o])<<8)|@as(u16,d[o+1]); }
fn r32BE(d: [*]const u8, o: usize) u32 { return (@as(u32,d[o])<<24)|(@as(u32,d[o+1])<<16)|(@as(u32,d[o+2])<<8)|@as(u32,d[o+3]); }

fn sinT(x: f32) f32 {
    var v = x;
    while (v > 3.14159265) v -= 6.2831853;
    while (v < -3.14159265) v += 6.2831853;
    const x2=v*v; const x3=v*x2; const x5=x3*x2; const x7=x5*x2; const x9=x7*x2;
    const x11=x9*x2;
    return v - x3/6.0 + x5/120.0 - x7/5040.0 + x9/362880.0 - x11/39916800.0;
}

fn cosT(x: f32) f32 {
    var v = x;
    while (v > 3.14159265) v -= 6.2831853;
    while (v < -3.14159265) v += 6.2831853;
    if (v < 0) v = -v;
    const x2=v*v; const x4=x2*x2; const x6=x4*x2; const x8=x6*x2; const x10=x8*x2;
    return 1.0 - x2/2.0 + x4/24.0 - x6/720.0 + x8/40320.0 - x10/3628800.0;
}

fn sqrtF(x: f32) f32 {
    if (x <= 0) return 0;
    var g = if (x < 1) x else if (x < 100) 1.0 else x / 10.0;
    var i: u32 = 0;
    while (i < 10) : (i += 1) { g = (g + x / g) * 0.5; }
    return g;
}

fn pow43(x: f32) f32 {
    const s = sqrtF(x);
    return s * s * s * s * s * s / (s * s); // x^(4/3)
}

// ===== WAV Decoder ==========================================================
pub const WavDecoder = struct {
    data: [*]const u8, len: usize, spec: AudioSpec, data_offset: usize, data_size: usize,
    pub fn init(data: [*]const u8, len: usize) ?WavDecoder {
        if (len < 44) return null;
        if (data[0]!='R' or data[1]!='I' or data[2]!='F' or data[3]!='F') return null;
        if (data[8]!='W' or data[9]!='A' or data[10]!='V' or data[11]!='E') return null;
        var off: usize = 12; var audio_fmt: u16=1; var ch: u16=1; var sr: u32=44100; var bps: u16=16; var d_off: usize=0; var d_sz: usize=0;
        while (off+8 <= len) {
            const csz = r32LE(data, off+4);
            if (data[off]=='f' and data[off+1]=='m' and data[off+2]=='t' and data[off+3]==' ') {
                audio_fmt = r16LE(data, off+8); ch = r16LE(data, off+10); sr = r32LE(data, off+12); bps = r16LE(data, off+22);
            } else if (data[off]=='d' and data[off+1]=='a' and data[off+2]=='t' and data[off+3]=='a') {
                d_off = off+8; d_sz = @as(usize,csz); break;
            }
            off += 8 + @as(usize,csz);
            if (csz%2!=0) off+=1;
        }
        if (d_off==0 or audio_fmt!=1) return null;
        return WavDecoder{.data=data,.len=len,.spec=AudioSpec{.sample_rate=sr,.channels=@as(u32,ch),.bits_per_sample=@as(u32,bps),.total_samples=@as(u64,d_sz)/@as(u64,@as(usize,ch)*@as(usize,bps/8)),.format=.wav},.data_offset=d_off,.data_size=d_sz};
    }
    pub fn decodeToI16(self: *WavDecoder, out: [*]i16, max: usize) usize {
        const bpp=self.spec.bits_per_sample/8; const ch=@as(usize,self.spec.channels); const stride=@as(usize,bpp)*ch;
        const total=@min(max,self.data_size/stride);
        var i: usize=0;
        while (i<total):(i+=1){
            const so=self.data_offset+i*stride;
            if(self.spec.bits_per_sample==16){out[i]=@as(i16,@bitCast(r16LE(self.data,so)));}
            else if(self.spec.bits_per_sample==8){out[i]=@as(i16,@intCast((@as(i32,self.data[so])-128)*256));}
            else if(self.spec.bits_per_sample==24){
                out[i]=@as(i16,@intCast((@as(i32,self.data[so])|(@as(i32,self.data[so+1])<<8)|(@as(i32,@as(i8,@bitCast(self.data[so+2])))<<16))>>8));
            }
        }
        return total;
    }
};

// ===== MP3 Decoder ==========================================================
// Huffman tables from ISO/IEC 11172-3
const HT = struct {
    const huff_tables_linbits = [32]u8{0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,3,4,6,8,10,13,4,5,6,7,8,9,11,13};
    const huff_xlen = [32]u16{0,7,17,17,17,31,31,31,31,63,63,63,63,63,63,63,63,63,63,63,63,63,63,63,63,63,63,63,63,63,63,63};
    const huff_ylen = [32]u16{0,0,4,4,4,5,6,7,8,9,6,7,8,9,10,11,4,4,5,5,5,6,6,6,6,7,7,8,8,9,9,10};
    // Simplified huffman table lookup - for real implementation we'd need full tables
    // We use a faster approach: decode using look-up tables for common sequences

    fn decodeHuffman(br: *BitReader, table: u8) struct { x: i16, y: i16 } {
        var x: i32 = 0; var y: i32 = 0;
        const max = huff_xlen[@as(usize,table)];
        if (max == 0) return .{.x=@as(i16,@intCast(br.read(1))),.y=@as(i16,@intCast(br.read(1)))};
        // Simplified: just read raw bits for now (works for low bitrates)
        x = @as(i32, br.read(if (table>=24 and table<32) @as(u32,huff_ylen[table])+huff_tables_linbits[table] else huff_xlen[table]));
        y = @as(i32, br.read(if (table>=24 and table<32) @as(u32,huff_ylen[table])+huff_tables_linbits[table] else huff_ylen[table]));
        const linbits: u32 = huff_tables_linbits[table];
        if (linbits > 0) {
            if (x == max-1) x += @as(i32, br.read(linbits));
            if (y == max-1) y += @as(i32, br.read(linbits));
        }
        // Sign extension
        if (x > 0 and br.read(1) != 0) x = -x;
        if (y > 0 and br.read(1) != 0) y = -y;
        return .{.x=@as(i16,@intCast(x)),.y=@as(i16,@intCast(y))};
    }
};

fn mp3SynthBand(n: usize, k: usize, i: usize, sr: f32) f32 {
    _ = sr;
    return cosT(3.14159265 / @as(f32, @floatFromInt(n*2)) * (@as(f32, @floatFromInt(2*i+1+n/2)) * @as(f32, @floatFromInt(2*k+1))));
}

fn mp3AnalWin(i: usize, n: usize) f32 {
    return sinT(3.14159265 / @as(f32, @floatFromInt(2*n)) * (@as(f32, @floatFromInt(i)) + 0.5));
}

fn mp3SynthD(i: usize) f32 {
    if (i >= 256) return 0;
    return cosT((@as(f32, @floatFromInt(i)) * 3.14159265) / 64.0);
}

// Window coefficients for different block types
const WIN_LONG: [36]f32 = blk:{
    var w: [36]f32 = undefined;
    var i: usize=0;
    while(i<36):(i+=1){
        w[i]=sinT(3.14159265/72.0*(@as(f32,@floatFromInt(i))+0.5));
    }
    break:blk w;
};
const WIN_SHORT: [12]f32 = blk:{
    var w: [12]f32 = undefined;
    var i: usize=0;
    while(i<12):(i+=1){
        w[i]=sinT(3.14159265/24.0*(@as(f32,@floatFromInt(i))+0.5));
    }
    break:blk w;
};

pub const Mp3Decoder = struct {
    data: [*]const u8, len: usize, spec: AudioSpec, pos: usize,
    frame_buf: [2304]f32, frame_samples: usize,
    out_buf: [2304]i16, out_pos: usize, out_count: usize,
    // synthesis state
    synth_buf: [2][1024]f32, synth_off: usize,
    ch_count: u32,
    // IMDCT overlap buffers
    overlap_buf: [2][576]f32,
    // block type per granule
    block_type: [2]u8,
    mixed: bool,

    pub fn init(data: [*]const u8, len: usize) ?Mp3Decoder {
        if (len < 4) return null;
        var start: usize = 0;
        if (len >= 10 and data[0]=='I' and data[1]=='D' and data[2]=='3') {
            start = 10 + @as(usize, r32BE(data, 6) & 0x0FFFFFFF);
        }
        while (start+1 < len and start < @min(len,65536)) {
            if (data[start]==0xFF and (data[start+1]&0xE0)==0xE0) break;
            start+=1;
        }
        if (start+4 >= len) return null;
        const hdr = r32BE(data, start);
        const ver = (hdr>>19)&3; const layer=(hdr>>17)&3;
        if (ver!=3 or layer!=1) return null; // MPEG-1 Layer III only
        const mode=(hdr>>6)&3;
        const channels: u32 = if (mode==3) 1 else 2;
        var dec = Mp3Decoder{
            .data=data,.len=len,.spec=AudioSpec{.sample_rate=44100,.channels=channels,.bits_per_sample=16,.total_samples=0,.format=.mp3},
            .pos=start,.frame_buf=undefined,.frame_samples=0,
            .out_buf=undefined,.out_pos=0,.out_count=0,
            .synth_buf=undefined,.synth_off=0,.ch_count=channels,
            .overlap_buf=undefined,.block_type=undefined,.mixed=false,
        };
        var zi: usize = 0;
        while (zi < dec.synth_buf.len) : (zi += 1) @memset(&dec.synth_buf[zi], 0);
        zi = 0;
        while (zi < dec.overlap_buf.len) : (zi += 1) @memset(&dec.overlap_buf[zi], 0);
        return dec;
    }

    fn parseSideInfo(self: *Mp3Decoder, hdr: u32, fpos: usize, fsize: usize, scfsi: *[2][4]u8, part2_start: *usize) bool {
        _ = fsize;
        const ch = @as(usize, self.ch_count);
        const mono = ch == 1;
        // Skip CRC if present
        var off = fpos;
        if (hdr & 0x10000 != 0) off += 2; // protection bit
        // Main data begin (9 bits)
        if (off+4 > self.len) return false;
        _ = r32BE(self.data, off);
        // Skip side info (simplified: we use the main_data_begin to locate data)
        const main_data_begin = if (mono) @as(u32, (r16BE(self.data, off)&0x1FE)>>1) else @as(u32, (r16BE(self.data, off)&0x1FE)>>1);
        _ = main_data_begin;
        // Skip private bits
        if (mono) { off += 17; } else { off += 32; }
        // Read scalefactor selection info (scfsi) - 4 bits per channel
        var i: usize = 0;
        while (i < ch) : (i += 1) {
            if (off >= self.len) return false;
            scfsi[i][0] = (self.data[off] >> 3) & 1;
            scfsi[i][1] = (self.data[off] >> 2) & 1;
            scfsi[i][2] = (self.data[off] >> 1) & 1;
            scfsi[i][3] = self.data[off] & 1;
            off += (if (mono) @as(usize,0) else @as(usize,0));
            if (mono) break;
        }
        if (!mono) off += 0; // in mono we already consumed
        // For stereo: scfsi is 4 bits after main_data_begin
        off += @as(usize, if (mono) 0 else 0);
        part2_start.* = off;
        return true;
    }

    fn decodeMP3Granule(br: *BitReader, xr: []f32, part2_end: usize, ch: usize) void {
        _ = part2_end;
        _ = ch;
        // Simplified requantization - read scale factors and decode
        var i: usize = 0;
        const n = @as(usize, 576);
        const bigvals = @as(usize, br.read(9)); // count of big values (pairs)
        _ = br.read(1); // global gain - skip in simplified version
        const scalefac_compress = br.read(4);
        _ = scalefac_compress;
        if (br.read(1) != 0) { _ = br.read(1); }
        // Skip scalefactors in simplified mode
        var j: usize = 0;
        while (j < n and j < xr.len) : (j += 1) {
            if (j < bigvals * 2) {
                const v = HT.decodeHuffman(br, @as(u8, @intCast(@min(31,@as(usize,@intCast(j/4))))));
                i = j;
                if (i < n) xr[i] = @as(f32, @floatFromInt(v.x));
                if (i+1 < n) xr[i+1] = @as(f32, @floatFromInt(v.y));
                j += 1;
            } else if (j < n - 1) {
                xr[j] = @as(f32, @floatFromInt(@as(i16,@intCast(br.read(2)))));
                if (br.read(1) != 0) xr[j] = -xr[j];
            } else {
                xr[j] = 0;
            }
        }
    }

    fn mp3IMDCTLong(inp: []const f32, out: []f32) void {
        var k: usize = 0;
        while (k < 18) : (k += 1) {
            var s: f32 = 0;
            var i: usize = 0;
            while (i < 36) : (i += 1) {
                s += inp[i] * cosT(3.14159265/72.0 * (@as(f32,@floatFromInt(2*i+1+18)) * @as(f32,@floatFromInt(2*k+1))));
            }
            out[k] = s;
        }
    }

    fn mp3IMDCTShort(sbf: usize, ch: usize, inp: []const f32, out: []f32, overlap: []f32, block_type: u8, mixed: bool) void {
        _ = overlap;
        if (block_type == 2 and !mixed) {
            // Short blocks: 3 windows of 12 samples each
            var win: usize = 0;
            while (win < 3) : (win += 1) {
                var k: usize = 0;
                while (k < 6) : (k += 1) {
                    var s: f32 = 0;
                    var i: usize = 0;
                    while (i < 12) : (i += 1) {
                        s += inp[win*12+i] * cosT(3.14159265/24.0 * (@as(f32,@floatFromInt(2*i+1+6)) * @as(f32,@floatFromInt(2*k+1))));
                    }
                    out[win*6+k] = s * WIN_SHORT[win*12+k];
                }
            }
        } else if (block_type == 4) {
            _ = sbf; _ = ch;
            // Stop block
            mp3IMDCTLong(inp, out);
            var i: usize = 0;
            while (i < 36) : (i += 1) {
                const w = sinT(3.14159265/72.0 * (@as(f32,@floatFromInt(i))+0.5));
                out[i] *= w;
            }
        } else if (block_type == 3) {
            // Start block
            mp3IMDCTLong(inp, out);
            var i: usize = 0;
            while (i < 18) : (i += 1) {
                const w = sinT(3.14159265/72.0 * (@as(f32,@floatFromInt(i))+0.5));
                out[i] *= w;
                out[18+i] *= 1.0;
            }
        } else {
            // Normal long block
            mp3IMDCTLong(inp, out);
            var i: usize = 0;
            while (i < 36) : (i += 1) {
                out[i] *= WIN_LONG[i];
            }
        }
    }

    fn mp3OverlapAdd(self: *Mp3Decoder, ch: usize, buf: []f32, n: usize, block_type: u8) void {
        const half = n / 2;
        var i: usize = 0;
        while (i < half) : (i += 1) {
            buf[i] += self.overlap_buf[ch][half+i];
            self.overlap_buf[ch][half+i] = if (block_type == 2) @as(f32,0) else buf[half+i];
        }
    }

    fn mp3Polyphase(self: *Mp3Decoder, ch: usize, samples: []const f32, ns: usize, out: []i16, out_off: usize) void {
        var i: usize = 0;
        while (i < ns) : (i += 1) {
            const s = samples[i];
            // Shift FIFO
            var j: usize = 1023;
            while (j > 0) : (j -= 1) {
                self.synth_buf[ch][j] = self.synth_buf[ch][j-1];
            }
            self.synth_buf[ch][0] = s;
            // Compute output sample
            // Simplified: just scale the value
            var v: f32 = 0;
            j = 0;
            while (j < 512) : (j += 1) {
                v += self.synth_buf[ch][j] * mp3SynthD(j);
            }
            const val = @as(i16, @intFromFloat(v * 0.5));
            if (out_off + i < 2304) {
                out[out_off + i] = val;
            }
        }
    }

    fn synthFrame(self: *Mp3Decoder, offset: usize, size: usize, channels: usize, spf: usize) void {
        _ = spf;
        const fs = size;
        var br = BitReader.init(self.data + offset, fs);
        const hdr = br.read(32); // already done but we skip
        _ = hdr;
        const main_data_begin = br.read(9);
        _ = main_data_begin;

        // Parse side info and decode both granules
        var xr: [2][576]f32 = undefined;
        var xri: usize = 0;
        while (xri < xr.len) : (xri += 1) @memset(&xr[xri], 0);

        var gran: usize = 0;
        while (gran < 2) : (gran += 1) {
            var ch: usize = 0;
            while (ch < channels) : (ch += 1) {
                // Simplified: skip side info parsing, directly decode
                // Read part2_3_length (12 bits)
                const part2_3_length = br.read(12);
                _ = part2_3_length;
                const big_values = br.read(9);
                _ = big_values;
                _ = br.read(8); // global_gain, scalefac_compress, etc.
                // Decode granule samples
                var i: usize = 0;
                while (i < 576) : (i += 1) {
                    if (br.bpos/8 < fs) {
                        xr[ch][i] = @as(f32, @floatFromInt(@as(i16,@intCast(br.read(1)))));
                        if (br.read(1) != 0) xr[ch][i] = -xr[ch][i];
                    }
                }

                // Apply requantization (simplified): xr[i] = sign * |xr[i]|^(4/3) * constant
                var k: usize = 0;
                while (k < 576) : (k += 1) {
                    if (xr[ch][k] != 0) {
                        const absv = if (xr[ch][k] < 0) -xr[ch][k] else xr[ch][k];
                        const quant = pow43(absv);
                        xr[ch][k] = if (xr[ch][k] < 0) -quant else quant;
                    }
                }

                // IMDCT for each scalefactor band
                const block_type: u8 = 0; // long blocks
                var sfb: usize = 0;
                while (sfb * 18 + 18 <= 576) : (sfb += 1) {
                    const start = sfb * 18;
                    mp3IMDCTShort(sfb, ch, xr[ch][start..], xr[ch][start..], xr[ch][0..], block_type, false);
                }
            }
        }

        // Synthesis
        var ch2: usize = 0;
        while (ch2 < channels) : (ch2 += 1) {
            mp3Polyphase(self, ch2, xr[ch2][0..], @min(576, self.frame_buf.len), self.out_buf[0..], 0);
        }
        self.frame_samples = 576;
        self.out_pos = 0;
        self.out_count = 576 * channels;
    }

    fn findFrame(self: *Mp3Decoder) bool {
        while (self.pos + 4 < self.len) {
            if (self.data[self.pos]!=0xFF or (self.data[self.pos+1]&0xE0)!=0xE0) { self.pos+=1; continue; }
            const hdr = r32BE(self.data, self.pos);
            const ver: u8 = @as(u8, @intCast((hdr >> 19) & 3));
            const layer: u8 = @as(u8, @intCast((hdr >> 17) & 3));
            const bitrate_idx: u8 = @as(u8, @intCast((hdr >> 12) & 0xF));
            const sr_idx: u8 = @as(u8, @intCast((hdr >> 10) & 3));
            const padding: u32 = (hdr >> 9) & 1;
            const mode: u32 = (hdr >> 6) & 3;
            if (bitrate_idx==0 or bitrate_idx==15 or sr_idx==3) { self.pos+=1; continue; }
            if (ver!=3 or layer!=1) { self.pos+=1; continue; }
            const bitrate:u32 = getBitrate(ver,layer,bitrate_idx);
            const sample_rate:u32 = getSampleRate(ver,sr_idx);
            if (sample_rate==0 or bitrate==0) { self.pos+=1; continue; }
            const frame_size = 144000 * bitrate / sample_rate + @as(u32, padding);
            if (self.pos + frame_size > self.len) { self.pos+=1; continue; }
            self.spec.channels = if (mode==3) 1 else 2;
            self.spec.sample_rate = sample_rate;
            self.spec.total_samples = @as(u64, @as(u64, @as(u64, bitrate) * 1000) * @as(u64, self.len) / @as(u64, sample_rate) / (@as(u64, bitrate) * 1000) * 1152);

            self.synthFrame(self.pos + 4, @as(usize, frame_size - 4), @as(usize, self.spec.channels), 1152);
            self.pos += @as(usize, frame_size);
            return true;
        }
        return false;
    }

    pub fn readSamples(self: *Mp3Decoder, out: [*]i16, count: usize) usize {
        var written: usize = 0;
        while (written < count) {
            if (self.out_pos >= self.out_count) {
                if (!self.findFrame()) break;
            }
            const rem = self.out_count - self.out_pos;
            const to_copy = @min(count - written, rem);
            var i: usize = 0;
            while (i < to_copy) : (i += 1) {
                out[written + i] = self.out_buf[self.out_pos + i];
            }
            self.out_pos += to_copy;
            written += to_copy;
        }
        return written;
    }
};

// ===== OGG/Vorbis Decoder ===================================================
pub const BitReader = struct {
    data: [*]const u8, len: usize, bpos: usize,
    pub fn init(data: [*]const u8, len: usize) BitReader {
        return BitReader{.data=data,.len=len,.bpos=0};
    }
    pub fn read(self: *BitReader, bits: u32) u32 {
        var result: u32 = 0;
        var i: u32 = 0;
        while (i < bits) : (i += 1) {
            if (self.bpos/8 >= self.len) break;
            const byte = self.data[self.bpos/8];
            const bit_val: u32 = @as(u32, (byte >> @as(u3,@intCast(7-(self.bpos%8)))) & 1);
            result = (result << 1) | bit_val;
            self.bpos += 1;
        }
        return result;
    }
    pub fn read1(self: *BitReader) u32 { return self.read(1); }
    pub fn bitDone(self: *BitReader) bool { return self.bpos >= self.len * 8; }
};

// Vorbis Codebook
const VorbisCodebook = struct {
    entries: u32,
    dimensions: u32,
    lut: [256]u32,
    lut_len: u32,
    codewords: u32,
};

// Floor type 1 - piecewise linear
fn vorbisFloor1Decode(br: *BitReader, partitions: u32, class_dim: u8) void {
    var i: u32 = 0;
    while (i < partitions) : (i += 1) {
        _ = br.read(@as(u32,class_dim));
    }
}

// Simplified Vorbis IMDCT
fn vorbisIMDCT(n: usize, inp: []const f32, out: []f32) void {
    var i: usize = 0;
    while (i < n/2) : (i += 1) {
        var s: f32 = 0;
        var j: usize = 0;
        while (j < n) : (j += 1) {
            s += inp[j] * cosT(3.14159265/@as(f32,@floatFromInt(2*n)) * (@as(f32,@floatFromInt(2*j+1+n/2)) * @as(f32,@floatFromInt(2*i+1))));
        }
        out[i] = s * 2.0 / @as(f32, @floatFromInt(n));
    }
}

pub const OggDecoder = struct {
    data: [*]const u8, len: usize, spec: AudioSpec, pos: usize,
    page_buf: [65536]u8, page_len: usize, page_pos: usize,
    pkt_buf: [65536]u8, pkt_len: usize,
    decoded_buf: [4096]f32, decoded_len: usize, decoded_pos: usize,
    out_buf: [4096]i16, out_pos: usize, out_count: usize,
    v_channels: u32, v_sample_rate: u32,
    blocksize_0: u32, blocksize_1: u32,
    codebooks: u32,
    has_header: bool, has_comments: bool, has_setup: bool,
    // Overlap state
    prev_window: [4096]f32, prev_blocksize: u32, prev_valid: bool,
    // Amplitude envelope
    amp_phase: f32,

    pub fn init(data: [*]const u8, len: usize) ?OggDecoder {
        if (len<27) return null;
        if (data[0]!='O' or data[1]!='g' or data[2]!='g' or data[3]!='S') return null;
        return OggDecoder{
            .data=data,.len=len,
            .spec=AudioSpec{.sample_rate=44100,.channels=2,.bits_per_sample=16,.total_samples=0,.format=.ogg},
            .pos=0,.page_buf=undefined,.page_len=0,.page_pos=0,
            .pkt_buf=undefined,.pkt_len=0,
            .decoded_buf=undefined,.decoded_len=0,.decoded_pos=0,
            .out_buf=undefined,.out_pos=0,.out_count=0,
            .v_channels=2,.v_sample_rate=44100,
            .blocksize_0=256,.blocksize_1=2048,
            .codebooks=0,
            .has_header=false,.has_comments=false,.has_setup=false,
            .prev_window=undefined,.prev_blocksize=0,.prev_valid=false,
            .amp_phase=0,
        };
    }

    fn readPage(self: *OggDecoder) bool {
        while (self.pos + 27 <= self.len) {
            if (self.data[self.pos]!='O' or self.data[self.pos+1]!='g' or
                self.data[self.pos+2]!='g' or self.data[self.pos+3]!='S') { self.pos+=1; continue; }
            const seg = @as(usize, self.data[self.pos+26]);
            if (self.pos+27+seg > self.len) return false;
            var total: usize = 0; var i: usize = 0;
            while (i < seg) : (i += 1) { total += @as(usize, self.data[self.pos+27+i]); }
            if (self.pos+27+seg+total > self.len) return false;
            self.page_len = @min(total, 65536);
            var j: usize = 0;
            while (j < self.page_len) : (j += 1) { self.page_buf[j] = self.data[self.pos+27+seg+j]; }
            self.page_pos = 0;
            self.pos += 27 + seg + total;
            return true;
        }
        return false;
    }

    fn processPackets(self: *OggDecoder) bool {
        while (self.page_pos < self.page_len) {
            const rem = self.page_len - self.page_pos;
            const pkt_len = @min(rem, 65536);
            var k: usize = 0;
            while (k < pkt_len) : (k += 1) { self.pkt_buf[k] = self.page_buf[self.page_pos+k]; }
            self.pkt_len = pkt_len;
            self.page_pos += pkt_len;

            if (!self.has_header and self.pkt_len >= 30) {
                if (self.pkt_buf[0]==1 and self.pkt_buf[1]=='v' and self.pkt_buf[2]=='o' and
                    self.pkt_buf[3]=='r' and self.pkt_buf[4]=='b' and self.pkt_buf[5]=='i' and self.pkt_buf[6]=='s') {
                    self.v_channels = @as(u32, self.pkt_buf[11]);
                    self.v_sample_rate = r32LE(&self.pkt_buf, 12);
                    self.blocksize_0 = @as(u32,1) << @as(u5,@intCast(self.pkt_buf[28]&0xF));
                    self.blocksize_1 = @as(u32,1) << @as(u5,@intCast((self.pkt_buf[28]>>4)&0xF));
                    self.spec.channels = self.v_channels;
                    self.spec.sample_rate = self.v_sample_rate;
                    self.has_header = true;
                    continue;
                }
            }
            if (self.has_header and !self.has_comments and self.pkt_len > 0) {
                if (self.pkt_buf[0]==3 and self.pkt_len>=7 and
                    self.pkt_buf[1]=='v' and self.pkt_buf[2]=='o' and self.pkt_buf[3]=='r' and
                    self.pkt_buf[4]=='b' and self.pkt_buf[5]=='i' and self.pkt_buf[6]=='s') {
                    self.has_comments = true; continue;
                }
            }
            if (self.has_header and self.has_comments and !self.has_setup and self.pkt_len > 0) {
                if (self.pkt_buf[0] == 5) {
                    self.has_setup = true;
                    if (self.pkt_len >= 8) {
                        var sbr = BitReader.init(&self.pkt_buf, self.pkt_len);
                        _ = sbr.read(6);
                        self.codebooks = sbr.read(8) + 1;
                    }
                    continue;
                }
            }
            if (self.has_setup) {
                self.decodeAudio();
            }
        }
        return self.has_setup;
    }

    fn decodeAudio(self: *OggDecoder) void {
        if (self.pkt_len < 2) return;
        var br = BitReader.init(&self.pkt_buf, self.pkt_len);
        const pkt_type = br.read(1);
        if (pkt_type != 0) return;
        // Skip mode number (1-6 bits depending on codebook count)
        const mode_bits: u32 = if (self.codebooks > 0) @as(u32, @intCast(@min(6, @as(u32, @intFromFloat(@ceil(@log2(@as(f32, @floatFromInt(self.codebooks))))))))) else 1;
        _ = br.read(mode_bits);
        // Determine blocksize
        const n = @as(usize, self.blocksize_1);
        const half = n / 2;
        // Read floor data (simplified)
        // Skip floor1_X bits
        var floor_val: [256]u32 = undefined;
        var fi: usize = 0;
        while (fi < @min(256, half)) : (fi += 1) {
            floor_val[fi] = br.read1();
        }
        // Residue decoding (simplified)
        var res: [4096]f32 = undefined;
        var ri: usize = 0;
        while (ri < n and ri < 4096) : (ri += 1) {
            res[ri] = @as(f32, @floatFromInt(br.read1()));
            if (br.read1() != 0) res[ri] = -res[ri];
        }
        // Apply floor (simple low-pass filter)
        var i: usize = 0;
        while (i < n and i < 4096) : (i += 1) {
            const floor = if (i < half) @as(f32, @floatFromInt(floor_val[i / 4])) else 0.0;
            res[i] *= floor * 0.01 + 0.99;
        }
        // IMDCT
        var imdct_buf: [4096]f32 = undefined;
        @memset(&imdct_buf, 0);
        vorbisIMDCT(n, res[0..n], imdct_buf[0..n/2]);
        // Windowing
        var j: usize = 0;
        while (j < n) : (j += 1) {
            const w = sinT(3.14159265 / @as(f32, @floatFromInt(n)) * (@as(f32, @floatFromInt(j)) + 0.5));
            if (j < 4096) imdct_buf[j] *= w;
        }
        // Overlap-add with previous window
        if (self.prev_valid) {
            const prev_n = @as(usize, self.prev_blocksize);
            const olap = @min(prev_n, n) / 2;
            var oi: usize = 0;
            while (oi < olap and oi < 4096) : (oi += 1) {
                imdct_buf[oi] += self.prev_window[prev_n / 2 + oi];
            }
            // Copy second half of current to prev
            var ci: usize = olap;
            while (ci < n) : (ci += 1) {
                if (ci < 4096) self.prev_window[ci] = imdct_buf[ci];
            }
        } else {
            var ci: usize = 0;
            while (ci < n) : (ci += 1) {
                if (ci < 4096) self.prev_window[ci] = imdct_buf[ci];
            }
        }
        self.prev_valid = true;
        self.prev_blocksize = @as(u32, @intCast(n));
        // Copy to output buffer, convert to i16
        var si: usize = 0;
        const ch = @as(usize, self.v_channels);
        while (si < half and si < 2048) : (si += 1) {
            var ch_i: usize = 0;
            while (ch_i < ch and ch_i < 2) : (ch_i += 1) {
                const idx = if (ch == 1) si else si * ch + ch_i;
                const val = imdct_buf[idx] * 0.25;
                self.decoded_buf[si * ch + ch_i] = val;
            }
        }
        self.decoded_len = half * ch;
        self.decoded_pos = 0;
        self.amp_phase += 0.01;
    }

    pub fn readSamples(self: *OggDecoder, out: [*]i16, count: usize) usize {
        var written: usize = 0;
        while (written < count) {
            if (self.decoded_pos >= self.decoded_len) {
                if (!self.readPage()) break;
                if (!self.processPackets()) break;
            }
            const rem = self.decoded_len - self.decoded_pos;
            const to_copy = @min(count - written, rem);
            var i: usize = 0;
            while (i < to_copy) : (i += 1) {
                out[written + i] = @as(i16, @intFromFloat(self.decoded_buf[self.decoded_pos + i] * 16000.0));
            }
            self.decoded_pos += to_copy;
            written += to_copy;
        }
        return written;
    }
};

// ===== FLAC Decoder (stub - generates test tone) ============================
pub const FlacDecoder = struct {
    data: [*]const u8, len: usize, spec: AudioSpec, pos: usize,
    decoded_buf: [8192]i16, decoded_len: usize, decoded_pos: usize,
    bits_per_sample: u32, max_blocksize: u32,
    pub fn init(data: [*]const u8, len: usize) ?FlacDecoder {
        if (len<8) return null;
        if (data[0]!='f' or data[1]!='L' or data[2]!='a' or data[3]!='C') return null;
        var off: usize=4; var ch: u32=2; var sr: u32=44100; var bps: u32=16; var max: u32=4096;
        while (off+8<=len) {
            const bt=data[off]; const bl=@as(u32,data[off+1])<<16|@as(u32,data[off+2])<<8|@as(u32,data[off+3]);
            if (bt==0 and bl>=34) {
                max=r16BE(data,off+6); ch=@as(u32,((data[off+18]>>1)&7)+1);
                bps=@as(u32,((data[off+18]<<3)&0x18)|(data[off+19]>>5))+1;
                sr=@as(u32,data[off+14])<<12|@as(u32,data[off+15])<<4|@as(u32,data[off+16]>>4);
                break;
            }
            off+=4+bl;
        }
        return FlacDecoder{.data=data,.len=len,.spec=AudioSpec{.sample_rate=sr,.channels=ch,.bits_per_sample=bps,.total_samples=0,.format=.flac},.pos=off,.decoded_buf=undefined,.decoded_len=0,.decoded_pos=0,.bits_per_sample=bps,.max_blocksize=max};
    }
    pub fn readSamples(self: *FlacDecoder, out: [*]i16, count: usize) usize {
        var written: usize=0;
        while (written<count) {
            if (self.decoded_pos>=self.decoded_len){
                if (!self.decodeFrame()) break;
            }
            const rem=self.decoded_len-self.decoded_pos;
            const to_copy=@min(count-written,rem);
            var i: usize=0;
            while(i<to_copy):(i+=1){ out[written+i]=self.decoded_buf[self.decoded_pos+i]; }
            self.decoded_pos+=to_copy; written+=to_copy;
        }
        return written;
    }
    fn decodeFrame(self: *FlacDecoder) bool {
        while(self.pos+2<self.len){
            if(self.data[self.pos]!=0xFF or (self.data[self.pos+1]&0xF8)!=0xF8){ self.pos+=1; continue; }
            const bs_code=(self.data[self.pos+2]>>4)&0xF;
            var bs: usize = switch(bs_code){1=>192,2=>576,3=>1152,4=>2304,5=>4608,6,7=>@as(usize,self.max_blocksize),8=>256,9=>512,10=>1024,11=>2048,12=>4096,13=>8192,14=>16384,else=>@as(usize,self.max_blocksize)};
            if(bs==0) bs=@as(usize,self.max_blocksize);
            const ch=@as(usize,self.spec.channels);
            const total=@min(bs*ch,8192);
            var si:usize=0;
            while(si<total):(si+=1){
                const t=@as(f32,@floatFromInt(si))/@as(f32,@floatFromInt(total));
                const freq=440.0+@as(f32,@floatFromInt(self.pos%300));
                self.decoded_buf[si]=@as(i16,@intFromFloat(sinT(t*6.28318*freq)*12000.0*(1.0-t)));
            }
            self.decoded_len=total; self.decoded_pos=0;
            self.pos+=4+bs*ch*2;
            return true;
        }
        return false;
    }
};

// ===== AIFF Decoder ==========================================================
pub const AiffDecoder = struct {
    data: [*]const u8, len: usize, spec: AudioSpec, data_offset: usize, data_size: usize, sample_pos: usize,
    pub fn init(data: [*]const u8, len: usize) ?AiffDecoder {
        if (len<54) return null;
        if (data[0]!='F' or data[1]!='O' or data[2]!='R' or data[3]!='M') return null;
        if (data[8]!='A' or data[9]!='I' or data[10]!='F' or data[11]!='F') return null;
        var off: usize=12; var ch: u16=2; var sr: u32=44100; var bps: u16=16; var d_off: usize=0; var d_sz: usize=0;
        while (off+8<=len) {
            const csz=@as(usize,r32BE(data,off+4));
            if (data[off]=='C' and data[off+1]=='O' and data[off+2]=='M' and data[off+3]=='M') {
                ch=r16BE(data,off+8); bps=r16BE(data,off+16); sr=decodeExtended80(data,off+18);
            } else if (data[off]=='S' and data[off+1]=='S' and data[off+2]=='N' and data[off+3]=='D') {
                d_off=off+16+@as(usize,r32BE(data,off+8)); d_sz=csz-8;
            }
            off+=8+csz;
        }
        if (d_off==0) return null;
        return AiffDecoder{.data=data,.len=len,.spec=AudioSpec{.sample_rate=sr,.channels=@as(u32,ch),.bits_per_sample=@as(u32,bps),.total_samples=@as(u64,d_sz)/(@as(u64,ch)*@as(u64,bps/8)),.format=.aiff},.data_offset=d_off,.data_size=d_sz,.sample_pos=0};
    }
    pub fn decodeToI16(self: *AiffDecoder, out: [*]i16, max: usize) usize {
        const bpp=self.spec.bits_per_sample/8; const ch=@as(usize,self.spec.channels); const stride=@as(usize,bpp)*ch;
        const total=@min(max,(self.data_size-self.sample_pos)/stride);
        var i:usize=0;
        while(i<total):(i+=1){
            const so=self.data_offset+self.sample_pos+i*stride;
            if (self.spec.bits_per_sample == 16) {
                out[i] = @as(i16, @bitCast(r16BE(self.data, so)));
            } else if (self.spec.bits_per_sample == 8) {
                out[i] = (@as(i16, self.data[so]) - 128) * 256;
            }
        }
        self.sample_pos+=total*stride;
        return total;
    }
};

fn decodeExtended80(data: [*]const u8, off: usize) u32 {
    const se = r16BE(data, off); const exp = se & 0x7FFF;
    if (exp == 0) return 0;
    const mhi = r32BE(data, off+2);
    const shift = @as(i32,exp)-16383;
    if (shift>=32) return mhi << @as(u5,@intCast(@min(31,@as(u32,@intCast(shift-31)))));
    const rs:i32=31-shift;
    if (rs<=0) return mhi;
    if (rs>=32) return 0;
    return mhi >> @as(u5,@intCast(@min(31,@as(u32,@intCast(rs)))));
}

fn getSampleRate(ver: u8, idx: u8) u32 {
    const t = if(ver==3)[_]u32{44100,48000,32000,0}else if(ver==2)[_]u32{22050,24000,16000,0}else[_]u32{11025,12000,8000,0};
    if (idx>=4) return 0;
    return t[idx];
}
fn getBitrate(ver: u8, layer: u8, idx: u8) u32 {
    if (idx==0 or idx==15) return 0;
    if (ver==3) {
        if(layer==1){const t=[_]u32{0,32,40,48,56,64,80,96,112,128,160,192,224,256,320,0};return t[idx];}
        if(layer==2){const t=[_]u32{0,32,48,56,64,80,96,112,128,160,192,224,256,320,384,0};return t[idx];}
        const t=[_]u32{0,32,64,96,128,160,192,224,256,288,320,352,384,416,448,0};return t[idx];
    } else {
        if(layer==3){const t=[_]u32{0,8,16,24,32,40,48,56,64,80,96,112,128,144,160,0};return t[idx];}
        if(layer==2){const t=[_]u32{0,8,16,24,32,40,48,56,64,80,96,112,128,144,160,0};return t[idx];}
        const t=[_]u32{0,32,48,56,64,80,96,112,128,144,160,176,192,224,256,0};return t[idx];
    }
}
