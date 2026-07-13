#include "laser_ad9528.h"
#include "laser_hw.h"
#include <stdio.h>
#include <string.h>
#include "sleep.h"
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
#define AD9528_OUT0_LDO_STATUS_REG     0x0503U
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
#define AD9528_IO_UPDATE_REG           0x000FU
#define AD9528_IO_UPDATE_ENABLE        0x01U
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
    uint8_t product_id = 0U;
    uint8_t revision = 0U;
    uint8_t vendor_id = 0U;

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
    AD9528_DUMP_READ(AD9528_OUT0_LDO_STATUS_REG, 1U, reg0503_raw);
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

typedef struct {
    uint16_t first;
    uint16_t last;
} LaserAd9528ReadRange;

int32_t laser_ad9528_dump_full_readonly(void)
{
    static const LaserAd9528ReadRange ranges[] = {
        {0x0000U, 0x000FU},
        {0x0100U, 0x010AU},
        {0x0200U, 0x0208U},
        {0x0300U, 0x032EU},
        {0x0400U, 0x0403U},
        {0x0500U, 0x0508U}
    };
    uint8_t product_id = 0U;
    uint8_t revision = 0U;
    uint8_t vendor_id = 0U;
    uint32_t range_index;
    int32_t status;

    if (!ad9528_initialized) {
        return XST_FAILURE;
    }
    status = laser_ad9528_identify(&product_id, &revision, &vendor_id);
    if (status != XST_SUCCESS) {
        return status;
    }

    ad9528_last_read_error_reg = 0U;
    xil_printf("AD9528_FULL_DUMP_BEGIN readonly=1 ranges=0000-000f,0100-010a,0200-0208,0300-032e,0400-0403,0500-0508\r\n");
    for (range_index = 0U;
         range_index < (uint32_t)(sizeof(ranges) / sizeof(ranges[0]));
         ++range_index) {
        uint16_t reg;
        for (reg = ranges[range_index].first;
             reg <= ranges[range_index].last;
             ++reg) {
            uint8_t value = 0U;
            status = laser_ad9528_read(reg, &value);
            if (status != XST_SUCCESS) {
                ad9528_last_read_error_reg = reg;
                xil_printf("AD9528_FULL_DUMP_ERROR addr=0x%04x status=%ld\r\n",
                           (unsigned int)reg, (long)status);
                return status;
            }
            xil_printf("AD9528_REG addr=0x%04x value=0x%02x\r\n",
                       (unsigned int)reg, (unsigned int)value);
        }
    }
    xil_printf("AD9528_FULL_DUMP_END readonly=1\r\n");
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
                                     uint8_t requested_value,
                                     const char *field_description,
                                     uint8_t shared_resource)
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
    entry->field_description = field_description;
    entry->shared_resource = shared_resource;
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
    uint8_t product_id;
    uint8_t revision;
    uint8_t vendor_id;
    uint8_t reg0503;
    uint8_t reg0501;
    uint8_t reg0500;

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
    plan->affects_out0 = 1U;
    plan->affects_shared_clock_tree = 1U;
    plan->may_affect_other_outputs = 1U;
    plan->directly_modifies_other_output_channels = 0U;
    plan->requires_pll1_lock = 0U;
    plan->requires_pll2_lock = 0U;

    status = laser_ad9528_identify(&product_id, &revision, &vendor_id);
    if (status != XST_SUCCESS) {
        return status;
    }
    plan->spi_identity_valid = 1U;
    status = laser_ad9528_read(AD9528_OUT0_LDO_STATUS_REG, &reg0503);
    if (status != XST_SUCCESS) return status;
    status = laser_ad9528_read(AD9528_CHANNEL_PD0_REG, &reg0501);
    if (status != XST_SUCCESS) return status;
    status = laser_ad9528_read(AD9528_GLOBAL_PD_REG, &reg0500);
    if (status != XST_SUCCESS) return status;
    plan->out0_ldo_enabled = ((reg0503 & 0x01U) == 0x01U);
    plan->out0_channel_enabled = ((reg0501 & 0x01U) == 0U);
    plan->chip_enabled = ((reg0500 & 0x01U) == 0U);
    plan->clock_distribution_enabled = ((reg0500 & 0x02U) == 0U);

