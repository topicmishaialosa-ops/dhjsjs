const gfx = @import("render.zig");
const utils = @import("utils.zig");

const MAX_FILENAME = 256;
const MAX_CONTENT = 65536;
const MAX_CONSOLE = 8192;
const MAX_FILES = 256;

const FileEntry = struct {
    name: [MAX_FILENAME]u8,
    len: usize,
    is_dir: bool,
};

// ── Native IDE palette ──
const APP_BG = gfx.rgb(13, 17, 23);
const MENU_BG = gfx.rgb(22, 27, 34);
const MENU_BG_2 = gfx.rgb(28, 35, 45);
const MENU_TEXT = gfx.rgb(213, 219, 228);
const MENU_DIM = gfx.rgb(126, 140, 158);
const TOOL_BG = gfx.rgb(17, 23, 32);
const TOOL_BG_2 = gfx.rgb(24, 32, 43);
const TOOL_BUTTON = gfx.rgb(38, 48, 63);
const TOOL_BUTTON_HI = gfx.rgb(47, 59, 78);
const TOOL_BUTTON_ACCENT = gfx.rgb(36, 107, 154);
const TOOL_TEXT = gfx.rgb(229, 236, 246);
const TAB_BG = gfx.rgb(20, 25, 34);
const TAB_ACTIVE = gfx.rgb(15, 20, 28);
const TAB_INACTIVE = gfx.rgb(29, 36, 47);
const TAB_ACCENT = gfx.rgb(72, 174, 188);
const EDITOR_BG = gfx.rgb(12, 16, 22);
const GUTTER_BG = gfx.rgb(16, 21, 29);
const GUTTER_LINE = gfx.rgb(42, 52, 66);
const CUR_LINE_BG = gfx.rgb(23, 31, 42);
const CONSOLE_BG = gfx.rgb(10, 13, 18);
const CONSOLE_HEAD = gfx.rgb(18, 24, 33);
const CONSOLE_TEXT = gfx.rgb(139, 214, 153);
const STATUS_BG = gfx.rgb(20, 27, 36);
const STATUS_TEXT = gfx.rgb(161, 174, 193);
const TEXT_COL = gfx.rgb(232, 238, 247);
const NUML_COL = gfx.rgb(91, 105, 125);
const NUML_CUR = gfx.rgb(205, 215, 230);
const SCROLL_TRACK = gfx.rgb(18, 23, 31);
const SCROLL_THUMB = gfx.rgb(70, 88, 108);
const SCROLL_THUMB_HI = gfx.rgb(96, 120, 148);
const MODIFIED_COL = gfx.rgb(244, 185, 76);
const SELECTION_BG = gfx.rgb(42, 72, 108);
const TRACK_W: u32 = 5;

const MenuAction = enum(u8) {
    none,
    new_file,
    open_file,
    save_file,
    exit_app,
    build,
    about,
    separator,
};

const MenuItem = struct {
    label: []const u8,
    action: MenuAction,
    shortcut: []const u8,
    enabled: bool,
};

const MenuDef = struct {
    label: []const u8,
    items: []const MenuItem,
};

const MENUS = [_]MenuDef{
    .{
        .label = "File",
        .items = &.{
            .{ .label = "New", .action = .new_file, .shortcut = "Ctrl+N", .enabled = true },
            .{ .label = "Open", .action = .open_file, .shortcut = "Ctrl+O", .enabled = true },
            .{ .label = "Save", .action = .save_file, .shortcut = "Ctrl+S", .enabled = true },
            .{ .label = "", .action = .separator, .shortcut = "", .enabled = false },
            .{ .label = "Exit", .action = .exit_app, .shortcut = "Esc", .enabled = true },
        },
    },
    .{
        .label = "Edit",
        .items = &.{
            .{ .label = "Undo", .action = .none, .shortcut = "", .enabled = false },
            .{ .label = "Copy", .action = .none, .shortcut = "", .enabled = false },
            .{ .label = "Paste", .action = .none, .shortcut = "", .enabled = false },
        },
    },
    .{
        .label = "Sketch",
        .items = &.{
            .{ .label = "Verify", .action = .build, .shortcut = "F5", .enabled = true },
            .{ .label = "Upload", .action = .build, .shortcut = "F5", .enabled = true },
        },
    },
    .{
        .label = "Tools",
        .items = &.{
            .{ .label = "Terminal", .action = .none, .shortcut = "", .enabled = false },
        },
    },
    .{
        .label = "Help",
        .items = &.{
            .{ .label = "About dhjsjs", .action = .about, .shortcut = "", .enabled = true },
        },
    },
};

const MENU_LABELS = [_][]const u8{ "File", "Edit", "Sketch", "Tools", "Help" };
const MENU_LABEL_X = [_]i32{ 0, 6, 12, 20, 27 };

fn isKw(s: []const u8) bool {
    const words = [_][]const u8{ "fn", "hui", "if", "uebok", "return", "while", "activity", "compose", "state", "viewmodel", "true", "false", "null", "int", "string", "bool", "void" };
    for (words) |w| { if (utils.sliceEql(s, w)) return true; }
    return false;
}

const HL_KEYWORD: u8 = 0;
const HL_STRING: u8 = 1;
const HL_NUMBER: u8 = 2;
const HL_COMMENT: u8 = 3;
const HL_NORMAL: u8 = 4;
const HL_FUNC: u8 = 5;

pub fn fontScale(w: u32) u32 {
    const raw = @divFloor(@min(w, 2400), 800);
    if (raw < 1) return 1;
    if (raw > 2) return 2;
    return raw;
}

fn highlightLine(line: []const u8, buf: []u8) void {
    var i: usize = 0;
    while (i < line.len and i < buf.len) {
        if (line[i] == '"') {
            buf[i] = HL_STRING;
            i += 1;
            while (i < line.len and line[i] != '"') : (i += 1) buf[i] = HL_STRING;
            if (i < line.len) { buf[i] = HL_STRING; i += 1; }
        } else if (line[i] == '/' and i + 1 < line.len and line[i + 1] == '/') {
            while (i < line.len and i < buf.len) : (i += 1) buf[i] = HL_COMMENT;
        } else if (utils.isAlpha(line[i]) or line[i] == '_') {
            const start = i;
            while (i < line.len and utils.isAlphaNum(line[i])) : (i += 1) {}
            const t = isKw(line[start..i]);
            var k = start;
            while (k < i and k < buf.len) : (k += 1) buf[k] = if (t) HL_KEYWORD else HL_FUNC;
        } else if (utils.isDigit(line[i])) {
            buf[i] = HL_NUMBER;
            i += 1;
        } else {
            buf[i] = HL_NORMAL;
            i += 1;
        }
    }
}

fn fmtU32(val: u32, buf: []u8) []const u8 {
    var tmp: [16]u8 = undefined;
    var i: usize = 0;
    var n = val;
    if (n == 0) {
        buf[0] = '0';
        return buf[0..1];
    }
    while (n > 0) : (n /= 10) {
        tmp[i] = @as(u8, @intCast(n % 10)) + '0';
        i += 1;
    }
    var j: usize = 0;
    while (j < i) : (j += 1) {
        buf[j] = tmp[i - 1 - j];
    }
    return buf[0..i];
}

