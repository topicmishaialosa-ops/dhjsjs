pub const SYS_FTRUNCATE: usize = 77;
pub const SYS_MEMFD_CREATE: usize = 438;

pub fn syscall3(nr: usize, a1: usize, a2: usize, a3: usize) usize {
    var r: usize = undefined;
    asm volatile ("syscall"
        : [r] "={rax}" (r),
        : [n] "{rax}" (nr), [a1] "{rdi}" (a1), [a2] "{rsi}" (a2), [a3] "{rdx}" (a3),
        : .{ .rcx = true, .r11 = true, .memory = true }
    );
    return r;
}

pub fn syscall2(nr: usize, a1: usize, a2: usize) usize {
    var r: usize = undefined;
    asm volatile ("syscall"
        : [r] "={rax}" (r),
        : [n] "{rax}" (nr), [a1] "{rdi}" (a1), [a2] "{rsi}" (a2),
        : .{ .rcx = true, .r11 = true, .memory = true }
    );
    return r;
}

pub fn syscall1(nr: usize, a1: usize) usize {
    var r: usize = undefined;
    asm volatile ("syscall"
        : [r] "={rax}" (r),
        : [n] "{rax}" (nr), [a1] "{rdi}" (a1),
        : .{ .rcx = true, .r11 = true, .memory = true }
    );
    return r;
}

pub fn syscall6(nr: usize, a1: usize, a2: usize, a3: usize, a4: usize, a5: usize, a6: usize) usize {
    var r: usize = undefined;
    asm volatile ("syscall"
        : [r] "={rax}" (r),
        : [n] "{rax}" (nr), [a1] "{rdi}" (a1), [a2] "{rsi}" (a2), [a3] "{rdx}" (a3),
          [a4] "{r10}" (a4), [a5] "{r8}" (a5), [a6] "{r9}" (a6),
        : .{ .rcx = true, .r11 = true, .memory = true }
    );
    return r;
}

const SYS_READ: usize = 0;
const SYS_WRITE: usize = 1;
const SYS_OPEN: usize = 2;
const SYS_CLOSE: usize = 3;
const SYS_POLL: usize = 7;
const SYS_MMAP: usize = 9;
const SYS_MUNMAP: usize = 11;
const SYS_IOCTL: usize = 16;
const SYS_SOCKET: usize = 41;
const SYS_CONNECT: usize = 42;
const SYS_EXIT_GROUP: usize = 231;

pub const O_RDWR: i32 = 2;
pub const PROT_READ: i32 = 1;
pub const PROT_WRITE: i32 = 2;
pub const MAP_SHARED: i32 = 1;
pub const AF_UNIX: i32 = 1;
pub const SOCK_STREAM: i32 = 1;
pub const POLLIN: i16 = 1;

pub const PollFd = struct {
    fd: i32,
    events: i16,
    revents: i16,
};

pub fn socket(domain: i32, type_: i32, protocol: i32) i32 {
    return @as(i32, @intCast(@as(isize, @bitCast(syscall3(SYS_SOCKET, @as(usize, @bitCast(@as(isize, domain))), @as(usize, @bitCast(@as(isize, type_))), @as(usize, @bitCast(@as(isize, protocol))))))));
}

pub fn connect(fd: i32, addr: [*]const u8, addrlen: u32) i32 {
    return @as(i32, @intCast(@as(isize, @bitCast(syscall3(SYS_CONNECT, @as(usize, @bitCast(@as(isize, fd))), @intFromPtr(addr), addrlen)))));
}

pub fn poll(fds: [*]PollFd, nfds: usize, timeout: i32) i32 {
    return @as(i32, @intCast(@as(isize, @bitCast(syscall3(SYS_POLL, @intFromPtr(fds), nfds, @as(usize, @bitCast(@as(isize, timeout))))))));
}

pub fn open(path: [*]const u8, flags: i32, mode: i32) i32 {
    const r = syscall3(SYS_OPEN, @intFromPtr(path), @as(usize, @bitCast(@as(isize, flags))), @as(usize, @bitCast(@as(isize, mode))));
    return @as(i32, @intCast(@as(isize, @bitCast(r))));
}

pub fn close(fd: i32) void {
    _ = syscall1(SYS_CLOSE, @as(usize, @bitCast(@as(isize, fd))));
}

pub fn write(fd: i32, buf: [*]const u8, len: usize) isize {
    return @bitCast(syscall3(SYS_WRITE, @as(usize, @bitCast(@as(isize, fd))), @intFromPtr(buf), len));
}

pub fn read(fd: i32, buf: [*]u8, len: usize) isize {
    return @bitCast(syscall3(SYS_READ, @as(usize, @bitCast(@as(isize, fd))), @intFromPtr(buf), len));
}

pub fn exit(code: i32) noreturn {
    _ = syscall1(SYS_EXIT_GROUP, @as(usize, @bitCast(@as(isize, code))));
    unreachable;
}

pub fn writeStr(fd: i32, str: [*]const u8, len: usize) void {
    _ = write(fd, str, len);
}

