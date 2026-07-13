#ifndef RUNTIME_AD9528_CONFIGS_H
#define RUNTIME_AD9528_CONFIGS_H
#include <stddef.h>
#include <stdint.h>
typedef struct {
    uint32_t out0_hz, pfd_hz, vco_hz, expected_odiv2_count_1ms;
    uint32_t vco_lower_margin_hz, vco_upper_margin_hz;
    uint16_t n2, out0_div, register_plan_id;
    uint8_t doubler, r1, m1, executable_register_encoding;
} RuntimeAd9528Config;
extern const RuntimeAd9528Config runtime_ad9528_configs[];
extern const size_t runtime_ad9528_config_count;
#endif
