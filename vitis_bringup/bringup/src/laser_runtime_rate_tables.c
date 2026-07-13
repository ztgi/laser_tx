/*
 * Managed-Vitis source bridge for deterministic offline-generated tables.
 * The generated files remain repository-level artifacts shared by host tests
 * and the bare-metal application; this bridge makes them normal managed
 * application inputs without hand-added object files.
 */
#include "../../../generated/runtime_ad9528_configs.c"
#include "../../../generated/runtime_gt_tuples.c"
#include "../../../generated/runtime_mmcm_recipes.c"
