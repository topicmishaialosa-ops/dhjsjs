pub const is_windows = false;
pub const is_linux = true;

pub const SYS_FTRUNCATE: usize = 77;
pub const SYS_MEMFD_CREATE: usize = 438;
pub const SYS_SEND: usize = 44;
pub const SYS_RECV: usize = 45;
pub const SYS_BIND: usize = 49;
pub const SYS_LISTEN: usize = 50;
pub const SYS_ACCEPT: usize = 43;
pub const SYS_FSTAT: usize = 5;
pub const SYS_GETPID: usize = 39;
pub const SYS_NANOSLEEP: usize = 35;
pub const SYS_LSEEK: usize = 8;
pub const SYS_DUP: usize = 32;
pub const SYS_SETSOCKOPT: usize = 54;
pub const SYS_GETSOCKOPT: usize = 55;
pub const SYS_READ: usize = 0;
pub const SYS_WRITE: usize = 1;
pub const SYS_OPEN: usize = 2;
pub const SYS_CLOSE: usize = 3;
pub const SYS_POLL: usize = 7;
pub const SYS_MMAP: usize = 9;
pub const SYS_MUNMAP: usize = 11;
pub const SYS_IOCTL: usize = 16;
pub const SYS_SOCKET: usize = 41;
pub const SYS_CONNECT: usize = 42;
pub const SYS_EXIT_GROUP: usize = 231;

const WIN32_FUNCS = if (is_windows) struct {
    extern "kernel32" fn GetStdHandle(nStdHandle: u32) usize;
    extern "kernel32" fn WriteFile(hFile: usize, lpBuffer: [*]const u8, nNumberOfBytesToWrite: u32, lpNumberOfBytesWritten: *u32, lpOverlapped: ?*anyopaque) i32;
    extern "kernel32" fn ReadFile(hFile: usize, lpBuffer: [*]u8, nNumberOfBytesToRead: u32, lpNumberOfBytesRead: *u32, lpOverlapped: ?*anyopaque) i32;
    extern "kernel32" fn CloseHandle(hObject: usize) i32;
    extern "kernel32" fn ExitProcess(uExitCode: u32) noreturn;
    extern "kernel32" fn CreateFileA(lpFileName: [*]const u8, dwDesiredAccess: u32, dwShareMode: u32, lpSecurityAttributes: ?*anyopaque, dwCreationDisposition: u32, dwFlagsAndAttributes: u32, hTemplateFile: usize) i32;
    extern "kernel32" fn CreateDirectoryA(lpPathName: [*]const u8, lpSecurityAttributes: ?*anyopaque) i32;
    extern "kernel32" fn GetEnvironmentVariableA(lpName: [*]const u8, lpBuffer: [*]u8, nSize: u32) u32;
    extern "kernel32" fn SetFilePointerEx(hFile: usize, liDistanceToMove: i64, lpNewFilePointer: ?*i64, dwMoveMethod: u32) i32;
    extern "kernel32" fn SetEndOfFile(hFile: usize) i32;
    extern "kernel32" fn GetCurrentProcessId() u32;
    extern "kernel32" fn Sleep(dwMilliseconds: u32) void;
    extern "kernel32" fn VirtualAlloc(lpAddress: ?*anyopaque, dwSize: usize, flAllocationType: u32, flProtect: u32) ?*anyopaque;
    extern "kernel32" fn VirtualFree(lpAddress: *anyopaque, dwSize: usize, dwFreeType: u32) i32;
    extern "kernel32" fn GetCommandLineA() [*]u8;
    extern "kernel32" fn GetModuleFileNameA(hModule: usize, lpFilename: [*]u8, nSize: u32) u32;
    extern "kernel32" fn GetLastError() u32;
    extern "ws2_32" fn WSAStartup(wVersionRequested: u16, lpWSAData: *WSAData) i32;
    extern "ws2_32" fn WSACleanup() i32;
    extern "ws2_32" fn socket(af: i32, type_: i32, protocol: i32) usize;
    extern "ws2_32" fn connect(s: usize, name: [*]const u8, namelen: i32) i32;
    extern "ws2_32" fn bind(s: usize, name: [*]const u8, namelen: i32) i32;
    extern "ws2_32" fn listen(s: usize, backlog: i32) i32;
    extern "ws2_32" fn accept(s: usize, addr: [*]u8, addrlen: *i32) usize;
    extern "ws2_32" fn send(s: usize, buf: [*]const u8, len: i32, flags: i32) i32;
    extern "ws2_32" fn recv(s: usize, buf: [*]u8, len: i32, flags: i32) i32;
    extern "ws2_32" fn closesocket(s: usize) i32;
    extern "ws2_32" fn WSAPoll(fdArray: [*]PollFd, fds: u32, timeout: i32) i32;
    extern "ws2_32" fn ioctlsocket(s: usize, cmd: i32, argp: *u32) i32;
} else struct {
    pub fn GetStdHandle(_: u32) usize { unreachable; }
    pub fn WriteFile(_: usize, _: [*]const u8, _: u32, _: *u32, _: ?*anyopaque) i32 { unreachable; }
    pub fn ReadFile(_: usize, _: [*]u8, _: u32, _: *u32, _: ?*anyopaque) i32 { unreachable; }
    pub fn CloseHandle(_: usize) i32 { unreachable; }
    pub fn ExitProcess(_: u32) noreturn { unreachable; }
    pub fn CreateFileA(_: [*]const u8, _: u32, _: u32, _: ?*anyopaque, _: u32, _: u32, _: usize) i32 { unreachable; }
    pub fn CreateDirectoryA(_: [*]const u8, _: ?*anyopaque) i32 { unreachable; }
    pub fn GetEnvironmentVariableA(_: [*]const u8, _: [*]u8, _: u32) u32 { unreachable; }
    pub fn SetFilePointerEx(_: usize, _: i64, _: ?*i64, _: u32) i32 { unreachable; }
    pub fn SetEndOfFile(_: usize) i32 { unreachable; }
    pub fn GetCurrentProcessId() u32 { unreachable; }
    pub fn Sleep(_: u32) void { unreachable; }
    pub fn VirtualAlloc(_: ?*anyopaque, _: usize, _: u32, _: u32) ?*anyopaque { unreachable; }
    pub fn VirtualFree(_: *anyopaque, _: usize, _: u32) i32 { unreachable; }
    pub fn GetCommandLineA() [*]u8 { unreachable; }
    pub fn GetModuleFileNameA(_: usize, _: [*]u8, _: u32) u32 { unreachable; }
    pub fn GetLastError() u32 { unreachable; }
    pub fn WSAStartup(_: u16, _: *WSAData) i32 { unreachable; }
    pub fn WSACleanup() i32 { unreachable; }
    pub fn socket(_: i32, _: i32, _: i32) usize { unreachable; }
    pub fn connect(_: usize, _: [*]const u8, _: i32) i32 { unreachable; }
    pub fn bind(_: usize, _: [*]const u8, _: i32) i32 { unreachable; }
    pub fn listen(_: usize, _: i32) i32 { unreachable; }
    pub fn accept(_: usize, _: [*]u8, _: *i32) usize { unreachable; }
    pub fn send(_: usize, _: [*]const u8, _: i32, _: i32) i32 { unreachable; }
    pub fn recv(_: usize, _: [*]u8, _: i32, _: i32) i32 { unreachable; }
    pub fn closesocket(_: usize) i32 { unreachable; }
    pub fn WSAPoll(_: [*]PollFd, _: u32, _: i32) i32 { unreachable; }
    pub fn ioctlsocket(_: usize, _: i32, _: *u32) i32 { unreachable; }
};

