#include "sprite.h"

#define FUEL_W          14
#define FUEL_H          24

static uint8_t spr_active;
static uint8_t spr_x;
static uint8_t spr_enter_row;
static uint8_t spawn_timer;

uint8_t blit_out_active;
uint8_t blit_out_x;
uint8_t blit_out_row;

void sprite_init(void)
{
    spr_active = 0;
    spawn_timer = 0;
}

void sprite_check_spawn(uint8_t river_left, uint8_t river_right)
{
    uint8_t mid;

    if (spr_active)
        return;

    if (spawn_timer > 0) {
        spawn_timer--;
        return;
    }

    mid = (river_left >> 1) + (river_right >> 1);
    spr_x = (mid - 7) & 0xFE;
    spr_enter_row = 0;
    spr_active = 1;
    spawn_timer = 150;
}

void sprite_prepare_blit(void)
{
    blit_out_active = 0;
    if (spr_active && spr_enter_row < FUEL_H) {
        blit_out_active = 1;
        blit_out_x = spr_x;
        blit_out_row = spr_enter_row;
        spr_enter_row++;
        if (spr_enter_row >= FUEL_H)
            spr_active = 0;
    }
}
