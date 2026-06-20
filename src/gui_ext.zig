const gfx = @import("render.zig");
const gui = @import("gui.zig");

pub const MAX_TABS: usize = 32;
pub const MAX_MENU_ITEMS: usize = 64;
pub const MAX_TREE_NODES: usize = 128;

const TabItem = struct { label: [64]u8, label_len: usize };
const MenuItem = struct { label: [32]u8, label_len: usize, open: bool };

pub const TabBar = struct {
    tabs: [MAX_TABS]TabItem,
    tab_count: usize,
    active_tab: usize,
    tab_width: u32,
};

pub const ComboBox = struct {
    items: [MAX_TABS]TabItem,
    item_count: usize,
    selected: usize,
    open: bool,
};

pub const TreeNode = struct {
    label: [64]u8,
    label_len: usize,
    depth: u32,
    expanded: bool,
    selected: bool,
    has_children: bool,
};

pub const TreeView = struct {
    nodes: [MAX_TREE_NODES]TreeNode,
    node_count: usize,
    scroll_offset: i32,
};

pub const ScrollArea = struct {
    scroll_y: i32,
    scroll_x: i32,
    content_h: u32,
    content_w: u32,
    view_h: u32,
    view_w: u32,
    scrollbar_visible: bool,
};

pub const MenuBar = struct {
    menus: [MAX_MENU_ITEMS]MenuItem,
    menu_count: usize,
    active_menu: i32,
};

pub const ColorPicker = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
    mode: u8,
};

pub const ProgressBar = struct {
    value: f32,
    animated: bool,
    label: [64]u8,
    label_len: usize,
};

pub const RadioButton = struct {
    group: u32,
    value: u32,
    label: [64]u8,
    label_len: usize,
};

pub const ImageDisplay = struct {
    pixels: ?[*]u32,
    width: u32,
    height: u32,
    scale: f32,
};

pub fn drawProgressBar(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, value: f32, track_color: u32, fill_color: u32, border_color: u32) void {
    fillRect(fb, x, y, w, h, track_color);
    const fill_w: u32 = @intCast(@max(0, @min(w, @as(u32, @intFromFloat(@as(f64, value) * @as(f64, w))))));
    if (fill_w > 0) {
        fillRect(fb, x, y, fill_w, h, fill_color);
    }
    drawRectBorder(fb, x, y, w, h, border_color);
}

pub fn drawTabBar(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, tabs: *TabBar, style: *const gui.Style, mouse_x: i32, mouse_y: i32, clicked: bool) usize {
    fillRect(fb, x, y, w, h, style.panel_bg);
    drawRectBorder(fb, x, y, w, h, style.border);

    const tab_w = if (tabs.tab_count > 0) w / @as(u32, @intCast(tabs.tab_count)) else w;
    tabs.tab_width = tab_w;

    var i: usize = 0;
    while (i < tabs.tab_count) : (i += 1) {
        const tx = x + @as(i32, @intCast(i * tab_w));
        const tw = if (i == tabs.tab_count - 1) w - @as(u32, @intCast(i * tab_w)) else tab_w;

        const hovered = mouse_x >= tx and mouse_x < tx + @as(i32, @intCast(tw)) and
            mouse_y >= y and mouse_y < y + @as(i32, @intCast(h));

        const bg = if (i == tabs.active_tab) style.accent
            else if (hovered) style.button_hover
            else style.button_bg;

        fillRect(fb, tx, y, tw, h, bg);
        drawRectBorder(fb, tx, y, tw, h, style.border);

        const label = tabs.tabs[i].label[0..tabs.tabs[i].label_len];
        drawText(fb, label, tx + 4, y + 4, if (i == tabs.active_tab) style.text else style.text_dim, 8);

        if (hovered and clicked) {
            tabs.active_tab = i;
        }
    }
    return tabs.active_tab;
}