pub const WSAData = extern struct {
    wVersion: u16,
    wHighVersion: u16,
    iMaxSockets: u16,
    iMaxUdpDg: u16,
    lpVendorInfo: [*]u8,
    szDescription: [257]u8,
    szSystemStatus: [129]u8,
};

pub const AF_UNIX: i32 = 1;
pub const AF_INET: i32 = 2;
pub const SOCK_STREAM: i32 = 1;
pub const SOCK_DGRAM: i32 = 2;
pub const POLLIN: i16 = 1;
pub const SOL_SOCKET: i32 = 1;
pub const SO_REUSEADDR: i32 = 2;
pub const SO_REUSEPORT: i32 = 15;
pub const SO_BINDTODEVICE: i32 = 25;
pub const O_RDWR: i32 = if (is_windows) 0 else 2;
pub const MAKEWORD: fn (u8, u8) u16 = struct { fn impl(a: u8, b: u8) u16 { return @as(u16, a) | (@as(u16, b) << 8); } }.impl;
pub const FIONBIO: i32 = 0x8004667E;
pub const SD_SEND: i32 = 1;
pub const MSG_WAITALL: i32 = 8;
pub const PROT_READ: i32 = 1;
pub const PROT_WRITE: i32 = 2;
pub const MAP_SHARED: i32 = 1;
pub const STDIN: i32 = 0;
pub const STDOUT: i32 = 1;

pub const GENERIC_READ: u32 = 0x80000000;
pub const GENERIC_WRITE: u32 = 0x40000000;
pub const OPEN_EXISTING: u32 = 3;
pub const CREATE_ALWAYS: u32 = 2;
pub const OPEN_ALWAYS: u32 = 4;
pub const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;
pub const FILE_SHARE_READ: u32 = 1;
pub const FILE_SHARE_WRITE: u32 = 2;
pub const STD_OUTPUT_HANDLE: u32 = 0xFFFFFFF5;
pub const STD_ERROR_HANDLE: u32 = 0xFFFFFFF4;
pub const STD_INPUT_HANDLE: u32 = 0xFFFFFFF6;
pub const INVALID_HANDLE_VALUE: i32 = -1;

