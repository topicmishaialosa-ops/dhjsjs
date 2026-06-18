pub const CodeBuffer = struct {
    buf: [65536]u8,
    pos: usize,

    pub fn init() CodeBuffer {
        return CodeBuffer{ .buf = undefined, .pos = 0 };
    }

    pub fn get(self: *const CodeBuffer) []const u8 {
        return self.buf[0..self.pos];
    }

    pub fn getMut(self: *CodeBuffer) []u8 {
        return self.buf[0..self.pos];
    }

    pub fn byte(self: *CodeBuffer, b: u8) void {
        if (self.pos < self.buf.len) { self.buf[self.pos] = b; self.pos += 1; }
    }

    pub fn word(self: *CodeBuffer, w: u16) void {
        self.byte(@as(u8, @truncate(w)));
        self.byte(@as(u8, @truncate(w >> 8)));
    }

    pub fn dword(self: *CodeBuffer, dw: u32) void {
        self.byte(@as(u8, @truncate(dw)));
        self.byte(@as(u8, @truncate(dw >> 8)));
        self.byte(@as(u8, @truncate(dw >> 16)));
        self.byte(@as(u8, @truncate(dw >> 24)));
    }

    pub fn qword(self: *CodeBuffer, qw: u64) void {
        self.dword(@as(u32, @truncate(qw)));
        self.dword(@as(u32, @truncate(qw >> 32)));
    }

    pub fn modrm(self: *CodeBuffer, mod: u8, reg: u8, rm: u8) void {
        self.byte((mod << 6) | ((reg & 7) << 3) | (rm & 7));
    }

    pub fn movRImm64(self: *CodeBuffer, reg: u8, val: u64) void {
        var r = reg;
        if (r >= 8) { self.byte(0x49); r -= 8; } else { self.byte(0x48); }
        self.byte(0xB8 | (r & 7));
        self.qword(val);
    }

    pub fn xorRR(self: *CodeBuffer, dst: u8, src: u8) void {
        var d = dst; var s = src;
        if (d >= 8 or s >= 8) { self.byte(if (d >= 8) 0x4D else 0x49); d &= 7; s &= 7; } else { self.byte(0x48); }
        self.byte(0x31);
        self.modrm(3, s & 7, d & 7);
    }

    pub fn syscall(self: *CodeBuffer) void {
        self.byte(0x0F);
        self.byte(0x05);
    }

    pub fn ret(self: *CodeBuffer) void {
        self.byte(0xC3);
    }

    pub fn movRImm32(self: *CodeBuffer, reg: u8, val: u32) void {
        var r = reg;
        if (r >= 8) { self.byte(0x41); r -= 8; } else { self.byte(0x48); }
        self.byte(0xB8 | (r & 7));
        self.dword(val);
    }
};

pub const RAX: u8 = 0;
pub const RCX: u8 = 1;
pub const RDX: u8 = 2;
pub const RBX: u8 = 3;
pub const RSP: u8 = 4;
pub const RBP: u8 = 5;
pub const RSI: u8 = 6;
pub const RDI: u8 = 7;
pub const R8: u8 = 8;
pub const R9: u8 = 9;
pub const R10: u8 = 10;
pub const R11: u8 = 11;
pub const R12: u8 = 12;
pub const R13: u8 = 13;
pub const R14: u8 = 14;
pub const R15: u8 = 15;

pub fn buildElf64(cb: *CodeBuffer) void {
    const code = cb.get();
    const entry_off = @as(u64, @intCast(64 + 56));
    const code_align: usize = 4096;
    const code_sz = ((code.len + code_align - 1) / code_align) * code_align;

    cb.pos = 0;
    // ELF header (64 bytes)
    cb.byte(0x7F); cb.byte('E'); cb.byte('L'); cb.byte('F');
    cb.byte(2); cb.byte(1); cb.byte(1); cb.byte(0);
    cb.qword(0); // padding
    cb.word(2); // ET_EXEC
    cb.word(0x3E); // x86_64
    cb.dword(1);
    cb.qword(0x400000 + entry_off); // entry
    cb.qword(64); // phoff
    cb.qword(0); // shoff
    cb.dword(0);
    cb.word(64);
    cb.word(56);
    cb.word(1);
    cb.word(0);
    cb.word(0);
    cb.word(0);

    // PHDR (56 bytes)
    cb.dword(1); // PT_LOAD
    cb.dword(7); // flags
    cb.qword(0); // offset
    cb.qword(0x400000); // vaddr
    cb.qword(0x400000); // paddr
    cb.qword(@as(u64, @intCast(code_sz))); // filesz
    cb.qword(@as(u64, @intCast(code_sz))); // memsz
    cb.qword(code_align); // align

    // Code
    var i: usize = 0;
    while (i < code.len) : (i += 1) cb.byte(code[i]);
    while (cb.pos < 64 + 56 + code_sz) : (cb.pos += 1) cb.buf[cb.pos] = 0;
}
