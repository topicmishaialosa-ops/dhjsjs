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

const Var = struct { name: []const u8, off: i32 }; // off is SP-relative (positive)
const MAX_VARS = 64;
const NO_NODE: parser_mod.NodeIdx = -1;

fn structFieldCount(pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, name: []const u8) i32 {
    var pi: usize = 0;
    while (pi < parser_mod.MAX_NODES) : (pi += 1) {
        const n = &pool[pi];
        if (n.kind == .struct_decl and eq(n.name_start[0..n.name_len], name)) {
            var count: i32 = 0;
            var ch = n.first_child;
            while (ch != parser_mod.NO_NODE) {
                if (pool[@as(usize, @intCast(ch))].kind == .var_decl) { count += 1; }
                ch = pool[@as(usize, @intCast(ch))].next_sibling;
            }
            return count;
        }
    }
    return 0;
}

pub fn compile(prog_root: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode) cg.CodeBuffer {
    return compileEx(prog_root, pool, false);
}

pub fn compileEx(prog_root: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, keep_alive: bool) cg.CodeBuffer {
    var cb = cg.CodeBuffer.init();
    var vars: [MAX_VARS]Var = undefined;
    var vc: usize = 0;
    var stack_off: i32 = 0;
    var loop_stack: [16]usize = undefined;
    var loop_depth: usize = 0;

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

    // Entry: call main
    const call_pos = cb.len;
    cb.bl(); // placeholder → patched to main
    if (keep_alive) {
        const loop_pos = cb.len;
        cb.branch();
        cb.patchB(loop_pos, loop_pos);
    } else {
        cb.movRImm64(cg.X8, 93);
        // X0 already holds main's return value after BL
        cb.svc(0);
    }

    var main_body_pos: usize = 0;
    ch = prog.first_child;
    while (ch != parser_mod.NO_NODE) {
        const cn = &pool[@as(usize, @intCast(ch))];
        if (cn.kind == .fn_decl) {
            if (ch == main_idx) main_body_pos = cb.len;
            compileFn(cn, pool, &cb, &vars, &vc, &stack_off, &loop_stack, &loop_depth);
        }
        ch = cn.next_sibling;
    }

    cb.patchBL(call_pos, main_body_pos);
    return cb;
}