#define AD9528_PLAN_WRITE(reg, mask, value, description, shared) \
    do { \
        status = ad9528_add_plan_write(plan, (reg), (mask), (value), \
                                       (description), (shared)); \
        if (status != XST_SUCCESS) { return status; } \
    } while (0)
    AD9528_PLAN_WRITE(AD9528_PLL1_CTRL0_REG, 0x05U,
                      AD9528_PLL1_OSC_IN_DIFF_EN,
                      "VCXO_DIFFERENTIAL_RECEIVER_ENABLE", 1U);
    AD9528_PLAN_WRITE(AD9528_PLL1_CTRL1_REG, AD9528_PLL1_BYPASS_BITS,
                      AD9528_PLL1_BYPASS_BITS,
                      "PLL1_REFA_REFB_FEEDBACK_BYPASS", 1U);
    AD9528_PLAN_WRITE(AD9528_OUT0_CTRL_REG, AD9528_OUT_SOURCE_MASK,
                      AD9528_OUT_SOURCE_VCXO,
                      "OUT0_SOURCE_VCXO", 0U);
    AD9528_PLAN_WRITE(AD9528_OUT0_DRIVER_REG, AD9528_OUT_DRIVER_MASK,
                      AD9528_OUT_DRIVER_LVDS,
                      "OUT0_DRIVER_LVDS", 0U);
    AD9528_PLAN_WRITE(AD9528_OUT0_DIVIDER_REG, 0xFFU,
                      AD9528_OUT_DIVIDER_1,
                      "OUT0_DIVIDE_BY_1", 0U);
    AD9528_PLAN_WRITE(AD9528_CHANNEL_PD0_REG, 0x01U, 0x00U,
                      "OUT0_CHANNEL_POWER_UP", 0U);
    AD9528_PLAN_WRITE(AD9528_GLOBAL_PD_REG, AD9528_PD_PLL1_PLL2_MASK,
                      AD9528_PD_PLL1_PLL2,
                      "PLL1_PLL2_GLOBAL_POWER_DOWN", 1U);
#undef AD9528_PLAN_WRITE
    return XST_SUCCESS;
}

int32_t laser_ad9528_format_clock_profile_plan(
    char *buffer, size_t buffer_size, const LaserAd9528ClockProfilePlan *plan)
{
    if (buffer == 0 || buffer_size == 0U || plan == 0) {
        return XST_INVALID_PARAM;
    }
    (void)snprintf(buffer, buffer_size,
                   "OK AD9528_PROFILE_PLAN profile=%s profile_state=PLANNED_ONLY configured_out0_hz=%lu runtime_active_likely=0 measured_out0_hz=UNKNOWN writes=%u requires_io_update=%u requires_sync=%u requires_pll1_lock=%u requires_pll2_lock=%u affects_out0=%u affects_shared_clock_tree=%u may_affect_other_outputs=%u directly_modifies_other_output_channels=%u board_verified=0 preconditions=SPI_ID:%u,BOARD_VCXO_HZ:122880000,BOARD_VCXO_SOURCE:DIFFERENTIAL,ASSUMPTION_CONFIDENCE:BOARD_SCHEMATIC_AND_MANUAL_ONLY,OUT0_LDO:%u,OUT0_CHANNEL:%u,CHIP:%u,CLOCK_DISTRIBUTION:%u planned_postconditions=MASKED_READBACK_MATCH,OUT0_SOURCE_VCXO,OUT0_DIV1,OUT0_LVDS,OUT0_CHANNEL_ENABLED,OUT0_LDO_ENABLED,CLOCK_DISTRIBUTION_ENABLED,PLL1_POWER_DOWN,PLL2_POWER_DOWN,VCXO_STATUS_VALID,CONFIGURED_122880000,MEASURED_UNKNOWN",
                   plan->profile_name,
                   (unsigned long)plan->configured_out0_hz,
                   (unsigned int)plan->write_count,
                   (unsigned int)plan->requires_io_update,
                   (unsigned int)plan->requires_sync,
                   (unsigned int)plan->requires_pll1_lock,
                   (unsigned int)plan->requires_pll2_lock,
                   (unsigned int)plan->affects_out0,
                   (unsigned int)plan->affects_shared_clock_tree,
                   (unsigned int)plan->may_affect_other_outputs,
                   (unsigned int)plan->directly_modifies_other_output_channels,
                   (unsigned int)plan->spi_identity_valid,
                   (unsigned int)plan->out0_ldo_enabled,
                   (unsigned int)plan->out0_channel_enabled,
                   (unsigned int)plan->chip_enabled,
                   (unsigned int)plan->clock_distribution_enabled);
    return XST_SUCCESS;
}

