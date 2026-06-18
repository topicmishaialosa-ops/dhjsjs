const gfx = @import("render.zig");

const MAX_NODES: usize = 256;

pub const CNode = struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
    text_start: [*]const u8,
    text_len: usize,
    color: gfx.Color,
    bg: gfx.Color,
};

pub const Compositor = struct {
    nodes: [MAX_NODES]CNode,
    count: usize,

    pub fn init() Compositor {
        return Compositor{ .nodes = undefined, .count = 0 };
    }

    pub fn addNode(self: *Compositor, x: i32, y: i32, w: u32, h: u32, text: []const u8, color: gfx.Color, bg: gfx.Color) void {
        if (self.count >= MAX_NODES) return;
        self.nodes[self.count] = CNode{
            .x = x,
            .y = y,
            .w = w,
            .h = h,
            .text_start = text.ptr,
            .text_len = text.len,
            .color = color,
            .bg = bg,
        };
        self.count += 1;
    }

    pub fn composite(self: *const Compositor, fb: *gfx.Framebuffer) void {
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            const n = &self.nodes[i];
            fb.fillRect(gfx.Rect{ .x = n.x, .y = n.y, .w = n.w, .h = n.h }, n.bg);
            if (n.text_len > 0) {
                fb.drawText(n.text_start[0..n.text_len], n.x + 4, n.y + 4, n.color, 14);
            }
        }
    }

    pub fn clear(self: *Compositor) void {
        self.count = 0;
    }
};
