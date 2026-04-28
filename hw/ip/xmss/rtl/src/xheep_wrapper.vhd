library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.params.ALL;

entity xheep_wrapper is
    port (
        clk         : in  std_logic;
        rst_ni      : in  std_logic; -- Reset asíncrono activo bajo (Estándar X-HEEP)

        -- ==========================================================
        -- INTERFAZ BUS ESCLAVO (X-HEEP REGISTER INTERFACE )
        -- ==========================================================
        reg_req     : in  std_logic;
        reg_we      : in  std_logic;
        reg_addr    : in  std_logic_vector(31 downto 0); -- Direcciones a nivel de byte
        reg_wdata   : in  std_logic_vector(31 downto 0);
        reg_wstrb   : in  std_logic_vector(3 downto 0);
        reg_gnt     : out std_logic;
        reg_rvalid  : out std_logic;
        reg_rdata   : out std_logic_vector(31 downto 0);
        -- ==========================================================
        -- INTERFAZ BUS ESCLAVO (X-HEEP OBI MASTER (XMMSS -> External Memory) )
        -- ==========================================================
    );
end xheep_wrapper;

architecture Behavioral of xheep_wrapper is

    -- ==============================================================
    -- 1. SEÑALES DE CONTROL Y REGISTROS
    -- ==============================================================
    signal reg_enable   : std_logic := '0';
    signal reg_mlen     : std_logic_vector(31 downto 0) := (others => '0');
    
    -- Señales que salen del XMSS
    signal xmss_done    : std_logic;
    signal xmss_valid   : std_logic_vector(15 downto 0);
    signal xmss_rst_high: std_logic;

    -- ==============================================================
    -- 2. SEÑALES DEL EMPAQUETADOR (32 bit -> 256 bit)
    -- ==============================================================
    signal packer_en    : std_logic;
    signal packer_wen   : std_logic;
    signal packer_addr  : std_logic_vector(BRAM_ADDR_SIZE-1 downto 0);
    signal packer_din   : std_logic_vector(255 downto 0);
    
    signal buffer_256   : std_logic_vector(255 downto 0) := (others => '0');
    signal wdata_swapped: std_logic_vector(31 downto 0);
    signal word_index   : integer range 0 to 7;

    -- ==============================================================
    -- 3. SEÑALES DE LA BRAM FÍSICA E INFERENCIA
    -- ==============================================================
    type ram_type is array (0 to (2**BRAM_ADDR_SIZE) - 1) of std_logic_vector(255 downto 0);
    signal physical_bram : ram_type := (others => (others => '0'));

    -- Multiplexor Puerto A
    signal b_en_a       : std_logic;
    signal b_wen_a      : std_logic;
    signal b_addr_a     : std_logic_vector(BRAM_ADDR_SIZE-1 downto 0);
    signal b_din_a      : std_logic_vector(255 downto 0);
    signal b_dout_a     : std_logic_vector(255 downto 0);

    -- Señales directas del IP XMSS Puerto A y B
    signal ip_en_a, ip_wen_a     : std_logic;
    signal ip_addr_a             : std_logic_vector(BRAM_ADDR_SIZE-1 downto 0);
    signal ip_din_a              : std_logic_vector(255 downto 0);
    
    signal ip_en_b, ip_wen_b     : std_logic;
    signal ip_addr_b             : std_logic_vector(BRAM_ADDR_SIZE-1 downto 0);
    signal ip_din_b              : std_logic_vector(255 downto 0);
    signal b_dout_b              : std_logic_vector(255 downto 0);

    -- Lectura combinacional para cumplir reg_intf
    signal reg_rdata_c           : std_logic_vector(31 downto 0);
    signal full_word_write       : std_logic;
