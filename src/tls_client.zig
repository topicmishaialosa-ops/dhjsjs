const sys = @import("sys.zig");
const tls = @import("tls.zig");

pub fn main() void {
    var args_buf: [8][256]u8 = undefined;
    var arg_count: usize = 0;
    var arg_start: usize = 0;
    var cmdline: [4096]u8 = undefined;
    const cl = @as([*]u8, @ptrFromInt(@as(usize, @intFromPtr(&cmdline))));
    var cl_len: usize = 0;

    if (sys.is_linux) {
        const fd = sys.open("/proc/self/cmdline\x00", 0, 0);
        if (fd >= 0) {
            const n = sys.read(fd, cl, cmdline.len);
            sys.close(fd);
            if (n > 0) cl_len = @as(usize, @intCast(n));
        }
    }

    if (cl_len == 0) {
        _ = sys.write(2, "tls_client: cannot read cmdline\n", 33);
        sys.exit(1);
    }

    var ci: usize = 0;
    while (ci < cl_len) {
        arg_start = ci;
        while (ci < cl_len and cmdline[ci] != 0) ci += 1;
        if (ci > arg_start and arg_count < args_buf.len) {
            for (0..ci - arg_start) |j| {
                args_buf[arg_count][j] = cmdline[arg_start + j];
            }
            args_buf[arg_count][ci - arg_start] = 0;
            arg_count += 1;
        }
        ci += 1;
    }

    if (arg_count < 2) {
        _ = sys.write(2, "usage: tls_client <method> <host> [port] <path> [body]\n", 55);
        sys.exit(1);
    }

    const method = @as([*]u8, &args_buf[1]);
    const host = @as([*]u8, &args_buf[2]);
    var mlen: usize = 0;
    while (method[mlen] != 0) mlen += 1;
    var hlen: usize = 0;
    while (host[hlen] != 0) hlen += 1;

    var port: u16 = 443;
    var path: [*]u8 = undefined;
    var plen: usize = 0;
    var blen: usize = 0;
    var body_buf: [4096]u8 = [_]u8{0} ** 4096;

    var arg3_is_port = true;
    var tmpi: usize = 0;
    while (args_buf[3][tmpi] != 0) : (tmpi += 1) {
        if (args_buf[3][tmpi] < '0' or args_buf[3][tmpi] > '9') { arg3_is_port = false; break; }
    }

    if (arg3_is_port and tmpi > 0 and tmpi < 6) {
        port = 0;
        var pi3: usize = 0;
        while (pi3 < tmpi) : (pi3 += 1) port = port * 10 + (args_buf[3][pi3] - '0');
        if (arg_count >= 5) {
            path = @as([*]u8, &args_buf[4]);
            while (path[plen] != 0) plen += 1;
            if (arg_count >= 6) {
                var bi: usize = 0;
                while (args_buf[5][bi] != 0 and bi < 4095) : (bi += 1) body_buf[bi] = args_buf[5][bi];
                blen = bi;
            }
        } else {
            path = @as([*]u8, @ptrFromInt(@intFromPtr("/\x00")));
            plen = 1;
        }
    } else {
        path = @as([*]u8, &args_buf[3]);
        while (path[plen] != 0) plen += 1;
        if (arg_count >= 5) {
            var bi: usize = 0;
            while (args_buf[4][bi] != 0 and bi < 4095) : (bi += 1) body_buf[bi] = args_buf[4][bi];
            blen = bi;
        }
    }

    var resp = if (blen > 0)
        tls.httpsPost(host[0..hlen], path[0..plen], body_buf[0..blen])
    else
        tls.httpsGet(host[0..hlen], path[0..plen]);

    if (!resp.success) {
        _ = sys.write(2, "tls_client: TLS handshake failed\n", 34);
        sys.exit(1);
    }

    // Write response to stdout
    var off: usize = 0;
    while (off < resp.data_len) {
        const w = sys.write(1, @as([*]u8, &resp.data) + off, resp.data_len - off);
        if (w <= 0) break;
        off += @as(usize, @intCast(w));
    }

    sys.exit(0);
}
