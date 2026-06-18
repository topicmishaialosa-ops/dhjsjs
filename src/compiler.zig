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

const Var = struct { name: []const u8, off: i32 };
const MAX_VARS = 64;

pub fn compile(prog_root: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode) cg.CodeBuffer {
    _ = prog_root;
    var cb = cg.CodeBuffer.init();
    var vars: [MAX_VARS]Var = undefined;
    var vc: usize = 0;
    var stack_off: i32 = 0;

    // Find main function index
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
        cb.movRImm64(cg.RDI, 0);
        cb.movRImm64(cg.RAX, 60);
        cb.syscall();
        return cb;
    }

    // Emit _start entry point
    const call_pos: usize = cb.pos;
    cb.callRel32(0);
    // exit with rax from main
    cb.movRR(cg.RDI, cg.RAX);
    cb.movRImm64(cg.RAX, 60);
    cb.syscall();

    // Emit all function bodies, track where main starts
    var main_body_pos: usize = 0;
    pi = 0;
    while (pi < parser_mod.MAX_NODES) : (pi += 1) {
        const n = &pool[pi];
        if (n.kind == .program) {
            var ch = n.first_child;
            while (ch != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(ch))];
                if (cn.kind == .fn_decl) {
                    if (ch == main_idx) main_body_pos = cb.pos;
                    compileFn(cn, pool, &cb, &vars, &vc, &stack_off);
                }
                ch = cn.next_sibling;
            }
        }
    }

    // Patch call to main
    const main_off: i32 = @as(i32, @intCast(main_body_pos)) - @as(i32, @intCast(call_pos + 5));
    patch32(&cb, call_pos + 1, main_off);

    return cb;
}

fn compileFn(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32) void {
    // Count var_decls (scan into block)
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

    // Prologue: push rbp, mov rbp rsp, sub rsp var_count*8
    cb.pushR(cg.RBP);
    cb.movRR(cg.RBP, cg.RSP);
    if (var_count > 0) cb.subRImm32(cg.RSP, @as(i32, @intCast(var_count)) * 8);

    child = n.first_child;
    while (child != parser_mod.NO_NODE) {
        compileStmt(child, pool, cb, vars, vc, stack_off);
        child = pool[@as(usize, @intCast(child))].next_sibling;
    }

    // Default return 0
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
            } else {
                cb.xorRR(cg.RAX, cg.RAX);
            }
            cb.movRR(cg.RSP, cg.RBP);
            cb.popR(cg.RBP);
            cb.ret();
        },
        .var_decl => {
            const name = n.name_start[0..n.name_len];
            stack_off.* -= 8;
            const off = stack_off.*;
            if (vc.* < MAX_VARS) {
                vars[vc.*] = Var{ .name = name, .off = off };
                vc.* += 1;
            }
            if (n.first_child != parser_mod.NO_NODE) {
                compileExprNode(n.first_child, pool, cb, vars, vc);
            } else {
                cb.xorRR(cg.RAX, cg.RAX);
            }
            cb.movMemR64(cg.RBP, off, cg.RAX);
        },
        .call => {
            compileCall(n, pool, cb, vars, vc);
        },
        .assign => {
            const name = n.name_start[0..n.name_len];
            const off = findVar(vars, vc.*, name);
            if (n.first_child != parser_mod.NO_NODE) {
                compileExprNode(n.first_child, pool, cb, vars, vc);
            } else {
                cb.xorRR(cg.RAX, cg.RAX);
            }
            if (off) |o| cb.movMemR64(cg.RBP, o, cg.RAX);
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
    if (idx == parser_mod.NO_NODE) { cb.xorRR(cg.RAX, cg.RAX); return; }
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .int_lit => {
            cb.movRImm64(cg.RAX, @as(u64, @intCast(strToInt(n.val_start[0..n.val_len]))));
        },
        .str_lit => {
            cb.xorRR(cg.RAX, cg.RAX);
        },
        .ident => {
            if (findVar(vars, vc.*, n.name_start[0..n.name_len])) |off| {
                cb.movRMem64(cg.RAX, cg.RBP, off);
            } else {
                cb.xorRR(cg.RAX, cg.RAX);
            }
        },
        .binary_op => compileBinaryOp(n, pool, cb, vars, vc),
        .unary_op => compileUnaryOp(n, pool, cb, vars, vc),
        else => {
            cb.xorRR(cg.RAX, cg.RAX);
        },
    }
}

