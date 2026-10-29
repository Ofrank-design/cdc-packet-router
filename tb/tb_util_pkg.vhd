-- tb_util_pkg.vhd
-- Small helpers shared by the testbenches. Simulation only.
--
-- Author: Frank Oduro <frankoduro1912@gmail.com>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tb_util_pkg is

    -- cheap, repeatable pseudo-random numbers (xorshift32); seed must be non-zero
    function xorshift32 (x : unsigned(31 downto 0)) return unsigned;

    -- true roughly pct percent of the time
    function chance (x : unsigned(31 downto 0); pct : natural) return boolean;

    -- the testbench derives packet shape from the packet id, so the scoreboard
    -- never needs a queue: it can just recompute what the id should look like
    function len_of  (id : natural) return natural;   -- 1..6 beats
    function dest_of (id : natural) return natural;   -- 0..3

end package tb_util_pkg;

package body tb_util_pkg is

    function xorshift32 (x : unsigned(31 downto 0)) return unsigned is
        variable v : unsigned(31 downto 0) := x;
    begin
        v := v xor shift_left(v, 13);
        v := v xor shift_right(v, 17);
        v := v xor shift_left(v, 5);
        return v;
    end function;

    function chance (x : unsigned(31 downto 0); pct : natural) return boolean is
    begin
        return to_integer(x(15 downto 8)) < (pct * 256) / 100;
    end function;

    function len_of (id : natural) return natural is
    begin
        return 1 + ((id * 7 + 3) mod 6);
    end function;

    function dest_of (id : natural) return natural is
    begin
        return (id + id / 3) mod 4;
    end function;

end package body tb_util_pkg;
