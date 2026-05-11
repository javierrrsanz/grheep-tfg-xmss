library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.wots_comp.ALL;
use work.wots_functions.ALL;
use work.xmss_main_typedef.ALL;
use work.params.ALL;
use ieee.numeric_std.all;

entity wots_core is
    port (
           clk   : in std_logic;
           reset : in std_logic;
           d     : in wots_core_input_type;
           q     : out wots_core_output_type);
end wots_core;

architecture Behavioral of wots_core is
    constant all_zeros : std_logic_vector(HASH_CHAINS-1 downto 0) := (others => '0');

    type chain_output_array is array (HASH_CHAINS-1 downto 0) of std_logic_vector(n*8 -1 downto 0);
    type chain_hash_array is array (HASH_CHAINS-1 downto 0) of hash_subsystem_input_type;
    type chain_counter_array is array (HASH_CHAINS-1 downto 0) of unsigned(WOTS_LEN_LOG -1 downto 0);

    type state_type is (S_IDLE, S_READ_SIG_REQ, S_READ_SIG_WAIT, S_CHAIN_EN, S_DONE_CHECK);

    type reg_type is record 
        state : state_type;
        ctr : integer range 0 to wots_len;
        done_indicator : std_logic_vector(HASH_CHAINS-1 downto 0);
        hash_sel : unsigned(HASH_CHAINS-1 downto 0);
        hold_timer : integer range 0 to 4; 
        sig_word : std_logic_vector(n*8-1 downto 0);
        word_pending : std_logic; -- NUEVO: Evita doble petición OBI
    end record;

    signal bram_offset : unsigned(WOTS_LEN_LOG-1 downto 0);
    signal chain_busy, chain_enable, chain_continue, chain_done : std_logic_vector(HASH_CHAINS-1 downto 0);
    signal chain_counter : chain_counter_array;
    signal chain_hash_output : chain_hash_array;
    signal chain_idle : std_logic;
    signal chain_output : chain_output_array;

    signal chain_start : unsigned(wots_log_w - 1 downto 0);
    signal hash_indicator : unsigned(HASH_CHAINS-1 downto 0);

    signal index : integer range 0 to HASH_CHAINS-1;
    signal msg_and_checksum : base_w_array;
    signal msg_as_int : unsigned(wots_log_w - 1 downto 0);
    signal r, r_in : reg_type;

