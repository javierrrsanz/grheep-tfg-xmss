library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.params.ALL;
use work.xmss_main_typedef.ALL;
use IEEE.NUMERIC_STD.ALL;

entity compute_root is
    port (
           clk   : in std_logic;
           reset : in std_logic;
           d     : in xmss_compute_root_input_type;
           q     : out xmss_compute_root_output_type);
end compute_root;

architecture Behavioral of compute_root is
    type state_type is (S_IDLE, S_REQ_AUTH, S_WAIT_AUTH, S_LOOP, S_THASH);
    type reg_type is record
        state : state_type;
        ctr : integer range 0 to wots_len;
        leaf_idx : unsigned(tree_height-1 downto 0);
        init : std_logic;
        auth_word : std_logic_vector(n*8-1 downto 0);
    end record;
    signal r, r_in : reg_type;
begin

    q.thash.address_3 <= x"00000002";
    q.thash.address_4 <= x"00000000";
    q.thash.address_5 <= std_logic_vector(to_unsigned(r.ctr, 32));
    q.thash.address_6 <= std_logic_vector(shift_right(resize(r.leaf_idx, 32), 1));
    
    q.root <= d.thash.o;

    combinational : process (r, d)
       variable v : reg_type;
    begin
        v := r;
        
        -- Default assignments
        q.done <= '0';
        q.thash.enable <= '0';
        q.mem.req <= '0';
        q.mem.addr <= (others => '0');

        case r.state is
           when S_IDLE =>    
                if d.enable = '1' then
                    v.ctr := 0;
                    v.init := '1';
                    v.leaf_idx := to_unsigned(d.leaf_idx, tree_height);
                    v.state := S_REQ_AUTH;
                end if;     
                
            when S_REQ_AUTH =>
                q.mem.req <= '1';
                -- CORRECCIÓN: Bus de 32 bits y offset multiplicado por 32 bytes
                q.mem.addr <= std_logic_vector(to_unsigned((BRAM_XMSS_SIG_AUTH + r.ctr) * 32, 32));
                if d.mem.gnt = '1' then
                    v.state := S_WAIT_AUTH;
                end if;
                
            when S_WAIT_AUTH =>
                if d.mem.valid = '1' then
                    v.auth_word := d.mem.data;
                    v.state := S_LOOP;
                end if;
                
            when S_THASH =>
                if d.thash.done = '1' then
                    -- Shift leaf index for the address
                    v.leaf_idx := shift_right(r.leaf_idx, 1); 
                    
                    -- Set init to 0
                    v.init := '0';
                    
                    -- Check whether the algorithm is done
                    if r.ctr = tree_height - 1 then
                        v.state := S_IDLE;
                        q.done <= '1';
                    else
                        v.ctr := r.ctr + 1;
                        v.state := S_REQ_AUTH;   
                    end if;
                end if;
                
            when S_LOOP =>
                q.thash.enable <= '1';
                v.state := S_THASH;
                
        end case;
        
        r_in <= v;
    end process; 

    -- Assign the inputs to the thash module
    -- If this is the first round, a leaf node will serve as one input.
    -- Otherwise one input is the previous value and the other is part
    -- of the auth path fetched from external memory.
    init_mux : process(r.init, d.leaf, d.thash.o, r.auth_word, r.leaf_idx)
    begin
        if r.leaf_idx mod 2 = 0 then
            if r.init = '1' then
                q.thash.input_1 <= d.leaf;
            else
                q.thash.input_1 <= d.thash.o;
            end if;
            q.thash.input_2 <= r.auth_word;
        else
            q.thash.input_1 <=  r.auth_word;
            if r.init = '1' then
                q.thash.input_2 <= d.leaf;
            else
                q.thash.input_2 <= d.thash.o;
            end if;
        end if;
    end process;

    sequential : process(clk)
    begin
       if rising_edge(clk) then
        if reset = '1' then
           r.state <= S_IDLE;
           r.auth_word <= (others => '0');
           r.ctr <= 0;
           r.init <= '0';
           r.leaf_idx <= (others => '0');
        else
           r <= r_in;
        end if;
       end if;
    end process;

end Behavioral;