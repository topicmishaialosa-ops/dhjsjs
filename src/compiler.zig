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
    else if (eq(op, "==")) { cb.cmpRR(cg.RAX, cg.RCX); cb.subRImm32(cg.RSP, 16); cb.pushfq(); cb.xorRR(cg.RAX, cg.RAX); cb.popfq(); cb.sete(cg.RAX); cb.addRImm32(cg.RSP, 16); }
    else if (eq(op, "!=")) { cb.cmpRR(cg.RAX, cg.RCX); cb.subRImm32(cg.RSP, 16); cb.pushfq(); cb.xorRR(cg.RAX, cg.RAX); cb.popfq(); cb.setne(cg.RAX); cb.addRImm32(cg.RSP, 16); }
    else if (eq(op, "<")) { cb.cmpRR(cg.RAX, cg.RCX); cb.subRImm32(cg.RSP, 16); cb.pushfq(); cb.xorRR(cg.RAX, cg.RAX); cb.popfq(); cb.setl(cg.RAX); cb.addRImm32(cg.RSP, 16); }
    else if (eq(op, ">")) { cb.cmpRR(cg.RAX, cg.RCX); cb.subRImm32(cg.RSP, 16); cb.pushfq(); cb.xorRR(cg.RAX, cg.RAX); cb.popfq(); cb.setg(cg.RAX); cb.addRImm32(cg.RSP, 16); }
    else if (eq(op, "<=")) { cb.cmpRR(cg.RAX, cg.RCX); cb.subRImm32(cg.RSP, 16); cb.pushfq(); cb.xorRR(cg.RAX, cg.RAX); cb.popfq(); cb.setle(cg.RAX); cb.addRImm32(cg.RSP, 16); }
    else if (eq(op, ">=")) { cb.cmpRR(cg.RAX, cg.RCX); cb.subRImm32(cg.RSP, 16); cb.pushfq(); cb.xorRR(cg.RAX, cg.RAX); cb.popfq(); cb.setge(cg.RAX); cb.addRImm32(cg.RSP, 16); }
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
    else if (eq(op, "!")) { cb.cmpRImm32(cg.RAX, 0); cb.subRImm32(cg.RSP, 16); cb.pushfq(); cb.xorRR(cg.RAX, cg.RAX); cb.popfq(); cb.sete(cg.RAX); cb.addRImm32(cg.RSP, 16); }
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
