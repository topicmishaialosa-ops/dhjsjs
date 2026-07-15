// ============================================================================
// gl3.zig — OpenGL 3.3 Core Profile GPU renderer
// X11 + GLX via extern declarations, zero runtime loading complexity
// ============================================================================

const sys = @import("sys.zig");
const font_mod = @import("font.zig");

// ---------------------------------------------------------------------------
// X11 extern declarations (same pattern as vk.zig)
// ---------------------------------------------------------------------------
extern "X11" fn XOpenDisplay(name: ?[*:0]const u8) callconv(.c) ?*anyopaque;
extern "X11" fn XDefaultScreen(dpy: *anyopaque) callconv(.c) i32;
extern "X11" fn XDefaultRootWindow(dpy: *anyopaque) callconv(.c) u64;
extern "X11" fn XDefaultVisual(dpy: *anyopaque, screen: i32) callconv(.c) ?*anyopaque;
extern "X11" fn XDefaultColormap(dpy: *anyopaque, screen: i32) callconv(.c) u64;
extern "X11" fn XCreateColormap(dpy: *anyopaque, win: u64, visual: ?*anyopaque, alloc: i32) callconv(.c) u64;
extern "X11" fn XCreateWindow(dpy: *anyopaque, parent: u64, x: i32, y: i32, w: u32, h: u32, border: u32, depth: i32, class: u32, visual: ?*anyopaque, mask: u64, attrs: ?*anyopaque) callconv(.c) u64;
extern "X11" fn XMapWindow(dpy: *anyopaque, win: u64) callconv(.c) i32;
extern "X11" fn XStoreName(dpy: *anyopaque, win: u64, name: [*:0]const u8) callconv(.c) i32;
extern "X11" fn XSelectInput(dpy: *anyopaque, win: u64, mask: i64) callconv(.c) i32;
extern "X11" fn XNextEvent(dpy: *anyopaque, event: *anyopaque) callconv(.c) i32;
extern "X11" fn XPending(dpy: *anyopaque) callconv(.c) i32;
extern "X11" fn XCloseDisplay(dpy: *anyopaque) callconv(.c) i32;
extern "X11" fn XDestroyWindow(dpy: *anyopaque, win: u64) callconv(.c) i32;
extern "X11" fn XFlush(dpy: *anyopaque) callconv(.c) i32;
extern "X11" fn XInternAtom(dpy: *anyopaque, name: [*:0]const u8, onlyIfExists: i32) callconv(.c) u64;
extern "X11" fn XChangeProperty(dpy: *anyopaque, win: u64, prop: u64, typ: u64, fmt: i32, mode: i32, data: [*]const u8, nelements: i32) callconv(.c) i32;
extern "X11" fn XSendEvent(dpy: *anyopaque, win: u64, propagate: i32, mask: i64, event: *anyopaque) callconv(.c) i32;

// ---------------------------------------------------------------------------
// GLX extern declarations
// ---------------------------------------------------------------------------
extern "GL" fn glXChooseFBConfig(dpy: *anyopaque, screen: i32, attrib_list: [*]const i32, nelements: *i32) callconv(.c) ?[*]u64;
extern "GL" fn glXGetVisualFromFBConfig(dpy: *anyopaque, config: u64) callconv(.c) ?*XVisualInfo;
extern "GL" fn glXCreateWindow(dpy: *anyopaque, config: u64, win: u64, attrib_list: ?[*]const i32) callconv(.c) u64;
extern "GL" fn glXMakeCurrent(dpy: *anyopaque, drawable: u64, ctx: u64) callconv(.c) i32;
extern "GL" fn glXSwapBuffers(dpy: *anyopaque, drawable: u64) callconv(.c) void;
extern "GL" fn glXDestroyContext(dpy: *anyopaque, ctx: u64) callconv(.c) void;
extern "GL" fn glXDestroyWindow(dpy: *anyopaque, win: u64) callconv(.c) void;
extern "GL" fn glXGetProcAddress(name: [*:0]const u8) callconv(.c) ?*const anyopaque;

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
// GLX_ARB_create_context (loaded via glXGetProcAddress)
// ---------------------------------------------------------------------------
const GlXCreateContextAttribsARB = *const fn (dpy: *anyopaque, config: u64, share: u64, direct: i32, attrib_list: ?[*]const i32) callconv(.c) u64;
var glXCreateContextAttribsARB_: ?GlXCreateContextAttribsARB = null;

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
const KeyPressMask: u64 = 1 << 0;
const KeyReleaseMask: u64 = 1 << 1;
const ButtonPressMask: u64 = 1 << 2;
const ButtonReleaseMask: u64 = 1 << 3;
const PointerMotionMask: u64 = 1 << 6;
const ExposureMask: u64 = 1 << 15;
const StructureNotifyMask: u64 = 1 << 17;

