#include "laser_runtime_rate_planner.h"

#include <stddef.h>
#include <string.h>

#define VCXO_HZ                 122880000ULL
#define GTX_MIN_LINE_RATE_BPS    500000000ULL
#define GTX_LOW_MAX_RATE_BPS    8000000000ULL
#define GTX_HIGH_MIN_RATE_BPS   9800000000ULL
#define GTX_MAX_LINE_RATE_BPS  10312500000ULL
#define CPLL_VCO_MIN_HZ         1600000000ULL
#define CPLL_VCO_MAX_HZ         3300000000ULL
#define QPLL_LOW_VCO_MIN_HZ     5930000000ULL
#define QPLL_LOW_VCO_MAX_HZ     8000000000ULL
#define QPLL_HIGH_VCO_MIN_HZ    9800000000ULL
#define QPLL_HIGH_VCO_MAX_HZ   10312500000ULL
#define MMCM_VCO_MIN_HZ          600000000ULL
#define MMCM_VCO_MAX_HZ         1200000000ULL

typedef struct {
    RuntimeRatePlan plan;
    uint64_t absolute_error_bps;
    uint32_t ad9528_margin_hz;
    uint32_t gt_margin_hz;
    uint32_t mmcm_margin_hz;
    uint32_t register_difference;
    uint8_t pll_change;
    uint8_t txout_div_change;
    uint8_t not_n2_only;
    size_t ad_index;
    size_t gt_index;
    uint8_t valid;
} RuntimeCandidate;

static uint64_t round_fraction(uint64_t numerator, uint64_t denominator)
{
    return (numerator + denominator / 2U) / denominator;
}

static uint64_t absolute_difference(uint64_t left, uint64_t right)
{
    return (left >= right) ? left - right : right - left;
}

static uint32_t minimum_u32(uint32_t left, uint32_t right)
{
    return (left < right) ? left : right;
}

static int fraction_in_range(uint64_t numerator, uint64_t denominator,
                             uint64_t lower, uint64_t upper)
{
    return numerator >= lower * denominator &&
           numerator <= upper * denominator;
}

static int line_rate_coverage_ok(uint64_t numerator, uint64_t denominator)
{
    if (!fraction_in_range(numerator, denominator,
                           GTX_MIN_LINE_RATE_BPS, GTX_MAX_LINE_RATE_BPS)) {
        return 0;
    }
    return numerator <= GTX_LOW_MAX_RATE_BPS * denominator ||
           numerator >= GTX_HIGH_MIN_RATE_BPS * denominator;
}

static int cpll_line_range_ok(uint8_t txout_div, uint64_t numerator,
                              uint64_t denominator)
{
    switch (txout_div) {
    case 1U: return fraction_in_range(numerator, denominator, 3200000000ULL, 6600000000ULL);
    case 2U: return fraction_in_range(numerator, denominator, 1600000000ULL, 3300000000ULL);
    case 4U: return fraction_in_range(numerator, denominator,  800000000ULL, 1650000000ULL);
    case 8U: return fraction_in_range(numerator, denominator,  500000000ULL,  825000000ULL);
    default: return 0;
    }
}

static int qpll_line_range_ok(uint8_t txout_div, int upper_band,
                              uint64_t numerator, uint64_t denominator)
{
    if (upper_band != 0) {
        switch (txout_div) {
        case 1U: return fraction_in_range(numerator, denominator, 9800000000ULL, 10312500000ULL);
        case 2U: return fraction_in_range(numerator, denominator, 4900000000ULL,  5156250000ULL);
        case 4U: return fraction_in_range(numerator, denominator, 2450000000ULL,  2578125000ULL);
        case 8U: return fraction_in_range(numerator, denominator, 1225000000ULL,  1289062500ULL);
        case 16U:return fraction_in_range(numerator, denominator,  612500000ULL,   644531250ULL);
        default:return 0;
        }
    }
    switch (txout_div) {
    case 1U: return fraction_in_range(numerator, denominator, 5930000000ULL, 8000000000ULL);
    case 2U: return fraction_in_range(numerator, denominator, 2965000000ULL, 4000000000ULL);
    case 4U: return fraction_in_range(numerator, denominator, 1482500000ULL, 2000000000ULL);
    case 8U: return fraction_in_range(numerator, denominator,  741250000ULL, 1000000000ULL);
    default:return 0;
    }
}

