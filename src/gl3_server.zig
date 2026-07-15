// ============================================================================
// gl3_server.zig — GL3 rendering server for dhjsjs games
// Reads commands from stdin, renders via OpenGL 3.3, sends events to stdout
// Protocol: fixed 24-byte commands, 16-byte event responses
// ============================================================================

const sys = @import("sys.zig");
const gl3 = @import("gl3.zig");

// Command types (sent from dhjsjs program to server via stdin)
const CMD_INIT: u8 = 1; // (w:u32, h:u32)
const CMD_DEINIT: u8 = 2;
const CMD_BEGIN_FRAME: u8 = 3;
const CMD_END_FRAME: u8 = 4;
const CMD_FILL_RECT: u8 = 10; // (x:i32, y:i32, w:i32, h:i32, color:u32)
const CMD_FILL_GRAD_H: u8 = 11; // (x, y, w, h, c1, c2)
const CMD_FILL_GRAD_V: u8 = 12;
const CMD_DRAW_BORDER: u8 = 13; // (x, y, w, h, color, thickness)
const CMD_FILL_ROUNDED: u8 = 14; // (x, y, w, h, r, color)
const CMD_DRAW_TEXT: u8 = 20; // (x:i32, y:i32, len:u32, color:u32, scale_bits:u32, + text bytes)
const CMD_FLUSH: u8 = 30;
const CMD_SLEEP: u8 = 40; // (ms:u32)
const CMD_PING: u8 = 255; // respond with PONG

// Response types (sent from server to dhjsjs program via stdout)
const RESP_EVENT: u8 = 1; // (type:u32, data:u64)
const RESP_PONG: u8 = 255;

// Event types in response
const EVT_NONE: u32 = 0;
const EVT_KEY_PRESS: u32 = 1;
const EVT_KEY_RELEASE: u32 = 2;
const EVT_MOUSE_DOWN: u32 = 3;
const EVT_MOUSE_UP: u32 = 4;
const EVT_MOUSE_MOVE: u32 = 5;
const EVT_CLOSE: u32 = 6;
const EVT_RESIZE: u32 = 7;

fn readExact(fd: i32, buf: []u8) bool {
    var off: usize = 0;
    while (off < buf.len) {
        const n = sys.read(fd, buf.ptr + off, buf.len - off);
        if (n <= 0) return false;
        off += @intCast(n);
    }
    return true;
}

fn writeAll(fd: i32, data: []const u8) void {
    var off: usize = 0;
    while (off < data.len) {
        const n = sys.write(fd, data.ptr + off, data.len - off);
        if (n <= 0) break;
        off += @intCast(n);
    }
}

fn readU32(buf: []const u8, off: usize) u32 {
    return @as(u32, buf[off]) | (@as(u32, buf[off + 1]) << 8) | (@as(u32, buf[off + 2]) << 16) | (@as(u32, buf[off + 3]) << 24);
}

fn readI32(buf: []const u8, off: usize) i32 {
    return @bitCast(readU32(buf, off));
}

fn writeU32(buf: []u8, off: usize, val: u32) void {
    buf[off] = @truncate(val);
    buf[off + 1] = @truncate(val >> 8);
    buf[off + 2] = @truncate(val >> 16);
    buf[off + 3] = @truncate(val >> 24);
}

fn writeU64(buf: []u8, off: usize, val: u64) void {
    writeU32(buf, off, @truncate(val));
    writeU32(buf, off + 4, @truncate(val >> 32));
}

fn sendEvent(out_fd: i32, evt_type: u32, data: u64) void {
    var resp: [16]u8 = .{0} ** 16;
    resp[0] = RESP_EVENT;
    writeU32(&resp, 4, evt_type);
    writeU64(&resp, 8, data);
    writeAll(out_fd, &resp);
}

