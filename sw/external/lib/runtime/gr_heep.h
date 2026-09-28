// Copyright 2022 EPFL and Politecnico di Torino.
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// File: gr_heep.h
// Author: Luigi Giuffrida
// Date: 09/11/2024
// Description: Address map for gr_heep external peripherals.



#ifndef GR_HEEP_H
#define GR_HEEP_H

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

#include "core_v_mini_mcu.h"

// Number of masters and slaves on the external crossbar
#define EXT_XBAR_NMASTER 1
#define EXT_XBAR_NSLAVE 0


// Memory map
// ----------


// Peripheral map
// ----------



// XMSS
#define XMSS_PERIPH_START_ADDRESS (EXT_PERIPHERAL_START_ADDRESS + 0x0)
#define XMSS_PERIPH_SIZE 0x4000
#define XMSS_PERIPH_END_ADDRESS (XMSS_PERIPH_START_ADDRESS + 0x4000)


#ifdef __cplusplus
} // extern "C"
#endif // __cplusplus

#endif // GR_HEEP_H
