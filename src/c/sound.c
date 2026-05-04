/* TIKI RIVER RAID — sound.c
 * Sound effects via AY-3-8912 PSG.
 * Uses set_psg() directly to preserve R7 bit 6 (Port A = scroll output).
 *
 * AY R7 bits (active low: 0=enabled, 1=disabled):
 *   0: Tone A   1: Tone B   2: Tone C
 *   3: Noise A  4: Noise B  5: Noise C
 *   6: Port A direction (1=output — MUST stay 1 for scroll)
 *   7: Port B direction
 */

#include <arch/tiki100.h>
#include "sound.h"

/* R7 base: bit6=1 (Port A output for scroll), all channels disabled */
#define R7_BASE  0x7F   /* 0111 1111: all tone+noise disabled, port A out */

/* Track active sound state for combining channels */
static uint8_t engine_active;   /* 1 = engine noise running on ch A */
static uint8_t shot_timer;      /* >0 = shot/explode tone on ch B, counts down */
static uint8_t shot_noise_on;   /* 1 = noise active on ch C */
static uint8_t sfx_type;        /* 0=shoot, 1=explode, 2=crash */

/* Recompute R7 mixer from current state */
static void mixer_update(void)
{
    uint8_t tone_mask, noise_mask, r7;
    tone_mask = 0;
    noise_mask = 0;
    if (engine_active)  noise_mask = noise_mask | 1;  /* noise on ch A */
    if (shot_timer > 0) tone_mask = tone_mask | 2;    /* tone on ch B */
    if (shot_noise_on)  noise_mask = noise_mask | 4;  /* noise on ch C */
    r7 = R7_BASE & ~(tone_mask | (noise_mask << 3));
    set_psg(7, r7);
}

void sound_init(void)
{
    engine_active = 0;
    shot_timer = 0;
    shot_noise_on = 0;
    sfx_type = 0;
    /* Silence all channels */
    set_psg(8, 0);   /* vol A = 0 */
    set_psg(9, 0);   /* vol B = 0 */
    set_psg(10, 0);  /* vol C = 0 */
    mixer_update();
}

void sound_off(void)
{
    engine_active = 0;
    shot_timer = 0;
    shot_noise_on = 0;
    sfx_type = 0;
    set_psg(8, 0);
    set_psg(9, 0);
    set_psg(10, 0);
    mixer_update();
}

/* Engine noise: channel A noise, moderate period for a rumble */
void snd_engine_on(void)
{
    set_psg(6, 14);       /* noise period (0-31): 14 = mid-low rumble */
    set_psg(8, 7);        /* channel A volume (0-15) */
    engine_active = 1;
    mixer_update();
}

void snd_engine_off(void)
{
    set_psg(8, 0);        /* silence channel A */
    engine_active = 0;
    mixer_update();
}

/* Shooting sound: classic AY laser zap using two channels (B tone + C noise)
 * Rapid descending tone sweep on ch B, short noise burst on ch C.
 * Based on techniques from AYFX/ZX Spectrum game sound effects. */

/* Per-frame tone periods for descending sweep (high→low frequency) */
/* --- Shoot SFX: 5-frame descending zap --- */
static const uint16_t shoot_tone[] = {
    10, 60, 180, 400, 700
};
static const uint8_t shoot_vol[] = {
    15, 15, 13, 9, 4
};
#define SHOOT_FRAMES 5

/* --- Explode SFX: 8-frame low rumbling boom (rocket hit) --- */
static const uint16_t expl_tone[] = {
    80, 200, 350, 500, 600, 700, 800, 900
};
static const uint8_t expl_vol[] = {
    15, 15, 14, 13, 11, 9, 5, 2
};
static const uint8_t expl_noise[] = {
    4, 6, 8, 12, 16, 20, 24, 28
};
#define EXPL_FRAMES 8

/* --- Crash SFX: 15-frame big explosion (plane crash) --- */
static const uint16_t crash_tone[] = {
    30, 100, 200, 350, 500, 600, 700, 800, 850, 900, 950, 1000, 1050, 1100, 1200
};
static const uint8_t crash_vol[] = {
    15, 15, 15, 15, 14, 14, 13, 12, 11, 10, 8, 6, 4, 2, 1
};
static const uint8_t crash_nvol[] = {
    15, 15, 14, 13, 12, 11, 10, 9, 7, 5, 3, 2, 1, 0, 0
};
static const uint8_t crash_noise[] = {
    2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30
};
#define CRASH_FRAMES 15

