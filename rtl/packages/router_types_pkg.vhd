-- router_types_pkg.vhd
-- One place that defines what a packet word looks like on the wire.
--
--   [ sop | eop | dest(1:0) | payload(31:0) ]   -> 36 bits
--
-- Every word carries its own sop/eop/dest. That costs a few FIFO bits but
-- means the read side never has to remember which packet it is in, and
-- metadata can't drift away from its payload.
--
-- Author: Frank Oduro <frankoduro1912@gmail.com>

library ieee;
use ieee.std_logic_1164.all;

package router_types_pkg is

    constant PAYLOAD_W : natural := 32;
    constant DEST_W    : natural := 2;
    constant NUM_PORTS : natural := 2 ** DEST_W;
    constant WORD_W    : natural := PAYLOAD_W + DEST_W + 2;

    subtype payload_t is std_logic_vector(PAYLOAD_W - 1 downto 0);
    subtype dest_t    is std_logic_vector(DEST_W - 1 downto 0);
    subtype word_t    is std_logic_vector(WORD_W - 1 downto 0);

    function pack_word (
        sop     : std_logic;
        eop     : std_logic;
        dest    : dest_t;
        payload : payload_t
    ) return word_t;

    function word_sop     (w : word_t) return std_logic;
    function word_eop     (w : word_t) return std_logic;
    function word_dest    (w : word_t) return dest_t;
    function word_payload (w : word_t) return payload_t;

end package router_types_pkg;

package body router_types_pkg is

    function pack_word (
        sop     : std_logic;
        eop     : std_logic;
        dest    : dest_t;
        payload : payload_t
    ) return word_t is
    begin
        return sop & eop & dest & payload;
    end function;

    function word_sop (w : word_t) return std_logic is
    begin
        return w(WORD_W - 1);
    end function;

    function word_eop (w : word_t) return std_logic is
    begin
        return w(WORD_W - 2);
    end function;

    function word_dest (w : word_t) return dest_t is
    begin
        return w(PAYLOAD_W + DEST_W - 1 downto PAYLOAD_W);
    end function;

    function word_payload (w : word_t) return payload_t is
    begin
        return w(PAYLOAD_W - 1 downto 0);
    end function;

end package body router_types_pkg;
