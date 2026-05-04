/* TIKI RIVER RAID — main.c
 * Title screen, game loop with vertical scrolling river.
 *
 * Controls: SPACE = start, Q = quit (title→OS, game→title)
 */

#include <string.h>
#include "defs.h"
#include "video.h"
#include "input.h"
#include "river.h"

extern uint8_t kbd_scan(void);
extern uint8_t sav_valid;
extern uint8_t gs_do_plane;

/* Fuel barrel constants */
#define FUEL_W  14
#define FUEL_H  24

/* Enemy constants */
#define HELI_W   16
#define HELI_H   10
#define BOAT_W   32
#define BOAT_H   8
#define BLIT_FUEL  0
#define BLIT_HELI  1
#define BLIT_BOAT  2
#define LIVES_START 3

/* ── Delay loop ── */
void delay(uint16_t n)
{
    volatile uint16_t i;
    for (i = 0; i < n; i++) ;
}

/* ── Sprite rectangle (offset from sprite origin) ── */
typedef struct {
    uint8_t dx, dy, w, h;
} SpriteRect;

/* ── Plane sprites: forward, left-turn, right-turn (12x12) ── */
static const SpriteRect spr_plane_fwd[] = {
    { 5, 0, 2, 2},   /* nose */
    { 4, 2, 4, 2},   /* upper body */
    { 2, 4, 8, 2},   /* mid body */
    { 0, 6, 12, 2},  /* wings */
    { 4, 8, 4, 2},   /* lower body */
    { 2,10, 2, 2},   /* left tail */
    { 8,10, 2, 2}    /* right tail */
};
#define SPR_FWD_COUNT 7

static const SpriteRect spr_plane_left[] = {
    { 4, 0, 2, 2},   /* nose shifted left */
    { 3, 2, 4, 2},   /* upper body */
    { 1, 4, 8, 2},   /* mid body */
    { 0, 6, 12, 1},  /* wings wide */
    { 2, 7, 10, 1},  /* wings taper */
    { 4, 8, 4, 2},   /* lower body */
    { 2,10, 2, 2},   /* left tail */
    { 8,10, 2, 2}    /* right tail */
};
#define SPR_LEFT_COUNT 8

static const SpriteRect spr_plane_right[] = {
    { 6, 0, 2, 2},   /* nose shifted right */
    { 5, 2, 4, 2},   /* upper body */
    { 3, 4, 8, 2},   /* mid body */
    { 0, 6, 12, 1},  /* wings wide */
    { 0, 7, 10, 1},  /* wings taper */
    { 4, 8, 4, 2},   /* lower body */
    { 2,10, 2, 2},   /* left tail */
    { 8,10, 2, 2}    /* right tail */
};
#define SPR_RIGHT_COUNT 8

/* Draw a sprite from rectangle list */
static void draw_sprite(uint8_t x, uint8_t y,
                        const SpriteRect *rects, uint8_t count,
                        uint8_t colour)
{
    uint8_t i;
    for (i = 0; i < count; i++)
        vid_fill_rect(x + rects[i].dx, y + rects[i].dy,
                      rects[i].w, rects[i].h, colour);
}

/* ── Game state ── */
static uint16_t score;
static uint16_t fuel;          /* 0..FUEL_FULL: internal fuel level */
static uint8_t lives;

/* Forward declaration */
static void draw_centred(uint16_t y, const char *str, uint8_t colour);

#define FUEL_MAX       32      /* full gauge width in pixels */
#define FUEL_FULL      1500    /* internal fuel at 100% (~30s at 50 batches/sec) */
#define FUEL_PICKUP    450     /* 30% of FUEL_FULL */
#define FUEL_GAUGE_X   40      /* gauge bar left edge */
#define FUEL_GAUGE_Y   (HUD_TOP + 3)  /* gauge bar top (relative to HUD) */
#define FUEL_GAUGE_H   5       /* gauge bar height */
#define SCORE_X        160     /* score left edge */
#define HUD_UPDATE_INTERVAL 50 /* batches between full HUD refresh (~1 sec) */

/* ── Number to decimal string (right-aligned, up to 5 digits) ── */
static char score_buf[7];
static void uint16_to_str(uint16_t val, char *buf)
{
    uint8_t i;
    buf[0] = ' '; buf[1] = ' '; buf[2] = ' ';
    buf[3] = ' '; buf[4] = ' '; buf[5] = '\0';
    i = 4;
    if (val == 0) {
        buf[i] = '0';
        return;
    }
    while (val > 0) {
        buf[i] = '0' + (uint8_t)(val % 10);
        val = val / 10;
        if (i == 0) break;
        i--;
    }
}

