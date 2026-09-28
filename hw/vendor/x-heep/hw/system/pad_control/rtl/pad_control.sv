// Copyright 2022 EPFL
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1




module pad_control #(
    parameter type reg_req_t = logic,
    parameter type reg_rsp_t = logic,
    parameter NUM_PAD = 1
) (

    input logic clk_i,
    input logic rst_ni,

    // Bus Interface
    input reg_req_t reg_req_i,
    output reg_rsp_t reg_rsp_o,
    output logic [NUM_PAD-1:0][7:0] pad_attributes_o,
    output logic [NUM_PAD-1:0][0:0] pad_muxes_o
);


  import core_v_mini_mcu_pkg::*;

  import pad_control_reg_pkg::*;

  pad_control_reg2hw_t reg2hw;

  pad_control_reg_top #(
      .reg_req_t(reg_req_t),
      .reg_rsp_t(reg_rsp_t)
  ) pad_control_reg_top_i (
      .clk_i,
      .rst_ni,
      .reg_req_i,
      .reg_rsp_o,
      .reg2hw,
      .devmode_i(1'b1)
  );

  assign pad_attributes_o[PAD_CLK] = reg2hw.pad_attribute_clk.q;
  assign pad_attributes_o[PAD_RST] = reg2hw.pad_attribute_rst.q;
  assign pad_attributes_o[PAD_BOOT_SELECT] = reg2hw.pad_attribute_boot_select.q;
  assign pad_attributes_o[PAD_EXECUTE_FROM_FLASH] = reg2hw.pad_attribute_execute_from_flash.q;
  assign pad_attributes_o[PAD_JTAG_TCK] = reg2hw.pad_attribute_jtag_tck.q;
  assign pad_attributes_o[PAD_JTAG_TMS] = reg2hw.pad_attribute_jtag_tms.q;
  assign pad_attributes_o[PAD_JTAG_TRST] = reg2hw.pad_attribute_jtag_trst.q;
  assign pad_attributes_o[PAD_JTAG_TDI] = reg2hw.pad_attribute_jtag_tdi.q;
  assign pad_attributes_o[PAD_JTAG_TDO] = reg2hw.pad_attribute_jtag_tdo.q;
  assign pad_attributes_o[PAD_UART_RX] = reg2hw.pad_attribute_uart_rx.q;
  assign pad_attributes_o[PAD_UART_TX] = reg2hw.pad_attribute_uart_tx.q;
  assign pad_attributes_o[PAD_EXIT_VALUE] = reg2hw.pad_attribute_exit_value.q;
  assign pad_attributes_o[PAD_EXIT_VALID] = reg2hw.pad_attribute_exit_valid.q;
  assign pad_attributes_o[PAD_GPIO_0] = reg2hw.pad_attribute_gpio_0.q;
  assign pad_attributes_o[PAD_GPIO_1] = reg2hw.pad_attribute_gpio_1.q;
  assign pad_attributes_o[PAD_GPIO_2] = reg2hw.pad_attribute_gpio_2.q;
  assign pad_attributes_o[PAD_GPIO_3] = reg2hw.pad_attribute_gpio_3.q;
  assign pad_attributes_o[PAD_GPIO_4] = reg2hw.pad_attribute_gpio_4.q;
  assign pad_attributes_o[PAD_GPIO_5] = reg2hw.pad_attribute_gpio_5.q;
  assign pad_attributes_o[PAD_GPIO_6] = reg2hw.pad_attribute_gpio_6.q;
  assign pad_attributes_o[PAD_GPIO_7] = reg2hw.pad_attribute_gpio_7.q;
  assign pad_attributes_o[PAD_GPIO_8] = reg2hw.pad_attribute_gpio_8.q;
  assign pad_attributes_o[PAD_GPIO_9] = reg2hw.pad_attribute_gpio_9.q;
  assign pad_attributes_o[PAD_GPIO_10] = reg2hw.pad_attribute_gpio_10.q;
  assign pad_attributes_o[PAD_GPIO_11] = reg2hw.pad_attribute_gpio_11.q;
  assign pad_attributes_o[PAD_GPIO_12] = reg2hw.pad_attribute_gpio_12.q;
  assign pad_attributes_o[PAD_GPIO_13] = reg2hw.pad_attribute_gpio_13.q;
  assign pad_attributes_o[PAD_SPI_FLASH_SCK] = reg2hw.pad_attribute_spi_flash_sck.q;
  assign pad_attributes_o[PAD_SPI_FLASH_CS_0] = reg2hw.pad_attribute_spi_flash_cs_0.q;
  assign pad_attributes_o[PAD_SPI_FLASH_CS_1] = reg2hw.pad_attribute_spi_flash_cs_1.q;
  assign pad_attributes_o[PAD_SPI_FLASH_SD_0] = reg2hw.pad_attribute_spi_flash_sd_0.q;
  assign pad_attributes_o[PAD_SPI_FLASH_SD_1] = reg2hw.pad_attribute_spi_flash_sd_1.q;
  assign pad_attributes_o[PAD_SPI_FLASH_SD_2] = reg2hw.pad_attribute_spi_flash_sd_2.q;
  assign pad_attributes_o[PAD_SPI_FLASH_SD_3] = reg2hw.pad_attribute_spi_flash_sd_3.q;
  assign pad_attributes_o[PAD_SPI_SCK] = reg2hw.pad_attribute_spi_sck.q;
  assign pad_attributes_o[PAD_SPI_CS_0] = reg2hw.pad_attribute_spi_cs_0.q;
  assign pad_attributes_o[PAD_SPI_CS_1] = reg2hw.pad_attribute_spi_cs_1.q;
  assign pad_attributes_o[PAD_SPI_SD_0] = reg2hw.pad_attribute_spi_sd_0.q;
  assign pad_attributes_o[PAD_SPI_SD_1] = reg2hw.pad_attribute_spi_sd_1.q;
  assign pad_attributes_o[PAD_SPI_SD_2] = reg2hw.pad_attribute_spi_sd_2.q;
  assign pad_attributes_o[PAD_SPI_SD_3] = reg2hw.pad_attribute_spi_sd_3.q;
  assign pad_attributes_o[PAD_SPI_SLAVE_SCK] = reg2hw.pad_attribute_spi_slave_sck.q;
  assign pad_attributes_o[PAD_SPI_SLAVE_CS] = reg2hw.pad_attribute_spi_slave_cs.q;
  assign pad_attributes_o[PAD_SPI_SLAVE_MISO] = reg2hw.pad_attribute_spi_slave_miso.q;
  assign pad_attributes_o[PAD_SPI_SLAVE_MOSI] = reg2hw.pad_attribute_spi_slave_mosi.q;
  assign pad_attributes_o[PAD_PDM2PCM_PDM] = reg2hw.pad_attribute_pdm2pcm_pdm.q;
  assign pad_attributes_o[PAD_PDM2PCM_CLK] = reg2hw.pad_attribute_pdm2pcm_clk.q;
  assign pad_attributes_o[PAD_I2S_SCK] = reg2hw.pad_attribute_i2s_sck.q;
  assign pad_attributes_o[PAD_I2S_WS] = reg2hw.pad_attribute_i2s_ws.q;
  assign pad_attributes_o[PAD_I2S_SD] = reg2hw.pad_attribute_i2s_sd.q;
  assign pad_attributes_o[PAD_SPI2_CS_0] = reg2hw.pad_attribute_spi2_cs_0.q;
  assign pad_attributes_o[PAD_SPI2_CS_1] = reg2hw.pad_attribute_spi2_cs_1.q;
  assign pad_attributes_o[PAD_SPI2_SCK] = reg2hw.pad_attribute_spi2_sck.q;
  assign pad_attributes_o[PAD_SPI2_SD_0] = reg2hw.pad_attribute_spi2_sd_0.q;
  assign pad_attributes_o[PAD_SPI2_SD_1] = reg2hw.pad_attribute_spi2_sd_1.q;
  assign pad_attributes_o[PAD_SPI2_SD_2] = reg2hw.pad_attribute_spi2_sd_2.q;
  assign pad_attributes_o[PAD_SPI2_SD_3] = reg2hw.pad_attribute_spi2_sd_3.q;
  assign pad_attributes_o[PAD_I2C_SCL] = reg2hw.pad_attribute_i2c_scl.q;
  assign pad_attributes_o[PAD_I2C_SDA] = reg2hw.pad_attribute_i2c_sda.q;

  assign pad_muxes_o[PAD_SPI_SLAVE_SCK] = 1'(reg2hw.pad_mux_spi_slave_sck.q);
  assign pad_muxes_o[PAD_SPI_SLAVE_CS] = 1'(reg2hw.pad_mux_spi_slave_cs.q);
  assign pad_muxes_o[PAD_SPI_SLAVE_MISO] = 1'(reg2hw.pad_mux_spi_slave_miso.q);
  assign pad_muxes_o[PAD_SPI_SLAVE_MOSI] = 1'(reg2hw.pad_mux_spi_slave_mosi.q);
  assign pad_muxes_o[PAD_PDM2PCM_PDM] = 1'(reg2hw.pad_mux_pdm2pcm_pdm.q);
  assign pad_muxes_o[PAD_PDM2PCM_CLK] = 1'(reg2hw.pad_mux_pdm2pcm_clk.q);
  assign pad_muxes_o[PAD_I2S_SCK] = 1'(reg2hw.pad_mux_i2s_sck.q);
  assign pad_muxes_o[PAD_I2S_WS] = 1'(reg2hw.pad_mux_i2s_ws.q);
  assign pad_muxes_o[PAD_I2S_SD] = 1'(reg2hw.pad_mux_i2s_sd.q);
  assign pad_muxes_o[PAD_SPI2_CS_0] = 1'(reg2hw.pad_mux_spi2_cs_0.q);
  assign pad_muxes_o[PAD_SPI2_CS_1] = 1'(reg2hw.pad_mux_spi2_cs_1.q);
  assign pad_muxes_o[PAD_SPI2_SCK] = 1'(reg2hw.pad_mux_spi2_sck.q);
  assign pad_muxes_o[PAD_SPI2_SD_0] = 1'(reg2hw.pad_mux_spi2_sd_0.q);
  assign pad_muxes_o[PAD_SPI2_SD_1] = 1'(reg2hw.pad_mux_spi2_sd_1.q);
  assign pad_muxes_o[PAD_SPI2_SD_2] = 1'(reg2hw.pad_mux_spi2_sd_2.q);
  assign pad_muxes_o[PAD_SPI2_SD_3] = 1'(reg2hw.pad_mux_spi2_sd_3.q);
  assign pad_muxes_o[PAD_I2C_SCL] = 1'(reg2hw.pad_mux_i2c_scl.q);
  assign pad_muxes_o[PAD_I2C_SDA] = 1'(reg2hw.pad_mux_i2c_sda.q);

endmodule : pad_control
