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
    // Function label (just generate code directly)
    cb.pushR(cg.RBP);
    cb.movRR(cg.RBP, cg.RSP);

    var child = n.first_child;
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
            if (n.val_len > 0) {
                compileExpr(n.val_start[0..n.val_len], pool, cb, vars, vc);
            } else {
                cb.xorRR(cg.RAX, cg.RAX);
            }
            cb.movRR(cg.RSP, cg.RBP);
            cb.popR(cg.RBP);
            cb.ret();
        },
        .let_decl => {
            const name = n.name_start[0..n.name_len];
            stack_off.* -= 8;
            const off = stack_off.*;
            if (vc.* < MAX_VARS) {
                vars[vc.*] = Var{ .name = name, .off = off };
                vc.* += 1;
            }
            if (n.val_len > 0) {
                compileExpr(n.val_start[0..n.val_len], pool, cb, vars, vc);
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
                compileStmt(n.first_child, pool, cb, vars, vc, stack_off);
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

fn compileExpr(s: []const u8, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize) void {
    _ = pool;
    if (s.len > 0 and s[0] >= '0' and s[0] <= '9') {
        cb.movRImm64(cg.RAX, @as(u64, @intCast(strToInt(s))));
    } else if (s.len > 0 and s[0] == '"') {
        cb.xorRR(cg.RAX, cg.RAX);
    } else if (findVar(vars, vc.*, s)) |off| {
        cb.movRMem64(cg.RAX, cg.RBP, off);
    } else {
        cb.xorRR(cg.RAX, cg.RAX);
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
    // Evaluate condition (first child)
    if (n.first_child != parser_mod.NO_NODE) {
        compileStmt(n.first_child, pool, cb, vars, vc, stack_off);
    }
    cb.cmpRImm32(cg.RAX, 0);

    const je_pos = cb.pos;
    cb.jeRel32(0);

    const after_cond = cb.pos;

    // then branch
    if (n.first_child != parser_mod.NO_NODE) {
        const sib = pool[@as(usize, @intCast(n.first_child))].next_sibling;
        if (sib != parser_mod.NO_NODE) {
            compileStmt(sib, pool, cb, vars, vc, stack_off);
        }
    }

    const jmp_pos = cb.pos;
    cb.jmpRel32(0);

    const else_pos = cb.pos;
    patch32(cb, je_pos, @as(i32, @intCast(else_pos)) - @as(i32, @intCast(after_cond)));

    // else branch
    if (n.first_child != parser_mod.NO_NODE) {
        const sib0 = pool[@as(usize, @intCast(n.first_child))].next_sibling;
        if (sib0 != parser_mod.NO_NODE) {
            const sib = pool[@as(usize, @intCast(sib0))].next_sibling;
            if (sib != parser_mod.NO_NODE) {
                compileStmt(sib, pool, cb, vars, vc, stack_off);
            }
        }
    }

    const end_pos = cb.pos;
    patch32(cb, jmp_pos, @as(i32, @intCast(end_pos)) - @as(i32, @intCast(else_pos)));
}

fn compileWhile(n: *const parser_mod.AstNode, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, stack_off: *i32) void {
    const loop_pos = cb.pos;

    if (n.first_child != parser_mod.NO_NODE) {
        compileStmt(n.first_child, pool, cb, vars, vc, stack_off);
    }
    cb.cmpRImm32(cg.RAX, 0);

    const je_pos = cb.pos;
    cb.jeRel32(0);
    const after_cond = cb.pos;

    if (n.first_child != parser_mod.NO_NODE) {
        const sib = pool[@as(usize, @intCast(n.first_child))].next_sibling;
        if (sib != parser_mod.NO_NODE) {
            compileStmt(sib, pool, cb, vars, vc, stack_off);
        }
    }

    const back_off = @as(i32, @intCast(loop_pos)) - @as(i32, @intCast(cb.pos + 5));
    cb.jmpRel32(back_off);

    const end_pos = cb.pos;
    patch32(cb, je_pos, @as(i32, @intCast(end_pos)) - @as(i32, @intCast(after_cond)));
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
