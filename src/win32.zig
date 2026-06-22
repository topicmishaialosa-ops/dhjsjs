const sys = @import("sys.zig");
const gfx = @import("render.zig");

const WIN32 = if (sys.is_windows) struct {
    extern "user32" fn CreateWindowExA(dwExStyle: u32, lpClassName: [*]const u8, lpWindowName: [*]const u8, dwStyle: u32, x: i32, y: i32, nWidth: i32, nHeight: i32, hWndParent: usize, hMenu: usize, hInstance: usize, lpParam: ?*anyopaque) usize;
    extern "user32" fn DefWindowProcA(hWnd: usize, Msg: u32, wParam: usize, lParam: usize) usize;
    extern "user32" fn DestroyWindow(hWnd: usize) i32;
    extern "user32" fn DispatchMessageA(lpMsg: *MSG) usize;
    extern "user32" fn GetMessageA(lpMsg: *MSG, hWnd: usize, wMsgFilterMin: u32, wMsgFilterMax: u32) i32;
    extern "user32" fn PeekMessageA(lpMsg: *MSG, hWnd: usize, wMsgFilterMin: u32, wMsgFilterMax: u32, wRemoveMsg: u32) i32;
    extern "user32" fn PostQuitMessage(nExitCode: i32) void;
    extern "user32" fn RegisterClassA(lpWndClass: *WNDCLASSA) u16;
    extern "user32" fn ShowWindow(hWnd: usize, nCmdShow: i32) i32;
    extern "user32" fn UpdateWindow(hWnd: usize) i32;
    extern "user32" fn TranslateMessage(lpMsg: *MSG) i32;
    extern "gdi32" fn BitBlt(hdc: usize, x: i32, y: i32, cx: i32, cy: i32, hdcSrc: usize, x1: i32, y1: i32, rop: u32) i32;
    extern "gdi32" fn CreateCompatibleBitmap(hdc: usize, cx: i32, cy: i32) usize;
    extern "gdi32" fn CreateCompatibleDC(hdc: usize) usize;
    extern "gdi32" fn DeleteDC(hdc: usize) i32;
    extern "gdi32" fn DeleteObject(hgo: usize) i32;
    extern "gdi32" fn GetDC(hWnd: usize) usize;
    extern "gdi32" fn ReleaseDC(hWnd: usize, hDC: usize) i32;
    extern "gdi32" fn SelectObject(hdc: usize, h: usize) usize;
    extern "gdi32" fn SetDIBitsToDevice(hdc: usize, xDest: i32, yDest: i32, w: u32, h: u32, xSrc: i32, ySrc: i32, uStartScan: u32, cScanLines: u32, lpvBits: [*]const u8, lpbmi: *BITMAPINFO, fuColorUse: u32) i32;
} else struct {
    pub fn CreateWindowExA(_: u32, _: [*]const u8, _: [*]const u8, _: u32, _: i32, _: i32, _: i32, _: i32, _: usize, _: usize, _: usize, _: ?*anyopaque) usize { unreachable; }
    pub fn DefWindowProcA(_: usize, _: u32, _: usize, _: usize) usize { unreachable; }
    pub fn DestroyWindow(_: usize) i32 { unreachable; }
    pub fn DispatchMessageA(_: *MSG) usize { unreachable; }
    pub fn GetMessageA(_: *MSG, _: usize, _: u32, _: u32) i32 { unreachable; }
    pub fn PeekMessageA(_: *MSG, _: usize, _: u32, _: u32, _: u32) i32 { unreachable; }
    pub fn PostQuitMessage(_: i32) void { unreachable; }
    pub fn RegisterClassA(_: *WNDCLASSA) u16 { unreachable; }
    pub fn ShowWindow(_: usize, _: i32) i32 { unreachable; }
    pub fn UpdateWindow(_: usize) i32 { unreachable; }
    pub fn TranslateMessage(_: *MSG) i32 { unreachable; }
    pub fn BitBlt(_: usize, _: i32, _: i32, _: i32, _: i32, _: usize, _: i32, _: i32, _: u32) i32 { unreachable; }
    pub fn CreateCompatibleBitmap(_: usize, _: i32, _: i32) usize { unreachable; }
    pub fn CreateCompatibleDC(_: usize) usize { unreachable; }
    pub fn DeleteDC(_: usize) i32 { unreachable; }
    pub fn DeleteObject(_: usize) i32 { unreachable; }
    pub fn GetDC(_: usize) usize { unreachable; }
    pub fn ReleaseDC(_: usize, _: usize) i32 { unreachable; }
    pub fn SelectObject(_: usize, _: usize) usize { unreachable; }
    pub fn SetDIBitsToDevice(_: usize, _: i32, _: i32, _: u32, _: u32, _: i32, _: i32, _: u32, _: u32, _: [*]const u8, _: *BITMAPINFO, _: u32) i32 { unreachable; }
};

