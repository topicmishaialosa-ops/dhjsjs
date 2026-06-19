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
pub const X30: u8 = 30;
pub const FP: u8 = 29;
pub const ZR: u8 = 31;

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

    pub fn add(self: *CodeBuffer, rd: u8, rn: u8, rm: u8) void {
        self.dword(0x8B000000 | (@as(u32, rm) << 16) | (@as(u32, rn) << 5) | rd);
    }

    pub fn adds(self: *CodeBuffer, rd: u8, rn: u8, rm: u8) void {
        self.dword(0xAB000000 | (@as(u32, rm) << 16) | (@as(u32, rn) << 5) | rd);
    }

    pub fn sub(self: *CodeBuffer, rd: u8, rn: u8, rm: u8) void {
        self.dword(0xCB000000 | (@as(u32, rm) << 16) | (@as(u32, rn) << 5) | rd);
    }

    pub fn subs(self: *CodeBuffer, rd: u8, rn: u8, rm: u8) void {
        self.dword(0xEB000000 | (@as(u32, rm) << 16) | (@as(u32, rn) << 5) | rd);
    }

    pub fn mul(self: *CodeBuffer, rd: u8, rn: u8, rm: u8) void {
        self.dword(0x9B007C00 | (@as(u32, rm) << 16) | (@as(u32, rn) << 5) | rd);
    }

    pub fn sdiv(self: *CodeBuffer, rd: u8, rn: u8, rm: u8) void {
        self.dword(0x9AC00C00 | (@as(u32, rm) << 16) | (@as(u32, rn) << 5) | rd);
    }

    pub fn and_(self: *CodeBuffer, rd: u8, rn: u8, rm: u8) void {
        self.dword(0x8A000000 | (@as(u32, rm) << 16) | (@as(u32, rn) << 5) | rd);
    }

    pub fn orr(self: *CodeBuffer, rd: u8, rn: u8, rm: u8) void {
        self.dword(0xAA000000 | (@as(u32, rm) << 16) | (@as(u32, rn) << 5) | rd);
    }

    pub fn eor(self: *CodeBuffer, rd: u8, rn: u8, rm: u8) void {
        self.dword(0xCA000000 | (@as(u32, rm) << 16) | (@as(u32, rn) << 5) | rd);
    }

    pub fn lsl(self: *CodeBuffer, rd: u8, rn: u8, rm: u8) void {
        self.dword(0x9A200000 | (@as(u32, rm) << 16) | (@as(u32, rn) << 5) | rd);
    }

    pub fn lsr(self: *CodeBuffer, rd: u8, rn: u8, rm: u8) void {
        self.dword(0x9A200000 | (@as(u32, rm) << 16) | (1 << 12) | (@as(u32, rn) << 5) | rd);
    }

    pub fn asr(self: *CodeBuffer, rd: u8, rn: u8, rm: u8) void {
        self.dword(0x9A600000 | (@as(u32, rm) << 16) | (@as(u32, rn) << 5) | rd);
    }

    pub fn addi(self: *CodeBuffer, rd: u8, rn: u8, imm: u16) void {
        self.dword(0x91000000 | ((@as(u32, imm) & 0xFFF) << 10) | (@as(u32, rn) << 5) | rd);
    }

    pub fn subi(self: *CodeBuffer, rd: u8, rn: u8, imm: u16) void {
        self.dword(0xD1000000 | ((@as(u32, imm) & 0xFFF) << 10) | (@as(u32, rn) << 5) | rd);
    }

    pub fn cmp(self: *CodeBuffer, rn: u8, rm: u8) void {
        self.subs(31, rn, rm);
    }

    pub fn mov(self: *CodeBuffer, rd: u8, rn: u8) void {
        self.add(rd, rn, 31);
    }

    pub fn stp(self: *CodeBuffer, rt1: u8, rt2: u8, rn: u8, off: i32) void {
        const imm7: u32 = @as(u32, @bitCast(off >> 3)) & 0x7F;
        self.dword(0xA9000000 | (imm7 << 15) | (@as(u32, rt2) << 10) | (@as(u32, rn) << 5) | rt1);
    }

    pub fn stpPre(self: *CodeBuffer, rt1: u8, rt2: u8, rn: u8, off: i32) void {
        const imm7: u32 = @as(u32, @bitCast((off >> 3) & 0x7F));
        self.dword(0xA9800000 | (imm7 << 15) | (@as(u32, rt2) << 10) | (@as(u32, rn) << 5) | rt1);
    }

    pub fn stpPost(self: *CodeBuffer, rt1: u8, rt2: u8, rn: u8, off: i32) void {
        const imm7: u32 = @as(u32, @bitCast((off >> 3) & 0x7F));
        self.dword(0xA8800000 | (imm7 << 15) | (@as(u32, rt2) << 10) | (@as(u32, rn) << 5) | rt1);
    }

    pub fn ldp(self: *CodeBuffer, rt1: u8, rt2: u8, rn: u8, off: i32) void {
        const imm7: u32 = @as(u32, @bitCast(off >> 3)) & 0x7F;
        self.dword(0xA9400000 | (imm7 << 15) | (@as(u32, rt2) << 10) | (@as(u32, rn) << 5) | rt1);
    }

    pub fn ldpPost(self: *CodeBuffer, rt1: u8, rt2: u8, rn: u8, off: i32) void {
        const imm7: u32 = @as(u32, @bitCast((off >> 3) & 0x7F));
        self.dword(0xA8C00000 | (imm7 << 15) | (@as(u32, rt2) << 10) | (@as(u32, rn) << 5) | rt1);
    }

    pub fn str64(self: *CodeBuffer, rt: u8, rn: u8, off: i32) void {
        const imm12: u32 = @as(u32, @bitCast(off >> 3)) & 0xFFF;
        self.dword(0xF9000000 | (imm12 << 10) | (@as(u32, rn) << 5) | rt);
    }

    pub fn ldr64(self: *CodeBuffer, rt: u8, rn: u8, off: i32) void {
        const imm12: u32 = @as(u32, @bitCast(off >> 3)) & 0xFFF;
        self.dword(0xF9400000 | (imm12 << 10) | (@as(u32, rn) << 5) | rt);
    }

    pub fn str32(self: *CodeBuffer, rt: u8, rn: u8, off: i32) void {
        const imm12: u32 = @as(u32, @bitCast(off >> 2)) & 0xFFF;
        self.dword(0xB9000000 | (imm12 << 10) | (@as(u32, rn) << 5) | rt);
    }

    pub fn ldr32(self: *CodeBuffer, rt: u8, rn: u8, off: i32) void {
        const imm12: u32 = @as(u32, @bitCast(off >> 2)) & 0xFFF;
        self.dword(0xB9400000 | (imm12 << 10) | (@as(u32, rn) << 5) | rt);
    }

    pub fn branch(self: *CodeBuffer) void {
        self.dword(0x14000000);
    }

    pub fn bl(self: *CodeBuffer) void {
        self.dword(0x94000000);
    }

    pub fn cbz(self: *CodeBuffer, rt: u8) void {
        self.dword(0xB4000000 | (@as(u32, rt)));
    }

    pub fn cbnz(self: *CodeBuffer, rt: u8) void {
        self.dword(0xB5000000 | (@as(u32, rt)));
    }

    pub fn bEq(self: *CodeBuffer) void { self.dword(0x54000000 | (0 << 0)); }
    pub fn bNe(self: *CodeBuffer) void { self.dword(0x54000000 | (1 << 0)); }
    pub fn bLt(self: *CodeBuffer) void { self.dword(0x54000000 | (10 << 0)); }
    pub fn bGe(self: *CodeBuffer) void { self.dword(0x54000000 | (11 << 0)); }
    pub fn bGt(self: *CodeBuffer) void { self.dword(0x54000000 | (12 << 0)); }
    pub fn bLe(self: *CodeBuffer) void { self.dword(0x54000000 | (13 << 0)); }

    pub fn patchB(self: *CodeBuffer, pos: usize, target: usize) void {
        const off = (@as(i32, @intCast(target)) - @as(i32, @intCast(pos))) >> 2;
        const imm26 = @as(u32, @bitCast(off)) & 0x3FFFFFF;
        const orig = @as(u32, @bitCast([_]u8{ self.buf[pos], self.buf[pos + 1], self.buf[pos + 2], self.buf[pos + 3] }));
        const enc = (orig & 0xFC000000) | imm26;
        self.buf[pos + 0] = @as(u8, @truncate(enc));
        self.buf[pos + 1] = @as(u8, @truncate(enc >> 8));
        self.buf[pos + 2] = @as(u8, @truncate(enc >> 16));
        self.buf[pos + 3] = @as(u8, @truncate(enc >> 24));
    }

    pub fn patchBL(self: *CodeBuffer, pos: usize, target: usize) void {
        self.patchB(pos, target);
    }

    pub fn patchCBZ(self: *CodeBuffer, pos: usize, target: usize) void {
        const off = (@as(i32, @intCast(target)) - @as(i32, @intCast(pos))) >> 2;
        const imm19 = @as(u32, @bitCast(off)) & 0x7FFFF;
        const orig = @as(u32, @bitCast([_]u8{ self.buf[pos], self.buf[pos + 1], self.buf[pos + 2], self.buf[pos + 3] }));
        const enc = (orig & 0xFF00001F) | (imm19 << 5);
        self.buf[pos + 0] = @as(u8, @truncate(enc));
        self.buf[pos + 1] = @as(u8, @truncate(enc >> 8));
        self.buf[pos + 2] = @as(u8, @truncate(enc >> 16));
        self.buf[pos + 3] = @as(u8, @truncate(enc >> 24));
    }

    pub fn patchCBNZ(self: *CodeBuffer, pos: usize, target: usize) void {
        self.patchCBZ(pos, target);
    }

    pub fn patchBCond(self: *CodeBuffer, pos: usize, target: usize) void {
        const off = (@as(i32, @intCast(target)) - @as(i32, @intCast(pos))) >> 2;
        const imm19 = @as(u32, @bitCast(off)) & 0x7FFFF;
        const orig = @as(u32, @bitCast([_]u8{ self.buf[pos], self.buf[pos + 1], self.buf[pos + 2], self.buf[pos + 3] }));
        const enc = (orig & 0xFF00001F) | (imm19 << 5);
        self.buf[pos + 0] = @as(u8, @truncate(enc));
        self.buf[pos + 1] = @as(u8, @truncate(enc >> 8));
        self.buf[pos + 2] = @as(u8, @truncate(enc >> 16));
        self.buf[pos + 3] = @as(u8, @truncate(enc >> 24));
    }

    pub fn neg(self: *CodeBuffer, rd: u8, rn: u8) void {
        self.sub(rd, 31, rn);
    }

    pub fn cset(self: *CodeBuffer, rd: u8, cond: u8) void {
        self.dword(0x9A800000 | (@as(u32, cond) << 12) | rd);
    }

    pub fn csneg(self: *CodeBuffer, rd: u8, rn: u8, rm: u8, cond: u8) void {
        self.dword(0xDA800000 | (@as(u32, rm) << 16) | (cond << 12) | (@as(u32, rn) << 5) | rd);
    }

    pub fn sxtw(self: *CodeBuffer, rd: u8, rn: u8) void {
        self.dword(0x93407C00 | (@as(u32, rn) << 5) | rd);
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

    pub fn buildElf64Dyn(self: *CodeBuffer) void {
        const code_len = self.len;
        const page: u64 = 0x1000;
        const code_vaddr: u64 = page;

        const phdr_off: u64 = 64;
        const phdr_num: u16 = 4;
        const phdr_end = phdr_off + phdr_num * 56;
        const dyn_off = phdr_end;
        const dyn_num: u64 = 4;
        const dyn_size = dyn_num * 16;
        const sym_off = dyn_off + dyn_size;
        const sym_count: u64 = 2;
        const sym_size = sym_count * 24;
        const str_off = sym_off + sym_size;
        const str_size: u64 = 26;
        const hdr_end = str_off + str_size;
        const pad = (page - (hdr_end % page)) % page;
        const code_foff = hdr_end + pad;
        const total: u64 = code_foff + code_len;

        var out: [65536]u8 = undefined;

        // ELF header
        out[0..4].* = [_]u8{ 0x7F, 'E', 'L', 'F' };
        out[4] = 2; out[5] = 1; out[6] = 1; out[7] = 0;
        var i: usize = 8; while (i < 16) : (i += 1) out[i] = 0;
        // e_type=2 (ET_DYN), e_machine=0xB7 (AArch64), e_version=1
        i = 0; while (i < 2) : (i += 1) out[16 + i] = le16(2)[i];
        i = 0; while (i < 2) : (i += 1) out[18 + i] = le16(0xB7)[i];
        i = 0; while (i < 4) : (i += 1) out[20 + i] = le32(1)[i];
        // e_entry = code_vaddr (entry point - the first instruction)
        i = 0; while (i < 8) : (i += 1) out[24 + i] = le64(code_vaddr)[i];
        // e_phoff
        i = 0; while (i < 8) : (i += 1) out[32 + i] = le64(phdr_off)[i];
        // e_shoff = 0
        i = 0; while (i < 8) : (i += 1) out[40 + i] = 0;
        // e_flags
        i = 0; while (i < 4) : (i += 1) out[48 + i] = 0;
        // e_ehsize = 64
        i = 0; while (i < 2) : (i += 1) out[52 + i] = le16(64)[i];
        // e_phentsize = 56
        i = 0; while (i < 2) : (i += 1) out[54 + i] = le16(56)[i];
        // e_phnum
        i = 0; while (i < 2) : (i += 1) out[56 + i] = le16(phdr_num)[i];
        // e_shentsize = 0
        i = 0; while (i < 2) : (i += 1) out[58 + i] = 0;
        // e_shnum = 0
        i = 0; while (i < 2) : (i += 1) out[60 + i] = 0;
        // e_shstrndx = 0
        i = 0; while (i < 2) : (i += 1) out[62 + i] = 0;

        // Program header 0: PT_PHDR
        var ph = phdr_off;
        i = 0; while (i < 4) : (i += 1) out[ph + i] = le32(6)[i];        // p_type = PT_PHDR
        i = 0; while (i < 4) : (i += 1) out[ph + 4 + i] = le32(4)[i];    // p_flags = PF_R
        i = 0; while (i < 8) : (i += 1) out[ph + 8 + i] = le64(phdr_off)[i]; // p_offset
        i = 0; while (i < 8) : (i += 1) out[ph + 16 + i] = le64(phdr_off)[i]; // p_vaddr
        i = 0; while (i < 8) : (i += 1) out[ph + 24 + i] = le64(phdr_off)[i]; // p_paddr
        i = 0; while (i < 8) : (i += 1) out[ph + 32 + i] = le64(phdr_end - phdr_off)[i]; // p_filesz
        i = 0; while (i < 8) : (i += 1) out[ph + 40 + i] = le64(phdr_end - phdr_off)[i]; // p_memsz
        i = 0; while (i < 8) : (i += 1) out[ph + 48 + i] = le64(8)[i];   // p_align

        // Program header 1: PT_LOAD
        ph = phdr_off + 56;
        i = 0; while (i < 4) : (i += 1) out[ph + i] = le32(1)[i];        // p_type = PT_LOAD
        i = 0; while (i < 4) : (i += 1) out[ph + 4 + i] = le32(7)[i];    // p_flags = RWX
        i = 0; while (i < 8) : (i += 1) out[ph + 8 + i] = le64(0)[i];    // p_offset = 0
        i = 0; while (i < 8) : (i += 1) out[ph + 16 + i] = le64(0)[i];   // p_vaddr = 0
        i = 0; while (i < 8) : (i += 1) out[ph + 24 + i] = le64(0)[i];   // p_paddr = 0
        i = 0; while (i < 8) : (i += 1) out[ph + 32 + i] = le64(total)[i];  // p_filesz
        i = 0; while (i < 8) : (i += 1) out[ph + 40 + i] = le64(total)[i];  // p_memsz
        i = 0; while (i < 8) : (i += 1) out[ph + 48 + i] = le64(page)[i];   // p_align

        // Program header 2: PT_DYNAMIC
        ph = phdr_off + 112;
        i = 0; while (i < 4) : (i += 1) out[ph + i] = le32(2)[i];        // p_type = PT_DYNAMIC
        i = 0; while (i < 4) : (i += 1) out[ph + 4 + i] = le32(6)[i];    // p_flags = RW
        i = 0; while (i < 8) : (i += 1) out[ph + 8 + i] = le64(dyn_off)[i]; // p_offset
        i = 0; while (i < 8) : (i += 1) out[ph + 16 + i] = le64(dyn_off)[i]; // p_vaddr
        i = 0; while (i < 8) : (i += 1) out[ph + 24 + i] = le64(dyn_off)[i]; // p_paddr
        i = 0; while (i < 8) : (i += 1) out[ph + 32 + i] = le64(dyn_size)[i]; // p_filesz
        i = 0; while (i < 8) : (i += 1) out[ph + 40 + i] = le64(dyn_size)[i]; // p_memsz
        i = 0; while (i < 8) : (i += 1) out[ph + 48 + i] = le64(8)[i];   // p_align

        // Program header 3: PT_GNU_STACK
        ph = phdr_off + 168;
        i = 0; while (i < 4) : (i += 1) out[ph + i] = le32(0x6474e551)[i]; // p_type = PT_GNU_STACK
        i = 0; while (i < 4) : (i += 1) out[ph + 4 + i] = le32(6)[i];      // p_flags = RW
        i = 0; while (i < 8) : (i += 1) out[ph + 8 + i] = 0;  // p_offset
        i = 0; while (i < 8) : (i += 1) out[ph + 16 + i] = 0;  // p_vaddr
        i = 0; while (i < 8) : (i += 1) out[ph + 24 + i] = 0;  // p_paddr
        i = 0; while (i < 8) : (i += 1) out[ph + 32 + i] = 0;  // p_filesz
        i = 0; while (i < 8) : (i += 1) out[ph + 40 + i] = 0;  // p_memsz
        i = 0; while (i < 8) : (i += 1) out[ph + 48 + i] = le64(16)[i];  // p_align

        // .dynamic section
        var dp = dyn_off;
        // DT_SYMTAB
        i = 0; while (i < 8) : (i += 1) out[dp + i] = le64(6)[i];         // d_tag
        i = 0; while (i < 8) : (i += 1) out[dp + 8 + i] = le64(sym_off)[i]; // d_un.d_val
        dp += 16;
        // DT_STRTAB
        i = 0; while (i < 8) : (i += 1) out[dp + i] = le64(5)[i];
        i = 0; while (i < 8) : (i += 1) out[dp + 8 + i] = le64(str_off)[i];
        dp += 16;
        // DT_STRSZ
        i = 0; while (i < 8) : (i += 1) out[dp + i] = le64(10)[i];
        i = 0; while (i < 8) : (i += 1) out[dp + 8 + i] = le64(str_size)[i];
        dp += 16;
        // DT_NULL
        i = 0; while (i < 8) : (i += 1) out[dp + i] = 0;
        i = 0; while (i < 8) : (i += 1) out[dp + 8 + i] = 0;

        // .dynsym section
        var sp = sym_off;
        // Entry 0: null symbol (all zeros)
        i = 0; while (i < 24) : (i += 1) out[sp + i] = 0;
        sp += 24;
        // Entry 1: ANativeActivity_onCreate
        i = 0; while (i < 4) : (i += 1) out[sp + i] = le32(1)[i];     // st_name
        i = 0; while (i < 1) : (i += 1) out[sp + 4 + i] = 0x12;       // st_info
        i = 0; while (i < 1) : (i += 1) out[sp + 5 + i] = 0;          // st_other
        i = 0; while (i < 2) : (i += 1) out[sp + 6 + i] = le16(0)[i]; // st_shndx
        i = 0; while (i < 8) : (i += 1) out[sp + 8 + i] = le64(code_vaddr)[i]; // st_value
        i = 0; while (i < 8) : (i += 1) out[sp + 16 + i] = le64(code_len)[i];  // st_size

        // .dynstr section
        const str_data = "\x00" ++ "ANativeActivity_onCreate\x00";
        var stp2 = str_off;
        i = 0; while (i < str_data.len) : (i += 1) { out[stp2] = str_data[i]; stp2 += 1; }
        // Pad str data
        while (stp2 < hdr_end) : (stp2 += 1) out[stp2] = 0;

        // Padding before code
        var pp = hdr_end;
        while (pp < code_foff) : (pp += 1) out[pp] = 0;

        // Code
        i = 0; while (i < code_len) : (i += 1) out[code_foff + i] = self.buf[i];

        // Copy back
        self.len = @as(usize, @intCast(total));
        i = 0; while (i < self.len) : (i += 1) self.buf[i] = out[i];
    }
};
