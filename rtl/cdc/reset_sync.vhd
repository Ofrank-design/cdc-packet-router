-- reset_sync.vhd
-- Reset goes in asynchronously, comes out synchronously.
--
-- Asserting reset needs no clock, so it hits immediately. Releasing it is
-- the dangerous part: if the release lands near a clock edge, flops can
-- go metastable. So the release walks through a short shift register
-- clocked by the domain it is resetting.
--
-- Author: Frank Oduro <frankoduro1912@gmail.com>

library ieee;
use ieee.std_logic_1164.all;

entity reset_sync is
    generic (
        STAGES : positive := 2
    );
    port (
        clk     : in  std_logic;
        arst_n  : in  std_logic;   -- asynchronous, active low
        srst_n  : out std_logic    -- asserts at once, releases on clk
    );
end entity reset_sync;

architecture rtl of reset_sync is

    signal pipe : std_logic_vector(STAGES - 1 downto 0) := (others => '0');

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of pipe : signal is "TRUE";

begin

    process (clk, arst_n)
    begin
        if arst_n = '0' then
            pipe <= (others => '0');
        elsif rising_edge(clk) then
            if STAGES = 1 then
                pipe(0) <= '1';
            else
                pipe <= pipe(STAGES - 2 downto 0) & '1';
            end if;
        end if;
    end process;

    srst_n <= pipe(STAGES - 1);

end architecture rtl;