fn countVarDecls(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode) i32 {
    if (n.first_child == parser_mod.NO_NODE) return 0;
    var count: i32 = 0;
    var ch = n.first_child;
    while (ch != parser_mod.NO_NODE) {
        const cn = &pool[@as(usize, @intCast(ch))];
        switch (cn.kind) {
            .var_decl => {
                var arr_sz: i32 = 1;
                if (cn.val_len > 0) arr_sz = @as(i32, @intCast(strToInt(cn.val_start[0..cn.val_len])));
                count += @max(1, arr_sz);
            },
            .assign => {
                count += 1;
            },
            .struct_var_decl => {
                const field_count = structFieldCount(pool, cn.name_start[0..cn.name_len]);
                count += @max(1, field_count);
            },
            .block => {
                count += countVarDecls(cn, pool);
            },
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

fn compileFn(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32, loop_stack: *[16]usize, loop_depth: *usize) void {
    const var_count: i32 = countVarDecls(n, pool);
    const frame: i32 = @as(i32, @intCast(var_count)) * 8;

    cb.stpPre(cg.FP, cg.X30, 31, -16);
    cb.addi(cg.FP, 31, 0);
    if (frame > 0) cb.subi(31, 31, @as(u16, @intCast(frame)));

    var child = n.first_child;
    while (child != parser_mod.NO_NODE) {
        compileStmt(child, pool, cb, vars, vc, stack_off, frame, loop_stack, loop_depth);
        child = pool[@as(usize, @intCast(child))].next_sibling;
    }

    cb.mov(cg.X0, cg.ZR);
    if (frame > 0) cb.addi(31, 31, @as(u16, @intCast(frame)));
    cb.ldpPost(cg.FP, cg.X30, 31, 16);
    cb.ret();
}

fn compileStmt(idx: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32, frame: i32, loop_stack: *[16]usize, loop_depth: *usize) void {
    if (idx == parser_mod.NO_NODE) return;
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .block => {
            var ch = n.first_child;
            while (ch != parser_mod.NO_NODE) {
                compileStmt(ch, pool, cb, vars, vc, stack_off, frame, loop_stack, loop_depth);
                ch = pool[@as(usize, @intCast(ch))].next_sibling;
            }
        },
        .ret_stmt => {
            if (n.first_child != parser_mod.NO_NODE) {
                compileExprNode(n.first_child, pool, cb, vars, vc, frame);
            } else {
                cb.mov(cg.X0, cg.ZR);
            }
            cb.addi(31, cg.FP, 0);
            cb.ldpPost(cg.FP, cg.X30, 31, 16);
            cb.ret();
        },
        .var_decl => {
            const name = n.name_start[0..n.name_len];
            var arr_sz: i32 = 1;
            const init_expr: parser_mod.NodeIdx = n.first_child;
            if (n.val_len > 0) arr_sz = @as(i32, @intCast(strToInt(n.val_start[0..n.val_len])));
            const total_slots: i32 = @max(1, arr_sz);
            var si: i32 = 0;
            var first_sp_off: i32 = 0;
            while (si < total_slots) : (si += 1) {
                stack_off.* -= 8;
                const sp_off = stack_off.* + frame; // SP-relative, positive
                if (si == 0) {
                    first_sp_off = sp_off;
                    if (vc.* < MAX_VARS) {
                        vars[vc.*] = Var{ .name = name, .off = sp_off };
                        vc.* += 1;
                    }
                }
                if (si == 0 and init_expr != parser_mod.NO_NODE) {
                    compileExprNode(init_expr, pool, cb, vars, vc, frame);
                    cb.str64(cg.X0, 31, sp_off);
                } else if (si == 0 and init_expr == parser_mod.NO_NODE and total_slots == 1) {
                    cb.str64(cg.ZR, 31, sp_off);
                }
            }
        },
        .struct_var_decl => {
            const struct_name = n.name_start[0..n.name_len];
            const var_name = n.val_start[0..n.val_len];
            const field_count = structFieldCount(pool, struct_name);
            var i: i32 = 0;
            while (i < @max(1, field_count)) : (i += 1) {
                stack_off.* -= 8;
                const sp_off = stack_off.* + frame;
                if (vc.* < MAX_VARS) {
                    vars[vc.*] = Var{ .name = var_name, .off = sp_off };
                    vc.* += 1;
                }
                cb.str64(cg.ZR, 31, sp_off);
            }
        },
        .call => compileCall(n, pool, cb, vars, vc, frame),
        .assign => {
            const name = n.name_start[0..n.name_len];
            const existing = findVarOffset(vars, vc.*, name);
            const off = if (existing) |o| o else blk: {
                stack_off.* -= 8;
                const sp_off = stack_off.* + frame;
                if (vc.* < MAX_VARS) {
                    vars[vc.*] = Var{ .name = name, .off = sp_off };
                    vc.* += 1;
                }
                break :blk sp_off;
            };
            if (n.first_child != parser_mod.NO_NODE) {
                compileExprNode(n.first_child, pool, cb, vars, vc, frame);
            } else {
                cb.mov(cg.X0, cg.ZR);
            }
            cb.str64(cg.X0, 31, off);
        },
        .store => {
            const lvalue = n.first_child;
            const rvalue = if (lvalue != parser_mod.NO_NODE) pool[@as(usize, @intCast(lvalue))].next_sibling else parser_mod.NO_NODE;
            if (lvalue != parser_mod.NO_NODE and rvalue != parser_mod.NO_NODE) {
                compileExprAddr(lvalue, pool, cb, vars, vc, frame);
                pushX0(cb);
                compileExprNode(rvalue, pool, cb, vars, vc, frame);
                cb.ldr64(cg.X1, 31, 0);
                cb.addi(31, 31, 8);
                cb.str64(cg.X1, cg.X0, 0);
            }
        },
        .if_stmt => compileIf(n, pool, cb, vars, vc, stack_off, frame, loop_stack, loop_depth),
        .while_stmt => compileWhile(n, pool, cb, vars, vc, stack_off, frame, loop_stack, loop_depth),
        .break_stmt => {
            if (loop_depth.* > 0) {
                const end_pos = loop_stack[loop_depth.* - 1];
                cb.branch();
                cb.patchB(cb.len - 4, end_pos);
            }
        },
        .continue_stmt => {
            if (loop_depth.* > 0) {
                // continue: jump back to loop start (condition check)
                // We store loop_start at the begin slot and end at the next slot
                // Actually for continue we need the loop condition start
                // Loop stack stores: [loop_start, end_pos]
                // continue needs to jump to loop_start which is at [loop_depth-2]
                if (loop_depth.* >= 2) {
                    const cond_start = loop_stack[loop_depth.* - 2];
                    cb.branch();
                    cb.patchB(cb.len - 4, cond_start);
                }
            }
        },
        .struct_decl => {},
        else => {
            var ch = n.first_child;
            while (ch != parser_mod.NO_NODE) {
                compileStmt(ch, pool, cb, vars, vc, stack_off, frame, loop_stack, loop_depth);
                ch = pool[@as(usize, @intCast(ch))].next_sibling;
            }
        },
    }
}

fn compileExprNode(idx: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, frame: i32) void {
    if (idx == parser_mod.NO_NODE) { cb.mov(cg.X0, cg.ZR); return; }
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .int_lit => {
            const v = strToInt(n.val_start[0..n.val_len]);
            cb.movRImm64(cg.X0, @as(u64, @bitCast(v)));
        },
        .str_lit => {
            const s = n.val_start[0..n.val_len];
            const adr_pos = cb.len;
            cb.adr(cg.X0);
            const b_pos = cb.len;
            cb.dword(0x14000000);
            const str_pos = cb.len;
            for (s) |c| cb.byte(c);
            while (cb.len % 4 != 0) cb.byte(0);
            cb.patchAdr(adr_pos, str_pos);
            cb.patchB(b_pos, cb.len);
        },
        .ident => {
            if (findVarOffset(vars, vc.*, n.name_start[0..n.name_len])) |off| {
                cb.ldr64(cg.X0, 31, off);
            } else {
                cb.mov(cg.X0, cg.ZR);
            }
        },
        .binary_op => compileBinaryOp(n, pool, cb, vars, vc, frame),
        .unary_op => compileUnaryOp(n, pool, cb, vars, vc, frame),
        .field_access => compileFieldAccess(n, pool, cb, vars, vc, frame),
        .array_index => compileArrayIndex(n, pool, cb, vars, vc, frame),
        .addr_of => compileAddrOf(n, pool, cb, vars, vc, frame),
        .deref => compileDeref(n, pool, cb, vars, vc, frame),
        .sizeof_expr => compileSizeof(n, pool, cb, vars, vc),
        else => cb.mov(cg.X0, cg.ZR),
    }
}

fn compileExprAddr(idx: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, frame: i32) void {
    if (idx == parser_mod.NO_NODE) { cb.mov(cg.X0, cg.ZR); return; }
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .ident => {
            if (findVarOffset(vars, vc.*, n.name_start[0..n.name_len])) |off| {
                cb.addi(cg.X0, 31, @as(u16, @intCast(off)));
            } else { cb.mov(cg.X0, cg.ZR); }
        },
        .deref => {
            compileExprNode(n.first_child, pool, cb, vars, vc, frame);
        },
        .field_access => {
            compileExprAddr(n.first_child, pool, cb, vars, vc, frame);
            const field = n.name_start[0..n.name_len];
            const field_off = findFieldOffset(pool, field);
            if (field_off > 0) cb.addi(cg.X0, cg.X0, @as(u16, @intCast(field_off)));
        },
        .array_index => {
            compileExprAddr(n.first_child, pool, cb, vars, vc, frame);
            const idx_node = if (n.first_child != parser_mod.NO_NODE)
                pool[@as(usize, @intCast(n.first_child))].next_sibling
            else
                parser_mod.NO_NODE;
            if (idx_node != parser_mod.NO_NODE) {
                pushX0(cb);
                compileExprNode(idx_node, pool, cb, vars, vc, frame);
                cb.mov(cg.X10, cg.X0);
                popX0(cb);
                cb.subShift(cg.X0, cg.X0, cg.X10, 3);
            }
        },
        else => compileExprNode(idx, pool, cb, vars, vc, frame),
    }
}

