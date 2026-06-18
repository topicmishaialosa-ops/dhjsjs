const lexer_mod = @import("lexer.zig");

pub const NodeKind = enum(u8) {
    program,
    fn_decl,
    activity_decl,
    compose_decl,
    state_decl,
    viewmodel_decl,
    var_decl,
    ret_stmt,
    if_stmt,
    while_stmt,
    block,
    call,
    assign,
    ident,
    int_lit,
    str_lit,
    binary_op,
    unary_op,
};

pub const NodeIdx = i32;
pub const NO_NODE: NodeIdx = -1;

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

pub const MAX_NODES = 1024;

pub const Parser = struct {
    pool: [MAX_NODES]AstNode,
    node_count: usize,
    lex: lexer_mod.Lexer,
    tok: lexer_mod.Token,

    pub fn init(source: [*]const u8, len: usize) Parser {
        var p = Parser{
            .pool = undefined,
            .node_count = 0,
            .lex = lexer_mod.Lexer.init(source, len),
            .tok = undefined,
        };
        p.tok = p.lex.next();
        return p;
    }

    fn allocNode(self: *Parser, kind: NodeKind, name: [*]const u8, name_len: usize, val: [*]const u8, val_len: usize, line: usize, col: usize) NodeIdx {
        const idx = @as(NodeIdx, @intCast(self.node_count));
        if (idx >= MAX_NODES) return NO_NODE;
        self.pool[@as(usize, @intCast(idx))] = AstNode{
            .kind = kind,
            .name_start = name,
            .name_len = name_len,
            .val_start = val,
            .val_len = val_len,
            .first_child = NO_NODE,
            .next_sibling = NO_NODE,
            .line = line,
            .col = col,
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
        self.tok = self.lex.next();
    }

    fn tokMatch(self: *Parser, s: []const u8) bool {
        if (self.tok.len != s.len) return false;
        var i: usize = 0;
        while (i < s.len) : (i += 1) {
            if (self.tok.start[i] != s[i]) return false;
        }
        return true;
    }

    fn tokStr(self: *Parser) []const u8 {
        return self.tok.start[0..self.tok.len];
    }

    pub fn parse(self: *Parser) NodeIdx {
        const prog = self.allocNode(.program, "program", 7, "", 0, 1, 1);
        while (self.tok.kind != .eof) {
            if (self.tokMatch("fn")) {
                const n = self.parseFnDecl();
                self.addChild(prog, n);
            } else if (self.tokMatch("activity")) {
                const n = self.parseActivityDecl();
                self.addChild(prog, n);
            } else if (self.tokMatch("compose")) {
                const n = self.parseComposeDecl();
                self.addChild(prog, n);
            } else if (self.tokMatch("state")) {
                const n = self.parseStateDecl();
                self.addChild(prog, n);
            } else if (self.tokMatch("viewmodel")) {
                const n = self.parseViewmodelDecl();
                self.addChild(prog, n);
            } else {
                self.eat();
            }
        }
        return prog;
    }

    fn parseFnDecl(self: *Parser) NodeIdx {
        const line = self.tok.line;
        const col = self.tok.col;
        self.eat();
        const name = self.tokStr();
        self.eat();
        const n = self.allocNode(.fn_decl, name.ptr, name.len, "", 0, line, col);
        if (self.tokMatch("(")) {
            self.eat();
            while (!self.tokMatch(")") and self.tok.kind != .eof) {
                self.eat();
            }
            if (self.tokMatch(")")) self.eat();
        }
        // skip return type annotation
        while (!self.tokMatch("{") and self.tok.kind != .eof) {
            self.eat();
        }
        if (self.tokMatch("{")) {
            self.eat();
            const block = self.parseBlock();
            self.addChild(n, block);
        }
        return n;
    }

    fn parseActivityDecl(self: *Parser) NodeIdx {
        const line = self.tok.line;
        const col = self.tok.col;
        self.eat();
        const name = self.tokStr();
        self.eat();
        const n = self.allocNode(.activity_decl, name.ptr, name.len, "", 0, line, col);
        if (self.tokMatch("{")) {
            self.eat();
            const block = self.parseBlock();
            self.addChild(n, block);
        }
        return n;
    }

    fn parseComposeDecl(self: *Parser) NodeIdx {
        const line = self.tok.line;
        const col = self.tok.col;
        self.eat();
        const name = self.tokStr();
        self.eat();
        const n = self.allocNode(.compose_decl, name.ptr, name.len, "", 0, line, col);
        if (self.tokMatch("{")) {
            self.eat();
            const block = self.parseBlock();
            self.addChild(n, block);
        }
        return n;
    }

    fn parseStateDecl(self: *Parser) NodeIdx {
        const line = self.tok.line;
        const col = self.tok.col;
        self.eat();
        const name = self.tokStr();
        self.eat();
        var val_start: [*]const u8 = "".ptr;
        var val_len: usize = 0;
        if (self.tokMatch("=")) {
            self.eat();
            val_start = self.tok.start;
            val_len = self.tok.len;
            self.eat();
        }
        return self.allocNode(.state_decl, name.ptr, name.len, val_start, val_len, line, col);
    }

    fn parseViewmodelDecl(self: *Parser) NodeIdx {
        const line = self.tok.line;
        const col = self.tok.col;
        self.eat();
        const name = self.tokStr();
        self.eat();
        const n = self.allocNode(.viewmodel_decl, name.ptr, name.len, "", 0, line, col);
        if (self.tokMatch("{")) {
            self.eat();
            const block = self.parseBlock();
            self.addChild(n, block);
        }
        return n;
    }

    fn parseBlock(self: *Parser) NodeIdx {
        const line = self.tok.line;
        const col = self.tok.col;
        const n = self.allocNode(.block, "block", 5, "", 0, line, col);
        while (self.tok.kind != .eof) {
            if (self.tokMatch("}")) {
                self.eat();
                break;
            } else if (self.tokMatch("hui")) {
                const child = self.parseVarDecl();
                self.addChild(n, child);
            } else if (self.tokMatch("return")) {
                const child = self.parseRetStmt();
                self.addChild(n, child);
            } else if (self.tokMatch("if")) {
                const child = self.parseIfStmt();
                self.addChild(n, child);
            } else if (self.tokMatch("while")) {
                const child = self.parseWhileStmt();
                self.addChild(n, child);
            } else if (self.tok.kind == .identifier) {
                const name = self.tokStr();
                self.eat();
                if (self.tokMatch("(")) {
                    self.addChild(n, self.allocNode(.call, name.ptr, name.len, "", 0, line, col));
                } else if (self.tokMatch("=")) {
                    self.eat();
                    const assign = self.allocNode(.assign, name.ptr, name.len, "", 0, line, col);
                    const expr = self.parseExpr(0);
                    if (expr != NO_NODE) self.addChild(assign, expr);
                    self.addChild(n, assign);
                }
            } else {
                self.eat();
            }
        }
        return n;
    }

    fn parseVarDecl(self: *Parser) NodeIdx {
        const line = self.tok.line;
        const col = self.tok.col;
        self.eat();
        const name = self.tokStr();
        self.eat();
        const n = self.allocNode(.var_decl, name.ptr, name.len, "", 0, line, col);
        if (self.tokMatch("=")) {
            self.eat();
            const expr = self.parseExpr(0);
            if (expr != NO_NODE) self.addChild(n, expr);
        }
        return n;
    }

    fn parseRetStmt(self: *Parser) NodeIdx {
        const line = self.tok.line;
        const col = self.tok.col;
        self.eat();
        const n = self.allocNode(.ret_stmt, "return", 6, "", 0, line, col);
        if (self.tok.kind != .eof and !self.tokMatch("}") and !self.tokMatch(";")) {
            const expr = self.parseExpr(0);
            if (expr != NO_NODE) self.addChild(n, expr);
        }
        return n;
    }

    fn parseIfStmt(self: *Parser) NodeIdx {
        const line = self.tok.line;
        const col = self.tok.col;
        self.eat();
        const n = self.allocNode(.if_stmt, "if", 2, "", 0, line, col);
        if (self.tokMatch("(")) {
            self.eat();
            const cond = self.parseExpr(0);
            if (cond != NO_NODE) self.addChild(n, cond);
            while (!self.tokMatch(")") and self.tok.kind != .eof) {
                self.eat();
            }
            if (self.tokMatch(")")) self.eat();
        } else {
            const cond = self.parseExpr(0);
            if (cond != NO_NODE) self.addChild(n, cond);
        }
        if (self.tokMatch("{")) {
            self.eat();
            const block = self.parseBlock();
            self.addChild(n, block);
        }
        if (self.tokMatch("uebok")) {
            self.eat();
            if (self.tokMatch("{")) {
                self.eat();
                const block = self.parseBlock();
                self.addChild(n, block);
            }
        }
        return n;
    }

    fn parseWhileStmt(self: *Parser) NodeIdx {
        const line = self.tok.line;
        const col = self.tok.col;
        self.eat();
        const n = self.allocNode(.while_stmt, "while", 5, "", 0, line, col);
        if (self.tokMatch("(")) {
            self.eat();
            const cond = self.parseExpr(0);
            if (cond != NO_NODE) self.addChild(n, cond);
            while (!self.tokMatch(")") and self.tok.kind != .eof) {
                self.eat();
            }
            if (self.tokMatch(")")) self.eat();
        } else {
            const cond = self.parseExpr(0);
            if (cond != NO_NODE) self.addChild(n, cond);
        }
        if (self.tokMatch("{")) {
            self.eat();
            const block = self.parseBlock();
            self.addChild(n, block);
        }
        return n;
    }

    fn parseExpr(self: *Parser, min_prec: usize) NodeIdx {
        var left = self.parsePrimary();
        if (left == NO_NODE) return NO_NODE;
        while (true) {
            const prec = opPrecedence(self.tok);
            if (prec == 0 or prec < min_prec) break;
            const line = self.tok.line;
            const col = self.tok.col;
            const op_start = self.tok.start;
            const op_len = self.tok.len;
            self.eat();
            const right = self.parseExpr(prec + 1);
            if (right == NO_NODE) return NO_NODE;
            const node = self.allocNode(.binary_op, op_start, op_len, "", 0, line, col);
            self.addChild(node, left);
            self.addChild(node, right);
            left = node;
        }
        return left;
    }

    fn parsePrimary(self: *Parser) NodeIdx {
        const line = self.tok.line;
        const col = self.tok.col;
        if (self.tok.kind == .integer) {
            const n = self.allocNode(.int_lit, "", 0, self.tok.start, self.tok.len, line, col);
            self.eat();
            return n;
        }
        if (self.tok.kind == .string) {
            const n = self.allocNode(.str_lit, "", 0, self.tok.start, self.tok.len, line, col);
            self.eat();
            return n;
        }
        if (self.tok.kind == .identifier or self.tok.kind == .keyword) {
            const name = self.tokStr();
            self.eat();
            if (self.tokMatch("(")) {
                const n = self.allocNode(.call, name.ptr, name.len, "", 0, line, col);
                self.eat();
                while (!self.tokMatch(")") and self.tok.kind != .eof) {
                    const arg = self.parseExpr(0);
                    if (arg != NO_NODE) self.addChild(n, arg);
                    if (self.tokMatch(",")) self.eat();
                }
                if (self.tokMatch(")")) self.eat();
                return n;
            }
            return self.allocNode(.ident, name.ptr, name.len, "", 0, line, col);
        }
        if (self.tokMatch("(")) {
            self.eat();
            const expr = self.parseExpr(0);
            if (self.tokMatch(")")) self.eat();
            return expr;
        }
        if (self.tokMatch("!")) {
            self.eat();
            const operand = self.parseExpr(7);
            const n = self.allocNode(.unary_op, "!", 1, "", 0, line, col);
            if (operand != NO_NODE) self.addChild(n, operand);
            return n;
        }
        if (self.tokMatch("-")) {
            self.eat();
            const operand = self.parseExpr(7);
            const n = self.allocNode(.unary_op, "-", 1, "", 0, line, col);
            if (operand != NO_NODE) self.addChild(n, operand);
            return n;
        }
        return NO_NODE;
    }
};

fn opPrecedence(tok: lexer_mod.Token) usize {
    if (tok.kind != .symbol) return 0;
    if (tok.len == 1) {
        switch (tok.start[0]) {
            '*', '/' => return 6,
            '+', '-' => return 5,
            '<', '>' => return 4,
            else => return 0,
        }
    }
    if (tok.len == 2) {
        if (tok.start[0] == '=' and tok.start[1] == '=') return 4;
        if (tok.start[0] == '!' and tok.start[1] == '=') return 4;
        if (tok.start[0] == '<') return 4; // <=
        if (tok.start[0] == '>') return 4; // >=
        if (tok.start[0] == '&' and tok.start[1] == '&') return 3;
        if (tok.start[0] == '|' and tok.start[1] == '|') return 2;
    }
    return 0;
}
