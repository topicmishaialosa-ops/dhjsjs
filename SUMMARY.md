# dhjsjs Project Summary

## Architecture
- **compiler.zig**: dhjsjs language compiler (x86-64 Linux machine code generator)
- **sys.zig**: System call wrappers (Linux + Windows Winsock)
- **render.zig**: Software framebuffer renderer with custom 8×8 bitmap font (scalable 2×–3×)
- **display.zig**: Display backend abstraction (X11, Wayland, fbdev, Win32, mem)
- **gui.zig**: GUI component system (widgets, layout, event handling, 30+ themes)
- **gui_render.zig**: Extended GUI rendering (glass panels, shadows, gradients)
- **mouse.zig**: GUI mouse input state library (buttons, wheel, drag, capture, double-click)
- **ide.zig**: Full-featured IDE built on Gui toolkit (tabs, file tree, canvas preview, syntax highlighting, console)
- **parser_mod.zig**: dhjsjs language parser
- **codegen.zig**: x86-64 machine code emitter
- **codegen_arm.zig**: ARM64 machine code emitter
- **win32.zig**: Windows GDI display backend
- **wayland.zig**: Wayland display server protocol
- **tty.zig**: Terminal (VT100/ANSI) display backend
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
- **compiler.zig**: 9 `jmpRel32` instructions had off-by-one `patch32` (5-byte jumps used 6-byte offset formula) — caused segfault in x11_open
- **gui.zig Canvas init**: X11 crash fixed — `gui.canvas` must be initialized with `gfx.Canvas.init(&fb)`, not `undefined`, otherwise `xconn` field is garbage leading to GP fault in `beginFrame`

## Inline Binary Dependencies (removed fork+exec)
- **audioplay**: Now calls `player_mod.playFile` directly (like `wavplay`/`mp3play`), no fork+exec
- **playerapp**: Forks + calls `media_player.main()` directly, no exec
- **guiApp/guiapp**: Forks + calls `gui_srv.main()` directly, no exec
- **guiServer/guiserver**: Forks + calls `gui_srv.main()` directly, removed /proc/self/environ envp setup (was only needed for execve)
- Dead `emitTlsClientX64` function removed (never called; TLS already inline)
- **Makefile**: Now only builds `dhjsjs` and `dhjsjs_cc` (all helper binaries removed)

## Font System
- Custom 8×8 bitmap font (hand-designed, 95 glyphs ASCII 32–126)
- FONT_W=8, FONT_H=8 (u8 per row)
- Redesigned glyphs for improved legibility — smoother curves on all letters, numbers, punctuation
- **Scaled rendering**: `Canvas.drawText` and `drawGlyphScaled` support arbitrary scale (size/8), enabling 16×16 (2×) and 24×24 (3×) rendering for IDE and GUI
- Consistently drawn across all display backends (X11, Wayland, TTY, Win32)

## GUI System (gui.zig / gui_render.zig)
- Immediate-mode widget tree with event propagation
- Components: Window, Button, Label, Slider, TextEdit, ScrollArea, Card, RadioButton, ProgressBar, ListBox, Tooltip, TabBar, ColorPicker, **Canvas** (reserved widget area)
- **canvasWidget()**: Allocates space in layout, returns CanvasHandle with `.rect`, `.hovered`, `.clicked`, `.dragging`, `.mx`, `.my`, `.fb` — for custom drawing inside Gui layouts
- Gradient-filled widgets with multi-layer soft shadows and glow effects
- Style system: 30 customizable fields (colors, rounding, shadow, spacing, padding)
- **StyleBuilder (Zig)**: chained API for building custom styles in code
- **setStyle(fd, id, val) builtin**: change any style field from dhjsjs language
- Theme presets: Dark, Light, Modern Dark, Modern Light, Diamond (purple), Tokyo Night, Catppuccin, Gruvbox, Everforest, Nord, Ayu, Material, Ocean, Forest, Retro Terminal, High Contrast, Monochrome, Rose Pine, Candy, Sunset, Gruvbox Light, Ayu Light, Material Light, Nord Light, Sakura, Washed, Coffee, Slate
- Full mouse layer via `mouse.zig`: primary/middle/secondary/X buttons, vertical/horizontal wheel, pressed/released/clicked flags, double-click detection, drag start/release, capture ownership, hit-test helpers
- Backends normalize input before GUI

