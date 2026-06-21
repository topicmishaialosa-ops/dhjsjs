const parser_mod = @import("parser.zig");
const cg = @import("codegen.zig");
const errors_mod = @import("errors.zig");

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) if (a[i] != b[i]) return false;
    return true;
}

fn strToInt(s: []const u8) i64 {
    var v: i64 = 0;
    var i: usize = 0;
    if (s.len > 2 and s[0] == '0' and (s[1] == 'x' or s[1] == 'X')) {
        i = 2;
        while (i < s.len) : (i += 1) {
            const c = s[i];
            v <<= 4;
            if (c >= '0' and c <= '9') { v |= @as(i64, c - '0'); }
            if (c >= 'a' and c <= 'f') { v |= @as(i64, c - 'a' + 10); }
            if (c >= 'A' and c <= 'F') { v |= @as(i64, c - 'A' + 10); }
        }
    } else {
        while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) v = v * 10 + (s[i] - '0');
    }
    return v;
}

fn formatMsg(buf: []u8, pos: usize, parts: []const []const u8) usize {
    var p = pos;
    for (parts) |part| {
        var i: usize = 0;
        while (i < part.len and p < buf.len) : (i += 1) {
            buf[p] = part[i];
            p += 1;
        }
    }
    return p;
}

const Var = struct { name: []const u8, off: i32, size: i32 };
const MAX_VARS = 64;

pub fn compile(prog_root: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, errs: *errors_mod.ErrorList) cg.CodeBuffer {
    var cb = cg.CodeBuffer.init();
    var vars: [MAX_VARS]Var = undefined;
    var vc: usize = 0;
    var stack_off: i32 = 0;

    if (prog_root == parser_mod.NO_NODE) {
        cb.movRImm64(cg.RDI, 0);
        cb.movRImm64(cg.RAX, 60);
        cb.syscall();
        return cb;
    }

    const prog = &pool[@as(usize, @intCast(prog_root))];
    var main_idx: parser_mod.NodeIdx = parser_mod.NO_NODE;
    var ch = prog.first_child;
    while (ch != parser_mod.NO_NODE) {
        const cn = &pool[@as(usize, @intCast(ch))];
        if (cn.kind == .fn_decl and eq(cn.name_start[0..cn.name_len], "main")) {
            main_idx = ch;
        }
        ch = cn.next_sibling;
    }

    if (main_idx == parser_mod.NO_NODE) {
        errs.add(.comp_undefined_fn, "no 'main' function found", 1, 1, "add a 'fn main()' function as the entry point");
        cb.movRImm64(cg.RDI, 0);
        cb.movRImm64(cg.RAX, 60);
        cb.syscall();
        return cb;
    }

    const call_pos: usize = cb.pos;
    cb.callRel32(0);
    cb.movRR(cg.RDI, cg.RAX);
    cb.movRImm64(cg.RAX, 60);
    cb.syscall();

    var main_body_pos: usize = 0;
    var has_return: bool = false;
    ch = prog.first_child;
    while (ch != parser_mod.NO_NODE) {
        const cn = &pool[@as(usize, @intCast(ch))];
        if (cn.kind == .fn_decl) {
            if (ch == main_idx) main_body_pos = cb.pos;
            compileFn(cn, pool, &cb, &vars, &vc, &stack_off, errs, &has_return);
        }
        ch = cn.next_sibling;
    }

    // main has implicit return 0 if no return statement

    const main_off: i32 = @as(i32, @intCast(main_body_pos)) - @as(i32, @intCast(call_pos + 5));
    patch32(&cb, call_pos + 1, main_off);
    return cb;
}

fn countVarDecls(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode) usize {
    if (n.first_child == parser_mod.NO_NODE) return 0;
    var count: usize = 0;
    var ch = n.first_child;
    while (ch != parser_mod.NO_NODE) {
        const cn = &pool[@as(usize, @intCast(ch))];
        switch (cn.kind) {
            .var_decl => {
                var arr_sz: i32 = 1;
                if (cn.val_len > 0) arr_sz = @as(i32, @intCast(strToInt(cn.val_start[0..cn.val_len])));
                count += @as(usize, @intCast(@max(1, arr_sz)));
            },
            .block => count += countVarDecls(cn, pool),
            .if_stmt => {
                if (cn.first_child != parser_mod.NO_NODE) {
                    const then_blk = pool[@as(usize, @intCast(cn.first_child))].next_sibling;
                    if (then_blk != parser_mod.NO_NODE) count += countVarDecls(&pool[@as(usize, @intCast(then_blk))], pool);
                    const else_blk = if (then_blk != parser_mod.NO_NODE) pool[@as(usize, @intCast(then_blk))].next_sibling else parser_mod.NO_NODE;
                    if (else_blk != parser_mod.NO_NODE) count += countVarDecls(&pool[@as(usize, @intCast(else_blk))], pool);
                }
            },
            .while_stmt => {
                if (cn.first_child != parser_mod.NO_NODE) {
                    const body = pool[@as(usize, @intCast(cn.first_child))].next_sibling;
                    if (body != parser_mod.NO_NODE) count += countVarDecls(&pool[@as(usize, @intCast(body))], pool);
                }
            },
            else => {},
        }
        ch = cn.next_sibling;
    }
    return count;
}

fn compileFn(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32, errs: *errors_mod.ErrorList, has_return: *bool) void {
    const var_count: usize = countVarDecls(n, pool);
    cb.pushR(cg.RBP);
    cb.movRR(cg.RBP, cg.RSP);
    const frame: i32 = @as(i32, @intCast(var_count)) * 8;
    if (frame > 0) cb.subRImm32(cg.RSP, frame);

    var child = n.first_child;
    while (child != parser_mod.NO_NODE) {
        compileStmt(child, pool, cb, vars, vc, stack_off, errs, has_return);
        child = pool[@as(usize, @intCast(child))].next_sibling;
    }

    cb.xorRR(cg.RAX, cg.RAX);
    cb.movRR(cg.RSP, cg.RBP);
    cb.popR(cg.RBP);
    cb.ret();
}

fn compileStmt(idx: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32, errs: *errors_mod.ErrorList, has_return: *bool) void {
    if (idx == parser_mod.NO_NODE) return;
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .block => {
            var ch = n.first_child;
            while (ch != parser_mod.NO_NODE) {
                compileStmt(ch, pool, cb, vars, vc, stack_off, errs, has_return);
                ch = pool[@as(usize, @intCast(ch))].next_sibling;
            }
        },
        .ret_stmt => {
            has_return.* = true;
            if (n.first_child != parser_mod.NO_NODE) {
                compileExprNode(n.first_child, pool, cb, vars, vc, errs);
            } else { cb.xorRR(cg.RAX, cg.RAX); }
            cb.movRR(cg.RSP, cg.RBP);
            cb.popR(cg.RBP);
            cb.ret();
        },
        .var_decl => {
            const name = n.name_start[0..n.name_len];
            var arr_sz: i32 = 1;
            const init_expr: parser_mod.NodeIdx = n.first_child;
            if (n.val_len > 0) {
                arr_sz = @as(i32, @intCast(strToInt(n.val_start[0..n.val_len])));
            }
            const total_slots: i32 = @max(1, arr_sz);
            var si: i32 = 0;
            var first_off: i32 = 0;
            while (si < total_slots) : (si += 1) {
                stack_off.* -= 8;
                const off = stack_off.*;
                if (si == 0) {
                    first_off = off;
                    if (vc.* < MAX_VARS) {
                        vars[vc.*] = Var{ .name = name, .off = off, .size = 8 };
                        vc.* += 1;
                    }
                }
                if (si == 0 and init_expr != parser_mod.NO_NODE) {
                    compileExprNode(init_expr, pool, cb, vars, vc, errs);
                    cb.movMemR64(cg.RBP, off, cg.RAX);
                } else if (si == 0 and init_expr == parser_mod.NO_NODE and total_slots == 1) {
                    cb.xorRR(cg.RAX, cg.RAX);
                    cb.movMemR64(cg.RBP, off, cg.RAX);
                }
            }
        },
        .call => { compileCall(n, pool, cb, vars, vc, errs); },
        .assign => {
            if (n.first_child != parser_mod.NO_NODE) {
                compileExprNode(n.first_child, pool, cb, vars, vc, errs);
            } else { cb.xorRR(cg.RAX, cg.RAX); }
            const name = n.name_start[0..n.name_len];
            const off = findVarIndex(vars, vc.*, name);
            if (off) |o| {
                cb.movMemR64(cg.RBP, vars[o].off, cg.RAX);
            } else if (vc.* < MAX_VARS) {
                stack_off.* -= 8;
                vars[vc.*] = Var{ .name = name, .off = stack_off.*, .size = 8 };
                vc.* += 1;
                cb.movMemR64(cg.RBP, stack_off.*, cg.RAX);
            }
        },
        .if_stmt => compileIf(n, pool, cb, vars, vc, stack_off, errs, has_return),
        .while_stmt => compileWhile(n, pool, cb, vars, vc, stack_off, errs, has_return),
        .store => {
            const lval = n.first_child;
            const val = if (lval != parser_mod.NO_NODE) pool[@as(usize, @intCast(lval))].next_sibling else parser_mod.NO_NODE;
            if (val != parser_mod.NO_NODE) {
                compileExprNode(val, pool, cb, vars, vc, errs);
            } else { cb.xorRR(cg.RAX, cg.RAX); }
            cb.pushR(cg.RAX);
            if (lval != parser_mod.NO_NODE) {
                compileExprAddr(lval, pool, cb, vars, vc, errs);
            } else { cb.xorRR(cg.RAX, cg.RAX); }
            cb.popR(cg.RCX);
            cb.movMemR64(cg.RAX, 0, cg.RCX);
        },
        .struct_decl => {},
        else => {
            var ch = n.first_child;
            while (ch != parser_mod.NO_NODE) {
                compileStmt(ch, pool, cb, vars, vc, stack_off, errs, has_return);
                ch = pool[@as(usize, @intCast(ch))].next_sibling;
            }
        },
    }
}

fn compileExprNode(idx: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, errs: *errors_mod.ErrorList) void {
    if (idx == parser_mod.NO_NODE) { cb.xorRR(cg.RAX, cg.RAX); return; }
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .int_lit => {
            cb.movRImm64(cg.RAX, @as(u64, @intCast(strToInt(n.val_start[0..n.val_len]))));
        },
        .str_lit => {
            const s = n.val_start[0..n.val_len];
            cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
            cb.dword(2);
            cb.byte(0xEB);
            const skip: u8 = @as(u8, @intCast(s.len)) + 1;
            cb.byte(skip);
            for (s) |c| cb.byte(c);
            cb.byte(0);
        },
        .ident => {
            const vname = n.name_start[0..n.name_len];
            if (findVarOffset(vars, vc.*, vname)) |off| {
                cb.movRMem64(cg.RAX, cg.RBP, off);
            } else {
                var buf: [128]u8 = undefined;
                const parts = [_][]const u8{ "undefined variable '", vname, "'" };
                const len = formatMsg(&buf, 0, &parts);
                errs.add(.comp_undefined_var, buf[0..len], n.line, n.col, "declare the variable with 'hui name = value;' before using it");
                cb.xorRR(cg.RAX, cg.RAX);
            }
        },
        .binary_op => compileBinaryOp(n, pool, cb, vars, vc, errs),
        .unary_op => compileUnaryOp(n, pool, cb, vars, vc, errs),
        .field_access => compileFieldAccess(n, pool, cb, vars, vc, errs),
        .array_index => compileArrayIndex(n, pool, cb, vars, vc, errs),
        .addr_of => compileAddrOf(n, pool, cb, vars, vc, errs),
        .deref => compileDeref(n, pool, cb, vars, vc, errs),
        .sizeof_expr => compileSizeof(n, pool, cb, vars, vc, errs),
        .call => compileCall(n, pool, cb, vars, vc, errs),
        else => { cb.xorRR(cg.RAX, cg.RAX); },
    }
}

fn compileExprAddr(idx: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, errs: *errors_mod.ErrorList) void {
    if (idx == parser_mod.NO_NODE) { cb.xorRR(cg.RAX, cg.RAX); return; }
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .ident => {
            const addr_name = n.name_start[0..n.name_len];
            if (findVarOffset(vars, vc.*, addr_name)) |off| {
                cb.leaRMem(cg.RAX, cg.RBP, off);
            } else {
                var buf: [128]u8 = undefined;
                const parts = [_][]const u8{ "undefined variable '", addr_name, "'" };
                const len = formatMsg(&buf, 0, &parts);
                errs.add(.comp_undefined_var, buf[0..len], n.line, n.col, "declare the variable with 'hui name = value;' before using it");
                cb.xorRR(cg.RAX, cg.RAX);
            }
        },
        .deref => {
            compileExprNode(n.first_child, pool, cb, vars, vc, errs);
        },
        .field_access => {
            compileExprAddr(n.first_child, pool, cb, vars, vc, errs);
            const field = n.name_start[0..n.name_len];
            const field_off = findFieldOffset(pool, field);
            if (field_off > 0) cb.addRImm32(cg.RAX, field_off);
        },
        .array_index => {
            compileExprAddr(n.first_child, pool, cb, vars, vc, errs);
            const idx_node = if (n.first_child != parser_mod.NO_NODE)
                pool[@as(usize, @intCast(n.first_child))].next_sibling
            else
                parser_mod.NO_NODE;
            if (idx_node != parser_mod.NO_NODE) {
                cb.pushR(cg.RAX);
                compileExprNode(idx_node, pool, cb, vars, vc, errs);
                cb.movRR(cg.RCX, cg.RAX);
                cb.negR(cg.RCX);
                cb.shlRImm8(cg.RCX, 3);
                cb.popR(cg.RAX);
                cb.addRR(cg.RAX, cg.RCX);
            }
        },
        else => compileExprNode(idx, pool, cb, vars, vc, errs),
    }
}

