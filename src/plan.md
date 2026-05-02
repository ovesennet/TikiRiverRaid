# TIKI-100 River Raid-Style Game Implementation Plan

## 1. Goal

Implement a River Raid-inspired vertical scrolling shooter for the TIKI-100 computer using:

- C for main game logic
- Z80 assembly for performance-critical rendering, scrolling, sprite drawing, input, and sound routines
- Procedural river generation rather than storing full level maps

The main technical risk is smooth vertical scrolling on TIKI-100 hardware. The first milestone should therefore be a scrolling prototype, not the complete game.

---

## 2. Target Game Structure

The game should have these main screens:

1. Start/logo screen
2. Game initialization
3. Main gameplay loop
4. Bridge/section transition
5. Crash/death handling
6. Game over screen
7. High score or restart screen, if time allows

---

## 3. Start / Logo Screen

### Purpose

The start screen should establish the game identity and give the player a moment before gameplay starts.

### Suggested Contents

- Game logo/title, for example:

```text
TIKI RIVER RAID
```

or a different title if you want to avoid using the original name directly.

- Simple river graphic in the background
- Player plane sprite shown near the bottom
- Text:

```text
PRESS FIRE TO START (space key)
```

- Optional:

```text
C 2026 ARCTIC RETRO
```

### Implementation Notes

The logo screen can use a static bitmap or character/tile graphics. It does not need scrolling.

Recommended approach:

- Draw static logo using C or precomputed screen data
- Use assembly routine to clear screen quickly
- Poll joystick/keyboard/fire button
- When fire is pressed, initialize game state and switch to gameplay

### Logo Screen Tasks

- [ ] Define title graphics
- [ ] Define start screen layout
- [ ] Implement `ClearScreenAsm()`
- [ ] Implement `DrawLogoScreen()`
- [ ] Implement `WaitForStartInput()`
- [ ] Transition to game initialization

---

## 4. Core Game Concept

The player controls a jet/plane flying upward along a river.

The screen scrolls vertically downward, making it appear that the plane is moving north/upstream.

The player must:

- Avoid river banks
- Avoid or shoot enemies
- Destroy bridges
- Collect fuel from fuel tanks
- Avoid running out of fuel

---

## 5. Level / River Data Representation

The Atari 2600 game does not use traditional hand-authored full levels. It uses a deterministic pseudo-random generation system.

For the TIKI-100 version, use a similar concept:

```text
fixed RNG seed + section generator + river shape table + object generator
```

This avoids storing a large vertical map in memory.

---

## 6. River Sections

Represent the river as sections.

Recommended structure:

- One section = 16 river blocks
- One block = 32 vertical pixels / scanlines, or another height suitable for the TIKI display mode
- The last block in a section contains a bridge
- The other 15 blocks contain river geometry and optional objects

Example:

```c
#define BLOCKS_PER_SECTION 16
#define RIVER_BLOCK_HEIGHT 32

typedef struct
{
    uint8_t riverShapeId;
    uint8_t flags;
    uint8_t objectType;
    uint8_t objectX;
    int8_t  objectDx;
} RiverBlockData;

typedef struct
{
    RiverBlockData blocks[BLOCKS_PER_SECTION];
} RiverSection;
```

---

## 7. River Shape Representation

Do not store the river as pixels. Store compact shape IDs.

Each block should refer to a river shape table.

Example:

```c
typedef struct
{
    uint8_t leftBankTop;
    uint8_t rightBankTop;
    uint8_t leftBankBottom;
    uint8_t rightBankBottom;
    uint8_t islandLeftTop;
    uint8_t islandRightTop;
    uint8_t islandLeftBottom;
    uint8_t islandRightBottom;
} RiverShape;
```

A block can then interpolate or step the bank positions from top to bottom.

Simpler version:

```c
typedef struct
{
    uint8_t leftBank;
    uint8_t rightBank;
    uint8_t islandLeft;
    uint8_t islandRight;
} RiverShapeSimple;
```

Start with the simple version. Add sloped banks later if performance allows.

---

## 8. River Block Runtime Representation

A generated block can be expanded into a runtime format before it enters the visible screen buffer.

