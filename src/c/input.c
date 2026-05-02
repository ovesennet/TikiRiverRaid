/* TIKI RIVER RAID — input.c
 * Direct keyboard matrix scanning.
 * Reads hardware state every frame — true held detection,
 * instant response, instant release. No BIOS, no buffering.
 */

#include "input.h"

extern uint8_t kbd_scan(void);
extern void kbd_init(void);
extern void kbd_shutdown(void);

static uint8_t s_cur;      /* current frame bitmask */
static uint8_t s_prev;     /* previous frame bitmask */

void input_init(void)
{
    kbd_init();
    s_cur = 0;
    s_prev = 0;
}

void input_shutdown(void)
{
    kbd_shutdown();
}

void input_flush(void)
{
    s_cur = 0;
    s_prev = 0;
}

void input_poll(void)
{
    s_prev = s_cur;
    s_cur = kbd_scan();
}

uint8_t input_held(uint8_t bit)
{
    return (s_cur & bit) ? 1 : 0;
}

uint8_t input_pressed(uint8_t bit)
{
    return ((s_cur & bit) && !(s_prev & bit)) ? 1 : 0;
}

uint8_t input_any(void)
{
    return (s_cur & KBIT_ANY) ? 1 : 0;
}
