#include "laser_ad9528_measure.h"
#include "laser_hw.h"
#include "xgpio.h"
#include "xstatus.h"
#include <stdio.h>
#include <string.h>

static XGpio ad9528_measure_gpio;
static int ad9528_measure_initialized;
static uint8_t ad9528_measure_transition_pending;
static uint16_t ad9528_measure_transition_sequence;

static uint16_t laser_ad9528_measure_sequence(uint32_t status)
{
    return (uint16_t)((status & LASER_AD9528_MEASURE_STATUS_SEQUENCE_MASK) >>
                      LASER_AD9528_MEASURE_STATUS_SEQUENCE_SHIFT);
}

static uint8_t laser_ad9528_measure_version(uint32_t status)
{
    return (uint8_t)((status & LASER_AD9528_MEASURE_STATUS_VERSION_MASK) >>
                     LASER_AD9528_MEASURE_STATUS_VERSION_SHIFT);
}

int laser_ad9528_measure_init(void)
{
    int status = XGpio_Initialize(&ad9528_measure_gpio,
                                  LASER_AD9528_MEASURE_GPIO_DEVICE_ID);
    if (status != XST_SUCCESS) {
        ad9528_measure_initialized = 0;
        return status;
    }
    XGpio_SetDataDirection(&ad9528_measure_gpio,
                           LASER_AD9528_MEASURE_COUNT_CHANNEL, 0xffffffffU);
    XGpio_SetDataDirection(&ad9528_measure_gpio,
                           LASER_AD9528_MEASURE_STATUS_CHANNEL, 0xffffffffU);
    ad9528_measure_initialized = 1;
    ad9528_measure_transition_pending = 0U;
    return XST_SUCCESS;
}

int laser_ad9528_measure_mark_transition(void)
{
    uint32_t status;

    if (!ad9528_measure_initialized) {
        return XST_FAILURE;
    }
    status = XGpio_DiscreteRead(&ad9528_measure_gpio,
                                LASER_AD9528_MEASURE_STATUS_CHANNEL);
    ad9528_measure_transition_sequence = laser_ad9528_measure_sequence(status);
    ad9528_measure_transition_pending = 1U;
    return XST_SUCCESS;
}

int laser_ad9528_measure_read(LaserAd9528Measurement *measurement)
{
    uint32_t status_before;
    uint32_t status_after;
    uint32_t count;
    uint16_t sequence;
    uint32_t retry;

    if (measurement == NULL) {
        return XST_INVALID_PARAM;
    }
    memset(measurement, 0, sizeof(*measurement));
    measurement->state = LASER_AD9528_MEASUREMENT_READ_ERROR;
    if (!ad9528_measure_initialized) {
        return XST_FAILURE;
    }

    for (retry = 0U; retry < LASER_AD9528_MEASURE_MAX_RETRIES; ++retry) {
        status_before = XGpio_DiscreteRead(&ad9528_measure_gpio,
                                           LASER_AD9528_MEASURE_STATUS_CHANNEL);
        count = XGpio_DiscreteRead(&ad9528_measure_gpio,
                                   LASER_AD9528_MEASURE_COUNT_CHANNEL);
        status_after = XGpio_DiscreteRead(&ad9528_measure_gpio,
                                          LASER_AD9528_MEASURE_STATUS_CHANNEL);
        if (laser_ad9528_measure_sequence(status_before) !=
            laser_ad9528_measure_sequence(status_after)) {
            continue;
        }

        measurement->format_version = laser_ad9528_measure_version(status_after);
        if (measurement->format_version != LASER_AD9528_MEASURE_FORMAT_VERSION) {
            measurement->state = LASER_AD9528_MEASUREMENT_FORMAT_ERROR;
            return XST_FAILURE;
        }
        sequence = laser_ad9528_measure_sequence(status_after);
        measurement->sequence = sequence;
        measurement->alive = (status_after &
            LASER_AD9528_MEASURE_STATUS_ALIVE_MASK) != 0U;
        measurement->in_range = (status_after &
            LASER_AD9528_MEASURE_STATUS_IN_RANGE_MASK) != 0U;
        measurement->valid = (status_after &
            LASER_AD9528_MEASURE_STATUS_VALID_MASK) != 0U;
        measurement->raw_count = count;

        if (ad9528_measure_transition_pending) {
            if (sequence == ad9528_measure_transition_sequence) {
                measurement->valid = 0U;
            } else {
                ad9528_measure_transition_pending = 0U;
            }
        }

        if (!measurement->valid) {
            measurement->state = LASER_AD9528_MEASUREMENT_NOT_VALID;
            measurement->raw_count = 0U;
            return XST_SUCCESS;
        }
        measurement->odiv2_hz = (uint64_t)measurement->raw_count * 1000ULL;
        measurement->out0_hz = measurement->odiv2_hz *
                                LASER_AD9528_MEASURE_ODIV2_FACTOR;
        measurement->state = measurement->in_range ?
            LASER_AD9528_MEASUREMENT_VALID_IN_RANGE :
            LASER_AD9528_MEASUREMENT_VALID_OUT_OF_RANGE;
        return XST_SUCCESS;
    }

    measurement->state = LASER_AD9528_MEASUREMENT_READ_ERROR;
    return XST_FAILURE;
}