pub const TIOCGWINSZ: usize = 0x5413;
pub const TCGETS: usize = 0x5401;
pub const TCSETS: usize = 0x5402;
pub const ECHO: u32 = 0x0008;
pub const ICANON: u32 = 0x0002;
pub const ISIG: u32 = 0x0001;
pub const ICANON_OFF: u32 = 0xFFFD;
pub const ECHO_OFF: u32 = 0xFFF7;
pub const ISIG_OFF: u32 = 0xFFFE;
pub const VMIN: usize = 6;
pub const VTIME: usize = 5;

pub const SockAddrIn = extern struct { family: u16, port: u16, addr: u32, zero: [8]u8 };

pub const PollFd = struct { fd: i32, events: i16, revents: i16 };

pub const Timespec = extern struct { sec: i64, nsec: i64 };

pub const Stat = struct {
    dev: u64, ino: u64, nlink: u64, mode: u32,
    uid: u32, gid: u32, pad0: u32, rdev: u64,
    size: i64, blksize: i64, blocks: i64,
    atime: i64, atime_nsec: i64, mtime: i64, mtime_nsec: i64, ctime: i64, ctime_nsec: i64,
};

pub const Termios = extern struct { iflag: u32, oflag: u32, cflag: u32, lflag: u32, c_line: u8, cc: [19]u8 };

pub const Winsize = struct { ws_row: u16, ws_col: u16, ws_xpixel: u16, ws_ypixel: u16 };

pub fn htons(x: u16) u16 {
    return @truncate((@as(u32, x) << 8) | (@as(u32, x) >> 8));
}

pub fn inetAddr(ip: [*]const u8) u32 {
    var octets: [4]u8 = undefined;
    var oi: usize = 0;
    var val: u32 = 0;
    var i: usize = 0;
    while (oi < 4) : (oi += 1) {
        val = 0;
        while (ip[i] >= '0' and ip[i] <= '9') : (i += 1) val = val * 10 + (ip[i] - '0');
        octets[oi] = @as(u8, @intCast(val));
        if (ip[i] == '.') i += 1;
    }
    return @as(u32, octets[0]) | (@as(u32, octets[1]) << 8) | (@as(u32, octets[2]) << 16) | (@as(u32, octets[3]) << 24);
}

pub fn syscall3(nr: usize, a1: usize, a2: usize, a3: usize) usize {
    if (is_linux) {
        var r: usize = undefined;
        asm volatile ("syscall"
            : [r] "={rax}" (r),
            : [n] "{rax}" (nr), [a1] "{rdi}" (a1), [a2] "{rsi}" (a2), [a3] "{rdx}" (a3),
            : .{ .rcx = true, .r11 = true, .memory = true }
        );
        return r;
    }
    return 0;
}

pub fn syscall2(nr: usize, a1: usize, a2: usize) usize {
    if (is_linux) {
        var r: usize = undefined;
        asm volatile ("syscall"
            : [r] "={rax}" (r),
            : [n] "{rax}" (nr), [a1] "{rdi}" (a1), [a2] "{rsi}" (a2),
            : .{ .rcx = true, .r11 = true, .memory = true }
        );
        return r;
    }
    return 0;
}

pub fn syscall1(nr: usize, a1: usize) usize {
    if (is_linux) {
        var r: usize = undefined;
        asm volatile ("syscall"
            : [r] "={rax}" (r),
            : [n] "{rax}" (nr), [a1] "{rdi}" (a1),
            : .{ .rcx = true, .r11 = true, .memory = true }
        );
        return r;
    }
    return 0;
}

pub fn syscall6(nr: usize, a1: usize, a2: usize, a3: usize, a4: usize, a5: usize, a6: usize) usize {
    if (is_linux) {
        var r: usize = undefined;
        asm volatile ("syscall"
            : [r] "={rax}" (r),
            : [n] "{rax}" (nr), [a1] "{rdi}" (a1), [a2] "{rsi}" (a2), [a3] "{rdx}" (a3),
              [a4] "{r10}" (a4), [a5] "{r8}" (a5), [a6] "{r9}" (a6),
            : .{ .rcx = true, .r11 = true, .memory = true }
        );
        return r;
    }
    return 0;
}

pub fn open(path: [*]const u8, flags: i32, mode: i32) i32 {
    if (is_windows) {
        var access: u32 = GENERIC_READ;
        if (flags & 2 != 0) access |= GENERIC_WRITE;
        const disp: u32 = if (flags & 0x40 != 0) CREATE_ALWAYS else OPEN_EXISTING;
        return WIN32_FUNCS.CreateFileA(path, access, FILE_SHARE_READ | FILE_SHARE_WRITE, null, disp, FILE_ATTRIBUTE_NORMAL, 0);
    }
    const r = syscall3(SYS_OPEN, @intFromPtr(path), @as(usize, @bitCast(@as(isize, flags))), @as(usize, @bitCast(@as(isize, mode))));
    return @as(i32, @intCast(@as(isize, @bitCast(r))));
}

