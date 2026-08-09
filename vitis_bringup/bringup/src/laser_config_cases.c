#include "laser_config_cases.h"
#include <string.h>
#include "xstatus.h"

const char *laser_test_case_name(LaserTestCase test_case)
{
    switch (test_case) {
    case LASER_TEST_DIRECT63:  return "DIRECT63";
    case LASER_TEST_DIRECT127: return "DIRECT127";
    case LASER_TEST_PRBS6:     return "CONFIGURED_PRBS6_GOLDEN";
    case LASER_TEST_PRBS7:     return "CONFIGURED_PRBS7_GOLDEN";
    case LASER_TEST_MULTI_GAP: return "MULTI_GAP";
    default: return "INVALID";
    }
}

int laser_test_case_expects_config_error(LaserTestCase test_case)
{
    (void)test_case;
    return 0;
}

int laser_make_test_config(LaserTestCase test_case, LaserConfig *config)
{
    if (config == NULL) {
        return XST_INVALID_PARAM;
    }
    memset(config, 0, sizeof(*config));
    config->repeat_cycles = 4U;
    config->head_delay_bits = 3U;
    config->gap_len_bits[0] = 1U;
    config->gap_len_bits[1] = 64U;
    config->gap_len_bits[2] = 3U;
    config->pattern_low = 0x89abcdefU;
    config->pattern_mid = 0x01234567U;
    config->pattern_high = 0x76543210U;
    config->pattern_top = 0x52a55aa5U;

    switch (test_case) {
    case LASER_TEST_DIRECT63:
        break;
    case LASER_TEST_DIRECT127:
        config->pattern_len_127 = 1U;
        break;
    case LASER_TEST_PRBS6:
        /* Legacy x^6+x^5+1, seed[5:0]=0x1a, output MSB first into
         * configured_pattern[i]. PL no longer contains an LFSR. */
        config->pattern_low = 0xa3083f56U;
        config->pattern_mid = 0x376938bcU;
        config->pattern_high = 0U;
        config->pattern_top = 0U;
        break;
    case LASER_TEST_PRBS7:
        /* Legacy x^7+x^6+1, seed[6:0]=0x5a, output MSB first into
         * configured_pattern[i]. PL no longer contains an LFSR. */
        config->pattern_len_127 = 1U;
        config->pattern_low = 0x74b1bdadU;
        config->pattern_mid = 0x103faa67U;
        config->pattern_high = 0xcd13c50cU;
        config->pattern_top = 0x491c2f95U;
        break;
    case LASER_TEST_MULTI_GAP:
        break;
    default:
        return XST_INVALID_PARAM;
    }
    return XST_SUCCESS;
}
