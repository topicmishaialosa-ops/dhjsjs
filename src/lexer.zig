const utils = @import("utils.zig");
const errors_mod = @import("errors.zig");

pub const TokenKind = enum(u8) {
    identifier,
    integer,
    string,
    keyword,
    symbol,
    eof,
    invalid,
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
    errs: *errors_mod.ErrorList,

    pub fn init(source: [*]const u8, len: usize, errs: *errors_mod.ErrorList) Lexer {
        return Lexer{ .source = source, .len = len, .pos = 0, .line = 1, .col = 1, .errs = errs };
    }

    pub fn initSlice(source: []const u8, errs: *errors_mod.ErrorList) Lexer {
        return init(source.ptr, source.len, errs);
    }

    pub fn next(self: *Lexer) Token {
        self.skipWhitespace();
        if (self.pos >= self.len) return Token{ .kind = .eof, .start = "", .len = 0, .line = self.line, .col = self.col };

        const start_line = self.line;
        const start_col = self.col;
        const ch = self.source[self.pos];

        if (utils.isAlpha(ch) or ch == '_') return self.readWord(start_line, start_col);
        if (utils.isDigit(ch)) return self.readNumber(start_line, start_col);
        if (ch == '"') return self.readString(start_line, start_col);
        if (ch == '(' or ch == ')' or ch == '{' or ch == '}' or ch == ';' or ch == ',') return self.readSingle(start_line, start_col);
        if (ch == '+' or ch == '-' or ch == '*' or ch == '/' or ch == '%') return self.readSingle(start_line, start_col);
        if (ch == '=' or ch == '!' or ch == '<' or ch == '>' or ch == '&' or ch == '|' or ch == '^' or ch == '~') return self.readSymbol(start_line, start_col);
        if (ch == '[' or ch == ']') return self.readSingle(start_line, start_col);
        if (ch == '.') return self.readSingle(start_line, start_col);
        return self.readInvalid(start_line, start_col);
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
            } else if (ch == '/' and self.pos + 1 < self.len and self.source[self.pos + 1] == '*') {
                self.pos += 2;
                self.col += 2;
                while (self.pos + 1 < self.len and !(self.source[self.pos] == '*' and self.source[self.pos + 1] == '/')) {
                    if (self.source[self.pos] == '\n') { self.line += 1; self.col = 1; }
                    else { self.col += 1; }
                    self.pos += 1;
                }
                if (self.pos + 1 < self.len) { self.pos += 2; self.col += 2; }
                else {
                    self.errs.add(.lex_unterminated_block_comment, "unterminated block comment", self.line, self.col, "add '*/' to close the comment");
                }
            } else {
                break;
            }
        }
    }

    fn readSingle(self: *Lexer, line: usize, col: usize) Token {
        const start = self.pos;
        self.pos += 1;
        self.col += 1;
        return Token{ .kind = .symbol, .start = self.source + start, .len = 1, .line = line, .col = col };
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
        if (self.pos + 2 < self.len and self.source[self.pos] == '0' and self.source[self.pos + 1] == 'x') {
            self.pos += 2;
            self.col += 2;
            while (self.pos < self.len and utils.isHexDigit(self.source[self.pos])) {
                self.pos += 1;
                self.col += 1;
            }
        } else {
            while (self.pos < self.len and utils.isDigit(self.source[self.pos])) {
                self.pos += 1;
                self.col += 1;
            }
        }
        if (self.pos < self.len and utils.isAlpha(self.source[self.pos])) {
            while (self.pos < self.len and utils.isAlphaNum(self.source[self.pos])) {
                self.pos += 1;
                self.col += 1;
            }
            self.errs.add(.lex_invalid_char, "invalid number literal", line, col, "remove non-digit characters from the number");
        }
        return Token{ .kind = .integer, .start = self.source + start, .len = self.pos - start, .line = line, .col = col };
    }

    fn readString(self: *Lexer, line: usize, col: usize) Token {
        self.pos += 1;
        self.col += 1;
        const start = self.pos;
        while (self.pos < self.len and self.source[self.pos] != '"') {
            if (self.source[self.pos] == '\\') {
                if (self.pos + 1 < self.len) { self.pos += 2; self.col += 2; }
                else { self.pos += 1; self.col += 1; break; }
            } else {
                if (self.source[self.pos] == '\n') { self.line += 1; self.col = 1; }
                else { self.col += 1; }
                self.pos += 1;
            }
        }
        const tok: Token = if (self.pos >= self.len) blk: {
            self.errs.add(.lex_unterminated_string, "unterminated string literal", line, col, "add a closing double quote '\"' at the end of the string");
            break :blk Token{ .kind = .invalid, .start = self.source + start, .len = self.pos - start, .line = line, .col = col };
        } else blk: {
            const t = Token{ .kind = .string, .start = self.source + start, .len = self.pos - start, .line = line, .col = col };
            self.pos += 1;
            self.col += 1;
            break :blk t;
        };
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

    fn readInvalid(self: *Lexer, line: usize, col: usize) Token {
        const start = self.pos;
        self.pos += 1;
        self.col += 1;
        self.errs.add(.lex_invalid_char, "invalid character in source", line, col, "remove this character or replace it with a valid one");
        return Token{ .kind = .invalid, .start = self.source + start, .len = 1, .line = line, .col = col };
    }
};

fn isKeyword(ptr: [*]const u8, len: usize) bool {
    const words = [_][]const u8{
        "fn", "hui", "if", "uebok", "return", "while", "struct", "sizeof",
        "activity", "compose", "state", "viewmodel",
        "true", "false", "null", "int", "string", "bool", "void",
        "break", "continue", "const",
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
