#include "laser_ad9528_runtime.h"

#include "laser_ad9528.h"
#include "laser_ad9528_measure.h"
#include "sleep.h"
#include "xstatus.h"

#include <string.h>

#define AD9528_RUNTIME_COMMON_WRITES 12U
#define AD9528_RUNTIME_IO_UPDATE_REG 0x000fU
#define AD9528_RUNTIME_VCO_CTRL_REG  0x0203U
#define AD9528_RUNTIME_STATUS_REG    0x0508U
#define AD9528_RUNTIME_CAL_REG       0x0509U
#define AD9528_RUNTIME_POLL_US       1000U
#define AD9528_RUNTIME_CAL_TIMEOUT   500000U
#define AD9528_RUNTIME_LOCK_TIMEOUT  500000U
#define AD9528_RUNTIME_MEAS_TIMEOUT  2000000U
#define AD9528_RUNTIME_WINDOWS       3U

typedef struct {
    uint8_t busy;
    uint8_t valid;
    uint8_t count;
    uint16_t regs[LASER_RUNTIME_AD9528_WRITE_COUNT];
    uint8_t values[LASER_RUNTIME_AD9528_WRITE_COUNT];
    LaserAd9528RuntimeStatus status;
} RuntimeSnapshot;

static RuntimeSnapshot runtime_snapshot;

static void set_error(LaserAd9528RuntimeError error, uint16_t reg)
{
    runtime_snapshot.status.state = LASER_AD9528_RUNTIME_ERROR;
    runtime_snapshot.status.error = error;
    runtime_snapshot.status.failed_reg = reg;
}

static int io_update(void)
{
    return laser_ad9528_write(AD9528_RUNTIME_IO_UPDATE_REG, 0x01U);
}

static int snapshot_plan(const RuntimeRatePlan *plan)
{
    uint8_t i;
    runtime_snapshot.count = plan->ad9528_write_count;
    for (i = 0U; i < plan->ad9528_write_count; ++i) {
        runtime_snapshot.regs[i] = plan->ad9528_writes[i].address;
        if (laser_ad9528_read(runtime_snapshot.regs[i],
                              &runtime_snapshot.values[i]) != XST_SUCCESS) {
            set_error(LASER_AD9528_RUNTIME_ERROR_SPI,
                      runtime_snapshot.regs[i]);
            return XST_FAILURE;
        }
    }
    runtime_snapshot.valid = 1U;
    runtime_snapshot.status.snapshot_valid = 1U;
    return XST_SUCCESS;
}

static int write_range(const RuntimeRatePlan *plan, uint8_t first,
                       uint8_t last)
{
    uint8_t i;
    for (i = first; i < last; ++i) {
        uint8_t old_value;
        uint8_t new_value;
        if (laser_ad9528_read(plan->ad9528_writes[i].address,
                              &old_value) != XST_SUCCESS) {
            set_error(LASER_AD9528_RUNTIME_ERROR_SPI,
                      plan->ad9528_writes[i].address);
            return XST_FAILURE;
        }
        new_value = (uint8_t)((old_value &
            (uint8_t)~plan->ad9528_writes[i].mask) |
            (plan->ad9528_writes[i].value & plan->ad9528_writes[i].mask));
        if (laser_ad9528_write(plan->ad9528_writes[i].address,
                               new_value) != XST_SUCCESS) {
            set_error(LASER_AD9528_RUNTIME_ERROR_SPI,
                      plan->ad9528_writes[i].address);
            return XST_FAILURE;
        }
    }
    return XST_SUCCESS;
}

static int verify_range(const RuntimeRatePlan *plan, uint8_t first,
                        uint8_t last)
{
    uint8_t i;
    for (i = first; i < last; ++i) {
        uint8_t actual;
        uint8_t mask = plan->ad9528_writes[i].mask;
        if (laser_ad9528_read(plan->ad9528_writes[i].address,
                              &actual) != XST_SUCCESS) {
            set_error(LASER_AD9528_RUNTIME_ERROR_SPI,
                      plan->ad9528_writes[i].address);
            return XST_FAILURE;
        }
        if ((actual & mask) != (plan->ad9528_writes[i].value & mask)) {
            set_error(LASER_AD9528_RUNTIME_ERROR_READBACK,
                      plan->ad9528_writes[i].address);
            return XST_FAILURE;
        }
    }
    return XST_SUCCESS;
}

