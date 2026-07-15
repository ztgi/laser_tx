#ifndef LASER_AD9528_RUNTIME_H
#define LASER_AD9528_RUNTIME_H

#include <stdint.h>

#include "laser_runtime_rate_planner.h"

typedef enum {
    LASER_AD9528_RUNTIME_IDLE = 0,
    LASER_AD9528_RUNTIME_APPLYING,
    LASER_AD9528_RUNTIME_CALIBRATING,
    LASER_AD9528_RUNTIME_WAIT_LOCK,
    LASER_AD9528_RUNTIME_MEASURING,
    LASER_AD9528_RUNTIME_READY,
    LASER_AD9528_RUNTIME_RESTORING,
    LASER_AD9528_RUNTIME_ERROR
} LaserAd9528RuntimePhase;

typedef enum {
    LASER_AD9528_RUNTIME_ERROR_NONE = 0,
    LASER_AD9528_RUNTIME_ERROR_BUSY,
    LASER_AD9528_RUNTIME_ERROR_ARGUMENT,
    LASER_AD9528_RUNTIME_ERROR_IDENTITY,
    LASER_AD9528_RUNTIME_ERROR_SPI,
    LASER_AD9528_RUNTIME_ERROR_READBACK,
    LASER_AD9528_RUNTIME_ERROR_CALIBRATION,
    LASER_AD9528_RUNTIME_ERROR_PLL2_LOCK,
    LASER_AD9528_RUNTIME_ERROR_MEASUREMENT,
    LASER_AD9528_RUNTIME_ERROR_RESTORE
} LaserAd9528RuntimeError;

typedef struct {
    LaserAd9528RuntimePhase state;
    LaserAd9528RuntimeError error;
    uint16_t failed_reg;
    uint8_t snapshot_valid;
    uint8_t measurement_windows;
    uint32_t measured_count;
} LaserAd9528RuntimeStatus;

int laser_ad9528_runtime_apply(const RuntimeRatePlan *plan,
                               LaserAd9528RuntimeStatus *status);
int laser_ad9528_runtime_restore(const RuntimeRatePlan *previous_plan,
                                 LaserAd9528RuntimeStatus *status);
void laser_ad9528_runtime_commit(void);
void laser_ad9528_runtime_get_status(LaserAd9528RuntimeStatus *status);

#endif
