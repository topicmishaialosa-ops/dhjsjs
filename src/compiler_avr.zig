const parser_mod = @import("parser.zig");
const cg = @import("codegen_avr.zig");

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
            if (c >= '0' and c <= '9') v |= @as(i64, c - '0');
            if (c >= 'a' and c <= 'f') v |= @as(i64, c - 'a' + 10);
            if (c >= 'A' and c <= 'F') v |= @as(i64, c - 'A' + 10);
        }
    } else {
        while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) v = v * 10 + (s[i] - '0');
    }
    return v;
}

const Var = struct { name: []const u8, off: i32 };
const MAX_VARS = 64;
const NO_NODE: parser_mod.NodeIdx = -1;

pub fn compile(prog_root: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode) cg.CodeBuffer {
    var cb = cg.CodeBuffer.init();
    var vars: [MAX_VARS]Var = undefined;
    var vc: usize = 0;
    var stack_off: i32 = 2;

    if (prog_root == parser_mod.NO_NODE) {
        cb.li32(cg.A0, 0);
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
        cb.li32(cg.A0, 0);
        return cb;
    }

    cb.jmp();
    const jmp_patch = cb.len - 2;
    cb.patch_word(jmp_patch, 4);

    cb.eor(cg.R1, cg.R1);
    cb.ldi(cg.A0 + 3, @as(u8, @truncate(cg.RAMEND >> 8)));
    cb.ldi(cg.A0 + 2, @as(u8, @truncate(cg.RAMEND)));
    cb.out(cg.SPH, cg.A0 + 3);
    cb.out(cg.SPL, cg.A0 + 2);
    cb.movw(cg.Y, cg.SP);

    const call_pos = cb.len;
    cb.rcall_rel();

    cb.li32(cg.A0, 0);
    const infloop = cb.len;
    cb.rjmp_rel();
    cb.patch_rjmp(cb.len - 2, infloop / 2);

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

    cb.patch_rjmp(call_pos, main_body_pos / 2);
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
                    if (st.val_len > 0) arr_sz = @as(i32, @intCast(strToInt(st.val_start[0..st.val_len])));
                    var_count += @as(usize, @intCast(@max(1, arr_sz)));
                }
                ch2 = pool[@as(usize, @intCast(ch2))].next_sibling;
            }
        }
        child = cn.next_sibling;
    }

    const frame: i32 = @as(i32, @intCast(var_count)) * 4;
    cb.push(cg.R1);
    cb.push(cg.YH);
    cb.push(cg.YL);
    cb.in_(cg.YL, cg.SPL);
    cb.in_(cg.YH, cg.SPH);
    if (frame > 0) {
        cb.ldi(cg.A0, @as(u8, @truncate(@as(u32, @bitCast(frame)))));
        cb.ldi(cg.A0 + 1, @as(u8, @truncate(@as(u32, @bitCast(frame >> 8)))));
        cb.sub(cg.YL, cg.A0);
        cb.sbc(cg.YH, cg.A0 + 1);
        cb.out(cg.SPL, cg.YL);
        cb.out(cg.SPH, cg.YH);
        cb.movw(cg.Z, cg.Y);
        cb.adiw(cg.Z, 6);
        cb.ldi(cg.A0, @as(u8, @truncate(@as(u32, @bitCast(frame)))));
        var i: i32 = 0;
        while (i < frame) : (i += 4) {
            cb.ldi(cg.A0, 0);
            cb.ldi(cg.A0 + 1, 0);
            cb.ldi(cg.A0 + 2, 0);
            cb.ldi(cg.A0 + 3, 0);
            cb.st_z_inc(cg.A0);
            cb.st_z_inc(cg.A0 + 1);
            cb.st_z_inc(cg.A0 + 2);
            cb.st_z_inc(cg.A0 + 3);
        }
    }

    child = n.first_child;
    while (child != parser_mod.NO_NODE) {
        compileStmt(child, pool, cb, vars, vc, stack_off);
        child = pool[@as(usize, @intCast(child))].next_sibling;
    }

    cb.li32(cg.A0, 0);
    cb.out(cg.SPL, cg.YL);
    cb.out(cg.SPH, cg.YH);
    cb.pop(cg.YL);
    cb.pop(cg.YH);
    cb.pop(cg.R1);
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
                cb.li32(cg.A0, 0);
            }
            cb.out(cg.SPL, cg.YL);
            cb.out(cg.SPH, cg.YH);
            cb.pop(cg.YL);
            cb.pop(cg.YH);
            cb.pop(cg.R1);
            cb.ret();
        },
        .var_decl => {
            const name = n.name_start[0..n.name_len];
            var arr_sz: i32 = 1;
            const init_expr: parser_mod.NodeIdx = n.first_child;
            if (n.val_len > 0) arr_sz = @as(i32, @intCast(strToInt(n.val_start[0..n.val_len])));
            const total_slots: i32 = @max(1, arr_sz);
            var si: i32 = 0;
            var first_off: i32 = 0;
            while (si < total_slots) : (si += 1) {
                stack_off.* -= 4;
                const off = stack_off.*;
                if (si == 0) {
                    first_off = off;
                    if (vc.* < MAX_VARS) { vars[vc.*] = Var{ .name = name, .off = off }; vc.* += 1; }
                }
                if (si == 0 and init_expr != parser_mod.NO_NODE) {
                    compileExprNode(init_expr, pool, cb, vars, vc);
                    cb.storeVar(off, cg.A0);
                } else if (si == 0 and init_expr == parser_mod.NO_NODE and total_slots == 1) {
                    cb.li32(cg.A0, 0);
                    cb.storeVar(off, cg.A0);
                }
            }
        },
        .call => compileCall(n, pool, cb, vars, vc),
        .assign => {
            if (n.first_child != parser_mod.NO_NODE) {
                compileExprNode(n.first_child, pool, cb, vars, vc);
            } else {
                cb.li32(cg.A0, 0);
            }
            const name = n.name_start[0..n.name_len];
            if (findVarOffset(vars, vc.*, name)) |o| cb.storeVar(o, cg.A0);
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
    if (idx == parser_mod.NO_NODE) { cb.li32(cg.A0, 0); return; }
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .int_lit => cb.li32(cg.A0, @as(i32, @truncate(strToInt(n.val_start[0..n.val_len])))),
        .str_lit => cb.li32(cg.A0, 0),
        .ident => {
            if (findVarOffset(vars, vc.*, n.name_start[0..n.name_len])) |off| {
                cb.loadVar(cg.A0, off);
            } else cb.li32(cg.A0, 0);
        },
        .binary_op => compileBinaryOp(n, pool, cb, vars, vc),
        .unary_op => compileUnaryOp(n, pool, cb, vars, vc),
        .field_access => compileFieldAccess(n, pool, cb, vars, vc),
        .array_index => compileArrayIndex(n, pool, cb, vars, vc),
        .addr_of => compileAddrOf(n, pool, cb, vars, vc),
        .deref => compileDeref(n, pool, cb, vars, vc),
        .sizeof_expr => cb.li32(cg.A0, 4),
        else => cb.li32(cg.A0, 0),
    }
}

