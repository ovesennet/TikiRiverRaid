/* TIKI RIVER RAID — river.h
 * Procedural river generation.
 */

#ifndef RIVER_H
#define RIVER_H

#include <stdint.h>

/* Initialise the river generator with a seed */
void river_init(uint16_t seed);

/* Generate the next river scanline (returns left/right bank x positions) */
void river_generate_line(uint8_t *left, uint8_t *right);

#endif /* RIVER_H */