fn pushX0(cb: *cg.CodeBuffer) void {
    cb.subi(31, 31, 8);
    cb.str64(cg.X0, 31, 0);
}

fn popX0(cb: *cg.CodeBuffer) void {
    cb.ldr64(cg.X0, 31, 0);
    cb.addi(31, 31, 8);
}

fn emitStackSub(cb: *cg.CodeBuffer, amount: u32) void {
    var rem = amount;
    while (rem > 0) {
        const chunk: u16 = if (rem > 2048) 2048 else @as(u16, @intCast(rem));
        cb.subi(31, 31, chunk);
        rem -= chunk;
    }
}

fn emitStackAdd(cb: *cg.CodeBuffer, amount: u32) void {
    var rem = amount;
    while (rem > 0) {
        const chunk: u16 = if (rem > 2048) 2048 else @as(u16, @intCast(rem));
        cb.addi(31, 31, chunk);
        rem -= chunk;
    }
}

fn emitAddrFromSp(cb: *cg.CodeBuffer, dst: u8, off: u32) void {
    cb.addi(dst, 31, 0);
    var rem = off;
    while (rem > 0) {
        const chunk: u16 = if (rem > 2048) 2048 else @as(u16, @intCast(rem));
        cb.addi(dst, dst, chunk);
        rem -= chunk;
    }
}

fn emitWriteLit(cb: *cg.CodeBuffer, dst: u8, s: []const u8) void {
    for (s) |c| {
        cb.movRImm64(cg.X0, c);
        cb.str8(cg.X0, dst, 0);
        cb.addi(dst, dst, 1);
    }
}

fn emitCopyCString(cb: *cg.CodeBuffer, dst: u8, src: u8) void {
    const loop_pos = cb.len;
    cb.ldr8(cg.X0, src, 0);
    const done_pos = cb.len;
    cb.cbz(cg.X0);
    cb.str8(cg.X0, dst, 0);
    cb.addi(dst, dst, 1);
    cb.addi(src, src, 1);
    const jump_pos = cb.len;
    cb.branch();
    cb.patchB(jump_pos, loop_pos);
    cb.patchCBZ(done_pos, cb.len);
}

fn emitCStringLen(cb: *cg.CodeBuffer, src: u8, len_reg: u8) void {
    cb.mov(len_reg, cg.ZR);
    cb.cmp(src, cg.ZR);
    const null_pos = cb.len;
    cb.beq();
    cb.mov(cg.X14, src);
    const loop_pos = cb.len;
    cb.ldr8(cg.X0, cg.X14, 0);
    const done_pos = cb.len;
    cb.cbz(cg.X0);
    cb.addi(cg.X14, cg.X14, 1);
    cb.addi(len_reg, len_reg, 1);
    const jump_pos = cb.len;
    cb.branch();
    cb.patchB(jump_pos, loop_pos);
    cb.patchCBZ(done_pos, cb.len);
    cb.patchBCond(null_pos, cb.len);
}

fn emitWriteUnsignedDecimal(cb: *cg.CodeBuffer, value_reg: u8, dst: u8) void {
    cb.mov(cg.X14, value_reg);
    cb.movRImm64(cg.X15, 10);
    cb.mov(cg.X16, cg.ZR);

    const div_loop = cb.len;
    cb.sdiv(cg.X17, cg.X14, cg.X15);
    cb.mul(cg.X18, cg.X17, cg.X15);
    cb.sub(cg.X18, cg.X14, cg.X18);
    cb.movRImm64(cg.X0, '0');
    cb.add(cg.X0, cg.X0, cg.X18);
    cb.addi(cg.X18, 31, 0);
    cb.add(cg.X18, cg.X18, cg.X16);
    cb.str8(cg.X0, cg.X18, 0);
    cb.addi(cg.X16, cg.X16, 1);
    cb.mov(cg.X14, cg.X17);
    const more_digits = cb.len;
    cb.cbnz(cg.X14);
    cb.patchCBNZ(more_digits, div_loop);

    const out_loop = cb.len;
    cb.subi(cg.X16, cg.X16, 1);
    cb.addi(cg.X18, 31, 0);
    cb.add(cg.X18, cg.X18, cg.X16);
    cb.ldr8(cg.X0, cg.X18, 0);
    cb.str8(cg.X0, dst, 0);
    cb.addi(dst, dst, 1);
    const out_more = cb.len;
    cb.cbnz(cg.X16);
    cb.patchCBNZ(out_more, out_loop);
}

fn emitWriteIpHost(cb: *cg.CodeBuffer, ip_reg: u8, dst: u8) void {
    var shift: u8 = 0;
    var part: usize = 0;
    while (part < 4) : (part += 1) {
        cb.lsrImm(cg.X26, ip_reg, shift);
        cb.movRImm64(cg.X27, 255);
        cb.and_(cg.X26, cg.X26, cg.X27);
        emitWriteUnsignedDecimal(cb, cg.X26, dst);
        if (part < 3) emitWriteLit(cb, dst, ".");
        shift += 8;
    }
}

