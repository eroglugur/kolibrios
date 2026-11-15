;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                                                              ;;
;; Copyright (C) KolibriOS team 2004-2024. All rights reserved. ;;
;;  Distributed under terms of the GNU General Public License.  ;;
;;                                                              ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


iglobal
full_file_name_table    dd  sysdir_name
.size                   dd  1
endg

uglobal
sysdir_name     rb  64  ; 'sys',0
sysdir_path     rb  64
sysdir_name1    rb  64
sysdir_path1    rb  64
endg
; Example:
; align 64
; sysdir_name1 db 'KolibriOS',0
; align 64
; sysdir_path1 db 'HD0/1',0

proc Parser_params
    locals
        buff    rb  4   ; for test cd
    endl
if defined extended_primary_loader
        mov     ecx, sysdir_path
        mov     [ecx-64], dword 'sys'
        mov     [ecx-2], byte 3
        mov     esi, BOOT.syspath
        mov     edi, sysdir_path-1
        mov     ecx, 20
        rep movsb
; Kolibri 2.0: syspath=AUTO - probe disks for the system directory
; so the same image boots on IDE (HDn) and AHCI/SD (SDn) machines.
; Probing cannot run here: AHCI disks are registered after this point,
; so only raise a flag; the kernel resolves it before its first
; /sys access (PS/2 driver load in kernel.asm).
        cmp     dword [sysdir_path-1], 'AUTO'
        jnz     .done
        cmp     byte [sysdir_path+3], 0
        jnz     .done
        mov     byte [syspath_auto], 1
; placeholder until all disks are up
        mov     esi, syspath_rd
        mov     edi, sysdir_path-1
        mov     ecx, 6
        rep movsb
.done:
        ret
else
        mov     ax, [BOOT.sys_disk]
        mov     ecx, sysdir_path
        mov     [ecx-64], dword 'sys'
        mov     [ecx-2], byte 3
        mov     [ecx-1], byte '/'
        cmp     al, 'r' ; ram disk
        jnz     @f
        mov     [ecx], dword 'RD/?'
        mov     [ecx+3], byte ah
        mov     [ecx+4], byte 0
        ret

@@:
        cmp     al, 'm'
        jnz     .hard_disk
        mov     [ecx], dword 'CD?/'
        mov     [ecx+4], byte '1'
        mov     [ecx+5], dword '/KOL'
        mov     [ecx+9], dword 'IBRI'
        mov     [ecx+13], byte 0
.next_cd:
        mov     [ecx+2], byte ah
        inc     ah
        cmp     ah, '5'
        je      @f
        lea     edx, [buff]
        pushad
        stdcall read_file, read_firstapp, edx, 0, 4
        popad
        cmp     [edx], dword 'MENU'
        jne     .next_cd
@@:
        ret

.hard_disk:
        sub     al, '1'
        mov     [ecx], dword 'HD?/'
        mov     [ecx+2], byte al
        mov     [ecx+4], byte ah
        mov     [ecx+5], dword '/KOL'
        mov     [ecx+9], dword 'IBRI'
        mov     [ecx+13], byte 0
        ret
end if

endp

iglobal
syspath_tail    db      '/KOLIBRIOS/LAUNCHER', 0     ; probe tail
syspath_rd      db      '/RD/1', 0                   ; fallback
endg

uglobal
syspath_auto    rb      1
syspath_probe   rb      32
syspath_probe_buf rb    4
endg

; Kolibri 2.0: automatically locate the system directory.
; Probes /HDn/m then /SDn/m (n = 0..3, m = 1..4) for KOLIBRIOS/LAUNCHER,
; copies the first working prefix to sysdir_path-1 as '/XDn/m/KOLIBRIOS'.
; Falls back to /RD/1 when nothing is found.
proc syspath_autodetect
        push    ebx ecx edx esi edi
        mov     bl, 'H'                 ; disk type: IDE first
.type_loop:
        xor     edx, edx                ; DL = disk number 0..3
.disk_loop:
        mov     cl, '1'                 ; CL = partition number '1'..'4'
.part_loop:
; build "/XDn/m" + tail in syspath_probe
        mov     esi, syspath_probe
        mov     byte [esi], '/'
        mov     [esi+1], bl
        mov     word [esi+2], 'D0'
        mov     al, '0'
        add     al, dl
        mov     [esi+3], al
        mov     byte [esi+4], '/'
        mov     [esi+5], cl
        lea     edi, [esi+6]
        mov     esi, syspath_tail
@@:     lodsb
        stosb
        test    al, al
        jnz     @b
; probe: read the first 4 bytes of the marker file
        pushad
        stdcall read_file, syspath_probe, syspath_probe_buf, 0, 4
        test    eax, eax
        popad
        jnz     .next_part
; hit: copy "/XDn/m/KOLIBRIOS" into sysdir_path-1
        mov     esi, syspath_probe
        mov     edi, sysdir_path-1
        mov     ecx, 6 + 10             ; "/XDn/m" + "/KOLIBRIOS"
        rep movsb
        mov     byte [edi], 0
        DEBUGF  1, "K : AUTO sysdir found: %s\n", sysdir_path-1
        jmp     .done
.next_part:
        inc     cl
        cmp     cl, '4'
        jbe     .part_loop
.next_disk:
        inc     dl
        cmp     dl, 3
        jbe     .disk_loop
        cmp     bl, 'S'
        je      .fallback               ; both disk types exhausted
        mov     bl, 'S'
        jmp     .type_loop
.fallback:
        mov     esi, syspath_rd
        mov     edi, sysdir_path-1
        mov     ecx, 6
        rep movsb
        DEBUGF  1, "K : AUTO sysdir fallback to /RD/1\n"
