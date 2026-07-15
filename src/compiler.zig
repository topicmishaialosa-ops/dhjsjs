const parser_mod = @import("parser.zig");
const cg = @import("codegen.zig");
const errors_mod = @import("errors.zig");
const tls_mod = @import("tls.zig");
const player_mod = @import("player.zig");
const render_mod = @import("render.zig");
const x11_mod = @import("x11.zig");
const gl3_api = @import("gl3_api.zig");

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
            if (c >= '0' and c <= '9') {
                v |= @as(i64, c - '0');
            }
            if (c >= 'a' and c <= 'f') {
                v |= @as(i64, c - 'a' + 10);
            }
            if (c >= 'A' and c <= 'F') {
                v |= @as(i64, c - 'A' + 10);
            }
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

const MAX_FNS = 32;
const MAX_RELOCS = 512;
var fn_names: [MAX_FNS][]const u8 = undefined;
var fn_positions: [MAX_FNS]usize = undefined;
var fn_count: usize = 0;
var reloc_callpos: [MAX_RELOCS]usize = undefined;
var reloc_target_idx: [MAX_RELOCS]usize = undefined;
var reloc_count: usize = 0;

const MAX_GVARS = 128;
const MAX_GV_RELOCS = 512;
var gvars: [MAX_GVARS]Var = undefined;
var gvc: usize = 0;
var gv_offsets: [MAX_GVARS]u64 = undefined;
var gv_sizes: [MAX_GVARS]u64 = undefined;
var gv_init_nodes: [MAX_GVARS]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** MAX_GVARS;

// Loop tracking for break/continue
var loop_start_stack: [16]usize = undefined;
var loop_break_jmps: [16][64]usize = undefined;
var loop_break_count: [16]usize = undefined;
var loop_depth: usize = 0;
var gv_data_size: u64 = 0;
var gv_reloc_pos: [MAX_GV_RELOCS]usize = undefined;
var gv_reloc_data_off: [MAX_GV_RELOCS]u64 = undefined;
var gv_reloc_count: usize = 0;

pub fn compile(prog_root: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, errs: *errors_mod.ErrorList) cg.CodeBuffer {
    var cb = cg.CodeBuffer.init();
    var vars: [MAX_VARS]Var = undefined;
    var vc: usize = 0;
    var stack_off: i32 = 0;
    cg.build_data_size = 0;

    if (prog_root == parser_mod.NO_NODE) {
        cb.movRImm64(cg.RDI, 0);
        cb.movRImm64(cg.RAX, 60);
        cb.syscall();
        return cb;
    }

    const prog = &pool[@as(usize, @intCast(prog_root))];
    var main_idx: parser_mod.NodeIdx = parser_mod.NO_NODE;
    fn_count = 0;
    reloc_count = 0;
    gvc = 0;
    gv_data_size = 0;
    gv_reloc_count = 0;

    // Collect global variable declarations (var_decls at program level)
    {
        var ch2 = prog.first_child;
        while (ch2 != parser_mod.NO_NODE) {
            const cn2 = &pool[@as(usize, @intCast(ch2))];
            if (cn2.kind == .var_decl) {
                const gname = cn2.name_start[0..cn2.name_len];
                var arr_sz: u64 = 1;
                if (cn2.val_len > 0) arr_sz = @as(u64, @intCast(strToInt(cn2.val_start[0..cn2.val_len])));
                const total_size = arr_sz * 8;
                if (gvc < MAX_GVARS) {
                    gvars[gvc] = Var{ .name = gname, .off = 0, .size = 8 };
                    gv_offsets[gvc] = gv_data_size + total_size - 8;
                    gv_sizes[gvc] = total_size;
                    gv_init_nodes[gvc] = if (cn2.val_len == 0) cn2.first_child else parser_mod.NO_NODE;
                    gvc += 1;
                }
            }
            ch2 = cn2.next_sibling;
        }
    }

    // First pass: collect function names and find main
    var ch = prog.first_child;
    while (ch != parser_mod.NO_NODE) {
        const cn = &pool[@as(usize, @intCast(ch))];
        if (cn.kind == .fn_decl) {
            if (eq(cn.name_start[0..cn.name_len], "main")) {
                main_idx = ch;
            }
            if (fn_count < MAX_FNS) {
                fn_names[fn_count] = cn.name_start[0..cn.name_len];
                fn_positions[fn_count] = 0;
                fn_count += 1;
            }
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
            // Record this function's position
            const fname = cn.name_start[0..cn.name_len];
            var fi: usize = 0;
            while (fi < fn_count) : (fi += 1) {
                if (eq(fn_names[fi], fname)) {
                    fn_positions[fi] = cb.pos;
                    break;
                }
            }
            if (ch == main_idx) main_body_pos = cb.pos;
            compileFn(cn, pool, &cb, &vars, &vc, &stack_off, errs, &has_return);
        }
        ch = cn.next_sibling;
    }

    // Patch all relocations
    var ri: usize = 0;
    while (ri < reloc_count) : (ri += 1) {
        const call_pos2 = reloc_callpos[ri];
        const target_pos = fn_positions[reloc_target_idx[ri]];
        const off: i32 = @as(i32, @intCast(target_pos)) - @as(i32, @intCast(call_pos2 + 5));
        const off_u32: u32 = @as(u32, @bitCast(off));
        cb.buf[call_pos2 + 1] = @as(u8, @truncate(off_u32));
        cb.buf[call_pos2 + 2] = @as(u8, @truncate(off_u32 >> 8));
        cb.buf[call_pos2 + 3] = @as(u8, @truncate(off_u32 >> 16));
        cb.buf[call_pos2 + 4] = @as(u8, @truncate(off_u32 >> 24));
    }

    // Patch main call
    const main_off: i32 = @as(i32, @intCast(main_body_pos)) - @as(i32, @intCast(call_pos + 5));
    patch32(&cb, call_pos + 1, main_off);

    // Patch global variable relocations
    const code_len = cb.pos;
    const code_base = 0x400000 + 64 + 56;
    const data_base = code_base + code_len;
    {
        var gv_ri: usize = 0;
        while (gv_ri < gv_reloc_count) : (gv_ri += 1) {
            const ipos = gv_reloc_pos[gv_ri];
            const insn_addr = code_base + (ipos - 3);
            const target_addr = data_base + gv_reloc_data_off[gv_ri];
            const disp: i32 = @as(i32, @intCast(@as(i64, @intCast(target_addr)) - @as(i64, @intCast(insn_addr + 7))));
            patch32(&cb, ipos, disp);
        }
    }

    cg.build_data_size = gv_data_size;

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
    vc.* = 0;
    stack_off.* = 0;
    const var_count: usize = countVarDecls(n, pool);
    cb.pushR(cg.RBP);
    cb.movRR(cg.RBP, cg.RSP);
    const frame: i32 = @as(i32, @intCast(var_count)) * 8;
    if (frame > 0) cb.subRImm32(cg.RSP, frame);

    // Global variable initialization (only in main)
    if (eq(n.name_start[0..n.name_len], "main")) {
        var gv_i: usize = 0;
        while (gv_i < gvc) : (gv_i += 1) {
            const init_node = gv_init_nodes[gv_i];
            if (init_node != parser_mod.NO_NODE) {
                compileExprNode(init_node, pool, cb, vars, vc, errs);
                emitGlobalStore(cb, gv_offsets[gv_i]);
            }
        }
    }

    // Load parameters from argument registers (RDI, RSI, RDX, RCX, R8, R9)
    // Parameter var_decls are direct children of fn_decl before the block child
    const param_regs = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.RCX, cg.R8, cg.R9 };
    var param_idx: usize = 0;
    var child = n.first_child;
    while (child != parser_mod.NO_NODE) {
        const cn = &pool[@as(usize, @intCast(child))];
        if (cn.kind == .block) break;
        if (cn.kind == .var_decl) {
            const name = cn.name_start[0..cn.name_len];
            stack_off.* -= 8;
            const off = stack_off.*;
            if (vc.* < MAX_VARS) {
                vars[vc.*] = Var{ .name = name, .off = off, .size = 8 };
                vc.* += 1;
            }
            if (param_idx < 6) {
                cb.movMemR64(cg.RBP, off, param_regs[param_idx]);
                param_idx += 1;
            }
        }
        child = cn.next_sibling;
    }

    // Process remaining children (block body)
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
            } else {
                cb.xorRR(cg.RAX, cg.RAX);
            }
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
        .call => {
            compileCall(n, pool, cb, vars, vc, errs);
        },
        .assign => {
            if (n.first_child != parser_mod.NO_NODE) {
                compileExprNode(n.first_child, pool, cb, vars, vc, errs);
            } else {
                cb.xorRR(cg.RAX, cg.RAX);
            }
            const name = n.name_start[0..n.name_len];
            const off = findVarIndex(vars, vc.*, name);
            if (off) |o| {
                cb.movMemR64(cg.RBP, vars[o].off, cg.RAX);
            } else if (findGlobalVarIndex(name)) |gi| {
                emitGlobalStore(cb, gv_offsets[gi]);
            } else if (vc.* < MAX_VARS) {
                stack_off.* -= 8;
                vars[vc.*] = Var{ .name = name, .off = stack_off.*, .size = 8 };
                vc.* += 1;
                cb.movMemR64(cg.RBP, stack_off.*, cg.RAX);
            }
        },
        .if_stmt => compileIf(n, pool, cb, vars, vc, stack_off, errs, has_return),
        .while_stmt => compileWhile(n, pool, cb, vars, vc, stack_off, errs, has_return),
        .break_stmt => {
            if (loop_depth > 0) {
                const ld = loop_depth - 1;
                const jmp_pos = cb.pos;
                cb.jmpRel32(0);
                if (loop_break_count[ld] < 64) {
                    loop_break_jmps[ld][loop_break_count[ld]] = jmp_pos;
                    loop_break_count[ld] += 1;
                }
            }
        },
        .continue_stmt => {
            if (loop_depth > 0) {
                const start = loop_start_stack[loop_depth - 1];
                const back_off = @as(i32, @intCast(start)) - @as(i32, @intCast(cb.pos + 5));
                cb.jmpRel32(back_off);
            }
        },
        .store => {
            const lval = n.first_child;
            const val = if (lval != parser_mod.NO_NODE) pool[@as(usize, @intCast(lval))].next_sibling else parser_mod.NO_NODE;
            if (val != parser_mod.NO_NODE) {
                compileExprNode(val, pool, cb, vars, vc, errs);
            } else {
                cb.xorRR(cg.RAX, cg.RAX);
            }
            cb.pushR(cg.RAX);
            if (lval != parser_mod.NO_NODE) {
                compileExprAddr(lval, pool, cb, vars, vc, errs);
            } else {
                cb.xorRR(cg.RAX, cg.RAX);
            }
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
    if (idx == parser_mod.NO_NODE) {
        cb.xorRR(cg.RAX, cg.RAX);
        return;
    }
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .int_lit => {
            cb.movRImm64(cg.RAX, @as(u64, @intCast(strToInt(n.val_start[0..n.val_len]))));
        },
        .str_lit => {
            const s = n.val_start[0..n.val_len];
            cb.byte(0x48);
            cb.byte(0x8D);
            cb.byte(0x05);
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
            } else if (findGlobalOffset(vname)) |goff| {
                emitGlobalLoad(cb, goff);
            } else if (findColor(vname)) |c| {
                cb.movRImm64(cg.RAX, c);
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
        .ternary => {
            const cond = if (n.first_child != parser_mod.NO_NODE)
                &pool[@as(usize, @intCast(n.first_child))]
            else
                return cb.xorRR(cg.RAX, cg.RAX);
            const then_expr = if (cond.next_sibling != parser_mod.NO_NODE)
                cond.next_sibling
            else
                return cb.xorRR(cg.RAX, cg.RAX);
            const else_expr = if (pool[@as(usize, @intCast(then_expr))].next_sibling != parser_mod.NO_NODE)
                pool[@as(usize, @intCast(then_expr))].next_sibling
            else
                return cb.xorRR(cg.RAX, cg.RAX);

            // compile condition
            compileExprNode(n.first_child, pool, cb, vars, vc, errs);
            cb.cmpRImm32(cg.RAX, 0);
            const je_pos = cb.pos;
            cb.jeRel32(0);

            // compile then branch
            compileExprNode(then_expr, pool, cb, vars, vc, errs);
            const jmp_pos = cb.pos;
            cb.jmpRel32(0);

            // compile else branch
            const else_pos = cb.pos;
            patch32(cb, je_pos + 2, @as(i32, @intCast(else_pos)) - @as(i32, @intCast(je_pos + 6)));

            compileExprNode(else_expr, pool, cb, vars, vc, errs);
            const end_pos = cb.pos;
            patch32(cb, jmp_pos + 1, @as(i32, @intCast(end_pos)) - @as(i32, @intCast(jmp_pos + 5)));
        },
        else => {
            cb.xorRR(cg.RAX, cg.RAX);
        },
    }
}

