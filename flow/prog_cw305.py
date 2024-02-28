#!/usr/bin/env python3
#	prog_cw305.py
#	Markku-Juhani O. Saarinen <mjos@iki.fi>

#	program bitstream

import time, sys, tty, select
import chipwhisperer as cw
#from cw305_iut import cw305_iut

#	reads a string

iut_tx_idx = 0

def iut_read():
	global iut_tx_idx
	s = ''
	tx_idx = a7iut.fpga_read(a7iut.REG_TX_IDX, 1)[0]
	while tx_idx != iut_tx_idx:
		ch = a7iut.fpga_read(a7iut.REG_TX_BYTE, 1)[0]
		s += chr(ch)
		iut_tx_idx = tx_idx
		tx_idx = a7iut.fpga_read(a7iut.REG_TX_IDX, 1)[0]
	return s

#	write a string

iut_rx_idx = 0

def iut_write(s_in):
	global iut_rx_idx
	for ch in s_in:
		iut_rx_idx = (iut_rx_idx + 1) & 0xFF
		a7iut.fpga_write(a7iut.REG_RX_BYTE,[ord(ch)])
		a7iut.fpga_write(a7iut.REG_RX_IDX,[iut_rx_idx])
		rx_pos = a7iut.fpga_read(a7iut.REG_RX_POS, 1)[0]
		while rx_pos != iut_rx_idx:
			time.sleep(0.1)
			rx_pos = a7iut.fpga_read(a7iut.REG_RX_POS, 1)[0]

#	a "terminal"
def iut_term():
	fd = sys.stdin.fileno()	
	old_attr = tty.tcgetattr(fd)
	tty.setcbreak(fd)
	ch = ''
	
	while ch != '!':
		print(iut_read(), end='')
		sel = select.select([fd], [], [], 0.1)
		if sel[0] == [fd]:
			ch = sys.stdin.read(1)[0]
			iut_write(ch)

	print(".. iut_term() done")
	tty.tcsetattr(fd, tty.TCSANOW, old_attr)
 
#	program it

a7iut = cw.target(None, cw.targets.CW305,
	defines_files=["rtl/cw305_regs.vh"], bsfile='cw305.bit')

# get build time
print(a7iut.get_fpga_buildtime())

# set MHz
a7iut.pll.pll_outfreq_set(31.25E6,1)
#a7iut.pll.pll_outfreq_set(50E6,1)
print("freq= ", a7iut.pll.pll_outfreq_get(1))

# terminal
iut_term();

#	tio -b 28800 -m INLCRNL /dev/ttyUSB0