```c
typedef struct
{
    uint8_t leftBank;
    uint8_t rightBank;
    uint8_t islandLeft;
    uint8_t islandRight;
    uint8_t flags;
    uint8_t objectType;
    uint8_t objectX;
    int8_t  objectDx;
} RiverBlock;
```

Flags:

```c
#define RIVER_FLAG_NONE    0x00
#define RIVER_FLAG_ISLAND  0x01
#define RIVER_FLAG_BRIDGE  0x02
#define RIVER_FLAG_NARROW  0x04
```

Object types:

```c
#define OBJ_NONE       0
#define OBJ_FUEL       1
#define OBJ_SHIP       2
#define OBJ_HELICOPTER 3
#define OBJ_PLANE      4
#define OBJ_HOUSE      5
#define OBJ_BRIDGE     6
```

---

## 9. Rolling River Buffer

Do not keep a full level in memory.

Use a rolling buffer of blocks covering the visible screen plus some extra margin.

Example:

```c
#define VISIBLE_BLOCKS 8
#define EXTRA_BLOCKS   2
#define RIVER_BUFFER_BLOCKS (VISIBLE_BLOCKS + EXTRA_BLOCKS)

RiverBlock m_riverBuffer[RIVER_BUFFER_BLOCKS];
```

When a block scrolls off the bottom:

1. Remove/reuse the oldest block
2. Generate one new block at the top
3. Update buffer index

This keeps memory use small and predictable.

---

## 10. RNG and Procedural Generation

Use a deterministic 16-bit RNG.

Initial seed can be fixed, for example:

```c
uint16_t m_rngState = 0xA814;
```

The original Atari version is known to use fixed seed behavior, so this gives repeatable levels.

Example simple RNG:

```c
uint16_t NextRandom16(uint16_t state)
{
    uint8_t lsb = state & 1;
    state >>= 1;

    if (lsb)
        state ^= 0xB400;

    return state;
}

uint8_t NextRandomByte(void)
{
    m_rngState = NextRandom16(m_rngState);
    return (uint8_t)(m_rngState & 0xff);
}
```

This does not need to be bit-exact to the Atari game unless the goal is an exact clone.

---

## 11. River Generation Rules

### Basic Rules

For each section:

- Blocks 0 to 14: river geometry and possible objects
- Block 15: bridge

For each non-bridge block:

- Pick a river shape ID
- Decide whether an island exists
- Pick an object type, or no object
- Pick object X position inside the river

### Difficulty Progression

As the game progresses:

- River gets narrower
- More islands appear
- Enemy probability increases
- Fuel probability decreases slightly
- Enemy movement speed increases
- Bullet speed can remain constant
- Player speed can remain constant or increase after bridges

Suggested difficulty variables:

```c
typedef struct
{
    uint8_t sectionNumber;
    uint8_t minRiverWidth;
    uint8_t enemyProbability;
    uint8_t fuelProbability;
    uint8_t islandProbability;
    uint8_t enemySpeed;
    uint8_t scrollSpeed;
} DifficultyState;
```

---

## 12. Vertical Scrolling Strategy

This is the most important technical risk.

The TIKI-100 version should not start by implementing enemies or fuel. First prove that vertical scrolling can work at acceptable speed.

### Possible Scrolling Approaches

#### Approach A: Full Screen Memory Shift

Each frame:

1. Move most of screen memory down by 1 or more pixel rows
2. Draw new row at the top
3. Draw player and objects

Pros:

- Simple conceptually
- Easy to test

Cons:

- May be too slow if the video memory area is large
- Requires optimized Z80 block copy
- May cause visible tearing/flicker

Assembly routine idea:

```asm
; Scroll screen down by one character/pixel row depending on video mode
; Copy screen memory from bottom toward top to avoid overwrite
ScrollDownAsm:
    ; HL = source end
    ; DE = destination end
    ; BC = byte count
    ; LDDR
    ret
```

#### Approach B: Character/Tiled Vertical Scroll

Use character rows or tile rows rather than pixel rows.

Each scroll step:

1. Shift tile rows down
2. Draw one new tile row at the top

Pros:

- Much faster
- Better suited to limited hardware
- Easier collision detection

Cons:

- Less smooth if only scrolling in 8-pixel increments
- Can look more blocky

