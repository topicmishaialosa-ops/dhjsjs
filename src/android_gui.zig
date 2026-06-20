const bridge = @import("android_bridge.zig");

pub const MAX_EVENTS: usize = 16;

pub const TouchEvent = struct {
    x: f32,
    y: f32,
    action: u32,
    pointer_id: u32,
};

pub const KeyEvent = struct {
    action: u32,
    keycode: u32,
};

pub const GuiContext = struct {
    width: u32,
    height: u32,
    stride: u32,
    pixels: [*]u32,
    touch_events: [MAX_EVENTS]TouchEvent,
    touch_count: usize,
    key_events: [MAX_EVENTS]KeyEvent,
    key_count: usize,
    should_finish: bool,
    has_focus: bool,
    frame_count: u64,
};

const system = struct {
    extern "c" fn ANativeWindow_lock(window: *anyopaque, buffer: *anyopaque, dirty: ?*anyopaque) callconv(.C) i32;
    extern "c" fn ANativeWindow_unlockAndPost(window: *anyopaque) callconv(.C) i32;
    extern "c" fn AInputQueue_getEvent(queue: *anyopaque, event: **anyopaque) callconv(.C) i32;
    extern "c" fn AInputQueue_preDispatchEvent(queue: *anyopaque, event: *anyopaque) callconv(.C) i32;
    extern "c" fn AInputQueue_finishEvent(queue: *anyopaque, event: *anyopaque, handled: i32) callconv(.C) void;
    extern "c" fn AInputEvent_getType(event: *anyopaque) callconv(.C) i32;
    extern "c" fn AMotionEvent_getAction(event: *anyopaque) callconv(.C) i32;
    extern "c" fn AMotionEvent_getX(event: *anyopaque, pointer_idx: u64) callconv(.C) f32;
    extern "c" fn AMotionEvent_getY(event: *anyopaque, pointer_idx: u64) callconv(.C) f32;
    extern "c" fn AMotionEvent_getPointerId(event: *anyopaque, pointer_idx: u64) callconv(.C) i32;
    extern "c" fn AKeyEvent_getAction(event: *anyopaque) callconv(.C) i32;
    extern "c" fn AKeyEvent_getKeyCode(event: *anyopaque) callconv(.C) i32;
};

const AINPUT_EVENT_TYPE_MOTION = 2;
const AINPUT_EVENT_TYPE_KEY = 1;
const AMOTION_EVENT_ACTION_MASK: u32 = 0xFF;
const AMOTION_EVENT_ACTION_DOWN = 0;
const AMOTION_EVENT_ACTION_UP = 1;
const AMOTION_EVENT_ACTION_MOVE = 2;
const AKEY_EVENT_ACTION_DOWN = 0;
const AKEY_EVENT_ACTION_UP = 1;

const ANativeWindow_Buffer = extern struct {
    width: i32,
    height: i32,
    stride: i32,
    format: i32,
    bits: *anyopaque,
    reserved: [6]u32,
};

// Forward declaration of the user's compiled dhjsjs code
extern fn main() void;

var activity_ptr: ?*anyopaque = null;
var window_ptr: ?*anyopaque = null;
var input_queue_ptr: ?*anyopaque = null;
var has_focus: bool = false;
var should_finish: bool = false;
var ctx: GuiContext = undefined;

export fn ANativeActivity_onCreate(activity: *anyopaque, _: ?*anyopaque, _: usize) void {
    activity_ptr = activity;

    const cb_offset: u64 = 0x30;
    const onStart_offset: u64 = 0x00;
    const onResume_offset: u64 = 0x08;
    const onPause_offset: u64 = 0x10;
    const onStop_offset: u64 = 0x18;
    const onDestroy_offset: u64 = 0x20;
    const onWindowFocusChanged_offset: u64 = 0x28;
    const onNativeWindowCreated_offset: u64 = 0x30;
    const onNativeWindowDestroyed_offset: u64 = 0x38;
    const onInputQueueCreated_offset: u64 = 0x40;
    const onInputQueueDestroyed_offset: u64 = 0x48;

    const callbacks = @as(*[*]u64, @ptrCast(@as(*anyopaque, @ptrCast(@as(u64, @intFromPtr(activity)) + cb_offset))));

    // Create callback trampolines
    callbacks.*[onStart_offset / 8] = @intFromPtr(&onStart);
    callbacks.*[onResume_offset / 8] = @intFromPtr(&onResume);
    callbacks.*[onPause_offset / 8] = @intFromPtr(&onPause);
    callbacks.*[onStop_offset / 8] = @intFromPtr(&onStop);
    callbacks.*[onDestroy_offset / 8] = @intFromPtr(&onDestroy);
    callbacks.*[onWindowFocusChanged_offset / 8] = @intFromPtr(&onWindowFocusChanged);
    callbacks.*[onNativeWindowCreated_offset / 8] = @intFromPtr(&onNativeWindowCreated);
    callbacks.*[onNativeWindowDestroyed_offset / 8] = @intFromPtr(&onNativeWindowDestroyed);
    callbacks.*[onInputQueueCreated_offset / 8] = @intFromPtr(&onInputQueueCreated);
    callbacks.*[onInputQueueDestroyed_offset / 8] = @intFromPtr(&onInputQueueDestroyed);
}

