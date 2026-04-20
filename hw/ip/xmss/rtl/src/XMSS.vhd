library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.params.ALL;
use work.xmss_main_typedef.ALL;

entity XMSS is
    Port (
        -- Control y Reloj
        clk         : in  std_logic;
        reset       : in  std_logic;
        enable      : in  std_logic;
        
        -- Entradas de Datos
        mlen        : in  std_logic_vector(31 downto 0);
        
        -- Salidas de Estado
        done        : out std_logic;
        valid       : out std_logic_vector(15 downto 0); -- Antes: std_logic

        -- Interfaz Memoria BRAM - Puerto A
        bram_en_a   : out std_logic;
        bram_wen_a  : out std_logic;
        bram_addr_a : out std_logic_vector(BRAM_ADDR_SIZE-1 downto 0);
        bram_din_a  : out std_logic_vector(n*8-1 downto 0);
        bram_dout_a : in  std_logic_vector(n*8-1 downto 0);

        -- Interfaz Memoria BRAM - Puerto B
        bram_en_b   : out std_logic;
        bram_wen_b  : out std_logic;
        bram_addr_b : out std_logic_vector(BRAM_ADDR_SIZE-1 downto 0);
        bram_din_b  : out std_logic_vector(n*8-1 downto 0);
        bram_dout_b : in  std_logic_vector(n*8-1 downto 0)
    );
end XMSS;

architecture Structural of XMSS is

    signal vrfy_in   : xmss_verify_input_type;
    signal vrfy_out  : xmss_verify_output_type;
    signal hmsg_in   : hash_message_input_type;
    signal hmsg_out  : hash_message_output_type;
    signal wots_in   : wots_input_type;
    signal wots_out  : wots_output_type;
    signal ltree_in  : xmss_l_tree_input_type;
    signal ltree_out : xmss_l_tree_output_type;
    signal thash_in  : xmss_thash_h_input_type;
    signal thash_out : xmss_thash_h_output_type;
    signal hash_in   : hash_subsystem_input_type;
    signal hash_out  : hash_subsystem_output_type;

begin

    -- Instancias
    inst_xmss_verify : entity work.xmss_verify port map(clk => clk, reset => reset, d => vrfy_in, q => vrfy_out);
    inst_hash_msg    : entity work.hash_message port map(clk => clk, reset => reset, d => hmsg_in, q => hmsg_out);
    inst_wots        : entity work.wots port map(clk => clk, reset => reset, d => wots_in, q => wots_out);
    inst_ltree       : entity work.l_tree port map(clk => clk, reset => reset, d => ltree_in, q => ltree_out);
    inst_thash       : entity work.thash_h port map(clk => clk, reset => reset, d => thash_in, q => thash_out);
    inst_hash_core   : entity work.hash_core_collection port map(clk => clk, reset => reset, d => hash_in, q => hash_out);

    -- Salidas del Top
    done  <= vrfy_out.done;
    valid <= vrfy_out.valid;

    -- Entradas al orquestador
    vrfy_in.enable       <= enable;
    vrfy_in.mlen         <= to_integer(unsigned(mlen));
    vrfy_in.wots         <= wots_out.module_output;
    vrfy_in.l_tree       <= ltree_out.module_output;
    vrfy_in.thash        <= thash_out.module_output;
    vrfy_in.hash_message <= hmsg_out.module_output;
    vrfy_in.bram.a.dout  <= bram_dout_a;
    vrfy_in.bram.b.dout  <= bram_dout_b;

    -- Conexiones internas (NUEVO: La semilla fluye dinámicamente)
    hmsg_in.module_input <= vrfy_out.hash_message;
    hmsg_in.hash         <= hash_out;
    hmsg_in.bram.dout    <= bram_dout_b;

    wots_in.module_input <= vrfy_out.wots;
    wots_in.pub_seed     <= vrfy_out.pub_seed; -- <-- Semilla dinámica
    wots_in.bram_b.dout  <= bram_dout_b;
    wots_in.hash         <= hash_out;

    ltree_in.module_input <= vrfy_out.l_tree;
    ltree_in.bram.a.dout  <= bram_dout_a;
    ltree_in.bram.b.dout  <= bram_dout_b;
    ltree_in.thash        <= thash_out.module_output;

    thash_in.pub_seed     <= vrfy_out.pub_seed; -- <-- Semilla dinámica
    thash_in.hash         <= hash_out;

    -- Ruteo Dinámico MUX
    thash_in.module_input <= ltree_out.thash when vrfy_out.mode_select_l1 = "11" else vrfy_out.thash;
    hash_in <= hmsg_out.hash when vrfy_out.mode_select_l1 = "10" else 
               wots_out.hash when vrfy_out.mode_select_l1 = "01" else thash_out.hash;

    process(vrfy_out, wots_out, ltree_out, hmsg_out)
    begin
        if vrfy_out.mode_select_l1 = "01" then
            bram_en_a <= wots_out.bram.a.en; bram_wen_a <= wots_out.bram.a.wen; bram_addr_a <= wots_out.bram.a.addr; bram_din_a <= wots_out.bram.a.din;
            bram_en_b <= wots_out.bram.b.en; bram_wen_b <= wots_out.bram.b.wen; bram_addr_b <= wots_out.bram.b.addr; bram_din_b <= wots_out.bram.b.din;
        elsif vrfy_out.mode_select_l1 = "11" then
            bram_en_a <= ltree_out.bram.a.en; bram_wen_a <= ltree_out.bram.a.wen; bram_addr_a <= ltree_out.bram.a.addr; bram_din_a <= ltree_out.bram.a.din;
            bram_en_b <= ltree_out.bram.b.en; bram_wen_b <= ltree_out.bram.b.wen; bram_addr_b <= ltree_out.bram.b.addr; bram_din_b <= ltree_out.bram.b.din;
        elsif vrfy_out.mode_select_l1 = "10" then
            bram_en_a <= vrfy_out.bram.a.en; bram_wen_a <= vrfy_out.bram.a.wen; bram_addr_a <= vrfy_out.bram.a.addr; bram_din_a <= vrfy_out.bram.a.din;
            bram_en_b <= hmsg_out.bram.en; bram_wen_b <= hmsg_out.bram.wen; bram_addr_b <= hmsg_out.bram.addr; bram_din_b <= hmsg_out.bram.din;
        else
            bram_en_a <= vrfy_out.bram.a.en; bram_wen_a <= vrfy_out.bram.a.wen; bram_addr_a <= vrfy_out.bram.a.addr; bram_din_a <= vrfy_out.bram.a.din;
            bram_en_b <= vrfy_out.bram.b.en; bram_wen_b <= vrfy_out.bram.b.wen; bram_addr_b <= vrfy_out.bram.b.addr; bram_din_b <= vrfy_out.bram.b.din;
        end if;
    end process;
end Structural;