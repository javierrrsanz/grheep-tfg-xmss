library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.xmss_main_typedef.ALL;
use work.wots_comp.ALL;
use work.params.ALL;

entity WOTS is
    port (
           clk   : in std_logic;
           reset : in std_logic;
           d     : in wots_input_type;
           q     : out wots_output_type);
end WOTS;

architecture Behavioral of WOTS is
    alias m_in : wots_input_type_small is d.module_input;
    alias m_out : wots_output_type_small is q.module_output;

    signal core_in : wots_core_input_type;
    signal core_out : wots_core_output_type;
begin
    
    wots_core_inst : entity work.wots_core
    port map(
       clk          => clk,
       reset        => reset,
       d            => core_in,
	   q            => core_out
    );

    q.bram.b <= core_out.bram;
    q.bram.a.en <= '0';
    q.bram.a.wen <= '0';
    q.bram.a.addr <= (others => '0');
    q.bram.a.din <= (others => '0');
    
    q.hash <= core_out.hash;
    m_out.done <= core_out.done;

    core_in.enable <= m_in.enable;
    core_in.pub_seed <= d.pub_seed;
    core_in.bram <= d.bram_b;
    core_in.message <= m_in.message;
    core_in.address_4 <= m_in.address_4;
    core_in.hash <= d.hash;
    
end Behavioral;