#ifndef LASER_HW_H
#define LASER_HW_H

#include "xparameters.h"

#if defined(XPAR_AXI_GPIO_0_DEVICE_ID)
#define LASER_GPIO_DEVICE_ID XPAR_AXI_GPIO_0_DEVICE_ID
#else
#error "AXI GPIO device ID macro was not generated. Check the Vitis BSP/xparameters.h."
#endif

#if defined(XPAR_AXI_BRAM_CTRL_0_S_AXI_BASEADDR)
#define LASER_BRAM_BASEADDR XPAR_AXI_BRAM_CTRL_0_S_AXI_BASEADDR
#elif defined(XPAR_AXI_BRAM_CTRL_0_BASEADDR)
#define LASER_BRAM_BASEADDR XPAR_AXI_BRAM_CTRL_0_BASEADDR
#else
#error "AXI BRAM Controller base-address macro was not generated."
#endif

#define LASER_GPIO_CTRL_CHANNEL   1U
#define LASER_GPIO_STATUS_CHANNEL 2U

#define LASER_CONFIG_STRIDE_BYTES 32U
#define LASER_CONFIG_WORD_COUNT    8U

#endif