pub const IdeState = struct {
    filename: [MAX_FILENAME]u8,
    flen: usize,
    content: [MAX_CONTENT]u8,
    clen: usize,
    cx: usize,
    cy: usize,
    modified: bool,
    cursor_on: bool,
    frame_count: usize,
    needs_redraw: bool,
    status: [64]u8,
    status_len: usize,
    console: [MAX_CONSOLE]u8,
    con_len: usize,
    request_build: bool,
    open_menu: i32, // -1 = none, 0..4 = File, Edit, Sketch, Tools, Help
    files: [MAX_FILES]FileEntry,
    file_count: usize,
    cur_dir: [MAX_FILENAME]u8,
    cur_dir_len: usize,
    sidebar_w: u32, // computed in paint
    input_mode: bool,
    input_action: u8, // 'o'=open, 's'=save
    input_buf: [256]u8,
    input_len: usize,
    console_scroll: u32,
    console_scroll_max: u32,
    console_lines: u32,
    editor_scroll: usize,
    sidebar_scroll: usize,
    dragging: u8, // 0=none, 1=editor, 2=console, 3=sidebar
    drag_start_y: i32,
    drag_start_scroll: usize,
    sel_active: bool,
    sel_anchor_x: usize,
    sel_anchor_y: usize,
    sel_cursor_x: usize,
    sel_cursor_y: usize,
    clipboard: [4096]u8,
    clip_len: usize,
    building: bool,
    keymap: u8, // 0=en, 1=ru

    pub fn init() IdeState {
        var self = IdeState{
            .filename = undefined,
            .flen = 0,
            .content = undefined,
            .clen = 0,
            .cx = 0,
            .cy = 0,
            .modified = false,
            .cursor_on = true,
            .frame_count = 0,
            .status = undefined,
            .status_len = 0,
            .console = undefined,
            .con_len = 0,
            .request_build = false,
            .open_menu = -1,
            .files = undefined,
            .file_count = 0,
            .cur_dir = undefined,
            .cur_dir_len = 0,
            .sidebar_w = 0,
            .input_mode = false,
            .input_action = 0,
            .input_buf = undefined,
            .input_len = 0,
            .console_scroll = 0,
            .console_scroll_max = 0,
            .console_lines = 0,
            .editor_scroll = 0,
            .sidebar_scroll = 0,
            .dragging = 0,
            .drag_start_y = 0,
            .drag_start_scroll = 0,
            .sel_active = false,
            .sel_anchor_x = 0,
            .sel_anchor_y = 0,
            .sel_cursor_x = 0,
            .sel_cursor_y = 0,
            .clipboard = undefined,
            .clip_len = 0,
            .building = false,
            .keymap = 0,
            .needs_redraw = true,
        };
        self.cur_dir[0] = '.';
        self.cur_dir_len = 1;
        self.refreshFileList();
        return self;
    }

    pub fn setContent(self: *IdeState, src: []const u8) void {
        var i: usize = 0;
        while (i < src.len and i < MAX_CONTENT) : (i += 1) self.content[i] = src[i];
        self.clen = src.len;
        self.cx = 0;
        self.cy = 0;
        self.editor_scroll = 0;
        self.modified = false;
    }

    pub fn setStatus(self: *IdeState, msg: []const u8) void {
        var i: usize = 0;
        while (i < msg.len and i < 63) : (i += 1) self.status[i] = msg[i];
        self.status_len = msg.len;
    }

    pub fn addConsole(self: *IdeState, msg: []const u8) void {
        var i: usize = 0;
        while (i < msg.len and self.con_len < MAX_CONSOLE - 1) : (i += 1) {
            self.console[self.con_len] = msg[i];
            self.con_len += 1;
        }
    }

    fn editorVisibleLines(self: *IdeState, fb: *gfx.Framebuffer) usize {
        const L = self.layout(fb);
        const vis = L.ed_h / L.ch_h;
        return if (vis > 0) @as(usize, @intCast(vis)) else 1;
    }

    fn consoleVisibleLines(self: *IdeState, fb: *gfx.Framebuffer) usize {
        const L = self.layout(fb);
        const vis = L.con_h / L.ch_h;
        return if (vis > 0) @as(usize, @intCast(vis)) else 1;
    }

    fn sidebarVisibleItems(self: *IdeState, fb: *gfx.Framebuffer) usize {
        const L = self.layout(fb);
        const vis = L.ed_h / L.ch_h;
        return if (vis > 0) @as(usize, @intCast(vis)) else 1;
    }

    pub fn ensureCursorVisible(self: *IdeState, fb: *gfx.Framebuffer) void {
        if (self.cy < self.editor_scroll) {
            self.editor_scroll = self.cy;
        } else {
            const vis = self.editorVisibleLines(fb);
            if (self.cy >= self.editor_scroll + vis) {
                self.editor_scroll = self.cy - vis + 1;
            }
        }
    }

    pub fn scrollEditorBy(self: *IdeState, fb: *gfx.Framebuffer, delta: i32) void {
        const total = self.totalLines();
        const vis = self.editorVisibleLines(fb);
        const max_scroll = if (total > vis) total - vis else @as(usize, 0);
        if (delta < 0) {
            const d = @as(usize, @intCast(-delta));
            self.editor_scroll = if (self.editor_scroll > d) self.editor_scroll - d else 0;
        } else if (delta > 0) {
            const d = @as(usize, @intCast(delta));
            self.editor_scroll = if (self.editor_scroll + d < max_scroll) self.editor_scroll + d else max_scroll;
        }
    }

    pub fn scrollConsoleBy(self: *IdeState, fb: *gfx.Framebuffer, delta: i32) void {
        const total = self.conLines();
        const vis = self.consoleVisibleLines(fb);
        const max_scroll = if (total > vis) total - vis else @as(usize, 0);
        if (delta < 0) {
            const d = @as(usize, @intCast(-delta));
            const cur = @as(usize, self.console_scroll);
            self.console_scroll = @as(u32, @intCast(if (cur > d) cur - d else 0));
        } else if (delta > 0) {
            const d = @as(usize, @intCast(delta));
            const cur = @as(usize, self.console_scroll);
            self.console_scroll = if (cur + d < max_scroll) @as(u32, @intCast(cur + d)) else @as(u32, @intCast(max_scroll));
        }
    }

    pub fn scrollSidebarBy(self: *IdeState, fb: *gfx.Framebuffer, delta: i32) void {
        const total = self.file_count;
        const vis = self.sidebarVisibleItems(fb);
        const max_scroll = if (total > vis) total - vis else @as(usize, 0);
        if (delta < 0) {
            const d = @as(usize, @intCast(-delta));
            self.sidebar_scroll = if (self.sidebar_scroll > d) self.sidebar_scroll - d else 0;
        } else if (delta > 0) {
            const d = @as(usize, @intCast(delta));
            self.sidebar_scroll = if (self.sidebar_scroll + d < max_scroll) self.sidebar_scroll + d else max_scroll;
        }
    }

    pub fn handleMouseWheel(self: *IdeState, fb: *gfx.Framebuffer, mx: i32, my: i32, delta: i32) void {
        const L = self.layout(fb);
        if (my < @as(i32, @intCast(L.top_y))) return;
        if (self.sidebar_w > 0 and mx >= 0 and @as(u32, @intCast(mx)) < self.sidebar_w) {
            self.scrollSidebarBy(fb, delta);
            return;
        }
        const con_top = @as(i32, @intCast(L.top_y + L.ed_h));
        if (my >= con_top) {
            self.scrollConsoleBy(fb, delta);
        } else {
            self.scrollEditorBy(fb, delta);
        }
    }

    fn editorThumbRect(self: *IdeState, fb: *gfx.Framebuffer, out: *gfx.Rect) bool {
        const L = self.layout(fb);
        const total = self.totalLines();
        const vis = self.editorVisibleLines(fb);
        if (total <= vis) return false;
        const thumb_h = @as(u32, @intCast(@max(@as(usize, 6), L.ed_h * vis / total)));
        const thumb_y = L.top_y + L.ed_h * @as(u32, @intCast(self.editor_scroll)) / total;
        out.* = gfx.Rect{ .x = @as(i32, @intCast(fb.width - TRACK_W)), .y = @as(i32, @intCast(thumb_y)), .w = TRACK_W, .h = thumb_h };
        return true;
    }

    fn sidebarThumbRect(self: *IdeState, fb: *gfx.Framebuffer, out: *gfx.Rect) bool {
        const L = self.layout(fb);
        const total = self.file_count;
        const vis = self.sidebarVisibleItems(fb);
        if (total <= vis) return false;
        const thumb_h = @as(u32, @intCast(@max(@as(usize, 6), L.ed_h * vis / total)));
        const thumb_y = L.top_y + L.ed_h * @as(u32, @intCast(self.sidebar_scroll)) / total;
        out.* = gfx.Rect{ .x = @as(i32, @intCast(self.sidebar_w - TRACK_W)), .y = @as(i32, @intCast(thumb_y)), .w = TRACK_W, .h = thumb_h };
        return true;
    }

    fn consoleThumbRect(self: *IdeState, fb: *gfx.Framebuffer, out: *gfx.Rect) bool {
        const L = self.layout(fb);
        const total = self.conLines();
        const vis = self.consoleVisibleLines(fb);
        if (total <= vis) return false;
        const thumb_h = @as(u32, @intCast(@max(@as(usize, 6), L.con_h * vis / total)));
        const thumb_y = L.top_y + L.ed_h + L.con_h * self.console_scroll / total;
        out.* = gfx.Rect{ .x = @as(i32, @intCast(fb.width - TRACK_W)), .y = @as(i32, @intCast(thumb_y)), .w = TRACK_W, .h = thumb_h };
        return true;
    }

    pub fn scrollbarHit(self: *IdeState, fb: *gfx.Framebuffer, mx: i32, my: i32) u8 {
        var r: gfx.Rect = undefined;
        if (self.editorThumbRect(fb, &r)) {
            if (mx >= r.x and mx < r.x + @as(i32, @intCast(r.w)) and my >= r.y and my < r.y + @as(i32, @intCast(r.h))) return 1;
        }
        if (self.sidebarThumbRect(fb, &r)) {
            if (mx >= r.x and mx < r.x + @as(i32, @intCast(r.w)) and my >= r.y and my < r.y + @as(i32, @intCast(r.h))) return 3;
        }
        if (self.consoleThumbRect(fb, &r)) {
            if (mx >= r.x and mx < r.x + @as(i32, @intCast(r.w)) and my >= r.y and my < r.y + @as(i32, @intCast(r.h))) return 2;
        }
        return 0;
    }

    pub fn startDrag(self: *IdeState, fb: *gfx.Framebuffer, mx: i32, my: i32) bool {
        const hit = self.scrollbarHit(fb, mx, my);
        if (hit == 0) return false;
        self.dragging = hit;
        self.drag_start_y = my;
        self.drag_start_scroll = switch (hit) {
            1 => self.editor_scroll,
            2 => @as(usize, self.console_scroll),
            3 => self.sidebar_scroll,
            else => 0,
        };
        return true;
    }

    pub fn updateDrag(self: *IdeState, fb: *gfx.Framebuffer, my: i32) void {
        if (self.dragging == 0) return;
        const L = self.layout(fb);
        const delta_y = my - self.drag_start_y;
        if (self.dragging == 1) {
            const total = self.totalLines();
            const vis = self.editorVisibleLines(fb);
            if (total <= vis) return;
            const max_scroll = total - vis;
            const delta_lines = @divTrunc(@as(i32, @intCast(total)) * delta_y, @as(i32, @intCast(L.ed_h)));
            var new_scroll = @as(i32, @intCast(self.drag_start_scroll)) + delta_lines;
            if (new_scroll < 0) new_scroll = 0;
            if (new_scroll > @as(i32, @intCast(max_scroll))) new_scroll = @as(i32, @intCast(max_scroll));
            self.editor_scroll = @as(usize, @intCast(new_scroll));
        } else if (self.dragging == 2) {
            const total = self.conLines();
            const vis = self.consoleVisibleLines(fb);
            if (total <= vis) return;
            const max_scroll = total - vis;
            const delta_lines = @divTrunc(@as(i32, @intCast(total)) * delta_y, @as(i32, @intCast(L.con_h)));
            var new_scroll = @as(i32, @intCast(self.drag_start_scroll)) + delta_lines;
            if (new_scroll < 0) new_scroll = 0;
            if (new_scroll > @as(i32, @intCast(max_scroll))) new_scroll = @as(i32, @intCast(max_scroll));
            self.console_scroll = @as(u32, @intCast(new_scroll));
        } else if (self.dragging == 3) {
            const total = self.file_count;
            const vis = self.sidebarVisibleItems(fb);
            if (total <= vis) return;
            const max_scroll = total - vis;
            const delta_lines = @divTrunc(@as(i32, @intCast(total)) * delta_y, @as(i32, @intCast(L.ed_h)));
            var new_scroll = @as(i32, @intCast(self.drag_start_scroll)) + delta_lines;
            if (new_scroll < 0) new_scroll = 0;
            if (new_scroll > @as(i32, @intCast(max_scroll))) new_scroll = @as(i32, @intCast(max_scroll));
            self.sidebar_scroll = @as(usize, @intCast(new_scroll));
        }
    }

    pub fn endDrag(self: *IdeState) void {
        self.dragging = 0;
    }

    fn selectionStartEnd(self: *IdeState, out_start_y: *usize, out_start_x: *usize, out_end_y: *usize, out_end_x: *usize) void {
        const ay = self.sel_anchor_y;
        const ax = self.sel_anchor_x;
        const cy = self.sel_cursor_y;
        const cx = self.sel_cursor_x;
        if (ay < cy) {
            out_start_y.* = ay; out_start_x.* = ax; out_end_y.* = cy; out_end_x.* = cx;
        } else if (ay > cy) {
            out_start_y.* = cy; out_start_x.* = cx; out_end_y.* = ay; out_end_x.* = ax;
        } else {
            out_start_y.* = ay; out_end_y.* = ay;
            if (ax < cx) { out_start_x.* = ax; out_end_x.* = cx; }
            else { out_start_x.* = cx; out_end_x.* = ax; }
        }
    }

    fn selectionAbsRange(self: *IdeState, start: *usize, end: *usize) bool {
        if (!self.sel_active) return false;
        var sy: usize = 0; var sx: usize = 0; var ey: usize = 0; var ex: usize = 0;
        self.selectionStartEnd(&sy, &sx, &ey, &ex);
        const s_start = self.getLineStart(sy);
        const e_start = self.getLineStart(ey);
        start.* = s_start + byteOffsetForCodepoint(self.content[s_start..self.getLineEnd(sy)], sx);
        end.* = e_start + byteOffsetForCodepoint(self.content[e_start..self.getLineEnd(ey)], ex);
        return end.* > start.*;
    }

    pub fn clearSelection(self: *IdeState) void {
        self.sel_active = false;
    }

    pub fn clearAll(self: *IdeState) void {
        self.clen = 0;
        self.cx = 0;
        self.cy = 0;
        self.flen = 0;
        self.modified = false;
        self.con_len = 0;
        self.editor_scroll = 0;
        self.console_scroll = 0;
        self.clearSelection();
        self.setStatus("cleared");
    }

    pub fn selectAll(self: *IdeState) void {
        self.sel_active = true;
        self.sel_anchor_x = 0;
        self.sel_anchor_y = 0;
        const total = self.totalLines();
        const last = if (total > 0) total - 1 else 0;
        self.sel_cursor_y = last;
        self.sel_cursor_x = self.getLineLen(last);
        self.setStatus("select all");
    }

    fn deleteRange(self: *IdeState, start: usize, end: usize) void {
        if (end <= start or start > self.clen) return;
        const real_end = @min(end, self.clen);
        const len = real_end - start;
        var i = start;
        while (i + len < self.clen) : (i += 1) self.content[i] = self.content[i + len];
        self.clen -= len;
        self.cy = self.lineFromPos(start);
        const line_start = self.getLineStart(self.cy);
        self.cx = codepointCount(self.content[line_start..start]);
        self.clearSelection();
        self.modified = true;
    }

    fn lineFromPos(self: *IdeState, pos: usize) usize {
        var ln: usize = 0;
        var i: usize = 0;
        while (i < pos and i < self.clen) : (i += 1) {
            if (self.content[i] == '\n') ln += 1;
        }
        return ln;
    }

    pub fn copySelection(self: *IdeState) void {
        var start: usize = 0; var end: usize = 0;
        if (!self.selectionAbsRange(&start, &end)) return;
        const len = end - start;
        var i: usize = 0;
        while (i < len and i < self.clipboard.len - 1) : (i += 1) self.clipboard[i] = self.content[start + i];
        self.clip_len = @min(len, self.clipboard.len - 1);
        self.setStatus("copied");
    }

    pub fn pasteClipboard(self: *IdeState) void {
        if (self.clip_len == 0) { self.setStatus("clipboard empty"); return; }
        var start: usize = 0; var end: usize = 0;
        if (self.selectionAbsRange(&start, &end)) self.deleteRange(start, end);
        var i: usize = 0;
        while (i < self.clip_len and self.clen < MAX_CONTENT - 1) : (i += 1) {
            self.insertChar(self.clipboard[i]);
        }
        self.setStatus("pasted");
    }

    pub fn startSelectionAtCursor(self: *IdeState) void {
        self.sel_active = true;
        self.sel_anchor_x = self.cx;
        self.sel_anchor_y = self.cy;
        self.sel_cursor_x = self.cx;
        self.sel_cursor_y = self.cy;
    }

    pub fn updateSelectionTo(self: *IdeState, cy: usize, cx: usize) void {
        if (!self.sel_active) {
            self.sel_active = true;
            self.sel_anchor_x = self.cx;
            self.sel_anchor_y = self.cy;
        }
        self.sel_cursor_x = cx;
        self.sel_cursor_y = cy;
    }

    pub fn openFile(self: *IdeState, filepath: []const u8) void {
        const sys = @import("sys.zig");
        var path: [MAX_FILENAME]u8 = undefined;
        var pi: usize = 0;
        while (pi < filepath.len and pi < MAX_FILENAME - 1) : (pi += 1) path[pi] = filepath[pi];
        path[pi] = 0;
        const fd = sys.open(&path, 0, 0);
        if (fd < 0) { self.setStatus("open failed"); return; }
        var total: usize = 0;
        while (total < MAX_CONTENT) {
            const n = sys.read(fd, self.content[total..].ptr, MAX_CONTENT - total);
            if (n <= 0) break;
            total += @as(usize, @intCast(n));
        }
        sys.close(fd);
        self.clen = total;
        self.cx = 0;
        self.cy = 0;
        self.editor_scroll = 0;
        self.modified = false;
        var fi: usize = 0;
        while (fi < filepath.len and fi < MAX_FILENAME - 1) : (fi += 1) self.filename[fi] = filepath[fi];
        self.flen = filepath.len;
        self.setStatus("opened");
    }

    pub fn saveFile(self: *IdeState) void {
        if (self.flen == 0) {
            self.startInput("save");
            return;
        }
        const sys = @import("sys.zig");
        var path: [MAX_FILENAME]u8 = undefined;
        var pi: usize = 0;
        while (pi < self.flen and pi < MAX_FILENAME - 1) : (pi += 1) path[pi] = self.filename[pi];
        path[pi] = 0;
        const fd = sys.open(&path, sys.O_RDWR | 0x40 | 0x200, 0x1A4);
        if (fd < 0) { self.setStatus("save failed"); return; }
        _ = sys.write(fd, @as([*]const u8, &self.content), self.clen);
        sys.close(fd);
        self.modified = false;
        self.setStatus("saved");
    }

    pub fn refreshFileList(self: *IdeState) void {
        const sys = @import("sys.zig");
        var path: [MAX_FILENAME]u8 = undefined;
        var pi: usize = 0;
        if (self.cur_dir_len > 0) {
            for (self.cur_dir[0..self.cur_dir_len]) |c| { path[pi] = c; pi += 1; }
        }
        path[pi] = 0;
        const fd = sys.open(&path, 0, 0);
        if (fd < 0) {
            const dot = [2]u8{ '.', 0 };
            const fd2 = sys.open(&dot, 0, 0);
            if (fd2 < 0) {
                self.file_count = 0;
                self.addConsole("explorer: cannot open current directory\n");
                return;
            }
            self.cur_dir_len = 0;
            self.scanDir(fd2);
            sys.close(fd2);
            return;
        }
        self.scanDir(fd);
        sys.close(fd);
        var msg: [64]u8 = undefined;
        var mi: usize = 0;
        const prefix = "explorer: ";
        for (prefix) |c| { msg[mi] = c; mi += 1; }
        var nb: [16]u8 = undefined;
        const ns = fmtU32(@as(u32, @intCast(self.file_count)), nb[0..]);
        for (ns) |c| { msg[mi] = c; mi += 1; }
        const suffix = " files\n";
        for (suffix) |c| { msg[mi] = c; mi += 1; }
        self.addConsole(msg[0..mi]);
    }

    fn scanDir(self: *IdeState, fd: i32) void {
        const sys = @import("sys.zig");
        var buf: [4096]u8 = undefined;
        const n = sys.readDir(fd, &buf);
        if (n <= 0) {
            self.file_count = 0;
            if (n < 0) self.addConsole("explorer: readDir failed\n");
            return;
        }
        var off: usize = 0;
        var idx: usize = 0;
        while (off < n and idx < MAX_FILES) {
            const d_reclen = @as(u16, @intCast(buf[off+16])) | (@as(u16, @intCast(buf[off+17])) << 8);
            const d_type = buf[off + 18];
            var di: usize = off + 19;
            var ni: usize = 0;
            while (di < off + d_reclen and buf[di] != 0 and ni < MAX_FILENAME - 1) : (di += 1) {
                self.files[idx].name[ni] = buf[di];
                ni += 1;
            }
            self.files[idx].name[ni] = 0;
            self.files[idx].len = ni;
            var is_dir = d_type == 4;
            if (!is_dir and d_type == 0 and ni > 0) {
                var full_path: [MAX_FILENAME]u8 = undefined;
                var pi: usize = 0;
                if (self.cur_dir_len > 0) {
                    for (self.cur_dir[0..self.cur_dir_len]) |c| { full_path[pi] = c; pi += 1; }
                }
                var k: usize = 0;
                while (k < ni) : (k += 1) { full_path[pi] = self.files[idx].name[k]; pi += 1; }
                full_path[pi] = 0;
                const sfd = sys.open(&full_path, 0, 0);
                if (sfd >= 0) {
                    var st: sys.Stat = undefined;
                    if (sys.fstat(sfd, &st) == 0) {
                        is_dir = (st.mode & 0o040000) != 0;
                    }
                    sys.close(sfd);
                }
            }
            self.files[idx].is_dir = is_dir;
            if (ni > 0 and !(ni == 1 and self.files[idx].name[0] == '.')) {
                idx += 1;
            }
            off += d_reclen;
        }
        self.file_count = idx;
        if (self.cur_dir_len > 0 and self.file_count < MAX_FILES) {
            var k: usize = self.file_count;
            while (k > 0) : (k -= 1) {
                self.files[k] = self.files[k - 1];
            }
            self.files[0].name[0] = '.';
            self.files[0].name[1] = '.';
            self.files[0].name[2] = 0;
            self.files[0].len = 2;
            self.files[0].is_dir = true;
            self.file_count += 1;
        }
        var i: usize = 0;
        while (i < self.file_count) {
            var j: usize = i + 1;
            while (j < self.file_count) : (j += 1) {
                var swap = false;
                if (self.files[j].is_dir and !self.files[i].is_dir) {
                    swap = true;
                } else if (self.files[j].is_dir == self.files[i].is_dir) {
                    var k: usize = 0;
                    while (k < self.files[i].len and k < self.files[j].len) : (k += 1) {
                        if (self.files[j].name[k] < self.files[i].name[k]) { swap = true; break; }
                        if (self.files[j].name[k] > self.files[i].name[k]) { break; }
                    }
                    if (!swap and self.files[j].len < self.files[i].len) swap = true;
                }
                if (swap) {
                    const tmp = self.files[i];
                    self.files[i] = self.files[j];
                    self.files[j] = tmp;
                }
            }
            i += 1;
        }
    }

    // ── layout ─────────────────────────────────────────────
    fn Layout(T: type) type {
        return struct {
            sc: T,
            ch_w: T,
            ch_h: T,
            menu_h: T,
            tool_h: T,
            tab_h: T,
            gutter_w: T,
            margin_x: T,
            top_y: T,
            con_h: T,
            status_h: T,
            ed_h: T,
            sidebar_w: T,
        };
    }

    fn layout(self: *IdeState, fb: *const gfx.Framebuffer) Layout(u32) {
        const sc = fontScale(fb.width);
        const ch_w = sc * gfx.FONT_W;
        const ch_h = sc * gfx.FONT_H + 4;
        const menu_h = ch_h;
        const tool_h = ch_h;
        const tab_h = ch_h;
        const gutter_w = ch_w * 5 + 14;
        const top_y = menu_h + tool_h + tab_h;
        const status_h = ch_h;
        const avail = if (fb.height > top_y + status_h) fb.height - top_y - status_h else 0;
        const con_h = avail / 4;
        const ed_h = if (avail > con_h) avail - con_h else 0;
        const sidebar_w_val = self.sidebar_w;
        const margin_x = sidebar_w_val + gutter_w;
        return .{ .sc = sc, .ch_w = ch_w, .ch_h = ch_h, .menu_h = menu_h, .tool_h = tool_h, .tab_h = tab_h, .gutter_w = gutter_w, .margin_x = margin_x, .top_y = top_y, .con_h = con_h, .status_h = status_h, .ed_h = ed_h, .sidebar_w = sidebar_w_val };
    }

    // ── paint ───────────────────────────────────────────────
    pub fn paint(self: *IdeState, fb: *gfx.Framebuffer, mx: i32, my: i32, mdown: bool) void {
        const sc = fontScale(fb.width);
        const ch_w = sc * gfx.FONT_W;
        self.sidebar_w = @min(ch_w * 20, fb.width / 4);
        const L = self.layout(fb);

        fb.fill(EDITOR_BG);
        self.drawSidebar(fb, L, mx, my, mdown);
        if (self.sidebar_w > 0) {
            fb.fillRect(gfx.Rect{ .x = @as(i32, @intCast(self.sidebar_w - 1)), .y = 0, .w = 1, .h = fb.height }, GUTTER_LINE);
        }
        self.drawMenu(fb, L, mx, my, mdown);
        self.drawToolbar(fb, L, mx, my, mdown);
        self.drawTabBar(fb, L);
        self.drawGutter(fb, L);
        self.drawLines(fb, L);
        self.drawCursor(fb, L);
        if (self.input_mode) self.drawInputPrompt(fb, L);
        self.drawConsole(fb, L);
        self.drawStatus(fb, L);
        self.drawScrollbarOverlays(fb, L, mx, my);
    }

    fn drawSidebar(self: *IdeState, fb: *gfx.Framebuffer, L: Layout(u32), mx: i32, my: i32, mdown: bool) void {
        if (self.sidebar_w == 0) return;
        const sw = L.sidebar_w;
        fb.fillRect(gfx.Rect{ .x = 0, .y = @as(i32, @intCast(L.top_y)), .w = sw, .h = L.ed_h }, GUTTER_BG);
        fb.fillRect(gfx.Rect{ .x = @as(i32, @intCast(sw - 1)), .y = @as(i32, @intCast(L.top_y)), .w = 1, .h = L.ed_h }, GUTTER_LINE);
        fb.drawText("EXPLORER", 4, @as(i32, @intCast(L.top_y)), TAB_ACCENT, L.ch_w);

        var i: usize = self.sidebar_scroll;
        while (i < self.file_count) : (i += 1) {
            const iy = @as(i32, @intCast(L.top_y + (i - self.sidebar_scroll + 1) * L.ch_h));
            if (iy + @as(i32, @intCast(L.ch_h)) > @as(i32, @intCast(L.top_y + L.ed_h))) break;
            const name = self.files[i].name[0..self.files[i].len];
            const maxc = @as(usize, @intCast(@max(sw, L.ch_w) / L.ch_w - 2));
            const disp = if (name.len > maxc) name[0..maxc] else name;
            const hover = mx >= 0 and mx < @as(i32, @intCast(sw)) and my >= iy and my < iy + @as(i32, @intCast(L.ch_h));
            if (hover) {
                fb.fillRect(gfx.Rect{ .x = 0, .y = iy, .w = sw, .h = L.ch_h }, if (mdown) TOOL_BUTTON_ACCENT else TOOL_BUTTON_HI);
            }
            const color = if (self.files[i].is_dir) TAB_ACCENT else TEXT_COL;
            fb.drawText(disp, 4, iy, color, L.ch_w);
        }
    }

    fn drawMenu(self: *IdeState, fb: *gfx.Framebuffer, L: Layout(u32), mx: i32, my: i32, _: bool) void {
        const menu_y: i32 = 0;
        fb.fillRect(gfx.Rect{ .x = 0, .y = menu_y, .w = fb.width, .h = L.menu_h }, MENU_BG);
        fb.fillRect(gfx.Rect{ .x = 0, .y = menu_y + @as(i32, @intCast(L.menu_h - 1)), .w = fb.width, .h = 1 }, GUTTER_LINE);

        const ty = menu_y + @as(i32, @intCast((L.menu_h - L.ch_h) / 2));

        for (&MENU_LABELS, 0..) |label, i| {
            const xi = 8 + MENU_LABEL_X[i] * @as(i32, @intCast(L.ch_w));
            const wi = @as(i32, @intCast(label.len * L.ch_w + L.ch_w));
            const hover = mx >= xi and mx < xi + wi and my >= menu_y and my < menu_y + @as(i32, @intCast(L.menu_h));
            const is_open = self.open_menu == @as(i32, @intCast(i));

            if (is_open or hover) {
                fb.fillRect(gfx.Rect{ .x = xi, .y = menu_y, .w = @as(u32, @intCast(wi)), .h = L.menu_h }, MENU_BG_2);
            }
            fb.drawText(label, xi + @as(i32, @intCast(L.ch_w / 2)), ty, if (is_open) TAB_ACCENT else MENU_TEXT, L.ch_w);

            // draw dropdown
            if (is_open) {
                const menu_def = &MENUS[i];
                const drop_x = @as(i32, @intCast(0)); // full width
                const drop_y = menu_y + @as(i32, @intCast(L.menu_h));
                const drop_w = fb.width;
                var item_y = drop_y;
                for (menu_def.items) |item| {
                    item_y += @as(i32, @intCast(if (item.label.len == 0) L.ch_h / 2 else L.ch_h));
                }
                const drop_h = @as(u32, @intCast(item_y - drop_y));
                // draw bg
                fb.fillRect(gfx.Rect{ .x = drop_x, .y = drop_y, .w = drop_w, .h = drop_h }, MENU_BG);
                fb.fillRect(gfx.Rect{ .x = drop_x, .y = drop_y, .w = 1, .h = drop_h }, GUTTER_LINE);
                // draw items
                item_y = drop_y;
                for (menu_def.items) |item| {
                    if (item.label.len == 0) {
                        fb.fillRect(gfx.Rect{ .x = drop_x + 4, .y = item_y, .w = drop_w - 8, .h = 1 }, GUTTER_LINE);
                        item_y += @as(i32, @intCast(L.ch_h / 2));
                        continue;
                    }
                    const ih = @as(i32, @intCast(L.ch_h));
                    const i_hover = mx >= drop_x and mx < drop_x + @as(i32, @intCast(drop_w)) and
                        my >= item_y and my < item_y + ih;
                    if (i_hover) {
                        fb.fillRect(gfx.Rect{ .x = @as(u32, @intCast(drop_x)), .y = item_y, .w = drop_w, .h = @as(u32, @intCast(ih)) }, TOOL_BUTTON_ACCENT);
                    }
                    fb.drawText(item.label, drop_x + @as(i32, @intCast(L.ch_w)), item_y, if (item.enabled) MENU_TEXT else MENU_DIM, L.ch_w);
                    if (item.shortcut.len > 0) {
                        const sx = drop_x + @as(i32, @intCast(drop_w)) - @as(i32, @intCast(item.shortcut.len * L.ch_w + L.ch_w));
                        fb.drawText(item.shortcut, sx, item_y, MENU_DIM, L.ch_w);
                    }
                    item_y += ih;
                }
            }
        }
    }

    fn drawToolbar(self: *IdeState, fb: *gfx.Framebuffer, L: Layout(u32), mx: i32, my: i32, mdown: bool) void {
        const y0 = @as(i32, @intCast(L.menu_h));
        fb.fillRect(gfx.Rect{ .x = 0, .y = y0, .w = fb.width, .h = L.tool_h }, TOOL_BG);
        fb.fillRect(gfx.Rect{ .x = 0, .y = y0 + @as(i32, @intCast(L.tool_h - 1)), .w = fb.width, .h = 1 }, GUTTER_LINE);

        const buttons = [_][]const u8{ "Verify", "Upload", "New", "Open", "Save", "Build", "Clear" };
        var bx: i32 = 8;
        for (&buttons, 0..) |btn, bi| {
            const bw = @as(i32, @intCast(btn.len * L.ch_w + L.ch_w));
            const hover = mx >= bx and mx < bx + bw and my >= y0 and my < y0 + @as(i32, @intCast(L.tool_h));
            const is_building = self.building and bi == 5;
            if (hover or is_building) {
                const bg = if (is_building) TOOL_BUTTON_ACCENT else if (mdown) TOOL_BUTTON_ACCENT else TOOL_BUTTON_HI;
                fb.fillRect(gfx.Rect{ .x = @as(i32, @intCast(bx)), .y = y0, .w = @as(u32, @intCast(bw)), .h = L.tool_h }, bg);
            }
            fb.drawText(btn, bx + @as(i32, @intCast(L.ch_w / 2)), y0 + @as(i32, @intCast((L.tool_h - L.ch_h) / 2)), TOOL_TEXT, L.ch_w);
            bx += bw + @as(i32, @intCast(L.ch_w));
        }
    }

    fn drawTabBar(self: *IdeState, fb: *gfx.Framebuffer, L: Layout(u32)) void {
        const y0 = @as(i32, @intCast(L.menu_h + L.tool_h));
        const tx = @as(i32, @intCast(L.sidebar_w));
        const tw = fb.width - L.sidebar_w;
        fb.fillRect(gfx.Rect{ .x = tx, .y = y0, .w = tw, .h = L.tab_h }, TAB_BG);
        fb.fillRect(gfx.Rect{ .x = tx, .y = y0 + @as(i32, @intCast(L.tab_h - 1)), .w = tw, .h = 1 }, GUTTER_LINE);

        const title = if (self.flen > 0) self.filename[0..self.flen] else "untitled.dhjsjs";
        const tab_w = @as(u32, @intCast(@min(@as(usize, L.ch_w * 20), @as(usize, L.ch_w * 2 + @as(u32, @intCast(title.len)) * L.ch_w))));

        fb.fillRect(gfx.Rect{ .x = tx, .y = y0, .w = tab_w, .h = L.tab_h }, TAB_ACTIVE);
        fb.fillRect(gfx.Rect{ .x = tx, .y = y0 + @as(i32, @intCast(L.tab_h - 2)), .w = tab_w, .h = 2 }, TAB_ACCENT);
        const ty2 = y0 + @as(i32, @intCast((L.tab_h - L.ch_h) / 2));
        var xp: i32 = tx + 8;
        if (self.modified) {
            fb.drawText("\xE2\x97\x8B", xp, ty2, MODIFIED_COL, L.ch_w);
            xp += @as(i32, @intCast(L.ch_w));
        }
        const max_chars = (tab_w - @as(u32, @intCast(xp - tx))) / L.ch_w;
        const display = if (title.len > max_chars) title[0..max_chars] else title;
        fb.drawText(display, xp, ty2, TEXT_COL, L.ch_w);
    }

    fn glyphForCodepoint(cp: u32) [gfx.FONT_H]u16 {
        return gfx.getGlyph(cp);
    }

    fn colorForHL(h: u8) gfx.Color {
        return switch (h) {
            HL_KEYWORD => gfx.rgb(86, 156, 214),
            HL_STRING => gfx.rgb(206, 145, 120),
            HL_NUMBER => gfx.rgb(181, 206, 168),
            HL_COMMENT => gfx.rgb(106, 153, 85),
            HL_FUNC => gfx.rgb(220, 220, 170),
            else => TEXT_COL,
        };
    }

    fn drawGutter(self: *IdeState, fb: *gfx.Framebuffer, L: Layout(u32)) void {
        _ = self;
        const con_top = @as(i32, @intCast(L.top_y + L.ed_h));
        const gx = @as(i32, @intCast(L.sidebar_w));
        fb.fillRect(gfx.Rect{ .x = gx, .y = @as(i32, @intCast(L.top_y)), .w = L.gutter_w, .h = L.ed_h }, GUTTER_BG);
        fb.fillRect(gfx.Rect{ .x = @as(i32, @intCast(L.sidebar_w + L.gutter_w - 1)), .y = @as(i32, @intCast(L.top_y)), .w = 1, .h = @as(u32, @intCast(con_top - @as(i32, @intCast(L.top_y)))) }, GUTTER_LINE);
    }

    fn selectionLineRange(self: *IdeState, line_idx: usize, start_y: usize, start_x: usize, end_y: usize, end_x: usize, out_x1: *usize, out_x2: *usize) bool {
        if (line_idx < start_y or line_idx > end_y) return false;
        const line_len = self.getLineLen(line_idx);
        if (start_y == end_y) {
            if (line_idx != start_y) return false;
            const x1 = @min(start_x, line_len);
            const x2 = @min(end_x, line_len);
            if (x2 <= x1) return false;
            out_x1.* = x1; out_x2.* = x2;
            return true;
        }
        if (line_idx == start_y) {
            const x1 = @min(start_x, line_len);
            out_x1.* = x1; out_x2.* = line_len;
            return x1 < line_len;
        }
        if (line_idx == end_y) {
            const x2 = @min(end_x, line_len);
            out_x1.* = 0; out_x2.* = x2;
            return x2 > 0;
        }
        out_x1.* = 0; out_x2.* = line_len;
        return line_len > 0;
    }

    fn drawLines(self: *IdeState, fb: *gfx.Framebuffer, L: Layout(u32)) void {
        var y: u32 = L.top_y;
        var line_idx: usize = self.editor_scroll;
        var i: usize = self.getLineStart(line_idx);
        var line_start: usize = i;

        while (i <= self.clen and y + L.ch_h <= L.top_y + L.ed_h) : (i += 1) {
            if (i == self.clen or self.content[i] == '\n') {
                const line_num = line_idx + 1;
                const is_current = line_idx == self.cy;
                if (is_current) {
                    fb.fillRect(gfx.Rect{ .x = @as(i32, @intCast(L.margin_x)), .y = @as(i32, @intCast(y)), .w = fb.width - L.margin_x, .h = L.ch_h }, CUR_LINE_BG);
                }
                var nb: [16]u8 = undefined;
                const ns = fmtU32(@as(u32, @intCast(line_num)), nb[0..]);
                fb.drawText(ns, @as(i32, @intCast(L.margin_x - L.ch_w * 4 - 8)), @as(i32, @intCast(y)), if (is_current) NUML_CUR else NUML_COL, L.ch_w);
                if (self.sel_active) {
                    var sy: usize = 0; var sx: usize = 0; var ey: usize = 0; var ex: usize = 0;
                    self.selectionStartEnd(&sy, &sx, &ey, &ex);
                    var sx1: usize = 0; var sx2: usize = 0;
                    if (self.selectionLineRange(line_idx, sy, sx, ey, ex, &sx1, &sx2)) {
                        const sel_x = @as(i32, @intCast(L.margin_x)) + @as(i32, @intCast(sx1)) * @as(i32, @intCast(L.ch_w));
                        const sel_w = @as(u32, @intCast(sx2 - sx1)) * L.ch_w;
                        fb.fillRect(gfx.Rect{ .x = sel_x, .y = @as(i32, @intCast(y)), .w = sel_w, .h = L.ch_h }, SELECTION_BG);
                    }
                }
                const text = self.content[line_start..i];
                if (text.len > 0) {
                    const max_vis = @as(usize, @intCast((fb.width - L.margin_x) / L.ch_w));
                    const vis = if (codepointCount(text) > max_vis) text[0..byteOffsetForCodepoint(text, max_vis)] else text;
                    var hl: [512]u8 = undefined;
                    const hl_len = @min(vis.len, hl.len);
                    highlightLine(vis, hl[0..hl_len]);
                    var cx: i32 = @as(i32, @intCast(L.margin_x));
                    var ci: usize = 0;
                    var cpi: usize = 0;
                    while (ci < hl_len) {
                        var cp: u32 = 0; var cplen: u3 = 1;
                        _ = utf8Decode(vis, ci, &cp, &cplen);
                        const g = glyphForCodepoint(cp);
                        if (cp == '\t') {
                            cx += @as(i32, @intCast(L.ch_w)) * 3;
                        } else if (cp >= 32) {
                            fb.drawGlyphScaled(g, cx, @as(i32, @intCast(y)), gfx.colorToU32(colorForHL(hl[ci])), L.sc);
                            cx += @as(i32, @intCast(L.ch_w));
                        } else {
                            cx += @as(i32, @intCast(L.ch_w));
                        }
                        ci += cplen;
                        cpi += 1;
                    }
                }
                y += L.ch_h;
                line_idx += 1;
                line_start = i + 1;
            }
        }

        const total = @as(u32, @intCast(self.totalLines()));
        if (total > 0 and L.ed_h > L.ch_h) {
            const vis_lines = L.ed_h / L.ch_h;
            const track_w: u32 = 5;
            fb.fillRect(gfx.Rect{ .x = @as(i32, @intCast(fb.width - track_w - 1)), .y = @as(i32, @intCast(L.top_y)), .w = track_w + 1, .h = L.ed_h }, SCROLL_TRACK);
            const thumb_h = @max(@as(u32, 6), L.ed_h * vis_lines / total);
            const thumb_y = L.top_y + L.ed_h * @as(u32, @intCast(self.editor_scroll)) / total;
            fb.fillRect(gfx.Rect{ .x = @as(i32, @intCast(fb.width - track_w)), .y = @as(i32, @intCast(thumb_y)), .w = track_w, .h = @min(thumb_h, L.ed_h) }, SCROLL_THUMB);
        }
    }

    fn drawCursor(self: *IdeState, fb: *gfx.Framebuffer, L: Layout(u32)) void {
        if (!self.cursor_on or self.input_mode) return;
        if (self.cy < self.editor_scroll) return;
        const line_on_screen = self.cy - self.editor_scroll;
        const vis = self.editorVisibleLines(fb);
        if (line_on_screen >= vis) return;
        const x = @as(i32, @intCast(L.margin_x)) + @as(i32, @intCast(self.cx)) * @as(i32, @intCast(L.ch_w));
        const y = @as(i32, @intCast(L.top_y)) + @as(i32, @intCast(line_on_screen)) * @as(i32, @intCast(L.ch_h));
        if (y + @as(i32, @intCast(L.ch_h)) <= @as(i32, @intCast(L.top_y + L.ed_h))) {
            fb.fillRect(gfx.Rect{ .x = x, .y = y, .w = @as(u32, @intCast(@max(@as(i32, @intCast(L.sc)), 2))), .h = L.ch_h }, TEXT_COL);
        }
    }

    fn drawInputPrompt(self: *IdeState, fb: *gfx.Framebuffer, L: Layout(u32)) void {
        const y = @as(i32, @intCast(L.top_y + L.ed_h - L.ch_h));
        fb.fillRect(gfx.Rect{ .x = @as(i32, @intCast(L.margin_x)), .y = y, .w = fb.width - L.margin_x, .h = L.ch_h }, gfx.rgb(20, 40, 45));
        const prompt = if (self.input_action == 's') "Save: " else "Open: ";
        const plen: i32 = if (self.input_action == 's') 6 else 6;
        fb.drawText(prompt, @as(i32, @intCast(L.margin_x + 4)), y, TAB_ACCENT, L.ch_w);
        const path = self.input_buf[0..self.input_len];
        const maxc = @as(usize, @intCast((fb.width - L.margin_x - 4) / L.ch_w - @as(u32, @intCast(plen))));
        const display = if (path.len > maxc) path[path.len - maxc ..] else path;
        fb.drawText(display, @as(i32, @intCast(L.margin_x + 4)) + @as(i32, @intCast(L.ch_w * @as(u32, @intCast(plen)))), y, TEXT_COL, L.ch_w);
        if (self.cursor_on) {
            fb.fillRect(gfx.Rect{ .x = @as(i32, @intCast(L.margin_x + 4)) + @as(i32, @intCast(L.ch_w * @as(u32, @intCast(plen)))) + @as(i32, @intCast(display.len * L.ch_w)), .y = y, .w = 2, .h = L.ch_h }, TEXT_COL);
        }
    }

    fn drawConsole(self: *IdeState, fb: *gfx.Framebuffer, L: Layout(u32)) void {
        const con_top = L.top_y + L.ed_h;
        const cx = @as(i32, @intCast(L.sidebar_w));
        const cw = fb.width - L.sidebar_w;
        fb.fillRect(gfx.Rect{ .x = cx, .y = @as(i32, @intCast(con_top)), .w = cw, .h = L.con_h }, CONSOLE_BG);
        fb.fillRect(gfx.Rect{ .x = cx, .y = @as(i32, @intCast(con_top - 1)), .w = cw, .h = 1 }, GUTTER_LINE);

        const max_lines = if (L.ch_h > 0) L.con_h / L.ch_h else 1;
        const total = self.conLines();
        const max_scroll = if (total > max_lines) total - max_lines else @as(usize, 0);
        if (self.console_scroll > max_scroll) self.console_scroll = @as(u32, @intCast(max_scroll));
        const skip = self.console_scroll;

        var line_idx: usize = 0;
        var pos = self.findConLineStart(skip);
        while (pos < self.con_len and line_idx < max_lines) {
            var end = pos;
            while (end < self.con_len and self.console[end] != '\n') : (end += 1) {}
            if (end > pos) {
                const maxc = @as(usize, @intCast((cw - 4) / L.ch_w));
                const seg = self.console[pos..end];
                fb.drawText(if (seg.len > maxc) seg[0..maxc] else seg, cx + 4, @as(i32, @intCast(con_top + 2 + line_idx * L.ch_h)), CONSOLE_TEXT, L.ch_w);
            }
            line_idx += 1;
            pos = end + 1;
        }
    }

    fn drawStatus(self: *IdeState, fb: *gfx.Framebuffer, L: Layout(u32)) void {
        const sy = @as(i32, @intCast(L.top_y + L.ed_h + L.con_h));
        fb.fillRect(gfx.Rect{ .x = 0, .y = sy, .w = fb.width, .h = L.status_h }, STATUS_BG);
        fb.fillRect(gfx.Rect{ .x = 0, .y = sy - 1, .w = fb.width, .h = 1 }, GUTTER_LINE);

        const sty = sy + @as(i32, @intCast((L.status_h - L.ch_h) / 2));
        var lb: [16]u8 = undefined;
        fb.drawText(fmtU32(@as(u32, @intCast(self.cy + 1)), lb[0..]), 8, sty, TEXT_COL, L.ch_w);
        fb.drawText(":", 8 + @as(i32, @intCast(L.ch_w)), sty, NUML_COL, L.ch_w);
        var cb: [16]u8 = undefined;
        fb.drawText(fmtU32(@as(u32, @intCast(self.cx + 1)), cb[0..]), 8 + @as(i32, @intCast(L.ch_w + L.ch_w / 2 + 2)), sty, TEXT_COL, L.ch_w);

        if (self.modified) fb.drawText("  \xE2\x97\x8B", @as(i32, @intCast(L.ch_w * 3)), sty, MODIFIED_COL, L.ch_w);
        if (self.status_len > 0) fb.drawText(self.status[0..self.status_len], @as(i32, @intCast(L.ch_w * 5)), sty, STATUS_TEXT, L.ch_w);
        fb.drawText("dhjsjs  UTF-8", @as(i32, @intCast(fb.width)) - @as(i32, @intCast(L.ch_w * 8)), sty, STATUS_TEXT, L.ch_w);
    }

    fn drawScrollbarOverlays(self: *IdeState, fb: *gfx.Framebuffer, L: Layout(u32), mx: i32, my: i32) void {
        _ = L;
        var r: gfx.Rect = undefined;
        if (self.editorThumbRect(fb, &r)) {
            if (self.dragging == 1 or (mx >= r.x and mx < r.x + @as(i32, @intCast(r.w)) and my >= r.y and my < r.y + @as(i32, @intCast(r.h)))) {
                fb.fillRect(r, SCROLL_THUMB_HI);
            }
        }
        if (self.sidebarThumbRect(fb, &r)) {
            if (self.dragging == 3 or (mx >= r.x and mx < r.x + @as(i32, @intCast(r.w)) and my >= r.y and my < r.y + @as(i32, @intCast(r.h)))) {
                fb.fillRect(r, SCROLL_THUMB_HI);
            }
        }
        if (self.consoleThumbRect(fb, &r)) {
            if (self.dragging == 2 or (mx >= r.x and mx < r.x + @as(i32, @intCast(r.w)) and my >= r.y and my < r.y + @as(i32, @intCast(r.h)))) {
                fb.fillRect(r, SCROLL_THUMB_HI);
            }
        }
    }

    // ── mouse ───────────────────────────────────────────────
    pub fn handleMouseClick(self: *IdeState, fb: *gfx.Framebuffer, mx: i32, my: i32) void {
        const L = self.layout(fb);
        const sc = fontScale(fb.width);
        const ch_w = sc * gfx.FONT_W;
        const ch_h = sc * gfx.FONT_H + 4;
        const top_y = (ch_h) * 3;

        if (my < @as(i32, @intCast(top_y))) {
            // menu bar
            if (my < @as(i32, @intCast(ch_h))) {
                // map x position to menu index
                var mi: i32 = -1;
                for (&MENU_LABEL_X, 0..) |lx, li| {
                    const xi = 8 + lx * @as(i32, @intCast(ch_w));
                    const lbl = MENU_LABELS[li];
                    const wi = @as(i32, @intCast(lbl.len * ch_w + ch_w));
                    if (mx >= xi and mx < xi + wi) { mi = @as(i32, @intCast(li)); break; }
                }
                if (mi >= 0) {
                    if (self.open_menu == mi) {
                        self.open_menu = -1;
                    } else {
                        self.open_menu = mi;
                    }
                } else {
                    self.open_menu = -1;
                }
                // check if clicked on a dropdown item
                if (self.open_menu >= 0) {
                    const menu_def = &MENUS[@as(usize, @intCast(self.open_menu))];
                    const drop_x: i32 = 0;
                    const drop_y = @as(i32, @intCast(ch_h));
                    const drop_w = fb.width;
                    var item_y = drop_y;
                    for (menu_def.items) |item| {
                        if (item.label.len == 0) {
                            item_y += @as(i32, @intCast(ch_h / 2));
                            continue;
                        }
                        const ih = @as(i32, @intCast(ch_h));
                        const i_hover = mx >= drop_x and mx < drop_x + @as(i32, @intCast(drop_w)) and
                            my >= item_y and my < item_y + ih;
                        if (i_hover and item.enabled) {
                            switch (item.action) {
                                .new_file => { self.clen = 0; self.cx = 0; self.cy = 0; self.modified = false; self.flen = 0; self.setStatus("new file"); },
                                .open_file => self.startInput("open"),
                                .save_file => self.saveFile(),
                                .build => self.request_build = true,
                                .about => self.setStatus("dhjsjs IDE v0.1 — tiny Zig-based IDE"),
                                else => {},
                            }
                            self.open_menu = -1;
                            break;
                        }
                        item_y += ih;
                    }
                }
                return;
            }
            // toolbar: [Verify]=0, [Upload]=1, [New]=2, [Open]=3, [Save]=4
            if (my >= @as(i32, @intCast(ch_h)) and my < @as(i32, @intCast(ch_h * 2))) {
                const rel_x = @as(i32, mx - 8);
                const btn_w = @as(i32, @intCast(ch_w * 5));
                const spacing = @as(i32, @intCast(ch_w));
                const idx = @divFloor(rel_x, btn_w + spacing);
                if (idx == 2) { self.clen = 0; self.cx = 0; self.cy = 0; self.modified = false; self.setStatus("new file"); }
                if (idx == 3) self.startInput("open");
                if (idx == 4) self.saveFile();
                if (idx == 0 or idx == 1 or idx == 5) self.request_build = true;
                if (idx == 6) self.clearAll();
            }
            return;
        }

        // scrollbar drag / track jump
        if (self.startDrag(fb, mx, my)) return;
        const con_top_i = @as(i32, @intCast(L.top_y + L.ed_h));
        if (self.sidebar_w > 0 and mx >= @as(i32, @intCast(self.sidebar_w - TRACK_W)) and mx < @as(i32, @intCast(self.sidebar_w)) and my >= @as(i32, @intCast(L.top_y)) and my < con_top_i) {
            const total = self.file_count;
            const vis = self.sidebarVisibleItems(fb);
            if (total > vis) {
                const max_scroll = total - vis;
                const ratio = @as(u32, @intCast(@max(my - @as(i32, @intCast(L.top_y)), 0))) * total / L.ed_h;
                self.sidebar_scroll = @min(ratio, max_scroll);
            }
            return;
        }
        if (mx >= @as(i32, @intCast(fb.width - TRACK_W)) and mx < @as(i32, @intCast(fb.width)) and my >= @as(i32, @intCast(L.top_y)) and my < con_top_i) {
            const total = self.totalLines();
            const vis = self.editorVisibleLines(fb);
            if (total > vis) {
                const max_scroll = total - vis;
                const ratio = @as(u32, @intCast(@max(my - @as(i32, @intCast(L.top_y)), 0))) * total / L.ed_h;
                self.editor_scroll = @min(ratio, max_scroll);
            }
            return;
        }
        if (mx >= @as(i32, @intCast(fb.width - TRACK_W)) and mx < @as(i32, @intCast(fb.width)) and my >= con_top_i and my < @as(i32, @intCast(L.top_y + L.ed_h + L.con_h))) {
            const total = self.conLines();
            const vis = self.consoleVisibleLines(fb);
            if (total > vis) {
                const max_scroll = total - vis;
                const ratio = @as(u32, @intCast(@max(my - con_top_i, 0))) * total / L.con_h;
                self.console_scroll = @as(u32, @intCast(@min(ratio, max_scroll)));
            }
            return;
        }

        // sidebar click
        if (self.sidebar_w > 0 and mx >= 0 and @as(u32, @intCast(@max(mx, 0))) < self.sidebar_w and my >= @as(i32, @intCast(top_y))) {
            const rel_idx = @divFloor(@max(my - @as(i32, @intCast(top_y)), 0), @max(@as(i32, @intCast(ch_h)), 1));
            if (rel_idx > 0) {
                const file_idx = @as(usize, @intCast(rel_idx - 1)) + self.sidebar_scroll;
                if (file_idx < self.file_count) {
                    if (self.files[file_idx].is_dir) {
                        const name = self.files[file_idx].name[0..self.files[file_idx].len];
                        if (name.len == 2 and name[0] == '.' and name[1] == '.') {
                            if (self.cur_dir_len > 0) {
                                var end = self.cur_dir_len - 1;
                                while (end > 0 and self.cur_dir[end] != '/') : (end -= 1) {}
                                self.cur_dir_len = end;
                            }
                        } else {
                            var pi: usize = 0;
                            if (self.cur_dir_len > 0) {
                                for (self.cur_dir[0..self.cur_dir_len]) |c| { self.cur_dir[pi] = c; pi += 1; }
                            }
                            for (name) |c| { self.cur_dir[pi] = c; pi += 1; }
                            self.cur_dir[pi] = '/'; pi += 1;
                            self.cur_dir_len = pi;
                        }
                        self.refreshFileList();
                    } else {
                        var path_buf: [MAX_FILENAME]u8 = undefined;
                        var pi2: usize = 0;
                        if (self.cur_dir_len > 0) {
                            for (self.cur_dir[0..self.cur_dir_len]) |c| { path_buf[pi2] = c; pi2 += 1; }
                        }
                        for (self.files[file_idx].name[0..self.files[file_idx].len]) |c| { path_buf[pi2] = c; pi2 += 1; }
                        path_buf[pi2] = 0;
                        self.openFile(path_buf[0..pi2]);
                    }
                }
            }
            return;
        }

        self.open_menu = -1;
        self.moveCursorToMouse(fb, mx, my);
        self.startSelectionAtCursor();
    }

    pub fn moveCursorToMouse(self: *IdeState, fb: *gfx.Framebuffer, mx: i32, my: i32) void {
        const L = self.layout(fb);
        const top_y = L.top_y;
        const rel_y = @as(u32, @intCast(@max(my - @as(i32, @intCast(top_y)), 0)));
        const rel_x = @as(u32, @intCast(@max(mx - @as(i32, @intCast(self.sidebar_w + L.gutter_w)), 0)));
        const new_cy = rel_y / L.ch_h + self.editor_scroll;
        const total_lines = self.totalLines();
        self.cy = @min(new_cy, if (total_lines > 0) total_lines - 1 else 0);
        const line_start = self.getLineStart(self.cy);
        const line_end = self.getLineEnd(self.cy);
        const max_cx = codepointCount(self.content[line_start..line_end]);
        var new_cx = @as(usize, @intCast(rel_x / L.ch_w));
        if (new_cx > max_cx) new_cx = max_cx;
        self.cx = new_cx;
    }

    pub fn updateSelectionFromMouse(self: *IdeState, fb: *gfx.Framebuffer, mx: i32, my: i32) void {
        self.moveCursorToMouse(fb, mx, my);
        self.updateSelectionTo(self.cy, self.cx);
    }

    pub fn startInput(self: *IdeState, action: []const u8) void {
        self.input_mode = true;
        self.input_len = 0;
        self.input_action = if (action.len > 0) action[0] else 'o';
        if (action.len > 0 and action[0] == 's') {
            self.setStatus("Save as: type path, Enter to save, Esc to cancel");
        } else {
            self.setStatus("Open: type path, Enter to open, Esc to cancel");
        }
    }

    pub fn cancelInput(self: *IdeState) void {
        self.input_mode = false;
        self.input_len = 0;
        self.setStatus("cancelled");
    }

    pub fn confirmInput(self: *IdeState) void {
        if (self.input_len > 0) {
            const path = self.input_buf[0..self.input_len];
            if (self.input_action == 's') {
                var fi: usize = 0;
                while (fi < path.len and fi < MAX_FILENAME - 1) : (fi += 1) self.filename[fi] = path[fi];
                self.flen = path.len;
                self.saveFile();
            } else {
                self.openFile(path);
            }
        }
        self.input_mode = false;
        self.input_len = 0;
    }

    pub fn inputChar(self: *IdeState, ch: u8) bool {
        if (!self.input_mode) return false;
        switch (ch) {
            '\n', '\r' => self.confirmInput(),
            0x1b => self.cancelInput(),
            0x7f, 0x08 => { if (self.input_len > 0) self.input_len -= 1; },
            else => {
                if (ch >= 32 and ch < 127 and self.input_len < 255) {
                    self.input_buf[self.input_len] = ch;
                    self.input_len += 1;
                }
            },
        }
        return true;
    }

    // ── helpers ─────────────────────────────────────────────
    fn conLines(self: *IdeState) usize {
        var n: usize = 0;
        for (self.console[0..self.con_len]) |c| { if (c == '\n') n += 1; }
        return if (self.con_len > 0 and self.console[self.con_len - 1] != '\n') n + 1 else n;
    }

    fn findConLineStart(self: *IdeState, line: usize) usize {
        var ln: usize = 0;
        var i: usize = 0;
        while (i < self.con_len and ln < line) : (i += 1) { if (self.console[i] == '\n') ln += 1; }
        return if (i < self.con_len) i + 1 else self.con_len;
    }

    fn totalLines(self: *IdeState) usize {
        var n: usize = 1;
        for (self.content[0..self.clen]) |c| { if (c == '\n') n += 1; }
        return n;
    }

    fn getLineStart(self: *IdeState, line: usize) usize {
        var ln: usize = 0;
        var i: usize = 0;
        while (i < self.clen and ln < line) : (i += 1) { if (self.content[i] == '\n') ln += 1; }
        return i;
    }

    fn getLineEnd(self: *IdeState, line: usize) usize {
        var start = self.getLineStart(line);
        while (start < self.clen and self.content[start] != '\n') : (start += 1) {}
        return start;
    }

    fn utf8LeadLen(b: u8) u3 {
        if (b < 0x80) return 1;
        if (b & 0xE0 == 0xC0) return 2;
        if (b & 0xF0 == 0xE0) return 3;
        if (b & 0xF8 == 0xF0) return 4;
        return 1; // invalid / continuation treated as single byte
    }

    fn utf8IsCont(b: u8) bool {
        return b & 0xC0 == 0x80;
    }

    fn utf8Decode(buf: []const u8, i: usize, cp: *u32, len: *u3) bool {
        if (i >= buf.len) return false;
        const b0 = buf[i];
        const l = utf8LeadLen(b0);
        if (l == 1) { cp.* = b0; len.* = 1; return true; }
        if (i + l > buf.len) { cp.* = 0xFFFD; len.* = 1; return true; }
        var c: u32 = b0 & ((@as(u32, 1) << @as(u5, @intCast(7 - l))) - 1);
        var j: usize = 1;
        while (j < l) : (j += 1) {
            const b = buf[i + j];
            if (!utf8IsCont(b)) { cp.* = 0xFFFD; len.* = @as(u3, @intCast(j)); return true; }
            c = (c << 6) | (b & 0x3F);
        }
        cp.* = c;
        len.* = l;
        return true;
    }

    fn codepointCount(buf: []const u8) usize {
        var n: usize = 0;
        var i: usize = 0;
        while (i < buf.len) {
            var cp: u32 = 0; var len: u3 = 1;
            _ = utf8Decode(buf, i, &cp, &len);
            i += len;
            n += 1;
        }
        return n;
    }

    fn byteOffsetForCodepoint(buf: []const u8, cp_pos: usize) usize {
        var i: usize = 0;
        var n: usize = 0;
        while (i < buf.len and n < cp_pos) {
            var cp: u32 = 0; var len: u3 = 1;
            _ = utf8Decode(buf, i, &cp, &len);
            i += len;
            n += 1;
        }
        return i;
    }

    fn getLineLen(self: *IdeState, line: usize) usize {
        const start = self.getLineStart(line);
        const end = self.getLineEnd(line);
        return codepointCount(self.content[start..end]);
    }

    fn bytePos(self: *IdeState) usize {
        const start = self.getLineStart(self.cy);
        return start + byteOffsetForCodepoint(self.content[start..self.getLineEnd(self.cy)], self.cx);
    }

    pub fn utf8Encode(cp: u32, out: []u8) u3 {
        if (cp < 0x80) {
            out[0] = @as(u8, @intCast(cp));
            return 1;
        } else if (cp < 0x800) {
            out[0] = @as(u8, @intCast(0xC0 | (cp >> 6)));
            out[1] = @as(u8, @intCast(0x80 | (cp & 0x3F)));
            return 2;
        } else if (cp < 0x10000) {
            out[0] = @as(u8, @intCast(0xE0 | (cp >> 12)));
            out[1] = @as(u8, @intCast(0x80 | ((cp >> 6) & 0x3F)));
            out[2] = @as(u8, @intCast(0x80 | (cp & 0x3F)));
            return 3;
        } else {
            out[0] = @as(u8, @intCast(0xF0 | (cp >> 18)));
            out[1] = @as(u8, @intCast(0x80 | ((cp >> 12) & 0x3F)));
            out[2] = @as(u8, @intCast(0x80 | ((cp >> 6) & 0x3F)));
            out[3] = @as(u8, @intCast(0x80 | (cp & 0x3F)));
            return 4;
        }
    }

    pub fn insertCodepoint(self: *IdeState, cp: u32) void {
        if (self.input_mode) {
            var tmp: [4]u8 = undefined;
            const len = utf8Encode(cp, &tmp);
            var i: usize = 0;
            while (i < len and self.input_len < 255) : (i += 1) {
                self.input_buf[self.input_len] = tmp[i];
                self.input_len += 1;
            }
            return;
        }
        var start: usize = 0; var end: usize = 0;
        if (self.selectionAbsRange(&start, &end)) {
            self.deleteRange(start, end);
        }
        var tmp: [4]u8 = undefined;
        const len = utf8Encode(cp, &tmp);
        if (self.clen + len >= MAX_CONTENT) return;
        var pos = self.bytePos();
        if (pos > self.clen) pos = self.clen;
        var i = self.clen + len - 1;
        while (i >= pos + len) : (i -= 1) {
            self.content[i] = self.content[i - len];
            if (i == pos + len) break;
        }
        i = 0;
        while (i < len) : (i += 1) self.content[pos + i] = tmp[i];
        self.clen += len;
        self.cx += 1;
        if (cp == '\n') { self.cx = 0; self.cy += 1; }
        self.modified = true;
    }

    pub fn insertChar(self: *IdeState, ch: u8) void {
        self.insertCodepoint(ch);
    }

    pub fn deleteChar(self: *IdeState) void {
        if (self.input_mode) {
            if (self.input_len > 0) self.input_len -= 1;
            return;
        }
        var start: usize = 0; var end: usize = 0;
        if (self.selectionAbsRange(&start, &end)) {
            self.deleteRange(start, end);
            return;
        }
        const line_start = self.getLineStart(self.cy);
        const line_end = self.getLineEnd(self.cy);
        const pos = line_start + byteOffsetForCodepoint(self.content[line_start..line_end], self.cx);
        if (pos == 0 or self.clen == 0) return;
        const prev_pos = line_start + byteOffsetForCodepoint(self.content[line_start..line_end], self.cx - 1);
        const del_len = pos - prev_pos;
        var i = prev_pos;
        while (i + del_len < self.clen) : (i += 1) self.content[i] = self.content[i + del_len];
        self.clen -= del_len;
        if (self.cx > 0) {
            self.cx -= 1;
        } else if (self.cy > 0) {
            self.cy -= 1;
            self.cx = self.getLineLen(self.cy);
        }
        self.modified = true;
    }

    pub fn cursorLeft(self: *IdeState) void {
        self.clearSelection();
        if (self.cx > 0) { self.cx -= 1; }
        else if (self.cy > 0) { self.cy -= 1; self.cx = self.getLineLen(self.cy); }
    }

    pub fn cursorRight(self: *IdeState) void {
        self.clearSelection();
        if (self.cx < self.getLineLen(self.cy)) { self.cx += 1; }
        else if (self.getLineEnd(self.cy) < self.clen) { self.cy += 1; self.cx = 0; }
    }

    pub fn cursorUp(self: *IdeState) void {
        self.clearSelection();
        if (self.cy > 0) { self.cy -= 1; self.cx = @min(self.cx, self.getLineLen(self.cy)); }
    }

    pub fn cursorDown(self: *IdeState) void {
        self.clearSelection();
        if (self.getLineStart(self.cy + 1) < self.clen) { self.cy += 1; self.cx = @min(self.cx, self.getLineLen(self.cy)); }
    }

    pub fn cursorHome(self: *IdeState) void { self.clearSelection(); self.cx = 0; }
    pub fn cursorEnd(self: *IdeState) void { self.clearSelection(); self.cx = self.getLineLen(self.cy); }
};
