; k20marker - Kolibri 2.0 persistence test utility
;
; Writes two marker files to the boot partition (/hd0/1) using SF70.2
; and then requests a clean power-off (SF18.9) so the kernel flushes
; its disk caches. Intended to be started from AUTORUN.DAT.
;
; Build: fasm k20marker.asm k20marker
; This file is part of Kolibri 2.0 (GPL-2.0, same as the repository).

use32
org 0x0

db 'MENUET01'               ; 8-byte signature
dd 0x01                     ; header version
dd _start                   ; entry point
dd _image_end               ; end of file image (code + data)
dd _mem_end                 ; total memory to allocate (image + stack)
dd _mem_end                 ; stack top
dd 0x0                      ; program parameters
dd 0x0                      ; current directory path buffer

APP_STACK = 0x1000

_start:
        ; --- write /hd0/1/persist1.txt ---
        mov     eax, 70             ; SF70: file system
        mov     ebx, fio1           ; SF70.2: create/rewrite
        int     0x40
        mov     [result1], eax

        ; --- write /hd0/1/persist2.txt ---
        mov     eax, 70
        mov     ebx, fio2
        int     0x40
        mov     [result2], eax

        ; --- request clean power-off so caches get flushed ---
        mov     eax, 18             ; SF18: system
        mov     ebx, 9              ; subfunction 9: shutdown
        mov     ecx, 2              ; 2 = power off
        int     0x40

        ; if shutdown did not happen, just exit
        mov     eax, -1
        int     0x40

align 4
fio1:
        dd 2                       ; subfunction 2: create/rewrite
        dd 0                       ; offset lo
        dd 0                       ; offset hi
        dd msg1_len                ; number of bytes to write
        dd msg1                    ; buffer
        db '/hd0/1/persist1.txt', 0

fio2:
        dd 2
        dd 0
        dd 0
        dd msg2_len
        dd msg2
        db '/hd0/1/persist2.txt', 0

result1 dd ?
result2 dd ?

msg1    db 'kolibri 2.0 persistence marker 1', 13, 10
msg1_len = $ - msg1
msg2    db 'kolibri 2.0 persistence marker 2 - a slightly longer line to make the second file different', 13, 10
msg2_len = $ - msg2

_image_end:

align 16
_mem_end = _image_end + APP_STACK