// X11 event types
const KeyPress: u8 = 2;
const KeyRelease: u8 = 3;
const ButtonPress: u8 = 4;
const ButtonRelease: u8 = 5;
const MotionNotify: u8 = 6;
const ConfigureNotify: u8 = 22;
const ClientMessage: u8 = 33;

// X11 XEvent layout (big enough for any event)
const XEvent = extern union {
    type_: u8,
    _pad: [95]u8,
};

// ---------------------------------------------------------------------------
// GL function pointers (loaded via glXGetProcAddress)
// ---------------------------------------------------------------------------
var glViewport_: *const fn (x: i32, y: i32, w: i32, h: i32) callconv(.c) void = undefined;
var glScissor_: *const fn (x: i32, y: i32, w: i32, h: i32) callconv(.c) void = undefined;
var glEnable_: *const fn (cap: u32) callconv(.c) void = undefined;
var glDisable_: *const fn (cap: u32) callconv(.c) void = undefined;
var glBlendFunc_: *const fn (sfactor: u32, dfactor: u32) callconv(.c) void = undefined;
var glClearColor_: *const fn (r: f32, g: f32, b: f32, a: f32) callconv(.c) void = undefined;
var glClear_: *const fn (mask: u32) callconv(.c) void = undefined;

var glGenBuffers_: *const fn (n: i32, buffers: *u32) callconv(.c) void = undefined;
var glBindBuffer_: *const fn (target: u32, buffer: u32) callconv(.c) void = undefined;
var glBufferData_: *const fn (target: u32, size: isize, data: ?*const anyopaque, usage: u32) callconv(.c) void = undefined;
var glDeleteBuffers_: *const fn (n: i32, buffers: [*]const u32) callconv(.c) void = undefined;

var glGenVertexArrays_: *const fn (n: i32, arrays: *u32) callconv(.c) void = undefined;
var glBindVertexArray_: *const fn (array: u32) callconv(.c) void = undefined;
var glDeleteVertexArrays_: *const fn (n: i32, arrays: [*]const u32) callconv(.c) void = undefined;
var glEnableVertexAttribArray_: *const fn (index: u32) callconv(.c) void = undefined;
var glDisableVertexAttribArray_: *const fn (index: u32) callconv(.c) void = undefined;
var glVertexAttribPointer_: *const fn (index: u32, size: i32, typ: u32, normalized: u8, stride: i32, ptr: ?*const anyopaque) callconv(.c) void = undefined;

var glGenTextures_: *const fn (n: i32, textures: *u32) callconv(.c) void = undefined;
var glBindTexture_: *const fn (target: u32, texture: u32) callconv(.c) void = undefined;
var glTexImage2D_: *const fn (target: u32, level: i32, internal: i32, w: i32, h: i32, border: i32, format: u32, typ: u32, pixels: ?*const anyopaque) callconv(.c) void = undefined;
var glTexParameteri_: *const fn (target: u32, pname: u32, param: i32) callconv(.c) void = undefined;
var glDeleteTextures_: *const fn (n: i32, textures: [*]const u32) callconv(.c) void = undefined;
var glActiveTexture_: *const fn (texture: u32) callconv(.c) void = undefined;

var glCreateShader_: *const fn (shader_type: u32) callconv(.c) u32 = undefined;
var glShaderSource_: *const fn (shader: u32, count: i32, src: *const [*:0]const u8, len: ?*const i32) callconv(.c) void = undefined;
var glCompileShader_: *const fn (shader: u32) callconv(.c) void = undefined;
var glCreateProgram_: *const fn () callconv(.c) u32 = undefined;
var glAttachShader_: *const fn (program: u32, shader: u32) callconv(.c) void = undefined;
var glLinkProgram_: *const fn (program: u32) callconv(.c) void = undefined;
var glUseProgram_: *const fn (program: u32) callconv(.c) void = undefined;
var glGetShaderiv_: *const fn (shader: u32, pname: u32, params: *i32) callconv(.c) void = undefined;
var glGetProgramiv_: *const fn (program: u32, pname: u32, params: *i32) callconv(.c) void = undefined;
var glGetShaderInfoLog_: *const fn (shader: u32, buf_size: i32, len: *i32, info: [*]u8) callconv(.c) void = undefined;
var glGetProgramInfoLog_: *const fn (program: u32, buf_size: i32, len: *i32, info: [*]u8) callconv(.c) void = undefined;
var glDeleteShader_: *const fn (shader: u32) callconv(.c) void = undefined;
var glDeleteProgram_: *const fn (program: u32) callconv(.c) void = undefined;
var glGetAttribLocation_: *const fn (program: u32, name: [*:0]const u8) callconv(.c) i32 = undefined;
var glGetUniformLocation_: *const fn (program: u32, name: [*:0]const u8) callconv(.c) i32 = undefined;
var glUniform1i_: *const fn (loc: i32, v: i32) callconv(.c) void = undefined;
var glUniform4f_: *const fn (loc: i32, x: f32, y: f32, z: f32, w: f32) callconv(.c) void = undefined;
var glUniformMatrix4fv_: *const fn (loc: i32, count: i32, transpose: u8, value: [*]const f32) callconv(.c) void = undefined;
var glDrawArrays_: *const fn (mode: u32, first: i32, count: i32) callconv(.c) void = undefined;