fn compileExprAddr(idx: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    if (idx == parser_mod.NO_NODE) { cb.li32(cg.A0, 0); return; }
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .ident => {
            if (findVarOffset(vars, vc.*, n.name_start[0..n.name_len])) |off| {
                cb.movw(cg.Z, cg.Y);
                cb.ldi(cg.T0, @as(u8, @truncate(@as(u32, @bitCast(off)))));
                cb.add(cg.ZL, cg.T0);
                cb.ldi(cg.T0, @as(u8, @truncate(@as(u32, @bitCast(off >> 8)))));
                cb.adc(cg.ZH, cg.T0);
                cb.mov(cg.A0, cg.ZL);
                cb.mov(cg.A0 + 1, cg.ZH);
                cb.li32(cg.A0 + 2, 0);
            } else cb.li32(cg.A0, 0);
        },
        .deref => compileExprNode(n.first_child, pool, cb, vars, vc),
        .field_access => {
            compileExprAddr(n.first_child, pool, cb, vars, vc);
            const field = n.name_start[0..n.name_len];
            const field_off = findFieldOffset(pool, field);
            if (field_off > 0) {
                cb.ldi(cg.T0, @as(u8, @truncate(@as(u32, @bitCast(field_off)))));
                cb.add(cg.A0, cg.T0);
                cb.ldi(cg.T0, @as(u8, @truncate(@as(u32, @bitCast(field_off >> 8)))));
                cb.adc(cg.A0 + 1, cg.T0);
            }
        },
        .array_index => {
            compileExprAddr(n.first_child, pool, cb, vars, vc);
            const idx_node = if (n.first_child != parser_mod.NO_NODE)
                pool[@as(usize, @intCast(n.first_child))].next_sibling else parser_mod.NO_NODE;
            if (idx_node != parser_mod.NO_NODE) {
                cb.pushR32(cg.A0);
                compileExprNode(idx_node, pool, cb, vars, vc);
                cb.mov(cg.T0, cg.A0);
                cb.mov(cg.T0 + 1, cg.A0 + 1);
                cb.mov(cg.T0 + 2, cg.A0 + 2);
                cb.mov(cg.T0 + 3, cg.A0 + 3);
                cb.popR32(cg.A0);
                cb.lsl32(cg.T0);
                cb.lsl32(cg.T0);
                cb.lsl32(cg.T0);
                cb.add(cg.A0, cg.T0);
                cb.adc(cg.A0 + 1, cg.T0 + 1);
                cb.adc(cg.A0 + 2, cg.T0 + 2);
                cb.adc(cg.A0 + 3, cg.T0 + 3);
            }
        },
        else => compileExprNode(idx, pool, cb, vars, vc),
    }
}

