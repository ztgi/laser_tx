#include "laser_ad9528.h"
#include "laser_hw.h"
#include <stdio.h>
#include <string.h>
#include "xspips.h"
#include "xil_printf.h"
#include "xstatus.h"

static XSpiPs ad9528_spi;
static int ad9528_initialized;
static uint16_t ad9528_last_read_error_reg;
static uint8_t ad9528_last_product_id;
static uint8_t ad9528_last_revision;
static uint8_t ad9528_last_vendor_id;

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
#define AD9528_PLL2_CP_REG             0x0200U
#define AD9528_PLL2_FB_DIV_REG         0x0201U
#define AD9528_PLL2_LOOP_FILTER0_REG   0x0205U
#define AD9528_PLL2_LOOP_FILTER1_REG   0x0206U
#define AD9528_PLL2_AUX_REG            0x0209U
#define AD9528_CHANNEL_SYNC_REG        0x032AU
#define AD9528_SYSREF_RESAMPLE0_REG    0x032DU
#define AD9528_RESERVED_0503_REG       0x0503U
#define AD9528_RESERVED_0504_REG       0x0504U

#define AD9528_PLL1_CTRL0_REG          0x0108U
#define AD9528_PLL1_CTRL1_REG          0x0109U
#define AD9528_OUT0_CTRL_REG           0x0300U
#define AD9528_OUT0_DRIVER_REG         0x0301U
#define AD9528_OUT0_DIVIDER_REG        0x0302U
#define AD9528_CHANNEL_PD0_REG         0x0501U

#define AD9528_PLL1_OSC_IN_DIFF_EN     0x01U
#define AD9528_PLL1_BYPASS_BITS        0x38U
#define AD9528_OUT_SOURCE_MASK         0xE0U
#define AD9528_OUT_SOURCE_VCXO         0x20U
#define AD9528_OUT_DRIVER_MASK         0xC0U
#define AD9528_OUT_DRIVER_LVDS         0x00U
#define AD9528_OUT_DIVIDER_1           0x00U
#define AD9528_PD_PLL1_PLL2_MASK       0x0CU
#define AD9528_PD_PLL1_PLL2            0x0CU

#define AD9528_PLL1_FEEDBACK_BYPASS_EN (1UL << 13)
#define AD9528_PLL1_REFB_BYPASS_EN     (1UL << 12)
#define AD9528_PLL1_REFA_BYPASS_EN     (1UL << 11)
#define AD9528_PLL2_FREQ_DOUBLER_EN    (1U << 5)
#define AD9528_READBACK_CALIBRATING    (1U << 8)
#define AD9528_READBACK_PLL2_LOCKED    (1U << 1)
#define AD9528_READBACK_PLL1_LOCKED    (1U << 0)
#define AD9528_PD_OUT_CLOCKS           (1U << 1)

#define AD9528_REFERENCE_VCXO_HZ 122880000UL

#define AD9528_SERIAL_PORT_CONFIG_REG 0x0000U
#define AD9528_SERIAL_PORT_4WIRE       0x18U
#define AD9528_PRODUCT_ID_REG          0x0003U
#define AD9528_REVISION_REG            0x0006U
#define AD9528_VENDOR_ID_REG           0x000CU
#define AD9528_PRODUCT_ID_EXPECTED     0x05U
#define AD9528_REVISION_EXPECTED       0x03U
#define AD9528_VENDOR_ID_EXPECTED      0x56U

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
    /* No CPOL/CPHA option bits: SPI mode 0 (CPOL=0, CPHA=0). */
    status = XSpiPs_SetOptions(&ad9528_spi,
                               XSPIPS_MASTER_OPTION |
                               XSPIPS_FORCE_SSELECT_OPTION);
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

    /*
     * AD9528 powers up with the bidirectional serial data path.  This board
     * has separate SDIO/MOSI and SDO/MISO nets, so enable the dedicated SDO.
     * Register 0x0000 is the serial-port live register and needs no
     * IO_UPDATE.  This is the only configuration write performed here.
     */
    status = laser_ad9528_write(AD9528_SERIAL_PORT_CONFIG_REG,
                                AD9528_SERIAL_PORT_4WIRE);
    if (status != XST_SUCCESS) {
        ad9528_initialized = 0;
        return status;
    }
    return laser_ad9528_identify(&ad9528_last_product_id,
                                 &ad9528_last_revision,
                                 &ad9528_last_vendor_id);
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
    int32_t status = ad9528_transfer(tx, rx);
    xil_printf("AD9528 SPI WRITE reg=0x%04x TX=%02x %02x %02x RX=%02x %02x %02x status=%ld\r\n",
               (unsigned int)reg,
               (unsigned int)tx[0], (unsigned int)tx[1], (unsigned int)tx[2],
               (unsigned int)rx[0], (unsigned int)rx[1], (unsigned int)rx[2],
               (long)status);
    return status;
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
    xil_printf("AD9528 SPI READ  reg=0x%04x TX=%02x %02x %02x RX=%02x %02x %02x status=%ld\r\n",
               (unsigned int)reg,
               (unsigned int)tx[0], (unsigned int)tx[1], (unsigned int)tx[2],
               (unsigned int)rx[0], (unsigned int)rx[1], (unsigned int)rx[2],
               (long)status);
    if (status == XST_SUCCESS) {
        *data = rx[2];
    }
    return status;
}

