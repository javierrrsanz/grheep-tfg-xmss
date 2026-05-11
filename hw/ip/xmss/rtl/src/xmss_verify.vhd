library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.params.ALL;
use work.xmss_main_typedef.ALL;
use IEEE.NUMERIC_STD.ALL;

entity xmss_verify is
    port(
        clk   : in std_logic;
        reset : in std_logic;
        d     : in xmss_verify_input_type;
        q     : out xmss_verify_output_type);
end xmss_verify;

architecture Behavioral of xmss_verify is    
    type state_type is (
        S_IDLE,
        S_LOAD_INDEX_REQ,
        S_LOAD_INDEX_WAIT,
        S_LOAD_PUB_SEED_REQ,
        S_LOAD_PUB_SEED_WAIT,
        S_HASH_MESSAGE,
        S_WOTS_VRFY,
        S_LTREE,
        S_ROOT_REQ,
        S_ROOT_WAIT,
        S_COMP_ROOT,
        S_CHECK_1,
        S_WAIT_DELAY,
        S_CHECK_2,
        S_DONE
    );
    
    type reg_type is record
        state : state_type;
        index : unsigned(tree_height-1 downto 0);
        is_valid : std_logic_vector(15 downto 0);
        pub_seed : std_logic_vector(n*8-1 downto 0);
        
        -- Registros de Seguridad Redundante FI
        check_1_pass  : std_logic;
        calc_root_reg : std_logic_vector(n*8-1 downto 0);
        exp_root_reg  : std_logic_vector(n*8-1 downto 0);
    end record;

    signal compute_root : xmss_compute_root_input_type;
    signal r, r_in : reg_type;
    signal modules_root_q : xmss_compute_root_output_type;

    attribute DONT_TOUCH : string;
    attribute DONT_TOUCH of r : signal is "TRUE";
    attribute DONT_TOUCH of r_in : signal is "TRUE";

