-- cdc_gray_sync.vhd
-- Two-flop synchronizer for a Gray-coded vector.
--
-- This is only safe because a Gray counter that steps by one flips exactly
-- one bit per step: whichever way the destination resolves a bit that is
-- caught mid-change, it sees either the old pointer or the new one, never
-- something in between. Feed it a binary counter and it will bite you.
--
-- Author: Frank Oduro <frankoduro1912@gmail.com>

library ieee;
use ieee.std_logic_1164.all;

entity cdc_gray_sync is
    generic (
        WIDTH : positive := 4
    );
    port (
        dst_clk   : in  std_logic;
        dst_rst_n : in  std_logic;
        gray_in   : in  std_logic_vector(WIDTH - 1 downto 0);
        gray_out  : out std_logic_vector(WIDTH - 1 downto 0)
    );
end entity cdc_gray_sync;

architecture rtl of cdc_gray_sync is

    signal ff1 : std_logic_vector(WIDTH - 1 downto 0) := (others => '0');
    signal ff2 : std_logic_vector(WIDTH - 1 downto 0) := (others => '0');

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of ff1 : signal is "TRUE";
    attribute ASYNC_REG of ff2 : signal is "TRUE";

begin

    process (dst_clk, dst_rst_n)
    begin
        if dst_rst_n = '0' then
            ff1 <= (others => '0');
            ff2 <= (others => '0');
        elsif rising_edge(dst_clk) then
            ff1 <= gray_in;
            ff2 <= ff1;
        end if;
    end process;

    gray_out <= ff2;

end architecture rtl;