int32_t laser_ad9528_format_clock_profile_plan_transaction(
    char *buffer, size_t buffer_size, const LaserAd9528ClockProfilePlan *plan,
    uint32_t transaction_index)
{
    const LaserAd9528RegisterPlan *entry;

    if (buffer == 0 || buffer_size == 0U || plan == 0 ||
        transaction_index >= plan->write_count) {
        return XST_INVALID_PARAM;
    }
    entry = &plan->writes[transaction_index];
    (void)snprintf(buffer, buffer_size,
                   "OK AD9528_PROFILE_PLAN_TRANSACTION profile=%s profile_state=PLANNED_ONLY index=%lu reg=%04x old=%02x mask=%02x value=%02x new=%02x readback_mask=%02x readback_expected=%02x field=%s shared_resource=%u read_only=1",
                   plan->profile_name,
                   (unsigned long)transaction_index,
                   (unsigned int)entry->reg,
                   (unsigned int)entry->old_value,
                   (unsigned int)entry->mask,
                   (unsigned int)entry->value,
                   (unsigned int)entry->new_value,
                   (unsigned int)entry->readback_mask,
                   (unsigned int)entry->readback_value,
                   entry->field_description,
                   (unsigned int)entry->shared_resource);
    return XST_SUCCESS;
}

typedef struct {
    LaserAd9528CandidateStatus status;
    uint8_t snapshot[LASER_AD9528_PROFILE_PLAN_MAX_WRITES];
    uint8_t snapshot_status_0508;
    uint8_t snapshot_status_0509;
    LaserAd9528CandidateState snapshot_candidate_state;
    uint32_t snapshot_configured_out0_hz;
    uint8_t busy;
    uint8_t applied;
} LaserAd9528CandidateContext;

static LaserAd9528CandidateContext ad9528_candidate = {
    .status = {
        .state = LASER_AD9528_CANDIDATE_IDLE,
        .last_error = LASER_AD9528_CANDIDATE_ERROR_NONE
    }
};

static void ad9528_candidate_set_failure(LaserAd9528CandidateError error,
                                         uint16_t reg, uint8_t expected,
                                         uint8_t actual)
{
    ad9528_candidate.status.last_error = error;
    ad9528_candidate.status.failed_reg = reg;
    ad9528_candidate.status.failed_expected = expected;
    ad9528_candidate.status.failed_actual = actual;
    ad9528_candidate.status.runtime_active_likely = 0U;
    ad9528_candidate.status.readback_ok = 0U;
    ad9528_candidate.status.vcxo_status_ok = 0U;
    ad9528_candidate.status.state = LASER_AD9528_CANDIDATE_ERROR;
}

static int32_t ad9528_candidate_rollback(
    const LaserAd9528ClockProfilePlan *plan, uint8_t final_restored_state)
{
    uint8_t i;
    uint8_t readback;
    int32_t status;
    uint8_t rollback_ok = 1U;

    ad9528_candidate.status.state = LASER_AD9528_CANDIDATE_ROLLBACK;
    ad9528_candidate.status.rollback_attempted = 1U;
    ad9528_candidate.status.rollback_success = 0U;

    for (i = 0U; i < plan->write_count; ++i) {
        xil_printf("TRACE AD9528_CANDIDATE ROLLBACK_WRITE index=%u reg=0x%04x value=0x%02x\r\n",
                   (unsigned int)i,
                   (unsigned int)plan->writes[i].reg,
                   (unsigned int)ad9528_candidate.snapshot[i]);
        status = laser_ad9528_write(plan->writes[i].reg,
                                    ad9528_candidate.snapshot[i]);
        if (status != XST_SUCCESS) {
            rollback_ok = 0U;
        }
    }
    xil_printf("TRACE AD9528_CANDIDATE ROLLBACK_IO_UPDATE reg=0x%04x value=0x%02x\r\n",
               AD9528_IO_UPDATE_REG, AD9528_IO_UPDATE_ENABLE);
    status = laser_ad9528_write(AD9528_IO_UPDATE_REG,
                                AD9528_IO_UPDATE_ENABLE);
    if (status != XST_SUCCESS) {
        rollback_ok = 0U;
    } else {
        ad9528_candidate.status.io_update_writes++;
    }
    usleep(10000U);
    for (i = 0U; i < plan->write_count; ++i) {
        xil_printf("TRACE AD9528_CANDIDATE ROLLBACK_POST_READ index=%u reg=0x%04x\r\n",
                   (unsigned int)i,
                   (unsigned int)plan->writes[i].reg);
        status = laser_ad9528_read(plan->writes[i].reg, &readback);
        if (status != XST_SUCCESS ||
            readback != ad9528_candidate.snapshot[i]) {
            rollback_ok = 0U;
        }
    }
    if (!rollback_ok) {
        ad9528_candidate.status.last_error =
            LASER_AD9528_CANDIDATE_ERROR_ROLLBACK_FAILED;
        ad9528_candidate.status.state = LASER_AD9528_CANDIDATE_ERROR;
        ad9528_candidate.status.rollback_success = 0U;
        ad9528_candidate.applied = 0U;
        ad9528_candidate.status.snapshot_valid = 0U;
        return XST_FAILURE;
    }
    ad9528_candidate.status.rollback_success = 1U;
    ad9528_candidate.status.configured_out0_hz =
        ad9528_candidate.snapshot_configured_out0_hz;
    ad9528_candidate.status.runtime_active_likely = 0U;
    ad9528_candidate.applied = 0U;
    ad9528_candidate.status.snapshot_valid = 0U;
    if (final_restored_state) {
        ad9528_candidate.status.state = LASER_AD9528_CANDIDATE_RESTORED;
        ad9528_candidate.status.last_error =
            LASER_AD9528_CANDIDATE_ERROR_NONE;
        ad9528_candidate.status.readback_ok = 1U;
        ad9528_candidate.status.vcxo_status_ok = 0U;
    }
    return XST_SUCCESS;
}

