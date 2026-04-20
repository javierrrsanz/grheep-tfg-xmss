library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.params.ALL;
use work.xmss_main_typedef.ALL;

entity hash_core_collection is
    Port ( clk : in STD_LOGIC;
           reset : in STD_LOGIC;
           d     : in hash_subsystem_input_type;
           q     : out hash_subsystem_output_type);
end hash_core_collection;

architecture Behavioral of hash_core_collection is
    constant ALL_ONES : std_logic_vector(HASH_CORES-1 downto 0) := (others => '1');
    constant ALL_ZEROS : std_logic_vector(HASH_CORES-1 downto 0) := (others => '0');

    type hash_output_array is array (HASH_CORES-1 downto 0) of std_logic_vector(n*8-1 downto 0);
    type id_array is array (HASH_CORES-1 downto 0) of hash_id;
    
    -- Máquina de estados del árbitro (4 ciclos blindados para lectura)
    type arbiter_state is (ARB_IDLE, ARB_HOLD_1, ARB_HOLD_2, ARB_HOLD_3, ARB_HOLD_4);

    type reg_type is record 
        done_queue : std_logic_vector(HASH_CORES-1 downto 0);
        mnext_queue : std_logic_vector(HASH_CORES-1 downto 0);
        ids : id_array;
        busy_indicator, halt_indicator : std_logic_vector(HASH_CORES-1 downto 0);
        busy : std_logic;
        arb_state : arbiter_state;
        active_core : integer range 0 to HASH_CORES-1;
    end record;
    
    signal hash_outputs : hash_output_array;
    signal done, mnext, enable : std_logic_vector(HASH_CORES-1 downto 0);
    signal r, r_in : reg_type;

begin

   HashCore: for I in 0 to HASH_CORES-1 generate
      SWITCH_SHA : if (HASH_FUNCTION = "SHA") generate
        SHA : entity work.absorb_message 
        port map(
            clk     => clk, reset => reset, d.enable  => enable(I),
            -- FIX: Usamos el registro 'r' para no congelarlo prematuramente
            d.len  => d.len, d.input => d.input, d.halt => r.halt_indicator(I),
            q.done  => done(I), q.mnext => mnext(I), q.o => hash_outputs(I));
      end generate SWITCH_SHA;
   end generate HashCore;

   q.idle <= '1' when r.busy_indicator = ALL_ZEROS else '0';
   q.busy <= r.busy;

combinational : process (r, d, done, mnext, hash_outputs)
       variable v : reg_type;
       variable v_mnext_handled : boolean;
       variable v_done_handled  : boolean;
       variable v_core_assigned : boolean;
       variable v_fallback_done : boolean;
    begin
       v := r;
       
       q.done <= '0';
       q.o <= (others => '0');
       q.done_id <= zero_hash_id;
       q.mnext <= '0';
       enable <= (others => '0');
       v.busy := '0';
       
       v.done_queue := r.done_queue or done;
       v.mnext_queue := r.mnext_queue or mnext;

       -- Mantenemos congelados a los cores que esperan turno
       for k in 0 to HASH_CORES-1 loop
           v.halt_indicator(k) := v.mnext_queue(k);
       end loop;

       -- ID estable para el bus
       q.id <= r.ids(r.active_core);
       
       -- ÁRBITRO SERIALIZADOR (Priority Encoder sin EXITS)
       case r.arb_state is
           when ARB_IDLE =>
               v_mnext_handled := false;
               for k in 0 to HASH_CORES-1 loop
                   if r.mnext_queue(k) = '1' and not v_mnext_handled then
                       v.active_core := k;
                       q.mnext <= '1';
                       q.id <= r.ids(k);
                       
                       v.mnext_queue(k) := '0';
                       v.halt_indicator(k) := '0';
                       v.ids(k).block_ctr := r.ids(k).block_ctr + 1;
                       v.arb_state := ARB_HOLD_1;
                       v_mnext_handled := true;
                   end if;
               end loop;
               
           when ARB_HOLD_1 => v.arb_state := ARB_HOLD_2;
           when ARB_HOLD_2 => v.arb_state := ARB_HOLD_3;
           when ARB_HOLD_3 => v.arb_state := ARB_HOLD_4;
           when ARB_HOLD_4 => v.arb_state := ARB_IDLE;
       end case;

       -- Liberar cores (Priority Encoder sin EXITS)
       v_done_handled := false;
       for k in 0 to HASH_CORES-1 loop
            -- ATENCIÓN: Se evalúa 'r' para mantener el ciclo de retardo de tu diseño original
            if r.done_queue(k) = '1' and not v_done_handled then
                q.done <= '1';
                v.done_queue(k) := '0';
                v.busy_indicator(k) := '0';
                q.done_id <= r.ids(k);
                q.o <= hash_outputs(k);
                v_done_handled := true;
            end if;
        end loop;

       -- Asignar trabajo (Priority Encoder sin EXITS)
       v_core_assigned := false;
       if d.enable = '1' then
           for k in 0 to HASH_CORES-1 loop
                if v.busy_indicator(k) = '0' and not v_core_assigned then
                    enable(k) <= '1';
                    v.busy_indicator(k) := '1';
                    v.ids(k) := d.id;
                    v_core_assigned := true;
                end if;
           end loop;
       end if;

       if v.busy_indicator = ALL_ONES then v.busy := '1'; end if;

       -- Fallback ID
       v_fallback_done := false;
       if v.arb_state = ARB_IDLE and r.mnext_queue = ALL_ZEROS then
           for k in 0 to HASH_CORES-1 loop
               -- CLAVE PARA ROMPER EL BUCLE FÍSICO: Evaluamos r.busy_indicator en lugar de v.
               -- Así no reenviamos el ID en el mismo ciclo exacto en el que llega un nuevo d.enable
               if v.busy_indicator(k) = '1' and r.busy_indicator(k) = '1' and not v_fallback_done then
                   q.id <= r.ids(k);
                   v_fallback_done := true;
               end if;
           end loop;
       end if;

       r_in <= v;
    end process;
    
   sequential : process(clk)
   begin
       if rising_edge(clk) then
        if reset = '1' then
           r.busy_indicator <= (others => '0');
           r.done_queue <= (others => '0');
           r.mnext_queue <= (others => '0');
           r.halt_indicator <= (others => '0');
           r.busy <= '0';
           r.arb_state <= ARB_IDLE;
           r.active_core <= 0;
           r.ids <= (others => zero_hash_id);
        else
           r <= r_in;
        end if;
       end if;
    end process;
end Behavioral;