pub const MSG = extern struct { hwnd: usize, message: u32, wParam: usize, lParam: usize, time: u32, pt_x: i32, pt_y: i32 };
pub const WNDCLASSA = extern struct { style: u32, lpfnWndProc: *const fn (usize, u32, usize, usize) callconv(.Stdcall) usize, cbClsExtra: i32, cbWndExtra: i32, hInstance: usize, hIcon: usize, hCursor: usize, hbrBackground: usize, lpszMenuName: [*]const u8, lpszClassName: [*]const u8 };
pub const BITMAPINFOHEADER = extern struct { biSize: u32, biWidth: i32, biHeight: i32, biPlanes: u16, biBitCount: u16, biCompression: u32, biSizeImage: u32, biXPelsPerMeter: i32, biYPelsPerMeter: i32, biClrUsed: u32, biClrImportant: u32 };
pub const BITMAPINFO = extern struct { bmiHeader: BITMAPINFOHEADER, bmiColors: [1]u32 };

pub const CS_HREDRAW: u32 = 2;
pub const CS_VREDRAW: u32 = 1;
pub const WS_OVERLAPPEDWINDOW: u32 = 0xCF0000;
pub const WS_VISIBLE: u32 = 0x10000000;
pub const CW_USEDEFAULT: i32 = 0x80000000;
pub const SW_SHOW: i32 = 5;
pub const WM_DESTROY: u32 = 2;
pub const WM_CLOSE: u32 = 16;
pub const WM_PAINT: u32 = 15;
pub const WM_SIZE: u32 = 5;
pub const WM_KEYDOWN: u32 = 256;
pub const WM_KEYUP: u32 = 257;
pub const WM_MOUSEMOVE: u32 = 512;
pub const WM_LBUTTONDOWN: u32 = 513;
pub const WM_LBUTTONUP: u32 = 514;
pub const WM_RBUTTONDOWN: u32 = 516;
pub const WM_RBUTTONUP: u32 = 517;
pub const WM_MBUTTONDOWN: u32 = 519;
pub const WM_MBUTTONUP: u32 = 520;
pub const WM_MOUSEWHEEL: u32 = 522;
pub const WM_XBUTTONDOWN: u32 = 523;
pub const WM_XBUTTONUP: u32 = 524;
pub const WM_MOUSEHWHEEL: u32 = 526;
pub const WM_QUIT: u32 = 18;
pub const PM_REMOVE: u32 = 1;
pub const SRCCOPY: u32 = 0xCC0020;
pub const BI_RGB: u32 = 0;

var g_hwnd: usize = 0;
var g_hdc: usize = 0;
var g_mem_dc: usize = 0;
var g_bmp: usize = 0;
var g_fb: [*]u32 = undefined;
var g_w: u32 = 0;
var g_h: u32 = 0;
var g_ev_buf: [64]sys.Event = undefined;
var g_ev_count: usize = 0;
var g_ev_head: usize = 0;

fn pushEvent(ev: sys.Event) void {
    if (g_ev_count < g_ev_buf.len) {
        g_ev_buf[(g_ev_head + g_ev_count) % g_ev_buf.len] = ev;
        g_ev_count += 1;
    }
}

