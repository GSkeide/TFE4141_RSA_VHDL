library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity exponentiation is
  generic (
    C_block_size : integer := 256
  );
  port (
    --input control
    valid_in  : in  std_logic;
    ready_in  : out std_logic;

    --input data
    message   : in  std_logic_vector(C_block_size-1 downto 0);
    key       : in  std_logic_vector(C_block_size-1 downto 0);

    --output control
    ready_out : in  std_logic;
    valid_out : out std_logic;

    --output data
    result    : out std_logic_vector(C_block_size-1 downto 0);

    --modulus
    modulus   : in  std_logic_vector(C_block_size-1 downto 0);

    --utility
    clk       : in  std_logic;
    reset_n   : in  std_logic
  );
end exponentiation;

architecture Behavioral of exponentiation is
  -- R = 1 << C_block_size  (Montgomery radix, needs C_block_size+1 bits)
  constant R : unsigned(C_block_size downto 0) := shift_left(to_unsigned(1, C_block_size+1), C_block_size);

  type state_t is (IDLE, MONT_SUB, MONT_SEL, LOOP_START, LOOP_WAIT, LAST_START, LAST_WAIT, FINISH);
  signal state, next_state : state_t;

  signal count : integer range 0 to C_block_size-1;

  signal c_init    : std_logic_vector(C_block_size-1 downto 0);
  signal p_reg     : unsigned(C_block_size-1 downto 0);
  signal c_reg     : unsigned(C_block_size-1 downto 0);
  signal n_reg     : unsigned(C_block_size-1 downto 0);
  signal key_e_reg : unsigned(C_block_size-1 downto 0);
    -- mont_sub/sel
  signal p2_reg   : unsigned(C_block_size downto 0);     -- 2P
  signal diff_reg : unsigned(C_block_size+1 downto 0);   -- 2P - n, with borrow bit


  -- slv copies for the multiplier port maps
  signal p_slv : std_logic_vector(C_block_size-1 downto 0);
  signal c_slv : std_logic_vector(C_block_size-1 downto 0);
  signal n_slv : std_logic_vector(C_block_size-1 downto 0);

  -- multiplier control/data
  signal start_c, done_c : std_logic;
  signal start_p, done_p : std_logic;
  signal b_c   : std_logic_vector(C_block_size-1 downto 0);
  signal res_c : std_logic_vector(C_block_size-1 downto 0);
  signal res_p : std_logic_vector(C_block_size-1 downto 0);
begin

  -- C = R - n   (1 in Montgomery representation)
  c_init <= std_logic_vector(resize(R - unsigned(modulus), C_block_size));

  p_slv <= std_logic_vector(p_reg);
  c_slv <= std_logic_vector(c_reg);
  n_slv <= std_logic_vector(n_reg);
  -- handshakes
  ready_in  <= '1' when state = IDLE   else '0';
  valid_out <= '1' when state = FINISH else '0';

  -- one-cycle start pulses (each *_START state lasts exactly one cycle)
  start_c <= '1' when state = LOOP_START or state = LAST_START else '0';
  start_p <= '1' when state = LOOP_START else '0';

  -- b input of mult_c: P inside the loop, 1 for the final conversion
  b_c <= std_logic_vector(to_unsigned(1, C_block_size)) when state = LAST_START else p_slv;
  -- let's us use one c_mult instead of 2

  -- C = mont(C, P, n)   and at the end   mont(C, 1, n)
  mult_c : entity work.montgomery_mult
    generic map (K => C_block_size)
    port map (
      clk    => clk,
      rstn   => reset_n,
      start  => start_c,
      done   => done_c,
      a      => c_slv,
      b      => b_c,
      n      => n_slv,
      result => res_c
    );

  -- P = mont(P, P, n)
  mult_p : entity work.montgomery_mult
    generic map (K => C_block_size)
    port map (
      clk    => clk,
      rstn   => reset_n,
      start  => start_p,
      done   => done_p,
      a      => p_slv,
      b      => p_slv,
      n      => n_slv,
      result => res_p
    );

  -- State register
  state_reg : process(clk, reset_n)
  begin
    if reset_n = '0' then
      state <= IDLE;
    elsif rising_edge(clk) then
      state <= next_state;
    end if;
  end process state_reg;

  -- Next-state logic (combinational)
  fsm_logic : process(state, valid_in, ready_out, count, done_c, done_p)
  begin
    next_state <= state;

    case state is
      when IDLE =>
        if valid_in = '1' then
          next_state <= MONT_SUB;
        end if;

      when MONT_SUB =>
        next_state <= MONT_SEL;

      when MONT_SEL =>
        if count = C_block_size-1 then
          next_state <= LOOP_START;
        else
          next_state <= MONT_SUB;
        end if;

      when LOOP_START =>
        next_state <= LOOP_WAIT;

      when LOOP_WAIT =>
        -- both multipliers have the same latency, so they finish together
        if done_p = '1' then
          if count = C_block_size-1 then
            next_state <= LAST_START;
          else
            next_state <= LOOP_START;
          end if;
        end if;

      when LAST_START =>
        next_state <= LAST_WAIT;

      when LAST_WAIT =>
        if done_c = '1' then
          next_state <= FINISH;
        end if;

      when FINISH =>
        if ready_out = '1' then
          next_state <= IDLE;
        end if;

      when others =>
        next_state <= IDLE;
    end case;
  end process fsm_logic;

  -- Datapath
  datapath : process(clk, reset_n)
  begin
    if reset_n = '0' then
      p_reg     <= (others => '0');
      c_reg     <= (others => '0');
      n_reg     <= (others => '0');
      key_e_reg <= (others => '0');
      result    <= (others => '0');
      count     <= 0;
    elsif rising_edge(clk) then
      case state is
        when IDLE =>
          if valid_in = '1' then
            p_reg     <= unsigned(message);
            n_reg     <= unsigned(modulus);
            key_e_reg <= unsigned(key);
            c_reg     <= unsigned(c_init);
            count     <= 0;
          end if;

        when MONT_SUB =>  -- compute 2P and 2P - n
          p2_reg   <= p_reg & '0';
          diff_reg <= resize(p_reg & '0', C_block_size+2) - resize(n_reg, C_block_size+2);

        when MONT_SEL =>  -- pick result based on the borrow bit
          if diff_reg(C_block_size+1) = '0' then     -- non-negative, so 2P >= n
            p_reg <= diff_reg(C_block_size-1 downto 0);
          else
            p_reg <= p2_reg(C_block_size-1 downto 0);
          end if;

          if count = C_block_size-1 then
            count <= 0;
          else
            count <= count + 1;
          end if;

        when LOOP_START =>
          null;  -- multipliers capture C and P this cycle

        when LOOP_WAIT =>
          if done_p = '1' then
            if key_e_reg(0) = '1' then
              c_reg <= unsigned(res_c);                   -- C = mont(C, P, n)
            end if;
            p_reg     <= unsigned(res_p);                 -- P = mont(P, P, n)
            key_e_reg <= shift_right(key_e_reg, 1);

            if count = C_block_size-1 then
              count <= 0;
            else
              count <= count + 1;
            end if;
          end if;

        when LAST_START =>
          null;  -- mult_c captures C and 1 this cycle

        when LAST_WAIT =>
          if done_c = '1' then
            result <= res_c;                              -- mont(C, 1, n)
          end if;

        when FINISH =>
          null;

        when others =>
          null;
      end case;
    end if;
  end process datapath;

end architecture Behavioral;