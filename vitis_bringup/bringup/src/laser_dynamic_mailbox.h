#ifndef LASER_DYNAMIC_MAILBOX_H
#define LASER_DYNAMIC_MAILBOX_H

#include <stdint.h>

#include "laser_runtime_rate_planner.h"

#define LASER_DYNAMIC_MAILBOX_DEFAULT_TIMEOUT_MS 5000U

typedef struct {
    uint32_t raw;
    uint16_t sequence;
    uint8_t busy;
    uint8_t prepared;
    uint8_t switch_done;
    uint8_t switch_error;
    uint8_t rollback_done;
    uint8_t descriptor_valid;
    uint8_t verify_pass;
    uint8_t sequence_error;
    uint8_t failed_stage;
} LaserDynamicMailboxStatus;

int laser_dynamic_mailbox_init(void);
int laser_dynamic_mailbox_prepare(const RuntimeRatePlan *plan,
                                  uint32_t sequence);
int laser_dynamic_mailbox_wait_prepared(uint32_t sequence,
                                        uint32_t timeout_ms,
                                        LaserDynamicMailboxStatus *final_status);
int laser_dynamic_mailbox_signal_refclk_ready(void);
int laser_dynamic_mailbox_wait_switch(uint32_t sequence,
                                      uint32_t timeout_ms,
                                      LaserDynamicMailboxStatus *final_status);
int laser_dynamic_mailbox_signal_abort(void);
int laser_dynamic_mailbox_signal_rollback_ready(void);
int laser_dynamic_mailbox_wait_rollback(uint32_t sequence,
                                        uint32_t timeout_ms,
                                        LaserDynamicMailboxStatus *final_status);
int laser_dynamic_mailbox_read_status(LaserDynamicMailboxStatus *status);

#endif
