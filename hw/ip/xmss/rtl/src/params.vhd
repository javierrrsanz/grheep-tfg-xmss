library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package params is
   
   constant HASH_CORES : Integer := 4; 
   constant HASH_CHAINS: Integer := 4;
   constant HASH_FUNCTION : STRING := "SHA"; 

   constant n               : Integer := 32;
   constant wots_w          : Integer := 16;
   constant wots_log_w      : Integer := 4;
   constant wots_len1       : Integer := 64;
   constant wots_len2       : Integer := 3;
   constant wots_len        : Integer := wots_len1 + wots_len2;
   constant wots_len_log    : Integer := 7;
   constant tree_height     : Integer := 10;
   constant ID_CTR_LEN : Integer := wots_len_log;

   -- BRAM Sections (Optimizado para Verify-Only)
   -- Se eliminan las secciones de TreeHash intermedio y Stack usadas solo en firma
   constant BRAM_PK             : integer := 0;
   constant BRAM_WOTS_KEY       : integer := BRAM_PK + 1;
   constant BRAM_XMSS_SIG_WOTS  : integer := BRAM_WOTS_KEY + wots_len;
   constant BRAM_XMSS_SIG_AUTH  : integer := BRAM_XMSS_SIG_WOTS + wots_len;
   constant BRAM_XMSS_SIG       : integer := BRAM_XMSS_SIG_AUTH + tree_height;
   constant BRAM_MESSAGE        : integer := BRAM_XMSS_SIG + 4;
   
    constant BRAM_ADDR_SIZE : integer := 8;
    constant MAX_MLEN : integer := 2048;
    -- hash_message antepone 4 palabras de n bytes (R, root, idx, prefix)
    -- por lo que el motor hash puede recibir hasta MAX_MLEN + 4*8*n bits.
    constant MAX_HASH_LEN : integer := MAX_MLEN + 4*8*n;
   
   -- NUEVO: Estados seguros para mitigación FI (Multibit)
   constant STATUS_VALID   : std_logic_vector(15 downto 0) := x"3C5A";
   constant STATUS_INVALID : std_logic_vector(15 downto 0) := x"C3A5";
   constant STATUS_IDLE    : std_logic_vector(15 downto 0) := x"0000";

   type hash_id is record
        block_ctr : unsigned(2 downto 0);
        ctr : unsigned(ID_CTR_LEN-1 downto 0);
   end record;

   -- Restauradas constantes necesarias para xmss_main_typedef
   constant zero_hash_id : hash_id := (others => (others => '0'));
   constant dont_care_hash_id : hash_id := (others => (others => '-'));


   type bram_interface_in is record
       EN           :  STD_LOGIC;
       WEN          :  STD_LOGIC;
       ADDR         :  STD_LOGIC_VECTOR(BRAM_ADDR_SIZE-1 DOWNTO 0);
       DIN          : STD_LOGIC_VECTOR(n*8-1 DOWNTO 0);
    end record;

   type bram_interface_out is record
	   DOUT          :  STD_LOGIC_VECTOR(n*8-1 DOWNTO 0);
   end record;
    
    type dual_port_bram_in is record
        a : bram_interface_in;
        b : bram_interface_in;
    end record;
    
    type dual_port_bram_out is record
        a : bram_interface_out;
        b : bram_interface_out;
    end record;
    
     constant bram_zero : bram_interface_in := (
        en => '0',
        wen => '0',
        addr => (others => '-'),
        din => (others => '-')
     );

     constant dual_bram_zero : dual_port_bram_in :=(
        a=> bram_zero,
        b=> bram_zero);
	
end package;