int32_t laser_ad9528_read_chip_id(uint32_t *chip_id)
{
    uint8_t id3, id4, id5;
    int32_t status;
    if (chip_id == 0) {
        return XST_INVALID_PARAM;
    }
    status = laser_ad9528_read(0x0003U, &id3);
    if (status != XST_SUCCESS) return status;
    status = laser_ad9528_read(0x0004U, &id4);
    if (status != XST_SUCCESS) return status;
    status = laser_ad9528_read(0x0005U, &id5);
    if (status != XST_SUCCESS) return status;
    *chip_id = ((uint32_t)id5 << 16) | ((uint32_t)id4 << 8) | id3;
    return XST_SUCCESS;
}

int32_t laser_ad9528_identify(uint8_t *product_id, uint8_t *revision,
                              uint8_t *vendor_id)
{
    int32_t status;

    if (product_id == 0 || revision == 0 || vendor_id == 0) {
        return XST_INVALID_PARAM;
    }
    status = laser_ad9528_read(AD9528_PRODUCT_ID_REG, product_id);
    if (status != XST_SUCCESS) return status;
    status = laser_ad9528_read(AD9528_REVISION_REG, revision);
    if (status != XST_SUCCESS) return status;
    status = laser_ad9528_read(AD9528_VENDOR_ID_REG, vendor_id);
    if (status != XST_SUCCESS) return status;

    ad9528_last_product_id = *product_id;
    ad9528_last_revision = *revision;
    ad9528_last_vendor_id = *vendor_id;
    xil_printf("AD9528 identity: reg0003=0x%02x reg0006=0x%02x reg000c=0x%02x expected=05/03/56\r\n",
               (unsigned int)*product_id, (unsigned int)*revision,
               (unsigned int)*vendor_id);
    if (*product_id != AD9528_PRODUCT_ID_EXPECTED ||
        *revision != AD9528_REVISION_EXPECTED ||
        *vendor_id != AD9528_VENDOR_ID_EXPECTED) {
        xil_printf("AD9528 identity mismatch: full runtime dump is blocked\r\n");
        return XST_DEVICE_NOT_FOUND;
    }
    return XST_SUCCESS;
}

void laser_ad9528_get_last_identity(uint8_t *product_id, uint8_t *revision,
                                    uint8_t *vendor_id)
{
    if (product_id != 0) *product_id = ad9528_last_product_id;
    if (revision != 0) *revision = ad9528_last_revision;
    if (vendor_id != 0) *vendor_id = ad9528_last_vendor_id;
}

