const sys = @import("sys.zig");

pub const JsonType = enum(u8) {
    null = 0,
    false_ = 1,
    true_ = 2,
    number = 3,
    string = 4,
    array = 5,
    object = 6,
};

pub const JsonNode = struct {
    kind: u8,
    num_val: f64,
    str_start: ?[*:0]const u8,
    str_len: u32,
    first_child: ?*JsonNode,
    next_sibling: ?*JsonNode,
    key: ?[*:0]const u8,
    key_len: u32,
};

// --- Arena allocator (bump allocator over mmap pages) ---

const PAGE_SIZE = 4096;
const MAX_PAGES = 4096; // up to 16 MB

var arena_buf: ?[*]u8 = null;
var arena_len: usize = 0;
var arena_cap: usize = 0;
var arena_used: usize = 0;

fn arenaAlloc(n: usize) ?[*]u8 {
    const aligned = (n + 15) & ~@as(usize, 15); // 16-byte align
    if (arena_buf) |buf| {
        if (arena_used + aligned <= arena_cap) {
            const ptr = buf + arena_used;
            arena_used += aligned;
            return ptr;
        }
    }
    // grow: mmap more pages
    const needed = arena_len + n;
    const new_pages = (needed / PAGE_SIZE) + 1;
    const new_cap = new_pages * PAGE_SIZE;
    if (arena_buf) |buf| {
        // We can't really grow mmap in-place, so we map a bigger region
        // and copy. But since json_free resets everything, we just map fresh.
        sys.munmap(buf, arena_cap);
    }
    const new_buf = sys.mmap(null, new_cap, sys.PROT_READ | sys.PROT_WRITE, 0x02 | 0x20, -1, 0);
    if (new_buf) |b| {
        arena_buf = @ptrCast(b);
        arena_cap = new_cap;
        arena_len = new_cap;
        const ptr = arena_buf.? + arena_used;
        arena_used += aligned;
        return ptr;
    }
    return null;
}

fn arenaFree() void {
    if (arena_buf) |buf| {
        sys.munmap(buf, arena_cap);
        arena_buf = null;
    }
    arena_len = 0;
    arena_cap = 0;
    arena_used = 0;
}

fn allocNode() *JsonNode {
    const p = arenaAlloc(@sizeOf(JsonNode)) orelse @panic("json oom");
    const node: *JsonNode = @ptrCast(@alignCast(p));
    node.* = JsonNode{
        .kind = @intFromEnum(JsonType.null),
        .num_val = 0,
        .str_start = null,
        .str_len = 0,
        .first_child = null,
        .next_sibling = null,
        .key = null,
        .key_len = 0,
    };
    return node;
}

fn strLen(p: [*:0]const u8) u32 {
    var i: u32 = 0;
    while (p[i] != 0) : (i += 1) {}
    return i;
}

