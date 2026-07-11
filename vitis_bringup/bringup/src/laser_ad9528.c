#include "laser_ad9528.h"
#include "laser_hw.h"
#include <stdio.h>
#include "xspips.h"
#include "xil_printf.h"
#include "xstatus.h"

static XSpiPs ad9528_spi;
static int ad9528_initialized;
static uint16_t ad9528_last_read_error_reg;

/*
 * These addresses and bitfields are read-only decoding aids copied from the
 * ADI AD9528 register definitions used by the local project_gtx reference
 * driver.  No function in this file writes any of them during a dump.
 */
#define AD9528_CHIP_ID_LAST_REG       0x0006U
#define AD9528_PLL1_CTRL_LAST_REG     0x010AU
#define AD9528_PLL2_CTRL_REG          0x0202U
#define AD9528_PLL2_VCO_CTRL_REG      0x0203U
#define AD9528_PLL2_M1_REG            0x0204U
#define AD9528_PLL2_R1_REG            0x0207U
#define AD9528_PLL2_N2_REG            0x0208U
#define AD9528_OUT0_LAST_REG          0x0302U
#define AD9528_GLOBAL_PD_REG          0x0500U
#define AD9528_CHANNEL_PD_LAST_REG    0x0502U
#define AD9528_STATUS0_REG            0x0505U
#define AD9528_STATUS1_REG            0x0506U
#define AD9528_STATUS_PIN_ENABLE_REG  0x0507U
#define AD9528_READBACK_LAST_REG      0x0509U

#define AD9528_PLL1_FEEDBACK_BYPASS_EN (1UL << 13)
#define AD9528_PLL1_REFB_BYPASS_EN     (1UL << 12)
#define AD9528_PLL1_REFA_BYPASS_EN     (1UL << 11)
#define AD9528_PLL2_FREQ_DOUBLER_EN    (1U << 5)
#define AD9528_READBACK_CALIBRATING    (1U << 8)
#define AD9528_READBACK_PLL2_LOCKED    (1U << 1)
#define AD9528_READBACK_PLL1_LOCKED    (1U << 0)
#define AD9528_PD_OUT_CLOCKS           (1U << 1)

#define AD9528_REFERENCE_VCXO_HZ 122880000UL

int32_t laser_ad9528_spi_init(void)
{
    XSpiPs_Config *config;
    int status;

    config = XSpiPs_LookupConfig(LASER_SPI_DEVICE_ID);
    if (config == 0) {
        return XST_DEVICE_NOT_FOUND;
    }
    status = XSpiPs_CfgInitialize(&ad9528_spi, config, config->BaseAddress);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XSpiPs_SetOptions(&ad9528_spi, XSPIPS_MASTER_OPTION | XSPIPS_FORCE_SSELECT_OPTION);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XSpiPs_SetClkPrescaler(&ad9528_spi, XSPIPS_CLK_PRESCALE_64);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XSpiPs_SetSlaveSelect(&ad9528_spi, LASER_AD9528_SPI_SLAVE);
    if (status != XST_SUCCESS) {
        return status;
    }
    ad9528_initialized = 1;
    return XST_SUCCESS;
}

static int32_t ad9528_transfer(uint8_t tx[3], uint8_t rx[3])
{
    if (!ad9528_initialized) {
        return XST_FAILURE;
    }
    return XSpiPs_PolledTransfer(&ad9528_spi, tx, rx, 3U);
}

static int32_t laser_ad9528_read_n(uint16_t last_reg, uint8_t count,
                                   uint32_t *value)
{
    uint32_t result = 0U;
    uint8_t i;

    if (value == 0 || count == 0U || count > 4U) {
        return XST_INVALID_PARAM;
    }
    for (i = 0U; i < count; ++i) {
        uint8_t byte_value;
        int32_t status = laser_ad9528_read((uint16_t)(last_reg - i), &byte_value);
        if (status != XST_SUCCESS) {
            ad9528_last_read_error_reg = (uint16_t)(last_reg - i);
            xil_printf("AD9528 read failed: reg=0x%04x status=%ld\r\n",
                       (unsigned int)ad9528_last_read_error_reg, (long)status);
            return status;
        }
        result = (result << 8) | byte_value;
    }
    *value = result;
    return XST_SUCCESS;
}

