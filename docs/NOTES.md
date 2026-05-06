# TIKI RIVER RAID — Technical Notes

## Overview

Tiki River Raid is a vertical scrolling shooter inspired by Activision's River Raid,
for the **TIKI-100** computer — a Norwegian Z80-based CP/M machine from the 1980s.
Written in C and Z80 assembly using the **z88dk** toolchain (sccz80 compiler).
Outputs a CP/M .COM executable and a raw 400K disk image for the Djupdal emulator.

NOTE: The game is not bug-free, but playable. You are welcome to contribute by fixing bugs.

## Target Hardware

- **CPU:** Z80 @ 4 MHz
- **RAM:** 64 KB (shared with VRAM when banked)
- **Display:** Mode 3 — 256×256 pixels, 16 colours
- **Sound:** YM2149 / AY-3-8910 PSG — 3 tone channels, accessed via z88dk
  `set_psg()` (ports $16/$17)
- **VRAM:** 32 KB mapped at $0000–$7FFF when system register port $1C bit 3 is set
- **VRAM layout:** 128 bytes/scanline × 256 scanlines. 2 pixels per byte:
  low nibble (bits 3–0) = even pixel, high nibble (bits 7–4) = odd pixel
- **Byte address formula:** `y × 128 + x / 2`
- **Palette:** 8-bit RGB encoding — bits 7–5 = red, bits 4–2 = green, bits 1–0 = blue
- **Hardware scroll:** AY-3-8912 register 14 controls vertical scroll offset.
  Effective VRAM address = (addr + scroll_reg × 128) MOD 32768

## Toolchain

- **Compiler:** z88dk sccz80 (`zcc +cpm -subtype=tiki100_400k -compiler=sccz80`)
- **Target:** CP/M with TIKI-100 400K disk subtype (links `-ltiki100` library)
- **Startup:** `-startup=0` (minimal CRT)
- **Disk image:** `-Cz--container=raw` produces a raw .img renamed to .dsk
- **Build:** PowerShell script `build.ps1`, deploy via `deploy.ps1`

## Memory Architecture

Code is split between normal memory and **high memory** (above $8000):

- **C code and data** live in normal sections (loaded at $0100+ by CP/M)
- **Assembly routines and font data** live in `SECTION code_graphics` (above $8000)
  so they remain accessible when VRAM is banked into $0000–$7FFF
- **BSS variables** for graphics parameters live in `SECTION bss_graphics` (also high memory)
- **Keyboard scanning** lives in `SECTION code_driver`

The z88dk library provides `swapgfxbk` / `swapgfxbk1` to bank VRAM in and out.

## C ↔ Assembly Interface

C functions write parameters to global variables in `bss_graphics`, then call
assembly entry points. For example, `vid_fill_rect()` writes `gfx_x1`, `gfx_y1`,
`gfx_width`, `gfx_height`, `gfx_colour`, then calls `vid_fill_rect_gfx`.

## Source Structure

### C files (`src/c/`)

| File | Purpose |
|------|---------|
| `main.c` | Game loop, state machine, title screen, HUD, collision, scoring |
| `video.c` | Video init/shutdown, drawing primitive wrappers, scroll control |
| `input.c` | Direct keyboard matrix scanning (zero-latency held state) |
| `river.c` | Procedural river generation using Galois LFSR RNG |
| `sound.c` | PSG sound effects (engine, shoot, explode, crash, refuel) |
| `sprite.c` | Sprite spawn logic and blit preparation |

### Headers (`src/c/`)

| File | Purpose |
|------|---------|
| `defs.h` | Screen geometry, palette indices, game constants |
| `video.h` | Drawing primitive and scroll declarations |
| `input.h` | Input bitmask bits and polling API |
| `river.h` | River generator API |
| `sound.h` | Sound effects API |
| `sprite.h` | Sprite management API |

### Assembly (`src/asm/`)

| File | Purpose |
|------|---------|
| `screen.asm` | All VRAM routines: clear, hline, fill_rect, text, river line, game step, sprite blit, HUD snapshot, vsync ISR |
| `keyboard.asm` | Direct keyboard matrix scanning via port $00 |

## Graphics Routines (screen.asm)