static int tolerance_ok(uint64_t requested, uint64_t actual, uint32_t ppm)
{
    uint64_t difference = absolute_difference(requested, actual);
    if (difference > UINT64_MAX / 1000000ULL ||
        requested > UINT64_MAX / (uint64_t)ppm) {
        return 0;
    }
    return difference * 1000000ULL <= requested * (uint64_t)ppm;
}

static int32_t signed_error_ppm(uint64_t requested, uint64_t actual)
{
    uint64_t difference = absolute_difference(requested, actual);
    uint64_t magnitude = (difference * 1000000ULL + requested / 2U) / requested;
    return (actual >= requested) ? (int32_t)magnitude : -(int32_t)magnitude;
}

static size_t ad9528_lower_bound(uint64_t desired_hz)
{
    size_t low = 0U;
    size_t high = runtime_ad9528_config_count;
    while (low < high) {
        size_t middle = low + (high - low) / 2U;
        if ((uint64_t)runtime_ad9528_configs[middle].out0_hz < desired_hz) {
            low = middle + 1U;
        } else {
            high = middle;
        }
    }
    return low;
}

static const RuntimeMmcmRecipe *select_mmcm_recipe(uint64_t line_num,
                                                   uint64_t line_den,
                                                   uint32_t *vco_hz,
                                                   uint32_t *margin_hz)
{
    const RuntimeMmcmRecipe *best = NULL;
    uint64_t input_den = line_den * 32ULL;
    uint32_t best_margin = 0U;
    size_t i;
    for (i = 0U; i < runtime_mmcm_recipe_count; ++i) {
        uint64_t candidate_num = line_num * runtime_mmcm_recipes[i].mult;
        uint64_t rounded;
        uint32_t margin;
        if (!fraction_in_range(candidate_num, input_den,
                               MMCM_VCO_MIN_HZ, MMCM_VCO_MAX_HZ)) {
            continue;
        }
        rounded = round_fraction(candidate_num, input_den);
        margin = minimum_u32((uint32_t)(rounded - MMCM_VCO_MIN_HZ),
                             (uint32_t)(MMCM_VCO_MAX_HZ - rounded));
        if (best == NULL || margin > best_margin ||
            (margin == best_margin && runtime_mmcm_recipes[i].mult < best->mult)) {
            best = &runtime_mmcm_recipes[i];
            best_margin = margin;
            *vco_hz = (uint32_t)rounded;
            *margin_hz = margin;
        }
    }
    return best;
}

static void fill_ad9528_writes(RuntimeRatePlan *plan)
{
    uint16_t calibration = (uint16_t)(plan->ad9528_m1 * plan->ad9528_n2);
    uint8_t feedback_ab = (uint8_t)(((calibration % 4U) << 6) |
                                    (calibration / 4U));
    const LaserRuntimeAd9528Write writes[LASER_RUNTIME_AD9528_WRITE_COUNT] = {
        {0x0108U,0x05U,0x01U}, {0x0109U,0x38U,0x38U},
        {0x0200U,0xffU,0xe6U}, {0x0201U,0xffU,feedback_ab},
        {0x0202U,0xa3U,0x03U}, {0x0203U,0x17U,0x10U},
        {0x0204U,0x0fU,plan->ad9528_m1},
        {0x0205U,0xffU,0x3aU}, {0x0206U,0x01U,0x00U},
        {0x0207U,0x1fU,plan->ad9528_r1},
        {0x0208U,0xffU,(uint8_t)(plan->ad9528_n2 - 1U)},
        {0x0500U,0x08U,0x00U}, {0x0300U,0xe0U,0x00U},
        {0x0301U,0xc0U,0x00U},
        {0x0302U,0xffU,(uint8_t)(plan->ad9528_out_div - 1U)},
        {0x0501U,0x01U,0x00U}
    };
    memcpy(plan->ad9528_writes, writes, sizeof(writes));
    plan->ad9528_write_count = LASER_RUNTIME_AD9528_WRITE_COUNT;
}