int32_t laser_ad9528_candidate_set(const char *profile_name)
{
    static const uint8_t expected_old_masked[] = {
        0x00U, 0x00U, 0x00U, 0x00U, 0x04U, 0x00U, 0x00U
    };
    LaserAd9528ClockProfilePlan plan;
    LaserAd9528CandidateError original_error;
    uint8_t product_id;
    uint8_t revision;
    uint8_t vendor_id;
    uint8_t serial_cfg;
    uint8_t reg0503;
    uint8_t reg0501;
    uint8_t reg0500;
    uint8_t reg0508;
    uint8_t reg0509;
    uint8_t current;
    uint8_t readback;
    uint8_t i;
    uint8_t writes_started = 0U;
    LaserAd9528CandidateState previous_candidate_state;
    uint32_t previous_configured_out0_hz;
    int32_t status;

    if (profile_name == 0) {
        return XST_INVALID_PARAM;
    }
    if (ad9528_candidate.busy) {
        ad9528_candidate_set_failure(LASER_AD9528_CANDIDATE_ERROR_BUSY,
                                     0U, 0U, 0U);
        return XST_FAILURE;
    }
    if (!ad9528_profile_name_is_vcxo_122p88(profile_name)) {
        ad9528_candidate_set_failure(
            LASER_AD9528_CANDIDATE_ERROR_UNSUPPORTED_PROFILE,
            0U, 0U, 0U);
        return XST_NO_FEATURE;
    }

    ad9528_candidate.busy = 1U;
    previous_candidate_state = ad9528_candidate.status.state;
    previous_configured_out0_hz =
        ad9528_candidate.status.configured_out0_hz;
    ad9528_candidate.status.state = LASER_AD9528_CANDIDATE_PRECHECK;
    ad9528_candidate.status.last_error = LASER_AD9528_CANDIDATE_ERROR_NONE;
    ad9528_candidate.status.failed_reg = 0U;
    ad9528_candidate.status.failed_expected = 0U;
    ad9528_candidate.status.failed_actual = 0U;
    ad9528_candidate.status.config_writes = 0U;
    ad9528_candidate.status.io_update_writes = 0U;
    ad9528_candidate.status.rollback_attempted = 0U;
    ad9528_candidate.status.rollback_success = 0U;

    status = laser_ad9528_identify(&product_id, &revision, &vendor_id);
    if (status != XST_SUCCESS) {
        ad9528_candidate_set_failure(
            LASER_AD9528_CANDIDATE_ERROR_IDENTITY_MISMATCH,
            AD9528_PRODUCT_ID_REG, AD9528_PRODUCT_ID_EXPECTED, product_id);
        goto done;
    }
    status = laser_ad9528_read(AD9528_SERIAL_PORT_CONFIG_REG, &serial_cfg);
    if (status != XST_SUCCESS) {
        ad9528_candidate_set_failure(LASER_AD9528_CANDIDATE_ERROR_SPI_READ,
                                     AD9528_SERIAL_PORT_CONFIG_REG, 0U, 0U);
        goto done;
    }
    status = laser_ad9528_read(AD9528_OUT0_LDO_STATUS_REG, &reg0503);
    if (status != XST_SUCCESS) goto precheck_read_error;
    status = laser_ad9528_read(AD9528_CHANNEL_PD0_REG, &reg0501);
    if (status != XST_SUCCESS) goto precheck_read_error;
    status = laser_ad9528_read(AD9528_GLOBAL_PD_REG, &reg0500);
    if (status != XST_SUCCESS) goto precheck_read_error;
    if ((serial_cfg & AD9528_SERIAL_PORT_4WIRE) != AD9528_SERIAL_PORT_4WIRE) {
        ad9528_candidate_set_failure(
            LASER_AD9528_CANDIDATE_ERROR_PRECONDITION_MISMATCH,
            AD9528_SERIAL_PORT_CONFIG_REG, AD9528_SERIAL_PORT_4WIRE,
            (uint8_t)(serial_cfg & AD9528_SERIAL_PORT_4WIRE));
        goto done;
    }
    if ((reg0503 & 0x01U) == 0U) {
        ad9528_candidate_set_failure(
            LASER_AD9528_CANDIDATE_ERROR_PRECONDITION_MISMATCH,
            AD9528_OUT0_LDO_STATUS_REG, 0x01U, (uint8_t)(reg0503 & 0x01U));
        goto done;
    }
    if ((reg0501 & 0x01U) != 0U) {
        ad9528_candidate_set_failure(
            LASER_AD9528_CANDIDATE_ERROR_PRECONDITION_MISMATCH,
            AD9528_CHANNEL_PD0_REG, 0x00U, (uint8_t)(reg0501 & 0x01U));
        goto done;
    }
    if ((reg0500 & 0x03U) != 0U) {
        ad9528_candidate_set_failure(
            LASER_AD9528_CANDIDATE_ERROR_PRECONDITION_MISMATCH,
            AD9528_GLOBAL_PD_REG, 0x00U, (uint8_t)(reg0500 & 0x03U));
        goto done;
    }

    status = laser_ad9528_plan_clock_profile(profile_name, &plan);
    if (status != XST_SUCCESS) {
        ad9528_candidate_set_failure(LASER_AD9528_CANDIDATE_ERROR_SPI_READ,
                                     laser_ad9528_last_read_error_reg(), 0U, 0U);
        goto done;
    }
    for (i = 0U; i < plan.write_count; ++i) {
        if ((plan.writes[i].old_value & plan.writes[i].mask) !=
            (expected_old_masked[i] & plan.writes[i].mask)) {
            ad9528_candidate_set_failure(
                LASER_AD9528_CANDIDATE_ERROR_PRECONDITION_MISMATCH,
                plan.writes[i].reg,
                (uint8_t)(expected_old_masked[i] & plan.writes[i].mask),
                (uint8_t)(plan.writes[i].old_value & plan.writes[i].mask));
            goto done;
        }
    }

    ad9528_candidate.status.state = LASER_AD9528_CANDIDATE_SNAPSHOT;
    for (i = 0U; i < plan.write_count; ++i) {
        status = laser_ad9528_read(plan.writes[i].reg,
                                   &ad9528_candidate.snapshot[i]);
        if (status != XST_SUCCESS) {
            ad9528_candidate_set_failure(LASER_AD9528_CANDIDATE_ERROR_SPI_READ,
                                         plan.writes[i].reg, 0U, 0U);
            goto done;
        }
    }
    status = laser_ad9528_read(0x0508U,
                               &ad9528_candidate.snapshot_status_0508);
    if (status != XST_SUCCESS) goto snapshot_read_error;
    status = laser_ad9528_read(0x0509U,
                               &ad9528_candidate.snapshot_status_0509);
    if (status != XST_SUCCESS) goto snapshot_read_error;
    ad9528_candidate.snapshot_candidate_state = previous_candidate_state;
    ad9528_candidate.snapshot_configured_out0_hz =
        previous_configured_out0_hz;
    ad9528_candidate.status.snapshot_valid = 1U;

    ad9528_candidate.status.state = LASER_AD9528_CANDIDATE_PROGRAM;
    for (i = 0U; i < plan.write_count; ++i) {
        uint8_t new_value;
        status = laser_ad9528_read(plan.writes[i].reg, &current);
        if (status != XST_SUCCESS) {
            ad9528_candidate_set_failure(LASER_AD9528_CANDIDATE_ERROR_SPI_READ,
                                         plan.writes[i].reg, 0U, 0U);
            goto rollback;
        }
        if ((current & plan.writes[i].mask) !=
            (expected_old_masked[i] & plan.writes[i].mask)) {
            ad9528_candidate_set_failure(
                LASER_AD9528_CANDIDATE_ERROR_PRECONDITION_MISMATCH,
                plan.writes[i].reg,
                (uint8_t)(expected_old_masked[i] & plan.writes[i].mask),
                (uint8_t)(current & plan.writes[i].mask));
            goto rollback;
        }
        new_value = (uint8_t)((current & (uint8_t)~plan.writes[i].mask) |
                              (plan.writes[i].value & plan.writes[i].mask));
        xil_printf("TRACE AD9528_CANDIDATE WRITE index=%u reg=0x%04x current=0x%02x mask=0x%02x value=0x%02x new=0x%02x\r\n",
                   (unsigned int)i,
                   (unsigned int)plan.writes[i].reg,
                   (unsigned int)current,
                   (unsigned int)plan.writes[i].mask,
                   (unsigned int)plan.writes[i].value,
                   (unsigned int)new_value);
        /* A failed SPI return cannot prove that no device write occurred. */
        writes_started = 1U;
        status = laser_ad9528_write(plan.writes[i].reg, new_value);
        if (status != XST_SUCCESS) {
            ad9528_candidate_set_failure(LASER_AD9528_CANDIDATE_ERROR_SPI_WRITE,
                                         plan.writes[i].reg, new_value, 0U);
            goto rollback;
        }
        ad9528_candidate.status.config_writes++;
    }

    ad9528_candidate.status.state = LASER_AD9528_CANDIDATE_IO_UPDATE;
    xil_printf("TRACE AD9528_CANDIDATE IO_UPDATE reg=0x%04x value=0x%02x\r\n",
               AD9528_IO_UPDATE_REG, AD9528_IO_UPDATE_ENABLE);
    status = laser_ad9528_write(AD9528_IO_UPDATE_REG,
                                AD9528_IO_UPDATE_ENABLE);
    if (status != XST_SUCCESS) {
        ad9528_candidate_set_failure(LASER_AD9528_CANDIDATE_ERROR_IO_UPDATE,
                                     AD9528_IO_UPDATE_REG,
                                     AD9528_IO_UPDATE_ENABLE, 0U);
        goto rollback;
    }
    ad9528_candidate.status.io_update_writes = 1U;
    usleep(10000U);

    ad9528_candidate.status.state = LASER_AD9528_CANDIDATE_POST_READBACK;
    for (i = 0U; i < plan.write_count; ++i) {
        xil_printf("TRACE AD9528_CANDIDATE POST_READ index=%u reg=0x%04x expected_masked=0x%02x mask=0x%02x\r\n",
                   (unsigned int)i,
                   (unsigned int)plan.writes[i].reg,
                   (unsigned int)plan.writes[i].readback_value,
                   (unsigned int)plan.writes[i].readback_mask);
        status = laser_ad9528_read(plan.writes[i].reg, &readback);
        if (status != XST_SUCCESS ||
            (readback & plan.writes[i].readback_mask) !=
            (plan.writes[i].readback_value & plan.writes[i].readback_mask)) {
            ad9528_candidate_set_failure(
                LASER_AD9528_CANDIDATE_ERROR_POST_READBACK,
                plan.writes[i].reg, plan.writes[i].readback_value, readback);
            goto rollback;
        }
    }
    status = laser_ad9528_read(AD9528_OUT0_LDO_STATUS_REG, &reg0503);
    if (status != XST_SUCCESS) goto post_read_error;
    status = laser_ad9528_read(AD9528_CHANNEL_PD0_REG, &reg0501);
    if (status != XST_SUCCESS) goto post_read_error;
    status = laser_ad9528_read(AD9528_GLOBAL_PD_REG, &reg0500);
    if (status != XST_SUCCESS) goto post_read_error;
    status = laser_ad9528_read(0x0508U, &reg0508);
    if (status != XST_SUCCESS) goto post_read_error;
    status = laser_ad9528_read(0x0509U, &reg0509);
    if (status != XST_SUCCESS) goto post_read_error;
    (void)reg0509;
    if ((reg0503 & 0x01U) == 0U || (reg0501 & 0x01U) != 0U ||
        (reg0500 & 0x0FU) != AD9528_PD_PLL1_PLL2 ||
        (reg0508 & 0x20U) == 0U) {
        LaserAd9528CandidateError error =
            ((reg0508 & 0x20U) == 0U) ?
            LASER_AD9528_CANDIDATE_ERROR_VCXO_STATUS :
            LASER_AD9528_CANDIDATE_ERROR_POST_READBACK;
        ad9528_candidate_set_failure(error, AD9528_READBACK_LAST_REG,
                                     0x20U, reg0508);
        goto rollback;
    }

    ad9528_candidate.status.state =
        LASER_AD9528_CANDIDATE_READY_UNMEASURED;
    ad9528_candidate.status.configured_out0_hz = AD9528_REFERENCE_VCXO_HZ;
    ad9528_candidate.status.runtime_active_likely = 1U;
    ad9528_candidate.status.readback_ok = 1U;
    ad9528_candidate.status.vcxo_status_ok = 1U;
    ad9528_candidate.status.last_error = LASER_AD9528_CANDIDATE_ERROR_NONE;
    ad9528_candidate.applied = 1U;
    status = XST_SUCCESS;
    goto done;

precheck_read_error:
    ad9528_candidate_set_failure(LASER_AD9528_CANDIDATE_ERROR_SPI_READ,
                                 laser_ad9528_last_read_error_reg(), 0U, 0U);
    goto done;
snapshot_read_error:
    ad9528_candidate_set_failure(LASER_AD9528_CANDIDATE_ERROR_SPI_READ,
                                 laser_ad9528_last_read_error_reg(), 0U, 0U);
    goto done;
post_read_error:
    ad9528_candidate_set_failure(LASER_AD9528_CANDIDATE_ERROR_SPI_READ,
                                 laser_ad9528_last_read_error_reg(), 0U, 0U);
rollback:
    original_error = ad9528_candidate.status.last_error;
    if (writes_started || ad9528_candidate.status.io_update_writes != 0U) {
        if (ad9528_candidate_rollback(&plan, 0U) == XST_SUCCESS) {
            ad9528_candidate.status.state = LASER_AD9528_CANDIDATE_ERROR;
            ad9528_candidate.status.last_error = original_error;
        }
    }
    status = XST_FAILURE;
done:
    ad9528_candidate.busy = 0U;
    return status;
}