This may be the best first version.

#### Approach C: Virtual Ring Buffer / Start Address Trick

If the TIKI-100 video hardware supports changing display start address or row offset, use a ring buffer.

Each frame:

1. Change the visible start row
2. Draw newly exposed row into hidden part of video memory
3. Wrap around when needed

Pros:

- Very fast
- Smoothest if hardware supports it

Cons:

- Depends on video hardware capability
- More complex
- May not be possible on TIKI-100

This should be investigated, but not assumed.

#### Approach D: Redraw Whole Playfield Each Frame

Each frame:

1. Clear playfield area
2. Draw river from rolling block buffer at current scroll offset
3. Draw objects and player

Pros:

- Very clean logic
- No destructive scrolling bugs

Cons:

- Likely too slow unless graphics are simple
- May flicker without double buffering

This is useful for debugging, but probably not the final approach.

---

## 13. Recommended Scrolling Plan

### Phase 1: Character-Row Scrolling Prototype

Start with tile/character-row scrolling.

Target:

- Scroll river downward by one character row at a time
- Generate a new row at the top
- Keep player fixed near bottom
- No objects yet
- No bullets yet

Reason:

This proves the game structure with the least rendering cost.

Tasks:

- [ ] Choose video mode
- [ ] Define playfield width
- [ ] Define river character/tile symbols
- [ ] Implement `ScrollPlayfieldDownOneRowAsm()`
- [ ] Implement `DrawRiverRowTopAsm()` or C equivalent
- [ ] Generate river rows from `RiverBlock`
- [ ] Keep frame timing stable

### Phase 2: Pixel-Row or Sub-Character Smoothness

If character-row scrolling works but feels too coarse:

Options:

1. Scroll every N frames to slow it down
2. Use 2-pixel or 4-pixel high tiles
3. Add animation frames to water to fake smoother motion
4. Investigate pixel-level copying if memory bandwidth allows it

### Phase 3: Optimized Assembly Scrolling

If full screen memory shift is required, write highly optimized Z80 assembly.

Possible strategy:

- Scroll only the game playfield, not the whole screen
- Keep score/fuel panel in a separate fixed area
- Copy from bottom to top using `LDDR`
- Use unrolled loops for fixed-width rows if faster

Recommended screen layout:

```text
+-----------------------------+
| SCORE   FUEL   BRIDGE       |  fixed HUD
+-----------------------------+
|                             |
|        scrolling river      |
|                             |
|                             |
|            player           |
+-----------------------------+
```

Only the scrolling river area should be moved.

---

## 14. Playfield Layout

Suggested coordinate system:

```text
x = 0..159 or suitable TIKI graphics width
y = 0..gameAreaHeight-1
```

Keep a fixed HUD at the top or side.

Suggested layout:

```c
#define SCREEN_WIDTH        160
#define SCREEN_HEIGHT       200
#define HUD_HEIGHT          16
#define PLAYFIELD_TOP       HUD_HEIGHT
#define PLAYFIELD_HEIGHT    (SCREEN_HEIGHT - HUD_HEIGHT)
#define PLAYER_Y            (SCREEN_HEIGHT - 32)
```

Adjust these values to the selected TIKI display mode.

---

## 15. River Row Generation

Generate rows from the current river block.

Simple row generator:

```c
void GenerateRiverRow(uint8_t yInBlock, RiverBlock *block, uint8_t *rowBuffer)
{
    for (uint8_t x = 0; x < SCREEN_WIDTH; x++)
    {
        if (x < block->leftBank || x > block->rightBank)
            rowBuffer[x] = TILE_LAND;
        else if (block->flags & RIVER_FLAG_ISLAND &&
                 x >= block->islandLeft && x <= block->islandRight)
            rowBuffer[x] = TILE_LAND;
        else
            rowBuffer[x] = TILE_WATER;
    }
}
```

For tile mode, generate tile columns instead of pixels.

---

## 16. Player Plane

The player plane should remain near the bottom of the screen.

Controls:

- Left/right: horizontal movement
- Up/down: speed change or vertical movement, optional
- Fire: shoot missile/bullet

Suggested player state:

