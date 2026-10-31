# router_template.xdc
# TEMPLATE for Xilinx Vivado. Not run through a vendor tool yet - port names,
# cell paths and clock pins need adapting to your top level and board. Treat
# every line as something to verify against your own timing and CDC reports.

# --- clocks -----------------------------------------------------------------
create_clock -name wr_clk -period 20.000 [get_ports wr_clk]   ;# 50 MHz
create_clock -name rd_clk -period 5.000  [get_ports rd_clk]   ;# 200 MHz

# The two clocks are unrelated. This stops the tool from trying to time paths
# between them as if they were synchronous. It does NOT make the crossings
# safe; the limits below still apply to the pointer paths.
set_clock_groups -asynchronous -group [get_clocks wr_clk] -group [get_clocks rd_clk]

# --- Gray pointer crossings ------------------------------------------------
# Each pointer bit must arrive well inside one destination period, and the
# bits must not skew apart by more than that. Bound the datapath delay to the
# faster (destination) period. Adjust the cell patterns to match your
# hierarchy after synthesis.
set_max_delay -datapath_only 5.000 \
    -from [get_cells -hierarchical -filter {NAME =~ *fifo/rgray_reg*}] \
    -to   [get_cells -hierarchical -filter {NAME =~ *fifo/sync_r2w/ff1_reg*}]

set_max_delay -datapath_only 5.000 \
    -from [get_cells -hierarchical -filter {NAME =~ *fifo/wgray_reg*}] \
    -to   [get_cells -hierarchical -filter {NAME =~ *fifo/sync_w2r/ff1_reg*}]

# --- single-bit level crossing ---------------------------------------------
set_max_delay -datapath_only 5.000 \
    -to [get_cells -hierarchical -filter {NAME =~ *link_sync/ff1_reg*}]

# --- reset ------------------------------------------------------------------
# rst_n is asynchronous by design; reset_sync handles the release. Do not add
# a timing exception that hides reset-release paths into the reset_sync flops.

# --- io ---------------------------------------------------------------------
# Add set_input_delay / set_output_delay and pin assignments for your board.
