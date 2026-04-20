
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.xmss_main_typedef.ALL;
use work.params.ALL;
use ieee.numeric_std.all;


entity thash_h is
    port (
           clk   : in std_logic;
           reset : in std_logic;
           d     : in xmss_thash_h_input_type;
           q     : out xmss_thash_h_output_type);
end thash_h;

architecture Behavioral of thash_h is
    alias m_in : xmss_thash_h_input_type_small is d.module_input;
    alias m_out : xmss_thash_h_output_type_small is q.module_output;

    type state_type is (S_IDLE, S_KEY, S_BITMASK_2, S_BITMASK_1, S_CORE_HASH_INIT, S_CORE_HASH, S_WAIT_FOR_HASH);
    
    type reg_type is record
        state : state_type;
        mask_input_1, mask_input_2, key : std_logic_vector(n*8-1 downto 0);
        done : std_logic;
        -- NUEVO: Banderas de sincronización para evitar condiciones de carrera
        key_done : std_logic;
        m1_done  : std_logic;
        m2_done  : std_logic;
    end record;
    
    signal hash_enable : std_logic;
    signal r, r_in : reg_type;
    signal block_ctr : unsigned(2 downto 0);

begin
    
    -- Static output wiring    
	m_out.o <= r.key;
	m_out.done <= r.done;

    combinational : process (r, d)
	   variable v : reg_type;
	begin
        v := r;
        
        -- Default assignments
        q.hash.len <= 768;
        q.hash.enable <= '0';
        
        q.hash.id.ctr <= to_unsigned(0, ID_CTR_LEN);
        q.hash.id.block_ctr <= (others => '0');
        
        block_ctr <= d.hash.id.block_ctr;
        
        v.done := '0';

        -- Si un núcleo termina en CUALQUIER momento de la fase de preparación, guardamos su dato y levantamos su bandera.
        if d.hash.done = '1' and (r.state = S_BITMASK_1 or r.state = S_BITMASK_2 or r.state = S_WAIT_FOR_HASH) then
            if d.hash.done_id.ctr = to_unsigned(0, ID_CTR_LEN) then
                v.key := d.hash.o;
                v.key_done := '1';
            elsif d.hash.done_id.ctr = to_unsigned(1, ID_CTR_LEN) then
                v.mask_input_1 := r.mask_input_1 xor d.hash.o;
                v.m1_done := '1';
            elsif d.hash.done_id.ctr = to_unsigned(2, ID_CTR_LEN) then
                v.mask_input_2 := r.mask_input_2 xor d.hash.o;
                v.m2_done := '1';
            end if;
        end if;
        	    
     	case r.state is
     	      when S_IDLE =>
                  if m_in.enable = '1' then
                       v.mask_input_1 := m_in.input_1;
                       v.mask_input_2 := m_in.input_2;
                       -- Limpiamos banderas
                       v.key_done := '0';
                       v.m1_done := '0';
                       v.m2_done := '0';
                       v.state := S_KEY;
                  end if;
                  
              when S_KEY =>
                  q.hash.enable <= '1';
                  q.hash.id.block_ctr <= "000";
                  block_ctr <= "000";
                  v.state := S_BITMASK_1;
                  
              when S_BITMASK_1 =>
                  if d.hash.busy = '0' then
                        q.hash.enable <= '1';
                        q.hash.id.ctr <= to_unsigned(1, ID_CTR_LEN);
                        q.hash.id.block_ctr <= "000";
                        block_ctr <= "000";
                        v.state := S_BITMASK_2;
                  end if;
                  -- (La recolección de hashes terminados ahora se hace arriba)
                  
              when S_BITMASK_2 =>
                  if d.hash.busy = '0' then
                        q.hash.enable <= '1';
                        q.hash.id.ctr <= to_unsigned(2, ID_CTR_LEN);
                        q.hash.id.block_ctr <= "000";
                        block_ctr <= "000";
                        v.state := S_WAIT_FOR_HASH;
                  end if;
                  
              when S_WAIT_FOR_HASH =>
                  -- Solo avanzamos cuando sepamos de que los 3 cálculos han terminado
                  if v.key_done = '1' and v.m1_done = '1' and v.m2_done = '1' then
                        v.state := S_CORE_HASH_INIT;
                  end if;
                  
              when S_CORE_HASH_INIT =>
                    q.hash.enable <= '1';
                    q.hash.len <= 1024;
                    q.hash.id.ctr <= to_unsigned(3, ID_CTR_LEN);
                    q.hash.id.block_ctr <= "100";
                    block_ctr <= "100";
                    v.state := S_CORE_HASH;
                    
              when S_CORE_HASH =>
                  if d.hash.done = '1' then
                      v.key := d.hash.o;
                      v.done := '1';
                      v.state := S_IDLE;
                  end if;
        end case;
        r_in <= v;
    end process;

    hash_mux : process(block_ctr, m_in, r.mask_input_1, r.mask_input_2, d.pub_seed, r.key, d.hash.id.ctr)
    begin
        case block_ctr is
            when "000" => q.hash.input <= std_logic_vector(to_unsigned(3, n*8));
            when "001" => q.hash.input <= d.pub_seed;
            when "010" => q.hash.input <= x"00000000" & x"00000000" & x"00000000" & m_in.address_3 & m_in.address_4 
                                    & m_in.address_5 & m_in.address_6 & std_logic_vector(resize(d.hash.id.ctr, 32));
            when "100" => q.hash.input <= std_logic_vector(to_unsigned(1, n*8));
            when "101" => q.hash.input <= r.key;
            when "110" => q.hash.input <= r.mask_input_1;
            when "111" => q.hash.input <= r.mask_input_2;
            when others => q.hash.input <= (others => '-');
        end case;
    end process;

    sequential : process(clk)
	begin
	   if rising_edge(clk) then
	    if reset = '1' then
	       r.state <= S_IDLE;
           -- Inicializar seguridad
           r.key_done <= '0';
           r.m1_done <= '0';
           r.m2_done <= '0';
	    else
		   r <= r_in;
        end if;
       end if;
    end process;
end Behavioral;