```c
typedef struct
{
    uint8_t x;
    uint8_t y;
    uint8_t speed;
    uint8_t alive;
    uint8_t fireCooldown;
} PlayerState;
```

---

## 17. Collision Detection

Use simple bounding boxes first.

Collision types:

- Player vs land/river bank
- Player vs island
- Player vs enemy
- Bullet vs enemy
- Bullet vs bridge
- Player vs fuel tank

For river collision, sample a few points on the player sprite:

```c
uint8_t IsPlayerOverLand(PlayerState *player)
{
    if (IsLandPixel(player->x, player->y)) return 1;
    if (IsLandPixel(player->x - 4, player->y + 4)) return 1;
    if (IsLandPixel(player->x + 4, player->y + 4)) return 1;
    return 0;
}
```

With tile graphics, sample tile cells instead of pixels.

---

## 18. Objects and Enemies

Start with static objects. Add moving enemies later.

Object state:

```c
#define MAX_OBJECTS 12

typedef struct
{
    uint8_t active;
    uint8_t type;
    uint8_t x;
    uint8_t y;
    int8_t  dx;
    uint8_t flags;
} GameObject;

GameObject m_objects[MAX_OBJECTS];
```

Objects enter from the top as river blocks are generated.

Each frame:

1. Move objects downward with scroll
2. Apply horizontal movement for ships/helicopters/planes
3. Remove objects when off-screen
4. Draw active objects

---

## 19. Bullets / Missiles

Keep bullets simple.

```c
#define MAX_BULLETS 2

typedef struct
{
    uint8_t active;
    uint8_t x;
    uint8_t y;
} Bullet;
```

Each frame:

- Bullet moves upward
- If bullet hits enemy, destroy enemy
- If bullet hits bridge, destroy bridge and advance section
- If bullet exits screen, deactivate

---

## 20. Fuel System

Fuel should continuously decrease.

Suggested state:

```c
uint16_t m_fuel;
```

Each frame or tick:

- Reduce fuel
- If player overlaps fuel tank, increase fuel
- If player shoots fuel tank, destroy it and do not refuel
- If fuel reaches zero, player dies

---

## 21. Bridge Rules

Every section ends with a bridge.

Rules:

- Bridge appears in block 15
- Player must shoot bridge to continue
- If player collides with bridge, player dies
- Destroying bridge gives score and increases difficulty
- After bridge destruction, next section continues

Implementation:

```c
void OnBridgeDestroyed(void)
{
    m_score += 500;
    m_difficulty.sectionNumber++;
    IncreaseDifficulty();
}
```

---

## 22. Rendering Architecture

Separate static scrolling background from dynamic sprites.

Recommended order per frame:

1. Wait for safe display period if possible
2. Scroll playfield or update ring buffer
3. Draw newly exposed river row/tile row at top
4. Erase old sprite positions
5. Update game objects
6. Draw objects
7. Draw bullets
8. Draw player
9. Update HUD if needed

Important:

- Avoid redrawing HUD every frame
- Avoid full screen clears during gameplay
- Track old sprite positions so they can be erased cheaply

---

## 23. C and Assembly Split

### C Code Responsibilities

- Game state
- Level generation
- Object spawning
- Difficulty progression
- Collision logic
- Scoring
- Fuel logic
- High-level game loop

### Z80 Assembly Responsibilities

- Screen clear
- Playfield scroll
- Draw row/tile row
- Draw sprites
- Erase sprites
- Joystick/keyboard polling if needed
- Sound effects if needed

Suggested files:

```text
src/
  main.c
  game.c
  game.h
  river.c
  river.h
  objects.c
  objects.h
  player.c
  player.h
  render.c
  render.h
  input.c
  input.h
  asm/
    screen.asm
    scroll.asm
    sprites.asm
    input.asm
    sound.asm
```

---

## 24. First Scrolling Prototype

This should be built before the actual game.

### Prototype Goal

Display an endlessly scrolling river with random banks.

No player, no bullets, no enemies.

### Requirements

- Fixed HUD or blank top area
- Scrolling playfield
- Generated river rows
- Stable speed
- No visible corruption

### Success Criteria

- River scrolls continuously
- No flicker that makes gameplay impossible
- CPU has enough time left for player and object logic
- Scrolling speed can be adjusted