int32_t laser_ad9528_write(uint16_t reg, uint8_t data)
{
    uint8_t tx[3] = {(uint8_t)((reg >> 8) & 0x7fU), (uint8_t)reg, data};
    uint8_t rx[3] = {0U, 0U, 0U};
    return ad9528_transfer(tx, rx);
}

int32_t laser_ad9528_read(uint16_t reg, uint8_t *data)
{
    uint8_t tx[3] = {(uint8_t)(0x80U | ((reg >> 8) & 0x7fU)), (uint8_t)reg, 0U};
    uint8_t rx[3] = {0U, 0U, 0U};
    int32_t status;
    if (data == 0) {
        return XST_INVALID_PARAM;
    }
    status = ad9528_transfer(tx, rx);
    if (status == XST_SUCCESS) {
        *data = rx[2];
    }
    return status;
}

int32_t laser_ad9528_read_chip_id(uint32_t *chip_id)
{
    uint8_t id0, id1, id2;
    int32_t status;
    if (chip_id == 0) {
        return XST_INVALID_PARAM;
    }
    status = laser_ad9528_read(0x0000U, &id0);
    if (status != XST_SUCCESS) return status;
    status = laser_ad9528_read(0x0001U, &id1);
    if (status != XST_SUCCESS) return status;
    status = laser_ad9528_read(0x0002U, &id2);
    if (status != XST_SUCCESS) return status;
    *chip_id = ((uint32_t)id0 << 16) | ((uint32_t)id1 << 8) | id2;
    return XST_SUCCESS;
}

int32_t laser_ad9528_basic_check(void)
{
    uint32_t chip_id;
    int32_t status = laser_ad9528_read_chip_id(&chip_id);
    if (status == XST_SUCCESS) {
        xil_printf("AD9528 chip id  : 0x%06lx\r\n", (unsigned long)chip_id);
    } else {
        xil_printf("AD9528 readback : failed (%ld)\r\n", (long)status);
    }
    return status;
}

int32_t laser_ad9528_apply_rate_profile(uint32_t profile_id)
{
    (void)profile_id;
    return XST_NO_FEATURE;
}