int32_t laser_ad9528_candidate_restore(void)
{
    LaserAd9528ClockProfilePlan plan;
    int32_t status;

    if (ad9528_candidate.busy) {
        return XST_FAILURE;
    }
    if (!ad9528_candidate.status.snapshot_valid || !ad9528_candidate.applied) {
        ad9528_candidate_set_failure(
            LASER_AD9528_CANDIDATE_ERROR_NO_ACTIVE_CANDIDATE,
            0U, 0U, 0U);
        return XST_FAILURE;
    }
    status = laser_ad9528_plan_clock_profile("VCXO_122P88", &plan);
    if (status != XST_SUCCESS) {
        ad9528_candidate_set_failure(LASER_AD9528_CANDIDATE_ERROR_SPI_READ,
                                     laser_ad9528_last_read_error_reg(), 0U, 0U);
        return status;
    }
    ad9528_candidate.busy = 1U;
    ad9528_candidate.status.config_writes = 0U;
    ad9528_candidate.status.io_update_writes = 0U;
    ad9528_candidate.status.rollback_attempted = 0U;
    ad9528_candidate.status.rollback_success = 0U;
    status = ad9528_candidate_rollback(&plan, 1U);
    ad9528_candidate.busy = 0U;
    return status;
}

void laser_ad9528_get_candidate_status(LaserAd9528CandidateStatus *status)
{
    if (status != 0) {
        *status = ad9528_candidate.status;
    }
}