fn compileBinaryOp(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    const op = n.name_start[0..n.name_len];
    const left = n.first_child;
    const right = if (left != parser_mod.NO_NODE)
        pool[@as(usize, @intCast(left))].next_sibling
    else
        parser_mod.NO_NODE;
    if (left == parser_mod.NO_NODE or right == parser_mod.NO_NODE) { cb.xorRR(cg.RAX, cg.RAX); return; }

    compileExprNode(left, pool, cb, vars, vc); // rax = left
    cb.pushR(cg.RAX); // save left
    compileExprNode(right, pool, cb, vars, vc); // rax = right
    cb.movRR(cg.RCX, cg.RAX); // rcx = right
    cb.popR(cg.RAX); // rax = left

    if (eq(op, "+")) {
        cb.addRR(cg.RAX, cg.RCX);
    } else if (eq(op, "-")) {
        cb.subRR(cg.RAX, cg.RCX);
    } else if (eq(op, "*")) {
        cb.imulRR(cg.RAX, cg.RCX);
    } else if (eq(op, "/")) {
        cb.cqo();
        cb.idivR(cg.RCX);
    } else if (eq(op, "==")) {
        cb.cmpRR(cg.RAX, cg.RCX);
        cb.pushfq();
        cb.xorRR(cg.RAX, cg.RAX);
        cb.popfq();
        cb.sete(cg.RAX);
    } else if (eq(op, "!=")) {
        cb.cmpRR(cg.RAX, cg.RCX);
        cb.pushfq();
        cb.xorRR(cg.RAX, cg.RAX);
        cb.popfq();
        cb.setne(cg.RAX);
    } else if (eq(op, "<")) {
        cb.cmpRR(cg.RAX, cg.RCX);
        cb.pushfq();
        cb.xorRR(cg.RAX, cg.RAX);
        cb.popfq();
        cb.setl(cg.RAX);
    } else if (eq(op, ">")) {
        cb.cmpRR(cg.RAX, cg.RCX);
        cb.pushfq();
        cb.xorRR(cg.RAX, cg.RAX);
        cb.popfq();
        cb.setg(cg.RAX);
    } else if (eq(op, "<=")) {
        cb.cmpRR(cg.RAX, cg.RCX);
        cb.pushfq();
        cb.xorRR(cg.RAX, cg.RAX);
        cb.popfq();
        cb.setle(cg.RAX);
    } else if (eq(op, ">=")) {
        cb.cmpRR(cg.RAX, cg.RCX);
        cb.pushfq();
        cb.xorRR(cg.RAX, cg.RAX);
        cb.popfq();
        cb.setge(cg.RAX);
    } else if (eq(op, "&&")) {
        cb.andRR(cg.RAX, cg.RCX);
    } else if (eq(op, "||")) {
        cb.orRR(cg.RAX, cg.RCX);
    } else {
        cb.xorRR(cg.RAX, cg.RAX);
    }
}

fn compileUnaryOp(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    const op = n.name_start[0..n.name_len];
    const operand = n.first_child;
    compileExprNode(operand, pool, cb, vars, vc);
    if (eq(op, "-")) {
        cb.negR(cg.RAX);
    } else if (eq(op, "!")) {
        cb.cmpRImm32(cg.RAX, 0);
        cb.pushfq();
        cb.xorRR(cg.RAX, cg.RAX);
        cb.popfq();
        cb.sete(cg.RAX);
    }
}

