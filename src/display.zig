const gfx = @import("render.zig");
const sys = @import("sys.zig");
const x11_mod = @import("x11.zig");
const wl_mod = @import("wayland.zig");

pub const Event = union(enum) {
    key_press: u8,
    key_release: u8,
    mouse_move: struct { x: i32, y: i32 },
    mouse_down: struct { x: i32, y: i32, btn: u8 },
    mouse_up: struct { x: i32, y: i32, btn: u8 },
    close,
    resize: struct { w: u32, h: u32 },
    expose,
};

pub const DisplayBackend = struct {
    mode: u8,
    xconn: x11_mod.X11Conn,
    wlconn: wl_mod.WlConn,
    fb: *gfx.Framebuffer,

    pub fn init(fb: *gfx.Framebuffer) DisplayBackend {
        const conn = x11_mod.x11Open(0);
        if (conn) |c| {
            var db = DisplayBackend{ .mode = 1, .xconn = c, .wlconn = undefined, .fb = fb };
            db.xconn.createWindow(0, 0, @as(u16, @intCast(fb.width)), @as(u16, @intCast(fb.height)));
            db.xconn.setTitle("dhjsjs GUI");
            db.xconn.createGC();
            db.xconn.mapWindow();
            db.xconn.selectInput(2 | 16 | 32 | 64 | 2048);
            return db;
        }
        var wl = wl_mod.WlConn.open(0);
        if (wl) |*w_ptr| {
            if (w_ptr.createSurface(fb.width, fb.height)) {
                const db = DisplayBackend{ .mode = 10, .xconn = undefined, .wlconn = w_ptr.*, .fb = fb };
                return db;
            }
        }
        const ffd = sys.open("/dev/fb0\x00", sys.O_RDWR, 0);
        if (ffd >= 0) { sys.close(ffd); return DisplayBackend{ .mode = 2, .xconn = undefined, .wlconn = undefined, .fb = fb }; }
        return DisplayBackend{ .mode = 3, .xconn = undefined, .wlconn = undefined, .fb = fb };
    }

    pub fn present(self: *DisplayBackend) void {
        if (self.mode == 1) {
            self.xconn.putImage(self.fb.pixels, self.fb.width, self.fb.height);
        } else if (self.mode == 10) {
            self.wlconn.putImage(self.fb.pixels, self.fb.width, self.fb.height);
            self.wlconn.commit();
        }
    }

    pub fn pollEvent(self: *DisplayBackend) ?Event {
        if (self.mode == 1) {
            var pfd: [1]sys.PollFd = undefined;
            pfd[0] = sys.PollFd{ .fd = self.xconn.fd, .events = sys.POLLIN, .revents = 0 };
            if (sys.poll(&pfd, 1, 15) > 0) {
                const ev = self.xconn.nextEvent() orelse return null;
                switch (ev.type) {
                    2 => return Event{ .key_press = @as(u8, @intCast(ev.keycode)) },
                    3 => return Event{ .key_release = @as(u8, @intCast(ev.keycode)) },
                    4 => return Event{ .mouse_down = .{ .x = ev.event_x, .y = ev.event_y, .btn = ev.detail } },
                    5 => return Event{ .mouse_up = .{ .x = ev.event_x, .y = ev.event_y, .btn = ev.detail } },
                    6 => return Event{ .mouse_move = .{ .x = ev.event_x, .y = ev.event_y } },
                    12 => return Event.expose,
                    33 => return Event.close,
                    else => return null,
                }
            }
        } else if (self.mode == 10) {
            self.wlconn.dispatchEvents();
        }
        return null;
    }

    pub fn close(self: *DisplayBackend) void {
        if (self.mode == 1) self.xconn.close();
        if (self.mode == 10) self.wlconn.close();
    }
};
