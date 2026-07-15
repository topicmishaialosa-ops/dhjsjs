// ============================================================================
// gl3.zig — OpenGL 3.3 Core Profile GPU renderer
// libX11.so + libGL.so loaded at runtime via elf_loader — ZERO link-time deps
// ============================================================================

const sys = @import("sys.zig");
const elf = @import("elf_loader.zig");
const font_mod = @import("font.zig");

// ---------------------------------------------------------------------------
// X11 function pointers (loaded from libX11.so at runtime)
// ---------------------------------------------------------------------------
var XOpenDisplay_: *const fn (?[*:0]const u8) callconv(.c) ?*anyopaque = undefined;
var XDefaultScreen_: *const fn (*anyopaque) callconv(.c) i32 = undefined;
var XDefaultRootWindow_: *const fn (*anyopaque) callconv(.c) u64 = undefined;
var XDefaultVisual_: *const fn (*anyopaque, i32) callconv(.c) ?*anyopaque = undefined;
var XCreateWindow_: *const fn (*anyopaque, u64, i32, i32, u32, u32, u32, i32, u32, ?*anyopaque, u64, ?*anyopaque) callconv(.c) u64 = undefined;
var XMapWindow_: *const fn (*anyopaque, u64) callconv(.c) i32 = undefined;
var XStoreName_: *const fn (*anyopaque, u64, [*:0]const u8) callconv(.c) i32 = undefined;
var XSelectInput_: *const fn (*anyopaque, u64, i64) callconv(.c) i32 = undefined;
var XNextEvent_: *const fn (*anyopaque, *anyopaque) callconv(.c) i32 = undefined;
var XPending_: *const fn (*anyopaque) callconv(.c) i32 = undefined;
var XCloseDisplay_: *const fn (*anyopaque) callconv(.c) i32 = undefined;
var XDestroyWindow_: *const fn (*anyopaque, u64) callconv(.c) i32 = undefined;
var XFlush_: *const fn (*anyopaque) callconv(.c) i32 = undefined;
var XInternAtom_: *const fn (*anyopaque, [*:0]const u8, i32) callconv(.c) u64 = undefined;
var XChangeProperty_: *const fn (*anyopaque, u64, u64, u64, i32, i32, [*]const u8, i32) callconv(.c) i32 = undefined;

// ---------------------------------------------------------------------------
// GLX function pointers (loaded from libGL.so at runtime)
// ---------------------------------------------------------------------------
var glXChooseFBConfig_: *const fn (*anyopaque, i32, [*]const i32, *i32) callconv(.c) ?[*]u64 = undefined;
var glXGetVisualFromFBConfig_: *const fn (*anyopaque, u64) callconv(.c) ?*XVisualInfo = undefined;
var glXCreateWindow_: *const fn (*anyopaque, u64, u64, ?[*]const i32) callconv(.c) u64 = undefined;
var glXMakeCurrent_: *const fn (*anyopaque, u64, u64) callconv(.c) i32 = undefined;
var glXSwapBuffers_: *const fn (*anyopaque, u64) callconv(.c) void = undefined;
var glXDestroyContext_: *const fn (*anyopaque, u64) callconv(.c) void = undefined;
var glXDestroyWindow_: *const fn (*anyopaque, u64) callconv(.c) void = undefined;
var glXGetProcAddress_: *const fn ([*:0]const u8) callconv(.c) ?*const anyopaque = undefined;

// glXCreateContextAttribsARB (loaded via glXGetProcAddress)
const GlXCreateContextAttribsARB = *const fn (*anyopaque, u64, u64, i32, ?[*]const i32) callconv(.c) u64;
var glXCreateContextAttribsARB_: ?GlXCreateContextAttribsARB = null;

const XVisualInfo = extern struct {
    visual: ?*anyopaque,
    visualid: u64,
    screen: i32,
    depth: i32,
    class: i32,
    red_mask: u64,
    green_mask: u64,
    blue_mask: u64,
    colormap_size: i32,
    bits_per_rgb: i32,
};

// ---------------------------------------------------------------------------
// GL function pointers (loaded from libGL.so via glXGetProcAddress)
// ---------------------------------------------------------------------------
var glViewport_: *const fn (i32, i32, i32, i32) callconv(.c) void = undefined;
var glScissor_: *const fn (i32, i32, i32, i32) callconv(.c) void = undefined;
var glEnable_: *const fn (u32) callconv(.c) void = undefined;
var glDisable_: *const fn (u32) callconv(.c) void = undefined;
var glBlendFunc_: *const fn (u32, u32) callconv(.c) void = undefined;
var glClearColor_: *const fn (f32, f32, f32, f32) callconv(.c) void = undefined;
var glClear_: *const fn (u32) callconv(.c) void = undefined;

var glGenBuffers_: *const fn (i32, *u32) callconv(.c) void = undefined;
var glBindBuffer_: *const fn (u32, u32) callconv(.c) void = undefined;
var glBufferData_: *const fn (u32, isize, ?*const anyopaque, u32) callconv(.c) void = undefined;
var glDeleteBuffers_: *const fn (i32, [*]const u32) callconv(.c) void = undefined;

var glGenVertexArrays_: *const fn (i32, *u32) callconv(.c) void = undefined;
var glBindVertexArray_: *const fn (u32) callconv(.c) void = undefined;
var glDeleteVertexArrays_: *const fn (i32, [*]const u32) callconv(.c) void = undefined;
var glEnableVertexAttribArray_: *const fn (u32) callconv(.c) void = undefined;
var glDisableVertexAttribArray_: *const fn (u32) callconv(.c) void = undefined;
var glVertexAttribPointer_: *const fn (u32, i32, u32, u8, i32, ?*const anyopaque) callconv(.c) void = undefined;

var glGenTextures_: *const fn (i32, *u32) callconv(.c) void = undefined;
var glBindTexture_: *const fn (u32, u32) callconv(.c) void = undefined;
var glTexImage2D_: *const fn (u32, i32, i32, i32, i32, i32, u32, u32, ?*const anyopaque) callconv(.c) void = undefined;
var glTexParameteri_: *const fn (u32, u32, i32) callconv(.c) void = undefined;
var glDeleteTextures_: *const fn (i32, [*]const u32) callconv(.c) void = undefined;
var glActiveTexture_: *const fn (u32) callconv(.c) void = undefined;

