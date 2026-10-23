library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity exponentiation_tb is
	generic (
		C_block_size : integer := 256
	);
end exponentiation_tb;


architecture expBehave of exponentiation_tb is

	signal message 		: STD_LOGIC_VECTOR ( C_block_size-1 downto 0 ) := (others => '0');
	signal key 			: STD_LOGIC_VECTOR ( C_block_size-1 downto 0 ) := (others => '0');
	signal valid_in 	: STD_LOGIC := '0';
	signal ready_in 	: STD_LOGIC;
	signal ready_out 	: STD_LOGIC := '0';
	signal valid_out 	: STD_LOGIC;
	signal result 		: STD_LOGIC_VECTOR(C_block_size-1 downto 0);
	signal modulus 		: STD_LOGIC_VECTOR(C_block_size-1 downto 0) := (others => '0');
	signal clk 			: STD_LOGIC := '0';
	signal reset_n 		: STD_LOGIC := '0';

	constant CLK_PERIOD : time := 10 ns;  -- 100 MHz

	-- Helper: small integer -> 256-bit vector
	function to_vec(x : natural) return std_logic_vector is
	begin
		return std_logic_vector(to_unsigned(x, C_block_size));
	end function;

	-- 256-bit test key (generated in Python: n = p*q, e = 65537, d = e^-1 mod phi)
	constant N_256 : std_logic_vector(255 downto 0) := x"a4e136a4f5198b9a3d5004a24fe05f06769c841aedbf8a47e3c7c9bc4d17df35";
	constant E_256 : std_logic_vector(255 downto 0) := x"0000000000000000000000000000000000000000000000000000000000010001";
	constant D_256 : std_logic_vector(255 downto 0) := x"6531b09717b341023e454142d9616d100ef62f03ed76bd661efc6025aebe8835";
	constant M_256 : std_logic_vector(255 downto 0) := x"736a947a843fdda7b1eedaffcc3d5506a17a4340f9c08feffa1b1bf13879399b";
	constant C_256 : std_logic_vector(255 downto 0) := x"8ac7956d0fe9c682a8764eed0a199a12bce8e4af768937be8e7c9d97cb98675c";

	signal errors : natural := 0;

begin
	i_exponentiation : entity work.exponentiation
		generic map (
			C_block_size => C_block_size
		)
		port map (
			message   => message  ,
			key       => key      ,
			valid_in  => valid_in ,
			ready_in  => ready_in ,
			ready_out => ready_out,
			valid_out => valid_out,
			result    => result   ,
			modulus   => modulus  ,
			clk       => clk      ,
			reset_n   => reset_n
		);

	clk <= not clk after CLK_PERIOD / 2;

	stimulus : process

		-- Send one message, wait for the result and compare it to the expected value.
		-- stall_cycles: how long to hold ready_out low after the result appears,
		-- to check that the core keeps the result stable until it is accepted.
		procedure run_test(
			name         : string;
			msg, e, n    : std_logic_vector(C_block_size-1 downto 0);
			expected     : std_logic_vector(C_block_size-1 downto 0);
			stall_cycles : natural := 0
		) is
		begin
			-- Present the input and wait until the core accepts it
			wait until rising_edge(clk);
			message  <= msg;
			key      <= e;
			modulus  <= n;
			valid_in <= '1';
			ready_out <= '1' when stall_cycles = 0 else '0';
			wait until rising_edge(clk) and ready_in = '1' for 1 ms;
			valid_in <= '0';
			if ready_in /= '1' then
				report name & ": TIMEOUT, ready_in never went high" severity error;
				errors <= errors + 1;
				ready_out <= '1';
				return;
			end if;

			-- Wait for the result (with a timeout, so a hang doesn't run forever)
			wait until rising_edge(clk) and valid_out = '1' for 5 ms;
			if valid_out /= '1' then
				report name & ": TIMEOUT, valid_out never went high" severity error;
				errors <= errors + 1;
				return;
			end if;

			-- Optional back-pressure: result must stay valid and unchanged
			for i in 1 to stall_cycles loop
				wait until rising_edge(clk);
				if valid_out /= '1' or result /= expected then
					report name & ": result changed while ready_out was low" severity error;
					errors <= errors + 1;
				end if;
			end loop;
			ready_out <= '1';

			if result = expected then
				report name & ": PASS";
			else
				report name & ": FAIL, got 0x" & to_hstring(result) &
				       ", expected 0x" & to_hstring(expected) severity error;
				errors <= errors + 1;
			end if;
			wait until rising_edge(clk);
		end procedure;

	begin
		-- Reset
		reset_n <= '0';
		wait for 5 * CLK_PERIOD;
		reset_n <= '1';
		wait for 2 * CLK_PERIOD;

		-- Small numbers from the Python model: n = 11901, e = 5, d = 3173
		run_test("small encrypt", to_vec(1231),  to_vec(5),    to_vec(11901), to_vec(11614));
		run_test("small decrypt", to_vec(11614), to_vec(3173), to_vec(11901), to_vec(1231));

		-- Full 256-bit key
		run_test("256-bit encrypt", M_256, E_256, N_256, C_256, stall_cycles => 10);
		run_test("256-bit decrypt", C_256, D_256, N_256, M_256);

		wait for 1 ns;
		if errors = 0 then
			report "ALL TESTS PASSED";
		else
			report integer'image(errors) & " TEST(S) FAILED" severity error;
		end if;
		std.env.finish;
	end process;

end expBehave;