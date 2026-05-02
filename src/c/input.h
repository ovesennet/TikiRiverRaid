/* TIKI RIVER RAID — input.h
 * Direct keyboard matrix scanning — zero latency, true held state.
 */

#ifndef INPUT_H
#define INPUT_H

#include <stdint.h>

/* Bitmask bits returned by kbd_scan() / input_poll() */
#define KBIT_LEFT   0x01    /* 'a' held */
#define KBIT_RIGHT  0x02    /* 'd' held */
#define KBIT_FIRE   0x04    /* space held */
#define KBIT_QUIT   0x08    /* 'q' held */
#define KBIT_PAUSE  0x10    /* 'p' held */
#define KBIT_ANY    0x80    /* any key held */

void input_init(void);
void input_shutdown(void);

/* Call once per frame — scans keyboard matrix */
void input_poll(void);

/* Flush state */
void input_flush(void);

/* Returns 1 if key is currently held */
uint8_t input_held(uint8_t bit);

/* Returns 1 if key was just pressed this frame (edge) */
uint8_t input_pressed(uint8_t bit);

/* Returns 1 if any key is held */
uint8_t input_any(void);

#endif /* INPUT_H */