All in `SECTION code_graphics` — accessible during VRAM banking.

| Routine | Description |
|---------|-------------|
| `vid_clear_asm` | Zero all 32K VRAM via `LDIR` |
| `vid_hline_gfx` | 3-phase horizontal line: left partial, middle fill, right partial |
| `vid_fill_rect_gfx` | Calls hline per row of rectangle |
| `vid_draw_text_gfx` | String rendering with single VRAM bank switch |
| `vid_draw_river_line_asm` | Full-width river line (land + water + land) in one bank switch |
| `vid_game_step_asm` | Combined per-step: erase plane, scroll, river line, HUD, draw plane — ONE bank switch |
| `vid_game_frame_asm` | Batched multi-step frame rendering |
| `vid_enemy_shift_asm` | Horizontal shift of enemy sprite bytes in VRAM |
| `vid_enemy_mirror_asm` | Horizontal mirror of enemy sprite (reverses bytes + swaps nibbles) |
| `scroll_set_asm` / `scroll_get_asm` | Hardware scroll register access via AY reg 14 |
| `wait_vsync_asm` | Wait for next vertical blank interrupt (~50 Hz) |
| `vsync_init_asm` | Install frame-counter ISR at CP/M interrupt hook ($F057) |
| `hud_snapshot_asm` | Copy HUD VRAM rows into RAM buffer for per-step restoration |

### Font

- 5×7 pixel glyphs (A–Z, 0–9, space, punctuation)
- Characters advance by 6px (5 + 1 spacing)
- ASCII lookup table maps to glyph indices

## Scrolling System

The core technical challenge. Uses the TIKI-100's hardware vertical scroll:

- **AY register 14** sets a vertical line offset — the display wraps around VRAM
- Each game step decrements the scroll register, then draws a new river line
  at the "incoming" VRAM row (the row that just scrolled into view at the top)
- Drawing at a screen Y always goes to the correct VRAM address because the
  assembly routines add the scroll offset to the Y coordinate
- Multiple steps are batched per vblank (default: 4 lines/frame) for speed

### Save-Under Buffer

The plane sprite uses a 150-byte save-under buffer (10 bytes wide × 15 rows)
to store the VRAM content beneath it before drawing. This allows clean erasure
without knowing the background colour at each pixel. The buffer is invalidated
on scroll register changes.

### HUD Snapshot

The HUD (bottom 12 rows) is pre-rendered to a 1536-byte RAM buffer. Each game
step copies this buffer to VRAM via LDIR, preventing scroll from corrupting
the fixed HUD area. This is faster than redrawing text/gauges every step.

## River Generation

Procedural terrain using a 16-bit Galois LFSR (polynomial $B400):

- River is always symmetric around screen centre (x=128)
- Width varies between 26px (10%) and 230px (90%) of screen
- Segments of 120–375 lines before picking a new target width
- Width changes at 4px per line towards the target (steep banks)
- Bank edges are stored in a 256-entry ring buffer indexed by VRAM row
  for per-step collision checking

## Sprite System

Sprites are drawn row-by-row into the scrolling river as it generates,
effectively "printing" them into the terrain one scanline at a time:

- **Fuel barrels** — 14×24px, drawn as the river scrolls past
- **Helicopters** — 16×10px, bounce horizontally between banks
- **Boats** — 32×8px, bounce horizontally between banks
- **Jets** — 16×6px, fly straight across the river

The `vid_set_blit()` / `vid_set_blit_type()` calls configure which sprite
row to draw on the next game step. The ASM routine embeds the sprite data
directly and selects the correct row from pre-stored pixel patterns.

Enemy sprites are shifted horizontally in VRAM using `vid_enemy_shift`
(byte-level LDIR/LDDR) and mirrored with `vid_enemy_mirror` (nibble swap).

## Collision Detection

Three collision types, checked every scroll step for instant response:

1. **River bank** — plane edges vs stored bank_l[]/bank_r[] at plane Y
2. **Enemy** — bounding box overlap between plane and current enemy
3. **Fuel barrel** — bounding box overlap for pickup (adds fuel, score)

Rocket-vs-enemy and rocket-vs-fuel are also checked per frame.

## Game Rules

