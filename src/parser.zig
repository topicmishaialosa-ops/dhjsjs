const lexer_mod = @import("lexer.zig");
const errors_mod = @import("errors.zig");

pub const NodeKind = enum(u8) {
    program,
    fn_decl,
    activity_decl,
    compose_decl,
    state_decl,
    viewmodel_decl,
    struct_decl,
    var_decl,
    struct_var_decl,
    ret_stmt,
    if_stmt,
    while_stmt,
    break_stmt,
    continue_stmt,
    block,
    call,
    assign,
    ident,
    int_lit,
    str_lit,
    binary_op,
    unary_op,
    field_access,
    array_index,
    addr_of,
    deref,
    sizeof_expr,
    store,
};

pub const NodeIdx = i32;
pub const NO_NODE: NodeIdx = -1;
pub const MAX_NODES = 2048;

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |c, i| if (c != b[i]) return false;
    return true;
}

pub const AstNode = struct {
    kind: NodeKind,
    name_start: [*]const u8,
    name_len: usize,
    val_start: [*]const u8,
    val_len: usize,
    first_child: NodeIdx,
    next_sibling: NodeIdx,
    line: usize,
    col: usize,
};

fn tokStrPtr(tok: lexer_mod.Token) struct { ptr: [*]const u8, len: usize } {
    return .{ .ptr = tok.start, .len = tok.len };
}