const char *laser_ad9528_candidate_state_name(LaserAd9528CandidateState state)
{
    switch (state) {
    case LASER_AD9528_CANDIDATE_IDLE: return "IDLE";
    case LASER_AD9528_CANDIDATE_PRECHECK: return "PRECHECK";
    case LASER_AD9528_CANDIDATE_SNAPSHOT: return "SNAPSHOT";
    case LASER_AD9528_CANDIDATE_PROGRAM: return "PROGRAM";
    case LASER_AD9528_CANDIDATE_BUFFER_READBACK: return "BUFFER_READBACK";
    case LASER_AD9528_CANDIDATE_IO_UPDATE: return "IO_UPDATE";
    case LASER_AD9528_CANDIDATE_POST_READBACK: return "POST_READBACK";
    case LASER_AD9528_CANDIDATE_READY_UNMEASURED: return "READY_UNMEASURED";
    case LASER_AD9528_CANDIDATE_ROLLBACK: return "ROLLBACK";
    case LASER_AD9528_CANDIDATE_RESTORED: return "RESTORED";
    case LASER_AD9528_CANDIDATE_ERROR: return "ERROR";
    default: return "UNKNOWN";
    }
}

const char *laser_ad9528_candidate_error_name(LaserAd9528CandidateError error)
{
    switch (error) {
    case LASER_AD9528_CANDIDATE_ERROR_NONE: return "NONE";
    case LASER_AD9528_CANDIDATE_ERROR_BUSY: return "BUSY";
    case LASER_AD9528_CANDIDATE_ERROR_UNSUPPORTED_PROFILE: return "UNSUPPORTED_PROFILE";
    case LASER_AD9528_CANDIDATE_ERROR_IDENTITY_MISMATCH: return "AD9528_IDENTITY_MISMATCH";
    case LASER_AD9528_CANDIDATE_ERROR_PRECONDITION_MISMATCH: return "AD9528_PRECONDITION_MISMATCH";
    case LASER_AD9528_CANDIDATE_ERROR_SPI_READ: return "SPI_READ_FAILED";
    case LASER_AD9528_CANDIDATE_ERROR_SPI_WRITE: return "SPI_WRITE_FAILED";
    case LASER_AD9528_CANDIDATE_ERROR_BUFFER_READBACK: return "BUFFER_READBACK_MISMATCH";
    case LASER_AD9528_CANDIDATE_ERROR_IO_UPDATE: return "IO_UPDATE_FAILED";
    case LASER_AD9528_CANDIDATE_ERROR_POST_READBACK: return "POST_READBACK_MISMATCH";
    case LASER_AD9528_CANDIDATE_ERROR_VCXO_STATUS: return "VCXO_STATUS_INVALID";
    case LASER_AD9528_CANDIDATE_ERROR_ROLLBACK_FAILED: return "ROLLBACK_FAILED";
    case LASER_AD9528_CANDIDATE_ERROR_NO_ACTIVE_CANDIDATE: return "NO_ACTIVE_CANDIDATE";
    default: return "UNKNOWN_ERROR";
    }
}

