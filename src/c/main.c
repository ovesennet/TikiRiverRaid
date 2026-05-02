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
static uint8_t fuel_level;     /* 0..32: fuel gauge width in pixels */

/* Forward declaration */
static void draw_centred(uint16_t y, const char *str, uint8_t colour);

#define FUEL_MAX       32      /* full gauge width in pixels */
#define FUEL_GAUGE_X   98      /* gauge bar left edge */
#define FUEL_GAUGE_Y   243     /* gauge bar top */
#define FUEL_GAUGE_H   5       /* gauge bar height */

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

/* ── HUD drawing (full, for initial draw) ── */
static void draw_hud(void)
{
    vid_hline(0, 255, HUD_SEP_Y, COL_BLACK);
    vid_fill_rect(0, HUD_TOP, 128, HUD_HEIGHT, HUD_COLOUR);
    vid_fill_rect(128, HUD_TOP, 128, HUD_HEIGHT, HUD_COLOUR);

    /* Score */
    uint16_to_str(score, score_buf);
    draw_centred(HUD_TOP + 1, score_buf, COL_YELLOW);

    /* Fuel gauge frame: "E" [bar area] "F" */
    vid_draw_text(FUEL_GAUGE_X - 12, FUEL_GAUGE_Y - 1, "E", COL_WHITE);
    vid_draw_text(FUEL_GAUGE_X + FUEL_MAX + 4, FUEL_GAUGE_Y - 1, "F", COL_WHITE);
    /* Gauge outline (1px border) */
    vid_hline(FUEL_GAUGE_X - 1, FUEL_GAUGE_X + FUEL_MAX, FUEL_GAUGE_Y - 1, COL_WHITE);
    vid_hline(FUEL_GAUGE_X - 1, FUEL_GAUGE_X + FUEL_MAX, FUEL_GAUGE_Y + FUEL_GAUGE_H, COL_WHITE);
    vid_fill_rect(FUEL_GAUGE_X - 1, FUEL_GAUGE_Y, 1, FUEL_GAUGE_H, COL_WHITE);
    vid_fill_rect(FUEL_GAUGE_X + FUEL_MAX, FUEL_GAUGE_Y, 1, FUEL_GAUGE_H, COL_WHITE);
    /* Fill gauge */
    if (fuel_level > 0)
        vid_fill_rect(FUEL_GAUGE_X, FUEL_GAUGE_Y, fuel_level, FUEL_GAUGE_H, COL_BRGREEN);

    /* ACTIVISION logo text */
    draw_centred(HUD_TOP + HUD_HEIGHT - 7, "ACTIVISION", COL_BRBLUE);
}

/* ── Update score display (call when score changes) ── */
static void update_score(void)
{
    uint16_to_str(score, score_buf);
    /* Clear score area and redraw */
    vid_fill_rect(80, HUD_TOP + 1, 96, 7, HUD_COLOUR);
    draw_centred(HUD_TOP + 1, score_buf, COL_YELLOW);
}

/* ── Update fuel gauge bar (call when fuel_level changes) ── */
static void update_fuel_gauge(void)
{
    /* Clear gauge interior */
    vid_fill_rect(FUEL_GAUGE_X, FUEL_GAUGE_Y, FUEL_MAX, FUEL_GAUGE_H, HUD_COLOUR);
    /* Fill to current level */
    if (fuel_level > 0)
        vid_fill_rect(FUEL_GAUGE_X, FUEL_GAUGE_Y, fuel_level, FUEL_GAUGE_H, COL_BRGREEN);
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

/* Fuel barrel — single counter approach, no state machine */
static uint8_t fuel_x;
static uint16_t fuel_step;
static uint16_t fuel_gap;
static uint8_t plane_x;
static uint8_t gl_left, gl_right;
static uint16_t gl_y;
static uint8_t gl_scroll_reg;
static uint8_t gl_keys;
static uint8_t gl_input_ctr;

#define MOVE_SPEED 3

static void game_loop(void)
{

    vid_clear();
    scroll_set(0);
    scroll_speed = SCROLL_SPEED_DEFAULT;
    plane_x = PLANE_START_X;
    sav_valid = 0;
    score = 0;
    fuel_level = FUEL_MAX;

    /* Init river with game seed */
    river_init(RNG_SEED);
    fuel_step = 0;
    fuel_x = 100;
    fuel_gap = 500;

    /* Fill screen with initial river */
    for (gl_y = 0; gl_y < SCREEN_H; gl_y++) {
        river_generate_line(&gl_left, &gl_right);
        vid_draw_river_line((uint8_t)(SCREEN_H - 1 - gl_y), gl_left, gl_right);
    }

    /* Draw initial HUD — plane will be drawn by first vid_game_step */
    draw_hud();

    gl_scroll_reg = 0;
    gl_keys = 0;
    gl_input_ctr = 0;

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

            /* Fuel barrel */
            if (fuel_step < FUEL_H) {
                vid_set_blit(1, fuel_x, (uint8_t)fuel_step);
            } else {
                vid_set_blit(0, 0, 0);
            }

            /* Draw plane only on last step (after all scrolls) */
            if (gl_input_ctr + 1 == scroll_speed) {
                gs_do_plane = 1;
            } else {
                gs_do_plane = 0;
            }

            vid_game_step(gl_scroll_reg, 0, gl_left, gl_right, plane_x, PLANE_Y, COL_YELLOW);

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
        }

        /* Score: +10 per batch */
        score += 10;

        /* Fuel: slowly deplete */
        if (fuel_level > 0)
            fuel_level--;

        /* Redraw full HUD (scroll shifts it every step) */
        draw_hud();
    }

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
