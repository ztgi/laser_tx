#ifndef LASER_AD9528_H
#define LASER_AD9528_H

#include <stdint.h>
#include <stddef.h>

#define LASER_AD9528_PROFILE_PLAN_MAX_WRITES 8U

typedef struct {
    uint16_t reg;
    uint8_t old_value;
    uint8_t mask;
    uint8_t value;
    uint8_t new_value;
    uint8_t readback_mask;
    uint8_t readback_value;
    const char *field_description;
    uint8_t shared_resource;
} LaserAd9528RegisterPlan;

typedef struct {
    const char *profile_name;
    uint32_t configured_out0_hz;
    uint8_t write_count;
    uint8_t requires_io_update;
    uint8_t requires_sync;
    uint8_t affects_out0;
    uint8_t affects_shared_clock_tree;
    uint8_t may_affect_other_outputs;
    uint8_t directly_modifies_other_output_channels;
    uint8_t spi_identity_valid;
    uint8_t out0_ldo_enabled;
    uint8_t out0_channel_enabled;
    uint8_t chip_enabled;
    uint8_t clock_distribution_enabled;
    uint8_t requires_pll1_lock;
    uint8_t requires_pll2_lock;
    LaserAd9528RegisterPlan writes[LASER_AD9528_PROFILE_PLAN_MAX_WRITES];
} LaserAd9528ClockProfilePlan;

typedef enum {
    LASER_AD9528_CANDIDATE_IDLE = 0,
    LASER_AD9528_CANDIDATE_PRECHECK,
    LASER_AD9528_CANDIDATE_SNAPSHOT,
    LASER_AD9528_CANDIDATE_PROGRAM,
    LASER_AD9528_CANDIDATE_BUFFER_READBACK,
    LASER_AD9528_CANDIDATE_IO_UPDATE,
    LASER_AD9528_CANDIDATE_POST_READBACK,
    LASER_AD9528_CANDIDATE_READY_UNMEASURED,
    LASER_AD9528_CANDIDATE_ROLLBACK,
    LASER_AD9528_CANDIDATE_RESTORED,
    LASER_AD9528_CANDIDATE_ERROR
} LaserAd9528CandidateState;

typedef enum {
    LASER_AD9528_CANDIDATE_ERROR_NONE = 0,
    LASER_AD9528_CANDIDATE_ERROR_BUSY,
    LASER_AD9528_CANDIDATE_ERROR_UNSUPPORTED_PROFILE,
    LASER_AD9528_CANDIDATE_ERROR_IDENTITY_MISMATCH,
    LASER_AD9528_CANDIDATE_ERROR_PRECONDITION_MISMATCH,
    LASER_AD9528_CANDIDATE_ERROR_SPI_READ,
    LASER_AD9528_CANDIDATE_ERROR_SPI_WRITE,
    LASER_AD9528_CANDIDATE_ERROR_BUFFER_READBACK,
    LASER_AD9528_CANDIDATE_ERROR_IO_UPDATE,
    LASER_AD9528_CANDIDATE_ERROR_POST_READBACK,
    LASER_AD9528_CANDIDATE_ERROR_VCXO_STATUS,
    LASER_AD9528_CANDIDATE_ERROR_ROLLBACK_FAILED,
    LASER_AD9528_CANDIDATE_ERROR_NO_SNAPSHOT
} LaserAd9528CandidateError;

typedef struct {
    LaserAd9528CandidateState state;
    LaserAd9528CandidateError last_error;
    uint32_t configured_out0_hz;
    uint8_t runtime_active_likely;
    uint8_t vcxo_status_ok;
    uint8_t readback_ok;
    uint8_t snapshot_valid;
    uint8_t rollback_attempted;
    uint8_t rollback_success;
    uint8_t config_writes;
    uint8_t io_update_writes;
    uint16_t failed_reg;
    uint8_t failed_expected;
    uint8_t failed_actual;
} LaserAd9528CandidateStatus;