pub const Parser = struct {
    lex: lexer_mod.Lexer,
    tok: lexer_mod.Token,
    pool: [MAX_NODES]AstNode,
    node_count: usize,
    err: bool,
    strbuf: [2048]u8,
    strbuf_off: usize,
    errs: *errors_mod.ErrorList,
    fn_names: [32][]const u8,
    fn_count: usize,

    pub fn init(source: [*]const u8, len: usize, errs: *errors_mod.ErrorList) Parser {
        var p = Parser{
            .lex = lexer_mod.Lexer.init(source, len, errs),
            .tok = undefined,
            .pool = undefined,
            .node_count = 0,
            .err = false,
            .strbuf = undefined,
            .strbuf_off = 0,
            .errs = errs,
            .fn_names = undefined,
            .fn_count = 0,
        };
        p.tok = p.lex.next();
        return p;
    }

    fn allocNode(self: *Parser, kind: NodeKind, name_start: [*]const u8, name_len: usize, val_start: [*]const u8, val_len: usize, line: usize, col: usize) NodeIdx {
        if (self.node_count >= MAX_NODES) {
            self.errs.add(.parse_unexpected_eof, "too many nodes (limit 2048)", line, col, "reduce code complexity or split into multiple files");
            self.err = true;
            return 0;
        }
        const idx = @as(NodeIdx, @intCast(self.node_count));
        self.pool[@as(usize, @intCast(idx))] = AstNode{
            .kind = kind, .name_start = name_start, .name_len = name_len,
            .val_start = val_start, .val_len = val_len,
            .first_child = NO_NODE, .next_sibling = NO_NODE, .line = line, .col = col,
        };
        self.node_count += 1;
        return idx;
    }

    fn addChild(self: *Parser, parent: NodeIdx, child: NodeIdx) void {
        if (parent == NO_NODE or child == NO_NODE) return;
        if (self.pool[@intCast(parent)].first_child == NO_NODE) {
            self.pool[@intCast(parent)].first_child = child;
        } else {
            var last = self.pool[@intCast(parent)].first_child;
            while (self.pool[@intCast(last)].next_sibling != NO_NODE) {
                last = self.pool[@intCast(last)].next_sibling;
            }
            self.pool[@intCast(last)].next_sibling = child;
        }
    }

    fn eat(self: *Parser) void {
        if (self.tok.kind == .invalid) {
            self.tok = self.lex.next();
            return;
        }
        self.tok = self.lex.next();
    }

    fn tokStr(self: *Parser) struct { ptr: [*]const u8, len: usize } {
        return .{ .ptr = self.tok.start, .len = self.tok.len };
    }

    fn tokMatch(self: *Parser, s: []const u8) bool {
        if (self.tok.len != s.len) return false;
        for (s, 0..) |c, i| if (self.tok.start[i] != c) return false;
        return true;
    }

    fn expect(self: *Parser, s: []const u8) bool {
        if (self.tokMatch(s)) { self.eat(); return true; }
        const msg_buf = self.formatExpectMsg(s);
        self.errs.add(.parse_unexpected_token, msg_buf[0..], self.tok.line, self.tok.col, "add the expected token here");
        self.err = true;
        return false;
    }

    fn formatExpectMsg(self: *Parser, expected: []const u8) []const u8 {
        const buf = self.strbuf[self.strbuf_off..];
        const prefix = "expected '";
        var i: usize = 0;
        while (i < prefix.len and i < buf.len) : (i += 1) buf[i] = prefix[i];
        var j: usize = 0;
        while (j < expected.len and i + j < buf.len) : (j += 1) buf[i + j] = expected[j];
        i += j;
        if (i < buf.len) { buf[i] = '\''; i += 1; }
        const tok_s = tokStrPtr(self.tok);
        const got = " but got '";
        j = 0;
        while (j < got.len and i + j < buf.len) : (j += 1) buf[i + j] = got[j];
        i += j;
        j = 0;
        while (j < tok_s.len and i + j < buf.len) : (j += 1) buf[i + j] = tok_s.ptr[j];
        i += j;
        if (i < buf.len) { buf[i] = '\''; i += 1; }
        const result = self.strbuf[self.strbuf_off..i];
        self.strbuf_off = i;
        return result;
    }

    // --- Top-Level ---

    pub fn parse(self: *Parser) NodeIdx {
        const prog = self.allocNode(.program, "", 0, "", 0, 1, 1);
        while (self.tok.kind != .eof and !self.err) {
            if (self.tok.kind == .keyword and self.tokMatch("fn")) {
                self.addChild(prog, self.parseFnDecl());
            } else if (self.tok.kind == .keyword and self.tokMatch("struct")) {
                self.addChild(prog, self.parseStructDecl());
            } else if (self.tok.kind == .keyword and self.tokMatch("activity")) {
                self.addChild(prog, self.parseActivityDecl());
            } else if (self.tok.kind == .keyword and self.tokMatch("compose")) {
                self.addChild(prog, self.parseComposeDecl());
            } else if (self.tok.kind == .keyword and self.tokMatch("state")) {
                self.addChild(prog, self.parseStateDecl());
            } else if (self.tok.kind == .keyword and self.tokMatch("viewmodel")) {
                self.addChild(prog, self.parseViewmodelDecl());
            } else if (self.tok.kind == .keyword and self.tokMatch("hui")) {
                self.addChild(prog, self.parseVarDecl());
            } else if (self.tok.kind != .eof and self.tok.kind != .invalid) {
                self.errs.add(.parse_unexpected_token, "unexpected token at top level", self.tok.line, self.tok.col, "expected 'fn', 'struct', 'hui', or another top-level declaration");
                self.eat();
            } else if (self.tok.kind == .invalid) {
                self.eat();
            } else {
                break;
            }
        }
        if (self.tok.kind != .eof and !self.err) {
            if (!self.tokMatch(";")) {
                if (self.tok.kind == .eof) {
                    self.errs.add(.parse_unexpected_eof, "unexpected end of file after program body", self.tok.line, self.tok.col, "add a semicolon ';' to end the program");
                } else {
                    self.errs.add(.parse_missing_semicolon, "expected ';' at end of program", self.tok.line, self.tok.col, "add a semicolon ';' here");
                }
                self.err = true;
            } else {
                self.eat();
            }
        }
        return prog;
    }

    // --- Struct ---

    fn parseStructDecl(self: *Parser) NodeIdx {
        const line = self.tok.line;
        const col = self.tok.col;
        self.eat();
        const name = self.tokStr();
        self.eat();
        const n = self.allocNode(.struct_decl, name.ptr, name.len, "", 0, line, col);
        if (self.tokMatch("{")) {
            self.eat();
            while (!self.tokMatch("}") and self.tok.kind != .eof) {
                if (self.tok.kind == .keyword and self.tokMatch("hui")) {
                    self.addChild(n, self.parseVarDecl());
                } else { self.eat(); }
            }
            if (self.tokMatch("}")) self.eat();
        }
        if (self.tokMatch(";")) self.eat();
        return n;
    }

    // --- Function ---

    fn parseFnDecl(self: *Parser) NodeIdx {
        const line = self.tok.line;
        const col = self.tok.col;
        self.eat();
        if (self.tok.kind != .identifier and self.tok.kind != .keyword) {
            self.errs.add(.parse_expected_ident, "expected function name after 'fn'", self.tok.line, self.tok.col, "add a function name here (e.g. 'fn main() {')");
            self.err = true;
            return NO_NODE;
        }
        const name = self.tokStr();
        // Check duplicate function name
        var fi: usize = 0;
        while (fi < self.fn_count) : (fi += 1) {
            if (eq(name.ptr[0..name.len], self.fn_names[fi])) {
                const dup_buf = self.strbuf[self.strbuf_off..];
                const prefix = "duplicate function '";
                var i: usize = 0;
                while (i < prefix.len and i < dup_buf.len) : (i += 1) dup_buf[i] = prefix[i];
                var j: usize = 0;
                while (j < name.len and i + j < dup_buf.len) : (j += 1) dup_buf[i + j] = name.ptr[j];
                i += j;
                if (i < dup_buf.len) { dup_buf[i] = '\''; i += 1; }
                self.errs.add(.parse_duplicate_fn, dup_buf[0..i], self.tok.line, self.tok.col, "rename or remove the duplicate function");
                self.err = true;
            }
        }
        if (self.fn_count < 32) {
            self.fn_names[self.fn_count] = name.ptr[0..name.len];
            self.fn_count += 1;
        }
        self.eat();
        const n = self.allocNode(.fn_decl, name.ptr, name.len, "", 0, line, col);
        if (self.tokMatch("(")) {
            self.eat();
            while (!self.tokMatch(")") and self.tok.kind != .eof) {
                if (self.tok.kind == .keyword and (self.tokMatch("hui") or self.tokMatch("int") or self.tokMatch("string") or self.tokMatch("bool") or self.tokMatch("void"))) {
                    self.eat(); // skip type
                    if (self.tok.kind == .identifier or self.tok.kind == .keyword) self.eat(); // skip param name
                    if (self.tokMatch(",")) self.eat();
                } else {
                    self.errs.add(.parse_unexpected_token, "invalid parameter in function declaration", self.tok.line, self.tok.col, "parameters should be like 'int name' or 'string name'");
                    self.eat();
                }
            }
            if (self.tokMatch(")")) {
                self.eat();
            } else {
                self.errs.add(.parse_missing_close_paren, "expected ')' in function declaration", self.tok.line, self.tok.col, "add ')' to close parameter list");
                self.err = true;
            }
        } else {
            self.errs.add(.parse_unexpected_token, "expected '(' after function name", self.tok.line, self.tok.col, "add '(' and ')' with optional parameters");
            self.err = true;
        }
        // Skip return type annotation
        while (!self.tokMatch("{") and !self.tokMatch(";") and self.tok.kind != .eof) { self.eat(); }
        if (self.tokMatch("{")) {
            self.eat();
            const block = self.parseBlock();
            self.addChild(n, block);
        } else if (self.tokMatch(";")) {
            self.eat();
        } else {
            self.errs.add(.parse_missing_open_brace, "expected '{' for function body", self.tok.line, self.tok.col, "add '{' to start the function body");
            self.err = true;
        }
        return n;
    }

    fn parseActivityDecl(self: *Parser) NodeIdx {
        const line = self.tok.line; const col = self.tok.col;
        self.eat(); const name = self.tokStr(); self.eat();
        const n = self.allocNode(.activity_decl, name.ptr, name.len, "", 0, line, col);
        if (self.tokMatch("{")) { self.eat(); const b = self.parseBlock(); self.addChild(n, b); }
        return n;
    }

    fn parseComposeDecl(self: *Parser) NodeIdx {
        const line = self.tok.line; const col = self.tok.col;
        self.eat(); const name = self.tokStr(); self.eat();
        const n = self.allocNode(.compose_decl, name.ptr, name.len, "", 0, line, col);
        if (self.tokMatch("{")) { self.eat(); const b = self.parseBlock(); self.addChild(n, b); }
        return n;
    }

    fn parseStateDecl(self: *Parser) NodeIdx {
        const line = self.tok.line; const col = self.tok.col;
        self.eat();
        if (self.tok.kind == .identifier or self.tok.kind == .keyword) {
            const name = self.tokStr(); self.eat();
            const n = self.allocNode(.state_decl, name.ptr, name.len, "", 0, line, col);
            if (self.tokMatch("=")) { self.eat(); const v = self.tokStr(); self.eat(); _ = v; }
            if (self.tokMatch(";")) self.eat();
            return n;
        }
        return NO_NODE;
    }

    fn parseViewmodelDecl(self: *Parser) NodeIdx {
        const line = self.tok.line; const col = self.tok.col;
        self.eat(); const name = self.tokStr(); self.eat();
        const n = self.allocNode(.viewmodel_decl, name.ptr, name.len, "", 0, line, col);
        if (self.tokMatch("{")) { self.eat(); const b = self.parseBlock(); self.addChild(n, b); }
        return n;
    }

    // --- Statements ---

    fn parseBlock(self: *Parser) NodeIdx {
        const line = self.tok.line; const col = self.tok.col;
        const n = self.allocNode(.block, "", 0, "", 0, line, col);
        while (!self.tokMatch("}") and self.tok.kind != .eof and !self.err) {
            self.addChild(n, self.parseStatement());
        }
        if (self.tokMatch("}")) {
            self.eat();
        } else if (self.tok.kind == .eof) {
            self.errs.add(.parse_missing_close_brace, "expected '}' to close block, got end of file", self.tok.line, self.tok.col, "add matching '}' for this block");
            self.err = true;
        }
        return n;
    }

    fn parseStatement(self: *Parser) NodeIdx {
        if (self.tok.kind == .keyword and self.tokMatch("hui")) {
            return self.parseVarDecl();
        }
        if (self.tok.kind == .keyword and self.tokMatch("const")) {
            return self.parseVarDecl();
        }
        if (self.tok.kind == .keyword and self.tokMatch("return")) {
            return self.parseReturnStmt();
        }
        if (self.tok.kind == .keyword and self.tokMatch("if")) {
            return self.parseIfStmt();
        }
        if (self.tok.kind == .keyword and self.tokMatch("while")) {
            return self.parseWhileStmt();
        }
        if (self.tok.kind == .keyword and self.tokMatch("break")) {
            self.eat();
            if (self.tokMatch(";")) self.eat();
            return self.allocNode(.break_stmt, "", 0, "", 0, self.tok.line, self.tok.col);
        }
        if (self.tok.kind == .keyword and self.tokMatch("continue")) {
            self.eat();
            if (self.tokMatch(";")) self.eat();
            return self.allocNode(.continue_stmt, "", 0, "", 0, self.tok.line, self.tok.col);
        }
        if (self.tok.kind == .keyword and self.tokMatch("struct")) {
            return self.parseStructVarDecl();
        }
        if (self.tokMatch("{")) {
            self.eat();
            const n = self.parseBlock();
            return n;
        }
        // Parse expression statement (assign, call, etc.)
        if (self.tok.kind == .eof or self.tok.kind == .invalid) {
            self.errs.add(.parse_unexpected_eof, "expected statement, got end of file", self.tok.line, self.tok.col, "add a statement or remove extra content");
            self.err = true;
            return NO_NODE;
        }
        if (self.tokMatch("}")) {
            self.errs.add(.parse_unexpected_token, "unexpected '}' - no matching block to close", self.tok.line, self.tok.col, "remove this extra '}'");
            self.eat();
            self.err = true;
            return NO_NODE;
        }
        return self.parseExprStmt();
    }

    fn parseVarDecl(self: *Parser) NodeIdx {
        const line = self.tok.line; const col = self.tok.col;
        self.eat();
        if (self.tok.kind != .identifier and self.tok.kind != .keyword) {
            self.errs.add(.parse_expected_ident, "expected variable name after 'hui'", self.tok.line, self.tok.col, "add a name for the variable (e.g. 'hui x = 42')");
            self.err = true;
            return NO_NODE;
        }
        const name = self.tokStr();
        self.eat();
        var arr_size: NodeIdx = NO_NODE;
        if (self.tokMatch("[")) {
            self.eat();
            arr_size = self.parseExpr(0);
            if (!self.tokMatch("]")) {
                self.errs.add(.parse_unexpected_token, "expected ']' after array size", self.tok.line, self.tok.col, "add ']' to close array declaration");
                self.err = true;
            } else {
                self.eat();
            }
        }
    const sz_str = if (arr_size != NO_NODE) self.pool[@as(usize, @intCast(arr_size))].val_start else "";
    const sz_len = if (arr_size != NO_NODE) self.pool[@as(usize, @intCast(arr_size))].val_len else @as(usize, 0);
    const n = self.allocNode(.var_decl, name.ptr, name.len, sz_str, sz_len, line, col);
    if (self.tokMatch("=")) {
        self.eat();
        const expr = self.parseExpr(0);
        if (expr != NO_NODE) self.addChild(n, expr);
    }
    if (self.tokMatch(";")) {
        self.eat();
    } else if (self.tok.kind != .eof) {
        self.errs.add(.parse_missing_semicolon, "expected ';' after variable declaration", self.tok.line, self.tok.col, "add ';' at the end of the declaration");
        self.err = true;
    }
    return n;
    }

    fn parseStructVarDecl(self: *Parser) NodeIdx {
        const line = self.tok.line; const col = self.tok.col;
        self.eat(); // skip 'struct'
        const type_name = self.tokStr(); // struct type name
        self.eat();
        const var_name = self.tokStr(); // variable name
        self.eat();
        const n = self.allocNode(.struct_var_decl, type_name.ptr, type_name.len, var_name.ptr, var_name.len, line, col);
        if (self.tokMatch(";")) self.eat();
        return n;
    }

    fn parseReturnStmt(self: *Parser) NodeIdx {
        const line = self.tok.line; const col = self.tok.col;
        self.eat();
        const n = self.allocNode(.ret_stmt, "", 0, "", 0, line, col);
        if (!self.tokMatch(";") and self.tok.kind != .eof) {
            const expr = self.parseExpr(0);
            if (expr != NO_NODE) self.addChild(n, expr);
        }
        if (self.tokMatch(";")) self.eat();
        return n;
    }

    fn parseIfStmt(self: *Parser) NodeIdx {
        const line = self.tok.line; const col = self.tok.col;
        self.eat();
        var had_paren = false;
        const n = self.allocNode(.if_stmt, "", 0, "", 0, line, col);
        if (self.tokMatch("(")) { self.eat(); had_paren = true; }
        const cond = self.parseExpr(0);
        if (cond == NO_NODE) {
            self.errs.add(.parse_expected_expr, "expected condition in 'if' statement", self.tok.line, self.tok.col, "add a comparison or boolean expression (e.g. 'x > 0')");
            self.err = true;
        } else {
            self.addChild(n, cond);
        }
        if (had_paren) {
            if (self.tokMatch(")")) { self.eat(); }
            else {
                self.errs.add(.parse_missing_close_paren, "expected ')' to close condition", self.tok.line, self.tok.col, "add ')' to close the condition");
                self.err = true;
            }
        }
        if (self.tokMatch("{")) {
            self.eat(); const block = self.parseBlock(); self.addChild(n, block);
        } else if (!self.err) {
            self.errs.add(.parse_missing_open_brace, "expected '{' for if body", self.tok.line, self.tok.col, "add '{' and '}' around the if body");
            self.err = true;
        }
        if (self.tokMatch("uebok")) {
            self.eat();
            if (self.tokMatch("{")) { self.eat(); const block = self.parseBlock(); self.addChild(n, block); }
            else {
                self.errs.add(.parse_missing_open_brace, "expected '{' for else body", self.tok.line, self.tok.col, "add '{' and '}' around the else body");
                self.err = true;
            }
        }
        return n;
    }

    fn parseWhileStmt(self: *Parser) NodeIdx {
        const line = self.tok.line; const col = self.tok.col;
        self.eat();
        var had_paren = false;
        const n = self.allocNode(.while_stmt, "while", 5, "", 0, line, col);
        if (self.tokMatch("(")) { self.eat(); had_paren = true; }
        const cond = self.parseExpr(0);
        if (cond == NO_NODE) {
            self.errs.add(.parse_expected_expr, "expected condition in 'while' statement", self.tok.line, self.tok.col, "add a comparison or boolean expression (e.g. 'x < 10')");
            self.err = true;
        } else {
            self.addChild(n, cond);
        }
        if (had_paren) {
            if (self.tokMatch(")")) { self.eat(); }
            else {
                self.errs.add(.parse_missing_close_paren, "expected ')' to close condition", self.tok.line, self.tok.col, "add ')' to close the condition");
                self.err = true;
            }
        }
        if (self.tokMatch("{")) { self.eat(); const block = self.parseBlock(); self.addChild(n, block); }
        else if (!self.err) {
            self.errs.add(.parse_missing_open_brace, "expected '{' for while body", self.tok.line, self.tok.col, "add '{' and '}' around the while body");
            self.err = true;
        }
        return n;
    }

    // --- Expression statements ---

    fn parseExprStmt(self: *Parser) NodeIdx {
        const n = self.parseExpr(0);
        if (n != NO_NODE and self.tokMatch("=")) {
            self.eat();
            const store = self.allocNode(.store, "", 0, "", 0, self.tok.line, self.tok.col);
            self.addChild(store, n);
            const val = self.parseExpr(0);
            if (val != NO_NODE) self.addChild(store, val);
            if (self.tokMatch(";")) self.eat();
            return store;
        }
        if (self.tokMatch(";")) self.eat();
        return n;
    }

    // --- Expressions ---

    fn opPrecedence(self: *Parser) u8 {
        if (self.tok.kind != .symbol) return 0;
        if (self.tokMatch("||")) return 2;
        if (self.tokMatch("&&")) return 3;
        if (self.tokMatch("|")) return 4;
        if (self.tokMatch("^")) return 5;
        if (self.tokMatch("&")) return 6;
        if (self.tokMatch("==") or self.tokMatch("!=") or self.tokMatch("<") or self.tokMatch(">") or self.tokMatch("<=") or self.tokMatch(">=")) return 7;
        if (self.tokMatch("<<") or self.tokMatch(">>")) return 8;
        if (self.tokMatch("+") or self.tokMatch("-")) return 9;
        if (self.tokMatch("*") or self.tokMatch("/") or self.tokMatch("%")) return 10;
        if (self.tokMatch("[")) return 11;
        if (self.tokMatch(".")) return 12;
        return 0;
    }

    pub fn parseExpr(self: *Parser, min_prec: u8) NodeIdx {
        var left = self.parsePrimary();
        if (left == NO_NODE) return NO_NODE;

        while (true) {
            const prec = self.opPrecedence();
            if (prec == 0 or prec < min_prec) break;

            if (self.tokMatch("[")) {
                self.eat();
                const idx = self.parseExpr(0);
                const n = self.allocNode(.array_index, "", 0, "", 0, self.tok.line, self.tok.col);
                self.addChild(n, left);
                if (idx != NO_NODE) self.addChild(n, idx);
                left = n;
                if (self.tokMatch("]")) self.eat();
                continue;
            }

            if (self.tokMatch(".")) {
                self.eat();
                const field = self.tokStr();
                self.eat();
                const n = self.allocNode(.field_access, field.ptr, field.len, "", 0, self.tok.line, self.tok.col);
                self.addChild(n, left);
                left = n;
                continue;
            }

            const op = self.tokStr();
            self.eat();
            const right = self.parseExpr(prec + 1);
            if (eq(op.ptr[0..op.len], "+") and left != NO_NODE and right != NO_NODE) {
                const nl = &self.pool[@as(usize, @intCast(left))];
                const nr = &self.pool[@as(usize, @intCast(right))];
                if (nl.kind == .str_lit and nr.kind == .str_lit) {
                    const total = nl.val_len + nr.val_len;
                    const concat_start = self.strbuf_off;
                    if (concat_start + total < self.strbuf.len) {
                        @memcpy(self.strbuf[concat_start..][0..nl.val_len], nl.val_start[0..nl.val_len]);
                        @memcpy(self.strbuf[concat_start + nl.val_len ..][0..nr.val_len], nr.val_start[0..nr.val_len]);
                        self.strbuf_off += total;
                        left = self.allocNode(.str_lit, "", 0, self.strbuf[concat_start..].ptr, total, self.tok.line, self.tok.col);
                    } else {
                        const n = self.allocNode(.binary_op, op.ptr, op.len, "", 0, self.tok.line, self.tok.col);
                        if (left != NO_NODE) self.addChild(n, left);
                        if (right != NO_NODE) self.addChild(n, right);
                        left = n;
                    }
                } else {
                    const n = self.allocNode(.binary_op, op.ptr, op.len, "", 0, self.tok.line, self.tok.col);
                    if (left != NO_NODE) self.addChild(n, left);
                    if (right != NO_NODE) self.addChild(n, right);
                    left = n;
                }
            } else {
                const n = self.allocNode(.binary_op, op.ptr, op.len, "", 0, self.tok.line, self.tok.col);
                if (left != NO_NODE) self.addChild(n, left);
                if (right != NO_NODE) self.addChild(n, right);
                left = n;
            }
        }
        return left;
    }

    fn unescape(self: *Parser, src: [*]const u8, len: usize) []const u8 {
        const start = self.strbuf_off;
        var i: usize = 0;
        while (i < len and self.strbuf_off < self.strbuf.len) {
            if (src[i] == '\\' and i + 1 < len) {
                i += 1;
                const c = src[i];
                if (c == 'n') { self.strbuf[self.strbuf_off] = 0x0A; }
                else if (c == 'r') { self.strbuf[self.strbuf_off] = 0x0D; }
                else if (c == 't') { self.strbuf[self.strbuf_off] = 0x09; }
                else if (c == '\\') { self.strbuf[self.strbuf_off] = 0x5C; }
                else if (c == '"') { self.strbuf[self.strbuf_off] = 0x22; }
                else { self.strbuf[self.strbuf_off] = '\\'; i -= 1; }
                self.strbuf_off += 1;
            } else {
                self.strbuf[self.strbuf_off] = src[i];
                self.strbuf_off += 1;
            }
            i += 1;
        }
        return self.strbuf[start..self.strbuf_off];
    }

    fn parsePrimary(self: *Parser) NodeIdx {
        const line = self.tok.line; const col = self.tok.col;

        // sizeof
        if (self.tok.kind == .keyword and self.tokMatch("sizeof")) {
            self.eat();
            if (self.tokMatch("(")) { self.eat(); }
            const expr = self.parseExpr(0);
            if (self.tokMatch(")")) { self.eat(); }
            const n = self.allocNode(.sizeof_expr, "", 0, "", 0, line, col);
            if (expr != NO_NODE) self.addChild(n, expr);
            return n;
        }

        // Address-of: &expr
        if (self.tokMatch("&")) {
            self.eat();
            const expr = self.parsePrimary();
            const n = self.allocNode(.addr_of, "", 0, "", 0, line, col);
            if (expr != NO_NODE) self.addChild(n, expr);
            return n;
        }

        // Dereference: *expr
        if (self.tokMatch("*")) {
            self.eat();
            const expr = self.parsePrimary();
            const n = self.allocNode(.deref, "", 0, "", 0, line, col);
            if (expr != NO_NODE) self.addChild(n, expr);
            return n;
        }

        // Unary operators: ! - 
        if (self.tokMatch("!")) {
            self.eat();
            const operand = self.parsePrimary();
            const n = self.allocNode(.unary_op, "!", 1, "", 0, line, col);
            if (operand != NO_NODE) self.addChild(n, operand);
            return n;
        }
        if (self.tokMatch("-")) {
            self.eat();
            const operand = self.parsePrimary();
            const n = self.allocNode(.unary_op, "-", 1, "", 0, line, col);
            if (operand != NO_NODE) self.addChild(n, operand);
            return n;
        }

        // Parenthesized expression
        if (self.tokMatch("(")) {
            self.eat();
            const expr = self.parseExpr(0);
            if (!self.tokMatch(")")) {
                self.errs.add(.parse_missing_close_paren, "expected ')' to close expression", self.tok.line, self.tok.col, "add ')' here");
                self.err = true;
            } else {
                self.eat();
            }
            return expr;
        }

        // Integer literal
        if (self.tok.kind == .integer) {
            const v = self.tokStr();
            self.eat();
            return self.allocNode(.int_lit, "", 0, v.ptr, v.len, line, col);
        }

        // String literal (with escape sequence processing)
        if (self.tok.kind == .string) {
            const v = self.tokStr();
            self.eat();
            const unesc = self.unescape(v.ptr, v.len);
            return self.allocNode(.str_lit, "", 0, unesc.ptr, unesc.len, line, col);
        }

        // Identifier
        if (self.tok.kind == .identifier or self.tok.kind == .keyword) {
            const name = self.tokStr();
            self.eat();

            // Function call
            if (self.tokMatch("(")) {
                self.eat();
                const n = self.allocNode(.call, name.ptr, name.len, "", 0, line, col);
                while (!self.tokMatch(")") and self.tok.kind != .eof) {
                    const arg = self.parseExpr(0);
                    if (arg != NO_NODE) self.addChild(n, arg);
                    if (self.tokMatch(",")) { self.eat(); }
                    else if (!self.tokMatch(")") and self.tok.kind != .eof) {
                        self.errs.add(.parse_unexpected_token, "expected ')' or ',' in function arguments", self.tok.line, self.tok.col, "add ')' to close the call or ',' to add more arguments");
                        self.err = true;
                        break;
                    }
                }
                if (self.tokMatch(")")) {
                    self.eat();
                } else {
                    self.errs.add(.parse_missing_close_paren, "expected ')' after function arguments", self.tok.line, self.tok.col, "add ')' to close function call");
                    self.err = true;
                }
                return n;
            }

            // Assign: name = expr
            if (self.tokMatch("=")) {
                self.eat();
                const assign = self.allocNode(.assign, name.ptr, name.len, "", 0, line, col);
                const expr = self.parseExpr(0);
                if (expr != NO_NODE) self.addChild(assign, expr);
                return assign;
            }

            return self.allocNode(.ident, name.ptr, name.len, "", 0, line, col);
        }

        if (self.tokMatch("}")) {
            self.errs.add(.parse_unexpected_token, "unexpected '}' - no matching opening brace", self.tok.line, self.tok.col, "remove this extra '}' or check braces");
            self.err = true;
            return NO_NODE;
        }
        if (self.tok.kind == .eof) {
            self.errs.add(.parse_unexpected_eof, "unexpected end of file while parsing expression", self.tok.line, self.tok.col, "add the missing expression or remove incomplete code");
            self.err = true;
            return NO_NODE;
        }

        self.errs.add(.parse_expected_expr, "expected an expression", self.tok.line, self.tok.col, "add a value, variable, or parenthesized expression here");
        self.err = true;
        return NO_NODE;
    }
};
