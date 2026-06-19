const parser_mod = @import("parser.zig");
const cg = @import("codegen.zig");

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) if (a[i] != b[i]) return false;
    return true;
}

fn strToInt(s: []const u8) i64 {
    var v: i64 = 0;
    var i: usize = 0;
    while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) v = v * 10 + (s[i] - '0');
    return v;
}

const Var = struct { name: []const u8, off: i32, size: i32 };
const MAX_VARS = 64;

pub fn compile(prog_root: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode) cg.CodeBuffer {
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
    ch = prog.first_child;
    while (ch != parser_mod.NO_NODE) {
        const cn = &pool[@as(usize, @intCast(ch))];
        if (cn.kind == .fn_decl) {
            if (ch == main_idx) main_body_pos = cb.pos;
            compileFn(cn, pool, &cb, &vars, &vc, &stack_off);
        }
        ch = cn.next_sibling;
    }

    const main_off: i32 = @as(i32, @intCast(main_body_pos)) - @as(i32, @intCast(call_pos + 5));
    patch32(&cb, call_pos + 1, main_off);
    return cb;
}

fn compileFn(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32) void {
    var var_count: usize = 0;
    var child = n.first_child;
    while (child != parser_mod.NO_NODE) {
        const cn = &pool[@as(usize, @intCast(child))];
        if (cn.kind == .block) {
            var ch2 = cn.first_child;
            while (ch2 != parser_mod.NO_NODE) {
                const st = &pool[@as(usize, @intCast(ch2))];
                if (st.kind == .var_decl) {
                    var arr_sz: i32 = 1;
                    if (st.val_len > 0) {
                        arr_sz = @as(i32, @intCast(strToInt(st.val_start[0..st.val_len])));
                    }
                    var_count += @as(usize, @intCast(@max(1, arr_sz)));
                }
                ch2 = pool[@as(usize, @intCast(ch2))].next_sibling;
            }
        }
        child = cn.next_sibling;
    }

    cb.pushR(cg.RBP);
    cb.movRR(cg.RBP, cg.RSP);
    const frame: i32 = @as(i32, @intCast(var_count)) * 8;
    if (frame > 0) cb.subRImm32(cg.RSP, frame);

    child = n.first_child;
    while (child != parser_mod.NO_NODE) {
        compileStmt(child, pool, cb, vars, vc, stack_off);
        child = pool[@as(usize, @intCast(child))].next_sibling;
    }

    cb.xorRR(cg.RAX, cg.RAX);
    cb.movRR(cg.RSP, cg.RBP);
    cb.popR(cg.RBP);
    cb.ret();
}

fn compileStmt(idx: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32) void {
    if (idx == parser_mod.NO_NODE) return;
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .block => {
            var ch = n.first_child;
            while (ch != parser_mod.NO_NODE) {
                compileStmt(ch, pool, cb, vars, vc, stack_off);
                ch = pool[@as(usize, @intCast(ch))].next_sibling;
            }
        },
        .ret_stmt => {
            if (n.first_child != parser_mod.NO_NODE) {
                compileExprNode(n.first_child, pool, cb, vars, vc);
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
            while (si < total_slots) : (si += 1) {
                stack_off.* -= 8;
                const off = stack_off.*;
                if (vc.* < MAX_VARS) {
                    vars[vc.*] = Var{ .name = name, .off = off, .size = 8 };
                    vc.* += 1;
                }
                if (si == 0 and init_expr != parser_mod.NO_NODE) {
                    compileExprNode(init_expr, pool, cb, vars, vc);
                    cb.movMemR64(cg.RBP, off, cg.RAX);
                } else if (si == 0 and init_expr == parser_mod.NO_NODE and total_slots == 1) {
                    cb.xorRR(cg.RAX, cg.RAX);
                    cb.movMemR64(cg.RBP, off, cg.RAX);
                }
            }
        },
        .call => { compileCall(n, pool, cb, vars, vc); },
        .assign => {
            if (n.first_child != parser_mod.NO_NODE) {
                compileExprNode(n.first_child, pool, cb, vars, vc);
            } else { cb.xorRR(cg.RAX, cg.RAX); }
            const name = n.name_start[0..n.name_len];
            const off = findVarIndex(vars, vc.*, name);
            if (off) |o| cb.movMemR64(cg.RBP, vars[o].off, cg.RAX);
        },
        .if_stmt => compileIf(n, pool, cb, vars, vc, stack_off),
        .while_stmt => compileWhile(n, pool, cb, vars, vc, stack_off),
        .store => {
            const lval = n.first_child;
            const val = if (lval != parser_mod.NO_NODE) pool[@as(usize, @intCast(lval))].next_sibling else parser_mod.NO_NODE;
            if (val != parser_mod.NO_NODE) {
                compileExprNode(val, pool, cb, vars, vc);
            } else { cb.xorRR(cg.RAX, cg.RAX); }
            cb.pushR(cg.RAX);
            if (lval != parser_mod.NO_NODE) {
                compileExprAddr(lval, pool, cb, vars, vc);
            } else { cb.xorRR(cg.RAX, cg.RAX); }
            cb.popR(cg.RCX);
            cb.movMemR64(cg.RAX, 0, cg.RCX);
        },
        .struct_decl => {},
        else => {
            var ch = n.first_child;
            while (ch != parser_mod.NO_NODE) {
                compileStmt(ch, pool, cb, vars, vc, stack_off);
                ch = pool[@as(usize, @intCast(ch))].next_sibling;
            }
        },
    }
}

