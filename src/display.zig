const gfx = @import("render.zig");
const sys = @import("sys.zig");
const x11_mod = @import("x11.zig");
const wl_mod = @import("wayland.zig");

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
            db.xconn.setTitle("dhjsjs IDE");
            db.xconn.createGC();
            db.xconn.mapWindow();
            return db;
        }
        const wl = wl_mod.WlConn.open(0);
        if (wl) |w| {
            if (w.createSurface(fb.width, fb.height)) {
                var db = DisplayBackend{ .mode = 10, .xconn = undefined, .wlconn = w, .fb = fb };
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

    pub fn pollEvent(self: *DisplayBackend) ?u8 {
        if (self.mode == 1) {
            var pfd: [1]sys.PollFd = undefined;
            pfd[0] = sys.PollFd{ .fd = self.xconn.fd, .events = sys.POLLIN, .revents = 0 };
            if (sys.poll(&pfd, 1, 30) > 0) {
                const ev = self.xconn.nextEvent() orelse return null;
                if (ev.type == 2) return @as(u8, @intCast(ev.keycode));
                if (ev.type == 3) return 0xFE;
                if (ev.type == 33) return 0xFF;
                if (ev.type == 12) return 0xFD;
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
