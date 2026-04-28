library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.params.ALL;

entity xheep_wrapper_tb is
end xheep_wrapper_tb;

architecture Behavioral of xheep_wrapper_tb is

    constant clk_period : time := 10 ns;

    -- Señales del DUT
    signal clk         : std_logic := '0';
    signal rst_ni      : std_logic := '0';
    signal reg_req     : std_logic := '0';
    signal reg_we      : std_logic := '0';
    signal reg_addr    : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_wdata   : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_wstrb   : std_logic_vector(3 downto 0) := (others => '0');
    signal reg_gnt     : std_logic;
    signal reg_rvalid  : std_logic;
    signal reg_rdata   : std_logic_vector(31 downto 0);

    -- ==============================================================
    -- LA FIRMA OFICIAL (KAT VECTORS)
    -- ==============================================================
    type ram_type is array (0 to 255) of std_logic_vector(255 downto 0);
    
    impure function get_kat_signature return ram_type is
        variable mem : ram_type := (others => (others => '0'));
    begin
        -- ROOT 
        mem(BRAM_PK) := x"A3F3840A84B677379478D1DFE084F8F528F79C0DF72A9E8A937775EBECCF60F8";
        
        -- WOTS SIGNATURE (67 Bloques)
        mem(BRAM_XMSS_SIG_WOTS + 0) := x"49DADC5FE200C42CECE300CB71B0DD37E38D1DE0F766438F09C16028887D60D9";
        mem(BRAM_XMSS_SIG_WOTS + 1) := x"868C74920658323B7C9CDD670A68C9B7DE18C808EA42A2D4F9B4A5E3D70FF2F7";
        mem(BRAM_XMSS_SIG_WOTS + 2) := x"097FC69AC835B00E4B503FE75442D94A1D27FF63155B192697997D1F6F4C642C";
        mem(BRAM_XMSS_SIG_WOTS + 3) := x"CA294AA684EE6233884E1B63CB15A39FF09A6FEECCA5BC0E91A46AF4AD9899FE";
        mem(BRAM_XMSS_SIG_WOTS + 4) := x"1CD7E87FF294A2EE0DFE14765A3B6B2C72AF4897D06C44AEEFC7303ADB8881EF";
        mem(BRAM_XMSS_SIG_WOTS + 5) := x"4116497554C380C50BC7A489DE9E681021D3BE54BFCBCF64FC013F360E34CD13";
        mem(BRAM_XMSS_SIG_WOTS + 6) := x"CD96386E24FA22CAE31B4A1F5938272005BD5400712F4E5AEA3CDD48200876A5";
        mem(BRAM_XMSS_SIG_WOTS + 7) := x"A0FB72F7D79367F78469364BAD593142B597DF6D90EC6482E197EA8B54F9516C";
        mem(BRAM_XMSS_SIG_WOTS + 8) := x"F9703D9AC7741BB3A7B3E61097D606225A3071C1ED25053758D0C16E838640B7";
        mem(BRAM_XMSS_SIG_WOTS + 9) := x"BBDBA06FEFBAF0E40C94EE36C7DD8810A374027326E8007E60A4D39AC4BBB57E";
        mem(BRAM_XMSS_SIG_WOTS + 10) := x"5DEC4BD82021240971575B3C119F1DDB2391BEE2D6534C95A27A7992EE777F77";
        mem(BRAM_XMSS_SIG_WOTS + 11) := x"5CFA313D3FD800DC469032100C3C8C19ADBB44FF8922B7F9C441FAC8E063FB0F";
        mem(BRAM_XMSS_SIG_WOTS + 12) := x"674D2307E31DA0B010B8F0B374C28A5BF583F0DCD90DC7CB42D91FB9CDCA4291";
        mem(BRAM_XMSS_SIG_WOTS + 13) := x"05C264DD04A433B764FB2BA559F68AE9D5B4279701D561F674FB6E152C14E8E3";
        mem(BRAM_XMSS_SIG_WOTS + 14) := x"30D828A66D1332E264129BC8DC81AC663A655C7DFB926D9859899C25917BCA53";
        mem(BRAM_XMSS_SIG_WOTS + 15) := x"18CE1E6FEF081836C91A6F4A804CD60A130F01BB84AE6DC88911D47690D250FC";
        mem(BRAM_XMSS_SIG_WOTS + 16) := x"F2A6A711FCC16A9930F054F248999F721013CE0F521A6A91EC384F5456FBE81B";
        mem(BRAM_XMSS_SIG_WOTS + 17) := x"B59D4F27A0ED98077E61C09F9DF1E1314C250D8E929F65595BD00D963CF99B7E";
        mem(BRAM_XMSS_SIG_WOTS + 18) := x"C18633508F012A95956F22132337C2087383DF37913576EF8100A913E613D5AE";
        mem(BRAM_XMSS_SIG_WOTS + 19) := x"6BC39F177724FB0D84E84AF9E602999B7232849AC47B66CC53B8F714F387C1E2";
        mem(BRAM_XMSS_SIG_WOTS + 20) := x"4247D7498405C7CBD7F6CDF81BB8F7EC637CAB8F376DAA7B508CE7399B04EA68";
        mem(BRAM_XMSS_SIG_WOTS + 21) := x"0B4D78EDDEE8BBB1AF3C70B9D24F14486D6D04B3CC2D84F7BA58F2B4A292637C";
        mem(BRAM_XMSS_SIG_WOTS + 22) := x"68C6FB44AECA3B8A27360D982949BF8C11741EA61255F86D41AC98D63F1F3A98";
        mem(BRAM_XMSS_SIG_WOTS + 23) := x"328B7124C982876CCF77CFDB424B886905D1932A86CD805A968A945496F43BD2";
        mem(BRAM_XMSS_SIG_WOTS + 24) := x"29F3B0FA38F5182A526D258A8185F786385FFD22A6EA0882E3EEF12D202862B2";
        mem(BRAM_XMSS_SIG_WOTS + 25) := x"739CBD1F1A8A6490C3AC9597C27F11BDBFA0FB27666A51D35C4BBE1F066CA0BA";
        mem(BRAM_XMSS_SIG_WOTS + 26) := x"AC8AA33E0A7AE23547FE9051D2E6000E0C45996699157D07F9623CFD575FC773";
        mem(BRAM_XMSS_SIG_WOTS + 27) := x"165FD46714722CCDA9CAA1689144C0337333E23272F63D02EBD51913135DB555";
        mem(BRAM_XMSS_SIG_WOTS + 28) := x"83D39DDB82758B675883178205FE814DA99605F45E5F774F907B05CB52208F05";
        mem(BRAM_XMSS_SIG_WOTS + 29) := x"F3F6BCD8E318D464C9ACDC211B0A5AA81A3D161E0F54C290C993CC76EF44B9D8";
        mem(BRAM_XMSS_SIG_WOTS + 30) := x"E62F624D340E3CEDF1B4B1D6E44D9D8E44EE2AE1E9E8C910CC04FC7740BFC7DC";
        mem(BRAM_XMSS_SIG_WOTS + 31) := x"8BDE6BF851F8C0E89244D0A7767826111939D303563CDC66284672337DD0D9B4";
        mem(BRAM_XMSS_SIG_WOTS + 32) := x"9A3462420E30C8796D5BF54F8C90E661BE37449CABFC1C6F258E45E33E8E154A";
        mem(BRAM_XMSS_SIG_WOTS + 33) := x"78FE3CAEB51BDF5D17DCD0B5F30606DEF8A9D25C7DDDC73A536F3C160726DF2E";
        mem(BRAM_XMSS_SIG_WOTS + 34) := x"EBC66EE47B4D52CFFFBC379C50D9D423D0EB2D2749471801D13FD222D2CFC408";
        mem(BRAM_XMSS_SIG_WOTS + 35) := x"413867564928D8602B5CCCD9BD28CAE6D56FD94E0D9ABBD2CC3C2EBECC79B8BA";
        mem(BRAM_XMSS_SIG_WOTS + 36) := x"BDB6CDAF357BB40663E198F6259EDA1D85B4E532032222D0AD3B0E004FC88BB0";
        mem(BRAM_XMSS_SIG_WOTS + 37) := x"E2D27CE808E42EBBA4F8A02E9F02622AEC379F92D6B9C370410C00887469E5EB";
        mem(BRAM_XMSS_SIG_WOTS + 38) := x"72CFDBA10852C6C8046D7A8E7D2366A1BCF8F68BFBFF7D2D63C82B691AF51B3C";
        mem(BRAM_XMSS_SIG_WOTS + 39) := x"B4A37AE6886E0D576FDD2C4FD24AA0012016B047AAF8B2675AC9EA9968499049";
        mem(BRAM_XMSS_SIG_WOTS + 40) := x"34FF872A05FDCBDD76FA1158C3A12D40B85116776462D94D45922C9065E40AA0";
        mem(BRAM_XMSS_SIG_WOTS + 41) := x"BA03E685F8692A3125D6A9DA10DA923B600C7E134BB0082C60EB249CA1DF3520";
        mem(BRAM_XMSS_SIG_WOTS + 42) := x"2F372287CDEE0474F45540E498556D956539267E73FA4857627D8601D9014B03";
        mem(BRAM_XMSS_SIG_WOTS + 43) := x"2C57BA6947CAD0F1F61D01F2239BDAE40930C6230658B2B47E8873EFC4941F3B";
        mem(BRAM_XMSS_SIG_WOTS + 44) := x"2C044CBAA2A88CD0AE5522DC8808A3F19E040D36DA97DEB89CA4EB2850B4F3B8";
        mem(BRAM_XMSS_SIG_WOTS + 45) := x"94835256069B66C10BAC25F8DA9367F3A814B6A4875921F113C04158214A8EEC";
        mem(BRAM_XMSS_SIG_WOTS + 46) := x"6263A640E115BFDBC1B6E4144BC664B22674E4DC46B0AFC7C6217A01B4895534";
        mem(BRAM_XMSS_SIG_WOTS + 47) := x"BF5097650EBBB0D5430B2F99B3F221AC5A3CDD28906FB7659114832FD7BA54D0";
        mem(BRAM_XMSS_SIG_WOTS + 48) := x"3F5717963DA8ACC5D159998B07544C9D97520A460149ED7AF77D12A6C4E27AC7";
        mem(BRAM_XMSS_SIG_WOTS + 49) := x"C87650FB85D8F169D72138078C1D9C11F66BDCC30B84E74830408A52047462DF";
        mem(BRAM_XMSS_SIG_WOTS + 50) := x"3A45081DBB95B56CD5CE8393C0BA02CAFCD59176C1A273F441D341725CCA46F6";
        mem(BRAM_XMSS_SIG_WOTS + 51) := x"0FCCD8721262B33A53A226F7F23B4740D3D0F0C9FAEB9418FAA176484481C27D";
        mem(BRAM_XMSS_SIG_WOTS + 52) := x"D1E04FDDA9B5896BDCE9FFE5B87C21D244F85C5A213FAD80785E12E127592E32";
        mem(BRAM_XMSS_SIG_WOTS + 53) := x"86701578043AB297BF3F2AACE24CAF6D3A6CB4D11207B96C1619A1A7FADBC905";
        mem(BRAM_XMSS_SIG_WOTS + 54) := x"D898F02F616AC1E4A5FF6A4C3C8203262604E888E712C1F0A7A2EC082A721B96";
        mem(BRAM_XMSS_SIG_WOTS + 55) := x"011A6B8C635F8DE898A2B3EF635FF19A08A9230C05A60D7F06CE33384FED0B13";
        mem(BRAM_XMSS_SIG_WOTS + 56) := x"C87A6C07A13B5966C2298A7CB43F39F2155ED209681458F8A4C247ED882A777A";
        mem(BRAM_XMSS_SIG_WOTS + 57) := x"6491DBF1764EF0C66A7414DA2C63B649A5EE6DD796B9A84F6EB6C14D3646CFDF";
        mem(BRAM_XMSS_SIG_WOTS + 58) := x"02701C86187BEFE6875DD2F075F6FE0F3B52CA1B71760AA42DB8C3E4A6DE78B5";
        mem(BRAM_XMSS_SIG_WOTS + 59) := x"1F8DDC56394704BE0DBBA46C959F8BC8E7A48F1ACE28821BEBEC524AE6BBFDDB";
        mem(BRAM_XMSS_SIG_WOTS + 60) := x"08C838B3F09A93837DFD9DE664A9FB73541720ABA8A8F76B03A56A78E9FA0696";
        mem(BRAM_XMSS_SIG_WOTS + 61) := x"B658BEB8FFD0783CC35BCB4FF9BA951CF74CA65D6B1C0AA433735C99CE45A6D9";
        mem(BRAM_XMSS_SIG_WOTS + 62) := x"C015E5AB71D61C605383521F0ABB37DD66BEA650685E53EDB533EA1E2D12C807";
        mem(BRAM_XMSS_SIG_WOTS + 63) := x"8B2AE0EA0260A1C456A18F157CB6C942193E09EC7C242716CA575EE8496965B0";
        mem(BRAM_XMSS_SIG_WOTS + 64) := x"7AEFC58455C0CC28C27FFAEE3ED2511A947F08B1219F87BB87801FED8EC57AA7";
        mem(BRAM_XMSS_SIG_WOTS + 65) := x"CE440979B66D9F2CCBF601BF5C9B7D3ECBA785BBDF8FCF47BF20B3FA8C289E92";
        mem(BRAM_XMSS_SIG_WOTS + 66) := x"BD33C36FFADFB5001399C653194F32D5224944B820A783D576B7359E02C04358";
        
        -- AUTH PATH (10 Bloques)
        mem(BRAM_XMSS_SIG_AUTH + 0) := x"37B49DCB62EB3AD663A4571DDBCF4579AFB5945411E5D09615BA034B5C25C192";
        mem(BRAM_XMSS_SIG_AUTH + 1) := x"8619FA5BB10D6C7059165C99FBC1DF7669D00A5D80FA8AA14C7EE7137E0C00A9";
        mem(BRAM_XMSS_SIG_AUTH + 2) := x"2B2C207FF650B6816D8E9AAAC5FD1F8A75D72950BAE297017B40EFFB8E825EEC";
        mem(BRAM_XMSS_SIG_AUTH + 3) := x"AC13AE0D7195B7586D743BB0F57BD6B55B089477A4BF4160E8FF41ADCEFF1FAE";
        mem(BRAM_XMSS_SIG_AUTH + 4) := x"3E0BF31C7ECAB5EEF01CEE8DC6AB4AA35AD25FFDED1CBBE3A15106AB499737F8";
        mem(BRAM_XMSS_SIG_AUTH + 5) := x"A0A5449EB1D5180AE2467BD97AE99079FE71A9E630E43F991C3D59A1C3717CFE";
        mem(BRAM_XMSS_SIG_AUTH + 6) := x"CAC369788B3B0251EA9A360EC1B8136DC8BF44ABDB95D2FCFA43AABF9AF774CA";
        mem(BRAM_XMSS_SIG_AUTH + 7) := x"B28265702EF4FBDC75E260A07F6F0A40ABE92FFA88A23EFCC4EF0A4BAF011431";
        mem(BRAM_XMSS_SIG_AUTH + 8) := x"15A71C360162ED94F9029C4F2356349D8CCE28C575139DBD00D2142E237CFD0A";
        mem(BRAM_XMSS_SIG_AUTH + 9) := x"9E4F084513B6B12549420F476FF2159CBBA943CE64DC260DA1BA5A47DB3F42A3";

        -- INDICE, R, SEMILLA, ROOT
        mem(BRAM_XMSS_SIG)     := x"0000000000000000000000000000000000000000000000000000000000000000";
        mem(BRAM_XMSS_SIG + 1) := x"83BECF8807135195BC71DE8E314AC7A6ECEE8B5A6FCFF2FDAB00D9494A72968B";
        mem(BRAM_XMSS_SIG + 2) := x"0C3052F5D059043BABFA627EA37C03D49191A2997D0833DA274137EDDEF66168";
        mem(BRAM_XMSS_SIG + 3) := x"A3F3840A84B677379478D1DFE084F8F528F79C0DF72A9E8A937775EBECCF60F8";

        -- MENSAJE
        mem(BRAM_MESSAGE)      := x"4669726D6120544647205648444C000000000000000000000000000000000000";

        return mem;
    end function;

    signal kat_memory : ram_type := get_kat_signature;

