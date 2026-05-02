; TIKI RIVER RAID - screen.asm
; Low-level VRAM drawing routines for Tiki-100 mode 3 (256x256x16).
;
; Mode 3 VRAM layout:
;   128 bytes per scanline, 256 scanlines = 32768 bytes
;   2 pixels per byte: bits 3-0 = left (even x), bits 7-4 = right (odd x)
;   Byte address = y * 128 + x / 2
;
; Hardware scroll:
;   AY-3-8912 register 14 (data port) controls vertical scroll.
;   Effective VRAM addr = (addr + scroll_reg * 128) MOD 32768
;   Scroll is transparent to CPU — drawing at screen Y always goes
;   to the correct visible line regardless of scroll offset.

    SECTION code_graphics

    PUBLIC  _vid_clear_asm
    PUBLIC  _vid_hline_gfx
    PUBLIC  _vid_fill_rect_gfx
    PUBLIC  _vid_draw_text_gfx
    PUBLIC  _vid_draw_river_line_asm
    PUBLIC  _vid_game_step_asm
    PUBLIC  _vid_game_frame_asm
    PUBLIC  _vid_begin_vram_asm
    PUBLIC  _vid_end_vram_asm
    PUBLIC  _vid_hline_nr_asm
    PUBLIC  _vid_fill_rect_nr_asm
    PUBLIC  _scroll_set_asm
    PUBLIC  _scroll_get_asm
    PUBLIC  _wait_vsync_asm
    PUBLIC  _vsync_init_asm
    PUBLIC  _vsync_shutdown_asm

    EXTERN  swapgfxbk
    EXTERN  swapgfxbk1

; ============================================================
; Global parameter block for C -> ASM communication
; ============================================================
    SECTION bss_graphics

    PUBLIC  _gfx_x1
    PUBLIC  _gfx_y1
    PUBLIC  _gfx_x2
    PUBLIC  _gfx_y2
    PUBLIC  _gfx_colour
    PUBLIC  _gfx_width
    PUBLIC  _gfx_height

_gfx_x1:       defs 2
_gfx_y1:       defs 2
_gfx_x2:       defs 2
_gfx_y2:       defs 2
_gfx_colour:   defs 1
_gfx_width:    defs 1
_gfx_height:   defs 1

; Scratch for hline
_hl_base:      defs 2
_hl_x1:        defs 1
_hl_x2:        defs 1
_hl_colbyte:   defs 1
_hl_colnib:    defs 1

; Text draw parameters
    PUBLIC  _txt_x
    PUBLIC  _txt_y
    PUBLIC  _txt_str
    PUBLIC  _txt_colour

_txt_x:        defs 2
_txt_y:        defs 2
_txt_str:      defs 2
_txt_colour:   defs 1

; Text scratch
_txt_colbyte:  defs 1
_txt_vram:     defs 2
_txt_glyph:    defs 2

; River line parameters
    PUBLIC  _riv_y
    PUBLIC  _riv_left
    PUBLIC  _riv_right
    PUBLIC  _riv_land_col
    PUBLIC  _riv_water_col

_riv_y:        defs 1
_riv_left:     defs 1
_riv_right:    defs 1
_riv_land_col: defs 1
_riv_water_col: defs 1

; Game step parameters (plane)
    PUBLIC  _gs_plane_x
    PUBLIC  _gs_plane_y
    PUBLIC  _gs_plane_col
    PUBLIC  _gs_plane_pose
    PUBLIC  _gs_hud_sep_y
    PUBLIC  _gs_hud_top_y
    PUBLIC  _gs_hud_col

_gs_plane_x:   defs 1
_gs_plane_y:   defs 1
_gs_plane_col: defs 1
_gs_plane_pose: defs 1
_gs_hud_sep_y: defs 1
_gs_hud_top_y: defs 1
_gs_hud_col:   defs 1

; Sprite blit parameters
    PUBLIC  _gs_blit_active
    PUBLIC  _gs_blit_x
    PUBLIC  _gs_blit_row
    PUBLIC  _gs_do_plane

_gs_blit_active: defs 1
_gs_blit_x:      defs 1
_gs_blit_row:    defs 1
_gs_do_plane:    defs 1

    PUBLIC  _gs_scroll_reg
_gs_scroll_reg:  defs 1

; Scroll value
    PUBLIC  _scroll_val

_scroll_val:   defs 1

; Frame counter & vsync
    PUBLIC  _frame_counter

_frame_counter: defs 1
_saved_f057:    defs 3          ; save original 3 bytes at $F057

; Text string buffer (high memory copy)
_txt_strbuf:   defs 32

; ── Save-under buffer for plane sprite ──
; Bounding box: 10 bytes wide (20px) × 15 rows = 150 bytes
; Stores raw VRAM bytes under the plane so background can be restored
    PUBLIC  _sav_valid

_sav_valid:    defs 1          ; 0 = no saved data yet, 1 = valid
_sav_x_byte:   defs 1          ; byte-aligned X/2 of saved region
_sav_y:        defs 1          ; screen Y of saved region
_sav_w:        defs 1          ; width in bytes (always SAV_W_BYTES)
_sav_h:        defs 1          ; height in rows (always SAV_H_ROWS)

SAV_W_BYTES equ 10             ; 20 pixels, covers 18px bbox + alignment
SAV_H_ROWS  equ 15             ; 14px plane + 1 trail row

_sav_buf:      defs SAV_W_BYTES * SAV_H_ROWS   ; 150 bytes
_sav_scroll:   defs 1          ; scroll_reg value at time of last save

; ── Pre-generated step buffer for batched frame rendering ──
    PUBLIC  _step_buf
    PUBLIC  _step_count

