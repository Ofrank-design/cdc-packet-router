-- packet_router_tb.vhd
-- End-to-end check of the whole router across the two clock domains.
--
-- The source sends packets of 1..6 beats to four output ports. Length and
-- destination are pure functions of the packet id (see tb_util_pkg), so the
-- sink can verify every word it sees without keeping a queue: right port,
-- sop on beat 0, eop on the last beat, payload = {packet id, beat}.
--
-- Non-sop beats carry random garbage on src_dest on purpose. If the router
-- ever trusted that instead of the stamped destination, packets would split
-- across ports and the sink would catch it.
--
-- Also exercised: random per-port backpressure, src_enable dropping for
-- 400 ns every few microseconds (with link_up following it across the
-- clock boundary), and a stray non-sop word at the end, which must be
-- dropped and counted rather than forwarded.
--
-- Not covered here: reset in the middle of traffic. See docs/verification.md.
--
-- Author: Frank Oduro <frankoduro1912@gmail.com>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.router_types_pkg.all;
use work.tb_util_pkg.all;

entity packet_router_tb is
    generic (
        WR_PERIOD_PS : positive := 20000;
        RD_PERIOD_PS : positive := 5000;
        WR_PHASE_PS  : natural  := 3000;
        RD_PHASE_PS  : natural  := 700;
        SRC_PCT      : natural  := 90;
        OUT_PCT      : natural  := 90;
        NUM_PKTS     : positive := 400;
        SEED         : positive := 7;
        EXPECT_FULL  : boolean  := false
    );
end entity packet_router_tb;

architecture sim of packet_router_tb is

    signal wr_clk, rd_clk : std_logic := '0';
    signal rst_n          : std_logic := '0';

    signal src_enable : std_logic := '0';
    signal src_valid  : std_logic := '0';
    signal src_ready  : std_logic;
    signal src_sop    : std_logic := '0';
    signal src_eop    : std_logic := '0';
    signal src_dest   : dest_t    := (others => '0');
    signal src_data   : payload_t := (others => '0');
    signal rx_malformed : unsigned(15 downto 0);
    signal wr_full    : std_logic;

    signal out_valid  : std_logic_vector(NUM_PORTS - 1 downto 0);
    signal out_ready  : std_logic_vector(NUM_PORTS - 1 downto 0) := (others => '0');
    signal out_sop, out_eop : std_logic;
    signal out_dest   : dest_t;
    signal out_data   : payload_t;
    signal rd_empty   : std_logic;
    signal link_up    : std_logic;

    signal inject_stray : std_logic := '0';
    signal rx_pid_s     : natural   := 0;
    signal seen_full    : boolean   := false;
    signal sim_done     : boolean   := false;

