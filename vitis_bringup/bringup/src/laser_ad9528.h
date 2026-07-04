#ifndef LASER_AD9528_H
#define LASER_AD9528_H

#include <stdint.h>

int32_t laser_ad9528_spi_init(void);
int32_t laser_ad9528_write(uint16_t reg, uint8_t data);
int32_t laser_ad9528_read(uint16_t reg, uint8_t *data);
int32_t laser_ad9528_read_chip_id(uint32_t *chip_id);
int32_t laser_ad9528_basic_check(void);
int32_t laser_ad9528_apply_rate_profile(uint32_t profile_id);

#endif
