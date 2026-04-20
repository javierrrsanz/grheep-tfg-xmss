library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.params.ALL;
use work.xmss_main_typedef.ALL;
use IEEE.NUMERIC_STD.ALL;

entity hash_message is
    port(
        clk   : in std_logic;
        reset : in std_logic;
        d     : in hash_message_input_type;
        q     : out hash_message_output_type);
end hash_message;

architecture Behavioral of hash_message is
    alias m_in : hash_message_input_type_small is d.module_input;
    alias m_out : hash_message_output_type_small is q.module_output;
        
    type state_type is (S_IDLE, S_HASH_MESSAGE_INIT, S_WAIT_MNEXT, S_ABSORB_MESSAGE);
    
    type reg_type is record
        state : state_type;
        ctr : integer range 0 to 15;
        mhash : std_logic_vector(n*8-1 downto 0);
        block_count : integer range 0 to 4; 
    end record;
    
    signal bram_select : unsigned(1 downto 0);
    signal hash_select : unsigned(1 downto 0);
    signal r, r_in : reg_type;
begin

    q.hash.len <= 4*8*n + m_in.mlen;
    q.hash.id.ctr <= to_unsigned(0, ID_CTR_LEN);
    q.hash.id.block_ctr <= "000";
    q.bram.en <= '1';
    q.bram.wen <= '0';
    q.bram.din <= (others => '0');
    
    m_out.mhash <= r.mhash;

    combinational : process (r, d)
       variable v : reg_type;
    begin
        v := r;
        m_out.done <= '0';
        q.hash.enable <= '0';
        
        -- Mantenemos la selección del bloque actual de forma estable
        case r.block_count is
            when 0 => hash_select <= "00"; bram_select <= "00"; -- Prefijo
            when 1 => hash_select <= "01"; bram_select <= "00"; -- R
            when 2 => hash_select <= "01"; bram_select <= "01"; -- Root
            when 3 => hash_select <= "10"; bram_select <= "00"; -- Index
            when 4 => hash_select <= "01"; bram_select <= "10"; -- Mensaje
            when others => hash_select <= "00"; bram_select <= "00";
        end case;

        case r.state is
           when S_IDLE =>
               if m_in.enable = '1' then
                   v.ctr := 0;
                   v.block_count := 0;
                   v.state := S_HASH_MESSAGE_INIT;
               end if;                  

           when S_HASH_MESSAGE_INIT =>
               q.hash.enable <= '1';
               -- Sincronización crítica: No avanzamos de bloque con el mnext del ciclo inicial
               v.state := S_WAIT_MNEXT;

           when S_WAIT_MNEXT =>
               -- Solo avanzamos de bloque si recibimos mnext y NO es el ciclo de arranque
               if d.hash.mnext = '1' then
                   if r.block_count < 4 then
                       v.block_count := r.block_count + 1;
                       -- Nos quedamos en este estado para el siguiente mnext
                   else
                       v.state := S_ABSORB_MESSAGE;
                   end if;
               end if;
               
               if d.hash.done = '1' then
                   v.mhash := d.hash.o;
                   m_out.done <= '1';
                   v.state := S_IDLE;
               end if;

           when S_ABSORB_MESSAGE =>
               -- Gestión del mensaje largo (multiples bloques de BRAM)
               if d.hash.mnext = '1' then 
                   v.ctr := r.ctr + 1; 
               end if;
               
               if d.hash.done = '1' then
                   v.mhash := d.hash.o;
                   m_out.done <= '1';
                   v.state := S_IDLE;
               end if;     

           when others => v.state := S_IDLE;
        end case;
        r_in <= v;
    end process;

    hash_mux : process(hash_select, m_in.index, d.bram.dout)
    begin
        case hash_select is
            when "00" => q.hash.input <= std_logic_vector(to_unsigned(2, n*8));
            when "10" => q.hash.input <= std_logic_vector(resize(m_in.index, n*8));
            when others => q.hash.input <= d.bram.dout;
        end case;
    end process;

    bram_mux : process(bram_select, r.ctr)
    begin
        case bram_select is
            when "00" => q.bram.addr <= std_logic_vector(to_unsigned(BRAM_XMSS_SIG + 1, BRAM_ADDR_SIZE)); -- R
            when "01" => q.bram.addr <= std_logic_vector(to_unsigned(BRAM_PK, BRAM_ADDR_SIZE)); -- Root
            when "10" => q.bram.addr <= std_logic_vector(to_unsigned(BRAM_MESSAGE + r.ctr, BRAM_ADDR_SIZE)); -- Mensaje
            when others => q.bram.addr <= (others => '0');
        end case;
    end process;

    sequential : process(clk)
    begin
       if rising_edge(clk) then
        if reset = '1' then
           r.state <= S_IDLE;
           r.ctr <= 0;
           r.block_count <= 0;
           r.mhash <= (others => '0');
        else
           r <= r_in;
        end if;
       end if;
    end process;
end Behavioral;