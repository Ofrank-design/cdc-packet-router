-- async_fifo.vhd
-- Dual-clock FIFO with Gray-coded pointer crossings (Cummings-style).
--
-- Each side owns one pointer and only ever compares it against a
-- synchronized, slightly stale copy of the other side's pointer. Stale
-- means pessimistic: full may stay up a couple of cycles after space
-- opens, empty may stay up a couple of cycles after data lands. Neither
-- error can lose or invent data.
--
-- Read port is first-word-fall-through: rd_data always shows the head
-- when empty = '0', and rd_en pops it. The read is combinational off the
-- memory array, so it maps to distributed RAM, not block RAM. Swap in a
-- registered read if you need BRAM and can afford the extra cycle.
--
-- wr_rst_n / rd_rst_n must be released through reset_sync in their own
-- domains, and should be asserted together. Resetting just one side while
-- the other runs leaves the pointers out of step.
--
-- Depth is 2**ADDR_W. ADDR_W must be at least 2 - the full compare needs
-- the two top Gray bits plus at least one more.
--
-- Author: Frank Oduro <frankoduro1912@gmail.com>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity async_fifo is
    generic (
        DATA_W : positive := 36;
        ADDR_W : positive := 4
    );
    port (
        -- write side
        wr_clk   : in  std_logic;
        wr_rst_n : in  std_logic;
        wr_en    : in  std_logic;
        wr_data  : in  std_logic_vector(DATA_W - 1 downto 0);
        full     : out std_logic;

        -- read side
        rd_clk   : in  std_logic;
        rd_rst_n : in  std_logic;
        rd_en    : in  std_logic;
        rd_data  : out std_logic_vector(DATA_W - 1 downto 0);
        empty    : out std_logic
    );
end entity async_fifo;

architecture rtl of async_fifo is

    constant PTR_W : natural := ADDR_W + 1;      -- one extra wrap bit
    constant DEPTH : natural := 2 ** ADDR_W;

    type mem_t is array (0 to DEPTH - 1) of std_logic_vector(DATA_W - 1 downto 0);
    signal mem : mem_t := (others => (others => '0'));

    -- write domain
    signal wbin, wbin_next   : unsigned(PTR_W - 1 downto 0) := (others => '0');
    signal wgray, wgray_next : std_logic_vector(PTR_W - 1 downto 0) := (others => '0');
    signal rgray_in_wclk     : std_logic_vector(PTR_W - 1 downto 0);
    signal full_i, full_next : std_logic := '0';
    signal wr_fire           : std_logic;

    -- read domain
    signal rbin, rbin_next   : unsigned(PTR_W - 1 downto 0) := (others => '0');
    signal rgray, rgray_next : std_logic_vector(PTR_W - 1 downto 0) := (others => '0');
    signal wgray_in_rclk     : std_logic_vector(PTR_W - 1 downto 0);
    signal empty_i, empty_next : std_logic := '1';
    signal rd_fire           : std_logic;

    function bin_to_gray (b : unsigned) return std_logic_vector is
    begin
        return std_logic_vector(b xor shift_right(b, 1));
    end function;

begin

    assert ADDR_W >= 2
        report "async_fifo: ADDR_W must be >= 2"
        severity failure;

    ------------------------------------------------------------------
    -- Write side (wr_clk)
    ------------------------------------------------------------------
    wr_fire    <= wr_en and not full_i;
    wbin_next  <= wbin + 1 when wr_fire = '1' else wbin;
    wgray_next <= bin_to_gray(wbin_next);

    -- Full: next write Gray pointer equals the read pointer with its two
    -- MSBs inverted - i.e. we have lapped the reader exactly once.
    full_next <= '1' when wgray_next =
                    (not rgray_in_wclk(PTR_W - 1) &
                     not rgray_in_wclk(PTR_W - 2) &
                     rgray_in_wclk(PTR_W - 3 downto 0))
                 else '0';

    write_regs : process (wr_clk, wr_rst_n)
    begin
        if wr_rst_n = '0' then
            wbin   <= (others => '0');
            wgray  <= (others => '0');
            full_i <= '0';
        elsif rising_edge(wr_clk) then
            wbin   <= wbin_next;
            wgray  <= wgray_next;
            full_i <= full_next;
        end if;
    end process;

    write_mem : process (wr_clk)
    begin
        if rising_edge(wr_clk) then
            if wr_fire = '1' then
                mem(to_integer(wbin(ADDR_W - 1 downto 0))) <= wr_data;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Read side (rd_clk)
    ------------------------------------------------------------------
    rd_fire    <= rd_en and not empty_i;
    rbin_next  <= rbin + 1 when rd_fire = '1' else rbin;
    rgray_next <= bin_to_gray(rbin_next);

    -- Empty: we have caught up with the (stale) write pointer.
    empty_next <= '1' when rgray_next = wgray_in_rclk else '0';

    read_regs : process (rd_clk, rd_rst_n)
    begin
        if rd_rst_n = '0' then
            rbin    <= (others => '0');
            rgray   <= (others => '0');
            empty_i <= '1';
        elsif rising_edge(rd_clk) then
            rbin    <= rbin_next;
            rgray   <= rgray_next;
            empty_i <= empty_next;
        end if;
    end process;

    -- Hand out zeros while empty so unwritten slots never leak into the
    -- consumer (and X's stay out of waveforms).
    rd_data <= mem(to_integer(rbin(ADDR_W - 1 downto 0)))
               when empty_i = '0' else (others => '0');

    ------------------------------------------------------------------
    -- Pointer crossings
    ------------------------------------------------------------------
    sync_r2w : entity work.cdc_gray_sync
        generic map (WIDTH => PTR_W)
        port map (
            dst_clk   => wr_clk,
            dst_rst_n => wr_rst_n,
            gray_in   => rgray,
            gray_out  => rgray_in_wclk
        );

    sync_w2r : entity work.cdc_gray_sync
        generic map (WIDTH => PTR_W)
        port map (
            dst_clk   => rd_clk,
            dst_rst_n => rd_rst_n,
            gray_in   => wgray,
            gray_out  => wgray_in_rclk
        );

    full  <= full_i;
    empty <= empty_i;

end architecture rtl;
