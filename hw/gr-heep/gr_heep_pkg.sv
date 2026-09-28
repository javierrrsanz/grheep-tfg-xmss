// Copyright 2024 Politecnico di Torino.
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// File: gr_heep_pkg.sv
// Author: Luigi Giuffrida
// Date: 16/10/2024
// Description: GR-HEEP pkg



package gr_heep_pkg;

  import addr_map_rule_pkg::*;
  import core_v_mini_mcu_pkg::*;

  // ---------------
  // CORE-V-MINI-MCU
  // ---------------

  // SPC
  localparam int unsigned AoSPCNum = 32'd1;

  localparam int unsigned DMAMasterPortsNum = DMA_NUM_MASTER_PORTS;
  localparam int unsigned DMACHNum = DMA_CH_NUM;

  // --------------------
  // CV-X-IF COPROCESSORS
  // --------------------



  // ----------------
  // EXTERNAL OBI BUS
  // ----------------

  // Number of masters and slaves
  localparam int unsigned ExtXbarNMaster = 32'd1;
  localparam int unsigned ExtXbarNSlave = 32'd0;
  localparam int unsigned ExtXbarNMasterRnd = ExtXbarNMaster > 0 ? ExtXbarNMaster : 32'd1;
  localparam int unsigned ExtXbarNSlaveRnd = ExtXbarNSlave > 0 ? ExtXbarNSlave : 32'd1;
  localparam int unsigned LogExtXbarNMaster = ExtXbarNMaster > 32'd1 ? $clog2(
      ExtXbarNMaster
  ) : 32'd1;
  localparam int unsigned LogExtXbarNSlave = ExtXbarNSlave > 32'd1 ? $clog2(ExtXbarNSlave) : 32'd1;


  // --------------------
  // EXTERNAL PERIPHERALS
  // --------------------

  // Number of external peripherals
  localparam int unsigned ExtPeriphNSlave = 32'd1;
  localparam int unsigned LogExtPeriphNSlave = (ExtPeriphNSlave > 32'd1) ? $clog2(
      ExtPeriphNSlave
  ) : 32'd1;
  localparam int unsigned ExtPeriphNSlaveRnd = (ExtPeriphNSlave > 32'd1) ? ExtPeriphNSlave : 32'd1;


  // Memory map
  // ----------
  // Xmss
  localparam int unsigned XmssPeriphIdx = 32'd0;
  localparam logic [31:0] XmssPeriphStartAddr = EXT_PERIPHERAL_START_ADDRESS + 32'h0;
  localparam logic [31:0] XmssPeriphSize = 32'h4000;
  localparam logic [31:0] XmssPeriphEndAddr = XmssPeriphStartAddr + 32'h4000;

  // External peripherals address map
  localparam addr_map_rule_t [ExtPeriphNSlave-1:0] ExtPeriphAddrRules = '{
      '{idx: XmssPeriphIdx, start_addr: XmssPeriphStartAddr, end_addr: XmssPeriphEndAddr}
  };

  localparam int unsigned ExtPeriphDefaultIdx = 32'd0;


  localparam int unsigned ExtInterrupts = 32'd1;

endpackage

