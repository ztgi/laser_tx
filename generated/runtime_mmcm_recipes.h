#ifndef RUNTIME_MMCM_RECIPES_H
#define RUNTIME_MMCM_RECIPES_H
#include <stddef.h>
#include <stdint.h>
#define RUNTIME_MMCM_WRITE_COUNT 15U
typedef struct { uint8_t address; uint16_t value; } RuntimeMmcmWrite;
typedef struct { uint8_t mult; RuntimeMmcmWrite writes[RUNTIME_MMCM_WRITE_COUNT]; } RuntimeMmcmRecipe;
extern const RuntimeMmcmRecipe runtime_mmcm_recipes[];
extern const size_t runtime_mmcm_recipe_count;
#endif