begin

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

    dut : entity work.packet_router
        generic map (FIFO_ADDR_W => 3)
        port map (
            wr_clk => wr_clk, rd_clk => rd_clk, rst_n => rst_n,
            src_enable => src_enable, src_valid => src_valid, src_ready => src_ready,
            src_sop => src_sop, src_eop => src_eop, src_dest => src_dest, src_data => src_data,
            rx_malformed => rx_malformed, wr_full => wr_full,
            out_valid => out_valid, out_ready => out_ready,
            out_sop => out_sop, out_eop => out_eop, out_dest => out_dest, out_data => out_data,
            rd_empty => rd_empty, link_up => link_up
        );

    ------------------------------------------------------------------
    -- Source: holds a beat until it is accepted, like any valid/ready master
    ------------------------------------------------------------------
    source : process (wr_clk)
        variable rng          : unsigned(31 downto 0) := to_unsigned(SEED * 2654435 + 1, 32);
        variable pid, beat    : natural := 0;
        variable accepted     : boolean;
        variable cur_stray    : boolean := false;
        variable stray_issued : boolean := false;
    begin
        if rising_edge(wr_clk) then
            accepted := (src_valid = '1' and src_ready = '1');

            if accepted then
                if cur_stray then
                    cur_stray := false;
                elsif beat = len_of(pid) - 1 then
                    pid  := pid + 1;
                    beat := 0;
                else
                    beat := beat + 1;
                end if;
            end if;

            rng := xorshift32(rng);

            if src_valid = '1' and not accepted then
                null;   -- hold the beat on the bus until it is taken
            elsif rst_n = '1' and pid < NUM_PKTS and chance(rng, SRC_PCT) then
                src_valid <= '1';
                if beat = 0 then
                    src_sop  <= '1';
                    src_dest <= std_logic_vector(to_unsigned(dest_of(pid), DEST_W));
                else
                    src_sop  <= '0';
                    src_dest <= std_logic_vector(rng(5 downto 4));   -- junk on purpose
                end if;
                if beat = len_of(pid) - 1 then
                    src_eop <= '1';
                else
                    src_eop <= '0';
                end if;
                src_data <= std_logic_vector(to_unsigned(pid mod 65536, 16)) &
                            std_logic_vector(to_unsigned(beat, 16));
            elsif pid >= NUM_PKTS and inject_stray = '1' and not stray_issued then
                src_valid    <= '1';
                src_sop      <= '0';
                src_eop      <= '0';
                src_dest     <= (others => '0');
                src_data     <= x"DEAD0001";
                cur_stray    := true;
                stray_issued := true;
            else
                src_valid <= '0';
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Source enable drops now and then, link_up must follow
    ------------------------------------------------------------------
    enable_ctl : process
    begin
        wait for 150 ns;
        src_enable <= '1';
        wait for 100 ns;
        assert link_up = '1' report "link_up should rise after src_enable" severity failure;
        while not sim_done loop
            wait for 3 us;
            exit when sim_done;
            src_enable <= '0';
            wait for 400 ns;
            assert link_up = '0' report "link_up should drop with src_enable" severity failure;
            src_enable <= '1';
            wait for 100 ns;
            assert link_up = '1' report "link_up should recover" severity failure;
        end loop;
        wait;
    end process;

    ------------------------------------------------------------------
    -- Sink and scoreboard
    ------------------------------------------------------------------
    sink : process (rd_clk)
        variable rng       : unsigned(31 downto 0) := to_unsigned(SEED * 40503 + 5, 32);
        variable pid, beat : natural := 0;
        variable ones      : natural;
        variable len       : natural;
    begin
        if rising_edge(rd_clk) then
            ones := 0;
            for p in 0 to NUM_PORTS - 1 loop
                if out_valid(p) = '1' then
                    ones := ones + 1;
                end if;
            end loop;
            assert ones <= 1 report "out_valid must be one-hot or idle" severity failure;

            for p in 0 to NUM_PORTS - 1 loop
                if out_valid(p) = '1' and out_ready(p) = '1' then
                    assert pid < NUM_PKTS report "extra word emerged after the last packet" severity failure;
                    len := len_of(pid);
                    assert p = dest_of(pid)
                        report "packet " & integer'image(pid) & " beat " & integer'image(beat) &
                               " left on port " & integer'image(p) &
                               ", expected " & integer'image(dest_of(pid))
                        severity failure;
                    assert to_integer(unsigned(out_dest)) = p
                        report "out_dest disagrees with the port" severity failure;
                    assert (out_sop = '1') = (beat = 0)
                        report "sop wrong on packet " & integer'image(pid) severity failure;
                    assert (out_eop = '1') = (beat = len - 1)
                        report "eop wrong on packet " & integer'image(pid) severity failure;
                    assert out_data = std_logic_vector(to_unsigned(pid mod 65536, 16)) &
                                      std_logic_vector(to_unsigned(beat, 16))
                        report "payload wrong on packet " & integer'image(pid) &
                               " beat " & integer'image(beat)
                        severity failure;

                    if beat = len - 1 then
                        pid  := pid + 1;
                        beat := 0;
                    else
                        beat := beat + 1;
                    end if;
                end if;
            end loop;
            rx_pid_s <= pid;

            rng := xorshift32(rng);
            for p in 0 to NUM_PORTS - 1 loop
                if chance(rotate_right(rng, p * 8), OUT_PCT) then
                    out_ready(p) <= '1';
                else
                    out_ready(p) <= '0';
                end if;
            end loop;
        end if;
    end process;

    cover_full : process (wr_full)
    begin
        if wr_full = '1' then
            seen_full <= true;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Sequencing
    ------------------------------------------------------------------
    main : process
    begin
        rst_n <= '0';
        wait for 100 ns;
        rst_n <= '1';

        wait until rx_pid_s = NUM_PKTS for 20 ms;
        assert rx_pid_s = NUM_PKTS
            report "timeout: only " & integer'image(rx_pid_s) & " of " &
                   integer'image(NUM_PKTS) & " packets arrived"
            severity failure;

        wait for 300 ns;
        assert rd_empty = '1' report "FIFO should be drained" severity failure;
        assert rx_malformed = 0 report "clean traffic must not count as malformed" severity failure;

        inject_stray <= '1';
        wait until rx_malformed = 1 for 10 us;
        assert rx_malformed = 1 report "stray word was not counted" severity failure;

        wait for 500 ns;
        assert rd_empty = '1' report "stray word leaked into the FIFO" severity failure;
        assert rx_pid_s = NUM_PKTS report "stray word was forwarded" severity failure;

        if EXPECT_FULL then
            assert seen_full report "this scenario was meant to hit full and never did" severity failure;
        end if;

        sim_done <= true;
        report "packet_router_tb PASS: " & integer'image(NUM_PKTS) & " packets, full seen=" &
               boolean'image(seen_full);
        finish;
    end process;

end architecture sim;
