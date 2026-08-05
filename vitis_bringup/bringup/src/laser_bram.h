#ifndef LASER_BRAM_H
#define LASER_BRAM_H

#include <stdint.h>

#define LASER_TX_RECORD_MAGIC             0x5458U
#define LASER_TX_RECORD_FORMAT_VERSION    2U
#define LASER_TX_RECORD_WORD_COUNT        16U
#define LASER_TX_RECORD_MAX_CONFIGS       128U
#define LASER_TX_RECORD_MAX_REPEAT        16U
#define LASER_TX_RECORD_MAX_GAPS          15U
#define LASER_TX_RECORD_GAP_WIDTH         8U

typedef struct {
    /* Layout-compatible reserved fields. PL internal PRBS generation has
     * been removed; these values are serialized but ignored by hardware. */
    uint32_t seed;
    uint8_t repeat_cycles;
    uint8_t prbs_order;
    uint8_t direct_source;
    /* The original bit position remains the 63/127 configured-pattern
     * length selector. */
    uint8_t direct_len_127;
    uint8_t phase_shift_en;
    uint8_t loop_en;
    uint8_t head_delay_bits;
    uint8_t gap_len_bits[LASER_TX_RECORD_MAX_GAPS];
    uint8_t eom_enable;
    uint16_t eom_global_pattern_index;
    uint16_t eom_lead_ticks;
    uint16_t eom_trail_ticks;
    uint32_t pattern_low;
    uint32_t pattern_mid;
    uint32_t pattern_high;
    uint32_t pattern_top;
} LaserConfig;

int laser_bram_validate_config(const LaserConfig *config);
int laser_bram_write_config(uint8_t index, const LaserConfig *config);
int laser_bram_verify_config(uint8_t index, const LaserConfig *config);
uint32_t laser_bram_read_word(uint8_t index, uint32_t word_index);
uint32_t laser_bram_crc32_payload(const uint32_t words[LASER_TX_RECORD_WORD_COUNT]);

#endif
