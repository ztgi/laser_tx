#ifndef LASER_CONFIG_CASES_H
#define LASER_CONFIG_CASES_H

#include "laser_bram.h"

typedef enum {
    LASER_TEST_DIRECT63 = 0,
    LASER_TEST_DIRECT127,
    LASER_TEST_PRBS6,
    LASER_TEST_PRBS7,
    LASER_TEST_MULTI_GAP
} LaserTestCase;

const char *laser_test_case_name(LaserTestCase test_case);
int laser_test_case_expects_config_error(LaserTestCase test_case);
int laser_make_test_config(LaserTestCase test_case, LaserConfig *config);

#endif