fn compileArmArgToReg(
    idx: parser_mod.NodeIdx,
    dst: u8,
    default_value: i64,
    pool: *[parser_mod.MAX_NODES]parser_mod.AstNode,
    cb: *cg.CodeBuffer,
    vars: *[MAX_VARS]Var,
    vc: *usize,
    frame: i32,
) void {
    if (idx == parser_mod.NO_NODE) {
        cb.movRImm64(dst, @as(u64, @bitCast(default_value)));
        return;
    }
    const n = &pool[@as(usize, @intCast(idx))];
    if (n.kind == .int_lit) {
        cb.movRImm64(dst, @as(u64, @bitCast(strToInt(n.val_start[0..n.val_len]))));
        return;
    }
    compileExprNode(idx, pool, cb, vars, vc, frame);
    cb.mov(dst, cg.X0);
}

fn compileBinaryOp(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, frame: i32) void {
    const op = n.name_start[0..n.name_len];
    const left = n.first_child;
    const right = if (left != parser_mod.NO_NODE) pool[@as(usize, @intCast(left))].next_sibling else parser_mod.NO_NODE;
    if (left == parser_mod.NO_NODE or right == parser_mod.NO_NODE) { cb.mov(cg.X0, cg.ZR); return; }

    compileExprNode(left, pool, cb, vars, vc, frame);
    pushX0(cb);
    compileExprNode(right, pool, cb, vars, vc, frame);
    cb.mov(cg.X10, cg.X0);
    popX0(cb);

    if (eq(op, "+")) {
        cb.add(cg.X0, cg.X0, cg.X10);
    } else if (eq(op, "-")) {
        cb.sub(cg.X0, cg.X0, cg.X10);
    } else if (eq(op, "*")) {
        cb.mul(cg.X0, cg.X0, cg.X10);
    } else if (eq(op, "/")) {
        cb.sdiv(cg.X0, cg.X0, cg.X10);
    } else if (eq(op, "%")) {
        cb.sdiv(cg.X9, cg.X0, cg.X10);
        cb.mul(cg.X9, cg.X9, cg.X10);
        cb.sub(cg.X0, cg.X0, cg.X9);
    } else if (eq(op, "==")) {
        cb.sub(cg.X9, cg.X0, cg.X10);
        cb.cmp(cg.X9, cg.ZR);
        cb.cset(cg.X0, 0);
    } else if (eq(op, "!=")) {
        cb.sub(cg.X9, cg.X0, cg.X10);
        cb.cmp(cg.X9, cg.ZR);
        cb.cset(cg.X0, 1);
    } else if (eq(op, "<")) {
        cb.cmp(cg.X0, cg.X10);
        cb.cset(cg.X0, 10);
    } else if (eq(op, ">")) {
        cb.cmp(cg.X10, cg.X0);
        cb.cset(cg.X0, 10);
    } else if (eq(op, "<=")) {
        cb.cmp(cg.X10, cg.X0);
        cb.cset(cg.X0, 10);
        cb.eor(cg.X0, cg.X0, cg.ZR);
    } else if (eq(op, ">=")) {
        cb.cmp(cg.X0, cg.X10);
        cb.cset(cg.X0, 10);
        cb.eor(cg.X0, cg.X0, cg.ZR);
    } else if (eq(op, "&&")) {
        cb.and_(cg.X0, cg.X0, cg.X10);
        cb.cmp(cg.X0, cg.ZR);
        cb.cset(cg.X0, 1);
    } else if (eq(op, "||")) {
        cb.orr(cg.X0, cg.X0, cg.X10);
        cb.cmp(cg.X0, cg.ZR);
        cb.cset(cg.X0, 1);
    } else if (eq(op, "|")) {
        cb.orr(cg.X0, cg.X0, cg.X10);
    } else if (eq(op, "&")) {
        cb.and_(cg.X0, cg.X0, cg.X10);
    } else if (eq(op, "^")) {
        cb.eor(cg.X0, cg.X0, cg.X10);
    } else if (eq(op, "<<")) {
        cb.lsl(cg.X0, cg.X0, cg.X10);
    } else if (eq(op, ">>")) {
        cb.lsr(cg.X0, cg.X0, cg.X10);
    } else {
        cb.mov(cg.X0, cg.ZR);
    }
}

fn compileUnaryOp(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, frame: i32) void {
    const op = n.name_start[0..n.name_len];
    const operand = n.first_child;
    compileExprNode(operand, pool, cb, vars, vc, frame);
    if (eq(op, "-")) {
        cb.neg(cg.X0, cg.X0);
    } else if (eq(op, "!")) {
        cb.cmp(cg.X0, cg.ZR);
        cb.cset(cg.X0, 0);
    }
}

