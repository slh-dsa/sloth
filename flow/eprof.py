#!/usr/bin/env python3
#	eprof.py
#	Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

import os, sys, math, re

#	parse attributes into a string (hopefully of 9 char)

def cnt_str(cnt):	
	if cnt == 0:
		return '         '
	else:
		return f'{cnt:9d}'

#	read source file mapping
	
fr = open("../firmware.pmap")
addr = 0x0

fsc = {}		#	function counts
lsc = {}		#	source line counts

for sf in fr:
	s = sf.rstrip()
	if s[0:2] == '0x':
		addr = int(s,16)
	elif s.find(':') > 0:
		v = s.split(':')
		if v[1][0].isdigit():
			ln = int(v[1].split()[0])
			fn = v[0]
			if fn in lsc:
				if ln in lsc[fn]:
					lsc[fn][ln] = lsc[fn][ln] + 1
				else:
					lsc[fn][ln] = 1
			else:
				lsc[fn] = {ln: 1}
	else:
		if s in fsc:
			fsc[s] = fsc[s] + 1
		else:
			fsc[s] = 1
fr.close()

#	breakdown by function

fw = open("func.txt", "w")
for fc in fsc:
	fw.write(f'{cnt_str(fsc[fc])} : {fc}\n')
fw.close()

#	individual files

for rfn in lsc:
	pfl=len(os.path.commonprefix([os.getcwd(), rfn]))
	wfn = rfn[pfl:].replace("/","_");
	print("writing:", wfn)
	fr = open(rfn, "r")
	fw = open(wfn, "w")
	ln = 0
	for sf in fr:
		ln += 1
		s = sf.rstrip()
		if ln in lsc[rfn]:
			fw.write(f'{cnt_str(lsc[rfn][ln])} : {s}\n')
		else:
			fw.write(f'          : {s}\n')
	fr.close()
	fw.close()