fn onStart(activity: *anyopaque) callconv(.C) void {
    _ = activity;
}

fn onResume(activity: *anyopaque) callconv(.C) void {
    _ = activity;
    if (window_ptr) |win| {
        renderFrame(win);
    }
}

fn onPause(activity: *anyopaque) callconv(.C) void {
    _ = activity;
}

fn onStop(activity: *anyopaque) callconv(.C) void {
    _ = activity;
}

fn onDestroy(activity: *anyopaque) callconv(.C) void {
    _ = activity;
    should_finish = true;
}

fn onWindowFocusChanged(activity: *anyopaque, hasWindowFocus: i32) callconv(.C) void {
    _ = activity;
    has_focus = hasWindowFocus != 0;
}

fn onNativeWindowCreated(activity: *anyopaque, window: *anyopaque) callconv(.C) void {
    _ = activity;
    window_ptr = window;
    renderFrame(window);
}

fn onNativeWindowDestroyed(activity: *anyopaque, window: *anyopaque) callconv(.C) void {
    _ = activity;
    _ = window;
    window_ptr = null;
}

fn onInputQueueCreated(activity: *anyopaque, queue: *anyopaque) callconv(.C) void {
    _ = activity;
    input_queue_ptr = queue;
}

fn onInputQueueDestroyed(activity: *anyopaque, queue: *anyopaque) callconv(.C) void {
    _ = activity;
    _ = queue;
    input_queue_ptr = null;
}

fn renderFrame(window: *anyopaque) void {
    var buffer: ANativeWindow_Buffer = undefined;
    if (system.ANativeWindow_lock(window, &buffer, null) != 0) return;

    const w = @as(u32, @intCast(buffer.width));
    const h = @as(u32, @intCast(buffer.height));
    const stride = @as(u32, @intCast(buffer.stride));
    const pixels = @as([*]u32, @ptrCast(buffer.bits));

    ctx.width = w;
    ctx.height = h;
    ctx.stride = stride;
    ctx.pixels = pixels;
    ctx.should_finish = should_finish;
    ctx.has_focus = has_focus;

    processInput();

    // Write state to fixed addresses for dhjsjs code to read
    const cmd_ptr = @as(*volatile bridge.AndroidCmd, @ptrFromInt(bridge.ANDROID_CMD_ADDR));
    cmd_ptr.fb_width = w;
    cmd_ptr.fb_height = h;
    cmd_ptr.fb_stride = stride;
    cmd_ptr.fb_pixels = @intFromPtr(pixels);
    cmd_ptr.should_finish = if (should_finish) 1 else 0;
    cmd_ptr.has_focus = if (has_focus) 1 else 0;

    // Store touch info from latest event
    if (ctx.touch_count > 0) {
        cmd_ptr.touch_x = ctx.touch_events[0].x;
        cmd_ptr.touch_y = ctx.touch_events[0].y;
        cmd_ptr.touch_down = if (ctx.touch_events[0].action == 0) 1 else 0;
        cmd_ptr.touch_action = ctx.touch_events[0].action;
        cmd_ptr.touch_pointer_id = ctx.touch_events[0].pointer_id;
    } else {
        cmd_ptr.touch_down = 0;
    }
    ctx.touch_count = 0;
    ctx.key_count = 0;

    // Call user code (dhjsjs compiled)
    main();

    _ = system.ANativeWindow_unlockAndPost(window);
    ctx.frame_count += 1;
}

fn processInput() void {
    const queue = input_queue_ptr orelse return;
    ctx.touch_count = 0;
    ctx.key_count = 0;

    var event: ?*anyopaque = null;
    while (ctx.touch_count < MAX_EVENTS and ctx.key_count < MAX_EVENTS) {
        if (system.AInputQueue_getEvent(queue, &event) != 0) break;
        if (event) |ev| {
            _ = system.AInputQueue_preDispatchEvent(queue, ev);
            const etype = system.AInputEvent_getType(ev);
            if (etype == AINPUT_EVENT_TYPE_MOTION) {
                const action = @as(u32, @intCast(system.AMotionEvent_getAction(ev))) & AMOTION_EVENT_ACTION_MASK;
                if (ctx.touch_count < MAX_EVENTS) {
                    ctx.touch_events[ctx.touch_count] = TouchEvent{
                        .x = system.AMotionEvent_getX(ev, 0),
                        .y = system.AMotionEvent_getY(ev, 0),
                        .action = action,
                        .pointer_id = @as(u32, @intCast(system.AMotionEvent_getPointerId(ev, 0))),
                    };
                    ctx.touch_count += 1;
                }
            } else if (etype == AINPUT_EVENT_TYPE_KEY) {
                if (ctx.key_count < MAX_EVENTS) {
                    ctx.key_events[ctx.key_count] = KeyEvent{
                        .action = @as(u32, @intCast(system.AKeyEvent_getAction(ev))),
                        .keycode = @as(u32, @intCast(system.AKeyEvent_getKeyCode(ev))),
                    };
                    ctx.key_count += 1;
                }
            }
            system.AInputQueue_finishEvent(queue, ev, 1);
        } else break;
    }
}
