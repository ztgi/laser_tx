#ifndef LASER_BRAM_H
#define LASER_BRAM_H

#include <stdint.h>

typedef struct {
    uint32_t seed;
    uint32_t repeat_cycles;
    uint8_t gap_len_bits;
    uint16_t insert_after;
    uint8_t prbs_order;
    uint8_t phase_shift_en;
    uint8_t loop_en;
    uint32_t pattern_low;
    uint32_t pattern_mid;
    uint32_t pattern_high;
    uint32_t pattern_top;
} LaserConfig;

int laser_bram_write_config(uint8_t index, const LaserConfig *config);
int laser_bram_verify_config(uint8_t index, const LaserConfig *config);
uint32_t laser_bram_read_word(uint8_t index, uint32_t word_index);

#endif