var glCreateShader_: *const fn (u32) callconv(.c) u32 = undefined;
var glShaderSource_: *const fn (u32, i32, *const [*:0]const u8, ?*const i32) callconv(.c) void = undefined;
var glCompileShader_: *const fn (u32) callconv(.c) void = undefined;
var glCreateProgram_: *const fn () callconv(.c) u32 = undefined;
var glAttachShader_: *const fn (u32, u32) callconv(.c) void = undefined;
var glLinkProgram_: *const fn (u32) callconv(.c) void = undefined;
var glUseProgram_: *const fn (u32) callconv(.c) void = undefined;
var glGetShaderiv_: *const fn (u32, u32, *i32) callconv(.c) void = undefined;
var glGetProgramiv_: *const fn (u32, u32, *i32) callconv(.c) void = undefined;
var glGetShaderInfoLog_: *const fn (u32, i32, *i32, [*]u8) callconv(.c) void = undefined;
var glGetProgramInfoLog_: *const fn (u32, i32, *i32, [*]u8) callconv(.c) void = undefined;
var glDeleteShader_: *const fn (u32) callconv(.c) void = undefined;
var glDeleteProgram_: *const fn (u32) callconv(.c) void = undefined;
var glGetAttribLocation_: *const fn (u32, [*:0]const u8) callconv(.c) i32 = undefined;
var glGetUniformLocation_: *const fn (u32, [*:0]const u8) callconv(.c) i32 = undefined;
var glUniform1i_: *const fn (i32, i32) callconv(.c) void = undefined;
var glUniform4f_: *const fn (i32, f32, f32, f32, f32) callconv(.c) void = undefined;
var glUniformMatrix4fv_: *const fn (i32, i32, u8, [*]const f32) callconv(.c) void = undefined;
var glDrawArrays_: *const fn (u32, i32, i32) callconv(.c) void = undefined;

// ---------------------------------------------------------------------------
// GL constants
// ---------------------------------------------------------------------------
const GL_ARRAY_BUFFER: u32 = 0x8892;
const GL_STATIC_DRAW: u32 = 0x88E4;
const GL_DYNAMIC_DRAW: u32 = 0x88E8;
const GL_FLOAT: u32 = 0x1406;
const GL_UNSIGNED_BYTE: u32 = 0x1401;
const GL_TRIANGLES: u32 = 0x0004;
const GL_BLEND: u32 = 0x0BE2;
const GL_SRC_ALPHA: u32 = 0x0302;
const GL_ONE_MINUS_SRC_ALPHA: u32 = 0x0303;
const GL_TEXTURE_2D: u32 = 0x0DE1;
const GL_TEXTURE0: u32 = 0x84C0;
const GL_TEXTURE_MIN_FILTER: u32 = 0x2801;
const GL_TEXTURE_MAG_FILTER: u32 = 0x2800;
const GL_LINEAR: u32 = 0x2601;
const GL_NEAREST: u32 = 0x2600;
const GL_RGBA: u32 = 0x1908;
const GL_COLOR_BUFFER_BIT: u32 = 0x4000;
const GL_DEPTH_BUFFER_BIT: u32 = 0x0100;
const GL_VERTEX_SHADER: u32 = 0x8B31;
const GL_FRAGMENT_SHADER: u32 = 0x8B30;
const GL_COMPILE_STATUS: u32 = 0x8B81;
const GL_LINK_STATUS: u32 = 0x8B82;

// GLX constants
const GLX_RENDER_TYPE: u32 = 0x8011;
const GLX_RGBA_BIT: u32 = 0x00000001;
const GLX_DRAWABLE_TYPE: u32 = 0x8010;
const GLX_WINDOW_BIT: u32 = 0x00000001;
const GLX_RED_SIZE: u32 = 8;
const GLX_GREEN_SIZE: u32 = 9;
const GLX_BLUE_SIZE: u32 = 10;
const GLX_ALPHA_SIZE: u32 = 11;
const GLX_DEPTH_SIZE: u32 = 12;
const GLX_DOUBLEBUFFER: u32 = 5;
const GLX_NONE: u32 = 0x8000;

const GLX_CONTEXT_MAJOR_VERSION_ARB: u32 = 0x2091;
const GLX_CONTEXT_MINOR_VERSION_ARB: u32 = 0x2092;
const GLX_CONTEXT_FLAGS_ARB: u32 = 0x2094;
const GLX_CONTEXT_PROFILE_MASK_ARB: u32 = 0x9126;
const GLX_CONTEXT_CORE_PROFILE_BIT_ARB: u32 = 0x00000001;
const GLX_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB: u32 = 0x0002;

// X11 event masks
const KeyPressMask: u64 = 1;
const KeyReleaseMask: u64 = 2;
const ButtonPressMask: u64 = 4;
const ButtonReleaseMask: u64 = 8;
const PointerMotionMask: u64 = 64;
const ExposureMask: u64 = 32768;
const StructureNotifyMask: u64 = 131072;

// X11 event types
const KeyPress: u8 = 2;
const KeyRelease: u8 = 3;
const ButtonPress: u8 = 4;
const ButtonRelease: u8 = 5;
const MotionNotify: u8 = 6;
const ConfigureNotify: u8 = 22;
const ClientMessage: u8 = 33;

const XEvent = extern union {
    type_: u8,
    _pad: [95]u8,
};

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
var active = false;
var lib_x11: ?*elf.LibHandle = null;
var lib_gl: ?*elf.LibHandle = null;
var x_dpy: ?*anyopaque = null;
var x_screen: i32 = 0;
var x_win: u64 = 0;
var glx_drawable: u64 = 0;
var glx_ctx: u64 = 0;
var win_w: u32 = 0;
var win_h: u32 = 0;
var wm_delete_msg: u64 = 0;

// Batch renderer
var vao: u32 = 0;
var vbo: u32 = 0;
var shader_prog: u32 = 0;
var font_atlas_tex: u32 = 0;
var u_proj: i32 = -1;
var u_tex: i32 = -1;
var u_mode: i32 = -1;

var cur_mode: u32 = 0;
var cur_tex: u32 = 0;
var batch_count: u32 = 0;

const MAX_BATCH_VERTS: u32 = 65536;

var batch_verts: [*]Vertex = undefined;

