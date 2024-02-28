#	prog_vcu118.tcl
#	Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

#	===	a vivado tcl script for writing bitstream on device

open_hw_manager
connect_hw_server -url localhost:3121
current_hw_target [get_hw_targets]
set_property PARAM.FREQUENCY 15000000 [get_hw_targets]
open_hw_target
set_property PROGRAM.FILE {vcu118.bit}  [lindex [get_hw_devices] 0]
program_hw_devices [lindex [get_hw_devices] 0]

