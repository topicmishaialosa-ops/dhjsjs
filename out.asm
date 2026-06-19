section .text
global _start

_start:
    mov rax, 60
    xor rdi, rdi
    syscall

main:
    ; let x = 42
    ; let name = dhjsjs
    mov rax, x
    ret
    ret

    ; <unknown>