static int calibrate_and_lock(void)
{
    uint32_t elapsed;
    uint8_t value = 0U;
    uint8_t seen = 0U;
    runtime_snapshot.status.state = LASER_AD9528_RUNTIME_CALIBRATING;
    if (laser_ad9528_read(AD9528_RUNTIME_VCO_CTRL_REG, &value) != XST_SUCCESS ||
        laser_ad9528_write(AD9528_RUNTIME_VCO_CTRL_REG,
                           (uint8_t)(value | 1U)) != XST_SUCCESS ||
        io_update() != XST_SUCCESS) {
        set_error(LASER_AD9528_RUNTIME_ERROR_SPI,
                  AD9528_RUNTIME_VCO_CTRL_REG);
        return XST_FAILURE;
    }
    for (elapsed = 0U; elapsed < AD9528_RUNTIME_CAL_TIMEOUT;
         elapsed += AD9528_RUNTIME_POLL_US) {
        if (laser_ad9528_read(AD9528_RUNTIME_CAL_REG, &value) != XST_SUCCESS) {
            set_error(LASER_AD9528_RUNTIME_ERROR_SPI,
                      AD9528_RUNTIME_CAL_REG);
            return XST_FAILURE;
        }
        if ((value & 1U) != 0U) seen = 1U;
        else if (seen) break;
        usleep(AD9528_RUNTIME_POLL_US);
    }
    if (!seen || elapsed >= AD9528_RUNTIME_CAL_TIMEOUT) {
        set_error(LASER_AD9528_RUNTIME_ERROR_CALIBRATION,
                  AD9528_RUNTIME_CAL_REG);
        return XST_FAILURE;
    }
    runtime_snapshot.status.state = LASER_AD9528_RUNTIME_WAIT_LOCK;
    for (elapsed = 0U; elapsed < AD9528_RUNTIME_LOCK_TIMEOUT;
         elapsed += AD9528_RUNTIME_POLL_US) {
        if (laser_ad9528_read(AD9528_RUNTIME_STATUS_REG, &value) != XST_SUCCESS) {
            set_error(LASER_AD9528_RUNTIME_ERROR_SPI,
                      AD9528_RUNTIME_STATUS_REG);
            return XST_FAILURE;
        }
        if ((value & 0xa2U) == 0xa2U) return XST_SUCCESS;
        usleep(AD9528_RUNTIME_POLL_US);
    }
    set_error(LASER_AD9528_RUNTIME_ERROR_PLL2_LOCK,
              AD9528_RUNTIME_STATUS_REG);
    return XST_FAILURE;
}

static int measure_plan(const RuntimeRatePlan *plan)
{
    LaserAd9528Measurement measurement;
    uint32_t elapsed;
    uint32_t tolerance = (plan->ad9528_expected_count + 99U) / 100U;
    uint16_t last_sequence = 0U;
    uint8_t have_sequence = 0U;
    uint8_t windows = 0U;
    runtime_snapshot.status.state = LASER_AD9528_RUNTIME_MEASURING;
    if (laser_ad9528_measure_mark_transition() != XST_SUCCESS) {
        set_error(LASER_AD9528_RUNTIME_ERROR_MEASUREMENT, 0U);
        return XST_FAILURE;
    }
    for (elapsed = 0U; elapsed < AD9528_RUNTIME_MEAS_TIMEOUT;
         elapsed += AD9528_RUNTIME_POLL_US) {
        if (laser_ad9528_measure_read(&measurement) == XST_SUCCESS &&
            measurement.valid && measurement.alive &&
            (!have_sequence || measurement.sequence != last_sequence)) {
            uint32_t delta = measurement.raw_count >=
                plan->ad9528_expected_count ?
                measurement.raw_count - plan->ad9528_expected_count :
                plan->ad9528_expected_count - measurement.raw_count;
            have_sequence = 1U;
            last_sequence = measurement.sequence;
            runtime_snapshot.status.measured_count = measurement.raw_count;
            if (delta > tolerance) {
                set_error(LASER_AD9528_RUNTIME_ERROR_MEASUREMENT, 0U);
                return XST_FAILURE;
            }
            runtime_snapshot.status.measurement_windows = ++windows;
            if (windows >= AD9528_RUNTIME_WINDOWS) return XST_SUCCESS;
        }
        usleep(AD9528_RUNTIME_POLL_US);
    }
    set_error(LASER_AD9528_RUNTIME_ERROR_MEASUREMENT, 0U);
    return XST_FAILURE;
}

