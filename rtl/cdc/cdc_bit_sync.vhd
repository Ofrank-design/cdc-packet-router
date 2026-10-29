-- cdc_bit_sync.vhd
-- Two-flop synchronizer for ONE slowly changing control bit.
--
-- Use it for levels (enable, status, a handshake state bit). Do not use it
-- for pulses shorter than a destination clock period - the destination may
-- never see them - and never bit-by-bit on a bus. Buses go through the
-- async FIFO.
--
-- Author: Frank Oduro <frankoduro1912@gmail.com>

library ieee;
use ieee.std_logic_1164.all;

entity cdc_bit_sync is
    port (
        dst_clk   : in  std_logic;
        dst_rst_n : in  std_logic;   -- already synchronized to dst_clk
        async_in  : in  std_logic;
        sync_out  : out std_logic
    );
end entity cdc_bit_sync;

architecture rtl of cdc_bit_sync is

    signal ff1 : std_logic := '0';
    signal ff2 : std_logic := '0';

    -- Keeps Vivado from optimizing the pair away and tells it to place the
    -- two flops side by side. Other vendors have their own spelling.
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of ff1 : signal is "TRUE";
    attribute ASYNC_REG of ff2 : signal is "TRUE";

begin

    process (dst_clk, dst_rst_n)
    begin
        if dst_rst_n = '0' then
            ff1 <= '0';
            ff2 <= '0';
        elsif rising_edge(dst_clk) then
            ff1 <= async_in;   -- may go metastable, nothing reads it directly
            ff2 <= ff1;        -- one full period to settle
        end if;
    end process;

    sync_out <= ff2;

end architecture rtl;