int32_t laser_ad9528_dump_runtime_state(LaserAd9528RuntimeState *state)
{
    uint32_t value;
    uint32_t pll2_input_hz;
    uint32_t n2;
    uint32_t m1;
    uint32_t r1;
    int32_t status;

    if (state == 0) {
        return XST_INVALID_PARAM;
    }
    if (!ad9528_initialized) {
        return XST_FAILURE;
    }

    *state = (LaserAd9528RuntimeState){0};
    ad9528_last_read_error_reg = 0U;
#define AD9528_DUMP_READ(last_reg, count, member) \
    do { \
        status = laser_ad9528_read_n((last_reg), (count), &value); \
        if (status != XST_SUCCESS) { return status; } \
        state->member = value; \
    } while (0)
    AD9528_DUMP_READ(AD9528_CHIP_ID_LAST_REG, 4U, chip_id_raw);
    AD9528_DUMP_READ(AD9528_PLL1_CTRL_LAST_REG, 3U, pll1_ctrl_raw);
    AD9528_DUMP_READ(AD9528_PLL2_CTRL_REG, 1U, pll2_ctrl_raw);
    AD9528_DUMP_READ(AD9528_PLL2_VCO_CTRL_REG, 1U, pll2_vco_ctrl_raw);
    AD9528_DUMP_READ(AD9528_PLL2_M1_REG, 1U, pll2_m1_raw);
    AD9528_DUMP_READ(AD9528_PLL2_R1_REG, 1U, pll2_r1_raw);
    AD9528_DUMP_READ(AD9528_PLL2_N2_REG, 1U, pll2_n2_raw);
    AD9528_DUMP_READ(AD9528_OUT0_LAST_REG, 3U, out0_raw);
    AD9528_DUMP_READ(AD9528_GLOBAL_PD_REG, 1U, global_pd_raw);
    AD9528_DUMP_READ(AD9528_CHANNEL_PD_LAST_REG, 2U, channel_pd_raw);
    AD9528_DUMP_READ(AD9528_STATUS0_REG, 1U, status0_raw);
    AD9528_DUMP_READ(AD9528_STATUS1_REG, 1U, status1_raw);
    AD9528_DUMP_READ(AD9528_STATUS_PIN_ENABLE_REG, 1U, status_pin_enable_raw);
    AD9528_DUMP_READ(AD9528_READBACK_LAST_REG, 2U, readback_raw);
#undef AD9528_DUMP_READ

    state->pll1_bypass_likely =
        ((state->pll1_ctrl_raw & (AD9528_PLL1_FEEDBACK_BYPASS_EN |
                                  AD9528_PLL1_REFB_BYPASS_EN |
                                  AD9528_PLL1_REFA_BYPASS_EN)) ==
         (AD9528_PLL1_FEEDBACK_BYPASS_EN |
          AD9528_PLL1_REFB_BYPASS_EN |
          AD9528_PLL1_REFA_BYPASS_EN));
    state->pll1_ref_mode = (uint8_t)((state->pll1_ctrl_raw >> 16) & 0x7U);
    state->pll1_feedback_source_vcxo =
        (uint8_t)((state->pll1_ctrl_raw >> 10) & 0x1U);
    state->pll2_input_direct_vcxo_likely = state->pll1_bypass_likely;
    state->pll1_locked = (state->readback_raw & AD9528_READBACK_PLL1_LOCKED) != 0U;
    state->pll2_locked = (state->readback_raw & AD9528_READBACK_PLL2_LOCKED) != 0U;
    state->pll2_calibrating = (state->readback_raw & AD9528_READBACK_CALIBRATING) != 0U;
    state->pll2_doubler_enabled =
        (state->pll2_ctrl_raw & AD9528_PLL2_FREQ_DOUBLER_EN) != 0U;
    state->out0_source = (uint8_t)((state->out0_raw >> 5) & 0x7U);
    state->out0_divider = (uint8_t)(((state->out0_raw >> 16) & 0xFFU) + 1U);
    state->out0_driver_mode = (uint8_t)((state->out0_raw >> 14) & 0x3U);
    state->out0_config_enabled =
        ((state->global_pd_raw & AD9528_PD_OUT_CLOCKS) == 0U) &&
        ((state->channel_pd_raw & 0x0001U) == 0U);

    /* A frequency is only derived for the documented direct-VCXO bypass case. */
    r1 = state->pll2_r1_raw & 0x1FU;
    n2 = (state->pll2_n2_raw & 0xFFU) + 1U;
    m1 = state->pll2_m1_raw & 0x7U;
    if (state->pll1_bypass_likely && r1 != 0U && m1 >= 3U && m1 <= 5U) {
        uint64_t vco = (uint64_t)AD9528_REFERENCE_VCXO_HZ *
                       (state->pll2_doubler_enabled ? 2U : 1U) * n2 * m1;
        vco /= r1;
        if (vco <= UINT32_MAX) {
            state->derived_vco_hz = (uint32_t)vco;
            state->derived_vco_valid = 1U;
            pll2_input_hz = state->derived_vco_hz / m1;
            if (state->out0_source == 0U && state->out0_divider != 0U) {
                state->derived_out0_hz = pll2_input_hz / state->out0_divider;
                state->derived_out0_valid = 1U;
            }
        }
    }
    return XST_SUCCESS;
}

uint16_t laser_ad9528_last_read_error_reg(void)
{
    return ad9528_last_read_error_reg;
}