typedef struct {
    uint32_t chip_id_raw;
    uint32_t pll1_ctrl_raw;
    uint8_t pll2_ctrl_raw;
    uint8_t pll2_vco_ctrl_raw;
    uint8_t pll2_m1_raw;
    uint8_t pll2_r1_raw;
    uint8_t pll2_n2_raw;
    uint32_t out0_raw;
    uint8_t global_pd_raw;
    uint16_t channel_pd_raw;
    uint8_t status0_raw;
    uint8_t status1_raw;
    uint8_t status_pin_enable_raw;
    uint16_t readback_raw;
    uint8_t reg0200_raw;
    uint8_t reg0201_raw;
    uint8_t reg0205_raw;
    uint8_t reg0206_raw;
    uint8_t reg0209_raw;
    uint8_t reg032a_raw;
    uint8_t reg032d_raw;
    uint8_t reg0503_raw;
    uint8_t reg0504_raw;
    uint8_t pll1_ref_mode;
    uint8_t pll1_feedback_source_vcxo;
    uint8_t pll1_bypass_likely;
    uint8_t pll2_input_direct_vcxo_likely;
    uint8_t pll1_locked;
    uint8_t pll2_locked;
    uint8_t pll2_calibrating;
    uint8_t pll2_doubler_enabled;
    uint8_t out0_source;
    uint8_t out0_divider;
    uint8_t out0_driver_mode;
    uint8_t out0_config_enabled;
    uint8_t derived_vco_valid;
    uint8_t derived_out0_valid;
    uint32_t derived_vco_hz;
    uint32_t derived_out0_hz;
} LaserAd9528RuntimeState;

int32_t laser_ad9528_spi_init(void);
int32_t laser_ad9528_write(uint16_t reg, uint8_t data);
int32_t laser_ad9528_read(uint16_t reg, uint8_t *data);
int32_t laser_ad9528_read_chip_id(uint32_t *chip_id);
int32_t laser_ad9528_identify(uint8_t *product_id, uint8_t *revision,
                              uint8_t *vendor_id);
void laser_ad9528_get_last_identity(uint8_t *product_id, uint8_t *revision,
                                    uint8_t *vendor_id);
int32_t laser_ad9528_basic_check(void);
int32_t laser_ad9528_apply_rate_profile(uint32_t profile_id);
int32_t laser_ad9528_dump_runtime_state(LaserAd9528RuntimeState *state);
uint16_t laser_ad9528_last_read_error_reg(void);
void laser_ad9528_print_runtime_state(const LaserAd9528RuntimeState *state);
int32_t laser_ad9528_format_runtime_status(char *buffer, size_t buffer_size,
                                            const LaserAd9528RuntimeState *state);
int32_t laser_ad9528_format_default_image(char *buffer, size_t buffer_size,
                                           const LaserAd9528RuntimeState *state);
int32_t laser_ad9528_plan_clock_profile(const char *profile_name,
                                         LaserAd9528ClockProfilePlan *plan);
int32_t laser_ad9528_format_clock_profile_plan(
    char *buffer, size_t buffer_size, const LaserAd9528ClockProfilePlan *plan);
int32_t laser_ad9528_format_clock_profile_plan_transaction(
    char *buffer, size_t buffer_size, const LaserAd9528ClockProfilePlan *plan,
    uint32_t transaction_index);
int32_t laser_ad9528_candidate_set(const char *profile_name);
int32_t laser_ad9528_candidate_restore(void);
void laser_ad9528_get_candidate_status(LaserAd9528CandidateStatus *status);
const char *laser_ad9528_candidate_state_name(LaserAd9528CandidateState state);
const char *laser_ad9528_candidate_error_name(LaserAd9528CandidateError error);
int32_t laser_ad9528_format_candidate_status(
    char *buffer, size_t buffer_size, const LaserAd9528CandidateStatus *status,
    const char *response_prefix);

#endif
