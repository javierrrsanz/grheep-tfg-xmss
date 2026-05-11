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
        
    type state_type is (S_IDLE, S_START_HASH, S_WAIT_MNEXT, S_FETCH_REQ, S_FETCH_WAIT);
    
    type reg_type is record
        state       : state_type;
        ctr         : integer range 0 to MAX_MLEN/32 + 1;
        block_count : integer range 0 to 4;
        mhash       : std_logic_vector(n*8-1 downto 0);
        mem_data    : std_logic_vector(n*8-1 downto 0);
        halt_hash   : std_logic;
    end record;
    
    signal r, r_in : reg_type;
begin

    q.hash.len <= 4*8*n + m_in.mlen;
    q.hash.id.ctr <= to_unsigned(0, ID_CTR_LEN);
    q.hash.id.block_ctr <= "000";
    
    m_out.mhash <= r.mhash;
    q.hash.halt <= r.halt_hash; -- Propagación del Halt al motor SHA

    combinational : process (r, d, m_in)
       variable v : reg_type;
    begin
        v := r;
        m_out.done <= '0';
        q.hash.enable <= '0';
        q.mem.req <= '0';
        q.mem.addr <= (others => '0');
        
        -- MUX Combinacional: Alimenta al Hash Core con el dato correcto
        if r.block_count = 0 then
            q.hash.input <= std_logic_vector(to_unsigned(2, n*8)); -- 1. Prefix (Interno)
        elsif r.block_count = 3 then
            q.hash.input <= std_logic_vector(resize(m_in.index, n*8)); -- 4. Index (Interno)
        else
            q.hash.input <= r.mem_data; -- 2(R), 3(Root) y 5+(Mensaje) vienen del bus OBI
        end if;

        case r.state is
           when S_IDLE =>
               if m_in.enable = '1' then
                   v.ctr := 0;
                   v.block_count := 0;
                   v.state := S_START_HASH;
               end if;                  

           when S_START_HASH =>
               q.hash.enable <= '1';
               v.state := S_WAIT_MNEXT;

           when S_WAIT_MNEXT =>
               -- El motor SHA pide el siguiente bloque de 256 bits
               if d.hash.mnext = '1' then
                   if r.block_count < 4 then
                       v.block_count := r.block_count + 1;
                   else
                       v.ctr := r.ctr + 1;
                   end if;
                   
                   -- Si el bloque que toca AHORA requiere memoria externa, congelamos y leemos
                   if (v.block_count = 1) or (v.block_count = 2) or (v.block_count >= 4) then
                       v.halt_hash := '1';
                       v.state := S_FETCH_REQ;
                   end if;
               end if;
               
               if d.hash.done = '1' then
                   v.mhash := d.hash.o;
                   m_out.done <= '1';
                   v.state := S_IDLE;
               end if;

           when S_FETCH_REQ =>
               q.mem.req <= '1';
               -- Cálculo de dirección (Ojo: Adaptado a 32 bits absolutos para OBI)
               if r.block_count = 1 then
                   q.mem.addr <= std_logic_vector(to_unsigned((BRAM_XMSS_SIG + 1) * 32, 32)); -- R
               elsif r.block_count = 2 then
                   q.mem.addr <= std_logic_vector(to_unsigned(BRAM_PK * 32, 32)); -- Root
               else
                   q.mem.addr <= std_logic_vector(to_unsigned((BRAM_MESSAGE + r.ctr) * 32, 32)); -- Msg
               end if;
               
               if d.mem.gnt = '1' then
                   v.state := S_FETCH_WAIT;
               end if;

           when S_FETCH_WAIT =>
               -- Cuando el bus OBI devuelve el dato, lo guardamos y quitamos el freno
               if d.mem.valid = '1' then
                   v.mem_data := d.mem.data;
                   v.halt_hash := '0';
                   v.state := S_WAIT_MNEXT;
               end if;     

           when others => v.state := S_IDLE;
        end case;
        r_in <= v;
    end process;

    sequential : process(clk)
    begin
       if rising_edge(clk) then
        if reset = '1' then
           r.state <= S_IDLE;
           r.ctr <= 0;
           r.block_count <= 0;
           r.mhash <= (others => '0');
           r.mem_data <= (others => '0');
           r.halt_hash <= '0';
        else
           r <= r_in;
        end if;
       end if;
    end process;
end Behavioral;