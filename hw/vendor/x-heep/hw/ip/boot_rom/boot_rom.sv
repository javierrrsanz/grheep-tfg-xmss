/* Copyright 2018 ETH Zurich and University of Bologna.
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * File: $filename.v
 *
 * Description: Auto-generated bootrom
 */

// Auto-generated code
module boot_rom
  import reg_pkg::*;
(
  input  reg_req_t     reg_req_i,
  output reg_rsp_t     reg_rsp_o
);
  import core_v_mini_mcu_pkg::*;

  localparam int unsigned RomSize = 161;

  logic [RomSize-1:0][31:0] mem;
  assign mem = {
    32'h00000000,
    32'h95c1ddda,
    32'h91e6581a,
    32'hdba9d5b7,
    32'h7f641135,
    32'h881991e3,
    32'h27a38210,
    32'h8ff90e7d,
    32'h46aa3916,
    32'h8082b75d,
    32'hfe0f15e3,
    32'h1f7d0491,
    32'h0054a023,
    32'h0285a283,
    32'hdfe50ff7,
    32'hf79383a1,
    32'h49dc002f,
    32'h5f13003e,
    32'h0f13fe07,
    32'hdfe349dc,
    32'h00010245,
    32'ha22301d4,
    32'h62330800,
    32'h0437a029,
    32'h01d46233,
    32'h09000437,
    32'h000a0763,
    32'he299fffe,
    32'h0e9341c6,
    32'h86b38e36,
    32'h01c6d363,
    32'h10000e13,
    32'hceb1bff5,
    32'h10500073,
    32'ha009a011,
    32'h95020000,
    32'h0f930000,
    32'h0f130000,
    32'h0e930000,
    32'h0e130000,
    32'h0d930000,
    32'h0d130000,
    32'h0c930000,
    32'h0c130000,
    32'h0b930000,
    32'h0b130000,
    32'h0a930000,
    32'h0a130000,
    32'h09930000,
    32'h09130000,
    32'h08930000,
    32'h08130000,
    32'h07930000,
    32'h07130000,
    32'h06930000,
    32'h06130000,
    32'h05930000,
    32'h04930000,
    32'h04130000,
    32'h03930000,
    32'h03130000,
    32'h02930000,
    32'h02130000,
    32'h01930000,
    32'h01130000,
    32'h00931805,
    32'h05130000,
    32'h05370000,
    32'h100f0056,
    32'h20234289,
    32'h087e1963,
    32'h010e5e13,
    32'h01029e13,
    32'hc5a38393,
    32'h6391fe03,
    32'h0ae30013,
    32'h73130102,
    32'hd3130046,
    32'h22830056,
    32'h20234285,
    32'h00562c23,
    32'h62a10056,
    32'h2a230039,
    32'h92930056,
    32'h28234281,
    32'h00562423,
    32'h04428293,
    32'h62a1fe03,
    32'h97e313fd,
    32'h03110e11,
    32'h0fee9063,
    32'h00032f03,
    32'h000e2e83,
    32'h02060e13,
    32'h43a115e3,
    32'h03130000,
    32'h03170056,
    32'h20234289,
    32'hfe028ae3,
    32'h0012f293,
    32'h0102d293,
    32'h00462283,
    32'h00562023,
    32'h42910056,
    32'h2a232200,
    32'h02930056,
    32'h2c2362a1,
    32'h20070637,
    32'h132000ef,
    32'h4a0186ce,
    32'h448113c0,
    32'h00ef4a05,
    32'h2e468693,
    32'h668564a1,
    32'h405909b3,
    32'h2e428293,
    32'h62850285,
    32'ha903dfe5,
    32'h0ff7f793,
    32'h83a149dc,
    32'hfe07dfe3,
    32'h49dc0001,
    32'h0245a223,
    32'h00340213,
    32'h09000437,
    32'hfe07dfe3,
    32'h49dc0001,
    32'hd1d8070d,
    32'h11000737,
    32'hfe075fe3,
    32'h49d80001,
    32'hd5d8470d,
    32'hfe075fe3,
    32'h49d8d1d8,
    32'h070d1000,
    32'h0737d5d8,
    32'h0ab00713,
    32'hc9980087,
    32'h6713f007,
    32'h77134998,
    32'hd1884501,
    32'hcd980705,
    32'h0fff0737,
    32'hc9988f49,
    32'h4998a000,
    32'h05372002,
    32'h05b79582,
    32'h18058593,
    32'h400005b7,
    32'hc1884505,
    32'h200285b7,
    32'hc9110145,
    32'hc5039582,
    32'h498cd175,
    32'h00c5c503,
    32'he5110085,
    32'hc5032000,
    32'h05b79502,
    32'h41c8c119,
    32'h0005c503,
    32'h200405b7
  };

  logic [$clog2(core_v_mini_mcu_pkg::BOOTROM_SIZE)-1-2:0] word_addr;
  logic [$clog2(RomSize)-1:0] rom_addr;

  assign word_addr = reg_req_i.addr[$clog2(core_v_mini_mcu_pkg::BOOTROM_SIZE)-1:2];
  assign rom_addr  = word_addr[$clog2(RomSize)-1:0];

  assign reg_rsp_o.error = 1'b0;
  assign reg_rsp_o.ready = 1'b1;

  always_comb begin
    if (word_addr > (RomSize-1)) begin
      reg_rsp_o.rdata = '0;
    end else begin
      reg_rsp_o.rdata = mem[rom_addr];
    end
  end

endmodule
