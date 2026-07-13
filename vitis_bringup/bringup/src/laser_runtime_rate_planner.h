#ifndef LASER_RUNTIME_RATE_PLANNER_H
#define LASER_RUNTIME_RATE_PLANNER_H

#include <stdint.h>

#include "../../../generated/runtime_ad9528_configs.h"
#include "../../../generated/runtime_gt_tuples.h"
#include "../../../generated/runtime_mmcm_recipes.h"

#define LASER_RUNTIME_RATE_DEFAULT_PREFERRED_PPM 5000U
#define LASER_RUNTIME_RATE_DEFAULT_MAXIMUM_PPM   50000U
#define LASER_RUNTIME_RATE_MAXIMUM_ALLOWED_PPM   50000U
#define LASER_RUNTIME_AD9528_WRITE_COUNT         16U

typedef enum {
    LASER_RUNTIME_PLL_CPLL = 0,
    LASER_RUNTIME_PLL_QPLL = 1,
    LASER_RUNTIME_PLL_BOTH = 2
} LaserRuntimeAllowedPll;

typedef enum {
    LASER_RUNTIME_PATH_AD9528_OUT0 = 1
} LaserRuntimeImplementationPath;

typedef enum {
    LASER_RUNTIME_PLAN_OK = 0,
    LASER_RUNTIME_PLAN_BAD_ARGUMENT = -1,
    LASER_RUNTIME_PLAN_NO_SOLUTION = -2
} LaserRuntimePlanStatus;

typedef struct {
    uint16_t address;
    uint8_t mask;
    uint8_t value;
} LaserRuntimeAd9528Write;

typedef struct {
    uint64_t requested_line_rate_bps;
    uint32_t preferred_error_ppm;
    uint32_t maximum_error_ppm;
    uint8_t allowed_pll_type;
    uint8_t allowed_implementation_path;
} RuntimeRatePlanRequest;

typedef struct {
    uint64_t requested_line_rate_bps;
    uint64_t actual_line_rate_bps;
    int32_t line_rate_error_ppm;

    uint8_t ad9528_doubler;
    uint8_t ad9528_r1;
    uint16_t ad9528_n2;
    uint8_t ad9528_m1;
    uint16_t ad9528_out_div;
    uint32_t ad9528_pfd_hz;
    uint32_t ad9528_vco_hz;
    uint32_t ad9528_out0_hz;
    uint32_t ad9528_expected_count;
    uint16_t ad9528_register_plan_id;
    uint8_t ad9528_write_count;
    LaserRuntimeAd9528Write ad9528_writes[LASER_RUNTIME_AD9528_WRITE_COUNT];

    uint8_t gt_pll_type;
    uint8_t gt_refclk_div;
    uint8_t gt_fbdiv;
    uint8_t gt_fbdiv_45;
    uint8_t gt_txout_div;
    uint8_t gt_txout_div_encoding;
    uint8_t gt_drp_encoding_confirmed;
    uint64_t gt_vco_hz;

    uint8_t mmcm_mult;
    uint8_t mmcm_write_count;
    RuntimeMmcmWrite mmcm_writes[RUNTIME_MMCM_WRITE_COUNT];
    uint32_t mmcm_vco_hz;
    uint32_t txoutclk_hz;
    uint32_t txusrclk_hz;
    uint32_t txusrclk2_hz;
    uint32_t verify_expected_count;
    uint32_t verify_tolerance;

    uint8_t implementation_path;
    uint8_t plan_executable;
    uint8_t evidence_level;
    const char *rejected_reason;
} RuntimeRatePlan;

typedef struct {
    uint32_t gt_tuples_considered;
    uint32_t ad9528_candidates_considered;
    uint32_t tolerance_qualified;
    uint32_t mmcm_qualified;
    uint32_t executable_qualified;
    uint32_t planning_time_us;
} RuntimeRatePlanDiagnostics;

int laser_runtime_rate_plan(const RuntimeRatePlanRequest *request,
                            const RuntimeRatePlan *current_plan,
                            RuntimeRatePlan *result,
                            RuntimeRatePlanDiagnostics *diagnostics);

#endif
