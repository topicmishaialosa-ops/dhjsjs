const parser_mod = @import("parser.zig");

const OUTPUT_SIZE = 65536;

pub const Compiler = struct {
    buf: [OUTPUT_SIZE]u8,
    pos: usize,
    pool: *[parser_mod.MAX_NODES]parser_mod.AstNode,

    pub fn init(pool: *[parser_mod.MAX_NODES]parser_mod.AstNode) Compiler {
        return Compiler{
            .buf = undefined,
            .pos = 0,
            .pool = pool,
        };
    }

    pub fn getOutput(self: *const Compiler) []const u8 {
        return self.buf[0..self.pos];
    }

    fn write(self: *Compiler, data: []const u8) void {
        var i: usize = 0;
        while (i < data.len and self.pos + i < OUTPUT_SIZE) : (i += 1) {
            self.buf[self.pos + i] = data[i];
        }
        self.pos += i;
    }

    fn writeLine(self: *Compiler, s: []const u8) void {
        self.write(s);
        self.write("\n");
    }

    fn writeStr(self: *Compiler, ptr: [*]const u8, len: usize) void {
        var i: usize = 0;
        while (i < len and self.pos < OUTPUT_SIZE) : (i += 1) {
            self.buf[self.pos] = ptr[i];
            self.pos += 1;
        }
    }

    pub fn compileAsm(self: *Compiler) void {
        self.writeLine("section .text");
        self.writeLine("global _start");
        self.writeLine("");
        self.writeLine("_start:");
        self.writeLine("    mov rax, 60");
        self.writeLine("    xor rdi, rdi");
        self.writeLine("    syscall");
        self.writeLine("");

        var i: usize = 0;
        while (i < parser_mod.MAX_NODES) : (i += 1) {
            if (self.pool[i].kind == .program) {
                var child = self.pool[i].first_child;
                while (child != parser_mod.NO_NODE) {
                    self.compileNodeAsm(child);
                    child = self.pool[@intCast(child)].next_sibling;
                }
                break;
            }
        }
    }

    fn compileNodeAsm(self: *Compiler, idx: parser_mod.NodeIdx) void {
        const node = &self.pool[@intCast(idx)];
        switch (node.kind) {
            .fn_decl => {
                self.writeStr(node.name_start, node.name_len);
                self.write(":\n");
                var child = node.first_child;
                while (child != parser_mod.NO_NODE) {
                    self.compileNodeAsm(child);
                    child = self.pool[@intCast(child)].next_sibling;
                }
                self.writeLine("    ret");
                self.writeLine("");
            },
            .block => {
                var child = node.first_child;
                while (child != parser_mod.NO_NODE) {
                    self.compileNodeAsm(child);
                    child = self.pool[@intCast(child)].next_sibling;
                }
            },
            .let_decl => {
                self.write("    ; let ");
                self.writeStr(node.name_start, node.name_len);
                self.write(" = ");
                self.writeStr(node.val_start, node.val_len);
                self.writeLine("");
            },
            .ret_stmt => {
                self.write("    mov rax, ");
                self.writeStr(node.val_start, node.val_len);
                self.writeLine("");
                self.writeLine("    ret");
            },
            .call => {
                self.write("    call ");
                self.writeStr(node.name_start, node.name_len);
                self.writeLine("");
            },
            .state_decl => {
                self.write("    ; state ");
                self.writeStr(node.name_start, node.name_len);
                self.write(" = ");
                self.writeStr(node.val_start, node.val_len);
                self.writeLine("");
            },
            else => {
                self.writeLine("    ; <unknown>");
            },
        }
    }
};
