const parser_mod = @import("parser.zig");
const cg = @import("codegen_arm.zig");

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

const Var = struct { name: []const u8, off: i32 };
const MAX_VARS = 64;
const NO_NODE: parser_mod.NodeIdx = -1;

pub fn compile(prog_root: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode) cg.CodeBuffer {
    var cb = cg.CodeBuffer.init();
    var vars: [MAX_VARS]Var = undefined;
    var vc: usize = 0;
    var stack_off: i32 = 0;

    if (prog_root == parser_mod.NO_NODE) {
        cb.movRImm64(cg.X8, 93);
        cb.movRImm64(cg.X0, 0);
        cb.svc(0);
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
        cb.movRImm64(cg.X8, 93);
        cb.movRImm64(cg.X0, 0);
        cb.svc(0);
        return cb;
    }

    // NativeActivity entry: will be patched to call main
    const call_pos = cb.len;
    cb.bl(); // placeholder → patched to main
    // After main returns, loop forever
    const loop_pos = cb.len;
    cb.branch();
    // Patch branch to loop
    cb.patchB(loop_pos, loop_pos);

    // Move past the entry point code to compile functions
    var main_body_pos: usize = 0;
    ch = prog.first_child;
    while (ch != parser_mod.NO_NODE) {
        const cn = &pool[@as(usize, @intCast(ch))];
        if (cn.kind == .fn_decl) {
            if (ch == main_idx) main_body_pos = cb.len;
            compileFn(cn, pool, &cb, &vars, &vc, &stack_off);
        }
        ch = cn.next_sibling;
    }

    cb.patchBL(call_pos, main_body_pos);
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

    const frame: i32 = @as(i32, @intCast(var_count)) * 8;

    // stp x29, x30, [sp, #-16]!
    cb.stpPre(cg.FP, cg.X30, 31, -16);
    cb.addi(cg.FP, 31, 0); // mov x29, sp
    if (frame > 0) cb.subi(31, 31, @as(u16, @intCast(frame)));

    child = n.first_child;
    while (child != parser_mod.NO_NODE) {
        compileStmt(child, pool, cb, vars, vc, stack_off);
        child = pool[@as(usize, @intCast(child))].next_sibling;
    }

    // Return with default 0
    cb.mov(cg.X0, cg.ZR);
    if (frame > 0) cb.addi(31, 31, @as(u16, @intCast(frame)));
    cb.ldpPost(cg.FP, cg.X30, 31, 16);
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
            } else {
                cb.mov(cg.X0, cg.ZR);
            }
            cb.addi(31, cg.FP, 0); // sp = fp (restore past locals)
            cb.ldpPost(cg.FP, cg.X30, 31, 16);
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
                    vars[vc.*] = Var{ .name = name, .off = off };
                    vc.* += 1;
                }
                if (si == 0 and init_expr != parser_mod.NO_NODE) {
                    compileExprNode(init_expr, pool, cb, vars, vc);
                    cb.str64(cg.X0, cg.FP, off);
                } else if (si == 0 and init_expr == parser_mod.NO_NODE and total_slots == 1) {
                    cb.str64(cg.ZR, cg.FP, off);
                }
            }
        },
        .call => compileCall(n, pool, cb, vars, vc),
        .assign => {
            if (n.first_child != parser_mod.NO_NODE) {
                compileExprNode(n.first_child, pool, cb, vars, vc);
            } else {
                cb.mov(cg.X0, cg.ZR);
            }
            const name = n.name_start[0..n.name_len];
            const off = findVarOffset(vars, vc.*, name);
            if (off) |o| cb.str64(cg.X0, cg.FP, o);
        },
        .if_stmt => compileIf(n, pool, cb, vars, vc, stack_off),
        .while_stmt => compileWhile(n, pool, cb, vars, vc, stack_off),
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
    if (idx == parser_mod.NO_NODE) { cb.mov(cg.X0, cg.ZR); return; }
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .int_lit => {
            const v = strToInt(n.val_start[0..n.val_len]);
            cb.movRImm64(cg.X0, @as(u64, @bitCast(v)));
        },
        .str_lit => cb.mov(cg.X0, cg.ZR),
        .ident => {
            if (findVarOffset(vars, vc.*, n.name_start[0..n.name_len])) |off| {
                cb.ldr64(cg.X0, cg.FP, off);
            } else {
                cb.mov(cg.X0, cg.ZR);
            }
        },
        .binary_op => compileBinaryOp(n, pool, cb, vars, vc),
        .unary_op => compileUnaryOp(n, pool, cb, vars, vc),
        .field_access => compileFieldAccess(n, pool, cb, vars, vc),
        .array_index => compileArrayIndex(n, pool, cb, vars, vc),
        .addr_of => compileAddrOf(n, pool, cb, vars, vc),
        .deref => compileDeref(n, pool, cb, vars, vc),
        .sizeof_expr => compileSizeof(n, pool, cb, vars, vc),
        else => cb.mov(cg.X0, cg.ZR),
    }
}