pub fn close(fd: i32) void {
    if (is_windows) { _ = WIN32_FUNCS.CloseHandle(@as(usize, @bitCast(@as(isize, fd)))); return; }
    _ = syscall1(SYS_CLOSE, @as(usize, @bitCast(@as(isize, fd))));
}

pub fn write(fd: i32, buf: [*]const u8, len: usize) isize {
    if (is_windows) {
        if (fd == 1 or fd == 2) {
            const handle: u32 = if (fd == 1) STD_OUTPUT_HANDLE else STD_ERROR_HANDLE;
            const h = WIN32_FUNCS.GetStdHandle(handle);
            var written: u32 = 0;
            const ulen: u32 = @as(u32, @intCast(@min(len, @as(usize, 0xFFFFFFFF))));
            if (WIN32_FUNCS.WriteFile(h, buf, ulen, &written, null) != 0) return @as(isize, @intCast(written));
            return -1;
        }
        var written: u32 = 0;
        const ulen: u32 = @as(u32, @intCast(@min(len, @as(usize, 0xFFFFFFFF))));
        if (WIN32_FUNCS.WriteFile(@as(usize, @bitCast(@as(isize, fd))), buf, ulen, &written, null) != 0) return @as(isize, @intCast(written));
        return -1;
    }
    return @bitCast(syscall3(SYS_WRITE, @as(usize, @bitCast(@as(isize, fd))), @intFromPtr(buf), len));
}

pub fn read(fd: i32, buf: [*]u8, len: usize) isize {
    if (is_windows) {
        var read_count: u32 = 0;
        const ulen: u32 = @as(u32, @intCast(@min(len, @as(usize, 0xFFFFFFFF))));
        if (WIN32_FUNCS.ReadFile(@as(usize, @bitCast(@as(isize, fd))), buf, ulen, &read_count, null) != 0) return @as(isize, @intCast(read_count));
        return -1;
    }
    return @bitCast(syscall3(SYS_READ, @as(usize, @bitCast(@as(isize, fd))), @intFromPtr(buf), len));
}

pub fn exit(code: i32) noreturn {
    if (is_windows) WIN32_FUNCS.ExitProcess(@as(u32, @bitCast(code)));
    _ = syscall1(SYS_EXIT_GROUP, @as(usize, @bitCast(@as(isize, code))));
    unreachable;
}

pub fn writeStr(fd: i32, str: [*]const u8, len: usize) void {
    _ = write(fd, str, len);
}

pub fn readDir(fd: i32, buf: []u8) isize {
    return @bitCast(syscall3(217, @as(usize, @bitCast(@as(isize, fd))), @intFromPtr(buf.ptr), buf.len));
}

pub fn mmap(addr: ?*anyopaque, len: usize, prot: i32, flags: i32, fd: i32, off: i64) ?*anyopaque {
    if (is_windows) {
        const flProtect: u32 = if (prot & 2 != 0) 0x04 else 0x02;
        const allocType: u32 = 0x1000 | 0x2000;
        return WIN32_FUNCS.VirtualAlloc(addr, len, allocType, flProtect);
    }
    const r = syscall6(SYS_MMAP, @intFromPtr(addr), len, @as(usize, @bitCast(@as(isize, prot))), @as(usize, @bitCast(@as(isize, flags))), @as(usize, @bitCast(@as(isize, fd))), @as(usize, @bitCast(off)));
    if (r > 0xFFFFFFFFFFFFF000) return null;
    return @ptrFromInt(r);
}

pub fn munmap(addr: *anyopaque, len: usize) void {
    if (is_windows) { _ = WIN32_FUNCS.VirtualFree(addr, 0, 0x8000); return; }
    _ = syscall2(SYS_MUNMAP, @intFromPtr(addr), len);
}

pub fn mkdir(path: [*]const u8, mode: i32) i32 {
    if (is_windows) return WIN32_FUNCS.CreateDirectoryA(path, null);
    return @as(i32, @intCast(@as(isize, @bitCast(syscall2(83, @intFromPtr(path), @as(usize, @bitCast(@as(isize, mode))))))));
}

