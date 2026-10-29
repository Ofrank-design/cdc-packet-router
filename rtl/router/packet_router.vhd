-- packet_router.vhd
-- Top level: 50 MHz-ish write side, 200 MHz-ish read side, one async FIFO
-- in between. The clocks are treated as unrelated.
--
--   src_* ──► packet_ingress ──► async_fifo ──► packet_egress ──► out_*[port]
--             (wr_clk)           (both)         (rd_clk)
--
-- One external active-low reset feeds both domains through their own
-- reset_sync, so assertion is immediate everywhere and release is clean
-- in each clock domain.
--
-- link_up is src_enable carried across with a plain bit synchronizer - a
-- level, so a two-flop sync is the right tool.
--
-- Author: Frank Oduro <frankoduro1912@gmail.com>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.router_types_pkg.all;

entity packet_router is
    generic (
        FIFO_ADDR_W : positive := 4          -- depth = 2**FIFO_ADDR_W words
    );
    port (
        wr_clk          : in  std_logic;
        rd_clk          : in  std_logic;
        rst_n           : in  std_logic;     -- async, active low

        -- source side (wr_clk)
        src_enable      : in  std_logic;
        src_valid       : in  std_logic;
        src_ready       : out std_logic;
        src_sop         : in  std_logic;
        src_eop         : in  std_logic;
        src_dest        : in  dest_t;
        src_data        : in  payload_t;
        rx_malformed    : out unsigned(15 downto 0);
        wr_full         : out std_logic;

        -- output side (rd_clk)
        out_valid       : out std_logic_vector(NUM_PORTS - 1 downto 0);
        out_ready       : in  std_logic_vector(NUM_PORTS - 1 downto 0);
        out_sop         : out std_logic;
        out_eop         : out std_logic;
        out_dest        : out dest_t;
        out_data        : out payload_t;
        rd_empty        : out std_logic;
        link_up         : out std_logic
    );
end entity packet_router;

architecture rtl of packet_router is

    signal wr_rst_n, rd_rst_n : std_logic;

    signal fifo_full, fifo_empty : std_logic;
    signal fifo_wr_en, fifo_rd_en : std_logic;
    signal fifo_wr_data, fifo_rd_data : word_t;

begin

    wr_reset : entity work.reset_sync
        port map (clk => wr_clk, arst_n => rst_n, srst_n => wr_rst_n);

    rd_reset : entity work.reset_sync
        port map (clk => rd_clk, arst_n => rst_n, srst_n => rd_rst_n);

    ingress : entity work.packet_ingress
        port map (
            clk             => wr_clk,
            rst_n           => wr_rst_n,
            src_enable      => src_enable,
            src_valid       => src_valid,
            src_ready       => src_ready,
            src_sop         => src_sop,
            src_eop         => src_eop,
            src_dest        => src_dest,
            src_data        => src_data,
            fifo_full       => fifo_full,
            fifo_wr_en      => fifo_wr_en,
            fifo_wr_data    => fifo_wr_data,
            malformed_count => rx_malformed
        );

    fifo : entity work.async_fifo
        generic map (DATA_W => WORD_W, ADDR_W => FIFO_ADDR_W)
        port map (
            wr_clk   => wr_clk,
            wr_rst_n => wr_rst_n,
            wr_en    => fifo_wr_en,
            wr_data  => fifo_wr_data,
            full     => fifo_full,
            rd_clk   => rd_clk,
            rd_rst_n => rd_rst_n,
            rd_en    => fifo_rd_en,
            rd_data  => fifo_rd_data,
            empty    => fifo_empty
        );

    egress : entity work.packet_egress
        port map (
            fifo_empty   => fifo_empty,
            fifo_rd_data => fifo_rd_data,
            fifo_rd_en   => fifo_rd_en,
            out_valid    => out_valid,
            out_ready    => out_ready,
            out_sop      => out_sop,
            out_eop      => out_eop,
            out_dest     => out_dest,
            out_data     => out_data
        );

    link_sync : entity work.cdc_bit_sync
        port map (
            dst_clk   => rd_clk,
            dst_rst_n => rd_rst_n,
            async_in  => src_enable,
            sync_out  => link_up
        );

    wr_full  <= fifo_full;
    rd_empty <= fifo_empty;

end architecture rtl;