fn compileExprNode(idx: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    if (idx == parser_mod.NO_NODE) { cb.xorRR(cg.RAX, cg.RAX); return; }
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .int_lit => {
            cb.movRImm64(cg.RAX, @as(u64, @intCast(strToInt(n.val_start[0..n.val_len]))));
        },
        .str_lit => {
            const s = n.val_start[0..n.val_len];
            const skip = @as(u8, @intCast(8 + s.len));
            cb.byte(0xEB);
            cb.byte(skip);
            for (s) |c| cb.byte(c);
            cb.byte(0);
            const neg: i32 = -@as(i32, @intCast(8 + s.len));
            cb.byte(0x48);
            cb.byte(0x8D);
            cb.byte(0x05);
            cb.dword(@as(u32, @bitCast(neg)));
        },
        .ident => {
            if (findVarOffset(vars, vc.*, n.name_start[0..n.name_len])) |off| {
                cb.movRMem64(cg.RAX, cg.RBP, off);
            } else { cb.xorRR(cg.RAX, cg.RAX); }
        },
        .binary_op => compileBinaryOp(n, pool, cb, vars, vc),
        .unary_op => compileUnaryOp(n, pool, cb, vars, vc),
        .field_access => compileFieldAccess(n, pool, cb, vars, vc),
        .array_index => compileArrayIndex(n, pool, cb, vars, vc),
        .addr_of => compileAddrOf(n, pool, cb, vars, vc),
        .deref => compileDeref(n, pool, cb, vars, vc),
        .sizeof_expr => compileSizeof(n, pool, cb, vars, vc),
        .call => compileCall(n, pool, cb, vars, vc),
        else => { cb.xorRR(cg.RAX, cg.RAX); },
    }
}

fn compileExprAddr(idx: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    if (idx == parser_mod.NO_NODE) { cb.xorRR(cg.RAX, cg.RAX); return; }
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .ident => {
            if (findVarOffset(vars, vc.*, n.name_start[0..n.name_len])) |off| {
                cb.leaRMem(cg.RAX, cg.RBP, off);
            } else { cb.xorRR(cg.RAX, cg.RAX); }
        },
        .deref => {
            compileExprNode(n.first_child, pool, cb, vars, vc);
        },
        .field_access => {
            compileExprAddr(n.first_child, pool, cb, vars, vc);
            const field = n.name_start[0..n.name_len];
            const field_off = findFieldOffset(pool, field);
            if (field_off > 0) cb.addRImm32(cg.RAX, field_off);
        },
        .array_index => {
            compileExprAddr(n.first_child, pool, cb, vars, vc);
            const idx_node = if (n.first_child != parser_mod.NO_NODE)
                pool[@as(usize, @intCast(n.first_child))].next_sibling
            else
                parser_mod.NO_NODE;
            if (idx_node != parser_mod.NO_NODE) {
                cb.pushR(cg.RAX);
                compileExprNode(idx_node, pool, cb, vars, vc);
                cb.movRR(cg.RCX, cg.RAX);
                cb.popR(cg.RAX);
                cb.addRR(cg.RAX, cg.RCX);
            }
        },
        else => compileExprNode(idx, pool, cb, vars, vc),
    }
}

fn compileBinaryOp(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    const op = n.name_start[0..n.name_len];
    const left = n.first_child;
    const right = if (left != parser_mod.NO_NODE) pool[@as(usize, @intCast(left))].next_sibling else parser_mod.NO_NODE;
    if (left == parser_mod.NO_NODE or right == parser_mod.NO_NODE) { cb.xorRR(cg.RAX, cg.RAX); return; }

    compileExprNode(left, pool, cb, vars, vc);
    cb.pushR(cg.RAX);
    compileExprNode(right, pool, cb, vars, vc);
    cb.movRR(cg.RCX, cg.RAX);
    cb.popR(cg.RAX);

    if (eq(op, "+")) { cb.addRR(cg.RAX, cg.RCX); }
    else if (eq(op, "-")) { cb.subRR(cg.RAX, cg.RCX); }
    else if (eq(op, "*")) { cb.imulRR(cg.RAX, cg.RCX); }
    else if (eq(op, "/")) { cb.cqo(); cb.idivR(cg.RCX); }
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
    else { cb.xorRR(cg.RAX, cg.RAX); }
}

