#include "laser_ad9528.h"
#include "laser_hw.h"
#include "xspips.h"
#include "xil_printf.h"
#include "xstatus.h"

static XSpiPs ad9528_spi;
static int ad9528_initialized;

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
