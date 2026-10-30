-- async_fifo_tb.vhd
-- Streams a numbered sequence through the FIFO with the two clocks fully
-- independent: separate periods, separate start phases, separate random
-- stall patterns. A scoreboard checks every word that is actually accepted
-- on the read side against the sequence number it should be, so loss,
-- duplication and reordering all show up as a mismatch.
--
-- The generics let scripts/run_sims.sh sweep clock ratios, phases and
-- traffic pressure. The FIFO is deliberately tiny (8 deep) so it wraps its
-- pointers hundreds of times per run and hits full/empty constantly.
--
-- Both sides also keep rd_en / wr_en high at times when the FIFO cannot
-- take them. The FIFO is supposed to ignore those, and the scoreboard
-- would catch it if it didn't.
--
-- Author: Frank Oduro <frankoduro1912@gmail.com>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_util_pkg.all;

entity async_fifo_tb is
    generic (
        WR_PERIOD_PS : positive := 20000;
        RD_PERIOD_PS : positive := 5000;
        WR_PHASE_PS  : natural  := 7000;
        RD_PHASE_PS  : natural  := 1000;
        WR_PCT       : natural  := 70;     -- % of write cycles that try to write
        RD_PCT       : natural  := 70;     -- % of read cycles that try to read
        NUM_WORDS    : positive := 5000;
        SEED         : positive := 1;
        EXPECT_FULL  : boolean  := false;  -- fail if full never showed up
        EXPECT_EMPTY : boolean  := false   -- fail if empty never came back
    );
end entity async_fifo_tb;

architecture sim of async_fifo_tb is

    constant DATA_W : positive := 16;
    constant ADDR_W : positive := 3;
    constant DEPTH  : natural  := 2 ** ADDR_W;

    signal wr_clk, rd_clk       : std_logic := '0';
    signal ext_rst_n            : std_logic := '0';
    signal wr_rst_n, rd_rst_n   : std_logic;

    signal wr_en, rd_en         : std_logic := '0';
    signal wr_data              : std_logic_vector(DATA_W - 1 downto 0) := (others => '0');
    signal rd_data              : std_logic_vector(DATA_W - 1 downto 0);
    signal full, empty          : std_logic;

    signal sent_s, got_s        : natural := 0;
    signal seen_full            : boolean := false;
    signal seen_empty           : boolean := false;