fn compileCall(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, frame: i32) void {
    const name = n.name_start[0..n.name_len];
    if (eq(name, "syscall")) {
        const regs = [_]u8{ cg.X8, cg.X0, cg.X1, cg.X2, cg.X3, cg.X4 };
        var ai: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and ai < 6) {
            compileExprNode(ch, pool, cb, vars, vc, frame);
            pushX0(cb);
            ch = pool[@as(usize, @intCast(ch))].next_sibling;
            ai += 1;
        }
        if (ai == 0) { cb.svc(0); return; }
        cb.ldr64(cg.X0, 31, @as(i32, @intCast((ai - 1) * 8)));
        if (regs[0] != cg.X0) cb.mov(regs[0], cg.X0);
        var ri: usize = ai;
        while (ri > 1) {
            ri -= 1;
            cb.ldr64(regs[ri], 31, 0);
            cb.addi(31, 31, 8);
        }
        cb.addi(31, 31, 8);
        cb.svc(0);
        return;
    }
    if (eq(name, "print")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) {
            compileExprNode(ch, pool, cb, vars, vc, frame);
            cb.mov(cg.X1, cg.X0);
        } else {
            cb.mov(cg.X1, cg.ZR);
        }
        var len: i64 = -1;
        if (ch != parser_mod.NO_NODE) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (cn.kind == .str_lit) len = @as(i64, @intCast(cn.val_len));
            if (len < 0 and cn.next_sibling != parser_mod.NO_NODE) {
                const len_node = &pool[@as(usize, @intCast(cn.next_sibling))];
                if (len_node.kind == .int_lit) len = strToInt(len_node.val_start[0..len_node.val_len]);
            }
        }
        cb.movRImm64(cg.X8, 64);
        cb.movRImm64(cg.X0, 1);
        if (len >= 0) cb.movRImm64(cg.X2, @as(u64, @bitCast(@as(u64, @intCast(len)))));
        cb.svc(0);
        return;
    }
    if (eq(name, "open")) {
        var ai2: usize = 0;
        var args: [3]i64 = .{0} ** 3;
        var ch2 = n.first_child;
        while (ch2 != parser_mod.NO_NODE and ai2 < 3) {
            const cn = &pool[@as(usize, @intCast(ch2))];
            if (cn.kind == .int_lit) args[ai2] = strToInt(cn.val_start[0..cn.val_len]);
            ai2 += 1;
            ch2 = cn.next_sibling;
        }
        // openat: syscall(56, AT_FDCWD=-100, path, flags, mode)
        cb.movRImm64(cg.X8, 56);
        cb.movRImm64(cg.X0, @as(u64, @bitCast(@as(i64, -100))));
        cb.movRImm64(cg.X1, @as(u64, @bitCast(args[0])));
        cb.movRImm64(cg.X2, @as(u64, @bitCast(args[1])));
        cb.movRImm64(cg.X3, @as(u64, @bitCast(args[2])));
        cb.svc(0);
        return;
    }
    if (eq(name, "read")) {
        var ai2: usize = 0;
        var args: [3]i64 = .{0} ** 3;
        var ch2 = n.first_child;
        while (ch2 != parser_mod.NO_NODE and ai2 < 3) {
            const cn = &pool[@as(usize, @intCast(ch2))];
            if (cn.kind == .int_lit) args[ai2] = strToInt(cn.val_start[0..cn.val_len]);
            ai2 += 1;
            ch2 = cn.next_sibling;
        }
        cb.movRImm64(cg.X8, 63);
        cb.movRImm64(cg.X0, @as(u64, @bitCast(args[0])));
        cb.movRImm64(cg.X1, @as(u64, @bitCast(args[1])));
        cb.movRImm64(cg.X2, @as(u64, @bitCast(args[2])));
        cb.svc(0);
        return;
    }
    if (eq(name, "write")) {
        var ai2: usize = 0;
        var args: [3]i64 = .{0} ** 3;
        var ch2 = n.first_child;
        while (ch2 != parser_mod.NO_NODE and ai2 < 3) {
            const cn = &pool[@as(usize, @intCast(ch2))];
            if (cn.kind == .int_lit) args[ai2] = strToInt(cn.val_start[0..cn.val_len]);
            ai2 += 1;
            ch2 = cn.next_sibling;
        }
        cb.movRImm64(cg.X8, 64);
        cb.movRImm64(cg.X0, @as(u64, @bitCast(args[0])));
        cb.movRImm64(cg.X1, @as(u64, @bitCast(args[1])));
        cb.movRImm64(cg.X2, @as(u64, @bitCast(args[2])));
        cb.svc(0);
        return;
    }
    if (eq(name, "close")) {
        var ai2: usize = 0;
        var fd_val: i64 = 0;
        var ch2 = n.first_child;
        while (ch2 != parser_mod.NO_NODE and ai2 < 1) {
            const cn = &pool[@as(usize, @intCast(ch2))];
            if (cn.kind == .int_lit) fd_val = strToInt(cn.val_start[0..cn.val_len]);
            ai2 += 1;
            ch2 = cn.next_sibling;
        }
        cb.movRImm64(cg.X8, 57);
        cb.movRImm64(cg.X0, @as(u64, @bitCast(fd_val)));
        cb.svc(0);
        return;
    }
    if (eq(name, "socket") or eq(name, "connect") or eq(name, "bind") or eq(name, "listen") or eq(name, "accept") or eq(name, "send") or eq(name, "recv")) {
        const arm_nr: i64 = if (eq(name, "socket")) 198 else if (eq(name, "connect")) 203 else if (eq(name, "bind")) 200 else if (eq(name, "listen")) 201 else if (eq(name, "accept")) 242 else if (eq(name, "send")) 211 else 212;
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
        if (arg_i == 3 and !is_expr[1] and (arm_nr == 203 or arm_nr == 200)) {
            var ip_v: i64 = 0; var port_v: i64 = 0;
            if (!is_expr[1]) { const cn = &pool[@as(usize, @intCast(args_list[1]))]; ip_v = strToInt(cn.val_start[0..cn.val_len]); }
            if (!is_expr[2]) { const cn = &pool[@as(usize, @intCast(args_list[2]))]; port_v = strToInt(cn.val_start[0..cn.val_len]); }
            const pnet = @as(u16, @intCast(port_v));
            const pnet_be = (@as(u16, @intCast(pnet)) << 8) | (@as(u16, @intCast(pnet)) >> 8);
            if (is_expr[0]) { compileExprNode(args_list[0], pool, cb, vars, vc, frame); }
            cb.subi(31, 31, 16);
            cb.movRImm64(cg.X9, 2);
            cb.str16(cg.X9, 31, 0);
            cb.movRImm64(cg.X9, @as(u64, @intCast(pnet_be)));
            cb.str16(cg.X9, 31, 2);
            cb.movRImm64(cg.X9, @as(u64, @intCast(@as(u32, @intCast(ip_v)))));
            cb.str32(cg.X9, 31, 4);
            cb.str32(cg.ZR, 31, 8);
            cb.str32(cg.ZR, 31, 12);
            cb.movRImm64(cg.X8, @as(u64, @bitCast(arm_nr)));
            if (!is_expr[0]) { var fd: i64 = 0; const cn = &pool[@as(usize, @intCast(args_list[0]))]; if (cn.kind == .int_lit) fd = strToInt(cn.val_start[0..cn.val_len]); cb.movRImm64(cg.X0, @as(u64, @bitCast(fd))); }
            cb.addi(cg.X1, 31, 0);
            cb.movRImm64(cg.X2, 16);
            cb.svc(0);
            cb.addi(31, 31, 16);
            return;
        }
        if (arm_nr == 212 and arg_i >= 2 and !is_expr[1]) {
            const cn = &pool[@as(usize, @intCast(args_list[1]))];
            if (cn.kind == .int_lit and strToInt(cn.val_start[0..cn.val_len]) == 0) {
                if (is_expr[0]) { compileExprNode(args_list[0], pool, cb, vars, vc, frame); }
                cb.subi(31, 31, 2048);
                cb.subi(31, 31, 2048);
                cb.movRImm64(cg.X8, 212);
                if (!is_expr[0]) { var fd: i64 = 0; const cn2 = &pool[@as(usize, @intCast(args_list[0]))]; if (cn2.kind == .int_lit) fd = strToInt(cn2.val_start[0..cn2.val_len]); cb.movRImm64(cg.X0, @as(u64, @bitCast(fd))); }
                cb.addi(cg.X1, 31, 0);
                cb.movRImm64(cg.X2, 4096);
                cb.movRImm64(cg.X3, 0);
                cb.movRImm64(cg.X4, 0);
                cb.movRImm64(cg.X5, 0);
                cb.svc(0);
                cb.addi(31, 31, 2048);
                cb.addi(31, 31, 2048);
                return;
            }
        }
        var ei: usize = 0;
        while (ei < arg_i) : (ei += 1) { if (is_expr[ei]) { compileExprNode(args_list[ei], pool, cb, vars, vc, frame); pushX0(cb); } }
        cb.movRImm64(cg.X8, @as(u64, @bitCast(arm_nr)));
        var ri: usize = arg_i;
        while (ri > 0) { ri -= 1;
            if (is_expr[ri]) { popX0(cb); cb.mov(@as(u8, @intCast(ri)), cg.X0); }
            else if (args_list[ri] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[ri]))];
                cb.movRImm64(@as(u8, @intCast(ri)), @as(u64, @bitCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.svc(0);
        return;
    }
    if (eq(name, "android_http_get") or eq(name, "android_http_post")) {
        const is_post = eq(name, "android_http_post");
        const scratch_off: u32 = 0;
        const request_off: u32 = 64;
        const response_off: u32 = request_off + 4096;
        const total_stack: u32 = response_off + 8192;
        _ = scratch_off;

        var args_list: [4]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 4;
        var arg_i: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_i < 4) {
            args_list[arg_i] = ch;
            arg_i += 1;
            ch = pool[@as(usize, @intCast(ch))].next_sibling;
        }

        compileArmArgToReg(args_list[0], cg.X21, 0, pool, cb, vars, vc, frame); // ip, little-endian u32: 0x0100007F -> 127.0.0.1
        compileArmArgToReg(args_list[1], cg.X22, 80, pool, cb, vars, vc, frame); // port
        compileArmArgToReg(args_list[2], cg.X23, 0, pool, cb, vars, vc, frame); // path pointer
        if (is_post) compileArmArgToReg(args_list[3], cg.X24, 0, pool, cb, vars, vc, frame) else cb.mov(cg.X24, cg.ZR);
        if (is_post) emitCStringLen(cb, cg.X24, cg.X25) else cb.mov(cg.X25, cg.ZR);

        emitStackSub(cb, total_stack);

        cb.movRImm64(cg.X0, 2);
        cb.str16(cg.X0, 31, 0);
        cb.mov(cg.X26, cg.X22);
        cb.movRImm64(cg.X27, 255);
        cb.and_(cg.X0, cg.X26, cg.X27);
        cb.movRImm64(cg.X28, 256);
        cb.mul(cg.X0, cg.X0, cg.X28);
        cb.lsrImm(cg.X1, cg.X26, 8);
        cb.and_(cg.X1, cg.X1, cg.X27);
        cb.orr(cg.X0, cg.X0, cg.X1);
        cb.str16(cg.X0, 31, 2);
        cb.str32(cg.X21, 31, 4);
        cb.str64(cg.ZR, 31, 8);

        cb.movRImm64(cg.X8, 198);
        cb.movRImm64(cg.X0, 2);
        cb.movRImm64(cg.X1, 1);
        cb.mov(cg.X2, cg.ZR);
        cb.svc(0);
        cb.mov(cg.X19, cg.X0);

        var error_branches: [8]usize = .{0} ** 8;
        var error_count: usize = 0;

        cb.cmp(cg.X19, cg.ZR);
        error_branches[error_count] = cb.len;
        error_count += 1;
        cb.blt();

        cb.movRImm64(cg.X8, 203);
        cb.mov(cg.X0, cg.X19);
        cb.addi(cg.X1, 31, 0);
        cb.movRImm64(cg.X2, 16);
        cb.svc(0);
        cb.cmp(cg.X0, cg.ZR);
        error_branches[error_count] = cb.len;
        error_count += 1;
        cb.blt();

        emitAddrFromSp(cb, cg.X20, request_off);
        if (is_post) emitWriteLit(cb, cg.X20, "POST ") else emitWriteLit(cb, cg.X20, "GET ");
        cb.cmp(cg.X23, cg.ZR);
        const path_copy_branch = cb.len;
        cb.bne();
        emitWriteLit(cb, cg.X20, "/");
        const path_done_jump = cb.len;
        cb.branch();
        const path_copy_pos = cb.len;
        cb.patchBCond(path_copy_branch, path_copy_pos);
        emitCopyCString(cb, cg.X20, cg.X23);
        cb.patchB(path_done_jump, cb.len);
        emitWriteLit(cb, cg.X20, " HTTP/1.0\r\nHost: ");
        emitWriteIpHost(cb, cg.X21, cg.X20);
        emitWriteLit(cb, cg.X20, "\r\nConnection: close\r\n");
        if (is_post) {
            emitWriteLit(cb, cg.X20, "Content-Length: ");
            emitWriteUnsignedDecimal(cb, cg.X25, cg.X20);
            emitWriteLit(cb, cg.X20, "\r\nContent-Type: application/x-www-form-urlencoded\r\n");
        }
        emitWriteLit(cb, cg.X20, "\r\n");
        if (is_post) {
            cb.cmp(cg.X24, cg.ZR);
            const body_done_branch = cb.len;
            cb.beq();
            emitCopyCString(cb, cg.X20, cg.X24);
            cb.patchBCond(body_done_branch, cb.len);
        }

        emitAddrFromSp(cb, cg.X26, request_off);
        cb.mov(cg.X27, cg.X26);
        cb.sub(cg.X28, cg.X20, cg.X26);

        const write_loop = cb.len;
        cb.cmp(cg.X28, cg.ZR);
        const write_done_branch = cb.len;
        cb.beq();
        cb.movRImm64(cg.X8, 64);
        cb.mov(cg.X0, cg.X19);
        cb.mov(cg.X1, cg.X27);
        cb.mov(cg.X2, cg.X28);
        cb.svc(0);
        cb.cmp(cg.X0, cg.ZR);
        error_branches[error_count] = cb.len;
        error_count += 1;
        cb.ble();
        cb.add(cg.X27, cg.X27, cg.X0);
        cb.sub(cg.X28, cg.X28, cg.X0);
        const write_jump = cb.len;
        cb.branch();
        cb.patchB(write_jump, write_loop);
        cb.patchBCond(write_done_branch, cb.len);

        emitAddrFromSp(cb, cg.X21, response_off);
        cb.movRImm64(cg.X22, 8191);
        const read_loop = cb.len;
        cb.cmp(cg.X22, cg.ZR);
        const read_done_empty = cb.len;
        cb.beq();
        cb.movRImm64(cg.X8, 63);
        cb.mov(cg.X0, cg.X19);
        cb.mov(cg.X1, cg.X21);
        cb.mov(cg.X2, cg.X22);
        cb.svc(0);
        cb.cmp(cg.X0, cg.ZR);
        const read_ok_branch = cb.len;
        cb.bgt();
        const read_done_jump = cb.len;
        cb.branch();
        const read_ok_pos = cb.len;
        cb.patchBCond(read_ok_branch, read_ok_pos);
        cb.add(cg.X21, cg.X21, cg.X0);
        cb.sub(cg.X22, cg.X22, cg.X0);
        const read_jump = cb.len;
        cb.branch();
        cb.patchB(read_jump, read_loop);
        const read_done_pos = cb.len;
        cb.patchBCond(read_done_empty, read_done_pos);
        cb.patchB(read_done_jump, read_done_pos);
        cb.str8(cg.ZR, cg.X21, 0);

        cb.movRImm64(cg.X8, 57);
        cb.mov(cg.X0, cg.X19);
        cb.svc(0);
        emitAddrFromSp(cb, cg.X0, response_off);
        emitStackAdd(cb, total_stack);
        const success_done_jump = cb.len;
        cb.branch();

        const error_pos = cb.len;
        var epi: usize = 0;
        while (epi < error_count) : (epi += 1) cb.patchBCond(error_branches[epi], error_pos);
        cb.movRImm64(cg.X8, 57);
        cb.mov(cg.X0, cg.X19);
        cb.svc(0);
        cb.mov(cg.X0, cg.ZR);
        emitStackAdd(cb, total_stack);

        cb.patchB(success_done_jump, cb.len);
        return;
     }
     if (eq(name, "setTheme")) {
         // setTheme(fd, theme_id) -> sends CMD_SET_THEME to gui_srv
         // fd: file descriptor to write to (gui_srv write end from guiServer)
         // theme_id: 0=dark, 1=light, 2=modern_dark, 3=modern_light
         var args_list: [2]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 2;
         var arg_i: usize = 0;
         var ch = n.first_child;
         while (ch != parser_mod.NO_NODE and arg_i < 2) {
             args_list[arg_i] = ch;
             ch = pool[@as(usize, @intCast(ch))].next_sibling;
             arg_i += 1;
         }

         compileArmArgToReg(args_list[0], cg.X19, 0, pool, cb, vars, vc, frame);
         compileArmArgToReg(args_list[1], cg.X20, 0, pool, cb, vars, vc, frame);

         cb.subi(31, 31, 64);
         cb.movRImm64(cg.X0, 13);
         cb.str8(cg.X0, 31, 0);
         cb.movRImm64(cg.X21, 255);
         cb.and_(cg.X0, cg.X20, cg.X21);
         cb.str8(cg.X0, 31, 1);
         cb.lsrImm(cg.X0, cg.X20, 8);
         cb.and_(cg.X0, cg.X0, cg.X21);
         cb.str8(cg.X0, 31, 2);
         cb.lsrImm(cg.X0, cg.X20, 16);
         cb.and_(cg.X0, cg.X0, cg.X21);
         cb.str8(cg.X0, 31, 3);
         cb.lsrImm(cg.X0, cg.X20, 24);
         cb.and_(cg.X0, cg.X0, cg.X21);
         cb.str8(cg.X0, 31, 4);
         {
             var off: i32 = 5;
             while (off < 61) : (off += 1) cb.str8(cg.ZR, 31, off);
         }

         cb.movRImm64(cg.X8, 64);
         cb.mov(cg.X0, cg.X19);
         cb.addi(cg.X1, 31, 0);
         cb.movRImm64(cg.X2, 61);
         cb.svc(0);
         cb.addi(31, 31, 32);
         cb.addi(31, 31, 32);

         return;
     }
     cb.mov(cg.X0, cg.ZR);
}