fn eqlBytes(a: [*]const u8, b: [*]const u8, len: u32) bool {
    var i: u32 = 0;
    while (i < len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn skipWhitespace(p: *[*:0]const u8) void {
    while (p.*[0] == ' ' or p.*[0] == '\t' or p.*[0] == '\n' or p.*[0] == '\r') {
        p.* += 1;
    }
}

fn parseString(p: *[*:0]const u8, out_len: *u32) ?[*:0]const u8 {
    if (p.*[0] != '"') return null;
    p.* += 1;
    const start = p.*;
    var len: u32 = 0;
    while (p.*[0] != '"' and p.*[0] != 0) {
        if (p.*[0] == '\\') {
            p.* += 2;
            len += 2;
        } else {
            p.* += 1;
            len += 1;
        }
    }
    if (p.*[0] != '"') return null;
    out_len.* = len;
    p.* += 1;
    return start;
}

// Simple float parser (no std needed)
fn parseFloat(input: []const u8) f64 {
    var i: usize = 0;
    var negative = false;
    if (input.len > 0 and input[0] == '-') {
        negative = true;
        i = 1;
    } else if (input.len > 0 and input[0] == '+') {
        i = 1;
    }

    var int_part: f64 = 0;
    while (i < input.len and input[i] >= '0' and input[i] <= '9') {
        int_part = int_part * 10.0 + @as(f64, @floatFromInt(input[i] - '0'));
        i += 1;
    }

    var frac_part: f64 = 0;
    if (i < input.len and input[i] == '.') {
        i += 1;
        var frac_div: f64 = 10.0;
        while (i < input.len and input[i] >= '0' and input[i] <= '9') {
            frac_part += @as(f64, @floatFromInt(input[i] - '0')) / frac_div;
            frac_div *= 10.0;
            i += 1;
        }
    }

    var result = int_part + frac_part;

    // exponent
    if (i < input.len and (input[i] == 'e' or input[i] == 'E')) {
        i += 1;
        var exp_neg = false;
        if (i < input.len and input[i] == '-') {
            exp_neg = true;
            i += 1;
        } else if (i < input.len and input[i] == '+') {
            i += 1;
        }
        var exp: i32 = 0;
        while (i < input.len and input[i] >= '0' and input[i] <= '9') {
            exp = exp * 10 + @as(i32, input[i] - '0');
            i += 1;
        }
        var mult: f64 = 1;
        var j: i32 = 0;
        while (j < exp) : (j += 1) {
            mult *= 10.0;
        }
        if (exp_neg) {
            result /= mult;
        } else {
            result *= mult;
        }
    }

    if (negative) result = -result;
    return result;
}

fn parseValue(p: *[*:0]const u8) ?*JsonNode {
    skipWhitespace(p);
    if (p.*[0] == 0) return null;

    if (p.*[0] == '"') {
        var len: u32 = 0;
        const start = parseString(p, &len) orelse return null;
        const node = allocNode();
        node.kind = @intFromEnum(JsonType.string);
        node.str_start = start;
        node.str_len = len;
        return node;
    }

    if (p.*[0] == '{') {
        return parseObject(p);
    }

    if (p.*[0] == '[') {
        return parseArray(p);
    }

    if (p.*[0] == 't' and p.*[1] == 'r' and p.*[2] == 'u' and p.*[3] == 'e') {
        p.* += 4;
        const node = allocNode();
        node.kind = @intFromEnum(JsonType.true_);
        return node;
    }

    if (p.*[0] == 'f' and p.*[1] == 'a' and p.*[2] == 'l' and p.*[3] == 's' and p.*[4] == 'e') {
        p.* += 5;
        const node = allocNode();
        node.kind = @intFromEnum(JsonType.false_);
        return node;
    }

    if (p.*[0] == 'n' and p.*[1] == 'u' and p.*[2] == 'l' and p.*[3] == 'l') {
        p.* += 4;
        const node = allocNode();
        node.kind = @intFromEnum(JsonType.null);
        return node;
    }

    // number
    var num_start = p.*;
    var num_len: usize = 0;
    while (p.*[0] == '-' or p.*[0] == '+' or p.*[0] == '.' or (p.*[0] >= '0' and p.*[0] <= '9') or p.*[0] == 'e' or p.*[0] == 'E') {
        p.* += 1;
        num_len += 1;
    }
    if (num_len > 0) {
        const node = allocNode();
        node.kind = @intFromEnum(JsonType.number);
        const slice = num_start[0..num_len];
        node.num_val = parseFloat(slice);
        return node;
    }

    return null;
}

fn parseObject(p: *[*:0]const u8) ?*JsonNode {
    if (p.*[0] != '{') return null;
    p.* += 1;
    const node = allocNode();
    node.kind = @intFromEnum(JsonType.object);
    var last_child: ?*JsonNode = null;

    skipWhitespace(p);
    if (p.*[0] == '}') { p.* += 1; return node; }

    while (true) {
        skipWhitespace(p);
        var key_len: u32 = 0;
        const key_start = parseString(p, &key_len) orelse break;
        skipWhitespace(p);
        if (p.*[0] != ':') break;
        p.* += 1;
        skipWhitespace(p);
        const val = parseValue(p) orelse break;
        val.key = key_start;
        val.key_len = key_len;
        if (last_child) |lc| {
            lc.next_sibling = val;
        } else {
            node.first_child = val;
        }
        last_child = val;
        skipWhitespace(p);
        if (p.*[0] == '}') { p.* += 1; return node; }
        if (p.*[0] != ',') break;
        p.* += 1;
    }
    return null;
}

fn parseArray(p: *[*:0]const u8) ?*JsonNode {
    if (p.*[0] != '[') return null;
    p.* += 1;
    const node = allocNode();
    node.kind = @intFromEnum(JsonType.array);
    var last_child: ?*JsonNode = null;

    skipWhitespace(p);
    if (p.*[0] == ']') { p.* += 1; return node; }

    while (true) {
        skipWhitespace(p);
        const val = parseValue(p) orelse break;
        if (last_child) |lc| {
            lc.next_sibling = val;
        } else {
            node.first_child = val;
        }
        last_child = val;
        skipWhitespace(p);
        if (p.*[0] == ']') { p.* += 1; return node; }
        if (p.*[0] != ',') break;
        p.* += 1;
    }
    return null;
}

pub export fn json_parse(str: [*:0]const u8) ?*JsonNode {
    var p = str;
    return parseValue(&p);
}

pub export fn json_free(root: ?*JsonNode) void {
    _ = root;
    arenaFree();
}

pub export fn json_type(node: ?*JsonNode) u32 {
    if (node) |n| return n.kind;
    return 0;
}

pub export fn json_num(node: ?*JsonNode) u64 {
    if (node) |n| return @as(u64, @bitCast(n.num_val));
    return 0;
}

pub export fn json_str(node: ?*JsonNode) ?[*:0]const u8 {
    if (node) |n| return n.str_start;
    return null;
}

pub export fn json_str_len(node: ?*JsonNode) u32 {
    if (node) |n| return n.str_len;
    return 0;
}

pub export fn json_first_child(node: ?*JsonNode) ?*JsonNode {
    if (node) |n| return n.first_child;
    return null;
}

pub export fn json_next_sibling(node: ?*JsonNode) ?*JsonNode {
    if (node) |n| return n.next_sibling;
    return null;
}

pub export fn json_key(node: ?*JsonNode) ?[*:0]const u8 {
    if (node) |n| return n.key;
    return null;
}

pub export fn json_key_len(node: ?*JsonNode) u32 {
    if (node) |n| return n.key_len;
    return 0;
}

pub export fn json_get(obj: ?*JsonNode, key: [*:0]const u8) ?*JsonNode {
    if (obj) |o| {
        var ch = o.first_child;
        while (ch) |c| {
            if (c.key) |k| {
                const klen = c.key_len;
                const klen2 = strLen(key);
                if (klen == klen2 and eqlBytes(k, key, klen)) {
                    return c;
                }
            }
            ch = c.next_sibling;
        }
    }
    return null;
}

pub export fn json_idx(arr: ?*JsonNode, idx: u32) ?*JsonNode {
    if (arr) |a| {
        var ch = a.first_child;
        var i: u32 = 0;
        while (ch) |c| {
            if (i == idx) return c;
            i += 1;
            ch = c.next_sibling;
        }
    }
    return null;
}

pub export fn json_len(arr: ?*JsonNode) u32 {
    if (arr) |a| {
        var ch = a.first_child;
        var i: u32 = 0;
        while (ch) |_| {
            i += 1;
            ch = ch.?.next_sibling;
        }
        return i;
    }
    return 0;
}
