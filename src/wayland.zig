const sys = @import("sys.zig");

fn write16(buf: []u8, off: usize, v: u16) void {
    buf[off] = @as(u8, @truncate(v));
    buf[off + 1] = @as(u8, @truncate(v >> 8));
}

fn write32(buf: []u8, off: usize, v: u32) void {
    buf[off] = @as(u8, @truncate(v));
    buf[off + 1] = @as(u8, @truncate(v >> 8));
    buf[off + 2] = @as(u8, @truncate(v >> 16));
    buf[off + 3] = @as(u8, @truncate(v >> 24));
}

fn read32(buf: []const u8, off: usize) u32 {
    return @as(u32, buf[off]) | (@as(u32, buf[off + 1]) << 8) | (@as(u32, buf[off + 2]) << 16) | (@as(u32, buf[off + 3]) << 24);
}

fn writeStr(fd: i32, s: []const u8) void {
    var off: usize = 0;
    while (off < s.len) { const n = sys.write(fd, s.ptr + off, s.len - off); if (n <= 0) break; off += @as(usize, @intCast(n)); }
}

fn readExact(fd: i32, buf: []u8) bool {
    var off: usize = 0;
    while (off < buf.len) { const n = sys.read(fd, buf.ptr + off, buf.len - off); if (n <= 0) return false; off += @as(usize, @intCast(n)); }
    return true;
}