pub fn getenv(key: []const u8, buf: []u8) ?[]u8 {
    if (is_windows) {
        const n = WIN32_FUNCS.GetEnvironmentVariableA(key.ptr, buf.ptr, @as(u32, @intCast(@min(buf.len, @as(usize, 0xFFFFFFFF)))));
        if (n == 0 or n > buf.len) return null;
        return buf[0..n];
    }
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

pub fn ioctl(fd: i32, req: usize, arg: usize) i32 {
    if (!is_linux) return -1;
    return @as(i32, @intCast(@as(isize, @bitCast(syscall3(SYS_IOCTL, @as(usize, @bitCast(@as(isize, fd))), req, arg)))));
}

pub fn tcgetattr(fd: i32, termios: *Termios) i32 {
    if (!is_linux) return -1;
    return ioctl(fd, TCGETS, @intFromPtr(termios));
}

pub fn tcsetattr(fd: i32, termios: *const Termios) i32 {
    if (!is_linux) return -1;
    return ioctl(fd, TCSETS, @intFromPtr(termios));
}

pub fn getWinsize(fd: i32) ?Winsize {
    if (!is_linux) return null;
    var ws: Winsize = undefined;
    if (ioctl(fd, TIOCGWINSZ, @intFromPtr(&ws)) < 0) return null;
    return ws;
}

pub fn setRawMode(fd: i32) ?Termios {
    if (!is_linux) return null;
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
    if (is_linux) _ = tcsetattr(fd, termios);
}

pub fn ftruncate(fd: i32, len: usize) i32 {
    if (is_windows) {
        const off: i64 = @as(i64, @intCast(len));
        if (WIN32_FUNCS.SetFilePointerEx(@as(usize, @bitCast(@as(isize, fd))), off, null, 0) != 0 and WIN32_FUNCS.SetEndOfFile(@as(usize, @bitCast(@as(isize, fd)))) != 0) return 0;
        return -1;
    }
    return @as(i32, @intCast(@as(isize, @bitCast(syscall2(SYS_FTRUNCATE, @as(usize, @bitCast(@as(isize, fd))), len)))));
}

pub fn memfdCreate(name: []const u8, flags: u32) i32 {
    if (!is_linux) return -1;
    return @as(i32, @intCast(@as(isize, @bitCast(syscall2(SYS_MEMFD_CREATE, @intFromPtr(name.ptr), flags)))));
}

var winsock_started: bool = false;

pub fn socketInit() i32 {
    if (comptime is_windows) {
        if (!winsock_started) {
            var wsa_data: WSAData = undefined;
            if (WIN32_FUNCS.WSAStartup(MAKEWORD(2, 2), &wsa_data) != 0) return -1;
            winsock_started = true;
        }
    }
    return 0;
}

pub fn socket(domain: i32, type_: i32, protocol: i32) i32 {
    if (is_windows) {
        _ = socketInit();
        const s = WIN32_FUNCS.socket(domain, type_, protocol);
        if (s == ~@as(usize, 0)) return -1;
        return @as(i32, @intCast(s));
    }
    return @as(i32, @intCast(@as(isize, @bitCast(syscall3(SYS_SOCKET, @as(usize, @bitCast(@as(isize, domain))), @as(usize, @bitCast(@as(isize, type_))), @as(usize, @bitCast(@as(isize, protocol))))))));
}

pub fn connect(fd: i32, addr: [*]const u8, addrlen: u32) i32 {
    if (is_windows) {
        return WIN32_FUNCS.connect(@as(usize, @bitCast(@as(isize, fd))), addr, @as(i32, @intCast(addrlen)));
    }
    return @as(i32, @intCast(@as(isize, @bitCast(syscall3(SYS_CONNECT, @as(usize, @bitCast(@as(isize, fd))), @intFromPtr(addr), addrlen)))));
}

pub fn poll(fds: [*]PollFd, nfds: usize, timeout: i32) i32 {
    if (is_windows) {
        return WIN32_FUNCS.WSAPoll(fds, @as(u32, @intCast(nfds)), timeout);
    }
    return @as(i32, @intCast(@as(isize, @bitCast(syscall3(SYS_POLL, @intFromPtr(fds), nfds, @as(usize, @bitCast(@as(isize, timeout))))))));
}

pub fn bind(fd: i32, addr: [*]const u8, addrlen: u32) i32 {
    if (is_windows) {
        return WIN32_FUNCS.bind(@as(usize, @bitCast(@as(isize, fd))), addr, @as(i32, @intCast(addrlen)));
    }
    return @as(i32, @intCast(@as(isize, @bitCast(syscall3(SYS_BIND, @as(usize, @bitCast(@as(isize, fd))), @intFromPtr(addr), addrlen)))));
}

pub fn listen(fd: i32, backlog: i32) i32 {
    if (is_windows) {
        return WIN32_FUNCS.listen(@as(usize, @bitCast(@as(isize, fd))), backlog);
    }
    return @as(i32, @intCast(@as(isize, @bitCast(syscall2(SYS_LISTEN, @as(usize, @bitCast(@as(isize, fd))), @as(usize, @bitCast(@as(isize, backlog))))))));
}

pub fn accept(fd: i32, addr: [*]u8, addrlen: *u32) i32 {
    if (is_windows) {
        var wlen: i32 = @as(i32, @intCast(addrlen.*));
        const s = WIN32_FUNCS.accept(@as(usize, @bitCast(@as(isize, fd))), addr, &wlen);
        addrlen.* = @as(u32, @intCast(wlen));
        if (s == ~@as(usize, 0)) return -1;
        return @as(i32, @intCast(s));
    }
    return @as(i32, @intCast(@as(isize, @bitCast(syscall3(SYS_ACCEPT, @as(usize, @bitCast(@as(isize, fd))), @intFromPtr(addr), @intFromPtr(addrlen))))));
}

pub fn send(fd: i32, buf: [*]const u8, len: usize, flags: i32) isize {
    if (is_windows) {
        const n = WIN32_FUNCS.send(@as(usize, @bitCast(@as(isize, fd))), buf, @as(i32, @intCast(len)), flags);
        if (n < 0) return -1;
        return @as(isize, @intCast(n));
    }
    return @bitCast(syscall6(SYS_SEND, @as(usize, @bitCast(@as(isize, fd))), @intFromPtr(buf), len, @as(usize, @bitCast(@as(isize, flags))), 0, 0));
}

pub fn recv(fd: i32, buf: [*]u8, len: usize, flags: i32) isize {
    if (is_windows) {
        const n = WIN32_FUNCS.recv(@as(usize, @bitCast(@as(isize, fd))), buf, @as(i32, @intCast(len)), flags);
        if (n < 0) return -1;
        return @as(isize, @intCast(n));
    }
    return @bitCast(syscall6(SYS_RECV, @as(usize, @bitCast(@as(isize, fd))), @intFromPtr(buf), len, @as(usize, @bitCast(@as(isize, flags))), 0, 0));
}

pub fn closeSocket(fd: i32) i32 {
    if (is_windows) {
        return WIN32_FUNCS.closesocket(@as(usize, @bitCast(@as(isize, fd))));
    }
    close(fd);
    return 0;
}

pub fn sendAll(fd: i32, buf: [*]const u8, len: usize) bool {
    if (!is_linux) return false;
    var off: usize = 0;
    while (off < len) {
        const n = send(fd, buf + off, len - off, 0);
        if (n <= 0) return false;
        off += @as(usize, @intCast(n));
    }
    return true;
}

pub fn recvAll(fd: i32, buf: [*]u8, len: usize) bool {
    if (!is_linux) return false;
    var off: usize = 0;
    while (off < len) {
        const n = recv(fd, buf + off, len - off, 0);
        if (n <= 0) return false;
        off += @as(usize, @intCast(n));
    }
    return true;
}

pub fn getpid() i32 {
    if (is_windows) return @as(i32, @bitCast(WIN32_FUNCS.GetCurrentProcessId()));
    return @as(i32, @intCast(@as(isize, @bitCast(syscall1(SYS_GETPID, 0)))));
}

pub fn nanosleep(req: *const Timespec, rem: ?*Timespec) i32 {
    if (is_windows) { WIN32_FUNCS.Sleep(@as(u32, @intCast(req.sec * 1000 + req.nsec / 1000000))); return 0; }
    return @as(i32, @intCast(@as(isize, @bitCast(syscall2(SYS_NANOSLEEP, @intFromPtr(req), @intFromPtr(rem orelse return -1))))));
}

pub fn lseek(fd: i32, off: i64, whence: i32) i64 {
    if (is_windows) {
        var new_ptr: i64 = undefined;
        if (WIN32_FUNCS.SetFilePointerEx(@as(usize, @bitCast(@as(isize, fd))), off, &new_ptr, @as(u32, @intCast(whence))) != 0) return new_ptr;
        return -1;
    }
    return @bitCast(syscall3(SYS_LSEEK, @as(usize, @bitCast(@as(isize, fd))), @as(usize, @bitCast(off)), @as(usize, @bitCast(@as(isize, whence)))));
}

pub fn dup(fd: i32) i32 {
    if (!is_linux) return -1;
    return @as(i32, @intCast(@as(isize, @bitCast(syscall1(SYS_DUP, @as(usize, @bitCast(@as(isize, fd))))))));
}

pub fn fstat(fd: i32, stat: *Stat) i32 {
    if (!is_linux) return -1;
    return @as(i32, @intCast(@as(isize, @bitCast(syscall2(SYS_FSTAT, @as(usize, @bitCast(@as(isize, fd))), @intFromPtr(stat))))));
}

pub fn resolveHostname(hostname: []const u8) u32 {
    if (!is_linux) return 0;
    const ip = resolveHostsFile(hostname);
    if (ip != 0) return ip;
    return dnsQuery(hostname);
}

fn resolveHostsFile(hostname: []const u8) u32 {
    const fd = open("/etc/hosts\x00", 0, 0);
    if (fd < 0) return 0;
    defer _ = close(fd);
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;
    while (pos < buf.len) {
        const n = read(fd, buf[pos..].ptr, buf.len - pos);
        if (n <= 0) break;
        pos += @as(usize, @intCast(n));
    }
    if (pos == 0) return 0;
    var i: usize = 0;
    while (i < pos) {
        while (i < pos and (buf[i] == ' ' or buf[i] == '\t')) i += 1;
        if (i >= pos or buf[i] == '#' or buf[i] == '\n') { while (i < pos and buf[i] != '\n') i += 1; i += 1; continue; }
        var octets: [4]u8 = undefined;
        var oi: usize = 0;
        while (oi < 4 and i < pos) : (oi += 1) {
            var val: u32 = 0;
            while (i < pos and buf[i] >= '0' and buf[i] <= '9') : (i += 1) val = val * 10 + (buf[i] - '0');
            octets[oi] = @as(u8, @intCast(val));
            if (oi < 3 and i < pos and buf[i] == '.') i += 1;
        }
        while (i < pos and (buf[i] == ' ' or buf[i] == '\t')) i += 1;
        const hstart = i;
        while (i < pos and (buf[i] != ' ' and buf[i] != '\t' and buf[i] != '\n' and buf[i] != '#')) i += 1;
        const hlen = i - hstart;
        if (hlen == hostname.len) {
            var match = true;
            var hi: usize = 0;
            while (hi < hlen) : (hi += 1) { if (buf[hstart + hi] != hostname[hi]) { match = false; break; } }
            if (match and oi == 4) return @as(u32, octets[0]) | (@as(u32, octets[1]) << 8) | (@as(u32, octets[2]) << 16) | (@as(u32, octets[3]) << 24);
        }
    }
    return 0;
}

fn dnsQuery(hostname: []const u8) u32 {
    if (hostname.len == 0 or hostname.len > 253) return 0;

    var buf: [512]u8 = undefined;
    buf[0] = 0x12; buf[1] = 0x34;
    buf[2] = 0x01; buf[3] = 0x00;
    buf[4] = 0x00; buf[5] = 0x01;
    buf[6] = 0x00; buf[7] = 0x00;
    buf[8] = 0x00; buf[9] = 0x00;
    buf[10] = 0x00; buf[11] = 0x00;

    var pos: usize = 12;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= hostname.len) : (i += 1) {
        if (i == hostname.len or hostname[i] == '.') {
            if (i > start) {
                const llen = i - start;
                if (llen > 63) return 0;
                buf[pos] = @as(u8, @intCast(llen)); pos += 1;
                var j: usize = 0;
                while (j < llen) : (j += 1) { buf[pos] = hostname[start + j]; pos += 1; }
            }
            start = i + 1;
        }
    }
    buf[pos] = 0; pos += 1;
    buf[pos] = 0; buf[pos+1] = 1; pos += 2;
    buf[pos] = 0; buf[pos+1] = 1; pos += 2;
    const qlen = pos;

    const fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return 0;
    defer _ = closeSocket(fd);

    const ns_ip = getNameServer();
    if (ns_ip == 0) return 0;

    var addr: SockAddrIn = undefined;
    addr.family = @as(u16, @intCast(AF_INET));
    addr.port = htons(53);
    addr.addr = ns_ip;
    addr.zero = [_]u8{0} ** 8;
    const addr_bytes = @as([*]const u8, @ptrCast(&addr));
    if (connect(fd, addr_bytes, @sizeOf(SockAddrIn)) < 0) return 0;

    if (send(fd, &buf, qlen, 0) < 0) return 0;

    var pfd: [1]PollFd = undefined;
    pfd[0].fd = fd;
    pfd[0].events = 1;
    if (poll(&pfd, 1, 5000) <= 0) return 0;

    var resp: [512]u8 = undefined;
    const n = recv(fd, &resp, resp.len, 0);
    if (n < 12) return 0;
    const rn = @as(usize, @intCast(n));

    if (resp[0] != 0x12 or resp[1] != 0x34) return 0;
    if ((resp[2] & 0x80) == 0) return 0;
    if ((resp[3] & 0x0F) != 0) return 0;

    const qdcount = (@as(usize, resp[4]) << 8) | resp[5];
    const ancount = (@as(usize, resp[6]) << 8) | resp[7];
    if (ancount == 0) return 0;

    pos = 12;
    var qi: usize = 0;
    while (qi < qdcount) : (qi += 1) {
        while (pos < rn and resp[pos] != 0) {
            if ((resp[pos] & 0xC0) == 0xC0) { pos += 2; break; }
            pos += 1 + resp[pos];
        }
        pos += 1;
        pos += 4;
    }

    var ai: usize = 0;
    while (ai < ancount and pos + 10 < rn) : (ai += 1) {
        if ((resp[pos] & 0xC0) == 0xC0) { pos += 2; }
        else { while (pos < rn and resp[pos] != 0) pos += 1 + resp[pos]; pos += 1; }
        if (pos + 10 > rn) return 0;
        const atype = (@as(usize, resp[pos]) << 8) | resp[pos+1]; pos += 2;
        const aclass = (@as(usize, resp[pos]) << 8) | resp[pos+1]; pos += 2;
        pos += 4;
        const rdlen = (@as(usize, resp[pos]) << 8) | resp[pos+1]; pos += 2;
        if (atype == 1 and aclass == 1 and rdlen == 4 and pos + 4 <= rn) {
            return @as(u32, resp[pos]) | (@as(u32, resp[pos+1]) << 8) | (@as(u32, resp[pos+2]) << 16) | (@as(u32, resp[pos+3]) << 24);
        }
        pos += rdlen;
    }
    return 0;
}

