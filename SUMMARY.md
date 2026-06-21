# dhjsjs Project Summary

## Architecture
- **compiler.zig**: dhjsjs language compiler (x86-64 Linux machine code generator)
- **sys.zig**: System call wrappers (Linux + Windows Winsock)
- **render.zig**: Software framebuffer renderer with custom 8×8 bitmap font
- **display.zig**: Display backend abstraction (X11, Wayland, fbdev, Win32, mem)
- **gui.zig**: GUI component system (widgets, layout, event handling)
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

## HTTP Client
- `http_client` binary: standalone Zig executable
  - Usage: `http_client <method> <host> [port] <path> [body]`
  - Methods: GET, POST, resolve (DNS via /etc/hosts, /etc/resolv.conf nameserver, fallback UDP query to 8.8.8.8:53)
  - Supports custom port via optional 3rd numeric argument
  - Uses sys.socket/connect/send/recv, sends HTTP/1.0 requests
- Compiler builtins (`compiler.zig:~2200-2520`):
  - `http.get(host, path)` / `http_get` / `httpget` → fork, pipe, exec http_client GET
  - `http.post(host, path, body)` / `http_post` / `httppost` → fork, pipe, exec http_client POST
  - `resolve(hostname)` / `resolve_hostname` → fork, pipe, exec http_client resolve → returns u32 IP
  - All three save args to registers before buffer allocation (avoids stack corruption after fork)
  - Response captured via pipe (read end in parent, write end dup2'd to child's stdout)
  - Response returned as stack-allocated string pointer (valid until next function call)
  - Parsed via `parser.zig` dotted call syntax (`http.get(...)` → detects `ident . ident (`)

## Bugfixes Applied
- HTTP client dotted-decimal detection fixed (oi==4 && hi==hlen check)
- HTTP client error message updated (removed "/etc/hosts or use IP" hint)
- `http.post`: `subRImm32(RSP, 4)` → `subRImm32(RSP, 8)` (pipe writes 8 bytes, was corrupting body pointer)
- `http.post`: args now saved to registers (R10/R9/R8) before buffer allocation (child was popping from buffer instead of args)
- `resolve`: `movRR(R9, RAX)` → `pushR(RAX)` (argv[0]="http_client" was never pushed, only "resolve" and hostname appeared)
- `sys.zig`: `closeSocket` fixed (was returning void as i32)
- guiServer infinite loop: jne target off-by-2 fixed
- Integer overflow in `gui.zig:1218`: `client_h -| 8`

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
- drawCard() helper for rendering card-style panels

## Sound/Audio
- `wavplay(path)` / `mp3play(path)` → fork media_player, wait
- `playerapp()` → fork media_player (detached)
- `audioplay(freq, duration, ...)` → OSS /dev/dsp playback
- `audio()` → configure audio format/channels/speed

## Android Support
- Builtins: android_width, android_height, android_fb_ptr, android_stride
- android_pixel(x, y, color), android_rect(x, y, w, h, color)
- android_touch_x, android_touch_y, android_touch_down
- android_http_get(ip, port, path) → performs HTTP GET request (ARM64 inline)
- android_http_post(ip, port, path, body) → performs HTTP POST request (ARM64 inline)
- APK build via `dhjsjs_cc build --target apk`

## Windows Port
- Win32 GDI backend in win32.zig (window, DIB section, keyboard/mouse events)
- Winsock support in sys.zig (conditional on is_windows)
- Win32 struct with extern declarations + Linux stubs
- Compiles on Linux (stub mode), untested on Windows host

## Known Limitations
- Win32 backend cannot be tested without a Windows host
- No TLS/HTTPS support
- `http.get`/`http.post` always connect to default port 80 (no port argument in builtin)
- Android HTTP builtins send HTTP/1.0 GET/POST over inline ARM64 socket syscalls, without fork+exec
- `src/http.zig` is dead code (unused Zig HTTP library)
