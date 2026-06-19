pub const CodeBuffer = struct {
    buf: [65536]u8,
    pos: usize,

    pub fn init() CodeBuffer {
        return CodeBuffer{ .buf = undefined, .pos = 0 };
    }

    pub fn get(self: *const CodeBuffer) []const u8 {
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

    pub fn modrm(self: *CodeBuffer, mod_: u8, reg: u8, rm: u8) void {
        self.byte((mod_ << 6) | ((reg & 7) << 3) | (rm & 7));
    }

    pub fn rex_w(self: *CodeBuffer, r: u8, x: u8, b: u8) void {
        self.byte(0x48 | (r << 2) | (x << 1) | b);
    }

    pub fn rex_wb(self: *CodeBuffer, r: u8, b: u8) void {
        self.rex_w(r, 0, b);
    }

    fn rex_if(self: *CodeBuffer, r: u8, rm: u8) void {
        if (r >= 8 or rm >= 8) self.rex_wb(if (r >= 8) 1 else 0, if (rm >= 8) 1 else 0);
    }

    pub fn pushR(self: *CodeBuffer, r: u8) void {
        if (r >= 8) { self.byte(0x41); self.byte(0x50 | (r & 7)); }
        else { self.byte(0x50 | r); }
    }

    pub fn popR(self: *CodeBuffer, r: u8) void {
        if (r >= 8) { self.byte(0x41); self.byte(0x58 | (r & 7)); }
        else { self.byte(0x58 | r); }
    }

    pub fn movRR(self: *CodeBuffer, dst: u8, src: u8) void {
        if (dst == src) return;
        self.rex_w(@as(u8, @intCast(src >> 3)), 0, @as(u8, @intCast(dst >> 3)));
        self.byte(0x89);
        self.modrm(3, src, dst);
    }

    pub fn movRImm64(self: *CodeBuffer, r: u8, val: u64) void {
        self.rex_w(0, 0, @as(u8, @intCast(r >> 3)));
        self.byte(0xB8 | (r & 7));
        self.qword(val);
    }

    pub fn movRImm32(self: *CodeBuffer, r: u8, val: u32) void {
        if (r >= 8) self.byte(0x41);
        self.byte(0xB8 | (r & 7));
        self.dword(val);
    }

    pub fn movRMem64(self: *CodeBuffer, r: u8, base: u8, off: i32) void {
        self.rex_w(@as(u8, @intCast(r >> 3)), 0, @as(u8, @intCast(base >> 3)));
        self.byte(0x8B);
        if (off == 0) {
            self.modrm(0, r, base);
        } else if (off >= -128 and off <= 127) {
            self.modrm(1, r, base);
        } else {
            self.modrm(2, r, base);
        }
        if (base == RSP or base == R12) self.byte(0x24);
        if (off >= -128 and off <= 127 and off != 0) {
            self.byte(@as(u8, @bitCast(@as(i8, @intCast(off)))));
        } else if (off != 0) {
            self.dword(@as(u32, @bitCast(off)));
        }
    }

    pub fn movMemR64(self: *CodeBuffer, base: u8, off: i32, r: u8) void {
        self.rex_w(@as(u8, @intCast(r >> 3)), 0, @as(u8, @intCast(base >> 3)));
        self.byte(0x89);
        if (off == 0) {
            self.modrm(0, r, base);
        } else if (off >= -128 and off <= 127) {
            self.modrm(1, r, base);
        } else {
            self.modrm(2, r, base);
        }
        if (base == RSP or base == R12) self.byte(0x24);
        if (off >= -128 and off <= 127 and off != 0) {
            self.byte(@as(u8, @bitCast(@as(i8, @intCast(off)))));
        } else if (off != 0) {
            self.dword(@as(u32, @bitCast(off)));
        }
    }

    pub fn movRAReg(self: *CodeBuffer, r: u8, addr: u32) void {
        self.byte(0x48 | (if (r >= 8) 1 else 0));
        self.byte(0xA1);
        self.qword(addr);
    }

    pub fn addRR(self: *CodeBuffer, dst: u8, src: u8) void {
        self.rex_w(@as(u8, @intCast(src >> 3)), 0, @as(u8, @intCast(dst >> 3)));
        self.byte(0x01);
        self.modrm(3, src, dst);
    }

    pub fn subRR(self: *CodeBuffer, dst: u8, src: u8) void {
        self.rex_if(dst, src);
        self.byte(0x29);
        self.modrm(3, src, dst);
    }

    pub fn addRImm32(self: *CodeBuffer, r: u8, val: i32) void {
        if (val >= -128 and val <= 127) {
            self.rex_wb(0, if (r >= 8) 1 else 0);
            self.byte(0x83);
            self.modrm(3, 0, r);
            self.byte(@as(u8, @bitCast(@as(i8, @intCast(val)))));
        } else {
            self.rex_wb(0, if (r >= 8) 1 else 0);
            self.byte(0x81);
            self.modrm(3, 0, r);
            self.dword(@as(u32, @bitCast(val)));
        }
    }

    pub fn subRImm32(self: *CodeBuffer, r: u8, val: i32) void {
        if (val >= -128 and val <= 127) {
            self.rex_wb(0, if (r >= 8) 1 else 0);
            self.byte(0x83);
            self.modrm(3, 5, r);
            self.byte(@as(u8, @bitCast(@as(i8, @intCast(val)))));
        } else {
            self.rex_wb(0, if (r >= 8) 1 else 0);
            self.byte(0x81);
            self.modrm(3, 5, r);
            self.dword(@as(u32, @bitCast(val)));
        }
    }

    pub fn xorRR(self: *CodeBuffer, dst: u8, src: u8) void {
        self.rex_if(dst, src);
        self.byte(0x31);
        self.modrm(3, src, dst);
    }

    pub fn cmpRImm32(self: *CodeBuffer, r: u8, val: i32) void {
        if (val >= -128 and val <= 127) {
            self.rex_if(r, 0);
            self.byte(0x83);
            self.modrm(3, 7, r);
            self.byte(@as(u8, @bitCast(@as(i8, @intCast(val)))));
        } else {
            self.rex_if(r, 0);
            self.byte(0x81);
            self.modrm(3, 7, r);
            self.dword(@as(u32, @bitCast(val)));
        }
    }

    pub fn imulRR(self: *CodeBuffer, dst: u8, src: u8) void {
        self.rex_if(dst, src);
        self.byte(0x0F);
        self.byte(0xAF);
        self.modrm(3, dst, src);
    }

    pub fn cqo(self: *CodeBuffer) void {
        self.rex_w(0, 0, 0);
        self.byte(0x99);
    }

    pub fn idivR(self: *CodeBuffer, r: u8) void {
        self.rex_w(0, 0, @as(u8, @intCast(r >> 3)));
        self.byte(0xF7);
        self.modrm(3, 7, r);
    }

    pub fn andRR(self: *CodeBuffer, dst: u8, src: u8) void {
        self.rex_if(dst, src);
        self.byte(0x21);
        self.modrm(3, src, dst);
    }

    pub fn orRR(self: *CodeBuffer, dst: u8, src: u8) void {
        self.rex_if(dst, src);
        self.byte(0x09);
        self.modrm(3, src, dst);
    }

    pub fn negR(self: *CodeBuffer, r: u8) void {
        self.rex_w(0, 0, @as(u8, @intCast(r >> 3)));
        self.byte(0xF7);
        self.modrm(3, 3, r);
    }

    pub fn notR(self: *CodeBuffer, r: u8) void {
        self.rex_w(0, 0, @as(u8, @intCast(r >> 3)));
        self.byte(0xF7);
        self.modrm(3, 2, r);
    }

    pub fn shlRcl(self: *CodeBuffer, r: u8) void {
    self.rex_w(0, 0, @as(u8, @intCast(r >> 3)));
    self.byte(0xD3);
    self.modrm(3, 4, r);
}

pub fn shrRcl(self: *CodeBuffer, r: u8) void {
    self.rex_w(0, 0, @as(u8, @intCast(r >> 3)));
    self.byte(0xD3);
    self.modrm(3, 5, r);
}

pub fn shlRImm8(self: *CodeBuffer, r: u8, imm: u8) void {
    if (imm == 0) return;
    self.rex_w(0, 0, @as(u8, @intCast(r >> 3)));
    self.byte(0xC1);
    self.modrm(3, 4, r);
    self.byte(imm);
}

pub fn pushfq(self: *CodeBuffer) void {
        self.byte(0x9C);
    }

    pub fn popfq(self: *CodeBuffer) void {
        self.byte(0x9D);
    }

    pub fn sete(self: *CodeBuffer, r: u8) void {
        self.byte(0x0F);
        self.byte(0x94);
        self.modrm(3, 0, r);
    }

    pub fn setne(self: *CodeBuffer, r: u8) void {
        self.byte(0x0F);
        self.byte(0x95);
        self.modrm(3, 0, r);
    }

    pub fn setl(self: *CodeBuffer, r: u8) void {
        self.byte(0x0F);
        self.byte(0x9C);
        self.modrm(3, 0, r);
    }

    pub fn setg(self: *CodeBuffer, r: u8) void {
        self.byte(0x0F);
        self.byte(0x9F);
        self.modrm(3, 0, r);
    }

    pub fn setle(self: *CodeBuffer, r: u8) void {
        self.byte(0x0F);
        self.byte(0x9E);
        self.modrm(3, 0, r);
    }

    pub fn setge(self: *CodeBuffer, r: u8) void {
        self.byte(0x0F);
        self.byte(0x9D);
        self.modrm(3, 0, r);
    }

    pub fn cmpRR(self: *CodeBuffer, a: u8, b: u8) void {
        self.rex_if(b, a);
        self.byte(0x39);
        self.modrm(3, b, a);
    }

    pub fn jmpRel32(self: *CodeBuffer, off: i32) void {
        self.byte(0xE9);
        self.dword(@as(u32, @bitCast(off)));
    }

    pub fn jmpRel8(self: *CodeBuffer, off: i8) void {
        self.byte(0xEB);
        self.byte(@as(u8, @bitCast(off)));
    }

    fn jcc32(self: *CodeBuffer, cc: u8, off: i32) void {
        self.byte(0x0F);
        self.byte(0x80 | cc);
        self.dword(@as(u32, @bitCast(off)));
    }

    fn jcc8(self: *CodeBuffer, cc: u8, off: i8) void {
        self.byte(0x70 | cc);
        self.byte(@as(u8, @bitCast(off)));
    }

    pub fn jeRel32(self: *CodeBuffer, off: i32) void { self.jcc32(0x04, off); }
    pub fn jneRel32(self: *CodeBuffer, off: i32) void { self.jcc32(0x05, off); }
    pub fn jlRel32(self: *CodeBuffer, off: i32) void { self.jcc32(0x0C, off); }
    pub fn jleRel32(self: *CodeBuffer, off: i32) void { self.jcc32(0x0E, off); }
    pub fn jgRel32(self: *CodeBuffer, off: i32) void { self.jcc32(0x0F, off); }
    pub fn jgeRel32(self: *CodeBuffer, off: i32) void { self.jcc32(0x0D, off); }
    pub fn jeRel8(self: *CodeBuffer, off: i8) void { self.jcc8(0x04, off); }
    pub fn jneRel8(self: *CodeBuffer, off: i8) void { self.jcc8(0x05, off); }

    pub fn callRel32(self: *CodeBuffer, off: i32) void {
        self.byte(0xE8);
        self.dword(@as(u32, @bitCast(off)));
    }

    pub fn syscall(self: *CodeBuffer) void {
        self.byte(0x0F);
        self.byte(0x05);
    }

    pub fn ret(self: *CodeBuffer) void {
        self.byte(0xC3);
    }

    pub fn movImm16RSP(self: *CodeBuffer, off: u8, val: u16) void {
        self.byte(0x66);
        self.byte(0xC7);
        if (off == 0) { self.byte(0x04); self.byte(0x24); }
        else { self.byte(0x44); self.byte(0x24); self.byte(off); }
        self.word(val);
    }

    pub fn movImm32RSP(self: *CodeBuffer, off: u8, val: u32) void {
        self.byte(0xC7);
        if (off == 0) { self.byte(0x04); self.byte(0x24); }
        else { self.byte(0x44); self.byte(0x24); self.byte(off); }
        self.dword(val);
    }

    pub fn leaRMem(self: *CodeBuffer, r: u8, base: u8, off: i32) void {
        self.rex_w(0, if (base >= 8) 1 else 0, if (r >= 8) 1 else 0);
        if (off == 0) {
            self.byte(0x8D);
            self.modrm(0, r, base);
            if (base == RSP or base == R12) self.byte(0x24);
        } else if (off >= -128 and off <= 127) {
            self.byte(0x8D);
            self.modrm(1, r, base);
            if (base == RSP or base == R12) self.byte(0x24);
            self.byte(@as(u8, @bitCast(@as(i8, @intCast(off)))));
        } else {
            self.byte(0x8D);
            self.modrm(2, r, base);
            if (base == RSP or base == R12) self.byte(0x24);
            self.dword(@as(u32, @bitCast(off)));
        }
    }

    pub fn bytes(self: *CodeBuffer, data: []const u8) void {
        var i: usize = 0;
        while (i < data.len and self.pos < self.buf.len) : (i += 1) {
            self.buf[self.pos] = data[i];
            self.pos += 1;
        }
    }

    pub fn buildPe64(self: *CodeBuffer) void {
        const code_len = self.pos;
        if (code_len < 6) return;

        var code_copy: [65536]u8 = undefined;
        var ci: usize = 0;
        while (ci < code_len) : (ci += 1) code_copy[ci] = self.buf[ci];

        // Find `mov rax, 60; syscall` (48 B8 3C 00 00 00 00 00 00 00 0F 05)
        var exit_pos: usize = 0;
        var found = false;
        {
            var i: usize = 0;
            while (i < code_len - 12) : (i += 1) {
                if (code_copy[i] == 0x48 and code_copy[i+1] == 0xB8 and
                    code_copy[i+2] == 0x3C and code_copy[i+9] == 0x00 and
                    code_copy[i+10] == 0x0F and code_copy[i+11] == 0x05)
                {
                    exit_pos = i;
                    found = true;
                    break;
                }
            }
        }

        const has_main_entry = found and exit_pos >= 3 and
            code_copy[exit_pos - 3] == 0x48 and
            code_copy[exit_pos - 2] == 0x89 and
            code_copy[exit_pos - 1] == 0xC7;

        // Replace exit syscall with NOPs + RET (entry point return = process exit)
        // RAX already contains the return value from main, just RET
        if (found) {
            if (has_main_entry) {
                // Exit sequence: mov rdi,rax (3) + mov rax,60 (10) + syscall (2) = 15 bytes
                // Replace with NOPs + RET
                var p: usize = exit_pos - 3;
                const end = exit_pos + 12; // 15 bytes total
                while (p < end - 1) : (p += 1) code_copy[p] = 0x90;
                code_copy[end - 1] = 0xC3; // RET
            } else {
                // No main: mov rdi,0 (10) + mov rax,60 (10) + syscall (2) = 22 bytes
                // Find mov rdi,0 before exit_pos
                var p: usize = 0;
                while (p < exit_pos and p < code_len) : (p += 1) {
                    if (code_copy[p] == 0x48 and p + 9 < code_len and code_copy[p + 1] == 0xBF) {
                        // Found mov rdi, imm64 - replace with xor eax,eax + NOPs + RET
                        code_copy[p] = 0x31; // xor eax, eax
                        code_copy[p + 1] = 0xC0;
                        var k: usize = p + 2;
                        while (k < exit_pos + 12 - 1) : (k += 1) code_copy[k] = 0x90;
                        code_copy[exit_pos + 12 - 1] = 0xC3; // RET
                        break;
                    }
                }
            }
        }

        const file_align: u32 = 0x200;
        const sect_align: u32 = 0x1000;
        const headers_size: u32 = 0x200;

        const text_rva: u32 = 0x1000;
        const text_raw: u32 = headers_size;
        const text_file_sz: u32 = ((@as(u32, @intCast(code_len)) + file_align - 1) / file_align) * file_align;
        const text_mem_sz: u32 = ((@as(u32, @intCast(code_len)) + sect_align - 1) / sect_align) * sect_align;

        const image_size: u32 = text_rva + text_mem_sz;
        const image_base: u64 = 0x140000000;
        const entry_rva: u32 = text_rva;

        // Build PE file
        self.pos = 0;

        // DOS Header (64 bytes)
        self.byte('M'); self.byte('Z');
        {
            var z: usize = 0;
            while (z < 58) : (z += 1) self.byte(0);
        }
        self.dword(0x80); // e_lfanew

        // DOS stub (64 bytes)
        {
            var z: usize = 0;
            while (z < 0x40) : (z += 1) self.byte(0);
        }

        // PE signature
        self.byte('P'); self.byte('E'); self.byte(0); self.byte(0);

        // COFF Header (20 bytes)
        self.word(0x8664);                // Machine: x86_64
        self.word(1);                      // NumberOfSections (only .text)
        self.dword(0);                     // TimeDateStamp
        self.dword(0);                     // PointerToSymbolTable
        self.dword(0);                     // NumberOfSymbols
        self.word(0xF0);                   // SizeOfOptionalHeader
        self.word(0x22);                   // Characteristics

        // Optional Header PE32+ (112 bytes)
        self.word(0x020B);                 // Magic
        self.byte(10);                      // MajorLinkerVersion
        self.byte(0);                      // MinorLinkerVersion
        self.dword(@as(u32, @intCast(code_len))); // SizeOfCode
        self.dword(0);                     // SizeOfInitializedData
        self.dword(0);                     // SizeOfUninitializedData
        self.dword(entry_rva);             // AddressOfEntryPoint
        self.dword(text_rva);              // BaseOfCode
        self.qword(image_base);            // ImageBase
        self.dword(sect_align);            // SectionAlignment
        self.dword(file_align);            // FileAlignment
        self.word(6);                      // MajorOSVersion
        self.word(0);                      // MinorOSVersion
        self.word(0);                      // MajorImageVersion
        self.word(0);                      // MinorImageVersion
        self.word(6);                      // MajorSubsystemVersion
        self.word(0);                      // MinorSubsystemVersion
        self.dword(0);                     // Win32VersionValue
        self.dword(image_size);            // SizeOfImage
        self.dword(headers_size);          // SizeOfHeaders
        self.dword(0);                     // CheckSum
        self.word(3);                      // Subsystem: WINDOWS_CUI
        self.word(0x0140);                 // DllCharacteristics
        self.qword(0x100000);             // SizeOfStackReserve
        self.qword(0x1000);               // SizeOfStackCommit
        self.qword(0x100000);             // SizeOfHeapReserve
        self.qword(0x1000);               // SizeOfHeapCommit
        self.dword(0);                     // LoaderFlags
        self.dword(16);                    // NumberOfRvaAndSizes

        // Data Directory (128 bytes, all empty = no imports needed)
        {
            var z: usize = 0;
            while (z < 16 * 8) : (z += 1) self.byte(0);
        }

        // Section: .text
        self.bytes(".text\x00\x00\x00");
        self.dword(@as(u32, @intCast(code_len)));  // VirtualSize
        self.dword(text_rva);
        self.dword(text_file_sz);
        self.dword(text_raw);
        self.dword(0); self.dword(0); self.word(0); self.word(0);
        self.dword(0x60000020); // CODE | EXECUTE | READ

        // Pad remaining headers to headers_size
        if (self.pos > headers_size) { self.pos = headers_size; }
        while (self.pos < headers_size) {
            self.byte(0);
        }

        // .text content
        ci = 0;
        while (ci < code_len) : (ci += 1) self.byte(code_copy[ci]);
        // Pad to file_align
        const text_end = text_raw + text_file_sz;
        while (self.pos < text_end) { self.byte(0); }
    }

    pub fn buildElf64(self: *CodeBuffer) void {
        const code_len = self.pos;
        const entry_off: u64 = 64 + 56;
        const page_align: u64 = 4096;
        const total_file_sz: u64 = 64 + 56 + code_len;
        const total_mem_sz = ((total_file_sz + page_align - 1) / page_align) * page_align;

        var code_copy: [65536]u8 = undefined;
        var ci: usize = 0;
        while (ci < code_len) : (ci += 1) code_copy[ci] = self.buf[ci];

        self.pos = 0;
        self.byte(0x7F); self.byte('E'); self.byte('L'); self.byte('F');
        self.byte(2); self.byte(1); self.byte(1); self.byte(0);
        self.qword(0);
        self.word(2);
        self.word(0x3E);
        self.dword(1);
        self.qword(0x400000 + entry_off);
        self.qword(64);
        self.qword(0);
        self.dword(0);
        self.word(64);
        self.word(56);
        self.word(1);
        self.word(0);
        self.word(0);
        self.word(0);

        self.dword(1);
        self.dword(7);
        self.qword(0);
        self.qword(0x400000);
        self.qword(0x400000);
        self.qword(total_file_sz);
        self.qword(total_mem_sz);
        self.qword(page_align);

        ci = 0;
        while (ci < code_len) : (ci += 1) self.byte(code_copy[ci]);
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