fn compileFieldAccess(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, frame: i32) void {
    compileExprAddr(n.first_child, pool, cb, vars, vc, frame);
    const field = n.name_start[0..n.name_len];
    const field_off = findFieldOffset(pool, field);
    if (field_off > 0) cb.addi(cg.X0, cg.X0, @as(u16, @intCast(field_off)));
    cb.ldr64(cg.X0, cg.X0, 0);
}

fn compileArrayIndex(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, frame: i32) void {
    const arr = n.first_child;
    const idx = if (arr != parser_mod.NO_NODE) pool[@as(usize, @intCast(arr))].next_sibling else parser_mod.NO_NODE;
    if (arr == parser_mod.NO_NODE or idx == parser_mod.NO_NODE) { cb.mov(cg.X0, cg.ZR); return; }

    compileExprAddr(arr, pool, cb, vars, vc, frame);
    pushX0(cb);
    compileExprNode(idx, pool, cb, vars, vc, frame);
    cb.mov(cg.X10, cg.X0);
    popX0(cb);
    cb.subShift(cg.X0, cg.X0, cg.X10, 3);
    cb.ldr64(cg.X0, cg.X0, 0);
}

fn compileAddrOf(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, frame: i32) void {
    compileExprAddr(n.first_child, pool, cb, vars, vc, frame);
}

