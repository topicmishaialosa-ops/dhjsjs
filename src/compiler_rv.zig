const parser_mod = @import("parser.zig");
const cg = @import("codegen_rv.zig");

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

pub fn compile(prog_root: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode) cg.CodeBuffer {
    _ = prog_root;
    var cb = cg.CodeBuffer.init();
    var vars: [MAX_VARS]Var = undefined;
    var vc: usize = 0;
    var stack_off: i32 = 0;

    var main_idx: parser_mod.NodeIdx = parser_mod.NO_NODE;
    var pi: usize = 0;
    while (pi < parser_mod.MAX_NODES) : (pi += 1) {
        const n = &pool[pi];
        if (n.kind == .program) {
            var ch = n.first_child;
            while (ch != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(ch))];
                if (cn.kind == .fn_decl and eq(cn.name_start[0..cn.name_len], "main")) {
                    main_idx = ch;
                }
                ch = cn.next_sibling;
            }
        }
    }

    if (main_idx == parser_mod.NO_NODE) {
        cb.li(cg.A7, 93);
        cb.li(cg.A0, 0);
        cb.ecall();
        return cb;
    }

    const call_pos = cb.len;
    cb.jal(cg.RA);
    cb.li(cg.A7, 93);
    cb.ecall();

    var main_body_pos: usize = 0;
    pi = 0;
    while (pi < parser_mod.MAX_NODES) : (pi += 1) {
        const n = &pool[pi];
        if (n.kind == .program) {
            var ch = n.first_child;
            while (ch != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(ch))];
                if (cn.kind == .fn_decl) {
                    if (ch == main_idx) main_body_pos = cb.len;
                    compileFn(cn, pool, &cb, &vars, &vc, &stack_off);
                }
                ch = cn.next_sibling;
            }
        }
    }

    cb.patchJal(call_pos, main_body_pos);
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
                if (pool[@as(usize, @intCast(ch2))].kind == .var_decl) var_count += 1;
                ch2 = pool[@as(usize, @intCast(ch2))].next_sibling;
            }
        }
        child = cn.next_sibling;
    }

    const frame: i32 = @as(i32, @intCast(var_count)) * 4;

    cb.sw(cg.RA, cg.SP, -4);
    cb.sw(cg.FP, cg.SP, -8);
    cb.addi(cg.FP, cg.SP, -8);
    cb.addi(cg.SP, cg.SP, -8 - frame);

    child = n.first_child;
    while (child != parser_mod.NO_NODE) {
        compileStmt(child, pool, cb, vars, vc, stack_off);
        child = pool[@as(usize, @intCast(child))].next_sibling;
    }

    cb.li(cg.A0, 0);
    cb.addi(cg.SP, cg.FP, 8);
    cb.lw(cg.FP, cg.SP, -8);
    cb.lw(cg.RA, cg.SP, -4);
    cb.addi(cg.SP, cg.SP, 8);
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
                cb.li(cg.A0, 0);
            }
            cb.addi(cg.SP, cg.FP, 8);
            cb.lw(cg.FP, cg.SP, -8);
            cb.lw(cg.RA, cg.SP, -4);
            cb.addi(cg.SP, cg.SP, 8);
            cb.ret();
        },
        .var_decl => {
            const name = n.name_start[0..n.name_len];
            stack_off.* -= 4;
            const off = stack_off.*;
            if (vc.* < MAX_VARS) {
                vars[vc.*] = Var{ .name = name, .off = off };
                vc.* += 1;
            }
            if (n.first_child != parser_mod.NO_NODE) {
                compileExprNode(n.first_child, pool, cb, vars, vc);
            } else {
                cb.li(cg.A0, 0);
            }
            cb.sw(cg.A0, cg.FP, off);
        },
        .call => compileCall(n, pool, cb, vars, vc),
        .assign => {
            const name = n.name_start[0..n.name_len];
            const off = findVar(vars, vc.*, name);
            if (n.first_child != parser_mod.NO_NODE) {
                compileExprNode(n.first_child, pool, cb, vars, vc);
            } else {
                cb.li(cg.A0, 0);
            }
            if (off) |o| cb.sw(cg.A0, cg.FP, o);
        },
        .if_stmt => compileIf(n, pool, cb, vars, vc, stack_off),
        .while_stmt => compileWhile(n, pool, cb, vars, vc, stack_off),
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
    if (idx == parser_mod.NO_NODE) { cb.li(cg.A0, 0); return; }
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .int_lit => cb.li(cg.A0, @as(i32, @intCast(strToInt(n.val_start[0..n.val_len])))),
        .str_lit => cb.li(cg.A0, 0),
        .ident => {
            if (findVar(vars, vc.*, n.name_start[0..n.name_len])) |off| {
                cb.lw(cg.A0, cg.FP, off);
            } else {
                cb.li(cg.A0, 0);
            }
        },
        .binary_op => compileBinaryOp(n, pool, cb, vars, vc),
        .unary_op => compileUnaryOp(n, pool, cb, vars, vc),
        else => cb.li(cg.A0, 0),
    }
}

