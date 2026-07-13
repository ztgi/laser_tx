#ifndef LASER_AD9528_MEASURE_H
#define LASER_AD9528_MEASURE_H

#include <stddef.h>
#include <stdint.h>

#define LASER_AD9528_MEASURE_GT_CTRL_CLK_HZ 50000000U
#define LASER_AD9528_MEASURE_WINDOW_CYCLES  50000U
#define LASER_AD9528_MEASURE_WINDOW_US      1000U
#define LASER_AD9528_MEASURE_ODIV2_FACTOR   2U
#define LASER_AD9528_MEASURE_COUNT_MIN      60000U
#define LASER_AD9528_MEASURE_COUNT_MAX      62900U
#define LASER_AD9528_MEASURE_FORMAT_VERSION 1U
#define LASER_AD9528_MEASURE_MAX_RETRIES    4U

#define LASER_AD9528_MEASURE_STATUS_VALID_MASK       0x00000001U
#define LASER_AD9528_MEASURE_STATUS_IN_RANGE_MASK    0x00000002U
#define LASER_AD9528_MEASURE_STATUS_ALIVE_MASK       0x00000004U
#define LASER_AD9528_MEASURE_STATUS_VERSION_SHIFT    4U
#define LASER_AD9528_MEASURE_STATUS_VERSION_MASK     0x000000F0U
#define LASER_AD9528_MEASURE_STATUS_SEQUENCE_SHIFT   16U
#define LASER_AD9528_MEASURE_STATUS_SEQUENCE_MASK    0xFFFF0000U

#define LASER_AD9528_MEASURE_COUNT_CHANNEL  1U
#define LASER_AD9528_MEASURE_STATUS_CHANNEL 2U

typedef enum {
    LASER_AD9528_MEASUREMENT_VALID_IN_RANGE = 0,
    LASER_AD9528_MEASUREMENT_VALID_OUT_OF_RANGE,
    LASER_AD9528_MEASUREMENT_NOT_VALID,
    LASER_AD9528_MEASUREMENT_READ_ERROR,
    LASER_AD9528_MEASUREMENT_FORMAT_ERROR
} LaserAd9528MeasurementState;

typedef struct {
    uint32_t raw_count;
    uint16_t sequence;
    uint8_t valid;
    uint8_t in_range;
    uint8_t alive;
    uint8_t format_version;
    uint64_t odiv2_hz;
    uint64_t out0_hz;
    LaserAd9528MeasurementState state;
} LaserAd9528Measurement;

int laser_ad9528_measure_init(void);
int laser_ad9528_measure_read(LaserAd9528Measurement *measurement);
int laser_ad9528_measure_mark_transition(void);
const char *laser_ad9528_measure_state_name(LaserAd9528MeasurementState state);
int laser_ad9528_measure_format_udp(char *buffer, size_t buffer_size,
                                    const LaserAd9528Measurement *measurement,
                                    int read_status);

#endif