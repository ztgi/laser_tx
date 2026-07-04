#ifndef LASER_STATUS_H
#define LASER_STATUS_H

#include <stdint.h>

#define LASER_STATUS_CFG_VALID       0x00000001U
#define LASER_STATUS_CFG_ERROR       0x00000002U
#define LASER_STATUS_PATTERN_VALID   0x00000004U
#define LASER_STATUS_BUSY            0x00000008U
#define LASER_STATUS_DONE            0x00000010U
#define LASER_STATUS_PHASE_ACTIVE    0x00000020U
#define LASER_STATUS_SEQUENCE_ACTIVE 0x00000040U

#define LASER_STATUS_PHASE_OFFSET(s) (((s) >> 8) & 0xffU)
#define LASER_STATUS_CURRENT_STATE(s) (((s) >> 16) & 0xffU)
#define LASER_STATUS_ERROR_CODE(s)    (((s) >> 24) & 0xffU)

void laser_print_status(uint32_t status);

#endif
