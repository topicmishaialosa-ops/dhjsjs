pub const CodeBuffer = struct {
    buf: [65536]u8,
    len: usize,

    pub fn init() CodeBuffer {
        return CodeBuffer{ .buf = undefined, .len = 0 };
    }

    pub fn get(self: *CodeBuffer) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn byte(self: *CodeBuffer, b: u8) void {
        self.buf[self.len] = b;
        self.len += 1;
    }

    pub fn w16(self: *CodeBuffer, w: u16) void {
        self.byte(@as(u8, @truncate(w)));
        self.byte(@as(u8, @truncate(w >> 8)));
    }

    pub fn w32(self: *CodeBuffer, dw: u32) void {
        self.byte(@as(u8, @truncate(dw)));
        self.byte(@as(u8, @truncate(dw >> 8)));
        self.byte(@as(u8, @truncate(dw >> 16)));
        self.byte(@as(u8, @truncate(dw >> 24)));
    }

    pub fn lui(self: *CodeBuffer, rd: u8, imm20: u32) void {
        self.w32(0x37 | (@as(u32, rd) & 0x1F) | ((imm20 & 0xFFFFF) << 12));
    }

    pub fn addi(self: *CodeBuffer, rd: u8, rs1: u8, imm12: i32) void {
        self.w32(0x13 | ((@as(u32, rd) & 0x1F) << 7) | ((@as(u32, rs1) & 0x1F) << 15) | ((@as(u32, @bitCast(imm12)) & 0xFFF) << 20));
    }

    fn i_type(self: *CodeBuffer, opcode: u32, rd: u8, rs1: u8, imm12: u32) void {
        self.w32(opcode | ((@as(u32, rd) & 0x1F) << 7) | ((@as(u32, rs1) & 0x1F) << 15) | ((imm12 & 0xFFF) << 20));
    }

    fn r_type(self: *CodeBuffer, funct7: u32, rd: u8, rs1: u8, rs2: u8, funct3: u32) void {
        self.w32(0x33 | ((@as(u32, rd) & 0x1F) << 7) | ((funct3 & 0x7) << 12) | ((@as(u32, rs1) & 0x1F) << 15) | ((@as(u32, rs2) & 0x1F) << 20) | ((funct7 & 0x7F) << 25));
    }

    pub fn slti(self: *CodeBuffer, rd: u8, rs1: u8, imm12: i32) void { self.i_type(0x13, rd, rs1, @as(u32, @bitCast(imm12)) | (0x2 << 12)); }
    pub fn sltiu(self: *CodeBuffer, rd: u8, rs1: u8, imm12: i32) void { self.i_type(0x13, rd, rs1, @as(u32, @bitCast(imm12)) | (0x3 << 12)); }
    pub fn xori(self: *CodeBuffer, rd: u8, rs1: u8, imm12: i32) void { self.i_type(0x13, rd, rs1, @as(u32, @bitCast(imm12)) | (0x4 << 12)); }
    pub fn ori(self: *CodeBuffer, rd: u8, rs1: u8, imm12: i32) void { self.i_type(0x13, rd, rs1, @as(u32, @bitCast(imm12)) | (0x6 << 12)); }
    pub fn andi(self: *CodeBuffer, rd: u8, rs1: u8, imm12: i32) void { self.i_type(0x13, rd, rs1, @as(u32, @bitCast(imm12)) | (0x7 << 12)); }

    pub fn slli(self: *CodeBuffer, rd: u8, rs1: u8, shamt: u8) void { self.i_type(0x13, rd, rs1, (@as(u32, shamt) & 0x1F) | (0x1 << 12)); }
    pub fn srli(self: *CodeBuffer, rd: u8, rs1: u8, shamt: u8) void { self.i_type(0x13, rd, rs1, (@as(u32, shamt) & 0x1F) | (0x5 << 12)); }
    pub fn srai(self: *CodeBuffer, rd: u8, rs1: u8, shamt: u8) void { self.i_type(0x13, rd, rs1, (@as(u32, shamt) & 0x1F) | (0x5 << 12) | (0x400 << 20)); }

    pub fn add(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void { self.r_type(0, rd, rs1, rs2, 0); }
    pub fn sub(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void { self.r_type(0x20, rd, rs1, rs2, 0); }
    pub fn slt(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void { self.r_type(0, rd, rs1, rs2, 2); }
    pub fn sltu(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void { self.r_type(0, rd, rs1, rs2, 3); }
    pub fn xor_(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void { self.r_type(0, rd, rs1, rs2, 4); }
    pub fn or_(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void { self.r_type(0, rd, rs1, rs2, 6); }
    pub fn and_(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void { self.r_type(0, rd, rs1, rs2, 7); }
    pub fn sll(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void { self.r_type(0, rd, rs1, rs2, 1); }
    pub fn srl(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void { self.r_type(0, rd, rs1, rs2, 5); }
    pub fn sra(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void { self.r_type(0x20, rd, rs1, rs2, 5); }

    pub fn mul(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void { self.r_type(1, rd, rs1, rs2, 0); }
    pub fn mulh(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void { self.r_type(1, rd, rs1, rs2, 1); }
    pub fn div(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void { self.r_type(0x200, rd, rs1, rs2, 0); }
    pub fn rem(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void { self.r_type(0x600, rd, rs1, rs2, 0); }

    pub fn mv(self: *CodeBuffer, rd: u8, rs1: u8) void { self.addi(rd, rs1, 0); }
    pub fn neg(self: *CodeBuffer, rd: u8, rs1: u8) void { self.sub(rd, ZERO, rs1); }
    pub fn not_(self: *CodeBuffer, rd: u8, rs1: u8) void { self.xori(rd, rs1, -1); }
    pub fn seqz(self: *CodeBuffer, rd: u8, rs1: u8) void { self.sltiu(rd, rs1, 1); }
    pub fn snez(self: *CodeBuffer, rd: u8, rs1: u8) void { self.sltu(rd, ZERO, rs1); }

    pub fn li(self: *CodeBuffer, rd: u8, val: i32) void {
        if (val >= -2048 and val <= 2047) {
            self.addi(rd, ZERO, val);
        } else {
            const upper = @as(u32, @bitCast(val)) +% 0x800;
            const hi = @as(u32, @bitCast(upper & 0xFFFFF000));
            if (hi != 0) self.lui(rd, hi >> 12);
            const lo = val -% @as(i32, @bitCast(hi));
            if (lo != 0) self.addi(rd, if (hi != 0) rd else ZERO, lo);
        }
    }

    pub fn lw(self: *CodeBuffer, rd: u8, rs1: u8, off12: i32) void {
        const off = @as(u32, @bitCast(off12)) & 0xFFF;
        self.w32(0x03 | ((@as(u32, rd) & 0x1F) << 7) | (0x2 << 12) | ((@as(u32, rs1) & 0x1F) << 15) | (off << 20));
    }

    pub fn sw(self: *CodeBuffer, rs2: u8, rs1: u8, off12: i32) void {
        const off = @as(u32, @bitCast(off12)) & 0xFFF;
        const enc = 0x23 | ((@as(u32, rs2) & 0x1F) << 20) | ((@as(u32, rs1) & 0x1F) << 15) | (0x2 << 12) | ((off & 0xFE0) << 20) | ((off & 0x1F) << 7);
        self.w32(enc);
    }

    pub fn lb(self: *CodeBuffer, rd: u8, rs1: u8, off12: i32) void {
        const off = @as(u32, @bitCast(off12)) & 0xFFF;
        self.w32(0x03 | ((@as(u32, rd) & 0x1F) << 7) | ((@as(u32, rs1) & 0x1F) << 15) | (off << 20));
    }

    pub fn sb(self: *CodeBuffer, rs2: u8, rs1: u8, off12: i32) void {
        const off = @as(u32, @bitCast(off12)) & 0xFFF;
        const enc = 0x23 | ((@as(u32, rs2) & 0x1F) << 20) | ((@as(u32, rs1) & 0x1F) << 15) | ((off & 0xFE0) << 20) | ((off & 0x1F) << 7);
        self.w32(enc);
    }

    pub fn beq(self: *CodeBuffer, rs1: u8, rs2: u8) void {
        self.w32(0x63 | ((@as(u32, rs1) & 0x1F) << 15) | ((@as(u32, rs2) & 0x1F) << 20));
    }

    pub fn bne(self: *CodeBuffer, rs1: u8, rs2: u8) void {
        self.w32(0x63 | ((@as(u32, rs1) & 0x1F) << 15) | ((@as(u32, rs2) & 0x1F) << 20) | (0x1 << 12));
    }

    pub fn blt(self: *CodeBuffer, rs1: u8, rs2: u8) void {
        self.w32(0x63 | ((@as(u32, rs1) & 0x1F) << 15) | ((@as(u32, rs2) & 0x1F) << 20) | (0x4 << 12));
    }

    pub fn bge(self: *CodeBuffer, rs1: u8, rs2: u8) void {
        self.w32(0x63 | ((@as(u32, rs1) & 0x1F) << 15) | ((@as(u32, rs2) & 0x1F) << 20) | (0x5 << 12));
    }

    pub fn jal(self: *CodeBuffer, rd: u8) void {
        self.w32(0x6F | ((@as(u32, rd) & 0x1F) << 7));
    }

    pub fn jalr(self: *CodeBuffer, rd: u8, rs1: u8, off12: i32) void {
        self.w32(0x67 | ((@as(u32, rd) & 0x1F) << 7) | ((@as(u32, rs1) & 0x1F) << 15) | (@as(u32, @bitCast(off12)) & 0xFFF) << 20);
    }

    pub fn ecall(self: *CodeBuffer) void { self.w32(0x00000073); }

    pub fn ret(self: *CodeBuffer) void {
        self.jalr(ZERO, RA, 0);
    }

    pub fn pushR(self: *CodeBuffer, r: u8) void {
        self.sw(r, SP, -4);
        self.addi(SP, SP, -4);
    }

    pub fn popR(self: *CodeBuffer, r: u8) void {
        self.lw(r, SP, 0);
        self.addi(SP, SP, 4);
    }

    pub fn patchBranch(self: *CodeBuffer, pos: usize, target: usize) void {
        const off = @as(i32, @intCast(target)) - @as(i32, @intCast(pos));
        const imm = @as(u32, @bitCast(off)) & 0x1FFE;
        const orig = @as(u32, @bitCast([_]u8{
            self.buf[pos], self.buf[pos + 1],
            self.buf[pos + 2], self.buf[pos + 3],
        }));
        const rs1 = (orig >> 15) & 0x1F;
        const rs2 = (orig >> 20) & 0x1F;
        const funct3 = (orig >> 12) & 0x7;
        const enc = 0x63
            | (funct3 << 12)
            | (rs1 << 15)
            | (rs2 << 20)
            | ((imm >> 12 & 0x1) << 31)
            | ((imm >> 5 & 0x3F) << 25)
            | ((imm >> 1 & 0xF) << 8)
            | ((imm >> 11 & 0x1) << 7);
        self.buf[pos + 0] = @as(u8, @truncate(enc));
        self.buf[pos + 1] = @as(u8, @truncate(enc >> 8));
        self.buf[pos + 2] = @as(u8, @truncate(enc >> 16));
        self.buf[pos + 3] = @as(u8, @truncate(enc >> 24));
    }

    pub fn patchJal(self: *CodeBuffer, pos: usize, target: usize) void {
        const off = @as(i32, @intCast(target)) - @as(i32, @intCast(pos));
        const imm = @as(u32, @bitCast(off)) & 0x1FFFFE;
        const orig = @as(u32, @bitCast([_]u8{
            self.buf[pos], self.buf[pos + 1],
            self.buf[pos + 2], self.buf[pos + 3],
        }));
        const rd = (orig >> 7) & 0x1F;
        const enc = 0x6F
            | (rd << 7)
            | ((imm >> 12 & 0xFF) << 12)
            | ((imm >> 11 & 0x1) << 20)
            | ((imm >> 1 & 0x3FF) << 21)
            | ((imm >> 20 & 0x1) << 31);
        self.buf[pos + 0] = @as(u8, @truncate(enc));
        self.buf[pos + 1] = @as(u8, @truncate(enc >> 8));
        self.buf[pos + 2] = @as(u8, @truncate(enc >> 16));
        self.buf[pos + 3] = @as(u8, @truncate(enc >> 24));
    }

    pub fn buildElf32(self: *CodeBuffer) void {
        const code_len = self.len;
        const base: u32 = 0x10000;
        const phdr_off: u32 = 0x34;
        const code_off_i: u32 = 0x54;
        const total: u32 = code_off_i + @as(u32, @intCast(code_len));
        var out: [65536]u8 = undefined;

        out[0..4].* = [_]u8{ 0x7F, 'E', 'L', 'F' };
        out[4] = 1; out[5] = 1; out[6] = 1; out[7] = 0;
        var i: usize = 8; while (i < 16) : (i += 1) out[i] = 0;
        i = 0; while (i < 2) : (i += 1) out[16 + i] = le16(2)[i];
        i = 0; while (i < 2) : (i += 1) out[18 + i] = le16(0xF3)[i];
        i = 0; while (i < 4) : (i += 1) out[20 + i] = le32(1)[i];
        i = 0; while (i < 4) : (i += 1) out[24 + i] = le32(base + code_off_i)[i];
        i = 0; while (i < 4) : (i += 1) out[28 + i] = le32(phdr_off)[i];
        i = 0; while (i < 4) : (i += 1) out[32 + i] = le32(0)[i];
        i = 0; while (i < 4) : (i += 1) out[36 + i] = le32(0)[i];
        i = 0; while (i < 2) : (i += 1) out[40 + i] = le16(52)[i];
        i = 0; while (i < 2) : (i += 1) out[42 + i] = le16(32)[i];
        i = 0; while (i < 2) : (i += 1) out[44 + i] = le16(1)[i];
        i = 0; while (i < 2) : (i += 1) out[46 + i] = le16(40)[i];
        i = 0; while (i < 2) : (i += 1) out[48 + i] = le16(0)[i];
        i = 0; while (i < 2) : (i += 1) out[50 + i] = le16(0)[i];

        i = 0; while (i < 4) : (i += 1) out[52 + i] = le32(1)[i];
        i = 0; while (i < 4) : (i += 1) out[56 + i] = le32(0)[i];
        i = 0; while (i < 4) : (i += 1) out[60 + i] = le32(base)[i];
        i = 0; while (i < 4) : (i += 1) out[64 + i] = le32(base)[i];
        i = 0; while (i < 4) : (i += 1) out[68 + i] = le32(total)[i];
        i = 0; while (i < 4) : (i += 1) out[72 + i] = le32(total)[i];
        i = 0; while (i < 4) : (i += 1) out[76 + i] = le32(7)[i];
        i = 0; while (i < 4) : (i += 1) out[80 + i] = le32(0x1000)[i];

        i = 84; while (i < code_off_i) : (i += 1) out[i] = 0;
        i = 0; while (i < code_len) : (i += 1) out[code_off_i + i] = self.buf[i];

        self.len = code_off_i + code_len;
        i = 0; while (i < self.len) : (i += 1) self.buf[i] = out[i];
    }
};

pub const ZERO: u8 = 0;
pub const RA: u8 = 1;
pub const SP: u8 = 2;
pub const GP: u8 = 3;
pub const TP: u8 = 4;
pub const T0: u8 = 5;
pub const T1: u8 = 6;
pub const T2: u8 = 7;
pub const FP: u8 = 8;
pub const S0: u8 = 8;
pub const S1: u8 = 9;
pub const A0: u8 = 10;
pub const A1: u8 = 11;
pub const A2: u8 = 12;
pub const A3: u8 = 13;
pub const A4: u8 = 14;
pub const A5: u8 = 15;
pub const A6: u8 = 16;
pub const A7: u8 = 17;
pub const S2: u8 = 18;
pub const S3: u8 = 19;
pub const S4: u8 = 20;
pub const S5: u8 = 21;
pub const S6: u8 = 22;
pub const S7: u8 = 23;
pub const T3: u8 = 28;

fn le32(v: u32) [4]u8 {
    return [_]u8{ @as(u8, @truncate(v)), @as(u8, @truncate(v >> 8)), @as(u8, @truncate(v >> 16)), @as(u8, @truncate(v >> 24)) };
}

fn le16(v: u16) [2]u8 {
    return [_]u8{ @as(u8, @truncate(v)), @as(u8, @truncate(v >> 8)) };
}