pub fn drawComboBox(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, combo: *ComboBox, style: *const gui.Style, mouse_x: i32, mouse_y: i32, clicked: bool) usize {
    const is_hovered = mouse_x >= x and mouse_x < x + @as(i32, @intCast(w)) and
        mouse_y >= y and mouse_y < y + @as(i32, @intCast(h));

    const bg = if (is_hovered) style.button_hover else style.input_bg;
    fillRect(fb, x, y, w, h, bg);
    drawRectBorder(fb, x, y, w, h, style.input_border);

    if (combo.selected < combo.item_count) {
        const label = combo.items[combo.selected].label[0..combo.items[combo.selected].label_len];
        drawText(fb, label, x + 4, y + 4, style.input_text, 8);
    }

    const arrow_x = x + @as(i32, @intCast(w)) - 16;
    drawText(fb, "v", arrow_x, y + 4, style.text_dim, 8);

    if (is_hovered and clicked) {
        combo.open = !combo.open;
    }

    if (combo.open) {
        const drop_y = y + @as(i32, @intCast(h)) + 2;
        const drop_h = @as(u32, @intCast(combo.item_count)) * (h + 2);
        fillRect(fb, x, drop_y, w, drop_h, style.input_bg);
        drawRectBorder(fb, x, drop_y, w, drop_h, style.input_border);

        var di: usize = 0;
        while (di < combo.item_count) : (di += 1) {
            const iy = drop_y + @as(i32, @intCast(di * (h + 2)));
            const ih: u32 = h;
            const i_hovered = mouse_x >= x and mouse_x < x + @as(i32, @intCast(w)) and
                mouse_y >= iy and mouse_y < iy + @as(i32, @intCast(ih));

            if (i_hovered) {
                fillRect(fb, x + 1, iy, w - 2, ih, style.button_hover);
            }
            const label = combo.items[di].label[0..combo.items[di].label_len];
            drawText(fb, label, x + 4, iy + 4, style.input_text, 8);

            if (i_hovered and clicked) {
                combo.selected = di;
                combo.open = false;
            }
        }
    }
    return combo.selected;
}

pub fn drawRadioButton(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, _group: u32, value: u32, selected: *u32, style: *const gui.Style, mouse_x: i32, mouse_y: i32, clicked: bool) void {
    _ = _group;
    const is_hovered = mouse_x >= x and mouse_x < x + @as(i32, @intCast(w)) and
        mouse_y >= y and mouse_y < y + @as(i32, @intCast(h));

    if (is_hovered and clicked) {
        selected.* = value;
    }

    const cx = x + 8;
    const cy = y + @as(i32, @intCast(h)) / 2;
    const r: i32 = 6;

    drawCircle(fb, cx, cy, r, if (is_hovered) style.accent else style.border);
    if (selected.* == value) {
        drawCircle(fb, cx, cy, 3, style.accent);
    }
}

pub fn drawTreeView(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, tree: *TreeView, style: *const gui.Style, mouse_x: i32, mouse_y: i32, clicked: bool) void {
    fillRect(fb, x, y, w, h, style.panel_bg);
    drawRectBorder(fb, x, y, w, h, style.border);

    const row_h: i32 = 22;
    var cy = y - tree.scroll_offset;
    var i: usize = 0;
    while (i < tree.node_count) : (i += 1) {
        const node = &tree.nodes[i];
        if (cy + row_h < y or cy > y + @as(i32, @intCast(h))) {
            cy += row_h;
            continue;
        }

        const indent = @as(i32, @intCast(node.depth * 16));
        const nx = x + 4 + indent;

        const is_hovered = mouse_x >= x and mouse_x < x + @as(i32, @intCast(w)) and
            mouse_y >= cy and mouse_y < cy + row_h;

        if (is_hovered) {
            fillRect(fb, x + 1, cy, w - 2, @as(u32, @intCast(row_h)), style.button_hover);
        }
        if (node.selected) {
            fillRect(fb, x + 1, cy, w - 2, @as(u32, @intCast(row_h)), style.accent);
        }

        if (node.has_children) {
            const arrow = if (node.expanded) "v" else ">";
            drawText(fb, arrow, nx, cy + 3, style.text_dim, 8);
        }

        const label = node.label[0..node.label_len];
        drawText(fb, label, nx + 12, cy + 3, style.text, 8);

        if (is_hovered and clicked) {
            if (node.has_children) {
                node.expanded = !node.expanded;
            }
            node.selected = true;
        }

        cy += row_h;
    }
}