fn loadGL(comptime T: type, name: [*:0]const u8) ?T {
    const ptr = glXGetProcAddress(name) orelse return null;
    return @as(T, @ptrCast(@alignCast(ptr)));
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
var active = false;
var x_dpy: ?*anyopaque = null;
var x_screen: i32 = 0;
var x_root: u64 = 0;
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
const ATLAS_COLS = 32; // 512 / 16

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
// Math (no std)
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
    if (batch_count + needed > MAX_BATCH_VERTS) {
        flushBatch();
    }
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
// Public API
// ---------------------------------------------------------------------------

pub fn init(w: u32, h: u32) bool {
    if (active) return true;

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

    // Load glXCreateContextAttribsARB
    glXCreateContextAttribsARB_ = @as(GlXCreateContextAttribsARB, @ptrCast(@alignCast(
        glXGetProcAddress("glXCreateContextAttribsARB") orelse return false,
    )));

    // Open X11 display
    x_dpy = XOpenDisplay(null) orelse return false;
    x_screen = XDefaultScreen(x_dpy.?);
    x_root = XDefaultRootWindow(x_dpy.?);

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
    const configs = glXChooseFBConfig(x_dpy.?, x_screen, &fb_attribs, &num_configs) orelse return false;
    if (num_configs == 0) return false;
    const config = configs[0];
    // Free the config list (we only need the first one)

    // Get visual for window creation
    const vis_info = glXGetVisualFromFBConfig(x_dpy.?, config) orelse return false;
    const visual = vis_info.visual orelse return false;

    // Create window
    x_win = XCreateWindow(
        x_dpy.?,
        x_root,
        0, 0,
        w, h,
        0,
        24, // depth
        1, // InputOutput
        visual,
        0x2082, // CWColormap | CWEventMask | CWBackPixel
        @ptrFromInt(0),
    );
    if (x_win == 0) return false;

    // Set title
    _ = XStoreName(x_dpy.?, x_win, "dhjsjs OpenGL 3.3");

    // Select input events
    _ = XSelectInput(x_dpy.?, x_win, @intCast(KeyPressMask | KeyReleaseMask | ButtonPressMask | ButtonReleaseMask | PointerMotionMask | ExposureMask | StructureNotifyMask));

    // Map window
    _ = XMapWindow(x_dpy.?, x_win);
    _ = XFlush(x_dpy.?);

    // Register WM_DELETE_WINDOW
    wm_delete_msg = XInternAtom(x_dpy.?, "WM_DELETE_WINDOW", 0);
    _ = XChangeProperty(x_dpy.?, x_win, XInternAtom(x_dpy.?, "WM_PROTOCOLS", 0), 6, 32, 0, @ptrCast(&wm_delete_msg), 1);

    // Create GLX drawable
    glx_drawable = glXCreateWindow(x_dpy.?, config, x_win, null);
    if (glx_drawable == 0) return false;

    // Create GL 3.3 Core context
    var ctx_attribs = [_]i32{
        @intCast(GLX_CONTEXT_MAJOR_VERSION_ARB), 3,
        @intCast(GLX_CONTEXT_MINOR_VERSION_ARB), 3,
        @intCast(GLX_CONTEXT_FLAGS_ARB), @intCast(GLX_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB),
        @intCast(GLX_CONTEXT_PROFILE_MASK_ARB), @intCast(GLX_CONTEXT_CORE_PROFILE_BIT_ARB),
        0,
    };
    glx_ctx = glXCreateContextAttribsARB_.?(x_dpy.?, config, 0, 1, &ctx_attribs);
    if (glx_ctx == 0) return false;

    // Make current
    if (glXMakeCurrent(x_dpy.?, glx_drawable, glx_ctx) == 0) return false;

    win_w = w;
    win_h = h;

    // GL state
    glViewport_(0, 0, @intCast(w), @intCast(h));
    glEnable_(GL_BLEND);
    glBlendFunc_(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    // Compile shaders
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

    if (glx_drawable != 0) glXDestroyWindow(x_dpy.?, glx_drawable);
    if (glx_ctx != 0) glXDestroyContext(x_dpy.?, glx_ctx);

    if (vbo != 0) {
        const bufs = [_]u32{vbo};
        glDeleteBuffers_(1, &bufs);
    }
    if (vao != 0) {
        const arrs = [_]u32{vao};
        glDeleteVertexArrays_(1, &arrs);
    }
    if (shader_prog != 0) glDeleteProgram_(shader_prog);
    if (font_atlas_tex != 0) {
        const texs = [_]u32{font_atlas_tex};
        glDeleteTextures_(1, &texs);
    }

    sys.munmap(@ptrCast(batch_verts), MAX_BATCH_VERTS * @sizeOf(Vertex));

    if (x_win != 0) _ = XDestroyWindow(x_dpy.?, x_win);
    if (x_dpy) |dpy| {
        _ = XCloseDisplay(dpy);
        x_dpy = null;
    }
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
    glXSwapBuffers(x_dpy.?, glx_drawable);
}

pub fn pollEvent() ?Event {
    if (!active or x_dpy == null) return null;

    while (XPending(x_dpy.?) > 0) {
        var ev: XEvent = undefined;
        _ = XNextEvent(x_dpy.?, &ev);
        const ev_type = ev.type_;

        if (ev_type == KeyPress) {
            // XKeyEvent: type(1) + pad(1) + serial(4) + send_event(4) + display(8) + window(8) + root(8) + subwindow(8) + time(8) + x,y(4+4) + state(4) + keycode(1) + same_screen(1)
            // keycode is at offset 44 in the event struct
            const keycode = ev._pad[43]; // 0-indexed, 44th byte
            return .{ .key_press = keycode };
        }
        if (ev_type == KeyRelease) {
            const keycode = ev._pad[43];
            return .{ .key_release = keycode };
        }
        if (ev_type == ButtonPress) {
            // XButtonEvent: x,y at offsets 16,20 (i16), button at offset 41 (u8)
            const mx = @as(i16, @bitCast(@as(u16, ev._pad[16] | (@as(u16, ev._pad[17]) << 8))));
            const my = @as(i16, @bitCast(@as(u16, ev._pad[20] | (@as(u16, ev._pad[21]) << 8))));
            const btn = ev._pad[41];
            return .{ .mouse_down = .{ .x = mx, .y = my, .button = btn } };
        }
        if (ev_type == ButtonRelease) {
            const mx = @as(i16, @bitCast(@as(u16, ev._pad[16] | (@as(u16, ev._pad[17]) << 8))));
            const my = @as(i16, @bitCast(@as(u16, ev._pad[20] | (@as(u16, ev._pad[21]) << 8))));
            const btn = ev._pad[41];
            return .{ .mouse_up = .{ .x = mx, .y = my, .button = btn } };
        }
        if (ev_type == MotionNotify) {
            const mx = @as(i16, @bitCast(@as(u16, ev._pad[16] | (@as(u16, ev._pad[17]) << 8))));
            const my = @as(i16, @bitCast(@as(u16, ev._pad[20] | (@as(u16, ev._pad[21]) << 8))));
            return .{ .mouse_move = .{ .x = mx, .y = my } };
        }
        if (ev_type == ConfigureNotify) {
            // XConfigureEvent: x,y(16), width(18), height(20) as i16
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
        if (ev_type == ClientMessage) {
            // Check WM_DELETE_WINDOW
            // XClientMessageEvent: format at offset 32, data at offset 36
            const data32_0 = @as(u64, ev._pad[36]) | (@as(u64, ev._pad[37]) << 8) | (@as(u64, ev._pad[38]) << 16) | (@as(u64, ev._pad[39]) << 24);
            if (data32_0 == wm_delete_msg) return .close;
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

    // Center
    if (w > r * 2 and h > r * 2) {
        fillRect(x + r, y, w - r * 2, h, color);
    }
    // Left/right strips
    if (r > 0) {
        fillRect(x, y + r, r, h - r * 2, color);
        fillRect(x + w - r, y + r, r, h - r * 2, color);
    }
    // Corner fans
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
pub fn getDisplay() ?*anyopaque { return x_dpy; }