const Vertex = extern struct {
    pos_x: f32,
    pos_y: f32,
    uv_x: f32,
    uv_y: f32,
    color: u32,
};

// ---------------------------------------------------------------------------
// Font atlas
// ---------------------------------------------------------------------------
const ATLAS_W = 512;
const ATLAS_H = 64;
const ATLAS_COLS = 32;

var atlas_uv_scale_x: f32 = 0;
var atlas_uv_scale_y: f32 = 0;

fn generateFontAtlas() [ATLAS_W * ATLAS_H * 4]u8 {
    var pixels: [ATLAS_W * ATLAS_H * 4]u8 = .{0} ** (ATLAS_W * ATLAS_H * 4);
    var gi: u32 = 0;
    while (gi < font_mod.GLYPH_COUNT) : (gi += 1) {
        const col = gi % ATLAS_COLS;
        const row = gi / ATLAS_COLS;
        const px = col * font_mod.FONT_W;
        const py = row * font_mod.FONT_H;
        const glyph_data = font_mod.fontData[gi * font_mod.FONT_H ..][0..font_mod.FONT_H];
        var y: u32 = 0;
        while (y < font_mod.FONT_H) : (y += 1) {
            const row_bits = glyph_data[y];
            var x: u32 = 0;
            while (x < font_mod.FONT_W) : (x += 1) {
                const bit = @as(u32, 1) << @intCast(15 - x);
                if ((row_bits & bit) != 0) {
                    const idx = ((py + y) * ATLAS_W + (px + x)) * 4;
                    pixels[idx] = 255;
                    pixels[idx + 1] = 255;
                    pixels[idx + 2] = 255;
                    pixels[idx + 3] = 255;
                }
            }
        }
    }
    return pixels;
}

// ---------------------------------------------------------------------------
// Shaders
// ---------------------------------------------------------------------------
const VS_SRC: [*:0]const u8 =
    \\#version 330 core
    \\layout(location=0) in vec2 aPos;
    \\layout(location=1) in vec2 aUV;
    \\layout(location=2) in vec4 aColor;
    \\uniform mat4 uProj;
    \\out vec2 vUV;
    \\out vec4 vColor;
    \\void main() {
    \\    gl_Position = uProj * vec4(aPos, 0.0, 1.0);
    \\    vUV = aUV;
    \\    vColor = aColor;
    \\}
    \\
;

const FS_SRC: [*:0]const u8 =
    \\#version 330 core
    \\in vec2 vUV;
    \\in vec4 vColor;
    \\uniform sampler2D uTex;
    \\uniform int uMode;
    \\out vec4 fragColor;
    \\void main() {
    \\    if (uMode == 0) {
    \\        fragColor = vColor;
    \\    } else if (uMode == 1) {
    \\        fragColor = texture(uTex, vUV) * vColor;
    \\    } else {
    \\        float d = texture(uTex, vUV).a;
    \\        float a = smoothstep(0.4, 0.6, d);
    \\        fragColor = vec4(vColor.rgb, vColor.a * a);
    \\    }
    \\}
    \\
;

fn compileShader(src: [*:0]const u8, typ: u32) u32 {
    const s = glCreateShader_(typ);
    if (s == 0) return 0;
    glShaderSource_(s, 1, @ptrCast(&src), null);
    glCompileShader_(s);
    var status: i32 = 0;
    glGetShaderiv_(s, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        var log_buf: [512]u8 = undefined;
        var log_len: i32 = 0;
        glGetShaderInfoLog_(s, 512, &log_len, &log_buf);
        glDeleteShader_(s);
        return 0;
    }
    return s;
}

fn linkProg(vs: u32, fs: u32) u32 {
    const p = glCreateProgram_();
    if (p == 0) return 0;
    glAttachShader_(p, vs);
    glAttachShader_(p, fs);
    glLinkProgram_(p);
    var status: i32 = 0;
    glGetProgramiv_(p, GL_LINK_STATUS, &status);
    if (status == 0) {
        glDeleteProgram_(p);
        return 0;
    }
    return p;
}

// ---------------------------------------------------------------------------
// Projection matrix (column-major)
// ---------------------------------------------------------------------------
fn orthoMatrix(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) [16]f32 {
    return .{
        2.0 / (right - left), 0, 0, 0,
        0, 2.0 / (top - bottom), 0, 0,
        0, 0, -2.0 / (far - near), 0,
        -(right + left) / (right - left), -(top + bottom) / (top - bottom), -(far + near) / (far - near), 1.0,
    };
}

// ---------------------------------------------------------------------------
// Color packing
// ---------------------------------------------------------------------------
fn packColor(r: u8, g: u8, b: u8, a: u8) u32 {
    return @as(u32, a) << 24 | @as(u32, b) << 16 | @as(u32, g) << 8 | @as(u32, r);
}

fn packU32(color: u32) u32 {
    const a: u8 = @truncate(color >> 24);
    const r: u8 = @truncate(color >> 16);
    const g: u8 = @truncate(color >> 8);
    const b: u8 = @truncate(color);
    return packColor(r, g, b, a);
}

// ---------------------------------------------------------------------------
// Math
// ---------------------------------------------------------------------------
fn mathSin(x: f32) f32 {
    var v = x;
    const pi: f32 = 3.14159265;
    while (v > pi) v -= 2 * pi;
    while (v < -pi) v += 2 * pi;
    const v2 = v * v;
    return v - v * v2 / 6.0 + v * v2 * v2 / 120.0 - v * v2 * v2 * v2 / 5040.0 + v * v2 * v2 * v2 * v2 / 362880.0;
}

fn mathCos(x: f32) f32 {
    return mathSin(x + 1.5707963);
}

// ---------------------------------------------------------------------------
// Batch internals
// ---------------------------------------------------------------------------
fn flushBatch() void {
    if (batch_count == 0) return;
    glBufferData_(GL_ARRAY_BUFFER, @intCast(@as(u64, batch_count) * @sizeOf(Vertex)), batch_verts, GL_DYNAMIC_DRAW);
    glDrawArrays_(GL_TRIANGLES, 0, @intCast(batch_count));
    batch_count = 0;
}

fn ensureCap(needed: u32) void {
    if (batch_count + needed > MAX_BATCH_VERTS) flushBatch();
}

