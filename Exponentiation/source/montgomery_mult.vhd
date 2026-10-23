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
    result : out std_logic_vector(K-1 downto 0)
  );
end entity;

architecture rtl of montgomery_mult is
  type state_t is (IDLE, FIRST, SECOND, FIN_SUB, FIN_SEL);
  signal state, next_state : state_t;

  signal a_reg : unsigned(K-1 downto 0);
  signal b_reg : unsigned(K-1 downto 0);
  signal n_reg : unsigned(K-1 downto 0);
  signal t_reg : unsigned(K+1 downto 0);   -- K+2 bits: holds the sum before shifting
  signal count : integer range 0 to K-1;
  signal diff_reg : unsigned(K+2 downto 0);   -- t - n, top bit is the borrow
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
  fsm_logic : process(state, start, count)
  begin
    next_state <= state;

    case state is
      when IDLE =>
        if start = '1' then
          next_state <= FIRST;
        end if;

      when FIRST =>
        next_state <= SECOND;

      when SECOND =>
        if count = K-1 then
          next_state <= FIN_SUB;
        else
          next_state <= FIRST;
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
  begin
    if rstn = '0' then
      done <= '0';
    elsif rising_edge(clk) then
      done <= '0';

      case state is
        when IDLE =>
          if start = '1' then
            t_reg <= (others => '0');
            a_reg <= unsigned(a);
            b_reg <= unsigned(b);
            n_reg <= unsigned(n);
            count <= 0;
          end if;

        when FIRST =>   -- runs 256 times          -- if (a >> i) & 1: t += b
          if a_reg(0) = '1' then
            t_reg <= t_reg + b_reg;
          end if;

        when SECOND =>   -- runs 256 times         -- if t & 1: t += n;  t >>= 1
          if t_reg(0) = '1' then
            t_reg <= shift_right(t_reg + n_reg, 1);
          else
            t_reg <= shift_right(t_reg, 1);
          end if;
          a_reg <= shift_right(a_reg, 1); -- shift a for the next if statement
          if count /= K-1 then
            count <= count + 1;
          end if;

          when FIN_SUB =>               -- diff = t - n
          diff_reg <= resize(t_reg, K+3) - resize(n_reg, K+3);
 
        when FIN_SEL =>               -- keep diff if no borrow (t >= n)
          if diff_reg(K+2) = '0' then
            t_reg <= diff_reg(K+1 downto 0);
          end if;
          done <= '1';



        when others =>
          null;
      end case;
    end if;
  end process datapath;

  result <= std_logic_vector(t_reg(K-1 downto 0));

end architecture;