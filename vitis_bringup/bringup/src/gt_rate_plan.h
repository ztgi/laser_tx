#ifndef GT_RATE_PLAN_H
#define GT_RATE_PLAN_H

#include <stddef.h>
#include <stdint.h>

#define GT_RATE_PLAN_OK                 0
#define GT_RATE_PLAN_STATUS_UNSUPPORTED -1
#define GT_RATE_PLAN_STATUS_BAD_ARG     -2

typedef enum {
    GT_RATE_PLAN_EXACT = 0,
    GT_RATE_PLAN_NEAREST,
    GT_RATE_PLAN_UNSUPPORTED
} GtRatePlanResult;

typedef enum {
    GT_RATE_REF_LOCAL_125 = 0,
    GT_RATE_REF_LOCAL_15625 = 1,
    GT_RATE_REF_AD9528_OUT0 = 2
} GtRateRefSource;

typedef enum {
    GT_RATE_PLL_CPLL = 0,
    GT_RATE_PLL_QPLL = 1
} GtRatePllSource;

/* A verified fixed profile.  This table is planning metadata only: it never
 * exposes GT/MMCM DRP address or data writes to UDP. */
typedef struct {
    uint32_t rate_mbps;
    uint32_t rate_id;
    GtRatePllSource pll_source;
    uint32_t refclk_hz;
    uint32_t expected_txusrclk2_hz;
    uint32_t freq_counter_min;
    uint32_t freq_counter_max;
    uint16_t cpll_drp_value;
    uint8_t txout_div;
    uint8_t mmcm_profile_id;
    uint8_t qpll_n;
    uint8_t qpll_required;
    uint8_t ad9528_dynamic_required;
    uint8_t board_verified;
} GtRateProfile;

typedef struct {
    GtRatePlanResult result;
    uint32_t requested_rate_mbps;
    uint32_t selected_rate_mbps;
    uint32_t selected_rate_id;
    uint32_t nearest_lower_mbps;
    uint32_t nearest_upper_mbps;
    uint32_t absolute_error_mbps;
    const GtRateProfile *profile;
    const char *reason;
} GtRatePlan;

int gt_rate_plan_exact(uint32_t requested_rate_mbps, GtRatePlan *plan);
int gt_rate_plan_nearest(uint32_t requested_rate_mbps, GtRatePlan *plan);

/* Compatibility name for exact-only callers. */
int gt_rate_plan(uint32_t requested_rate_mbps, GtRatePlan *plan);

size_t gt_rate_profile_count(void);
const GtRateProfile *gt_rate_profile_at(size_t index);
const GtRateProfile *gt_rate_profile_from_rate_id(uint32_t rate_id);
uint32_t gt_rate_profile_rate_mbps_from_id(uint32_t rate_id);
const char *gt_rate_plan_result_name(GtRatePlanResult result);
const char *gt_rate_ref_source_name(GtRateRefSource ref_source);
const char *gt_rate_pll_source_name(GtRatePllSource pll_source);
void gt_rate_plan_print(const GtRatePlan *plan);

#endif
