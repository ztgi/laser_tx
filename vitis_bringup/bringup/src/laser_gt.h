#ifndef LASER_GT_H
#define LASER_GT_H

#include <stdint.h>

#define LASER_GT_STATUS_CPLL_LOCK     0x00000001U
#define LASER_GT_STATUS_TX_RESET_DONE 0x00000002U
#define LASER_GT_STATUS_READY         0x00000004U
#define LASER_GT_STATUS_CTRL_RESET    0x00000008U
#define LASER_GT_STATUS_CURRENT_RATE_ID(s) (((s) >> 4) & 0xfU)
#define LASER_GT_STATUS_PROFILE(s)    LASER_GT_STATUS_CURRENT_RATE_ID(s)
#define LASER_GT_STATUS_ALREADY_CURRENT 0x00000100U
#define LASER_GT_STATUS_RATE_DONE       0x00000200U
#define LASER_GT_STATUS_RATE_BUSY       0x00000400U
#define LASER_GT_STATUS_RATE_ERROR      0x00000800U
#define LASER_GT_STATUS_GT_DRP_DONE     0x00001000U
#define LASER_GT_STATUS_MMCM_DRP_DONE   0x00002000U
#define LASER_GT_STATUS_GT_DRP_WRITTEN  0x00004000U
#define LASER_GT_STATUS_MMCM_DRP_WRITTEN 0x00008000U
#define LASER_GT_STATUS_RATE_STATE(s)   (((s) >> 16) & 0xffU)
#define LASER_GT_STATUS_RATE_ERROR_CODE(s) (((s) >> 24) & 0xffU)

#define LASER_RATE_STATE_IDLE             0x00U
#define LASER_RATE_STATE_REQUEST          0x01U
#define LASER_RATE_STATE_VALIDATE         0x02U
#define LASER_RATE_STATE_QUIESCE_TX       0x03U
#define LASER_RATE_STATE_ASSERT_RESET     0x04U
#define LASER_RATE_STATE_PROGRAM_GT_DRP   0x05U
#define LASER_RATE_STATE_PROGRAM_MMCM_DRP 0x06U
#define LASER_RATE_STATE_RELEASE_RESET    0x07U
#define LASER_RATE_STATE_WAIT_LOCK        0x08U
#define LASER_RATE_STATE_VERIFY_RATE      0x09U
#define LASER_RATE_STATE_DONE             0x0aU
#define LASER_RATE_STATE_WAIT_MMCM_RESET_RELEASE 0x0bU
#define LASER_RATE_STATE_ERROR            0x80U

#define LASER_RATE_ERR_NONE                         0x00U
#define LASER_RATE_ERR_UNSUPPORTED_RATE             0x01U
#define LASER_RATE_ERR_TX_QUIESCE_TIMEOUT           0x02U
#define LASER_RATE_ERR_GT_DRP_TIMEOUT               0x03U
#define LASER_RATE_ERR_GT_DRP_READBACK_MISMATCH     0x04U
#define LASER_RATE_ERR_MMCM_DRP_TIMEOUT             0x05U
#define LASER_RATE_ERR_MMCM_LOCK_TIMEOUT            0x06U
#define LASER_RATE_ERR_TX_RESETDONE_TIMEOUT         0x07U
#define LASER_RATE_ERR_GT_READY_TIMEOUT             0x08U
#define LASER_RATE_ERR_TXUSRCLK2_NOT_ALIVE          0x09U
#define LASER_RATE_ERR_TXUSRCLK2_FREQ_OUT_OF_WINDOW 0x0aU
#define LASER_RATE_ERR_CPLL_LOCK_TIMEOUT            0x0bU

int laser_gt_init(void);
uint32_t laser_gt_read_status(void);
int laser_gt_is_ready(uint32_t status);
uint32_t laser_gt_rate_id_to_mbps(uint32_t rate_id);
const char *laser_gt_rate_state_name(uint32_t state);
const char *laser_gt_rate_error_name(uint32_t error_code);
void laser_gt_print_status(uint32_t status);

#endif
