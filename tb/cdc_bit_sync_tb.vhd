-- cdc_bit_sync_tb.vhd
-- Walks the synchronizer input across ten different phases of the 200 MHz
-- destination clock and checks:
--   * levels propagate, with a latency between one and two destination periods
--   * a pulse shorter than the destination period is sometimes missed - this
--     is the documented limit of the part, and the test makes sure we are
--     really exercising it - and when it IS caught it comes out one period wide
--   * reset clears the output immediately and release takes two clock edges
--
-- RTL simulation cannot model real metastability. This proves the protocol,
-- not the analog behaviour; CDC lint and timing reports cover the rest.
--
-- Author: Frank Oduro <frankoduro1912@gmail.com>

library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity cdc_bit_sync_tb is
end entity cdc_bit_sync_tb;

architecture sim of cdc_bit_sync_tb is

    constant CLK_P : time := 5 ns;

    signal clk   : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal din   : std_logic := '0';
    signal dout  : std_logic;

    signal rise_cnt   : natural := 0;
    signal last_width : time    := 0 ns;

begin

    clk <= not clk after CLK_P / 2;

    dut : entity work.cdc_bit_sync
        port map (dst_clk => clk, dst_rst_n => rst_n, async_in => din, sync_out => dout);

    monitor : process (dout)
        variable t_rise : time := 0 ns;
    begin
        if rising_edge(dout) then
            t_rise   := now;
            rise_cnt <= rise_cnt + 1;
        elsif falling_edge(dout) then
            last_width <= now - t_rise;
        end if;
    end process;

    stim : process
        variable t0, lat : time;
        variable before  : natural;
        variable caught  : natural := 0;
    begin
        wait for 23 ns;
        rst_n <= '1';
        wait for 40 ns;
        assert dout = '0' report "output should idle low" severity failure;

        -- levels, ten phases across the destination period
        for k in 0 to 9 loop
            wait until rising_edge(clk);
            wait for k * 500 ps + 250 ps;
            t0 := now;
            din <= '1';
            wait until dout = '1' for 30 ns;
            lat := now - t0;
            assert dout = '1' report "rising level never arrived" severity failure;
            assert lat > CLK_P and lat <= 2 * CLK_P
                report "rising latency out of range: " & time'image(lat) severity failure;
            wait for 20 ns;

            wait until rising_edge(clk);
            wait for k * 500 ps + 250 ps;
            t0 := now;
            din <= '0';
            wait until dout = '0' for 30 ns;
            lat := now - t0;
            assert dout = '0' report "falling level never arrived" severity failure;
            assert lat > CLK_P and lat <= 2 * CLK_P
                report "falling latency out of range: " & time'image(lat) severity failure;
            wait for 20 ns;
        end loop;

        -- 1 ns pulses (shorter than the 5 ns destination period)
        for k in 0 to 9 loop
            wait until rising_edge(clk);
            wait for k * 500 ps + 250 ps;
            before := rise_cnt;
            din <= '1';
            wait for 1 ns;
            din <= '0';
            wait for 30 ns;
            assert rise_cnt - before <= 1
                report "one pulse produced more than one output pulse" severity failure;
            if rise_cnt - before = 1 then
                caught := caught + 1;
                assert last_width = CLK_P
                    report "caught pulse should be exactly one period wide" severity failure;
            end if;
        end loop;
        report "short pulses caught: " & integer'image(caught) & " of 10";
        assert caught > 0 and caught < 10
            report "expected some, but not all, short pulses to be caught" severity failure;

        -- reset while the output is high
        din <= '1';
        wait for 40 ns;
        assert dout = '1' report "level should be high before reset test" severity failure;
        wait for 1.3 ns;
        rst_n <= '0';
        wait for 1 ns;
        assert dout = '0' report "reset must clear the output at once" severity failure;
        wait for 20 ns;
        assert dout = '0' report "output must stay low while reset is held" severity failure;

        wait until rising_edge(clk);
        wait for 1.7 ns;
        rst_n <= '1';
        wait for 500 ps;
        assert dout = '0' report "output must not jump high on reset release" severity failure;
        wait for 4 * CLK_P;
        assert dout = '1' report "input level should reappear after release" severity failure;

        report "cdc_bit_sync_tb PASS";
        finish;
    end process;

end architecture sim;
