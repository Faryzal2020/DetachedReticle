.code

extern OnNativeMouseAim:proc

; Hook relay for Cyberpunk2077.exe RVA 0x51D462 (Gameplay Look Integrator)
; Replaces 8 bytes: F3 0F 11 B1 9C 00 00 00 (movss [rcx+9Ch], xmm6)
; Inputs from caller:
;   rcx:   Player puppet orientation accumulator object ([rax+8])
;   xmm6:  yawDelta (float) - mouse X delta
;   xmm7:  pitchDelta (float) - mouse Y delta
; Stack layout on entry:
;   [rsp]: return address to 0x51D467 (rsp % 16 == 8)

MouseLookRelay proc
    ; Stack frame allocation: 0D8h bytes (216 bytes).
    ; 8 (ret addr) + 216 = 224, 224 % 16 == 0 (16-byte aligned for call).
    sub rsp, 0D8h

    ; Preserve volatile XMM registers (16-byte aligned offsets)
    movaps [rsp+20h], xmm0
    movaps [rsp+30h], xmm1
    movaps [rsp+40h], xmm2
    movaps [rsp+50h], xmm3
    movaps [rsp+60h], xmm4
    movaps [rsp+70h], xmm5

    ; Preserve volatile General Purpose registers
    mov [rsp+80h], rax
    mov [rsp+88h], rcx
    mov [rsp+90h], rdx
    mov [rsp+98h], r8
    mov [rsp+0A0h], r9
    mov [rsp+0A8h], r10
    mov [rsp+0B0h], r11

    ; Spill xmm6 (raw yaw delta) and xmm7 (raw pitch delta) to stack variables
    movss dword ptr [rsp+0C0h], xmm6
    movss dword ptr [rsp+0C4h], xmm7

    ; Invoke OnNativeMouseAim(rcx, &yawDelta, &pitchDelta)
    ; rcx = context pointer
    lea rdx, [rsp+0C0h]
    lea r8,  [rsp+0C4h]
    call OnNativeMouseAim

    ; Retrieve updated chase deltas back into xmm6 and xmm7
    movss xmm6, dword ptr [rsp+0C0h]
    movss xmm7, dword ptr [rsp+0C4h]

    ; Restore preserved volatile registers
    movaps xmm0, [rsp+20h]
    movaps xmm1, [rsp+30h]
    movaps xmm2, [rsp+40h]
    movaps xmm3, [rsp+50h]
    movaps xmm4, [rsp+60h]
    movaps xmm5, [rsp+70h]

    mov rax, [rsp+80h]
    mov rcx, [rsp+88h]
    mov rdx, [rsp+90h]
    mov r8,  [rsp+98h]
    mov r9,  [rsp+0A0h]
    mov r10, [rsp+0A8h]
    mov r11, [rsp+0B0h]

    add rsp, 0D8h

    ; Execute displaced instruction: write smoothed yaw delta to accumulator
    movss dword ptr [rcx+9Ch], xmm6

    ; Return to 0x51D467 (which executes 3 NOPs and continues to 0x51D46A)
    ret
MouseLookRelay endp

end
