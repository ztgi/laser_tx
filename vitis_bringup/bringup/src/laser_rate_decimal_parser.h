#ifndef LASER_RATE_DECIMAL_PARSER_H
#define LASER_RATE_DECIMAL_PARSER_H

#include <stdint.h>

enum {
    LASER_RATE_DECIMAL_OK = 0,
    LASER_RATE_DECIMAL_BAD_ARG = -1,
    LASER_RATE_DECIMAL_INVALID = -2,
    LASER_RATE_DECIMAL_RANGE = -3
};

int laser_rate_decimal_mbps_to_bps(const char *text, uint64_t *rate_bps);

#endif
