// Copyright 2024 Politecnico di Torino, EPFL, and Univesidad Politecnica de Madrid.
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// File: gr_heep.sv
// Author: Luigi Giuffrida, David Mallasen, Iñigo Díez de Ulzurrun
// Description: GR-HEEP top-level module


module gr_heep (
  // X-HEEP interface
  inout wire clk_i,
  inout wire rst_ni,
  inout wire boot_select_i,
  inout wire execute_from_flash_i,
  inout wire jtag_tck_i,
  inout wire jtag_tms_i,
  inout wire jtag_trst_ni,
  inout wire jtag_tdi_i,
  inout wire jtag_tdo_o,
  inout wire uart_rx_i,
  inout wire uart_tx_o,
  inout wire exit_value_o,
  inout wire exit_valid_o,
  inout wire gpio_0_io,
  inout wire gpio_1_io,
  inout wire gpio_2_io,
  inout wire gpio_3_io,
  inout wire gpio_4_io,
  inout wire gpio_5_io,
  inout wire gpio_6_io,
  inout wire gpio_7_io,
  inout wire gpio_8_io,
  inout wire gpio_9_io,
  inout wire gpio_10_io,
  inout wire gpio_11_io,
  inout wire gpio_12_io,
  inout wire gpio_13_io,
  inout wire spi_flash_sck_io,
  inout wire spi_flash_cs_0_io,
  inout wire spi_flash_cs_1_io,
  inout wire spi_flash_sd_0_io,
  inout wire spi_flash_sd_1_io,
  inout wire spi_flash_sd_2_io,
  inout wire spi_flash_sd_3_io,
  inout wire spi_sck_io,
  inout wire spi_cs_0_io,
  inout wire spi_cs_1_io,
  inout wire spi_sd_0_io,
  inout wire spi_sd_1_io,
  inout wire spi_sd_2_io,
  inout wire spi_sd_3_io,
  inout wire spi_slave_sck_io,
  inout wire spi_slave_cs_io,
  inout wire spi_slave_miso_io,
  inout wire spi_slave_mosi_io,
  inout wire pdm2pcm_pdm_io,
  inout wire pdm2pcm_clk_io,
  inout wire i2s_sck_io,
  inout wire i2s_ws_io,
  inout wire i2s_sd_io,
  inout wire spi2_cs_0_io,
  inout wire spi2_cs_1_io,
  inout wire spi2_sck_io,
  inout wire spi2_sd_0_io,
  inout wire spi2_sd_1_io,
  inout wire spi2_sd_2_io,
  inout wire spi2_sd_3_io,
  inout wire i2c_scl_io,
  inout wire i2c_sda_io
);
  import obi_pkg::*;
  import reg_pkg::*;
  import fifo_pkg::*;
  import gr_heep_pkg::*;
  import core_v_mini_mcu_pkg::*;

  // PARAMETERS
  localparam int unsigned ExtXbarNmasterRnd = (gr_heep_pkg::ExtXbarNMaster > 0) ?
    gr_heep_pkg::ExtXbarNMaster : 32'd1;
  localparam int unsigned ExtDomainsRnd = core_v_mini_mcu_pkg::EXTERNAL_DOMAINS == 0 ?
    32'd1 : core_v_mini_mcu_pkg::EXTERNAL_DOMAINS;

  // INTERNAL SIGNALS
  // ----------------
  // Synchronized reset
  logic rst_nin_sync;

  // Exit value
  logic [31:0] exit_value;

  // X-HEEP external master ports
  obi_req_t heep_core_instr_req;
  obi_resp_t heep_core_instr_rsp;
  obi_req_t heep_core_data_req;
  obi_resp_t heep_core_data_rsp;
  obi_req_t heep_debug_master_req;
  obi_resp_t heep_debug_master_rsp;
  obi_req_t [DMA_NUM_MASTER_PORTS-1:0] heep_dma_read_req;
  obi_resp_t [DMA_NUM_MASTER_PORTS-1:0] heep_dma_read_rsp;
  obi_req_t [DMA_NUM_MASTER_PORTS-1:0] heep_dma_write_req;
  obi_resp_t [DMA_NUM_MASTER_PORTS-1:0] heep_dma_write_rsp;
  obi_req_t [DMA_NUM_MASTER_PORTS-1:0] heep_dma_addr_req;
  obi_resp_t [DMA_NUM_MASTER_PORTS-1:0] heep_dma_addr_rsp;
  fifo_req_t [core_v_mini_mcu_pkg::DMA_CH_NUM-1:0] hw_fifo_req;
  fifo_resp_t [core_v_mini_mcu_pkg::DMA_CH_NUM-1:0] hw_fifo_rsp;
  logic [core_v_mini_mcu_pkg::DMA_CH_NUM-1:0] hw_fifo_done;

  // External DMA slots
  logic [core_v_mini_mcu_pkg::DMA_CH_NUM-1:0] ext_dma_slot_tx;
  logic [core_v_mini_mcu_pkg::DMA_CH_NUM-1:0] ext_dma_slot_rx;
  logic [core_v_mini_mcu_pkg::DMA_CH_NUM-1:0] dma_done;

  // X-HEEP slave ports
  obi_req_t [ExtXbarNmasterRnd-1:0] heep_slave_req;
  obi_resp_t [ExtXbarNmasterRnd-1:0] heep_slave_rsp;


  // External master ports
  obi_req_t [ExtXbarNmasterRnd-1:0] gr_heep_master_req;
  obi_resp_t [ExtXbarNmasterRnd-1:0] gr_heep_master_resp;

  // X-HEEP external peripheral master ports
  reg_req_t heep_peripheral_req;
  reg_rsp_t heep_peripheral_rsp;

  // Interrupt vector
  logic [core_v_mini_mcu_pkg::NEXT_INT-1:0] ext_int_vector;
  logic intr_ext_peripheral;

  // Power Manager signals
  logic cpu_subsystem_powergate_switch_n;
  logic cpu_subsystem_powergate_switch_ack_n;
  logic peripheral_subsystem_powergate_switch_n;
  logic peripheral_subsystem_powergate_switch_ack_n;

  // External SPC interface signals
  reg_req_t [AoSPCNum-1:0] ext_ao_peripheral_req;
  reg_rsp_t [AoSPCNum-1:0] ext_ao_peripheral_resp;


  // PAD controller
  reg_req_t pad_req;
  reg_rsp_t pad_rsp;
  logic [core_v_mini_mcu_pkg::NUM_PAD-1:0][7:0] pad_attributes;
  logic [core_v_mini_mcu_pkg::NUM_PAD-1:0][0:0] pad_muxes;

  // External power domains
  logic [ExtDomainsRnd-1:0] external_subsystem_powergate_switch_n;
  logic [ExtDomainsRnd-1:0] external_subsystem_powergate_switch_ack_n;
  logic [ExtDomainsRnd-1:0] external_subsystem_powergate_iso_n;

  // External RAM banks retentive mode control
  logic [ExtDomainsRnd-1:0] external_ram_banks_set_retentive_n;

  // External domains reset
  logic [ExtDomainsRnd-1:0] external_subsystem_rst_n;

  // External domains clock-gating
  logic [ExtDomainsRnd-1:0] external_subsystem_clkgate_en_n;

  logic ext_debug_req;
  logic ext_debug_reset_n;

  // CORE-V eXtension Interface (CV-X-IF)
  if_xif ext_xif ();  // unused

  // CORE-V-MINI-MCU input/output pins
  logic clk_in_x, clk_out_x, clk_oe_x;
  logic rst_nin_x, rst_nout_x, rst_noe_x;
  logic boot_select_in_x, boot_select_out_x, boot_select_oe_x;
  logic execute_from_flash_in_x, execute_from_flash_out_x, execute_from_flash_oe_x;
  logic jtag_tck_in_x, jtag_tck_out_x, jtag_tck_oe_x;
  logic jtag_tms_in_x, jtag_tms_out_x, jtag_tms_oe_x;
  logic jtag_trst_nin_x, jtag_trst_nout_x, jtag_trst_noe_x;
  logic jtag_tdi_in_x, jtag_tdi_out_x, jtag_tdi_oe_x;
  logic jtag_tdo_in_x, jtag_tdo_out_x, jtag_tdo_oe_x;
  logic uart_rx_in_x, uart_rx_out_x, uart_rx_oe_x;
  logic uart_tx_in_x, uart_tx_out_x, uart_tx_oe_x;
  logic exit_value_in_x, exit_value_out_x, exit_value_oe_x;
  logic exit_valid_in_x, exit_valid_out_x, exit_valid_oe_x;
  logic gpio_0_in_x, gpio_0_out_x, gpio_0_oe_x;
  logic gpio_1_in_x, gpio_1_out_x, gpio_1_oe_x;
  logic gpio_2_in_x, gpio_2_out_x, gpio_2_oe_x;
  logic gpio_3_in_x, gpio_3_out_x, gpio_3_oe_x;
  logic gpio_4_in_x, gpio_4_out_x, gpio_4_oe_x;
  logic gpio_5_in_x, gpio_5_out_x, gpio_5_oe_x;
  logic gpio_6_in_x, gpio_6_out_x, gpio_6_oe_x;
  logic gpio_7_in_x, gpio_7_out_x, gpio_7_oe_x;
  logic gpio_8_in_x, gpio_8_out_x, gpio_8_oe_x;
  logic gpio_9_in_x, gpio_9_out_x, gpio_9_oe_x;
  logic gpio_10_in_x, gpio_10_out_x, gpio_10_oe_x;
  logic gpio_11_in_x, gpio_11_out_x, gpio_11_oe_x;
  logic gpio_12_in_x, gpio_12_out_x, gpio_12_oe_x;
  logic gpio_13_in_x, gpio_13_out_x, gpio_13_oe_x;
  logic spi_flash_sck_in_x, spi_flash_sck_out_x, spi_flash_sck_oe_x;
  logic spi_flash_cs_0_in_x, spi_flash_cs_0_out_x, spi_flash_cs_0_oe_x;
  logic spi_flash_cs_1_in_x, spi_flash_cs_1_out_x, spi_flash_cs_1_oe_x;
  logic spi_flash_sd_0_in_x, spi_flash_sd_0_out_x, spi_flash_sd_0_oe_x;
  logic spi_flash_sd_1_in_x, spi_flash_sd_1_out_x, spi_flash_sd_1_oe_x;
  logic spi_flash_sd_2_in_x, spi_flash_sd_2_out_x, spi_flash_sd_2_oe_x;
  logic spi_flash_sd_3_in_x, spi_flash_sd_3_out_x, spi_flash_sd_3_oe_x;
  logic spi_sck_in_x, spi_sck_out_x, spi_sck_oe_x;
  logic spi_cs_0_in_x, spi_cs_0_out_x, spi_cs_0_oe_x;
  logic spi_cs_1_in_x, spi_cs_1_out_x, spi_cs_1_oe_x;
  logic spi_sd_0_in_x, spi_sd_0_out_x, spi_sd_0_oe_x;
  logic spi_sd_1_in_x, spi_sd_1_out_x, spi_sd_1_oe_x;
  logic spi_sd_2_in_x, spi_sd_2_out_x, spi_sd_2_oe_x;
  logic spi_sd_3_in_x, spi_sd_3_out_x, spi_sd_3_oe_x;
  logic spi_slave_sck_in_x, spi_slave_sck_out_x, spi_slave_sck_oe_x;
  logic gpio_14_in_x, gpio_14_out_x, gpio_14_oe_x;
  logic spi_slave_sck_in_x_muxed, spi_slave_sck_out_x_muxed, spi_slave_sck_oe_x_muxed;
  logic spi_slave_cs_in_x, spi_slave_cs_out_x, spi_slave_cs_oe_x;
  logic gpio_15_in_x, gpio_15_out_x, gpio_15_oe_x;
  logic spi_slave_cs_in_x_muxed, spi_slave_cs_out_x_muxed, spi_slave_cs_oe_x_muxed;
  logic spi_slave_miso_in_x, spi_slave_miso_out_x, spi_slave_miso_oe_x;
  logic gpio_16_in_x, gpio_16_out_x, gpio_16_oe_x;
  logic spi_slave_miso_in_x_muxed, spi_slave_miso_out_x_muxed, spi_slave_miso_oe_x_muxed;
  logic spi_slave_mosi_in_x, spi_slave_mosi_out_x, spi_slave_mosi_oe_x;
  logic gpio_17_in_x, gpio_17_out_x, gpio_17_oe_x;
  logic spi_slave_mosi_in_x_muxed, spi_slave_mosi_out_x_muxed, spi_slave_mosi_oe_x_muxed;
  logic pdm2pcm_pdm_in_x, pdm2pcm_pdm_out_x, pdm2pcm_pdm_oe_x;
  logic gpio_18_in_x, gpio_18_out_x, gpio_18_oe_x;
  logic pdm2pcm_pdm_in_x_muxed, pdm2pcm_pdm_out_x_muxed, pdm2pcm_pdm_oe_x_muxed;
  logic pdm2pcm_clk_in_x, pdm2pcm_clk_out_x, pdm2pcm_clk_oe_x;
  logic gpio_19_in_x, gpio_19_out_x, gpio_19_oe_x;
  logic pdm2pcm_clk_in_x_muxed, pdm2pcm_clk_out_x_muxed, pdm2pcm_clk_oe_x_muxed;
  logic i2s_sck_in_x, i2s_sck_out_x, i2s_sck_oe_x;
  logic gpio_20_in_x, gpio_20_out_x, gpio_20_oe_x;
  logic i2s_sck_in_x_muxed, i2s_sck_out_x_muxed, i2s_sck_oe_x_muxed;
  logic i2s_ws_in_x, i2s_ws_out_x, i2s_ws_oe_x;
  logic gpio_21_in_x, gpio_21_out_x, gpio_21_oe_x;
  logic i2s_ws_in_x_muxed, i2s_ws_out_x_muxed, i2s_ws_oe_x_muxed;
  logic i2s_sd_in_x, i2s_sd_out_x, i2s_sd_oe_x;
  logic gpio_22_in_x, gpio_22_out_x, gpio_22_oe_x;
  logic i2s_sd_in_x_muxed, i2s_sd_out_x_muxed, i2s_sd_oe_x_muxed;
  logic spi2_cs_0_in_x, spi2_cs_0_out_x, spi2_cs_0_oe_x;
  logic gpio_23_in_x, gpio_23_out_x, gpio_23_oe_x;
  logic spi2_cs_0_in_x_muxed, spi2_cs_0_out_x_muxed, spi2_cs_0_oe_x_muxed;
  logic spi2_cs_1_in_x, spi2_cs_1_out_x, spi2_cs_1_oe_x;
  logic gpio_24_in_x, gpio_24_out_x, gpio_24_oe_x;
  logic spi2_cs_1_in_x_muxed, spi2_cs_1_out_x_muxed, spi2_cs_1_oe_x_muxed;
  logic spi2_sck_in_x, spi2_sck_out_x, spi2_sck_oe_x;
  logic gpio_25_in_x, gpio_25_out_x, gpio_25_oe_x;
  logic spi2_sck_in_x_muxed, spi2_sck_out_x_muxed, spi2_sck_oe_x_muxed;
  logic spi2_sd_0_in_x, spi2_sd_0_out_x, spi2_sd_0_oe_x;
  logic gpio_26_in_x, gpio_26_out_x, gpio_26_oe_x;
  logic spi2_sd_0_in_x_muxed, spi2_sd_0_out_x_muxed, spi2_sd_0_oe_x_muxed;
  logic spi2_sd_1_in_x, spi2_sd_1_out_x, spi2_sd_1_oe_x;
  logic gpio_27_in_x, gpio_27_out_x, gpio_27_oe_x;
  logic spi2_sd_1_in_x_muxed, spi2_sd_1_out_x_muxed, spi2_sd_1_oe_x_muxed;
  logic spi2_sd_2_in_x, spi2_sd_2_out_x, spi2_sd_2_oe_x;
  logic gpio_28_in_x, gpio_28_out_x, gpio_28_oe_x;
  logic spi2_sd_2_in_x_muxed, spi2_sd_2_out_x_muxed, spi2_sd_2_oe_x_muxed;
  logic spi2_sd_3_in_x, spi2_sd_3_out_x, spi2_sd_3_oe_x;
  logic gpio_29_in_x, gpio_29_out_x, gpio_29_oe_x;
  logic spi2_sd_3_in_x_muxed, spi2_sd_3_out_x_muxed, spi2_sd_3_oe_x_muxed;
  logic i2c_scl_in_x, i2c_scl_out_x, i2c_scl_oe_x;
  logic gpio_31_in_x, gpio_31_out_x, gpio_31_oe_x;
  logic i2c_scl_in_x_muxed, i2c_scl_out_x_muxed, i2c_scl_oe_x_muxed;
  logic i2c_sda_in_x, i2c_sda_out_x, i2c_sda_oe_x;
  logic gpio_30_in_x, gpio_30_out_x, gpio_30_oe_x;
  logic i2c_sda_in_x_muxed, i2c_sda_out_x_muxed, i2c_sda_oe_x_muxed;

  // --------------
  // SYSTEM MODULES
  // --------------

  // Reset synchronizer
  // ---------------
  rstgen rstgen_i (
    .clk_i      (clk_in_x),
    .rst_ni     (rst_nin_x),
    .test_mode_i(1'b0),          // not implemented
    .rst_no     (rst_nin_sync),
    .init_no    ()               // unused
  );

  // CORE-V-MINI-MCU (microcontroller)
  // ---------------------------------
  core_v_mini_mcu #(
    .EXT_XBAR_NMASTER(ExtXbarNMaster),
    .AO_SPC_NUM      (AoSPCNum),
    .EXT_HARTS       (1)
  ) core_v_mini_mcu_i (
    // MCU pads
    .clk_i(clk_in_x),
    .rst_ni(rst_nin_sync),
    .boot_select_i(boot_select_in_x),
    .execute_from_flash_i(execute_from_flash_in_x),
    .jtag_tck_i(jtag_tck_in_x),
    .jtag_tms_i(jtag_tms_in_x),
    .jtag_trst_ni(jtag_trst_nin_x),
    .jtag_tdi_i(jtag_tdi_in_x),
    .jtag_tdo_o(jtag_tdo_out_x),
    .uart_rx_i(uart_rx_in_x),
    .uart_tx_o(uart_tx_out_x),
    .exit_valid_o(exit_valid_out_x),
    .gpio_0_i(gpio_0_in_x),
    .gpio_0_o(gpio_0_out_x),
    .gpio_0_oe_o(gpio_0_oe_x),
    .gpio_1_i(gpio_1_in_x),
    .gpio_1_o(gpio_1_out_x),
    .gpio_1_oe_o(gpio_1_oe_x),
    .gpio_2_i(gpio_2_in_x),
    .gpio_2_o(gpio_2_out_x),
    .gpio_2_oe_o(gpio_2_oe_x),
    .gpio_3_i(gpio_3_in_x),
    .gpio_3_o(gpio_3_out_x),
    .gpio_3_oe_o(gpio_3_oe_x),
    .gpio_4_i(gpio_4_in_x),
    .gpio_4_o(gpio_4_out_x),
    .gpio_4_oe_o(gpio_4_oe_x),
    .gpio_5_i(gpio_5_in_x),
    .gpio_5_o(gpio_5_out_x),
    .gpio_5_oe_o(gpio_5_oe_x),
    .gpio_6_i(gpio_6_in_x),
    .gpio_6_o(gpio_6_out_x),
    .gpio_6_oe_o(gpio_6_oe_x),
    .gpio_7_i(gpio_7_in_x),
    .gpio_7_o(gpio_7_out_x),
    .gpio_7_oe_o(gpio_7_oe_x),
    .gpio_8_i(gpio_8_in_x),
    .gpio_8_o(gpio_8_out_x),
    .gpio_8_oe_o(gpio_8_oe_x),
    .gpio_9_i(gpio_9_in_x),
    .gpio_9_o(gpio_9_out_x),
    .gpio_9_oe_o(gpio_9_oe_x),
    .gpio_10_i(gpio_10_in_x),
    .gpio_10_o(gpio_10_out_x),
    .gpio_10_oe_o(gpio_10_oe_x),
    .gpio_11_i(gpio_11_in_x),
    .gpio_11_o(gpio_11_out_x),
    .gpio_11_oe_o(gpio_11_oe_x),
    .gpio_12_i(gpio_12_in_x),
    .gpio_12_o(gpio_12_out_x),
    .gpio_12_oe_o(gpio_12_oe_x),
    .gpio_13_i(gpio_13_in_x),
    .gpio_13_o(gpio_13_out_x),
    .gpio_13_oe_o(gpio_13_oe_x),
    .spi_flash_sck_i(spi_flash_sck_in_x),
    .spi_flash_sck_o(spi_flash_sck_out_x),
    .spi_flash_sck_oe_o(spi_flash_sck_oe_x),
    .spi_flash_cs_0_i(spi_flash_cs_0_in_x),
    .spi_flash_cs_0_o(spi_flash_cs_0_out_x),
    .spi_flash_cs_0_oe_o(spi_flash_cs_0_oe_x),
    .spi_flash_cs_1_i(spi_flash_cs_1_in_x),
    .spi_flash_cs_1_o(spi_flash_cs_1_out_x),
    .spi_flash_cs_1_oe_o(spi_flash_cs_1_oe_x),
    .spi_flash_sd_0_i(spi_flash_sd_0_in_x),
    .spi_flash_sd_0_o(spi_flash_sd_0_out_x),
    .spi_flash_sd_0_oe_o(spi_flash_sd_0_oe_x),
    .spi_flash_sd_1_i(spi_flash_sd_1_in_x),
    .spi_flash_sd_1_o(spi_flash_sd_1_out_x),
    .spi_flash_sd_1_oe_o(spi_flash_sd_1_oe_x),
    .spi_flash_sd_2_i(spi_flash_sd_2_in_x),
    .spi_flash_sd_2_o(spi_flash_sd_2_out_x),
    .spi_flash_sd_2_oe_o(spi_flash_sd_2_oe_x),
    .spi_flash_sd_3_i(spi_flash_sd_3_in_x),
    .spi_flash_sd_3_o(spi_flash_sd_3_out_x),
    .spi_flash_sd_3_oe_o(spi_flash_sd_3_oe_x),
    .spi_sck_i(spi_sck_in_x),
    .spi_sck_o(spi_sck_out_x),
    .spi_sck_oe_o(spi_sck_oe_x),
    .spi_cs_0_i(spi_cs_0_in_x),
    .spi_cs_0_o(spi_cs_0_out_x),
    .spi_cs_0_oe_o(spi_cs_0_oe_x),
    .spi_cs_1_i(spi_cs_1_in_x),
    .spi_cs_1_o(spi_cs_1_out_x),
    .spi_cs_1_oe_o(spi_cs_1_oe_x),
    .spi_sd_0_i(spi_sd_0_in_x),
    .spi_sd_0_o(spi_sd_0_out_x),
    .spi_sd_0_oe_o(spi_sd_0_oe_x),
    .spi_sd_1_i(spi_sd_1_in_x),
    .spi_sd_1_o(spi_sd_1_out_x),
    .spi_sd_1_oe_o(spi_sd_1_oe_x),
    .spi_sd_2_i(spi_sd_2_in_x),
    .spi_sd_2_o(spi_sd_2_out_x),
    .spi_sd_2_oe_o(spi_sd_2_oe_x),
    .spi_sd_3_i(spi_sd_3_in_x),
    .spi_sd_3_o(spi_sd_3_out_x),
    .spi_sd_3_oe_o(spi_sd_3_oe_x),
    .spi_slave_sck_i(spi_slave_sck_in_x),
    .gpio_14_i(gpio_14_in_x),
    .gpio_14_o(gpio_14_out_x),
    .gpio_14_oe_o(gpio_14_oe_x),
    .spi_slave_cs_i(spi_slave_cs_in_x),
    .gpio_15_i(gpio_15_in_x),
    .gpio_15_o(gpio_15_out_x),
    .gpio_15_oe_o(gpio_15_oe_x),
    .spi_slave_miso_i(spi_slave_miso_in_x),
    .spi_slave_miso_o(spi_slave_miso_out_x),
    .spi_slave_miso_oe_o(spi_slave_miso_oe_x),
    .gpio_16_i(gpio_16_in_x),
    .gpio_16_o(gpio_16_out_x),
    .gpio_16_oe_o(gpio_16_oe_x),
    .spi_slave_mosi_i(spi_slave_mosi_in_x),
    .gpio_17_i(gpio_17_in_x),
    .gpio_17_o(gpio_17_out_x),
    .gpio_17_oe_o(gpio_17_oe_x),
    .pdm2pcm_pdm_i(pdm2pcm_pdm_in_x),
    .pdm2pcm_pdm_o(pdm2pcm_pdm_out_x),
    .pdm2pcm_pdm_oe_o(pdm2pcm_pdm_oe_x),
    .gpio_18_i(gpio_18_in_x),
    .gpio_18_o(gpio_18_out_x),
    .gpio_18_oe_o(gpio_18_oe_x),
    .pdm2pcm_clk_i(pdm2pcm_clk_in_x),
    .pdm2pcm_clk_o(pdm2pcm_clk_out_x),
    .pdm2pcm_clk_oe_o(pdm2pcm_clk_oe_x),
    .gpio_19_i(gpio_19_in_x),
    .gpio_19_o(gpio_19_out_x),
    .gpio_19_oe_o(gpio_19_oe_x),
    .i2s_sck_i(i2s_sck_in_x),
    .i2s_sck_o(i2s_sck_out_x),
    .i2s_sck_oe_o(i2s_sck_oe_x),
    .gpio_20_i(gpio_20_in_x),
    .gpio_20_o(gpio_20_out_x),
    .gpio_20_oe_o(gpio_20_oe_x),
    .i2s_ws_i(i2s_ws_in_x),
    .i2s_ws_o(i2s_ws_out_x),
    .i2s_ws_oe_o(i2s_ws_oe_x),
    .gpio_21_i(gpio_21_in_x),
    .gpio_21_o(gpio_21_out_x),
    .gpio_21_oe_o(gpio_21_oe_x),
    .i2s_sd_i(i2s_sd_in_x),
    .i2s_sd_o(i2s_sd_out_x),
    .i2s_sd_oe_o(i2s_sd_oe_x),
    .gpio_22_i(gpio_22_in_x),
    .gpio_22_o(gpio_22_out_x),
    .gpio_22_oe_o(gpio_22_oe_x),
    .spi2_cs_0_i(spi2_cs_0_in_x),
    .spi2_cs_0_o(spi2_cs_0_out_x),
    .spi2_cs_0_oe_o(spi2_cs_0_oe_x),
    .gpio_23_i(gpio_23_in_x),
    .gpio_23_o(gpio_23_out_x),
    .gpio_23_oe_o(gpio_23_oe_x),
    .spi2_cs_1_i(spi2_cs_1_in_x),
    .spi2_cs_1_o(spi2_cs_1_out_x),
    .spi2_cs_1_oe_o(spi2_cs_1_oe_x),
    .gpio_24_i(gpio_24_in_x),
    .gpio_24_o(gpio_24_out_x),
    .gpio_24_oe_o(gpio_24_oe_x),
    .spi2_sck_i(spi2_sck_in_x),
    .spi2_sck_o(spi2_sck_out_x),
    .spi2_sck_oe_o(spi2_sck_oe_x),
    .gpio_25_i(gpio_25_in_x),
    .gpio_25_o(gpio_25_out_x),
    .gpio_25_oe_o(gpio_25_oe_x),
    .spi2_sd_0_i(spi2_sd_0_in_x),
    .spi2_sd_0_o(spi2_sd_0_out_x),
    .spi2_sd_0_oe_o(spi2_sd_0_oe_x),
    .gpio_26_i(gpio_26_in_x),
    .gpio_26_o(gpio_26_out_x),
    .gpio_26_oe_o(gpio_26_oe_x),
    .spi2_sd_1_i(spi2_sd_1_in_x),
    .spi2_sd_1_o(spi2_sd_1_out_x),
    .spi2_sd_1_oe_o(spi2_sd_1_oe_x),
    .gpio_27_i(gpio_27_in_x),
    .gpio_27_o(gpio_27_out_x),
    .gpio_27_oe_o(gpio_27_oe_x),
    .spi2_sd_2_i(spi2_sd_2_in_x),
    .spi2_sd_2_o(spi2_sd_2_out_x),
    .spi2_sd_2_oe_o(spi2_sd_2_oe_x),
    .gpio_28_i(gpio_28_in_x),
    .gpio_28_o(gpio_28_out_x),
    .gpio_28_oe_o(gpio_28_oe_x),
    .spi2_sd_3_i(spi2_sd_3_in_x),
    .spi2_sd_3_o(spi2_sd_3_out_x),
    .spi2_sd_3_oe_o(spi2_sd_3_oe_x),
    .gpio_29_i(gpio_29_in_x),
    .gpio_29_o(gpio_29_out_x),
    .gpio_29_oe_o(gpio_29_oe_x),
    .i2c_scl_i(i2c_scl_in_x),
    .i2c_scl_o(i2c_scl_out_x),
    .i2c_scl_oe_o(i2c_scl_oe_x),
    .gpio_31_i(gpio_31_in_x),
    .gpio_31_o(gpio_31_out_x),
    .gpio_31_oe_o(gpio_31_oe_x),
    .i2c_sda_i(i2c_sda_in_x),
    .i2c_sda_o(i2c_sda_out_x),
    .i2c_sda_oe_o(i2c_sda_oe_x),
    .gpio_30_i(gpio_30_in_x),
    .gpio_30_o(gpio_30_out_x),
    .gpio_30_oe_o(gpio_30_oe_x),

    // IDs
    .hart_id_i('0),
    .xheep_instance_id_i('0),

    // CORE-V eXtension Interface
    .xif_compressed_if(ext_xif),
    .xif_issue_if(ext_xif),
    .xif_commit_if(ext_xif),
    .xif_mem_if(ext_xif),
    .xif_mem_result_if(ext_xif),
    .xif_result_if(ext_xif),

    // Pad controller interface
    .pad_req_o (pad_req),
    .pad_resp_i(pad_rsp),

    // External slave ports
    .ext_xbar_master_req_i (heep_slave_req),
    .ext_xbar_master_resp_o(heep_slave_rsp),

    // External master ports
    .ext_core_instr_req_o(heep_core_instr_req),
    .ext_core_instr_resp_i(heep_core_instr_rsp),
    .ext_core_data_req_o(heep_core_data_req),
    .ext_core_data_resp_i(heep_core_data_rsp),
    .ext_debug_master_req_o(heep_debug_master_req),
    .ext_debug_master_resp_i(heep_debug_master_rsp),
    .ext_dma_read_req_o(heep_dma_read_req),
    .ext_dma_read_resp_i(heep_dma_read_rsp),
    .ext_dma_write_req_o(heep_dma_write_req),
    .ext_dma_write_resp_i(heep_dma_write_rsp),
    .ext_dma_addr_req_o(heep_dma_addr_req),
    .ext_dma_addr_resp_i(heep_dma_addr_rsp),
    .hw_fifo_req_o(hw_fifo_req),
    .hw_fifo_resp_i(hw_fifo_rsp),
    .hw_fifo_done_i(hw_fifo_done),

    // External peripherals slave ports
    .ext_peripheral_slave_req_o (heep_peripheral_req),
    .ext_peripheral_slave_resp_i(heep_peripheral_rsp),

    // SPC signals
    .ext_ao_peripheral_slave_req_i (ext_ao_peripheral_req),
    .ext_ao_peripheral_slave_resp_o(ext_ao_peripheral_resp),

    // Power switches connected by the backend
    .cpu_subsystem_powergate_switch_no(cpu_subsystem_powergate_switch_n),
    .cpu_subsystem_powergate_switch_ack_ni(cpu_subsystem_powergate_switch_ack_n),
    .peripheral_subsystem_powergate_switch_no(peripheral_subsystem_powergate_switch_n),
    .peripheral_subsystem_powergate_switch_ack_ni(peripheral_subsystem_powergate_switch_ack_n),

    .external_subsystem_powergate_switch_no(external_subsystem_powergate_switch_n),
    .external_subsystem_powergate_switch_ack_ni(external_subsystem_powergate_switch_ack_n),
    .external_subsystem_powergate_iso_no(external_subsystem_powergate_iso_n),

    // Control signals for external peripherals
    .external_subsystem_rst_no(external_subsystem_rst_n),
    .external_ram_banks_set_retentive_no(external_ram_banks_set_retentive_n),
    .external_subsystem_clkgate_en_no(external_subsystem_clkgate_en_n),

    // External interrupts
    .intr_vector_ext_i(ext_int_vector),
    .intr_ext_peripheral_i(intr_ext_peripheral),

    .ext_debug_req_o(ext_debug_req),
    .ext_debug_reset_no(ext_debug_reset_n),
    .ext_cpu_subsystem_rst_no(),

    .ext_dma_slot_tx_i(ext_dma_slot_tx),
    .ext_dma_slot_rx_i(ext_dma_slot_rx),

    .ext_dma_stop_i('0),
    .dma_done_o(dma_done),

    .exit_value_o(exit_value)
  );

  assign heep_core_instr_rsp = '0;
  assign heep_core_data_rsp = '0;
  assign heep_debug_master_rsp = '0;
  assign heep_dma_read_rsp = '0;
  assign heep_dma_write_rsp = '0;
  assign heep_dma_addr_rsp = '0;
  assign ext_ao_peripheral_req = '0;

  gr_heep_peripherals gr_heep_peripherals_i (
    .clk_i(clk_in_x),
    .rst_ni(rst_nin_sync),
    .gr_heep_master_req_o(heep_slave_req),
    .gr_heep_master_resp_i(heep_slave_rsp),
    .gr_heep_peripheral_req_i(heep_peripheral_req),
    .gr_heep_peripheral_rsp_o(heep_peripheral_rsp),
    .gr_heep_peripheral_vec_int_o(ext_int_vector[0:0]),
    .gr_heep_peripheral_int_o(intr_ext_peripheral)
  );

  assign hw_fifo_done = '0;
  assign hw_fifo_rsp = '0;
  assign ext_dma_slot_tx = '0;
  assign ext_dma_slot_rx = '0;
  assign ext_int_vector[NEXT_INT-1:1] = '0;
  assign exit_value_out_x = exit_value[0];

  // Pad ring
  // --------
  gr_heep_pad_ring gr_heep_pad_ring_i (
    .clk_o(clk_in_x),
    .clk_io(clk_i),
    .rst_no(rst_nin_x),
    .rst_nio(rst_ni),
    .boot_select_o(boot_select_in_x),
    .boot_select_io(boot_select_i),
    .execute_from_flash_o(execute_from_flash_in_x),
    .execute_from_flash_io(execute_from_flash_i),
    .jtag_tck_o(jtag_tck_in_x),
    .jtag_tck_io(jtag_tck_i),
    .jtag_tms_o(jtag_tms_in_x),
    .jtag_tms_io(jtag_tms_i),
    .jtag_trst_no(jtag_trst_nin_x),
    .jtag_trst_nio(jtag_trst_ni),
    .jtag_tdi_o(jtag_tdi_in_x),
    .jtag_tdi_io(jtag_tdi_i),
    .jtag_tdo_i(jtag_tdo_out_x),
    .jtag_tdo_io(jtag_tdo_o),
    .uart_rx_o(uart_rx_in_x),
    .uart_rx_io(uart_rx_i),
    .uart_tx_i(uart_tx_out_x),
    .uart_tx_io(uart_tx_o),
    .exit_value_i(exit_value_out_x),
    .exit_value_io(exit_value_o),
    .exit_valid_i(exit_valid_out_x),
    .exit_valid_io(exit_valid_o),
    .gpio_0_i(gpio_0_out_x),
    .gpio_0_oe_i(gpio_0_oe_x),
    .gpio_0_o(gpio_0_in_x),
    .gpio_0_io(gpio_0_io),
    .gpio_1_i(gpio_1_out_x),
    .gpio_1_oe_i(gpio_1_oe_x),
    .gpio_1_o(gpio_1_in_x),
    .gpio_1_io(gpio_1_io),
    .gpio_2_i(gpio_2_out_x),
    .gpio_2_oe_i(gpio_2_oe_x),
    .gpio_2_o(gpio_2_in_x),
    .gpio_2_io(gpio_2_io),
    .gpio_3_i(gpio_3_out_x),
    .gpio_3_oe_i(gpio_3_oe_x),
    .gpio_3_o(gpio_3_in_x),
    .gpio_3_io(gpio_3_io),
    .gpio_4_i(gpio_4_out_x),
    .gpio_4_oe_i(gpio_4_oe_x),
    .gpio_4_o(gpio_4_in_x),
    .gpio_4_io(gpio_4_io),
    .gpio_5_i(gpio_5_out_x),
    .gpio_5_oe_i(gpio_5_oe_x),
    .gpio_5_o(gpio_5_in_x),
    .gpio_5_io(gpio_5_io),
    .gpio_6_i(gpio_6_out_x),
    .gpio_6_oe_i(gpio_6_oe_x),
    .gpio_6_o(gpio_6_in_x),
    .gpio_6_io(gpio_6_io),
    .gpio_7_i(gpio_7_out_x),
    .gpio_7_oe_i(gpio_7_oe_x),
    .gpio_7_o(gpio_7_in_x),
    .gpio_7_io(gpio_7_io),
    .gpio_8_i(gpio_8_out_x),
    .gpio_8_oe_i(gpio_8_oe_x),
    .gpio_8_o(gpio_8_in_x),
    .gpio_8_io(gpio_8_io),
    .gpio_9_i(gpio_9_out_x),
    .gpio_9_oe_i(gpio_9_oe_x),
    .gpio_9_o(gpio_9_in_x),
    .gpio_9_io(gpio_9_io),
    .gpio_10_i(gpio_10_out_x),
    .gpio_10_oe_i(gpio_10_oe_x),
    .gpio_10_o(gpio_10_in_x),
    .gpio_10_io(gpio_10_io),
    .gpio_11_i(gpio_11_out_x),
    .gpio_11_oe_i(gpio_11_oe_x),
    .gpio_11_o(gpio_11_in_x),
    .gpio_11_io(gpio_11_io),
    .gpio_12_i(gpio_12_out_x),
    .gpio_12_oe_i(gpio_12_oe_x),
    .gpio_12_o(gpio_12_in_x),
    .gpio_12_io(gpio_12_io),
    .gpio_13_i(gpio_13_out_x),
    .gpio_13_oe_i(gpio_13_oe_x),
    .gpio_13_o(gpio_13_in_x),
    .gpio_13_io(gpio_13_io),
    .spi_flash_sck_i(spi_flash_sck_out_x),
    .spi_flash_sck_oe_i(spi_flash_sck_oe_x),
    .spi_flash_sck_o(spi_flash_sck_in_x),
    .spi_flash_sck_io(spi_flash_sck_io),
    .spi_flash_cs_0_i(spi_flash_cs_0_out_x),
    .spi_flash_cs_0_oe_i(spi_flash_cs_0_oe_x),
    .spi_flash_cs_0_o(spi_flash_cs_0_in_x),
    .spi_flash_cs_0_io(spi_flash_cs_0_io),
    .spi_flash_cs_1_i(spi_flash_cs_1_out_x),
    .spi_flash_cs_1_oe_i(spi_flash_cs_1_oe_x),
    .spi_flash_cs_1_o(spi_flash_cs_1_in_x),
    .spi_flash_cs_1_io(spi_flash_cs_1_io),
    .spi_flash_sd_0_i(spi_flash_sd_0_out_x),
    .spi_flash_sd_0_oe_i(spi_flash_sd_0_oe_x),
    .spi_flash_sd_0_o(spi_flash_sd_0_in_x),
    .spi_flash_sd_0_io(spi_flash_sd_0_io),
    .spi_flash_sd_1_i(spi_flash_sd_1_out_x),
    .spi_flash_sd_1_oe_i(spi_flash_sd_1_oe_x),
    .spi_flash_sd_1_o(spi_flash_sd_1_in_x),
    .spi_flash_sd_1_io(spi_flash_sd_1_io),
    .spi_flash_sd_2_i(spi_flash_sd_2_out_x),
    .spi_flash_sd_2_oe_i(spi_flash_sd_2_oe_x),
    .spi_flash_sd_2_o(spi_flash_sd_2_in_x),
    .spi_flash_sd_2_io(spi_flash_sd_2_io),
    .spi_flash_sd_3_i(spi_flash_sd_3_out_x),
    .spi_flash_sd_3_oe_i(spi_flash_sd_3_oe_x),
    .spi_flash_sd_3_o(spi_flash_sd_3_in_x),
    .spi_flash_sd_3_io(spi_flash_sd_3_io),
    .spi_sck_i(spi_sck_out_x),
    .spi_sck_oe_i(spi_sck_oe_x),
    .spi_sck_o(spi_sck_in_x),
    .spi_sck_io(spi_sck_io),
    .spi_cs_0_i(spi_cs_0_out_x),
    .spi_cs_0_oe_i(spi_cs_0_oe_x),
    .spi_cs_0_o(spi_cs_0_in_x),
    .spi_cs_0_io(spi_cs_0_io),
    .spi_cs_1_i(spi_cs_1_out_x),
    .spi_cs_1_oe_i(spi_cs_1_oe_x),
    .spi_cs_1_o(spi_cs_1_in_x),
    .spi_cs_1_io(spi_cs_1_io),
    .spi_sd_0_i(spi_sd_0_out_x),
    .spi_sd_0_oe_i(spi_sd_0_oe_x),
    .spi_sd_0_o(spi_sd_0_in_x),
    .spi_sd_0_io(spi_sd_0_io),
    .spi_sd_1_i(spi_sd_1_out_x),
    .spi_sd_1_oe_i(spi_sd_1_oe_x),
    .spi_sd_1_o(spi_sd_1_in_x),
    .spi_sd_1_io(spi_sd_1_io),
    .spi_sd_2_i(spi_sd_2_out_x),
    .spi_sd_2_oe_i(spi_sd_2_oe_x),
    .spi_sd_2_o(spi_sd_2_in_x),
    .spi_sd_2_io(spi_sd_2_io),
    .spi_sd_3_i(spi_sd_3_out_x),
    .spi_sd_3_oe_i(spi_sd_3_oe_x),
    .spi_sd_3_o(spi_sd_3_in_x),
    .spi_sd_3_io(spi_sd_3_io),
    .spi_slave_sck_i(spi_slave_sck_out_x_muxed),
    .spi_slave_sck_oe_i(spi_slave_sck_oe_x_muxed),
    .spi_slave_sck_o(spi_slave_sck_in_x_muxed),
    .spi_slave_sck_io(spi_slave_sck_io),
    .spi_slave_cs_i(spi_slave_cs_out_x_muxed),
    .spi_slave_cs_oe_i(spi_slave_cs_oe_x_muxed),
    .spi_slave_cs_o(spi_slave_cs_in_x_muxed),
    .spi_slave_cs_io(spi_slave_cs_io),
    .spi_slave_miso_i(spi_slave_miso_out_x_muxed),
    .spi_slave_miso_oe_i(spi_slave_miso_oe_x_muxed),
    .spi_slave_miso_o(spi_slave_miso_in_x_muxed),
    .spi_slave_miso_io(spi_slave_miso_io),
    .spi_slave_mosi_i(spi_slave_mosi_out_x_muxed),
    .spi_slave_mosi_oe_i(spi_slave_mosi_oe_x_muxed),
    .spi_slave_mosi_o(spi_slave_mosi_in_x_muxed),
    .spi_slave_mosi_io(spi_slave_mosi_io),
    .pdm2pcm_pdm_i(pdm2pcm_pdm_out_x_muxed),
    .pdm2pcm_pdm_oe_i(pdm2pcm_pdm_oe_x_muxed),
    .pdm2pcm_pdm_o(pdm2pcm_pdm_in_x_muxed),
    .pdm2pcm_pdm_io(pdm2pcm_pdm_io),
    .pdm2pcm_clk_i(pdm2pcm_clk_out_x_muxed),
    .pdm2pcm_clk_oe_i(pdm2pcm_clk_oe_x_muxed),
    .pdm2pcm_clk_o(pdm2pcm_clk_in_x_muxed),
    .pdm2pcm_clk_io(pdm2pcm_clk_io),
    .i2s_sck_i(i2s_sck_out_x_muxed),
    .i2s_sck_oe_i(i2s_sck_oe_x_muxed),
    .i2s_sck_o(i2s_sck_in_x_muxed),
    .i2s_sck_io(i2s_sck_io),
    .i2s_ws_i(i2s_ws_out_x_muxed),
    .i2s_ws_oe_i(i2s_ws_oe_x_muxed),
    .i2s_ws_o(i2s_ws_in_x_muxed),
    .i2s_ws_io(i2s_ws_io),
    .i2s_sd_i(i2s_sd_out_x_muxed),
    .i2s_sd_oe_i(i2s_sd_oe_x_muxed),
    .i2s_sd_o(i2s_sd_in_x_muxed),
    .i2s_sd_io(i2s_sd_io),
    .spi2_cs_0_i(spi2_cs_0_out_x_muxed),
    .spi2_cs_0_oe_i(spi2_cs_0_oe_x_muxed),
    .spi2_cs_0_o(spi2_cs_0_in_x_muxed),
    .spi2_cs_0_io(spi2_cs_0_io),
    .spi2_cs_1_i(spi2_cs_1_out_x_muxed),
    .spi2_cs_1_oe_i(spi2_cs_1_oe_x_muxed),
    .spi2_cs_1_o(spi2_cs_1_in_x_muxed),
    .spi2_cs_1_io(spi2_cs_1_io),
    .spi2_sck_i(spi2_sck_out_x_muxed),
    .spi2_sck_oe_i(spi2_sck_oe_x_muxed),
    .spi2_sck_o(spi2_sck_in_x_muxed),
    .spi2_sck_io(spi2_sck_io),
    .spi2_sd_0_i(spi2_sd_0_out_x_muxed),
    .spi2_sd_0_oe_i(spi2_sd_0_oe_x_muxed),
    .spi2_sd_0_o(spi2_sd_0_in_x_muxed),
    .spi2_sd_0_io(spi2_sd_0_io),
    .spi2_sd_1_i(spi2_sd_1_out_x_muxed),
    .spi2_sd_1_oe_i(spi2_sd_1_oe_x_muxed),
    .spi2_sd_1_o(spi2_sd_1_in_x_muxed),
    .spi2_sd_1_io(spi2_sd_1_io),
    .spi2_sd_2_i(spi2_sd_2_out_x_muxed),
    .spi2_sd_2_oe_i(spi2_sd_2_oe_x_muxed),
    .spi2_sd_2_o(spi2_sd_2_in_x_muxed),
    .spi2_sd_2_io(spi2_sd_2_io),
    .spi2_sd_3_i(spi2_sd_3_out_x_muxed),
    .spi2_sd_3_oe_i(spi2_sd_3_oe_x_muxed),
    .spi2_sd_3_o(spi2_sd_3_in_x_muxed),
    .spi2_sd_3_io(spi2_sd_3_io),
    .i2c_scl_i(i2c_scl_out_x_muxed),
    .i2c_scl_oe_i(i2c_scl_oe_x_muxed),
    .i2c_scl_o(i2c_scl_in_x_muxed),
    .i2c_scl_io(i2c_scl_io),
    .i2c_sda_i(i2c_sda_out_x_muxed),
    .i2c_sda_oe_i(i2c_sda_oe_x_muxed),
    .i2c_sda_o(i2c_sda_in_x_muxed),
    .i2c_sda_io(i2c_sda_io),

    // Pad attributes
    .pad_attributes_i(pad_attributes)
  );

  // Constant pad signals
  assign clk_out_x = 1'b0;
  assign clk_oe_x = 1'b0;
  assign rst_nout_x = 1'b0;
  assign rst_noe_x = 1'b0;
  assign boot_select_out_x = 1'b0;
  assign boot_select_oe_x = 1'b0;
  assign execute_from_flash_out_x = 1'b0;
  assign execute_from_flash_oe_x = 1'b0;
  assign jtag_tck_out_x = 1'b0;
  assign jtag_tck_oe_x = 1'b0;
  assign jtag_tms_out_x = 1'b0;
  assign jtag_tms_oe_x = 1'b0;
  assign jtag_trst_nout_x = 1'b0;
  assign jtag_trst_noe_x = 1'b0;
  assign jtag_tdi_out_x = 1'b0;
  assign jtag_tdi_oe_x = 1'b0;
  assign jtag_tdo_oe_x = 1'b1;
  assign uart_rx_out_x = 1'b0;
  assign uart_rx_oe_x = 1'b0;
  assign uart_tx_oe_x = 1'b1;
  assign exit_value_oe_x = 1'b1;
  assign exit_valid_oe_x = 1'b1;
  assign spi_slave_sck_out_x = 1'b0;
  assign spi_slave_sck_oe_x = 1'b0;
  assign spi_slave_cs_out_x = 1'b0;
  assign spi_slave_cs_oe_x = 1'b0;
  assign spi_slave_mosi_out_x = 1'b0;
  assign spi_slave_mosi_oe_x = 1'b0;

  // Shared pads multiplexing
  always_comb begin
    spi_slave_sck_in_x = 1'b0;
    gpio_14_in_x = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_SPI_SLAVE_SCK])
      0: begin

        spi_slave_sck_out_x_muxed = spi_slave_sck_out_x;
        spi_slave_sck_oe_x_muxed  = spi_slave_sck_oe_x;
        spi_slave_sck_in_x        = spi_slave_sck_in_x_muxed;
      end
      1: begin

        spi_slave_sck_out_x_muxed = gpio_14_out_x;
        spi_slave_sck_oe_x_muxed  = gpio_14_oe_x;
        gpio_14_in_x              = spi_slave_sck_in_x_muxed;
      end
      default: begin
        spi_slave_sck_out_x_muxed = spi_slave_sck_out_x;
        spi_slave_sck_oe_x_muxed  = spi_slave_sck_oe_x;
        spi_slave_sck_in_x        = spi_slave_sck_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    spi_slave_cs_in_x = 1'b0;
    gpio_15_in_x = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_SPI_SLAVE_CS])
      0: begin

        spi_slave_cs_out_x_muxed = spi_slave_cs_out_x;
        spi_slave_cs_oe_x_muxed  = spi_slave_cs_oe_x;
        spi_slave_cs_in_x        = spi_slave_cs_in_x_muxed;
      end
      1: begin

        spi_slave_cs_out_x_muxed = gpio_15_out_x;
        spi_slave_cs_oe_x_muxed  = gpio_15_oe_x;
        gpio_15_in_x             = spi_slave_cs_in_x_muxed;
      end
      default: begin
        spi_slave_cs_out_x_muxed = spi_slave_cs_out_x;
        spi_slave_cs_oe_x_muxed  = spi_slave_cs_oe_x;
        spi_slave_cs_in_x        = spi_slave_cs_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    spi_slave_miso_in_x = 1'b0;
    gpio_16_in_x = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_SPI_SLAVE_MISO])
      0: begin

        spi_slave_miso_out_x_muxed = spi_slave_miso_out_x;
        spi_slave_miso_oe_x_muxed  = spi_slave_miso_oe_x;
        spi_slave_miso_in_x        = spi_slave_miso_in_x_muxed;
      end
      1: begin

        spi_slave_miso_out_x_muxed = gpio_16_out_x;
        spi_slave_miso_oe_x_muxed  = gpio_16_oe_x;
        gpio_16_in_x               = spi_slave_miso_in_x_muxed;
      end
      default: begin
        spi_slave_miso_out_x_muxed = spi_slave_miso_out_x;
        spi_slave_miso_oe_x_muxed  = spi_slave_miso_oe_x;
        spi_slave_miso_in_x        = spi_slave_miso_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    spi_slave_mosi_in_x = 1'b0;
    gpio_17_in_x = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_SPI_SLAVE_MOSI])
      0: begin

        spi_slave_mosi_out_x_muxed = spi_slave_mosi_out_x;
        spi_slave_mosi_oe_x_muxed  = spi_slave_mosi_oe_x;
        spi_slave_mosi_in_x        = spi_slave_mosi_in_x_muxed;
      end
      1: begin

        spi_slave_mosi_out_x_muxed = gpio_17_out_x;
        spi_slave_mosi_oe_x_muxed  = gpio_17_oe_x;
        gpio_17_in_x               = spi_slave_mosi_in_x_muxed;
      end
      default: begin
        spi_slave_mosi_out_x_muxed = spi_slave_mosi_out_x;
        spi_slave_mosi_oe_x_muxed  = spi_slave_mosi_oe_x;
        spi_slave_mosi_in_x        = spi_slave_mosi_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    pdm2pcm_pdm_in_x = 1'b0;
    gpio_18_in_x = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_PDM2PCM_PDM])
      0: begin

        pdm2pcm_pdm_out_x_muxed = pdm2pcm_pdm_out_x;
        pdm2pcm_pdm_oe_x_muxed  = pdm2pcm_pdm_oe_x;
        pdm2pcm_pdm_in_x        = pdm2pcm_pdm_in_x_muxed;
      end
      1: begin

        pdm2pcm_pdm_out_x_muxed = gpio_18_out_x;
        pdm2pcm_pdm_oe_x_muxed  = gpio_18_oe_x;
        gpio_18_in_x            = pdm2pcm_pdm_in_x_muxed;
      end
      default: begin
        pdm2pcm_pdm_out_x_muxed = pdm2pcm_pdm_out_x;
        pdm2pcm_pdm_oe_x_muxed  = pdm2pcm_pdm_oe_x;
        pdm2pcm_pdm_in_x        = pdm2pcm_pdm_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    pdm2pcm_clk_in_x = 1'b0;
    gpio_19_in_x = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_PDM2PCM_CLK])
      0: begin

        pdm2pcm_clk_out_x_muxed = pdm2pcm_clk_out_x;
        pdm2pcm_clk_oe_x_muxed  = pdm2pcm_clk_oe_x;
        pdm2pcm_clk_in_x        = pdm2pcm_clk_in_x_muxed;
      end
      1: begin

        pdm2pcm_clk_out_x_muxed = gpio_19_out_x;
        pdm2pcm_clk_oe_x_muxed  = gpio_19_oe_x;
        gpio_19_in_x            = pdm2pcm_clk_in_x_muxed;
      end
      default: begin
        pdm2pcm_clk_out_x_muxed = pdm2pcm_clk_out_x;
        pdm2pcm_clk_oe_x_muxed  = pdm2pcm_clk_oe_x;
        pdm2pcm_clk_in_x        = pdm2pcm_clk_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    i2s_sck_in_x = 1'b0;
    gpio_20_in_x = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_I2S_SCK])
      0: begin

        i2s_sck_out_x_muxed = i2s_sck_out_x;
        i2s_sck_oe_x_muxed  = i2s_sck_oe_x;
        i2s_sck_in_x        = i2s_sck_in_x_muxed;
      end
      1: begin

        i2s_sck_out_x_muxed = gpio_20_out_x;
        i2s_sck_oe_x_muxed  = gpio_20_oe_x;
        gpio_20_in_x        = i2s_sck_in_x_muxed;
      end
      default: begin
        i2s_sck_out_x_muxed = i2s_sck_out_x;
        i2s_sck_oe_x_muxed  = i2s_sck_oe_x;
        i2s_sck_in_x        = i2s_sck_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    i2s_ws_in_x  = 1'b0;
    gpio_21_in_x = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_I2S_WS])
      0: begin

        i2s_ws_out_x_muxed = i2s_ws_out_x;
        i2s_ws_oe_x_muxed  = i2s_ws_oe_x;
        i2s_ws_in_x        = i2s_ws_in_x_muxed;
      end
      1: begin

        i2s_ws_out_x_muxed = gpio_21_out_x;
        i2s_ws_oe_x_muxed  = gpio_21_oe_x;
        gpio_21_in_x       = i2s_ws_in_x_muxed;
      end
      default: begin
        i2s_ws_out_x_muxed = i2s_ws_out_x;
        i2s_ws_oe_x_muxed  = i2s_ws_oe_x;
        i2s_ws_in_x        = i2s_ws_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    i2s_sd_in_x  = 1'b0;
    gpio_22_in_x = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_I2S_SD])
      0: begin

        i2s_sd_out_x_muxed = i2s_sd_out_x;
        i2s_sd_oe_x_muxed  = i2s_sd_oe_x;
        i2s_sd_in_x        = i2s_sd_in_x_muxed;
      end
      1: begin

        i2s_sd_out_x_muxed = gpio_22_out_x;
        i2s_sd_oe_x_muxed  = gpio_22_oe_x;
        gpio_22_in_x       = i2s_sd_in_x_muxed;
      end
      default: begin
        i2s_sd_out_x_muxed = i2s_sd_out_x;
        i2s_sd_oe_x_muxed  = i2s_sd_oe_x;
        i2s_sd_in_x        = i2s_sd_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    spi2_cs_0_in_x = 1'b0;
    gpio_23_in_x   = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_SPI2_CS_0])
      0: begin

        spi2_cs_0_out_x_muxed = spi2_cs_0_out_x;
        spi2_cs_0_oe_x_muxed  = spi2_cs_0_oe_x;
        spi2_cs_0_in_x        = spi2_cs_0_in_x_muxed;
      end
      1: begin

        spi2_cs_0_out_x_muxed = gpio_23_out_x;
        spi2_cs_0_oe_x_muxed  = gpio_23_oe_x;
        gpio_23_in_x          = spi2_cs_0_in_x_muxed;
      end
      default: begin
        spi2_cs_0_out_x_muxed = spi2_cs_0_out_x;
        spi2_cs_0_oe_x_muxed  = spi2_cs_0_oe_x;
        spi2_cs_0_in_x        = spi2_cs_0_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    spi2_cs_1_in_x = 1'b0;
    gpio_24_in_x   = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_SPI2_CS_1])
      0: begin

        spi2_cs_1_out_x_muxed = spi2_cs_1_out_x;
        spi2_cs_1_oe_x_muxed  = spi2_cs_1_oe_x;
        spi2_cs_1_in_x        = spi2_cs_1_in_x_muxed;
      end
      1: begin

        spi2_cs_1_out_x_muxed = gpio_24_out_x;
        spi2_cs_1_oe_x_muxed  = gpio_24_oe_x;
        gpio_24_in_x          = spi2_cs_1_in_x_muxed;
      end
      default: begin
        spi2_cs_1_out_x_muxed = spi2_cs_1_out_x;
        spi2_cs_1_oe_x_muxed  = spi2_cs_1_oe_x;
        spi2_cs_1_in_x        = spi2_cs_1_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    spi2_sck_in_x = 1'b0;
    gpio_25_in_x  = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_SPI2_SCK])
      0: begin

        spi2_sck_out_x_muxed = spi2_sck_out_x;
        spi2_sck_oe_x_muxed  = spi2_sck_oe_x;
        spi2_sck_in_x        = spi2_sck_in_x_muxed;
      end
      1: begin

        spi2_sck_out_x_muxed = gpio_25_out_x;
        spi2_sck_oe_x_muxed  = gpio_25_oe_x;
        gpio_25_in_x         = spi2_sck_in_x_muxed;
      end
      default: begin
        spi2_sck_out_x_muxed = spi2_sck_out_x;
        spi2_sck_oe_x_muxed  = spi2_sck_oe_x;
        spi2_sck_in_x        = spi2_sck_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    spi2_sd_0_in_x = 1'b0;
    gpio_26_in_x   = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_SPI2_SD_0])
      0: begin

        spi2_sd_0_out_x_muxed = spi2_sd_0_out_x;
        spi2_sd_0_oe_x_muxed  = spi2_sd_0_oe_x;
        spi2_sd_0_in_x        = spi2_sd_0_in_x_muxed;
      end
      1: begin

        spi2_sd_0_out_x_muxed = gpio_26_out_x;
        spi2_sd_0_oe_x_muxed  = gpio_26_oe_x;
        gpio_26_in_x          = spi2_sd_0_in_x_muxed;
      end
      default: begin
        spi2_sd_0_out_x_muxed = spi2_sd_0_out_x;
        spi2_sd_0_oe_x_muxed  = spi2_sd_0_oe_x;
        spi2_sd_0_in_x        = spi2_sd_0_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    spi2_sd_1_in_x = 1'b0;
    gpio_27_in_x   = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_SPI2_SD_1])
      0: begin

        spi2_sd_1_out_x_muxed = spi2_sd_1_out_x;
        spi2_sd_1_oe_x_muxed  = spi2_sd_1_oe_x;
        spi2_sd_1_in_x        = spi2_sd_1_in_x_muxed;
      end
      1: begin

        spi2_sd_1_out_x_muxed = gpio_27_out_x;
        spi2_sd_1_oe_x_muxed  = gpio_27_oe_x;
        gpio_27_in_x          = spi2_sd_1_in_x_muxed;
      end
      default: begin
        spi2_sd_1_out_x_muxed = spi2_sd_1_out_x;
        spi2_sd_1_oe_x_muxed  = spi2_sd_1_oe_x;
        spi2_sd_1_in_x        = spi2_sd_1_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    spi2_sd_2_in_x = 1'b0;
    gpio_28_in_x   = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_SPI2_SD_2])
      0: begin

        spi2_sd_2_out_x_muxed = spi2_sd_2_out_x;
        spi2_sd_2_oe_x_muxed  = spi2_sd_2_oe_x;
        spi2_sd_2_in_x        = spi2_sd_2_in_x_muxed;
      end
      1: begin

        spi2_sd_2_out_x_muxed = gpio_28_out_x;
        spi2_sd_2_oe_x_muxed  = gpio_28_oe_x;
        gpio_28_in_x          = spi2_sd_2_in_x_muxed;
      end
      default: begin
        spi2_sd_2_out_x_muxed = spi2_sd_2_out_x;
        spi2_sd_2_oe_x_muxed  = spi2_sd_2_oe_x;
        spi2_sd_2_in_x        = spi2_sd_2_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    spi2_sd_3_in_x = 1'b0;
    gpio_29_in_x   = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_SPI2_SD_3])
      0: begin

        spi2_sd_3_out_x_muxed = spi2_sd_3_out_x;
        spi2_sd_3_oe_x_muxed  = spi2_sd_3_oe_x;
        spi2_sd_3_in_x        = spi2_sd_3_in_x_muxed;
      end
      1: begin

        spi2_sd_3_out_x_muxed = gpio_29_out_x;
        spi2_sd_3_oe_x_muxed  = gpio_29_oe_x;
        gpio_29_in_x          = spi2_sd_3_in_x_muxed;
      end
      default: begin
        spi2_sd_3_out_x_muxed = spi2_sd_3_out_x;
        spi2_sd_3_oe_x_muxed  = spi2_sd_3_oe_x;
        spi2_sd_3_in_x        = spi2_sd_3_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    i2c_scl_in_x = 1'b0;
    gpio_31_in_x = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_I2C_SCL])
      0: begin

        i2c_scl_out_x_muxed = i2c_scl_out_x;
        i2c_scl_oe_x_muxed  = i2c_scl_oe_x;
        i2c_scl_in_x        = i2c_scl_in_x_muxed;
      end
      1: begin

        i2c_scl_out_x_muxed = gpio_31_out_x;
        i2c_scl_oe_x_muxed  = gpio_31_oe_x;
        gpio_31_in_x        = i2c_scl_in_x_muxed;
      end
      default: begin
        i2c_scl_out_x_muxed = i2c_scl_out_x;
        i2c_scl_oe_x_muxed  = i2c_scl_oe_x;
        i2c_scl_in_x        = i2c_scl_in_x_muxed;
      end
    endcase
  end
  always_comb begin
    i2c_sda_in_x = 1'b0;
    gpio_30_in_x = 1'b0;
    unique case (pad_muxes[core_v_mini_mcu_pkg::PAD_I2C_SDA])
      0: begin

        i2c_sda_out_x_muxed = i2c_sda_out_x;
        i2c_sda_oe_x_muxed  = i2c_sda_oe_x;
        i2c_sda_in_x        = i2c_sda_in_x_muxed;
      end
      1: begin

        i2c_sda_out_x_muxed = gpio_30_out_x;
        i2c_sda_oe_x_muxed  = gpio_30_oe_x;
        gpio_30_in_x        = i2c_sda_in_x_muxed;
      end
      default: begin
        i2c_sda_out_x_muxed = i2c_sda_out_x;
        i2c_sda_oe_x_muxed  = i2c_sda_oe_x;
        i2c_sda_in_x        = i2c_sda_in_x_muxed;
      end
    endcase
  end

  // Pad control
  // -----------
  pad_control #(
    .reg_req_t(reg_req_t),
    .reg_rsp_t(reg_rsp_t),
    .NUM_PAD  (NUM_PAD)
  ) pad_control_i (
    .clk_i           (clk_in_x),
    .rst_ni          (rst_nin_sync),
    .reg_req_i       (pad_req),
    .reg_rsp_o       (pad_rsp),
    .pad_attributes_o(pad_attributes),
    .pad_muxes_o     (pad_muxes)
  );

endmodule  // gr_heep_top