### Test Variants

1. Character-row scroll
2. Pixel-row memory copy, if possible
3. Redraw-only version for comparison
4. Ring-buffer version if hardware supports it

---

## 25. Minimal Vertical Scroll Test Code Shape

Pseudo-code:

```c
void TestScrollingRiver(void)
{
    InitVideoMode();
    ClearScreenAsm();
    InitRiverGenerator(0xA814);
    FillInitialRiverBuffer();

    while (1)
    {
        WaitFrame();

        ScrollPlayfieldDownOneRowAsm();

        GenerateNextRiverRow(m_topRowBuffer);
        DrawTopRiverRowAsm(m_topRowBuffer);

        if (InputPressedExit())
            break;
    }
}
```

This test should become the base of the final gameplay renderer.

---

## 26. Sprite Drawing Strategy

The game will need sprites over the scrolling background.

Recommended simple method:

1. Before drawing a sprite, save the background under it
2. Draw sprite with mask
3. Next frame, restore saved background
4. Move sprite
5. Save new background
6. Draw again

Sprite structure:

```c
typedef struct
{
    uint8_t width;
    uint8_t height;
    const uint8_t *mask;
    const uint8_t *pixels;
} SpriteDef;
```

Runtime sprite state:

```c
typedef struct
{
    uint8_t x;
    uint8_t y;
    uint8_t oldX;
    uint8_t oldY;
    uint8_t visible;
    const SpriteDef *sprite;
    uint8_t background[SPRITE_BG_MAX_SIZE];
} SpriteInstance;
```

If background save/restore is too expensive, redraw a small tile rectangle behind each sprite instead.

---

## 27. Graphics Style

For TIKI-100 hardware, prioritize readability over detail.

Recommended style:

- Solid water area
- Solid land area
- Simple high-contrast plane sprite
- Small but readable fuel tank
- Bridges as horizontal bars across river
- Simple enemies: ship, helicopter, plane

Animation can be minimal:

- Water animation by alternating characters/tiles
- Enemy 2-frame animation
- Explosion 3-frame animation

---

## 28. Performance Budget

Frame cost priorities:

1. Scrolling
2. Sprite erase/draw
3. Collision detection
4. Object movement
5. HUD update
6. Sound

Rules:

- Do not update score text every frame unless changed
- Do not redraw fuel bar every frame unless value changed enough
- Keep object count low
- Use lookup tables for river shape and collision
- Avoid multiplication/division in the game loop
- Prefer fixed-point or integer counters

---

## 29. Development Milestones

### Milestone 1: Logo Screen

- [ ] Clear screen
- [ ] Draw title/logo
- [ ] Poll input
- [ ] Start game on fire/key

### Milestone 2: Scrolling River Prototype

- [ ] Choose video mode
- [ ] Implement row/tile scroll
- [ ] Generate river rows
- [ ] Display continuous scrolling river
- [ ] Measure whether speed is acceptable

### Milestone 3: Player Plane

- [ ] Draw player sprite
- [ ] Move left/right
- [ ] Clamp movement to screen
- [ ] Detect collision with land

### Milestone 4: Fuel and HUD

- [ ] Add fuel counter
- [ ] Draw HUD
- [ ] Add fuel tank object
- [ ] Refuel on contact

### Milestone 5: Bullets

- [ ] Fire bullet
- [ ] Move bullet upward
- [ ] Remove bullet off-screen
- [ ] Bullet-object collision

### Milestone 6: Bridge Sections

- [ ] Generate bridge every 16 blocks
- [ ] Require shooting bridge
- [ ] Advance section
- [ ] Increase difficulty

### Milestone 7: Enemies

- [ ] Add ships
- [ ] Add helicopters
- [ ] Add planes
- [ ] Add movement patterns
- [ ] Add collisions

### Milestone 8: Game Polish

- [ ] Explosions
- [ ] Sound effects
- [ ] Score balancing
- [ ] Game over screen
- [ ] Optional high score

---

## 30. Main Technical Questions to Answer Early

These must be tested before spending much time on the full game:

1. Which TIKI-100 video mode is best?
2. Is pixel-level vertical scrolling fast enough?
3. Is character/tile-row scrolling acceptable visually?
4. Can the display start address be changed for a ring-buffer scroll?
5. How much CPU time remains after scrolling?
6. How expensive is masked sprite drawing?
7. Can the playfield be narrower than the full screen to reduce copy cost?

---

## 31. Recommended Initial Decision

Start with character/tile-row scrolling.

Reason:

- It is much more likely to work on Z80 hardware
- It keeps memory bandwidth manageable
- It lets the game logic be built early
- It can later be improved with smaller tile heights or pixel scrolling

The first playable version should not require perfect smooth scrolling. A fast, stable scrolling river with good controls is more important.

---

## 32. Minimal Game Loop

```c
void GameLoop(void)
{
    while (m_gameRunning)
    {
        WaitFrame();

        ReadInput();
        UpdatePlayer();
        UpdateBullets();
        UpdateObjects();
        UpdateFuel();

        ScrollPlayfield();
        GenerateAndDrawNewRiverRowsIfNeeded();

        CheckCollisions();

        EraseOldSprites();
        DrawObjects();
        DrawBullets();
        DrawPlayer();

        UpdateHudIfNeeded();
    }
}
```

If sprite flicker occurs, try this order instead:

```c
void GameLoopAlternative(void)
{
    while (m_gameRunning)
    {
        WaitFrame();

        EraseOldSprites();
        ScrollPlayfield();
        GenerateAndDrawNewRiverRowsIfNeeded();

        ReadInput();
        UpdatePlayer();
        UpdateBullets();
        UpdateObjects();
        UpdateFuel();
        CheckCollisions();

        DrawObjects();
        DrawBullets();
        DrawPlayer();
        UpdateHudIfNeeded();
    }
}
```

The correct ordering depends on the final sprite erase strategy.

---

## 33. Suggested Data Files

```text
data/
  river_shapes.c
  sprites.c
  logo.c
  font.c
```

`river_shapes.c` should contain predefined shape templates.

Example:

```c
const RiverShapeSimple g_riverShapes[] =
{
    { 32, 128, 0, 0 },
    { 28, 124, 0, 0 },
    { 36, 132, 0, 0 },
    { 24, 116, 64, 80 },
    { 40, 136, 72, 88 }
};
```

---

## 34. Suggested First Week Plan

### Day 1

- Select video mode
- Clear screen from assembly
- Draw static logo screen
- Poll start input

### Day 2

- Implement basic river row generation
- Draw static river screen

### Day 3

- Implement character/tile-row scrolling
- Generate new row at top

### Day 4

- Optimize scrolling routine
- Measure speed by visual test

### Day 5

- Add player sprite
- Move player left/right

### Day 6

- Add land collision
- Add simple crash state

### Day 7

- Add fuel counter and one fuel tank object

---

## 35. Risk List

### High Risk

- Vertical scrolling too slow
- Sprite drawing causing flicker
- Collision map not matching visual map

### Medium Risk

- Too many moving objects
- Fuel/bridge difficulty balance
- Joystick/input latency

### Low Risk

- Logo screen
- Basic RNG generation
- Static HUD
- Score handling

---

## 36. Contingency Plan if Smooth Scrolling Fails

If smooth pixel scrolling is too slow, use one of these fallbacks:

### Fallback 1: Character-Row Scroll

Scroll by 8 pixels or one character row. This is acceptable for a retro-style game.

### Fallback 2: Step Scroll with Animation

Scroll one row every few frames, but animate water to make motion feel more alive.

### Fallback 3: Smaller Playfield

Use a narrower scrolling area and keep static borders or HUD panels on the sides.

### Fallback 4: Chunk-Based Movement

Move the river in chunks of 4 or 8 pixels and make the player/enemies move smoothly relative to it.

---

## 37. Final Recommendation

Build the game from the scrolling system outward.

Recommended order:

1. Logo/start screen
2. Scrolling river prototype
3. Player movement
4. River collision
5. Fuel
6. Bullets
7. Bridges
8. Enemies
9. Polish

Do not spend much time on graphics or enemies before proving the vertical scrolling approach.

The most likely successful implementation is a tile/character-row scrolling playfield with compact procedural river generation and assembly-optimized row shifting/drawing.