.done:
        pop     edi esi edx ecx ebx
        ret
endp

cp866toUpper:
; convert cp866 character in al to uppercase
        cmp     al, 'a'
        jb      .ret
        cmp     al, 'z'
        jbe     @f
        cmp     al, 0xA0
        jb      .ret
        cmp     al, 0xB0
        jb      @f
        cmp     al, 0xE0
        jb      .ret
        cmp     al, 0xF0
        jb      .rus
        cmp     al, 0xF7
        ja      .ret
        and     eax, -2
.ret:
        ret

@@:
        sub     eax, 32
        ret

.rus:
        sub     eax, 0xE0-0x90
        ret

utf16toUpper:
; convert UTF-16 character in ax to uppercase
        cmp     ax, 'a'
        jb      .ret
        cmp     ax, 'z'
        jbe     @f
        cmp     ax, 430h
        jb      .ret
        cmp     ax, 450h
        jb      @f
        cmp     ax, 460h
        jnc     .ret
        sub     eax, 80
.ret:
        ret

@@:
        sub     eax, 32
        ret

uni2ansi_char:
; convert UNICODE character in ax to ANSI character in al using cp866 encoding
        cmp     ax, 0x80
        jb      .ret
        cmp     ax, 0xB6
        jz      .B6
        cmp     ax, 0x400
        jb      .unk
        cmp     ax, 0x410
        jb      @f
        cmp     ax, 0x440
        jb      .rus1
        cmp     ax, 0x450
        jb      .rus2
        cmp     ax, 0x460
        jb      @f
.unk:
        mov     al, '_'
.ret:
        ret

.B6:
        mov     al, 20
        ret

.rus1:  ; 0x410-0x43F -> 0x80-0xAF
        add     al, 0x70
        ret

.rus2:  ; 0x440-0x44F -> 0xE0-0xEF
        add     al, 0xA0
        ret

@@:
        push    ecx edi
        mov     ecx, 8
        mov     edi, .table
        repnz scasb
        mov     ah, cl
        pop     edi ecx
        jnz     .unk
        mov     al, 0xF7
        sub     al, ah
        ret

.table  db  1, 51h, 4, 54h, 7, 57h, 0Eh, 5Eh

ansi2uni_char:
; convert ANSI character in al to UNICODE character in ax, using cp866 encoding
        movzx   eax, al
        cmp     al, 0x80
        jb      @f      ; 0x00-0x7F - trivial map
        cmp     al, 0xB0
        jb      .rus    ; 0x80-0xAF -> 0x410-0x43F
        cmp     al, 0xE0
        jb      .unk
        cmp     al, 0xF0
        jb      .rus2   ; 0xE0-0xEF -> 0x440-0x44F
        cmp     al, 0xF8
        jnc     .unk
        mov     al, [eax+uni2ansi_char.table-0xF0]
        add     ax, 400h
        ret

@@:
        cmp     al, 20
        jnz     .ret
        mov     al, 0xB6
.ret:
        ret

.rus:
        add     ax, 0x410-0x80
        ret

.rus2:
        add     ax, 0x440-0xE0
        ret

.unk:
        mov     al, '_'
        ret

cp866toUTF8_string:
;   in:
; esi -> cp866 string (could be zero terminated)
; edi -> buffer for UTF-8 string
; ecx = buffer size (signed)
        lodsb
        call    ansi2uni_char
        push    eax
        call    UTF16to8
        pop     eax
        js      @f
        test    eax, eax
        jnz     cp866toUTF8_string
@@:
        ret

; SF=1 -> counter
; ZF=1 -> zero char

UTF16to8_string:
;   in:
; esi -> UTF-16 string (could be zero terminated)
; edi -> buffer for UTF-8 string
; ecx = buffer size (signed)
        xor     eax, eax
@@:
        lodsw
        push    eax
        call    UTF16to8
        pop     eax
        js      @f
        test    eax, eax
        jnz     @b
@@:
        ret

UTF16to8:
;   in:
; ax = UTF-16 char
; edi -> buffer for UTF-8 char (increasing)
; ecx = byte counter (decreasing)
        movzx   eax, ax
        dec     ecx
        js      .ret
        cmp     eax, 80h
        jnc     @f
        stosb
        test    eax, eax    ; SF=0
.ret:
        ret

@@:
        dec     ecx
        js      .ret
        cmp     eax, 800h
        jnc     @f
        shl     eax, 2
        shr     al, 2
        or      eax, 1100000010000000b
        xchg    al, ah
        stosw
        ret

@@:
        dec     ecx
        js      .ret
        shl     eax, 4
        shr     ax, 2
        shr     al, 2
        or      eax, 111000001000000010000000b
        bswap   eax
        shr     eax, 8
        stosb
        shr     eax, 8
        stosw
        ret

utf8to16:
; in: esi -> UTF-8 char (increasing)
; out: ax = UTF-16 char
        lodsb
        test    al, al
        jns     .got
        shl     al, 2
        jnc     utf8to16
@@:
        shl     ax, 8
        lodsb
        test    al, al
        jns     .got
        shl     al, 2
        jc      @b
        shr     ah, 2
        shl     ax, 3
        jnc     @f
        shl     eax, 3
        lodsb
        test    al, al
        jns     .got
        shl     al, 2
        jc      @b
        shr     eax, 2
        ret

@@:
        shr     ax, 5
        ret

.got:
        xor     ah, ah
        ret

strlen:
; in: esi -> source
; out: ecx = length
        push    edi eax
        or      ecx, -1
        mov     edi, esi
        xor     eax, eax
        repnz scasb
        inc     ecx
        not     ecx
        pop     eax edi
        ret
