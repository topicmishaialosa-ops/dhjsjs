pub const ANDROID_FB_ADDR: u64 = 0x200000;
pub const ANDROID_CMD_ADDR: u64 = 0x200100;

pub const AndroidCmd = extern struct {
    activity_ptr: u64,          // 0
    window_ptr: u64,            // 8
    input_queue_ptr: u64,       // 16
    has_window: u32,            // 24
    has_focus: u32,             // 28
    should_finish: u32,         // 32
    fb_width: u32,              // 36
    fb_height: u32,             // 40
    fb_stride: u32,             // 44
    fb_pixels: u64,             // 48
    touch_x: i32,               // 56 (integer pixel coord)
    touch_y: i32,               // 60
    touch_down: u32,            // 64
    touch_action: u32,          // 68 (0=down,1=up,2=move)
    touch_pointer_id: u32,      // 72
    key_action: u32,            // 76 (0=down,1=up)
    key_code: u32,              // 80
    lock_fn: u64,               // 88
    unlock_fn: u64,             // 96
    get_event_fn: u64,          // 104
    finish_event_fn: u64,       // 112
    get_event_type_fn: u64,     // 120
    get_action_fn: u64,         // 128
    get_x_fn: u64,              // 136
    get_y_fn: u64,              // 144
    get_keycode_fn: u64,        // 152
    present_fn: u64,            // 160
    touch_count: u32,           // 168
    touch_x_arr: [16]i32,       // 172
    touch_y_arr: [16]i32,       // 236
    touch_down_arr: [16]u32,    // 300
    touch_action_arr: [16]u32,  // 364
    touch_id_arr: [16]u32,      // 428
    clicked: u32,               // 492
    click_x: i32,               // 496
    click_y: i32,               // 500
    cur_ev_type: u32,           // 504 (1=touch_down,2=touch_up,3=touch_move,4=key_down,5=key_up)
    event_cursor: u32,          // 508
};

pub const AndroidFb = struct {
    pixels: [800 * 600 * 4]u8,
};

pub fn initCmd() AndroidCmd {
    return AndroidCmd{
        .activity_ptr = 0,
        .window_ptr = 0,
        .input_queue_ptr = 0,
        .has_window = 0,
        .has_focus = 0,
        .should_finish = 0,
        .fb_width = 0,
        .fb_height = 0,
        .fb_stride = 0,
        .fb_pixels = 0,
        .touch_x = 0,
        .touch_y = 0,
        .touch_down = 0,
        .touch_action = 0,
        .touch_pointer_id = 0,
        .key_action = 0,
        .key_code = 0,
        .lock_fn = 0,
        .unlock_fn = 0,
        .get_event_fn = 0,
        .finish_event_fn = 0,
        .get_event_type_fn = 0,
        .get_action_fn = 0,
        .get_x_fn = 0,
        .get_y_fn = 0,
        .get_keycode_fn = 0,
        .present_fn = 0,
        .touch_count = 0,
        .touch_x_arr = [_]i32{0} ** 16,
        .touch_y_arr = [_]i32{0} ** 16,
        .touch_down_arr = [_]u32{0} ** 16,
        .touch_action_arr = [_]u32{0} ** 16,
        .touch_id_arr = [_]u32{0} ** 16,
        .clicked = 0,
        .click_x = 0,
        .click_y = 0,
        .cur_ev_type = 0,
        .event_cursor = 0,
    };
}
