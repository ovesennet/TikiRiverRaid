; TIKI RIVER RAID - keyboard.asm
; Direct keyboard matrix scanning via port $00.
;
; TIKI-100 keyboard: 8 rows x 12 columns on port $00.
;   - Write to port $00 to reset scan to column 1
;   - Read port $00 returns one column per read (columns 1-12)
;   - Bit SET = key NOT pressed, bit CLEAR = key pressed
;
; Key positions from hardware docs:
;   'a'     = col 2, bit 3
;   'd'     = col 3, bit 6
;   space   = col 1, bit 4
;   'q'     = col 2, bit 6
;   'p'     = col 7, bit 1

    SECTION code_driver

    PUBLIC  _kbd_init
    PUBLIC  _kbd_shutdown
    PUBLIC  _kbd_scan

; Result bitmask bits
KBIT_LEFT   equ 0       ; 'a'
KBIT_RIGHT  equ 1       ; 'd'
KBIT_FIRE   equ 2       ; space
KBIT_QUIT   equ 3       ; 'q'
KBIT_PAUSE  equ 4       ; 'p'
KBIT_ANY    equ 7       ; any key

_kbd_init:
    ret

_kbd_shutdown:
    ret

; ------------------------------------------------
; uint8_t kbd_scan(void)
; Returns bitmask: bit0=left, 1=right, 2=fire,
;   3=quit, 4=pause, 7=any key held
; ------------------------------------------------
_kbd_scan:
    ld      e, 0            ; result bitmask
    ld      d, 0            ; anykey accumulator

    ; Reset scan to column 1
    out     ($00), a

    ; --- Column 1 ---
    in      a, ($00)
    ld      c, a
    ld      a, c
    cpl                     ; invert: now 1=pressed
    or      d
    ld      d, a            ; accumulate any
    bit     4, c            ; space: bit4, 0=pressed
    jr      nz, ks_no_spc
    set     KBIT_FIRE, e
ks_no_spc:

    ; --- Column 2 ---
    in      a, ($00)
    ld      c, a
    ld      a, c
    cpl
    or      d
    ld      d, a
    bit     3, c            ; 'a': bit 3
    jr      nz, ks_no_a
    set     KBIT_LEFT, e
ks_no_a:
    bit     6, c            ; 'q': bit 6
    jr      nz, ks_no_q
    set     KBIT_QUIT, e
ks_no_q:

    ; --- Column 3 ---
    in      a, ($00)
    ld      c, a
    ld      a, c
    cpl
    or      d
    ld      d, a
    bit     6, c            ; 'd': bit 6
    jr      nz, ks_no_d
    set     KBIT_RIGHT, e
ks_no_d:

    ; --- Columns 4-6 (skip, just accumulate any) ---
    in      a, ($00)        ; col 4
    cpl
    or      d
    ld      d, a

    in      a, ($00)        ; col 5
    cpl
    or      d
    ld      d, a

    in      a, ($00)        ; col 6
    cpl
    or      d
    ld      d, a

    ; --- Column 7 ---
    in      a, ($00)
    ld      c, a
    ld      a, c
    cpl
    or      d
    ld      d, a
    bit     1, c            ; 'p': bit 1
    jr      nz, ks_no_p
    set     KBIT_PAUSE, e
ks_no_p:

    ; --- Columns 8-12 (just accumulate any) ---
    in      a, ($00)        ; col 8
    cpl
    or      d
    ld      d, a

    in      a, ($00)        ; col 9
    cpl
    or      d
    ld      d, a

    in      a, ($00)        ; col 10
    cpl
    or      d
    ld      d, a

    in      a, ($00)        ; col 11
    cpl
    or      d
    ld      d, a

    in      a, ($00)        ; col 12
    cpl
    or      d
    ld      d, a

    ; Set ANY bit if any key pressed anywhere
    ld      a, d
    or      a
    jr      z, ks_no_any
    set     KBIT_ANY, e
ks_no_any:

    ld      l, e
    ret
