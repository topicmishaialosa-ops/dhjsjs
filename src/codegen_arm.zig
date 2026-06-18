pub const X0: u8 = 0;
pub const X1: u8 = 1;
pub const X2: u8 = 2;
pub const X3: u8 = 3;
pub const X4: u8 = 4;
pub const X5: u8 = 5;
pub const X6: u8 = 6;
pub const X7: u8 = 7;
pub const X8: u8 = 8;
pub const X30: u8 = 30;

fn le64(v: u64) [8]u8 {
    return [_]u8{
        @as(u8, @truncate(v >> 0)),
        @as(u8, @truncate(v >> 8)),
        @as(u8, @truncate(v >> 16)),
        @as(u8, @truncate(v >> 24)),
        @as(u8, @truncate(v >> 32)),
        @as(u8, @truncate(v >> 40)),
        @as(u8, @truncate(v >> 48)),
        @as(u8, @truncate(v >> 56)),
    };
}

fn le32(v: u32) [4]u8 {
    return [_]u8{
        @as(u8, @truncate(v >> 0)),
        @as(u8, @truncate(v >> 8)),
        @as(u8, @truncate(v >> 16)),
        @as(u8, @truncate(v >> 24)),
    };
}

fn le16(v: u16) [2]u8 {
    return [_]u8{ @as(u8, @truncate(v >> 0)), @as(u8, @truncate(v >> 8)) };
}

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

    pub fn word(self: *CodeBuffer, w: u16) void {
        const bytes = le16(w);
        self.buf[self.len + 0] = bytes[0];
        self.buf[self.len + 1] = bytes[1];
        self.len += 2;
    }

    pub fn dword(self: *CodeBuffer, dw: u32) void {
        const bytes = le32(dw);
        self.buf[self.len + 0] = bytes[0];
        self.buf[self.len + 1] = bytes[1];
        self.buf[self.len + 2] = bytes[2];
        self.buf[self.len + 3] = bytes[3];
        self.len += 4;
    }

    pub fn movz(self: *CodeBuffer, rd: u8, imm: u16, shift: u8) void {
        const enc: u32 = 0xD2800000 | (@as(u32, imm) << 5) | (@as(u32, shift >> 4) << 21) | rd;
        self.dword(enc);
    }

    pub fn movk(self: *CodeBuffer, rd: u8, imm: u16, shift: u8) void {
        const enc: u32 = 0xF2800000 | (@as(u32, imm) << 5) | (@as(u32, shift >> 4) << 21) | rd;
        self.dword(enc);
    }

    pub fn movRImm64(self: *CodeBuffer, rd: u8, val: u64) void {
        self.movz(rd, @as(u16, @truncate(val >> 0)), 0);
        if (val > 0xFFFF) self.movk(rd, @as(u16, @truncate(val >> 16)), 16);
        if (val > 0xFFFFFFFF) self.movk(rd, @as(u16, @truncate(val >> 32)), 32);
        if (val > 0xFFFFFFFFFFFF) self.movk(rd, @as(u16, @truncate(val >> 48)), 48);
    }

    pub fn svc(self: *CodeBuffer, imm: u16) void {
        const enc: u32 = 0xD4000001 | (@as(u32, imm) << 5);
        self.dword(enc);
    }

    pub fn ret(self: *CodeBuffer) void {
        self.dword(0xD65F03C0);
    }

    pub fn buildElf64(self: *CodeBuffer) void {
        const code_len = self.len;
        const elf_total: u64 = 128 + code_len;
        const base: u64 = 0x400000;

        var out: [65536]u8 = undefined;

        // ELF header
        out[0..4].* = [_]u8{ 0x7F, 'E', 'L', 'F' };
        out[4] = 2; out[5] = 1; out[6] = 1; out[7] = 0;
        var i: usize = 8; while (i < 16) : (i += 1) out[i] = 0;
        const header_fields = le16(2) ++ le16(0xB7) ++ le32(1);
        i = 0; while (i < 8) : (i += 1) out[16 + i] = header_fields[i];
        const entry_bytes = le64(base);
        i = 0; while (i < 8) : (i += 1) out[24 + i] = entry_bytes[i];
        const phoff_bytes = le64(64);
        i = 0; while (i < 8) : (i += 1) out[32 + i] = phoff_bytes[i];
        i = 0; while (i < 8) : (i += 1) out[40 + i] = 0;
        i = 0; while (i < 4) : (i += 1) out[48 + i] = 0;
        i = 0; while (i < 2) : (i += 1) out[52 + i] = le16(64)[i];
        i = 0; while (i < 2) : (i += 1) out[54 + i] = le16(56)[i];
        i = 0; while (i < 2) : (i += 1) out[56 + i] = le16(1)[i];
        i = 0; while (i < 6) : (i += 1) out[58 + i] = 0;

        // Program header at offset 64
        i = 0; while (i < 4) : (i += 1) out[64 + i] = le32(1)[i];
        i = 0; while (i < 4) : (i += 1) out[68 + i] = le32(5)[i];
        i = 0; while (i < 8) : (i += 1) out[72 + i] = le64(128)[i];
        i = 0; while (i < 8) : (i += 1) out[80 + i] = le64(base)[i];
        i = 0; while (i < 8) : (i += 1) out[88 + i] = le64(base)[i];
        i = 0; while (i < 8) : (i += 1) out[96 + i] = le64(elf_total)[i];
        i = 0; while (i < 8) : (i += 1) out[104 + i] = le64(elf_total)[i];
        i = 0; while (i < 8) : (i += 1) out[112 + i] = le64(0)[i];
        i = 0; while (i < 8) : (i += 1) out[120 + i] = le64(0)[i];

        // Copy code starting at offset 128
        i = 0; while (i < code_len) : (i += 1) out[128 + i] = self.buf[i];

        // Copy everything back
        self.len = 128 + code_len;
        i = 0; while (i < self.len) : (i += 1) self.buf[i] = out[i];
    }
};
