/* TIKI RIVER RAID — video.c
 * Video init and C wrappers calling ASM routines in screen.asm.
 */

#include <arch/tiki100.h>
#include "video.h"

/* Assembly routines in screen.asm */
extern void vid_clear_asm(void);
extern void vid_hline_gfx(void);
extern void vid_fill_rect_gfx(void);
extern void vid_draw_text_gfx(void);
extern void vid_draw_river_line_asm(void);
extern void vid_game_step_asm(void);
extern void vid_game_frame_asm(void);
extern void vid_begin_vram_asm(void);
extern void vid_end_vram_asm(void);
extern void vid_hline_nr_asm(void);
extern void vid_fill_rect_nr_asm(void);
extern void scroll_set_asm(void);
extern void scroll_get_asm(void);
extern void vsync_init_asm(void);
extern void vsync_shutdown_asm(void);
extern void wait_vsync_asm(void);
extern void hud_snapshot_asm(void);

/* Global parameter blocks (bss_graphics section in screen.asm) */
extern uint16_t gfx_x1;
extern uint16_t gfx_y1;
extern uint16_t gfx_x2;
extern uint16_t gfx_y2;
extern uint8_t  gfx_colour;
extern uint8_t  gfx_width;
extern uint8_t  gfx_height;

extern uint16_t txt_x;
extern uint16_t txt_y;
extern uint16_t txt_str;
extern uint8_t  txt_colour;

extern uint8_t  riv_y;
extern uint8_t  riv_left;
extern uint8_t  riv_right;
extern uint8_t  riv_land_col;
extern uint8_t  riv_water_col;

extern uint8_t  gs_plane_x;
extern uint8_t  gs_plane_y;
extern uint8_t  gs_plane_col;
extern uint8_t  gs_plane_pose;
extern uint8_t  gs_hud_sep_y;
extern uint8_t  gs_hud_top_y;
extern uint8_t  gs_hud_col;

extern uint8_t  gs_blit_active;
extern uint8_t  gs_blit_x;
extern uint8_t  gs_blit_row;
extern uint8_t  gs_blit_type;
extern uint8_t  gs_blit_mirror;

extern uint8_t  gs_scroll_reg;

extern uint8_t  step_buf[];
extern uint8_t  step_count;

extern uint8_t  scroll_val;

/* Palette: CGA-like 16 colours (same as TikiArkanoid) */
static const char palette[16] = {
    0x00, 0x03, 0x1C, 0x1F, 0xE0, 0xE3, 0xF0, 0xDB,
    0x49, 0x4B, 0x5C, 0x5F, 0xEC, 0xF3, 0xFC, 0xFF,
};

void vid_init(void)
{
    gr_defmod(3);
    gr_setpalette(16, palette);

    /* Install frame-counter ISR at CP/M interrupt hook */
    vsync_init_asm();

    /* Set default river colours */
    riv_land_col = LAND_COLOUR;
    riv_water_col = WATER_COLOUR;

    /* Set HUD repair params (constant during game) */
    gs_hud_sep_y = HUD_SEP_Y;
    gs_hud_top_y = HUD_TOP;
    gs_hud_col = HUD_COLOUR;

    /* Reset hardware scroll */
    scroll_set(0);

    vid_clear();
}

void vid_shutdown(void)
{
    /* Reset scroll before restoring video mode */
    scroll_set(0);

    /* Restore original CP/M interrupt handler */
    vsync_shutdown_asm();

    gr_defmod(1);
}

void vid_clear(void)       { vid_clear_asm(); }

void vid_hline(uint16_t x1, uint16_t x2, uint16_t y, uint8_t colour)
{
    if (y >= 256) return;
    if (x1 > x2) { uint16_t t = x1; x1 = x2; x2 = t; }
    if (x2 >= 256) x2 = 255;
    gfx_x1 = x1; gfx_x2 = x2; gfx_y1 = y; gfx_colour = colour;
    vid_hline_gfx();
}

