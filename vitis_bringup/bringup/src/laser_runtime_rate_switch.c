#include "laser_runtime_rate_switch.h"

#include "xstatus.h"

#include <string.h>

static LaserRuntimeRateSwitchStatus runtime_switch;

static int rollback_pl(uint32_t sequence, uint8_t abort_first)
{
    if (abort_first) {
        (void)laser_dynamic_mailbox_signal_abort();
        /* ABORT first moves the executor to its error/rollback gate. */
        (void)laser_dynamic_mailbox_wait_switch(
            sequence, 100U, &runtime_switch.mailbox);
    }
    if (laser_dynamic_mailbox_signal_rollback_ready() != XST_SUCCESS ||
        laser_dynamic_mailbox_wait_rollback(
            sequence, LASER_DYNAMIC_MAILBOX_DEFAULT_TIMEOUT_MS,
            &runtime_switch.mailbox) != XST_SUCCESS) {
        runtime_switch.error = LASER_RUNTIME_SWITCH_ERROR_ROLLBACK;
        runtime_switch.state = LASER_RUNTIME_SWITCH_ERROR;
        return XST_FAILURE;
    }
    return XST_SUCCESS;
}

int laser_runtime_rate_switch_init(void)
{
    memset(&runtime_switch, 0, sizeof(runtime_switch));
    runtime_switch.state = LASER_RUNTIME_SWITCH_IDLE;
    return laser_dynamic_mailbox_init();
}

int laser_runtime_rate_switch_plan(const RuntimeRatePlanRequest *request,
                                   RuntimeRatePlan *plan,
                                   RuntimeRatePlanDiagnostics *diagnostics)
{
    return laser_runtime_rate_plan(request,
        runtime_switch.current_plan_valid ? &runtime_switch.current_plan : NULL,
        plan, diagnostics);
}

int laser_runtime_rate_switch_execute(const RuntimeRatePlanRequest *request)
{
    int status;
    uint8_t previous_valid;
    RuntimeRatePlan previous_plan;
    if (request == NULL || (runtime_switch.state != LASER_RUNTIME_SWITCH_IDLE &&
        runtime_switch.state != LASER_RUNTIME_SWITCH_DONE &&
        runtime_switch.state != LASER_RUNTIME_SWITCH_ERROR)) {
        return XST_FAILURE;
    }
    previous_valid = runtime_switch.current_plan_valid;
    previous_plan = runtime_switch.current_plan;
    runtime_switch.state = LASER_RUNTIME_SWITCH_PLANNING;
    runtime_switch.error = LASER_RUNTIME_SWITCH_ERROR_NONE;
    memset(&runtime_switch.requested_plan, 0,
           sizeof(runtime_switch.requested_plan));
    status = laser_runtime_rate_switch_plan(
        request, &runtime_switch.requested_plan, &runtime_switch.diagnostics);
    if (status != LASER_RUNTIME_PLAN_OK ||
        !runtime_switch.requested_plan.plan_executable) {
        runtime_switch.error = LASER_RUNTIME_SWITCH_ERROR_PLAN;
        runtime_switch.state = LASER_RUNTIME_SWITCH_ERROR;
        return XST_FAILURE;
    }
    runtime_switch.sequence++;
    if (runtime_switch.sequence == 0U) runtime_switch.sequence = 1U;
    runtime_switch.state = LASER_RUNTIME_SWITCH_PREPARING_PL;
    if (laser_dynamic_mailbox_prepare(&runtime_switch.requested_plan,
                                      runtime_switch.sequence) != XST_SUCCESS) {
        runtime_switch.error = LASER_RUNTIME_SWITCH_ERROR_MAILBOX_PREPARE;
        runtime_switch.state = LASER_RUNTIME_SWITCH_ERROR;
        return XST_FAILURE;
    }
    if (laser_dynamic_mailbox_wait_prepared(
            runtime_switch.sequence,
            LASER_DYNAMIC_MAILBOX_DEFAULT_TIMEOUT_MS,
            &runtime_switch.mailbox) != XST_SUCCESS) {
        runtime_switch.error =
            LASER_RUNTIME_SWITCH_ERROR_MAILBOX_PREPARED_TIMEOUT;
        if (runtime_switch.mailbox.busy) {
            runtime_switch.state = LASER_RUNTIME_SWITCH_ROLLING_BACK;
            (void)rollback_pl(runtime_switch.sequence, 1U);
        } else {
            runtime_switch.state = LASER_RUNTIME_SWITCH_ERROR;
        }
        return XST_FAILURE;
    }

    runtime_switch.state = LASER_RUNTIME_SWITCH_PROGRAMMING_AD9528;
    if (laser_ad9528_runtime_apply(&runtime_switch.requested_plan,
                                   &runtime_switch.ad9528) != XST_SUCCESS) {
        runtime_switch.error = LASER_RUNTIME_SWITCH_ERROR_AD9528;
        runtime_switch.state = LASER_RUNTIME_SWITCH_ROLLING_BACK;
        (void)rollback_pl(runtime_switch.sequence, 1U);
        return XST_FAILURE;
    }

    runtime_switch.state = LASER_RUNTIME_SWITCH_SWITCHING_PL;
    if (laser_dynamic_mailbox_signal_refclk_ready() != XST_SUCCESS) {
        runtime_switch.error = LASER_RUNTIME_SWITCH_ERROR_PL;
        runtime_switch.state = LASER_RUNTIME_SWITCH_ROLLING_BACK;
        (void)laser_ad9528_runtime_restore(previous_valid ?
            &previous_plan : NULL, &runtime_switch.ad9528);
        (void)rollback_pl(runtime_switch.sequence, 1U);
        runtime_switch.state = LASER_RUNTIME_SWITCH_ERROR;
        return XST_FAILURE;
    }
    if (laser_dynamic_mailbox_wait_switch(
            runtime_switch.sequence,
            LASER_DYNAMIC_MAILBOX_DEFAULT_TIMEOUT_MS,
            &runtime_switch.mailbox) != XST_SUCCESS) {
        runtime_switch.error = LASER_RUNTIME_SWITCH_ERROR_PL;
        runtime_switch.state = LASER_RUNTIME_SWITCH_ROLLING_BACK;
        if (laser_ad9528_runtime_restore(previous_valid ? &previous_plan : NULL,
                                         &runtime_switch.ad9528) != XST_SUCCESS ||
            rollback_pl(runtime_switch.sequence, 0U) != XST_SUCCESS) {
            runtime_switch.error = LASER_RUNTIME_SWITCH_ERROR_ROLLBACK;
        }
        runtime_switch.state = LASER_RUNTIME_SWITCH_ERROR;
        return XST_FAILURE;
    }

    laser_ad9528_runtime_commit();
    runtime_switch.current_plan = runtime_switch.requested_plan;
    runtime_switch.current_plan_valid = 1U;
    runtime_switch.state = LASER_RUNTIME_SWITCH_DONE;
    runtime_switch.error = LASER_RUNTIME_SWITCH_ERROR_NONE;
    return XST_SUCCESS;
}

