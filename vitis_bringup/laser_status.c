#include "laser_status.h"
#include "xil_printf.h"

static const char *laser_yes_no(uint32_t value)
{
    return value ? "yes" : "no";
}

void laser_print_status(uint32_t status)
{
    xil_printf("\r\nlaser status = 0x%08lx\r\n", (unsigned long)status);
    xil_printf("  cfg_valid       : %s\r\n",
               laser_yes_no(status & LASER_STATUS_CFG_VALID));
    xil_printf("  cfg_error       : %s\r\n",
               laser_yes_no(status & LASER_STATUS_CFG_ERROR));
    xil_printf("  pattern_valid   : %s\r\n",
               laser_yes_no(status & LASER_STATUS_PATTERN_VALID));
    xil_printf("  busy            : %s\r\n",
               laser_yes_no(status & LASER_STATUS_BUSY));
    xil_printf("  done            : %s\r\n",
               laser_yes_no(status & LASER_STATUS_DONE));
    xil_printf("  phase_active    : %s\r\n",
               laser_yes_no(status & LASER_STATUS_PHASE_ACTIVE));
    xil_printf("  sequence_active : %s\r\n",
               laser_yes_no(status & LASER_STATUS_SEQUENCE_ACTIVE));
    xil_printf("  phase_offset    : %lu\r\n",
               (unsigned long)LASER_STATUS_PHASE_OFFSET(status));
    xil_printf("  current_state   : %lu\r\n",
               (unsigned long)LASER_STATUS_CURRENT_STATE(status));
    xil_printf("  error_code      : 0x%02lx\r\n",
               (unsigned long)LASER_STATUS_ERROR_CODE(status));
}