fn compileExprAddr(idx: parser_mod.NodeIdx, pool: *[parser_mod.MAX_NODES]parser_mod.AstNode, cb: *cg.CodeBuffer, vars: *[MAX_VARS]Var, vc: *usize, errs: *errors_mod.ErrorList) void {
    if (idx == parser_mod.NO_NODE) {
        cb.xorRR(cg.RAX, cg.RAX);
        return;
    }
    const n = &pool[@as(usize, @intCast(idx))];
    switch (n.kind) {
        .ident => {
            const addr_name = n.name_start[0..n.name_len];
            if (findVarOffset(vars, vc.*, addr_name)) |off| {
                cb.leaRMem(cg.RAX, cg.RBP, off);
            } else if (findGlobalOffset(addr_name)) |goff| {
                emitGlobalAddr(cb, goff);
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
    if (left == parser_mod.NO_NODE or right == parser_mod.NO_NODE) {
        cb.xorRR(cg.RAX, cg.RAX);
        return;
    }

    compileExprNode(left, pool, cb, vars, vc, errs);
    cb.pushR(cg.RAX);
    compileExprNode(right, pool, cb, vars, vc, errs);
    cb.movRR(cg.RCX, cg.RAX);
    cb.popR(cg.RAX);

    if (eq(op, "+")) {
        cb.addRR(cg.RAX, cg.RCX);
    } else if (eq(op, "-")) {
        cb.subRR(cg.RAX, cg.RCX);
    } else if (eq(op, "*")) {
        cb.imulRR(cg.RAX, cg.RCX);
    } else if (eq(op, "/")) {
        cb.cqo();
        cb.idivR(cg.RCX);
    } else if (eq(op, "%")) {
        cb.cqo();
        cb.idivR(cg.RCX);
        cb.movRR(cg.RAX, cg.RDX);
    } else if (eq(op, "&")) {
        cb.andRR(cg.RAX, cg.RCX);
    } else if (eq(op, "|")) {
        cb.orRR(cg.RAX, cg.RCX);
    } else if (eq(op, "^")) {
        cb.xorRR(cg.RAX, cg.RCX);
    } else if (eq(op, "<<")) {
        cb.shlRcl(cg.RAX);
    } else if (eq(op, ">>")) {
        cb.shrRcl(cg.RAX);
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
    } else if (eq(op, "&&") or eq(op, "and")) {
        cb.andRR(cg.RAX, cg.RCX);
    } else if (eq(op, "||") or eq(op, "or")) {
        cb.orRR(cg.RAX, cg.RCX);
    } else {
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
    if (eq(op, "-")) {
        cb.negR(cg.RAX);
    } else if (eq(op, "!")) {
        cb.cmpRImm32(cg.RAX, 0);
        cb.pushfq();
        cb.xorRR(cg.RAX, cg.RAX);
        cb.popfq();
        cb.sete(cg.RAX);
    } else if (eq(op, "~")) {
        cb.notR(cg.RAX);
    } else {
        var buf: [128]u8 = undefined;
        const parts = [_][]const u8{ "unknown unary operator '", op, "'" };
        const len = formatMsg(&buf, 0, &parts);
        errs.add(.comp_type_mismatch, buf[0..len], n.line, n.col, "use a valid unary operator: -, !, ~");
        cb.xorRR(cg.RAX, cg.RAX);
    }
}

fn patchJccTo(cb: *cg.CodeBuffer, at: usize, target: usize) void {
    patch32(cb, at + 2, @as(i32, @intCast(target)) - @as(i32, @intCast(at + 6)));
}

fn patchJmpTo(cb: *cg.CodeBuffer, at: usize, target: usize) void {
    patch32(cb, at + 1, @as(i32, @intCast(target)) - @as(i32, @intCast(at + 5)));
}

fn emitCopyCStringX64(cb: *cg.CodeBuffer, dst: u8, src: u8) void {
    const loop_pos = cb.pos;
    cb.movzxRMem8(cg.RAX, src, 0);
    cb.cmpRImm32(cg.RAX, 0);
    const done = cb.pos;
    cb.jeRel32(0);
    cb.movMemR8(dst, 0, cg.RAX);
    cb.addRImm32(dst, 1);
    cb.addRImm32(src, 1);
    cb.jmpRel32(@as(i32, @intCast(loop_pos)) - @as(i32, @intCast(cb.pos + 5)));
    patchJccTo(cb, done, cb.pos);
}

fn emitCStringLenX64(cb: *cg.CodeBuffer, src: u8, len_reg: u8) void {
    cb.xorRR(len_reg, len_reg);
    cb.movRR(cg.R11, src);
    const loop_pos = cb.pos;
    cb.movzxRMem8(cg.RAX, cg.R11, 0);
    cb.cmpRImm32(cg.RAX, 0);
    const done = cb.pos;
    cb.jeRel32(0);
    cb.addRImm32(cg.R11, 1);
    cb.addRImm32(len_reg, 1);
    cb.jmpRel32(@as(i32, @intCast(loop_pos)) - @as(i32, @intCast(cb.pos + 5)));
    patchJccTo(cb, done, cb.pos);
}

fn emitWriteLitX64(cb: *cg.CodeBuffer, dst: u8, lit: []const u8) void {
    var i: usize = 0;
    while (i < lit.len) : (i += 1) {
        cb.movMemImm8(dst, 0, lit[i]);
        cb.addRImm32(dst, 1);
    }
}

fn emitRipCStringX64(cb: *cg.CodeBuffer, dst: u8, lit: []const u8) void {
    cb.byte(0x48);
    cb.byte(0x8D);
    cb.byte(0x05);
    cb.dword(2);
    cb.byte(0xEB);
    cb.byte(@as(u8, @intCast(lit.len)));
    for (lit) |c| cb.byte(c);
    cb.movRR(dst, cg.RAX);
}

fn emitWriteUnsignedDecimalX64(cb: *cg.CodeBuffer, value_reg: u8, dst: u8) void {
    cb.movRR(cg.RAX, value_reg);
    cb.cmpRImm32(cg.RAX, 0);
    const non_zero = cb.pos;
    cb.jneRel32(0);
    cb.movMemImm8(dst, 0, '0');
    cb.addRImm32(dst, 1);
    const done_zero = cb.pos;
    cb.jmpRel32(0);

    patchJccTo(cb, non_zero, cb.pos);
    cb.subRImm32(cg.RSP, 32);
    cb.xorRR(cg.RCX, cg.RCX);
    cb.movRImm64(cg.R10, 10);
    const div_loop = cb.pos;
    cb.xorRR(cg.RDX, cg.RDX);
    cb.idivR(cg.R10);
    cb.addRImm32(cg.RDX, '0');
    cb.movRR(cg.R11, cg.RSP);
    cb.addRR(cg.R11, cg.RCX);
    cb.movMemR8(cg.R11, 0, cg.RDX);
    cb.addRImm32(cg.RCX, 1);
    cb.cmpRImm32(cg.RAX, 0);
    const div_more = cb.pos;
    cb.jneRel32(0);
    patchJccTo(cb, div_more, div_loop);

    const write_loop = cb.pos;
    cb.subRImm32(cg.RCX, 1);
    cb.movRR(cg.R11, cg.RSP);
    cb.addRR(cg.R11, cg.RCX);
    cb.movzxRMem8(cg.RDX, cg.R11, 0);
    cb.movMemR8(dst, 0, cg.RDX);
    cb.addRImm32(dst, 1);
    cb.cmpRImm32(cg.RCX, 0);
    const write_more = cb.pos;
    cb.jneRel32(0);
    patchJccTo(cb, write_more, write_loop);
    cb.addRImm32(cg.RSP, 32);

    patchJmpTo(cb, done_zero, cb.pos);
}

fn emitInlineResolveX64(cb: *cg.CodeBuffer, host_reg: u8) void {
    const total_stack: i32 = 2048;
    var fail_no_fd: [32]usize = .{0} ** 32;
    var fail_no_fd_count: usize = 0;
    var fail_close: [16]usize = .{0} ** 16;
    var fail_close_count: usize = 0;
    var dotted_fail: [12]usize = .{0} ** 12;
    var dotted_fail_count: usize = 0;

    cb.movRR(cg.R9, host_reg);
    cb.movRR(cg.R13, host_reg);
    cb.xorRR(cg.R12, cg.R12);
    cb.xorRR(cg.RBX, cg.RBX);
    const dotted_octet_loop = cb.pos;
    cb.xorRR(cg.R10, cg.R10);
    cb.xorRR(cg.R11, cg.R11);
    const dotted_digit_loop = cb.pos;
    cb.movzxRMem8(cg.RAX, cg.R9, 0);
    cb.cmpRImm32(cg.RAX, '0');
    const dotted_digits_done_low = cb.pos;
    cb.jlRel32(0);
    cb.cmpRImm32(cg.RAX, '9');
    const dotted_digits_done_high = cb.pos;
    cb.jgRel32(0);
    cb.movRImm64(cg.RDX, 10);
    cb.imulRR(cg.R10, cg.RDX);
    cb.subRImm32(cg.RAX, '0');
    cb.addRR(cg.R10, cg.RAX);
    cb.addRImm32(cg.R11, 1);
    cb.cmpRImm32(cg.R10, 255);
    dotted_fail[dotted_fail_count] = cb.pos;
    dotted_fail_count += 1;
    cb.jgRel32(0);
    cb.addRImm32(cg.R9, 1);
    cb.jmpRel32(@as(i32, @intCast(dotted_digit_loop)) - @as(i32, @intCast(cb.pos + 5)));

    const dotted_digits_done = cb.pos;
    patchJccTo(cb, dotted_digits_done_low, dotted_digits_done);
    patchJccTo(cb, dotted_digits_done_high, dotted_digits_done);
    cb.cmpRImm32(cg.R11, 0);
    dotted_fail[dotted_fail_count] = cb.pos;
    dotted_fail_count += 1;
    cb.jeRel32(0);
    cb.movRR(cg.RDX, cg.RBX);
    cb.shlRImm8(cg.RDX, 3);
    cb.movRR(cg.RCX, cg.RDX);
    cb.shlRcl(cg.R10);
    cb.orRR(cg.R12, cg.R10);
    cb.cmpRImm32(cg.RBX, 3);
    const dotted_last_octet = cb.pos;
    cb.jeRel32(0);
    cb.cmpRImm32(cg.RAX, '.');
    dotted_fail[dotted_fail_count] = cb.pos;
    dotted_fail_count += 1;
    cb.jneRel32(0);
    cb.addRImm32(cg.R9, 1);
    cb.addRImm32(cg.RBX, 1);
    cb.jmpRel32(@as(i32, @intCast(dotted_octet_loop)) - @as(i32, @intCast(cb.pos + 5)));

    const dotted_last_pos = cb.pos;
    patchJccTo(cb, dotted_last_octet, dotted_last_pos);
    cb.cmpRImm32(cg.RAX, 0);
    dotted_fail[dotted_fail_count] = cb.pos;
    dotted_fail_count += 1;
    cb.jneRel32(0);
    cb.movRR(cg.RAX, cg.R12);
    const dotted_success_jump = cb.pos;
    cb.jmpRel32(0);

    const dns_start = cb.pos;
    var dfi: usize = 0;
    while (dfi < dotted_fail_count) : (dfi += 1) patchJccTo(cb, dotted_fail[dfi], dns_start);

    cb.subRImm32(cg.RSP, total_stack);
    cb.leaRMem(cg.R14, cg.RSP, 0);
    cb.leaRMem(cg.R15, cg.RSP, 512);

    cb.movMemImm8(cg.R14, 0, 0x12);
    cb.movMemImm8(cg.R14, 1, 0x34);
    cb.movMemImm8(cg.R14, 2, 0x01);
    cb.movMemImm8(cg.R14, 3, 0x00);
    cb.movMemImm8(cg.R14, 4, 0x00);
    cb.movMemImm8(cg.R14, 5, 0x01);
    var hdr_i: i32 = 6;
    while (hdr_i < 12) : (hdr_i += 1) cb.movMemImm8(cg.R14, hdr_i, 0);

    cb.leaRMem(cg.R12, cg.RSP, 12);
    cb.movRR(cg.R9, cg.R13);
    const label_loop = cb.pos;
    cb.movRR(cg.R10, cg.R12);
    cb.movMemImm8(cg.R10, 0, 0);
    cb.addRImm32(cg.R12, 1);
    cb.xorRR(cg.R11, cg.R11);

    const char_loop = cb.pos;
    cb.movzxRMem8(cg.RAX, cg.R9, 0);
    cb.cmpRImm32(cg.RAX, 0);
    const label_done_zero = cb.pos;
    cb.jeRel32(0);
    cb.cmpRImm32(cg.RAX, '.');
    const label_done_dot = cb.pos;
    cb.jeRel32(0);
    cb.movMemR8(cg.R12, 0, cg.RAX);
    cb.addRImm32(cg.R12, 1);
    cb.addRImm32(cg.R9, 1);
    cb.addRImm32(cg.R11, 1);
    cb.cmpRImm32(cg.R11, 63);
    fail_no_fd[fail_no_fd_count] = cb.pos;
    fail_no_fd_count += 1;
    cb.jgRel32(0);
    cb.jmpRel32(@as(i32, @intCast(char_loop)) - @as(i32, @intCast(cb.pos + 5)));

    const label_end = cb.pos;
    patchJccTo(cb, label_done_zero, label_end);
    patchJccTo(cb, label_done_dot, label_end);
    cb.movMemR8(cg.R10, 0, cg.R11);
    cb.cmpRImm32(cg.R11, 0);
    const non_empty_label = cb.pos;
    cb.jneRel32(0);
    cb.cmpRImm32(cg.RAX, 0);
    fail_no_fd[fail_no_fd_count] = cb.pos;
    fail_no_fd_count += 1;
    cb.jneRel32(0);
    patchJccTo(cb, non_empty_label, cb.pos);
    cb.cmpRImm32(cg.RAX, '.');
    const all_labels_done = cb.pos;
    cb.jneRel32(0);
    cb.addRImm32(cg.R9, 1);
    cb.jmpRel32(@as(i32, @intCast(label_loop)) - @as(i32, @intCast(cb.pos + 5)));

    patchJccTo(cb, all_labels_done, cb.pos);
    cb.movMemImm8(cg.R12, 0, 0);
    cb.addRImm32(cg.R12, 1);
    cb.movMemImm8(cg.R12, 0, 0);
    cb.movMemImm8(cg.R12, 1, 1);
    cb.movMemImm8(cg.R12, 2, 0);
    cb.movMemImm8(cg.R12, 3, 1);
    cb.addRImm32(cg.R12, 4);
    cb.movRR(cg.RBX, cg.R12);
    cb.subRR(cg.RBX, cg.R14);

    cb.movRImm64(cg.RAX, 41);
    cb.movRImm64(cg.RDI, 2);
    cb.movRImm64(cg.RSI, 2);
    cb.xorRR(cg.RDX, cg.RDX);
    cb.syscall();
    cb.movRR(cg.R13, cg.RAX);
    cb.cmpRImm32(cg.RAX, 0);
    fail_no_fd[fail_no_fd_count] = cb.pos;
    fail_no_fd_count += 1;
    cb.jlRel32(0);

    cb.leaRMem(cg.R10, cg.RSP, 1024);
    cb.movMemImm16(cg.R10, 0, 2);
    cb.movMemImm16(cg.R10, 2, 0x3500);
    cb.movMemImm32(cg.R10, 4, 0x08080808);
    cb.movMemImm32(cg.R10, 8, 0);
    cb.movMemImm32(cg.R10, 12, 0);

    cb.movRImm64(cg.RAX, 42);
    cb.movRR(cg.RDI, cg.R13);
    cb.movRR(cg.RSI, cg.R10);
    cb.movRImm64(cg.RDX, 16);
    cb.syscall();
    cb.cmpRImm32(cg.RAX, 0);
    fail_close[fail_close_count] = cb.pos;
    fail_close_count += 1;
    cb.jlRel32(0);

    cb.movRImm64(cg.RAX, 1);
    cb.movRR(cg.RDI, cg.R13);
    cb.movRR(cg.RSI, cg.R14);
    cb.movRR(cg.RDX, cg.RBX);
    cb.syscall();
    cb.cmpRImm32(cg.RAX, 0);
    fail_close[fail_close_count] = cb.pos;
    fail_close_count += 1;
    cb.jleRel32(0);

    cb.leaRMem(cg.R10, cg.RSP, 1040);
    cb.movMemR32(cg.R10, 0, cg.R13);
    cb.movMemImm16(cg.R10, 4, 1);
    cb.movMemImm16(cg.R10, 6, 0);
    cb.movRImm64(cg.RAX, 7);
    cb.movRR(cg.RDI, cg.R10);
    cb.movRImm64(cg.RSI, 1);
    cb.movRImm64(cg.RDX, 5000);
    cb.syscall();
    cb.cmpRImm32(cg.RAX, 0);
    fail_close[fail_close_count] = cb.pos;
    fail_close_count += 1;
    cb.jleRel32(0);

    cb.xorRR(cg.RAX, cg.RAX);
    cb.movRR(cg.RDI, cg.R13);
    cb.movRR(cg.RSI, cg.R15);
    cb.movRImm64(cg.RDX, 512);
    cb.syscall();
    cb.movRR(cg.R9, cg.RAX);
    cb.cmpRImm32(cg.RAX, 12);
    fail_close[fail_close_count] = cb.pos;
    fail_close_count += 1;
    cb.jleRel32(0);

    cb.movRImm64(cg.RAX, 3);
    cb.movRR(cg.RDI, cg.R13);
    cb.syscall();

    cb.movzxRMem8(cg.RAX, cg.R15, 0);
    cb.cmpRImm32(cg.RAX, 0x12);
    fail_no_fd[fail_no_fd_count] = cb.pos;
    fail_no_fd_count += 1;
    cb.jneRel32(0);
    cb.movzxRMem8(cg.RAX, cg.R15, 1);
    cb.cmpRImm32(cg.RAX, 0x34);
    fail_no_fd[fail_no_fd_count] = cb.pos;
    fail_no_fd_count += 1;
    cb.jneRel32(0);

    cb.movzxRMem8(cg.R10, cg.R15, 6);
    cb.shlRImm8(cg.R10, 8);
    cb.movzxRMem8(cg.RAX, cg.R15, 7);
    cb.orRR(cg.R10, cg.RAX);
    cb.cmpRImm32(cg.R10, 0);
    fail_no_fd[fail_no_fd_count] = cb.pos;
    fail_no_fd_count += 1;
    cb.jeRel32(0);

    cb.leaRMem(cg.R12, cg.R15, 12);
    const skip_q_loop = cb.pos;
    cb.movzxRMem8(cg.RAX, cg.R12, 0);
    cb.cmpRImm32(cg.RAX, 0);
    const skip_q_done = cb.pos;
    cb.jeRel32(0);
    cb.addRImm32(cg.R12, 1);
    cb.addRR(cg.R12, cg.RAX);
    cb.jmpRel32(@as(i32, @intCast(skip_q_loop)) - @as(i32, @intCast(cb.pos + 5)));
    patchJccTo(cb, skip_q_done, cb.pos);
    cb.addRImm32(cg.R12, 5);

    const answer_loop = cb.pos;
    cb.cmpRImm32(cg.R10, 0);
    fail_no_fd[fail_no_fd_count] = cb.pos;
    fail_no_fd_count += 1;
    cb.jeRel32(0);
    cb.movzxRMem8(cg.RAX, cg.R12, 0);
    cb.movRR(cg.RBX, cg.RAX);
    cb.movRImm64(cg.RAX, 0xC0);
    cb.andRR(cg.RBX, cg.RAX);
    cb.cmpRImm32(cg.RBX, 0xC0);
    const plain_name = cb.pos;
    cb.jneRel32(0);
    cb.addRImm32(cg.R12, 2);
    const name_done_jmp = cb.pos;
    cb.jmpRel32(0);
    patchJccTo(cb, plain_name, cb.pos);
    const plain_loop = cb.pos;
    cb.movzxRMem8(cg.RAX, cg.R12, 0);
    cb.cmpRImm32(cg.RAX, 0);
    const plain_done = cb.pos;
    cb.jeRel32(0);
    cb.addRImm32(cg.R12, 1);
    cb.addRR(cg.R12, cg.RAX);
    cb.jmpRel32(@as(i32, @intCast(plain_loop)) - @as(i32, @intCast(cb.pos + 5)));
    patchJccTo(cb, plain_done, cb.pos);
    cb.addRImm32(cg.R12, 1);
    patchJmpTo(cb, name_done_jmp, cb.pos);

    cb.movzxRMem8(cg.RAX, cg.R12, 0);
    cb.cmpRImm32(cg.RAX, 0);
    const skip_answer_1 = cb.pos;
    cb.jneRel32(0);
    cb.movzxRMem8(cg.RAX, cg.R12, 1);
    cb.cmpRImm32(cg.RAX, 1);
    const skip_answer_2 = cb.pos;
    cb.jneRel32(0);
    cb.movzxRMem8(cg.RAX, cg.R12, 2);
    cb.cmpRImm32(cg.RAX, 0);
    const skip_answer_3 = cb.pos;
    cb.jneRel32(0);
    cb.movzxRMem8(cg.RAX, cg.R12, 3);
    cb.cmpRImm32(cg.RAX, 1);
    const skip_answer_4 = cb.pos;
    cb.jneRel32(0);
    cb.movzxRMem8(cg.RAX, cg.R12, 8);
    cb.cmpRImm32(cg.RAX, 0);
    const skip_answer_5 = cb.pos;
    cb.jneRel32(0);
    cb.movzxRMem8(cg.RAX, cg.R12, 9);
    cb.cmpRImm32(cg.RAX, 4);
    const skip_answer_6 = cb.pos;
    cb.jneRel32(0);
    cb.movRMem32(cg.RAX, cg.R12, 10);
    cb.addRImm32(cg.RSP, total_stack);
    const success_jump = cb.pos;
    cb.jmpRel32(0);

    const skip_answer_pos = cb.pos;
    patchJccTo(cb, skip_answer_1, skip_answer_pos);
    patchJccTo(cb, skip_answer_2, skip_answer_pos);
    patchJccTo(cb, skip_answer_3, skip_answer_pos);
    patchJccTo(cb, skip_answer_4, skip_answer_pos);
    patchJccTo(cb, skip_answer_5, skip_answer_pos);
    patchJccTo(cb, skip_answer_6, skip_answer_pos);
    cb.movzxRMem8(cg.RAX, cg.R12, 8);
    cb.shlRImm8(cg.RAX, 8);
    cb.movzxRMem8(cg.RBX, cg.R12, 9);
    cb.orRR(cg.RAX, cg.RBX);
    cb.addRImm32(cg.R12, 10);
    cb.addRR(cg.R12, cg.RAX);
    cb.subRImm32(cg.R10, 1);
    cb.jmpRel32(@as(i32, @intCast(answer_loop)) - @as(i32, @intCast(cb.pos + 5)));

    const close_fail_pos = cb.pos;
    var fci: usize = 0;
    while (fci < fail_close_count) : (fci += 1) patchJccTo(cb, fail_close[fci], close_fail_pos);
    cb.movRImm64(cg.RAX, 3);
    cb.movRR(cg.RDI, cg.R13);
    cb.syscall();

    const fail_pos = cb.pos;
    var fni: usize = 0;
    while (fni < fail_no_fd_count) : (fni += 1) patchJccTo(cb, fail_no_fd[fni], fail_pos);
    cb.xorRR(cg.RAX, cg.RAX);
    cb.addRImm32(cg.RSP, total_stack);
    patchJmpTo(cb, success_jump, cb.pos);
    patchJmpTo(cb, dotted_success_jump, cb.pos);
}

fn emitInlineHttpX64(cb: *cg.CodeBuffer, is_post: bool, headers_reg: u8) void {
    const request_off: i32 = 0;
    const response_off: i32 = 4096;
    const sockaddr_off: i32 = 12288;
    const total_stack: i32 = 12320;
    var fail_no_fd: [16]usize = .{0} ** 16;
    var fail_no_fd_count: usize = 0;
    var fail_close: [16]usize = .{0} ** 16;
    var fail_close_count: usize = 0;

    cb.pushR(cg.R8);
    cb.pushR(cg.R9);
    cb.pushR(cg.R10);
    emitInlineResolveX64(cb, cg.R8);
    cb.movRR(cg.R12, cg.RAX);
    cb.popR(cg.R10);
    cb.popR(cg.R9);
    cb.popR(cg.R8);
    cb.cmpRImm32(cg.R12, 0);
    const have_ip = cb.pos;
    cb.jneRel32(0);
    cb.xorRR(cg.RAX, cg.RAX);
    const no_ip_done = cb.pos;
    cb.jmpRel32(0);
    patchJccTo(cb, have_ip, cb.pos);

    if (is_post) {
        cb.cmpRImm32(cg.R10, 0);
        const body_present = cb.pos;
        cb.jneRel32(0);
        cb.xorRR(cg.R11, cg.R11);
        const body_len_done = cb.pos;
        cb.jmpRel32(0);
        patchJccTo(cb, body_present, cb.pos);
        emitCStringLenX64(cb, cg.R10, cg.R11);
        patchJmpTo(cb, body_len_done, cb.pos);
    } else {
        cb.xorRR(cg.R11, cg.R11);
    }

    cb.subRImm32(cg.RSP, total_stack);
    cb.leaRMem(cg.R14, cg.RSP, request_off);
    cb.leaRMem(cg.R15, cg.RSP, response_off);

    if (is_post) emitWriteLitX64(cb, cg.R14, "POST ") else emitWriteLitX64(cb, cg.R14, "GET ");
    cb.cmpRImm32(cg.R9, 0);
    const path_present = cb.pos;
    cb.jneRel32(0);
    emitWriteLitX64(cb, cg.R14, "/");
    const path_done = cb.pos;
    cb.jmpRel32(0);
    patchJccTo(cb, path_present, cb.pos);
    emitCopyCStringX64(cb, cg.R14, cg.R9);
    patchJmpTo(cb, path_done, cb.pos);

    emitWriteLitX64(cb, cg.R14, " HTTP/1.0\r\nHost: ");
    emitCopyCStringX64(cb, cg.R14, cg.R8);
    emitWriteLitX64(cb, cg.R14, "\r\nConnection: close\r\n");
    if (headers_reg != 0xFF) {
        cb.cmpRImm32(headers_reg, 0);
        const no_headers = cb.pos;
        cb.jeRel32(0);
        emitCopyCStringX64(cb, cg.R14, headers_reg);
        patchJccTo(cb, no_headers, cb.pos);
    }
    if (is_post) {
        emitWriteLitX64(cb, cg.R14, "Content-Length: ");
        emitWriteUnsignedDecimalX64(cb, cg.R11, cg.R14);
        emitWriteLitX64(cb, cg.R14, "\r\nContent-Type: application/x-www-form-urlencoded\r\n");
    }
    emitWriteLitX64(cb, cg.R14, "\r\n");
    if (is_post) {
        cb.cmpRImm32(cg.R10, 0);
        const no_body = cb.pos;
        cb.jeRel32(0);
        emitCopyCStringX64(cb, cg.R14, cg.R10);
        patchJccTo(cb, no_body, cb.pos);
    }

    cb.movRR(cg.RBX, cg.R14);
    cb.leaRMem(cg.R14, cg.RSP, request_off);
    cb.subRR(cg.RBX, cg.R14);

    cb.movRImm64(cg.RAX, 41);
    cb.movRImm64(cg.RDI, 2);
    cb.movRImm64(cg.RSI, 1);
    cb.xorRR(cg.RDX, cg.RDX);
    cb.syscall();
    cb.movRR(cg.R13, cg.RAX);
    cb.cmpRImm32(cg.RAX, 0);
    fail_no_fd[fail_no_fd_count] = cb.pos;
    fail_no_fd_count += 1;
    cb.jlRel32(0);

    cb.leaRMem(cg.R10, cg.RSP, sockaddr_off);
    cb.movMemImm16(cg.R10, 0, 2);
    cb.movMemImm16(cg.R10, 2, 0x5000);
    cb.movMemR32(cg.R10, 4, cg.R12);
    cb.movMemImm32(cg.R10, 8, 0);
    cb.movMemImm32(cg.R10, 12, 0);
    cb.movRImm64(cg.RAX, 42);
    cb.movRR(cg.RDI, cg.R13);
    cb.movRR(cg.RSI, cg.R10);
    cb.movRImm64(cg.RDX, 16);
    cb.syscall();
    cb.cmpRImm32(cg.RAX, 0);
    fail_close[fail_close_count] = cb.pos;
    fail_close_count += 1;
    cb.jlRel32(0);

    cb.movRR(cg.R10, cg.R14);
    cb.movRR(cg.R11, cg.RBX);
    cb.movRImm64(cg.RAX, 1);
    cb.movRR(cg.RDI, cg.R13);
    cb.movRR(cg.RSI, cg.R10);
    cb.movRR(cg.RDX, cg.R11);
    cb.syscall();
    cb.cmpRImm32(cg.RAX, 0);
    fail_close[fail_close_count] = cb.pos;
    fail_close_count += 1;
    cb.jleRel32(0);

    cb.movRR(cg.R10, cg.R15);
    cb.movRImm64(cg.R11, 8191);
    const read_loop = cb.pos;
    cb.cmpRImm32(cg.R11, 0);
    const read_full = cb.pos;
    cb.jeRel32(0);
    cb.xorRR(cg.RAX, cg.RAX);
    cb.movRR(cg.RDI, cg.R13);
    cb.movRR(cg.RSI, cg.R10);
    cb.movRR(cg.RDX, cg.R11);
    cb.syscall();
    cb.cmpRImm32(cg.RAX, 0);
    const read_done = cb.pos;
    cb.jleRel32(0);
    cb.addRR(cg.R10, cg.RAX);
    cb.subRR(cg.R11, cg.RAX);
    cb.jmpRel32(@as(i32, @intCast(read_loop)) - @as(i32, @intCast(cb.pos + 5)));
    const read_end = cb.pos;
    patchJccTo(cb, read_full, read_end);
    patchJccTo(cb, read_done, read_end);
    cb.movMemImm8(cg.R10, 0, 0);
    cb.movRImm64(cg.RAX, 3);
    cb.movRR(cg.RDI, cg.R13);
    cb.syscall();
    cb.movRR(cg.RAX, cg.R15);
    cb.addRImm32(cg.RSP, total_stack);
    const success_jump = cb.pos;
    cb.jmpRel32(0);

    const close_fail_pos = cb.pos;
    var fci: usize = 0;
    while (fci < fail_close_count) : (fci += 1) patchJccTo(cb, fail_close[fci], close_fail_pos);
    cb.movRImm64(cg.RAX, 3);
    cb.movRR(cg.RDI, cg.R13);
    cb.syscall();

    const fail_pos = cb.pos;
    var fni: usize = 0;
    while (fni < fail_no_fd_count) : (fni += 1) patchJccTo(cb, fail_no_fd[fni], fail_pos);
    cb.xorRR(cg.RAX, cg.RAX);
    cb.addRImm32(cg.RSP, total_stack);
    patchJmpTo(cb, success_jump, cb.pos);
    patchJmpTo(cb, no_ip_done, cb.pos);
}

fn emitTlsClientX64(cb: *cg.CodeBuffer) void {
    // R8=host, R9=path, R10=body (0 for GET)
    cb.subRImm32(cg.RSP, 16384);

    cb.subRImm32(cg.RSP, 8);
    cb.movRR(cg.RDI, cg.RSP);
    cb.xorRR(cg.RSI, cg.RSI);
    cb.movRImm64(cg.RAX, 22);
    cb.syscall();
    cb.popR(cg.R13); // R13 = pipe_read | (pipe_write << 32)
    cb.movRR(cg.R12, cg.R13);
    cb.shrRImm8(cg.R12, 32); // R12 = pipe_write

    cb.movRImm64(cg.RAX, 57);
    cb.syscall();
    cb.cmpRImm32(cg.RAX, 0);
    const tlsc_parent = cb.pos;
    cb.jneRel32(0);

    // child: close pipe_read, dup2(pipe_write, 1), exec ./dhjsjs_cc with helper argv[0].
    cb.movRR(cg.RDI, cg.R13);
    cb.movRImm64(cg.RAX, 3);
    cb.syscall();
    cb.movRR(cg.RDI, cg.R12);
    cb.movRImm64(cg.RSI, 1);
    cb.movRImm64(cg.RAX, 33);
    cb.syscall();
    cb.movRR(cg.RDI, cg.R12);
    cb.movRImm64(cg.RAX, 3);
    cb.syscall();

    cb.cmpRImm32(cg.R10, 0);
    const tlsc_get_method = cb.pos;
    cb.jeRel32(0);
    emitRipCStringX64(cb, cg.R11, "POST\x00");
    const tlsc_method_done = cb.pos;
    cb.jmpRel32(0);
    patchJccTo(cb, tlsc_get_method, cb.pos);
    emitRipCStringX64(cb, cg.R11, "GET\x00");
    patchJmpTo(cb, tlsc_method_done, cb.pos);

    // argv: [tls_client, GET|POST, host, path, body?, NULL]
    cb.movRImm64(cg.RAX, 0);
    cb.pushR(cg.RAX);
    cb.cmpRImm32(cg.R10, 0);
    const tlsc_no_body_arg = cb.pos;
    cb.jeRel32(0);
    cb.pushR(cg.R10);
    patchJccTo(cb, tlsc_no_body_arg, cb.pos);
    cb.pushR(cg.R9);
    cb.pushR(cg.R8);
    cb.pushR(cg.R11);
    emitRipCStringX64(cb, cg.RAX, "tls_client\x00");
    cb.pushR(cg.RAX);

    cb.movRR(cg.RSI, cg.RSP);
    emitRipCStringX64(cb, cg.RDI, "./dhjsjs_cc\x00");
    cb.xorRR(cg.RDX, cg.RDX);
    cb.movRImm64(cg.RAX, 59);
    cb.syscall();
    cb.movRImm64(cg.RDI, 1);
    cb.movRImm64(cg.RAX, 60);
    cb.syscall();

    const tlsc_parent_pos = cb.pos;
    patchJccTo(cb, tlsc_parent, tlsc_parent_pos);
    cb.movRR(cg.R14, cg.RAX); // child pid

    // parent: close pipe_write
    cb.movRR(cg.RDI, cg.R12);
    cb.movRImm64(cg.RAX, 3);
    cb.syscall();

    // read response
    cb.xorRR(cg.R15, cg.R15);
    const tlsc_read_loop = cb.pos;
    cb.cmpRImm32(cg.R15, 16300);
    const tlsc_read_full = cb.pos;
    cb.jgeRel32(0);
    cb.movRR(cg.RDI, cg.R13);
    cb.leaRMem(cg.RSI, cg.RSP, 0);
    cb.addRR(cg.RSI, cg.R15);
    cb.movRImm64(cg.RDX, 16300);
    cb.subRR(cg.RDX, cg.R15);
    cb.xorRR(cg.RAX, cg.RAX);
    cb.syscall();
    cb.cmpRImm32(cg.RAX, 0);
    const tlsc_read_done = cb.pos;
    cb.jleRel32(0);
    cb.addRR(cg.R15, cg.RAX);
    cb.jmpRel32(@as(i32, @intCast(tlsc_read_loop)) - @as(i32, @intCast(cb.pos + 5)));

    patchJccTo(cb, tlsc_read_done, cb.pos);
    patchJccTo(cb, tlsc_read_full, cb.pos);

    cb.leaRMem(cg.RAX, cg.RSP, 0);
    cb.addRR(cg.RAX, cg.R15);
    cb.byte(0xC6);
    cb.byte(0x00);
    cb.byte(0x00);

    cb.movRR(cg.RDI, cg.R13);
    cb.movRImm64(cg.RAX, 3);
    cb.syscall();

    cb.subRImm32(cg.RSP, 16);
    cb.movRR(cg.RDI, cg.R14);
    cb.leaRMem(cg.RSI, cg.RSP, 0);
    cb.xorRR(cg.RDX, cg.RDX);
    cb.xorRR(cg.R10, cg.R10);
    cb.movRImm64(cg.RAX, 61);
    cb.syscall();
    cb.addRImm32(cg.RSP, 16);

    cb.movRR(cg.RAX, cg.RSP);
    cb.addRImm32(cg.RSP, 16384);
}

fn emitInlineX11Open(cb: *cg.CodeBuffer) void {
    // RDI=w, RSI=h, RDX=title
    // RAX=disp ptr or 0
    cb.pushR(cg.RBP);
    cb.movRR(cg.RBP, cg.RSP);
    cb.subRImm32(cg.RSP, 4096);
    cb.pushR(cg.R12); cb.pushR(cg.R13); cb.pushR(cg.R14); cb.pushR(cg.R15);
    cb.movMemR64(cg.RBP, -32, cg.RDI); // w
    cb.movMemR64(cg.RBP, -24, cg.RSI); // h
    // socket
    cb.movRImm32(cg.RDI, 1); cb.movRImm32(cg.RSI, 1); cb.xorRR(cg.RDX, cg.RDX);
    cb.movRImm64(cg.RAX, 41); cb.syscall();
    cb.cmpRImm32(cg.RAX, 0);
    const xo_fail1 = cb.pos; cb.jlRel32(0);
    cb.movRR(cg.R12, cg.RAX);
    // sockaddr_un
    cb.movMemImm16(cg.RSP, 0, 1);
    const sock_path = "/tmp/.X11-unix/X0";
    for (sock_path, 0..) |c, i| cb.movMemImm8(cg.RSP, @as(i32, @intCast(2 + i)), c);
    cb.movMemImm8(cg.RSP, @as(i32, @intCast(2 + sock_path.len)), 0);
    // connect
    cb.movRR(cg.RDI, cg.R12); cb.leaRMem(cg.RSI, cg.RSP, 0); cb.movRImm64(cg.RDX, 21);
    cb.movRImm64(cg.RAX, 42); cb.syscall();
    cb.cmpRImm32(cg.RAX, 0);
    const xo_fail2 = cb.pos; cb.jlRel32(0);
    // build conn request
    cb.movMemImm8(cg.RSP, 256, 0x6C); cb.movMemImm8(cg.RSP, 257, 0);
    cb.movMemImm16(cg.RSP, 258, 11); cb.movMemImm16(cg.RSP, 260, 0);
    cb.movMemImm16(cg.RSP, 262, 0); cb.movMemImm16(cg.RSP, 264, 0);
    cb.movMemImm16(cg.RSP, 266, 0);
    // write conn req
    cb.movRR(cg.RDI, cg.R12); cb.leaRMem(cg.RSI, cg.RSP, 256); cb.movRImm64(cg.RDX, 12);
    cb.movRImm64(cg.RAX, 1); cb.syscall();
    cb.cmpRImm32(cg.RAX, 12);
    const xo_fail3 = cb.pos; cb.jneRel32(0);
    // read 8-byte header
    cb.movRR(cg.RDI, cg.R12); cb.leaRMem(cg.RSI, cg.RSP, 512); cb.movRImm64(cg.RDX, 8);
    cb.xorRR(cg.RAX, cg.RAX); cb.syscall();
    cb.cmpRImm32(cg.RAX, 8);
    const xo_fail4 = cb.pos; cb.jneRel32(0);
    cb.cmpMemImm8(cg.RSP, 512, 1);
    const xo_fail5 = cb.pos; cb.jneRel32(0);
    // additional data length
    cb.movzxRMem8(cg.R13, cg.RSP, 518); cb.movzxRMem8(cg.R14, cg.RSP, 519);
    cb.shlRImm8(cg.R14, 8); cb.orRR(cg.R13, cg.R14);
    cb.shlRImm8(cg.R13, 2);
    cb.cmpRImm32(cg.R13, 3000);
    const xo_fail6 = cb.pos; cb.jgRel32(0);
    // read additional data
    cb.movRR(cg.RDI, cg.R12); cb.leaRMem(cg.RSI, cg.RSP, 520); cb.movRR(cg.RDX, cg.R13);
    cb.xorRR(cg.RAX, cg.RAX); cb.syscall();
    cb.cmpRR(cg.RAX, cg.R13);
    const xo_fail7 = cb.pos; cb.jneRel32(0);
    // parse response
    cb.movRMem32(cg.R14, cg.RSP, 524); cb.movMemR32(cg.RBP, -40, cg.R14); // id_base
    cb.movzxRMem8(cg.R15, cg.RSP, 536); cb.movzxRMem8(cg.R14, cg.RSP, 537);
    cb.shlRImm8(cg.R14, 8); cb.orRR(cg.R15, cg.R14); // R15 = vendor_len
    cb.movzxRMem8(cg.R14, cg.RSP, 541); // R14 = num_formats
    // off = 40 + vendor_len; pad
    cb.movRImm64(cg.R8, 40); cb.addRR(cg.R8, cg.R15);
    cb.addRImm32(cg.R8, 3); cb.shrRImm8(cg.R8, 2); cb.shlRImm8(cg.R8, 2);
    // off += formats*8; pad
    cb.movRR(cg.R9, cg.R14); cb.shlRImm8(cg.R9, 3); cb.addRR(cg.R8, cg.R9);
    cb.addRImm32(cg.R8, 3); cb.shrRImm8(cg.R8, 2); cb.shlRImm8(cg.R8, 2);
    // screen addr in RDI
    cb.leaRMem(cg.RDI, cg.RSP, 520); cb.addRR(cg.RDI, cg.R8);
    // read screen
    cb.movRMem32(cg.R9, cg.RDI, 0); cb.movMemR32(cg.RBP, -44, cg.R9); // root
    cb.movRMem32(cg.R9, cg.RDI, 8); cb.movMemR32(cg.RBP, -48, cg.R9); // white
    cb.movRMem32(cg.R9, cg.RDI, 12); cb.movMemR32(cg.RBP, -52, cg.R9); // black
    cb.movRMem32(cg.R9, cg.RDI, 20); cb.movRImm64(cg.R10, 0xFFFF); cb.andRR(cg.R9, cg.R10);
    cb.movMemR32(cg.RBP, -56, cg.R9); // w
    cb.movRMem32(cg.R9, cg.RDI, 22); cb.andRR(cg.R9, cg.R10);
    cb.movMemR32(cg.RBP, -60, cg.R9); // h
    cb.movzxRMem8(cg.R9, cg.RDI, 38); cb.movMemR8(cg.RBP, -61, cg.R9); // depth
    // wid = id_base + 1, gc = id_base + 2
    cb.movRMem32(cg.R14, cg.RBP, -40); cb.movRR(cg.R15, cg.R14);
    cb.addRImm32(cg.R14, 1); cb.movMemR32(cg.RBP, -64, cg.R14); // wid
    cb.addRImm32(cg.R15, 2); cb.movMemR32(cg.RBP, -68, cg.R15); // gc
    // --- CreateWindow ---
    cb.movMemImm8(cg.RSP, 256, 1); cb.movMemImm8(cg.RSP, 257, 0);
    cb.movMemImm16(cg.RSP, 258, 10);
    cb.movRMem32(cg.R9, cg.RBP, -64); cb.movMemR32(cg.RSP, 260, cg.R9); // wid
    cb.movRMem32(cg.R9, cg.RBP, -44); cb.movMemR32(cg.RSP, 264, cg.R9); // root
    cb.movMemImm32(cg.RSP, 268, 0); // x=0,y=0
    // w,h
    cb.movRMem32(cg.R9, cg.RBP, -32); cb.movRMem32(cg.R10, cg.RBP, -24);
    cb.shlRImm8(cg.R10, 16); cb.orRR(cg.R9, cg.R10);
    cb.movMemR32(cg.RSP, 272, cg.R9);
    cb.movMemImm32(cg.RSP, 276, 0x00010000); // border=0,class=1
    cb.movMemImm32(cg.RSP, 280, 0); // visual=0
    cb.movMemImm32(cg.RSP, 284, 2050); // mask
    cb.movRMem32(cg.R9, cg.RBP, -52); cb.movMemR32(cg.RSP, 288, cg.R9); // black
    cb.movMemImm32(cg.RSP, 292, 0x804D); // event mask
    // write CreateWindow
    cb.movRR(cg.RDI, cg.R12); cb.leaRMem(cg.RSI, cg.RSP, 256); cb.movRImm64(cg.RDX, 40);
    cb.movRImm64(cg.RAX, 1); cb.syscall();
    cb.cmpRImm32(cg.RAX, 40);
    const xo_fail8 = cb.pos; cb.jneRel32(0);
    // --- MapWindow ---
    cb.movMemImm8(cg.RSP, 256, 8); cb.movMemImm8(cg.RSP, 257, 0);
    cb.movMemImm16(cg.RSP, 258, 2);
    cb.movRMem32(cg.R9, cg.RBP, -64); cb.movMemR32(cg.RSP, 260, cg.R9);
    cb.movRR(cg.RDI, cg.R12); cb.leaRMem(cg.RSI, cg.RSP, 256); cb.movRImm64(cg.RDX, 8);
    cb.movRImm64(cg.RAX, 1); cb.syscall();
    cb.cmpRImm32(cg.RAX, 8);
    const xo_fail9 = cb.pos; cb.jneRel32(0);
    // --- CreateGC ---
    cb.movMemImm8(cg.RSP, 256, 55); cb.movMemImm8(cg.RSP, 257, 0);
    cb.movMemImm16(cg.RSP, 258, 4);
    cb.movRMem32(cg.R9, cg.RBP, -68); cb.movMemR32(cg.RSP, 260, cg.R9); // gc
    cb.movRMem32(cg.R9, cg.RBP, -64); cb.movMemR32(cg.RSP, 264, cg.R9); // drawable
    cb.movMemImm32(cg.RSP, 268, 0);
    cb.movRR(cg.RDI, cg.R12); cb.leaRMem(cg.RSI, cg.RSP, 256); cb.movRImm64(cg.RDX, 16);
    cb.movRImm64(cg.RAX, 1); cb.syscall();
    cb.cmpRImm32(cg.RAX, 16);
    const xo_fail10 = cb.pos; cb.jneRel32(0);
    // --- mmap framebuffer ---
    cb.movRMem64(cg.R8, cg.RBP, -32); // w
    cb.movRMem64(cg.R9, cg.RBP, -24); // h
    cb.imulRR(cg.R8, cg.R9); // R8 = w*h
    cb.shlRImm8(cg.R8, 2); // R8 = w*h*4
    cb.xorRR(cg.RDI, cg.RDI); cb.movRR(cg.RSI, cg.R8); cb.movRImm64(cg.RDX, 3);
    cb.movRImm64(cg.R10, 0x22); cb.movRImm64(cg.R8, ~@as(u64, 0)); cb.xorRR(cg.R9, cg.R9);
    cb.movRImm64(cg.RAX, 9); cb.syscall();
    cb.cmpRImm32(cg.RAX, -1);
    const xo_fail11 = cb.pos; cb.jeRel32(0);
    cb.pushR(cg.RAX); // save fb on stack
    // --- mmap display struct (48 bytes) ---
    cb.xorRR(cg.RDI, cg.RDI); cb.movRImm64(cg.RSI, 48); cb.movRImm64(cg.RDX, 3);
    cb.movRImm64(cg.R10, 0x22); cb.movRImm64(cg.R8, ~@as(u64, 0)); cb.xorRR(cg.R9, cg.R9);
    cb.movRImm64(cg.RAX, 9); cb.syscall();
    cb.cmpRImm32(cg.RAX, -1);
    const xo_fail12 = cb.pos; cb.jeRel32(0);
    cb.movRR(cg.R14, cg.RAX); // R14 = disp
    // Fill display struct
    cb.popR(cg.R15); // R15 = fb
    cb.movMemR64(cg.R14, 0, cg.R15); // pixels
    cb.movRMem64(cg.R9, cg.RBP, -32); cb.movMemR32(cg.R14, 8, cg.R9); // w
    cb.movRMem64(cg.R9, cg.RBP, -24); cb.movMemR32(cg.R14, 12, cg.R9); // h
    cb.movRMem64(cg.R9, cg.RBP, -32); cb.movMemR32(cg.R14, 16, cg.R9); // stride
    cb.movMemR32(cg.R14, 20, cg.R12); // fd
    cb.movRMem32(cg.R9, cg.RBP, -64); cb.movMemR32(cg.R14, 24, cg.R9); // window
    cb.movRMem32(cg.R9, cg.RBP, -68); cb.movMemR32(cg.R14, 28, cg.R9); // gc
    cb.movMemImm8(cg.R14, 32, 24); // depth
    // success path
    cb.movRR(cg.RAX, cg.R14);
    const xo_done = cb.pos;
    cb.jmpRel32(0);
    // fail paths
    const fail_patches = [_]usize{ xo_fail1, xo_fail2, xo_fail3, xo_fail4, xo_fail5, xo_fail6, xo_fail7, xo_fail8, xo_fail9, xo_fail10, xo_fail11, xo_fail12 };
    for (fail_patches) |fp| {
        patch32(cb, fp + 2, @as(i32, @intCast(cb.pos)) - @as(i32, @intCast(fp + 6)));
    }
    cb.xorRR(cg.RAX, cg.RAX); // return 0
    patch32(cb, xo_done + 1, @as(i32, @intCast(cb.pos)) - @as(i32, @intCast(xo_done + 5)));
    // restore
    cb.popR(cg.R15); cb.popR(cg.R14); cb.popR(cg.R13); cb.popR(cg.R12);
    cb.addRImm32(cg.RSP, 4096);
    cb.popR(cg.RBP);
}

fn emitInlineX11Present(cb: *cg.CodeBuffer) void {
    cb.pushR(cg.RBP); cb.movRR(cg.RBP, cg.RSP); cb.subRImm32(cg.RSP, 256);
    cb.pushR(cg.R12); cb.pushR(cg.R13); cb.pushR(cg.R14); cb.pushR(cg.R15);
    cb.pushR(cg.RBX);
    cb.movRMem64(cg.R12, cg.RDI, 0);
    cb.movRMem32(cg.R13, cg.RDI, 8);
    cb.movRMem32(cg.R14, cg.RDI, 12);
    cb.movRMem32(cg.R15, cg.RDI, 20);
    cb.movRMem32(cg.R8, cg.RDI, 24);
    cb.movRMem32(cg.R9, cg.RDI, 28);
    cb.xorRR(cg.R10, cg.R10);
    const xp_loop = cb.pos;
    cb.cmpRR(cg.R10, cg.R14);
    const xp_done = cb.pos; cb.jgeRel32(0);
    // max_rows = 262116 / (w*4)
    cb.movRImm32(cg.RAX, 262116);
    cb.movRR(cg.R11, cg.R13);
    cb.shlRImm8(cg.R11, 2);
    cb.xorRR(cg.RDX, cg.RDX);
    cb.idivR(cg.R11);
    cb.cmpRImm32(cg.RAX, 1);
    const xp_min1 = cb.pos; cb.jgeRel32(0);
    cb.movRImm32(cg.RAX, 1);
    const xp_min1_t = cb.pos;
    cb.movRR(cg.R11, cg.R14);
    cb.subRR(cg.R11, cg.R10);
    cb.cmpRR(cg.RAX, cg.R11);
    const xp_min2 = cb.pos; cb.jleRel32(0);
    cb.movRR(cg.RAX, cg.R11);
    const xp_min2_t = cb.pos;
    cb.movRR(cg.R11, cg.RAX); // R11d = batch_h
    // Build PutImage header at RSP
    cb.movMemImm16(cg.RSP, 0, (72 << 8) | 2);
    // length = 6 + w * batch_h
    cb.movRR(cg.RAX, cg.R13); cb.movRR(cg.RBX, cg.R11);
    cb.imulRR(cg.RAX, cg.RBX); cb.addRImm32(cg.RAX, 6);
    cb.movMemR8(cg.RSP, 2, cg.RAX);
    cb.shrRImm8(cg.RAX, 8); cb.movMemR8(cg.RSP, 3, cg.RAX);
    // window + gc
    cb.movMemR32(cg.RSP, 4, cg.R8);
    cb.movMemR32(cg.RSP, 8, cg.R9);
    // w + batch_h
    cb.movRR(cg.RAX, cg.R13); cb.movRR(cg.RBX, cg.R11);
    cb.shlRImm8(cg.RBX, 16); cb.orRR(cg.RAX, cg.RBX);
    cb.movMemR32(cg.RSP, 12, cg.RAX);
    // dst_x=0 + dst_y=y
    cb.movRR(cg.RAX, cg.R10); cb.shlRImm8(cg.RAX, 16);
    cb.movMemR32(cg.RSP, 16, cg.RAX);
    // left_pad + depth + padding
    cb.movMemImm32(cg.RSP, 20, 24 << 8);
    // write header
    cb.movRR(cg.RDI, cg.R15); cb.leaRMem(cg.RSI, cg.RSP, 0); cb.movRImm64(cg.RDX, 24);
    cb.movRImm64(cg.RAX, 1); cb.syscall();
    // write pixel rows
    cb.xorRR(cg.RBX, cg.RBX);
    const xp_inner = cb.pos;
    cb.cmpRR(cg.RBX, cg.R11);
    const xp_rows_done = cb.pos; cb.jgeRel32(0);
    cb.movRR(cg.RAX, cg.R10); cb.addRR(cg.RAX, cg.RBX);
    cb.imulRR(cg.RAX, cg.R13); cb.shlRImm8(cg.RAX, 2);
    cb.addRR(cg.RAX, cg.R12);
    cb.movRR(cg.RDI, cg.R15); cb.movRR(cg.RSI, cg.RAX);
    cb.movRR(cg.RAX, cg.R13); cb.shlRImm8(cg.RAX, 2);
    cb.movRR(cg.RDX, cg.RAX); cb.movRImm64(cg.RAX, 1);
    cb.syscall();
    cb.addRImm32(cg.RBX, 1);
    cb.jmpRel32(@as(i32, @intCast(xp_inner)) - @as(i32, @intCast(cb.pos + 5)));
    const xp_rows_t = cb.pos;
    // y += batch_h
    cb.addRR(cg.R10, cg.R11);
    cb.jmpRel32(@as(i32, @intCast(xp_loop)) - @as(i32, @intCast(cb.pos + 5)));
    const xp_done_t = cb.pos;
    // patch jumps
    patch32(cb, xp_done + 2, @as(i32, @intCast(xp_done_t)) - @as(i32, @intCast(xp_done + 6)));
    patch32(cb, xp_min1 + 2, @as(i32, @intCast(xp_min1_t)) - @as(i32, @intCast(xp_min1 + 6)));
    patch32(cb, xp_min2 + 2, @as(i32, @intCast(xp_min2_t)) - @as(i32, @intCast(xp_min2 + 6)));
    patch32(cb, xp_rows_done + 2, @as(i32, @intCast(xp_rows_t)) - @as(i32, @intCast(xp_rows_done + 6)));
    cb.popR(cg.RBX); cb.popR(cg.R15); cb.popR(cg.R14);
    cb.popR(cg.R13); cb.popR(cg.R12); cb.addRImm32(cg.RSP, 256);
    cb.popR(cg.RBP);
}

fn emitInlineX11PollEvent(cb: *cg.CodeBuffer) void {
    // RDI = disp ptr
    // save regs
    cb.pushR(cg.RBP); cb.movRR(cg.RBP, cg.RSP); cb.subRImm32(cg.RSP, 64);
    cb.pushR(cg.R12); cb.pushR(cg.R13); cb.pushR(cg.R14);
    cb.movRMem32(cg.R12, cg.RDI, 20); // fd
    // read 32 bytes at RSP
    cb.movRR(cg.RDI, cg.R12); cb.leaRMem(cg.RSI, cg.RSP, 0); cb.movRImm64(cg.RDX, 32);
    cb.xorRR(cg.RAX, cg.RAX); cb.syscall();
    cb.cmpRImm32(cg.RAX, 32);
    const xe_fail = cb.pos; cb.jneRel32(0);
    // parse event type
    cb.movzxRMem8(cg.R13, cg.RSP, 0); // R13d = event type
    cb.xorRR(cg.R14, cg.R14); // R14d = unified type
    // ButtonPress (4)
    cb.cmpRImm32(cg.R13, 4);
    const xe_not4 = cb.pos; cb.jneRel32(0);
    cb.movRImm32(cg.R14, 1);
    cb.movRImm64(cg.RDI, 0x200100);
    cb.movRMem32(cg.RAX, cg.RSP, 24); cb.movRImm64(cg.RCX, 0xFFFF); cb.andRR(cg.RAX, cg.RCX); cb.movMemR32(cg.RDI, 56, cg.RAX); // x
    cb.movRMem32(cg.RAX, cg.RSP, 26); cb.movRImm64(cg.RCX, 0xFFFF); cb.andRR(cg.RAX, cg.RCX); cb.movMemR32(cg.RDI, 60, cg.RAX); // y
    cb.movMemImm32(cg.RDI, 68, 0); // action = down
    cb.movMemImm32(cg.RDI, 64, 1); // touch_down = 1
    const xe_done4 = cb.pos; cb.jmpRel32(0);
    // ButtonRelease (5)
    const xe_not4_t = cb.pos;
    cb.cmpRImm32(cg.R13, 5);
    const xe_not5 = cb.pos; cb.jneRel32(0);
    cb.movRImm32(cg.R14, 2);
    cb.movRImm64(cg.RDI, 0x200100);
    cb.movMemImm32(cg.RDI, 68, 1); // action = up
    cb.movMemImm32(cg.RDI, 64, 0); // touch_down = 0
    const xe_done5 = cb.pos; cb.jmpRel32(0);
    // MotionNotify (6)
    const xe_not5_t = cb.pos;
    cb.cmpRImm32(cg.R13, 6);
    const xe_not6 = cb.pos; cb.jneRel32(0);
    cb.movRImm32(cg.R14, 3);
    cb.movRImm64(cg.RDI, 0x200100);
    cb.movRMem32(cg.RAX, cg.RSP, 24); cb.movRImm64(cg.RCX, 0xFFFF); cb.andRR(cg.RAX, cg.RCX); cb.movMemR32(cg.RDI, 56, cg.RAX); // x
    cb.movRMem32(cg.RAX, cg.RSP, 26); cb.movRImm64(cg.RCX, 0xFFFF); cb.andRR(cg.RAX, cg.RCX); cb.movMemR32(cg.RDI, 60, cg.RAX); // y
    cb.movMemImm32(cg.RDI, 68, 2); // action = move
    cb.movMemImm32(cg.RDI, 64, 1); // touch_down = 1
    const xe_done6 = cb.pos; cb.jmpRel32(0);
    // KeyPress (2)
    const xe_not6_t = cb.pos;
    cb.cmpRImm32(cg.R13, 2);
    const xe_not2 = cb.pos; cb.jneRel32(0);
    cb.movRImm32(cg.R14, 4);
    cb.movRImm64(cg.RDI, 0x200100);
    cb.movzxRMem8(cg.RAX, cg.RSP, 1); cb.movMemR32(cg.RDI, 80, cg.RAX); // keycode
    cb.movMemImm32(cg.RDI, 76, 0); // key_action = down
    const xe_done2 = cb.pos; cb.jmpRel32(0);
    // KeyRelease (3)
    const xe_not2_t = cb.pos;
    cb.cmpRImm32(cg.R13, 3);
    const xe_not3 = cb.pos; cb.jneRel32(0);
    cb.movRImm32(cg.R14, 5);
    cb.movRImm64(cg.RDI, 0x200100);
    cb.movzxRMem8(cg.RAX, cg.RSP, 1); cb.movMemR32(cg.RDI, 80, cg.RAX); // keycode
    cb.movMemImm32(cg.RDI, 76, 1); // key_action = up
    const xe_done3 = cb.pos; cb.jmpRel32(0);
    // Expose (12) and others: unified = 0 (already in R14)
    const xe_expose = cb.pos;
    // Store unified type
    cb.movRImm64(cg.RDI, 0x200100 + 504);
    cb.movMemR32(cg.RDI, 0, cg.R14);
    cb.movRR(cg.RAX, cg.R14);
    const xe_ret = cb.pos; cb.jmpRel32(0);
    // fail: return 0
    const xe_fail_t = cb.pos;
    cb.xorRR(cg.RAX, cg.RAX);
    const xe_ret_t = cb.pos;
    // patch jumps
    patch32(cb, xe_fail + 2, @as(i32, @intCast(xe_fail_t)) - @as(i32, @intCast(xe_fail + 6)));
    patch32(cb, xe_not4 + 2, @as(i32, @intCast(xe_not4_t)) - @as(i32, @intCast(xe_not4 + 6)));
    patch32(cb, xe_done4 + 1, @as(i32, @intCast(xe_expose)) - @as(i32, @intCast(xe_done4 + 5)));
    patch32(cb, xe_not5 + 2, @as(i32, @intCast(xe_not5_t)) - @as(i32, @intCast(xe_not5 + 6)));
    patch32(cb, xe_done5 + 1, @as(i32, @intCast(xe_expose)) - @as(i32, @intCast(xe_done5 + 5)));
    patch32(cb, xe_not6 + 2, @as(i32, @intCast(xe_not6_t)) - @as(i32, @intCast(xe_not6 + 6)));
    patch32(cb, xe_done6 + 1, @as(i32, @intCast(xe_expose)) - @as(i32, @intCast(xe_done6 + 5)));
    patch32(cb, xe_not2 + 2, @as(i32, @intCast(xe_not2_t)) - @as(i32, @intCast(xe_not2 + 6)));
    patch32(cb, xe_done2 + 1, @as(i32, @intCast(xe_expose)) - @as(i32, @intCast(xe_done2 + 5)));
    patch32(cb, xe_not3 + 2, @as(i32, @intCast(xe_expose)) - @as(i32, @intCast(xe_not3 + 6))); // fall through to expose
    patch32(cb, xe_done3 + 1, @as(i32, @intCast(xe_expose)) - @as(i32, @intCast(xe_done3 + 5)));
    patch32(cb, xe_ret + 1, @as(i32, @intCast(xe_ret_t)) - @as(i32, @intCast(xe_ret + 5)));
    // restore
    cb.popR(cg.R14); cb.popR(cg.R13); cb.popR(cg.R12);
    cb.addRImm32(cg.RSP, 64); cb.popR(cg.RBP);
}

fn compileGuiPacket(
    n: *const parser_mod.AstNode,
    pool: *[parser_mod.MAX_NODES]parser_mod.AstNode,
    cb: *cg.CodeBuffer,
    vars: *[MAX_VARS]Var,
    vc: *usize,
    errs: *errors_mod.ErrorList,
    cmd_type: u8,
    default_id: i64,
    has_id: bool,
    has_value: bool,
    has_label: bool,
) void {
    var vals: [7]i64 = .{0} ** 7;
    vals[1] = default_id;
    var label_buf: [32]u8 = .{0} ** 32;
    var fd_is_expr = false;
    var fd_expr_node: parser_mod.NodeIdx = parser_mod.NO_NODE;
    var is_expr: [7]bool = .{false} ** 7;
    var expr_nodes: [7]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 7;
    var expr_order: [7]usize = .{0} ** 7;
    var expr_count: usize = 0;

    const field_count: usize = if (has_id) 7 else 6;
    var arg_idx: usize = 0;
    var ch = n.first_child;
    while (ch != parser_mod.NO_NODE) : (arg_idx += 1) {
        const cn = &pool[@as(usize, @intCast(ch))];
        if (arg_idx == 0) {
            if (cn.kind == .int_lit) vals[0] = strToInt(cn.val_start[0..cn.val_len]) else {
                fd_is_expr = true;
                fd_expr_node = ch;
            }
        } else if (arg_idx < field_count) {
            const dst = if (has_id) arg_idx else arg_idx + 1;
            if (cn.kind == .int_lit) vals[dst] = strToInt(cn.val_start[0..cn.val_len]) else {
                is_expr[dst] = true;
                expr_nodes[dst] = ch;
                expr_order[expr_count] = dst;
                expr_count += 1;
            }
        } else if (has_value and arg_idx == field_count) {
            if (cn.kind == .int_lit) vals[6] = strToInt(cn.val_start[0..cn.val_len]) else {
                is_expr[6] = true;
                expr_nodes[6] = ch;
                expr_order[expr_count] = 6;
                expr_count += 1;
            }
        } else if (has_label and cn.kind == .str_lit) {
            var i: usize = 0;
            while (i < 32 and i < cn.val_len) : (i += 1) label_buf[i] = cn.val_start[i];
        }
        ch = cn.next_sibling;
    }

    cb.subRImm32(cg.RSP, 64);

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

    {
        var ei: usize = 0;
        while (ei < expr_count) : (ei += 1) {
            compileExprNode(expr_nodes[expr_order[ei]], pool, cb, vars, vc, errs);
            cb.pushR(cg.RAX);
        }
    }

    cb.movImm32RSP(0, @as(u32, cmd_type));
    if (!is_expr[1]) cb.movImm32RSP(1, @as(u32, @truncate(@as(u64, @bitCast(vals[1])))));
    if (!is_expr[2]) cb.movImm32RSP(5, @as(u32, @truncate(@as(u64, @bitCast(vals[2])))));
    if (!is_expr[3]) cb.movImm32RSP(9, @as(u32, @truncate(@as(u64, @bitCast(vals[3])))));
    if (!is_expr[4]) cb.movImm32RSP(13, @as(u32, @truncate(@as(u64, @bitCast(vals[4])))));
    if (!is_expr[5]) cb.movImm32RSP(17, @as(u32, @truncate(@as(u64, @bitCast(vals[5])))));
    if (!is_expr[6]) {
        cb.movRImm64(cg.RAX, @as(u64, @bitCast(vals[6])));
        cb.movMemR64(cg.RSP, 21, cg.RAX);
    }

    {
        var pi: usize = expr_count;
        while (pi > 0) {
            pi -= 1;
            const ea = expr_order[pi];
            cb.popR(cg.RAX);
            if (ea == 1) cb.movMemR32(cg.RSP, 1, cg.RAX) else if (ea == 2) cb.movMemR32(cg.RSP, 5, cg.RAX) else if (ea == 3) cb.movMemR32(cg.RSP, 9, cg.RAX) else if (ea == 4) cb.movMemR32(cg.RSP, 13, cg.RAX) else if (ea == 5) cb.movMemR32(cg.RSP, 17, cg.RAX) else if (ea == 6) cb.movMemR64(cg.RSP, 21, cg.RAX);
        }
    }

    if (fd_is_expr) {
        compileExprNode(fd_expr_node, pool, cb, vars, vc, errs);
        cb.byte(0x89);
        cb.byte(0xC7);
    } else {
        cb.movRImm64(cg.RDI, @as(u64, @intCast(vals[0])));
    }
    cb.leaRMem(cg.RSI, cg.RSP, 0);
    cb.movRImm64(cg.RDX, 61);
    cb.movRImm64(cg.RAX, 1);
    cb.syscall();
    cb.addRImm32(cg.RSP, 64);
}

fn collectGuiArgs(
    n: *const parser_mod.AstNode,
    pool: *[parser_mod.MAX_NODES]parser_mod.AstNode,
    args: *[10]parser_mod.NodeIdx,
    label_buf: *[32]u8,
) usize {
    var ai: usize = 0;
    var ch = n.first_child;
    while (ch != parser_mod.NO_NODE) {
        const cn = &pool[@as(usize, @intCast(ch))];
        if (cn.kind == .str_lit) {
            var i: usize = 0;
            while (i < 32 and i < cn.val_len) : (i += 1) label_buf[i] = cn.val_start[i];
        } else if (ai < args.len) {
            args[ai] = ch;
            ai += 1;
        }
        ch = cn.next_sibling;
    }
    return ai;
}

fn compileGuiBeginPacket(cb: *cg.CodeBuffer, cmd_type: u8, label_buf: *const [32]u8) void {
    cb.subRImm32(cg.RSP, 64);
    cb.xorRR(cg.RAX, cg.RAX);
    cb.movMemR64(cg.RSP, 0, cg.RAX);
    cb.movMemR64(cg.RSP, 8, cg.RAX);
    cb.movMemR64(cg.RSP, 16, cg.RAX);
    cb.movMemR64(cg.RSP, 24, cg.RAX);
    cb.movMemR64(cg.RSP, 32, cg.RAX);
    cb.movMemR64(cg.RSP, 40, cg.RAX);
    cb.movMemR64(cg.RSP, 48, cg.RAX);
    cb.movMemR64(cg.RSP, 56, cg.RAX);
    cb.movImm32RSP(0, @as(u32, cmd_type));

    var li: usize = 0;
    while (li < 4) : (li += 1) {
        var q: u64 = 0;
        var bi: usize = 0;
        while (bi < 8) : (bi += 1) {
            const idx = li * 8 + bi;
            q |= (@as(u64, label_buf[idx])) << @as(u6, @intCast(bi * 8));
        }
        cb.movRImm64(cg.RAX, q);
        cb.movMemR64(cg.RSP, @as(i32, @intCast(29 + li * 8)), cg.RAX);
    }
}

fn compileGuiArgToRax(
    idx: parser_mod.NodeIdx,
    default_value: i64,
    pool: *[parser_mod.MAX_NODES]parser_mod.AstNode,
    cb: *cg.CodeBuffer,
    vars: *[MAX_VARS]Var,
    vc: *usize,
    errs: *errors_mod.ErrorList,
) void {
    if (idx == parser_mod.NO_NODE) {
        cb.movRImm64(cg.RAX, @as(u64, @bitCast(default_value)));
    } else {
        compileExprNode(idx, pool, cb, vars, vc, errs);
    }
}

fn compileGuiStore32(
    idx: parser_mod.NodeIdx,
    off: i32,
    pool: *[parser_mod.MAX_NODES]parser_mod.AstNode,
    cb: *cg.CodeBuffer,
    vars: *[MAX_VARS]Var,
    vc: *usize,
    errs: *errors_mod.ErrorList,
) void {
    compileGuiArgToRax(idx, 0, pool, cb, vars, vc, errs);
    cb.movMemR32(cg.RSP, off, cg.RAX);
}

fn compileGuiStore64(
    idx: parser_mod.NodeIdx,
    off: i32,
    pool: *[parser_mod.MAX_NODES]parser_mod.AstNode,
    cb: *cg.CodeBuffer,
    vars: *[MAX_VARS]Var,
    vc: *usize,
    errs: *errors_mod.ErrorList,
) void {
    compileGuiArgToRax(idx, 0, pool, cb, vars, vc, errs);
    cb.movMemR64(cg.RSP, off, cg.RAX);
}

fn compileGuiStorePackedPair(
    lo_idx: parser_mod.NodeIdx,
    hi_idx: parser_mod.NodeIdx,
    off: i32,
    pool: *[parser_mod.MAX_NODES]parser_mod.AstNode,
    cb: *cg.CodeBuffer,
    vars: *[MAX_VARS]Var,
    vc: *usize,
    errs: *errors_mod.ErrorList,
) void {
    compileGuiArgToRax(lo_idx, 0, pool, cb, vars, vc, errs);
    cb.pushR(cg.RAX);
    compileGuiArgToRax(hi_idx, 0, pool, cb, vars, vc, errs);
    cb.shlRImm8(cg.RAX, 32);
    cb.popR(cg.RDI);
    cb.shlRImm8(cg.RDI, 32);
    cb.shrRImm8(cg.RDI, 32);
    cb.orRR(cg.RAX, cg.RDI);
    cb.movMemR64(cg.RSP, off, cg.RAX);
}

fn compileGuiFinishPacket(
    fd_idx: parser_mod.NodeIdx,
    pool: *[parser_mod.MAX_NODES]parser_mod.AstNode,
    cb: *cg.CodeBuffer,
    vars: *[MAX_VARS]Var,
    vc: *usize,
    errs: *errors_mod.ErrorList,
) void {
    compileGuiArgToRax(fd_idx, 0, pool, cb, vars, vc, errs);
    cb.byte(0x89);
    cb.byte(0xC7); // mov edi, eax
    cb.leaRMem(cg.RSI, cg.RSP, 0);
    cb.movRImm64(cg.RDX, 61);
    cb.movRImm64(cg.RAX, 1);
    cb.syscall();
    cb.addRImm32(cg.RSP, 64);
}

fn compileGuiPacketDirect(
    n: *const parser_mod.AstNode,
    pool: *[parser_mod.MAX_NODES]parser_mod.AstNode,
    cb: *cg.CodeBuffer,
    vars: *[MAX_VARS]Var,
    vc: *usize,
    errs: *errors_mod.ErrorList,
    cmd_type: u8,
    map: []const u8,
) void {
    var args: [10]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 10;
    var label_buf: [32]u8 = .{0} ** 32;
    _ = collectGuiArgs(n, pool, &args, &label_buf);

    compileGuiBeginPacket(cb, cmd_type, &label_buf);
    var mi: usize = 0;
    while (mi < map.len) : (mi += 1) {
        const idx = args[mi + 1];
        switch (map[mi]) {
            1 => compileGuiStore32(idx, 1, pool, cb, vars, vc, errs),
            2 => compileGuiStore32(idx, 5, pool, cb, vars, vc, errs),
            3 => compileGuiStore32(idx, 9, pool, cb, vars, vc, errs),
            4 => compileGuiStore32(idx, 13, pool, cb, vars, vc, errs),
            5 => compileGuiStore32(idx, 17, pool, cb, vars, vc, errs),
            6 => compileGuiStore64(idx, 21, pool, cb, vars, vc, errs),
            else => {},
        }
    }
    compileGuiFinishPacket(args[0], pool, cb, vars, vc, errs);
}

fn compileGuiPacketPacked(
    n: *const parser_mod.AstNode,
    pool: *[parser_mod.MAX_NODES]parser_mod.AstNode,
    cb: *cg.CodeBuffer,
    vars: *[MAX_VARS]Var,
    vc: *usize,
    errs: *errors_mod.ErrorList,
    cmd_type: u8,
    id_arg: usize,
    lo_arg: usize,
    hi_arg: usize,
) void {
    var args: [10]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 10;
    var label_buf: [32]u8 = .{0} ** 32;
    _ = collectGuiArgs(n, pool, &args, &label_buf);

    compileGuiBeginPacket(cb, cmd_type, &label_buf);
    if (id_arg != 0) compileGuiStore32(args[id_arg], 1, pool, cb, vars, vc, errs);
    compileGuiStore32(args[1], 5, pool, cb, vars, vc, errs);
    compileGuiStore32(args[2], 9, pool, cb, vars, vc, errs);
    compileGuiStore32(args[3], 13, pool, cb, vars, vc, errs);
    compileGuiStore32(args[4], 17, pool, cb, vars, vc, errs);
    compileGuiStorePackedPair(args[lo_arg], args[hi_arg], 21, pool, cb, vars, vc, errs);
    compileGuiFinishPacket(args[0], pool, cb, vars, vc, errs);
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
        if (ch != parser_mod.NO_NODE) {
            compileExprNode(ch, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
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
        var ai: usize = 0;
        var av: [3]i64 = .{ 2, 1, 0 };
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and ai < 3) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (cn.kind == .int_lit) av[ai] = strToInt(cn.val_start[0..cn.val_len]);
            ai += 1;
            ch = cn.next_sibling;
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
        const regs2 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri2: usize = arg_i;
        while (ri2 > 0) {
            ri2 -= 1;
            if (is_expr[ri2]) {
                cb.popR(regs2[ri2]);
            } else if (args_list[ri2] != parser_mod.NO_NODE) {
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
        const regs3 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri3: usize = arg_i;
        while (ri3 > 0) {
            ri3 -= 1;
            if (is_expr[ri3]) {
                cb.popR(regs3[ri3]);
            } else if (args_list[ri3] != parser_mod.NO_NODE) {
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
        const regs4 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri4: usize = arg_i;
        while (ri4 > 0) {
            ri4 -= 1;
            if (is_expr[ri4]) {
                cb.popR(regs4[ri4]);
            } else if (args_list[ri4] != parser_mod.NO_NODE) {
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
        const regs5 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri5: usize = arg_i;
        while (ri5 > 0) {
            ri5 -= 1;
            if (is_expr[ri5]) {
                cb.popR(regs5[ri5]);
            } else if (args_list[ri5] != parser_mod.NO_NODE) {
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
        const regs6 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri6: usize = arg_i;
        while (ri6 > 0) {
            ri6 -= 1;
            if (is_expr[ri6]) {
                cb.popR(regs6[ri6]);
            } else if (args_list[ri6] != parser_mod.NO_NODE) {
                const cn = &pool[@as(usize, @intCast(args_list[ri6]))];
                cb.movRImm64(regs6[ri6], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, 8);
        cb.syscall();
        return;
    }
    if (eq(name, "dup2")) {
        var oldfd: i64 = 0;
        var newfd: i64 = 0;
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
        if (ch != parser_mod.NO_NODE) {
            compileExprNode(ch, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        if (ch != parser_mod.NO_NODE) {
            const nxt = pool[@as(usize, @intCast(ch))].next_sibling;
            if (nxt != parser_mod.NO_NODE) {
                compileExprNode(nxt, pool, cb, vars, vc, errs);
            } else {
                cb.movRImm64(cg.RAX, 0x1C0);
            }
        } else {
            cb.movRImm64(cg.RAX, 0x1C0);
        }
        cb.movRR(cg.RSI, cg.RAX);
        cb.popR(cg.RDI);
        cb.movRImm64(cg.RAX, 83);
        cb.syscall();
        return;
    }
    if (eq(name, "chdir")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) {
            compileExprNode(ch, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
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
        const regs7 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri7: usize = arg_i;
        while (ri7 > 0) {
            ri7 -= 1;
            if (is_expr[ri7]) {
                cb.popR(regs7[ri7]);
            } else if (args_list[ri7] != parser_mod.NO_NODE) {
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
        if (ch != parser_mod.NO_NODE) {
            compileExprNode(ch, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
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
        const regs8 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri8: usize = arg_i;
        while (ri8 > 0) {
            ri8 -= 1;
            if (is_expr[ri8]) {
                cb.popR(regs8[ri8]);
            } else if (args_list[ri8] != parser_mod.NO_NODE) {
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
        if (ch != parser_mod.NO_NODE) {
            compileExprNode(ch, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.movRR(cg.RDI, cg.RAX);
        cb.movRImm64(cg.RAX, 63);
        cb.syscall();
        return;
    }
    if (eq(name, "time")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) {
            compileExprNode(ch, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
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
        const regs9 = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri9: usize = arg_i;
        while (ri9 > 0) {
            ri9 -= 1;
            if (is_expr[ri9]) {
                cb.popR(regs9[ri9]);
            } else if (args_list[ri9] != parser_mod.NO_NODE) {
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
        const regsA = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var riA: usize = arg_i;
        while (riA > 0) {
            riA -= 1;
            if (is_expr[riA]) {
                cb.popR(regsA[riA]);
            } else if (args_list[riA] != parser_mod.NO_NODE) {
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
        const regsB = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var riB: usize = arg_i;
        while (riB > 0) {
            riB -= 1;
            if (is_expr[riB]) {
                cb.popR(regsB[riB]);
            } else if (args_list[riB] != parser_mod.NO_NODE) {
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
        const regsC = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var riC: usize = arg_i;
        while (riC > 0) {
            riC -= 1;
            if (is_expr[riC]) {
                cb.popR(regsC[riC]);
            } else if (args_list[riC] != parser_mod.NO_NODE) {
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
        if (ch != parser_mod.NO_NODE) {
            compileExprNode(ch, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.movRR(cg.RDI, cg.RAX);
        cb.movRImm64(cg.RAX, 84);
        cb.syscall();
        return;
    }
    if (eq(name, "unlink")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) {
            compileExprNode(ch, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
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
        const regsD = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var riD: usize = arg_i;
        while (riD > 0) {
            riD -= 1;
            if (is_expr[riD]) {
                cb.popR(regsD[riD]);
            } else if (args_list[riD] != parser_mod.NO_NODE) {
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
            arg_i += 1;
            ch = cn.next_sibling;
        }
        if (arg_i == 3) {
            var fd_v: i64 = 0;
            var ip_v: i64 = 0;
            var port_v: i64 = 0;
            if (!is_expr[0]) {
                const cn = &pool[@as(usize, @intCast(args_list[0]))];
                if (cn.kind == .int_lit) fd_v = strToInt(cn.val_start[0..cn.val_len]);
            }
            if (!is_expr[1]) {
                const cn = &pool[@as(usize, @intCast(args_list[1]))];
                if (cn.kind == .int_lit) ip_v = strToInt(cn.val_start[0..cn.val_len]);
            }
            if (!is_expr[2]) {
                const cn = &pool[@as(usize, @intCast(args_list[2]))];
                if (cn.kind == .int_lit) port_v = strToInt(cn.val_start[0..cn.val_len]);
            }
            const pnet = @as(u16, @intCast(port_v));
            const pnet_be = (@as(u16, @intCast(pnet)) << 8) | (@as(u16, @intCast(pnet)) >> 8);
            if (is_expr[0]) {
                compileExprNode(args_list[0], pool, cb, vars, vc, errs);
            }
            cb.subRImm32(cg.RSP, 16);
            cb.movImm16RSP(0, @as(u16, @intCast(2)));
            cb.movImm16RSP(2, pnet_be);
            cb.movImm32RSP(4, @as(u32, @intCast(ip_v)));
            cb.movImm32RSP(8, 0);
            cb.movImm32RSP(12, 0);
            if (is_expr[0]) {
                cb.movRR(cg.RDI, cg.RAX);
            } else {
                cb.movRImm64(cg.RDI, @as(u64, @intCast(fd_v)));
            }
            cb.leaRMem(cg.RSI, cg.RSP, 0);
            cb.movRImm64(cg.RDX, 16);
            cb.movRImm64(cg.RAX, 42);
            cb.syscall();
            cb.addRImm32(cg.RSP, 16);
        } else {
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
            arg_i += 1;
            ch = cn.next_sibling;
        }
        if (arg_i == 3) {
            var fd_v: i64 = 0;
            var ip_v: i64 = 0;
            var port_v: i64 = 0;
            if (!is_expr[0]) {
                const cn = &pool[@as(usize, @intCast(args_list[0]))];
                if (cn.kind == .int_lit) fd_v = strToInt(cn.val_start[0..cn.val_len]);
            }
            if (!is_expr[1]) {
                const cn = &pool[@as(usize, @intCast(args_list[1]))];
                if (cn.kind == .int_lit) ip_v = strToInt(cn.val_start[0..cn.val_len]);
            }
            if (!is_expr[2]) {
                const cn = &pool[@as(usize, @intCast(args_list[2]))];
                if (cn.kind == .int_lit) port_v = strToInt(cn.val_start[0..cn.val_len]);
            }
            const pnet = @as(u16, @intCast(port_v));
            const pnet_be = (@as(u16, @intCast(pnet)) << 8) | (@as(u16, @intCast(pnet)) >> 8);
            if (is_expr[0]) {
                compileExprNode(args_list[0], pool, cb, vars, vc, errs);
            }
            cb.subRImm32(cg.RSP, 16);
            cb.movImm16RSP(0, @as(u16, @intCast(2)));
            cb.movImm16RSP(2, pnet_be);
            cb.movImm32RSP(4, @as(u32, @intCast(ip_v)));
            cb.movImm32RSP(8, 0);
            cb.movImm32RSP(12, 0);
            if (is_expr[0]) {
                cb.movRR(cg.RDI, cg.RAX);
            } else {
                cb.movRImm64(cg.RDI, @as(u64, @intCast(fd_v)));
            }
            cb.leaRMem(cg.RSI, cg.RSP, 0);
            cb.movRImm64(cg.RDX, 16);
            cb.movRImm64(cg.RAX, 49);
            cb.syscall();
            cb.addRImm32(cg.RSP, 16);
        } else {
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
            arg_i += 1;
            ch = cn.next_sibling;
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
            if (is_expr[0]) {
                compileExprNode(args_list[0], pool, cb, vars, vc, errs);
                cb.movRR(cg.RDI, cg.RAX);
            } else {
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
                cb.movRImm64(regs[ri], @as(u64, @intCast(if (cn.kind == .int_lit) strToInt(cn.val_start[0..cn.val_len]) else 0)));
            }
        }
        cb.movRImm64(cg.RAX, @as(u64, @intCast(sys_nr)));
        cb.syscall();
        return;
    }
    if (eq(name, "wavplay") or eq(name, "mp3play")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) {
            compileExprNode(ch, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.movRR(cg.RDI, cg.RAX);
        cb.movRImm64(cg.RAX, @intFromPtr(&player_mod.playFile));
        cb.byte(0xFF);
        cb.modrm(3, 2, 0);
        return;
    }
    if (eq(name, "playerapp")) {
        cb.movRImm64(cg.RAX, 57);
        cb.syscall();
        cb.cmpRImm32(cg.RAX, 0);
        const pp_parent = cb.pos;
        cb.jneRel32(0);

        cb.byte(0x48);
        cb.byte(0x8D);
        cb.byte(0x05);
        cb.dword(2);
        cb.byte(0xEB);
        const pp_argv0 = "media_player\x00";
        cb.byte(@as(u8, @intCast(pp_argv0.len)));
        for (pp_argv0) |c| cb.byte(c);
        cb.movRR(cg.R9, cg.RAX);

        cb.byte(0x48);
        cb.byte(0x8D);
        cb.byte(0x05);
        cb.dword(2);
        cb.byte(0xEB);
        const pp_exe = "./dhjsjs_cc\x00";
        cb.byte(@as(u8, @intCast(pp_exe.len)));
        for (pp_exe) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX);

        cb.movRImm64(cg.RAX, 0);
        cb.pushR(cg.RAX);
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

        cb.byte(0x48);
        cb.byte(0x8D);
        cb.byte(0x05);
        cb.dword(2);
        cb.byte(0xEB);
        const gp_argv0 = "gui_srv\x00";
        cb.byte(@as(u8, @intCast(gp_argv0.len)));
        for (gp_argv0) |c| cb.byte(c);
        cb.movRR(cg.R9, cg.RAX);

        cb.byte(0x48);
        cb.byte(0x8D);
        cb.byte(0x05);
        cb.dword(2);
        cb.byte(0xEB);
        const gp_exe = "./dhjsjs_cc\x00";
        cb.byte(@as(u8, @intCast(gp_exe.len)));
        for (gp_exe) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX);

        cb.movRImm64(cg.RAX, 0);
        cb.pushR(cg.RAX);
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
        cb.byte(0x48);
        cb.byte(0x8D);
        cb.byte(0x05);
        cb.dword(2);
        cb.byte(0xEB);
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
        cb.byte(0x49);
        cb.byte(0x89);
        cb.byte(0x1E); // mov [r14], rbx
        cb.addRImm32(cg.R14, 8); // advance envp
        cb.jmpRel8(0); // → check_null (fwd, patched below)
        const env_fwd_jmp_pos = cb.pos - 2;

        // scan_next:
        cb.addRImm32(cg.RBX, 1); // advance scan pointer

        // check_null:
        const env_check_null = cb.pos;
        cb.byte(0x80);
        cb.byte(0x3B);
        cb.byte(0x00); // cmp byte [rbx], 0
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
        cb.byte(0x49);
        cb.byte(0x89);
        cb.byte(0x06); // mov [r14], rax

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
        cb.popR(cg.R8); // R8 = pipe_a_read | (pipe_a_write << 32)
        cb.movRR(cg.R9, cg.R8);
        cb.shrRImm8(cg.R9, 32); // R9 = pipe_a_write

        // pipe B: child→parent (results)
        cb.subRImm32(cg.RSP, 8);
        cb.movRR(cg.RDI, cg.RSP);
        cb.xorRR(cg.RSI, cg.RSI);
        cb.movRImm64(cg.RAX, 22);
        cb.syscall();
        cb.popR(cg.R10); // R10 = pipe_b_read | (pipe_b_write << 32)
        cb.movRR(cg.R11, cg.R10);
        cb.shrRImm8(cg.R11, 32); // R11 = pipe_b_write

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

        cb.byte(0x48);
        cb.byte(0x8D);
        cb.byte(0x05);
        cb.dword(2);
        cb.byte(0xEB);
        const gsv_argv0 = "gui_srv\x00";
        cb.byte(@as(u8, @intCast(gsv_argv0.len)));
        for (gsv_argv0) |c| cb.byte(c);
        cb.movRR(cg.R9, cg.RAX);

        cb.byte(0x48);
        cb.byte(0x8D);
        cb.byte(0x05);
        cb.dword(2);
        cb.byte(0xEB);
        const gsv_exe = "./dhjsjs_cc\x00";
        cb.byte(@as(u8, @intCast(gsv_exe.len)));
        for (gsv_exe) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX);

        cb.movRImm64(cg.RAX, 0);
        cb.pushR(cg.RAX);
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
        if (!is_expr[1]) cb.movImm32RSP(0, @as(u32, @intCast(@as(u8, @intCast(gv[1]))))); // type @ 0
        if (!is_expr[2]) cb.movImm32RSP(1, @as(u32, @bitCast(@as(i32, @intCast(gv[2]))))); // id @ 1
        if (!is_expr[3]) cb.movImm32RSP(5, @as(u32, @bitCast(@as(i32, @intCast(gv[3]))))); // x @ 5
        if (!is_expr[4]) cb.movImm32RSP(9, @as(u32, @bitCast(@as(i32, @intCast(gv[4]))))); // y @ 9
        if (!is_expr[5]) cb.movImm32RSP(13, @as(u32, @bitCast(@as(i32, @intCast(gv[5]))))); // w @ 13
        if (!is_expr[6]) cb.movImm32RSP(17, @as(u32, @bitCast(@as(i32, @intCast(gv[6]))))); // h @ 17
        if (!is_expr[7]) {
            const val_u64 = @as(u64, @bitCast(gv[7]));
            cb.movRImm64(cg.RAX, val_u64);
            cb.movMemR64(cg.RSP, 21, cg.RAX); // val @ 21
        }

        // Pop expression values in reverse order and write to struct
        {
            var pi: usize = expr_count;
            while (pi > 0) {
                pi -= 1;
                const ea = expr_order[pi];
                cb.popR(cg.RAX);
                if (ea == 7) {
                    cb.movMemR64(cg.RSP, 21, cg.RAX); // val @ 21
                } else if (ea == 1) {
                    cb.byte(0x88);
                    cb.byte(0x44);
                    cb.byte(0x24);
                    cb.byte(0x00); // mov [rsp+0], al
                } else {
                    const off: i32 = if (ea == 2) 1 else if (ea == 3) 5 else if (ea == 4) 9 else if (ea == 5) 13 else 17;
                    cb.movMemR32(cg.RSP, off, cg.RAX);
                }
            }
        }

        // Set up write syscall using fd (expression or constant)
        if (fd_is_expr) {
            compileExprNode(fd_expr_node, pool, cb, vars, vc, errs);
            cb.byte(0x89);
            cb.byte(0xC7); // mov edi, eax (32-bit, zero-extends → correct fd)
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
    if (eq(name, "guiFrame") or eq(name, "guiframe")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 5, &[_]u8{});
        return;
    }
    if (eq(name, "guiButton") or eq(name, "guibutton")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 1, &[_]u8{ 1, 2, 3, 4, 5, 6 });
        return;
    }
    if (eq(name, "guiSlider") or eq(name, "guislider")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 2, &[_]u8{ 1, 2, 3, 4, 5, 6 });
        return;
    }
    if (eq(name, "guiLabel") or eq(name, "guilabel")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 3, &[_]u8{ 2, 3, 4, 5 });
        return;
    }
    if (eq(name, "guiCheck") or eq(name, "guicheck") or eq(name, "guiCheckbox") or eq(name, "guicheckbox")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 4, &[_]u8{ 1, 2, 3, 4, 5, 6 });
        return;
    }
    if (eq(name, "guiPixel") or eq(name, "guipixel")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 6, &[_]u8{ 2, 3, 6 });
        return;
    }
    if (eq(name, "guiRect") or eq(name, "guirect")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 7, &[_]u8{ 2, 3, 4, 5, 6 });
        return;
    }
    if (eq(name, "guiLine") or eq(name, "guiline")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 8, &[_]u8{ 2, 3, 4, 5, 6 });
        return;
    }
    if (eq(name, "guiCircle") or eq(name, "guicircle")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 9, &[_]u8{ 2, 3, 4, 6 });
        return;
    }
    if (eq(name, "guiGradientH") or eq(name, "guigradienth")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 10, &[_]u8{ 2, 3, 4, 5, 6 });
        return;
    }
    if (eq(name, "guiGradientV") or eq(name, "guigradientv")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 11, &[_]u8{ 2, 3, 4, 5, 6 });
        return;
    }
    if (eq(name, "guiWait") or eq(name, "guiwait")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 12, &[_]u8{});
        return;
    }
    if (eq(name, "guiPanel") or eq(name, "guipanel")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 17, &[_]u8{ 2, 3, 4, 5 });
        return;
    }
    if (eq(name, "guiText") or eq(name, "guitext")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 18, &[_]u8{ 2, 3, 4, 5, 6 });
        return;
    }
    if (eq(name, "guiTriangle") or eq(name, "guitriangle")) {
        var tri_args: [10]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 10;
        var tri_label: [32]u8 = .{0} ** 32;
        const tri_count = collectGuiArgs(n, pool, &tri_args, &tri_label);
        if (tri_count >= 8) {
            compileGuiPacketPacked(n, pool, cb, vars, vc, errs, 19, 7, 5, 6);
        } else {
            compileGuiPacketPacked(n, pool, cb, vars, vc, errs, 19, 0, 5, 6);
        }
        return;
    }
    if (eq(name, "guiGlassPanel") or eq(name, "guiglasspanel")) {
        compileGuiPacketPacked(n, pool, cb, vars, vc, errs, 20, 0, 6, 5);
        return;
    }
    if (eq(name, "guiShadow") or eq(name, "guishadow")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 21, &[_]u8{ 2, 3, 4, 5, 6 });
        return;
    }
    if (eq(name, "setStyle") or eq(name, "setstyle")) {
        // setStyle(fd, field_id, value), colors accept 0xRRGGBB or 0xAARRGGBB.
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 22, &[_]u8{ 1, 6 });
        return;
    }
    if (eq(name, "guiClear") or eq(name, "guiclear")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 23, &[_]u8{6});
        return;
    }
    if (eq(name, "guiRoundRect") or eq(name, "guiroundrect") or eq(name, "guiRoundedRect") or eq(name, "guiroundedrect")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 24, &[_]u8{ 2, 3, 4, 5, 1, 6 });
        return;
    }
    if (eq(name, "guiBorder") or eq(name, "guiborder")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 25, &[_]u8{ 2, 3, 4, 5, 6 });
        return;
    }
    if (eq(name, "guiGradient") or eq(name, "guigradient")) {
        compileGuiPacketPacked(n, pool, cb, vars, vc, errs, 26, 7, 5, 6);
        return;
    }
    if (eq(name, "guiBezier") or eq(name, "guibezier")) {
        compileGuiPacketPacked(n, pool, cb, vars, vc, errs, 27, 7, 5, 6);
        return;
    }
    if (eq(name, "guiClip") or eq(name, "guiclip") or eq(name, "guiSetClip") or eq(name, "guisetclip")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 28, &[_]u8{ 2, 3, 4, 5 });
        return;
    }
    if (eq(name, "guiNoClip") or eq(name, "guinoclip") or eq(name, "guiClearClip") or eq(name, "guiclearclip")) {
        compileGuiPacketDirect(n, pool, cb, vars, vc, errs, 29, &[_]u8{});
        return;
    }
    if (eq(name, "setTheme")) {
        // setTheme(fd, theme_id) -> sends CMD_SET_THEME to gui_srv
        // fd: file descriptor to write to (gui_srv write end from guiServer)
        // theme_id: 0=dark, 1=light, 2=modern_dark, 3=modern_light, 4=diamond
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
        cb.movImm32RSP(0, @as(u32, 13)); // CMD_SET_THEME = 13
        // id @ offset 1 (theme_id)
        if (!is_expr[1]) cb.movImm32RSP(1, @as(u32, @bitCast(@as(i32, @intCast(gv[1]))))); // id @ 1
        // x @ offset 5
        cb.movImm32RSP(5, 0); // unused
        // y @ offset 9
        cb.movImm32RSP(9, 0); // unused
        // w @ offset 13
        cb.movImm32RSP(13, 0); // unused
        // h @ offset 17
        cb.movImm32RSP(17, 0); // unused
        // val @ offset 21
        cb.movRImm64(cg.RAX, 0);
        cb.movMemR64(cg.RSP, 21, cg.RAX); // unused

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
            cb.byte(0x89);
            cb.byte(0xC7); // mov edi, eax
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
    if (eq(name, "setStyleColor")) {
        // setStyleColor(fd, field_index, color) -> CMD_SET_STYLE_COLOR
        // field_index: 0=BG, 1=PANEL_BG, 2=BTN_BG, 3=BTN_HOVER, 4=TEXT_COL,
        //              5=ACCENT, 6=BORDER, 7=CHECK_MARK, 8=INPUT_BG, 9=SEPARATOR
        var sc_gv: [8]i64 = .{0} ** 8;
        var sc_is_expr: [8]bool = .{false} ** 8;
        var sc_expr_nodes: [8]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 8;
        var sc_expr_order: [7]usize = .{0} ** 7;
        var sc_expr_count: usize = 0;
        var sc_arg_idx: usize = 0;
        var sc_ch = n.first_child;
        while (sc_ch != parser_mod.NO_NODE and sc_arg_idx < 3) : (sc_arg_idx += 1) {
            const sc_cn = &pool[@as(usize, @intCast(sc_ch))];
            if (sc_cn.kind == .int_lit) {
                sc_gv[sc_arg_idx] = strToInt(sc_cn.val_start[0..sc_cn.val_len]);
            } else {
                sc_is_expr[sc_arg_idx] = true;
                sc_expr_nodes[sc_arg_idx] = sc_ch;
                sc_expr_order[sc_expr_count] = sc_arg_idx;
                sc_expr_count += 1;
            }
            sc_ch = sc_cn.next_sibling;
        }
        cb.subRImm32(cg.RSP, 64);
        var sc_li: usize = 0;
        while (sc_li < 4) : (sc_li += 1) {
            cb.movRImm64(cg.RAX, 0);
            cb.movMemR64(cg.RSP, @as(i32, @intCast(29 + sc_li * 8)), cg.RAX);
        }
        {
            var sei: usize = 0;
            while (sei < sc_expr_count) : (sei += 1) {
                compileExprNode(sc_expr_nodes[sc_expr_order[sei]], pool, cb, vars, vc, errs);
                cb.pushR(cg.RAX);
            }
        }
        cb.movImm32RSP(0, @as(u32, 14)); // CMD_SET_STYLE_COLOR
        if (!sc_is_expr[1]) {
            cb.movImm32RSP(1, @as(u32, @bitCast(@as(i32, @intCast(sc_gv[1])))));
        } else {
            cb.movImm32RSP(1, 0); // placeholder, filled by pop
        }
        cb.movImm32RSP(5, 0);
        cb.movImm32RSP(9, 0);
        cb.movImm32RSP(13, 0);
        cb.movImm32RSP(17, 0);
        if (!sc_is_expr[2]) {
            const sc_val_u64 = @as(u64, @intCast(sc_gv[2]));
            cb.movRImm64(cg.RAX, sc_val_u64);
            cb.movMemR64(cg.RSP, 21, cg.RAX);
        } else {
            cb.movRImm64(cg.RAX, 0);
            cb.movMemR64(cg.RSP, 21, cg.RAX);
        }
        {
            var spi: usize = sc_expr_count;
            while (spi > 0) {
                spi -= 1;
                const sea = sc_expr_order[spi];
                cb.popR(cg.RAX);
                if (sea == 0) {} else if (sea == 1) {
                    cb.movMemR32(cg.RSP, 1, cg.RAX);
                } else if (sea == 2) {
                    cb.movMemR64(cg.RSP, 21, cg.RAX);
                }
            }
        }
        if (sc_is_expr[0]) {
            compileExprNode(sc_expr_nodes[sc_expr_order[0]], pool, cb, vars, vc, errs);
            cb.byte(0x89);
            cb.byte(0xC7);
        } else {
            cb.movRImm64(cg.RDI, @as(u64, @intCast(sc_gv[0])));
        }
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.movRImm64(cg.RDX, 61);
        cb.movRImm64(cg.RAX, 1);
        cb.syscall();
        cb.addRImm32(cg.RSP, 64);
        return;
    }
    if (eq(name, "setStyleRounding")) {
        // setStyleRounding(fd, rounding) -> CMD_SET_STYLE_ROUNDING
        var sr_gv: [8]i64 = .{0} ** 8;
        var sr_is_expr: [8]bool = .{false} ** 8;
        var sr_expr_nodes: [8]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 8;
        var sr_expr_order: [7]usize = .{0} ** 7;
        var sr_expr_count: usize = 0;
        var sr_arg_idx: usize = 0;
        var sr_ch = n.first_child;
        while (sr_ch != parser_mod.NO_NODE and sr_arg_idx < 2) : (sr_arg_idx += 1) {
            const sr_cn = &pool[@as(usize, @intCast(sr_ch))];
            if (sr_cn.kind == .int_lit) {
                sr_gv[sr_arg_idx] = strToInt(sr_cn.val_start[0..sr_cn.val_len]);
            } else {
                sr_is_expr[sr_arg_idx] = true;
                sr_expr_nodes[sr_arg_idx] = sr_ch;
                sr_expr_order[sr_expr_count] = sr_arg_idx;
                sr_expr_count += 1;
            }
            sr_ch = sr_cn.next_sibling;
        }
        cb.subRImm32(cg.RSP, 64);
        var sr_li: usize = 0;
        while (sr_li < 4) : (sr_li += 1) {
            cb.movRImm64(cg.RAX, 0);
            cb.movMemR64(cg.RSP, @as(i32, @intCast(29 + sr_li * 8)), cg.RAX);
        }
        {
            var sei: usize = 0;
            while (sei < sr_expr_count) : (sei += 1) {
                compileExprNode(sr_expr_nodes[sr_expr_order[sei]], pool, cb, vars, vc, errs);
                cb.pushR(cg.RAX);
            }
        }
        cb.movImm32RSP(0, @as(u32, 15)); // CMD_SET_STYLE_ROUNDING
        if (!sr_is_expr[1]) {
            cb.movImm32RSP(1, @as(u32, @bitCast(@as(i32, @intCast(sr_gv[1])))));
        } else {
            cb.movImm32RSP(1, 0);
        }
        cb.movImm32RSP(5, 0);
        cb.movImm32RSP(9, 0);
        cb.movImm32RSP(13, 0);
        cb.movImm32RSP(17, 0);
        cb.movRImm64(cg.RAX, 0);
        cb.movMemR64(cg.RSP, 21, cg.RAX);
        {
            var spi: usize = sr_expr_count;
            while (spi > 0) {
                spi -= 1;
                const sea = sr_expr_order[spi];
                cb.popR(cg.RAX);
                if (sea == 0) {} else if (sea == 1) {
                    cb.movMemR32(cg.RSP, 1, cg.RAX);
                }
            }
        }
        if (sr_is_expr[0]) {
            compileExprNode(sr_expr_nodes[sr_expr_order[0]], pool, cb, vars, vc, errs);
            cb.byte(0x89);
            cb.byte(0xC7);
        } else {
            cb.movRImm64(cg.RDI, @as(u64, @intCast(sr_gv[0])));
        }
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.movRImm64(cg.RDX, 61);
        cb.movRImm64(cg.RAX, 1);
        cb.syscall();
        cb.addRImm32(cg.RSP, 64);
        return;
    }
    if (eq(name, "guiPoll") or eq(name, "guipoll")) {
        // guiPoll(efd) -> sends CMD_FRAME, reads response into stack buffer, returns buf address
        // efd is encoded fd from guiServer: (read_fd << 32) | write_fd
        const po_ch = n.first_child;
        if (po_ch != parser_mod.NO_NODE) {
            compileExprNode(po_ch, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        cb.popR(cg.R10); // R10 = efd
        cb.movRR(cg.R11, cg.R10); // R11 = efd
        cb.shlRImm8(cg.R11, 32); // R11 = write_fd << 32 (garbage in lower 32)
        cb.shrRImm8(cg.R11, 32); // R11 = write_fd (lower 32 bits of efd)
        cb.shrRImm8(cg.R10, 32); // R10 = read_fd (upper 32 bits of efd)
        cb.pushR(cg.R11); // save write_fd
        cb.pushR(cg.R10); // save read_fd
        // Allocate 262-byte buffer on stack (aligned to 8)
        cb.subRImm32(cg.RSP, 272);
        cb.movRR(cg.R12, cg.RSP); // R12 = buf
        // Build CMD_FRAME (61 bytes, type=5, rest=0)
        cb.movRImm64(cg.RDI, 0);
        cb.pushR(cg.RDI);
        cb.pushR(cg.RDI);
        cb.pushR(cg.RDI);
        cb.pushR(cg.RDI);
        cb.pushR(cg.RDI);
        cb.pushR(cg.RDI);
        cb.pushR(cg.RDI);
        cb.pushR(cg.RDI);
        cb.byte(0x48);
        cb.byte(0x8D);
        cb.byte(0x04);
        cb.byte(0x24); // lea rax, [rsp]
        cb.movRImm64(cg.RDI, 5);
        cb.movMemR8(cg.RAX, 0, cg.RDI); // buf[0] = 5 (CMD_FRAME)
        // Zero out bytes 1-60
        cb.xorRR(cg.RDI, cg.RDI);
        cb.movMemR64(cg.RAX, 1, cg.RDI);
        cb.movMemR64(cg.RAX, 9, cg.RDI);
        cb.movMemR64(cg.RAX, 17, cg.RDI);
        cb.movMemR64(cg.RAX, 25, cg.RDI);
        cb.movMemR64(cg.RAX, 33, cg.RDI);
        cb.movMemR64(cg.RAX, 41, cg.RDI);
        cb.movMemR64(cg.RAX, 49, cg.RDI);
        cb.movMemR64(cg.RAX, 57, cg.RDI);
        // Write 61 bytes to write_fd
        cb.movRR(cg.RDI, cg.R11); // write_fd
        cb.movRR(cg.RSI, cg.RAX); // buf
        cb.movRImm64(cg.RDX, 61);
        cb.movRImm64(cg.RAX, 1);
        cb.syscall();
        // Read response from read_fd into R12 buffer
        cb.addRImm32(cg.RSP, 64); // skip all 8 zero pushes (64 bytes)
        cb.addRImm32(cg.RSP, 272); // skip buffer (272 bytes)
        cb.popR(cg.RDI); // read_fd (was saved before buffer alloc)
        cb.addRImm32(cg.RSP, 8); // skip write_fd
        cb.movRR(cg.RSI, cg.R12); // buffer
        cb.movRImm64(cg.RDX, 262);
        cb.movRImm64(cg.RAX, 0);
        cb.syscall();
        // Return buffer address in RAX (buffer lives below RSP, safe until next push)
        cb.movRR(cg.RAX, cg.R12);
        return;
    }
    if (eq(name, "guiCount") or eq(name, "guicount")) {
        // guiCount(buf) -> reads u16 from buf[0..1]
        const gc_ch = n.first_child;
        if (gc_ch != parser_mod.NO_NODE) {
            compileExprNode(gc_ch, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        cb.popR(cg.RDI);
        cb.movzxRMem8(cg.RAX, cg.RDI, 0);
        cb.pushR(cg.RAX);
        cb.movzxRMem8(cg.RAX, cg.RDI, 1);
        cb.shlRImm8(cg.RAX, 8);
        cb.popR(cg.RDI);
        cb.orRR(cg.RAX, cg.RDI);
        return;
    }
    if (eq(name, "guiEvId") or eq(name, "guievid")) {
        // guiEvId(buf, idx) -> reads u32 from buf[2 + idx*12]
        var ei_args: [2]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 2;
        var ei_ac: usize = 0;
        var ei_ch = n.first_child;
        while (ei_ch != parser_mod.NO_NODE and ei_ac < 2) {
            ei_args[ei_ac] = ei_ch;
            ei_ch = pool[@as(usize, @intCast(ei_ch))].next_sibling;
            ei_ac += 1;
        }
        if (ei_args[0] != parser_mod.NO_NODE) {
            compileExprNode(ei_args[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        if (ei_args[1] != parser_mod.NO_NODE) {
            compileExprNode(ei_args[1], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        cb.popR(cg.R8); // R8 = idx
        cb.popR(cg.R9); // R9 = buf
        cb.movRImm64(cg.R10, 12);
        cb.imulRR(cg.R10, cg.R8); // R10 = idx * 12
        cb.addRImm32(cg.R10, 2); // R10 = idx * 12 + 2
        cb.addRR(cg.R10, cg.R9); // R10 = buf + idx * 12 + 2
        cb.movRMem32(cg.RAX, cg.R10, 0);
        return;
    }
    if (eq(name, "guiEvVal") or eq(name, "guievval")) {
        // guiEvVal(buf, idx) -> reads u64 from buf[6 + idx*12]
        var ev_args: [2]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 2;
        var ev_ac: usize = 0;
        var ev_ch = n.first_child;
        while (ev_ch != parser_mod.NO_NODE and ev_ac < 2) {
            ev_args[ev_ac] = ev_ch;
            ev_ch = pool[@as(usize, @intCast(ev_ch))].next_sibling;
            ev_ac += 1;
        }
        if (ev_args[0] != parser_mod.NO_NODE) {
            compileExprNode(ev_args[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        if (ev_args[1] != parser_mod.NO_NODE) {
            compileExprNode(ev_args[1], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        cb.popR(cg.R8); // R8 = idx
        cb.popR(cg.R9); // R9 = buf
        cb.movRImm64(cg.R10, 12);
        cb.imulRR(cg.R10, cg.R8); // R10 = idx * 12
        cb.addRImm32(cg.R10, 6); // R10 = idx * 12 + 2 + 4 = idx*12 + 6
        cb.addRR(cg.R10, cg.R9); // R10 = buf + idx * 12 + 6
        cb.movRMem64(cg.RAX, cg.R10, 0);
        return;
    }
    if (eq(name, "guiHotspot") or eq(name, "guihotspot")) {
        var hs_a: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var hs_c: usize = 0;
        var hs_ch = n.first_child;
        while (hs_ch != parser_mod.NO_NODE and hs_c < 6) {
            hs_a[hs_c] = hs_ch;
            hs_ch = pool[@as(usize, @intCast(hs_ch))].next_sibling;
            hs_c += 1;
        }
        cb.subRImm32(cg.RSP, 64);
        cb.movRImm64(cg.RDI, 16);
        cb.movMemR8(cg.RSP, 0, cg.RDI);
        cb.movRImm64(cg.RDI, 0);
        cb.movMemR64(cg.RSP, 1, cg.RDI);
        cb.movMemR64(cg.RSP, 9, cg.RDI);
        cb.movMemR64(cg.RSP, 17, cg.RDI);
        cb.movMemR64(cg.RSP, 21, cg.RDI);
        cb.movMemR64(cg.RSP, 29, cg.RDI);
        cb.movMemR64(cg.RSP, 37, cg.RDI);
        cb.movMemR64(cg.RSP, 45, cg.RDI);
        cb.movMemR64(cg.RSP, 53, cg.RDI);
        if (hs_a[1] != parser_mod.NO_NODE) {
            compileExprNode(hs_a[1], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.movMemR32(cg.RSP, 1, cg.RAX);
        if (hs_a[2] != parser_mod.NO_NODE) {
            compileExprNode(hs_a[2], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.movMemR32(cg.RSP, 5, cg.RAX);
        if (hs_a[3] != parser_mod.NO_NODE) {
            compileExprNode(hs_a[3], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.movMemR32(cg.RSP, 9, cg.RAX);
        if (hs_a[4] != parser_mod.NO_NODE) {
            compileExprNode(hs_a[4], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.movMemR32(cg.RSP, 13, cg.RAX);
        if (hs_a[5] != parser_mod.NO_NODE) {
            compileExprNode(hs_a[5], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.movMemR32(cg.RSP, 17, cg.RAX);
        if (hs_a[0] != parser_mod.NO_NODE) {
            compileExprNode(hs_a[0], pool, cb, vars, vc, errs);
            cb.pushR(cg.RAX);
            cb.popR(cg.RDI);
        } else {
            cb.xorRR(cg.RDI, cg.RDI);
        }
        cb.shlRImm8(cg.RDI, 32);
        cb.shrRImm8(cg.RDI, 32);
        cb.leaRMem(cg.RSI, cg.RSP, 0);
        cb.movRImm64(cg.RDX, 61);
        cb.movRImm64(cg.RAX, 1);
        cb.syscall();
        cb.addRImm32(cg.RSP, 64);
        return;
    }
    // ===== GL3 GPU rendering builtins (pipe-based) =====
    // gl3Init spawns gl3_server and returns encoded fd: (read_fd << 32) | write_fd
    if (eq(name, "gl3Init") or eq(name, "gl3init")) {
        // Same as guiServer but launches gl3_server
        // For now, reuse guiServer mechanism — spawn ./dhjsjs_cc gl3_server
        // pipe A: parent→child, pipe B: child→parent
        cb.subRImm32(cg.RSP, 8);
        cb.movRR(cg.RDI, cg.RSP);
        cb.xorRR(cg.RSI, cg.RSI);
        cb.movRImm64(cg.RAX, 22); // SYS_PIPE
        cb.syscall();
        cb.popR(cg.R8); // R8 = pipe_a_read | (pipe_a_write << 32)
        cb.movRR(cg.R9, cg.R8);
        cb.shrRImm8(cg.R9, 32); // R9 = pipe_a_write

        cb.subRImm32(cg.RSP, 8);
        cb.movRR(cg.RDI, cg.RSP);
        cb.xorRR(cg.RSI, cg.RSI);
        cb.movRImm64(cg.RAX, 22);
        cb.syscall();
        cb.popR(cg.R10); // R10 = pipe_b_read | (pipe_b_write << 32)
        cb.movRR(cg.R11, cg.R10);
        cb.shrRImm8(cg.R11, 32); // R11 = pipe_b_write

        // fork
        cb.movRImm64(cg.RAX, 57);
        cb.syscall();
        cb.cmpRImm32(cg.RAX, 0);
        const g3_parent = cb.pos;
        cb.jneRel32(0);

        // child: dup2(pipe_a_read, 0), dup2(pipe_b_write, 1), close rest, exec
        cb.movRR(cg.RDI, cg.R8);
        cb.movRImm64(cg.RSI, 0);
        cb.movRImm64(cg.RAX, 33); // SYS_DUP2
        cb.syscall();
        cb.movRR(cg.RDI, cg.R11);
        cb.movRImm64(cg.RSI, 1);
        cb.movRImm64(cg.RAX, 33);
        cb.syscall();
        // close all pipe fds
        cb.movRR(cg.RDI, cg.R8); cb.movRImm64(cg.RAX, 3); cb.syscall();
        cb.movRR(cg.RDI, cg.R9); cb.movRImm64(cg.RAX, 3); cb.syscall();
        cb.movRR(cg.RDI, cg.R10); cb.movRImm64(cg.RAX, 3); cb.syscall();
        cb.movRR(cg.RDI, cg.R11); cb.movRImm64(cg.RAX, 3); cb.syscall();

        // exec: argv = ["./dhjsjs_cc", "gl3_server", NULL]
        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05); cb.dword(2); cb.byte(0xEB);
        const g3_argv1 = "gl3_server\x00";
        cb.byte(@as(u8, @intCast(g3_argv1.len)));
        for (g3_argv1) |c| cb.byte(c);
        cb.movRR(cg.R9, cg.RAX); // R9 = argv[1]

        cb.byte(0x48); cb.byte(0x8D); cb.byte(0x05); cb.dword(2); cb.byte(0xEB);
        const g3_exe = "./dhjsjs_cc\x00";
        cb.byte(@as(u8, @intCast(g3_exe.len)));
        for (g3_exe) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX); // RDI = argv[0]

        cb.movRImm64(cg.RAX, 0);
        cb.pushR(cg.RAX); // NULL terminator
        cb.pushR(cg.R9); // argv[1]
        cb.pushR(cg.RDI); // argv[0]
        cb.movRR(cg.RSI, cg.RSP); // argv pointer
        cb.movRImm64(cg.RAX, 0); // envp = NULL
        cb.pushR(cg.RAX);
        cb.popR(cg.RDX);
        cb.movRImm64(cg.RAX, 59); // SYS_EXECVE
        cb.syscall();
        cb.movRImm64(cg.RDI, 1);
        cb.movRImm64(cg.RAX, 60);
        cb.syscall();

        const g3_parent_pos = cb.pos;
        patch32(cb, g3_parent + 2, @as(i32, @intCast(g3_parent_pos)) - @as(i32, @intCast(g3_parent + 6)));

        // parent: close unused ends, return (pipe_b_read << 32) | pipe_a_write
        cb.movRR(cg.RDI, cg.R8); cb.movRImm64(cg.RAX, 3); cb.syscall(); // close pipe_a_read
        cb.movRR(cg.RDI, cg.R11); cb.movRImm64(cg.RAX, 3); cb.syscall(); // close pipe_b_write
        // return (pipe_b_read << 32) | pipe_a_write
        cb.movRR(cg.RAX, cg.R10); // RAX = pipe_b_read | (pipe_b_write << 32)
        cb.shlRImm8(cg.RAX, 32); // RAX = pipe_b_read << 32
        cb.orRR(cg.RAX, cg.R9); // RAX = (pipe_b_read << 32) | pipe_a_write
        return;
    }
    // gl3Cmd(efd, cmd_type, p1, p2, p3, p4) — sends 24-byte command to gl3_server
    if (eq(name, "gl3Cmd") or eq(name, "gl3cmd")) {
        // efd is encoded fd, cmd_type is command byte, p1-p4 are u32 params
        var ga: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var gc: usize = 0;
        var gch = n.first_child;
        while (gch != parser_mod.NO_NODE and gc < 6) : (gc += 1) {
            ga[gc] = gch;
            gch = pool[@as(usize, @intCast(gch))].next_sibling;
        }
        // Extract write_fd from efd
        if (ga[0] != parser_mod.NO_NODE) {
            compileExprNode(ga[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // save efd
        cb.movRR(cg.R10, cg.RAX);
        cb.shlRImm8(cg.R10, 32);
        cb.shrRImm8(cg.R10, 32); // R10 = write_fd (lower 32)
        // Build 24-byte command on stack
        cb.subRImm32(cg.RSP, 32);
        cb.xorRR(cg.RAX, cg.RAX);
        cb.movMemR64(cg.RSP, 0, cg.RAX); // zero first 8 bytes
        cb.movMemR64(cg.RSP, 8, cg.RAX); // zero next 8
        cb.movMemR64(cg.RSP, 16, cg.RAX); // zero next 8
        // cmd_type
        if (ga[1] != parser_mod.NO_NODE) {
            compileExprNode(ga[1], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.movMemR8(cg.RSP, 0, cg.RAX);
        // p1 at offset 4
        if (ga[2] != parser_mod.NO_NODE) {
            compileExprNode(ga[2], pool, cb, vars, vc, errs);
        } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.movMemR32(cg.RSP, 4, cg.RAX);
        // p2 at offset 8
        if (ga[3] != parser_mod.NO_NODE) {
            compileExprNode(ga[3], pool, cb, vars, vc, errs);
        } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.movMemR32(cg.RSP, 8, cg.RAX);
        // p3 at offset 12
        if (ga[4] != parser_mod.NO_NODE) {
            compileExprNode(ga[4], pool, cb, vars, vc, errs);
        } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.movMemR32(cg.RSP, 12, cg.RAX);
        // p4 at offset 16
        if (ga[5] != parser_mod.NO_NODE) {
            compileExprNode(ga[5], pool, cb, vars, vc, errs);
        } else { cb.xorRR(cg.RAX, cg.RAX); }
        cb.movMemR32(cg.RSP, 16, cg.RAX);
        // write(fd, buf, 24)
        cb.movRR(cg.RDI, cg.R10); // fd
        cb.movRR(cg.RSI, cg.RSP); // buf
        cb.movRImm64(cg.RDX, 24); // len
        cb.movRImm64(cg.RAX, 1); // SYS_WRITE
        cb.syscall();
        cb.addRImm32(cg.RSP, 32);
        cb.popR(cg.RAX); // restore efd (not needed but clean stack)
        return;
    }
    // gl3ReadEvent(efd) — reads 16-byte event response from gl3_server
    if (eq(name, "gl3ReadEvent") or eq(name, "gl3readevent")) {
        if (n.first_child != parser_mod.NO_NODE) {
            compileExprNode(n.first_child, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        // extract read_fd from efd (upper 32 bits)
        cb.movRR(cg.R10, cg.RAX);
        cb.shrRImm8(cg.R10, 32); // R10 = read_fd
        // Allocate 16-byte buffer on stack
        cb.subRImm32(cg.RSP, 16);
        cb.movRR(cg.RDI, cg.R10);
        cb.movRR(cg.RSI, cg.RSP);
        cb.movRImm64(cg.RDX, 16);
        cb.movRImm64(cg.RAX, 0); // SYS_READ
        cb.syscall();
        // Return buffer address
        cb.movRR(cg.RAX, cg.RSP);
        // Don't free stack — caller must manage or we leak (same as guiPoll)
        return;
    }
    if (eq(name, "audioplay")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) {
            compileExprNode(ch, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);

        cb.movRImm64(cg.RAX, 57);
        cb.syscall();
        cb.cmpRImm32(cg.RAX, 0);
        const aud_parent = cb.pos;
        cb.jneRel32(0);

        cb.popR(cg.R8);

        cb.byte(0x48);
        cb.byte(0x8D);
        cb.byte(0x05);
        cb.dword(2);
        cb.byte(0xEB);
        const aud_argv0 = "media_player\x00";
        cb.byte(@as(u8, @intCast(aud_argv0.len)));
        for (aud_argv0) |c| cb.byte(c);
        cb.movRR(cg.R9, cg.RAX);

        cb.byte(0x48);
        cb.byte(0x8D);
        cb.byte(0x05);
        cb.dword(2);
        cb.byte(0xEB);
        const aud_exe = "./dhjsjs_cc\x00";
        cb.byte(@as(u8, @intCast(aud_exe.len)));
        for (aud_exe) |c| cb.byte(c);
        cb.movRR(cg.RDI, cg.RAX);

        // Push argv in reverse: argv[2]=NULL, [1]=path, [0]="media_player"
        cb.movRImm64(cg.RAX, 0);
        cb.pushR(cg.RAX); // argv[2] = NULL
        cb.pushR(cg.R8); // argv[1] = path
        cb.pushR(cg.R9); // argv[0] = "media_player"

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
        var ai: usize = 0;
        var av: [3]i64 = .{ 44100, 2, 0x10 };
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and ai < 3) {
            const cn = &pool[@as(usize, @intCast(ch))];
            if (cn.kind == .int_lit) av[ai] = strToInt(cn.val_start[0..cn.val_len]);
            ai += 1;
            ch = cn.next_sibling;
        }
        // embed "/dev/dsp\0"
        cb.byte(0x48);
        cb.byte(0x8D);
        cb.byte(0x05);
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
        const regs_aw = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.R10, cg.R8, cg.R9 };
        var ri_aw: usize = arg_i;
        while (ri_aw > 0) {
            ri_aw -= 1;
            if (is_expr[ri_aw]) {
                cb.popR(regs_aw[ri_aw]);
            } else if (args_list[ri_aw] != parser_mod.NO_NODE) {
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
        cb.byte(0x48);
        cb.byte(0x8D);
        cb.byte(0x05);
        cb.dword(2);
        cb.byte(0xEB);
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
        if (ch5 != parser_mod.NO_NODE) {
            compileExprNode(ch5, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
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
        if (ch6 != parser_mod.NO_NODE) {
            compileExprNode(ch6, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        // struct: {fb_ptr, fd, xres, yres} at RAX
        // xres at +16
        cb.movRMem64(cg.RAX, cg.RAX, 16);
        return;
    }
    if (eq(name, "fb_height")) {
        const ch7 = n.first_child;
        if (ch7 != parser_mod.NO_NODE) {
            compileExprNode(ch7, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
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
        if (args_list_fb[0] != parser_mod.NO_NODE) {
            compileExprNode(args_list_fb[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        // struct: {fb_ptr, fd, xres, yres}
        cb.movRMem64(cg.R14, cg.RAX, 0); // fb_ptr
        cb.movRMem64(cg.RDI, cg.RAX, 16); // width (xres)

        if (args_list_fb[1] != parser_mod.NO_NODE) {
            compileExprNode(args_list_fb[1], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        if (args_list_fb[2] != parser_mod.NO_NODE) {
            compileExprNode(args_list_fb[2], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        if (args_list_fb[3] != parser_mod.NO_NODE) {
            compileExprNode(args_list_fb[3], pool, cb, vars, vc, errs);
        } else {
            cb.movRImm64(cg.RAX, 0xFFFFFFFF);
        }

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
        if (args_list_fbf[0] != parser_mod.NO_NODE) {
            compileExprNode(args_list_fbf[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        // struct: {fb_ptr, fd, xres, yres}
        cb.movRMem64(cg.R14, cg.RAX, 0); // fb_ptr
        cb.movRMem64(cg.RDI, cg.RAX, 16); // width (xres)

        if (args_list_fbf[1] != parser_mod.NO_NODE) {
            compileExprNode(args_list_fbf[1], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        if (args_list_fbf[2] != parser_mod.NO_NODE) {
            compileExprNode(args_list_fbf[2], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        if (args_list_fbf[3] != parser_mod.NO_NODE) {
            compileExprNode(args_list_fbf[3], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        if (args_list_fbf[4] != parser_mod.NO_NODE) {
            compileExprNode(args_list_fbf[4], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        if (args_list_fbf[5] != parser_mod.NO_NODE) {
            compileExprNode(args_list_fbf[5], pool, cb, vars, vc, errs);
        } else {
            cb.movRImm64(cg.RAX, 0xFFFFFFFF);
        }

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
    if (eq(name, "rounded_rect") or eq(name, "gui_rounded_rect")) {
        var args: [7]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 7;
        var ac: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and ac < 7) {
            args[ac] = ch;
            ac += 1;
            ch = pool[@as(usize, @intCast(ch))].next_sibling;
        }
        if (ac < 7) { cb.xorRR(cg.RAX, cg.RAX); return; }
        // fb struct pointer -> RDI, RSI, RDX
        compileExprNode(args[0], pool, cb, vars, vc, errs);
        cb.movRMem64(cg.RDI, cg.RAX, 0);
        cb.movRMem64(cg.RSI, cg.RAX, 8);
        cb.movRMem64(cg.RDX, cg.RAX, 12);
        // compile remaining args and push in: x, y, w, h, rad, color
        compileExprNode(args[1], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[2], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[3], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[4], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[5], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[6], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        // pop into registers: RCX, R8, R9
        cb.popR(cg.RCX);
        cb.popR(cg.R8);
        cb.popR(cg.R9);
        // stack: [h, rad, color]
        cb.movRImm64(cg.RAX, @intFromPtr(&render_mod.drawFillRoundRect));
        cb.byte(0xFF);
        cb.modrm(3, 2, 0);
        // restore stack: remove h, rad, color (24 bytes)
        cb.addRImm32(cg.RSP, 24);
        return;
    }
    if (eq(name, "filled_gradient") or eq(name, "gui_filled_gradient")) {
        var args: [8]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 8;
        var ac: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and ac < 8) {
            args[ac] = ch;
            ac += 1;
            ch = pool[@as(usize, @intCast(ch))].next_sibling;
        }
        if (ac < 8) { cb.xorRR(cg.RAX, cg.RAX); return; }
        compileExprNode(args[0], pool, cb, vars, vc, errs);
        cb.movRMem64(cg.RDI, cg.RAX, 0);
        cb.movRMem64(cg.RSI, cg.RAX, 8);
        cb.movRMem64(cg.RDX, cg.RAX, 12);
        // push vertical, c2, c1, h, w, y, x (7 values)
        compileExprNode(args[7], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[6], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[5], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[4], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[3], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[2], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[1], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        // pop RCX=x, R8=y, R9=w
        cb.popR(cg.RCX);
        cb.popR(cg.R8);
        cb.popR(cg.R9);
        // stack: h, c1, c2, vertical (4*8=32)
        cb.movRImm64(cg.RAX, @intFromPtr(&render_mod.drawFillGradient));
        cb.byte(0xFF);
        cb.modrm(3, 2, 0);
        cb.addRImm32(cg.RSP, 32);
        return;
    }
    if (eq(name, "fill_color") or eq(name, "set_bg")) {
        var args: [2]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 2;
        var ac: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and ac < 2) {
            args[ac] = ch;
            ac += 1;
            ch = pool[@as(usize, @intCast(ch))].next_sibling;
        }
        if (ac < 2) { cb.xorRR(cg.RAX, cg.RAX); return; }
        compileExprNode(args[0], pool, cb, vars, vc, errs);
        cb.movRMem64(cg.RDI, cg.RAX, 0);
        cb.movRMem64(cg.RSI, cg.RAX, 8);
        cb.movRMem64(cg.RDX, cg.RAX, 12);
        compileExprNode(args[1], pool, cb, vars, vc, errs);
        cb.movRImm64(cg.R8, 0); // dummy for 4th arg
        cb.pushR(cg.RAX); // color as stacked but need 4 args? Our fillColor expects (pixels, width, height, color) — 4 args: RDI, RSI, RDX, RCX. So push then pop to RCX.
        cb.popR(cg.RCX);
        // stack should be clean
        cb.movRImm64(cg.RAX, @intFromPtr(&render_mod.fillColor));
        cb.byte(0xFF);
        cb.modrm(3, 2, 0);
        return;
    }
    if (eq(name, "draw_text") or eq(name, "gui_text")) {
        var args: [6]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 6;
        var ac: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and ac < 6) {
            args[ac] = ch;
            ac += 1;
            ch = pool[@as(usize, @intCast(ch))].next_sibling;
        }
        if (ac < 6) { cb.xorRR(cg.RAX, cg.RAX); return; }
        compileExprNode(args[0], pool, cb, vars, vc, errs);
        cb.movRMem64(cg.RDI, cg.RAX, 0);
        cb.movRMem64(cg.RSI, cg.RAX, 8);
        cb.movRMem64(cg.RDX, cg.RAX, 12);
        // push fontSize, color, text, y, x
        compileExprNode(args[5], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[4], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[3], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[2], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[1], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        cb.popR(cg.RCX); cb.popR(cg.R8); cb.popR(cg.R9);
        // stack: color, fontSize
        cb.movRImm64(cg.RAX, @intFromPtr(&render_mod.drawString));
        cb.byte(0xFF);
        cb.modrm(3, 2, 0);
        cb.addRImm32(cg.RSP, 16);
        return;
    }
    if (eq(name, "draw_button") or eq(name, "gui_button")) {
        var args: [9]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 9;
        var ac: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and ac < 9) {
            args[ac] = ch;
            ac += 1;
            ch = pool[@as(usize, @intCast(ch))].next_sibling;
        }
        if (ac < 9) { cb.xorRR(cg.RAX, cg.RAX); return; }
        compileExprNode(args[0], pool, cb, vars, vc, errs);
        cb.movRMem64(cg.RDI, cg.RAX, 0);
        cb.movRMem64(cg.RSI, cg.RAX, 8);
        cb.movRMem64(cg.RDX, cg.RAX, 12);
        // push h, rad, bgColor, textColor, text, w, y, x
        compileExprNode(args[4], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[5], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[6], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[7], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[8], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[3], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[2], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        compileExprNode(args[1], pool, cb, vars, vc, errs); cb.pushR(cg.RAX);
        cb.popR(cg.RCX); // x
        cb.popR(cg.R8);  // y
        cb.popR(cg.R9);  // w
        // stack: h, rad, bgColor, textColor, text (5*8=40 bytes)
        cb.movRImm64(cg.RAX, @intFromPtr(&render_mod.drawButton));
        cb.byte(0xFF);
        cb.modrm(3, 2, 0);
        cb.addRImm32(cg.RSP, 40);
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
        cb.movRMem32(cg.RAX, cg.RDI, 56);
        return;
    }
    if (eq(name, "android_touch_y")) {
        cb.movRImm64(cg.RDI, 0x200100);
        cb.movRMem32(cg.RAX, cg.RDI, 60);
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
    if (eq(name, "android_fb_open") or eq(name, "androidFbOpen")) {
        // create fb struct at 0x200200
        cb.movRImm64(cg.RDI, 0x200100);
        cb.movRMem64(cg.RAX, cg.RDI, 48); // pixels
        cb.movRImm64(cg.RDI, 0x200200);
        cb.movMemR64(cg.RDI, 0, cg.RAX);
        cb.xorRR(cg.RAX, cg.RAX);
        cb.movMemR64(cg.RDI, 8, cg.RAX); // fd = 0
        cb.movRImm64(cg.R8, 0x200100);
        cb.movRMem64(cg.RAX, cg.R8, 36); // width
        cb.movMemR64(cg.RDI, 16, cg.RAX);
        cb.movRMem64(cg.RAX, cg.R8, 40); // height
        cb.movMemR64(cg.RDI, 24, cg.RAX);
        cb.movRImm64(cg.RAX, 0x200200);
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
        if (aargs[0] != parser_mod.NO_NODE) {
            compileExprNode(aargs[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        if (aargs[1] != parser_mod.NO_NODE) {
            compileExprNode(aargs[1], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        if (aargs[2] != parser_mod.NO_NODE) {
            compileExprNode(aargs[2], pool, cb, vars, vc, errs);
        } else {
            cb.movRImm64(cg.RAX, 0xFFFFFFFF);
        }
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
        if (raargs[0] != parser_mod.NO_NODE) {
            compileExprNode(raargs[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // x
        if (raargs[1] != parser_mod.NO_NODE) {
            compileExprNode(raargs[1], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // y
        if (raargs[2] != parser_mod.NO_NODE) {
            compileExprNode(raargs[2], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // w
        if (raargs[3] != parser_mod.NO_NODE) {
            compileExprNode(raargs[3], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // h
        if (raargs[4] != parser_mod.NO_NODE) {
            compileExprNode(raargs[4], pool, cb, vars, vc, errs);
        } else {
            cb.movRImm64(cg.RAX, 0xFFFFFFFF);
        }
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
        cb.movRImm64(cg.RDI, 0x200100 + 168);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
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
        if (aargs[0] != parser_mod.NO_NODE) {
            compileExprNode(aargs[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // index
        cb.popR(cg.R8); // R8 = index
        cb.movRImm64(cg.R9, 4);
        cb.imulRR(cg.R9, cg.R8); // R9 = index*4
        cb.movRImm64(cg.RDI, 0x200100 + 172);
        cb.addRR(cg.RDI, cg.R9); // RDI = address
        cb.movRMem32(cg.RAX, cg.RDI, 0); // load f32 bits
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
        if (aargs[0] != parser_mod.NO_NODE) {
            compileExprNode(aargs[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // index
        cb.popR(cg.R8);
        cb.movRImm64(cg.R9, 4);
        cb.imulRR(cg.R9, cg.R8);
        cb.movRImm64(cg.RDI, 0x200100 + 236);
        cb.addRR(cg.RDI, cg.R9);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
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
        if (aargs[0] != parser_mod.NO_NODE) {
            compileExprNode(aargs[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        cb.popR(cg.R8);
        cb.movRImm64(cg.R9, 4);
        cb.imulRR(cg.R9, cg.R8);
        cb.movRImm64(cg.RDI, 0x200100 + 300);
        cb.addRR(cg.RDI, cg.R9);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
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
        if (aargs[0] != parser_mod.NO_NODE) {
            compileExprNode(aargs[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        cb.popR(cg.R8);
        cb.movRImm64(cg.R9, 4);
        cb.imulRR(cg.R9, cg.R8);
        cb.movRImm64(cg.RDI, 0x200100 + 428);
        cb.addRR(cg.RDI, cg.R9);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        return;
    }
    if (eq(name, "android_touch_action_index")) {
        var aargs: [1]parser_mod.NodeIdx = .{parser_mod.NO_NODE};
        var ac: usize = 0;
        var achild = n.first_child;
        while (achild != parser_mod.NO_NODE and ac < 1) {
            aargs[ac] = achild;
            ac += 1;
            achild = pool[@as(usize, @intCast(achild))].next_sibling;
        }
        if (aargs[0] != parser_mod.NO_NODE) {
            compileExprNode(aargs[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        cb.popR(cg.R8);
        cb.movRImm64(cg.R9, 4);
        cb.imulRR(cg.R9, cg.R8);
        cb.movRImm64(cg.RDI, 0x200100 + 364);
        cb.addRR(cg.RDI, cg.R9);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        return;
    }
    if (eq(name, "android_clicked")) {
        cb.movRImm64(cg.RDI, 0x200100 + 492);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        return;
    }
    if (eq(name, "android_click_x")) {
        cb.movRImm64(cg.RDI, 0x200100 + 496);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        return;
    }
    if (eq(name, "android_click_y")) {
        cb.movRImm64(cg.RDI, 0x200100 + 500);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        return;
    }
    if (eq(name, "gui_ev_type") or eq(name, "ev_type") or eq(name, "event_type")) {
        cb.movRImm64(cg.RDI, 0x200100 + 504);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        return;
    }
    if (eq(name, "gui_ev_x") or eq(name, "ev_x")) {
        cb.movRImm64(cg.RDI, 0x200100 + 56);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        return;
    }
    if (eq(name, "gui_ev_y") or eq(name, "ev_y")) {
        cb.movRImm64(cg.RDI, 0x200100 + 60);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        return;
    }
    if (eq(name, "gui_ev_action") or eq(name, "ev_action")) {
        cb.movRImm64(cg.RDI, 0x200100 + 68);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        return;
    }
    if (eq(name, "gui_ev_keycode") or eq(name, "ev_keycode")) {
        cb.movRImm64(cg.RDI, 0x200100 + 80);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        return;
    }
    if (eq(name, "gui_ev_pointer_id") or eq(name, "ev_pointer_id")) {
        cb.movRImm64(cg.RDI, 0x200100 + 72);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        return;
    }
    if (eq(name, "resolve") or eq(name, "resolve_hostname")) {
        const rch = n.first_child;
        if (rch != parser_mod.NO_NODE) {
            compileExprNode(rch, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        emitInlineResolveX64(cb, cg.RAX);
        return;
    }
    if (eq(name, "https.get") or eq(name, "https_get") or eq(name, "httpsget") or
        eq(name, "tls.get") or eq(name, "tls_get") or eq(name, "tlsget"))
    {
        var hg_args: [2]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 2;
        var hg_ac: usize = 0;
        var hg_ch = n.first_child;
        while (hg_ch != parser_mod.NO_NODE and hg_ac < 2) {
            hg_args[hg_ac] = hg_ch;
            hg_ch = pool[@as(usize, @intCast(hg_ch))].next_sibling;
            hg_ac += 1;
        }
        if (hg_args[0] != parser_mod.NO_NODE) {
            compileExprNode(hg_args[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        if (hg_args[1] != parser_mod.NO_NODE) {
            compileExprNode(hg_args[1], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        cb.popR(cg.R9);
        cb.popR(cg.R8);
        cb.movRR(cg.RDI, cg.R8);
        cb.movRR(cg.RSI, cg.R9);
        cb.movRR(cg.RDX, cg.R10);
        cb.movRImm64(cg.RAX, @intFromPtr(&tls_mod.httpsGetPacked));
        cb.byte(0xFF);
        cb.modrm(3, 2, 0);
        return;
    }
    if (eq(name, "tls_get_buf") or eq(name, "tls.buf") or eq(name, "tls_buf")) {
        cb.movRImm64(cg.RAX, @intFromPtr(&tls_mod.tls_response_data));
        return;
    }
    if (eq(name, "tls_get_len") or eq(name, "tls.len") or eq(name, "tls_len")) {
        cb.movRImm64(cg.RAX, @intFromPtr(&tls_mod.tls_response_len));
        cb.movRMem64(cg.RAX, cg.RAX, 0);
        return;
    }
    if (eq(name, "https.get_file") or eq(name, "https_get_file") or eq(name, "tls_get_file") or eq(name, "http_download")) {
        var dl_args: [3]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 3;
        var dl_ac: usize = 0;
        var dl_ch = n.first_child;
        while (dl_ch != parser_mod.NO_NODE and dl_ac < 3) {
            dl_args[dl_ac] = dl_ch;
            dl_ch = pool[@as(usize, @intCast(dl_ch))].next_sibling;
            dl_ac += 1;
        }
        if (dl_args[0] == parser_mod.NO_NODE or dl_args[1] == parser_mod.NO_NODE or dl_args[2] == parser_mod.NO_NODE) {
            cb.xorRR(cg.RAX, cg.RAX); return;
        }
        compileExprNode(dl_args[0], pool, cb, vars, vc, errs); // host
        cb.pushR(cg.RAX);
        compileExprNode(dl_args[1], pool, cb, vars, vc, errs); // path
        cb.pushR(cg.RAX);
        compileExprNode(dl_args[2], pool, cb, vars, vc, errs); // filename
        cb.pushR(cg.RAX);
        cb.popR(cg.RDX); // filename
        cb.popR(cg.RSI); // path
        cb.popR(cg.RDI); // host
        cb.movRImm64(cg.RAX, @intFromPtr(&tls_mod.httpsGetToFile));
        cb.byte(0xFF);
        cb.modrm(3, 2, 0);
        return;
    }
    if (eq(name, "https.post") or eq(name, "https_post") or eq(name, "httpspost") or
        eq(name, "tls.post") or eq(name, "tls_post") or eq(name, "tlspost"))
    {
        var hp_args: [3]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 3;
        var hp_ac: usize = 0;
        var hp_ch = n.first_child;
        while (hp_ch != parser_mod.NO_NODE and hp_ac < 3) {
            hp_args[hp_ac] = hp_ch;
            hp_ch = pool[@as(usize, @intCast(hp_ch))].next_sibling;
            hp_ac += 1;
        }
        if (hp_args[0] != parser_mod.NO_NODE) {
            compileExprNode(hp_args[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        if (hp_args[1] != parser_mod.NO_NODE) {
            compileExprNode(hp_args[1], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        if (hp_args[2] != parser_mod.NO_NODE) {
            compileExprNode(hp_args[2], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX);
        cb.popR(cg.R10);
        cb.popR(cg.R9);
        cb.popR(cg.R8);
        cb.movRR(cg.RDI, cg.R8);
        cb.movRR(cg.RSI, cg.R9);
        cb.movRR(cg.RDX, cg.R10);
        cb.movRImm64(cg.RAX, @intFromPtr(&tls_mod.httpsPostPacked));
        cb.byte(0xFF);
        cb.modrm(3, 2, 0);
        return;
    }
    if (eq(name, "http.get") or eq(name, "http_get") or eq(name, "httpget")) {
        var hg_args: [2]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 2;
        var hg_ac: usize = 0;
        var hg_ch = n.first_child;
        while (hg_ch != parser_mod.NO_NODE and hg_ac < 2) {
            hg_args[hg_ac] = hg_ch;
            hg_ch = pool[@as(usize, @intCast(hg_ch))].next_sibling;
            hg_ac += 1;
        }
        if (hg_args[0] != parser_mod.NO_NODE) {
            compileExprNode(hg_args[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // host
        if (hg_args[1] != parser_mod.NO_NODE) {
            compileExprNode(hg_args[1], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // path
        cb.popR(cg.R9); // R9 = path
        cb.popR(cg.R8); // R8 = host
        cb.xorRR(cg.R10, cg.R10);
        emitInlineHttpX64(cb, false, 0xFF);
        return;
    }
    if (eq(name, "http_get_ex") or eq(name, "httpgetex")) {
        var hx_args: [3]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 3;
        var hx_ac: usize = 0;
        var hx_ch = n.first_child;
        while (hx_ch != parser_mod.NO_NODE and hx_ac < 3) {
            hx_args[hx_ac] = hx_ch;
            hx_ch = pool[@as(usize, @intCast(hx_ch))].next_sibling;
            hx_ac += 1;
        }
        if (hx_args[0] != parser_mod.NO_NODE) {
            compileExprNode(hx_args[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // host
        if (hx_args[1] != parser_mod.NO_NODE) {
            compileExprNode(hx_args[1], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // path
        if (hx_args[2] != parser_mod.NO_NODE) {
            compileExprNode(hx_args[2], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // headers (top)
        cb.popR(cg.R10); // R10 = headers
        cb.popR(cg.R9); // R9 = path
        cb.popR(cg.R8); // R8 = host
        cb.xorRR(cg.R11, cg.R11); // R11 = 0 (no body)
        emitInlineHttpX64(cb, false, cg.R10);
        return;
    }
    if (eq(name, "http.post") or eq(name, "http_post") or eq(name, "httppost") or eq(name, "http.post")) {
        var hp_args: [3]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 3;
        var hp_ac: usize = 0;
        var hp_ch = n.first_child;
        while (hp_ch != parser_mod.NO_NODE and hp_ac < 3) {
            hp_args[hp_ac] = hp_ch;
            hp_ch = pool[@as(usize, @intCast(hp_ch))].next_sibling;
            hp_ac += 1;
        }
        if (hp_args[0] != parser_mod.NO_NODE) {
            compileExprNode(hp_args[0], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // host (deepest)
        if (hp_args[1] != parser_mod.NO_NODE) {
            compileExprNode(hp_args[1], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // path
        if (hp_args[2] != parser_mod.NO_NODE) {
            compileExprNode(hp_args[2], pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // body (top)
        cb.popR(cg.R10); // R10 = body
        cb.popR(cg.R9); // R9 = path
        cb.popR(cg.R8); // R8 = host
        emitInlineHttpX64(cb, true, 0xFF);
        return;
    }
    if (eq(name, "x11_open") or eq(name, "x11Open") or eq(name, "gui_open")) {
        var args: [3]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 3;
        var ac: usize = 0;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and ac < 3) {
            args[ac] = ch;
            ac += 1;
            ch = pool[@as(usize, @intCast(ch))].next_sibling;
        }
        if (ac < 3) { cb.xorRR(cg.RAX, cg.RAX); return; }
        compileExprNode(args[0], pool, cb, vars, vc, errs); // w
        cb.pushR(cg.RAX);
        compileExprNode(args[1], pool, cb, vars, vc, errs); // h
        cb.pushR(cg.RAX);
        compileExprNode(args[2], pool, cb, vars, vc, errs); // title
        cb.popR(cg.R9); // title
        cb.popR(cg.R8); // h
        cb.popR(cg.RDI); // w
        // note: need to move 2nd arg (h) to RSI, 3rd (title) to RDX
        cb.movRR(cg.RSI, cg.R8);
        cb.movRR(cg.RDX, cg.R9);
        emitInlineX11Open(cb);
        return;
    }
    if (eq(name, "gui_present") or eq(name, "present")) {
        const ch = n.first_child;
        if (ch != parser_mod.NO_NODE) {
            compileExprNode(ch, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.movRR(cg.RDI, cg.RAX);
        emitInlineX11Present(cb);
        return;
    }
    if (eq(name, "gui_poll_event") or eq(name, "poll_event")) {
        const pe_ch = n.first_child;
        if (pe_ch != parser_mod.NO_NODE) {
            compileExprNode(pe_ch, pool, cb, vars, vc, errs);
        } else {
            cb.xorRR(cg.RAX, cg.RAX);
        }
        cb.pushR(cg.RAX); // save disp (ignored on Android)
        // Detect platform: read has_window at 0x200100+24
        cb.movRImm64(cg.RDI, 0x200100);
        cb.movRMem32(cg.RAX, cg.RDI, 24);
        cb.cmpRImm32(cg.RAX, 0);
        const pe_je = cb.pos;
        cb.jeRel32(0); // if zero → X11 path (will patch)
        // --- Android path ---
        // RDI still = 0x200100
        cb.movRMem32(cg.RAX, cg.RDI, 508); // event_cursor
        cb.movRMem32(cg.RBX, cg.RDI, 168); // touch_count
        cb.cmpRR(cg.RAX, cg.RBX);
        const pe_jge = cb.pos;
        cb.jgeRel32(0); // if cursor >= touch_count → key check (will patch)
// --- Touch service (fall through) ---
        cb.pushR(cg.RAX); // save cursor
        cb.movRImm64(cg.R9, 4);
        cb.imulRR(cg.R9, cg.RAX); // offset = cursor * 4
        // touch_x_arr at 172 -> store to touch_x at 56
        cb.movRImm64(cg.RDI, 0x200100 + 172);
        cb.addRR(cg.RDI, cg.R9);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        cb.movRImm64(cg.RDI, 0x200100 + 56);
        cb.movMemR32(cg.RDI, 0, cg.RAX);
        // touch_y_arr at 236 -> store to touch_y at 60
        cb.movRImm64(cg.RDI, 0x200100 + 236);
        cb.addRR(cg.RDI, cg.R9);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        cb.movRImm64(cg.RDI, 0x200100 + 60);
        cb.movMemR32(cg.RDI, 0, cg.RAX);
        // touch_down_arr at 300 -> store to touch_down at 64
        cb.movRImm64(cg.RDI, 0x200100 + 300);
        cb.addRR(cg.RDI, cg.R9);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        cb.movRImm64(cg.RDI, 0x200100 + 64);
        cb.movMemR32(cg.RDI, 0, cg.RAX);
        // touch_action_arr at 364 -> store to touch_action at 68
        cb.movRImm64(cg.RDI, 0x200100 + 364);
        cb.addRR(cg.RDI, cg.R9);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        cb.movRImm64(cg.RDI, 0x200100 + 68);
        cb.movMemR32(cg.RDI, 0, cg.RAX);
        // touch_id_arr at 428 -> store to touch_pointer_id at 72
        cb.movRImm64(cg.RDI, 0x200100 + 428);
        cb.addRR(cg.RDI, cg.R9);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        cb.movRImm64(cg.RDI, 0x200100 + 72);
        cb.movMemR32(cg.RDI, 0, cg.RAX);
        // Set cur_ev_type = action + 1 (1=down,2=up,3=move)
        cb.movRImm64(cg.RDI, 0x200100 + 68);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        cb.addRImm32(cg.RAX, 1);
        cb.movRImm64(cg.RDI, 0x200100 + 504);
        cb.movMemR32(cg.RDI, 0, cg.RAX);
        // Increment event_cursor
        cb.popR(cg.RAX); // restore cursor
        cb.addRImm32(cg.RAX, 1);
        cb.movRImm64(cg.RDI, 0x200100 + 508);
        cb.movMemR32(cg.RDI, 0, cg.RAX);
        // Return cur_ev_type
        cb.movRImm64(cg.RDI, 0x200100 + 504);
        cb.movRMem32(cg.RAX, cg.RDI, 0);
        cb.popR(cg.R9); // discard saved disp
        const pe_jmp = cb.pos;
        cb.jmpRel32(0); // jump to end
// --- Key check (patch jge target) ---
        const key_check = cb.pos;
        patch32(cb, pe_jge + 2, @as(i32, @intCast(key_check)) - @as(i32, @intCast(pe_jge + 6)));
        cb.movRImm64(cg.RDI, 0x200100);
        cb.movRMem32(cg.RAX, cg.RDI, 76); // key_action
        cb.cmpRImm32(cg.RAX, 0);
        const pe_je2 = cb.pos;
        cb.jeRel32(0); // no key event -> end
        // Have key event: set cur_ev_type = 4 + key_action (4=down,5=up)
        cb.addRImm32(cg.RAX, 4);
        cb.movMemR32(cg.RDI, 504, cg.RAX);
        // Increment event_cursor
        cb.movRMem32(cg.RAX, cg.RDI, 508);
        cb.addRImm32(cg.RAX, 1);
        cb.movMemR32(cg.RDI, 508, cg.RAX);
        // Return cur_ev_type
        cb.movRMem32(cg.RAX, cg.RDI, 504);
        cb.popR(cg.R9); // discard saved disp
        const pe_jmp2 = cb.pos;
        cb.jmpRel32(0); // jump to end
// --- X11 path (patch je target) ---
        const x11_path = cb.pos;
        patch32(cb, pe_je + 2, @as(i32, @intCast(x11_path)) - @as(i32, @intCast(pe_je + 6)));
        cb.popR(cg.RDI); // restore disp from saved arg
        emitInlineX11PollEvent(cb);
// --- End ---
        const pe_end = cb.pos;
        patch32(cb, pe_jmp + 1, @as(i32, @intCast(pe_end)) - @as(i32, @intCast(pe_jmp + 5)));
        patch32(cb, pe_jmp2 + 1, @as(i32, @intCast(pe_end)) - @as(i32, @intCast(pe_jmp2 + 5)));
        patch32(cb, pe_je2 + 2, @as(i32, @intCast(pe_end)) - @as(i32, @intCast(pe_je2 + 6)));
        return;
    }
    if (eq(name, "str_get")) {
        // str_get(s, pos) -> byte at s[pos] (zero-extended to hui)
        // Reads a single byte from string s at offset pos
        var arg_count: usize = 0;
        var args: [2]parser_mod.NodeIdx = .{parser_mod.NO_NODE} ** 2;
        var ch = n.first_child;
        while (ch != parser_mod.NO_NODE and arg_count < 2) {
            args[arg_count] = ch;
            arg_count += 1;
            ch = pool[@as(usize, @intCast(ch))].next_sibling;
        }
        compileExprNode(args[0], pool, cb, vars, vc, errs);
        cb.pushR(cg.RAX);
        compileExprNode(args[1], pool, cb, vars, vc, errs);
        cb.pushR(cg.RAX);
        cb.popR(cg.RSI);  // RSI = pos (second arg)
        cb.popR(cg.RDI);  // RDI = s (first arg)
        // movzx rax, byte [rdi + rsi]
        cb.byte(0x48); // REX.W
        cb.byte(0x0F);
        cb.byte(0xB6);
        cb.byte(0x04); // modrm: mod=00, reg=0(RAX), r/m=4(SIB)
        cb.byte(0x37); // SIB: scale=0(x1), index=6(RSI), base=7(RDI)
        return;
    }
    // User-defined function call
    {
        var fi: usize = 0;
        var found: bool = false;
        while (fi < fn_count) : (fi += 1) {
            if (eq(name, fn_names[fi])) {
                found = true;
                break;
            }
        }
        if (found) {
            const call_regs = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.RCX, cg.R8, cg.R9 };
            // Count and evaluate arguments, push onto stack
            var arg_count: usize = 0;
            var ch = n.first_child;
            while (ch != parser_mod.NO_NODE) {
                compileExprNode(ch, pool, cb, vars, vc, errs);
                cb.pushR(cg.RAX);
                arg_count += 1;
                ch = pool[@as(usize, @intCast(ch))].next_sibling;
            }
            // Pop into argument registers in reverse order
            var ai: usize = arg_count;
            while (ai > 0) {
                ai -= 1;
                if (ai < 6) {
                    cb.popR(call_regs[ai]);
                } else {
                    cb.addRImm32(cg.RSP, 8);
                }
            }
            // Emit call with placeholder offset, record relocation
            if (reloc_count < MAX_RELOCS) {
                reloc_callpos[reloc_count] = cb.pos;
                cb.callRel32(0);
                reloc_target_idx[reloc_count] = fi;
                reloc_count += 1;
            } else {
                cb.movRImm64(cg.RAX, 0);
            }
        } else {
            // Check if name is a variable (function pointer call)
            const var_off = findVarOffset(vars, vc.*, name);
            const global_off = findGlobalOffset(name);
            if (var_off) |voff| {
                // Load function pointer from local variable into R10
                cb.movRMem64(cg.R10, cg.RBP, voff);
                // Evaluate arguments, push onto stack
                const call_regs_fp = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.RCX, cg.R8, cg.R9 };
                var arg_count_fp: usize = 0;
                var ch_fp = n.first_child;
                while (ch_fp != parser_mod.NO_NODE) {
                    compileExprNode(ch_fp, pool, cb, vars, vc, errs);
                    cb.pushR(cg.RAX);
                    arg_count_fp += 1;
                    ch_fp = pool[@as(usize, @intCast(ch_fp))].next_sibling;
                }
                var ai_fp: usize = arg_count_fp;
                while (ai_fp > 0) {
                    ai_fp -= 1;
                    if (ai_fp < 6) {
                        cb.popR(call_regs_fp[ai_fp]);
                    } else {
                        cb.addRImm32(cg.RSP, 8);
                    }
                }
                // Call through RAX
                cb.movRR(cg.RAX, cg.R10);
                cb.byte(0xFF);
                cb.modrm(3, 2, 0);
            } else if (global_off) |goff| {
                // Load function pointer from global variable into R10
                emitGlobalLoad(cb, goff);
                cb.movRR(cg.R10, cg.RAX);
                // Evaluate arguments, push onto stack
                const call_regs_fp = [_]u8{ cg.RDI, cg.RSI, cg.RDX, cg.RCX, cg.R8, cg.R9 };
                var arg_count_fp: usize = 0;
                var ch_fp = n.first_child;
                while (ch_fp != parser_mod.NO_NODE) {
                    compileExprNode(ch_fp, pool, cb, vars, vc, errs);
                    cb.pushR(cg.RAX);
                    arg_count_fp += 1;
                    ch_fp = pool[@as(usize, @intCast(ch_fp))].next_sibling;
                }
                var ai_fp: usize = arg_count_fp;
                while (ai_fp > 0) {
                    ai_fp -= 1;
                    if (ai_fp < 6) {
                        cb.popR(call_regs_fp[ai_fp]);
                    } else {
                        cb.addRImm32(cg.RSP, 8);
                    }
                }
                // Call through RAX
                cb.movRR(cg.RAX, cg.R10);
                cb.byte(0xFF);
                cb.modrm(3, 2, 0);
            } else {
                cb.movRImm64(cg.RAX, 0);
            }
        }
    }
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
    if (arr == parser_mod.NO_NODE or idx == parser_mod.NO_NODE) {
        cb.xorRR(cg.RAX, cg.RAX);
        return;
    }

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
    _ = _n;
    _ = _pool;
    _ = _vars;
    _ = _vc;
    _ = _errs;
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

    // Save vc/stack_off so both branches share same variable slots
    const then_vc = vc.*;
    const then_so = stack_off.*;

    if (then_blk != parser_mod.NO_NODE) compileStmt(then_blk, pool, cb, vars, vc, stack_off, errs, has_return);

    // Restore vc/stack_off for else branch (same slots as then-branch's start)
    const then_end_vc = vc.*;
    vc.* = then_vc;
    stack_off.* = then_so;

    var has_else = false;
    const jmp_pos = cb.pos;
    if (else_blk != parser_mod.NO_NODE) {
        has_else = true;
        cb.jmpRel32(0);
    }

    const else_pos = cb.pos;
    patch32(cb, je_pos + 2, @as(i32, @intCast(else_pos)) - @as(i32, @intCast(after_cond)));

    if (else_blk != parser_mod.NO_NODE) compileStmt(else_blk, pool, cb, vars, vc, stack_off, errs, has_return);

    // Keep the larger vc from either branch so vars declared in both are visible after
    if (vc.* < then_end_vc) vc.* = then_end_vc;

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

    // Push loop context
    const ld = loop_depth;
    if (ld < 16) {
        loop_start_stack[ld] = loop_pos;
        loop_break_count[ld] = 0;
    }
    loop_depth += 1;

    if (body != parser_mod.NO_NODE) compileStmt(body, pool, cb, vars, vc, stack_off, errs, has_return);

    // Pop loop context
    loop_depth -= 1;

    const back_off = @as(i32, @intCast(loop_pos)) - @as(i32, @intCast(cb.pos + 5));
    cb.jmpRel32(back_off);

    const end_pos = cb.pos;

    // Patch break jumps
    if (ld < 16) {
        var bi: usize = 0;
        while (bi < loop_break_count[ld]) : (bi += 1) {
            const jmp_pos = loop_break_jmps[ld][bi];
            patch32(cb, jmp_pos + 1, @as(i32, @intCast(end_pos)) - @as(i32, @intCast(jmp_pos + 5)));
        }
    }

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

fn findColor(name: []const u8) ?u64 {
    const colors = [_]struct { name: []const u8, val: u64 }{
        .{ .name = "black", .val = 0xFF000000 },
        .{ .name = "white", .val = 0xFFFFFFFF },
        .{ .name = "red", .val = 0xFFFF0000 },
        .{ .name = "green", .val = 0xFF00FF00 },
        .{ .name = "blue", .val = 0xFF0000FF },
        .{ .name = "yellow", .val = 0xFFFFFF00 },
        .{ .name = "cyan", .val = 0xFF00FFFF },
        .{ .name = "magenta", .val = 0xFFFF00FF },
        .{ .name = "silver", .val = 0xFFC0C0C0 },
        .{ .name = "gray", .val = 0xFF808080 },
        .{ .name = "grey", .val = 0xFF808080 },
        .{ .name = "maroon", .val = 0xFF800000 },
        .{ .name = "olive", .val = 0xFF808000 },
        .{ .name = "purple", .val = 0xFF800080 },
        .{ .name = "teal", .val = 0xFF008080 },
        .{ .name = "navy", .val = 0xFF000080 },
        .{ .name = "orange", .val = 0xFFFFA500 },
        .{ .name = "pink", .val = 0xFFFFC0CB },
        .{ .name = "brown", .val = 0xFFA52A2A },
        .{ .name = "lime", .val = 0xFF00FF00 },
        .{ .name = "indigo", .val = 0xFF4B0082 },
        .{ .name = "violet", .val = 0xFFEE82EE },
        .{ .name = "gold", .val = 0xFFFFD700 },
        .{ .name = "coral", .val = 0xFFFF7F50 },
        .{ .name = "salmon", .val = 0xFFFA8072 },
        .{ .name = "khaki", .val = 0xFFF0E68C },
        .{ .name = "plum", .val = 0xFFDDA0DD },
        .{ .name = "orchid", .val = 0xFFDA70D6 },
        .{ .name = "turquoise", .val = 0xFF40E0D0 },
        .{ .name = "tan", .val = 0xFFD2B48C },
        .{ .name = "tomato", .val = 0xFFFF6347 },
        .{ .name = "wheat", .val = 0xFFF5DEB3 },
        .{ .name = "beige", .val = 0xFFF5F5DC },
        .{ .name = "ivory", .val = 0xFFFFFFF0 },
        .{ .name = "linen", .val = 0xFFFAF0E6 },
        .{ .name = "lavender", .val = 0xFFE6E6FA },
        .{ .name = "mint", .val = 0xFF98FF98 },
        .{ .name = "peach", .val = 0xFFFFDAB9 },
        .{ .name = "apricot", .val = 0xFFFBCEB1 },
        .{ .name = "crimson", .val = 0xFFDC143C },
        .{ .name = "firebrick", .val = 0xFFB22222 },
        .{ .name = "darkred", .val = 0xFF8B0000 },
        .{ .name = "darkgreen", .val = 0xFF006400 },
        .{ .name = "darkblue", .val = 0xFF00008B },
        .{ .name = "darkcyan", .val = 0xFF008B8B },
        .{ .name = "darkmagenta", .val = 0xFF8B008B },
        .{ .name = "darkgray", .val = 0xFFA9A9A9 },
        .{ .name = "lightgray", .val = 0xFFD3D3D3 },
        .{ .name = "midnightblue", .val = 0xFF191970 },
        .{ .name = "skyblue", .val = 0xFF87CEEB },
        .{ .name = "steelblue", .val = 0xFF4682B4 },
        .{ .name = "royalblue", .val = 0xFF4169E1 },
        .{ .name = "slateblue", .val = 0xFF6A5ACD },
        .{ .name = "forestgreen", .val = 0xFF228B22 },
        .{ .name = "seagreen", .val = 0xFF2E8B57 },
        .{ .name = "springgreen", .val = 0xFF00FF7F },
        .{ .name = "chartreuse", .val = 0xFF7FFF00 },
        .{ .name = "darkorange", .val = 0xFFFF8C00 },
        .{ .name = "cornsilk", .val = 0xFFFFF8DC },
        .{ .name = "blanchedalmond", .val = 0xFFFFEBCD },
        .{ .name = "bisque", .val = 0xFFFFE4C4 },
        .{ .name = "navajowhite", .val = 0xFFFFDEAD },
        .{ .name = "snow", .val = 0xFFFFFAFA },
        .{ .name = "honeydew", .val = 0xFFF0FFF0 },
        .{ .name = "azure", .val = 0xFFF0FFFF },
    };
    for (colors) |c| {
        if (eq(name, c.name)) return c.val;
    }
    return null;
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

fn findGlobalOffset(name: []const u8) ?u64 {
    var i: usize = 0;
    while (i < gvc) : (i += 1) {
        if (eq(gvars[i].name, name)) return gv_offsets[i];
    }
    return null;
}

fn findGlobalVarIndex(name: []const u8) ?usize {
    var i: usize = 0;
    while (i < gvc) : (i += 1) {
        if (eq(gvars[i].name, name)) return i;
    }
    return null;
}

fn emitGlobalLoad(cb: *cg.CodeBuffer, goff: u64) void {
    if (gv_reloc_count < MAX_GV_RELOCS) {
        gv_reloc_pos[gv_reloc_count] = cb.pos + 3;
        gv_reloc_data_off[gv_reloc_count] = goff;
        gv_reloc_count += 1;
    }
    cb.rex_wb(0, 0);
    cb.byte(0x8B);
    cb.modrm(0, 0, 5);
    cb.dword(0);
}

fn emitGlobalStore(cb: *cg.CodeBuffer, goff: u64) void {
    if (gv_reloc_count < MAX_GV_RELOCS) {
        gv_reloc_pos[gv_reloc_count] = cb.pos + 3;
        gv_reloc_data_off[gv_reloc_count] = goff;
        gv_reloc_count += 1;
    }
    cb.rex_wb(0, 0);
    cb.byte(0x89);
    cb.modrm(0, 0, 5);
    cb.dword(0);
}

fn emitGlobalAddr(cb: *cg.CodeBuffer, goff: u64) void {
    if (gv_reloc_count < MAX_GV_RELOCS) {
        gv_reloc_pos[gv_reloc_count] = cb.pos + 3;
        gv_reloc_data_off[gv_reloc_count] = goff;
        gv_reloc_count += 1;
    }
    cb.rex_wb(0, 0);
    cb.byte(0x8D);
    cb.modrm(0, 0, 5);
    cb.dword(0);
}

fn patch32(cb: *cg.CodeBuffer, pos: usize, off: i32) void {
    if (pos + 4 > cb.buf.len) return;
    cb.buf[pos] = @as(u8, @truncate(@as(u32, @bitCast(off))));
    cb.buf[pos + 1] = @as(u8, @truncate(@as(u32, @bitCast(off >> 8))));
    cb.buf[pos + 2] = @as(u8, @truncate(@as(u32, @bitCast(off >> 16))));
    cb.buf[pos + 3] = @as(u8, @truncate(@as(u32, @bitCast(off >> 24))));
}

const NO_NODE: parser_mod.NodeIdx = -1;