_step_buf:     defs 48         ; 8 entries × 6 bytes (scroll,left,right,fuel_act,fuel_x,fuel_row)
_step_count:   defs 1
_step_ptr:     defs 2          ; internal scratch pointer

    SECTION code_graphics

; ============================================================
; vid_clear_asm — zero all 32K VRAM
; ============================================================
_vid_clear_asm:
    call    swapgfxbk
    ld      hl, 0
    ld      de, 1
    ld      bc, 32767
    ld      (hl), 0
    ldir
    call    swapgfxbk1
    ret

; ============================================================
; vid_hline_gfx — fast horizontal line
; Params: _gfx_x1, _gfx_x2, _gfx_y1, _gfx_colour
; ============================================================
_vid_hline_gfx:
    ld      hl, (_gfx_y1)
    ld      a, h
    or      a
    ret     nz

    ; Compute scanline base: y * 128
    ld      a, l
    srl     a
    ld      h, a
    ld      a, (_gfx_y1)
    rrca
    and     $80
    ld      l, a
    ld      (_hl_base), hl

    ; Sort x1, x2
    ld      a, (_gfx_x1)
    ld      b, a
    ld      a, (_gfx_x2)
    ld      c, a
    ld      a, b
    cp      c
    jr      c, hl_sorted
    jr      z, hl_sorted
    ld      b, c
    ld      c, a
hl_sorted:
    ld      a, b
    ld      (_hl_x1), a
    ld      a, c
    ld      (_hl_x2), a

    ; Build colour bytes
    ld      a, (_gfx_colour)
    and     $0F
    ld      (_hl_colnib), a
    ld      b, a
    rlca
    rlca
    rlca
    rlca
    or      b
    ld      (_hl_colbyte), a

    call    swapgfxbk
    call    hline_raw_body
    call    swapgfxbk1
    ret

; hline_raw — no bank switch version (caller must bracket)
; Reads _gfx_x1, _gfx_x2, _gfx_y1, _gfx_colour fresh each call
hline_raw:
    ld      hl, (_gfx_y1)
    ld      a, h
    or      a
    ret     nz
    ld      a, l
    srl     a
    ld      h, a
    ld      a, (_gfx_y1)
    rrca
    and     $80
    ld      l, a
    ld      (_hl_base), hl
    ld      a, (_gfx_x1)
    ld      b, a
    ld      a, (_gfx_x2)
    ld      c, a
    ld      a, b
    cp      c
    jr      c, hlr_sorted
    jr      z, hlr_sorted
    ld      b, c
    ld      c, a
hlr_sorted:
    ld      a, b
    ld      (_hl_x1), a
    ld      a, c
    ld      (_hl_x2), a
    ld      a, (_gfx_colour)
    and     $0F
    ld      (_hl_colnib), a
    ld      b, a
    rlca
    rlca
    rlca
    rlca
    or      b
    ld      (_hl_colbyte), a
    jp      hline_raw_body

; Phase 1: Left partial byte (x1 odd)
hline_raw_body:
    ld      a, (_hl_x1)
    bit     0, a
    jr      z, hl_no_left

    srl     a
    ld      hl, (_hl_base)
    add     a, l
    ld      l, a
    jr      nc, hl_lp_noc
    inc     h
hl_lp_noc:
    ld      a, (_hl_colbyte)
    and     $F0
    ld      b, a
    ld      a, (hl)
    and     $0F
    or      b
    ld      (hl), a

    ld      a, (_hl_x1)
    inc     a
    ld      (_hl_x1), a
    ld      b, a
    ld      a, (_hl_x2)
    cp      b
    jp      c, hl_done_raw

hl_no_left:
    ; Phase 3: Right partial byte (x2 even)
    ld      a, (_hl_x2)
    bit     0, a
    jr      nz, hl_no_right

    srl     a
    ld      hl, (_hl_base)
    add     a, l
    ld      l, a
    jr      nc, hl_rp_noc
    inc     h
hl_rp_noc:
    ld      a, (_hl_colnib)
    ld      b, a
    ld      a, (hl)
    and     $F0
    or      b
    ld      (hl), a

    ld      a, (_hl_x2)
    dec     a
    ld      (_hl_x2), a
    ld      b, a
    ld      a, (_hl_x1)
    ld      c, a
    ld      a, b
    cp      c
    jp      c, hl_done_raw

hl_no_right:
    ; Phase 2: Middle full bytes
    ld      a, (_hl_x1)
    srl     a
    ld      c, a

    ld      a, (_hl_x2)
    srl     a
    sub     c
    inc     a
    ld      b, a

    ld      hl, (_hl_base)
    ld      a, c
    add     a, l
    ld      l, a
    jr      nc, hl_mid_noc
    inc     h
hl_mid_noc:
    ld      a, (_hl_colbyte)

hl_fill:
    ld      (hl), a
    inc     hl
    djnz    hl_fill

hl_done_raw:
    ret

; ============================================================
; vid_fill_rect_gfx — fast filled rectangle
; Params: _gfx_x1, _gfx_y1, _gfx_width, _gfx_height, _gfx_colour
; ============================================================
_vid_fill_rect_gfx:
    ld      hl, (_gfx_x1)
    ld      a, (_gfx_width)
    dec     a
    add     a, l
    ld      l, a
    ld      a, 0
    adc     a, h
    ld      h, a
    ld      (_gfx_x2), hl

    ld      a, (_gfx_height)
    ld      b, a
    or      a
    ret     z

    call    swapgfxbk

fr_loop:
    push    bc
    call    hline_raw
    pop     bc

    ld      hl, (_gfx_y1)
    inc     hl
    ld      (_gfx_y1), hl
    ld      a, h
    or      a
    jr      nz, fr_done

    djnz    fr_loop
fr_done:
    call    swapgfxbk1
    ret

