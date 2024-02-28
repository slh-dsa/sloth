#	xc7a100t-synth.tcl
#	Markku-Juhani O. Saarinen <mjos@iki.fi>

#   ===	a vivado tcl script for bitstream generation

foreach fn [glob -type f ../rtl/*.v ../rtl/*.sv] {
	read_verilog $fn
}

read_xdc ../flow/cw305_main.xdc

synth_design -part xc7a100tftg256-2 -top cw305_top

opt_design
place_design
route_design

report_utilization
report_timing

write_bitstream -force ../cw305.bit
#write_verilog -force cw305.v
#write_mem_info -force cw305.mmi