fn compileDeref(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, frame: i32) void {
    compileExprNode(n.first_child, pool, cb, vars, vc, frame);
    cb.ldr64(cg.X0, cg.X0, 0);
}

fn compileSizeof(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, _vars: *[MAX_VARS]Var, _vc: *usize) void {
    _ = _vars; _ = _vc;
    // If sizeof is applied to an ident, check if it's a struct type name
    if (n.first_child != parser_mod.NO_NODE) {
        const child = &pool[@as(usize, @intCast(n.first_child))];
        if (child.kind == .ident) {
            const type_name = child.name_start[0..child.name_len];
            const fields = structFieldCount(pool, type_name);
            if (fields > 0) {
                cb.movRImm64(cg.X0, @as(u64, @bitCast(@as(i64, fields * 8))));
                return;
            }
        }
    }
    cb.movRImm64(cg.X0, 8);
}

fn compileIf(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32, frame: i32, loop_stack: *[16]usize, loop_depth: *usize) void {
    const cond = n.first_child;
    const then_blk = if (cond != parser_mod.NO_NODE) pool[@as(usize, @intCast(cond))].next_sibling else parser_mod.NO_NODE;
    const else_blk = if (then_blk != parser_mod.NO_NODE) pool[@as(usize, @intCast(then_blk))].next_sibling else parser_mod.NO_NODE;

    if (cond != parser_mod.NO_NODE) compileExprNode(cond, pool, cb, vars, vc, frame) else cb.mov(cg.X0, cg.ZR);
    const cbz_pos = cb.len;
    cb.cbz(cg.X0);

    if (then_blk != parser_mod.NO_NODE) compileStmt(then_blk, pool, cb, vars, vc, stack_off, frame, loop_stack, loop_depth);

    var has_else = false;
    const jmp_pos = cb.len;
    if (else_blk != parser_mod.NO_NODE) { has_else = true; cb.branch(); }

    const else_pos = cb.len;
    cb.patchCBZ(cbz_pos, else_pos);

    if (else_blk != parser_mod.NO_NODE) compileStmt(else_blk, pool, cb, vars, vc, stack_off, frame, loop_stack, loop_depth);

    const end_pos = cb.len;
    if (has_else) cb.patchB(jmp_pos, end_pos);
}

