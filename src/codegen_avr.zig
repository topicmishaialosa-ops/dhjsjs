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

    fn word(self: *CodeBuffer, w: u16) void {
        self.byte(@as(u8, @truncate(w >> 8)));
        self.byte(@as(u8, @truncate(w)));
    }

    fn op_rr(self: *CodeBuffer, op10: u16, rd: u8, rr: u8) void {
        self.word(op10 | ((@as(u16, rd) & 0x1F) << 5) | (@as(u16, rr) & 0x1F));
    }

    fn op_rd5(self: *CodeBuffer, op8_lo: u16, rd: u8) void {
        self.word(op8_lo | ((@as(u16, rd) & 0x1F) << 5));
    }

    pub fn add(self: *CodeBuffer, rd: u8, rr: u8) void { self.op_rr(0x0C00, rd, rr); }
    pub fn adc(self: *CodeBuffer, rd: u8, rr: u8) void { self.op_rr(0x1C00, rd, rr); }
    pub fn sub(self: *CodeBuffer, rd: u8, rr: u8) void { self.op_rr(0x1800, rd, rr); }
    pub fn sbc(self: *CodeBuffer, rd: u8, rr: u8) void { self.op_rr(0x0800, rd, rr); }
    pub fn and_(self: *CodeBuffer, rd: u8, rr: u8) void { self.op_rr(0x2000, rd, rr); }
    pub fn or_(self: *CodeBuffer, rd: u8, rr: u8) void { self.op_rr(0x2800, rd, rr); }
    pub fn eor(self: *CodeBuffer, rd: u8, rr: u8) void { self.op_rr(0x2400, rd, rr); }
    pub fn mov(self: *CodeBuffer, rd: u8, rr: u8) void { self.op_rr(0x2C00, rd, rr); }
    pub fn cp(self: *CodeBuffer, rd: u8, rr: u8) void { self.op_rr(0x1400, rd, rr); }
    pub fn cpc(self: *CodeBuffer, rd: u8, rr: u8) void { self.op_rr(0x0400, rd, rr); }

    pub fn ldi(self: *CodeBuffer, rd: u8, k: u8) void {
        self.word(0xE000 | ((@as(u16, k >> 4) & 0x0F) << 8) | ((@as(u16, rd) & 0x0F) << 4) | (@as(u16, k) & 0x0F));
    }

    pub fn inc(self: *CodeBuffer, rd: u8) void { self.op_rd5(0x9403, rd); }
    pub fn dec(self: *CodeBuffer, rd: u8) void { self.op_rd5(0x940A, rd); }
    pub fn neg(self: *CodeBuffer, rd: u8) void { self.op_rd5(0x9401, rd); }
    pub fn com(self: *CodeBuffer, rd: u8) void { self.op_rd5(0x9400, rd); }
    pub fn lsr(self: *CodeBuffer, rd: u8) void { self.op_rd5(0x9406, rd); }
    pub fn asr(self: *CodeBuffer, rd: u8) void { self.op_rd5(0x9405, rd); }

    pub fn lsl(self: *CodeBuffer, rd: u8) void { self.add(rd, rd); }
    pub fn rol(self: *CodeBuffer, rd: u8) void { self.adc(rd, rd); }
    pub fn ror(self: *CodeBuffer, rd: u8) void { self.op_rd5(0x9407, rd); }

    pub fn adiw(self: *CodeBuffer, rd: u8, k: u8) void {
        self.word(0x9600 | ((@as(u16, rd >> 1) & 0x07) << 9) | (@as(u16, k) & 0x3F));
    }
    pub fn sbiw(self: *CodeBuffer, rd: u8, k: u8) void {
        self.word(0x9700 | ((@as(u16, rd >> 1) & 0x07) << 9) | (@as(u16, k) & 0x3F));
    }

    pub fn ldd_y(self: *CodeBuffer, rd: u8, q: u8) void {
        const r = @as(u16, rd) & 0x1F;
        const d = @as(u16, q) & 0x3F;
        var enc: u16 = 0x8000;
        if ((d & 0x20) != 0) enc |= 0x2000;
        if ((d & 0x10) != 0) enc |= 0x1000;
        if ((d & 0x08) != 0) enc |= 0x0800;
        if ((d & 0x04) != 0) enc |= 0x0400;
        enc |= (r << 4);
        enc |= (1 << 3);
        if ((d & 0x02) != 0) enc |= 0x0004;
        if ((d & 0x01) != 0) enc |= 0x0002;
        if ((d & 0x04) != 0) enc |= 0x0001;
        self.word(enc);
    }

    pub fn std_y(self: *CodeBuffer, q: u8, rr: u8) void {
        const r = @as(u16, rr) & 0x1F;
        const d = @as(u16, q) & 0x3F;
        var enc: u16 = 0x8000;
        if ((d & 0x20) != 0) enc |= 0x2000;
        if ((d & 0x10) != 0) enc |= 0x1000;
        if ((d & 0x08) != 0) enc |= 0x0800;
        if ((d & 0x04) != 0) enc |= 0x0400;
        enc |= 0x0200;
        enc |= (r << 4);
        enc |= (1 << 3);
        if ((d & 0x02) != 0) enc |= 0x0004;
        if ((d & 0x01) != 0) enc |= 0x0002;
        if ((d & 0x04) != 0) enc |= 0x0001;
        self.word(enc);
    }

    pub fn lds(self: *CodeBuffer, rd: u8, addr: u16) void {
        self.word(0x9000 | ((@as(u16, rd) & 0x1F) << 4));
        self.word(addr);
    }

    pub fn sts(self: *CodeBuffer, addr: u16, rr: u8) void {
        self.word(0x9200 | ((@as(u16, rr) & 0x1F) << 4));
        self.word(addr);
    }

    pub fn ld_z_inc(self: *CodeBuffer, rd: u8) void {
        self.word(0x9001 | ((@as(u16, rd) & 0x1F) << 5));
    }

    pub fn st_z_inc(self: *CodeBuffer, rr: u8) void {
        self.word(0x9201 | ((@as(u16, rr) & 0x1F) << 5));
    }

    pub fn push(self: *CodeBuffer, rr: u8) void {
        self.word(0x920F | ((@as(u16, rr) & 0x1F) << 4));
    }

    pub fn pop(self: *CodeBuffer, rd: u8) void {
        self.word(0x900F | ((@as(u16, rd) & 0x1F) << 4));
    }

    pub fn movw(self: *CodeBuffer, rd: u8, rr: u8) void {
        self.word(0x0100 | ((@as(u16, rd >> 1) & 0x0F) << 4) | (@as(u16, rr >> 1) & 0x0F));
    }

    pub fn out(self: *CodeBuffer, addr: u8, rr: u8) void {
        self.word(0xB800 | ((@as(u16, addr) & 0x3F) << 5) | (@as(u16, rr) & 0x1F));
    }

    pub fn in_(self: *CodeBuffer, rd: u8, addr: u8) void {
        self.word(0xB000 | ((@as(u16, addr) & 0x3F) << 5) | (@as(u16, rd) & 0x1F));
    }

    pub fn sei(self: *CodeBuffer) void { self.word(0x9478); }
    pub fn cli(self: *CodeBuffer) void { self.word(0x94F8); }
    pub fn sleep(self: *CodeBuffer) void { self.word(0x9588); }
    pub fn nop(self: *CodeBuffer) void { self.word(0x0000); }
    pub fn ret(self: *CodeBuffer) void { self.word(0x9508); }

    pub fn mul(self: *CodeBuffer, rd: u8, rr: u8) void {
        self.word(0x9C00 | ((@as(u16, rd) & 0x1F) << 5) | (@as(u16, rr) & 0x1F));
    }

    pub fn rjmp(self: *CodeBuffer, k: u16) void {
        self.word(0xC000 | (k & 0xFFF));
    }

    pub fn rjmp_rel(self: *CodeBuffer) void { self.word(0xC000); }

    pub fn rcall(self: *CodeBuffer, k: u16) void {
        self.word(0xD000 | (k & 0xFFF));
    }

    pub fn rcall_rel(self: *CodeBuffer) void { self.word(0xD000); }

    pub fn jmp(self: *CodeBuffer) void {
        self.word(0x940C);
    }

    pub fn call(self: *CodeBuffer) void {
        self.word(0x940E);
    }

    pub fn brne(self: *CodeBuffer, k: u16) void {
        self.word(0xF400 | ((k & 0x7F) << 3) | ((k >> 6) & 0x01));
    }

    pub fn breq(self: *CodeBuffer, k: u16) void {
        self.word(0xF000 | ((k & 0x7F) << 3) | ((k >> 6) & 0x01));
    }

    pub fn brlt(self: *CodeBuffer, k: u16) void {
        self.word(0xF004 | ((k & 0x7F) << 3) | ((k >> 6) & 0x01));
    }

    pub fn brge(self: *CodeBuffer, k: u16) void {
        self.word(0xF404 | ((k & 0x7F) << 3) | ((k >> 6) & 0x01));
    }

    pub fn brlo(self: *CodeBuffer, k: u16) void {
        self.word(0xF002 | ((k & 0x7F) << 3) | ((k >> 6) & 0x01));
    }

    pub fn brsh(self: *CodeBuffer, k: u16) void {
        self.word(0xF402 | ((k & 0x7F) << 3) | ((k >> 6) & 0x01));
    }

    pub fn patch_rjmp(self: *CodeBuffer, pos: usize, target_word: usize) void {
        const off = target_word -% (pos / 2 + 1);
        const k = @as(u16, @truncate(off & 0xFFF));
        const orig = (@as(u16, self.buf[pos]) << 8) | @as(u16, self.buf[pos + 1]);
        self.buf[pos] = @as(u8, @truncate((orig & 0xF000) >> 8));
        self.buf[pos + 1] = @as(u8, @truncate((orig & 0xF000) >> 0));
        self.buf[pos] = @as(u8, @truncate(((orig & 0xF000) | k) >> 8));
        self.buf[pos + 1] = @as(u8, @truncate(((orig & 0xF000) | k)));
    }

    pub fn patch_br(self: *CodeBuffer, pos: usize, target_word: usize) void {
        const off = target_word -% (pos / 2 + 1);
        const k = @as(u16, @truncate(off & 0x7F));
        const orig = (@as(u16, self.buf[pos]) << 8) | @as(u16, self.buf[pos + 1]);
        const base = orig & 0xFC00;
        const enc = base | ((k & 0x3F) << 3) | ((k >> 6) & 0x01) | 0x00;
        self.buf[pos] = @as(u8, @truncate(enc >> 8));
        self.buf[pos + 1] = @as(u8, @truncate(enc));
    }

    pub fn patch_word(self: *CodeBuffer, pos: usize, val: u16) void {
        self.buf[pos] = @as(u8, @truncate(val >> 8));
        self.buf[pos + 1] = @as(u8, @truncate(val));
    }

    pub fn li32(self: *CodeBuffer, rd_lsb: u8, val: i32) void {
        self.ldi(rd_lsb, @as(u8, @truncate(@as(u32, @bitCast(val)))));
        self.ldi(rd_lsb + 1, @as(u8, @truncate(@as(u32, @bitCast(val)) >> 8)));
        self.ldi(rd_lsb + 2, @as(u8, @truncate(@as(u32, @bitCast(val)) >> 16)));
        self.ldi(rd_lsb + 3, @as(u8, @truncate(@as(u32, @bitCast(val)) >> 24)));
    }

    pub fn pushR32(self: *CodeBuffer, r_lsb: u8) void {
        self.push(r_lsb + 3);
        self.push(r_lsb + 2);
        self.push(r_lsb + 1);
        self.push(r_lsb);
    }

    pub fn popR32(self: *CodeBuffer, r_lsb: u8) void {
        self.pop(r_lsb);
        self.pop(r_lsb + 1);
        self.pop(r_lsb + 2);
        self.pop(r_lsb + 3);
    }

    pub fn loadVar(self: *CodeBuffer, rd_lsb: u8, off: i32) void {
        if (off >= 0 and off <= 63) {
            self.ldd_y(rd_lsb, @as(u8, @intCast(off)));
            self.ldd_y(rd_lsb + 1, @as(u8, @intCast(off + 1)));
            self.ldd_y(rd_lsb + 2, @as(u8, @intCast(off + 2)));
            self.ldd_y(rd_lsb + 3, @as(u8, @intCast(off + 3)));
            return;
        }
        self.movw(Z, Y);
        self.ldi(A0, @as(u8, @truncate(@as(u32, @bitCast(off)))));
        self.add(ZL, A0);
        self.ldi(A0, @as(u8, @truncate(@as(u32, @bitCast(off >> 8)))));
        self.adc(ZH, A0);
        self.ld_z_inc(rd_lsb);
        self.ld_z_inc(rd_lsb + 1);
        self.ld_z_inc(rd_lsb + 2);
        self.ld_z_inc(rd_lsb + 3);
    }

    pub fn storeVar(self: *CodeBuffer, off: i32, rs_lsb: u8) void {
        if (off >= 0 and off <= 63) {
            self.std_y(@as(u8, @intCast(off)), rs_lsb);
            self.std_y(@as(u8, @intCast(off + 1)), rs_lsb + 1);
            self.std_y(@as(u8, @intCast(off + 2)), rs_lsb + 2);
            self.std_y(@as(u8, @intCast(off + 3)), rs_lsb + 3);
            return;
        }
        self.movw(Z, Y);
        self.ldi(A0, @as(u8, @truncate(@as(u32, @bitCast(off)))));
        self.add(ZL, A0);
        self.ldi(A0, @as(u8, @truncate(@as(u32, @bitCast(off >> 8)))));
        self.adc(ZH, A0);
        self.st_z_inc(rs_lsb);
        self.st_z_inc(rs_lsb + 1);
        self.st_z_inc(rs_lsb + 2);
        self.st_z_inc(rs_lsb + 3);
    }

    pub fn add32(self: *CodeBuffer, rd_lsb: u8, rs_lsb: u8) void {
        self.add(rd_lsb, rs_lsb);
        self.adc(rd_lsb + 1, rs_lsb + 1);
        self.adc(rd_lsb + 2, rs_lsb + 2);
        self.adc(rd_lsb + 3, rs_lsb + 3);
    }

    pub fn sub32(self: *CodeBuffer, rd_lsb: u8, rs_lsb: u8) void {
        self.sub(rd_lsb, rs_lsb);
        self.sbc(rd_lsb + 1, rs_lsb + 1);
        self.sbc(rd_lsb + 2, rs_lsb + 2);
        self.sbc(rd_lsb + 3, rs_lsb + 3);
    }

    pub fn and32(self: *CodeBuffer, rd_lsb: u8, rs_lsb: u8) void {
        self.and_(rd_lsb, rs_lsb);
        self.and_(rd_lsb + 1, rs_lsb + 1);
        self.and_(rd_lsb + 2, rs_lsb + 2);
        self.and_(rd_lsb + 3, rs_lsb + 3);
    }

    pub fn or32(self: *CodeBuffer, rd_lsb: u8, rs_lsb: u8) void {
        self.or_(rd_lsb, rs_lsb);
        self.or_(rd_lsb + 1, rs_lsb + 1);
        self.or_(rd_lsb + 2, rs_lsb + 2);
        self.or_(rd_lsb + 3, rs_lsb + 3);
    }

    pub fn neg32(self: *CodeBuffer, rd_lsb: u8) void {
        self.neg(rd_lsb);
        self.ldi(R0, 0);
        self.sbc(rd_lsb + 1, R0);
        self.sbc(rd_lsb + 2, R0);
        self.sbc(rd_lsb + 3, R0);
    }

    pub fn eor32(self: *CodeBuffer, rd_lsb: u8, rs_lsb: u8) void {
        self.eor(rd_lsb, rs_lsb);
        self.eor(rd_lsb + 1, rs_lsb + 1);
        self.eor(rd_lsb + 2, rs_lsb + 2);
        self.eor(rd_lsb + 3, rs_lsb + 3);
    }

    pub fn cp32(self: *CodeBuffer, ra_lsb: u8, rb_lsb: u8) void {
        self.cp(ra_lsb, rb_lsb);
        self.cpc(ra_lsb + 1, rb_lsb + 1);
        self.cpc(ra_lsb + 2, rb_lsb + 2);
        self.cpc(ra_lsb + 3, rb_lsb + 3);
    }

    pub fn sub32flags(self: *CodeBuffer, rd_lsb: u8, rs_lsb: u8) void {
        self.sub(rd_lsb, rs_lsb);
        self.sbc(rd_lsb + 1, rs_lsb + 1);
        self.sbc(rd_lsb + 2, rs_lsb + 2);
        self.sbc(rd_lsb + 3, rs_lsb + 3);
    }

    pub fn lsl32(self: *CodeBuffer, rd_lsb: u8) void {
        self.lsl(rd_lsb + 3);
        self.rol(rd_lsb + 2);
        self.rol(rd_lsb + 1);
        self.rol(rd_lsb);
    }

    pub fn seqz32(self: *CodeBuffer, rd_lsb: u8) void {
        self.ldi(rd_lsb, 1);
        self.ldi(rd_lsb + 1, 0);
        self.ldi(rd_lsb + 2, 0);
        self.ldi(rd_lsb + 3, 0);
        self.breq(0);
        self.patch_br(self.len - 2, self.len / 2 + 2);
        self.ldi(rd_lsb, 0);
        self.ldi(rd_lsb + 1, 0);
    }

    pub fn snez32(self: *CodeBuffer, rd_lsb: u8) void {
        self.ldi(rd_lsb, 0);
        self.ldi(rd_lsb + 1, 0);
        self.ldi(rd_lsb + 2, 0);
        self.ldi(rd_lsb + 3, 0);
        self.breq(0);
        self.patch_br(self.len - 2, self.len / 2 + 4);
        self.ldi(rd_lsb, 1);
        self.ldi(rd_lsb + 1, 0);
    }

    pub fn sgez32(self: *CodeBuffer, rd_lsb: u8) void {
        self.ldi(rd_lsb, 0);
        self.ldi(rd_lsb + 1, 0);
        self.ldi(rd_lsb + 2, 0);
        self.ldi(rd_lsb + 3, 0);
        self.brlt(0);
        self.patch_br(self.len - 2, self.len / 2 + 4);
        self.ldi(rd_lsb, 1);
        self.ldi(rd_lsb + 1, 0);
    }

    pub fn buildHex(self: *CodeBuffer, flash_base: u32) void {
        const code_len = self.len;
        var addr: u32 = flash_base;
        var i: usize = 0;
        var hex_buf: [65536]u8 = undefined;
        var hex_pos: usize = 0;
        while (i < code_len) {
            var count: u8 = 0;
            while (count < 16 and i + count < code_len) {
                count += 1;
            }
            if (count == 0) break;
            var cksum: u8 = count;
            cksum +%= @as(u8, @truncate(addr >> 8));
            cksum +%= @as(u8, @truncate(addr));
            cksum +%= 0;
            hex_buf[hex_pos] = ':'; hex_pos += 1;
            hex_buf[hex_pos] = "0123456789ABCDEF"[count >> 4]; hex_pos += 1;
            hex_buf[hex_pos] = "0123456789ABCDEF"[count & 0x0F]; hex_pos += 1;
            hex_buf[hex_pos] = "0123456789ABCDEF"[@as(u8, @truncate(addr >> 12)) & 0x0F]; hex_pos += 1;
            hex_buf[hex_pos] = "0123456789ABCDEF"[@as(u8, @truncate(addr >> 8)) & 0x0F]; hex_pos += 1;
            hex_buf[hex_pos] = "0123456789ABCDEF"[@as(u8, @truncate(addr >> 4)) & 0x0F]; hex_pos += 1;
            hex_buf[hex_pos] = "0123456789ABCDEF"[@as(u8, @truncate(addr)) & 0x0F]; hex_pos += 1;
            hex_buf[hex_pos] = '0'; hex_pos += 1;
            hex_buf[hex_pos] = '0'; hex_pos += 1;
            var j: usize = 0;
            while (j < count) : (j += 1) {
                const b = self.buf[i + j];
                cksum +%= b;
                hex_buf[hex_pos] = "0123456789ABCDEF"[b >> 4]; hex_pos += 1;
                hex_buf[hex_pos] = "0123456789ABCDEF"[b & 0x0F]; hex_pos += 1;
            }
            cksum = ~cksum +% 1;
            hex_buf[hex_pos] = "0123456789ABCDEF"[cksum >> 4]; hex_pos += 1;
            hex_buf[hex_pos] = "0123456789ABCDEF"[cksum & 0x0F]; hex_pos += 1;
            hex_buf[hex_pos] = '\n'; hex_pos += 1;
            i += count;
            addr += count;
        }
        hex_buf[hex_pos] = ':'; hex_pos += 1;
        hex_buf[hex_pos] = '0'; hex_pos += 1;
        hex_buf[hex_pos] = '0'; hex_pos += 1;
        hex_buf[hex_pos] = '0'; hex_pos += 1;
        hex_buf[hex_pos] = '0'; hex_pos += 1;
        hex_buf[hex_pos] = '0'; hex_pos += 1;
        hex_buf[hex_pos] = '0'; hex_pos += 1;
        hex_buf[hex_pos] = '0'; hex_pos += 1;
        hex_buf[hex_pos] = 'F'; hex_pos += 1;
        hex_buf[hex_pos] = 'F'; hex_pos += 1;
        hex_buf[hex_pos] = 'F'; hex_pos += 1;
        hex_buf[hex_pos] = '\n'; hex_pos += 1;
        self.len = hex_pos;
        @memcpy(self.buf[0..hex_pos], hex_buf[0..hex_pos]);
    }

    pub fn buildBinary(self: *CodeBuffer, flash_size: usize) void {
        const code_len = self.len;
        if (code_len >= flash_size) return;
        @memset(self.buf[code_len..flash_size], 0);
        self.len = flash_size;
    }
};

pub const A0: u8 = 22;
pub const A1: u8 = 23;
pub const A2: u8 = 24;
pub const A3: u8 = 25;
pub const T0: u8 = 18;
pub const T1: u8 = 19;
pub const T2: u8 = 20;
pub const T3: u8 = 21;
pub const R0: u8 = 0;
pub const R1: u8 = 1;
pub const YL: u8 = 28;
pub const YH: u8 = 29;
pub const ZL: u8 = 30;
pub const ZH: u8 = 31;
pub const Y: u8 = 28;
pub const Z: u8 = 30;
pub const SP: u8 = 0;
pub const SPL: u8 = 0x3D;
pub const SPH: u8 = 0x3E;
pub const RAMEND: u16 = 0x08FF;