fn compileBinaryOp(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    const op = n.name_start[0..n.name_len];
    const left = n.first_child;
    const right = if (left != parser_mod.NO_NODE) pool[@as(usize, @intCast(left))].next_sibling else parser_mod.NO_NODE;
    if (left == parser_mod.NO_NODE or right == parser_mod.NO_NODE) { cb.li32(cg.A0, 0); return; }

    compileExprNode(left, pool, cb, vars, vc);
    cb.pushR32(cg.A0);
    compileExprNode(right, pool, cb, vars, vc);
    cb.mov(cg.T0, cg.A0);
    cb.mov(cg.T0 + 1, cg.A0 + 1);
    cb.mov(cg.T0 + 2, cg.A0 + 2);
    cb.mov(cg.T0 + 3, cg.A0 + 3);
    cb.popR32(cg.A0);

    if (eq(op, "+")) {
        cb.add32(cg.A0, cg.T0);
    } else if (eq(op, "-")) {
        cb.sub32(cg.A0, cg.T0);
    } else if (eq(op, "*")) {
        cb.li32(cg.A0, 0);
    } else if (eq(op, "/") or eq(op, "%")) {
        cb.li32(cg.A0, 0);
    } else if (eq(op, "==")) {
        cb.cp32(cg.A0, cg.T0);
        set_eq(cb);
    } else if (eq(op, "!=")) {
        cb.cp32(cg.A0, cg.T0);
        set_ne(cb);
    } else if (eq(op, "<")) {
        cb.cp32(cg.A0, cg.T0);
        set_lt(cb);
    } else if (eq(op, ">")) {
        cb.cp32(cg.T0, cg.A0);
        set_lt(cb);
    } else if (eq(op, "<=")) {
        cb.cp32(cg.T0, cg.A0);
        set_ge(cb);
    } else if (eq(op, ">=")) {
        cb.cp32(cg.A0, cg.T0);
        set_ge(cb);
    } else if (eq(op, "&&")) {
        cb.and32(cg.A0, cg.T0);
        cb.mov(cg.T0, cg.A0);
        cb.or_(cg.T0, cg.A0 + 1);
        cb.or_(cg.T0, cg.A0 + 2);
        cb.or_(cg.T0, cg.A0 + 3);
        cb.ldi(cg.A0, 0);
        cb.ldi(cg.A0 + 1, 0);
        cb.ldi(cg.A0 + 2, 0);
        cb.ldi(cg.A0 + 3, 0);
        const br_a = cb.len;
        cb.breq(0);
        cb.patch_br(br_a, cb.len / 2 + 4);
        cb.ldi(cg.A0, 1);
        cb.ldi(cg.A0 + 1, 0);
    } else if (eq(op, "||")) {
        cb.or32(cg.A0, cg.T0);
        cb.mov(cg.T0, cg.A0);
        cb.or_(cg.T0, cg.A0 + 1);
        cb.or_(cg.T0, cg.A0 + 2);
        cb.or_(cg.T0, cg.A0 + 3);
        cb.ldi(cg.A0, 0);
        cb.ldi(cg.A0 + 1, 0);
        cb.ldi(cg.A0 + 2, 0);
        cb.ldi(cg.A0 + 3, 0);
        const br_o = cb.len;
        cb.breq(0);
        cb.patch_br(br_o, cb.len / 2 + 4);
        cb.ldi(cg.A0, 1);
        cb.ldi(cg.A0 + 1, 0);
    } else {
        cb.li32(cg.A0, 0);
    }
}