fn compileWhile(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32, frame: i32, loop_stack: *[16]usize, loop_depth: *usize) void {
    const cond = n.first_child;
    const body = if (cond != parser_mod.NO_NODE) pool[@as(usize, @intCast(cond))].next_sibling else parser_mod.NO_NODE;

    const loop_start = cb.len;

    if (cond != parser_mod.NO_NODE) compileExprNode(cond, pool, cb, vars, vc, frame) else cb.mov(cg.X0, cg.ZR);
    const cbz_pos = cb.len;
    cb.cbz(cg.X0);

    // Push loop context: [loop_start, 0] (end_pos will be filled)
    const depth = loop_depth.*;
    if (depth + 2 < 16) {
        loop_stack[depth] = loop_start;
        loop_stack[depth + 1] = 0; // placeholder for end_pos
    }
    loop_depth.* += 2;

    if (body != parser_mod.NO_NODE) compileStmt(body, pool, cb, vars, vc, stack_off, frame, loop_stack, loop_depth);

    const jmp_pos = cb.len;
    cb.branch();
    cb.patchB(jmp_pos, loop_start);

    const end_pos = cb.len;
    cb.patchCBZ(cbz_pos, end_pos);

    // Pop loop context, store end_pos
    loop_depth.* -= 2;
    if (depth + 1 < 16) loop_stack[depth + 1] = end_pos;
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
                    if (eq(cn.name_start[0..cn.name_len], field)) return fi * 8;
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
