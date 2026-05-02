#ifndef SPRITE_H
#define SPRITE_H

#include "defs.h"

extern uint8_t blit_out_active;
extern uint8_t blit_out_x;
extern uint8_t blit_out_row;

void sprite_init(void);
void sprite_prepare_blit(void);
void sprite_check_spawn(uint8_t river_left, uint8_t river_right);

#endif
