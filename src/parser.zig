const lexer_mod = @import("lexer.zig");

pub const NodeKind = enum(u8) {
    program,
    fn_decl,
    activity_decl,
    compose_decl,
    state_decl,
    viewmodel_decl,
    let_decl,
    ret_stmt,
    if_stmt,
    while_stmt,
    block,
    call,
    assign,
    ident,
    int_lit,
    str_lit,
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
            } else if (self.tokMatch("let")) {
                const child = self.parseLetDecl();
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
                    self.addChild(n, self.allocNode(.assign, name.ptr, name.len, "", 0, line, col));
                }
            } else {
                self.eat();
            }
        }
        return n;
    }

    fn parseLetDecl(self: *Parser) NodeIdx {
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
        return self.allocNode(.let_decl, name.ptr, name.len, val_start, val_len, line, col);
    }

    fn parseRetStmt(self: *Parser) NodeIdx {
        const line = self.tok.line;
        const col = self.tok.col;
        self.eat();
        var val_start: [*]const u8 = "".ptr;
        var val_len: usize = 0;
        if (self.tok.kind != .eof) {
            val_start = self.tok.start;
            val_len = self.tok.len;
            self.eat();
        }
        return self.allocNode(.ret_stmt, "return", 6, val_start, val_len, line, col);
    }

    fn parseIfStmt(self: *Parser) NodeIdx {
        const line = self.tok.line;
        const col = self.tok.col;
        self.eat();
        const n = self.allocNode(.if_stmt, "if", 2, "", 0, line, col);
        if (self.tokMatch("(")) {
            self.eat();
            while (!self.tokMatch(")") and self.tok.kind != .eof) {
                self.eat();
            }
            if (self.tokMatch(")")) self.eat();
        }
        if (self.tokMatch("{")) {
            self.eat();
            const block = self.parseBlock();
            self.addChild(n, block);
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
            while (!self.tokMatch(")") and self.tok.kind != .eof) {
                self.eat();
            }
            if (self.tokMatch(")")) self.eat();
        }
        if (self.tokMatch("{")) {
            self.eat();
            const block = self.parseBlock();
            self.addChild(n, block);
        }
        return n;
    }
};
