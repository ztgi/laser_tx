    #include "laser_gpio.h"
#include <stddef.h>
#include "laser_hw.h"
#include "sleep.h"
#include "xstatus.h"

int laser_gpio_init(LaserGpio *gpio)
{
    int status;

    if (gpio == NULL) {
        return XST_INVALID_PARAM;
    }

    status = XGpio_Initialize(&gpio->instance, LASER_GPIO_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }

    XGpio_SetDataDirection(&gpio->instance, LASER_GPIO_CTRL_CHANNEL, 0x00000000U);
    XGpio_SetDataDirection(&gpio->instance, LASER_GPIO_STATUS_CHANNEL, 0xffffffffU);
    gpio->control_shadow = 0U;
    XGpio_DiscreteWrite(&gpio->instance, LASER_GPIO_CTRL_CHANNEL, 0U);
    return XST_SUCCESS;
}

void laser_gpio_write_control(LaserGpio *gpio, uint32_t value)
{
    gpio->control_shadow = value;
    XGpio_DiscreteWrite(&gpio->instance, LASER_GPIO_CTRL_CHANNEL, value);
}

void laser_gpio_select_config(LaserGpio *gpio, uint8_t index,
                              int direct_source, int direct_len_127)
{
    uint32_t value = gpio->control_shadow;

    value &= ~(LASER_CTRL_INDEX_MASK | LASER_CTRL_DIRECT_SOURCE |
               LASER_CTRL_DIRECT_LEN_127);
    value |= (uint32_t)index;
    if (direct_source) {
        value |= LASER_CTRL_DIRECT_SOURCE;
    }
    if (direct_len_127) {
        value |= LASER_CTRL_DIRECT_LEN_127;
    }
    laser_gpio_write_control(gpio, value);
}

void laser_gpio_soft_reset(LaserGpio *gpio)
{
    laser_gpio_write_control(gpio, gpio->control_shadow | LASER_CTRL_SOFT_RESET);
    usleep(10U);
    laser_gpio_write_control(gpio, gpio->control_shadow & ~LASER_CTRL_SOFT_RESET);
    usleep(10U);
}

void laser_gpio_toggle_apply(LaserGpio *gpio)
{
    /* Apply is an event encoded by changing state; never pulse it high then low. */
    laser_gpio_write_control(gpio, gpio->control_shadow ^ LASER_CTRL_APPLY_TOGGLE);
}

void laser_gpio_set_enable(LaserGpio *gpio, int enable)
{
    uint32_t value = gpio->control_shadow;
    if (enable) {
        value |= LASER_CTRL_ENABLE;
    } else {
        value &= ~LASER_CTRL_ENABLE;
    }
    laser_gpio_write_control(gpio, value);
}

void laser_gpio_rate_request(LaserGpio *gpio, uint32_t rate_id)
{
    uint32_t value = gpio->control_shadow;

    value &= ~LASER_CTRL_RATE_ID_MASK;
    value |= ((rate_id << LASER_CTRL_RATE_ID_SHIFT) & LASER_CTRL_RATE_ID_MASK);
    value ^= LASER_CTRL_RATE_REQ_TOGGLE;
    laser_gpio_write_control(gpio, value);
}

uint32_t laser_gpio_read_status(LaserGpio *gpio)
{
    return XGpio_DiscreteRead(&gpio->instance, LASER_GPIO_STATUS_CHANNEL);
}