pub fn drawScrollArea(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, scroll: *ScrollArea, style: *const gui.Style, mouse_x: i32, mouse_y: i32, scroll_delta: i32) void {
    scroll.view_h = h;
    scroll.view_w = w;

    if (scroll.content_h > h) {
        scroll.scrollbar_visible = true;
        scroll.scroll_y += scroll_delta * 20;
        scroll.scroll_y = @max(0, @min(scroll.scroll_y, @as(i32, @intCast(scroll.content_h - h))));

        const bar_h: u32 = @max(20, h * h / scroll.content_h);
        const denom = @as(i32, @intCast(scroll.content_h - h));
        const bar_y: i32 = if (denom > 0) y + @divTrunc(@as(i32, @intCast(h - bar_h)) * scroll.scroll_y, denom) else y;

        fillRect(fb, x + @as(i32, @intCast(w)) - 8, y, 8, h, style.panel_bg);
        fillRect(fb, x + @as(i32, @intCast(w)) - 8, bar_y, 8, bar_h, style.slider_thumb);
    } else {
        scroll.scrollbar_visible = false;
        scroll.scroll_y = 0;
    }

    _ = mouse_x;
    _ = mouse_y;
}

pub fn drawMenuBar(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, bar: *MenuBar, style: *const gui.Style, mouse_x: i32, mouse_y: i32, clicked: bool) void {
    fillRect(fb, x, y, w, h, style.panel_bg);
    drawRectBorder(fb, x, y, w, h, style.border);

    var cx = x + 4;
    var i: usize = 0;
    while (i < bar.menu_count) : (i += 1) {
        const label = bar.menus[i].label[0..bar.menus[i].label_len];
        const tw: u32 = @intCast(label.len * 8 + 12);

        const is_hovered = mouse_x >= cx and mouse_x < cx + @as(i32, @intCast(tw)) and
            mouse_y >= y and mouse_y < y + @as(i32, @intCast(h));

        if (is_hovered or bar.menus[i].open) {
            fillRect(fb, cx, y, tw, h, style.button_hover);
        }

        drawText(fb, label, cx + 6, y + 4, style.text, 8);

        if (is_hovered and clicked) {
            if (bar.active_menu == @as(i32, @intCast(i))) {
                bar.menus[i].open = !bar.menus[i].open;
                bar.active_menu = if (bar.menus[i].open) @as(i32, @intCast(i)) else -1;
            } else {
                if (bar.active_menu >= 0) {
                    bar.menus[@as(usize, @intCast(bar.active_menu))].open = false;
                }
                bar.menus[i].open = true;
                bar.active_menu = @as(i32, @intCast(i));
            }
        }

        cx += @as(i32, @intCast(tw));
    }
}

pub fn drawColorPicker(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, picker: *ColorPicker, style: *const gui.Style) void {
    fillRect(fb, x, y, w, h, style.panel_bg);
    drawRectBorder(fb, x, y, w, h, style.border);

    const grid_w = w / 8;
    const grid_h = (h - 24) / 4;

    var row: u32 = 0;
    while (row < 4) : (row += 1) {
        var col: u32 = 0;
        while (col < 8) : (col += 1) {
            const cx = x + @as(i32, @intCast(col * grid_w));
            const cy = y + @as(i32, @intCast(row * grid_h));
            const r: u8 = @intCast(@min(255, col * 36));
            const g: u8 = @intCast(@min(255, row * 85));
            const b: u8 = @intCast(@min(255, (col + row) * 25));
            const color = (@as(u32, 0xFF) << 24) | (@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b);
            fillRect(fb, cx, cy, grid_w, grid_h, color);
        }
    }

    const preview_y = y + @as(i32, @intCast(h)) - 20;
    const pr = @as(u8, @intFromFloat(picker.r * 255.0));
    const pg = @as(u8, @intFromFloat(picker.g * 255.0));
    const pb = @as(u8, @intFromFloat(picker.b * 255.0));
    const preview_color = (@as(u32, 0xFF) << 24) | (@as(u32, pr) << 16) | (@as(u32, pg) << 8) | @as(u32, pb);
    fillRect(fb, x + 4, preview_y, w - 8, 16, preview_color);
    drawRectBorder(fb, x + 4, preview_y, w - 8, 16, style.border);
}