fn set_lt(cb: *cg.CodeBuffer) void {
    cb.ldi(cg.A0, 0);
    cb.ldi(cg.A0 + 1, 0);
    cb.ldi(cg.A0 + 2, 0);
    cb.ldi(cg.A0 + 3, 0);
    const br = cb.len;
    cb.brge(0);
    cb.patch_br(br, cb.len / 2 + 4);
    cb.ldi(cg.A0, 1);
    cb.ldi(cg.A0 + 1, 0);
}

fn set_ge(cb: *cg.CodeBuffer) void {
    cb.ldi(cg.A0, 0);
    cb.ldi(cg.A0 + 1, 0);
    cb.ldi(cg.A0 + 2, 0);
    cb.ldi(cg.A0 + 3, 0);
    const br = cb.len;
    cb.brlt(0);
    cb.patch_br(br, cb.len / 2 + 4);
    cb.ldi(cg.A0, 1);
    cb.ldi(cg.A0 + 1, 0);
}

fn set_eq(cb: *cg.CodeBuffer) void {
    cb.ldi(cg.A0, 0);
    cb.ldi(cg.A0 + 1, 0);
    cb.ldi(cg.A0 + 2, 0);
    cb.ldi(cg.A0 + 3, 0);
    const br = cb.len;
    cb.brne(0);
    cb.patch_br(br, cb.len / 2 + 4);
    cb.ldi(cg.A0, 1);
    cb.ldi(cg.A0 + 1, 0);
}

fn set_ne(cb: *cg.CodeBuffer) void {
    cb.ldi(cg.A0, 0);
    cb.ldi(cg.A0 + 1, 0);
    cb.ldi(cg.A0 + 2, 0);
    cb.ldi(cg.A0 + 3, 0);
    const br = cb.len;
    cb.breq(0);
    cb.patch_br(br, cb.len / 2 + 4);
    cb.ldi(cg.A0, 1);
    cb.ldi(cg.A0 + 1, 0);
}

fn compileUnaryOp(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    const op = n.name_start[0..n.name_len];
    const operand = n.first_child;
    compileExprNode(operand, pool, cb, vars, vc);
    if (eq(op, "-")) {
        cb.neg32(cg.A0);
    } else if (eq(op, "!")) {
        cb.cp(cg.A0, cg.R1);
        cb.cpc(cg.A0 + 1, cg.R1);
        cb.cpc(cg.A0 + 2, cg.R1);
        cb.cpc(cg.A0 + 3, cg.R1);
        cb.ldi(cg.A0, 0);
        cb.ldi(cg.A0 + 1, 0);
        cb.ldi(cg.A0 + 2, 0);
        cb.ldi(cg.A0 + 3, 0);
        const br = cb.len;
        cb.brne(0);
        cb.patch_br(br, cb.len / 2 + 4);
        cb.ldi(cg.A0, 1);
        cb.ldi(cg.A0 + 1, 0);
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
            if (cn.kind == .int_lit) args[ai] = @as(i32, @truncate(strToInt(cn.val_start[0..cn.val_len])));
            ai += 1;
            ch = cn.next_sibling;
        }
        if (ai > 0 and args[0] == 0 and ai > 2) {
            const port_addr = @as(u8, @truncate(@as(u32, @bitCast(args[1]))));
            const val = @as(u8, @truncate(@as(u32, @bitCast(args[2]))));
            cb.ldi(cg.A0, val);
            cb.out(port_addr, cg.A0);
        }
        cb.li32(cg.A0, 0);
        return;
    }
    cb.li32(cg.A0, 0);
}

fn compileFieldAccess(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    compileExprAddr(n.first_child, pool, cb, vars, vc);
    const field = n.name_start[0..n.name_len];
    const field_off = findFieldOffset(pool, field);
    if (field_off > 0) {
        cb.ldi(cg.T0, @as(u8, @truncate(@as(u32, @bitCast(field_off)))));
        cb.add(cg.A0, cg.T0);
        cb.ldi(cg.T0, @as(u8, @truncate(@as(u32, @bitCast(field_off >> 8)))));
        cb.adc(cg.A0 + 1, cg.T0);
    }
    cb.movw(cg.Z, cg.A0);
    cb.ld_z_inc(cg.A0);
    cb.ld_z_inc(cg.A0 + 1);
    cb.ld_z_inc(cg.A0 + 2);
    cb.ld_z_inc(cg.A0 + 3);
}