int32_t laser_ad9528_format_candidate_status(
    char *buffer, size_t buffer_size, const LaserAd9528CandidateStatus *status,
    const char *response_prefix)
{
    if (buffer == 0 || buffer_size == 0U || status == 0 ||
        response_prefix == 0) {
        return XST_INVALID_PARAM;
    }
    const char *rollback_state = status->rollback_attempted ?
        (status->rollback_success ? "SUCCESS" : "FAILED") : "NOT_ATTEMPTED";
    (void)snprintf(buffer, buffer_size,
                   "%s profile=VCXO_122P88 state=%s configured_out0_hz=%lu runtime_active_likely=%u vcxo_status_ok=%u readback_ok=%u applied_snapshot_valid=%u rollback_state=%s rollback_attempted=%u rollback_success=%u last_error=%s failed_reg=0x%04x expected=0x%02x actual=0x%02x config_writes=%u io_update_writes=%u pll1_lock_required=0 pll2_lock_required=0 affects_shared_clock_tree=1 may_affect_other_outputs=1 board_verified=0",
                   response_prefix,
                   laser_ad9528_candidate_state_name(status->state),
                   (unsigned long)status->configured_out0_hz,
                   (unsigned int)status->runtime_active_likely,
                   (unsigned int)status->vcxo_status_ok,
                   (unsigned int)status->readback_ok,
                   (unsigned int)status->snapshot_valid,
                   rollback_state,
                   (unsigned int)status->rollback_attempted,
                   (unsigned int)status->rollback_success,
                   laser_ad9528_candidate_error_name(status->last_error),
                   (unsigned int)status->failed_reg,
                   (unsigned int)status->failed_expected,
                   (unsigned int)status->failed_actual,
                   (unsigned int)status->config_writes,
                   (unsigned int)status->io_update_writes);
    return XST_SUCCESS;
}
