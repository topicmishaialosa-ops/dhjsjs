const sys = @import("sys.zig");

pub const MAX_BUTTONS: usize = 8;
pub const PRIMARY: u8 = 1;
pub const MIDDLE: u8 = 2;
pub const SECONDARY: u8 = 3;
pub const X1: u8 = 4;
pub const X2: u8 = 5;

pub const DOUBLE_CLICK_FRAMES: u32 = 24;
pub const DOUBLE_CLICK_DIST: i32 = 4;
pub const DRAG_THRESHOLD: i32 = 3;

pub const Rect = struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
};

pub const ButtonState = struct {
    down: bool,
    pressed: bool,
    released: bool,
    clicked: bool,
    double_clicked: bool,
    dragging: bool,
    drag_started: bool,
    drag_released: bool,
    press_x: i32,
    press_y: i32,
    release_x: i32,
    release_y: i32,
    last_click_x: i32,
    last_click_y: i32,
    last_click_frame: u32,
};

pub const State = struct {
    x: i32,
    y: i32,
    prev_x: i32,
    prev_y: i32,
    dx: i32,
    dy: i32,
    wheel_x: i32,
    wheel_y: i32,
    entered: bool,
    left: bool,
    moved: bool,
    primary_down: bool,
    primary_pressed: bool,
    primary_released: bool,
    primary_clicked: bool,
    primary_double_clicked: bool,
    any_down: bool,
    any_pressed: bool,
    any_released: bool,
    capture_id: u32,
    hover_id: u32,
    frame: u32,
    buttons: [MAX_BUTTONS + 1]ButtonState,

    pub fn init() State {
        return State{
            .x = 0,
            .y = 0,
            .prev_x = 0,
            .prev_y = 0,
            .dx = 0,
            .dy = 0,
            .wheel_x = 0,
            .wheel_y = 0,
            .entered = false,
            .left = false,
            .moved = false,
            .primary_down = false,
            .primary_pressed = false,
            .primary_released = false,
            .primary_clicked = false,
            .primary_double_clicked = false,
            .any_down = false,
            .any_pressed = false,
            .any_released = false,
            .capture_id = 0,
            .hover_id = 0,
            .frame = 0,
            .buttons = [_]ButtonState{emptyButton()} ** (MAX_BUTTONS + 1),
        };
    }

    pub fn beginFrame(self: *State) void {
        self.prev_x = self.x;
        self.prev_y = self.y;
        self.dx = 0;
        self.dy = 0;
        self.wheel_x = 0;
        self.wheel_y = 0;
        self.entered = false;
        self.left = false;
        self.moved = false;
        self.primary_pressed = false;
        self.primary_released = false;
        self.primary_clicked = false;
        self.primary_double_clicked = false;
        self.any_pressed = false;
        self.any_released = false;
        self.hover_id = 0;
        self.frame +%= 1;

        var i: usize = 0;
        while (i < self.buttons.len) : (i += 1) {
            self.buttons[i].pressed = false;
            self.buttons[i].released = false;
            self.buttons[i].clicked = false;
            self.buttons[i].double_clicked = false;
            self.buttons[i].drag_started = false;
            self.buttons[i].drag_released = false;
        }
    }

    pub fn applyEvent(self: *State, ev: sys.Event) void {
        switch (ev) {
            .mouse_move => |m| self.moveTo(m.x, m.y),
            .mouse_down => |m| {
                self.moveTo(m.x, m.y);
                self.press(m.btn);
            },
            .mouse_up => |m| {
                self.moveTo(m.x, m.y);
                self.release(m.btn);
            },
            .scroll => |s| {
                self.wheel_x += s.dx;
                self.wheel_y += s.dy;
            },
            else => {},
        }
    }

    pub fn endFrame(self: *State) void {
        self.primary_down = self.isDown(PRIMARY);
        self.primary_pressed = self.isPressed(PRIMARY);
        self.primary_released = self.isReleased(PRIMARY);
        self.primary_clicked = self.isClicked(PRIMARY);
        self.primary_double_clicked = self.isDoubleClicked(PRIMARY);

        self.any_down = false;
        self.any_pressed = false;
        self.any_released = false;
        var i: usize = 1;
        while (i < self.buttons.len) : (i += 1) {
            if (self.buttons[i].down) self.any_down = true;
            if (self.buttons[i].pressed) self.any_pressed = true;
            if (self.buttons[i].released) self.any_released = true;
        }

        if (!self.any_down) self.capture_id = 0;
    }

    pub fn setCapture(self: *State, id: u32) void {
        self.capture_id = id;
    }

    pub fn releaseCapture(self: *State, id: u32) void {
        if (self.capture_id == id) self.capture_id = 0;
    }

    pub fn hasCapture(self: *const State, id: u32) bool {
        return self.capture_id == id;
    }

    pub fn hit(self: *const State, r: Rect) bool {
        return self.x >= r.x and self.x < r.x + @as(i32, @intCast(r.w)) and
            self.y >= r.y and self.y < r.y + @as(i32, @intCast(r.h));
    }

    pub fn hot(self: *State, id: u32, r: Rect) bool {
        if (self.capture_id != 0 and self.capture_id != id) return false;
        const ok = self.hit(r);
        if (ok) self.hover_id = id;
        return ok;
    }

    pub fn capturedOrHot(self: *State, id: u32, r: Rect) bool {
        if (self.capture_id == id) return true;
        return self.hot(id, r);
    }

    pub fn isDown(self: *const State, btn: u8) bool {
        if (btn > MAX_BUTTONS) return false;
        return self.buttons[btn].down;
    }

    pub fn isPressed(self: *const State, btn: u8) bool {
        if (btn > MAX_BUTTONS) return false;
        return self.buttons[btn].pressed;
    }

    pub fn isReleased(self: *const State, btn: u8) bool {
        if (btn > MAX_BUTTONS) return false;
        return self.buttons[btn].released;
    }

    pub fn isClicked(self: *const State, btn: u8) bool {
        if (btn > MAX_BUTTONS) return false;
        return self.buttons[btn].clicked;
    }

    pub fn isDoubleClicked(self: *const State, btn: u8) bool {
        if (btn > MAX_BUTTONS) return false;
        return self.buttons[btn].double_clicked;
    }

    pub fn isDragging(self: *const State, btn: u8) bool {
        if (btn > MAX_BUTTONS) return false;
        return self.buttons[btn].dragging;
    }

    pub fn dragStarted(self: *const State, btn: u8) bool {
        if (btn > MAX_BUTTONS) return false;
        return self.buttons[btn].drag_started;
    }

    pub fn dragReleased(self: *const State, btn: u8) bool {
        if (btn > MAX_BUTTONS) return false;
        return self.buttons[btn].drag_released;
    }

    pub fn dragX(self: *const State, btn: u8) i32 {
        if (btn > MAX_BUTTONS) return 0;
        return self.x - self.buttons[btn].press_x;
    }

    pub fn dragY(self: *const State, btn: u8) i32 {
        if (btn > MAX_BUTTONS) return 0;
        return self.y - self.buttons[btn].press_y;
    }

    fn moveTo(self: *State, x: i32, y: i32) void {
        self.dx += x - self.x;
        self.dy += y - self.y;
        self.x = x;
        self.y = y;
        self.moved = true;
        self.updateDragFlags();
    }

    fn press(self: *State, btn_raw: u8) void {
        const btn = normalizeButton(btn_raw);
        if (btn == 0 or btn > MAX_BUTTONS) return;
        var b = &self.buttons[btn];
        if (!b.down) {
            b.down = true;
            b.pressed = true;
            b.press_x = self.x;
            b.press_y = self.y;
            b.dragging = false;
            self.any_pressed = true;
        }
    }

    fn release(self: *State, btn_raw: u8) void {
        const btn = normalizeButton(btn_raw);
        if (btn == 0 or btn > MAX_BUTTONS) return;
        var b = &self.buttons[btn];
        if (b.down) {
            const ddx = absI32(self.x - b.press_x);
            const ddy = absI32(self.y - b.press_y);
            if (!b.dragging and (ddx > DRAG_THRESHOLD or ddy > DRAG_THRESHOLD)) {
                b.dragging = true;
                b.drag_started = true;
            }
            b.down = false;
            b.released = true;
            b.release_x = self.x;
            b.release_y = self.y;
            b.clicked = !b.dragging;
            b.drag_released = b.dragging;
            if (b.clicked and b.last_click_frame != 0xFFFFFFFF and
                self.frame -% b.last_click_frame <= DOUBLE_CLICK_FRAMES and
                absI32(self.x - b.last_click_x) <= DOUBLE_CLICK_DIST and
                absI32(self.y - b.last_click_y) <= DOUBLE_CLICK_DIST)
            {
                b.double_clicked = true;
            }
            if (b.clicked) {
                b.last_click_frame = self.frame;
                b.last_click_x = self.x;
                b.last_click_y = self.y;
            }
            b.dragging = false;
            self.any_released = true;
        }
    }

    fn updateDragFlags(self: *State) void {
        var i: usize = 1;
        while (i < self.buttons.len) : (i += 1) {
            if (self.buttons[i].down) {
                const ddx = absI32(self.x - self.buttons[i].press_x);
                const ddy = absI32(self.y - self.buttons[i].press_y);
                if (!self.buttons[i].dragging and (ddx > DRAG_THRESHOLD or ddy > DRAG_THRESHOLD)) {
                    self.buttons[i].dragging = true;
                    self.buttons[i].drag_started = true;
                }
            }
        }
    }
};

pub fn normalizeButton(btn: u8) u8 {
    if (btn <= MAX_BUTTONS) return btn;
    return 0;
}

pub fn rect(x: i32, y: i32, w: u32, h: u32) Rect {
    return Rect{ .x = x, .y = y, .w = w, .h = h };
}

fn emptyButton() ButtonState {
    return ButtonState{
        .down = false,
        .pressed = false,
        .released = false,
        .clicked = false,
        .double_clicked = false,
        .dragging = false,
        .drag_started = false,
        .drag_released = false,
        .press_x = 0,
        .press_y = 0,
        .release_x = 0,
        .release_y = 0,
        .last_click_x = 0,
        .last_click_y = 0,
        .last_click_frame = 0xFFFFFFFF,
    };
}

fn absI32(v: i32) i32 {
    return if (v < 0) -v else v;
}
