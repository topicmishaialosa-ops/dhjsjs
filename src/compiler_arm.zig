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
