-- packet_ingress.vhd
-- Write-clock side of the router: takes valid/ready words from the source,
-- stamps each one with its packet's destination, and pushes them into the
-- FIFO.
--
-- Rules, kept deliberately small:
--   * A word is accepted when valid and ready are both high on a clock edge.
--   * ready is low during reset, while src_enable is low, and while the FIFO
--     is full. That is the only backpressure the source sees.
--   * Only the sop word needs a meaningful dest; later words get the sop
--     word's dest stamped on them here.
--   * A word that arrives outside a packet without sop is a stray. It is
--     accepted off the bus (so the source isn't stuck) but dropped, and
--     counted. A sop that arrives while a packet is still open means the
--     previous packet was truncated; the new one goes through, and the
--     event is counted too.
--
-- Author: Frank Oduro <frankoduro1912@gmail.com>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.router_types_pkg.all;

entity packet_ingress is
    port (
        clk              : in  std_logic;
        rst_n            : in  std_logic;   -- synchronized to clk

        src_enable       : in  std_logic;
        src_valid        : in  std_logic;
        src_ready        : out std_logic;
        src_sop          : in  std_logic;
        src_eop          : in  std_logic;
        src_dest         : in  dest_t;
        src_data         : in  payload_t;

        fifo_full        : in  std_logic;
        fifo_wr_en       : out std_logic;
        fifo_wr_data     : out word_t;

        malformed_count  : out unsigned(15 downto 0)   -- saturates
    );
end entity packet_ingress;

architecture rtl of packet_ingress is

    signal in_packet : std_logic := '0';
    signal dest_q    : dest_t    := (others => '0');
    signal count_q   : unsigned(15 downto 0) := (others => '0');

    signal ready_i   : std_logic;
    signal accept    : std_logic;
    signal stray     : std_logic;
    signal truncated : std_logic;
    signal wr_en_i   : std_logic;
    signal eff_dest  : dest_t;

begin

    ready_i   <= rst_n and src_enable and not fifo_full;
    accept    <= src_valid and ready_i;

    stray     <= accept and not in_packet and not src_sop;
    truncated <= accept and in_packet and src_sop;
    wr_en_i   <= accept and not stray;

    eff_dest  <= src_dest when src_sop = '1' else dest_q;

    fifo_wr_en   <= wr_en_i;
    fifo_wr_data <= pack_word(src_sop, src_eop, eff_dest, src_data);
    src_ready    <= ready_i;

    state : process (clk, rst_n)
    begin
        if rst_n = '0' then
            in_packet <= '0';
            dest_q    <= (others => '0');
            count_q   <= (others => '0');
        elsif rising_edge(clk) then
            if wr_en_i = '1' then
                in_packet <= not src_eop;
                if src_sop = '1' then
                    dest_q <= src_dest;
                end if;
            end if;

            if (stray = '1' or truncated = '1') and count_q /= x"FFFF" then
                count_q <= count_q + 1;
            end if;
        end if;
    end process;

    malformed_count <= count_q;

end architecture rtl;
