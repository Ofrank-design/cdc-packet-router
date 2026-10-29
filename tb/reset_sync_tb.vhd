-- reset_sync_tb.vhd
-- Reset must assert the instant arst_n drops, and must release only on a
-- clock edge, two edges after arst_n rises, whatever phase the release lands
-- on. Re-asserting mid-cycle must also be immediate.
--
-- Author: Frank Oduro <frankoduro1912@gmail.com>

library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity reset_sync_tb is
end entity reset_sync_tb;

architecture sim of reset_sync_tb is

    constant CLK_P : time := 5 ns;

    signal clk    : std_logic := '0';
    signal arst_n : std_logic := '0';
    signal srst_n : std_logic;

begin

    clk <= not clk after CLK_P / 2;

    dut : entity work.reset_sync
        generic map (STAGES => 2)
        port map (clk => clk, arst_n => arst_n, srst_n => srst_n);

    stim : process
        variable t_rel, lat : time;
    begin
        wait for 12.3 ns;
        assert srst_n = '0' report "reset must be asserted from power-up" severity failure;

        for k in 0 to 9 loop
            wait until rising_edge(clk);
            wait for k * 500 ps + 250 ps;
            t_rel  := now;
            arst_n <= '1';
            wait for 100 ps;
            assert srst_n = '0' report "release must not be immediate" severity failure;

            wait until srst_n = '1' for 30 ns;
            assert srst_n = '1' report "reset never released" severity failure;
            lat := now - t_rel;
            assert lat > CLK_P and lat <= 2 * CLK_P
                report "release latency out of range: " & time'image(lat) severity failure;

            wait for 3 ns;
            arst_n <= '0';
            wait for 100 ps;
            assert srst_n = '0' report "re-assertion must be immediate" severity failure;
            wait for 12 ns;
            assert srst_n = '0' report "reset must hold while arst_n is low" severity failure;
        end loop;

        report "reset_sync_tb PASS";
        finish;
    end process;

end architecture sim;