begin

    -- Instancia del Wrapper
    uut : entity work.xheep_wrapper
        port map (
            clk         => clk,
            rst_ni      => rst_ni,
            reg_req     => reg_req,
            reg_we      => reg_we,
            reg_addr    => reg_addr,
            reg_wdata   => reg_wdata,
            reg_wstrb   => reg_wstrb,
            reg_gnt     => reg_gnt,
            reg_rvalid  => reg_rvalid,
            reg_rdata   => reg_rdata
        );

    -- Generador de Reloj
    process begin
        clk <= '0'; wait for clk_period / 2;
        clk <= '1'; wait for clk_period / 2;
    end process;

    -- ==============================================================
    -- EL EMULADOR DEL PROCESADOR (El Bootloader C en VHDL)
    -- ==============================================================
    process
        variable read_val : std_logic_vector(31 downto 0);
        variable data_256 : std_logic_vector(255 downto 0);
        variable word_32  : std_logic_vector(31 downto 0);
        variable addr     : unsigned(31 downto 0);
        
        -- Función auxiliar para emular el Little-Endian del bus
        function byte_swap(v: std_logic_vector(31 downto 0)) return std_logic_vector is
        begin
            return v(7 downto 0) & v(15 downto 8) & v(23 downto 16) & v(31 downto 24);
        end function;

        procedure bus_write(addr_in : std_logic_vector(31 downto 0); data_in : std_logic_vector(31 downto 0)) is
        begin
            wait until rising_edge(clk);
            reg_req   <= '1'; reg_we <= '1';
            reg_wstrb <= "1111"; 
            reg_addr  <= addr_in; reg_wdata <= data_in;
            
            wait until rising_edge(clk);
            reg_req   <= '0'; reg_we <= '0';
            reg_wstrb <= "0000"; 
        end procedure;

        procedure bus_read(addr_in : std_logic_vector(31 downto 0)) is
        begin
            wait until rising_edge(clk);
            reg_req  <= '1'; reg_we <= '0'; reg_addr <= addr_in;
            
            -- Puesto que el wrapper tiene lectura combinacional con latencia 0,
            -- reg_rdata será válido en este mismo instante (antes del siguiente flanco).
            -- Por lo tanto, capturamos en el siguiente flanco y bajamos la petición.
            wait until rising_edge(clk);
            read_val := reg_rdata;
            reg_req  <= '0'; 
        end procedure;

        -- Macro para inyectar una fila entera de 256 bits simulando un memcpy
        procedure load_bram_line(index : integer) is
        begin
            data_256 := kat_memory(index);
            addr := x"00002000" + to_unsigned(index * 32, 32); 
            
            for j in 0 to 7 loop
                word_32 := byte_swap(data_256(255 - j*32 downto 224 - j*32));
                bus_write(std_logic_vector(addr + to_unsigned(j * 4, 32)), word_32);
            end loop;
        end procedure;

    begin
        -- Secuencia de Boot
        rst_ni <= '0';
        wait for 10 * clk_period;
        wait until rising_edge(clk);
        rst_ni <= '1';
        wait for 10 * clk_period;

        report "=======================================================" severity note;
        report "=== INICIANDO INYECCION DE FIRMA COMPLETA XMSS      ===" severity note;
        report "=======================================================" severity note;

        -- 1. Escribir MLEN
        bus_write(x"00000008", std_logic_vector(to_unsigned(112, 32)));

        -- 2. Inyectar Root (Index 0)
        load_bram_line(0);
        
        -- 3. Inyectar WOTS Signature (Index 68 a 134)
        for i in 68 to 134 loop
            load_bram_line(i);
        end loop;
        
        -- 4. Inyectar Auth Path (Index 135 a 144)
        for i in 135 to 144 loop
            load_bram_line(i);
        end loop;
        
        -- 5. Inyectar Index, Randomness, Pub_Seed, Expected Root, Message (145 a 149)
        for i in 145 to 149 loop
            load_bram_line(i);
        end loop;

        report "-> [OK] Memoria cargada. Transmitidas " & integer'image((1 + 67 + 10 + 5) * 8) & " palabras de 32 bits." severity note;

        -- 6. Disparar el acelerador
        report "-> Arrancando acelerador de hardware..." severity note;
        bus_write(x"00000000", x"00000001");

        -- 7. Polling (Esperar a que termine)
        loop
            bus_read(x"00000004");
            exit when read_val(16) = '1';
            wait for 200 * clk_period; 
        end loop;

        -- 8. Validar el resultado
        report "=======================================================" severity note;
        if read_val(15 downto 0) = x"3C5A" then
            report "=== [PASS] FIRMA VALIDA Y VERIFICADA EN EL WRAPPER  ===" severity note;
        else
            -- NOTA: to_hstring requiere VHDL-2008. Si da error al compilar, cámbialo por un report con integer'image como tenías antes.
            report "=== [FAIL] FIRMA RECHAZADA. CODIGO: " & to_hstring(read_val(15 downto 0)) severity error;
        end if;
        report "=======================================================" severity note;

        -- 9. Auto-clear y fin
        bus_write(x"00000000", x"00000000");
        
        report "### SIMULACION FINALIZADA ###" severity note;
        wait;
    end process;

end Behavioral;