pub fn drawImage(fb: *gfx.Framebuffer, x: i32, y: i32, img: *ImageDisplay, style: *const gui.Style) void {
    if (img.pixels == null) return;
    const w = @as(u32, @intFromFloat(@as(f64, img.width) * @as(f64, img.scale)));
    const h = @as(u32, @intFromFloat(@as(f64, img.height) * @as(f64, img.scale)));

    fillRect(fb, x, y, w, h, style.panel_bg);

    if (img.scale >= 1.0) {
        var py: u32 = 0;
        while (py < img.height) : (py += 1) {
            var px: u32 = 0;
            while (px < img.width) : (px += 1) {
                const color = img.pixels.?[@as(usize, py) * img.width + px];
                const dx = x + @as(i32, @intCast(px * @as(u32, @intFromFloat(img.scale))));
                const dy = y + @as(i32, @intCast(py * @as(u32, @intFromFloat(img.scale))));
                const sw = @as(u32, @intFromFloat(img.scale));
                const sh = @as(u32, @intFromFloat(img.scale));
                fillRect(fb, dx, dy, sw, sh, color);
            }
        }
    }
}

pub fn initTabBar() TabBar {
    var tabs: [MAX_TABS]TabItem = undefined;
    var ti: usize = 0;
    while (ti < MAX_TABS) : (ti += 1) {
        tabs[ti] = TabItem{ .label = [_]u8{0} ** 64, .label_len = 0 };
    }
    return TabBar{
        .tabs = tabs,
        .tab_count = 0,
        .active_tab = 0,
        .tab_width = 0,
    };
}

pub fn addTab(bar: *TabBar, label: []const u8) void {
    if (bar.tab_count >= MAX_TABS) return;
    const idx = bar.tab_count;
    const len = @min(label.len, 63);
    var i: usize = 0;
    while (i < len) : (i += 1) bar.tabs[idx].label[i] = label[i];
    bar.tabs[idx].label_len = len;
    bar.tab_count += 1;
}

pub fn initComboBox() ComboBox {
    var items: [MAX_TABS]TabItem = undefined;
    var ii: usize = 0;
    while (ii < MAX_TABS) : (ii += 1) {
        items[ii] = TabItem{ .label = [_]u8{0} ** 64, .label_len = 0 };
    }
    return ComboBox{
        .items = items,
        .item_count = 0,
        .selected = 0,
        .open = false,
    };
}

pub fn addComboItem(combo: *ComboBox, label: []const u8) void {
    if (combo.item_count >= MAX_TABS) return;
    const idx = combo.item_count;
    const len = @min(label.len, 63);
    var i: usize = 0;
    while (i < len) : (i += 1) combo.items[idx].label[i] = label[i];
    combo.items[idx].label_len = len;
    combo.item_count += 1;
}

pub fn initTreeView() TreeView {
    return TreeView{
        .nodes = [_]TreeNode{
            .{ .label = [_]u8{0} ** 64, .label_len = 0, .depth = 0, .expanded = false, .selected = false, .has_children = false },
        } ** MAX_TREE_NODES,
        .node_count = 0,
        .scroll_offset = 0,
    };
}

pub fn addTreeNode(tree: *TreeView, label: []const u8, depth: u32, has_children: bool) void {
    if (tree.node_count >= MAX_TREE_NODES) return;
    const idx = tree.node_count;
    const len = @min(label.len, 63);
    var i: usize = 0;
    while (i < len) : (i += 1) tree.nodes[idx].label[i] = label[i];
    tree.nodes[idx].label_len = len;
    tree.nodes[idx].depth = depth;
    tree.nodes[idx].has_children = has_children;
    tree.node_count += 1;
}

pub fn initScrollArea() ScrollArea {
    return ScrollArea{
        .scroll_y = 0,
        .scroll_x = 0,
        .content_h = 0,
        .content_w = 0,
        .view_h = 0,
        .view_w = 0,
        .scrollbar_visible = false,
    };
}

pub fn initMenuBar() MenuBar {
    var menus: [MAX_MENU_ITEMS]MenuItem = undefined;
    var mi: usize = 0;
    while (mi < MAX_MENU_ITEMS) : (mi += 1) {
        menus[mi] = MenuItem{ .label = [_]u8{0} ** 32, .label_len = 0, .open = false };
    }
    return MenuBar{
        .menus = menus,
        .menu_count = 0,
        .active_menu = -1,
    };
}

