; k20cfg - Kolibri 2.0 settings tool
;
; Works on the persistent settings files below /sys (which is the boot
; partition's system directory in Kolibri 2.0 disk mode):
;
;   k20cfg kbd <n>       set the startlng digit in settings/lang.ini
;                        (1=En 2=Fi 3=Ge 4=Ru 5=Fr 6=Et 7=Ua 8=It 9=Be;
;                        @TASKBAR loads the matching layout from keymap.key
;                        on the next boot)
;   k20cfg wallp <path>  set [style]/bg_param=\S__<path> and
;                        bg_program=/sys/media/kiv in settings/system.ini
;                        (eskin runs kiv with the param on the next boot)
;   k20cfg kbdload <n>   apply layout <n> from settings/keymap.key right
;                        away via SF21.2 (the stock @TASKBAR reads
;                        startlng as ONE digit and caps layouts at 9, so
;                        this is how Kolibri 2.0 selects the Turkish
;                        layout 10 at boot; layouts 1..9 also work)
;   k20cfg check         dump the three active keymap tables (SF26.2)
;                        to /sys/K20CFG.BIN so the host can verify which
;                        layout the running kernel actually has
;
; lang.ini is patched in place, byte 0x16: @TASKBAR reads it with
; hardcoded byte offsets (MOI.INC load_ini), so the stock layout of the
; file must survive. system.ini is written through libini, the same way
; kiv does it, because eskin parses it with libini.
;
; Intended to be started from AUTORUN.DAT with a quoted parameter.
;
; Build: fasm k20cfg.asm k20cfg
; This file is part of Kolibri 2.0 (GPL-2.0, same as the repository).

use32
org 0x0

db 'MENUET01'               ; 8-byte signature
dd 0x01                     ; header version
dd _start                   ; entry point
dd _image_end               ; end of file image (code + data)
dd _mem_end                 ; total memory to allocate (image + bss + stack)
dd _mem_end                 ; stack top
dd params                   ; program parameters
dd 0x0                      ; current directory path buffer

include '../../proc32.inc'
include '../../macros.inc'
include '../../dll.inc'

_start:
        mcall   68, 11              ; init heap
        stdcall dll.Load, @IMPORT
        test    eax, eax
        jnz     exit

        mov     esi, params

        cmp     dword [esi], 'kbd '
        je      do_kbd
        cmp     dword [esi], 'kbdl'
        jne     .not_kbdload
        cmp     dword [esi+4], 'oad '
        jne     .not_kbdload
        jmp     do_kbdload
.not_kbdload:
        cmp     dword [esi], 'chec'
        jne     .not_check
        cmp     word [esi+4], 'k'
        je      do_check
.not_check:
        cmp     dword [esi], 'wall'
        jne     exit
        cmp     byte [esi+4], 'p'
        jne     exit
        cmp     byte [esi+5], ' '
        jne     exit

; --- wallp <path>: path is the rest of the parameter string ---
do_wallp:
        mov     dword [buf_wallp], '\S__'
        mov     esi, params+6
        mov     edi, buf_wallp+4
        xor     ecx, ecx
.cp:    lodsb
        stosb
        test    al, al
        jz      .cpd
        inc     ecx
        jmp     .cp
.cpd:   add     ecx, 4                ; ecx = '\S__' + path length
        invoke  ini_set_str, aSysIni, aStyle, aBgParam, buf_wallp, ecx
        invoke  ini_set_str, aSysIni, aStyle, aBgProg, aKiv, aKiv_len
        jmp     exit

; --- kbd <n>: patch the startlng digit at offset 0x16 of lang.ini ---
do_kbd:
        mov     byte [dbg_code], 1
        mov     esi, params+4
        xor     ebx, ebx
.digit: xor     eax, eax
        lodsb
        test    al, al
        jz      .got
        sub     al, '0'
        cmp     al, 9
        ja      .got                    ; any non-digit ends the number
        imul    ebx, ebx, 10
        add     ebx, eax
        jmp     .digit
.got:   mov     [dbg_parsed], bl
        test    ebx, ebx
        jz      .fail                   ; 0 is not a layout
        cmp     ebx, 9
        ja      .fail
        mov     [layout], bl
        ; read lang.ini
        mov     byte [dbg_code], 2
        mcall   70, fio_read
        mov     [dbg_read_eax], eax
        mov     [dbg_read_ebx], ebx
        test    eax, eax
        jz      .read_ok
        cmp     eax, 6                  ; ERROR_EOF: ebx bytes delivered
        jne     .fail
.read_ok:
        mov     [file_len], ebx
        cmp     ebx, 23
        jb      .fail
        ; sanity: byte 0x16 must be a layout digit in the stock file
        mov     al, [inicont_buf+0x16]
        mov     [dbg_byte16], al
        mov     byte [dbg_code], 4
        cmp     al, '1'
        jb      .fail
        cmp     al, '9'
        ja      .fail
        mov     al, [layout]
        add     al, '0'
        mov     [inicont_buf+0x16], al
        ; write the file back unchanged except that one byte
        mov     eax, [file_len]
        mov     [fio_write.size], eax
        mcall   70, fio_write
        mov     byte [dbg_code], 5
        jmp     exit
.fail:
        jmp     fail_dump

; --- kbdload <n>: apply layout n from keymap.key (works beyond 1..9) ---
do_kbdload:
        mov     byte [dbg_code], 11
        mov     esi, params+8
        xor     ebx, ebx
.digit: xor     eax, eax
        lodsb
        test    al, al
        jz      .got
        sub     al, '0'
        cmp     al, 9
        ja      .got                    ; any non-digit ends the number
        imul    ebx, ebx, 10
        add     ebx, eax
        jmp     .digit
.got:   mov     [dbg_parsed], bl
        test    ebx, ebx
        jz      .fail                   ; 0 is not a layout
        cmp     ebx, 255
        ja      .fail
        ; read keymap.key (eax=6 ERROR_EOF is fine, ebx = bytes read)
        mov     byte [dbg_code], 12
        mcall   70, fio_km
        mov     [dbg_read_eax], eax
        mov     [dbg_read_ebx], ebx
        test    eax, eax
        jz      .read_ok
        cmp     eax, 6
        jne     .fail
.read_ok:
        mov     [file_len], ebx
        ; bounds: layout n needs bytes (n-1)*384 .. n*384 of the file
        mov     byte [dbg_code], 13
        movzx   ebx, byte [dbg_parsed]
        dec     ebx
        imul    ebx, ebx, 384
        add     ebx, 384
        cmp     ebx, [file_len]
        ja      .fail
        sub     ebx, 384                ; ebx = table offset in km_buf
        mov     [km_off], ebx           ; mcall loads ebx=2, save the offset!
        ; apply the three tables - the same SF21.2 calls @TASKBAR uses
        lea     edx, [km_buf + ebx]
        mcall   21, 2, 1
        mov     ebx, [km_off]
        lea     edx, [km_buf + ebx + 128]
        mcall   21, 2, 2
        mov     ebx, [km_off]
        lea     edx, [km_buf + ebx + 256]
        mcall   21, 2, 3
        mov     byte [dbg_code], 15
        jmp     exit
.fail:
        jmp     fail_dump

; --- shared failure dump: K20DBG.BIN tells the host exactly where a
; --- kbd/kbdload run stopped (see the diagnostic block below) ---
fail_dump:
        mov     esi, params
        mov     edi, dbg_params
        mov     ecx, 12                 ; 48 bytes of the raw parameter string
        rep movsb
        mov     eax, [file_len]
        mov     [dbg_file_len], eax
        mcall   70, fio_dbg
        jmp     exit

; --- check: dump the active keymap tables ---
do_check:
        mcall   26, 2, 1, keymap_buf
        mcall   26, 2, 2, keymap_buf+128
        mcall   26, 2, 3, keymap_buf+256
        mcall   70, fio_check

exit:
        mcall   -1

align 4
fio_read:
        dd 0                        ; subfunction 0: read
        dd 0                        ; offset lo
        dd 0                        ; offset hi
        dd 512                      ; number of bytes to read
        dd inicont_buf              ; buffer
        db '/sys/settings/lang.ini', 0

fio_write:
        dd 2                        ; subfunction 2: create/rewrite
        dd 0                        ; offset lo
        dd 0                        ; offset hi
.size:  dd 512                      ; replaced with the real length
        dd inicont_buf              ; buffer
        db '/sys/settings/lang.ini', 0

fio_check:
        dd 2                        ; subfunction 2: create/rewrite
        dd 0                        ; offset lo
        dd 0                        ; offset hi
        dd 384                      ; three 128-byte tables
        dd keymap_buf               ; buffer
        db '/sys/K20CFG.BIN', 0

fio_dbg:
        dd 2                        ; subfunction 2: create/rewrite
        dd 0                        ; offset lo
        dd 0                        ; offset hi
        dd 80                       ; diagnostic block
        dd dbg_code                 ; buffer
        db '/sys/K20DBG.BIN', 0

fio_km:
        dd 0                        ; subfunction 0: read
        dd 0                        ; offset lo
        dd 0                        ; offset hi
        dd 16384                    ; number of bytes to read
        dd km_buf                   ; buffer
        db '/sys/settings/keymap.key', 0

aSysIni   db '/sys/settings/system.ini', 0
aStyle    db 'style', 0
aBgParam  db 'bg_param', 0
aBgProg   db 'bg_program', 0
aKiv      db '/sys/media/kiv', 0
aKiv_len  = $ - aKiv - 1

align 4
@IMPORT:
library libini, 'libini.obj'
import  libini, \
        ini_set_str, 'ini_set_str'

_image_end:

align 4
params     rb 256
buf_wallp  rb 264
keymap_buf rb 384
inicont_buf rb 512
km_buf     rb 16384
layout     rb 1
file_len   rd 1
km_off     rd 1

; diagnostic block dumped to /sys/K20DBG.BIN when "kbd" fails:
; code (1=parse 2=read 4=sanity), parsed digit, byte 0x16 as read,
; SF70.0 return values, file length, raw params string
dbg_code     rb 1
dbg_parsed   rb 1
dbg_byte16   rb 1
             rb 1
dbg_read_eax rd 1
dbg_read_ebx rd 1
dbg_file_len rd 1
dbg_params   rb 48

align 16
_mem_end = $ + 0x2000
