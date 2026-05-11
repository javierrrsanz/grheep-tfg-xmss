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
        
        -- Entradas de Datos (Punteros DMA desde el Wrapper)
        mlen        : in  std_logic_vector(31 downto 0);
        sig_base    : in  std_logic_vector(31 downto 0);
        msg_base    : in  std_logic_vector(31 downto 0);
        pk_base     : in  std_logic_vector(31 downto 0);
        
        -- Salidas de Estado
        done        : out std_logic;
        valid       : out std_logic_vector(15 downto 0);

        -- Interfaz Memoria Externa (Lectura 256-bit hacia el Wrapper OBI)
        mem_req     : out std_logic;
        mem_addr    : out std_logic_vector(31 downto 0);
        mem_gnt     : in  std_logic;
        mem_rvalid  : in  std_logic;
        mem_rdata   : in  std_logic_vector(n*8-1 downto 0)
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

    -- SCRATCHPAD INTERNO (4 KB) - Solo para nodos intermedios de L-Tree y WOTS PK
    signal scratch_en_a, scratch_wen_a : std_logic;
    signal scratch_addr_a : std_logic_vector(BRAM_ADDR_SIZE-1 downto 0);
    signal scratch_din_a, scratch_dout_a : std_logic_vector(n*8-1 downto 0);
    
    signal scratch_en_b, scratch_wen_b : std_logic;
    signal scratch_addr_b : std_logic_vector(BRAM_ADDR_SIZE-1 downto 0);
    signal scratch_din_b, scratch_dout_b : std_logic_vector(n*8-1 downto 0);

    -- FIX: 128 Posiciones para evitar Out of Bounds en las direcciones más altas del L-Tree
    type scratch_ram_type is array (0 to 127) of std_logic_vector(n*8-1 downto 0);
    signal scratch_mem : scratch_ram_type := (others => (others => '0'));

    signal mem_req_sel : mem_read_req;

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

    -- Ruteo Interno Dinámico
    hmsg_in.module_input <= vrfy_out.hash_message;
    hmsg_in.hash         <= hash_out;

    wots_in.module_input <= vrfy_out.wots;
    wots_in.pub_seed     <= vrfy_out.pub_seed; 
    wots_in.hash         <= hash_out;

    ltree_in.module_input <= vrfy_out.l_tree;
    ltree_in.bram.a.dout  <= scratch_dout_a;
    ltree_in.bram.b.dout  <= scratch_dout_b;
    ltree_in.thash        <= thash_out.module_output;

    thash_in.pub_seed     <= vrfy_out.pub_seed; 
    thash_in.hash         <= hash_out;

    thash_in.module_input <= ltree_out.thash when vrfy_out.mode_select_l1 = "11" else vrfy_out.thash;
    hash_in <= hmsg_out.hash when vrfy_out.mode_select_l1 = "10" else 
               wots_out.hash when vrfy_out.mode_select_l1 = "01" else thash_out.hash;

    -- Multiplexor de BRAM Interna (Scratchpad)
    process(vrfy_out, wots_out, ltree_out)
    begin
        scratch_en_a   <= '0'; scratch_wen_a  <= '0';
        scratch_addr_a <= (others => '0'); scratch_din_a  <= (others => '0');
        scratch_en_b   <= '0'; scratch_wen_b  <= '0';
        scratch_addr_b <= (others => '0'); scratch_din_b  <= (others => '0');

        if vrfy_out.mode_select_l1 = "01" then
            scratch_en_a   <= wots_out.bram.a.en;   scratch_wen_a  <= wots_out.bram.a.wen;
            scratch_addr_a <= wots_out.bram.a.addr; scratch_din_a  <= wots_out.bram.a.din;
            scratch_en_b   <= wots_out.bram.b.en;   scratch_wen_b  <= wots_out.bram.b.wen;
            scratch_addr_b <= wots_out.bram.b.addr; scratch_din_b  <= wots_out.bram.b.din;
        elsif vrfy_out.mode_select_l1 = "11" then
            scratch_en_a   <= ltree_out.bram.a.en;   scratch_wen_a  <= ltree_out.bram.a.wen;
            scratch_addr_a <= ltree_out.bram.a.addr; scratch_din_a  <= ltree_out.bram.a.din;
            scratch_en_b   <= ltree_out.bram.b.en;   scratch_wen_b  <= ltree_out.bram.b.wen;
            scratch_addr_b <= ltree_out.bram.b.addr; scratch_din_b  <= ltree_out.bram.b.din;
        end if;
    end process;

