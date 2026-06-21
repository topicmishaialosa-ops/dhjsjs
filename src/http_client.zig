const sys = @import("sys.zig");

pub fn main() void {
    var args_buf: [8][256]u8 = undefined;
    var arg_count: usize = 0;
    var arg_start: usize = 0;
    var cmdline: [4096]u8 = undefined;
    const cl = @as([*]u8, @ptrFromInt(@as(usize, @intFromPtr(&cmdline))));
    var cl_len: usize = 0;

    // read from /proc/self/cmdline (argv[0], argv[1], ...)
    if (sys.is_linux) {
        const fd = sys.open("/proc/self/cmdline\x00", 0, 0);
        if (fd >= 0) {
            const n = sys.read(fd, cl, cmdline.len);
            sys.close(fd);
            if (n > 0) cl_len = @as(usize, @intCast(n));
        }
    }

    if (cl_len == 0) {
        _ = sys.write(2, "http_client: cannot read cmdline\n", 33);
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
        _ = sys.write(2, "usage: http_client <method> <host> [port] <path> [body]\n", 55);
        sys.exit(1);
    }

    // Check for "resolve" command
    if (args_buf[1][0] == 'r' and args_buf[1][1] == 'e' and args_buf[1][2] == 's' and args_buf[1][3] == 'o' and args_buf[1][4] == 'l' and args_buf[1][5] == 'v' and args_buf[1][6] == 'e' and args_buf[1][7] == 0) {
        if (arg_count < 3) {
            _ = sys.write(2, "usage: http_client resolve <hostname>\n", 39);
            sys.exit(1);
        }
        const host = @as([*]u8, &args_buf[2]);
        var hlen: usize = 0;
        while (host[hlen] != 0) hlen += 1;
        const ip = sys.resolveHostname(host[0..hlen]);
        if (ip == 0) {
            _ = sys.write(2, "http_client: cannot resolve hostname\n", 38);
            sys.exit(1);
        }
        // Write IP as 4 bytes to stdout
        var ip_bytes: [4]u8 = undefined;
        ip_bytes[0] = @as(u8, @intCast(ip & 0xFF));
        ip_bytes[1] = @as(u8, @intCast((ip >> 8) & 0xFF));
        ip_bytes[2] = @as(u8, @intCast((ip >> 16) & 0xFF));
        ip_bytes[3] = @as(u8, @intCast((ip >> 24) & 0xFF));
        _ = sys.write(1, &ip_bytes, 4);
        sys.exit(0);
    }

    const method = @as([*]u8, &args_buf[1]);
    const host = @as([*]u8, &args_buf[2]);
    var mlen: usize = 0;
    while (method[mlen] != 0) mlen += 1;
    var hlen: usize = 0;
    while (host[hlen] != 0) hlen += 1;

    // Determine if arg 3 is a port (all digits) or path
    var port: u16 = 80;
    var path: [*]u8 = undefined;
    var plen: usize = 0;
    var blen: usize = 0;
    var req_body: [*]const u8 = @as([*]const u8, "");

    var arg3_is_port = true;
    var tmpi: usize = 0;
    while (args_buf[3][tmpi] != 0) : (tmpi += 1) {
        if (args_buf[3][tmpi] < '0' or args_buf[3][tmpi] > '9') { arg3_is_port = false; break; }
    }

    if (arg3_is_port and tmpi > 0 and tmpi < 6) {
        // Parse port
        port = 0;
        var pi3: usize = 0;
        while (pi3 < tmpi) : (pi3 += 1) port = port * 10 + (args_buf[3][pi3] - '0');
        if (arg_count >= 5) {
            path = @as([*]u8, &args_buf[4]);
            while (path[plen] != 0) plen += 1;
            if (arg_count >= 6) {
                req_body = @as([*]const u8, &args_buf[5]);
                while (req_body[blen] != 0) blen += 1;
            }
        } else {
            path = @as([*]u8, @ptrFromInt(@intFromPtr("/\x00")));
            plen = 1;
        }
    } else {
        path = @as([*]u8, &args_buf[3]);
        while (path[plen] != 0) plen += 1;
        if (arg_count >= 5) {
            req_body = @as([*]const u8, &args_buf[4]);
            while (req_body[blen] != 0) blen += 1;
        }
    }

    // resolve hostname
    var ip: u32 = 0;
    var octets: [4]u8 = undefined;
    var oi: usize = 0;
    var hi: usize = 0;
    while (oi < 4 and hi < hlen) : (oi += 1) {
        var val: u32 = 0;
        while (hi < hlen and host[hi] >= '0' and host[hi] <= '9') : (hi += 1) val = val * 10 + (host[hi] - '0');
        octets[oi] = @as(u8, @intCast(val));
        if (oi < 3 and hi < hlen and host[hi] == '.') hi += 1;
    }
    if (oi == 4 and hi == hlen) {
        ip = @as(u32, octets[0]) | (@as(u32, octets[1]) << 8) | (@as(u32, octets[2]) << 16) | (@as(u32, octets[3]) << 24);
    } else {
        ip = sys.resolveHostname(host[0..hlen]);
        if (ip == 0) {
            _ = sys.write(2, "http_client: cannot resolve hostname\n", 38);
            sys.exit(1);
        }
    }

    _ = sys.socketInit();

    const fd = sys.socket(sys.AF_INET, sys.SOCK_STREAM, 0);
    if (fd < 0) {
        _ = sys.write(2, "http_client: socket failed\n", 27);
        sys.exit(1);
    }
    defer _ = sys.closeSocket(fd);

    var addr: sys.SockAddrIn = undefined;
    addr.family = @as(u16, @intCast(sys.AF_INET));
    addr.port = sys.htons(port);
    addr.addr = ip;
    addr.zero = [_]u8{0} ** 8;
    const addr_bytes = @as([*]const u8, @ptrCast(&addr));

    if (sys.connect(fd, addr_bytes, @sizeOf(sys.SockAddrIn)) < 0) {
        _ = sys.write(2, "http_client: connect failed\n", 28);
        sys.exit(1);
    }

    // build HTTP request
    var req: [4096]u8 = undefined;
    var rp: usize = 0;

    var mi: usize = 0;
    while (mi < mlen and rp < 4086) : (mi += 1) { req[rp] = method[mi]; rp += 1; }
    req[rp] = ' '; rp += 1;
    var pi: usize = 0;
    while (pi < plen and rp < 4086) : (pi += 1) { req[rp] = path[pi]; rp += 1; }
    req[rp] = ' '; rp += 1;
    req[rp] = 'H'; rp += 1; req[rp] = 'T'; rp += 1; req[rp] = 'T'; rp += 1; req[rp] = 'P'; rp += 1;
    req[rp] = '/'; rp += 1; req[rp] = '1'; rp += 1; req[rp] = '.'; rp += 1; req[rp] = '0'; rp += 1;
    req[rp] = '\r'; rp += 1; req[rp] = '\n'; rp += 1;

    const hdr = "Host: ";
    var hdi: usize = 0;
    while (hdi < 6 and rp < 4086) : (hdi += 1) { req[rp] = hdr[hdi]; rp += 1; }
    var hi2: usize = 0;
    while (hi2 < hlen and rp < 4086) : (hi2 += 1) { req[rp] = host[hi2]; rp += 1; }
    req[rp] = '\r'; rp += 1; req[rp] = '\n'; rp += 1;

    if (blen > 0) {
        const cl_hdr = "Content-Length: ";
        var cli: usize = 0;
        while (cli < 16 and rp < 4086) : (cli += 1) { req[rp] = cl_hdr[cli]; rp += 1; }
        var tmp = blen;
        var digits: [16]u8 = undefined;
        var dc: usize = 0;
        while (tmp > 0) { digits[dc] = @as(u8, @intCast('0' + (tmp % 10))); tmp /= 10; dc += 1; }
        var di = dc;
        while (di > 0) { di -= 1; if (rp < 4086) { req[rp] = digits[di]; rp += 1; } }
        req[rp] = '\r'; rp += 1; req[rp] = '\n'; rp += 1;
        const ct = "Content-Type: application/x-www-form-urlencoded\r\n";
        var cti: usize = 0;
        while (cti < 47 and rp < 4086) : (cti += 1) { req[rp] = ct[cti]; rp += 1; }
    }

    req[rp] = '\r'; rp += 1; req[rp] = '\n'; rp += 1;

    var bi: usize = 0;
    while (bi < blen and rp < 4086) : (bi += 1) { req[rp] = req_body[bi]; rp += 1; }

    if (!sys.sendAll(fd, &req, rp)) {
        _ = sys.write(2, "http_client: send failed\n", 25);
        sys.exit(1);
    }

    // read response and write to stdout
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = sys.recv(fd, &buf, buf.len, 0);
        if (n <= 0) break;
        var off: usize = 0;
        while (off < @as(usize, @intCast(n))) {
            const w = sys.write(1, @as([*]u8, &buf) + off, @as(usize, @intCast(n)) - off);
            if (w <= 0) break;
            off += @as(usize, @intCast(w));
        }
    }

    sys.exit(0);
}
