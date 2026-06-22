# dhjsjs Project Summary

## Architecture
- **compiler.zig**: dhjsjs language compiler (x86-64 Linux machine code generator)
- **sys.zig**: System call wrappers (Linux + Windows Winsock)
- **render.zig**: Software framebuffer renderer with custom 8×8 bitmap font
- **display.zig**: Display backend abstraction (X11, Wayland, fbdev, Win32, mem)
- **gui.zig**: GUI component system (widgets, layout, event handling)
- **mouse.zig**: GUI mouse input state library (buttons, wheel, drag, capture, double-click)
- **parser_mod.zig**: dhjsjs language parser
- **codegen.zig**: x86-64 machine code emitter
- **win32.zig**: Windows GDI display backend
- **wayland.zig**: Wayland display server protocol
- **http_client.zig**: Standalone HTTP client binary (used by compiler builtins)
- **http.zig**: Dead code (unused Zig helper, kept for reference)

## Display Backends
| Mode | Backend | Platform | Status |
|------|---------|----------|--------|
| 1    | X11     | Linux    | ✅ Mouse, keyboard, resize, close |
| 2    | fbdev   | Linux    | ✅ Basic framebuffer |
| 3    | memory  | Any      | ✅ Headless (framebuffer only) |
| 10   | Wayland | Linux    | ✅ Mouse, keyboard, close |
| 20   | Win32   | Windows  | ✅ Compiles on Linux (stub mode) |

## HTTP/HTTPS Client
- HTTP implementation uses three strategies depending on platform:
  - **x86-64 Linux**: `fork+exec http_client` for HTTP, `fork+exec curl` for HTTPS
  - **ARM64 (Android)**: Inline ARM64 syscalls (socket/connect/send/recv, inline UDP DNS) — no fork needed
- Compiler builtins:
  - `http.get(host, path)` / `http_get` / `httpget` — GET (x86: fork+exec http_client, ARM64: inline)
  - `http.post(host, path, body)` / `http_post` / `httppost` — POST
  - `https.get(host, path)` / `https_get` / `httpsget` — HTTPS GET via fork+exec curl
  - `https.post(host, path, body)` / `https_post` / `httpspost` — HTTPS POST via fork+exec curl
  - `resolve(hostname)` / `resolve_hostname` — DNS (x86: fork+exec, ARM64: inline UDP)
  - ARM64 inline DNS: UDP query to 8.8.8.8:53 via socket/sendto/ppoll/recvfrom, timeout 5s
  - ARM64 inline HTTP: DNS resolve → socket → connect → write → read loop → response pointer
  - HTTPS curl: pipe+fork+exec `/bin/sh -c "curl -s URL"` (requires curl on target)
  - All builtins save args to registers before buffer allocation
  - Response captured via pipe or stack pointer

## Bugfixes Applied
- HTTP client dotted-decimal detection fixed (oi==4 && hi==hlen check)
- HTTP client error message updated (removed "/etc/hosts or use IP" hint)
- `http.post`: `subRImm32(RSP, 4)` → `subRImm32(RSP, 8)` (pipe writes 8 bytes, was corrupting body pointer)
- `http.post`: args now saved to registers (R10/R9/R8) before buffer allocation (child was popping from buffer instead of args)
- `resolve`: `movRR(R9, RAX)` → `pushR(RAX)` (argv[0]="http_client" was never pushed, only "resolve" and hostname appeared)
- `sys.zig`: `closeSocket` fixed (was returning void as i32)
- guiServer infinite loop: jne target off-by-2 fixed
- Integer overflow in `gui.zig:1218`: `client_h -| 8`
- `codegen.zig:leaRMem`: REX prefix bits were swapped (x/b instead of r/b), causing `lea r14,[rsp]` to encode as `lea r14,[r12]`
- `emitInlineResolveX64`: host pointer (RAX) saved to R13 at function entry instead of reloading from clobbered RAX at DNS encoding loop
- `AndroidCmd` struct changed from `auto` to `extern` layout for deterministic cross-architecture offsets
- `compiler.zig`: fixed multi-touch offsets (touch_count 164→168, arrays +4) to match extern layout; changed loads to `movRMem32` (was `movRMem64`)
- `compiler.zig`: basic Android builtins (has_focus, should_finish, fb_width, etc.) accidentally matched extern layout but had undefined behavior under `auto` layout on non-x86 targets