static uint32_t register_difference(const RuntimeRatePlan *current,
                                    const RuntimeRatePlan *candidate)
{
    if (current == NULL || current->plan_executable == 0U) {
        return UINT32_MAX / 2U;
    }
    return (current->ad9528_r1 != candidate->ad9528_r1) +
           (current->ad9528_n2 != candidate->ad9528_n2) +
           (current->ad9528_m1 != candidate->ad9528_m1) +
           (current->ad9528_out_div != candidate->ad9528_out_div) +
           (current->gt_pll_type != candidate->gt_pll_type) +
           (current->gt_refclk_div != candidate->gt_refclk_div) +
           (current->gt_fbdiv != candidate->gt_fbdiv) +
           (current->gt_fbdiv_45 != candidate->gt_fbdiv_45) +
           (current->gt_txout_div != candidate->gt_txout_div);
}

static int candidate_better(const RuntimeCandidate *left,
                            const RuntimeCandidate *right)
{
#define LESS_FIELD(field) do { if (left->field != right->field) return left->field < right->field; } while (0)
#define MORE_FIELD(field) do { if (left->field != right->field) return left->field > right->field; } while (0)
    if (right->valid == 0U) return 1;
    LESS_FIELD(absolute_error_bps);
    MORE_FIELD(ad9528_margin_hz);
    MORE_FIELD(gt_margin_hz);
    MORE_FIELD(mmcm_margin_hz);
    LESS_FIELD(register_difference);
    LESS_FIELD(pll_change);
    LESS_FIELD(txout_div_change);
    LESS_FIELD(not_n2_only);
    LESS_FIELD(ad_index);
    LESS_FIELD(gt_index);
    return 0;
#undef LESS_FIELD
#undef MORE_FIELD
}

