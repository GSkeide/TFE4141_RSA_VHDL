library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity montgomery_mult is
  generic (
    K : positive := 256
  );
  port (
    clk    : in  std_logic;
    rstn   : in  std_logic;

    -- handshakes
    start  : in  std_logic;
    done   : out std_logic;

    -- data
    a      : in  std_logic_vector(K-1 downto 0);
    b      : in  std_logic_vector(K-1 downto 0);
    n      : in  std_logic_vector(K-1 downto 0);
    key_K  : in  std_logic_vector(8 downto 0);
    result : out std_logic_vector(K-1 downto 0)
  );
end entity;

architecture rtl of montgomery_mult is
  type state_t is (IDLE, ITER, FIN_SUB, FIN_SEL);
  signal state, next_state : state_t;

  signal bn_pending : std_logic;
  signal a_reg : unsigned(K-1 downto 0);
  signal b_reg : unsigned(K-1 downto 0);
  signal n_reg : unsigned(K-1 downto 0);
  signal bn_reg : unsigned(K downto 0);
  signal t_reg : unsigned(K+1 downto 0);
  signal count : integer range 0 to K-1;
  signal diff_reg : unsigned(K+2 downto 0);   -- t - n, top bit is the borrow
  attribute max_fanout : integer;
  attribute max_fanout of a_reg : signal is 32; -- WORKED! Attributed fixed critical path from -0.004 WNS to +0.197 WNS !! (Slack was due to high fanout of a_reg (385 fanouts).
  -- with 0.197 wns.. time to add more RSA cores!
begin


  -- State register
  state_reg : process(clk, rstn)
  begin
    if rstn = '0' then
      state <= IDLE;
    elsif rising_edge(clk) then
      state <= next_state;
    end if;
  end process state_reg;


  -- Next-state logic (combinational)
  fsm_logic : process(state, count, bn_pending)
  begin
    next_state <= state;

    case state is
      when IDLE =>
        if bn_pending = '1' then
          next_state <= ITER;
        end if;

      when ITER =>
        if count = unsigned(key_K)-1 then
          next_state <= FIN_SUB;
        end if;


      when FIN_SUB =>
        next_state <= FIN_SEL;
 
      when FIN_SEL =>
        next_state <= IDLE;


      when others =>
        next_state <= IDLE;
    end case;
  end process fsm_logic;


  -- Datapath
  datapath : process(clk, rstn)
    variable sum_is_odd      : std_logic;
    variable sel    : std_logic_vector(1 downto 0);
    variable addend : unsigned(K+1 downto 0);
  begin
    
    if rstn = '0' then
      done <= '0';
      bn_pending <= '0';
    elsif rising_edge(clk) then
      done <= '0';

      case state is
        when IDLE =>
          if start = '1'  then
            t_reg <= (others => '0');
            a_reg <= unsigned(a);
            b_reg <= unsigned(b);
            n_reg <= unsigned(n);
            bn_pending <= '1'; -- load bn_reg in the next cycle
            count <= 0;
          end if;
          if bn_pending = '1' then -- Would love to use a PREP state for this instead, but that would require a 5th state. When i did that, it wanted 3 bits for the fsm instead of 2 bits, which ended up using 250 LUTs.. with 2 multipliers and 8 cores, that's 4000 LUTs, which ended up failing routing demands and making implementation take an hour..
            bn_reg <= resize(unsigned(b_reg), K+1) + resize(unsigned(n_reg), K+1);
            bn_pending <= '0';
          end if;

        when ITER =>   -- Runs K times
        -- We only add b to t_reg if LSB of a is 1.
        -- Using XOR on the LSB of t_reg and b_reg allow us to "check/predict" if t_reg and b_reg added together would be odd or not without adding the entire numbers.
        -- If t_reg will be odd, we must add n to make it even.
          sum_is_odd   := t_reg(0) xor (a_reg(0) and b_reg(0)); 
        -- sel = If a_i is 1, we want to add b. If the prediction of t + ai*b is odd, we want to add n. If both are true, we want to add b+n. If neither are true, we want to add 0.
          sel := a_reg(0) & sum_is_odd;

          case sel is
            when "00"   => addend := (others => '0');
            when "10"   => addend := resize(b_reg,  K+2);
            when "01"   => addend := resize(n_reg,  K+2);
            when others => addend := resize(bn_reg, K+2);
          end case;

          t_reg <= shift_right(t_reg + addend, 1);
          a_reg <= shift_right(a_reg, 1); -- shift a_reg right to get the next bit of a
          if count /= unsigned(key_K)-1 then
            count <= count + 1;
          end if;

          when FIN_SUB =>               -- diff = t - n
          -- If t > n, diff_reg will be positive and the top bit will be 0.
          -- If t < n, diff_reg will be negative and the top bit will be 1.
          diff_reg <= resize(t_reg, K+3) - resize(n_reg, K+3);
 
        when FIN_SEL =>
          if diff_reg(K+2) = '0' then -- if the subtraction is not negative, we use the subtraction as the final resul
            t_reg <= diff_reg(K+1 downto 0);
          end if;
          done <= '1'; -- t is the final result, we are done. t is within [0, n)



        when others =>
          null;
      end case;
    end if;
  end process datapath;

  result <= std_logic_vector(t_reg(K-1 downto 0)); -- Captured when done is high.

end architecture;