/* ── HUD drawing: renders to fixed VRAM rows, then snapshots to RAM ── */
static void draw_hud(void)
{
    uint8_t gauge_px;

    vid_fill_rect(0, HUD_TOP, 128, HUD_HEIGHT, HUD_COLOUR);
    vid_fill_rect(128, HUD_TOP, 128, HUD_HEIGHT, HUD_COLOUR);

    /* Fuel gauge frame: "E" [bar] "F" */
    vid_draw_text(FUEL_GAUGE_X - 12, FUEL_GAUGE_Y - 1, "E", COL_WHITE);
    vid_draw_text(FUEL_GAUGE_X + FUEL_MAX + 4, FUEL_GAUGE_Y - 1, "F", COL_WHITE);
    vid_hline(FUEL_GAUGE_X - 1, FUEL_GAUGE_X + FUEL_MAX, FUEL_GAUGE_Y - 1, COL_WHITE);
    vid_hline(FUEL_GAUGE_X - 1, FUEL_GAUGE_X + FUEL_MAX, FUEL_GAUGE_Y + FUEL_GAUGE_H, COL_WHITE);
    vid_fill_rect(FUEL_GAUGE_X - 1, FUEL_GAUGE_Y, 1, FUEL_GAUGE_H, COL_WHITE);
    vid_fill_rect(FUEL_GAUGE_X + FUEL_MAX, FUEL_GAUGE_Y, 1, FUEL_GAUGE_H, COL_WHITE);
    gauge_px = (uint8_t)(fuel * (uint16_t)FUEL_MAX / FUEL_FULL);
    if (gauge_px > FUEL_MAX) gauge_px = FUEL_MAX;
    if (gauge_px > 0)
        vid_fill_rect(FUEL_GAUGE_X, FUEL_GAUGE_Y, gauge_px, FUEL_GAUGE_H, COL_BRGREEN);

    /* Score — right of fuel gauge */
    uint16_to_str(score, score_buf);
    vid_draw_text(SCORE_X, FUEL_GAUGE_Y - 1, score_buf, COL_YELLOW);

    /* Lives indicator — far right */
    {
        static char lives_buf[4];
        lives_buf[0] = '0' + lives;
        lives_buf[1] = 'x';
        lives_buf[2] = '\0';
        vid_draw_text(220, FUEL_GAUGE_Y - 1, lives_buf, COL_WHITE);
    }

    /* Snapshot VRAM rows → RAM buffer for per-step copy */
    hud_snapshot();
}

/* ── Centre text on screen (256px wide, 6px per char) ── */
static void draw_centred(uint16_t y, const char *str, uint8_t colour)
{
    uint8_t len = 0;
    const char *p = str;
    uint16_t x;
    while (*p++) len++;
    x = (256 - (uint16_t)len * 6) / 2;
    vid_draw_text(x, y, str, colour);
}

/* ── Title screen ── */
static void draw_title(void)
{
    uint16_t y;
    uint8_t left, right;

    vid_clear();
    scroll_set(0);

    /* Draw static river background */
    river_init(0x1234);
    for (y = 0; y < SCREEN_H; y++) {
        river_generate_line(&left, &right);
        vid_draw_river_line((uint8_t)y, left, right);
    }

    /* Title area — black box behind text */
    vid_fill_rect(28, 48, 200, 56, COL_BLACK);
    draw_centred(54, "TIKI RIVER RAID", COL_WHITE);
    draw_centred(68, "A RIVER RAID CLONE", COL_BRCYAN);
    draw_centred(84, "2026 ARCTIC RETRO", COL_LTGREY);

    /* Instructions area */
    vid_fill_rect(28, 168, 200, 36, COL_BLACK);
    draw_centred(174, "PRESS SPACE TO START", COL_YELLOW);
    draw_centred(188, "Q TO QUIT", COL_LTGREY);
}

/* Returns 1 = start game, 0 = quit to OS */
static uint8_t title_screen(void)
{
    draw_title();
    input_flush();

    for (;;) {
        wait_vsync();
        input_poll();

        if (input_pressed(KBIT_FIRE))
            return 1;
        if (input_pressed(KBIT_QUIT))
            return 0;
    }
}

/* ── Game loop with vertical scrolling river ── */
static uint8_t scroll_speed;

