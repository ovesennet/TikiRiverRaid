/* TIKI RIVER RAID — video.h
 * Video subsystem — mode set, direct VRAM access for drawing.
 */

#ifndef VIDEO_H
#define VIDEO_H

#include "defs.h"

void vid_init(void);
void vid_shutdown(void);
void vid_clear(void);
void vid_hline(uint16_t x1, uint16_t x2, uint16_t y, uint8_t colour);
void vid_fill_rect(uint16_t x, uint16_t y, uint8_t w, uint8_t h, uint8_t colour);
void vid_draw_text(uint16_t x, uint16_t y, const char *str, uint8_t colour);

/* Draw one full-width river line (land + water + land) in a single VRAM switch */
void vid_draw_river_line(uint8_t y, uint8_t left, uint8_t right);

/* Combined game step: river line + HUD repair + plane sprite + optional fuel blit, ONE bank switch */
void vid_game_step(uint8_t riv_line_y, uint8_t left, uint8_t right,
                   uint8_t plane_x, uint8_t plane_y, uint8_t plane_col);

/* Set fuel sprite blit params (call before vid_game_step) */
void vid_set_blit(uint8_t active, uint8_t x, uint8_t row);

/* Batched VRAM access — bracket multiple _nr calls in a single bank switch */
void vid_begin_vram(void);
void vid_end_vram(void);
void vid_hline_nr(uint16_t x1, uint16_t x2, uint16_t y, uint8_t colour);
void vid_fill_rect_nr(uint16_t x, uint16_t y, uint8_t w, uint8_t h, uint8_t colour);

/* Hardware scroll via AY-3-8912 register 14 */
void scroll_set(uint8_t val);
uint8_t scroll_get(void);

/* Wait for next vertical blank interrupt (~50 Hz) */
void wait_vsync(void);

/* Frame counter — incremented by ISR at 50 Hz */
extern uint8_t frame_counter;

#endif /* VIDEO_H */