static int evaluate_candidate(const RuntimeRatePlanRequest *request,
                              const RuntimeRatePlan *current,
                              size_t ad_index, size_t gt_index,
                              RuntimeCandidate *candidate)
{
    const RuntimeAd9528Config *ad = &runtime_ad9528_configs[ad_index];
    const RuntimeGtTuple *gt = &runtime_gt_tuples[gt_index];
    uint64_t out_num = VCXO_HZ * ad->doubler * ad->n2;
    uint64_t out_den = (uint64_t)ad->r1 * ad->out0_div;
    uint64_t line_num;
    uint64_t line_den;
    uint64_t vco_num;
    uint64_t vco_den;
    uint64_t actual;
    uint64_t vco;
    uint64_t desired;
    int upper_qpll = 0;
    const RuntimeMmcmRecipe *mmcm;
    uint32_t mmcm_vco = 0U;
    uint32_t mmcm_margin = 0U;

    if (ad->executable_register_encoding == 0U) return 0;
    if (request->allowed_pll_type != LASER_RUNTIME_PLL_BOTH &&
        request->allowed_pll_type != gt->pll_type) return 0;
    if (gt->pll_type == RUNTIME_PLL_CPLL) {
        line_num = out_num * gt->fbdiv_45 * gt->fbdiv * 2ULL;
        line_den = out_den * gt->refclk_div * gt->txout_div;
        vco_num = out_num * gt->fbdiv_45 * gt->fbdiv;
        vco_den = out_den * gt->refclk_div;
        if (!fraction_in_range(vco_num, vco_den,
                               CPLL_VCO_MIN_HZ, CPLL_VCO_MAX_HZ) ||
            !cpll_line_range_ok(gt->txout_div, line_num, line_den)) return 0;
    } else {
        line_num = out_num * gt->fbdiv;
        line_den = out_den * gt->refclk_div * gt->txout_div;
        vco_num = out_num * gt->fbdiv;
        vco_den = out_den * gt->refclk_div;
        upper_qpll = fraction_in_range(vco_num, vco_den,
                                       QPLL_HIGH_VCO_MIN_HZ,
                                       QPLL_HIGH_VCO_MAX_HZ);
        if (upper_qpll == 0 &&
            !fraction_in_range(vco_num, vco_den,
                               QPLL_LOW_VCO_MIN_HZ,
                               QPLL_LOW_VCO_MAX_HZ)) return 0;
        if (!qpll_line_range_ok(gt->txout_div, upper_qpll,
                                line_num, line_den)) return 0;
    }
    if (!line_rate_coverage_ok(line_num, line_den)) return 0;
    actual = round_fraction(line_num, line_den);
    if (!tolerance_ok(request->requested_line_rate_bps, actual,
                      request->maximum_error_ppm)) return 0;
    mmcm = select_mmcm_recipe(line_num, line_den, &mmcm_vco, &mmcm_margin);
    if (mmcm == NULL) return 0;
    vco = round_fraction(vco_num, vco_den);
    desired = round_fraction(out_num, out_den);
    memset(candidate, 0, sizeof(*candidate));
    candidate->plan.requested_line_rate_bps = request->requested_line_rate_bps;
    candidate->plan.actual_line_rate_bps = actual;
    candidate->plan.line_rate_error_ppm = signed_error_ppm(
        request->requested_line_rate_bps, actual);
    candidate->plan.ad9528_doubler = ad->doubler;
    candidate->plan.ad9528_r1 = ad->r1;
    candidate->plan.ad9528_n2 = ad->n2;
    candidate->plan.ad9528_m1 = ad->m1;
    candidate->plan.ad9528_out_div = ad->out0_div;
    candidate->plan.ad9528_pfd_hz = ad->pfd_hz;
    candidate->plan.ad9528_vco_hz = ad->vco_hz;
    candidate->plan.ad9528_out0_hz = (uint32_t)desired;
    candidate->plan.ad9528_expected_count = (uint32_t)((desired + 1000U) / 2000U);
    candidate->plan.ad9528_register_plan_id = ad->register_plan_id;
    candidate->plan.gt_pll_type = gt->pll_type;
    candidate->plan.gt_refclk_div = gt->refclk_div;
    candidate->plan.gt_fbdiv = gt->fbdiv;
    candidate->plan.gt_fbdiv_45 = gt->fbdiv_45;
    candidate->plan.gt_txout_div = gt->txout_div;
    candidate->plan.gt_txout_div_encoding = gt->txout_div_encoding;
    candidate->plan.gt_drp_encoding_confirmed = gt->drp_encoding_confirmed;
    candidate->plan.gt_vco_hz = vco;
    candidate->plan.mmcm_mult = mmcm->mult;
    candidate->plan.mmcm_write_count = RUNTIME_MMCM_WRITE_COUNT;
    memcpy(candidate->plan.mmcm_writes, mmcm->writes, sizeof(mmcm->writes));
    candidate->plan.mmcm_vco_hz = mmcm_vco;
    candidate->plan.txoutclk_hz = (uint32_t)round_fraction(line_num, line_den * 32ULL);
    candidate->plan.txusrclk_hz = candidate->plan.txoutclk_hz;
    candidate->plan.txusrclk2_hz = (uint32_t)round_fraction(line_num, line_den * 64ULL);
    candidate->plan.verify_expected_count = (uint32_t)round_fraction(line_num, line_den * 64000ULL);
    candidate->plan.verify_tolerance = (candidate->plan.verify_expected_count + 99U) / 100U;
    candidate->plan.implementation_path = LASER_RUNTIME_PATH_AD9528_OUT0;
    candidate->plan.plan_executable = gt->drp_encoding_confirmed;
    candidate->plan.evidence_level = 1U;
    candidate->plan.rejected_reason = gt->drp_encoding_confirmed ?
        "NONE" : "GT_DRP_ENCODING_NOT_CONFIRMED";
    fill_ad9528_writes(&candidate->plan);
    candidate->absolute_error_bps = absolute_difference(
        request->requested_line_rate_bps, actual);
    candidate->ad9528_margin_hz = minimum_u32(ad->vco_lower_margin_hz,
                                              ad->vco_upper_margin_hz);
    if (gt->pll_type == RUNTIME_PLL_CPLL) {
        candidate->gt_margin_hz = minimum_u32((uint32_t)(vco - CPLL_VCO_MIN_HZ),
                                              (uint32_t)(CPLL_VCO_MAX_HZ - vco));
    } else if (upper_qpll != 0) {
        candidate->gt_margin_hz = minimum_u32((uint32_t)(vco - QPLL_HIGH_VCO_MIN_HZ),
                                              (uint32_t)(QPLL_HIGH_VCO_MAX_HZ - vco));
    } else {
        candidate->gt_margin_hz = minimum_u32((uint32_t)(vco - QPLL_LOW_VCO_MIN_HZ),
                                              (uint32_t)(QPLL_LOW_VCO_MAX_HZ - vco));
    }
    candidate->mmcm_margin_hz = mmcm_margin;
    candidate->register_difference = register_difference(current, &candidate->plan);
    candidate->pll_change = (current != NULL && current->plan_executable != 0U &&
                             current->gt_pll_type != candidate->plan.gt_pll_type);
    candidate->txout_div_change = (current != NULL && current->plan_executable != 0U &&
                                   current->gt_txout_div != candidate->plan.gt_txout_div);
    candidate->not_n2_only = (current == NULL || current->plan_executable == 0U ||
        current->ad9528_r1 != candidate->plan.ad9528_r1 ||
        current->ad9528_m1 != candidate->plan.ad9528_m1 ||
        current->ad9528_out_div != candidate->plan.ad9528_out_div);
    candidate->ad_index = ad_index;
    candidate->gt_index = gt_index;
    candidate->valid = 1U;
    return 1;
}

