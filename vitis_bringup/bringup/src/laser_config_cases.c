#include "laser_config_cases.h"
#include "xstatus.h"

const char *laser_test_case_name(LaserTestCase test_case)
{
    switch (test_case) {
    case LASER_TEST_DIRECT63:  return "DIRECT63";
    case LASER_TEST_DIRECT127: return "DIRECT127";
    case LASER_TEST_PRBS6:     return "PRBS6";
    case LASER_TEST_PRBS7:     return "PRBS7";
    case LASER_TEST_GAP:       return "GAP";
    case LASER_TEST_INVALID_REPEAT_ZERO: return "INVALID_REPEAT_ZERO";
    case LASER_TEST_INVALID_PRBS_SEED_ZERO: return "INVALID_PRBS_SEED_ZERO";
    case LASER_TEST_INVALID_INSERT_AFTER: return "INVALID_INSERT_AFTER";
    case LASER_TEST_INVALID_PRBS_ORDER: return "INVALID_PRBS_ORDER";
    case LASER_TEST_INVALID_DIRECT_MODE_MISMATCH: return "INVALID_DIRECT_MODE_MISMATCH";
    default: return "INVALID";
    }
}

int laser_test_case_expects_config_error(LaserTestCase test_case)
{
    switch (test_case) {
    case LASER_TEST_INVALID_REPEAT_ZERO:
    case LASER_TEST_INVALID_PRBS_SEED_ZERO:
    case LASER_TEST_INVALID_INSERT_AFTER:
    case LASER_TEST_INVALID_PRBS_ORDER:
    case LASER_TEST_INVALID_DIRECT_MODE_MISMATCH:
        return 1;
    default:
        return 0;
    }
}

int laser_make_test_config(LaserTestCase test_case, LaserConfig *config,
                           int *direct_source, int *direct_len_127)
{
    if (config == 0 || direct_source == 0 || direct_len_127 == 0) {
        return XST_INVALID_PARAM;
    }
    config->seed = 0x0000005aU;
    config->repeat_cycles = 4U;
    config->gap_len_bits = 0U;
    config->insert_after = 0U;
    config->prbs_order = 6U;
    config->phase_shift_en = 0U;
    config->loop_en = 0U;
    config->pattern_low = 0x89abcdefU;
    config->pattern_mid = 0x01234567U;
    config->pattern_high = 0x76543210U;
    config->pattern_top = 0x52a55aa5U;
    *direct_source = 0;
    *direct_len_127 = 0;

    switch (test_case) {
    case LASER_TEST_DIRECT63:
        *direct_source = 1;
        break;
    case LASER_TEST_DIRECT127:
        *direct_source = 1;
        *direct_len_127 = 1;
        break;
    case LASER_TEST_PRBS6:
        config->prbs_order = 6U;
        break;
    case LASER_TEST_PRBS7:
        config->prbs_order = 7U;
        break;
    case LASER_TEST_GAP:
        config->gap_len_bits = 8U;
        config->insert_after = 2U;
        break;
    case LASER_TEST_INVALID_REPEAT_ZERO:
        config->repeat_cycles = 0U;
        break;
    case LASER_TEST_INVALID_PRBS_SEED_ZERO:
        config->seed = 0U;
        config->prbs_order = 6U;
        break;
    case LASER_TEST_INVALID_INSERT_AFTER:
        config->repeat_cycles = 4U;
        config->insert_after = 5U;
        break;
    case LASER_TEST_INVALID_PRBS_ORDER:
        config->prbs_order = 8U;
        break;
    case LASER_TEST_INVALID_DIRECT_MODE_MISMATCH:
        *direct_source = 0;
        *direct_len_127 = 1;
        config->prbs_order = 6U;
        break;
    default:
        return XST_INVALID_PARAM;
    }
    return XST_SUCCESS;
}