fn compileUnaryOp(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    const op = n.name_start[0..n.name_len];
    const operand = n.first_child;
    compileExprNode(operand, pool, cb, vars, vc);
    if (eq(op, "-")) { cb.negR(cg.RAX); }
    else if (eq(op, "!")) { cb.cmpRImm32(cg.RAX, 0); cb.pushfq(); cb.xorRR(cg.RAX, cg.RAX); cb.popfq(); cb.sete(cg.RAX); }
}

fn compileCall(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
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
                compileExprNode(args_list[ei], pool, cb, vars, vc);
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
    cb.movRImm64(cg.RAX, 0);
}

fn compileFieldAccess(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    compileExprAddr(n.first_child, pool, cb, vars, vc);
    const field = n.name_start[0..n.name_len];
    const field_off = findFieldOffset(pool, field);
    if (field_off > 0) cb.addRImm32(cg.RAX, field_off);
    cb.movRMem64(cg.RAX, cg.RAX, 0);
}

fn compileArrayIndex(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    const arr = n.first_child;
    const idx = if (arr != parser_mod.NO_NODE) pool[@as(usize, @intCast(arr))].next_sibling else parser_mod.NO_NODE;
    if (arr == parser_mod.NO_NODE or idx == parser_mod.NO_NODE) { cb.xorRR(cg.RAX, cg.RAX); return; }

    compileExprAddr(arr, pool, cb, vars, vc);
    cb.pushR(cg.RAX);
    compileExprNode(idx, pool, cb, vars, vc);
    cb.movRR(cg.RCX, cg.RAX);
    cb.popR(cg.RAX);
    cb.addRR(cg.RAX, cg.RCX);
    cb.movRMem64(cg.RAX, cg.RAX, 0);
}

fn compileAddrOf(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    compileExprAddr(n.first_child, pool, cb, vars, vc);
}

fn compileDeref(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    compileExprNode(n.first_child, pool, cb, vars, vc);
    cb.movRMem64(cg.RAX, cg.RAX, 0);
}

fn compileSizeof(_n: *const parser_mod.AstNode, _pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, _vars: *[MAX_VARS]Var, _vc: *usize) void {
    _ = _n; _ = _pool; _ = _vars; _ = _vc;
    cb.movRImm64(cg.RAX, 8);
}

fn compileIf(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32) void {
    const cond = n.first_child;
    const then_blk = if (cond != parser_mod.NO_NODE) pool[@as(usize, @intCast(cond))].next_sibling else parser_mod.NO_NODE;
    const else_blk = if (then_blk != parser_mod.NO_NODE) pool[@as(usize, @intCast(then_blk))].next_sibling else parser_mod.NO_NODE;

    if (cond != parser_mod.NO_NODE) compileExprNode(cond, pool, cb, vars, vc) else cb.xorRR(cg.RAX, cg.RAX);
    cb.cmpRImm32(cg.RAX, 0);

    const je_pos = cb.pos;
    cb.jeRel32(0);
    const after_cond = cb.pos;

    if (then_blk != parser_mod.NO_NODE) compileStmt(then_blk, pool, cb, vars, vc, stack_off);

    var has_else = false;
    const jmp_pos = cb.pos;
    if (else_blk != parser_mod.NO_NODE) { has_else = true; cb.jmpRel32(0); }

    const else_pos = cb.pos;
    patch32(cb, je_pos + 2, @as(i32, @intCast(else_pos)) - @as(i32, @intCast(after_cond)));

    if (else_blk != parser_mod.NO_NODE) compileStmt(else_blk, pool, cb, vars, vc, stack_off);

    const end_pos = cb.pos;
    if (has_else) patch32(cb, jmp_pos + 1, @as(i32, @intCast(end_pos)) - @as(i32, @intCast(else_pos)));
}

fn compileWhile(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32) void {
    const cond = n.first_child;
    const body = if (cond != parser_mod.NO_NODE) pool[@as(usize, @intCast(cond))].next_sibling else parser_mod.NO_NODE;

    const loop_pos = cb.pos;
    if (cond != parser_mod.NO_NODE) compileExprNode(cond, pool, cb, vars, vc) else cb.xorRR(cg.RAX, cg.RAX);
    cb.cmpRImm32(cg.RAX, 0);

    const je_pos = cb.pos;
    cb.jeRel32(0);
    const after_cond = cb.pos;

    if (body != parser_mod.NO_NODE) compileStmt(body, pool, cb, vars, vc, stack_off);

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
