#	xcvu9p-synth.tcl
#	Markku-Juhani O. Saarinen <mjos@iki.fi>

#   ===	a vivado tcl script for bitstream generation

foreach fn [glob -type f ../rtl/*.v ../rtl/*.sv *.v] {
	read_verilog $fn
}

read_xdc ../flow/vcu118.xdc

synth_design -part xcvu9p-flga2104-2L-e -top vcu118_top

opt_design
place_design
route_design

report_utilization
report_timing

write_bitstream -force ../vcu118.bit
#write_verilog -force cw305_a7.v
#write_mem_info -force cw305_a7.mmi