; ============================================================
; vid_draw_river_line_asm — draw one full river scanline
; Single VRAM bank switch for all three segments (land/water/land).
; Params: _riv_y, _riv_left, _riv_right, _riv_land_col, _riv_water_col
; ============================================================
_vid_draw_river_line_asm:
    ; Set up y (shared across all three hline_raw calls)
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a

    call    swapgfxbk

    ; --- Left bank: x=0 to riv_left-1 ---
    ld      a, (_riv_left)
    or      a
    jr      z, rivl_no_left

    xor     a
    ld      (_gfx_x1), a
    ld      a, (_riv_left)
    dec     a
    ld      (_gfx_x2), a
    ld      a, (_riv_land_col)
    ld      (_gfx_colour), a
    ; Restore y (hline_raw reads it fresh)
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    call    hline_raw

rivl_no_left:
    ; --- Water: x=riv_left to riv_right ---
    ld      a, (_riv_left)
    ld      (_gfx_x1), a
    ld      a, (_riv_right)
    ld      (_gfx_x2), a
    ld      a, (_riv_water_col)
    ld      (_gfx_colour), a
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    call    hline_raw

    ; --- Right bank: x=riv_right+1 to 255 ---
    ld      a, (_riv_right)
    cp      255
    jr      z, rivl_no_right

    inc     a
    ld      (_gfx_x1), a
    ld      a, 255
    ld      (_gfx_x2), a
    ld      a, (_riv_land_col)
    ld      (_gfx_colour), a
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    call    hline_raw

rivl_no_right:
    call    swapgfxbk1
    ret

; ============================================================
; draw_river_fuel — one river scanline + optional fuel overlay
; Must be called with VRAM banked in.
; Reads: _riv_y, _riv_left, _riv_right, _riv_land_col, _riv_water_col
;        _gs_blit_active, _gs_blit_x, _gs_blit_row
; ============================================================
draw_river_fuel:
    ; Left bank: x=0 to riv_left-1
    ld      a, (_riv_left)
    or      a
    jr      z, drf_no_left
    xor     a
    ld      (_gfx_x1), a
    ld      a, (_riv_left)
    dec     a
    ld      (_gfx_x2), a
    ld      a, (_riv_land_col)
    ld      (_gfx_colour), a
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    call    hline_raw
drf_no_left:
    ; Water: riv_left to riv_right
    ld      a, (_riv_left)
    ld      (_gfx_x1), a
    ld      a, (_riv_right)
    ld      (_gfx_x2), a
    ld      a, (_riv_water_col)
    ld      (_gfx_colour), a
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    call    hline_raw
    ; Fuel overlay (if active)
    ld      a, (_gs_blit_active)
    or      a
    jp      z, drf_no_fuel
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    ld      a, (_gs_blit_row)
    cp      2
    jr      c, drf_fuel_narrow
    cp      22
    jr      nc, drf_fuel_narrow
    ; Wide red body: x+1 to x+12
    ld      a, (_gs_blit_x)
    inc     a
    ld      (_gfx_x1), a
    ld      a, (_gs_blit_x)
    add     a, 12
    ld      (_gfx_x2), a
    ld      a, 4
    ld      (_gfx_colour), a
    call    hline_raw
    ld      a, (_gs_blit_row)
    cp      5
    jr      z, drf_fuel_white
    cp      6
    jr      z, drf_fuel_white
    cp      7
    jr      z, drf_fuel_white
    cp      16
    jr      z, drf_fuel_white
    cp      17
    jr      z, drf_fuel_white
    cp      18
    jr      z, drf_fuel_white
    jr      drf_fuel_done
drf_fuel_white:
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    ld      a, (_gs_blit_x)
    add     a, 3
    ld      (_gfx_x1), a
    ld      a, (_gs_blit_x)
    add     a, 10
    ld      (_gfx_x2), a
    ld      a, 15
    ld      (_gfx_colour), a
    call    hline_raw
    jr      drf_fuel_done
drf_fuel_narrow:
    ld      a, (_gs_blit_x)
    add     a, 3
    ld      (_gfx_x1), a
    ld      a, (_gs_blit_x)
    add     a, 10
    ld      (_gfx_x2), a
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    ld      a, 4
    ld      (_gfx_colour), a
    call    hline_raw
drf_fuel_done:
    xor     a
    ld      (_gs_blit_active), a
drf_no_fuel:
    ; Right bank: riv_right+1 to 255
    ld      a, (_riv_right)
    cp      255
    jr      z, drf_no_right
    inc     a
    ld      (_gfx_x1), a
    ld      a, 255
    ld      (_gfx_x2), a
    ld      a, (_riv_land_col)
    ld      (_gfx_colour), a
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    call    hline_raw
drf_no_right:
    ret

; ============================================================
; Plane sprite data tables: count, then (dx, dy, w, h) per rect
; ============================================================
spr_fwd_data:
    defb    7
    defb    5, 0, 2, 2         ; nose
    defb    4, 2, 4, 2         ; upper body
    defb    2, 4, 8, 2         ; mid body
    defb    0, 6, 12, 2        ; wings
    defb    4, 8, 4, 2         ; lower body
    defb    2, 10, 2, 2        ; left tail
    defb    8, 10, 2, 2        ; right tail

spr_left_data:
    defb    8
    defb    4, 0, 2, 2         ; nose shifted left
    defb    3, 2, 4, 2         ; upper body
    defb    1, 4, 8, 2         ; mid body
    defb    0, 6, 12, 1        ; wings wide
    defb    2, 7, 10, 1        ; wings taper
    defb    4, 8, 4, 2         ; lower body
    defb    2, 10, 2, 2        ; left tail
    defb    8, 10, 2, 2        ; right tail

