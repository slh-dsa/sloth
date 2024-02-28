//	sim_tb.cpp
//	Markku-Juhani O. Saarinen <mjos@iki.fi>

//	===	verilator main for sim_tb

#include <verilated.h>
#include "Vsim_tb.h"

int main(int argc, char **argv)
{
	int hclk = 0;

	(void) argc;
	(void) argv;

	Vsim_tb* sim_tb = new Vsim_tb;

	// Simulate until $finish
	while (!Verilated::gotFinish()) {

		hclk++;
		sim_tb->clk = !sim_tb->clk;

		// Evaluate model
		sim_tb->eval();
	}

	// Final model cleanup
	sim_tb->final();

	// Destroy model
	delete sim_tb;

	return 0;
}