begin

    HashChain: for I in 0 to HASH_CHAINS-1 generate
      Chain : entity work.wots_chain 
        generic map(id => I+1)
        port map(
            clk => clk, reset => reset, 
            d.enable  => chain_enable(I), 
            d.seed => d.pub_seed, 
            d.X => r.sig_word, -- Pasa la palabra cacheadamente
            d.address_4 => d.address_4, 
            d.chain_index => r.ctr, 
            d.continue => chain_continue(I), 
            d.start => chain_start, 
            d.hash_available => hash_indicator(I),
            d.hash => d.hash, 
            q.hash => chain_hash_output(I), 
            q.done => chain_done(I),
            q.result => chain_output(I), 
            q.busy => chain_busy(I), 
            q.ctr => chain_counter(I)
        );
    end generate;

    hash_indicator <= r_in.hash_sel when d.hash.busy = '0' else (others => '0');
    chain_idle <= '1' when chain_busy = ALL_ZEROS else '0';
    msg_and_checksum <= base_w(d.message);
    msg_as_int <= unsigned(msg_and_checksum(wots_len-1-r.ctr)) when r.ctr /= wots_len else (others => '0');
    bram_offset <= chain_counter(index);

    q.bram.din <= chain_output(index);
    q.bram.en <= '1';
    chain_start <= msg_as_int; 
    
    -- Dirección de escritura PK local
    q.bram.addr <= std_logic_vector(to_unsigned(BRAM_WOTS_KEY, BRAM_ADDR_SIZE) + bram_offset);

    combinational : process (r, d, chain_hash_output, chain_done, chain_busy, chain_idle)
       variable v : reg_type;
    begin
        v := r;
        q.hash <= ZERO_HASH_INPUT;
        q.hash.halt <= '0';
        q.bram.wen <= '0';
        q.done <= '0';
        q.sig_mem.req <= '0';
        q.sig_mem.addr <= (others => '0');
        
        chain_enable <= (others => '0');
        chain_continue <= (others => '0');
        index <= 0;

        v.done_indicator := r.done_indicator or chain_done;

        -- CONTROLADOR DEL MULTIPLEXOR
        if d.hash.mnext = '1' and r.state /= S_IDLE then
           v.hash_sel := (others => '0');
           if to_integer(d.hash.id.ctr) > 0 and to_integer(d.hash.id.ctr) <= HASH_CHAINS then
               v.hash_sel(to_integer(d.hash.id.ctr) - 1) := '1';
           end if;
           v.hold_timer := 4; 
        elsif r.hold_timer > 0 then
           v.hold_timer := r.hold_timer - 1;
        elsif r.state = S_IDLE then
           v.hash_sel := (0 => '1', others => '0');
        else
           v.hash_sel := ROTATE_LEFT(r.hash_sel, 1);
        end if;
        
        for k in 0 to HASH_CHAINS-1 loop
             if v.hash_sel(k) = '1' then
                 q.hash <= chain_hash_output(k);
             end if;
        end loop;
        
        case r.state is
             when S_IDLE =>
                  if d.enable = '1' then
                      v.ctr := 0;
                      v.word_pending := '0';
                      v.state := S_READ_SIG_REQ;
                  end if;

             when S_READ_SIG_REQ =>
                  q.sig_mem.req <= '1';
                  -- Dirección a 32 bits, multiplicando offset por 32 bytes
                  q.sig_mem.addr <= std_logic_vector(to_unsigned((BRAM_XMSS_SIG_WOTS + r.ctr) * 32, 32));
                  if d.sig_mem.gnt = '1' then
                      v.state := S_READ_SIG_WAIT;
                  end if;

             when S_READ_SIG_WAIT =>
                  if d.sig_mem.valid = '1' then
                      v.sig_word := d.sig_mem.data;
                      v.word_pending := '1';
                      v.state := S_CHAIN_EN;
                  end if;

             when S_CHAIN_EN =>
                  for k in 0 to HASH_CHAINS-1 loop
                     if chain_busy(k) = '0' then
                         chain_enable(k) <= '1';
                         v.ctr := r.ctr + 1;
                         v.word_pending := '0'; -- Palabra consumida
                         exit;
                     end if;
                  end loop;
                  -- Vaya o no vaya la palabra al chain, revisamos terminados
                  v.state := S_DONE_CHECK;

             when S_DONE_CHECK =>
                  -- Gestión de completados (Vaciado a BRAM)
                  for k in 0 to HASH_CHAINS-1 loop
                     if r.done_indicator(k) = '1' then
                         index <= k;
                         v.done_indicator(k) := '0';
                         chain_continue(k) <= '1';
                         q.bram.wen <= '1';
                         exit; -- Escribe uno a uno
                     end if;
                  end loop;
                  
                  -- Lógica de salto corregida
                  if r.word_pending = '1' then
                        -- El DMA nos trajo el dato, pero todos los chains estaban ocupados. Reintentar.
                        v.state := S_CHAIN_EN;
                  elsif r.ctr = wots_len then
                        -- Se han enviado todas las cadenas, esperamos a que terminen.
                        if chain_idle = '1' and v.done_indicator = ALL_ZEROS then
                            v.state := S_IDLE;
                            q.done <= '1';
                        else
                            v.state := S_DONE_CHECK;
                        end if;
                  else
                        -- Palabra consumida y faltan más. Pedir al bus DMA.
                        v.state := S_READ_SIG_REQ;
                  end if;
        end case;
        r_in <= v;
    end process;

    sequential : process(clk)
    begin
       if rising_edge(clk) then
        if reset = '1' then
           r.state <= S_IDLE;
           r.hash_sel <= (0 => '1', others => '0');
           r.done_indicator <= (others => '0');
           r.ctr <= 0;
           r.hold_timer <= 0;
           r.sig_word <= (others => '0');
           r.word_pending <= '0';
        else
           r <= r_in;
        end if;
       end if;
    end process;
end Behavioral;