fn wndProc(hWnd: usize, msg: u32, wParam: usize, lParam: usize) callconv(.Stdcall) usize {
    switch (msg) {
        WM_CLOSE => { pushEvent(sys.Event.close); return 0; },
        WM_DESTROY => { WIN32.PostQuitMessage(0); return 0; },
        WM_KEYDOWN => {
            const kc = @as(u8, @intCast(wParam & 0xFF));
            pushEvent(sys.Event{ .key_press = kc });
            return 0;
        },
        WM_KEYUP => {
            const kc = @as(u8, @intCast(wParam & 0xFF));
            pushEvent(sys.Event{ .key_release = kc });
            return 0;
        },
        WM_MOUSEMOVE => {
            const x = @as(i32, @intCast(@as(u16, @truncate(lParam & 0xFFFF))));
            const y = @as(i32, @intCast(@as(u16, @truncate((lParam >> 16) & 0xFFFF))));
            pushEvent(sys.Event{ .mouse_move = .{ .x = x, .y = y } });
            return 0;
        },
        WM_LBUTTONDOWN => {
            const x = @as(i32, @intCast(@as(u16, @truncate(lParam & 0xFFFF))));
            const y = @as(i32, @intCast(@as(u16, @truncate((lParam >> 16) & 0xFFFF))));
            pushEvent(sys.Event{ .mouse_down = .{ .x = x, .y = y, .btn = 1 } });
            return 0;
        },
        WM_LBUTTONUP => {
            const x = @as(i32, @intCast(@as(u16, @truncate(lParam & 0xFFFF))));
            const y = @as(i32, @intCast(@as(u16, @truncate((lParam >> 16) & 0xFFFF))));
            pushEvent(sys.Event{ .mouse_up = .{ .x = x, .y = y, .btn = 1 } });
            return 0;
        },
        WM_RBUTTONDOWN => {
            const x = @as(i32, @intCast(@as(u16, @truncate(lParam & 0xFFFF))));
            const y = @as(i32, @intCast(@as(u16, @truncate((lParam >> 16) & 0xFFFF))));
            pushEvent(sys.Event{ .mouse_down = .{ .x = x, .y = y, .btn = 3 } });
            return 0;
        },
        WM_RBUTTONUP => {
            const x = @as(i32, @intCast(@as(u16, @truncate(lParam & 0xFFFF))));
            const y = @as(i32, @intCast(@as(u16, @truncate((lParam >> 16) & 0xFFFF))));
            pushEvent(sys.Event{ .mouse_up = .{ .x = x, .y = y, .btn = 3 } });
            return 0;
        },
        WM_MBUTTONDOWN => {
            const x = @as(i32, @intCast(@as(u16, @truncate(lParam & 0xFFFF))));
            const y = @as(i32, @intCast(@as(u16, @truncate((lParam >> 16) & 0xFFFF))));
            pushEvent(sys.Event{ .mouse_down = .{ .x = x, .y = y, .btn = 2 } });
            return 0;
        },
        WM_MBUTTONUP => {
            const x = @as(i32, @intCast(@as(u16, @truncate(lParam & 0xFFFF))));
            const y = @as(i32, @intCast(@as(u16, @truncate((lParam >> 16) & 0xFFFF))));
            pushEvent(sys.Event{ .mouse_up = .{ .x = x, .y = y, .btn = 2 } });
            return 0;
        },
        WM_XBUTTONDOWN => {
            const x = @as(i32, @intCast(@as(u16, @truncate(lParam & 0xFFFF))));
            const y = @as(i32, @intCast(@as(u16, @truncate((lParam >> 16) & 0xFFFF))));
            const xb = @as(u16, @truncate(wParam >> 16));
            const btn: u8 = if (xb == 1) 4 else 5;
            pushEvent(sys.Event{ .mouse_down = .{ .x = x, .y = y, .btn = btn } });
            return 1;
        },
        WM_XBUTTONUP => {
            const x = @as(i32, @intCast(@as(u16, @truncate(lParam & 0xFFFF))));
            const y = @as(i32, @intCast(@as(u16, @truncate((lParam >> 16) & 0xFFFF))));
            const xb = @as(u16, @truncate(wParam >> 16));
            const btn: u8 = if (xb == 1) 4 else 5;
            pushEvent(sys.Event{ .mouse_up = .{ .x = x, .y = y, .btn = btn } });
            return 1;
        },
         WM_SIZE => {
             const new_w = @as(u32, @intCast(lParam & 0xFFFF));
             const new_h = @as(u32, @intCast((lParam >> 16) & 0xFFFF));
             pushEvent(sys.Event{ .resize = .{ .w = new_w, .h = new_h } });
             return 0;
         },
         WM_MOUSEWHEEL => {
             const delta = @as(i16, @truncate(@as(u16, @truncate(wParam >> 16))));
             const steps = delta / 120;
             if (steps != 0) {
                 pushEvent(sys.Event{ .scroll = .{ .dx = 0, .dy = steps } });
             }
             return 0;
         },
         WM_MOUSEHWHEEL => {
             const delta = @as(i16, @truncate(@as(u16, @truncate(wParam >> 16))));
             const steps = delta / 120;
             if (steps != 0) {
                 pushEvent(sys.Event{ .scroll = .{ .dx = steps, .dy = 0 } });
             }
             return 0;
         },
         else => {},
    }
    return WIN32.DefWindowProcA(hWnd, msg, wParam, lParam);
}

