/* TIKI RIVER RAID — defs.h
 * Shared definitions, types, and constants.
 */

#ifndef DEFS_H
#define DEFS_H

#include <stdint.h>

/* ── Screen: 256x256 mode 3 (16 colours, 128 bytes/scanline) ── */
#define SCREEN_W       256
#define SCREEN_H       256

/* ── Palette indices (CGA-like 16 colours) ─────────────────── */
#define COL_BLACK      0
#define COL_BLUE       1
#define COL_GREEN      2
#define COL_CYAN       3
#define COL_RED        4
#define COL_MAGENTA    5
#define COL_ORANGE     6
#define COL_LTGREY     7
#define COL_DKGREY     8
#define COL_BRBLUE     9
#define COL_BRGREEN    10
#define COL_BRCYAN     11
#define COL_BRRED      12
#define COL_PINK       13
#define COL_YELLOW     14
#define COL_WHITE      15

/* ── Game states ───────────────────────────────────────────── */
#define STATE_TITLE    0
#define STATE_PLAY     1

/* ── River parameters ──────────────────────────────────────── */
#define RIVER_INIT_WIDTH    128
#define RIVER_MIN_WIDTH     26      /* ~10% of 256 */
#define RIVER_MAX_WIDTH     230     /* ~90% of 256 */
#define RIVER_INIT_CENTER   128
#define RNG_SEED            0xA814

/* Default scroll speed: lines to scroll per frame (variable at runtime) */
#define SCROLL_SPEED_DEFAULT  4

/* ── River colours ─────────────────────────────────────────── */
#define LAND_COLOUR    COL_GREEN
#define WATER_COLOUR   COL_BLUE

/* ── HUD / score area at bottom ────────────────────────────── */
#define HUD_TOP         244
#define HUD_HEIGHT      12     /* Y=244 to Y=255 */
#define HUD_SEP_Y       243    /* black separator line */
#define HUD_COLOUR      COL_BLACK

/* ── Player plane ──────────────────────────────────────────── */
#define PLANE_W         12
#define PLANE_H         12
#define PLANE_Y         219    /* HUD_SEP_Y - 12 - PLANE_H */
#define PLANE_START_X   122    /* (SCREEN_W - PLANE_W) / 2 */

/* Plane sprite poses */
#define POSE_FWD        0
#define POSE_LEFT       1
#define POSE_RIGHT      2

#endif /* DEFS_H */