int laser_runtime_rate_plan(const RuntimeRatePlanRequest *request,
                            const RuntimeRatePlan *current_plan,
                            RuntimeRatePlan *result,
                            RuntimeRatePlanDiagnostics *diagnostics)
{
    RuntimeCandidate best = {0};
    RuntimeCandidate best_non_executable = {0};
    size_t gt_index;
    if (request == NULL || result == NULL || diagnostics == NULL ||
        request->requested_line_rate_bps == 0U ||
        request->requested_line_rate_bps > GTX_MAX_LINE_RATE_BPS ||
        request->maximum_error_ppm == 0U ||
        request->maximum_error_ppm > LASER_RUNTIME_RATE_MAXIMUM_ALLOWED_PPM ||
        request->preferred_error_ppm > request->maximum_error_ppm ||
        request->allowed_pll_type > LASER_RUNTIME_PLL_BOTH ||
        request->allowed_implementation_path != LASER_RUNTIME_PATH_AD9528_OUT0) {
        return LASER_RUNTIME_PLAN_BAD_ARGUMENT;
    }
    memset(result, 0, sizeof(*result));
    memset(diagnostics, 0, sizeof(*diagnostics));
    for (gt_index = 0U; gt_index < runtime_gt_tuple_count; ++gt_index) {
        const RuntimeGtTuple *gt = &runtime_gt_tuples[gt_index];
        uint64_t need_num;
        uint64_t need_den;
        uint64_t desired_refclk;
        size_t lower;
        int offset;
        diagnostics->gt_tuples_considered++;
        if (request->allowed_pll_type != LASER_RUNTIME_PLL_BOTH &&
            request->allowed_pll_type != gt->pll_type) continue;
        if (gt->pll_type == RUNTIME_PLL_CPLL) {
            need_num = request->requested_line_rate_bps * gt->refclk_div * gt->txout_div;
            need_den = (uint64_t)2U * gt->fbdiv_45 * gt->fbdiv;
        } else {
            need_num = request->requested_line_rate_bps * gt->refclk_div * gt->txout_div;
            need_den = gt->fbdiv;
        }
        desired_refclk = round_fraction(need_num, need_den);
        lower = ad9528_lower_bound(desired_refclk);
        for (offset = -4; offset <= 4; ++offset) {
            RuntimeCandidate candidate;
            size_t ad_index;
            if (offset < 0 && lower < (size_t)(-offset)) continue;
            ad_index = (offset < 0) ? lower - (size_t)(-offset) : lower + (size_t)offset;
            if (ad_index >= runtime_ad9528_config_count) continue;
            diagnostics->ad9528_candidates_considered++;
            if (!evaluate_candidate(request, current_plan, ad_index, gt_index,
                                    &candidate)) continue;
            diagnostics->tolerance_qualified++;
            diagnostics->mmcm_qualified++;
            if (candidate.plan.plan_executable != 0U) {
                diagnostics->executable_qualified++;
                if (candidate_better(&candidate, &best)) best = candidate;
            } else if (candidate_better(&candidate, &best_non_executable)) {
                best_non_executable = candidate;
            }
        }
    }
    if (best.valid != 0U) {
        *result = best.plan;
        return LASER_RUNTIME_PLAN_OK;
    }
    if (best_non_executable.valid != 0U) {
        *result = best_non_executable.plan;
        result->plan_executable = 0U;
        result->rejected_reason = "GT_DRP_ENCODING_NOT_CONFIRMED";
    } else {
        result->requested_line_rate_bps = request->requested_line_rate_bps;
        result->rejected_reason = "NO_LEGAL_PLAN_WITHIN_TOLERANCE";
    }
    return LASER_RUNTIME_PLAN_NO_SOLUTION;
}
