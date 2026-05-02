/* TIKI RIVER RAID — river.c
 * Procedural river generation using deterministic LFSR RNG.
 * Generates one scanline at a time for the vertical scrolling river.
 */

#include "river.h"
#include "defs.h"

static uint16_t rng_state;
static uint8_t  river_width;
static uint8_t  target_width;
static uint8_t  segment_lines;    /* lines remaining in current segment */

void river_init(uint16_t seed)
{
    rng_state = seed;
    river_width  = RIVER_INIT_WIDTH;
    target_width = RIVER_INIT_WIDTH;
    segment_lines = 0;
}

/* 16-bit Galois LFSR — fast, deterministic RNG */
static uint8_t next_random(void)
{
    uint8_t lsb = rng_state & 1;
    rng_state >>= 1;
    if (lsb)
        rng_state ^= 0xB400;
    return (uint8_t)(rng_state & 0xFF);
}

void river_generate_line(uint8_t *left, uint8_t *right)
{
    uint8_t rnd, half_w;

    /* Start new segment: pick new target width */
    if (segment_lines == 0) {
        rnd = next_random();
        segment_lines = 120 + (next_random());  /* 120-375 lines per segment */

        /* New target width */
        rnd = next_random();
        target_width = RIVER_MIN_WIDTH + (rnd % (RIVER_MAX_WIDTH - RIVER_MIN_WIDTH + 1));
    }
    segment_lines--;

    /* Rapidly adjust width towards target (steep bank angles) */
    if (river_width < target_width) {
        river_width += 4;
        if (river_width > target_width)
            river_width = target_width;
    } else if (river_width > target_width) {
        river_width -= 4;
        if (river_width < target_width)
            river_width = target_width;
    }

    /* Mirror symmetrically around screen center (128) */
    half_w = river_width >> 1;
    *left  = 128 - half_w;
    *right = 128 + half_w;
}
