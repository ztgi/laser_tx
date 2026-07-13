#include "laser_rate_decimal_parser.h"

#include <stddef.h>

#define LASER_RATE_MAX_BPS 10312500000ULL

int laser_rate_decimal_mbps_to_bps(const char *text, uint64_t *rate_bps)
{
    uint64_t whole = 0U;
    uint32_t fraction = 0U;
    uint32_t fraction_digits = 0U;
    const char *cursor;

    if (text == NULL || rate_bps == NULL || text[0] == '\0') {
        return LASER_RATE_DECIMAL_BAD_ARG;
    }
    cursor = text;
    if (*cursor < '0' || *cursor > '9') {
        return LASER_RATE_DECIMAL_INVALID;
    }
    while (*cursor >= '0' && *cursor <= '9') {
        uint32_t digit = (uint32_t)(*cursor - '0');
        if (whole > (LASER_RATE_MAX_BPS / 1000000ULL - digit) / 10ULL) {
            return LASER_RATE_DECIMAL_RANGE;
        }
        whole = whole * 10ULL + digit;
        ++cursor;
    }
    if (*cursor == '.') {
        ++cursor;
        while (*cursor >= '0' && *cursor <= '9') {
            if (fraction_digits >= 3U) {
                return LASER_RATE_DECIMAL_INVALID;
            }
            fraction = fraction * 10U + (uint32_t)(*cursor - '0');
            ++fraction_digits;
            ++cursor;
        }
        if (fraction_digits == 0U) {
            return LASER_RATE_DECIMAL_INVALID;
        }
    }
    if (*cursor != '\0') {
        return LASER_RATE_DECIMAL_INVALID;
    }
    while (fraction_digits < 3U) {
        fraction *= 10U;
        ++fraction_digits;
    }
    *rate_bps = whole * 1000000ULL + (uint64_t)fraction * 1000ULL;
    if (*rate_bps == 0U || *rate_bps > LASER_RATE_MAX_BPS) {
        return LASER_RATE_DECIMAL_RANGE;
    }
    return LASER_RATE_DECIMAL_OK;
}
