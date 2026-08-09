#include "laser_bram.h"
#include <stddef.h>
#include "laser_hw.h"
#include "xil_io.h"
#include "xstatus.h"

static uint8_t laser_next_sequence_id = 1U;

static UINTPTR laser_bram_word_address(uint8_t index, uint32_t word_index)
{
    return (UINTPTR)LASER_BRAM_BASEADDR +
           ((UINTPTR)index * LASER_CONFIG_STRIDE_BYTES) +
           ((UINTPTR)word_index * sizeof(uint32_t));
}

static uint32_t laser_crc32_word_le(uint32_t crc, uint32_t value)
{
    uint32_t bit_index;
    for (bit_index = 0U; bit_index < 32U; ++bit_index) {
        crc = ((crc ^ value) & 1U) != 0U ?
              ((crc >> 1) ^ 0xEDB88320U) : (crc >> 1);
        value >>= 1;
    }
    return crc;
}

uint32_t laser_bram_crc32_payload(
    const uint32_t words[LASER_TX_RECORD_WORD_COUNT])
{
    uint32_t crc = 0xFFFFFFFFU;
    uint32_t i;
    for (i = 1U; i <= 14U; ++i) {
        crc = laser_crc32_word_le(crc, words[i]);
    }
    return ~crc;
}

static uint32_t laser_record_header(uint8_t sequence_id, uint8_t valid)
{
    return ((uint32_t)LASER_TX_RECORD_MAGIC << 16) |
           ((uint32_t)LASER_TX_RECORD_FORMAT_VERSION << 12) |
           ((uint32_t)(valid != 0U) << 11) |
           (uint32_t)sequence_id;
}

static uint32_t laser_phase_count(const LaserConfig *config)
{
    if (config->phase_shift_en == 0U) {
        return 1U;
    }
    return config->pattern_len_127 != 0U ? 127U : 63U;
}

int laser_bram_validate_config(const LaserConfig *config)
{
    uint32_t i;
    uint32_t active_gap_count;
    uint32_t pattern_instances;

    if (config == NULL) {
        return XST_INVALID_PARAM;
    }
    if (config->repeat_cycles < 1U ||
        config->repeat_cycles > LASER_TX_RECORD_MAX_REPEAT ||
        config->pattern_len_127 > 1U ||
        config->phase_shift_en > 1U || config->loop_en > 1U ||
        config->eom_enable > 1U || (config->pattern_top & 0x80000000U) != 0U) {
        return XST_INVALID_PARAM;
    }

    active_gap_count = (uint32_t)config->repeat_cycles - 1U;
    for (i = active_gap_count; i < LASER_TX_RECORD_MAX_GAPS; ++i) {
        if (config->gap_len_bits[i] != 0U) {
            return XST_INVALID_PARAM;
        }
    }

    pattern_instances = laser_phase_count(config) *
                        (uint32_t)config->repeat_cycles;
    if (config->eom_enable != 0U &&
        (uint32_t)config->eom_global_pattern_index >= pattern_instances) {
        return XST_INVALID_PARAM;
    }
    return XST_SUCCESS;
}

