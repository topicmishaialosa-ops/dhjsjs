const sys = @import("sys.zig");
const audio = @import("audio.zig");

pub const PLAYBACK_BUF_SIZE: usize = 8192;
pub const DECODE_BUF_SIZE: usize = 65536;

pub const PlayerState = enum(u8) {
    stopped,
    playing,
    paused,
    loading,
    err,
};

pub const Player = struct {
    state: PlayerState,
    dsp_fd: i32,
    file_fd: i32,
    file_data: [*]u8,
    file_size: usize,
    mem_ptr: ?*anyopaque,
    mem_size: usize,

    format: audio.AudioFormat,
    spec: audio.AudioSpec,

    wav_dec: ?audio.WavDecoder,
    mp3_dec: ?audio.Mp3Decoder,
    ogg_dec: ?audio.OggDecoder,
    flac_dec: ?audio.FlacDecoder,
    aiff_dec: ?audio.AiffDecoder,

    pcm_buf: [PLAYBACK_BUF_SIZE]i16,
    pcm_count: usize,
    pcm_pos: usize,

    sample_rate: u32,
    channels: u32,
    total_samples: u64,
    current_sample: u64,
    volume: f32,
    loop_enabled: bool,
    muted: bool,

    pub fn init() Player {
        return Player{
            .state = .stopped,
            .dsp_fd = -1,
            .file_fd = -1,
            .file_data = undefined,
            .file_size = 0,
            .mem_ptr = null,
            .mem_size = 0,
            .format = .unknown,
            .spec = audio.AudioSpec{
                .sample_rate = 44100,
                .channels = 2,
                .bits_per_sample = 16,
                .total_samples = 0,
                .format = .unknown,
            },
            .wav_dec = null,
            .mp3_dec = null,
            .ogg_dec = null,
            .flac_dec = null,
            .aiff_dec = null,
            .pcm_buf = [_]i16{0} ** PLAYBACK_BUF_SIZE,
            .pcm_count = 0,
            .pcm_pos = 0,
            .sample_rate = 44100,
            .channels = 2,
            .total_samples = 0,
            .current_sample = 0,
            .volume = 1.0,
            .loop_enabled = false,
            .muted = false,
        };
    }

    pub fn loadFile(self: *Player, path: [*]const u8) bool {
        self.unload();

        const fd = sys.open(path, 0, 0);
        if (fd < 0) {
            self.state = .err;
            return false;
        }

        var stat: sys.Stat = undefined;
        if (sys.fstat(fd, &stat) < 0) {
            sys.close(fd);
            self.state = .err;
            return false;
        }

        const size = @as(usize, @intCast(stat.size));
        if (size == 0) {
            sys.close(fd);
            self.state = .err;
            return false;
        }

        const ptr = sys.mmap(null, size, sys.PROT_READ, sys.MAP_SHARED, fd, 0) orelse {
            sys.close(fd);
            self.state = .err;
            return false;
        };

        self.file_fd = fd;
        self.file_data = @ptrCast(@alignCast(ptr));
        self.file_size = size;
        self.mem_ptr = ptr;
        self.mem_size = size;
        self.state = .loading;

        self.format = audio.detectFormat(self.file_data, self.file_size);

        return self.initDecoder();
    }

    fn initDecoder(self: *Player) bool {
        switch (self.format) {
            .wav => {
                if (audio.WavDecoder.init(self.file_data, self.file_size)) |dec| {
                    self.wav_dec = dec;
                    self.spec = dec.spec;
                    self.sample_rate = dec.spec.sample_rate;
                    self.channels = dec.spec.channels;
                    self.total_samples = dec.spec.total_samples;
                    self.state = .stopped;
                    return true;
                }
            },
            .mp3 => {
                if (audio.Mp3Decoder.init(self.file_data, self.file_size)) |dec| {
                    self.mp3_dec = dec;
                    self.spec = dec.spec;
                    self.sample_rate = dec.spec.sample_rate;
                    self.channels = dec.spec.channels;
                    self.state = .stopped;
                    return true;
                }
            },
            .ogg => {
                if (audio.OggDecoder.init(self.file_data, self.file_size)) |dec| {
                    self.ogg_dec = dec;
                    self.spec = dec.spec;
                    self.sample_rate = dec.spec.sample_rate;
                    self.channels = dec.spec.channels;
                    self.state = .stopped;
                    return true;
                }
            },
            .flac => {
                if (audio.FlacDecoder.init(self.file_data, self.file_size)) |dec| {
                    self.flac_dec = dec;
                    self.spec = dec.spec;
                    self.sample_rate = dec.spec.sample_rate;
                    self.channels = dec.spec.channels;
                    self.total_samples = dec.spec.total_samples;
                    self.state = .stopped;
                    return true;
                }
            },
            .aiff => {
                if (audio.AiffDecoder.init(self.file_data, self.file_size)) |dec| {
                    self.aiff_dec = dec;
                    self.spec = dec.spec;
                    self.sample_rate = dec.spec.sample_rate;
                    self.channels = dec.spec.channels;
                    self.total_samples = dec.spec.total_samples;
                    self.state = .stopped;
                    return true;
                }
            },
            else => {},
        }
        self.state = .err;
        return false;
    }

    pub fn openDsp(self: *Player) bool {
        const dsp_fd = sys.open("/dev/dsp\x00", sys.O_RDWR, 0);
        if (dsp_fd < 0) {
            self.dsp_fd = -1;
            return false;
        }
        self.dsp_fd = dsp_fd;

        var fmt_val = sys.AFMT_S16_LE;
        _ = sys.ioctl(self.dsp_fd, sys.SNDCTL_DSP_SETFMT, @intFromPtr(&fmt_val));

        var ch_val: i32 = @intCast(self.channels);
        _ = sys.ioctl(self.dsp_fd, sys.SNDCTL_DSP_CHANNELS, @intFromPtr(&ch_val));

        var sr_val: i32 = @intCast(self.sample_rate);
        _ = sys.ioctl(self.dsp_fd, sys.SNDCTL_DSP_SPEED, @intFromPtr(&sr_val));

        return true;
    }

    pub fn play(self: *Player) bool {
        if (self.state != .stopped and self.state != .paused) return false;

        if (self.dsp_fd < 0) {
            if (!self.openDsp()) return false;
        }

        self.state = .playing;
        return true;
    }

    pub fn pause(self: *Player) void {
        if (self.state == .playing) {
            self.state = .paused;
        }
    }

    pub fn stop(self: *Player) void {
        if (self.state == .playing or self.state == .paused) {
            self.state = .stopped;
            self.current_sample = 0;
            self.pcm_count = 0;
            self.pcm_pos = 0;
        }
    }

    pub fn seek(self: *Player, position: f32) void {
        if (self.total_samples == 0) return;
        const target = @as(u64, @intFromFloat(@as(f64, position) * @as(f64, @floatFromInt(self.total_samples))));
        self.current_sample = target;
        self.pcm_count = 0;
        self.pcm_pos = 0;
    }

    pub fn getPosition(self: *Player) f32 {
        if (self.total_samples == 0) return 0;
        return @as(f32, @floatFromInt(self.current_sample)) / @as(f32, @floatFromInt(self.total_samples));
    }

    pub fn getDurationSeconds(self: *Player) f32 {
        if (self.sample_rate == 0) return 0;
        return @as(f32, @floatFromInt(self.total_samples)) / @as(f32, @floatFromInt(self.sample_rate));
    }

    pub fn getCurrentSeconds(self: *Player) f32 {
        if (self.sample_rate == 0) return 0;
        return @as(f32, @floatFromInt(self.current_sample)) / @as(f32, @floatFromInt(self.sample_rate));
    }

    pub fn update(self: *Player) bool {
        if (self.state != .playing) return true;
        if (self.dsp_fd < 0) return false;

        const samples_to_read: usize = @min(PLAYBACK_BUF_SIZE, 4096);
        var decoded: usize = 0;

        switch (self.format) {
            .wav => {
                if (self.wav_dec) |*dec| {
                    decoded = dec.decodeToI16(&self.pcm_buf, samples_to_read);
                    self.current_sample += decoded;
                }
            },
            .mp3 => {
                if (self.mp3_dec) |*dec| {
                    decoded = dec.readSamples(&self.pcm_buf, samples_to_read);
                    self.current_sample += decoded;
                }
            },
            .ogg => {
                if (self.ogg_dec) |*dec| {
                    decoded = dec.readSamples(&self.pcm_buf, samples_to_read);
                    self.current_sample += decoded;
                }
            },
            .flac => {
                if (self.flac_dec) |*dec| {
                    decoded = dec.readSamples(&self.pcm_buf, samples_to_read);
                    self.current_sample += decoded;
                }
            },
            .aiff => {
                if (self.aiff_dec) |*dec| {
                    decoded = dec.decodeToI16(&self.pcm_buf, samples_to_read);
                    self.current_sample += decoded;
                }
            },
            else => return false,
        }

        if (decoded == 0) {
            if (self.loop_enabled) {
                self.current_sample = 0;
                self.pcm_count = 0;
                self.pcm_pos = 0;
                _ = self.initDecoder();
                return true;
            }
            self.state = .stopped;
            return false;
        }

        if (self.volume < 1.0 or self.muted) {
            var i: usize = 0;
            while (i < decoded) : (i += 1) {
                if (self.muted) {
                    self.pcm_buf[i] = 0;
                } else {
                    self.pcm_buf[i] = @as(i16, @intFromFloat(@as(f32, self.pcm_buf[i]) * self.volume));
                }
            }
        }

        const byte_count = decoded * 2;
        const written = sys.write(self.dsp_fd, @ptrCast(&self.pcm_buf), byte_count);
        return written > 0;
    }

    pub fn setVolume(self: *Player, vol: f32) void {
        self.volume = @max(0.0, @min(1.0, vol));
    }

    pub fn toggleMute(self: *Player) void {
        self.muted = !self.muted;
    }

    pub fn toggleLoop(self: *Player) void {
        self.loop_enabled = !self.loop_enabled;
    }

    pub fn unload(self: *Player) void {
        self.stop();
        if (self.dsp_fd >= 0) {
            sys.close(self.dsp_fd);
            self.dsp_fd = -1;
        }
        if (self.mem_ptr) |ptr| {
            sys.munmap(ptr, self.mem_size);
            self.mem_ptr = null;
            self.mem_size = 0;
        }
        if (self.file_fd >= 0) {
            sys.close(self.file_fd);
            self.file_fd = -1;
        }
        self.wav_dec = null;
        self.mp3_dec = null;
        self.ogg_dec = null;
        self.flac_dec = null;
        self.aiff_dec = null;
        self.format = .unknown;
        self.file_size = 0;
        self.state = .stopped;
    }

    pub fn getFormatName(self: *Player) []const u8 {
        return switch (self.format) {
            .wav => "WAV",
            .mp3 => "MP3",
            .ogg => "OGG",
            .flac => "FLAC",
            .aiff => "AIFF",
            else => "Unknown",
        };
    }

    pub fn getStateName(self: *Player) []const u8 {
        return switch (self.state) {
            .stopped => "Stopped",
            .playing => "Playing",
            .paused => "Paused",
            .loading => "Loading",
            .err => "Error",
        };
    }
};

pub export fn playFile(path: [*:0]const u8) u8 {
    var p = Player.init();
    if (!p.loadFile(path)) return 0;
    if (!p.openDsp()) return 0;
    if (!p.play()) return 0;
    while (p.update()) {}
    return 1;
}
