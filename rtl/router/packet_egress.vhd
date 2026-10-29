-- packet_egress.vhd
-- Read-clock side: looks at the word at the head of the FIFO, raises
-- out_valid on the port that word is addressed to, and pops the word when
-- that port says ready.
--
-- No state here. Because ingress stamped dest on every word, the head word
-- alone says where it goes. out_valid depends only on "FIFO not empty",
-- never on out_ready, so a consumer can wait for valid without a
-- combinational loop through its own ready.
--
-- Author: Frank Oduro <frankoduro1912@gmail.com>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.router_types_pkg.all;

entity packet_egress is
    port (
        fifo_empty   : in  std_logic;
        fifo_rd_data : in  word_t;
        fifo_rd_en   : out std_logic;

        out_valid    : out std_logic_vector(NUM_PORTS - 1 downto 0);
        out_ready    : in  std_logic_vector(NUM_PORTS - 1 downto 0);
        out_sop      : out std_logic;
        out_eop      : out std_logic;
        out_dest     : out dest_t;
        out_data     : out payload_t
    );
end entity packet_egress;

architecture rtl of packet_egress is

    signal dest_i : dest_t;

begin

    dest_i   <= word_dest(fifo_rd_data);
    out_sop  <= word_sop(fifo_rd_data);
    out_eop  <= word_eop(fifo_rd_data);
    out_dest <= dest_i;
    out_data <= word_payload(fifo_rd_data);

    select_port : process (fifo_empty, dest_i, out_ready)
    begin
        out_valid  <= (others => '0');
        fifo_rd_en <= '0';
        if fifo_empty = '0' then
            out_valid(to_integer(unsigned(dest_i))) <= '1';
            fifo_rd_en <= out_ready(to_integer(unsigned(dest_i)));
        end if;
    end process;

end architecture rtl;