void vid_fill_rect(uint16_t x, uint16_t y, uint8_t w, uint8_t h, uint8_t colour)
{
    if (w == 0 || h == 0) return;
    gfx_x1 = x; gfx_y1 = y; gfx_width = w; gfx_height = h; gfx_colour = colour;
    vid_fill_rect_gfx();
}

void vid_draw_text(uint16_t x, uint16_t y, const char *str, uint8_t colour)
{
    txt_x = x; txt_y = y; txt_str = (uint16_t)str; txt_colour = colour;
    vid_draw_text_gfx();
}

void vid_draw_river_line(uint8_t y, uint8_t left, uint8_t right)
{
    riv_y = y;
    riv_left = left;
    riv_right = right;
    vid_draw_river_line_asm();
}

void vid_game_step(uint8_t scroll_reg, uint8_t riv_line_y, uint8_t left, uint8_t right,
                   uint8_t plane_x, uint8_t plane_y, uint8_t plane_col)
{
    gs_scroll_reg = scroll_reg;
    riv_y = riv_line_y;
    riv_left = left;
    riv_right = right;
    gs_plane_x = plane_x;
    gs_plane_y = plane_y;
    gs_plane_col = plane_col;
    vid_game_step_asm();
}

void vid_set_blit(uint8_t active, uint8_t x, uint8_t row)
{
    gs_blit_active = active;
    gs_blit_x = x;
    gs_blit_row = row;
}

void vid_set_blit_type(uint8_t type)
{
    gs_blit_type = type;
}

extern void vid_enemy_shift_asm(void);
extern void vid_enemy_mirror_asm(void);

extern uint8_t es_screen_y;
extern uint8_t es_old_x;
extern uint8_t es_new_x;
extern uint8_t es_width;
extern uint8_t es_height;

void vid_set_blit_mirror(uint8_t mirror)
{
    gs_blit_mirror = mirror;
}

void vid_enemy_shift(uint8_t screen_y, uint8_t old_x, uint8_t new_x, uint8_t width, uint8_t height)
{
    es_screen_y = screen_y;
    es_old_x = old_x;
    es_new_x = new_x;
    es_width = width;
    es_height = height;
    vid_enemy_shift_asm();
}

void vid_enemy_mirror(uint8_t screen_y, uint8_t x, uint8_t width, uint8_t height)
{
    es_screen_y = screen_y;
    es_old_x = x;
    es_width = width;
    es_height = height;
    vid_enemy_mirror_asm();
}

void vid_set_plane_pose(uint8_t pose)
{
    gs_plane_pose = pose;
}

void vid_game_frame(uint8_t num_steps,
                    uint8_t plane_x, uint8_t plane_y, uint8_t plane_col)
{
    step_count = num_steps;
    gs_plane_x = plane_x;
    gs_plane_y = plane_y;
    gs_plane_col = plane_col;
    vid_game_frame_asm();
}

void vid_begin_vram(void) { vid_begin_vram_asm(); }
void vid_end_vram(void)   { vid_end_vram_asm(); }

void vid_hline_nr(uint16_t x1, uint16_t x2, uint16_t y, uint8_t colour)
{
    if (y >= 256) return;
    if (x1 > x2) { uint16_t t = x1; x1 = x2; x2 = t; }
    if (x2 >= 256) x2 = 255;
    gfx_x1 = x1; gfx_x2 = x2; gfx_y1 = y; gfx_colour = colour;
    vid_hline_nr_asm();
}

void vid_fill_rect_nr(uint16_t x, uint16_t y, uint8_t w, uint8_t h, uint8_t colour)
{
    if (w == 0 || h == 0) return;
    gfx_x1 = x; gfx_y1 = y; gfx_width = w; gfx_height = h; gfx_colour = colour;
    vid_fill_rect_nr_asm();
}

void scroll_set(uint8_t val)
{
    scroll_val = val;
    scroll_set_asm();
}

void hud_snapshot(void)
{
    hud_snapshot_asm();
}

uint8_t scroll_get(void)
{
    scroll_get_asm();
    return scroll_val;
}

void wait_vsync(void) { wait_vsync_asm(); }
