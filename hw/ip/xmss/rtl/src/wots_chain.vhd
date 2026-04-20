library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.wots_comp.ALL;
use work.params.ALL;

entity wots_chain is
    Generic( ID : integer);
    Port ( clk : in STD_LOGIC;
           reset : in STD_LOGIC;
           d     : in wots_chain_input_type;
           q     : out wots_chain_output_type);
end wots_chain;
    
architecture Behavioral of wots_chain is
    type state_type is (S_IDLE, S_KEY, S_LOOP, S_BITMASK, S_KEY_AND_MASK, S_CORE_HASH_INIT, S_CORE_HASH);
    type reg_type is record 
        state : state_type;
        cnt : unsigned(WOTS_LOG_W-1 downto 0);
        chain_index : unsigned(WOTS_LEN_LOG-1 downto 0);
        X : std_logic_vector(n*8-1 downto 0); 
        key : std_logic_vector(n*8-1 downto 0);
        halt_self : std_logic; -- RESTAURADO EL SEGURO
        key_and_mask : unsigned(1 downto 0);
        busy : std_logic; 
    end record;
    
    signal hash_sel : unsigned(2 downto 0);
    signal has_mnext, has_done, is_addressed : std_logic;
    signal r, r_in : reg_type;

begin
    q.busy <= r.busy;
    q.ctr <= r.chain_index;
    q.hash.len <= 768;
    q.hash.id.ctr <= to_unsigned(ID, ID_CTR_LEN);
    q.result <= r.X;

    is_addressed <= '1' when to_unsigned(ID, ID_CTR_LEN) = d.hash.id.ctr else '0';
    has_mnext <= '1' when d.hash.mnext = '1' and is_addressed = '1' else '0';
    has_done <= '1' when d.hash.done = '1' and (to_unsigned(ID, ID_CTR_LEN) = d.hash.done_id.ctr) else '0';

    combinational : process (r, d, has_mnext, has_done)
       variable v : reg_type;
    begin
       v := r;
       q.hash.enable <= '0';
       q.hash.id.block_ctr <= (others => '0');
       q.done <= '0';
       hash_sel <= d.hash.id.block_ctr;

       case r.state is      
           when S_IDLE =>
               v.busy := '0';
               if d.enable = '1' then
                   v.X := d.X;
                   v.cnt := d.start;
                   v.chain_index := to_unsigned(d.chain_index, WOTS_LEN_LOG);
                   v.busy := '1';
                   v.state := S_LOOP;
               end if;
               
           when S_LOOP =>
              if r.cnt = wots_w - 1 then
                    q.done <= '1';
                    v.state := S_IDLE; 
                    v.halt_self := '1'; -- CONGELA LOS DATOS HASTA QUE SE ESCRIBEN EN BRAM
              else 
                    v.state := S_KEY;
              end if;
              
           when S_KEY =>
                v.key_and_mask := "00";
                if d.hash_available = '1' then
                    q.hash.enable <= '1';
                    hash_sel <= "000";
                    v.state := S_BITMASK;
                end if;
                
           when S_BITMASK =>
                if d.hash_available = '1' then
                    q.hash.enable <= '1';
                    q.hash.id.block_ctr <= "100";
                    hash_sel <= "000";
                    v.state := S_KEY_AND_MASK;
                end if;
                if has_done = '1' then
                    v.key_and_mask(1) := '1';
                    v.key := d.hash.o;
                end if;
                
           when S_KEY_AND_MASK => 
                if has_done = '1' then
                    if d.hash.done_id.block_ctr(2) = '0' then 
                        v.key := d.hash.o;
                        v.key_and_mask(1) := '1';
                    else 
                        v.x := r.x xor d.hash.o;
                        v.key_and_mask(0) := '1';
                    end if;
               end if;
               if v.key_and_mask = "11" then
                    v.state := S_CORE_HASH_INIT;
               end if;
               
           when S_CORE_HASH_INIT =>
                if d.hash_available = '1' then
                    q.hash.enable <= '1';
                    q.hash.id.block_ctr <= "010";
                    hash_sel <= "111";
                    v.state := S_CORE_HASH;
                end if;
                
           when S_CORE_HASH =>
              if has_done = '1' then
                    v.cnt := r.cnt + 1;
                    v.X := d.hash.o;   
                    v.state := S_LOOP;
              end if;
       end case;
       
       if r.halt_self = '1' then
           q.hash.enable <= '0';
       end if;
       r_in <= v;
    end process;

    hash_mux : process(hash_sel, d, r.cnt, r.chain_index, r.key, r.X) is
    begin
       case hash_sel is
            when "000" => q.hash.input <= std_logic_vector(to_unsigned(3, n*8));
            when "001"|"101" => q.hash.input <= d.SEED;
            when "010" => q.hash.input <= x"00000000" & x"00000000" & x"00000000" & x"00000000" & d.address_4 & std_logic_vector(resize(r.chain_index, 32)) & std_logic_vector(resize(r.cnt, 32)) & x"00000000";
            when "110" => q.hash.input <= x"00000000" & x"00000000" & x"00000000" & x"00000000" & d.address_4 & std_logic_vector(resize(r.chain_index, 32)) & std_logic_vector(resize(r.cnt, 32)) & x"00000001";
            when "111" => q.hash.input <= std_logic_vector(to_unsigned(0, n*8));
            when "011" => q.hash.input <= r.key;
            when others => q.hash.input <= r.X;
       end case;
    end process;
    
    sequential : process(clk)
    begin
       if rising_edge(clk) then
        if reset = '1' then
           r.state <= S_IDLE;
           r.halt_self <= '0';
           r.busy <= '0';
           r.X <= (others => '0');
           r.chain_index <= (others => '0');
           r.cnt <= (others => '0');
        else
           if r.halt_self = '0' then
              r <= r_in;
           elsif d.continue = '1' then
              r.halt_self <= '0'; -- DESCONGELA LA CADENA
           end if;
        end if;
       end if;
    end process;
end Behavioral;