int32_t laser_ad9528_basic_check(void)
{
    uint32_t chip_id;
    uint8_t product_id = 0U;
    uint8_t revision = 0U;
    uint8_t vendor_id = 0U;
    int32_t status = laser_ad9528_identify(&product_id, &revision, &vendor_id);
    if (status == XST_SUCCESS) {
        status = laser_ad9528_read_chip_id(&chip_id);
        if (status == XST_SUCCESS) {
            xil_printf("AD9528 chip id  : raw[0005:0003]=0x%06lx revision=0x%02x vendor=0x%02x\r\n",
                       (unsigned long)chip_id, (unsigned int)revision,
                       (unsigned int)vendor_id);
        }
    } else {
        xil_printf("AD9528 identify : failed (%ld), raw 0003/0006/000c=%02x/%02x/%02x\r\n",
                   (long)status, (unsigned int)product_id,
                   (unsigned int)revision, (unsigned int)vendor_id);
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
    uint8_t product_id;
    uint8_t revision;
    uint8_t vendor_id;

    if (state == 0) {
        return XST_INVALID_PARAM;
    }
    if (!ad9528_initialized) {
        return XST_FAILURE;
    }

    status = laser_ad9528_identify(&product_id, &revision, &vendor_id);
    if (status != XST_SUCCESS) {
        return status;
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
    AD9528_DUMP_READ(AD9528_PLL2_CP_REG, 1U, reg0200_raw);
    AD9528_DUMP_READ(AD9528_PLL2_FB_DIV_REG, 1U, reg0201_raw);
    AD9528_DUMP_READ(AD9528_PLL2_LOOP_FILTER0_REG, 1U, reg0205_raw);
    AD9528_DUMP_READ(AD9528_PLL2_LOOP_FILTER1_REG, 1U, reg0206_raw);
    AD9528_DUMP_READ(AD9528_PLL2_AUX_REG, 1U, reg0209_raw);
    AD9528_DUMP_READ(AD9528_CHANNEL_SYNC_REG, 1U, reg032a_raw);
    AD9528_DUMP_READ(AD9528_SYSREF_RESAMPLE0_REG, 1U, reg032d_raw);
    AD9528_DUMP_READ(AD9528_RESERVED_0503_REG, 1U, reg0503_raw);
    AD9528_DUMP_READ(AD9528_RESERVED_0504_REG, 1U, reg0504_raw);
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
    xil_printf("AD9528 default image supplement: 0200=%02x 0201=%02x 0205=%02x 0206=%02x 0209=%02x 032a=%02x 032d=%02x 0503=%02x 0504=%02x clock_tree_initialized=0 out0_runtime_valid=0\r\n",
               (unsigned int)state->reg0200_raw,
               (unsigned int)state->reg0201_raw,
               (unsigned int)state->reg0205_raw,
               (unsigned int)state->reg0206_raw,
               (unsigned int)state->reg0209_raw,
               (unsigned int)state->reg032a_raw,
               (unsigned int)state->reg032d_raw,
               (unsigned int)state->reg0503_raw,
               (unsigned int)state->reg0504_raw);
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

int32_t laser_ad9528_format_default_image(char *buffer, size_t buffer_size,
                                           const LaserAd9528RuntimeState *state)
{
    if (buffer == 0 || buffer_size == 0U || state == 0) {
        return XST_INVALID_PARAM;
    }
    (void)snprintf(buffer, buffer_size,
                   "OK AD9528_DEFAULT_IMAGE reg0200=%02x reg0201=%02x reg0205=%02x reg0206=%02x reg0209=%02x reg032a=%02x reg032d=%02x reg0503=%02x reg0504=%02x clock_tree_initialized=0 out0_runtime_valid=0",
                   (unsigned int)state->reg0200_raw,
                   (unsigned int)state->reg0201_raw,
                   (unsigned int)state->reg0205_raw,
                   (unsigned int)state->reg0206_raw,
                   (unsigned int)state->reg0209_raw,
                   (unsigned int)state->reg032a_raw,
                   (unsigned int)state->reg032d_raw,
                   (unsigned int)state->reg0503_raw,
                   (unsigned int)state->reg0504_raw);
    return XST_SUCCESS;
}

static int32_t ad9528_add_plan_write(LaserAd9528ClockProfilePlan *plan,
                                     uint16_t reg, uint8_t mask,
                                     uint8_t requested_value)
{
    LaserAd9528RegisterPlan *entry;
    uint8_t old_value;
    int32_t status;

    if (plan->write_count >= LASER_AD9528_PROFILE_PLAN_MAX_WRITES) {
        return XST_FAILURE;
    }
    status = laser_ad9528_read(reg, &old_value);
    if (status != XST_SUCCESS) {
        return status;
    }
    entry = &plan->writes[plan->write_count++];
    entry->reg = reg;
    entry->old_value = old_value;
    entry->mask = mask;
    entry->value = requested_value;
    entry->new_value = (uint8_t)((old_value & (uint8_t)~mask) |
                                 (requested_value & mask));
    entry->readback_mask = mask;
    entry->readback_value = (uint8_t)(entry->new_value & mask);
    return XST_SUCCESS;
}

static int ad9528_profile_name_is_vcxo_122p88(const char *name)
{
    static const char expected[] = "VCXO_122P88";
    size_t i;

    for (i = 0U; expected[i] != '\0' && name[i] != '\0'; ++i) {
        char actual = name[i];
        if (actual >= 'a' && actual <= 'z') {
            actual = (char)(actual - ('a' - 'A'));
        }
        if (actual != expected[i]) {
            return 0;
        }
    }
    return expected[i] == '\0' && name[i] == '\0';
}

int32_t laser_ad9528_plan_clock_profile(const char *profile_name,
                                         LaserAd9528ClockProfilePlan *plan)
{
    int32_t status;

    if (profile_name == 0 || plan == 0) {
        return XST_INVALID_PARAM;
    }
    if (!ad9528_profile_name_is_vcxo_122p88(profile_name)) {
        return XST_NO_FEATURE;
    }
    *plan = (LaserAd9528ClockProfilePlan){0};
    plan->profile_name = "VCXO_122P88";
    plan->configured_out0_hz = AD9528_REFERENCE_VCXO_HZ;
    plan->requires_io_update = 1U;
    plan->requires_sync = 0U;
    plan->affects_other_outputs = 0U;

#define AD9528_PLAN_WRITE(reg, mask, value) \
    do { \
        status = ad9528_add_plan_write(plan, (reg), (mask), (value)); \
        if (status != XST_SUCCESS) { return status; } \
    } while (0)
    AD9528_PLAN_WRITE(AD9528_PLL1_CTRL0_REG, 0x05U,
                      AD9528_PLL1_OSC_IN_DIFF_EN);
    AD9528_PLAN_WRITE(AD9528_PLL1_CTRL1_REG, AD9528_PLL1_BYPASS_BITS,
                      AD9528_PLL1_BYPASS_BITS);
    AD9528_PLAN_WRITE(AD9528_OUT0_CTRL_REG, AD9528_OUT_SOURCE_MASK,
                      AD9528_OUT_SOURCE_VCXO);
    AD9528_PLAN_WRITE(AD9528_OUT0_DRIVER_REG, AD9528_OUT_DRIVER_MASK,
                      AD9528_OUT_DRIVER_LVDS);
    AD9528_PLAN_WRITE(AD9528_OUT0_DIVIDER_REG, 0xFFU,
                      AD9528_OUT_DIVIDER_1);
    AD9528_PLAN_WRITE(AD9528_CHANNEL_PD0_REG, 0x01U, 0x00U);
    AD9528_PLAN_WRITE(AD9528_GLOBAL_PD_REG, AD9528_PD_PLL1_PLL2_MASK,
                      AD9528_PD_PLL1_PLL2);
#undef AD9528_PLAN_WRITE
    return XST_SUCCESS;
}

int32_t laser_ad9528_format_clock_profile_plan(
    char *buffer, size_t buffer_size, const LaserAd9528ClockProfilePlan *plan)
{
    size_t used;
    uint8_t i;

    if (buffer == 0 || buffer_size == 0U || plan == 0) {
        return XST_INVALID_PARAM;
    }
    used = (size_t)snprintf(buffer, buffer_size,
                            "OK AD9528_PROFILE_PLAN profile=%s out0_hz=%lu writes=%u io_update=%u sync=%u affects_other_outputs=%u tx=",
                            plan->profile_name,
                            (unsigned long)plan->configured_out0_hz,
                            (unsigned int)plan->write_count,
                            (unsigned int)plan->requires_io_update,
                            (unsigned int)plan->requires_sync,
                            (unsigned int)plan->affects_other_outputs);
    for (i = 0U; i < plan->write_count && used < buffer_size; ++i) {
        const LaserAd9528RegisterPlan *entry = &plan->writes[i];
        int written = snprintf(buffer + used, buffer_size - used,
                               "%sreg=%04x/old=%02x/mask=%02x/value=%02x/new=%02x/readback_mask=%02x/readback_expected=%02x",
                               i == 0U ? "" : ",",
                               (unsigned int)entry->reg,
                               (unsigned int)entry->old_value,
                               (unsigned int)entry->mask,
                               (unsigned int)entry->value,
                               (unsigned int)entry->new_value,
                               (unsigned int)entry->readback_mask,
                               (unsigned int)entry->readback_value);
        if (written < 0) {
            return XST_FAILURE;
        }
        used += (size_t)written;
    }
    return used < buffer_size ? XST_SUCCESS : XST_FAILURE;
}