## Font System
- Custom 8×8 bitmap font (hand-designed, 95 glyphs ASCII 32–126)
- FONT_W=8, FONT_H=8 (u8 per row, was u16 for old 10×16)
- drawText mask changed from u16 to u8
- Consistent across all display backends

## GPU/Framebuffer API (dhjsjs builtins)
- `fb_open(w, h)` → framebuffer object
- `fb_pixel(fb, x, y, color)` → set pixel
- `fb_fill(fb, x, y, w, h, color)` → fill rect
- `fb_close(fb)` → free framebuffer

## GUI System (gui.zig)
- Widget tree with event propagation
- Components: Window, Button, Label, Slider, TextEdit, ScrollArea, Card
- Style system with colors, fonts, window_rounding
- Modern theme presets: style_modern_dark, style_modern_light
- guiApp/guiapp builtin → fork+exec gui_srv
- setTheme(fd, theme_id) builtin for runtime theme switching
- setStyleColor(fd, field_index, color) builtin for per-field color override (0=BG,1=PANEL_BG,2=BTN_BG,3=BTN_HOVER,4=TEXT_COL,5=ACCENT,6=BORDER,7=CHECK_MARK,8=INPUT_BG,9=SEPARATOR)
- setStyleRounding(fd, rounding) builtin for widget corner rounding
- drawCard() helper for rendering card-style panels
- Full mouse layer via `mouse.zig`: primary/middle/secondary/X buttons, vertical/horizontal wheel, pressed/released/clicked flags, double-click detection, drag start/release, capture ownership, and hit-test helpers
- Backends normalize input before GUI: X11 ButtonPress/ButtonRelease/PointerMotion and wheel buttons 4-7, Wayland pointer enter/motion/button/axis, Win32 left/right/middle/X buttons and vertical/horizontal wheel

## Sound/Audio
- `wavplay(path)` / `mp3play(path)` → fork media_player, wait
- `playerapp()` → fork media_player (detached)
- `audioplay(freq, duration, ...)` → OSS /dev/dsp playback
- `audio()` → configure audio format/channels/speed

## Android Support
- Builtins: android_width, android_height, android_fb_ptr, android_stride
- android_pixel(x, y, color), android_rect(x, y, w, h, color)
- android_touch_x, android_touch_y, android_touch_down
- android_clicked()/click_x()/click_y() — rising-edge click detection (replaces manual `prev_touch` tracking)
- android_touch_count, android_touch_x/y/down/id_index(i) — multi-touch
- http.get(host, path) / http_get / httpget → HTTP GET (ARM64: inline, resolves hostname via UDP DNS)
- http.post(host, path, body) / http_post / httppost → HTTP POST (ARM64: inline)
- resolve(hostname) / resolve_hostname → DNS resolution (ARM64: inline UDP, x86: inline)
- android_http_get(ip, port, path) → legacy HTTP GET (ARM64, numeric IP only)
- android_http_post(ip, port, path, body) → legacy HTTP POST (ARM64, numeric IP only)
- APK build via `dhjsjs_cc build --target apk`
- AndroidCmd struct changed from `auto` to `extern` layout (fixed offsets, cross-architecture stable)

## Windows Port
- Win32 GDI backend in win32.zig (window, DIB section, keyboard/mouse events)
- Winsock support in sys.zig (conditional on is_windows)
- Win32 struct with extern declarations + Linux stubs
- Compiles on Linux (stub mode), untested on Windows host

## New Features
- `android_clicked()`, `android_click_x()`, `android_click_y()` builtins for x86-64 and ARM64 — no more manual `prev_touch` tracking in dhjsjs code
- ARM64 `android_gui.zig`: rising-edge click detection in render loop, stores click state in AndroidCmd
- All Android display/touch builtins ported to ARM64 compiler_arm.zig (was only `android_http_get/post` before)
  - New: `android_width`, `height`, `should_finish`, `has_focus`, `touch_x/y/down`, `fb_ptr`, `stride`, `pixel`, `rect`, `touch_count`, `_x_index`, `_y_index`, `_down_index`, `_id_index`, `clicked`, `click_x`, `click_y`
- `gui_android.dhjsjs` example simplified — uses `android_clicked()` instead of manual rising-edge pattern

## Known Limitations
- Win32 backend cannot be tested without a Windows host
- `http.get`/`http.post` always connect to default port 80 (no port argument in builtin)
- HTTPS requires `curl` installed on the target system (inline TLS is not implemented)
- `src/http.zig` is dead code (unused Zig HTTP library)