fn compileArrayIndex(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    const arr = n.first_child;
    const idx = if (arr != parser_mod.NO_NODE) pool[@as(usize, @intCast(arr))].next_sibling else parser_mod.NO_NODE;
    if (arr == parser_mod.NO_NODE or idx == parser_mod.NO_NODE) { cb.li32(cg.A0, 0); return; }

    compileExprAddr(arr, pool, cb, vars, vc);
    cb.pushR32(cg.A0);
    compileExprNode(idx, pool, cb, vars, vc);
    cb.mov(cg.T0, cg.A0);
    cb.mov(cg.T0 + 1, cg.A0 + 1);
    cb.mov(cg.T0 + 2, cg.A0 + 2);
    cb.mov(cg.T0 + 3, cg.A0 + 3);
    cb.popR32(cg.A0);
    cb.lsl32(cg.T0);
    cb.lsl32(cg.T0);
    cb.lsl32(cg.T0);
    cb.add(cg.A0, cg.T0);
    cb.adc(cg.A0 + 1, cg.T0 + 1);
    cb.adc(cg.A0 + 2, cg.T0 + 2);
    cb.adc(cg.A0 + 3, cg.T0 + 3);
    cb.movw(cg.Z, cg.A0);
    cb.ld_z_inc(cg.A0);
    cb.ld_z_inc(cg.A0 + 1);
    cb.ld_z_inc(cg.A0 + 2);
    cb.ld_z_inc(cg.A0 + 3);
}

fn compileAddrOf(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    compileExprAddr(n.first_child, pool, cb, vars, vc);
}

fn compileDeref(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    compileExprNode(n.first_child, pool, cb, vars, vc);
    cb.movw(cg.Z, cg.A0);
    cb.ld_z_inc(cg.A0);
    cb.ld_z_inc(cg.A0 + 1);
    cb.ld_z_inc(cg.A0 + 2);
    cb.ld_z_inc(cg.A0 + 3);
}

fn compileIf(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32) void {
    const cond = n.first_child;
    const then_blk = if (cond != parser_mod.NO_NODE) pool[@as(usize, @intCast(cond))].next_sibling else parser_mod.NO_NODE;
    const else_blk = if (then_blk != parser_mod.NO_NODE) pool[@as(usize, @intCast(then_blk))].next_sibling else parser_mod.NO_NODE;

    if (cond != parser_mod.NO_NODE) compileExprNode(cond, pool, cb, vars, vc) else cb.li32(cg.A0, 0);
    const br_pos = cb.len;
    cb.breq(0);

    if (then_blk != parser_mod.NO_NODE) compileStmt(then_blk, pool, cb, vars, vc, stack_off);

    var has_else = false;
    const jmp_pos = cb.len;
    if (else_blk != parser_mod.NO_NODE) { has_else = true; cb.rjmp_rel(); }

    const else_pos = cb.len;
    cb.patch_br(br_pos, else_pos / 2);

    if (else_blk != parser_mod.NO_NODE) compileStmt(else_blk, pool, cb, vars, vc, stack_off);

    const end_pos = cb.len;
    if (has_else) cb.patch_rjmp(jmp_pos, end_pos / 2);
}

fn compileWhile(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32) void {
    const cond = n.first_child;
    const body = if (cond != parser_mod.NO_NODE) pool[@as(usize, @intCast(cond))].next_sibling else parser_mod.NO_NODE;

    const loop_pos = cb.len;

    if (cond != parser_mod.NO_NODE) compileExprNode(cond, pool, cb, vars, vc) else cb.li32(cg.A0, 0);
    const br_pos = cb.len;
    cb.breq(0);

    if (body != parser_mod.NO_NODE) compileStmt(body, pool, cb, vars, vc, stack_off);

    const jmp_pos = cb.len;
    cb.rjmp_rel();
    cb.patch_rjmp(jmp_pos, loop_pos / 2);

    const end_pos = cb.len;
    cb.patch_br(br_pos, end_pos / 2);
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
                    if (eq(cn.name_start[0..cn.name_len], field)) return fi * 4;
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
