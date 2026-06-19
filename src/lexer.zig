const utils = @import("utils.zig");

pub const TokenKind = enum(u8) {
    identifier,
    integer,
    string,
    keyword,
    symbol,
    eof,
};

pub const Token = struct {
    kind: TokenKind,
    start: [*]const u8,
    len: usize,
    line: usize,
    col: usize,
};

pub const Lexer = struct {
    source: [*]const u8,
    len: usize,
    pos: usize,
    line: usize,
    col: usize,

    pub fn init(source: [*]const u8, len: usize) Lexer {
        return Lexer{ .source = source, .len = len, .pos = 0, .line = 1, .col = 1 };
    }

    pub fn initSlice(source: []const u8) Lexer {
        return init(source.ptr, source.len);
    }

    pub fn next(self: *Lexer) Token {
        self.skipWhitespace();
        if (self.pos >= self.len) return Token{ .kind = .eof, .start = "", .len = 0, .line = self.line, .col = self.col };

        const start_line = self.line;
        const start_col = self.col;
        const ch = self.source[self.pos];

        if (utils.isAlpha(ch)) return self.readWord(start_line, start_col);
        if (utils.isDigit(ch)) return self.readNumber(start_line, start_col);
        if (ch == '"') return self.readString(start_line, start_col);
        return self.readSymbol(start_line, start_col);
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.len) {
            const ch = self.source[self.pos];
            if (ch == ' ' or ch == '\t' or ch == '\r') {
                self.pos += 1;
                self.col += 1;
            } else if (ch == '\n') {
                self.pos += 1;
                self.line += 1;
                self.col = 1;
            } else if (ch == '/' and self.pos + 1 < self.len and self.source[self.pos + 1] == '/') {
                while (self.pos < self.len and self.source[self.pos] != '\n') {
                    self.pos += 1;
                    self.col += 1;
                }
            } else {
                break;
            }
        }
    }

    fn readWord(self: *Lexer, line: usize, col: usize) Token {
        const start = self.pos;
        while (self.pos < self.len and utils.isAlphaNum(self.source[self.pos])) {
            self.pos += 1;
            self.col += 1;
        }
        const tok = Token{ .kind = .keyword, .start = self.source + start, .len = self.pos - start, .line = line, .col = col };
        if (!isKeyword(self.source + start, self.pos - start)) {
            return Token{ .kind = .identifier, .start = self.source + start, .len = self.pos - start, .line = line, .col = col };
        }
        return tok;
    }

    fn readNumber(self: *Lexer, line: usize, col: usize) Token {
        const start = self.pos;
        while (self.pos < self.len and utils.isDigit(self.source[self.pos])) {
            self.pos += 1;
            self.col += 1;
        }
        return Token{ .kind = .integer, .start = self.source + start, .len = self.pos - start, .line = line, .col = col };
    }

    fn readString(self: *Lexer, line: usize, col: usize) Token {
        self.pos += 1;
        self.col += 1;
        const start = self.pos;
        while (self.pos < self.len and self.source[self.pos] != '"') {
            if (self.source[self.pos] == '\\') { self.pos += 2; self.col += 2; }
            else { self.pos += 1; self.col += 1; }
        }
        const tok = Token{ .kind = .string, .start = self.source + start, .len = self.pos - start, .line = line, .col = col };
        if (self.pos < self.len) { self.pos += 1; self.col += 1; }
        return tok;
    }

    fn readSymbol(self: *Lexer, line: usize, col: usize) Token {
        const start = self.pos;
        const ch = self.source[self.pos];
        var len: usize = 1;
        if (self.pos + 1 < self.len) {
            const nch = self.source[self.pos + 1];
            if ((ch == '=' and nch == '=') or
                (ch == '!' and nch == '=') or
                (ch == '<' and nch == '=') or
                (ch == '>' and nch == '=') or
                (ch == '<' and nch == '<') or
                (ch == '>' and nch == '>') or
                (ch == '&' and nch == '&') or
                (ch == '|' and nch == '|'))
            { len = 2; }
        }
        self.pos += len;
        self.col += len;
        return Token{ .kind = .symbol, .start = self.source + start, .len = len, .line = line, .col = col };
    }
};

fn isKeyword(ptr: [*]const u8, len: usize) bool {
    const words = [_][]const u8{
        "fn", "hui", "if", "uebok", "return", "while", "struct", "sizeof",
        "activity", "compose", "state", "viewmodel",
        "true", "false", "null", "int", "string", "bool", "void",
    };
    for (words) |word| {
        if (len == word.len) {
            var match = true;
            var i: usize = 0;
            while (i < len) : (i += 1) { if (ptr[i] != word[i]) { match = false; break; } }
            if (match) return true;
        }
    }
    return false;
}
