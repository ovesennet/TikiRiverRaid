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

/* Combined game step: erase plane, scroll, river+HUD, draw plane — ONE bank switch */
void vid_game_step(uint8_t scroll_reg, uint8_t riv_line_y, uint8_t left, uint8_t right,
                   uint8_t plane_x, uint8_t plane_y, uint8_t plane_col);

/* Set fuel sprite blit params (call before vid_game_step) */
void vid_set_blit(uint8_t active, uint8_t x, uint8_t row);

/* Set blit sprite type: 0=fuel, 1=heli, 2=boat */
void vid_set_blit_type(uint8_t type);

/* Set blit mirror: mirror=1 to flip horizontally */
void vid_set_blit_mirror(uint8_t mirror);

/* Shift enemy sprite in VRAM horizontally (preserves pixel data) */
void vid_enemy_shift(uint8_t screen_y, uint8_t old_x, uint8_t new_x, uint8_t width, uint8_t height);

/* Mirror enemy sprite horizontally in VRAM (reverses bytes + swaps nibbles) */
void vid_enemy_mirror(uint8_t screen_y, uint8_t x, uint8_t width, uint8_t height);

/* Set plane sprite pose: 0=forward, 1=left, 2=right (call before vid_game_step) */
void vid_set_plane_pose(uint8_t pose);

/* Batched frame: pre-fill step_buf, then call this for ONE bank switch */
void vid_game_frame(uint8_t num_steps,
                    uint8_t plane_x, uint8_t plane_y, uint8_t plane_col);

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

/* Snapshot HUD VRAM rows into RAM buffer (call after rendering HUD) */
void hud_snapshot(void);

#endif /* VIDEO_H */