pub const Win32Display = struct {
    hwnd: usize,
    hdc: usize,
    mem_dc: usize,
    bmp: usize,
    w: u32,
    h: u32,
    fb: *gfx.Framebuffer,

    pub fn init(fb: *gfx.Framebuffer) ?Win32Display {
        if (!sys.is_windows) return null;
        const hInstance = @as(usize, @bitCast(@as(isize, -1)));
        var wc = WNDCLASSA{
            .style = CS_HREDRAW | CS_VREDRAW,
            .lpfnWndProc = wndProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = hInstance,
            .hIcon = 0,
            .hCursor = 0,
            .hbrBackground = 0,
            .lpszMenuName = "",
            .lpszClassName = "dhjsjsWin",
        };
        _ = WIN32.RegisterClassA(&wc);
        const hwnd = WIN32.CreateWindowExA(0, "dhjsjsWin", "dhjsjs GUI", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
            CW_USEDEFAULT, CW_USEDEFAULT, @as(i32, @intCast(fb.width)), @as(i32, @intCast(fb.height)),
            0, 0, hInstance, null);
        if (hwnd == 0) return null;
        const hdc = WIN32.GetDC(hwnd);
        const mem_dc = WIN32.CreateCompatibleDC(hdc);
        const bmp = WIN32.CreateCompatibleBitmap(hdc, @as(i32, @intCast(fb.width)), @as(i32, @intCast(fb.height)));
        _ = WIN32.SelectObject(mem_dc, bmp);
        g_hwnd = hwnd;
        g_hdc = hdc;
        g_mem_dc = mem_dc;
        g_bmp = bmp;
        g_fb = fb.pixels;
        g_w = fb.width;
        g_h = fb.height;
        return Win32Display{ .hwnd = hwnd, .hdc = hdc, .mem_dc = mem_dc, .bmp = bmp, .w = fb.width, .h = fb.height, .fb = fb };
    }

    pub fn present(self: *Win32Display) void {
        var bi = BITMAPINFO{
            .bmiHeader = BITMAPINFOHEADER{
                .biSize = @sizeOf(BITMAPINFOHEADER),
                .biWidth = @as(i32, @intCast(self.w)),
                .biHeight = -@as(i32, @intCast(self.h)),
                .biPlanes = 1,
                .biBitCount = 32,
                .biCompression = BI_RGB,
                .biSizeImage = self.w * self.h * 4,
                .biXPelsPerMeter = 0,
                .biYPelsPerMeter = 0,
                .biClrUsed = 0,
                .biClrImportant = 0,
            },
            .bmiColors = .{0},
        };
        _ = WIN32.SetDIBitsToDevice(self.mem_dc, 0, 0, self.w, self.h, 0, 0, 0, self.h, @as([*]const u8, @ptrCast(self.fb.pixels)), &bi, 0);
        _ = WIN32.BitBlt(self.hdc, 0, 0, @as(i32, @intCast(self.w)), @as(i32, @intCast(self.h)), self.mem_dc, 0, 0, SRCCOPY);
    }

    pub fn pollEvent(self: *Win32Display) ?sys.Event {
        _ = self;
        var msg: MSG = undefined;
        while (WIN32.PeekMessageA(&msg, 0, 0, 0, PM_REMOVE) != 0) {
            _ = WIN32.TranslateMessage(&msg);
            _ = WIN32.DispatchMessageA(&msg);
            if (msg.message == WM_QUIT) {
                pushEvent(sys.Event.close);
            }
        }
        if (g_ev_count > 0) {
            const ev = g_ev_buf[g_ev_head];
            g_ev_head = (g_ev_head + 1) % g_ev_buf.len;
            g_ev_count -= 1;
            return ev;
        }
        return null;
    }

    pub fn close(self: *Win32Display) void {
        _ = WIN32.DeleteObject(self.bmp);
        _ = WIN32.DeleteDC(self.mem_dc);
        _ = WIN32.ReleaseDC(self.hwnd, self.hdc);
        _ = WIN32.DestroyWindow(self.hwnd);
    }
};