- **Fuel:** Starts at 1500 (full), depletes 1 per frame (~30s to empty).
  Fuel barrels restore 450 (30% of full).
- **Lives:** 3 lives. On crash, respawn with full fuel at river centre.
- **Scoring:** Fuel pickup = 100 pts, enemy destroyed = 200 pts,
  fuel barrel destroyed = 80 pts
- **Enemies:** Helicopters and boats bounce between river banks;
  jets fly straight across and despawn at the far bank
- **Enemy movement:** Disabled for first ~4 seconds (200 frames) to give
  the player time to orient
- **Invulnerability:** Brief flash period after crash (hit_flash countdown)

## Input

- **Direct hardware scanning** via port $00 — no BIOS, no buffering
- Keyboard matrix: 8 rows × 12 columns, read sequentially per column
- Returns bitmask: bit0=left(A), bit1=right(D), bit2=fire(space),
  bit3=quit(Q), bit4=pause(P), bit7=any
- `input_poll()` called once per frame; `input_held()` / `input_pressed()`
  provide held state and rising-edge detection

## Sound

Sound uses the YM2149 / AY-3-8910 PSG chip, accessed via `set_psg()`.

**Critical constraint:** AY register 7 bit 6 must remain 1 (Port A output
direction) because Port A is used for the hardware scroll register.
All mixer updates preserve this bit via `R7_BASE = 0x7F`.

### Channel Allocation

| Channel | Usage |
|---------|-------|
| **A** | Engine noise (continuous rumble, noise period 14) |
| **B** | SFX tones (shoot sweep, explosion, crash, refuel chirp) |
| **C** | SFX noise (explosion/crash noise component) |

### Sound Effects

| Effect | Type | Frames | Description |
|--------|------|--------|-------------|
| Engine | Noise on A | Continuous | Mid-low rumble (period 14), volume 7 |
| Shoot | Tone B + Noise C | 5 | Rapid descending sweep (10→700), laser zap |
| Explode | Tone B + Noise C | 8 | Low boom, ascending noise period (4→28) |
| Crash | Tone B + Noise C | 15 | Big explosion, long decay, heavy noise |
| Refuel | Tone B only | 6 | Ascending chirp (600→30), pure tone |

`snd_update()` is called once per frame to advance envelope timers and
update PSG registers with pre-computed per-frame period/volume tables.

## Performance Considerations

- **Hardware scroll** — no pixel copying for vertical movement; the entire
  screen scrolls by changing one AY register
- **Single bank switch per step** — `vid_game_step_asm` does river line +
  sprite blit + plane draw + HUD restore in one VRAM banking cycle
- **Save-under** — plane erasure uses buffered restore instead of full
  background redraw
- **HUD in RAM** — pre-rendered to buffer, LDIR'd to VRAM (no text/rect calls)
- **Batched steps** — 4 scroll lines per vblank reduces overhead
- **No sprintf/printf** — custom `uint16_to_str` avoids pulling in heavy library
- **Ring buffer bank edges** — O(1) lookup for collision detection per step
- **VRAM sprite shift** — `LDIR`/`LDDR` to move enemy pixels instead of
  erase-and-redraw
- **Row-by-row sprite printing** — sprites drawn incrementally as terrain
  scrolls, avoiding full-sprite draw calls

## Title Screen

- Static river background drawn using the procedural generator (seed $1234)
- Black overlay box with centred text: title, subtitle, copyright
- Instructions panel: "PRESS SPACE TO START", "Q TO QUIT"
- Waits for space (start game) or Q (quit to OS)

## Game Screen Layout

- **Playfield:** Full 256px wide scrolling river (y=0 to y=242)
- **HUD separator:** Black line at y=243
- **HUD area (y=244–255):** Fuel gauge (E/F bar), score, lives counter
- **Plane:** Fixed at y=219, moves horizontally with A/D

## Build & Deploy

```
.\build.ps1              # Build tikirr.com + tikirr.dsk
.\build.ps1 -Clean       # Clean first
.\deploy.ps1             # Build, copy to work.dsk, launch emulator
```

The deploy script uses a custom CP/M disk image writer in PowerShell — it
reads the base disk, finds free directory slots and blocks, writes the .COM
file data, and saves the modified image. No external CP/M disk tools needed.

