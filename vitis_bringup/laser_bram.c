#include "laser_bram.h"
#include <stddef.h>
#include "laser_hw.h"
#include "xil_io.h"
#include "xstatus.h"

static void laser_config_to_words(const LaserConfig *config, uint32_t words[8])
{
    words[0] = config->seed;
    words[1] = config->repeat_cycles;
    words[2] = ((uint32_t)config->insert_after << 8) |
               (uint32_t)config->gap_len_bits;
    words[3] = (uint32_t)config->prbs_order |
               ((uint32_t)(config->phase_shift_en != 0U) << 8) |
               ((uint32_t)(config->loop_en != 0U) << 9);
    words[4] = config->pattern_low;
    words[5] = config->pattern_mid;
    words[6] = config->pattern_high;
    /* Stored as 32 bits; PL deliberately ignores bit 31 for a 127-bit pattern. */
    words[7] = config->pattern_top;
}

uint32_t laser_bram_read_word(uint8_t index, uint32_t word_index)
{
    UINTPTR address = (UINTPTR)LASER_BRAM_BASEADDR +
                      ((UINTPTR)index * LASER_CONFIG_STRIDE_BYTES) +
                      ((UINTPTR)word_index * sizeof(uint32_t));
    return Xil_In32(address);
}

int laser_bram_write_config(uint8_t index, const LaserConfig *config)
{
    uint32_t words[LASER_CONFIG_WORD_COUNT];
    uint32_t i;

    if (config == NULL) {
        return XST_INVALID_PARAM;
    }

    laser_config_to_words(config, words);
    for (i = 0U; i < LASER_CONFIG_WORD_COUNT; ++i) {
        UINTPTR address = (UINTPTR)LASER_BRAM_BASEADDR +
                          ((UINTPTR)index * LASER_CONFIG_STRIDE_BYTES) +
                          ((UINTPTR)i * sizeof(uint32_t));
        Xil_Out32(address, words[i]);
    }
    return XST_SUCCESS;
}

int laser_bram_verify_config(uint8_t index, const LaserConfig *config)
{
    uint32_t expected[LASER_CONFIG_WORD_COUNT];
    uint32_t i;

    if (config == NULL) {
        return XST_INVALID_PARAM;
    }

    laser_config_to_words(config, expected);
    for (i = 0U; i < LASER_CONFIG_WORD_COUNT; ++i) {
        if (laser_bram_read_word(index, i) != expected[i]) {
            return XST_FAILURE;
        }
    }
    return XST_SUCCESS;
}