const char *laser_ad9528_measure_state_name(LaserAd9528MeasurementState state)
{
    switch (state) {
    case LASER_AD9528_MEASUREMENT_VALID_IN_RANGE: return "VALID_IN_RANGE";
    case LASER_AD9528_MEASUREMENT_VALID_OUT_OF_RANGE: return "VALID_OUT_OF_RANGE";
    case LASER_AD9528_MEASUREMENT_NOT_VALID: return "NOT_VALID";
    case LASER_AD9528_MEASUREMENT_READ_ERROR: return "READ_ERROR";
    case LASER_AD9528_MEASUREMENT_FORMAT_ERROR: return "FORMAT_ERROR";
    default: return "UNKNOWN";
    }
}

int laser_ad9528_measure_format_udp(char *buffer, size_t buffer_size,
                                    const LaserAd9528Measurement *measurement,
                                    int read_status)
{
    if (buffer == NULL || buffer_size == 0U || measurement == NULL) {
        return XST_INVALID_PARAM;
    }
    if (read_status != XST_SUCCESS) {
        return snprintf(buffer, buffer_size,
                        "ERROR AD9528_MEASURE state=%s valid=0 in_range=0 alive=0 sequence=UNKNOWN odiv2_count=UNKNOWN measured_odiv2_hz=UNKNOWN measured_out0_hz=UNKNOWN window_us=%u",
                        laser_ad9528_measure_state_name(measurement->state),
                        (unsigned int)LASER_AD9528_MEASURE_WINDOW_US);
    }
    if (!measurement->valid) {
        return snprintf(buffer, buffer_size,
                        "OK AD9528_MEASURE state=%s valid=0 in_range=%u alive=%u sequence=%u odiv2_count=UNKNOWN measured_odiv2_hz=UNKNOWN measured_out0_hz=UNKNOWN window_us=%u",
                        laser_ad9528_measure_state_name(measurement->state),
                        (unsigned int)measurement->in_range,
                        (unsigned int)measurement->alive,
                        (unsigned int)measurement->sequence,
                        (unsigned int)LASER_AD9528_MEASURE_WINDOW_US);
    }
    return snprintf(buffer, buffer_size,
                    "OK AD9528_MEASURE state=%s valid=1 in_range=%u alive=%u sequence=%u odiv2_count=%lu measured_odiv2_hz=%llu measured_out0_hz=%llu window_us=%u",
                    laser_ad9528_measure_state_name(measurement->state),
                    (unsigned int)measurement->in_range,
                    (unsigned int)measurement->alive,
                    (unsigned int)measurement->sequence,
                    (unsigned long)measurement->raw_count,
                    (unsigned long long)measurement->odiv2_hz,
                    (unsigned long long)measurement->out0_hz,
                    (unsigned int)LASER_AD9528_MEASURE_WINDOW_US);
}