-- Inferencia de Memoria BRAM Interna (Optimizada para RAMB36)
    process(clk)
    begin
        if rising_edge(clk) then
            -- PUERTO A: Estrictamente de Lectura
            if scratch_en_a = '1' then
                scratch_dout_a <= scratch_mem(to_integer(unsigned(scratch_addr_a(6 downto 0))));
            end if;

            -- PUERTO B: Lectura y Escritura
            if scratch_en_b = '1' then
                if scratch_wen_b = '1' then
                    scratch_mem(to_integer(unsigned(scratch_addr_b(6 downto 0)))) <= scratch_din_b;
                end if;
                scratch_dout_b <= scratch_mem(to_integer(unsigned(scratch_addr_b(6 downto 0))));
            end if;
        end if;
    end process;

    -- Multiplexor de DMA Externo
    process(vrfy_out, hmsg_out, wots_out, mem_gnt, mem_rvalid, mem_rdata)
    begin
        mem_req_sel <= mem_read_req_zero;
        vrfy_in.mem <= mem_read_rsp_zero;
        hmsg_in.mem <= mem_read_rsp_zero;
        wots_in.sig_mem <= mem_read_rsp_zero;

        if vrfy_out.mode_select_l1 = "10" then
            mem_req_sel <= hmsg_out.mem;
            hmsg_in.mem.gnt <= mem_gnt;
            hmsg_in.mem.valid <= mem_rvalid;
            hmsg_in.mem.data <= mem_rdata;
        elsif vrfy_out.mode_select_l1 = "01" then
            mem_req_sel <= wots_out.sig_mem;
            wots_in.sig_mem.gnt <= mem_gnt;
            wots_in.sig_mem.valid <= mem_rvalid;
            wots_in.sig_mem.data <= mem_rdata;
        elsif vrfy_out.mode_select_l1 = "00" then
            mem_req_sel <= vrfy_out.mem;
            vrfy_in.mem.gnt <= mem_gnt;
            vrfy_in.mem.valid <= mem_rvalid;
            vrfy_in.mem.data <= mem_rdata;
        end if;
    end process;

    -- DECODIFICADOR DE DIRECCIONES DMA (Alineado con Boot ROM)
    process(mem_req_sel, sig_base, msg_base, pk_base)
        variable addr_bytes : unsigned(31 downto 0);
        variable offset     : unsigned(31 downto 0);
    begin
        mem_req  <= mem_req_sel.req;
        mem_addr <= (others => '0');

        addr_bytes := unsigned(mem_req_sel.addr);

        if mem_req_sel.req = '1' then
            -- 1. ZONA CLAVE PÚBLICA (Seguridad Máxima - Leído desde PK_BASE)
            if addr_bytes = to_unsigned(BRAM_PK * 32, 32) then 
                -- Root está en offset + 4 bytes del struct de la clave pública
                mem_addr <= std_logic_vector(unsigned(pk_base) + 4);
                
            elsif addr_bytes = to_unsigned((BRAM_PK + 1) * 32, 32) then
                -- Pub_Seed está en offset + 36 bytes
                mem_addr <= std_logic_vector(unsigned(pk_base) + 36);
                
            -- 2. ZONA MENSAJE
            elsif addr_bytes >= to_unsigned(BRAM_MESSAGE * 32, 32) then
                offset := addr_bytes - to_unsigned(BRAM_MESSAGE * 32, 32);
                mem_addr <= std_logic_vector(unsigned(msg_base) + offset);
                
            -- 3. ZONA FIRMA (Index, R, WOTS, Auth Path)
            else
                -- El script C posiciona la firma en RAM replicando los offsets VHDL
                mem_addr <= std_logic_vector(unsigned(sig_base) + addr_bytes);
            end if;
        end if;
    end process;
end Structural;