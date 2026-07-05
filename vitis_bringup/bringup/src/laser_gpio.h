#ifndef LASER_GPIO_H
#define LASER_GPIO_H

#include <stdint.h>
#include "xgpio.h"

#define LASER_CTRL_INDEX_MASK       0x000000ffU
#define LASER_CTRL_APPLY_TOGGLE     0x00000100U
#define LASER_CTRL_ENABLE           0x00000200U
#define LASER_CTRL_SOFT_RESET       0x00000400U
#define LASER_CTRL_DIRECT_SOURCE    0x00000800U
#define LASER_CTRL_DIRECT_LEN_127   0x00001000U
#define LASER_CTRL_RATE_ID_SHIFT    13U
#define LASER_CTRL_RATE_ID_MASK     0x0001e000U
#define LASER_CTRL_RATE_REQ_TOGGLE  0x00020000U

#define LASER_RATE_ID_NONE          0U
#define LASER_RATE_ID_500M          1U
#define LASER_RATE_ID_1000M         2U
#define LASER_RATE_ID_2000M         3U
#define LASER_RATE_ID_1250M         4U
#define LASER_RATE_ID_2500M         5U
#define LASER_RATE_ID_5000M         6U

typedef struct {
    XGpio instance;
    uint32_t control_shadow;
} LaserGpio;

int laser_gpio_init(LaserGpio *gpio);
void laser_gpio_write_control(LaserGpio *gpio, uint32_t value);
void laser_gpio_select_config(LaserGpio *gpio, uint8_t index,
                              int direct_source, int direct_len_127);
void laser_gpio_soft_reset(LaserGpio *gpio);
void laser_gpio_toggle_apply(LaserGpio *gpio);
void laser_gpio_set_enable(LaserGpio *gpio, int enable);
void laser_gpio_rate_request(LaserGpio *gpio, uint32_t rate_id);
uint32_t laser_gpio_read_status(LaserGpio *gpio);

#endif