fn compileBinaryOp(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, errs: *errors_mod.ErrorList) void {
    const op = n.name_start[0..n.name_len];
    const left = n.first_child;
    const right = if (left != parser_mod.NO_NODE) pool[@as(usize, @intCast(left))].next_sibling else parser_mod.NO_NODE;
    if (left == parser_mod.NO_NODE or right == parser_mod.NO_NODE) { cb.xorRR(cg.RAX, cg.RAX); return; }

    compileExprNode(left, pool, cb, vars, vc, errs);
    cb.pushR(cg.RAX);
    compileExprNode(right, pool, cb, vars, vc, errs);
    cb.movRR(cg.RCX, cg.RAX);
    cb.popR(cg.RAX);

    if (eq(op, "+")) { cb.addRR(cg.RAX, cg.RCX); }
    else if (eq(op, "-")) { cb.subRR(cg.RAX, cg.RCX); }
    else if (eq(op, "*")) { cb.imulRR(cg.RAX, cg.RCX); }
    else if (eq(op, "/")) { cb.cqo(); cb.idivR(cg.RCX); }
    else if (eq(op, "%")) { cb.cqo(); cb.idivR(cg.RCX); cb.movRR(cg.RAX, cg.RDX); }
    else if (eq(op, "&")) { cb.andRR(cg.RAX, cg.RCX); }
    else if (eq(op, "|")) { cb.orRR(cg.RAX, cg.RCX); }
    else if (eq(op, "^")) { cb.xorRR(cg.RAX, cg.RCX); }
    else if (eq(op, "<<")) { cb.shlRcl(cg.RAX); }
    else if (eq(op, ">>")) { cb.shrRcl(cg.RAX); }
    else if (eq(op, "==")) { cb.cmpRR(cg.RAX, cg.RCX); cb.pushfq(); cb.xorRR(cg.RAX, cg.RAX); cb.popfq(); cb.sete(cg.RAX); }
    else if (eq(op, "!=")) { cb.cmpRR(cg.RAX, cg.RCX); cb.pushfq(); cb.xorRR(cg.RAX, cg.RAX); cb.popfq(); cb.setne(cg.RAX); }
    else if (eq(op, "<")) { cb.cmpRR(cg.RAX, cg.RCX); cb.pushfq(); cb.xorRR(cg.RAX, cg.RAX); cb.popfq(); cb.setl(cg.RAX); }
    else if (eq(op, ">")) { cb.cmpRR(cg.RAX, cg.RCX); cb.pushfq(); cb.xorRR(cg.RAX, cg.RAX); cb.popfq(); cb.setg(cg.RAX); }
    else if (eq(op, "<=")) { cb.cmpRR(cg.RAX, cg.RCX); cb.pushfq(); cb.xorRR(cg.RAX, cg.RAX); cb.popfq(); cb.setle(cg.RAX); }
    else if (eq(op, ">=")) { cb.cmpRR(cg.RAX, cg.RCX); cb.pushfq(); cb.xorRR(cg.RAX, cg.RAX); cb.popfq(); cb.setge(cg.RAX); }
    else if (eq(op, "&&")) { cb.andRR(cg.RAX, cg.RCX); }
    else if (eq(op, "||")) { cb.orRR(cg.RAX, cg.RCX); }
    else {
        var buf: [128]u8 = undefined;
        const parts = [_][]const u8{ "unknown operator '", op, "'" };
        const len = formatMsg(&buf, 0, &parts);
        errs.add(.comp_type_mismatch, buf[0..len], n.line, n.col, "use a valid operator: +, -, *, /, %, ==, !=, <, >, <=, >=, &&, ||, &, |, ^, <<, >>");
        cb.xorRR(cg.RAX, cg.RAX);
    }
}

fn compileUnaryOp(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, errs: *errors_mod.ErrorList) void {
    const op = n.name_start[0..n.name_len];
    const operand = n.first_child;
    compileExprNode(operand, pool, cb, vars, vc, errs);
    if (eq(op, "-")) { cb.negR(cg.RAX); }
    else if (eq(op, "!")) { cb.cmpRImm32(cg.RAX, 0); cb.pushfq(); cb.xorRR(cg.RAX, cg.RAX); cb.popfq(); cb.sete(cg.RAX); }
    else {
        var buf: [128]u8 = undefined;
        const parts = [_][]const u8{ "unknown unary operator '", op, "'" };
        const len = formatMsg(&buf, 0, &parts);
        errs.add(.comp_type_mismatch, buf[0..len], n.line, n.col, "use a valid unary operator: -, !");
        cb.xorRR(cg.RAX, cg.RAX);
    }
}

