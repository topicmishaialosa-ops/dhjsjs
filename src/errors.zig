const sys = @import("sys.zig");

pub const ErrorKind = enum(u8) {
    lex_invalid_char,
    lex_unterminated_string,
    lex_unterminated_block_comment,
    parse_unexpected_eof,
    parse_unexpected_token,
    parse_missing_semicolon,
    parse_missing_close_paren,
    parse_missing_open_brace,
    parse_missing_close_brace,
    parse_expected_expr,
    parse_expected_ident,
    parse_duplicate_fn,
    parse_invalid_decl,
    comp_undefined_var,
    comp_undefined_fn,
    comp_type_mismatch,
    comp_wrong_arg_count,
    comp_unused_var,
    comp_missing_return,
    comp_deref_non_ptr,
};

pub const Error = struct {
    kind: ErrorKind,
    line: usize,
    col: usize,
    msg_len: usize,
    msg: [128]u8,
    hint_len: usize,
    hint: [128]u8,
};

pub const MAX_ERRORS = 64;

pub const ErrorList = struct {
    errors: [MAX_ERRORS]Error,
    count: usize,
    source: [*]const u8,
    source_len: usize,

    pub fn init(source: [*]const u8, source_len: usize) ErrorList {
        return ErrorList{
            .errors = undefined,
            .count = 0,
            .source = source,
            .source_len = source_len,
        };
    }

    pub fn hasErrors(self: *const ErrorList) bool {
        return self.count > 0;
    }

    pub fn add(self: *ErrorList, kind: ErrorKind, msg: []const u8, line: usize, col: usize, hint: []const u8) void {
        if (self.count >= MAX_ERRORS) return;
        const e = &self.errors[self.count];
        e.kind = kind;
        e.line = line;
        e.col = col;
        e.msg_len = @min(msg.len, 128);
        var i: usize = 0;
        while (i < e.msg_len) : (i += 1) e.msg[i] = msg[i];
        e.hint_len = @min(hint.len, 128);
        i = 0;
        while (i < e.hint_len) : (i += 1) e.hint[i] = hint[i];
        self.count += 1;
    }

    pub fn printAll(self: *const ErrorList) void {
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            self.printError(i);
        }
        if (self.count > 0) {
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            const prefix = "\x1b[31m";
            len = copyStr(prefix, &buf, 0);
            len += copyStr("error: compilation failed with ", &buf, len);
            len += fmtU32(@as(u32, @intCast(self.count)), &buf, len);
            len += copyStr(" error(s)", &buf, len);
            len += copyStr("\x1b[0m\n", &buf, len);
            _ = sys.write(2, &buf, len);
        }
    }

    fn printError(self: *const ErrorList, idx: usize) void {
        const e = &self.errors[idx];
        var buf: [512]u8 = undefined;
        var len: usize = 0;

        len += copyStr("\x1b[1;31merror\x1b[0m\x1b[1m", &buf, len);
        len += copyStr(" [", &buf, len);
        len += fmtU32(@as(u32, @intCast(e.line)), &buf, len);
        len += copyStr(":", &buf, len);
        len += fmtU32(@as(u32, @intCast(e.col)), &buf, len);
        len += copyStr("]: ", &buf, len);
        len += copyStr(e.msg[0..e.msg_len], &buf, len);
        len += copyStr("\x1b[0m\n", &buf, len);

        if (e.hint_len > 0) {
            len += copyStr("  \x1b[2m", &buf, len);
            len += copyStr(e.hint[0..e.hint_len], &buf, len);
            len += copyStr("\x1b[0m\n", &buf, len);
        }

        // Print source line with caret
        const line_start = findLineStart(self.source, self.source_len, e.line);
        const line_end = findLineEnd(self.source, self.source_len, line_start);
        if (line_end > line_start) {
            len += copyStr("  \x1b[36m|\x1b[0m ", &buf, len);
            var j: usize = line_start;
            while (j < line_end) : (j += 1) {
                if (len < buf.len - 1) {
                    buf[len] = self.source[j];
                    len += 1;
                }
            }
            len += copyStr("\n  \x1b[36m|\x1b[0m ", &buf, len);
            var k: usize = 0;
            while (k < e.col - 1) : (k += 1) {
                if (len < buf.len - 1) { buf[len] = ' '; len += 1; }
            }
            len += copyStr("\x1b[31m^\x1b[0m\n", &buf, len);
        }

        _ = sys.write(2, &buf, len);
    }

    pub fn printSummary(self: *const ErrorList) void {
        if (self.count > 0) {
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            len += copyStr("\x1b[31mcompilation failed (", &buf, len);
            len += fmtU32(@as(u32, @intCast(self.count)), &buf, len);
            len += copyStr(" errors)\x1b[0m\n", &buf, len);
            _ = sys.write(2, &buf, len);
        }
    }
};

fn findLineStart(src: [*]const u8, len: usize, line: usize) usize {
    var line_num: usize = 1;
    var i: usize = 0;
    while (i < len and line_num < line) : (i += 1) {
        if (src[i] == '\n') line_num += 1;
    }
    return i;
}

fn findLineEnd(src: [*]const u8, len: usize, start: usize) usize {
    var i: usize = start;
    while (i < len and src[i] != '\n') : (i += 1) {}
    return i;
}

fn copyStr(s: []const u8, buf: []u8, pos: usize) usize {
    var i: usize = 0;
    while (i < s.len and pos + i < buf.len) : (i += 1) {
        buf[pos + i] = s[i];
    }
    return s.len;
}

fn fmtU32(val: u32, buf: []u8, pos: usize) usize {
    var tmp: [16]u8 = undefined;
    var i: usize = 0;
    var n = val;
    if (n == 0) {
        if (pos < buf.len) buf[pos] = '0';
        return 1;
    }
    while (n > 0) : (n /= 10) {
        tmp[i] = @as(u8, @intCast(n % 10)) + '0';
        i += 1;
    }
    var j: usize = 0;
    while (j < i) : (j += 1) {
        if (pos + j < buf.len) buf[pos + j] = tmp[i - 1 - j];
    }
    return i;
}