## IDE (ide.zig)
- Full-featured native IDE built on the Gui toolkit
- **Architecture**: Gui layout (beginVertical/beginHorizontal) + styled widgets for chrome, canvasWidget + raw framebuffer drawing for editor text
- **Multiple tabs**: Each tab has its own content, cursor position, filename, modified flag, scroll offset
- **File tree sidebar**: Lists open files, click to switch tab, toggleable visibility
- **Syntax highlighting**: Keywords (`fn`, `hui`, `if`, `return`, `while`, etc.), strings, numbers, comments, functions — 5 highlight colors
- **Canvas preview tab**: When user code renders to a canvas framebuffer, displays pixels centered in the preview area
- **Toolbar**: [Build F5], [+ New], [Open], [Save] — clickable areas in the menu bar
- **Console panel**: Displays build output and status messages with auto-scroll
- **Status bar**: Line:column, modified indicator (●), status messages, file encoding
- **Input prompt**: File path entry overlay for open/save with Esc to cancel, Enter to confirm
- **Mouse support**: Click in editor to place cursor, click tabs to switch, click sidebar files to switch, click toolbar buttons
- **X11 backend**: Full Gui integration (mouse_state → InputState → beginFrame → paint → endFrame)
- **Wayland backend**: Same pipeline + evdev keyboard handling
- **TTY backend**: Falls back to terminal UI via tty.zig (accesses ide state via mirror fields)

## Canvas widget (dhjsjs builtin)
- `canvas()` in user code returns a Canvas object with drawing methods:
- `canvas.pixel(x, y, color)` — set pixel
- `canvas.rect(x, y, w, h, color)` — fill rectangle
- `canvas.circle(x, y, r, color)` — fill circle
- `canvas.line(x1, y1, x2, y2, color)` — draw line
- `canvas.text(x, y, str, color, size)` — draw text (scaled bitmap font)
- Integrated with IDE: canvas preview tab shows the rendered output in real time

## Sound/Audio
- `wavplay(path)` / `mp3play(path)` → fork media_player, wait (inline)
- `playerapp()` → fork media_player (detached, inline)
- `audioplay(freq, duration, ...)` → OSS /dev/dsp playback (direct call, no fork)
- `audio()` → configure audio format/channels/speed

## Android Support
- Builtins: android_width, android_height, android_fb_ptr, android_stride
- android_pixel(x, y, color), android_rect(x, y, w, h, color)
- android_touch_x, android_touch_y, android_touch_down
- android_clicked()/click_x()/click_y() — rising-edge click detection
- android_touch_count, android_touch_x/y/down/id_index(i) — multi-touch
- http.get/post — ARM64 inline (socket, DNS)
- APK build via `dhjsjs_cc build --target apk`
- AndroidCmd struct: extern layout (cross-architecture stable)

## Windows Port
- Win32 GDI backend in win32.zig (window, DIB section, keyboard/mouse events)
- Winsock support in sys.zig (conditional on is_windows)
- Win32 struct with extern declarations + Linux stubs
- Compiles on Linux (stub mode), untested on Windows host

## Known Limitations
- Win32 backend cannot be tested without a Windows host
- `http.get`/`http.post` always connect to default port 80 (no port argument in builtin)
- HTTPS requires `curl` installed on the target system (inline TLS is not implemented)
- `src/http.zig` is dead code (unused Zig HTTP library)
- IDE: fonts are scaled bitmaps (no TrueType), no bold/italic/antialiasing
- IDE: no file tree directory scanning (lists only open files)
- IDE: Wayland backend has basic keyboard support (evdev codes)
