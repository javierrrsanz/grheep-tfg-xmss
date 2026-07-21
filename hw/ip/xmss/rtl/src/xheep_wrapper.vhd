library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.params.ALL;
use work.xmss_main_typedef.ALL;
use work.sha_comp.ALL;

entity xheep_wrapper is
    port (
        clk          : in  std_logic;
        rst_ni       : in  std_logic;

        -- INTERFAZ ESCLAVA (Para configuración desde el procesador RISC-V)
        reg_req      : in  std_logic;
        reg_we       : in  std_logic;
        reg_addr     : in  std_logic_vector(31 downto 0);
        reg_wdata    : in  std_logic_vector(31 downto 0);
        reg_wstrb    : in  std_logic_vector(3 downto 0);
        reg_gnt      : out std_logic;
        reg_rvalid   : out std_logic;
        reg_rdata    : out std_logic_vector(31 downto 0);

        -- INTERFAZ MAESTRA DMA (Para pedir datos a la SRAM de X-HEEP)
        obi_req_o    : out std_logic;
        obi_we_o     : out std_logic;
        obi_be_o     : out std_logic_vector(3 downto 0);
        obi_addr_o   : out std_logic_vector(31 downto 0);
        obi_wdata_o  : out std_logic_vector(31 downto 0);
        obi_gnt_i    : in  std_logic;
        obi_rvalid_i : in  std_logic;
        obi_rdata_i  : in  std_logic_vector(31 downto 0);

        -- INTERRUPCIÓN
        irq_o        : out std_logic
    );
end xheep_wrapper;

architecture Behavioral of xheep_wrapper is

    -- Registros de Configuración (Esclavo)
    signal reg_ctrl      : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_sig_addr  : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_msg_addr  : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_mlen      : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_pk_addr   : std_logic_vector(31 downto 0) := (others => '0'); -- NUEVO para XMSS
    
    signal full_word_write : std_logic;
    signal reg_rdata_c     : std_logic_vector(31 downto 0);

    -- Latch de estado
    signal latched_done  : std_logic := '0';
    signal latched_valid : std_logic_vector(15 downto 0) := (others => '0');

    -- Señales hacia el Core XMSS
    signal xmss_enable   : std_logic := '0';
    signal xmss_done     : std_logic;
    signal xmss_valid    : std_logic_vector(15 downto 0);
    signal xmss_rst_high : std_logic;
    signal xmss_mem_req  : std_logic;
    signal xmss_mem_addr : std_logic_vector(31 downto 0);
    signal xmss_mem_gnt  : std_logic;
    signal xmss_mem_rvalid : std_logic;

    -- Señales del DMA interno bajo demanda
    signal mem_req      : std_logic;
    signal mem_addr     : std_logic_vector(31 downto 0);
    signal mem_gnt      : std_logic;
    signal mem_rvalid   : std_logic;
    signal mem_rdata    : std_logic_vector(255 downto 0);

    -- Máquina de estados del DMA Traductor (32-bit a 256-bit)
    type dma_state_type is (S_IDLE, S_REQ_WORD, S_WAIT_WORD, S_VALID_OUT);
    signal dma_state : dma_state_type := S_IDLE;

    signal dma_word_idx : integer range 0 to 7 := 0;
    signal base_addr    : unsigned(31 downto 0) := (others => '0');
    signal buffer_256   : std_logic_vector(255 downto 0) := (others => '0');
    
    -- Volteo de Endianness
    signal rdata_swapped : std_logic_vector(31 downto 0);

    -- SEÑALES MODO HASH ONLY
    signal hash_enable : std_logic := '0';
    signal hash_done   : std_logic := '0';
    signal hash_mem_req : std_logic := '0';
    signal hash_mem_addr : std_logic_vector(31 downto 0);
    signal hash_mem_gnt : std_logic;
    signal hash_mem_rvalid : std_logic;
    signal hash_result : std_logic_vector(255 downto 0) := (others => '0');
    
    signal absorb_in   : absorb_message_input_type;
    signal absorb_out  : absorb_message_output_type;

    type hash_state_type is (H_IDLE, H_REQ, H_WAIT_DMA, H_WAIT_SHA);
    signal hash_state : hash_state_type := H_IDLE;
    signal hash_addr_offset : unsigned(31 downto 0) := (others => '0');