fn compileBinaryOp(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    const op = n.name_start[0..n.name_len];
    const left = n.first_child;
    const right = if (left != parser_mod.NO_NODE)
        pool[@as(usize, @intCast(left))].next_sibling
    else
        parser_mod.NO_NODE;
    if (left == parser_mod.NO_NODE or right == parser_mod.NO_NODE) { cb.li(cg.A0, 0); return; }

    compileExprNode(left, pool, cb, vars, vc);
    cb.pushR(cg.A0);
    compileExprNode(right, pool, cb, vars, vc);
    cb.mv(cg.T0, cg.A0);
    cb.popR(cg.A0);

    if (eq(op, "+")) {
        cb.add(cg.A0, cg.A0, cg.T0);
    } else if (eq(op, "-")) {
        cb.sub(cg.A0, cg.A0, cg.T0);
    } else if (eq(op, "*")) {
        cb.mul(cg.A0, cg.A0, cg.T0);
    } else if (eq(op, "/")) {
        cb.div(cg.A0, cg.A0, cg.T0);
    } else if (eq(op, "==")) {
        cb.sub(cg.T1, cg.A0, cg.T0);
        cb.seqz(cg.A0, cg.T1);
    } else if (eq(op, "!=")) {
        cb.sub(cg.T1, cg.A0, cg.T0);
        cb.snez(cg.A0, cg.T1);
    } else if (eq(op, "<")) {
        cb.slt(cg.A0, cg.A0, cg.T0);
    } else if (eq(op, ">")) {
        cb.slt(cg.A0, cg.T0, cg.A0);
    } else if (eq(op, "<=")) {
        cb.slt(cg.A0, cg.T0, cg.A0);
        cb.seqz(cg.A0, cg.A0);
    } else if (eq(op, ">=")) {
        cb.slt(cg.A0, cg.A0, cg.T0);
        cb.seqz(cg.A0, cg.A0);
    } else if (eq(op, "&&")) {
        cb.and_(cg.A0, cg.A0, cg.T0);
        cb.snez(cg.A0, cg.A0);
    } else if (eq(op, "||")) {
        cb.or_(cg.A0, cg.A0, cg.T0);
        cb.snez(cg.A0, cg.A0);
    } else {
        cb.li(cg.A0, 0);
    }
}

fn compileUnaryOp(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    const op = n.name_start[0..n.name_len];
    const operand = n.first_child;
    compileExprNode(operand, pool, cb, vars, vc);
    if (eq(op, "-")) {
        cb.neg(cg.A0, cg.A0);
    } else if (eq(op, "!")) {
        cb.seqz(cg.A0, cg.A0);
    }
}

fn compileCall(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, _vars: *[MAX_VARS]Var, _vc: *usize) void {
    _ = _vars;
    _ = _vc;
    const name = n.name_start[0..n.name_len];
    if (eq(name, "syscall")) {
        var args: [6]i32 = .{0} ** 6;
        var ai: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and ai < 6) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (cn.kind == .int_lit) args[ai] = @as(i32, @intCast(strToInt(cn.val_start[0..cn.val_len])));
            ai += 1;
            ch = cn.next_sibling;
        }
        if (ai > 0) {
            cb.li(cg.A7, args[0]);
            if (ai > 1) cb.li(cg.A0, args[1]);
            if (ai > 2) cb.li(cg.A1, args[2]);
            if (ai > 3) cb.li(cg.A2, args[3]);
            if (ai > 4) cb.li(cg.A3, args[4]);
            if (ai > 5) cb.li(cg.A4, args[5]);
        }
        cb.ecall();
        return;
    }
    cb.li(cg.A0, 0);
}

fn compileIf(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32) void {
    const cond = n.first_child;
    const then_blk = if (cond != parser_mod.NO_NODE) pool[@as(usize, @intCast(cond))].next_sibling else parser_mod.NO_NODE;
    const else_blk = if (then_blk != parser_mod.NO_NODE) pool[@as(usize, @intCast(then_blk))].next_sibling else parser_mod.NO_NODE;

    if (cond != parser_mod.NO_NODE) compileExprNode(cond, pool, cb, vars, vc) else cb.li(cg.A0, 0);
    const beq_pos = cb.len;
    cb.beq(cg.A0, cg.ZERO);

    if (then_blk != parser_mod.NO_NODE) compileStmt(then_blk, pool, cb, vars, vc, stack_off);

    var has_else = false;
    const jmp_pos = cb.len;
    if (else_blk != parser_mod.NO_NODE) { has_else = true; cb.jal(cg.ZERO); }

    const else_pos = cb.len;
    cb.patchBranch(beq_pos, else_pos);

    if (else_blk != parser_mod.NO_NODE) compileStmt(else_blk, pool, cb, vars, vc, stack_off);

    const end_pos = cb.len;
    if (has_else) cb.patchJal(jmp_pos, end_pos);
}

fn compileWhile(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32) void {
    const cond = n.first_child;
    const body = if (cond != parser_mod.NO_NODE) pool[@as(usize, @intCast(cond))].next_sibling else parser_mod.NO_NODE;

    const loop_pos = cb.len;

    if (cond != parser_mod.NO_NODE) compileExprNode(cond, pool, cb, vars, vc) else cb.li(cg.A0, 0);
    const beq_pos = cb.len;
    cb.beq(cg.A0, cg.ZERO);

    if (body != parser_mod.NO_NODE) compileStmt(body, pool, cb, vars, vc, stack_off);

    const jmp_pos = cb.len;
    cb.jal(cg.ZERO);
    cb.patchJal(jmp_pos, loop_pos);

    const end_pos = cb.len;
    cb.patchBranch(beq_pos, end_pos);
}

fn findVar(vars: *[MAX_VARS]Var, count: usize, name: []const u8) ?i32 {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (eq(vars[i].name, name)) return vars[i].off;
    }
    return null;
}