fn compileCall(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    const name = n.name_start[0..n.name_len];

    if (eq(name, "syscall")) {
        var args: [6]i64 = .{0} ** 6;
        var ai: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and ai < 6) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (cn.kind == .int_lit) {
                args[ai] = strToInt(cn.val_start[0..cn.val_len]);
            } else if (cn.kind == .ident) {
                const on = findVar(vars, vc.*, cn.name_start[0..cn.name_len]);
                // can't resolve at compile time, skip for now
                _ = on;
            }
            ai += 1;
            ch = cn.next_sibling;
        }

        // Move args to registers: rdi, rsi, rdx, r10, r8, r9
        const regs = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri: usize = 0;
        while (ri < ai and ri < 6) : (ri += 1) {
            cb.movRImm64(regs[ri], @as(u64, @intCast(args[ri])));
        }
        // rax = syscall number (first arg if available)
        if (ai > 0) {
            cb.movRImm64(cg.RAX, @as(u64, @intCast(args[0])));
            // shift: syscall(nr, a1, a2, ...) -> rax=nr, rdi=a1, rsi=a2, ...
            if (ai > 1) cb.movRImm64(cg.RDI, @as(u64, @intCast(args[1])));
            if (ai > 2) cb.movRImm64(cg.RSI, @as(u64, @intCast(args[2])));
            if (ai > 3) cb.movRImm64(cg.RDX, @as(u64, @intCast(args[3])));
            if (ai > 4) cb.movRImm64(cg.R10, @as(u64, @intCast(args[4])));
            if (ai > 5) cb.movRImm64(cg.R8, @as(u64, @intCast(args[5])));
        }
        cb.syscall();
        cb.movRR(cg.RDI, cg.RAX); // save return value to temp
        return;
    }

    // Regular function call - just emit placeholder
    cb.movRImm64(cg.RAX, 0);
}

fn compileIf(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32) void {
    const cond = n.first_child;
    const then_blk = if (cond != parser_mod.NO_NODE)
        pool[@as(usize, @intCast(cond))].next_sibling
    else
        parser_mod.NO_NODE;
    const else_blk = if (then_blk != parser_mod.NO_NODE)
        pool[@as(usize, @intCast(then_blk))].next_sibling
    else
        parser_mod.NO_NODE;

    if (cond != parser_mod.NO_NODE) {
        compileExprNode(cond, pool, cb, vars, vc);
    } else {
        cb.xorRR(cg.RAX, cg.RAX);
    }
    cb.cmpRImm32(cg.RAX, 0);

    const je_pos = cb.pos;
    cb.jeRel32(0);
    const after_cond = cb.pos;

    if (then_blk != parser_mod.NO_NODE) {
        compileStmt(then_blk, pool, cb, vars, vc, stack_off);
    }

    var has_else = false;
    const jmp_pos = cb.pos;
    if (else_blk != parser_mod.NO_NODE) {
        has_else = true;
        cb.jmpRel32(0);
    }

    const else_pos = cb.pos;
    patch32(cb, je_pos + 2, @as(i32, @intCast(else_pos)) - @as(i32, @intCast(after_cond)));

    if (else_blk != parser_mod.NO_NODE) {
        compileStmt(else_blk, pool, cb, vars, vc, stack_off);
    }

    const end_pos = cb.pos;
    if (has_else) {
        patch32(cb, jmp_pos + 1, @as(i32, @intCast(end_pos)) - @as(i32, @intCast(else_pos)));
    }
}

fn compileWhile(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32) void {
    const cond = n.first_child;
    const body = if (cond != parser_mod.NO_NODE)
        pool[@as(usize, @intCast(cond))].next_sibling
    else
        parser_mod.NO_NODE;

    const loop_pos = cb.pos;

    if (cond != parser_mod.NO_NODE) {
        compileExprNode(cond, pool, cb, vars, vc);
    } else {
        cb.xorRR(cg.RAX, cg.RAX);
    }
    cb.cmpRImm32(cg.RAX, 0);

    const je_pos = cb.pos;
    cb.jeRel32(0);
    const after_cond = cb.pos;

    if (body != parser_mod.NO_NODE) {
        compileStmt(body, pool, cb, vars, vc, stack_off);
    }

    const back_off = @as(i32, @intCast(loop_pos)) - @as(i32, @intCast(cb.pos + 5));
    cb.jmpRel32(back_off);

    const end_pos = cb.pos;
    patch32(cb, je_pos + 2, @as(i32, @intCast(end_pos)) - @as(i32, @intCast(after_cond)));
}

fn findVar(vars: *[MAX_VARS]Var, count: usize, name: []const u8) ?i32 {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (eq(vars[i].name, name)) return vars[i].off;
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
