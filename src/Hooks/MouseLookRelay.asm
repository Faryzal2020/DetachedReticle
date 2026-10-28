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
    ; Stack frame allocation: 88h bytes (136 bytes).
    ; 8 + 136 = 144, 144 % 16 == 0 (16-byte aligned for call).
    sub rsp, 88h
    movaps [rsp+20h], xmm0
    movaps [rsp+30h], xmm1
    movaps [rsp+40h], xmm2
    movaps [rsp+50h], xmm3
    mov [rsp+60h], rax
    mov [rsp+68h], rcx
    mov [rsp+70h], rdx
    mov [rsp+78h], r8

    ; Spill xmm6 (raw yaw delta) and xmm7 (raw pitch delta) to stack variables
    movss dword ptr [rsp+80h], xmm6
    movss dword ptr [rsp+84h], xmm7

    ; Invoke OnNativeMouseAim(rcx, &yawDelta, &pitchDelta)
    ; rcx = context pointer
    lea rdx, [rsp+80h]
    lea r8,  [rsp+84h]
    call OnNativeMouseAim

    ; Retrieve updated chase deltas back into xmm6 and xmm7
    movss xmm6, dword ptr [rsp+80h]
    movss xmm7, dword ptr [rsp+84h]

    ; Restore preserved registers
    movaps xmm0, [rsp+20h]
    movaps xmm1, [rsp+30h]
    movaps xmm2, [rsp+40h]
    movaps xmm3, [rsp+50h]
    mov rax, [rsp+60h]
    mov rcx, [rsp+68h]
    mov rdx, [rsp+70h]
    mov r8,  [rsp+78h]
    add rsp, 88h

    ; Execute displaced instruction: write smoothed yaw delta to accumulator
    movss dword ptr [rcx+9Ch], xmm6

    ; Return to 0x51D467 (which executes 3 NOPs and continues to 0x51D46A)
    ret
MouseLookRelay endp

end