pub fn mmap(addr: ?*anyopaque, len: usize, prot: i32, flags: i32, fd: i32, off: i64) ?*anyopaque {
    const r = syscall6(
        SYS_MMAP,
        @intFromPtr(addr),
        len,
        @as(usize, @bitCast(@as(isize, prot))),
        @as(usize, @bitCast(@as(isize, flags))),
        @as(usize, @bitCast(@as(isize, fd))),
        @as(usize, @bitCast(off)),
    );
    if (r > 0xFFFFFFFFFFFFF000) return null;
    return @ptrFromInt(r);
}

pub fn munmap(addr: *anyopaque, len: usize) void {
    _ = syscall2(SYS_MUNMAP, @intFromPtr(addr), len);
}

pub fn mkdir(path: [*]const u8, mode: i32) i32 {
    return @as(i32, @intCast(@as(isize, @bitCast(syscall2(83, @intFromPtr(path), @as(usize, @bitCast(@as(isize, mode))))))));
}

pub const TIOCGWINSZ: usize = 0x5413;
pub const TCGETS: usize = 0x5401;
pub const TCSETS: usize = 0x5402;
pub const ECHO: u32 = 0x0008;
pub const ICANON: u32 = 0x0002;
pub const ISIG: u32 = 0x0001;
pub const ICANON_OFF: u32 = 0xFFFD;
pub const ECHO_OFF: u32 = 0xFFF7;
pub const ISIG_OFF: u32 = 0xFFFE;
pub const STDIN: i32 = 0;
pub const STDOUT: i32 = 1;
pub const VMIN: usize = 6;
pub const VTIME: usize = 5;

pub const Termios = extern struct {
    iflag: u32,
    oflag: u32,
    cflag: u32,
    lflag: u32,
    c_line: u8,
    cc: [19]u8,
};

pub const Winsize = struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
};

pub fn ioctl(fd: i32, req: usize, arg: usize) i32 {
    return @as(i32, @intCast(@as(isize, @bitCast(syscall3(SYS_IOCTL, @as(usize, @bitCast(@as(isize, fd))), req, arg)))));
}

pub fn tcgetattr(fd: i32, termios: *Termios) i32 {
    return ioctl(fd, TCGETS, @intFromPtr(termios));
}

pub fn tcsetattr(fd: i32, termios: *const Termios) i32 {
    return ioctl(fd, TCSETS, @intFromPtr(termios));
}

pub fn getWinsize(fd: i32) ?Winsize {
    var ws: Winsize = undefined;
    if (ioctl(fd, TIOCGWINSZ, @intFromPtr(&ws)) < 0) return null;
    return ws;
}

pub fn setRawMode(fd: i32) ?Termios {
    var t: Termios = undefined;
    if (tcgetattr(fd, &t) < 0) return null;
    var raw = t;
    raw.iflag &= ~@as(u32, 0x000B);
    raw.lflag &= ~(ECHO | ICANON | ISIG);
    raw.oflag &= ~@as(u32, 0x0001);
    raw.cc[VMIN] = 1;
    raw.cc[VTIME] = 0;
    if (tcsetattr(fd, &raw) < 0) return null;
    return t;
}

pub fn restoreMode(fd: i32, termios: *const Termios) void {
    _ = tcsetattr(fd, termios);
}

pub fn ftruncate(fd: i32, len: usize) i32 {
    return @as(i32, @intCast(@as(isize, @bitCast(syscall2(SYS_FTRUNCATE, @as(usize, @bitCast(@as(isize, fd))), len)))));
}

pub fn memfdCreate(name: []const u8, flags: u32) i32 {
    return @as(i32, @intCast(@as(isize, @bitCast(syscall2(SYS_MEMFD_CREATE, @intFromPtr(name.ptr), flags)))));
}

pub fn getenv(key: []const u8, buf: []u8) ?[]u8 {
    const fd = open("/proc/self/environ\x00", 0, 0);
    if (fd < 0) return null;
    defer _ = close(fd);

    var env: [4096]u8 = undefined;
    var pos: usize = 0;
    while (pos < env.len) {
        const n = read(fd, env[pos..].ptr, env.len - pos);
        if (n <= 0) break;
        pos += @as(usize, @intCast(n));
    }
    if (pos == 0) return null;

    var i: usize = 0;
    while (i < pos) {
        const end = i + (memchr(env[i..pos], 0) orelse (pos - i));
        if (end - i > key.len and env[i + key.len] == '=' and memEql(env[i..i + key.len], key)) {
            const val_start = i + key.len + 1;
            const vlen = end - val_start;
            if (vlen <= buf.len) {
                var j: usize = 0;
                while (j < vlen) : (j += 1) buf[j] = env[val_start + j];
                return buf[0..vlen];
            }
        }
        i = end + 1;
    }
    return null;
}

fn memchr(s: []const u8, byte: u8) ?usize {
    for (s, 0..) |b, i| if (b == byte) return i;
    return null;
}

fn memEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |av, i| if (av != b[i]) return false;
    return true;
}