fn compileExprAddr(idx: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    if (idx == parser_mod.NO_NODE) { cb.mov(cg.X0, cg.ZR); return; }
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .ident => {
            if (findVarOffset(vars, vc.*, n.name_start[0..n.name_len])) |off| {
                cb.addi(cg.X0, cg.FP, @as(u16, @intCast(off)));
            } else { cb.mov(cg.X0, cg.ZR); }
        },
        .deref => {
            compileExprNode(n.first_child, pool, cb, vars, vc);
        },
        .field_access => {
            compileExprAddr(n.first_child, pool, cb, vars, vc);
            const field = n.name_start[0..n.name_len];
            const field_off = findFieldOffset(pool, field);
            if (field_off > 0) cb.addi(cg.X0, cg.X0, @as(u16, @intCast(field_off)));
        },
        .array_index => {
            compileExprAddr(n.first_child, pool, cb, vars, vc);
            const idx_node = if (n.first_child != parser_mod.NO_NODE)
                pool[@as(usize, @intCast(n.first_child))].next_sibling
            else
                parser_mod.NO_NODE;
            if (idx_node != parser_mod.NO_NODE) {
                cb.str64(cg.X0, 31, -8);
                cb.subi(31, 31, 8);
                compileExprNode(idx_node, pool, cb, vars, vc);
                cb.mov(cg.X10, cg.X0);
                cb.ldr64(cg.X0, 31, 0);
                cb.addi(31, 31, 8);
                cb.add(cg.X0, cg.X0, cg.X10);
            }
        },
        else => compileExprNode(idx, pool, cb, vars, vc),
    }
}

fn compileBinaryOp(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    const op = n.name_start[0..n.name_len];
    const left = n.first_child;
    const right = if (left != parser_mod.NO_NODE)
        pool[@as(usize, @intCast(left))].next_sibling
    else
        parser_mod.NO_NODE;
    if (left == parser_mod.NO_NODE or right == parser_mod.NO_NODE) { cb.mov(cg.X0, cg.ZR); return; }

    compileExprNode(left, pool, cb, vars, vc);
    cb.str64(cg.X0, 31, -8); cb.subi(31, 31, 8);
    compileExprNode(right, pool, cb, vars, vc);
    cb.mov(cg.X10, cg.X0);
    cb.ldr64(cg.X0, 31, 0); cb.addi(31, 31, 8);

    if (eq(op, "+")) {
        cb.add(cg.X0, cg.X0, cg.X10);
    } else if (eq(op, "-")) {
        cb.sub(cg.X0, cg.X0, cg.X10);
    } else if (eq(op, "*")) {
        cb.mul(cg.X0, cg.X0, cg.X10);
    } else if (eq(op, "/")) {
        cb.sdiv(cg.X0, cg.X0, cg.X10);
    } else if (eq(op, "==")) {
        cb.sub(cg.X9, cg.X0, cg.X10);
        cb.cmp(cg.X9, cg.ZR);
        cb.cset(cg.X0, 0); // EQ
    } else if (eq(op, "!=")) {
        cb.sub(cg.X9, cg.X0, cg.X10);
        cb.cmp(cg.X9, cg.ZR);
        cb.cset(cg.X0, 1); // NE
    } else if (eq(op, "<")) {
        cb.cmp(cg.X0, cg.X10);
        cb.cset(cg.X0, 10); // LT
    } else if (eq(op, ">")) {
        cb.cmp(cg.X10, cg.X0);
        cb.cset(cg.X0, 10); // LT (swapped)
    } else if (eq(op, "<=")) {
        cb.cmp(cg.X10, cg.X0);
        cb.cset(cg.X0, 10); // LT (swapped)
        cb.eor(cg.X0, cg.X0, cg.ZR);
    } else if (eq(op, ">=")) {
        cb.cmp(cg.X0, cg.X10);
        cb.cset(cg.X0, 10); // LT
        cb.eor(cg.X0, cg.X0, cg.ZR);
    } else if (eq(op, "&&")) {
        cb.and_(cg.X0, cg.X0, cg.X10);
        cb.cmp(cg.X0, cg.ZR);
        cb.cset(cg.X0, 1); // NE
    } else if (eq(op, "||")) {
        cb.orr(cg.X0, cg.X0, cg.X10);
        cb.cmp(cg.X0, cg.ZR);
        cb.cset(cg.X0, 1); // NE
    } else {
        cb.mov(cg.X0, cg.ZR);
    }
}

fn compileUnaryOp(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    const op = n.name_start[0..n.name_len];
    const operand = n.first_child;
    compileExprNode(operand, pool, cb, vars, vc);
    if (eq(op, "-")) {
        cb.neg(cg.X0, cg.X0);
    } else if (eq(op, "!")) {
        cb.cmp(cg.X0, cg.ZR);
        cb.cset(cg.X0, 0); // EQ
    }
}

