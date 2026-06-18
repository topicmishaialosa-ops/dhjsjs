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
        const enc: u32 = 0x37 | (@as(u32, rd) & 0x1F) | ((imm20 & 0xFFFFF) << 12);
        self.w32(enc);
    }

    pub fn addi(self: *CodeBuffer, rd: u8, rs1: u8, imm12: i32) void {
        const i = @as(u32, @bitCast(imm12));
        const enc: u32 = 0x13 | ((@as(u32, rd) & 0x1F) << 7) | ((@as(u32, rs1) & 0x1F) << 15) | ((i & 0xFFF) << 20);
        self.w32(enc);
    }

    pub fn add(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void {
        const enc: u32 = 0x33 | ((@as(u32, rd) & 0x1F) << 7) | ((@as(u32, rs1) & 0x1F) << 15) | ((@as(u32, rs2) & 0x1F) << 20);
        self.w32(enc);
    }

    pub fn sub(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void {
        const enc: u32 = 0x40000033 | ((@as(u32, rd) & 0x1F) << 7) | ((@as(u32, rs1) & 0x1F) << 15) | ((@as(u32, rs2) & 0x1F) << 20);
        self.w32(enc);
    }

    pub fn xor_(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void {
        const enc: u32 = 0x4033 | ((@as(u32, rd) & 0x1F) << 7) | ((@as(u32, rs1) & 0x1F) << 15) | ((@as(u32, rs2) & 0x1F) << 20);
        self.w32(enc);
    }

    pub fn or_(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void {
        const enc: u32 = 0x6033 | ((@as(u32, rd) & 0x1F) << 7) | ((@as(u32, rs1) & 0x1F) << 15) | ((@as(u32, rs2) & 0x1F) << 20);
        self.w32(enc);
    }

    pub fn and_(self: *CodeBuffer, rd: u8, rs1: u8, rs2: u8) void {
        const enc: u32 = 0x7033 | ((@as(u32, rd) & 0x1F) << 7) | ((@as(u32, rs1) & 0x1F) << 15) | ((@as(u32, rs2) & 0x1F) << 20);
        self.w32(enc);
    }

    pub fn slli(self: *CodeBuffer, rd: u8, rs1: u8, shamt: u8) void {
        const enc: u32 = 0x1013 | ((@as(u32, rd) & 0x1F) << 7) | ((@as(u32, rs1) & 0x1F) << 15) | ((@as(u32, shamt) & 0x1F) << 20);
        self.w32(enc);
    }

    pub fn srli(self: *CodeBuffer, rd: u8, rs1: u8, shamt: u8) void {
        const enc: u32 = 0x5013 | ((@as(u32, rd) & 0x1F) << 7) | ((@as(u32, rs1) & 0x1F) << 15) | ((@as(u32, shamt) & 0x1F) << 20);
        self.w32(enc);
    }

    pub fn mv(self: *CodeBuffer, rd: u8, rs1: u8) void {
        self.addi(rd, rs1, 0);
    }

    pub fn li(self: *CodeBuffer, rd: u8, val: i32) void {
        if (val >= -2048 and val <= 2047) {
            self.addi(rd, 0, val);
        } else {
            const upper = @as(u32, @bitCast(val)) +% 0x800;
            const hi = @as(i32, @bitCast(upper & 0xFFFFF000));
            const lo = val -% hi;
            self.lui(rd, @as(u32, @bitCast(hi >> 12)));
            if (lo != 0) self.addi(rd, rd, lo);
        }
    }

    pub fn ecall(self: *CodeBuffer) void {
        self.w32(0x00000073);
    }

    pub fn ret(self: *CodeBuffer) void {
        self.w32(0x00008067);
    }

    pub fn buildElf32(self: *CodeBuffer) void {
        const code_len = self.len;
        const base: u32 = 0x10000;
        const phdr_off: u32 = 0x34;
        const code_off: u32 = 0x1000;
        const elf_total: u32 = code_off + @as(u32, @intCast(code_len));
        var out: [65536]u8 = undefined;

        out[0..4].* = [_]u8{ 0x7F, 'E', 'L', 'F' };
        out[4] = 1; out[5] = 1; out[6] = 1; out[7] = 0;
        var i: usize = 8; while (i < 16) : (i += 1) out[i] = 0;
        i = 0; while (i < 2) : (i += 1) out[16 + i] = le16(2)[i];
        i = 0; while (i < 2) : (i += 1) out[18 + i] = le16(0xF3)[i];
        i = 0; while (i < 4) : (i += 1) out[20 + i] = le32(1)[i];
        i = 0; while (i < 4) : (i += 1) out[24 + i] = le32(base + code_off)[i];
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
        i = 0; while (i < 4) : (i += 1) out[68 + i] = le32(elf_total)[i];
        i = 0; while (i < 4) : (i += 1) out[72 + i] = le32(elf_total)[i];
        i = 0; while (i < 4) : (i += 1) out[76 + i] = le32(7)[i];
        i = 0; while (i < 4) : (i += 1) out[80 + i] = le32(0x1000)[i];

        i = 84; while (i < code_off) : (i += 1) out[i] = 0;

        i = 0; while (i < code_len) : (i += 1) out[code_off + i] = self.buf[i];

        self.len = code_off + code_len;
        i = 0; while (i < self.len) : (i += 1) self.buf[i] = out[i];
    }
};

pub const X0: u8 = 0;
pub const X1: u8 = 1;
pub const X2: u8 = 2;
pub const X3: u8 = 3;
pub const X4: u8 = 4;
pub const X5: u8 = 5;
pub const X6: u8 = 6;
pub const X7: u8 = 7;
pub const X8: u8 = 8;
pub const X9: u8 = 9;
pub const X10: u8 = 10;
pub const X11: u8 = 11;
pub const X12: u8 = 12;
pub const X13: u8 = 13;
pub const X14: u8 = 14;
pub const X15: u8 = 15;
pub const X16: u8 = 16;
pub const X17: u8 = 17;
pub const X28: u8 = 28;
pub const X29: u8 = 29;
pub const X30: u8 = 30;
pub const X31: u8 = 31;

pub const A0: u8 = 10;
pub const A1: u8 = 11;
pub const A2: u8 = 12;
pub const A3: u8 = 13;
pub const A4: u8 = 14;
pub const A5: u8 = 15;
pub const A6: u8 = 16;
pub const A7: u8 = 17;
pub const RA: u8 = 1;
pub const SP: u8 = 2;
pub const GP: u8 = 3;
pub const TP: u8 = 4;
pub const FP: u8 = 8;

fn le32(v: u32) [4]u8 {
    return [_]u8{ @as(u8, @truncate(v)), @as(u8, @truncate(v >> 8)), @as(u8, @truncate(v >> 16)), @as(u8, @truncate(v >> 24)) };
}

fn le16(v: u16) [2]u8 {
    return [_]u8{ @as(u8, @truncate(v)), @as(u8, @truncate(v >> 8)) };
}
