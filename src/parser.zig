const lexer_mod = @import("lexer.zig");

pub const NodeKind = enum(u8) {
    program,
    fn_decl,
    activity_decl,
    compose_decl,
    state_decl,
    viewmodel_decl,
    struct_decl,
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

pub const Parser = struct {
    lex: lexer_mod.Lexer,
    tok: lexer_mod.Token,
    pool: [MAX_NODES]AstNode,
    node_count: usize,
    err: bool,

    pub fn init(source: [*]const u8, len: usize) Parser {
        var p = Parser{
            .lex = lexer_mod.Lexer.init(source, len),
            .tok = undefined,
            .pool = undefined,
            .node_count = 0,
            .err = false,
        };
        p.tok = p.lex.next();
        return p;
    }

    fn allocNode(self: *Parser, kind: NodeKind, name_start: [*]const u8, name_len: usize, val_start: [*]const u8, val_len: usize, line: usize, col: usize) NodeIdx {
        if (self.node_count >= MAX_NODES) { self.err = true; return 0; }
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

    fn eat(self: *Parser) void { self.tok = self.lex.next(); }

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
        self.err = true;
        return false;
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
            } else {
                break;
            }
        }
        if (self.err) return prog;
        _ = self.expect(";");
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
        const name = self.tokStr();
        self.eat();
        const n = self.allocNode(.fn_decl, name.ptr, name.len, "", 0, line, col);
        if (self.tokMatch("(")) {
            self.eat();
            while (!self.tokMatch(")") and self.tok.kind != .eof) { self.eat(); }
            if (self.tokMatch(")")) self.eat();
        }
        // Skip return type annotation
        while (!self.tokMatch("{") and !self.tokMatch(";") and self.tok.kind != .eof) { self.eat(); }
        if (self.tokMatch("{")) {
            self.eat();
            const block = self.parseBlock();
            self.addChild(n, block);
        } else if (self.tokMatch(";")) {
            self.eat();
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
        while (!self.tokMatch("}") and self.tok.kind != .eof) {
            self.addChild(n, self.parseStatement());
        }
        if (self.tokMatch("}")) self.eat();
        return n;
    }

    fn parseStatement(self: *Parser) NodeIdx {
        if (self.tok.kind == .keyword and self.tokMatch("hui")) {
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
        if (self.tokMatch("{")) {
            self.eat();
            const n = self.parseBlock();
            return n;
        }
        // Parse expression statement (assign, call, etc.)
        return self.parseExprStmt();
    }

    fn parseVarDecl(self: *Parser) NodeIdx {
        const line = self.tok.line; const col = self.tok.col;
        self.eat();
        const name = self.tokStr();
        self.eat();
        var arr_size: NodeIdx = NO_NODE;
        if (self.tokMatch("[")) {
            self.eat();
            arr_size = self.parseExpr(0);
            if (self.tokMatch("]")) self.eat();
        }
    const sz_str = if (arr_size != NO_NODE) self.pool[@as(usize, @intCast(arr_size))].val_start else "";
    const sz_len = if (arr_size != NO_NODE) self.pool[@as(usize, @intCast(arr_size))].val_len else @as(usize, 0);
    const n = self.allocNode(.var_decl, name.ptr, name.len, sz_str, sz_len, line, col);
    if (self.tokMatch("=")) {
        self.eat();
        const expr = self.parseExpr(0);
        if (expr != NO_NODE) self.addChild(n, expr);
    }
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
        const n = self.allocNode(.if_stmt, "", 0, "", 0, line, col);
        if (self.tokMatch("(")) { self.eat(); }
        const cond = self.parseExpr(0);
        if (cond != NO_NODE) self.addChild(n, cond);
        if (self.tokMatch(")")) { self.eat(); }
        if (self.tokMatch("{")) {
            self.eat(); const block = self.parseBlock(); self.addChild(n, block);
        }
        if (self.tokMatch("uebok")) {
            self.eat();
            if (self.tokMatch("{")) { self.eat(); const block = self.parseBlock(); self.addChild(n, block); }
        }
        return n;
    }

    fn parseWhileStmt(self: *Parser) NodeIdx {
        const line = self.tok.line; const col = self.tok.col;
        self.eat();
        const n = self.allocNode(.while_stmt, "while", 5, "", 0, line, col);
        if (self.tokMatch("(")) { self.eat(); }
        const cond = self.parseExpr(0);
        if (cond != NO_NODE) self.addChild(n, cond);
        if (self.tokMatch(")")) { self.eat(); }
        if (self.tokMatch("{")) { self.eat(); const block = self.parseBlock(); self.addChild(n, block); }
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
        if (self.tokMatch("*") or self.tokMatch("/")) return 10;
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
            const n = self.allocNode(.binary_op, op.ptr, op.len, "", 0, self.tok.line, self.tok.col);
            if (left != NO_NODE) self.addChild(n, left);
            if (right != NO_NODE) self.addChild(n, right);
            left = n;
        }
        return left;
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
            if (self.tokMatch(")")) self.eat();
            return expr;
        }

        // Integer literal
        if (self.tok.kind == .integer) {
            const v = self.tokStr();
            self.eat();
            return self.allocNode(.int_lit, "", 0, v.ptr, v.len, line, col);
        }

        // String literal
        if (self.tok.kind == .string) {
            const v = self.tokStr();
            self.eat();
            return self.allocNode(.str_lit, "", 0, v.ptr, v.len, line, col);
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
                    if (self.tokMatch(",")) self.eat();
                }
                if (self.tokMatch(")")) self.eat();
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

        return NO_NODE;
    }
};