spr_right_data:
    defb    8
    defb    6, 0, 2, 2         ; nose shifted right
    defb    5, 2, 4, 2         ; upper body
    defb    3, 4, 8, 2         ; mid body
    defb    0, 6, 12, 1        ; wings wide
    defb    0, 7, 10, 1        ; wings taper
    defb    4, 8, 4, 2         ; lower body
    defb    2, 10, 2, 2        ; left tail
    defb    8, 10, 2, 2        ; right tail

; ============================================================
; plane_restore — copy saved buffer back to VRAM (erase old sprite)
; Must be called with VRAM banked in.
; Skips if _sav_valid == 0.
; ============================================================
plane_restore:
    ld      a, (_sav_valid)
    or      a
    ret     z

    ld      a, (_sav_h)
    ld      b, a
    ld      de, _sav_buf       ; source = save buffer

pr_row:
    push    bc

    ; Compute VRAM addr: _sav_y * 128 + _sav_x_byte
    ld      a, (_sav_y)
    srl     a
    ld      h, a
    ld      a, (_sav_y)
    rrca
    and     $80
    ld      l, a
    ld      a, (_sav_x_byte)
    add     a, l
    ld      l, a
    jr      nc, pr_noc
    inc     h
pr_noc:
    ; HL = VRAM dest, DE = buffer source
    push    hl
    ex      de, hl             ; HL = source (buffer), DE = dest (VRAM)
    ld      bc, SAV_W_BYTES
    ldir                       ; copy buffer → VRAM
    ex      de, hl             ; DE = updated buffer ptr
    pop     hl                 ; discard (we don't need old HL)

    ; Advance _sav_y for next row
    ld      a, (_sav_y)
    inc     a                  ; wraps 255→0 (ring buffer)
    ld      (_sav_y), a

    pop     bc
    djnz    pr_row
    ret

; ============================================================
; plane_save — copy VRAM background into save buffer (before draw)
; Must be called with VRAM banked in.
; Input: compute sav_x_byte and sav_y from _gs_plane_x, _gs_plane_y
;        before calling this.
; Sets _sav_valid = 1.
; ============================================================
plane_save:
    ; Compute byte-aligned X: floor((plane_x - 3) / 2), clamped
    ld      a, (_gs_plane_x)
    sub     3
    jr      nc, ps_xok
    xor     a
ps_xok:
    srl     a                  ; x_byte = (plane_x - 3) / 2
    ld      (_sav_x_byte), a

    ; Save Y
    ld      a, (_gs_plane_y)
    ld      (_sav_y), a

    ; Save dimensions
    ld      a, SAV_W_BYTES
    ld      (_sav_w), a
    ld      a, SAV_H_ROWS
    ld      (_sav_h), a

    ld      a, SAV_H_ROWS
    ld      b, a
    ld      de, _sav_buf       ; dest = save buffer

    ; Need a local copy of Y since we increment it
    ld      a, (_gs_plane_y)
    ld      c, a               ; C = current Y

ps_row:
    push    bc

    ; Compute VRAM addr: C * 128 + _sav_x_byte
    ld      a, c
    srl     a
    ld      h, a
    ld      a, c
    rrca
    and     $80
    ld      l, a
    ld      a, (_sav_x_byte)
    add     a, l
    ld      l, a
    jr      nc, ps_noc
    inc     h
ps_noc:
    ; HL = VRAM source, DE = buffer dest
    ld      bc, SAV_W_BYTES
    ldir                       ; copy VRAM → buffer

    pop     bc
    ld      a, c
    inc     a                  ; next row (wraps 255→0)
    ld      c, a
    djnz    ps_row

    ; Mark buffer valid
    ld      a, 1
    ld      (_sav_valid), a
    ret

; ============================================================
; ============================================================
; draw_plane_sprite — table-driven sprite draw
; Input: HL = pointer to sprite data (count byte + rect data)
;        Uses _gs_plane_x, _gs_plane_y, _gs_plane_col
; ============================================================
draw_plane_sprite:
    ld      a, (hl)            ; count
    ld      b, a
    inc     hl
dps_loop:
    push    bc
    push    hl

    ; dx → gfx_x1
    ld      a, (_gs_plane_x)
    add     a, (hl)
    ld      (_gfx_x1), a
    inc     hl

    ; dy → gfx_y1
    ld      a, (_gs_plane_y)
    add     a, (hl)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    inc     hl

    ; w → gfx_width
    ld      a, (hl)
    ld      (_gfx_width), a
    inc     hl

    ; h → gfx_height
    ld      a, (hl)
    ld      (_gfx_height), a

    ; colour
    ld      a, (_gs_plane_col)
    ld      (_gfx_colour), a
    call    gs_fill_rect

    pop     hl
    ld      bc, 4
    add     hl, bc             ; advance to next rect
    pop     bc
    djnz    dps_loop
    ret

; ============================================================
; vid_game_step_asm — combined river + HUD + plane in ONE bank switch
; Params: _riv_y/left/right/land_col/water_col (river line)
;         _gs_hud_sep_y, _gs_hud_top_y, _gs_hud_col (HUD repair)
;         _gs_plane_x, _gs_plane_y, _gs_plane_col, _gs_plane_pose
; ============================================================
_vid_game_step_asm:
    ; Set up river y
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a

    call    swapgfxbk

    ; === RIVER LINE ===
    ; Left bank: x=0 to riv_left-1
    ld      a, (_riv_left)
    or      a
    jr      z, gs_no_left
    xor     a
    ld      (_gfx_x1), a
    ld      a, (_riv_left)
    dec     a
    ld      (_gfx_x2), a
    ld      a, (_riv_land_col)
    ld      (_gfx_colour), a
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    call    hline_raw
gs_no_left:
    ; Water: x=riv_left to riv_right
    ld      a, (_riv_left)
    ld      (_gfx_x1), a
    ld      a, (_riv_right)
    ld      (_gfx_x2), a
    ld      a, (_riv_water_col)
    ld      (_gfx_colour), a
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    call    hline_raw

    ; === FUEL SPRITE on water (if active) — 14x24 barrel ===
    ld      a, (_gs_blit_active)
    or      a
    jp      z, gs_no_fuel

    ; Y from riv_y
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a

    ; Rows 0,1,22,23 = narrow cap (x+3..x+10)
    ; Rows 2-21 = wide body (x+1..x+12)
    ; White bands on rows 5,6,7 and 16,17,18: x+3..x+10
    ld      a, (_gs_blit_row)
    cp      2
    jr      c, gs_fuel_narrow     ; rows 0-1
    cp      22
    jr      nc, gs_fuel_narrow    ; rows 22-23

    ; Wide red body: x+1 to x+12
    ld      a, (_gs_blit_x)
    inc     a
    ld      (_gfx_x1), a
    ld      a, (_gs_blit_x)
    add     a, 12
    ld      (_gfx_x2), a
    ld      a, 4               ; COL_RED
    ld      (_gfx_colour), a
    call    hline_raw

    ; White band rows 5,6,7 and 16,17,18
    ld      a, (_gs_blit_row)
    cp      5
    jr      z, gs_fuel_white
    cp      6
    jr      z, gs_fuel_white
    cp      7
    jr      z, gs_fuel_white
    cp      16
    jr      z, gs_fuel_white
    cp      17
    jr      z, gs_fuel_white
    cp      18
    jr      z, gs_fuel_white
    jr      gs_fuel_done

gs_fuel_white:
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    ld      a, (_gs_blit_x)
    add     a, 3
    ld      (_gfx_x1), a
    ld      a, (_gs_blit_x)
    add     a, 10
    ld      (_gfx_x2), a
    ld      a, 15              ; COL_WHITE
    ld      (_gfx_colour), a
    call    hline_raw
    jr      gs_fuel_done

gs_fuel_narrow:
    ; Narrow cap: x+3 to x+10
    ld      a, (_gs_blit_x)
    add     a, 3
    ld      (_gfx_x1), a
    ld      a, (_gs_blit_x)
    add     a, 10
    ld      (_gfx_x2), a
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    ld      a, 4               ; COL_RED
    ld      (_gfx_colour), a
    call    hline_raw

gs_fuel_done:
    xor     a
    ld      (_gs_blit_active), a

gs_no_fuel:
    ; Right bank: x=riv_right+1 to 255
    ld      a, (_riv_right)
    cp      255
    jr      z, gs_no_right
    inc     a
    ld      (_gfx_x1), a
    ld      a, 255
    ld      (_gfx_x2), a
    ld      a, (_riv_land_col)
    ld      (_gfx_colour), a
    ld      a, (_riv_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    call    hline_raw
gs_no_right:

    ; === HUD REPAIR: separator line (full width, black) ===
    xor     a
    ld      (_gfx_x1), a
    ld      a, 255
    ld      (_gfx_x2), a
    ld      a, (_gs_hud_sep_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    ld      (_gfx_colour), a        ; COL_BLACK = 0
    call    hline_raw

    ; === HUD REPAIR: top HUD line (full width, grey) ===
    xor     a
    ld      (_gfx_x1), a
    ld      a, 255
    ld      (_gfx_x2), a
    ld      a, (_gs_hud_top_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    ld      a, (_gs_hud_col)
    ld      (_gfx_colour), a
    call    hline_raw

    ; === PLANE (gated by gs_do_plane, scroll-aware save-under) ===
    ld      a, (_gs_do_plane)
    or      a
    jp      z, gs_skip_plane

    ; --- Restore old background at scroll-adjusted position ---
    ld      a, (_sav_valid)
    or      a
    jr      z, gs_no_restore

    ; delta = sav_scroll - gs_scroll_reg (mod 256)
    ; Since scroll_reg decrements, delta = number of scroll steps since save
    ld      a, (_sav_scroll)
    ld      b, a
    ld      a, (_gs_scroll_reg)
    ld      c, a
    ld      a, b
    sub     c               ; A = delta (unsigned 8-bit, wraps correctly)

    ; restore_y = plane_y + delta (ring buffer wraps at 256)
    ld      b, a
    ld      a, (_gs_plane_y)
    add     a, b
    ld      (_sav_y), a

    call    plane_restore

gs_no_restore:
    ; --- Save fresh background at current plane position ---
    call    plane_save

    ; --- Record scroll_reg for next restore ---
    ld      a, (_gs_scroll_reg)
    ld      (_sav_scroll), a

    ; --- Draw plane sprite ---
    ld      a, (_gs_plane_pose)
    or      a
    jr      z, gs_pose_fwd
    cp      1
    jr      z, gs_pose_left
    ld      hl, spr_right_data
    jr      gs_pose_go
gs_pose_fwd:
    ld      hl, spr_fwd_data
    jr      gs_pose_go
gs_pose_left:
    ld      hl, spr_left_data
gs_pose_go:
    call    draw_plane_sprite

gs_skip_plane:
    call    swapgfxbk1
    ret

; ============================================================
; vid_game_frame_asm — batched: N scroll steps + HUD + plane
; in ONE bank switch.  Pre-fill _step_buf from C before calling.
; Entry layout per step (6 bytes):
;   [0] scroll_val  [1] riv_left  [2] riv_right
;   [3] fuel_active [4] fuel_x   [5] fuel_row
; ============================================================
_vid_game_frame_asm:
    call    swapgfxbk

    ld      hl, _step_buf
    ld      (_step_ptr), hl
    ld      a, (_step_count)
    ld      b, a
    or      a
    jp      z, gf_no_steps

gf_step_loop:
    push    bc
    ld      hl, (_step_ptr)

    ; Set scroll register (port I/O — works during VRAM bank-in)
    ld      a, 14
    out     ($16), a
    ld      a, (hl)
    out     ($17), a
    inc     hl

    ; Load river params
    ld      a, (hl)
    ld      (_riv_left), a
    inc     hl
    ld      a, (hl)
    ld      (_riv_right), a
    inc     hl

    ; Load fuel params
    ld      a, (hl)
    ld      (_gs_blit_active), a
    inc     hl
    ld      a, (hl)
    ld      (_gs_blit_x), a
    inc     hl
    ld      a, (hl)
    ld      (_gs_blit_row), a
    inc     hl

    ld      (_step_ptr), hl

    ; Draw at y=0 (newly exposed scanline)
    xor     a
    ld      (_riv_y), a
    call    draw_river_fuel

    ; Track scroll offset for save-under
    ld      a, (_sav_y)
    inc     a
    ld      (_sav_y), a

    pop     bc
    djnz    gf_step_loop

gf_no_steps:
    ; === HUD REPAIR (once per frame) ===
    xor     a
    ld      (_gfx_x1), a
    ld      a, 255
    ld      (_gfx_x2), a
    ld      a, (_gs_hud_sep_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    ld      (_gfx_colour), a
    call    hline_raw

    xor     a
    ld      (_gfx_x1), a
    ld      a, 255
    ld      (_gfx_x2), a
    ld      a, (_gs_hud_top_y)
    ld      (_gfx_y1), a
    xor     a
    ld      (_gfx_y1+1), a
    ld      a, (_gs_hud_col)
    ld      (_gfx_colour), a
    call    hline_raw

    ; === PLANE ===
    call    plane_restore
    call    plane_save

    ld      a, (_gs_plane_pose)
    or      a
    jr      z, gf_pose_fwd
    cp      1
    jr      z, gf_pose_left
    ld      hl, spr_right_data
    jr      gf_pose_draw
gf_pose_fwd:
    ld      hl, spr_fwd_data
    jr      gf_pose_draw
gf_pose_left:
    ld      hl, spr_left_data
gf_pose_draw:
    call    draw_plane_sprite

    call    swapgfxbk1
    ret

; Helper: fill rect without bank switch (used by game_step)
; Reads _gfx_x1, _gfx_y1, _gfx_width, _gfx_height, _gfx_colour
gs_fill_rect:
    ld      hl, (_gfx_x1)
    ld      a, (_gfx_width)
    dec     a
    add     a, l
    ld      l, a
    ld      a, 0
    adc     a, h
    ld      h, a
    ld      (_gfx_x2), hl
    ld      a, (_gfx_height)
    ld      b, a
    or      a
    ret     z
gs_fr_loop:
    push    bc
    call    hline_raw
    pop     bc
    ld      hl, (_gfx_y1)
    inc     hl
    ld      (_gfx_y1), hl
    ld      a, h
    or      a
    ret     nz
    djnz    gs_fr_loop
    ret

; ============================================================
; vid_begin_vram / vid_end_vram — bracket for batched VRAM ops
; ============================================================
_vid_begin_vram_asm:
    call    swapgfxbk
    ret

_vid_end_vram_asm:
    call    swapgfxbk1
    ret

; ============================================================
; vid_hline_nr_asm — hline without bank switch (caller brackets)
; ============================================================
_vid_hline_nr_asm:
    call    hline_raw
    ret

; ============================================================
; vid_fill_rect_nr_asm — fill rect without bank switch
; ============================================================
_vid_fill_rect_nr_asm:
    ld      hl, (_gfx_x1)
    ld      a, (_gfx_width)
    dec     a
    add     a, l
    ld      l, a
    ld      a, 0
    adc     a, h
    ld      h, a
    ld      (_gfx_x2), hl
    ld      a, (_gfx_height)
    ld      b, a
    or      a
    ret     z
frnr_loop:
    push    bc
    call    hline_raw
    pop     bc
    ld      hl, (_gfx_y1)
    inc     hl
    ld      (_gfx_y1), hl
    ld      a, h
    or      a
    ret     nz
    djnz    frnr_loop
    ret

; ============================================================
; Hardware scroll via AY-3-8912 register 14 (data port)
; Port $16 = register select, Port $17 = data read/write
; ============================================================
_scroll_set_asm:
    ld      a, 14
    out     ($16), a
    ld      a, (_scroll_val)
    out     ($17), a
    ret

_scroll_get_asm:
    ld      a, 14
    out     ($16), a
    in      a, ($17)
    ld      (_scroll_val), a
    ld      l, a
    ret

; ============================================================
; Frame counter & vsync
; The CP/M interrupt handler at $F057 is patched to jump to
; our tiny ISR that increments a frame counter, then RETs.
; wait_vsync spins until the counter changes — never misses
; a frame even if game logic takes > 20ms.
; ============================================================

; Tiny ISR — just increment the frame counter and return.
_frame_isr:
    push    af
    ld      a, (_frame_counter)
    inc     a
    ld      (_frame_counter), a
    pop     af
    ret

; Install our ISR: save original $F057-$F059, patch with JP _frame_isr
_vsync_init_asm:
    ; Save original 3 bytes
    ld      a, ($F057)
    ld      (_saved_f057), a
    ld      a, ($F058)
    ld      (_saved_f057+1), a
    ld      a, ($F059)
    ld      (_saved_f057+2), a
    ; Patch: JP _frame_isr
    ld      a, $C3
    ld      ($F057), a
    ld      hl, _frame_isr
    ld      ($F058), hl
    xor     a
    ld      (_frame_counter), a
    ret

; Restore original 3 bytes at $F057
_vsync_shutdown_asm:
    ld      a, (_saved_f057)
    ld      ($F057), a
    ld      a, (_saved_f057+1)
    ld      ($F058), a
    ld      a, (_saved_f057+2)
    ld      ($F059), a
    ret

; Wait until frame_counter changes (spin-wait, ~50 Hz)
_wait_vsync_asm:
    ld      a, (_frame_counter)
_wv_loop:
    ld      b, a
    ld      a, (_frame_counter)
    cp      b
    jr      z, _wv_loop
    ret

; ============================================================
; Font data — 5x7 pixel glyphs
; ============================================================
_font_gfx:
    ; A
    defb $0E, $1B, $1B, $1F, $1B, $1B, $1B
    ; B
    defb $1E, $1B, $1B, $1E, $1B, $1B, $1E
    ; C
    defb $0E, $1B, $18, $18, $18, $1B, $0E
    ; D
    defb $1E, $1B, $1B, $1B, $1B, $1B, $1E
    ; E
    defb $1F, $18, $18, $1E, $18, $18, $1F
    ; F
    defb $1F, $18, $18, $1E, $18, $18, $18
    ; G
    defb $0E, $1B, $18, $1B, $1B, $1B, $0E
    ; H
    defb $1B, $1B, $1B, $1F, $1B, $1B, $1B
    ; I
    defb $1F, $04, $04, $04, $04, $04, $1F
    ; J
    defb $0F, $03, $03, $03, $03, $1B, $0E
    ; K
    defb $1B, $1A, $1C, $18, $1C, $1A, $1B
    ; L
    defb $18, $18, $18, $18, $18, $18, $1F
    ; M
    defb $1B, $1F, $15, $1B, $1B, $1B, $1B
    ; N
    defb $1B, $1B, $1F, $1F, $1B, $1B, $1B
    ; O
    defb $0E, $1B, $1B, $1B, $1B, $1B, $0E
    ; P
    defb $1E, $1B, $1B, $1E, $18, $18, $18
    ; Q
    defb $0E, $1B, $1B, $1B, $1B, $0E, $03
    ; R
    defb $1E, $1B, $1B, $1E, $1A, $1B, $1B
    ; S
    defb $0E, $1B, $18, $0E, $03, $1B, $0E
    ; T
    defb $1F, $04, $04, $04, $04, $04, $04
    ; U
    defb $1B, $1B, $1B, $1B, $1B, $1B, $0E
    ; V
    defb $1B, $1B, $1B, $1B, $1B, $0A, $04
    ; W
    defb $1B, $1B, $1B, $1B, $15, $1F, $0A
    ; X
    defb $1B, $1B, $0E, $04, $0E, $1B, $1B
    ; Y
    defb $1B, $1B, $0E, $04, $04, $04, $04
    ; Z
    defb $1F, $03, $06, $04, $0C, $18, $1F
    ; 0
    defb $0E, $1B, $1B, $1B, $1B, $1B, $0E
    ; 1
    defb $0C, $1C, $0C, $0C, $0C, $0C, $1F
    ; 2
    defb $0E, $1B, $03, $06, $0C, $18, $1F
    ; 3
    defb $0E, $1B, $03, $0E, $03, $1B, $0E
    ; 4
    defb $03, $0B, $13, $1B, $1F, $03, $03
    ; 5
    defb $1F, $18, $1E, $03, $03, $1B, $0E
    ; 6
    defb $0E, $18, $18, $1E, $1B, $1B, $0E
    ; 7
    defb $1F, $03, $03, $06, $0C, $0C, $0C
    ; 8
    defb $0E, $1B, $1B, $0E, $1B, $1B, $0E
    ; 9
    defb $0E, $1B, $1B, $0F, $03, $03, $0E
    ; space (index 36)
    defb $00, $00, $00, $00, $00, $00, $00
    ; ! (index 37)
    defb $04, $04, $04, $04, $04, $00, $04
    ; . (index 38)
    defb $00, $00, $00, $00, $00, $00, $04
    ; : (index 39)
    defb $00, $04, $00, $00, $00, $04, $00
    ; - (index 40)
    defb $00, $00, $00, $0E, $00, $00, $00

; ============================================================
; ASCII-to-glyph lookup table (128 entries)
; ============================================================
_char_map:
    ; 0x00-0x0F
    defb 36,36,36,36,36,36,36,36, 36,36,36,36,36,36,36,36
    ; 0x10-0x1F
    defb 36,36,36,36,36,36,36,36, 36,36,36,36,36,36,36,36
    ; 0x20-0x2F: ' ' ! " # $ % & ' ( ) * + , - . /
    defb 36,37,36,36,36,36,36,36, 36,36,36,36,36,40,38,36
    ; 0x30-0x3F: 0-9 : ; < = > ?
    defb 26,27,28,29,30,31,32,33, 34,35,39,36,36,36,36,36
    ; 0x40-0x4F: @ A-O
    defb 36, 0, 1, 2, 3, 4, 5, 6,  7, 8, 9,10,11,12,13,14
    ; 0x50-0x5F: P-Z [ \ ] ^ _
    defb 15,16,17,18,19,20,21,22, 23,24,25,36,36,36,36,36
    ; 0x60-0x6F: ` a-o (lowercase = uppercase)
    defb 36, 0, 1, 2, 3, 4, 5, 6,  7, 8, 9,10,11,12,13,14
    ; 0x70-0x7F: p-z { | } ~ DEL
    defb 15,16,17,18,19,20,21,22, 23,24,25,36,36,36,36,36

; ============================================================
; vid_draw_text_gfx — fast text rendering
; Params: _txt_x, _txt_y, _txt_str (pointer), _txt_colour
; ============================================================
_vid_draw_text_gfx:
    push    ix

    ; Copy string to high-memory buffer (max 31 chars + null)
    ld      hl, (_txt_str)
    ld      de, _txt_strbuf
    ld      b, 31
txt_strcpy:
    ld      a, (hl)
    ld      (de), a
    or      a
    jr      z, txt_strcpy_done
    inc     hl
    inc     de
    djnz    txt_strcpy
    xor     a
    ld      (de), a
txt_strcpy_done:

    ; Prepare colour byte (both nibbles same)
    ld      a, (_txt_colour)
    and     $0F
    ld      b, a
    rlca
    rlca
    rlca
    rlca
    or      b
    ld      (_txt_colbyte), a

    call    swapgfxbk

    ld      ix, _txt_strbuf

; Character loop
txt_char_loop:
    ld      a, (ix+0)
    or      a
    jp      z, txt_done
    inc     ix

    ; Map ASCII to glyph index
    and     $7F
    ld      e, a
    ld      d, 0
    ld      hl, _char_map
    add     hl, de
    ld      a, (hl)

    ; Compute glyph pointer: _font_gfx + index * 7
    ld      l, a
    ld      h, 0
    add     hl, hl          ; *2
    add     hl, hl          ; *4
    add     hl, hl          ; *8
    ld      e, a
    ld      d, 0
    or      a
    sbc     hl, de          ; *8 - *1 = *7
    ld      de, _font_gfx
    add     hl, de
    ld      (_txt_glyph), hl

    ; Compute VRAM address: y * 128 + x / 2
    ld      hl, (_txt_y)
    ld      a, l
    srl     a
    ld      h, a
    ld      a, (_txt_y)
    rrca
    and     $80
    ld      l, a

    ld      a, (_txt_x)
    srl     a
    add     a, l
    ld      l, a
    jr      nc, txt_noc1
    inc     h
txt_noc1:
    ; HL = VRAM address

    ld      b, 7            ; 7 rows

    ld      a, (_txt_x)
    and     $01
    ld      c, a            ; C = alignment (0=even, 1=odd)

    ld      de, (_txt_glyph)

txt_row_loop:
    push    bc
    push    hl

    ld      a, (de)
    inc     de
    push    de

    ld      b, a
    ld      a, c
    or      a
    jr      nz, txt_row_odd

    ; ── EVEN alignment ──
    ; Byte 0: pixel 0 (bit4) -> low nibble, pixel 1 (bit3) -> high nibble
    ld      a, (hl)
    and     $F0

    bit     4, b
    jr      z, txt_e0_bg
    ld      c, a
    ld      a, (_txt_colbyte)
    and     $0F
    or      c
    jr      txt_e0_done
txt_e0_bg:
txt_e0_done:
    ld      c, a

    bit     3, b
    jr      z, txt_e1_bg
    ld      a, (_txt_colbyte)
    and     $F0
    or      c
    jr      txt_e1_done
txt_e1_bg:
    ld      a, c
txt_e1_done:
    ld      (hl), a
    inc     hl

    ; Byte 1: pixel 2 (bit2) -> low, pixel 3 (bit1) -> high
    ld      a, 0

    bit     2, b
    jr      z, txt_e2_bg
    ld      a, (_txt_colbyte)
    and     $0F
txt_e2_bg:
    ld      c, a

    bit     1, b
    jr      z, txt_e3_bg
    ld      a, (_txt_colbyte)
    and     $F0
    or      c
    jr      txt_e3_done
txt_e3_bg:
    ld      a, c
txt_e3_done:
    ld      (hl), a
    inc     hl

    ; Byte 2: pixel 4 (bit0) -> low nibble, preserve high nibble
    ld      a, (hl)
    and     $F0

    bit     0, b
    jr      z, txt_e4_bg
    ld      c, a
    ld      a, (_txt_colbyte)
    and     $0F
    or      c
    jr      txt_e4_done
txt_e4_bg:
txt_e4_done:
    ld      (hl), a

    jr      txt_row_end

    ; ── ODD alignment ──
txt_row_odd:
    ; Byte 0: preserve low nibble, pixel 0 -> high nibble
    ld      a, (hl)
    and     $0F

    bit     4, b
    jr      z, txt_o0_bg
    ld      c, a
    ld      a, (_txt_colbyte)
    and     $F0
    or      c
    jr      txt_o0_done
txt_o0_bg:
txt_o0_done:
    ld      (hl), a
    inc     hl

    ; Byte 1: pixel 1 (bit3) -> low, pixel 2 (bit2) -> high
    ld      a, 0

    bit     3, b
    jr      z, txt_o1_bg
    ld      a, (_txt_colbyte)
    and     $0F
txt_o1_bg:
    ld      c, a

    bit     2, b
    jr      z, txt_o2_bg
    ld      a, (_txt_colbyte)
    and     $F0
    or      c
    jr      txt_o2_done
txt_o2_bg:
    ld      a, c
txt_o2_done:
    ld      (hl), a
    inc     hl

    ; Byte 2: pixel 3 (bit1) -> low, pixel 4 (bit0) -> high
    ld      a, 0

    bit     1, b
    jr      z, txt_o3_bg
    ld      a, (_txt_colbyte)
    and     $0F
txt_o3_bg:
    ld      c, a

    bit     0, b
    jr      z, txt_o4_bg
    ld      a, (_txt_colbyte)
    and     $F0
    or      c
    jr      txt_o4_done
txt_o4_bg:
    ld      a, c
txt_o4_done:
    ld      (hl), a

txt_row_end:
    pop     de
    pop     hl
    pop     bc

    ; Next scanline (+128 bytes)
    ld      a, l
    add     a, 128
    ld      l, a
    jr      nc, txt_row_nc
    inc     h
txt_row_nc:
    dec     b
    jp      nz, txt_row_loop

    ; Advance x by 6 (FONT_W=5 + SPACING=1)
    ld      hl, (_txt_x)
    ld      de, 6
    add     hl, de
    ld      (_txt_x), hl

    jp      txt_char_loop

txt_done:
    call    swapgfxbk1
    pop     ix
    ret
