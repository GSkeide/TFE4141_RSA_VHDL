--------------------------------------------------------------------------------
-- Author       : Oystein Gjermundnes
-- Organization : Norwegian University of Science and Technology (NTNU)
--                Department of Electronic Systems
--                https://www.ntnu.edu/ies
-- Course       : TFE4141 Design of digital systems 1 (DDS1)
-- Year         : 2018-2019
-- Project      : RSA accelerator
-- License      : This is free and unencumbered software released into the
--                public domain (UNLICENSE)
--------------------------------------------------------------------------------
-- Purpose:
--   RSA encryption core template. This core currently computes
--   C = M xor key_n
--
--   Replace/change this module so that it implements the function
--   C = M**key_e mod key_n.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity rsa_core is
	generic (
		-- Users to add parameters here
		C_BLOCK_SIZE          : integer := 256
	);
	port (
		-----------------------------------------------------------------------------
		-- Clocks and reset
		-----------------------------------------------------------------------------
		clk                    :  in std_logic;
		reset_n                :  in std_logic;

		-----------------------------------------------------------------------------
		-- Slave msgin interface
		-----------------------------------------------------------------------------
		-- Message that will be sent out is valid
		msgin_valid             : in std_logic;
		-- Slave ready to accept a new message
		msgin_ready             : out std_logic;
		-- Message that will be sent out of the rsa_msgin module
		msgin_data              :  in std_logic_vector(C_BLOCK_SIZE-1 downto 0);
		-- Indicates boundary of last packet
		msgin_last              :  in std_logic;

		-----------------------------------------------------------------------------
		-- Master msgout interface
		-----------------------------------------------------------------------------
		-- Message that will be sent out is valid
		msgout_valid            : out std_logic;
		-- Slave ready to accept a new message
		msgout_ready            :  in std_logic;
		-- Message that will be sent out of the rsa_msgin module
		msgout_data             : out std_logic_vector(C_BLOCK_SIZE-1 downto 0);
		-- Indicates boundary of last packet
		msgout_last             : out std_logic;

		-----------------------------------------------------------------------------
		-- Interface to the register block
		-----------------------------------------------------------------------------
		key_e_d                 :  in std_logic_vector(C_BLOCK_SIZE-1 downto 0);
		key_n                   :  in std_logic_vector(C_BLOCK_SIZE-1 downto 0);
                key_C                   :  in std_logic_vector(C_BLOCK_SIZE-1 downto 0);
                key_K                   :  in std_logic_vector(8 downto 0);
		rsa_status              : out std_logic_vector(31 downto 0)

	);
end rsa_core;


architecture rtl of rsa_core is
        constant CORE_COUNT : INTEGER := 8;

        type data_array_t is array (0 to CORE_COUNT-1)
                of std_logic_vector(C_BLOCK_SIZE-1 downto 0);

        -- Per-core handshake and data
        signal core_valid_in  : std_logic_vector(CORE_COUNT-1 downto 0);
        signal core_ready_in  : std_logic_vector(CORE_COUNT-1 downto 0);
        signal core_valid_out : std_logic_vector(CORE_COUNT-1 downto 0);
        signal core_ready_out : std_logic_vector(CORE_COUNT-1 downto 0);
        signal core_result    : data_array_t;
        signal core_last      : std_logic_vector(CORE_COUNT-1 downto 0);  -- 'last' flag per core

        -- Round-robin pointers: next core to receive a message / next core to send its result
        signal in_idx  : integer range 0 to CORE_COUNT-1;
        signal out_idx : integer range 0 to CORE_COUNT-1;

        signal in_ready  : std_logic;
        signal out_valid : std_logic;
begin

        gen_cores : for i in 0 to CORE_COUNT-1 generate
                -- Only the core selected by the pointer sees valid_in / ready_out
                core_valid_in(i)  <= msgin_valid  when in_idx  = i else '0';
                core_ready_out(i) <= msgout_ready when out_idx = i else '0';

                i_exponentiation : entity work.exponentiation
                        generic map (
                                C_block_size => C_BLOCK_SIZE
                        )
                        port map (
                                message   => msgin_data,
                                key       => key_e_d,
                                valid_in  => core_valid_in(i),
                                ready_in  => core_ready_in(i),
                                ready_out => core_ready_out(i),
                                valid_out => core_valid_out(i),
                                result    => core_result(i),
                                modulus   => key_n,
                                key_C     => key_C,
                                key_K     => key_K,
                                clk       => clk,
                                reset_n   => reset_n
                        );
        end generate gen_cores;
        -- input
        in_ready    <= core_ready_in(in_idx);
        msgin_ready <= in_ready;

        -- Output
        out_valid    <= core_valid_out(out_idx);
        msgout_valid <= out_valid;
        msgout_data  <= core_result(out_idx);
        msgout_last  <= core_last(out_idx);

        pointers : process(clk, reset_n)
        begin
                if reset_n = '0' then
                        in_idx    <= 0;
                        out_idx   <= 0;
                        core_last <= (others => '0');
                elsif rising_edge(clk) then
                        
                        if msgin_valid = '1' and in_ready = '1' then
                                core_last(in_idx) <= msgin_last;
                                if in_idx = CORE_COUNT-1 then
                                        in_idx <= 0;
                                else
                                        in_idx <= in_idx + 1;
                                end if;
                        end if;

                        
                        if out_valid = '1' and msgout_ready = '1' then
                                if out_idx = CORE_COUNT-1 then
                                        out_idx <= 0;
                                else
                                        out_idx <= out_idx + 1;
                                end if;
                        end if;
                end if;
        end process pointers;

        rsa_status <= (others => '0');
end rtl;