/* --- Refuel SFX: 6-frame ascending chirp (fuel pickup) --- */
static const uint16_t refuel_tone[] = {
    600, 350, 200, 120, 60, 30
};
static const uint8_t refuel_vol[] = {
    12, 14, 15, 15, 14, 10
};
#define REFUEL_FRAMES 6

static void sfx_stop(void)
{
    set_psg(9, 0);       /* silence ch B */
    set_psg(10, 0);      /* silence ch C */
    set_psg(6, 14);      /* restore engine noise period */
    shot_noise_on = 0;
    shot_timer = 0;
    mixer_update();
}

void snd_shoot(void)
{
    set_psg(2, shoot_tone[0] & 0xFF);
    set_psg(3, shoot_tone[0] >> 8);
    set_psg(9, 15);
    set_psg(6, 2);
    set_psg(10, 13);
    shot_noise_on = 1;
    sfx_type = 0;
    shot_timer = SHOOT_FRAMES;
    mixer_update();
}

void snd_explode(void)
{
    /* Low boom: tone + noise on ch B, heavy noise on ch C */
    set_psg(2, expl_tone[0] & 0xFF);
    set_psg(3, expl_tone[0] >> 8);
    set_psg(9, 15);
    set_psg(6, expl_noise[0]);
    set_psg(10, 15);
    shot_noise_on = 1;
    sfx_type = 1;
    shot_timer = EXPL_FRAMES;
    mixer_update();
}

void snd_crash(void)
{
    /* Big crash: loud low tone + heavy noise, long decay */
    set_psg(2, crash_tone[0] & 0xFF);
    set_psg(3, crash_tone[0] >> 8);
    set_psg(9, 15);
    set_psg(6, crash_noise[0]);
    set_psg(10, 15);
    shot_noise_on = 1;
    sfx_type = 2;
    shot_timer = CRASH_FRAMES;
    mixer_update();
}

void snd_refuel(void)
{
    /* Rising chirp: pure tone on ch B, no noise */
    set_psg(2, refuel_tone[0] & 0xFF);
    set_psg(3, refuel_tone[0] >> 8);
    set_psg(9, refuel_vol[0]);
    set_psg(10, 0);
    shot_noise_on = 0;
    sfx_type = 3;
    shot_timer = REFUEL_FRAMES;
    mixer_update();
}

/* Call once per frame to handle sound timers */
void snd_update(void)
{
    if (shot_timer > 0) {
        uint8_t idx, maxf;
        shot_timer--;

        if (sfx_type == 0) {
            /* Shoot */
            maxf = SHOOT_FRAMES;
            idx = maxf - 1 - shot_timer;
            set_psg(2, shoot_tone[idx] & 0xFF);
            set_psg(3, shoot_tone[idx] >> 8);
            set_psg(9, shoot_vol[idx]);
            if (idx == 2) {
                set_psg(10, 0);
                shot_noise_on = 0;
                set_psg(6, 14);
                mixer_update();
            }
        } else if (sfx_type == 1) {
            /* Explode */
            idx = EXPL_FRAMES - 1 - shot_timer;
            set_psg(2, expl_tone[idx] & 0xFF);
            set_psg(3, expl_tone[idx] >> 8);
            set_psg(9, expl_vol[idx]);
            set_psg(6, expl_noise[idx]);
            set_psg(10, expl_vol[idx]);
        } else if (sfx_type == 2) {
            /* Crash */
            idx = CRASH_FRAMES - 1 - shot_timer;
            set_psg(2, crash_tone[idx] & 0xFF);
            set_psg(3, crash_tone[idx] >> 8);
            set_psg(9, crash_vol[idx]);
            set_psg(6, crash_noise[idx]);
            set_psg(10, crash_nvol[idx]);
        } else {
            /* Refuel */
            idx = REFUEL_FRAMES - 1 - shot_timer;
            set_psg(2, refuel_tone[idx] & 0xFF);
            set_psg(3, refuel_tone[idx] >> 8);
            set_psg(9, refuel_vol[idx]);
        }

        if (shot_timer == 0) {
            sfx_stop();
        }
    }
}