int laser_runtime_rate_switch_abort(void)
{
    LaserAd9528RuntimeStatus ad_status;
    if (runtime_switch.state == LASER_RUNTIME_SWITCH_IDLE ||
        runtime_switch.state == LASER_RUNTIME_SWITCH_DONE) return XST_SUCCESS;
    runtime_switch.state = LASER_RUNTIME_SWITCH_ROLLING_BACK;
    laser_ad9528_runtime_get_status(&ad_status);
    if (ad_status.snapshot_valid) {
        if (laser_ad9528_runtime_restore(
                runtime_switch.current_plan_valid ?
                    &runtime_switch.current_plan : NULL,
                &runtime_switch.ad9528) != XST_SUCCESS) {
            runtime_switch.error = LASER_RUNTIME_SWITCH_ERROR_ROLLBACK;
            runtime_switch.state = LASER_RUNTIME_SWITCH_ERROR;
            return XST_FAILURE;
        }
    }
    if (rollback_pl(runtime_switch.sequence, 1U) != XST_SUCCESS)
        return XST_FAILURE;
    runtime_switch.state = LASER_RUNTIME_SWITCH_IDLE;
    runtime_switch.error = LASER_RUNTIME_SWITCH_ERROR_NONE;
    return XST_SUCCESS;
}

void laser_runtime_rate_switch_get_status(LaserRuntimeRateSwitchStatus *status)
{
    if (status != NULL) *status = runtime_switch;
}

const char *laser_runtime_rate_switch_state_name(LaserRuntimeSwitchState state)
{
    switch (state) {
    case LASER_RUNTIME_SWITCH_IDLE: return "IDLE";
    case LASER_RUNTIME_SWITCH_PLANNING: return "PLANNING";
    case LASER_RUNTIME_SWITCH_PREPARING_PL: return "PREPARING_PL";
    case LASER_RUNTIME_SWITCH_PROGRAMMING_AD9528: return "PROGRAMMING_AD9528";
    case LASER_RUNTIME_SWITCH_SWITCHING_PL: return "SWITCHING_PL";
    case LASER_RUNTIME_SWITCH_ROLLING_BACK: return "ROLLING_BACK";
    case LASER_RUNTIME_SWITCH_DONE: return "DONE";
    case LASER_RUNTIME_SWITCH_ERROR: return "ERROR";
    default: return "UNKNOWN";
    }
}

const char *laser_runtime_rate_switch_error_name(LaserRuntimeSwitchError error)
{
    switch (error) {
    case LASER_RUNTIME_SWITCH_ERROR_NONE: return "NONE";
    case LASER_RUNTIME_SWITCH_ERROR_PLAN: return "PLAN";
    case LASER_RUNTIME_SWITCH_ERROR_MAILBOX_PREPARE: return "MAILBOX_PREPARE";
    case LASER_RUNTIME_SWITCH_ERROR_MAILBOX_PREPARED_TIMEOUT:
        return "MAILBOX_PREPARED_TIMEOUT";
    case LASER_RUNTIME_SWITCH_ERROR_AD9528: return "AD9528";
    case LASER_RUNTIME_SWITCH_ERROR_PL: return "PL";
    case LASER_RUNTIME_SWITCH_ERROR_ROLLBACK: return "ROLLBACK";
    default: return "UNKNOWN";
    }
}