begin

    xmss_rst_high <= not rst_ni;
    full_word_write <= '1' when reg_wstrb = "1111" else '0';

    -- MUX DMA
    mem_req <= xmss_mem_req when hash_enable = '0' else hash_mem_req;
    mem_addr <= xmss_mem_addr when hash_enable = '0' else hash_mem_addr;
    xmss_mem_gnt <= mem_gnt when hash_enable = '0' else '0';
    xmss_mem_rvalid <= mem_rvalid when hash_enable = '0' else '0';
    hash_mem_gnt <= mem_gnt when hash_enable = '1' else '0';
    hash_mem_rvalid <= mem_rvalid when hash_enable = '1' else '0';

    -- 1. ESCLAVO DE CONFIGURACIÓN (RISC-V escribe aquí)
    process(clk, rst_ni)
    begin
        if rst_ni = '0' then
            reg_ctrl     <= (others => '0');
            reg_sig_addr <= (others => '0');
            reg_msg_addr <= (others => '0');
            reg_mlen     <= (others => '0');
            reg_pk_addr  <= (others => '0');
        elsif rising_edge(clk) then
            -- Autoclear del bit de START
            if reg_ctrl(0) = '1' then
                reg_ctrl(0) <= '0';
            end if;

            -- NUEVO: Auto-apaga el botón de ACK
            if reg_ctrl(1) = '1' then
                reg_ctrl(1) <= '0'; 
            end if;

            -- Autoclear del bit de START HASH
            if reg_ctrl(2) = '1' then
                reg_ctrl(2) <= '0';
            end if;

            if reg_req = '1' and reg_we = '1' and full_word_write = '1' then
                case reg_addr(7 downto 0) is
                    when x"00" => reg_ctrl     <= reg_wdata;
                    when x"08" => reg_sig_addr <= reg_wdata;
                    when x"10" => reg_msg_addr <= reg_wdata;
                    when x"14" => reg_mlen     <= reg_wdata;
                    when x"18" => reg_pk_addr  <= reg_wdata; -- Nueva dirección (Offset 0x18)
                    when others => null;
                end case;
            end if;
        end if;
    end process;

    process(reg_req, reg_we, reg_addr, reg_ctrl, latched_done, latched_valid, reg_sig_addr, reg_msg_addr, reg_mlen, reg_pk_addr)
    begin
        reg_rdata_c <= (others => '0');
        if reg_req = '1' and reg_we = '0' then
            case reg_addr(7 downto 0) is
                when x"00" => reg_rdata_c <= reg_ctrl;
                when x"04" => reg_rdata_c <= (31 downto 17 => '0') & latched_done & latched_valid;
                when x"08" => reg_rdata_c <= reg_sig_addr;
                when x"10" => reg_rdata_c <= reg_msg_addr;
                when x"14" => reg_rdata_c <= reg_mlen;
                when x"18" => reg_rdata_c <= reg_pk_addr;
                -- Registros Hash
                when x"20" => reg_rdata_c <= hash_result(255 downto 224);
                when x"24" => reg_rdata_c <= hash_result(223 downto 192);
                when x"28" => reg_rdata_c <= hash_result(191 downto 160);
                when x"2C" => reg_rdata_c <= hash_result(159 downto 128);
                when x"30" => reg_rdata_c <= hash_result(127 downto 96);
                when x"34" => reg_rdata_c <= hash_result(95 downto 64);
                when x"38" => reg_rdata_c <= hash_result(63 downto 32);
                when x"3C" => reg_rdata_c <= hash_result(31 downto 0);
                when others => reg_rdata_c <= (others => '0');
            end case;
        end if;
    end process;

    reg_rdata  <= reg_rdata_c;
    reg_rvalid <= reg_req and (not reg_we);
    reg_gnt    <= reg_req;


    -- 2. CONTROL PRINCIPAL DEL ACELERADOR
    process(clk, rst_ni)
    begin
        if rst_ni = '0' then
            xmss_enable <= '0';
            latched_done <= '0';
            latched_valid <= (others => '0');
            hash_enable <= '0';
        elsif rising_edge(clk) then
            if reg_ctrl(0) = '1' then
                xmss_enable <= '1';
                latched_done <= '0';
                latched_valid <= (others => '0');
            end if;

            if reg_ctrl(2) = '1' then
                hash_enable <= '1';
                latched_done <= '0';
            end if;

            -- NUEVO: La CPU apaga la interrupción (Bit 1)
            if reg_ctrl(1) = '1' then
                latched_done <= '0';
            end if;

            if xmss_done = '1' then
                xmss_enable <= '0';
                latched_done <= '1';
                latched_valid <= xmss_valid;
            end if;
            
            if hash_done = '1' then
                hash_enable <= '0';
                latched_done <= '1';
            end if;
        end if;
    end process;

    irq_o <= latched_done;

    -- 2.5 HASH ONLY FSM
    process(clk, rst_ni)
    begin
        if rst_ni = '0' then
            hash_state <= H_IDLE;
            hash_mem_req <= '0';
            hash_addr_offset <= (others => '0');
            absorb_in.enable <= '0';
            absorb_in.halt <= '0';
            absorb_in.len <= 0;
            absorb_in.input <= (others => '0');
            hash_done <= '0';
            hash_result <= (others => '0');
        elsif rising_edge(clk) then
            hash_done <= '0';
            absorb_in.enable <= '0';

            case hash_state is
                when H_IDLE =>
                    if hash_enable = '1' then
                        hash_state <= H_REQ;
                        hash_addr_offset <= (others => '0');
                        absorb_in.len <= to_integer(unsigned(reg_mlen));
                        hash_mem_req <= '1';
                        hash_mem_addr <= std_logic_vector(unsigned(reg_pk_addr));
                        absorb_in.halt <= '1'; -- Congelar SHA mientras traemos primeros 32B
                    end if;
                when H_REQ =>
                    if hash_mem_gnt = '1' then
                        hash_mem_req <= '0';
                        hash_state <= H_WAIT_DMA;
                    end if;
                when H_WAIT_DMA =>
                    if hash_mem_rvalid = '1' then
                        absorb_in.input <= mem_rdata;
                        absorb_in.enable <= '1';
                        absorb_in.halt <= '0'; -- Liberar SHA ahora que tenemos datos
                        hash_state <= H_WAIT_SHA;
                    end if;
                when H_WAIT_SHA =>
                    if absorb_out.mnext = '1' then
                        hash_addr_offset <= hash_addr_offset + 32;
                        hash_mem_req <= '1';
                        hash_mem_addr <= std_logic_vector(unsigned(reg_pk_addr) + hash_addr_offset + 32);
                        absorb_in.halt <= '1'; -- Congelar SHA mientras pedimos siguientes 32B
                        hash_state <= H_REQ;
                    elsif absorb_out.done = '1' then
                        hash_result <= absorb_out.o;
                        hash_done <= '1';
                        hash_state <= H_IDLE;
                    end if;
            end case;
        end if;
    end process;
    
    inst_hash_only : entity work.absorb_message
        port map(
            clk   => clk,
            reset => xmss_rst_high,
            d     => absorb_in,
            q     => absorb_out
        );


    -- 3. DMA MAESTRO "ON DEMAND" (Traductor 32b -> 256b)
    obi_we_o    <= '0'; -- Siempre leemos
    obi_be_o    <= "1111";
    obi_wdata_o <= (others => '0');

    -- Volteo criptográfico (Big Endian)
    rdata_swapped <= obi_rdata_i(7 downto 0) & obi_rdata_i(15 downto 8) & 
                     obi_rdata_i(23 downto 16) & obi_rdata_i(31 downto 24);

    -- Reconocimiento de petición combinacional (Aceleramos 1 ciclo)
    mem_gnt <= '1' when (dma_state = S_IDLE and mem_req = '1') else '0';

    process(clk, rst_ni)
    begin
        if rst_ni = '0' then
            dma_state <= S_IDLE;
            obi_req_o <= '0';
            dma_word_idx <= 0;
            buffer_256 <= (others => '0');
            base_addr <= (others => '0');
            mem_rvalid <= '0';
        elsif rising_edge(clk) then
            mem_rvalid <= '0'; -- Pulso por defecto a 0

            case dma_state is
                when S_IDLE =>
                    if mem_req = '1' then
                        base_addr <= unsigned(mem_addr);
                        dma_word_idx <= 0;
                        buffer_256 <= (others => '0');
                        dma_state <= S_REQ_WORD;
                    end if;

                when S_REQ_WORD =>
                    obi_req_o <= '1';
                    obi_addr_o <= std_logic_vector(base_addr + to_unsigned(dma_word_idx * 4, 32));
                    if obi_gnt_i = '1' then
                        obi_req_o <= '0';
                        dma_state <= S_WAIT_WORD;
                    end if;

                when S_WAIT_WORD =>
                    if obi_rvalid_i = '1' then
                        -- Llenamos el buffer en orden Big Endian
                        case dma_word_idx is
                            when 0 => buffer_256(255 downto 224) <= rdata_swapped;
                            when 1 => buffer_256(223 downto 192) <= rdata_swapped;
                            when 2 => buffer_256(191 downto 160) <= rdata_swapped;
                            when 3 => buffer_256(159 downto 128) <= rdata_swapped;
                            when 4 => buffer_256(127 downto 96)  <= rdata_swapped;
                            when 5 => buffer_256(95 downto 64)   <= rdata_swapped;
                            when 6 => buffer_256(63 downto 32)   <= rdata_swapped;
                            when 7 => buffer_256(31 downto 0)    <= rdata_swapped;
                            when others => null;
                        end case;

                        if dma_word_idx = 7 then
                            dma_state <= S_VALID_OUT;
                        else
                            dma_word_idx <= dma_word_idx + 1;
                            dma_state <= S_REQ_WORD;
                        end if;
                    end if;

                when S_VALID_OUT =>
                    -- Enviamos el pulso de dato listo al XMSS
                    mem_rvalid <= '1';
                    mem_rdata <= buffer_256;
                    dma_state <= S_IDLE;

                when others =>
                    dma_state <= S_IDLE;
            end case;
        end if;
    end process;

    -- 4. INSTANCIA DEL ACELERADOR XMSS
    inst_xmss_core : entity work.XMSS
        port map (
            clk         => clk,
            reset       => xmss_rst_high,
            enable      => xmss_enable,
            mlen        => reg_mlen,
            sig_base    => reg_sig_addr,
            msg_base    => reg_msg_addr,
            pk_base     => reg_pk_addr, -- Usamos el nuevo registro configurado en C
            done        => xmss_done,
            valid       => xmss_valid,
            mem_req     => xmss_mem_req,
            mem_addr    => xmss_mem_addr,
            mem_gnt     => xmss_mem_gnt,
            mem_rvalid  => xmss_mem_rvalid,
            mem_rdata   => mem_rdata
        );

end Behavioral;