int laser_ad9528_runtime_apply(const RuntimeRatePlan *plan,
                               LaserAd9528RuntimeStatus *status)
{
    uint8_t product = 0U, revision = 0U, vendor = 0U;
    LaserAd9528RuntimeError original_error;
    uint16_t original_failed_reg;
    int result = XST_FAILURE;
    if (runtime_snapshot.busy || runtime_snapshot.valid) {
        set_error(LASER_AD9528_RUNTIME_ERROR_BUSY, 0U);
        goto done;
    }
    if (plan == NULL || plan->ad9528_write_count !=
        LASER_RUNTIME_AD9528_WRITE_COUNT) {
        set_error(LASER_AD9528_RUNTIME_ERROR_ARGUMENT, 0U);
        goto done;
    }
    memset(&runtime_snapshot.status, 0, sizeof(runtime_snapshot.status));
    runtime_snapshot.busy = 1U;
    runtime_snapshot.status.state = LASER_AD9528_RUNTIME_APPLYING;
    if (laser_ad9528_identify(&product, &revision, &vendor) != XST_SUCCESS) {
        set_error(LASER_AD9528_RUNTIME_ERROR_IDENTITY, 0x0003U);
        goto done;
    }
    if (snapshot_plan(plan) != XST_SUCCESS ||
        write_range(plan, 0U, AD9528_RUNTIME_COMMON_WRITES) != XST_SUCCESS ||
        io_update() != XST_SUCCESS ||
        verify_range(plan, 0U, AD9528_RUNTIME_COMMON_WRITES) != XST_SUCCESS ||
        calibrate_and_lock() != XST_SUCCESS ||
        write_range(plan, AD9528_RUNTIME_COMMON_WRITES,
                    plan->ad9528_write_count) != XST_SUCCESS ||
        io_update() != XST_SUCCESS ||
        verify_range(plan, AD9528_RUNTIME_COMMON_WRITES,
                     plan->ad9528_write_count) != XST_SUCCESS ||
        measure_plan(plan) != XST_SUCCESS) {
        goto rollback;
    }
    runtime_snapshot.status.state = LASER_AD9528_RUNTIME_READY;
    runtime_snapshot.status.error = LASER_AD9528_RUNTIME_ERROR_NONE;
    result = XST_SUCCESS;
    goto done;

rollback:
    original_error = runtime_snapshot.status.error;
    original_failed_reg = runtime_snapshot.status.failed_reg;
    (void)laser_ad9528_runtime_restore(NULL, NULL);
    runtime_snapshot.status.state = LASER_AD9528_RUNTIME_ERROR;
    runtime_snapshot.status.error = original_error;
    runtime_snapshot.status.failed_reg = original_failed_reg;
done:
    runtime_snapshot.busy = 0U;
    if (status != NULL) *status = runtime_snapshot.status;
    return result;
}

int laser_ad9528_runtime_restore(const RuntimeRatePlan *previous_plan,
                                 LaserAd9528RuntimeStatus *status)
{
    uint8_t i;
    uint8_t actual;
    uint8_t ok = 1U;
    if (!runtime_snapshot.valid) {
        set_error(LASER_AD9528_RUNTIME_ERROR_RESTORE, 0U);
        if (status != NULL) *status = runtime_snapshot.status;
        return XST_FAILURE;
    }
    runtime_snapshot.status.state = LASER_AD9528_RUNTIME_RESTORING;
    for (i = 0U; i < runtime_snapshot.count; ++i) {
        if (laser_ad9528_write(runtime_snapshot.regs[i],
                               runtime_snapshot.values[i]) != XST_SUCCESS)
            ok = 0U;
    }
    if (io_update() != XST_SUCCESS) ok = 0U;
    usleep(1000U);
    for (i = 0U; i < runtime_snapshot.count; ++i) {
        if (laser_ad9528_read(runtime_snapshot.regs[i], &actual) != XST_SUCCESS ||
            actual != runtime_snapshot.values[i]) ok = 0U;
    }
    if (ok && previous_plan != NULL &&
        calibrate_and_lock() != XST_SUCCESS) ok = 0U;
    runtime_snapshot.valid = 0U;
    runtime_snapshot.status.snapshot_valid = 0U;
    if (!ok) {
        set_error(LASER_AD9528_RUNTIME_ERROR_RESTORE, 0U);
        if (status != NULL) *status = runtime_snapshot.status;
        return XST_FAILURE;
    }
    memset(&runtime_snapshot.status, 0, sizeof(runtime_snapshot.status));
    runtime_snapshot.status.state = LASER_AD9528_RUNTIME_IDLE;
    if (status != NULL) *status = runtime_snapshot.status;
    return XST_SUCCESS;
}

void laser_ad9528_runtime_commit(void)
{
    runtime_snapshot.valid = 0U;
    runtime_snapshot.status.snapshot_valid = 0U;
}

void laser_ad9528_runtime_get_status(LaserAd9528RuntimeStatus *status)
{
    if (status != NULL) *status = runtime_snapshot.status;
}
