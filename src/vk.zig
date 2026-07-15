// vk.zig — Vulkan renderer: instance + device + swapchain + triangle pipeline
const sys = @import("sys.zig");

// === Vulkan API (extern, linked at compile time) ===
extern "vulkan" fn vkCreateInstance(ci: ?*const anyopaque, ac: ?*const anyopaque, inst: *u64) callconv(.c) i32;
extern "vulkan" fn vkGetInstanceProcAddr(inst: u64, name: [*:0]const u8) callconv(.c) ?*const anyopaque;
extern "vulkan" fn vkEnumeratePhysicalDevices(inst: u64, count: *u32, devices: *u64) callconv(.c) i32;
extern "vulkan" fn vkGetPhysicalDeviceQueueFamilyProperties(phys: u64, count: *u32, props: ?*anyopaque) callconv(.c) void;
extern "vulkan" fn vkCreateDevice(phys: u64, ci: ?*const anyopaque, ac: ?*const anyopaque, dev: *u64) callconv(.c) i32;
extern "vulkan" fn vkGetDeviceQueue(dev: u64, fam: u32, idx: u32, q: *u64) callconv(.c) void;
extern "vulkan" fn vkCreateCommandPool(dev: u64, ci: ?*const anyopaque, ac: ?*const anyopaque, pool: *u64) callconv(.c) i32;
extern "vulkan" fn vkAllocateCommandBuffers(dev: u64, ai: ?*const anyopaque, cmds: [*]u64) callconv(.c) i32;
extern "vulkan" fn vkGetPhysicalDeviceMemoryProperties(phys: u64, props: ?*anyopaque) callconv(.c) void;
extern "vulkan" fn vkGetPhysicalDeviceSurfaceSupportKHR(phys: u64, fam: u32, surface: u64, supported: *u32) callconv(.c) i32;
extern "vulkan" fn vkGetPhysicalDeviceSurfaceCapabilitiesKHR(phys: u64, surface: u64, caps: ?*anyopaque) callconv(.c) i32;
extern "vulkan" fn vkGetPhysicalDeviceSurfaceFormatsKHR(phys: u64, surface: u64, count: *u32, fmts: ?*anyopaque) callconv(.c) i32;
extern "vulkan" fn vkGetPhysicalDeviceSurfacePresentModesKHR(phys: u64, surface: u64, count: u32, modes: ?*u32) callconv(.c) i32;
extern "vulkan" fn vkCreateXlibSurfaceKHR(inst: u64, ci: ?*const anyopaque, ac: ?*const anyopaque, surface: *u64) callconv(.c) i32;
extern "vulkan" fn vkDeviceWaitIdle(dev: u64) callconv(.c) i32;
extern "vulkan" fn vkQueuePresentKHR(q: u64, info: ?*const anyopaque) callconv(.c) i32;

// X11
extern "X11" fn XOpenDisplay(name: ?[*:0]const u8) callconv(.c) ?*anyopaque;
extern "X11" fn XDefaultScreen(dpy: *anyopaque) callconv(.c) i32;
extern "X11" fn XDefaultRootWindow(dpy: *anyopaque) callconv(.c) u64;
extern "X11" fn XDefaultVisual(dpy: *anyopaque, scr: i32) callconv(.c) *anyopaque;
extern "X11" fn XDefaultDepth(dpy: *anyopaque, scr: i32) callconv(.c) i32;
extern "X11" fn XCreateColormap(dpy: *anyopaque, w: u64, v: *anyopaque, a: i32) callconv(.c) u64;
extern "X11" fn XFreeColormap(dpy: *anyopaque, c: u64) callconv(.c) i32;
extern "X11" fn XCreateWindow(dpy: *anyopaque, p: u64, x: i32, y: i32, w: u32, h: u32, bw: u32, d: i32, cl: u32, vis: *anyopaque, mask: u64, attrs: *anyopaque) callconv(.c) u64;
extern "X11" fn XMapWindow(dpy: *anyopaque, w: u64) callconv(.c) i32;
extern "X11" fn XSelectInput(dpy: *anyopaque, w: u64, m: u64) callconv(.c) i32;
extern "X11" fn XStoreName(dpy: *anyopaque, w: u64, n: [*:0]const u8) callconv(.c) i32;
extern "X11" fn XNextEvent(dpy: *anyopaque, e: *anyopaque) callconv(.c) i32;
extern "X11" fn XPending(dpy: *anyopaque) callconv(.c) i32;
extern "X11" fn XCloseDisplay(dpy: *anyopaque) callconv(.c) i32;
extern "X11" fn XDestroyWindow(dpy: *anyopaque, w: u64) callconv(.c) i32;
extern "X11" fn XFlush(dpy: *anyopaque) callconv(.c) i32;