/* Fuel barrel — single counter approach */
static uint8_t fuel_x;
static uint16_t fuel_step;
static uint16_t fuel_gap;

/* Enemy — same counter approach as fuel */
static uint8_t enemy_x;
static uint16_t enemy_step;
static uint16_t enemy_gap;
static uint8_t enemy_type;     /* BLIT_HELI or BLIT_BOAT */
static uint8_t enemy_h;        /* height of current enemy */
static uint8_t enemy_w;        /* width of current enemy */

/* Lives */
static uint8_t hit_flash;      /* >0: invulnerability frames after hit */

/* River bank edge storage — indexed by VRAM row (ring buffer) */
static uint8_t bank_l[256];    /* left edge per VRAM row */
static uint8_t bank_r[256];    /* right edge per VRAM row */

static uint8_t plane_x;
static uint8_t gl_left, gl_right;
static uint16_t gl_y;
static uint8_t gl_scroll_reg;
static uint8_t gl_keys;
static uint8_t gl_input_ctr;
static uint8_t hud_timer;

#define MOVE_SPEED 3

static void game_loop(void)
{
    vid_clear();
    scroll_set(0);
    scroll_speed = SCROLL_SPEED_DEFAULT;
    plane_x = PLANE_START_X;
    sav_valid = 0;
    score = 0;
    fuel = FUEL_FULL;
    lives = LIVES_START;
    hit_flash = 0;

restart:
    vid_clear();
    scroll_set(0);
    scroll_speed = SCROLL_SPEED_DEFAULT;
    plane_x = PLANE_START_X;
    sav_valid = 0;
    hit_flash = 0;

    /* Init river with game seed */
    river_init(RNG_SEED);
    fuel_step = 0;
    fuel_x = 100;
    fuel_gap = 500;
    enemy_step = 0;
    enemy_x = 80;
    enemy_gap = 80;
    enemy_type = BLIT_HELI;
    enemy_h = HELI_H;
    enemy_w = HELI_W;

    /* Fill screen with initial river + store bank edges */
    for (gl_y = 0; gl_y < SCREEN_H; gl_y++) {
        river_generate_line(&gl_left, &gl_right);
        vid_draw_river_line((uint8_t)(SCREEN_H - 1 - gl_y), gl_left, gl_right);
        bank_l[(uint8_t)(SCREEN_H - 1 - gl_y)] = gl_left;
        bank_r[(uint8_t)(SCREEN_H - 1 - gl_y)] = gl_right;
    }

    /* Draw initial HUD — plane will be drawn by first vid_game_step */
    draw_hud();

    gl_scroll_reg = 0;
    gl_keys = 0;
    gl_input_ctr = 0;
    hud_timer = 0;

    for (;;) {
        /* Input once per batch */
        gl_keys = kbd_scan();

        if (gl_keys & KBIT_LEFT) {
            if (plane_x >= MOVE_SPEED)
                plane_x -= MOVE_SPEED;
            vid_set_plane_pose(POSE_LEFT);
        } else if (gl_keys & KBIT_RIGHT) {
            if (plane_x <= (uint8_t)(244 - MOVE_SPEED))
                plane_x += MOVE_SPEED;
            vid_set_plane_pose(POSE_RIGHT);
        } else {
            vid_set_plane_pose(POSE_FWD);
        }

        if (gl_keys & KBIT_QUIT)
            break;

        /* Batch scroll_speed steps per vblank */
        for (gl_input_ctr = 0; gl_input_ctr < scroll_speed; gl_input_ctr++) {
            gl_scroll_reg--;
            scroll_set(gl_scroll_reg);
            river_generate_line(&gl_left, &gl_right);

            /* Store bank edges for this VRAM row */
            bank_l[gl_scroll_reg] = gl_left;
            bank_r[gl_scroll_reg] = gl_right;

            /* Decide which object to blit this step: fuel barrel or enemy */
            if (fuel_step < FUEL_H) {
                vid_set_blit_type(BLIT_FUEL);
                vid_set_blit(1, fuel_x, (uint8_t)fuel_step);
            } else if (enemy_step < enemy_h) {
                vid_set_blit_type(enemy_type);
                vid_set_blit(1, enemy_x, (uint8_t)enemy_step);
            } else {
                vid_set_blit(0, 0, 0);
            }

            /* Draw plane every step to prevent jitter */
            gs_do_plane = 1;

            vid_game_step(gl_scroll_reg, 0, gl_left, gl_right, plane_x, PLANE_Y, COL_YELLOW);

            /* Advance fuel counter */
            fuel_step++;
            if (fuel_step >= (uint16_t)(FUEL_H + fuel_gap)) {
                uint8_t rnd, range;
                fuel_step = 0;
                rnd = frame_counter ^ gl_scroll_reg;
                fuel_gap = 250 + (uint16_t)(rnd & 0xFF) * 4;
                range = gl_right - gl_left;
                if (range > FUEL_W + 4) {
                    fuel_x = gl_left + 2 + (rnd % (range - FUEL_W - 2));
                } else {
                    fuel_x = gl_left + 2;
                }
                fuel_x = fuel_x & 0xFE;
            }

            /* Advance enemy counter */
            enemy_step++;
            if (enemy_step >= (uint16_t)(enemy_h + enemy_gap)) {
                uint8_t rnd, range;
                enemy_step = 0;
                rnd = (frame_counter * 7) ^ gl_scroll_reg;
                /* Alternate heli and boat */
                if (rnd & 0x04) {
                    enemy_type = BLIT_HELI;
                    enemy_h = HELI_H;
                    enemy_w = HELI_W;
                } else {
                    enemy_type = BLIT_BOAT;
                    enemy_h = BOAT_H;
                    enemy_w = BOAT_W;
                }
                enemy_gap = 60 + (uint16_t)(rnd & 0x3F);
                range = gl_right - gl_left;
                if (range > enemy_w + 4) {
                    enemy_x = gl_left + 2 + (rnd % (range - enemy_w - 2));
                } else {
                    enemy_x = gl_left + 2;
                }
                enemy_x = enemy_x & 0xFE;
            }
        }

        /* Score: +10 per batch */
        score += 10;

        /* Fuel: deplete 1 per batch (empty in ~30s at 50Hz) */
        if (fuel > 0)
            fuel--;

        /* Hit flash countdown */
        if (hit_flash > 0)
            hit_flash--;

        /* Barrel collision: check when barrel has scrolled to plane's Y */
        if (fuel_step >= (uint16_t)PLANE_Y &&
            fuel_step <= (uint16_t)(PLANE_Y + PLANE_H + FUEL_H - 2)) {
            if (plane_x + PLANE_W > fuel_x && plane_x < fuel_x + FUEL_W) {
                fuel = fuel + FUEL_PICKUP;
                if (fuel > FUEL_FULL) fuel = FUEL_FULL;
                fuel_step = (uint16_t)(PLANE_Y + PLANE_H + FUEL_H);
                score += 100;
            }
        }

        /* River bank collision: check plane against stored edges at PLANE_Y */
        if (hit_flash == 0) {
            uint8_t bl, br;
            bl = bank_l[PLANE_Y];
            br = bank_r[PLANE_Y];
            if (plane_x < bl || (plane_x + PLANE_W) > br) {
                goto crash;
            }
        }

        /* Enemy collision: check when enemy has scrolled to plane's Y */
        if (hit_flash == 0 &&
            enemy_step >= (uint16_t)PLANE_Y &&
            enemy_step <= (uint16_t)(PLANE_Y + PLANE_H + enemy_h - 2)) {
            if (plane_x + PLANE_W > enemy_x && plane_x < enemy_x + enemy_w) {
                /* Explode the enemy sprite at its current screen position */
                {
                    uint8_t ey;
                    ey = PLANE_Y;
                    vid_fill_rect(enemy_x, ey, enemy_w, enemy_h, COL_BLUE);
                    vid_fill_rect(enemy_x + 2, ey + 0, 1, 1, COL_YELLOW);
                    vid_fill_rect(enemy_x + 5, ey + 1, 2, 1, COL_BRRED);
                    vid_fill_rect(enemy_x + 1, ey + 2, 1, 1, COL_YELLOW);
                    vid_fill_rect(enemy_x + 7, ey + 2, 1, 1, COL_BRRED);
                    vid_fill_rect(enemy_x + 3, ey + 3, 2, 1, COL_YELLOW);
                    vid_fill_rect(enemy_x + 0, ey + 4, 1, 1, COL_BRRED);
                    vid_fill_rect(enemy_x + 6, ey + 4, 1, 1, COL_YELLOW);
                    vid_fill_rect(enemy_x + 4, ey + 5, 1, 1, COL_BRRED);
                    vid_fill_rect(enemy_x + 8, ey + 5, 1, 1, COL_YELLOW);
                    vid_fill_rect(enemy_x + 2, ey + 6, 1, 1, COL_YELLOW);
                    vid_fill_rect(enemy_x + 6, ey + 7, 1, 1, COL_BRRED);
                }
                score += 200;
                enemy_step = (uint16_t)(PLANE_Y + PLANE_H + enemy_h);
                goto crash;
            }
        }

        /* Game over if fuel empty */
        if (fuel == 0) {
            goto crash;
        }

        /* Periodically re-render HUD to RAM buffer (~1 sec) */
        hud_timer++;
        if (hud_timer >= HUD_UPDATE_INTERVAL) {
            hud_timer = 0;
            draw_hud();
        }
        continue;

crash:
        /* Stop scroll, draw scattered explosion dots over plane */
        {
            uint8_t cx, cy;
            cx = plane_x;
            cy = PLANE_Y;

            /* Clear plane area */
            vid_fill_rect(cx, cy, 12, 12, COL_BLUE);

            /* Scattered dots — yellow and red, ~16x16 area */
            vid_fill_rect(cx + 2, cy + 0, 1, 1, COL_YELLOW);
            vid_fill_rect(cx + 8, cy + 0, 1, 1, COL_BRRED);
            vid_fill_rect(cx + 12, cy + 1, 1, 1, COL_YELLOW);
            vid_fill_rect(cx + 0, cy + 2, 1, 1, COL_BRRED);
            vid_fill_rect(cx + 5, cy + 1, 2, 1, COL_YELLOW);
            vid_fill_rect(cx + 10, cy + 2, 1, 1, COL_BRRED);
            vid_fill_rect(cx + 3, cy + 3, 1, 1, COL_BRRED);
            vid_fill_rect(cx + 7, cy + 3, 2, 1, COL_YELLOW);
            vid_fill_rect(cx + 13, cy + 3, 1, 1, COL_YELLOW);
            vid_fill_rect(cx + 1, cy + 4, 1, 1, COL_YELLOW);
            vid_fill_rect(cx + 5, cy + 4, 1, 2, COL_BRRED);
            vid_fill_rect(cx + 9, cy + 5, 2, 1, COL_YELLOW);
            vid_fill_rect(cx + 11, cy + 4, 1, 1, COL_BRRED);
            vid_fill_rect(cx + 0, cy + 6, 1, 1, COL_YELLOW);
            vid_fill_rect(cx + 3, cy + 6, 2, 1, COL_YELLOW);
            vid_fill_rect(cx + 7, cy + 6, 1, 1, COL_BRRED);
            vid_fill_rect(cx + 12, cy + 6, 1, 1, COL_YELLOW);
            vid_fill_rect(cx + 2, cy + 7, 1, 1, COL_BRRED);
            vid_fill_rect(cx + 6, cy + 8, 2, 1, COL_YELLOW);
            vid_fill_rect(cx + 10, cy + 7, 1, 1, COL_YELLOW);
            vid_fill_rect(cx + 8, cy + 9, 1, 1, COL_BRRED);
            vid_fill_rect(cx + 1, cy + 9, 1, 1, COL_YELLOW);
            vid_fill_rect(cx + 4, cy + 10, 1, 1, COL_BRRED);
            vid_fill_rect(cx + 11, cy + 10, 1, 1, COL_YELLOW);
            vid_fill_rect(cx + 3, cy + 11, 1, 1, COL_YELLOW);
            vid_fill_rect(cx + 9, cy + 11, 1, 1, COL_BRRED);
            vid_fill_rect(cx + 13, cy + 9, 1, 1, COL_BRRED);

            /* Hold for ~1 second */
            delay(60000);
        }

        if (lives > 1) {
            lives--;
            fuel = FUEL_FULL;
            draw_hud();
            goto restart;
        } else {
            lives = 0;
            vid_fill_rect(60, 100, 136, 24, COL_BLACK);
            draw_centred(108, "GAME OVER", COL_BRRED);
            delay(60000);
            delay(60000);
            delay(60000);
            goto game_over;
        }
    }

game_over:
    /* Reset scroll before returning to title */
    scroll_set(0);
}

/* ── Entry point ── */
int main(void)
{
    vid_init();
    input_init();

    while (1) {
        if (!title_screen())
            break;          /* Q on title → quit to OS */
        game_loop();        /* Q in game → back to title */
    }

    vid_shutdown();
    input_shutdown();

    return 0;
}
