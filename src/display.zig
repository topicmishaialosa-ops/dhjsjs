const gfx = @import("render.zig");
const sys = @import("sys.zig");
const x11_mod = @import("x11.zig");
const wl_mod = @import("wayland.zig");
const w32_mod = @import("win32.zig");

pub const Event = sys.Event;

const X11_EVENT_MASK: u32 =
    1 |      // KeyPress
    2 |      // KeyRelease
    4 |      // ButtonPress
    8 |      // ButtonRelease
    64 |     // PointerMotion
    32768 |  // Exposure
    131072; // StructureNotify

pub const DisplayBackend = struct {
    mode: u8,
    xconn: x11_mod.X11Conn,
    wlconn: wl_mod.WlConn,
    w32: w32_mod.Win32Display,
    fb: *gfx.Framebuffer,

    pub fn init(fb: *gfx.Framebuffer) DisplayBackend {
        const conn = x11_mod.x11Open(0);
        if (conn) |c| {
            var db = DisplayBackend{ .mode = 1, .xconn = c, .wlconn = undefined, .w32 = undefined, .fb = fb };
            db.xconn.createWindow(0, 0, @as(u16, @intCast(fb.width)), @as(u16, @intCast(fb.height)));
            db.xconn.setTitle("dhjsjs GUI");
            db.xconn.createGC();
            db.xconn.mapWindow();
            db.xconn.selectInput(X11_EVENT_MASK);
            return db;
        }
        var wl = wl_mod.WlConn.open(0);
        if (wl) |*w_ptr| {
            if (w_ptr.createSurface(fb.width, fb.height)) {
                const db = DisplayBackend{ .mode = 10, .xconn = undefined, .wlconn = w_ptr.*, .w32 = undefined, .fb = fb };
                return db;
            }
        }
        if (sys.is_windows) {
            const w32d = w32_mod.Win32Display.init(fb) orelse return DisplayBackend{ .mode = 3, .xconn = undefined, .wlconn = undefined, .w32 = undefined, .fb = fb };
            return DisplayBackend{ .mode = 20, .xconn = undefined, .wlconn = undefined, .w32 = w32d, .fb = fb };
        }
        const ffd = sys.open("/dev/fb0\x00", sys.O_RDWR, 0);
        if (ffd >= 0) { sys.close(ffd); return DisplayBackend{ .mode = 2, .xconn = undefined, .wlconn = undefined, .w32 = undefined, .fb = fb }; }
        return DisplayBackend{ .mode = 3, .xconn = undefined, .wlconn = undefined, .w32 = undefined, .fb = fb };
    }

    pub fn present(self: *DisplayBackend) void {
        if (self.mode == 1) {
            self.xconn.putImage(self.fb.pixels, self.fb.width, self.fb.height);
        } else if (self.mode == 10) {
            self.wlconn.putImage(self.fb.pixels, self.fb.width, self.fb.height);
            self.wlconn.commit();
        } else if (self.mode == 20) {
            self.w32.present();
        }
    }

    pub fn presentCanvas(self: *DisplayBackend, canvas: *gfx.Canvas) void {
        if (self.mode == 1) {
            if (canvas.xconn == null) canvas.setNative(&self.xconn);
            canvas.flush();
        } else {
            self.present();
            canvas.resetDirty();
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
                     4 => {
                         if (ev.detail == 4) return Event{ .scroll = .{ .dx = 0, .dy = 1 } };
                         if (ev.detail == 5) return Event{ .scroll = .{ .dx = 0, .dy = -1 } };
                         if (ev.detail == 6) return Event{ .scroll = .{ .dx = -1, .dy = 0 } };
                         if (ev.detail == 7) return Event{ .scroll = .{ .dx = 1, .dy = 0 } };
                         const btn: u8 = if (ev.detail == 8) 4 else if (ev.detail == 9) 5 else ev.detail;
                         return Event{ .mouse_down = .{ .x = ev.event_x, .y = ev.event_y, .btn = btn } };
                     },
                     5 => {
                         if (ev.detail == 4) return null;
                         if (ev.detail == 5) return null;
                         if (ev.detail == 6) return null;
                         if (ev.detail == 7) return null;
                         const btn: u8 = if (ev.detail == 8) 4 else if (ev.detail == 9) 5 else ev.detail;
                         return Event{ .mouse_up = .{ .x = ev.event_x, .y = ev.event_y, .btn = btn } };
                     },
                     6 => return Event{ .mouse_move = .{ .x = ev.event_x, .y = ev.event_y } },
                     12 => return Event.expose,
                     33 => return Event.close,
                     else => return null,
                 }
            }
        } else if (self.mode == 10) {
            return self.wlconn.pollEvent();
        } else if (self.mode == 20) {
            return self.w32.pollEvent();
        }
        return null;
    }

    pub fn getX11Conn(self: *DisplayBackend) ?*x11_mod.X11Conn {
        if (self.mode == 1) return &self.xconn;
        return null;
    }

    pub fn close(self: *DisplayBackend) void {
        if (self.mode == 1) self.xconn.close();
        if (self.mode == 10) self.wlconn.close();
        if (self.mode == 20) self.w32.close();
    }
};
