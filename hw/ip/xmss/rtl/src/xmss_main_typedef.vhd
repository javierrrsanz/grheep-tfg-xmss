library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.params.ALL;

package xmss_main_typedef is

	type hash_subsystem_output_type is record
        done : std_logic;
        done_id : hash_id;
        mnext: std_logic;
        o    : std_logic_vector((n*8)-1 downto 0);
        busy, idle : std_logic;
        id : hash_id;
	end record;

    type hash_subsystem_input_type is record
	    id : hash_id;
        enable: std_logic;
      len   : integer range 0 to MAX_HASH_LEN;
        input : std_logic_vector((n*8)-1 downto 0);
    end record;

    constant zero_hash_input : hash_subsystem_input_type := (zero_hash_id, '0', 0,(others => '0'));
    constant dont_care_hash_input : hash_subsystem_input_type := (dont_care_hash_id, '-', 0,(others => '-'));

    type absorb_message_output_type is record
        done : std_logic;
        mnext: std_logic;
        o    : std_logic_vector((n*8)-1 downto 0);
	end record;

    type absorb_message_input_type is record
	    halt  : std_logic;
        enable: std_logic;
      len   : integer range 0 to MAX_HASH_LEN;
        input : std_logic_vector((n*8)-1 downto 0);
    end record;

    constant zero_hash_xmss_child_input : absorb_message_input_type := ('0', '0', 0,(others => '0'));

    --- WOTS
    type wots_input_type_small is record
       enable  : std_logic;
       message : std_logic_vector((n*8)-1 downto 0);
       address_4 : std_logic_vector(31 downto 0);
    end record;

    constant zero_wots_xmss_child_input : wots_input_type_small := ('0', (others => '-'), (others => '-'));

    type wots_input_type is record
       module_input : wots_input_type_small;
       pub_seed: std_logic_vector((n*8)-1 downto 0);
       bram_b : bram_interface_out;
       hash : hash_subsystem_output_type;
    end record;

    type wots_output_type_small is record
       done     : std_logic;
    end record;

    type wots_output_type is record
       module_output : wots_output_type_small;
       hash : hash_subsystem_input_type;
       bram : dual_port_bram_in;
    end record;
    
    --- THASH
    type xmss_thash_h_input_type_small is record
       enable  : std_logic;
       address_3 : std_logic_vector(31 downto 0);
       address_4 : std_logic_vector(31 downto 0);
       address_5 : std_logic_vector(31 downto 0);
       address_6 : std_logic_vector(31 downto 0);
       input_1 : std_logic_vector(8*n-1 downto 0);
       input_2 : std_logic_vector(8*n-1 downto 0);
    end record;

    constant zero_thash_xmss_child_input : xmss_thash_h_input_type_small := ('0', (others => '-'),(others => '-'),(others => '-'),(others => '-'), (others => '-'), (others => '-'));

    type xmss_thash_h_input_type is record
       module_input : xmss_thash_h_input_type_small;
       pub_seed : std_logic_vector(8*n-1 downto 0);
       hash : hash_subsystem_output_type;
    end record;
    
    type xmss_thash_h_output_type_small is record
       done     : std_logic;
       o : std_logic_vector(8*n-1 downto 0);
   	end record;
    
    type xmss_thash_h_output_type is record
       module_output : xmss_thash_h_output_type_small;
       hash : hash_subsystem_input_type;
	end record;
    
    --- LTREE
    type xmss_l_tree_input_type_small is record
       enable  : std_logic;
       address_4 : std_logic_vector(31 downto 0);
    end record;
    constant zero_l_tree_xmss_child_input : xmss_l_tree_input_type_small := ('0', (others => '-'));

    type xmss_l_tree_input_type is record
       module_input : xmss_l_tree_input_type_small;
       bram : dual_port_bram_out;
       thash : xmss_thash_h_output_type_small;
    end record;
    
    type xmss_l_tree_output_type_small is record
       done     : std_logic;
       leaf_node: std_logic_vector((n*8)-1 downto 0);
	end record;
    
    type xmss_l_tree_output_type is record
       module_output : xmss_l_tree_output_type_small;
       bram : dual_port_bram_in;
       thash : xmss_thash_h_input_type_small;
	end record;
	
    --- HASH MESSAGE
	type hash_message_input_type_small is record
       enable  : std_logic;
       index : unsigned(tree_height-1 downto 0);
       mlen : integer range 0 to MAX_MLEN;
    end record;

    constant zero_hash_message_xmss_child_input : hash_message_input_type_small := ('0',(others => '-'), 0);
    
	type hash_message_input_type is record
	   module_input : hash_message_input_type_small;
       hash : hash_subsystem_output_type;
       bram : bram_interface_out;
    end record;
	
	type hash_message_output_type_small is record
       done     : std_logic;
       mhash : std_logic_vector(8*n - 1 downto 0);
	end record;
	
    type hash_message_output_type is record
       module_output : hash_message_output_type_small;
       hash : hash_subsystem_input_type;
       bram : bram_interface_in;
	end record;
	
    --- COMPUTE ROOT
   type xmss_compute_root_input_type is record
       enable  : std_logic;
       leaf : std_logic_vector(n*8-1 downto 0);
       leaf_idx: integer range 0 to 2**tree_height-1;
       bram : bram_interface_out;
       thash: xmss_thash_h_output_type_small;
    end record;

    type xmss_compute_root_output_type is record
       done     : std_logic;
       thash : xmss_thash_h_input_type_small;
       bram : bram_interface_in;
       root : std_logic_vector(8*n-1 downto 0);
	end record;

   --- XMSS VERIFY (TOP LEVEL)
   type xmss_verify_input_type is record
       enable  : std_logic;
       mlen : integer range 0 to MAX_MLEN;
       wots : wots_output_type_small;
       l_tree : xmss_l_tree_output_type_small;
       thash : xmss_thash_h_output_type_small;
       hash_message : hash_message_output_type_small;
       bram : dual_port_bram_out;
    end record;

    type xmss_verify_output_type is record
       done     : std_logic;
       valid    : std_logic_vector(15 downto 0); -- CAMBIADO A MULTIBIT
       mode_select_l1 : unsigned(1 downto 0);
       pub_seed : std_logic_vector(n*8-1 downto 0);
       wots : wots_input_type_small;
       l_tree : xmss_l_tree_input_type_small;
       thash : xmss_thash_h_input_type_small;
       hash_message : hash_message_input_type_small;
       bram : dual_port_bram_in;
	end record;
	
end package;