fn compileCall(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, errs: *errors_mod.ErrorList) void {
    const name = n.name_start[0..n.name_len];
    if (eq(name, "syscall")) {
        var ch = n.first_child;
        var ai: usize = 0;

        var nr_val: i64 = 0;
        if (ch != parser_mod.NO_NODE) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (cn.kind == .int_lit) nr_val = strToInt(cn.val_start[0..cn.val_len]);
            ch = cn.next_sibling;
            ai = 1;
        }

        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            ai += 1;
            arg_i += 1;
            ch = cn.next_sibling;
        }

        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) {
            if (is_expr[ei]) {
                compileExprNode(args_list[ei], pool, cb, vars, vc, errs);
                cb.pushR(cg.RAX);
            }
        }

        const regs = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri: usize = arg_i;
        while (ri > 0) {
            ri -= 1;
            if (is_expr[ri]) {
                cb.popR(regs[ri]);
            } else if (args_list[ri] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[ri]))];
                const v: i64 = if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0;
                cb.movRImm64(regs[ri], @as(u64, @intCast(v)));
            }
        }

        cb.movRImm64(cg.RAX, @as(u64, @intCast(nr_val)));
        cb.syscall();
        return;
    }
    if (eq(name, "print")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) { compileExprNode(ch, pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.movRR(cg.RSI, cg.RAX);
        var plen: i64 = -1;
        if (ch != parser_mod.NO_NODE) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (cn.kind == .str_lit) plen = @as(i64, @intCast(cn.val_len));
            if (plen < 0 and cn.next_sibling != parser_mod.NO_NODE) {
                const ln = &pool[@as(usize, @intCast(cn.next_sibling))];
                if (ln.kind == .int_lit) plen = strToInt(ln.val_start[0..ln.val_len]);
            }
        }
        cb.movRImm64(cg.RAX, 1);
        cb.movRImm64(cg.RDI, 1);
        if (plen >= 0) cb.movRImm64(cg.RDX, @as(u64, @intCast(plen)));
        cb.syscall();
        return;
    }
    if (eq(name, "socket")) {
        var ai: usize = 0; var av: [3]i64 = .{2, 1, 0};
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and ai < 3) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (cn.kind == .int_lit) av[ai] = strToInt(cn.val_start[0..cn.val_len]);
            ai += 1; ch = cn.next_sibling;
        }
        cb.movRImm64(cg.RAX, 41);
        cb.movRImm64(cg.RDI, @as(u64, @intCast(av[0])));
        cb.movRImm64(cg.RSI, @as(u64, @intCast(av[1])));
        cb.movRImm64(cg.RDX, @as(u64, @intCast(av[2])));
        cb.syscall();
        return;
    }
    if (eq(name, "close")) {
        var fd: i64 = 0;
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (cn.kind == .int_lit) fd = strToInt(cn.val_start[0..cn.val_len]);
        }
        cb.movRImm64(cg.RAX, 3);
        cb.movRImm64(cg.RDI, @as(u64, @intCast(fd)));
        cb.syscall();
        return;
    }
    if (eq(name, "open")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
        const regs = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri: usize = arg_i;
        while (ri > 0) { ri -= 1;
            if (is_expr[ri]) { cb.popR(regs[ri]); }
            else if (args_list[ri] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[ri]))];
                cb.movRImm64(regs[ri], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, 2);
        cb.syscall();
        return;
    }
    if (eq(name, "read")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
        const regs2 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri2: usize = arg_i;
        while (ri2 > 0) { ri2 -= 1;
            if (is_expr[ri2]) { cb.popR(regs2[ri2]); }
            else if (args_list[ri2] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[ri2]))];
                cb.movRImm64(regs2[ri2], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, 0);
        cb.syscall();
        return;
    }
    if (eq(name, "write")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
        const regs3 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri3: usize = arg_i;
        while (ri3 > 0) { ri3 -= 1;
            if (is_expr[ri3]) { cb.popR(regs3[ri3]); }
            else if (args_list[ri3] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[ri3]))];
                cb.movRImm64(regs3[ri3], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, 1);
        cb.syscall();
        return;
    }
    if (eq(name, "exit")) {
        var code: i64 = 0;
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (cn.kind == .int_lit) code = strToInt(cn.val_start[0..cn.val_len]);
        }
        cb.movRImm64(cg.RDI, @as(u64, @intCast(code)));
        cb.movRImm64(cg.RAX, 60);
        cb.syscall();
        return;
    }
    if (eq(name, "mmap")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
        const regs4 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri4: usize = arg_i;
        while (ri4 > 0) { ri4 -= 1;
            if (is_expr[ri4]) { cb.popR(regs4[ri4]); }
            else if (args_list[ri4] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[ri4]))];
                cb.movRImm64(regs4[ri4], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, 9);
        cb.syscall();
        return;
    }
    if (eq(name, "munmap")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
        const regs5 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri5: usize = arg_i;
        while (ri5 > 0) { ri5 -= 1;
            if (is_expr[ri5]) { cb.popR(regs5[ri5]); }
            else if (args_list[ri5] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[ri5]))];
                cb.movRImm64(regs5[ri5], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, 11);
        cb.syscall();
        return;
    }
    if (eq(name, "fork")) {
        cb.movRImm64(cg.RAX, 57);
        cb.syscall();
        return;
    }
    if (eq(name, "getpid")) {
        cb.movRImm64(cg.RAX, 39);
        cb.syscall();
        return;
    }
    if (eq(name, "lseek")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
        const regs6 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri6: usize = arg_i;
        while (ri6 > 0) { ri6 -= 1;
            if (is_expr[ri6]) { cb.popR(regs6[ri6]); }
            else if (args_list[ri6] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[ri6]))];
                cb.movRImm64(regs6[ri6], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, 8);
        cb.syscall();
        return;
    }
    if (eq(name, "dup2")) {
        var oldfd: i64 = 0; var newfd: i64 = 0;
        var ch = n.first_child;
        if (ch != parser_mod.NO_NODE) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (cn.kind == .int_lit) oldfd = strToInt(cn.val_start[0..cn.val_len]);
            ch = cn.next_sibling;
        }
        if (ch != parser_mod.NO_NODE) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (cn.kind == .int_lit) newfd = strToInt(cn.val_start[0..cn.val_len]);
        }
        cb.movRImm64(cg.RDI, @as(u64, @intCast(oldfd)));
        cb.movRImm64(cg.RSI, @as(u64, @intCast(newfd)));
        cb.movRImm64(cg.RAX, 33);
        cb.syscall();
        return;
    }
    if (eq(name, "dup")) {
        var fd: i64 = 0;
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (cn.kind == .int_lit) fd = strToInt(cn.val_start[0..cn.val_len]);
        }
        cb.movRImm64(cg.RDI, @as(u64, @intCast(fd)));
        cb.movRImm64(cg.RAX, 32);
        cb.syscall();
        return;
    }
    if (eq(name, "mkdir")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) { compileExprNode(ch, pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX);
        if (ch != parser_mod.NO_NODE) {
            const nxt = pool[@as(usize, @intCast(ch))].next_sibling;
            if (nxt != parser_mod.NO_NODE) { compileExprNode(nxt, pool, cb, vars, vc, errs); }
            else { cb.movRImm64(cg.RAX, 0x1C0); }
        } else { cb.movRImm64(cg.RAX, 0x1C0); }
        cb.movRR(cg.RSI, cg.RAX);
        cb.popR(cg.RDI);
        cb.movRImm64(cg.RAX, 83);
        cb.syscall();
        return;
    }
    if (eq(name, "chdir")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) { compileExprNode(ch, pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.movRR(cg.RDI, cg.RAX);
        cb.movRImm64(cg.RAX, 80);
        cb.syscall();
        return;
    }
    if (eq(name, "getcwd")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
        const regs7 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri7: usize = arg_i;
        while (ri7 > 0) { ri7 -= 1;
            if (is_expr[ri7]) { cb.popR(regs7[ri7]); }
            else if (args_list[ri7] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[ri7]))];
                cb.movRImm64(regs7[ri7], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, 79);
        cb.syscall();
        return;
    }
    if (eq(name, "brk")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) { compileExprNode(ch, pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.movRR(cg.RDI, cg.RAX);
        cb.movRImm64(cg.RAX, 12);
        cb.syscall();
        return;
    }
    if (eq(name, "nanosleep")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
        const regs8 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri8: usize = arg_i;
        while (ri8 > 0) { ri8 -= 1;
            if (is_expr[ri8]) { cb.popR(regs8[ri8]); }
            else if (args_list[ri8] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[ri8]))];
                cb.movRImm64(regs8[ri8], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, 35);
        cb.syscall();
        return;
    }
    if (eq(name, "uname")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) { compileExprNode(ch, pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.movRR(cg.RDI, cg.RAX);
        cb.movRImm64(cg.RAX, 63);
        cb.syscall();
        return;
    }
    if (eq(name, "time")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) { compileExprNode(ch, pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.movRR(cg.RDI, cg.RAX);
        cb.movRImm64(cg.RAX, 201);
        cb.syscall();
        return;
    }
    if (eq(name, "stat")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
        const regs9 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri9: usize = arg_i;
        while (ri9 > 0) { ri9 -= 1;
            if (is_expr[ri9]) { cb.popR(regs9[ri9]); }
            else if (args_list[ri9] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[ri9]))];
                cb.movRImm64(regs9[ri9], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, 4);
        cb.syscall();
        return;
    }
    if (eq(name, "fstat")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
        const regsA = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var riA: usize = arg_i;
        while (riA > 0) { riA -= 1;
            if (is_expr[riA]) { cb.popR(regsA[riA]); }
            else if (args_list[riA] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[riA]))];
                cb.movRImm64(regsA[riA], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, 5);
        cb.syscall();
        return;
    }
    if (eq(name, "pipe")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
        const regsB = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var riB: usize = arg_i;
        while (riB > 0) { riB -= 1;
            if (is_expr[riB]) { cb.popR(regsB[riB]); }
            else if (args_list[riB] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[riB]))];
                cb.movRImm64(regsB[riB], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, 22);
        cb.syscall();
        return;
    }
    if (eq(name, "readlink")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
        const regsC = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var riC: usize = arg_i;
        while (riC > 0) { riC -= 1;
            if (is_expr[riC]) { cb.popR(regsC[riC]); }
            else if (args_list[riC] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[riC]))];
                cb.movRImm64(regsC[riC], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, 89);
        cb.syscall();
        return;
    }
    if (eq(name, "rmdir")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) { compileExprNode(ch, pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.movRR(cg.RDI, cg.RAX);
        cb.movRImm64(cg.RAX, 84);
        cb.syscall();
        return;
    }
    if (eq(name, "unlink")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) { compileExprNode(ch, pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.movRR(cg.RDI, cg.RAX);
        cb.movRImm64(cg.RAX, 87);
        cb.syscall();
        return;
    }
    if (eq(name, "chmod")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
        const regsD = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var riD: usize = arg_i;
        while (riD > 0) { riD -= 1;
            if (is_expr[riD]) { cb.popR(regsD[riD]); }
            else if (args_list[riD] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[riD]))];
                cb.movRImm64(regsD[riD], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, 90);
        cb.syscall();
        return;
    }
    if (eq(name, "connect")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        if (arg_i == 3) {
            var fd_v: i64 = 0; var ip_v: i64 = 0; var port_v: i64 = 0;
            if (!is_expr[0]) { const cn = &pool[@as(usize, @intCast(args_list[0]))]; if (cn.kind == .int_lit) fd_v = strToInt(cn.val_start[0..cn.val_len]); }
            if (!is_expr[1]) { const cn = &pool[@as(usize, @intCast(args_list[1]))]; if (cn.kind == .int_lit) ip_v = strToInt(cn.val_start[0..cn.val_len]); }
            if (!is_expr[2]) { const cn = &pool[@as(usize, @intCast(args_list[2]))]; if (cn.kind == .int_lit) port_v = strToInt(cn.val_start[0..cn.val_len]); }
            const pnet = @as(u16, @intCast(port_v));
            const pnet_be = (@as(u16, @intCast(pnet)) << 8) | (@as(u16, @intCast(pnet)) >> 8);
            if (is_expr[0]) { compileExprNode(args_list[0], pool, cb, vars, vc, errs); }
            cb.subRImm32(cg.RSP, 16);
            cb.movImm16RSP(0, @as(u16, @intCast(2)));
            cb.movImm16RSP(2, pnet_be);
            cb.movImm32RSP(4, @as(u32, @intCast(ip_v)));
            cb.movImm32RSP(8, 0);
            cb.movImm32RSP(12, 0);
            if (is_expr[0]) { cb.movRR(cg.RDI, cg.RAX); }
            else { cb.movRImm64(cg.RDI, @as(u64, @intCast(fd_v))); }
            cb.leaRMem(cg.RSI, cg.RSP, 0);
            cb.movRImm64(cg.RDX, 16);
            cb.movRImm64(cg.RAX, 42);
            cb.syscall();
            cb.addRImm32(cg.RSP, 16);
        } else {
            var ei: usize = 0;
            while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
            const regs = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
            var ri: usize = arg_i;
            while (ri > 0) { ri -= 1;
                if (is_expr[ri]) { cb.popR(regs[ri]); }
                else if (args_list[ri] != parser_mod.NO_NODE) {
                    const cn = &pool[@as(usize, @intCast(args_list[ri]))];
                    cb.movRImm64(regs[ri], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
                }
            }
            cb.movRImm64(cg.RAX, 42);
            cb.syscall();
        }
        return;
    }
    if (eq(name, "bind")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        if (arg_i == 3) {
            var fd_v: i64 = 0; var ip_v: i64 = 0; var port_v: i64 = 0;
            if (!is_expr[0]) { const cn = &pool[@as(usize, @intCast(args_list[0]))]; if (cn.kind == .int_lit) fd_v = strToInt(cn.val_start[0..cn.val_len]); }
            if (!is_expr[1]) { const cn = &pool[@as(usize, @intCast(args_list[1]))]; if (cn.kind == .int_lit) ip_v = strToInt(cn.val_start[0..cn.val_len]); }
            if (!is_expr[2]) { const cn = &pool[@as(usize, @intCast(args_list[2]))]; if (cn.kind == .int_lit) port_v = strToInt(cn.val_start[0..cn.val_len]); }
            const pnet = @as(u16, @intCast(port_v));
            const pnet_be = (@as(u16, @intCast(pnet)) << 8) | (@as(u16, @intCast(pnet)) >> 8);
            if (is_expr[0]) { compileExprNode(args_list[0], pool, cb, vars, vc, errs); }
            cb.subRImm32(cg.RSP, 16);
            cb.movImm16RSP(0, @as(u16, @intCast(2)));
            cb.movImm16RSP(2, pnet_be);
            cb.movImm32RSP(4, @as(u32, @intCast(ip_v)));
            cb.movImm32RSP(8, 0);
            cb.movImm32RSP(12, 0);
            if (is_expr[0]) { cb.movRR(cg.RDI, cg.RAX); }
            else { cb.movRImm64(cg.RDI, @as(u64, @intCast(fd_v))); }
            cb.leaRMem(cg.RSI, cg.RSP, 0);
            cb.movRImm64(cg.RDX, 16);
            cb.movRImm64(cg.RAX, 49);
            cb.syscall();
            cb.addRImm32(cg.RSP, 16);
        } else {
            var ei: usize = 0;
            while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
            const regs = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
            var ri: usize = arg_i;
            while (ri > 0) { ri -= 1;
                if (is_expr[ri]) { cb.popR(regs[ri]); }
                else if (args_list[ri] != parser_mod.NO_NODE) {
                    const cn = &pool[@as(usize, @intCast(args_list[ri]))];
                    cb.movRImm64(regs[ri], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
                }
            }
            cb.movRImm64(cg.RAX, 49);
            cb.syscall();
        }
        return;
    }
    if (eq(name, "recv")) {
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var use_stack_buf = false;
        if (arg_i >= 2 and !is_expr[1]) {
            const cn = &pool[@as(usize, @intCast(args_list[1]))];
            if (cn.kind == .int_lit and strToInt(cn.val_start[0..cn.val_len]) == 0) {
                use_stack_buf = true;
            }
        }
        if (use_stack_buf) {
            cb.subRImm32(cg.RSP, 4096);
            if (is_expr[0]) { compileExprNode(args_list[0], pool, cb, vars, vc, errs); cb.movRR(cg.RDI, cg.RAX); }
            else {
                var fd: i64 = 0;
                const cn = &pool[@as(usize, @intCast(args_list[0]))];
                if (cn.kind == .int_lit) fd = strToInt(cn.val_start[0..cn.val_len]);
                cb.movRImm64(cg.RDI, @as(u64, @intCast(fd)));
            }
            cb.movRImm64(cg.RAX, 45);
            cb.leaRMem(cg.RSI, cg.RSP, 0);
            cb.movRImm64(cg.RDX, 4096);
            cb.movRImm64(cg.R10, 0);
            cb.movRImm64(cg.R8, 0);
            cb.movRImm64(cg.R9, 0);
            cb.syscall();
            cb.addRImm32(cg.RSP, 4096);
        } else {
            var ei: usize = 0;
            while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
            const regs = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
            var ri: usize = arg_i;
            while (ri > 0) { ri -= 1;
                if (is_expr[ri]) { cb.popR(regs[ri]); }
                else if (args_list[ri] != parser_mod.NO_NODE) {
                    const cn = &pool[@as(usize, @intCast(args_list[ri]))];
                    cb.movRImm64(regs[ri], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
                }
            }
            cb.movRImm64(cg.RAX, 45);
            cb.syscall();
        }
        return;
    }
    if (eq(name, "listen") or eq(name, "accept") or eq(name, "send")) {
        const sys_nr: usize = if (eq(name, "listen")) 50 else if (eq(name, "accept")) 43 else 44;
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
        const regs = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri: usize = arg_i;
        while (ri > 0) { ri -= 1;
            if (is_expr[ri]) { cb.popR(regs[ri]); }
            else if (args_list[ri] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[ri]))];
                cb.movRImm64(regs[ri], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, @as(u64, @intCast(sys_nr)));
        cb.syscall();
        return;
    }
    if (eq(name, "wavplay") or eq(name, "mp3play")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) { compileExprNode(ch, pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX);

        cb.movRImm64(cg.RAX, 57);
        cb.syscall();
        cb.cmpRImm32(cg.RAX, 0);
        const wp_parent = cb.pos;
        cb.jneRel32(0);

        cb.popR(cg.R8);

        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const wp_argv0 = "media_player\x00";
        cb.byte(@as(u8, @intCast(wp_argv0.len)));
        for (wp_argv0) |c| cb.byte(c);
        cb.movRR(cg.R9, cg.RAX);

        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const wp_exe = "./media_player\x00";
        cb.byte(@as(u8, @intCast(wp_exe.len)));
        for (wp_exe) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX);

        cb.movRImm64(cg.RAX, 0); cb.pushR(cg.RAX);
        cb.pushR(cg.R8);
        cb.pushR(cg.R9);

        cb.movRR(cg.RSI, cg.RSP);
        cb.xorRR(cg.RDX, cg.RDX);
        cb.movRImm64(cg.RAX, 59);
        cb.syscall();
        cb.movRImm64(cg.RDI, 1);
        cb.movRImm64(cg.RAX, 60);
        cb.syscall();

        const wp_parent_pos = cb.pos;
        patch32(cb, wp_parent + 2, @as(i32, @intCast(wp_parent_pos)) - @as(i32, @intCast(wp_parent + 6)));

        cb.subRImm32(cg.RSP, 16);
        cb.movRR(cg.RDI, cg.RAX);
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.movRImm64(cg.RDX, 0);
        cb.movRImm64(cg.R10, 0);
        cb.movRImm64(cg.RAX, 61);
        cb.syscall();
        cb.addRImm32(cg.RSP, 16);

        cb.addRImm32(cg.RSP, 8);
        cb.movRImm64(cg.RAX, 0);
        return;
    }
    if (eq(name, "playerapp")) {
        cb.movRImm64(cg.RAX, 57);
        cb.syscall();
        cb.cmpRImm32(cg.RAX, 0);
        const pp_parent = cb.pos;
        cb.jneRel32(0);

        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const pp_argv0 = "media_player\x00";
        cb.byte(@as(u8, @intCast(pp_argv0.len)));
        for (pp_argv0) |c| cb.byte(c);
        cb.movRR(cg.R9, cg.RAX);

        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const pp_exe = "./media_player\x00";
        cb.byte(@as(u8, @intCast(pp_exe.len)));
        for (pp_exe) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX);

        cb.movRImm64(cg.RAX, 0); cb.pushR(cg.RAX);
        cb.pushR(cg.R9);

        cb.movRR(cg.RSI, cg.RSP);
        cb.xorRR(cg.RDX, cg.RDX);
        cb.movRImm64(cg.RAX, 59);
        cb.syscall();
        cb.movRImm64(cg.RDI, 1);
        cb.movRImm64(cg.RAX, 60);
        cb.syscall();

        const pp_parent_pos = cb.pos;
        patch32(cb, pp_parent + 2, @as(i32, @intCast(pp_parent_pos)) - @as(i32, @intCast(pp_parent + 6)));

        cb.subRImm32(cg.RSP, 16);
        cb.movRR(cg.RDI, cg.RAX);
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.movRImm64(cg.RDX, 0);
        cb.movRImm64(cg.R10, 0);
        cb.movRImm64(cg.RAX, 61);
        cb.syscall();
        cb.addRImm32(cg.RSP, 16);

        cb.movRImm64(cg.RAX, 0);
        return;
    }
    if (eq(name, "guiApp") or eq(name, "guiapp")) {
        cb.movRImm64(cg.RAX, 57);
        cb.syscall();
        cb.cmpRImm32(cg.RAX, 0);
        const gp_parent = cb.pos;
        cb.jneRel32(0);

        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const gp_argv0 = "gui_srv\x00";
        cb.byte(@as(u8, @intCast(gp_argv0.len)));
        for (gp_argv0) |c| cb.byte(c);
        cb.movRR(cg.R9, cg.RAX);

        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const gp_exe = "./gui_srv\x00";
        cb.byte(@as(u8, @intCast(gp_exe.len)));
        for (gp_exe) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX);

        cb.movRImm64(cg.RAX, 0); cb.pushR(cg.RAX);
        cb.pushR(cg.R9);

        cb.movRR(cg.RSI, cg.RSP);
        cb.xorRR(cg.RDX, cg.RDX);
        cb.movRImm64(cg.RAX, 59);
        cb.syscall();
        cb.movRImm64(cg.RDI, 1);
        cb.movRImm64(cg.RAX, 60);
        cb.syscall();

        const gp_parent_pos = cb.pos;
        patch32(cb, gp_parent + 2, @as(i32, @intCast(gp_parent_pos)) - @as(i32, @intCast(gp_parent + 6)));

        cb.subRImm32(cg.RSP, 16);
        cb.movRR(cg.RDI, cg.RAX);
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.movRImm64(cg.RDX, 0);
        cb.movRImm64(cg.R10, 0);
        cb.movRImm64(cg.RAX, 61);
        cb.syscall();
        cb.addRImm32(cg.RSP, 16);

        cb.movRImm64(cg.RAX, 0);
        return;
    }
    if (eq(name, "waitpid")) {
        var wpid: i64 = -1;
        const wch = n.first_child;
        if (wch != parser_mod.NO_NODE) {
            const wcn = &pool[@as(usize, @intCast(wch))];
            if (wcn.kind == .int_lit) wpid = strToInt(wcn.val_start[0..wcn.val_len]);
        }
        cb.subRImm32(cg.RSP, 16);
        cb.movRImm64(cg.RDI, @as(u64, @bitCast(wpid)));
        cb.movRR(cg.RSI, cg.RSP);
        cb.xorRR(cg.RDX, cg.RDX);
        cb.xorRR(cg.R10, cg.R10);
        cb.movRImm64(cg.RAX, 61);
        cb.syscall();
        cb.addRImm32(cg.RSP, 16);
        return;
    }
    if (eq(name, "guiServer") or eq(name, "guiserver")) {
        // Read /proc/self/environ → build envp array for child (must be before execve)
        // Allocate 8KB: 4KB for env data + 4KB for envp pointers (up to 512 vars)
        cb.subRImm32(cg.RSP, 8192);
        cb.xorRR(cg.R12, cg.R12); // default NULL envp

        // lea rdi, [rip + "/proc/self/environ\0"]
        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const gsv_env_path = "/proc/self/environ\x00";
        cb.byte(@as(u8, @intCast(gsv_env_path.len)));
        for (gsv_env_path) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX);

        cb.xorRR(cg.RSI, cg.RSI);
        cb.movRImm64(cg.RAX, 2); // SYS_OPEN
        cb.syscall();
        cb.cmpRImm32(cg.RAX, 0);
        const env_skip_fd = cb.pos;
        cb.jlRel32(0); // jump if fd < 0

        cb.movRR(cg.R14, cg.RAX); // R14 = fd
        cb.leaRMem(cg.RSI, cg.RSP, 4096); // buf = RSP+4096
        cb.movRR(cg.RDI, cg.R14);
        cb.movRImm64(cg.RDX, 4096);
        cb.xorRR(cg.RAX, cg.RAX); // SYS_READ
        cb.syscall();
        cb.movRR(cg.R15, cg.RAX); // R15 = bytes read

        cb.movRR(cg.RDI, cg.R14);
        cb.movRImm64(cg.RAX, 3); // SYS_CLOSE
        cb.syscall();

        // Build envp array at RSP (each entry = 8 bytes)
        cb.movRR(cg.R12, cg.RSP); // R12 = envp base (saved for child)
        cb.movRR(cg.R14, cg.RSP); // R14 = envp write pointer (advances)
        cb.leaRMem(cg.RBX, cg.RSP, 4096); // RBX = scan pointer into env data

        // Outer loop: store each string pointer
        const env_loop = cb.pos;
        cb.byte(0x49); cb.byte(0x89); cb.byte(0x1E); // mov [r14], rbx
        cb.addRImm32(cg.R14, 8); // advance envp
        cb.jmpRel8(0); // → check_null (fwd, patched below)
        const env_fwd_jmp_pos = cb.pos - 2;

        // scan_next:
        cb.addRImm32(cg.RBX, 1); // advance scan pointer

        // check_null:
        const env_check_null = cb.pos;
        cb.byte(0x80); cb.byte(0x3B); cb.byte(0x00); // cmp byte [rbx], 0
        cb.jneRel8(0); // → scan_next (bwd, patched below)
        const env_jne_pos = cb.pos - 2;

        // found null — skip and count
        cb.addRImm32(cg.RBX, 1); // skip null byte
        // Check if we've reached the end of data
        cb.movRR(cg.RAX, cg.RBX);
        cb.subRR(cg.RAX, cg.RSP);
        cb.subRImm32(cg.RAX, 4096);
        cb.cmpRR(cg.RAX, cg.R15);
        const env_jl_pos = cb.pos;
        cb.jlRel32(0); // → env_loop (bwd, patched below)

        // Done: NULL terminator for envp
        cb.xorRR(cg.RAX, cg.RAX);
        cb.byte(0x49); cb.byte(0x89); cb.byte(0x06); // mov [r14], rax

        const env_done = cb.pos;
        // Patch jumps
        patch32(cb, env_jl_pos + 2, @as(i32, @intCast(env_loop)) - @as(i32, @intCast(env_jl_pos + 6)));
        // jne (backward to scan_next)
        const env_jne_tgt = env_fwd_jmp_pos + 2; // scan_next is right after the fwd jmp (add 2 for the jmp instruction itself)
        cb.buf[env_jne_pos + 1] = @as(u8, @bitCast(@as(i8, @intCast(@as(i32, @intCast(env_jne_tgt)) - @as(i32, @intCast(env_jne_pos + 2))))));
        // jmp (forward to check_null)
        const env_fwd_tgt = env_check_null;
        cb.buf[env_fwd_jmp_pos + 1] = @as(u8, @bitCast(@as(i8, @intCast(@as(i32, @intCast(env_fwd_tgt)) - @as(i32, @intCast(env_fwd_jmp_pos + 2))))));
        // jl (error: skip env setup)
        patch32(cb, env_skip_fd + 2, @as(i32, @intCast(env_done)) - @as(i32, @intCast(env_skip_fd + 6)));

        // pipe A: parent→child (commands)
        cb.subRImm32(cg.RSP, 8);
        cb.movRR(cg.RDI, cg.RSP);
        cb.xorRR(cg.RSI, cg.RSI);
        cb.movRImm64(cg.RAX, 22);
        cb.syscall();
        cb.popR(cg.R8);              // R8 = pipe_a_read | (pipe_a_write << 32)
        cb.movRR(cg.R9, cg.R8);
        cb.shrRImm8(cg.R9, 32);      // R9 = pipe_a_write

        // pipe B: child→parent (results)
        cb.subRImm32(cg.RSP, 8);
        cb.movRR(cg.RDI, cg.RSP);
        cb.xorRR(cg.RSI, cg.RSI);
        cb.movRImm64(cg.RAX, 22);
        cb.syscall();
        cb.popR(cg.R10);             // R10 = pipe_b_read | (pipe_b_write << 32)
        cb.movRR(cg.R11, cg.R10);
        cb.shrRImm8(cg.R11, 32);     // R11 = pipe_b_write

        // fork
        cb.movRImm64(cg.RAX, 57);
        cb.syscall();
        cb.cmpRImm32(cg.RAX, 0);
        const gsv_parent = cb.pos;
        cb.jneRel32(0);

        // child: dup2(pipe_a_read, 0), dup2(pipe_b_write, 1), close all, exec
        cb.movRR(cg.RDI, cg.R8);
        cb.movRImm64(cg.RSI, 0);
        cb.movRImm64(cg.RAX, 33);
        cb.syscall();
        cb.movRR(cg.RDI, cg.R11);
        cb.movRImm64(cg.RSI, 1);
        cb.movRImm64(cg.RAX, 33);
        cb.syscall();
        cb.movRR(cg.RDI, cg.R8);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();
        cb.movRR(cg.RDI, cg.R9);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();
        cb.movRR(cg.RDI, cg.R10);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();
        cb.movRR(cg.RDI, cg.R11);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();

        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const gsv_argv0 = "gui_srv\x00";
        cb.byte(@as(u8, @intCast(gsv_argv0.len)));
        for (gsv_argv0) |c| cb.byte(c);
        cb.movRR(cg.R9, cg.RAX);

        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const gsv_exe = "./gui_srv\x00";
        cb.byte(@as(u8, @intCast(gsv_exe.len)));
        for (gsv_exe) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX);

        cb.movRImm64(cg.RAX, 0); cb.pushR(cg.RAX);
        cb.pushR(cg.R9);

        cb.movRR(cg.RSI, cg.RSP);
        cb.movRR(cg.RDX, cg.R12); // envp = built array (R12=0 = NULL if open failed)
        cb.movRImm64(cg.RAX, 59);
        cb.syscall();
        cb.movRImm64(cg.RDI, 1);
        cb.movRImm64(cg.RAX, 60);
        cb.syscall();

        const gsv_parent_pos = cb.pos;
        patch32(cb, gsv_parent + 2, @as(i32, @intCast(gsv_parent_pos)) - @as(i32, @intCast(gsv_parent + 6)));

        // parent: close(pipe_a_read), close(pipe_b_write), return (pipe_b_read<<32)|pipe_a_write
        cb.movRR(cg.RDI, cg.R8);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();
        cb.movRR(cg.RDI, cg.R11);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();

        cb.addRImm32(cg.RSP, 8192); // restore stack (was sub'd for envp)
        cb.movRR(cg.RAX, cg.R10);
        cb.shlRImm8(cg.RAX, 32);
        cb.orRR(cg.RAX, cg.R9);
        return;
    }
    if (eq(name, "guiCmd") or eq(name, "guicmd")) {
        var gv: [8]i64 = .{0} ** 8;
        var label_buf: [32]u8 = .{0} ** 32;
        var fd_is_expr = false;
        var fd_expr_node: parser_mod.NodeIdx = parser_mod.NO_NODE;
        var is_expr: [8]bool = .{false} ** 8;
        var expr_nodes: [8]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 8;
        var expr_order: [7]usize = .{0} ** 7;
        var expr_count: usize = 0;

        var arg_idx: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_idx < 9) : (arg_idx += 1) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (arg_idx < 8) {
                if (cn.kind == .int_lit) {
                    gv[arg_idx] = strToInt(cn.val_start[0..cn.val_len]);
                } else if (arg_idx == 0) {
                    fd_is_expr = true;
                    fd_expr_node = ch;
                } else {
                    is_expr[arg_idx] = true;
                    expr_nodes[arg_idx] = ch;
                    expr_order[expr_count] = arg_idx;
                    expr_count += 1;
                }
            } else {
                if (cn.kind == .str_lit) {
                    var i: usize = 0;
                    while (i < 32 and i < cn.val_len) : (i += 1) {
                        label_buf[i] = cn.val_start[i];
                    }
                }
            }
            ch = cn.next_sibling;
        }

        cb.subRImm32(cg.RSP, 64);

        // Write label at offset 29 (4 x 8 bytes)
        var li: usize = 0;
        while (li < 4) : (li += 1) {
            var q: u64 = 0;
            var bi: usize = 0;
            while (bi < 8) : (bi += 1) {
                const idx = li * 8 + bi;
                q |= (@as(u64, if (idx < 32) label_buf[idx] else 0)) << @as(u6, @intCast(bi * 8));
            }
            cb.movRImm64(cg.RAX, q);
            cb.movMemR64(cg.RSP, @as(i32, @intCast(29 + li * 8)), cg.RAX);
        }

        // Compile expression args (indices 1..7) and push in order
        {
            var ei: usize = 0;
            while (ei < expr_count) : (ei += 1) {
                compileExprNode(expr_nodes[expr_order[ei]], pool, cb, vars, vc, errs);
                cb.pushR(cg.RAX);
            }
        }

        // Write constant values for args 1..7 (low to high offset)
        // type must be written before id to handle 4-byte overlap at offset 0
        if (!is_expr[1]) cb.movImm32RSP(0, @as(u32, @intCast(@as(u8, @intCast(gv[1])))));  // type @ 0
        if (!is_expr[2]) cb.movImm32RSP(1, @as(u32, @bitCast(@as(i32, @intCast(gv[2])))));  // id @ 1
        if (!is_expr[3]) cb.movImm32RSP(5, @as(u32, @bitCast(@as(i32, @intCast(gv[3])))));  // x @ 5
        if (!is_expr[4]) cb.movImm32RSP(9, @as(u32, @bitCast(@as(i32, @intCast(gv[4])))));  // y @ 9
        if (!is_expr[5]) cb.movImm32RSP(13, @as(u32, @bitCast(@as(i32, @intCast(gv[5]))))); // w @ 13
        if (!is_expr[6]) cb.movImm32RSP(17, @as(u32, @bitCast(@as(i32, @intCast(gv[6]))))); // h @ 17
        if (!is_expr[7]) {
            const val_u64 = @as(u64, @bitCast(gv[7]));
            cb.movRImm64(cg.RAX, val_u64);
            cb.movMemR64(cg.RSP, 21, cg.RAX);  // val @ 21
        }

        // Pop expression values in reverse order and write to struct
        {
            var pi: usize = expr_count;
            while (pi > 0) {
                pi -= 1;
                const ea = expr_order[pi];
                cb.popR(cg.RAX);
                if (ea == 7) {
                    cb.movMemR64(cg.RSP, 21, cg.RAX);  // val @ 21
                } else if (ea == 1) {
                    cb.byte(0x88); cb.byte(0x44); cb.byte(0x24); cb.byte(0x00); // mov [rsp+0], al
                } else {
                    const off: i32 = if (ea == 2) 1 else if (ea == 3) 5 else if (ea == 4) 9 else if (ea == 5) 13 else 17;
                    cb.movMemR32(cg.RSP, off, cg.RAX);
                }
            }
        }

        // Set up write syscall using fd (expression or constant)
        if (fd_is_expr) {
            compileExprNode(fd_expr_node, pool, cb, vars, vc, errs);
            cb.byte(0x89); cb.byte(0xC7); // mov edi, eax (32-bit, zero-extends → correct fd)
        } else {
            cb.movRImm64(cg.RDI, @as(u64, @intCast(gv[0])));
        }
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.movRImm64(cg.RDX, 61);
        cb.movRImm64(cg.RAX, 1);
        cb.syscall();
        cb.addRImm32(cg.RSP, 64);
        return;
      }
      if (eq(name, "setTheme")) {
         // setTheme(fd, theme_id) -> sends CMD_SET_THEME to gui_srv
         // fd: file descriptor to write to (gui_srv write end from guiServer)
         // theme_id: 0=dark, 1=light, 2=modern_dark, 3=modern_light
         var gv: [8]i64 = .{0} ** 8;
         var is_expr: [8]bool = .{false} ** 8;
         var expr_nodes: [8]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 8;
         var expr_order: [7]usize = .{0} ** 7;
         var expr_count: usize = 0;

         var arg_idx: usize = 0;
         var ch = n.first_child;
         while (ch != parser_mod.NO_NODE and arg_idx < 2) : (arg_idx += 1) {
             const cn = &pool[@as(usize, @intCast(ch))];
             if (cn.kind == .int_lit) {
                 gv[arg_idx] = strToInt(cn.val_start[0..cn.val_len]);
             } else {
                 is_expr[arg_idx] = true;
                 expr_nodes[arg_idx] = ch;
                 expr_order[expr_count] = arg_idx;
                 expr_count += 1;
             }
             ch = cn.next_sibling;
         }

         cb.subRImm32(cg.RSP, 64);

         // Write label (empty string) at offset 29 (4 x 8 bytes of 0)
         var li: usize = 0;
         while (li < 4) : (li += 1) {
             cb.movRImm64(cg.RAX, 0);
             cb.movMemR64(cg.RSP, @as(i32, @intCast(29 + li * 8)), cg.RAX);
         }

         // Compile expression args (fd at index 0, theme_id at index 1)
         {
             var ei: usize = 0;
             while (ei < expr_count) : (ei += 1) {
                 compileExprNode(expr_nodes[expr_order[ei]], pool, cb, vars, vc, errs);
                 cb.pushR(cg.RAX);
             }
         }

         // Write constant values for args 0..7
         // fd @ offset 0 is handled specially below (used for syscall)
         // type @ offset 0
         cb.movImm32RSP(0, @as(u32, 13));  // CMD_SET_THEME = 13
         // id @ offset 1 (theme_id)
         if (!is_expr[1]) cb.movImm32RSP(1, @as(u32, @bitCast(@as(i32, @intCast(gv[1])))));  // id @ 1
         // x @ offset 5
         cb.movImm32RSP(5, 0);  // unused
         // y @ offset 9
         cb.movImm32RSP(9, 0);  // unused
         // w @ offset 13
         cb.movImm32RSP(13, 0); // unused
         // h @ offset 17
         cb.movImm32RSP(17, 0); // unused
         // val @ offset 21
         cb.movRImm64(cg.RAX, 0);
         cb.movMemR64(cg.RSP, 21, cg.RAX);  // unused

         // Pop expression values in reverse order and write to struct
         {
             var pi: usize = expr_count;
             while (pi > 0) {
                 pi -= 1;
                 const ea = expr_order[pi];
                 cb.popR(cg.RAX);
                 if (ea == 0) {
                     // fd -> will be used for syscall, don't write to struct
                 } else if (ea == 1) {
                     // theme_id -> id field at offset 1
                     cb.movMemR32(cg.RSP, 1, cg.RAX);
                 }
             }
         }

         // Set up write syscall using fd (expression or constant)
         if (is_expr[0]) {
             compileExprNode(expr_nodes[expr_order[0]], pool, cb, vars, vc, errs);
             cb.byte(0x89); cb.byte(0xC7); // mov edi, eax
         } else {
             cb.movRImm64(cg.RDI, @as(u64, @intCast(gv[0])));
         }
         cb.leaRMem(cg.RSI, cg.RSP, 0);
         cb.movRImm64(cg.RDX, 61);
         cb.movRImm64(cg.RAX, 1);
         cb.syscall();
         cb.addRImm32(cg.RSP, 64);
         return;
      }
      if (eq(name, "audioplay")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) { compileExprNode(ch, pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX);

        cb.movRImm64(cg.RAX, 57);
        cb.syscall();
        cb.cmpRImm32(cg.RAX, 0);
        const aud_parent = cb.pos;
        cb.jneRel32(0);

        cb.popR(cg.R8);

        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const aud_argv0 = "media_player\x00";
        cb.byte(@as(u8, @intCast(aud_argv0.len)));
        for (aud_argv0) |c| cb.byte(c);
        cb.movRR(cg.R9, cg.RAX);

        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const aud_exe = "./media_player\x00";
        cb.byte(@as(u8, @intCast(aud_exe.len)));
        for (aud_exe) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX);

        // Push argv in reverse: argv[2]=NULL, [1]=path, [0]="media_player"
        cb.movRImm64(cg.RAX, 0); cb.pushR(cg.RAX); // argv[2] = NULL
        cb.pushR(cg.R8);                            // argv[1] = path
        cb.pushR(cg.R9);                            // argv[0] = "media_player"

        cb.movRR(cg.RSI, cg.RSP);
        cb.xorRR(cg.RDX, cg.RDX);
        cb.movRImm64(cg.RAX, 59);
        cb.syscall();
        cb.movRImm64(cg.RDI, 1);
        cb.movRImm64(cg.RAX, 60);
        cb.syscall();

        const aud_parent_pos = cb.pos;
        patch32(cb, aud_parent + 2, @as(i32, @intCast(aud_parent_pos)) - @as(i32, @intCast(aud_parent + 6)));

        cb.subRImm32(cg.RSP, 16);
        cb.movRR(cg.RDI, cg.RAX);
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.movRImm64(cg.RDX, 0);
        cb.movRImm64(cg.R10, 0);
        cb.movRImm64(cg.RAX, 61);
        cb.syscall();
        cb.addRImm32(cg.RSP, 16);

        cb.addRImm32(cg.RSP, 8);
        cb.movRImm64(cg.RAX, 0);
        return;
    }
    if (eq(name, "audio_init")) {
        // audio_init(rate, channels, fmt) -> returns dsp_fd (or -1)
        var ai: usize = 0; var av: [3]i64 = .{44100, 2, 0x10};
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and ai < 3) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (cn.kind == .int_lit) av[ai] = strToInt(cn.val_start[0..cn.val_len]);
            ai += 1; ch = cn.next_sibling;
        }
        // embed "/dev/dsp\0"
        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2);
        cb.byte(0xEB);
        const dsp_str2 = "/dev/dsp\x00";
        cb.byte(@as(u8, @intCast(dsp_str2.len)));
        for (dsp_str2) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX);
        cb.movRImm64(cg.RSI, 2);
        cb.movRImm64(cg.RAX, 2);
        cb.syscall();
        cb.pushR(cg.RAX); // dsp_fd

        // reset
        cb.movRR(cg.RDI, cg.RAX);
        cb.movRImm64(cg.RSI, 0x80005000);
        cb.movRImm64(cg.RDX, 0);
        cb.movRImm64(cg.RAX, 16);
        cb.syscall();

        // format
        cb.popR(cg.RDI);
        cb.pushR(cg.RDI);
        cb.subRImm32(cg.RSP, 16);
        cb.movImm32RSP(0, @as(u32, @intCast(av[2])));
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.movRImm64(cg.RDX, 4);
        cb.movRImm64(cg.RAX, 16);
        cb.syscall();
        cb.addRImm32(cg.RSP, 16);

        // channels
        cb.popR(cg.RDI);
        cb.pushR(cg.RDI);
        cb.subRImm32(cg.RSP, 16);
        cb.movImm32RSP(0, @as(u32, @intCast(av[1])));
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.movRImm64(cg.RDX, 4);
        cb.movRImm64(cg.RAX, 16);
        cb.syscall();
        cb.addRImm32(cg.RSP, 16);

        // speed
        cb.popR(cg.RDI);
        cb.subRImm32(cg.RSP, 16);
        cb.movImm32RSP(0, @as(u32, @intCast(av[0])));
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.movRImm64(cg.RDX, 4);
        cb.movRImm64(cg.RAX, 16);
        cb.syscall();
        cb.addRImm32(cg.RSP, 16);

        // dsp_fd still in RDI -> RAX for return
        cb.movRR(cg.RAX, cg.RDI);
        return;
    }
    if (eq(name, "audio_write")) {
        // audio_write(fd, ptr, len)
        var is_expr: [6]bool = .{false} ** 6;
        var args_list: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 6) {
            args_list[arg_i] = ch;
            const cn = &pool[@as(usize, @intCast(ch))];
            is_expr[arg_i] = cn.kind != .int_lit;
            arg_i += 1; ch = cn.next_sibling;
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, errs); cb.pushR(cg.RAX); } }
        const regs_aw = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri_aw: usize = arg_i;
        while (ri_aw > 0) { ri_aw -= 1;
            if (is_expr[ri_aw]) { cb.popR(regs_aw[ri_aw]); }
            else if (args_list[ri_aw] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[ri_aw]))];
                cb.movRImm64(regs_aw[ri_aw], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, 1);
        cb.syscall();
        return;
    }
    if (eq(name, "audio_close")) {
        // audio_close(fd)
        var fd: i64 = 0;
        const ch2 = n.first_child;
        if (ch2 != parser_mod.NO_NODE) {
            const cn = &pool[@as(usize, @intCast(ch2))];
            if (cn.kind == .int_lit) fd = strToInt(cn.val_start[0..cn.val_len]);
        }
        cb.movRImm64(cg.RDI, @as(u64, @intCast(fd)));
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();
        return;
    }
    if (eq(name, "audio_pause") or eq(name, "audio_stop")) {
        // audio_stop(fd) - close DSP temporarily (ioctl reset)
        var fd: i64 = 0;
        const ch3 = n.first_child;
        if (ch3 != parser_mod.NO_NODE) {
            const cn = &pool[@as(usize, @intCast(ch3))];
            if (cn.kind == .int_lit) fd = strToInt(cn.val_start[0..cn.val_len]);
        }
        cb.movRImm64(cg.RDI, @as(u64, @intCast(fd)));
        cb.movRImm64(cg.RSI, 0x80005000);
        cb.movRImm64(cg.RDX, 0);
        cb.movRImm64(cg.RAX, 16);
        cb.syscall();
        return;
    }
    if (eq(name, "audio_play")) {
        // audio_play(fd) - unmute/resume after stop
        var fd: i64 = 0;
        const ch4 = n.first_child;
        if (ch4 != parser_mod.NO_NODE) {
            const cn = &pool[@as(usize, @intCast(ch4))];
            if (cn.kind == .int_lit) fd = strToInt(cn.val_start[0..cn.val_len]);
        }
        cb.movRImm64(cg.RDI, @as(u64, @intCast(fd)));
        cb.movRImm64(cg.RSI, 0x80045005); // SNDCTL_DSP_SETFMT just to resume
        cb.subRImm32(cg.RSP, 16);
        cb.movImm32RSP(0, 0x10); // AFMT_S16_LE
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.movRImm64(cg.RDX, 4);
        cb.movRImm64(cg.RAX, 16);
        cb.syscall();
        cb.addRImm32(cg.RSP, 16);
        return;
    }
    // --- Framebuffer built-ins ---
    if (eq(name, "fb_open")) {
        // Allocate struct {fb_ptr, fd, xres, yres} + var_info buffer
        cb.subRImm32(cg.RSP, 232); // 32 struct + 200 var_info

        // open /dev/fb0
        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const fb_str = "/dev/fb0\x00";
        cb.byte(@as(u8, @intCast(fb_str.len)));
        for (fb_str) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX);
        cb.movRImm64(cg.RSI, 2);
        cb.movRImm64(cg.RAX, 2);
        cb.syscall();
        cb.movMemR64(cg.RSP, 8, cg.RAX); // struct.fd at +8

        // mmap 8MB
        cb.movRImm64(cg.RDI, 0);
        cb.movRImm64(cg.RSI, 0x800000);
        cb.movRImm64(cg.RDX, 3);
        cb.movRImm64(cg.R10, 1);
        cb.movRMem64(cg.R8, cg.RSP, 8); // fd
        cb.movRImm64(cg.R9, 0);
        cb.movRImm64(cg.RAX, 9);
        cb.syscall();
        cb.movMemR64(cg.RSP, 0, cg.RAX); // struct.fb_ptr at +0

        // ioctl FBIOGET_VSCREENINFO
        cb.movRMem64(cg.RDI, cg.RSP, 8); // fd
        cb.movRImm64(cg.RSI, 0x4600);
        cb.leaRMem(cg.RDX, cg.RSP, 32); // var_info after struct
        cb.movRImm64(cg.RAX, 16);
        cb.syscall();
        // read xres = var_info[0], yres = var_info[4]
        cb.movRMem64(cg.R8, cg.RSP, 32 + 0);
        cb.movMemR64(cg.RSP, 16, cg.R8); // struct.xres at +16
        cb.movRMem64(cg.R8, cg.RSP, 32 + 4);
        cb.movMemR64(cg.RSP, 24, cg.R8); // struct.yres at +24

        // return RSP (struct pointer)
        cb.movRR(cg.RAX, cg.RSP);
        return;
    }
    if (eq(name, "fb_close")) {
        const ch5 = n.first_child;
        if (ch5 != parser_mod.NO_NODE) { compileExprNode(ch5, pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        // struct {fb_ptr, fd, xres, yres}
        // fb_ptr at +0, fd at +8
        cb.pushR(cg.RAX);
        cb.movRMem64(cg.RDI, cg.RAX, 8); // fd
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();
        cb.popR(cg.RAX);
        cb.movRMem64(cg.RDI, cg.RAX, 0); // fb_ptr
        cb.movRImm64(cg.RSI, 0x800000);
        cb.movRImm64(cg.RAX, 11);
        cb.syscall();
        cb.movRImm64(cg.RAX, 0);
        return;
    }
    if (eq(name, "fb_width")) {
        const ch6 = n.first_child;
        if (ch6 != parser_mod.NO_NODE) { compileExprNode(ch6, pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        // struct: {fb_ptr, fd, xres, yres} at RAX
        // xres at +16
        cb.movRMem64(cg.RAX, cg.RAX, 16);
        return;
    }
    if (eq(name, "fb_height")) {
        const ch7 = n.first_child;
        if (ch7 != parser_mod.NO_NODE) { compileExprNode(ch7, pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        // yres at +24
        cb.movRMem64(cg.RAX, cg.RAX, 24);
        return;
    }
    if (eq(name, "fb_pixel")) {
        var arg_i_fb: usize = 0;
        var args_list_fb: [4]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 4;
        var ch_fb = n.first_child;
        while (ch_fb != parser_mod.NO_NODE and arg_i_fb < 4) {
            args_list_fb[arg_i_fb] = ch_fb;
            ch_fb = pool[@as(usize, @intCast(ch_fb))].next_sibling;
            arg_i_fb += 1;
        }
        if (args_list_fb[0] != parser_mod.NO_NODE) { compileExprNode(args_list_fb[0], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        // struct: {fb_ptr, fd, xres, yres}
        cb.movRMem64(cg.R14, cg.RAX, 0);  // fb_ptr
        cb.movRMem64(cg.RDI, cg.RAX, 16); // width (xres)

        if (args_list_fb[1] != parser_mod.NO_NODE) { compileExprNode(args_list_fb[1], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX);
        if (args_list_fb[2] != parser_mod.NO_NODE) { compileExprNode(args_list_fb[2], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX);
        if (args_list_fb[3] != parser_mod.NO_NODE) { compileExprNode(args_list_fb[3], pool, cb, vars, vc, errs); } else { cb.movRImm64(cg.RAX, 0xFFFFFFFF); }

        cb.popR(cg.RCX);
        cb.popR(cg.RDX);
        // RCX = y, RDX = x
        cb.imulRR(cg.RCX, cg.RDI);
        cb.addRR(cg.RCX, cg.RDX);
        cb.shlRImm8(cg.RCX, 2);
        cb.addRR(cg.RCX, cg.R14);
        cb.movMemR64(cg.RCX, 0, cg.RAX);
        cb.movRImm64(cg.RAX, 0);
        return;
    }
    if (eq(name, "fb_fill")) {
        var arg_i_fbf: usize = 0;
        var args_list_fbf: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var ch_fbf = n.first_child;
        while (ch_fbf != parser_mod.NO_NODE and arg_i_fbf < 6) {
            args_list_fbf[arg_i_fbf] = ch_fbf;
            ch_fbf = pool[@as(usize, @intCast(ch_fbf))].next_sibling;
            arg_i_fbf += 1;
        }
        if (args_list_fbf[0] != parser_mod.NO_NODE) { compileExprNode(args_list_fbf[0], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        // struct: {fb_ptr, fd, xres, yres}
        cb.movRMem64(cg.R14, cg.RAX, 0);  // fb_ptr
        cb.movRMem64(cg.RDI, cg.RAX, 16); // width (xres)

        if (args_list_fbf[1] != parser_mod.NO_NODE) { compileExprNode(args_list_fbf[1], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX);
        if (args_list_fbf[2] != parser_mod.NO_NODE) { compileExprNode(args_list_fbf[2], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX);
        if (args_list_fbf[3] != parser_mod.NO_NODE) { compileExprNode(args_list_fbf[3], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX);
        if (args_list_fbf[4] != parser_mod.NO_NODE) { compileExprNode(args_list_fbf[4], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX);
        if (args_list_fbf[5] != parser_mod.NO_NODE) { compileExprNode(args_list_fbf[5], pool, cb, vars, vc, errs); } else { cb.movRImm64(cg.RAX, 0xFFFFFFFF); }

        cb.popR(cg.R15);
        cb.popR(cg.R11);
        cb.popR(cg.R10);
        cb.popR(cg.R9);
        cb.popR(cg.R8);

        cb.xorRR(cg.R12, cg.R12);
        const fb_fill_y_loop = cb.pos;
        cb.cmpRR(cg.R12, cg.R11);
        const fb_fill_y_done = cb.pos;
        cb.jgeRel32(0);

        cb.xorRR(cg.R13, cg.R13);
        const fb_fill_x_check = cb.pos;
        cb.cmpRR(cg.R13, cg.R10);
        const fb_fill_x_done = cb.pos;
        cb.jgeRel32(0);

        cb.movRR(cg.RAX, cg.R9);
        cb.addRR(cg.RAX, cg.R12);
        cb.imulRR(cg.RAX, cg.RDI);
        cb.addRR(cg.RAX, cg.R8);
        cb.addRR(cg.RAX, cg.R13);
        cb.shlRImm8(cg.RAX, 2);
        cb.addRR(cg.RAX, cg.R14);
        cb.movMemR64(cg.RAX, 0, cg.R15);

        cb.addRImm32(cg.R13, 1);
        cb.jmpRel32(@as(i32, @intCast(fb_fill_x_check)) - @as(i32, @intCast(cb.pos + 5)));

        const fb_fill_x_end = cb.pos;
        patch32(cb, fb_fill_x_done + 2, @as(i32, @intCast(fb_fill_x_end)) - @as(i32, @intCast(fb_fill_x_done + 6)));

        cb.addRImm32(cg.R12, 1);
        cb.jmpRel32(@as(i32, @intCast(fb_fill_y_loop)) - @as(i32, @intCast(cb.pos + 5)));

        const fb_fill_y_end = cb.pos;
        patch32(cb, fb_fill_y_done + 2, @as(i32, @intCast(fb_fill_y_end)) - @as(i32, @intCast(fb_fill_y_done + 6)));

        cb.movRImm64(cg.RAX, 0);
        return;
    }
    if (eq(name, "android_width")) {
        cb.movRImm64(cg.RDI, 0x200100);
        cb.movRMem64(cg.RAX, cg.RDI, 36);
        return;
    }
    if (eq(name, "android_height")) {
        cb.movRImm64(cg.RDI, 0x200100);
        cb.movRMem64(cg.RAX, cg.RDI, 40);
        return;
    }
    if (eq(name, "android_should_finish")) {
        cb.movRImm64(cg.RDI, 0x200100);
        cb.movRMem64(cg.RAX, cg.RDI, 32);
        return;
    }
    if (eq(name, "android_has_focus")) {
        cb.movRImm64(cg.RDI, 0x200100);
        cb.movRMem64(cg.RAX, cg.RDI, 28);
        return;
    }
    if (eq(name, "android_touch_x")) {
        cb.movRImm64(cg.RDI, 0x200100);
        cb.movRMem64(cg.RAX, cg.RDI, 56);
        return;
    }
    if (eq(name, "android_touch_y")) {
        cb.movRImm64(cg.RDI, 0x200100);
        cb.movRMem64(cg.RAX, cg.RDI, 60);
        return;
    }
    if (eq(name, "android_touch_down")) {
        cb.movRImm64(cg.RDI, 0x200100);
        cb.movRMem64(cg.RAX, cg.RDI, 64);
        return;
    }
    if (eq(name, "android_fb_ptr")) {
        cb.movRImm64(cg.RDI, 0x200100);
        cb.movRMem64(cg.RAX, cg.RDI, 48);
        return;
    }
    if (eq(name, "android_stride")) {
        cb.movRImm64(cg.RDI, 0x200100);
        cb.movRMem64(cg.RAX, cg.RDI, 44);
        return;
    }
    if (eq(name, "android_pixel")) {
        var aargs: [4]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 4;
        var ac: usize = 0;
        var achild = n.first_child;
        while (achild != parser_mod.NO_NODE and ac < 4) {
            aargs[ac] = achild;
            achild = pool[@as(usize, @intCast(achild))].next_sibling;
            ac += 1;
        }
        if (aargs[0] != parser_mod.NO_NODE) { compileExprNode(aargs[0], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX);
        if (aargs[1] != parser_mod.NO_NODE) { compileExprNode(aargs[1], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX);
        if (aargs[2] != parser_mod.NO_NODE) { compileExprNode(aargs[2], pool, cb, vars, vc, errs); } else { cb.movRImm64(cg.RAX, 0xFFFFFFFF); }
        cb.popR(cg.RCX);
        cb.popR(cg.R8);
        // read fb_pixels ptr from cmd+48, stride from cmd+44
        cb.movRImm64(cg.RDI, 0x200100);
        cb.movRMem64(cg.R9, cg.RDI, 44); // stride
        cb.movRMem64(cg.RDI, cg.RDI, 48); // fb_pixels ptr
        cb.imulRR(cg.R8, cg.R9);
        cb.addRR(cg.R8, cg.RCX);
        cb.shlRImm8(cg.R8, 2);
        cb.addRR(cg.RDI, cg.R8);
        cb.movMemR64(cg.RDI, 0, cg.RAX);
        cb.movRImm64(cg.RAX, 0);
        return;
    }
    if (eq(name, "android_rect")) {
        var raargs: [5]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 5;
        var rac: usize = 0;
        var rachild = n.first_child;
        while (rachild != parser_mod.NO_NODE and rac < 5) {
            raargs[rac] = rachild;
            rachild = pool[@as(usize, @intCast(rachild))].next_sibling;
            rac += 1;
        }
        if (raargs[0] != parser_mod.NO_NODE) { compileExprNode(raargs[0], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX); // x
        if (raargs[1] != parser_mod.NO_NODE) { compileExprNode(raargs[1], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX); // y
        if (raargs[2] != parser_mod.NO_NODE) { compileExprNode(raargs[2], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX); // w
        if (raargs[3] != parser_mod.NO_NODE) { compileExprNode(raargs[3], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX); // h
        if (raargs[4] != parser_mod.NO_NODE) { compileExprNode(raargs[4], pool, cb, vars, vc, errs); } else { cb.movRImm64(cg.RAX, 0xFFFFFFFF); }
        cb.pushR(cg.RAX); // color

        // Read fb_pixels ptr and stride from fixed addresses
        cb.movRImm64(cg.RDI, 0x200100);
        cb.movRMem64(cg.RDI, cg.RDI, 48); // RDI = fb_pixels ptr
        cb.movRImm64(cg.RSI, 0x200100);
        cb.movRMem64(cg.RSI, cg.RSI, 44); // RSI = stride

        // Pop args: color, h, w, y, x
        cb.popR(cg.R15); // color
        cb.popR(cg.R14); // h
        cb.popR(cg.R13); // w
        cb.popR(cg.R12); // y
        cb.popR(cg.R11); // x

        // R10 = dy = 0
        cb.xorRR(cg.R10, cg.R10);
        const rect_y_loop = cb.pos;
        cb.cmpRR(cg.R10, cg.R14);
        const rect_y_done = cb.pos;
        cb.jgeRel32(0);

        // R8 = line_start = pixels + (y + dy) * stride
        cb.movRR(cg.R8, cg.R12);
        cb.addRR(cg.R8, cg.R10);
        cb.imulRR(cg.R8, cg.RSI);
        cb.addRR(cg.R8, cg.RDI);

        // R9 = dx = 0
        cb.xorRR(cg.R9, cg.R9);
        const rect_x_loop = cb.pos;
        cb.cmpRR(cg.R9, cg.R13);
        const rect_x_done = cb.pos;
        cb.jgeRel32(0);

        // pixel at (x + dx)
        cb.movRR(cg.RAX, cg.R11);
        cb.addRR(cg.RAX, cg.R9);
        cb.shlRImm8(cg.RAX, 2);
        cb.addRR(cg.RAX, cg.R8);
        cb.movMemR64(cg.RAX, 0, cg.R15);

        cb.addRImm32(cg.R9, 1);
        cb.jmpRel32(@as(i32, @intCast(rect_x_loop)) - @as(i32, @intCast(cb.pos + 5)));

        const rect_x_end = cb.pos;
        patch32(cb, rect_x_done + 2, @as(i32, @intCast(rect_x_end)) - @as(i32, @intCast(rect_x_done + 6)));

        cb.addRImm32(cg.R10, 1);
        cb.jmpRel32(@as(i32, @intCast(rect_y_loop)) - @as(i32, @intCast(cb.pos + 5)));

        const rect_y_end = cb.pos;
        patch32(cb, rect_y_done + 2, @as(i32, @intCast(rect_y_end)) - @as(i32, @intCast(rect_y_done + 6)));

        cb.movRImm64(cg.RAX, 0);
        return;
     }
     if (eq(name, "android_touch_count")) {
         cb.movRImm64(cg.RDI, 0x200100 + 164);
         cb.movRMem64(cg.RAX, cg.RDI, 0);
         return;
     }
     if (eq(name, "android_touch_x_index")) {
         // android_touch_x_index(index) -> f32
         var aargs: [1]parser_mod.NodeIdx = .{parser_mod.NO_NODE};
         var ac: usize = 0;
         var achild = n.first_child;
         while (achild != parser_mod.NO_NODE and ac < 1) {
             aargs[ac] = achild;
             achild = pool[@as(usize, @intCast(achild))].next_sibling;
             ac += 1;
         }
         if (aargs[0] != parser_mod.NO_NODE) { compileExprNode(aargs[0], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
         cb.pushR(cg.RAX); // index
         cb.popR(cg.R8);   // R8 = index
         // compute offset = 168 + index*4
         cb.movRImm64(cg.R9, 4);
         cb.imulRR(cg.R9, cg.R8); // R9 = index*4
         cb.movRImm64(cg.RDI, 0x200100 + 168);
         cb.addRR(cg.RDI, cg.R9); // RDI = address
         cb.movRMem64(cg.RAX, cg.RDI, 0); // load f32 bits
         return;
     }
     if (eq(name, "android_touch_y_index")) {
         var aargs: [1]parser_mod.NodeIdx = .{parser_mod.NO_NODE};
         var ac: usize = 0;
         var achild = n.first_child;
         while (achild != parser_mod.NO_NODE and ac < 1) {
             aargs[ac] = achild;
             achild = pool[@as(usize, @intCast(achild))].next_sibling;
             ac += 1;
         }
         if (aargs[0] != parser_mod.NO_NODE) { compileExprNode(aargs[0], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
         cb.pushR(cg.RAX); // index
         cb.popR(cg.R8);
         cb.movRImm64(cg.R9, 4);
         cb.imulRR(cg.R9, cg.R8);
         cb.movRImm64(cg.RDI, 0x200100 + 232);
         cb.addRR(cg.RDI, cg.R9);
         cb.movRMem64(cg.RAX, cg.RDI, 0);
         return;
     }
     if (eq(name, "android_touch_down_index")) {
         var aargs: [1]parser_mod.NodeIdx = .{parser_mod.NO_NODE};
         var ac: usize = 0;
         var achild = n.first_child;
         while (achild != parser_mod.NO_NODE and ac < 1) {
             aargs[ac] = achild;
             achild = pool[@as(usize, @intCast(achild))].next_sibling;
             ac += 1;
         }
         if (aargs[0] != parser_mod.NO_NODE) { compileExprNode(aargs[0], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
         cb.pushR(cg.RAX);
         cb.popR(cg.R8);
         cb.movRImm64(cg.R9, 4);
         cb.imulRR(cg.R9, cg.R8);
         cb.movRImm64(cg.RDI, 0x200100 + 296);
         cb.addRR(cg.RDI, cg.R9);
         cb.movRMem64(cg.RAX, cg.RDI, 0);
         return;
     }
     if (eq(name, "android_touch_id_index")) {
         var aargs: [1]parser_mod.NodeIdx = .{parser_mod.NO_NODE};
         var ac: usize = 0;
         var achild = n.first_child;
         while (achild != parser_mod.NO_NODE and ac < 1) {
             aargs[ac] = achild;
             achild = pool[@as(usize, @intCast(achild))].next_sibling;
             ac += 1;
         }
         if (aargs[0] != parser_mod.NO_NODE) { compileExprNode(aargs[0], pool, cb, vars, vc, errs); } else { cb.xorRR(cg.RAX, cg.RAX); }
         cb.pushR(cg.RAX);
         cb.popR(cg.R8);
         cb.movRImm64(cg.R9, 4);
         cb.imulRR(cg.R9, cg.R8);
         cb.movRImm64(cg.RDI, 0x200100 + 360);
         cb.addRR(cg.RDI, cg.R9);
         cb.movRMem64(cg.RAX, cg.RDI, 0);
         return;
     }
     if (eq(name, "resolve") or eq(name, "resolve_hostname")) {
        // resolve(hostname_ptr) → u32 ip (fork+exec http_client resolve hostname)
        const rch = n.first_child;
        if (rch != parser_mod.NO_NODE) { compileExprNode(rch, pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX); // hostname ptr

        // Create pipe to read result
        cb.subRImm32(cg.RSP, 8);
        cb.movRR(cg.RDI, cg.RSP);
        cb.xorRR(cg.RSI, cg.RSI);
        cb.movRImm64(cg.RAX, 22); // SYS_PIPE
        cb.syscall();
        cb.popR(cg.R12); // R12 = pipe_read | (pipe_write << 32)
        cb.movRR(cg.R13, cg.R12);
        cb.shrRImm8(cg.R13, 32); // R13 = pipe_write

        // fork
        cb.movRImm64(cg.RAX, 57);
        cb.syscall();
        cb.cmpRImm32(cg.RAX, 0);
        const res_parent = cb.pos;
        cb.jneRel32(0);

        // child
        cb.movRR(cg.RDI, cg.R12); // close pipe_read
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();
        cb.movRR(cg.RDI, cg.R13); // dup2(pipe_write, 1)
        cb.movRImm64(cg.RSI, 1);
        cb.movRImm64(cg.RAX, 33);
        cb.syscall();
        cb.movRR(cg.RDI, cg.R13); // close pipe_write
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();

        cb.popR(cg.R8); // hostname ptr

        // argv[2] = host, argv[1] = "resolve", argv[0] = "http_client"
        cb.movRImm64(cg.RAX, 0); cb.pushR(cg.RAX); // argv[3] = NULL
        cb.pushR(cg.R8);  // argv[2] = hostname
        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const res_str = "resolve\x00";
        cb.byte(@as(u8, @intCast(res_str.len)));
        for (res_str) |c| cb.byte(c);
        cb.pushR(cg.RAX); // argv[1] = "resolve"
        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const res_argv0 = "http_client\x00";
        cb.byte(@as(u8, @intCast(res_argv0.len)));
        for (res_argv0) |c| cb.byte(c);
        cb.pushR(cg.RAX);
        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const res_exe = "./http_client\x00";
        cb.byte(@as(u8, @intCast(res_exe.len)));
        for (res_exe) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX);
        cb.movRR(cg.RSI, cg.RSP);
        cb.xorRR(cg.RDX, cg.RDX);
        cb.movRImm64(cg.RAX, 59);
        cb.syscall();
        cb.movRImm64(cg.RDI, 1);
        cb.movRImm64(cg.RAX, 60);
        cb.syscall();

        const res_parent_pos = cb.pos;
        patch32(cb, res_parent + 2, @as(i32, @intCast(res_parent_pos)) - @as(i32, @intCast(res_parent + 6)));

        // parent: close pipe_write, read 4 bytes from pipe_read
        cb.movRR(cg.RDI, cg.R13);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();

        // Read result
        cb.subRImm32(cg.RSP, 16);
        cb.movRR(cg.RDI, cg.R12);
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.movRImm64(cg.RDX, 4);
        cb.xorRR(cg.RAX, cg.RAX);
        cb.syscall();

        // Close pipe_read
        cb.movRR(cg.RDI, cg.R12);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();

        // Wait for child
        cb.subRImm32(cg.RSP, 16);
        cb.movRR(cg.RDI, cg.RAX);
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.xorRR(cg.RDX, cg.RDX);
        cb.xorRR(cg.R10, cg.R10);
        cb.movRImm64(cg.RAX, 61);
        cb.syscall();
        cb.addRImm32(cg.RSP, 16);

        // Read IP from stack buffer
        cb.xorRR(cg.RAX, cg.RAX);
        cb.byte(0x8A); cb.byte(0x04); cb.byte(0x24); // mov al, [rsp]
        cb.movRR(cg.R8, cg.RAX);
        cb.byte(0x8A); cb.byte(0x44); cb.byte(0x24); cb.byte(0x01); // mov al, [rsp+1]
        cb.shlRImm8(cg.RAX, 8);
        cb.orRR(cg.R8, cg.RAX);
        cb.byte(0x8A); cb.byte(0x44); cb.byte(0x24); cb.byte(0x02); // mov al, [rsp+2]
        cb.shlRImm8(cg.RAX, 16);
        cb.orRR(cg.R8, cg.RAX);
        cb.byte(0x8A); cb.byte(0x44); cb.byte(0x24); cb.byte(0x03); // mov al, [rsp+3]
        cb.shlRImm8(cg.RAX, 24);
        cb.orRR(cg.R8, cg.RAX);

        cb.addRImm32(cg.RSP, 16 + 8); // pop buffer + hostname ptr
        cb.movRR(cg.RAX, cg.R8);
        return;
    }
    if (eq(name, "http.get") or eq(name, "http_get") or eq(name, "httpget")) {
        // http.get(host_ptr, path_ptr) → returns response string pointer
        var hg_args: [2]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 2;
        var hg_ac: usize = 0;
        var hg_ch = n.first_child;
        while (hg_ch != parser_mod.NO_NODE and hg_ac < 2) {
            hg_args[hg_ac] = hg_ch;
            hg_ch = pool[@as(usize, @intCast(hg_ch))].next_sibling;
            hg_ac += 1;
        }
        if (hg_args[0] != parser_mod.NO_NODE) { compileExprNode(hg_args[0], pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX); // host
        if (hg_args[1] != parser_mod.NO_NODE) { compileExprNode(hg_args[1], pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX); // path

        // pipe + buffer setup (save args in regs first)
        cb.subRImm32(cg.RSP, 8);
        cb.movRR(cg.RDI, cg.RSP);
        cb.xorRR(cg.RSI, cg.RSI);
        cb.movRImm64(cg.RAX, 22); // SYS_PIPE
        cb.syscall();
        cb.popR(cg.R12); // R12 = pipe_read | (pipe_write << 32)
        cb.movRR(cg.R13, cg.R12);
        cb.shrRImm8(cg.R13, 32); // R13 = pipe_write

        // save args in regs (path on top, host below)
        cb.popR(cg.R9);  // R9 = path
        cb.popR(cg.R8);  // R8 = host

        // allocate response buffer
        cb.subRImm32(cg.RSP, 8192);
        cb.movRR(cg.R14, cg.RSP); // R14 = buffer

        // fork
        cb.movRImm64(cg.RAX, 57);
        cb.syscall();
        cb.cmpRImm32(cg.RAX, 0);
        const hg_parent = cb.pos;
        cb.jneRel32(0);

        // child: close pipe_read, dup2(pipe_write, 1)
        cb.movRR(cg.RDI, cg.R12);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();
        cb.movRR(cg.RDI, cg.R13);
        cb.movRImm64(cg.RSI, 1);
        cb.movRImm64(cg.RAX, 33);
        cb.syscall();
        cb.movRR(cg.RDI, cg.R13);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();

        // args already in R8(host), R9(path)
        // argv[4] = NULL, argv[3] = path, argv[2] = host
        cb.movRImm64(cg.RAX, 0); cb.pushR(cg.RAX);
        cb.pushR(cg.R9);
        cb.pushR(cg.R8);
        // argv[1] = "GET"
        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const hg_get = "GET\x00";
        cb.byte(@as(u8, @intCast(hg_get.len)));
        for (hg_get) |c| cb.byte(c);
        cb.pushR(cg.RAX);
        // argv[0] = "http_client"
        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const hg_argv0 = "http_client\x00";
        cb.byte(@as(u8, @intCast(hg_argv0.len)));
        for (hg_argv0) |c| cb.byte(c);
        cb.pushR(cg.RAX);
        // exe = "./http_client"
        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const hg_exe = "./http_client\x00";
        cb.byte(@as(u8, @intCast(hg_exe.len)));
        for (hg_exe) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX);
        cb.movRR(cg.RSI, cg.RSP);
        cb.xorRR(cg.RDX, cg.RDX);
        cb.movRImm64(cg.RAX, 59);
        cb.syscall();
        cb.movRImm64(cg.RDI, 1);
        cb.movRImm64(cg.RAX, 60);
        cb.syscall();

        const hg_parent_pos = cb.pos;
        patch32(cb, hg_parent + 2, @as(i32, @intCast(hg_parent_pos)) - @as(i32, @intCast(hg_parent + 6)));

        // parent: close pipe_write, read response
        cb.movRR(cg.RDI, cg.R13);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();

        cb.xorRR(cg.R15, cg.R15);
        const hg_read_loop = cb.pos;
        cb.movRR(cg.RDI, cg.R12);
        cb.movRR(cg.RSI, cg.R14);
        cb.addRR(cg.RSI, cg.R15);
        cb.movRImm64(cg.RDX, 4096);
        cb.xorRR(cg.RAX, cg.RAX);
        cb.syscall();
        cb.cmpRImm32(cg.RAX, 0);
        const hg_read_done = cb.pos;
        cb.jleRel32(0);
        cb.addRR(cg.R15, cg.RAX);
        cb.cmpRImm32(cg.R15, 8192);
        const hg_read_full = cb.pos;
        cb.jlRel32(0);

        const hg_read_done_lbl = cb.pos;
        patch32(cb, hg_read_done + 2, @as(i32, @intCast(hg_read_done_lbl)) - @as(i32, @intCast(hg_read_done + 6)));
        patch32(cb, hg_read_full + 2, @as(i32, @intCast(hg_read_loop)) - @as(i32, @intCast(hg_read_full + 6)));

        cb.movRR(cg.RAX, cg.R14);
        cb.addRR(cg.RAX, cg.R15);
        cb.byte(0xC6); cb.byte(0x00); cb.byte(0x00);

        cb.movRR(cg.RDI, cg.R12);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();

        cb.subRImm32(cg.RSP, 16);
        cb.movRR(cg.RDI, cg.RAX);
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.xorRR(cg.RDX, cg.RDX);
        cb.xorRR(cg.R10, cg.R10);
        cb.movRImm64(cg.RAX, 61);
        cb.syscall();
        cb.addRImm32(cg.RSP, 16);

        cb.movRR(cg.RAX, cg.R14);
        cb.addRImm32(cg.RSP, 8192 + 8 + 16);
        return;
    }
    if (eq(name, "http.post") or eq(name, "http_post") or eq(name, "httppost") or eq(name, "http.post")) {
        // http.post(host_ptr, path_ptr, body_ptr) → returns response string pointer
        var hp_args: [3]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 3;
        var hp_ac: usize = 0;
        var hp_ch = n.first_child;
        while (hp_ch != parser_mod.NO_NODE and hp_ac < 3) {
            hp_args[hp_ac] = hp_ch;
            hp_ch = pool[@as(usize, @intCast(hp_ch))].next_sibling;
            hp_ac += 1;
        }
        if (hp_args[0] != parser_mod.NO_NODE) { compileExprNode(hp_args[0], pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX); // host (deepest)
        if (hp_args[1] != parser_mod.NO_NODE) { compileExprNode(hp_args[1], pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX); // path
        if (hp_args[2] != parser_mod.NO_NODE) { compileExprNode(hp_args[2], pool, cb, vars, vc, errs); }
        else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.pushR(cg.RAX); // body (top)

        // Allocate pipe and stack buffer
        cb.subRImm32(cg.RSP, 8);
        cb.movRR(cg.RDI, cg.RSP);
        cb.xorRR(cg.RSI, cg.RSI);
        cb.movRImm64(cg.RAX, 22); // SYS_PIPE
        cb.syscall();
        cb.popR(cg.R12); // R12 = pipe_read | (pipe_write << 32)
        cb.movRR(cg.R13, cg.R12);
        cb.shrRImm8(cg.R13, 32); // R13 = pipe_write

        // save args in regs (body on top, path below, host deepest)
        cb.popR(cg.R10); // R10 = body
        cb.popR(cg.R9);  // R9 = path
        cb.popR(cg.R8);  // R8 = host

        cb.subRImm32(cg.RSP, 8192); // response buffer
        cb.movRR(cg.R14, cg.RSP);

        // fork
        cb.movRImm64(cg.RAX, 57);
        cb.syscall();
        cb.cmpRImm32(cg.RAX, 0);
        const hp_parent = cb.pos;
        cb.jneRel32(0);

        // child: setup pipes, exec http_client POST
        cb.movRR(cg.RDI, cg.R12);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();
        cb.movRR(cg.RDI, cg.R13);
        cb.movRImm64(cg.RSI, 1);
        cb.movRImm64(cg.RAX, 33);
        cb.syscall();
        cb.movRR(cg.RDI, cg.R13);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();

        // args already in R8(host), R9(path), R10(body)

        cb.movRImm64(cg.RAX, 0); cb.pushR(cg.RAX);
        cb.pushR(cg.R10);
        cb.pushR(cg.R9);
        cb.pushR(cg.R8);
        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const hp_post = "POST\x00";
        cb.byte(@as(u8, @intCast(hp_post.len)));
        for (hp_post) |c| cb.byte(c);
        cb.pushR(cg.RAX);
        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const hp_argv0 = "http_client\x00";
        cb.byte(@as(u8, @intCast(hp_argv0.len)));
        for (hp_argv0) |c| cb.byte(c);
        cb.movRR(cg.R9, cg.RAX);
        cb.pushR(cg.R9); // argv[0] = "http_client"
        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05);
        cb.dword(2); cb.byte(0xEB);
        const hp_exe = "./http_client\x00";
        cb.byte(@as(u8, @intCast(hp_exe.len)));
        for (hp_exe) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX);
        cb.movRR(cg.RSI, cg.RSP);
        cb.xorRR(cg.RDX, cg.RDX);
        cb.movRImm64(cg.RAX, 59);
        cb.syscall();
        cb.movRImm64(cg.RDI, 1);
        cb.movRImm64(cg.RAX, 60);
        cb.syscall();

        const hp_parent_pos = cb.pos;
        patch32(cb, hp_parent + 2, @as(i32, @intCast(hp_parent_pos)) - @as(i32, @intCast(hp_parent + 6)));

        // parent: close pipe_write, read
        cb.movRR(cg.RDI, cg.R13);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();

        cb.xorRR(cg.R15, cg.R15);
        const hp_read_loop = cb.pos;
        cb.movRR(cg.RDI, cg.R12);
        cb.movRR(cg.RSI, cg.R14);
        cb.addRR(cg.RSI, cg.R15);
        cb.movRImm64(cg.RDX, 4096);
        cb.xorRR(cg.RAX, cg.RAX);
        cb.syscall();
        cb.cmpRImm32(cg.RAX, 0);
        const hp_read_done = cb.pos;
        cb.jleRel32(0);
        cb.addRR(cg.R15, cg.RAX);
        cb.cmpRImm32(cg.R15, 8192);
        const hp_read_full = cb.pos;
        cb.jlRel32(0);

        const hp_read_done_lbl = cb.pos;
        patch32(cb, hp_read_done + 2, @as(i32, @intCast(hp_read_done_lbl)) - @as(i32, @intCast(hp_read_done + 6)));
        patch32(cb, hp_read_full + 2, @as(i32, @intCast(hp_read_loop)) - @as(i32, @intCast(hp_read_full + 6)));

        cb.movRR(cg.RAX, cg.R14);
        cb.addRR(cg.RAX, cg.R15);
        cb.byte(0xC6); cb.byte(0x00); cb.byte(0x00);

        cb.movRR(cg.RDI, cg.R12);
        cb.movRImm64(cg.RAX, 3);
        cb.syscall();

        cb.subRImm32(cg.RSP, 16);
        cb.movRR(cg.RDI, cg.RAX);
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.xorRR(cg.RDX, cg.RDX);
        cb.xorRR(cg.R10, cg.R10);
        cb.movRImm64(cg.RAX, 61);
        cb.syscall();
        cb.addRImm32(cg.RSP, 16);

        cb.movRR(cg.RAX, cg.R14);
        cb.addRImm32(cg.RSP, 8192 + 4 + 24); // buffer + pipe_fds + 3 args
        return;
    }
    cb.movRImm64(cg.RAX, 0);
}

fn compileFieldAccess(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, errs: *errors_mod.ErrorList) void {
    compileExprAddr(n.first_child, pool, cb, vars, vc, errs);
    const field = n.name_start[0..n.name_len];
    const field_off = findFieldOffset(pool, field);
    if (field_off > 0) cb.addRImm32(cg.RAX, field_off);
    cb.movRMem64(cg.RAX, cg.RAX, 0);
}

fn compileArrayIndex(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, errs: *errors_mod.ErrorList) void {
    const arr = n.first_child;
    const idx = if (arr != parser_mod.NO_NODE) pool[@as(usize, @intCast(arr))].next_sibling else parser_mod.NO_NODE;
    if (arr == parser_mod.NO_NODE or idx == parser_mod.NO_NODE) { cb.xorRR(cg.RAX, cg.RAX); return; }

    compileExprAddr(arr, pool, cb, vars, vc, errs);
    cb.pushR(cg.RAX);
    compileExprNode(idx, pool, cb, vars, vc, errs);
    cb.movRR(cg.RCX, cg.RAX);
    cb.negR(cg.RCX);
    cb.shlRImm8(cg.RCX, 3);
    cb.popR(cg.RAX);
    cb.addRR(cg.RAX, cg.RCX);
    cb.movRMem64(cg.RAX, cg.RAX, 0);
}

fn compileAddrOf(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, errs: *errors_mod.ErrorList) void {
    compileExprAddr(n.first_child, pool, cb, vars, vc, errs);
}

fn compileDeref(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, errs: *errors_mod.ErrorList) void {
    compileExprNode(n.first_child, pool, cb, vars, vc, errs);
    cb.movRMem64(cg.RAX, cg.RAX, 0);
}

fn compileSizeof(_n: *const parser_mod.AstNode, _pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, _vars: *[MAX_VARS]Var, _vc: *usize, _errs: *errors_mod.ErrorList) void {
    _ = _n; _ = _pool; _ = _vars; _ = _vc; _ = _errs;
    cb.movRImm64(cg.RAX, 8);
}

fn compileIf(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32, errs: *errors_mod.ErrorList, has_return: *bool) void {
    const cond = n.first_child;
    const then_blk = if (cond != parser_mod.NO_NODE) pool[@as(usize, @intCast(cond))].next_sibling else parser_mod.NO_NODE;
    const else_blk = if (then_blk != parser_mod.NO_NODE) pool[@as(usize, @intCast(then_blk))].next_sibling else parser_mod.NO_NODE;

    if (cond != parser_mod.NO_NODE) compileExprNode(cond, pool, cb, vars, vc, errs) else cb.xorRR(cg.RAX, cg.RAX);
    cb.cmpRImm32(cg.RAX, 0);

    const je_pos = cb.pos;
    cb.jeRel32(0);
    const after_cond = cb.pos;

    if (then_blk != parser_mod.NO_NODE) compileStmt(then_blk, pool, cb, vars, vc, stack_off, errs, has_return);

    var has_else = false;
    const jmp_pos = cb.pos;
    if (else_blk != parser_mod.NO_NODE) { has_else = true; cb.jmpRel32(0); }

    const else_pos = cb.pos;
    patch32(cb, je_pos + 2, @as(i32, @intCast(else_pos)) - @as(i32, @intCast(after_cond)));

    if (else_blk != parser_mod.NO_NODE) compileStmt(else_blk, pool, cb, vars, vc, stack_off, errs, has_return);

    const end_pos = cb.pos;
    if (has_else) patch32(cb, jmp_pos + 1, @as(i32, @intCast(end_pos)) - @as(i32, @intCast(else_pos)));
}

fn compileWhile(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32, errs: *errors_mod.ErrorList, has_return: *bool) void {
    const cond = n.first_child;
    const body = if (cond != parser_mod.NO_NODE) pool[@as(usize, @intCast(cond))].next_sibling else parser_mod.NO_NODE;

    const loop_pos = cb.pos;
    if (cond != parser_mod.NO_NODE) compileExprNode(cond, pool, cb, vars, vc, errs) else cb.xorRR(cg.RAX, cg.RAX);
    cb.cmpRImm32(cg.RAX, 0);

    const je_pos = cb.pos;
    cb.jeRel32(0);
    const after_cond = cb.pos;

    if (body != parser_mod.NO_NODE) compileStmt(body, pool, cb, vars, vc, stack_off, errs, has_return);

    const back_off = @as(i32, @intCast(loop_pos)) - @as(i32, @intCast(cb.pos + 5));
    cb.jmpRel32(back_off);

    const end_pos = cb.pos;
    patch32(cb, je_pos + 2, @as(i32, @intCast(end_pos)) - @as(i32, @intCast(after_cond)));
}

fn findFieldOffset(pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, field: []const u8) i32 {
    var pi: usize = 0;
    while (pi < parser_mod.MAX_NODES) : (pi += 1) {
        const n = &pool[pi];
        if (n.kind == .struct_decl) {
            var fi: i32 = 0;
            var ch = n.first_child;
            while (ch != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(ch))];
                if (cn.kind == .var_decl) {
                    if (eq(cn.name_start[0..cn.name_len], field)) {
                        return fi * 8;
                    }
                    fi += 1;
                }
                ch = cn.next_sibling;
            }
        }
    }
    return 0;
}

fn findVarOffset(vars: *[MAX_VARS]Var, count: usize, name: []const u8) ?i32 {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (eq(vars[i].name, name)) return vars[i].off;
    }
    return null;
}

fn findVarIndex(vars: *[MAX_VARS]Var, count: usize, name: []const u8) ?usize {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (eq(vars[i].name, name)) return i;
    }
    return null;
}

fn patch32(cb: *cg.CodeBuffer, pos: usize, off: i32) void {
    if (pos + 4 > cb.buf.len) return;
    cb.buf[pos] = @as(u8, @truncate(@as(u32, @bitCast(off))));
    cb.buf[pos + 1] = @as(u8, @truncate(@as(u32, @bitCast(off >> 8))));
    cb.buf[pos + 2] = @as(u8, @truncate(@as(u32, @bitCast(off >> 16))));
    cb.buf[pos + 3] = @as(u8, @truncate(@as(u32, @bitCast(off >> 24))));
}

const NO_NODE: parser_mod.NodeIdx = -1;
