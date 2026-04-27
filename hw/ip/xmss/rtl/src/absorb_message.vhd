library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.xmss_main_typedef.ALL;
use work.sha_comp.ALL;
use work.params.ALL;

entity absorb_message is
    Port ( clk : in STD_LOGIC;
           reset : in STD_LOGIC;
           d     : in absorb_message_input_type;
           q     : out absorb_message_output_type);
end absorb_message;

architecture Behavioral of absorb_message is
    type state_type is (
        S_IDLE, 
        S_WAIT_FETCH_LOW_1, 
        S_WAIT_FETCH_LOW_2, 
        S_FETCH_LOW, 
        S_HOLD_PADDING,
        S_HASHING, 
        S_WAIT_SHA_MNEXT, 
        S_WAIT_LOAD_HIGH_1, 
        S_WAIT_LOAD_HIGH_2, 
        S_LOAD_HIGH
    );

    type reg_type is record 
        state : state_type;
        block512 : unsigned(511 downto 0);
        total_len : integer range 0 to MAX_HASH_LEN;
        remaining_len : integer range -512 to MAX_HASH_LEN;
        len_appended : std_logic;
        shift_ctr : integer range 0 to 31;
    end record;

    type out_signals is record
        sha : sha_output_type;
    end record;

    signal modules : out_signals;
    signal r, r_in : reg_type;
    
    signal next_message : std_logic_vector(31 downto 0);
    signal next_enable  : std_logic;
    signal next_last    : std_logic;
    
    -- NUEVO: Señal para congelar el SHA256 mientras traemos datos
    signal fetch_halt   : std_logic;

begin

    -- Lógica de congelación: activa cuando esperamos a la BRAM
    fetch_halt <= '1' when (
        r.state = S_WAIT_LOAD_HIGH_1 or 
        r.state = S_WAIT_LOAD_HIGH_2 or 
        r.state = S_WAIT_FETCH_LOW_1 or 
        r.state = S_WAIT_FETCH_LOW_2 or 
        (r.state = S_LOAD_HIGH and r.remaining_len > 256)
    ) else '0';

    sha256 : entity work.sha256
    port map(
        clk       => clk,
        reset     => reset,
        d.enable  => next_enable,
        -- NUEVO: Inyectamos el halt interno junto con el externo
        d.halt    => d.halt or fetch_halt,
        d.last    => next_last,
        d.message => next_message,
        q         => modules.sha
    );

    q.o <= modules.sha.hash;

    combinational : process (r, d, modules)
       variable v : reg_type;
       variable v_hash_enable: std_logic;
    begin
       v := r;
       v_hash_enable := '0';
       q.mnext <= '0';
       q.done <= '0';

       case r.state is
           when S_IDLE =>
               if d.enable = '1' then
                   v.total_len := d.len;
                   v.remaining_len := d.len;
                   v.block512(511 downto 256) := unsigned(d.input);
                   v.len_appended := '0';
                   v.shift_ctr := 0;

                   if d.len > 256 then
                       q.mnext <= '1';
                       v.state := S_WAIT_FETCH_LOW_1;
                   else
                       v.block512(255 downto 0) := (others => '0');
                       v.block512(511 - d.len) := '1';
                       
                       -- FIX: Bucle para limpiar cualquier basura residual de la memoria
                       for i in 256 to 511 loop
                           if i < 511 - d.len then
                               v.block512(i) := '0';
                           end if;
                       end loop;
                       
                       if d.len <= 447 then
                           -- La longitud total debe pasarse en bits, si d.len es total_len
                           v.block512(63 downto 0) := to_unsigned(d.len, 64);
                           v.len_appended := '1';
                       end if;
                       v_hash_enable := '1';
                       v.state := S_HASHING;
                   end if;
               end if;

           when S_WAIT_FETCH_LOW_1 =>
               v.state := S_WAIT_FETCH_LOW_2;

           when S_WAIT_FETCH_LOW_2 =>
               v.state := S_FETCH_LOW;

           when S_FETCH_LOW =>
               v.block512(255 downto 0) := unsigned(d.input);

               if r.remaining_len < 512 then
                   v.block512(511 - r.remaining_len) := '1';
                   for i in 0 to 511 loop
                       if i < 511 - r.remaining_len then
                           v.block512(i) := '0';
                       end if;
                   end loop;
                   
                   if r.remaining_len <= 447 then
                       v.block512(63 downto 0) := to_unsigned(r.total_len, 64);
                       v.len_appended := '1';
                   end if;
               end if;
               
               v_hash_enable := '1';
               v.state := S_HASHING;

           when S_HOLD_PADDING =>
               v_hash_enable := '1';
               v.state := S_HASHING;

           when S_HASHING =>
               v.block512 := SHIFT_LEFT(r.block512, 32);
               v.shift_ctr := r.shift_ctr + 1;
               
               if r.shift_ctr = 15 then
                   v.state := S_WAIT_SHA_MNEXT;
                   v.remaining_len := r.remaining_len - 512;
               end if;
               
           when S_WAIT_SHA_MNEXT =>
               if r.len_appended = '1' then
                   if modules.sha.done = '1' then
                       q.done <= '1';
                       v.state := S_IDLE;
                   end if;
               else
                   if modules.sha.mnext = '1' then
                       if r.remaining_len <= 0 then
                           v.block512 := (others => '0');
                           if r.remaining_len = 0 then
                               v.block512(511) := '1';
                           end if;
                           v.block512(63 downto 0) := to_unsigned(r.total_len, 64);
                           v.len_appended := '1';
                           v.shift_ctr := 0;
                           v_hash_enable := '1';
                           v.state := S_HOLD_PADDING;
                       else
                           q.mnext <= '1';
                           v.state := S_WAIT_LOAD_HIGH_1;
                       end if;
                   end if;
               end if;
               
           when S_WAIT_LOAD_HIGH_1 =>
               v.state := S_WAIT_LOAD_HIGH_2;

           when S_WAIT_LOAD_HIGH_2 =>
               v.state := S_LOAD_HIGH;

           when S_LOAD_HIGH =>
               v.block512(511 downto 256) := unsigned(d.input);
               v.shift_ctr := 0;
               
               if r.remaining_len > 256 then
                   q.mnext <= '1';
                   v.state := S_WAIT_FETCH_LOW_1;
               else
                   v.block512(255 downto 0) := (others => '0');
                   v.block512(511 - r.remaining_len) := '1';
                   
                   -- FIX: Bucle para limpiar cualquier basura residual de la memoria
                   for i in 256 to 511 loop
                       if i < 511 - r.remaining_len then
                           v.block512(i) := '0';
                       end if;
                   end loop;
                   
                   if r.remaining_len <= 447 then
                       v.block512(63 downto 0) := to_unsigned(r.total_len, 64);
                       v.len_appended := '1';
                   end if;
                   v_hash_enable := '1';
                   v.state := S_HASHING;
               end if;

       end case;

       next_message <= std_logic_vector(v.block512(511 downto 480));
       next_enable  <= v_hash_enable;
       next_last    <= r.len_appended;
       
       r_in <= v;
    end process;

    sequential : process(clk)
    begin
       if rising_edge(clk) then
        if reset = '1' then
           r.state <= S_IDLE;
        elsif d.halt = '0' then
           r <= r_in;
        end if;
       end if;
    end process;
    
end Behavioral;