fn pushVert(x: f32, y: f32, u: f32, v: f32, color: u32) void {
    const vert = &batch_verts[batch_count];
    vert.pos_x = x;
    vert.pos_y = y;
    vert.uv_x = u;
    vert.uv_y = v;
    vert.color = color;
    batch_count += 1;
}

fn setTex(tex: u32) void {
    if (cur_tex != tex) {
        flushBatch();
        cur_tex = tex;
        if (tex != 0) {
            glActiveTexture_(GL_TEXTURE0);
            glBindTexture_(GL_TEXTURE_2D, tex);
            glUniform1i_(u_tex, 0);
        }
    }
}

fn setMode(mode: u32) void {
    if (cur_mode != mode) {
        flushBatch();
        cur_mode = mode;
        glUniform1i_(u_mode, @intCast(mode));
    }
}

// ---------------------------------------------------------------------------
// libGL.so function loading via glXGetProcAddress
// ---------------------------------------------------------------------------
fn loadGL(comptime T: type, name: [*:0]const u8) ?T {
    const ptr = glXGetProcAddress_(name) orelse return null;
    return @as(T, @ptrCast(@alignCast(ptr)));
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn init(w: u32, h: u32) bool {
    if (active) return true;

    // Load libX11.so at runtime
    lib_x11 = elf.open("libX11.so") orelse return false;
    XOpenDisplay_ = @as(@TypeOf(XOpenDisplay_), @ptrCast(@alignCast(elf.findSymbol(lib_x11.?, "XOpenDisplay") orelse return false)));
    XDefaultScreen_ = @as(@TypeOf(XDefaultScreen_), @ptrCast(@alignCast(elf.findSymbol(lib_x11.?, "XDefaultScreen") orelse return false)));
    XDefaultRootWindow_ = @as(@TypeOf(XDefaultRootWindow_), @ptrCast(@alignCast(elf.findSymbol(lib_x11.?, "XDefaultRootWindow") orelse return false)));
    XCreateWindow_ = @as(@TypeOf(XCreateWindow_), @ptrCast(@alignCast(elf.findSymbol(lib_x11.?, "XCreateWindow") orelse return false)));
    XMapWindow_ = @as(@TypeOf(XMapWindow_), @ptrCast(@alignCast(elf.findSymbol(lib_x11.?, "XMapWindow") orelse return false)));
    XStoreName_ = @as(@TypeOf(XStoreName_), @ptrCast(@alignCast(elf.findSymbol(lib_x11.?, "XStoreName") orelse return false)));
    XSelectInput_ = @as(@TypeOf(XSelectInput_), @ptrCast(@alignCast(elf.findSymbol(lib_x11.?, "XSelectInput") orelse return false)));
    XNextEvent_ = @as(@TypeOf(XNextEvent_), @ptrCast(@alignCast(elf.findSymbol(lib_x11.?, "XNextEvent") orelse return false)));
    XPending_ = @as(@TypeOf(XPending_), @ptrCast(@alignCast(elf.findSymbol(lib_x11.?, "XPending") orelse return false)));
    XCloseDisplay_ = @as(@TypeOf(XCloseDisplay_), @ptrCast(@alignCast(elf.findSymbol(lib_x11.?, "XCloseDisplay") orelse return false)));
    XDestroyWindow_ = @as(@TypeOf(XDestroyWindow_), @ptrCast(@alignCast(elf.findSymbol(lib_x11.?, "XDestroyWindow") orelse return false)));
    XFlush_ = @as(@TypeOf(XFlush_), @ptrCast(@alignCast(elf.findSymbol(lib_x11.?, "XFlush") orelse return false)));
    XInternAtom_ = @as(@TypeOf(XInternAtom_), @ptrCast(@alignCast(elf.findSymbol(lib_x11.?, "XInternAtom") orelse return false)));
    XChangeProperty_ = @as(@TypeOf(XChangeProperty_), @ptrCast(@alignCast(elf.findSymbol(lib_x11.?, "XChangeProperty") orelse return false)));

    // Load libGL.so at runtime
    lib_gl = elf.open("libGL.so") orelse return false;
    glXChooseFBConfig_ = @as(@TypeOf(glXChooseFBConfig_), @ptrCast(@alignCast(elf.findSymbol(lib_gl.?, "glXChooseFBConfig") orelse return false)));
    glXGetVisualFromFBConfig_ = @as(@TypeOf(glXGetVisualFromFBConfig_), @ptrCast(@alignCast(elf.findSymbol(lib_gl.?, "glXGetVisualFromFBConfig") orelse return false)));
    glXCreateWindow_ = @as(@TypeOf(glXCreateWindow_), @ptrCast(@alignCast(elf.findSymbol(lib_gl.?, "glXCreateWindow") orelse return false)));
    glXMakeCurrent_ = @as(@TypeOf(glXMakeCurrent_), @ptrCast(@alignCast(elf.findSymbol(lib_gl.?, "glXMakeCurrent") orelse return false)));
    glXSwapBuffers_ = @as(@TypeOf(glXSwapBuffers_), @ptrCast(@alignCast(elf.findSymbol(lib_gl.?, "glXSwapBuffers") orelse return false)));
    glXDestroyContext_ = @as(@TypeOf(glXDestroyContext_), @ptrCast(@alignCast(elf.findSymbol(lib_gl.?, "glXDestroyContext") orelse return false)));
    glXDestroyWindow_ = @as(@TypeOf(glXDestroyWindow_), @ptrCast(@alignCast(elf.findSymbol(lib_gl.?, "glXDestroyWindow") orelse return false)));
    glXGetProcAddress_ = @as(@TypeOf(glXGetProcAddress_), @ptrCast(@alignCast(elf.findSymbol(lib_gl.?, "glXGetProcAddress") orelse return false)));

    // Load GL functions via glXGetProcAddress
    glViewport_ = loadGL(@TypeOf(glViewport_), "glViewport") orelse return false;
    glScissor_ = loadGL(@TypeOf(glScissor_), "glScissor") orelse return false;
    glEnable_ = loadGL(@TypeOf(glEnable_), "glEnable") orelse return false;
    glDisable_ = loadGL(@TypeOf(glDisable_), "glDisable") orelse return false;
    glBlendFunc_ = loadGL(@TypeOf(glBlendFunc_), "glBlendFunc") orelse return false;
    glClearColor_ = loadGL(@TypeOf(glClearColor_), "glClearColor") orelse return false;
    glClear_ = loadGL(@TypeOf(glClear_), "glClear") orelse return false;
    glGenBuffers_ = loadGL(@TypeOf(glGenBuffers_), "glGenBuffers") orelse return false;
    glBindBuffer_ = loadGL(@TypeOf(glBindBuffer_), "glBindBuffer") orelse return false;
    glBufferData_ = loadGL(@TypeOf(glBufferData_), "glBufferData") orelse return false;
    glDeleteBuffers_ = loadGL(@TypeOf(glDeleteBuffers_), "glDeleteBuffers") orelse return false;
    glGenVertexArrays_ = loadGL(@TypeOf(glGenVertexArrays_), "glGenVertexArrays") orelse return false;
    glBindVertexArray_ = loadGL(@TypeOf(glBindVertexArray_), "glBindVertexArray") orelse return false;
    glDeleteVertexArrays_ = loadGL(@TypeOf(glDeleteVertexArrays_), "glDeleteVertexArrays") orelse return false;
    glEnableVertexAttribArray_ = loadGL(@TypeOf(glEnableVertexAttribArray_), "glEnableVertexAttribArray") orelse return false;
    glDisableVertexAttribArray_ = loadGL(@TypeOf(glDisableVertexAttribArray_), "glDisableVertexAttribArray") orelse return false;
    glVertexAttribPointer_ = loadGL(@TypeOf(glVertexAttribPointer_), "glVertexAttribPointer") orelse return false;
    glGenTextures_ = loadGL(@TypeOf(glGenTextures_), "glGenTextures") orelse return false;
    glBindTexture_ = loadGL(@TypeOf(glBindTexture_), "glBindTexture") orelse return false;
    glTexImage2D_ = loadGL(@TypeOf(glTexImage2D_), "glTexImage2D") orelse return false;
    glTexParameteri_ = loadGL(@TypeOf(glTexParameteri_), "glTexParameteri") orelse return false;
    glDeleteTextures_ = loadGL(@TypeOf(glDeleteTextures_), "glDeleteTextures") orelse return false;
    glActiveTexture_ = loadGL(@TypeOf(glActiveTexture_), "glActiveTexture") orelse return false;
    glCreateShader_ = loadGL(@TypeOf(glCreateShader_), "glCreateShader") orelse return false;
    glShaderSource_ = loadGL(@TypeOf(glShaderSource_), "glShaderSource") orelse return false;
    glCompileShader_ = loadGL(@TypeOf(glCompileShader_), "glCompileShader") orelse return false;
    glCreateProgram_ = loadGL(@TypeOf(glCreateProgram_), "glCreateProgram") orelse return false;
    glAttachShader_ = loadGL(@TypeOf(glAttachShader_), "glAttachShader") orelse return false;
    glLinkProgram_ = loadGL(@TypeOf(glLinkProgram_), "glLinkProgram") orelse return false;
    glUseProgram_ = loadGL(@TypeOf(glUseProgram_), "glUseProgram") orelse return false;
    glGetShaderiv_ = loadGL(@TypeOf(glGetShaderiv_), "glGetShaderiv") orelse return false;
    glGetProgramiv_ = loadGL(@TypeOf(glGetProgramiv_), "glGetProgramiv") orelse return false;
    glGetShaderInfoLog_ = loadGL(@TypeOf(glGetShaderInfoLog_), "glGetShaderInfoLog") orelse return false;
    glGetProgramInfoLog_ = loadGL(@TypeOf(glGetProgramInfoLog_), "glGetProgramInfoLog") orelse return false;
    glDeleteShader_ = loadGL(@TypeOf(glDeleteShader_), "glDeleteShader") orelse return false;
    glDeleteProgram_ = loadGL(@TypeOf(glDeleteProgram_), "glDeleteProgram") orelse return false;
    glGetAttribLocation_ = loadGL(@TypeOf(glGetAttribLocation_), "glGetAttribLocation") orelse return false;
    glGetUniformLocation_ = loadGL(@TypeOf(glGetUniformLocation_), "glGetUniformLocation") orelse return false;
    glUniform1i_ = loadGL(@TypeOf(glUniform1i_), "glUniform1i") orelse return false;
    glUniform4f_ = loadGL(@TypeOf(glUniform4f_), "glUniform4f") orelse return false;
    glUniformMatrix4fv_ = loadGL(@TypeOf(glUniformMatrix4fv_), "glUniformMatrix4fv") orelse return false;
    glDrawArrays_ = loadGL(@TypeOf(glDrawArrays_), "glDrawArrays") orelse return false;

    // Load glXCreateContextAttribsARB extension
    glXCreateContextAttribsARB_ = @as(GlXCreateContextAttribsARB, @ptrCast(@alignCast(
        glXGetProcAddress_("glXCreateContextAttribsARB") orelse return false,
    )));

    // Open X11 display
    x_dpy = XOpenDisplay_(null) orelse return false;
    x_screen = XDefaultScreen_(x_dpy.?);
    const x_root = XDefaultRootWindow_(x_dpy.?);

    // Choose GLX FBConfig
    var fb_attribs = [_]i32{
        @intCast(GLX_RENDER_TYPE), @intCast(GLX_RGBA_BIT),
        @intCast(GLX_DRAWABLE_TYPE), @intCast(GLX_WINDOW_BIT),
        @intCast(GLX_RED_SIZE), 8,
        @intCast(GLX_GREEN_SIZE), 8,
        @intCast(GLX_BLUE_SIZE), 8,
        @intCast(GLX_ALPHA_SIZE), 8,
        @intCast(GLX_DEPTH_SIZE), 24,
        @intCast(GLX_DOUBLEBUFFER), 1,
        GLX_NONE,
    };
    var num_configs: i32 = 0;
    const configs = glXChooseFBConfig_(x_dpy.?, x_screen, &fb_attribs, &num_configs) orelse return false;
    if (num_configs == 0) return false;
    const config = configs[0];

    // Get visual for window
    const vis_info = glXGetVisualFromFBConfig_(x_dpy.?, config) orelse return false;
    const visual = vis_info.visual orelse return false;

    // Create window
    x_win = XCreateWindow_(x_dpy.?, x_root, 0, 0, w, h, 0, 24, 1, visual, 0x2082, null);
    if (x_win == 0) return false;

    _ = XStoreName_(x_dpy.?, x_win, "dhjsjs OpenGL 3.3");
    _ = XSelectInput_(x_dpy.?, x_win, @intCast(KeyPressMask | KeyReleaseMask | ButtonPressMask | ButtonReleaseMask | PointerMotionMask | ExposureMask | StructureNotifyMask));
    _ = XMapWindow_(x_dpy.?, x_win);
    _ = XFlush_(x_dpy.?);

    // WM_DELETE_WINDOW
    wm_delete_msg = XInternAtom_(x_dpy.?, "WM_DELETE_WINDOW", 0);
    _ = XChangeProperty_(x_dpy.?, x_win, XInternAtom_(x_dpy.?, "WM_PROTOCOLS", 0), 6, 32, 0, @ptrCast(&wm_delete_msg), 1);

    // Create GLX drawable + context
    glx_drawable = glXCreateWindow_(x_dpy.?, config, x_win, null);
    if (glx_drawable == 0) return false;

    var ctx_attribs = [_]i32{
        @intCast(GLX_CONTEXT_MAJOR_VERSION_ARB), 3,
        @intCast(GLX_CONTEXT_MINOR_VERSION_ARB), 3,
        @intCast(GLX_CONTEXT_FLAGS_ARB), @intCast(GLX_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB),
        @intCast(GLX_CONTEXT_PROFILE_MASK_ARB), @intCast(GLX_CONTEXT_CORE_PROFILE_BIT_ARB),
        0,
    };
    glx_ctx = glXCreateContextAttribsARB_.?(x_dpy.?, config, 0, 1, &ctx_attribs);
    if (glx_ctx == 0) return false;
    if (glXMakeCurrent_(x_dpy.?, glx_drawable, glx_ctx) == 0) return false;

    win_w = w;
    win_h = h;

    // GL state
    glViewport_(0, 0, @intCast(w), @intCast(h));
    glEnable_(GL_BLEND);
    glBlendFunc_(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    // Shaders
    const vs = compileShader(VS_SRC, GL_VERTEX_SHADER);
    const fs = compileShader(FS_SRC, GL_FRAGMENT_SHADER);
    if (vs == 0 or fs == 0) return false;
    shader_prog = linkProg(vs, fs);
    if (shader_prog == 0) return false;
    glDeleteShader_(vs);
    glDeleteShader_(fs);

    u_proj = glGetUniformLocation_(shader_prog, "uProj");
    u_tex = glGetUniformLocation_(shader_prog, "uTex");
    u_mode = glGetUniformLocation_(shader_prog, "uMode");

    glUseProgram_(shader_prog);
    const proj = orthoMatrix(0, @floatFromInt(w), @floatFromInt(h), 0, -1, 1);
    glUniformMatrix4fv_(u_proj, 1, 0, &proj);
    glUniform1i_(u_tex, 0);
    glUniform1i_(u_mode, 0);

    // VAO + VBO
    glGenVertexArrays_(1, &vao);
    glBindVertexArray_(vao);
    glGenBuffers_(1, &vbo);
    glBindBuffer_(GL_ARRAY_BUFFER, vbo);
    glBufferData_(GL_ARRAY_BUFFER, @intCast(MAX_BATCH_VERTS * @sizeOf(Vertex)), null, GL_DYNAMIC_DRAW);

    glEnableVertexAttribArray_(0);
    glVertexAttribPointer_(0, 2, GL_FLOAT, 0, @intCast(@sizeOf(Vertex)), @ptrFromInt(0));
    glEnableVertexAttribArray_(1);
    glVertexAttribPointer_(1, 2, GL_FLOAT, 0, @intCast(@sizeOf(Vertex)), @ptrFromInt(8));
    glEnableVertexAttribArray_(2);
    glVertexAttribPointer_(2, 4, GL_UNSIGNED_BYTE, 1, @intCast(@sizeOf(Vertex)), @ptrFromInt(16));

    // Batch buffer
    const batch_mem = sys.mmap(null, MAX_BATCH_VERTS * @sizeOf(Vertex), sys.PROT_READ | sys.PROT_WRITE, 0x02 | 0x20, -1, 0) orelse return false;
    batch_verts = @ptrCast(@alignCast(batch_mem));

    // Font atlas
    const atlas_pixels = generateFontAtlas();
    glGenTextures_(1, &font_atlas_tex);
    glBindTexture_(GL_TEXTURE_2D, font_atlas_tex);
    glTexParameteri_(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, @intCast(GL_LINEAR));
    glTexParameteri_(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, @intCast(GL_LINEAR));
    glTexImage2D_(GL_TEXTURE_2D, 0, @intCast(GL_RGBA), ATLAS_W, ATLAS_H, 0, GL_RGBA, GL_UNSIGNED_BYTE, &atlas_pixels);

    atlas_uv_scale_x = 1.0 / @as(f32, ATLAS_W);
    atlas_uv_scale_y = 1.0 / @as(f32, ATLAS_H);

    active = true;
    return true;
}

pub fn deinit() void {
    if (!active) return;
    active = false;
    flushBatch();
    if (glx_drawable != 0) glXDestroyWindow_(x_dpy.?, glx_drawable);
    if (glx_ctx != 0) glXDestroyContext_(x_dpy.?, glx_ctx);
    if (vbo != 0) { const b = [_]u32{vbo}; glDeleteBuffers_(1, &b); }
    if (vao != 0) { const a = [_]u32{vao}; glDeleteVertexArrays_(1, &a); }
    if (shader_prog != 0) glDeleteProgram_(shader_prog);
    if (font_atlas_tex != 0) { const t = [_]u32{font_atlas_tex}; glDeleteTextures_(1, &t); }
    sys.munmap(@ptrCast(batch_verts), MAX_BATCH_VERTS * @sizeOf(Vertex));
    if (x_win != 0) _ = XDestroyWindow_(x_dpy.?, x_win);
    if (x_dpy) |dpy| { _ = XCloseDisplay_(dpy); x_dpy = null; }
    lib_gl = null;
    lib_x11 = null;
}

pub fn beginFrame() void {
    if (!active) return;
    glClearColor_(0.12, 0.12, 0.14, 1.0);
    glClear_(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    batch_count = 0;
    cur_tex = 0;
    cur_mode = 0;
    glUseProgram_(shader_prog);
    glBindVertexArray_(vao);
    glBindBuffer_(GL_ARRAY_BUFFER, vbo);
    glUniform1i_(u_mode, 0);
}

pub fn endFrame() void {
    if (!active) return;
    flushBatch();
    glXSwapBuffers_(x_dpy.?, glx_drawable);
}

pub fn pollEvent() ?Event {
    if (!active or x_dpy == null) return null;
    while (XPending_(x_dpy.?) > 0) {
        var ev: XEvent = undefined;
        _ = XNextEvent_(x_dpy.?, &ev);
        const t = ev.type_;
        if (t == KeyPress) return .{ .key_press = ev._pad[43] };
        if (t == KeyRelease) return .{ .key_release = ev._pad[43] };
        if (t == ButtonPress) {
            const mx = @as(i16, @bitCast(@as(u16, ev._pad[16] | (@as(u16, ev._pad[17]) << 8))));
            const my = @as(i16, @bitCast(@as(u16, ev._pad[20] | (@as(u16, ev._pad[21]) << 8))));
            return .{ .mouse_down = .{ .x = mx, .y = my, .button = ev._pad[41] } };
        }
        if (t == ButtonRelease) {
            const mx = @as(i16, @bitCast(@as(u16, ev._pad[16] | (@as(u16, ev._pad[17]) << 8))));
            const my = @as(i16, @bitCast(@as(u16, ev._pad[20] | (@as(u16, ev._pad[21]) << 8))));
            return .{ .mouse_up = .{ .x = mx, .y = my, .button = ev._pad[41] } };
        }
        if (t == MotionNotify) {
            const mx = @as(i16, @bitCast(@as(u16, ev._pad[16] | (@as(u16, ev._pad[17]) << 8))));
            const my = @as(i16, @bitCast(@as(u16, ev._pad[20] | (@as(u16, ev._pad[21]) << 8))));
            return .{ .mouse_move = .{ .x = mx, .y = my } };
        }
        if (t == ConfigureNotify) {
            const nw = @as(u16, @bitCast(@as(i16, @bitCast(@as(u16, ev._pad[18] | (@as(u16, ev._pad[19]) << 8))))));
            const nh = @as(u16, @bitCast(@as(i16, @bitCast(@as(u16, ev._pad[20] | (@as(u16, ev._pad[21]) << 8))))));
            if (nw != win_w or nh != win_h) {
                win_w = nw;
                win_h = nh;
                glViewport_(0, 0, @intCast(win_w), @intCast(win_h));
                const proj = orthoMatrix(0, @floatFromInt(win_w), @floatFromInt(win_h), 0, -1, 1);
                glUseProgram_(shader_prog);
                glUniformMatrix4fv_(u_proj, 1, 0, &proj);
            }
            return .{ .resize = .{ .w = win_w, .h = win_h } };
        }
        if (t == ClientMessage) {
            const d0 = @as(u64, ev._pad[36]) | (@as(u64, ev._pad[37]) << 8) | (@as(u64, ev._pad[38]) << 16) | (@as(u64, ev._pad[39]) << 24);
            if (d0 == wm_delete_msg) return .close;
        }
    }
    return null;
}

pub fn resize(w: u32, h: u32) void {
    if (!active) return;
    win_w = w;
    win_h = h;
    glViewport_(0, 0, @intCast(w), @intCast(h));
    const proj = orthoMatrix(0, @floatFromInt(w), @floatFromInt(h), 0, -1, 1);
    glUseProgram_(shader_prog);
    glUniformMatrix4fv_(u_proj, 1, 0, &proj);
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------
pub fn fillRect(x: i32, y: i32, w: i32, h: i32, color: u32) void {
    if (!active or w <= 0 or h <= 0) return;
    setTex(0);
    setMode(0);
    ensureCap(6);
    const c = packU32(color);
    const x1: f32 = @floatFromInt(x);
    const y1: f32 = @floatFromInt(y);
    const x2: f32 = @floatFromInt(x + w);
    const y2: f32 = @floatFromInt(y + h);
    pushVert(x1, y1, 0, 0, c);
    pushVert(x2, y1, 1, 0, c);
    pushVert(x1, y2, 0, 1, c);
    pushVert(x2, y1, 1, 0, c);
    pushVert(x2, y2, 1, 1, c);
    pushVert(x1, y2, 0, 1, c);
}

pub fn fillGradientH(x: i32, y: i32, w: i32, h: i32, c1: u32, c2: u32) void {
    if (!active or w <= 0 or h <= 0) return;
    setTex(0);
    setMode(0);
    ensureCap(6);
    const left = packU32(c1);
    const right = packU32(c2);
    const x1: f32 = @floatFromInt(x);
    const y1: f32 = @floatFromInt(y);
    const x2: f32 = @floatFromInt(x + w);
    const y2: f32 = @floatFromInt(y + h);
    pushVert(x1, y1, 0, 0, left);
    pushVert(x2, y1, 1, 0, right);
    pushVert(x1, y2, 0, 1, left);
    pushVert(x2, y1, 1, 0, right);
    pushVert(x2, y2, 1, 1, right);
    pushVert(x1, y2, 0, 1, left);
}

pub fn fillGradientV(x: i32, y: i32, w: i32, h: i32, c1: u32, c2: u32) void {
    if (!active or w <= 0 or h <= 0) return;
    setTex(0);
    setMode(0);
    ensureCap(6);
    const top = packU32(c1);
    const bot = packU32(c2);
    const x1: f32 = @floatFromInt(x);
    const y1: f32 = @floatFromInt(y);
    const x2: f32 = @floatFromInt(x + w);
    const y2: f32 = @floatFromInt(y + h);
    pushVert(x1, y1, 0, 0, top);
    pushVert(x2, y1, 1, 0, top);
    pushVert(x1, y2, 0, 1, bot);
    pushVert(x2, y1, 1, 0, top);
    pushVert(x2, y2, 1, 1, bot);
    pushVert(x1, y2, 0, 1, bot);
}

pub fn drawBorder(x: i32, y: i32, w: i32, h: i32, color: u32, t: i32) void {
    fillRect(x, y, w, t, color);
    fillRect(x, y + h - t, w, t, color);
    fillRect(x, y + t, t, h - t * 2, color);
    fillRect(x + w - t, y + t, t, h - t * 2, color);
}

pub fn fillRoundedRect(x: i32, y: i32, w: i32, h: i32, r: i32, color: u32) void {
    if (!active or w <= 0 or h <= 0) return;
    const c = packU32(color);
    setTex(0);
    setMode(0);
    if (w > r * 2 and h > r * 2) fillRect(x + r, y, w - r * 2, h, color);
    if (r > 0) {
        fillRect(x, y + r, r, h - r * 2, color);
        fillRect(x + w - r, y + r, r, h - r * 2, color);
    }
    for (0..4) |corner| {
        const cx: f32 = @floatFromInt(x + if (corner == 1 or corner == 3) w - r else r);
        const cy: f32 = @floatFromInt(y + if (corner == 2 or corner == 3) h - r else r);
        const rf: f32 = @floatFromInt(r);
        const flip_x = corner == 1 or corner == 3;
        const flip_y = corner == 2 or corner == 3;
        for (0..8) |i| {
            const a1 = @as(f32, @floatFromInt(i)) / 8.0 * 1.570796;
            const a2 = @as(f32, @floatFromInt(i + 1)) / 8.0 * 1.570796;
            var sx1 = mathCos(a1);
            var sy1 = mathSin(a1);
            var sx2 = mathCos(a2);
            var sy2 = mathSin(a2);
            if (flip_x) { sx1 = -sx1; sx2 = -sx2; }
            if (flip_y) { sy1 = -sy1; sy2 = -sy2; }
            ensureCap(3);
            pushVert(cx, cy, 0, 0, c);
            pushVert(cx + sx1 * rf, cy + sy1 * rf, 0, 0, c);
            pushVert(cx + sx2 * rf, cy + sy2 * rf, 0, 0, c);
        }
    }
}

pub fn drawText(x: i32, y: i32, text: []const u8, color: u32, scale: f32) void {
    if (!active or text.len == 0) return;
    setTex(font_atlas_tex);
    setMode(1);
    const c = packU32(color);
    var cx = x;
    for (text) |ch| {
        if (ch == '\n') { cx = x; continue; }
        const glyph_idx = font_mod.codepointIndex(@intCast(ch));
        const col = glyph_idx % ATLAS_COLS;
        const row = glyph_idx / ATLAS_COLS;
        const uv_x0 = @as(f32, @floatFromInt(col * font_mod.FONT_W)) * atlas_uv_scale_x;
        const uv_y0 = @as(f32, @floatFromInt(row * font_mod.FONT_H)) * atlas_uv_scale_y;
        const uv_x1 = uv_x0 + @as(f32, font_mod.FONT_W) * atlas_uv_scale_x;
        const uv_y1 = uv_y0 + @as(f32, font_mod.FONT_H) * atlas_uv_scale_y;
        const gw = @as(f32, font_mod.FONT_W) * scale;
        const gh = @as(f32, font_mod.FONT_H) * scale;
        const x1: f32 = @floatFromInt(cx);
        const y1: f32 = @floatFromInt(y);
        ensureCap(6);
        pushVert(x1, y1, uv_x0, uv_y0, c);
        pushVert(x1 + gw, y1, uv_x1, uv_y0, c);
        pushVert(x1, y1 + gh, uv_x0, uv_y1, c);
        pushVert(x1 + gw, y1, uv_x1, uv_y0, c);
        pushVert(x1 + gw, y1 + gh, uv_x1, uv_y1, c);
        pushVert(x1, y1 + gh, uv_x0, uv_y1, c);
        cx += @intFromFloat(gw);
    }
}

pub fn fillRectTex(x: i32, y: i32, w: i32, h: i32, tex: u32, uv_x: f32, uv_y: f32, uv_w: f32, uv_h: f32, tint: u32) void {
    if (!active or w <= 0 or h <= 0) return;
    setTex(tex);
    setMode(1);
    ensureCap(6);
    const c = packU32(tint);
    const x1: f32 = @floatFromInt(x);
    const y1: f32 = @floatFromInt(y);
    const x2: f32 = @floatFromInt(x + w);
    const y2: f32 = @floatFromInt(y + h);
    pushVert(x1, y1, uv_x, uv_y, c);
    pushVert(x2, y1, uv_x + uv_w, uv_y, c);
    pushVert(x1, y2, uv_x, uv_y + uv_h, c);
    pushVert(x2, y1, uv_x + uv_w, uv_y, c);
    pushVert(x2, y2, uv_x + uv_w, uv_y + uv_h, c);
    pushVert(x1, y2, uv_x, uv_y + uv_h, c);
}

pub fn flush() void {
    if (!active) return;
    flushBatch();
}

pub fn blitPixels(dx: i32, dy: i32, dw: u32, dh: u32, pixels: [*]u32, stride: u32) void {
    if (!active) return;
    _ = stride;
    var temp_tex: u32 = 0;
    glGenTextures_(1, &temp_tex);
    glBindTexture_(GL_TEXTURE_2D, temp_tex);
    glTexParameteri_(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, @intCast(GL_NEAREST));
    glTexParameteri_(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, @intCast(GL_NEAREST));
    glTexImage2D_(GL_TEXTURE_2D, 0, @intCast(GL_RGBA), @intCast(dw), @intCast(dh), 0, GL_RGBA, GL_UNSIGNED_BYTE, @as(*const anyopaque, @ptrCast(pixels)));
    fillRectTex(dx, dy, @intCast(dw), @intCast(dh), temp_tex, 0, 0, 1, 1, 0xFFFFFFFF);
    flushBatch();
    const texs = [_]u32{temp_tex};
    glDeleteTextures_(1, &texs);
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------
pub const Event = union(enum) {
    key_press: u8,
    key_release: u8,
    mouse_down: MouseData,
    mouse_up: MouseData,
    mouse_move: MouseData,
    resize: struct { w: u32, h: u32 },
    close,
};

pub const MouseData = struct {
    x: i32 = 0,
    y: i32 = 0,
    button: u8 = 0,
};

pub fn isActive() bool { return active; }
pub fn getWidth() u32 { return win_w; }
pub fn getHeight() u32 { return win_h; }
