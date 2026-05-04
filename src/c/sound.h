/* TIKI RIVER RAID — sound.h */

#ifndef SOUND_H
#define SOUND_H

#include <stdint.h>

void sound_init(void);
void sound_off(void);
void snd_engine_on(void);
void snd_engine_off(void);
void snd_shoot(void);
void snd_explode(void);
void snd_crash(void);
void snd_refuel(void);
void snd_update(void);

#endif
