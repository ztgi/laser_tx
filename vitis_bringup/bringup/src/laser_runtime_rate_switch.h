#ifndef LASER_RUNTIME_RATE_SWITCH_H
#define LASER_RUNTIME_RATE_SWITCH_H

#include <stdint.h>

#include "laser_ad9528_runtime.h"
#include "laser_dynamic_mailbox.h"
#include "laser_runtime_rate_planner.h"

typedef enum {
    LASER_RUNTIME_SWITCH_IDLE = 0,
    LASER_RUNTIME_SWITCH_PLANNING,
    LASER_RUNTIME_SWITCH_PREPARING_PL,
    LASER_RUNTIME_SWITCH_PROGRAMMING_AD9528,
    LASER_RUNTIME_SWITCH_SWITCHING_PL,
    LASER_RUNTIME_SWITCH_ROLLING_BACK,
    LASER_RUNTIME_SWITCH_DONE,
    LASER_RUNTIME_SWITCH_ERROR
} LaserRuntimeSwitchState;

typedef enum {
    LASER_RUNTIME_SWITCH_ERROR_NONE = 0,
    LASER_RUNTIME_SWITCH_ERROR_PLAN,
    LASER_RUNTIME_SWITCH_ERROR_MAILBOX_PREPARE,
    LASER_RUNTIME_SWITCH_ERROR_MAILBOX_PREPARED_TIMEOUT,
    LASER_RUNTIME_SWITCH_ERROR_AD9528,
    LASER_RUNTIME_SWITCH_ERROR_PL,
    LASER_RUNTIME_SWITCH_ERROR_ROLLBACK
} LaserRuntimeSwitchError;

typedef struct {
    LaserRuntimeSwitchState state;
    LaserRuntimeSwitchError error;
    uint32_t sequence;
    uint8_t current_plan_valid;
    RuntimeRatePlan current_plan;
    RuntimeRatePlan requested_plan;
    RuntimeRatePlanDiagnostics diagnostics;
    LaserDynamicMailboxStatus mailbox;
    LaserAd9528RuntimeStatus ad9528;
} LaserRuntimeRateSwitchStatus;

int laser_runtime_rate_switch_init(void);
int laser_runtime_rate_switch_plan(const RuntimeRatePlanRequest *request,
                                   RuntimeRatePlan *plan,
                                   RuntimeRatePlanDiagnostics *diagnostics);
int laser_runtime_rate_switch_execute(const RuntimeRatePlanRequest *request);
int laser_runtime_rate_switch_abort(void);
void laser_runtime_rate_switch_get_status(LaserRuntimeRateSwitchStatus *status);
const char *laser_runtime_rate_switch_state_name(LaserRuntimeSwitchState state);
const char *laser_runtime_rate_switch_error_name(LaserRuntimeSwitchError error);

#endif