fn compileCall(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, _vars: *[MAX_VARS]Var, _vc: *usize) void {
    _ = _vars;
    _ = _vc;
    const name = n.name_start[0..n.name_len];
    if (eq(name, "syscall")) {
        var args: [6]i64 = .{0} ** 6;
        var ai: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and ai < 6) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (cn.kind == .int_lit) args[ai] = strToInt(cn.val_start[0..cn.val_len]);
            ai += 1;
            ch = cn.next_sibling;
        }
        if (ai > 0) {
            cb.movRImm64(cg.X8, @as(u64, @bitCast(args[0])));
            if (ai > 1) cb.movRImm64(cg.X0, @as(u64, @bitCast(args[1])));
            if (ai > 2) cb.movRImm64(cg.X1, @as(u64, @bitCast(args[2])));
            if (ai > 3) cb.movRImm64(cg.X2, @as(u64, @bitCast(args[3])));
            if (ai > 4) cb.movRImm64(cg.X3, @as(u64, @bitCast(args[4])));
            if (ai > 5) cb.movRImm64(cg.X4, @as(u64, @bitCast(args[5])));
        }
        cb.svc(0);
        return;
    }
    cb.mov(cg.X0, cg.ZR);
}

fn compileFieldAccess(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    compileExprAddr(n.first_child, pool, cb, vars, vc);
    const field = n.name_start[0..n.name_len];
    const field_off = findFieldOffset(pool, field);
    if (field_off > 0) cb.addi(cg.X0, cg.X0, @as(u16, @intCast(field_off)));
    cb.ldr64(cg.X0, cg.X0, 0);
}

fn compileArrayIndex(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    const arr = n.first_child;
    const idx = if (arr != parser_mod.NO_NODE) pool[@as(usize, @intCast(arr))].next_sibling else parser_mod.NO_NODE;
    if (arr == parser_mod.NO_NODE or idx == parser_mod.NO_NODE) { cb.mov(cg.X0, cg.ZR); return; }

    compileExprAddr(arr, pool, cb, vars, vc);
    cb.str64(cg.X0, 31, -8); cb.subi(31, 31, 8);
    compileExprNode(idx, pool, cb, vars, vc);
    cb.mov(cg.X10, cg.X0);
    cb.ldr64(cg.X0, 31, 0); cb.addi(31, 31, 8);
    cb.add(cg.X0, cg.X0, cg.X10);
    cb.ldr64(cg.X0, cg.X0, 0);
}

fn compileAddrOf(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    compileExprAddr(n.first_child, pool, cb, vars, vc);
}

fn compileDeref(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    compileExprNode(n.first_child, pool, cb, vars, vc);
    cb.ldr64(cg.X0, cg.X0, 0);
}

fn compileSizeof(_n: *const parser_mod.AstNode, _pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, _vars: *[MAX_VARS]Var, _vc: *usize) void {
    _ = _n; _ = _pool; _ = _vars; _ = _vc;
    cb.movRImm64(cg.X0, 8);
}

fn compileIf(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32) void {
    const cond = n.first_child;
    const then_blk = if (cond != parser_mod.NO_NODE) pool[@as(usize, @intCast(cond))].next_sibling else parser_mod.NO_NODE;
    const else_blk = if (then_blk != parser_mod.NO_NODE) pool[@as(usize, @intCast(then_blk))].next_sibling else parser_mod.NO_NODE;

    if (cond != parser_mod.NO_NODE) compileExprNode(cond, pool, cb, vars, vc) else cb.mov(cg.X0, cg.ZR);
    const cbz_pos = cb.len;
    cb.cbz(cg.X0);

    if (then_blk != parser_mod.NO_NODE) compileStmt(then_blk, pool, cb, vars, vc, stack_off);

    var has_else = false;
    const jmp_pos = cb.len;
    if (else_blk != parser_mod.NO_NODE) { has_else = true; cb.branch(); }

    const else_pos = cb.len;
    cb.patchCBZ(cbz_pos, else_pos);

    if (else_blk != parser_mod.NO_NODE) compileStmt(else_blk, pool, cb, vars, vc, stack_off);

    const end_pos = cb.len;
    if (has_else) cb.patchB(jmp_pos, end_pos);
}

fn compileWhile(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32) void {
    const cond = n.first_child;
    const body = if (cond != parser_mod.NO_NODE) pool[@as(usize, @intCast(cond))].next_sibling else parser_mod.NO_NODE;

    const loop_pos = cb.len;

    if (cond != parser_mod.NO_NODE) compileExprNode(cond, pool, cb, vars, vc) else cb.mov(cg.X0, cg.ZR);
    const cbz_pos = cb.len;
    cb.cbz(cg.X0);

    if (body != parser_mod.NO_NODE) compileStmt(body, pool, cb, vars, vc, stack_off);

    const jmp_pos = cb.len;
    cb.branch();
    cb.patchB(jmp_pos, loop_pos);

    const end_pos = cb.len;
    cb.patchCBZ(cbz_pos, end_pos);
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