pub const WlConn = struct {
    fd: i32,
    display_id: u32,
    registry_id: u32,
    compositor_id: u32,
    shm_id: u32,
    seat_id: u32,
    wm_base_id: u32,
    surface_id: u32,
    shell_surface_id: u32,
    shm_pool_id: u32,
    buffer_id: u32,
    callback_id: u32,
    shm_ptr: [*]u8,
    shm_size: usize,
    w: u32,
    h: u32,
    running: bool,
    shift: bool,

    pub fn open(display_num: i32) ?WlConn {
        var buf: [256]u8 = undefined;
        const runtime = sys.getenv("XDG_RUNTIME_DIR", buf[0..]) orelse return null;
        var path: [128]u8 = undefined;
        var pi: usize = 0;
        for (runtime) |c| { path[pi] = c; pi += 1; if (pi >= 120) break; }
        const suffix = if (display_num == 0) "/wayland-0" else "/wayland-";
        for (suffix) |c| { path[pi] = c; pi += 1; if (pi >= 126) break; }
        if (display_num != 0) {
            var dn = display_num;
            if (dn > 9) { path[pi] = @as(u8, @intCast(@divTrunc(dn, 10) + '0')); pi += 1; dn = @rem(dn, 10); }
            path[pi] = @as(u8, @intCast(dn + '0')); pi += 1;
        }
        path[pi] = 0;

        const fd = sys.socket(sys.AF_UNIX, sys.SOCK_STREAM, 0);
        if (fd < 0) return null;
        var addr: [128]u8 = undefined;
        addr[0] = @as(u8, @intCast(sys.AF_UNIX));
        addr[1] = 0;
        var si: usize = 0;
        while (si <= pi) : (si += 1) addr[2 + si] = path[si];
        if (sys.connect(fd, &addr, @as(u32, @intCast(2 + pi + 1))) < 0) { sys.close(fd); return null; }

        var conn = WlConn{
            .fd = fd, .display_id = 1, .registry_id = 2, .compositor_id = 0,
            .shm_id = 0, .seat_id = 0, .wm_base_id = 0, .surface_id = 0,
            .shell_surface_id = 0, .shm_pool_id = 0, .buffer_id = 0,
            .callback_id = 0, .shm_ptr = undefined, .shm_size = 0,
            .w = 0, .h = 0, .running = true, .shift = false,
        };

        conn.wm_base_id = 0;
        conn.getRegistry();
        if (!conn.roundtrip()) { sys.close(fd); return null; }
        return conn;
    }

    fn wlMsg(self: *WlConn, obj: u32, op: u16, payload: []const u8) void {
        var hdr: [8]u8 = undefined;
        write32(&hdr, 0, obj);
        write32(&hdr, 4, (@as(u32, op) << 16) | @as(u32, @intCast(payload.len + 8)));
        writeStr(self.fd, &hdr);
        if (payload.len > 0) writeStr(self.fd, payload);
    }

    fn getRegistry(self: *WlConn) void {
        self.registry_id = 2;
        var buf: [12]u8 = undefined;
        write32(&buf, 0, 1);
        write32(&buf, 4, (1 << 16) | 12);
        write32(&buf, 8, self.registry_id);
        writeStr(self.fd, &buf);
    }

    fn roundtrip(self: *WlConn) bool {
        var sync_buf: [12]u8 = undefined;
        const sync_id = 3;
        write32(&sync_buf, 0, 1);
        write32(&sync_buf, 4, (0 << 16) | 12);
        write32(&sync_buf, 8, sync_id);
        writeStr(self.fd, &sync_buf);

        var running = true;
        while (running) {
            var hdr: [8]u8 = undefined;
            if (!readExact(self.fd, &hdr)) return false;
            const obj = read32(&hdr, 0);
            const op = @as(u16, @truncate(read32(&hdr, 4) >> 16));
            const size = read32(&hdr, 4) & 0xFFFF;
            if (size < 8) return false;
            const payload_len = size - 8;
            var payload: [256]u8 = undefined;
            if (payload_len > 0) {
                if (!readExact(self.fd, payload[0..payload_len])) return false;
            }

            if (obj == 1 and op == 0) {
                if (payload_len >= 4) {
                    const new_id = read32(&payload, 0);
                    _ = new_id;
                }
            } else if (obj == self.registry_id and op == 0) {
                if (payload_len >= 12) {
                    const name = read32(&payload, 0);
                    const iface_len = read32(&payload, 4);
                    const iface_end = 8 + iface_len;
                    const iface = payload[8..iface_end];
                    const ver = read32(&payload, (iface_end + 3) & ~@as(usize, 3));
                    _ = ver;
                    self.handleGlobal(name, iface);
                }
            } else if (obj == self.wm_base_id and op == 0) {
                running = false;
            } else if (obj == sync_id and op == 0) {
                running = false;
            } else if (obj == self.seat_id and op == 1) {
                self.handleCapabilities(payload[0]);
            } else if (obj == self.surface_id and op == 0) {
            }
        }
        return true;
    }

    fn handleGlobal(self: *WlConn, name: u32, iface: []const u8) void {
        if (matches(iface, "wl_compositor")) {
            self.compositor_id = 100;
            self.wlMsg(2, 0, &packBind(name, 100, 6));
        } else if (matches(iface, "wl_shm")) {
            self.shm_id = 101;
            self.wlMsg(2, 0, &packBind(name, 101, 1));
        } else if (matches(iface, "wl_seat")) {
            self.seat_id = 102;
            self.wlMsg(2, 0, &packBind(name, 102, 9));
        } else if (matches(iface, "xdg_wm_base")) {
            self.wm_base_id = 103;
            self.wlMsg(2, 0, &packBind(name, 103, 6));
        }
    }

    fn handleCapabilities(self: *WlConn, caps: u8) void {
        if (caps & 1 != 0) {
            const kb_id: u32 = 200;
            const msg = packObj(kb_id);
            self.wlMsg(self.seat_id, 0, msg[0..]);
        }
    }

    pub fn createSurface(self: *WlConn, w: u32, h: u32) bool {
        self.w = w;
        self.h = h;
        self.surface_id = 300;
        {
            const msg = packObj(self.surface_id);
            self.wlMsg(self.compositor_id, 0, msg[0..]);
        }
        self.shell_surface_id = 301;
        {
            const msg = packObj(self.shell_surface_id);
            self.wlMsg(self.wm_base_id, 0, msg[0..]);
        }

        var buf1: [12]u8 = undefined;
        write32(&buf1, 0, self.shell_surface_id);
        write32(&buf1, 4, (1 << 16) | 12);
        write32(&buf1, 8, self.surface_id);
        writeStr(self.fd, &buf1);

        var buf2: [12]u8 = undefined;
        write32(&buf2, 0, self.shell_surface_id);
        write32(&buf2, 4, (2 << 16) | 12);
        write32(&buf2, 8, 0);
        writeStr(self.fd, &buf2);

        var title: [64]u8 = undefined;
        var ti: usize = 0;
        const tstr = "dhjsjs IDE";
        for (tstr) |c| { title[ti] = c; ti += 1; }
        title[ti] = 0; ti += 1;
        var tbuf: [128]u8 = undefined;
        write32(&tbuf, 0, self.shell_surface_id);
        write32(&tbuf, 4, (3 << 16) | @as(u32, @intCast(8 + ti)));
        var tbi: usize = 8;
        for (tstr) |c| { tbuf[tbi] = c; tbi += 1; }
        tbuf[tbi] = 0; tbi += 1;
        writeStr(self.fd, tbuf[0..tbi]);

        const stride = w * 4;
        self.shm_size = @as(usize, stride) * h;
        const memfd = createMemFd(self.shm_size);
        if (memfd < 0) return false;

        const ptr = sys.mmap(null, self.shm_size, sys.PROT_READ | sys.PROT_WRITE, sys.MAP_SHARED, memfd, 0);
        sys.close(memfd);
        if (ptr == null) return false;
        self.shm_ptr = @as([*]u8, @ptrCast(ptr.?));

        self.shm_pool_id = 400;
        var pool_buf: [16]u8 = undefined;
        write32(&pool_buf, 0, self.shm_id);
        write32(&pool_buf, 4, (0 << 16) | 16);
        write32(&pool_buf, 8, @as(u32, @intCast(memfd)));
        write32(&pool_buf, 12, @as(u32, @intCast(self.shm_size)));
        writeStr(self.fd, &pool_buf);

        self.buffer_id = 401;
        var buf_buf: [20]u8 = undefined;
        write32(&buf_buf, 0, self.shm_id);
        write32(&buf_buf, 4, (1 << 16) | 20);
        write32(&buf_buf, 8, self.buffer_id);
        write32(&buf_buf, 12, @as(u32, @intCast(self.shm_pool_id)));
        write32(&buf_buf, 16, 0);
        write32(&buf_buf, 17, @as(u8, @truncate(stride)));
        write32(&buf_buf, 18, @as(u16, @truncate(w * 4 / 4)));
        writeStr(self.fd, &buf_buf);

        return true;
    }

    pub fn putImage(self: *WlConn, pixels: [*]u32, w: u32, h: u32) void {
        const stride = w * 4;
        const total = @as(usize, stride) * h;
        var i: usize = 0;
        while (i < total) : (i += 1) self.shm_ptr[i] = @as([*]u8, @ptrCast(pixels))[i];
    }

    pub fn commit(self: *WlConn) void {
        var buf: [8]u8 = undefined;
        write32(&buf, 0, self.surface_id);
        write32(&buf, 4, (1 << 16) | 8);
        writeStr(self.fd, &buf);

        var buf2: [8]u8 = undefined;
        write32(&buf2, 0, self.buffer_id);
        write32(&buf2, 4, (0 << 16) | 8);
        writeStr(self.fd, &buf2);

        var buf3: [12]u8 = undefined;
        write32(&buf3, 0, self.surface_id);
        write32(&buf3, 4, (5 << 16) | 12);
        write32(&buf3, 8, 0);
        write32(&buf3, 9, 0);
        writeStr(self.fd, &buf3);

        var buf4: [8]u8 = undefined;
        write32(&buf4, 0, self.surface_id);
        write32(&buf4, 4, (6 << 16) | 8);
        writeStr(self.fd, &buf4);
    }

    pub fn dispatchEvents(self: *WlConn) void {
        var hdr: [8]u8 = undefined;
        while (true) {
            var pfd: [1]sys.PollFd = undefined;
            pfd[0] = sys.PollFd{ .fd = self.fd, .events = sys.POLLIN, .revents = 0 };
            const n = sys.poll(&pfd, 1, 0);
            if (n <= 0) break;

            if (!readExact(self.fd, &hdr)) { self.running = false; return; }
            const obj = read32(&hdr, 0);
            const op = @as(u16, @truncate(read32(&hdr, 4) >> 16));
            const size = read32(&hdr, 4) & 0xFFFF;
            if (size < 8) { self.running = false; return; }
            const plen = size - 8;
            var payload: [256]u8 = undefined;
            if (plen > 0) { if (!readExact(self.fd, payload[0..plen])) { self.running = false; return; } }

            if (obj == self.seat_id + 1 and op == 0) {
                const kc = payload[4];
                if (kc == 1) self.running = false;
                if (kc == 14) self.shift = true;
                if (kc == 15) self.shift = false;
            }
        }
    }

    pub fn close(self: *WlConn) void {
        if (self.shm_size > 0 and @intFromPtr(self.shm_ptr) != 0) {
            sys.munmap(@ptrCast(self.shm_ptr), self.shm_size);
        }
        sys.close(self.fd);
    }
};

fn matches(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |c, i| if (c != b[i]) return false;
    return true;
}

fn packBind(name: u32, id: u32, ver: u32) [16]u8 {
    var buf: [16]u8 = undefined;
    write32(&buf, 0, name);
    write32(&buf, 4, ver);
    write32(&buf, 8, id);
    write32(&buf, 12, 0);
    return buf;
}

fn packObj(id: u32) [4]u8 {
    var buf: [4]u8 = undefined;
    write32(&buf, 0, id);
    return buf;
}

fn createMemFd(size: usize) i32 {
    const name = "dhjsjs";
    const fd = sys.memfdCreate(name, 1);
    if (fd < 0) return fd;
    if (sys.ftruncate(fd, size) < 0) { sys.close(fd); return -1; }
    return fd;
}