begin

    ------------------------------------------------------------------
    -- Two unrelated clocks
    ------------------------------------------------------------------
    wr_clk_gen : process
    begin
        wr_clk <= '0';
        wait for WR_PHASE_PS * 1 ps;
        loop
            wr_clk <= '1';
            wait for (WR_PERIOD_PS / 2) * 1 ps;
            wr_clk <= '0';
            wait for (WR_PERIOD_PS - WR_PERIOD_PS / 2) * 1 ps;
        end loop;
    end process;

    rd_clk_gen : process
    begin
        rd_clk <= '0';
        wait for RD_PHASE_PS * 1 ps;
        loop
            rd_clk <= '1';
            wait for (RD_PERIOD_PS / 2) * 1 ps;
            rd_clk <= '0';
            wait for (RD_PERIOD_PS - RD_PERIOD_PS / 2) * 1 ps;
        end loop;
    end process;

    wr_reset : entity work.reset_sync
        port map (clk => wr_clk, arst_n => ext_rst_n, srst_n => wr_rst_n);

    rd_reset : entity work.reset_sync
        port map (clk => rd_clk, arst_n => ext_rst_n, srst_n => rd_rst_n);

    dut : entity work.async_fifo
        generic map (DATA_W => DATA_W, ADDR_W => ADDR_W)
        port map (
            wr_clk => wr_clk, wr_rst_n => wr_rst_n,
            wr_en  => wr_en,  wr_data  => wr_data, full  => full,
            rd_clk => rd_clk, rd_rst_n => rd_rst_n,
            rd_en  => rd_en,  rd_data  => rd_data, empty => empty
        );

    ------------------------------------------------------------------
    -- Writer: counts a word as sent only when wr_en met a non-full FIFO
    ------------------------------------------------------------------
    writer : process (wr_clk)
        variable rng  : unsigned(31 downto 0) := to_unsigned(SEED * 2654435 + 17, 32);
        variable sent : natural := 0;
    begin
        if rising_edge(wr_clk) then
            if wr_rst_n = '0' then
                wr_en <= '0';
            else
                if wr_en = '1' and full = '0' then
                    sent := sent + 1;
                end if;
                sent_s <= sent;

                rng := xorshift32(rng);
                if sent < NUM_WORDS and chance(rng, WR_PCT) then
                    wr_en   <= '1';
                    wr_data <= std_logic_vector(to_unsigned(sent mod 65536, DATA_W));
                else
                    wr_en   <= '0';
                    wr_data <= std_logic_vector(rng(DATA_W - 1 downto 0));  -- junk, must be ignored
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Reader / scoreboard
    ------------------------------------------------------------------
    reader : process (rd_clk)
        variable rng : unsigned(31 downto 0) := to_unsigned(SEED * 40503 + 99, 32);
        variable got : natural := 0;
    begin
        if rising_edge(rd_clk) then
            if rd_rst_n = '0' then
                rd_en <= '0';
            else
                if empty = '1' and got > 0 then
                    seen_empty <= true;
                end if;

                if rd_en = '1' and empty = '0' then
                    assert to_integer(unsigned(rd_data)) = got mod 65536
                        report "scoreboard mismatch at word " & integer'image(got) &
                               ": expected " & integer'image(got mod 65536) &
                               ", read " & integer'image(to_integer(unsigned(rd_data)))
                        severity failure;
                    got := got + 1;
                end if;
                got_s <= got;

                rng := xorshift32(rng);
                if chance(rng, RD_PCT) then
                    rd_en <= '1';
                else
                    rd_en <= '0';
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Invariants and coverage
    ------------------------------------------------------------------
    occupancy : process (sent_s, got_s)
    begin
        assert sent_s >= got_s
            report "read more words than were written" severity failure;
        assert sent_s - got_s <= DEPTH
            report "more words in flight than the FIFO can hold: overwrite" severity failure;
    end process;

    cover_full : process (full)
    begin
        if full = '1' then
            seen_full <= true;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Sequencing
    ------------------------------------------------------------------
    main : process
    begin
        ext_rst_n <= '0';
        wait for 100 ns;
        ext_rst_n <= '1';

        wait until got_s = NUM_WORDS for 50 ms;
        assert got_s = NUM_WORDS
            report "timeout: only " & integer'image(got_s) & " of " &
                   integer'image(NUM_WORDS) & " words arrived"
            severity failure;

        wait for 500 ns;
        assert sent_s = NUM_WORDS report "writer count wrong" severity failure;
        assert empty = '1' report "FIFO should be empty after the drain" severity failure;

        if EXPECT_FULL then
            assert seen_full report "this scenario was meant to hit full and never did" severity failure;
        end if;
        if EXPECT_EMPTY then
            assert seen_empty report "this scenario was meant to starve the reader and never did" severity failure;
        end if;

        -- reset again with the FIFO idle: flags must land in their reset state
        ext_rst_n <= '0';
        wait for 100 ns;
        assert empty = '1' and full = '0' report "bad flags during reset" severity failure;
        ext_rst_n <= '1';
        wait for 300 ns;
        assert empty = '1' and full = '0' report "bad flags after reset release" severity failure;

        report "async_fifo_tb PASS: " & integer'image(NUM_WORDS) & " words, full seen=" &
               boolean'image(seen_full) & ", empty seen=" & boolean'image(seen_empty);
        finish;
    end process;

end architecture sim;