begin
    
    comproot : entity work.compute_root
    port map(
        clk     => clk,
        reset   => reset,
        d       => compute_root,
        q       => modules_root_q);

    compute_root.leaf <= d.l_tree.leaf_node;
    compute_root.leaf_idx <= to_integer(r.index);
    compute_root.thash <= d.thash;
    compute_root.mem <= d.mem; -- Pasa la respuesta de memoria externa a compute_root
    
    q.thash <= modules_root_q.thash;
    q.hash_message.mlen <=  d.mlen;
    q.hash_message.index <= r.index;
    q.l_tree.address_4 <= std_logic_vector(resize(r.index, 32));
    
    q.wots.message <= d.hash_message.mhash;
    q.wots.address_4 <= std_logic_vector(resize(r.index, 32));

    combinational : process (r, d, modules_root_q)
       variable v : reg_type;   
    begin
        v := r;
        
        -- Salidas por defecto
        q.pub_seed <= r.pub_seed;
        q.mode_select_l1 <= "00";
        q.valid <= r.is_valid;
        q.done <= '0';
        q.hash_message.enable <= '0';
        q.l_tree.enable <= '0';
        q.wots.enable <= '0';
        compute_root.enable <= '0';
        
        -- Inicialización segura del bus de memoria
        q.mem.req <= '0';
        q.mem.addr <= (others => '0');

        case r.state is
           when S_IDLE =>
               if d.enable = '1' then
                   v.state := S_LOAD_INDEX_REQ;
               end if;

           when S_LOAD_INDEX_REQ =>
               q.mem.req <= '1';
               -- Multiplicamos por 32 para alinear a bytes la dirección DMA
               q.mem.addr <= std_logic_vector(to_unsigned(BRAM_XMSS_SIG * 32, 32));
               if d.mem.gnt = '1' then
                   v.state := S_LOAD_INDEX_WAIT;
               end if;

           when S_LOAD_INDEX_WAIT =>
               if d.mem.valid = '1' then
                   v.index := unsigned(d.mem.data(tree_height - 1 downto 0));
                   v.state := S_LOAD_PUB_SEED_REQ;
               end if;

           when S_LOAD_PUB_SEED_REQ =>
               q.mem.req <= '1';
               -- BRAM_PK + 1 es el offset de bloque para pub_seed. Multiplicado por 32 bytes
               q.mem.addr <= std_logic_vector(to_unsigned((BRAM_PK + 1) * 32, 32));
               if d.mem.gnt = '1' then
                   v.state := S_LOAD_PUB_SEED_WAIT;
               end if;

           when S_LOAD_PUB_SEED_WAIT =>
               if d.mem.valid = '1' then
                   v.pub_seed := d.mem.data;
                   v.state := S_HASH_MESSAGE;
               end if;
               
           when S_HASH_MESSAGE => 
               q.mode_select_l1 <= "10";
               q.hash_message.enable <= '1';
               if d.hash_message.done = '1' then                       
                   v.state := S_WOTS_VRFY;
               end if;

           when S_WOTS_VRFY =>
               q.mode_select_l1 <= "01";
               q.wots.enable <= '1';
               if d.wots.done = '1' then
                   v.state := S_LTREE;
               end if;

           when S_LTREE =>
               q.mode_select_l1 <= "11";
               q.l_tree.enable <= '1';
               if d.l_tree.done = '1' then
                   v.state := S_ROOT_REQ;
               end if;

           when S_ROOT_REQ =>
               q.mem.req <= '1';
               -- BRAM_PK (offset 0) contiene el Root esperado.
               q.mem.addr <= std_logic_vector(to_unsigned(BRAM_PK * 32, 32));
               if d.mem.gnt = '1' then
                   v.state := S_ROOT_WAIT;
               end if;

           when S_ROOT_WAIT =>
               if d.mem.valid = '1' then
                   v.exp_root_reg := d.mem.data;
                   v.state := S_COMP_ROOT;
               end if;

           when S_COMP_ROOT =>
               q.mode_select_l1 <= "00";
               compute_root.enable <= '1';
               
               -- Ruteo seguro e individual de los campos de memoria del submódulo
               q.mem.req  <= modules_root_q.mem.req;
               q.mem.addr <= modules_root_q.mem.addr;
               
               if modules_root_q.done = '1' then
                   v.calc_root_reg := modules_root_q.root;
                   v.state := S_CHECK_1; 
               end if;

           -- VERIFICACIÓN (Intacta, diseño de seguridad original)
           when S_CHECK_1 =>
               if r.calc_root_reg = r.exp_root_reg then
                   v.check_1_pass := '1';
                   v.state := S_WAIT_DELAY;
               else
                   v.check_1_pass := '0';
                   v.is_valid := STATUS_INVALID;
                   v.state := S_DONE;
               end if;

           when S_WAIT_DELAY =>
               v.state := S_CHECK_2;

           when S_CHECK_2 =>
               if (r.calc_root_reg = r.exp_root_reg) and (r.check_1_pass = '1') then 
                   v.is_valid := STATUS_VALID;
               else
                   v.is_valid := STATUS_INVALID;
               end if;
               v.state := S_DONE;

           when S_DONE =>
               q.done <= '1';
               if d.enable = '0' then
                   v.is_valid := STATUS_IDLE; 
                   v.check_1_pass := '0';
                   v.state := S_IDLE; 
               end if;

        end case;
        r_in <= v;
    end process;

    sequential : process(clk)
    begin
       if rising_edge(clk) then
        if reset = '1' then
           r.state <= S_IDLE;
           r.index <= (others => '0');
           r.is_valid <= STATUS_IDLE; 
           r.pub_seed <= (others => '0');
           r.check_1_pass <= '0';
           r.calc_root_reg <= (others => '0');
           r.exp_root_reg <= (others => '0');
        else
           r <= r_in;
        end if;
       end if;
    end process;
end Behavioral;