pub fn main() !void {
    // stdin = commands from dhjsjs program
    // stdout = event responses to dhjsjs program
    const in_fd = sys.STDIN;
    const out_fd = sys.STDOUT;

    var running = true;

    while (running) {
        var cmd: [24]u8 = undefined;
        if (!readExact(in_fd, &cmd)) break;

        const cmd_type = cmd[0];

        switch (cmd_type) {
            CMD_INIT => {
                const w = readU32(&cmd, 4);
                const h = readU32(&cmd, 8);
                const ok = gl3.init(w, h);
                var resp: [16]u8 = .{0} ** 16;
                resp[0] = 1; // success flag
                resp[4] = if (ok) 1 else 0;
                writeAll(out_fd, &resp);
            },
            CMD_DEINIT => {
                gl3.deinit();
            },
            CMD_BEGIN_FRAME => {
                gl3.beginFrame();
            },
            CMD_END_FRAME => {
                gl3.endFrame();
            },
            CMD_FILL_RECT => {
                const x = readI32(&cmd, 4);
                const y = readI32(&cmd, 8);
                const w = readI32(&cmd, 12);
                const h = readI32(&cmd, 16);
                const color = readU32(&cmd, 20);
                gl3.fillRect(x, y, w, h, color);
            },
            CMD_FILL_GRAD_H => {
                const x = readI32(&cmd, 4);
                const y = readI32(&cmd, 8);
                const w = readI32(&cmd, 12);
                const h = readI32(&cmd, 16);
                const c1 = readU32(&cmd, 20);
                // Need extended command for 6 params — use second read
                var cmd2: [24]u8 = undefined;
                if (readExact(in_fd, &cmd2)) {
                    const c2 = readU32(&cmd2, 4);
                    gl3.fillGradientH(x, y, w, h, c1, c2);
                }
            },
            CMD_FILL_GRAD_V => {
                const x = readI32(&cmd, 4);
                const y = readI32(&cmd, 8);
                const w = readI32(&cmd, 12);
                const h = readI32(&cmd, 16);
                const c1 = readU32(&cmd, 20);
                var cmd2: [24]u8 = undefined;
                if (readExact(in_fd, &cmd2)) {
                    const c2 = readU32(&cmd2, 4);
                    gl3.fillGradientV(x, y, w, h, c1, c2);
                }
            },
            CMD_DRAW_BORDER => {
                const x = readI32(&cmd, 4);
                const y = readI32(&cmd, 8);
                const w = readI32(&cmd, 12);
                const h = readI32(&cmd, 16);
                const color = readU32(&cmd, 20);
                var cmd2: [24]u8 = undefined;
                if (readExact(in_fd, &cmd2)) {
                    const thickness = readI32(&cmd2, 4);
                    gl3.drawBorder(x, y, w, h, color, thickness);
                }
            },
            CMD_FILL_ROUNDED => {
                const x = readI32(&cmd, 4);
                const y = readI32(&cmd, 8);
                const w = readI32(&cmd, 12);
                const h = readI32(&cmd, 16);
                const color = readU32(&cmd, 20);
                var cmd2: [24]u8 = undefined;
                if (readExact(in_fd, &cmd2)) {
                    const r = readI32(&cmd2, 4);
                    gl3.fillRoundedRect(x, y, w, h, r, color);
                }
            },
            CMD_DRAW_TEXT => {
                const x = readI32(&cmd, 4);
                const y = readI32(&cmd, 8);
                const text_len = readU32(&cmd, 12);
                const color = readU32(&cmd, 16);
                const scale_bits = readU32(&cmd, 20);
                const scale: f32 = @bitCast(scale_bits);
                if (text_len > 0 and text_len < 1024) {
                    var text_buf: [1024]u8 = undefined;
                    if (readExact(in_fd, text_buf[0..text_len])) {
                        gl3.drawText(x, y, text_buf[0..text_len], color, scale);
                    }
                }
            },
            CMD_FLUSH => {
                gl3.flush();
            },
            CMD_SLEEP => {
                const ms = readU32(&cmd, 4);
                var ts: sys.Timespec = .{ .sec = @intCast(ms / 1000), .nsec = @intCast((ms % 1000) * 1_000_000) };
                _ = sys.nanosleep(&ts, null);
            },
            CMD_PING => {
                var resp: [16]u8 = .{0} ** 16;
                resp[0] = RESP_PONG;
                writeAll(out_fd, &resp);
            },
            else => {},
        }

        // After each command, poll for events and send them
        if (gl3.isActive()) {
            while (gl3.pollEvent()) |ev| {
                switch (ev) {
                    .close => { sendEvent(out_fd, EVT_CLOSE, 0); running = false; break; },
                    .key_press => |kc| sendEvent(out_fd, EVT_KEY_PRESS, kc),
                    .key_release => |kc| sendEvent(out_fd, EVT_KEY_RELEASE, kc),
                    .mouse_down => |md| sendEvent(out_fd, EVT_MOUSE_DOWN, (@as(u64, @intCast(md.x)) & 0xFFFF) | (@as(u64, @intCast(md.y)) << 16)),
                    .mouse_up => |md| sendEvent(out_fd, EVT_MOUSE_UP, (@as(u64, @intCast(md.x)) & 0xFFFF) | (@as(u64, @intCast(md.y)) << 16)),
                    .mouse_move => |md| sendEvent(out_fd, EVT_MOUSE_MOVE, (@as(u64, @intCast(md.x)) & 0xFFFF) | (@as(u64, @intCast(md.y)) << 16)),
                    .resize => |sz| sendEvent(out_fd, EVT_RESIZE, (@as(u64, sz.w) & 0xFFFF) | (@as(u64, sz.h) << 16)),
                }
            }
        }
    }
}