fn getNameServer() u32 {
    const fd = open("/etc/resolv.conf\x00", 0, 0);
    if (fd >= 0) {
        defer _ = close(fd);
        var buf: [1024]u8 = undefined;
        const n = read(fd, &buf, buf.len);
        if (n > 0) {
            var i: usize = 0;
            const len = @as(usize, @intCast(n));
            while (i + 10 < len) {
                if (buf[i] == 'n' and buf[i+1] == 'a' and buf[i+2] == 'm' and buf[i+3] == 'e' and buf[i+4] == 's' and buf[i+5] == 'e' and buf[i+6] == 'r' and buf[i+7] == 'v' and buf[i+8] == 'e' and buf[i+9] == 'r' and (buf[i+10] == ' ' or buf[i+10] == '\t')) {
                    i += 11;
                    while (i < len and (buf[i] == ' ' or buf[i] == '\t')) i += 1;
                    var octets: [4]u8 = undefined;
                    var oi: usize = 0;
                    while (oi < 4 and i < len) : (oi += 1) {
                        var val: u32 = 0;
                        while (i < len and buf[i] >= '0' and buf[i] <= '9') : (i += 1) val = val * 10 + (buf[i] - '0');
                        octets[oi] = @as(u8, @intCast(val));
                        if (oi < 3 and i < len and buf[i] == '.') i += 1;
                    }
                    if (oi == 4) return @as(u32, octets[0]) | (@as(u32, octets[1]) << 8) | (@as(u32, octets[2]) << 16) | (@as(u32, octets[3]) << 24);
                }
                i += 1;
            }
        }
    }
    return 0x08080808;
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

// --- OSS Audio -----------------------------------------------------------
pub const SNDCTL_DSP_SETFMT: usize  = 0x80045005;
pub const SNDCTL_DSP_CHANNELS: usize = 0x80045006;
pub const SNDCTL_DSP_SPEED: usize    = 0x8004500A;
pub const SNDCTL_DSP_RESET: usize    = 0x80005000;

pub const AFMT_U8: i32      = 0x00000008;
pub const AFMT_S16_LE: i32  = 0x00000010;
pub const AFMT_S16_BE: i32  = 0x00000020;
pub const AFMT_S32_LE: i32  = 0x00000080;

// --- Framebuffer (/dev/fb0) -----------------------------------------------
pub const FBIOGET_VSCREENINFO: usize = 0x4600;
pub const FBIOPUT_VSCREENINFO: usize = 0x4601;
pub const FBIOGET_FSCREENINFO: usize = 0x4602;

pub const FbVarScreenInfo = extern struct {
    xres: u32, yres: u32, xres_virtual: u32, yres_virtual: u32,
    xoffset: u32, yoffset: u32, bits_per_pixel: u32, grayscale: u32,
    red: [4]u32, green: [4]u32, blue: [4]u32, transp: [4]u32,
    nonstd: u32, activate: u32, height: u32, width: u32,
    accel_flags: u32, pixclock: u32, left_margin: u32, right_margin: u32,
    upper_margin: u32, lower_margin: u32, hsync_len: u32, vsync_len: u32,
    sync: u32, vmode: u32, rotate: u32, reserved: [5]u32,
};

pub const FbFixScreenInfo = extern struct {
    id: [16]u8, smem_start: u64, smem_len: u32, type: u32, type_aux: u32,
    visual: u32, xpanstep: u32, ypanstep: u32, ywrapstep: u32,
    line_length: u32, mmio_start: u64, mmio_len: u32, accel: u32,
    capabilities: u16, reserved: [2]u16,
};

// --- WAV header -----------------------------------------------------------
pub const WavHeader = extern struct {
    riff: [4]u8,
    file_len: u32,
    wave: [4]u8,
    fmt_id: [4]u8,
    fmt_len: u32,
    audio_fmt: u16,
    channels: u16,
    sample_rate: u32,
    byte_rate: u32,
    block_align: u16,
    bits_per_sample: u16,
};

pub const WavDataHeader = extern struct {
    data_id: [4]u8,
    data_len: u32,
};

// --- GUI events ------------------------------------------------------------
pub const Event = union(enum) {
    key_press: u8,
    key_release: u8,
    mouse_move: struct { x: i32, y: i32 },
    mouse_down: struct { x: i32, y: i32, btn: u8 },
    mouse_up: struct { x: i32, y: i32, btn: u8 },
    scroll: struct { dx: i32, dy: i32 },
    close,
    resize: struct { w: u32, h: u32 },
    expose,
};
