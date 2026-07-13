#ifndef RUNTIME_GT_TUPLES_H
#define RUNTIME_GT_TUPLES_H
#include <stddef.h>
#include <stdint.h>
enum { RUNTIME_PLL_CPLL=0, RUNTIME_PLL_QPLL=1 };
typedef struct {
    uint8_t pll_type, refclk_div, fbdiv_45, fbdiv, txout_div;
    uint8_t qpll_fbdiv_ratio, cpll_refclk_div_encoding;
    uint8_t cpll_fbdiv_45_encoding, cpll_fbdiv_encoding;
    uint8_t txout_div_encoding, drp_encoding_confirmed;
} RuntimeGtTuple;
extern const RuntimeGtTuple runtime_gt_tuples[];
extern const size_t runtime_gt_tuple_count;
#endif
