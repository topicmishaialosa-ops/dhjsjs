const sys = @import("sys.zig");

pub const Response = struct {
    status: u16,
    headers: [4096]u8,
    headers_len: usize,
    body: [65536]u8,
    body_len: usize,
};

fn readUntil(buf: []const u8, pos: *usize, delim: []const u8) ?[]const u8 {
    const start = pos.*;
    while (pos.* + delim.len <= buf.len) {
        var match = true;
        for (delim, 0..) |d, i| {
            if (buf[pos.* + i] != d) { match = false; break; }
        }
        if (match) {
            const result = buf[start..pos.*];
            pos.* += delim.len;
            return result;
        }
        pos.* += 1;
    }
    return null;
}

fn httpRequest(host: []const u8, path: []const u8, port: u16, method: []const u8, body: []const u8) ?Response {
    _ = sys.socketInit();

    // resolve hostname
    var ip: u32 = 0;
    var octets: [4]u8 = undefined;
    var oi: usize = 0;
    var hi: usize = 0;
    while (oi < 4 and hi < host.len) : (oi += 1) {
        var val: u32 = 0;
        while (hi < host.len and host[hi] >= '0' and host[hi] <= '9') : (hi += 1) val = val * 10 + (host[hi] - '0');
        octets[oi] = @as(u8, @intCast(val));
        if (oi < 3 and hi < host.len and host[hi] == '.') hi += 1;
    }
    if (oi == 4) {
        ip = @as(u32, octets[0]) | (@as(u32, octets[1]) << 8) | (@as(u32, octets[2]) << 16) | (@as(u32, octets[3]) << 24);
    } else {
        var host_buf: [256]u8 = undefined;
        var hc: usize = 0;
        while (hc < host.len and hc < 255) : (hc += 1) host_buf[hc] = host[hc];
        host_buf[hc] = 0;
        ip = sys.resolveHostname(host_buf[0..hc]);
        if (ip == 0) {
            // try DNS via /etc/hosts or fallback
            const fd = sys.socket(sys.AF_INET, sys.SOCK_DGRAM, 0);
            if (fd >= 0) sys.close(fd);
            return null;
        }
    }

    const fd = sys.socket(sys.AF_INET, sys.SOCK_STREAM, 0);
    if (fd < 0) return null;
    defer _ = sys.closeSocket(fd);

    var addr: sys.SockAddrIn = undefined;
    addr.family = @as(u16, @intCast(sys.AF_INET));
    addr.port = sys.htons(port);
    addr.addr = ip;
    addr.zero = [_]u8{0} ** 8;
    const addr_bytes = @as([*]const u8, @ptrCast(&addr));

    if (sys.connect(fd, addr_bytes, @sizeOf(sys.SockAddrIn)) < 0) return null;

    // build request
    var req_buf: [4096]u8 = undefined;
    var rp: usize = 0;

    // "GET /path HTTP/1.0\r\n"
    for (method) |c| { if (rp < 4086) { req_buf[rp] = c; rp += 1; } }
    req_buf[rp] = ' '; rp += 1;
    for (path) |c| { if (rp < 4086) { req_buf[rp] = c; rp += 1; } }
    req_buf[rp] = ' '; rp += 1;
    const ver = "HTTP/1.0\r\n";
    for (ver) |c| { if (rp < 4086) { req_buf[rp] = c; rp += 1; } }

    // "Host: ...\r\n"
    const hdr = "Host: ";
    for (hdr) |c| { if (rp < 4086) { req_buf[rp] = c; rp += 1; } }
    for (host) |c| { if (rp < 4086) { req_buf[rp] = c; rp += 1; } }
    req_buf[rp] = '\r'; rp += 1; req_buf[rp] = '\n'; rp += 1;

    if (body.len > 0) {
        // "Content-Length: ...\r\n"
        const cl = "Content-Length: ";
        for (cl) |c| { if (rp < 4086) { req_buf[rp] = c; rp += 1; } }
        var tmp = body.len;
        var digits: [16]u8 = undefined;
        var dc: usize = 0;
        while (tmp > 0) { digits[dc] = @as(u8, @intCast('0' + (tmp % 10))); tmp /= 10; dc += 1; }
        var di = dc;
        while (di > 0) { di -= 1; if (rp < 4086) { req_buf[rp] = digits[di]; rp += 1; } }
        req_buf[rp] = '\r'; rp += 1; req_buf[rp] = '\n'; rp += 1;

        // "Content-Type: application/x-www-form-urlencoded\r\n"
        const ct = "Content-Type: application/x-www-form-urlencoded\r\n";
        for (ct) |c| { if (rp < 4086) { req_buf[rp] = c; rp += 1; } }
    }

    // "\r\n" (end headers)
    req_buf[rp] = '\r'; rp += 1; req_buf[rp] = '\n'; rp += 1;

    // body
    for (body) |c| { if (rp < 4086) { req_buf[rp] = c; rp += 1; } }

    if (!sys.sendAll(fd, &req_buf, rp)) return null;

    // receive response
    var resp: Response = undefined;
    resp.headers_len = 0;
    resp.body_len = 0;
    resp.status = 0;

    var buf: [8192]u8 = undefined;
    var total: usize = 0;
    var header_done = false;

    while (total < buf.len) {
        const n = sys.recv(fd, buf.ptr + total, buf.len - total, 0);
        if (n <= 0) break;
        total += @as(usize, @intCast(n));
        if (!header_done) {
            var pos: usize = 0;
            // parse status line: "HTTP/1.0 200 OK\r\n"
            const status_line = readUntil(buf[0..total], &pos, "\r\n") orelse continue;
            if (status_line.len >= 12) {
                var si: usize = 9;
                while (si < status_line.len and status_line[si] >= '0' and status_line[si] <= '9') : (si += 1) {
                    resp.status = resp.status * 10 + (status_line[si] - '0');
                }
            }
            // read headers until blank line
            while (pos < total) {
                const line = readUntil(buf[0..total], &pos, "\r\n") orelse break;
                if (line.len == 0) { header_done = true; break; }
            }
            if (header_done) {
                // copy headers
                var ci: usize = 0;
                while (ci < pos and ci < resp.headers.len) : (ci += 1) {
                    resp.headers[ci] = buf[ci];
                }
                resp.headers_len = pos;
                // remaining data is body
                if (total > pos) {
                    var bi: usize = 0;
                    while (pos + bi < total and bi < resp.body.len) : (bi += 1) {
                        resp.body[bi] = buf[pos + bi];
                    }
                    resp.body_len = bi;
                }
                // continue reading more body
                while (resp.body_len < resp.body.len) {
                    const nn = sys.recv(fd, resp.body.ptr + resp.body_len, resp.body.len - resp.body_len, 0);
                    if (nn <= 0) break;
                    resp.body_len += @as(usize, @intCast(nn));
                }
                return resp;
            }
        }
    }

    return resp;
}

pub fn httpGet(host: []const u8, path: []const u8) ?Response {
    return httpRequest(host, path, 80, "GET", "");
}

pub fn httpPost(host: []const u8, path: []const u8, body: []const u8) ?Response {
    return httpRequest(host, path, 80, "POST", body);
}