begin

    -- Solución al Reset Invertido
    xmss_rst_high <= not rst_ni;

    -- ==============================================================
    -- A. ENDIANNESS 
    -- ==============================================================
    wdata_swapped <= reg_wdata(7 downto 0) & reg_wdata(15 downto 8) & 
                     reg_wdata(23 downto 16) & reg_wdata(31 downto 24);
    full_word_write <= '1' when reg_wstrb = "1111" else '0';

    -- ==============================================================
    -- B. BANCO DE REGISTROS Y EMPAQUETADOR DE MEMORIA
    -- ==============================================================
    word_index <= to_integer(unsigned(reg_addr(4 downto 2)));

    process(clk, rst_ni)
    begin
        if rst_ni = '0' then
            reg_enable  <= '0';
            reg_mlen    <= (others => '0');
            buffer_256  <= (others => '0');
        elsif rising_edge(clk) then
            -- Solo escritura secuencial
            if reg_req = '1' and reg_we = '1' and full_word_write = '1' then
                if reg_addr(13) = '0' then
                    case reg_addr(7 downto 0) is
                        when x"00" =>
                            reg_enable <= reg_wdata(0);
                        when x"08" =>
                            if unsigned(reg_wdata) > 2048 then
                                reg_mlen <= std_logic_vector(to_unsigned(2048, 32));
                            else
                                reg_mlen <= reg_wdata;
                            end if;
                        when others => null;
                    end case;
                elsif reg_enable = '0' then
                    case word_index is
                        when 0 => buffer_256(255 downto 224) <= wdata_swapped;
                        when 1 => buffer_256(223 downto 192) <= wdata_swapped;
                        when 2 => buffer_256(191 downto 160) <= wdata_swapped;
                        when 3 => buffer_256(159 downto 128) <= wdata_swapped;
                        when 4 => buffer_256(127 downto 96)  <= wdata_swapped;
                        when 5 => buffer_256(95 downto 64)   <= wdata_swapped;
                        when 6 => buffer_256(63 downto 32)   <= wdata_swapped;
                        when 7 => null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    -- Lectura combinacional (rdata válido cuando ready=1)
    process(reg_req, reg_we, reg_addr, reg_enable, xmss_done, xmss_valid, reg_mlen)
    begin
        reg_rdata_c <= (others => '0');
        if reg_req = '1' and reg_we = '0' then
            if reg_addr(13) = '0' then
                case reg_addr(7 downto 0) is
                    when x"00" => reg_rdata_c <= (31 downto 1 => '0') & reg_enable;
                    when x"04" => reg_rdata_c <= (31 downto 17 => '0') & xmss_done & xmss_valid;
                    when x"08" => reg_rdata_c <= reg_mlen;
                    when others => reg_rdata_c <= (others => '0');
                end case;
            end if;
        end if;
    end process;

    reg_rdata  <= reg_rdata_c;
    reg_rvalid <= reg_req and (not reg_we);
    reg_gnt    <= reg_req;

    -- Disparador del Empaquetador (Escribe al recibir la 8º palabra - offset 0x1C)
    packer_en   <= '1' when (reg_req = '1' and reg_we = '1' and full_word_write = '1' and reg_addr(13) = '1' and reg_enable = '0' and word_index = 7) else '0';
    packer_wen  <= packer_en;
    packer_addr <= reg_addr(4 + BRAM_ADDR_SIZE downto 5); -- Ejemplo: bits 12 downto 5 para tamaño de 8 bits
    packer_din  <= buffer_256(255 downto 32) & wdata_swapped;

    -- ==============================================================
    -- C. MULTIPLEXOR DE BRAM
    -- ==============================================================
    
    -- PUERTO A: Controlado por el packer si enable=0. Controlado por XMSS si enable=1.
    b_en_a   <= packer_en   when reg_enable = '0' else ip_en_a;
    b_wen_a  <= packer_wen  when reg_enable = '0' else ip_wen_a;
    b_addr_a <= packer_addr when reg_enable = '0' else ip_addr_a;
    b_din_a  <= packer_din  when reg_enable = '0' else ip_din_a;

    -- INFERENCIA BRAM FÍSICA
    process(clk)
    begin
        if rising_edge(clk) then
            -- Puerto A
            if b_en_a = '1' then
                if b_wen_a = '1' then
                    physical_bram(to_integer(unsigned(b_addr_a))) <= b_din_a;
                end if;
                b_dout_a <= physical_bram(to_integer(unsigned(b_addr_a)));
            end if;

            -- Puerto B (Solo lo usa tu XMSS)
            if ip_en_b = '1' then
                if ip_wen_b = '1' then
                    physical_bram(to_integer(unsigned(ip_addr_b))) <= ip_din_b;
                end if;
                b_dout_b <= physical_bram(to_integer(unsigned(ip_addr_b)));
            end if;
        end if;
    end process;

    -- ==============================================================
    -- D. INSTANCIA XMSS
    -- ==============================================================
    inst_xmss_core : entity work.XMSS
        port map (
            clk         => clk,
            reset       => xmss_rst_high,
            enable      => reg_enable,
            mlen        => reg_mlen,
            done        => xmss_done,
            valid       => xmss_valid,
            
            -- Puerto A
            bram_en_a   => ip_en_a,
            bram_wen_a  => ip_wen_a,
            bram_addr_a => ip_addr_a,
            bram_din_a  => ip_din_a,
            bram_dout_a => b_dout_a,
            
            -- Puerto B
            bram_en_b   => ip_en_b,
            bram_wen_b  => ip_wen_b,
            bram_addr_b => ip_addr_b,
            bram_din_b  => ip_din_b,
            bram_dout_b => b_dout_b
        );

end Behavioral;