pub fn addMenu(bar: *MenuBar, label: []const u8) void {
    if (bar.menu_count >= MAX_MENU_ITEMS) return;
    const idx = bar.menu_count;
    const len = @min(label.len, 31);
    var i: usize = 0;
    while (i < len) : (i += 1) bar.menus[idx].label[i] = label[i];
    bar.menus[idx].label_len = len;
    bar.menu_count += 1;
}

pub fn initColorPicker() ColorPicker {
    return ColorPicker{ .r = 1.0, .g = 0.5, .b = 0.0, .a = 1.0, .mode = 0 };
}

pub fn initProgressBar() ProgressBar {
    return ProgressBar{ .value = 0, .animated = false, .label = [_]u8{0} ** 64, .label_len = 0 };
}

fn fillRect(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, color: u32) void {
    const x1: u32 = if (x < 0) 0 else @intCast(x);
    const y1: u32 = if (y < 0) 0 else @intCast(y);
    const x2: u32 = @min(x1 + w, fb.width);
    const y2: u32 = @min(y1 + h, fb.height);
    var yi = y1;
    while (yi < y2) : (yi += 1) {
        const row = @as(usize, yi) * fb.stride;
        var xi = x1;
        while (xi < x2) : (xi += 1) {
            fb.pixels[row + xi] = color;
        }
    }
}

fn drawRectBorder(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, color: u32) void {
    if (w < 2 or h < 2) { fillRect(fb, x, y, w, h, color); return; }
    fillRect(fb, x, y, w, 1, color);
    fillRect(fb, x, y + @as(i32, @intCast(h)) - 1, w, 1, color);
    fillRect(fb, x, y, 1, h, color);
    fillRect(fb, x + @as(i32, @intCast(w)) - 1, y, 1, h, color);
}

fn drawText(fb: *gfx.Framebuffer, text: []const u8, x: i32, y: i32, color: u32, size: u32) void {
    const scale = if (size >= 8) @as(u32, @intCast(@divFloor(size, 8))) else 1;
    var cx = x;
    var cy = y;
    for (text) |ch| {
        if (ch == '\n') { cy += @as(i32, @intCast(scale * 8 + 2)); cx = x; continue; }
        const glyph = gfx.getGlyph(ch);
        var gy: u32 = 0;
        while (gy < 8) : (gy += 1) {
            var gx: u32 = 0;
            while (gx < 8) : (gx += 1) {
                if ((glyph[gy] & (@as(u8, 1) << @intCast(7 - gx))) != 0) {
                    const bx = cx + @as(i32, @intCast(gx * scale));
                    const by = cy + @as(i32, @intCast(gy * scale));
                    var sy: u32 = 0;
                    while (sy < scale) : (sy += 1) {
                        var sx: u32 = 0;
                        while (sx < scale) : (sx += 1) {
                            const px = bx + @as(i32, @intCast(sx));
                            const py = by + @as(i32, @intCast(sy));
                            if (px >= 0 and py >= 0 and px < @as(i32, @intCast(fb.width)) and py < @as(i32, @intCast(fb.height))) {
                                fb.pixels[@as(usize, @intCast(py)) * fb.stride + @as(usize, @intCast(px))] = color;
                            }
                        }
                    }
                }
            }
        }
        cx += @as(i32, @intCast(scale * 8 + 2));
    }
}

fn drawCircle(fb: *gfx.Framebuffer, cx: i32, cy: i32, r: i32, color: u32) void {
    var dy = -r;
    while (dy <= r) : (dy += 1) {
        var dx = -r;
        while (dx <= r) : (dx += 1) {
            if (dx * dx + dy * dy <= r * r) {
                const px = cx + dx;
                const py = cy + dy;
                if (px >= 0 and py >= 0 and px < @as(i32, @intCast(fb.width)) and py < @as(i32, @intCast(fb.height))) {
                    fb.pixels[@as(usize, @intCast(py)) * fb.stride + @as(usize, @intCast(px))] = color;
                }
            }
        }
    }
}