// === Device function pointers (loaded at runtime) ===
const Fns = struct {
    create_swapchain: *const fn (u64, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = undefined,
    destroy_swapchain: *const fn (u64, u64, ?*const anyopaque) callconv(.c) void = undefined,
    get_swapchain_images: *const fn (u64, u64, *u32, [*]u64) callconv(.c) i32 = undefined,
    create_image_view: *const fn (u64, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = undefined,
    destroy_image_view: *const fn (u64, u64, ?*const anyopaque) callconv(.c) void = undefined,
    create_render_pass: *const fn (u64, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = undefined,
    destroy_render_pass: *const fn (u64, u64, ?*const anyopaque) callconv(.c) void = undefined,
    create_framebuffer: *const fn (u64, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = undefined,
    destroy_framebuffer: *const fn (u64, u64, ?*const anyopaque) callconv(.c) void = undefined,
    create_shader_module: *const fn (u64, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = undefined,
    destroy_shader_module: *const fn (u64, u64, ?*const anyopaque) callconv(.c) void = undefined,
    create_graphics_pipelines: *const fn (u64, u64, u32, *const anyopaque, ?*const anyopaque, ?*u64) callconv(.c) i32 = undefined,
    destroy_pipeline: *const fn (u64, u64, ?*const anyopaque) callconv(.c) void = undefined,
    create_pipeline_layout: *const fn (u64, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = undefined,
    create_buffer: *const fn (u64, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = undefined,
    allocate_memory: *const fn (u64, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = undefined,
    bind_buffer_memory: *const fn (u64, u64, u64, u64) callconv(.c) i32 = undefined,
    map_memory: *const fn (u64, u64, u64, u64, u64, *?*anyopaque) callconv(.c) i32 = undefined,
    unmap_memory: *const fn (u64, u64) callconv(.c) void = undefined,
    get_buffer_memory_requirements: *const fn (u64, u64, *anyopaque) callconv(.c) void = undefined,
    begin_command_buffer: *const fn (u64, *const anyopaque) callconv(.c) i32 = undefined,
    end_command_buffer: *const fn (u64) callconv(.c) i32 = undefined,
    cmd_begin_render_pass: *const fn (u64, *const anyopaque, u32) callconv(.c) void = undefined,
    cmd_end_render_pass: *const fn (u64) callconv(.c) void = undefined,
    cmd_bind_pipeline: *const fn (u64, u32, u64) callconv(.c) void = undefined,
    cmd_set_viewport: *const fn (u64, u32, u32, *const anyopaque) callconv(.c) void = undefined,
    cmd_set_scissor: *const fn (u64, u32, u32, *const anyopaque) callconv(.c) void = undefined,
    cmd_bind_vertex_buffers: *const fn (u64, u32, u32, [*]const u64, [*]const u64) callconv(.c) void = undefined,
    cmd_draw: *const fn (u64, u32, u32, u32, u32) callconv(.c) void = undefined,
    create_fence: *const fn (u64, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = undefined,
    wait_for_fences: *const fn (u64, u32, [*]const u64, u32, u64) callconv(.c) i32 = undefined,
    reset_fences: *const fn (u64, u32, [*]const u64) callconv(.c) i32 = undefined,
    create_semaphore: *const fn (u64, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = undefined,
    acquire_next_image: *const fn (u64, u64, u64, u64, u64, *u32) callconv(.c) i32 = undefined,
    queue_submit: *const fn (u64, u32, *const anyopaque, u64) callconv(.c) i32 = undefined,
    queue_present: *const fn (u64, *const anyopaque) callconv(.c) i32 = undefined,
    free_command_buffers: *const fn (u64, u64, u32, [*]const u64) callconv(.c) void = undefined,
    cmd_pipeline_barrier: *const fn (u64, u32, u32, u32, u32, ?*const anyopaque, u32, ?*const anyopaque, u32, ?*const anyopaque) callconv(.c) void = undefined,
    cmd_copy_buffer_to_image: *const fn (u64, u64, u64, u32, ?*const anyopaque) callconv(.c) void = undefined,
    cmd_copy_buffer: *const fn (u64, u64, u64, u32, ?*const anyopaque) callconv(.c) void = undefined,
    flush_mapped_memory_ranges: *const fn (u64, u32, *const anyopaque) callconv(.c) i32,
};
var fns: Fns = undefined;

var loaded = false;

fn loadFns() void {
    const g = @as(*const fn (u64, [*:0]const u8) callconv(.c) ?*const anyopaque, @ptrCast(&vkGetInstanceProcAddr));
    const load = struct {
        fn f(name: [*:0]const u8) ?*const anyopaque { return g(vk_inst, name); }
    }.f;
    if (load("vkCreateSwapchainKHR")) |p| fns.create_swapchain = @ptrCast(p);
    if (load("vkDestroySwapchainKHR")) |p| fns.destroy_swapchain = @ptrCast(p);
    if (load("vkGetSwapchainImagesKHR")) |p| fns.get_swapchain_images = @ptrCast(p);
    if (load("vkCreateImageView")) |p| fns.create_image_view = @ptrCast(p);
    if (load("vkDestroyImageView")) |p| fns.destroy_image_view = @ptrCast(p);
    if (load("vkCreateRenderPass")) |p| fns.create_render_pass = @ptrCast(p);
    if (load("vkDestroyRenderPass")) |p| fns.destroy_render_pass = @ptrCast(p);
    if (load("vkCreateFramebuffer")) |p| fns.create_framebuffer = @ptrCast(p);
    if (load("vkDestroyFramebuffer")) |p| fns.destroy_framebuffer = @ptrCast(p);
    if (load("vkCreateShaderModule")) |p| fns.create_shader_module = @ptrCast(p);
    if (load("vkDestroyShaderModule")) |p| fns.destroy_shader_module = @ptrCast(p);
    if (load("vkCreateGraphicsPipelines")) |p| fns.create_graphics_pipelines = @ptrCast(p);
    if (load("vkDestroyPipeline")) |p| fns.destroy_pipeline = @ptrCast(p);
    if (load("vkCreatePipelineLayout")) |p| fns.create_pipeline_layout = @ptrCast(p);
    if (load("vkCreateBuffer")) |p| fns.create_buffer = @ptrCast(p);
    if (load("vkAllocateMemory")) |p| fns.allocate_memory = @ptrCast(p);
    if (load("vkBindBufferMemory")) |p| fns.bind_buffer_memory = @ptrCast(p);
    if (load("vkMapMemory")) |p| fns.map_memory = @ptrCast(p);
    if (load("vkUnmapMemory")) |p| fns.unmap_memory = @ptrCast(p);
    if (load("vkGetBufferMemoryRequirements")) |p| fns.get_buffer_memory_requirements = @ptrCast(p);
    if (load("vkBeginCommandBuffer")) |p| fns.begin_command_buffer = @ptrCast(p);
    if (load("vkEndCommandBuffer")) |p| fns.end_command_buffer = @ptrCast(p);
    if (load("vkCmdBeginRenderPass")) |p| fns.cmd_begin_render_pass = @ptrCast(p);
    if (load("vkCmdEndRenderPass")) |p| fns.cmd_end_render_pass = @ptrCast(p);
    if (load("vkCmdBindPipeline")) |p| fns.cmd_bind_pipeline = @ptrCast(p);
    if (load("vkCmdSetViewport")) |p| fns.cmd_set_viewport = @ptrCast(p);
    if (load("vkCmdSetScissor")) |p| fns.cmd_set_scissor = @ptrCast(p);
    if (load("vkCmdBindVertexBuffers")) |p| fns.cmd_bind_vertex_buffers = @ptrCast(p);
    if (load("vkCmdDraw")) |p| fns.cmd_draw = @ptrCast(p);
    if (load("vkCreateFence")) |p| fns.create_fence = @ptrCast(p);
    if (load("vkWaitForFences")) |p| fns.wait_for_fences = @ptrCast(p);
    if (load("vkResetFences")) |p| fns.reset_fences = @ptrCast(p);
    if (load("vkCreateSemaphore")) |p| fns.create_semaphore = @ptrCast(p);
    if (load("vkAcquireNextImageKHR")) |p| fns.acquire_next_image = @ptrCast(p);
    if (load("vkQueueSubmit")) |p| fns.queue_submit = @ptrCast(p);
    if (load("vkQueuePresentKHR")) |p| fns.queue_present = @ptrCast(p);
    if (load("vkFreeCommandBuffers")) |p| fns.free_command_buffers = @ptrCast(p);
    if (load("vkCmdPipelineBarrier")) |p| fns.cmd_pipeline_barrier = @ptrCast(p);
    if (load("vkCmdCopyBufferToImage")) |p| fns.cmd_copy_buffer_to_image = @ptrCast(p);
    if (load("vkCmdCopyBuffer")) |p| fns.cmd_copy_buffer = @ptrCast(p);
    if (load("vkFlushMappedMemoryRanges")) |p| fns.flush_mapped_memory_ranges = @ptrCast(p);
    loaded = true;
}

// === State ===
var x_dpy: ?*anyopaque = null;
var x_win: u64 = 0;
var fb_w: u32 = 0;
var fb_h: u32 = 0;
var ok = false;
var vk_inst: u64 = 0;
var vk_phys: u64 = 0;
var vk_dev: u64 = 0;
var vk_queue: u64 = 0;
var vk_qfam: u32 = 0;
var vk_surface: u64 = 0;
var vk_swap: u64 = 0;
var vk_images: [8]u64 = [_]u64{0} ** 8;
var vk_views: [8]u64 = [_]u64{0} ** 8;
var vk_nimg: u32 = 0;
var vk_rp: u64 = 0;
var vk_fbs: [8]u64 = [_]u64{0} ** 8;
var vk_pipe: u64 = 0;
var vk_pipe_layout: u64 = 0;
var vk_pool: u64 = 0;
var vk_cmds: [2]u64 = [_]u64{0} ** 2;
var vk_fence: [2]u64 = [_]u64{0} ** 2;
var vk_sem_avail: u64 = 0;
var vk_sem_done: u64 = 0;
var vk_vbuf: u64 = 0;
var vk_vmem: u64 = 0;
var vk_frame: u32 = 0;
var vk_mem_props: [192]u8 = undefined;

const XEvent = extern struct {
    type: u32, pad1: u32, serial: u64, send_event: i32, display: ?*anyopaque,
    window: u64, root: u64, subwindow: u64, time: u64,
    x: i32, y: i32, x_root: i32, y_root: i32,
    state: u32, keycode: u32, same_screen: i32,
};

pub fn init(_: ?*anyopaque, _: u32, w: u32, h: u32) bool {
    fb_w = w; fb_h = h;
    x_dpy = XOpenDisplay(null);
    if (x_dpy == null) return false;
    const scr = XDefaultScreen(x_dpy.?);
    const root = XDefaultRootWindow(x_dpy.?);
    const vis = XDefaultVisual(x_dpy.?, scr);
    const depth = XDefaultDepth(x_dpy.?, scr);
    const cmap = XCreateColormap(x_dpy.?, root, vis, 0);
    var a: [14]u64 = [_]u64{0} ** 14; a[12] = cmap;
    x_win = XCreateWindow(x_dpy.?, root, 0, 0, w, h, 0, depth, 0, vis, 1 << 13, @ptrCast(&a));
    _ = XFreeColormap(x_dpy.?, cmap);
    if (x_win == 0) return false;
    _ = XMapWindow(x_dpy.?, x_win);
    _ = XStoreName(x_dpy.?, x_win, "dhjsjs gpu");
    _ = XSelectInput(x_dpy.?, x_win, (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 12) | (1 << 17));
    _ = XFlush(x_dpy.?);
    if (!initVk()) return false;
    ok = true;
    return true;
}

fn initVk() bool {
    var ai: [8]u32 = [_]u32{1, 0, 0, 0, 0, 0, 0, 0x00100000}; // sType=APPLICATION_INFO, apiVersion=1.0
    var ext1: [14]u8 = undefined; var ext2: [19]u8 = undefined;
    @memcpy(&ext1, "VK_KHR_surface");
    @memcpy(&ext2, "VK_KHR_xlib_surface");
    var exts: [2]u64 = .{ @intFromPtr(&ext1), @intFromPtr(&ext2) };
    var ci: [8]u64 = [_]u64{ 1, 0, 0, @intFromPtr(&ai), 2, @intFromPtr(&exts), 0, 0 }; // sType=INSTANCE_CREATE_INFO
    if (vkCreateInstance(@ptrCast(&ci), null, &vk_inst) != 0) return false;

    loadFns();
    if (!loaded) return false;

    // Surface
    var sci: [4]u64 = .{ 1000002000, 0, @intFromPtr(x_dpy.?), x_win }; // XLIB_SURFACE_CREATE_INFO
    if (vkCreateXlibSurfaceKHR(vk_inst, @ptrCast(&sci), null, &vk_surface) != 0) return false;

    // Physical device
    var ndev: u32 = 1;
    if (vkEnumeratePhysicalDevices(vk_inst, &ndev, &vk_phys) != 0) return false;

    // Queue family
    var nqf: u32 = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(vk_phys, &nqf, null);
    var qfdata: [4096]u8 = undefined;
    var qi: usize = 0;
    while (qi < @sizeOf(@TypeOf(qfdata))) : (qi += 1) qfdata[qi] = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(vk_phys, &nqf, @ptrCast(&qfdata));
    var found = false;
    var i: u32 = 0;
    while (i < nqf) : (i += 1) {
        const off = @as(usize, i) * 56;
        const flags = @as(*align(1) u32, @ptrCast(@as([*]align(1) u8, @ptrCast(&qfdata)) + off)).*;
        var ps: u32 = 0;
        _ = vkGetPhysicalDeviceSurfaceSupportKHR(vk_phys, i, vk_surface, &ps);
        if ((flags & 1) != 0 and ps != 0) { vk_qfam = i; found = true; break; }
    }
    if (!found) return false;

    // Device
    var qci: [6]u32 = .{ 0, 0, 0, vk_qfam, 1, 0 }; // QUEUE_CREATE_INFO
    const pri_val: f32 = 1.0;
    qci[5] = @bitCast(pri_val);
    var dci: [8]u64 = .{ 3, 0, 0, 1, @intFromPtr(&qci), 0, 0, 0 }; // DEVICE_CREATE_INFO
    if (vkCreateDevice(vk_phys, @ptrCast(&dci), null, &vk_dev) != 0) return false;
    vkGetDeviceQueue(vk_dev, vk_qfam, 0, &vk_queue);

    // Swapchain
    var caps: [128]u8 = undefined;
    var ci2: usize = 0;
    while (ci2 < 128) : (ci2 += 1) caps[ci2] = 0;
    _ = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(vk_phys, vk_surface, @ptrCast(&caps));
    const ce_w = @as(*align(1) u32, @ptrCast(caps[8..].ptr)).*;
    const ce_h = @as(*align(1) u32, @ptrCast(caps[12..].ptr)).*;

    // Create swapchain
    var sc_buf: [72]u8 = undefined;
    var si: usize = 0;
    while (si < 72) : (si += 1) sc_buf[si] = 0;
    // sType at 0
    @as(*u32, @alignCast(@ptrCast(sc_buf[0..].ptr))).* = 1000001000; // SWAPCHAIN_CREATE_INFO
    // surface at 8
    @as(*u64, @alignCast(@ptrCast(sc_buf[8..].ptr))).* = vk_surface;
    // minImageCount at 16
    @as(*u32, @alignCast(@ptrCast(sc_buf[16..].ptr))).* = 3;
    // imageFormat at 20
    @as(*u32, @alignCast(@ptrCast(sc_buf[20..].ptr))).* = 44; // B8G8R8A8_UNORM
    // imageExtent at 24,28
    @as(*u32, @alignCast(@ptrCast(sc_buf[24..].ptr))).* = ce_w;
    @as(*u32, @alignCast(@ptrCast(sc_buf[28..].ptr))).* = ce_h;
    // imageArrayLayers at 32
    @as(*u32, @alignCast(@ptrCast(sc_buf[32..].ptr))).* = 1;
    // imageUsage at 36
    @as(*u32, @alignCast(@ptrCast(sc_buf[36..].ptr))).* = 4; // COLOR_ATTACHMENT
    // imageSharingMode at 40
    @as(*u32, @alignCast(@ptrCast(sc_buf[40..].ptr))).* = 0; // EXCLUSIVE
    // preTransform at 48
    @as(*u32, @alignCast(@ptrCast(sc_buf[48..].ptr))).* = 1; // IDENTITY
    // compositeAlpha at 52
    @as(*u32, @alignCast(@ptrCast(sc_buf[52..].ptr))).* = 1; // OPAQUE
    // presentMode at 56
    @as(*u32, @alignCast(@ptrCast(sc_buf[56..].ptr))).* = 0; // FIFO
    // clipped at 60
    @as(*u32, @alignCast(@ptrCast(sc_buf[60..].ptr))).* = 1;

    if (fns.create_swapchain(vk_dev, @ptrCast(&sc_buf), null, &vk_swap) != 0) return false;

    vk_nimg = 8;
    _ = fns.get_swapchain_images(vk_dev, vk_swap, &vk_nimg, &vk_images);

    // Image views
    var vi: u32 = 0;
    while (vi < vk_nimg) : (vi += 1) {
        var vci: [44]u8 = undefined;
        var vi2: usize = 0;
        while (vi2 < 44) : (vi2 += 1) vci[vi2] = 0;
        @as(*u32, @alignCast(@ptrCast(vci[0..].ptr))).* = 1000003003; // IMAGE_VIEW_CREATE_INFO
        @as(*u64, @alignCast(@ptrCast(vci[8..].ptr))).* = vk_images[vi];
        @as(*u32, @alignCast(@ptrCast(vci[16..].ptr))).* = 2; // VIEW_TYPE_2D
        @as(*u32, @alignCast(@ptrCast(vci[20..].ptr))).* = 44; // FORMAT_B8G8R8A8_UNORM
        @as(*u32, @alignCast(@ptrCast(vci[28..].ptr))).* = 1; // COLOR aspect
        _ = fns.create_image_view(vk_dev, @ptrCast(&vci), null, &vk_views[vi]);
    }

    // Render pass
    var aci: [32]u8 = undefined;
    var ai2: usize = 0;
    while (ai2 < 32) : (ai2 += 1) aci[ai2] = 0;
    @as(*u32, @alignCast(@ptrCast(aci[0..].ptr))).* = 44; // format
    @as(*u32, @alignCast(@ptrCast(aci[4..].ptr))).* = 1; // samples
    @as(*u32, @alignCast(@ptrCast(aci[8..].ptr))).* = 1; // loadOp=CLEAR
    @as(*u32, @alignCast(@ptrCast(aci[12..].ptr))).* = 0; // storeOp=STORE
    @as(*u32, @alignCast(@ptrCast(aci[20..].ptr))).* = 0; // initialLayout=UNDEFINED
    @as(*u32, @alignCast(@ptrCast(aci[24..].ptr))).* = 1000001002; // finalLayout=PRESENT_SRC

    var ac_ref: [2]u32 = .{ 0, 2 }; // attachment=0, layout=COLOR_ATTACHMENT_OPTIMAL
    var subpass: [64]u8 = undefined;
    var si2: usize = 0;
    while (si2 < 64) : (si2 += 1) subpass[si2] = 0;
    @as(*u32, @alignCast(@ptrCast(subpass[4..].ptr))).* = 0; // PIPELINE_BIND_POINT_GRAPHICS
    @as(*u32, @alignCast(@ptrCast(subpass[20..].ptr))).* = 1; // colorAttachmentCount
    @as(*u64, @alignCast(@ptrCast(subpass[24..].ptr))).* = @intFromPtr(&ac_ref);

    var rpci: [48]u8 = undefined;
    var ri: usize = 0;
    while (ri < 48) : (ri += 1) rpci[ri] = 0;
    @as(*u32, @alignCast(@ptrCast(rpci[0..].ptr))).* = 2; // RENDER_PASS_CREATE_INFO
    @as(*u32, @alignCast(@ptrCast(rpci[4..].ptr))).* = 1; // attachmentCount
    @as(*u64, @alignCast(@ptrCast(rpci[8..].ptr))).* = @intFromPtr(&aci);
    @as(*u32, @alignCast(@ptrCast(rpci[16..].ptr))).* = 1; // subpassCount
    @as(*u64, @alignCast(@ptrCast(rpci[20..].ptr))).* = @intFromPtr(&subpass);
    if (fns.create_render_pass(vk_dev, @ptrCast(&rpci), null, &vk_rp) != 0) return false;

    // Framebuffers
    var fi: u32 = 0;
    while (fi < vk_nimg) : (fi += 1) {
        var fbci: [40]u8 = undefined;
        var fbi: usize = 0;
        while (fbi < 40) : (fbi += 1) fbci[fbi] = 0;
        @as(*u32, @alignCast(@ptrCast(fbci[0..].ptr))).* = 37; // FRAMEBUFFER_CREATE_INFO
        @as(*u64, @alignCast(@ptrCast(fbci[8..].ptr))).* = vk_rp;
        @as(*u32, @alignCast(@ptrCast(fbci[16..].ptr))).* = 1;
        @as(*u64, @alignCast(@ptrCast(fbci[20..].ptr))).* = vk_views[fi];
        @as(*u32, @alignCast(@ptrCast(fbci[28..].ptr))).* = fb_w;
        @as(*u32, @alignCast(@ptrCast(fbci[32..].ptr))).* = fb_h;
        @as(*u32, @alignCast(@ptrCast(fbci[36..].ptr))).* = 1;
        _ = fns.create_framebuffer(vk_dev, @ptrCast(&fbci), null, &vk_fbs[fi]);
    }

    // Shaders — inline SPIR-V
    const vs = [_]u32{
        0x07230203, 0x00010000, 0x00080008, 0x00000005, 0x00000018,
        0x00020011, 0x00000001, 0x0006000B, 0x00000001, 0x4C534C47,
        0x00000001, 0x0000000D, 0x00000003, 0x00000002, 0x00000007,
        0x00000004, 0x00000001, 0x6E69616D, 0x00000000, 0x00000005,
        0x00000004, 0x00000000, 0x00000003, 0x00000001, 0x00000004,
        0x00000003, 0x00000000, 0x00000004, 0x00000003, 0x00000001,
        0x00000005, 0x00000005, 0x00000004, 0x00000002, 0x00000006,
        0x00000001, 0x00000000, 0x00050048, 0x00000003, 0x00000001,
        0x00000004, 0x00000002, 0x00050048, 0x00000003, 0x00000001,
        0x00000004, 0x00000004, 0x00050048, 0x00000003, 0x00000001,
        0x00000004, 0x00000006, 0x00050048, 0x00000003, 0x00000001,
        0x00000004, 0x00000008, 0x00050048, 0x00000003, 0x00000001,
        0x00000004, 0x0000000A, 0x00030047, 0x00000003, 0x00000002,
        0x00040047, 0x00000005, 0x0000001E, 0x00000000, 0x00040047,
        0x00000006, 0x0000001E, 0x00000002, 0x00050048, 0x00000007,
        0x00000001, 0x0000000B, 0x00000000, 0x00050048, 0x00000007,
        0x00000001, 0x0000000B, 0x00000002, 0x00040047, 0x00000007,
        0x0000001E, 0x00000000, 0x00050048, 0x00000008, 0x00000001,
        0x0000000B, 0x00000004, 0x00050048, 0x00000008, 0x00000001,
        0x0000000B, 0x00000006, 0x00040047, 0x00000008, 0x0000001E,
        0x00000002, 0x00050048, 0x00000009, 0x00000001, 0x0000000C,
        0x00000000, 0x00050048, 0x00000009, 0x00000001, 0x0000000C,
        0x00000002, 0x00050048, 0x00000009, 0x00000001, 0x0000000C,
        0x00000004, 0x00050048, 0x00000009, 0x00000001, 0x0000000C,
        0x00000006, 0x00040047, 0x00000009, 0x0000001E, 0x00000001,
        0x00050048, 0x0000000A, 0x00000001, 0x0000000C, 0x00000008,
        0x00050048, 0x0000000A, 0x00000001, 0x0000000C, 0x0000000A,
        0x00040047, 0x0000000A, 0x0000001E, 0x00000003, 0x00050048,
        0x0000000B, 0x00000001, 0x0000000C, 0x0000000C, 0x00050048,
        0x0000000B, 0x00000001, 0x0000000C, 0x0000000E, 0x00040047,
        0x0000000B, 0x0000001E, 0x00000004, 0x00050048, 0x0000000C,
        0x00000001, 0x0000000C, 0x00000010, 0x00050048, 0x0000000C,
        0x00000001, 0x0000000C, 0x00000012, 0x00040047, 0x0000000C,
        0x0000001E, 0x00000005, 0x00020013, 0x0000000D, 0x00030021,
        0x0000000E, 0x0000000D, 0x00040036, 0x0000000F, 0x00000001,
        0x0000000D, 0x0003003B, 0x00000010, 0x0000000F, 0x00000000,
        0x00060032, 0x00000011, 0x00000002, 0x00000012, 0x00000010,
        0x00000000, 0x0002001E, 0x00000012, 0x00000011, 0x0004003B,
        0x00000013, 0x00000012, 0x00000000, 0x0004003B, 0x00000014,
        0x00000012, 0x00000001, 0x0004003B, 0x00000015, 0x00000012,
        0x00000002, 0x0004003B, 0x00000016, 0x00000012, 0x00000003,
        0x0004003B, 0x00000017, 0x00000012, 0x00000004, 0x0004003B,
        0x00000018, 0x00000012, 0x00000005, 0x00050041, 0x00000019,
        0x0000000D, 0x00000013, 0x00000014, 0x0003003E, 0x00000010,
        0x00000000, 0x00000013, 0x000100FD,
    };
    const fs = [_]u32{
        0x07230203, 0x00010000, 0x00080008, 0x00000005, 0x00000014,
        0x00020011, 0x00000001, 0x0006000B, 0x00000001, 0x4C534C47,
        0x00000001, 0x0000000D, 0x00000003, 0x00000002, 0x00000007,
        0x00000004, 0x00000001, 0x6E69616D, 0x00000000, 0x00000005,
        0x00000004, 0x00000000, 0x00000003, 0x00000001, 0x00000004,
        0x00000003, 0x00000000, 0x00000004, 0x00000003, 0x00000001,
        0x00000005, 0x00000005, 0x00000004, 0x00000002, 0x00000006,
        0x00000001, 0x00000000, 0x00050048, 0x00000003, 0x00000001,
        0x00000004, 0x00000000, 0x00050048, 0x00000003, 0x00000001,
        0x00000004, 0x00000002, 0x00050048, 0x00000003, 0x00000001,
        0x00000004, 0x00000004, 0x00050048, 0x00000003, 0x00000001,
        0x00000004, 0x00000006, 0x00050048, 0x00000003, 0x00000001,
        0x00000004, 0x00000008, 0x00050048, 0x00000003, 0x00000001,
        0x00000004, 0x0000000A, 0x00030047, 0x00000003, 0x00000002,
        0x00040047, 0x00000005, 0x0000001E, 0x00000000, 0x00040047,
        0x00000006, 0x0000001E, 0x00000002, 0x00050048, 0x00000007,
        0x00000001, 0x0000000B, 0x00000000, 0x00050048, 0x00000007,
        0x00000001, 0x0000000B, 0x00000002, 0x00040047, 0x00000007,
        0x0000001E, 0x00000000, 0x00050048, 0x00000008, 0x00000001,
        0x0000000B, 0x00000004, 0x00050048, 0x00000008, 0x00000001,
        0x0000000B, 0x00000006, 0x00040047, 0x00000008, 0x0000001E,
        0x00000002, 0x00050048, 0x00000009, 0x00000001, 0x0000000C,
        0x00000000, 0x00050048, 0x00000009, 0x00000001, 0x0000000C,
        0x00000002, 0x00050048, 0x00000009, 0x00000001, 0x0000000C,
        0x00000004, 0x00050048, 0x00000009, 0x00000001, 0x0000000C,
        0x00000006, 0x00040047, 0x00000009, 0x0000001E, 0x00000001,
        0x00050048, 0x0000000A, 0x00000001, 0x0000000C, 0x00000008,
        0x00050048, 0x0000000A, 0x00000001, 0x0000000C, 0x0000000A,
        0x00040047, 0x0000000A, 0x0000001E, 0x00000003, 0x00050048,
        0x0000000B, 0x00000001, 0x0000000C, 0x0000000C, 0x00050048,
        0x0000000B, 0x00000001, 0x0000000C, 0x0000000E, 0x00040047,
        0x0000000B, 0x0000001E, 0x00000004, 0x00020013, 0x0000000D,
        0x00030021, 0x0000000E, 0x0000000D, 0x00040036, 0x0000000F,
        0x00000001, 0x0000000D, 0x0003003B, 0x00000010, 0x0000000F,
        0x00000000, 0x00060032, 0x00000011, 0x00000002, 0x00000012,
        0x00000010, 0x00000000, 0x0002001E, 0x00000012, 0x00000011,
        0x0004003B, 0x00000013, 0x00000012, 0x00000000, 0x0004003B,
        0x00000014, 0x00000012, 0x00000001, 0x0004003B, 0x00000015,
        0x00000012, 0x00000002, 0x0004003B, 0x00000016, 0x00000012,
        0x00000003, 0x0004003B, 0x00000017, 0x00000012, 0x00000004,
        0x0004003B, 0x00000018, 0x00000012, 0x00000005, 0x00050041,
        0x00000019, 0x0000000D, 0x00000013, 0x00000018, 0x0003003E,
        0x00000010, 0x00000000, 0x00000013, 0x000100FD,
    };

    var vs_ci: [16]u8 = undefined;
    var vsi: usize = 0;
    while (vsi < 16) : (vsi += 1) vs_ci[vsi] = 0;
    @as(*u32, @alignCast(@ptrCast(vs_ci[0..].ptr))).* = 43; // SHADER_MODULE_CREATE_INFO
    @as(*u64, @alignCast(@ptrCast(vs_ci[4..].ptr))).* = vs.len * 4;
    @as(*u64, @alignCast(@ptrCast(vs_ci[8..].ptr))).* = @intFromPtr(&vs);

    var fs_ci: [16]u8 = undefined;
    var fsi: usize = 0;
    while (fsi < 16) : (fsi += 1) fs_ci[fsi] = 0;
    @as(*u32, @alignCast(@ptrCast(fs_ci[0..].ptr))).* = 43;
    @as(*u64, @alignCast(@ptrCast(fs_ci[4..].ptr))).* = fs.len * 4;
    @as(*u64, @alignCast(@ptrCast(fs_ci[8..].ptr))).* = @intFromPtr(&fs);

    var vs_mod: u64 = 0; var fs_mod: u64 = 0;
    if (fns.create_shader_module(vk_dev, @ptrCast(&vs_ci), null, &vs_mod) != 0) return false;
    if (fns.create_shader_module(vk_dev, @ptrCast(&fs_ci), null, &fs_mod) != 0) return false;

    // Pipeline layout
    var plci: [16]u8 = undefined;
    var pli: usize = 0;
    while (pli < 16) : (pli += 1) plci[pli] = 0;
    @as(*u32, @alignCast(@ptrCast(plci[0..].ptr))).* = 42; // PIPELINE_LAYOUT_CREATE_INFO
    if (fns.create_pipeline_layout(vk_dev, @ptrCast(&plci), null, &vk_pipe_layout) != 0) return false;

    // Graphics pipeline — build in a big buffer
    var pipe_buf: [1024]u8 = undefined;
    var pi: usize = 0;
    while (pi < 1024) : (pi += 1) pipe_buf[pi] = 0;

    // Shader stages at offset 0
    @as(*u32, @alignCast(@ptrCast(pipe_buf[0..].ptr))).* = 29; // PIPELINE_SHADER_STAGE_CREATE_INFO (vs)
    @as(*u32, @alignCast(@ptrCast(pipe_buf[4..].ptr))).* = 1; // VERTEX_BIT
    @as(*u64, @alignCast(@ptrCast(pipe_buf[8..].ptr))).* = vs_mod;
    @as(*u32, @alignCast(@ptrCast(pipe_buf[128..].ptr))).* = 29; // PIPELINE_SHADER_STAGE_CREATE_INFO (fs)
    @as(*u32, @alignCast(@ptrCast(pipe_buf[132..].ptr))).* = 2; // FRAGMENT_BIT
    @as(*u64, @alignCast(@ptrCast(pipe_buf[136..].ptr))).* = fs_mod;

    // Vertex input state at offset 256
    @as(*u32, @alignCast(@ptrCast(pipe_buf[256..].ptr))).* = 30; // VERTEX_INPUT_STATE_CREATE_INFO
    @as(*u32, @alignCast(@ptrCast(pipe_buf[260..].ptr))).* = 1; // bindingCount
    @as(*u64, @alignCast(@ptrCast(pipe_buf[264..].ptr))).* = @intFromPtr(&pipe_buf[320]); // pBindings
    @as(*u32, @alignCast(@ptrCast(pipe_buf[272..].ptr))).* = 2; // attributeCount
    @as(*u64, @alignCast(@ptrCast(pipe_buf[280..].ptr))).* = @intFromPtr(&pipe_buf[340]); // pAttributes
    // binding desc at 320: binding=0, stride=24, rate=0
    @as(*u32, @alignCast(@ptrCast(pipe_buf[320..].ptr))).* = 0;
    @as(*u32, @alignCast(@ptrCast(pipe_buf[324..].ptr))).* = 24;
    @as(*u32, @alignCast(@ptrCast(pipe_buf[328..].ptr))).* = 0;
    // attr 0 at 340: loc=0, bind=0, fmt=106, off=0
    @as(*u32, @alignCast(@ptrCast(pipe_buf[340..].ptr))).* = 0;
    @as(*u32, @alignCast(@ptrCast(pipe_buf[344..].ptr))).* = 0;
    @as(*u32, @alignCast(@ptrCast(pipe_buf[348..].ptr))).* = 106; // R32G32B32_SFLOAT
    @as(*u32, @alignCast(@ptrCast(pipe_buf[352..].ptr))).* = 0;
    // attr 1 at 356: loc=1, bind=0, fmt=106, off=12
    @as(*u32, @alignCast(@ptrCast(pipe_buf[356..].ptr))).* = 1;
    @as(*u32, @alignCast(@ptrCast(pipe_buf[360..].ptr))).* = 0;
    @as(*u32, @alignCast(@ptrCast(pipe_buf[364..].ptr))).* = 106;
    @as(*u32, @alignCast(@ptrCast(pipe_buf[368..].ptr))).* = 12;

    // Input assembly at offset 384
    @as(*u32, @alignCast(@ptrCast(pipe_buf[384..].ptr))).* = 31; // INPUT_ASSEMBLY_STATE_CREATE_INFO
    @as(*u32, @alignCast(@ptrCast(pipe_buf[392..].ptr))).* = 3; // TRIANGLE_LIST

    // Viewport state at offset 416
    @as(*u32, @alignCast(@ptrCast(pipe_buf[416..].ptr))).* = 33; // VIEWPORT_STATE_CREATE_INFO
    @as(*u32, @alignCast(@ptrCast(pipe_buf[420..].ptr))).* = 1; // viewportCount
    @as(*u32, @alignCast(@ptrCast(pipe_buf[424..].ptr))).* = 1; // scissorCount

    // Rasterization state at offset 448
    @as(*u32, @alignCast(@ptrCast(pipe_buf[448..].ptr))).* = 34; // RASTERIZATION_STATE_CREATE_INFO
    @as(*u32, @alignCast(@ptrCast(pipe_buf[460..].ptr))).* = 0; // FILL
    @as(*u32, @alignCast(@ptrCast(pipe_buf[464..].ptr))).* = 0; // CULL_MODE_NONE
    @as(*u32, @alignCast(@ptrCast(pipe_buf[468..].ptr))).* = 1; // CCW

    // Multisample at offset 480
    @as(*u32, @alignCast(@ptrCast(pipe_buf[480..].ptr))).* = 35; // MULTISAMPLE_STATE_CREATE_INFO
    @as(*u32, @alignCast(@ptrCast(pipe_buf[484..].ptr))).* = 1; // SAMPLE_COUNT_1

    // Color blend at offset 512
    @as(*u32, @alignCast(@ptrCast(pipe_buf[512..].ptr))).* = 36; // COLOR_BLEND_STATE_CREATE_INFO
    @as(*u32, @alignCast(@ptrCast(pipe_buf[516..].ptr))).* = 1; // attachmentCount
    @as(*u64, @alignCast(@ptrCast(pipe_buf[520..].ptr))).* = @intFromPtr(&pipe_buf[560]); // pAttachments
    // blend attachment at 560
    @as(*u32, @alignCast(@ptrCast(pipe_buf[560..].ptr))).* = 0; // blendEnable
    @as(*u32, @alignCast(@ptrCast(pipe_buf[564..].ptr))).* = 2; // srcColorBlendFactor = ONE
    @as(*u32, @alignCast(@ptrCast(pipe_buf[576..].ptr))).* = 15; // colorWriteMask = 0xF

    // Dynamic state at offset 592
    @as(*u32, @alignCast(@ptrCast(pipe_buf[592..].ptr))).* = 38; // DYNAMIC_STATE_CREATE_INFO
    @as(*u32, @alignCast(@ptrCast(pipe_buf[596..].ptr))).* = 2;
    @as(*u64, @alignCast(@ptrCast(pipe_buf[600..].ptr))).* = @intFromPtr(&pipe_buf[620]);
    @as(*u32, @alignCast(@ptrCast(pipe_buf[620..].ptr))).* = 0; // VIEWPORT
    @as(*u32, @alignCast(@ptrCast(pipe_buf[624..].ptr))).* = 1; // SCISSOR

    // Graphics pipeline create info at offset 640
    @as(*u32, @alignCast(@ptrCast(pipe_buf[640..].ptr))).* = 28; // GRAPHICS_PIPELINE_CREATE_INFO
    @as(*u32, @alignCast(@ptrCast(pipe_buf[648..].ptr))).* = 2; // stageCount
    @as(*u64, @alignCast(@ptrCast(pipe_buf[652..].ptr))).* = @intFromPtr(&pipe_buf[0]); // pStages
    @as(*u64, @alignCast(@ptrCast(pipe_buf[660..].ptr))).* = @intFromPtr(&pipe_buf[256]); // pVertexInputState
    @as(*u64, @alignCast(@ptrCast(pipe_buf[668..].ptr))).* = @intFromPtr(&pipe_buf[384]); // pInputAssemblyState
    @as(*u64, @alignCast(@ptrCast(pipe_buf[684..].ptr))).* = @intFromPtr(&pipe_buf[416]); // pViewportState
    @as(*u64, @alignCast(@ptrCast(pipe_buf[692..].ptr))).* = @intFromPtr(&pipe_buf[448]); // pRasterizationState
    @as(*u64, @alignCast(@ptrCast(pipe_buf[700..].ptr))).* = @intFromPtr(&pipe_buf[480]); // pMultisampleState
    @as(*u64, @alignCast(@ptrCast(pipe_buf[716..].ptr))).* = @intFromPtr(&pipe_buf[512]); // pColorBlendState
    @as(*u64, @alignCast(@ptrCast(pipe_buf[724..].ptr))).* = @intFromPtr(&pipe_buf[592]); // pDynamicState
    @as(*u64, @alignCast(@ptrCast(pipe_buf[732..].ptr))).* = vk_pipe_layout; // layout
    @as(*u64, @alignCast(@ptrCast(pipe_buf[740..].ptr))).* = vk_rp; // renderPass
    // subpass at 748 = 0 (default)

    if (fns.create_graphics_pipelines(vk_dev, 0, 1, @as([*]u64, @alignCast(@ptrCast(&pipe_buf[640]))), null, &vk_pipe) != 0) return false;
    fns.destroy_shader_module(vk_dev, vs_mod, null);
    fns.destroy_shader_module(vk_dev, fs_mod, null);

    // Command pool + buffers
    var pool_ci: [16]u8 = undefined;
    var pi2: usize = 0;
    while (pi2 < 16) : (pi2 += 1) pool_ci[pi2] = 0;
    @as(*u32, @alignCast(@ptrCast(pool_ci[0..].ptr))).* = 16; // COMMAND_POOL_CREATE_INFO
    @as(*u32, @alignCast(@ptrCast(pool_ci[4..].ptr))).* = 1; // RESET_COMMAND_BUFFER_BIT
    @as(*u32, @alignCast(@ptrCast(pool_ci[8..].ptr))).* = vk_qfam;
    _ = vkCreateCommandPool(vk_dev, @ptrCast(&pool_ci), null, &vk_pool);

    var cbai: [24]u8 = undefined;
    var cbi: usize = 0;
    while (cbi < 24) : (cbi += 1) cbai[cbi] = 0;
    @as(*u32, @alignCast(@ptrCast(cbai[0..].ptr))).* = 40; // COMMAND_BUFFER_ALLOCATE_INFO
    @as(*u64, @alignCast(@ptrCast(cbai[4..].ptr))).* = vk_pool;
    @as(*u32, @alignCast(@ptrCast(cbai[12..].ptr))).* = 0; // PRIMARY
    @as(*u32, @alignCast(@ptrCast(cbai[16..].ptr))).* = 2;
    _ = vkAllocateCommandBuffers(vk_dev, @ptrCast(&cbai), &vk_cmds);

    // Sync
    var fci: [12]u8 = undefined;
    var fi2: usize = 0;
    while (fi2 < 12) : (fi2 += 1) fci[fi2] = 0;
    @as(*u32, @alignCast(@ptrCast(fci[0..].ptr))).* = 8; // FENCE_CREATE_INFO
    _ = fns.create_fence(vk_dev, @ptrCast(&fci), null, &vk_fence[0]);
    _ = fns.create_fence(vk_dev, @ptrCast(&fci), null, &vk_fence[1]);

    var sci2: [12]u8 = undefined;
    var sci3: usize = 0;
    while (sci3 < 12) : (sci3 += 1) sci2[sci3] = 0;
    @as(*u32, @alignCast(@ptrCast(sci2[0..].ptr))).* = 9; // SEMAPHORE_CREATE_INFO
    _ = fns.create_semaphore(vk_dev, @ptrCast(&sci2), null, &vk_sem_avail);
    _ = fns.create_semaphore(vk_dev, @ptrCast(&sci2), null, &vk_sem_done);

    // Vertex buffer
    var vertices = [_]f32{
        0.0, -0.5, 0.0,  1.0, 0.0, 0.0,
        -0.5, 0.5, 0.0,  0.0, 1.0, 0.0,
        0.5, 0.5, 0.0,   0.0, 0.0, 1.0,
    };
    const vbuf_size: u64 = @sizeOf(@TypeOf(vertices));

    var bci: [32]u8 = undefined;
    var bi: usize = 0;
    while (bi < 32) : (bi += 1) bci[bi] = 0;
    @as(*u32, @alignCast(@ptrCast(bci[0..].ptr))).* = 12; // BUFFER_CREATE_INFO
    @as(*u64, @alignCast(@ptrCast(bci[4..].ptr))).* = vbuf_size;
    @as(*u32, @alignCast(@ptrCast(bci[12..].ptr))).* = 4; // VERTEX_BUFFER
    @as(*u32, @alignCast(@ptrCast(bci[16..].ptr))).* = 0; // EXCLUSIVE
    if (fns.create_buffer(vk_dev, @ptrCast(&bci), null, &vk_vbuf) != 0) return false;

    var mem_req: [24]u8 = undefined;
    var mri: usize = 0;
    while (mri < 24) : (mri += 1) mem_req[mri] = 0;
    fns.get_buffer_memory_requirements(vk_dev, vk_vbuf, @ptrCast(&mem_req));
    const mem_size = @as(*u64, @alignCast(@ptrCast(mem_req[8..].ptr))).*;
    const mem_bits = @as(*u32, @alignCast(@ptrCast(mem_req[16..].ptr))).*;

    _ = vkGetPhysicalDeviceMemoryProperties(vk_phys, @ptrCast(&vk_mem_props));
    const type_count = @as(*u32, @alignCast(@ptrCast(&vk_mem_props))).*;
    var found_type = false;
    var ti: u32 = 0;
    while (ti < type_count) : (ti += 1) {
        const props = @as(*u32, @alignCast(@ptrCast(@as([*]u8, @ptrCast(&vk_mem_props)) + 136 + ti * 16 + 4))).*;
        if ((mem_bits & (@as(u32, 1) << @intCast(ti))) != 0 and (props & 3) != 0) { found_type = true; break; }
    }
    if (!found_type) return false;

    var alloc_ci: [16]u8 = undefined;
    var ali: usize = 0;
    while (ali < 16) : (ali += 1) alloc_ci[ali] = 0;
    @as(*u32, @alignCast(@ptrCast(alloc_ci[0..].ptr))).* = 5; // MEMORY_ALLOCATE_INFO
    @as(*u64, @alignCast(@ptrCast(alloc_ci[4..].ptr))).* = mem_size;
    @as(*u32, @alignCast(@ptrCast(alloc_ci[12..].ptr))).* = ti;
    if (fns.allocate_memory(vk_dev, @ptrCast(&alloc_ci), null, &vk_vmem) != 0) return false;
    _ = fns.bind_buffer_memory(vk_dev, vk_vbuf, vk_vmem, 0);

    var mapped: ?*anyopaque = null;
    _ = fns.map_memory(vk_dev, vk_vmem, 0, vbuf_size, 0, &mapped);
    if (mapped) |m| {
        @memcpy(@as([*]u8, @ptrCast(m))[0..vbuf_size], @as([*]const u8, @ptrCast(&vertices)));
        fns.unmap_memory(vk_dev, vk_vmem);
    }

    return true;
}

pub fn deinit() void {
    if (!ok) return;
    if (vk_dev != 0) _ = vkDeviceWaitIdle(vk_dev);
    if (x_dpy) |dpy| {
        if (x_win != 0) _ = XDestroyWindow(dpy, x_win);
        _ = XCloseDisplay(dpy);
        x_dpy = null;
    }
    ok = false;
}

pub fn beginFrame() void {}
pub fn endFrame() void {}

pub fn pollEvent() ?sys.Event {
    if (x_dpy == null) return null;
    if (XPending(x_dpy.?) == 0) return null;
    var ev: XEvent = undefined;
    _ = XNextEvent(x_dpy.?, @ptrCast(&ev));
    if (ev.type == 2) return sys.Event{ .key_press = @intCast(ev.keycode) };
    if (ev.type == 3) return sys.Event{ .key_release = @intCast(ev.keycode) };
    if (ev.type == 4) return .{ .mouse_down = .{ .x = ev.x, .y = ev.y, .btn = @intCast(ev.keycode) } };
    if (ev.type == 5) return .{ .mouse_up = .{ .x = ev.x, .y = ev.y, .btn = @intCast(ev.keycode) } };
    if (ev.type == 6) return .{ .mouse_move = .{ .x = ev.x, .y = ev.y } };
    if (ev.type == 12) return sys.Event.expose;
    if (ev.type == 33) return sys.Event.close;
    return null;
}

pub fn blitPixels(_: i32, _: i32, _: u32, _: u32) void {}
pub fn isActive() bool { return ok; }
pub fn getWindow() u64 { return x_win; }
pub fn isGpuEnabled() bool { return ok; }
pub fn getStagingBufferPtr() ?[*]u32 { return null; }