void laser_ad9528_print_runtime_state(const LaserAd9528RuntimeState *state)
{
    if (state == 0) {
        return;
    }
    xil_printf("AD9528 raw: chip=0x%08lx pll1=0x%06lx pll2ctrl=0x%02x vco=0x%02x m1=0x%02x r1=0x%02x n2=0x%02x\r\n",
               (unsigned long)state->chip_id_raw,
               (unsigned long)state->pll1_ctrl_raw,
               (unsigned int)state->pll2_ctrl_raw,
               (unsigned int)state->pll2_vco_ctrl_raw,
               (unsigned int)state->pll2_m1_raw,
               (unsigned int)state->pll2_r1_raw,
               (unsigned int)state->pll2_n2_raw);
    xil_printf("AD9528 raw: out0=0x%06lx pd=0x%02x chpd=0x%04x stat0=0x%02x stat1=0x%02x stat_en=0x%02x readback=0x%04x\r\n",
               (unsigned long)state->out0_raw,
               (unsigned int)state->global_pd_raw,
               (unsigned int)state->channel_pd_raw,
               (unsigned int)state->status0_raw,
               (unsigned int)state->status1_raw,
               (unsigned int)state->status_pin_enable_raw,
               (unsigned int)state->readback_raw);
    xil_printf("AD9528 parsed: pll1_ref_mode=%u pll1_feedback_vcxo=%u pll1_bypass_likely=%u pll2_direct_vcxo_likely=%u pll1_lock=%u pll2_lock=%u calibrating=%u doubler=%u out0_source=%u out0_div=%u out0_driver=%u out0_cfg_enabled=%u\r\n",
               (unsigned int)state->pll1_ref_mode,
               (unsigned int)state->pll1_feedback_source_vcxo,
               (unsigned int)state->pll1_bypass_likely,
               (unsigned int)state->pll2_input_direct_vcxo_likely,
               (unsigned int)state->pll1_locked,
               (unsigned int)state->pll2_locked,
               (unsigned int)state->pll2_calibrating,
               (unsigned int)state->pll2_doubler_enabled,
               (unsigned int)state->out0_source,
               (unsigned int)state->out0_divider,
               (unsigned int)state->out0_driver_mode,
               (unsigned int)state->out0_config_enabled);
    if (state->derived_out0_valid) {
        xil_printf("AD9528 derived: vco_hz=%lu out0_hz=%lu confidence=REGISTER_READBACK_ONLY\r\n",
                   (unsigned long)state->derived_vco_hz,
                   (unsigned long)state->derived_out0_hz);
    } else {
        xil_printf("AD9528 derived: vco_hz=UNKNOWN out0_hz=UNKNOWN confidence=REGISTER_READBACK_ONLY\r\n");
    }
}

int32_t laser_ad9528_format_runtime_status(char *buffer, size_t buffer_size,
                                            const LaserAd9528RuntimeState *state)
{
    if (buffer == 0 || buffer_size == 0U || state == 0) {
        return XST_INVALID_PARAM;
    }
    if (state->derived_out0_valid) {
        (void)snprintf(buffer, buffer_size,
                       "OK AD9528_STATUS spi_ok=1 chip_id=0x%08lx pll1_lock=%u pll2_lock=%u vco_hz=%lu out0_source=%u out0_divider=%u out0_hz=%lu out0_cfg_enabled=%u runtime_image_confidence=REGISTER_READBACK_ONLY error_code=0",
                       (unsigned long)state->chip_id_raw,
                       (unsigned int)state->pll1_locked,
                       (unsigned int)state->pll2_locked,
                       (unsigned long)state->derived_vco_hz,
                       (unsigned int)state->out0_source,
                       (unsigned int)state->out0_divider,
                       (unsigned long)state->derived_out0_hz,
                       (unsigned int)state->out0_config_enabled);
    } else {
        (void)snprintf(buffer, buffer_size,
                       "OK AD9528_STATUS spi_ok=1 chip_id=0x%08lx pll1_lock=%u pll2_lock=%u vco_hz=UNKNOWN out0_source=%u out0_divider=%u out0_hz=UNKNOWN out0_cfg_enabled=%u runtime_image_confidence=REGISTER_READBACK_ONLY error_code=0",
                       (unsigned long)state->chip_id_raw,
                       (unsigned int)state->pll1_locked,
                       (unsigned int)state->pll2_locked,
                       (unsigned int)state->out0_source,
                       (unsigned int)state->out0_divider,
                       (unsigned int)state->out0_config_enabled);
    }
    return XST_SUCCESS;
}