static void laser_config_to_words(const LaserConfig *config,
                                  uint8_t sequence_id,
                                  uint8_t commit_valid,
                                  uint32_t words[LASER_TX_RECORD_WORD_COUNT])
{
    uint32_t i;
    words[0] = laser_record_header(sequence_id, commit_valid);
    /* ABI-stable legacy PRBS fields are no longer software inputs. Keep
     * word1, word2[12:5] and word2[15] at their fixed legal value of zero;
     * words9..12 are the sole PL pattern source. */
    words[1] = 0U;
    words[2] = ((uint32_t)config->repeat_cycles & 0x1FU) |
               ((uint32_t)config->phase_shift_en << 13) |
               ((uint32_t)config->loop_en << 14) |
               ((uint32_t)config->pattern_len_127 << 16) |
               ((uint32_t)config->eom_enable << 17) |
               (((uint32_t)config->eom_global_pattern_index & 0x7FFU) << 18);
    words[3] = (uint32_t)config->head_delay_bits;
    for (i = 0U; i < 4U; ++i) {
        words[4U + i] =
            ((uint32_t)config->gap_len_bits[i * 4U]) |
            ((uint32_t)config->gap_len_bits[i * 4U + 1U] << 8) |
            ((uint32_t)config->gap_len_bits[i * 4U + 2U] << 16) |
            ((i == 3U) ? 0U :
             ((uint32_t)config->gap_len_bits[i * 4U + 3U] << 24));
    }
    words[8] = (uint32_t)config->eom_lead_ticks |
               ((uint32_t)config->eom_trail_ticks << 16);
    words[9] = config->pattern_low;
    words[10] = config->pattern_mid;
    words[11] = config->pattern_high;
    words[12] = config->pattern_top & 0x7FFFFFFFU;
    words[13] = (uint32_t)sequence_id |
                ((uint32_t)LASER_TX_RECORD_WORD_COUNT << 8) |
                ((uint32_t)LASER_TX_RECORD_MAX_REPEAT << 16) |
                ((uint32_t)LASER_TX_RECORD_GAP_WIDTH << 24);
    words[14] = 0U;
    words[15] = laser_bram_crc32_payload(words);
}

uint32_t laser_bram_read_word(uint8_t index, uint32_t word_index)
{
    return Xil_In32(laser_bram_word_address(index, word_index));
}

int laser_bram_write_config(uint8_t index, const LaserConfig *config)
{
    uint32_t words[LASER_TX_RECORD_WORD_COUNT];
    uint32_t i;
    uint8_t sequence_id;

    if (index >= LASER_TX_RECORD_MAX_CONFIGS ||
        laser_bram_validate_config(config) != XST_SUCCESS) {
        return XST_INVALID_PARAM;
    }

    sequence_id = laser_next_sequence_id++;
    if (laser_next_sequence_id == 0U) {
        laser_next_sequence_id = 1U;
    }
    laser_config_to_words(config, sequence_id, 0U, words);

    /* Invalidate first, then publish payload+CRC. */
    Xil_Out32(laser_bram_word_address(index, 0U), words[0]);
    for (i = 1U; i < LASER_TX_RECORD_WORD_COUNT; ++i) {
        Xil_Out32(laser_bram_word_address(index, i), words[i]);
    }
    for (i = 0U; i < LASER_TX_RECORD_WORD_COUNT; ++i) {
        if (laser_bram_read_word(index, i) != words[i]) {
            return XST_FAILURE;
        }
    }

    /* The valid header is the sole commit point. Xil_In/Out32 are volatile;
     * DMB prevents CPU ordering from moving the commit ahead of payload. */
    __asm__ volatile ("dmb sy" ::: "memory");
    words[0] = laser_record_header(sequence_id, 1U);
    Xil_Out32(laser_bram_word_address(index, 0U), words[0]);
    if (laser_bram_read_word(index, 0U) != words[0]) {
        return XST_FAILURE;
    }
    __asm__ volatile ("dmb sy" ::: "memory");
    return XST_SUCCESS;
}

int laser_bram_verify_config(uint8_t index, const LaserConfig *config)
{
    uint32_t expected[LASER_TX_RECORD_WORD_COUNT];
    uint32_t header;
    uint32_t i;
    uint8_t sequence_id;

    if (index >= LASER_TX_RECORD_MAX_CONFIGS ||
        laser_bram_validate_config(config) != XST_SUCCESS) {
        return XST_INVALID_PARAM;
    }
    header = laser_bram_read_word(index, 0U);
    sequence_id = (uint8_t)(header & 0xFFU);
    laser_config_to_words(config, sequence_id, 1U, expected);
    for (i = 0U; i < LASER_TX_RECORD_WORD_COUNT; ++i) {
        if (laser_bram_read_word(index, i) != expected[i]) {
            return XST_FAILURE;
        }
    }
    return XST_SUCCESS;
}
