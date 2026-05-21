# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Chi Zhang <chizhang@iis.ee.ethz.ch>

BENDER ?= bender
VLOG_ARGS = -svinputport=compat -override_timescale 1ns/1ps -suppress 2583 -suppress 13314
library ?= work
top_level ?= axi_to_dram_tb

DRAM_RTL_SIM_ROOT = $(dir $(realpath $(lastword $(MAKEFILE_LIST))))

# Recipes to build DRAMSys
include dram_rtl_sim.mk

# Path to DRAMsyslib
dramsys_resouces_path ?= $(realpath ./dramsys_lib/DRAMSys/configs)
dramsys_lib_path ?= $(realpath ./dramsys_lib/DRAMSys/build/lib)

# QuestaSim arguments
questa_args    ?=
questa_args += +DRAMSYS_RES=$(dramsys_resouces_path)
questa_args += -sv_lib $(dramsys_lib_path)/libsystemc
questa_args += -sv_lib $(dramsys_lib_path)/libDRAMSys_Simulator


# =========================================================
# VCS arguments
# =========================================================
vcs_args    ?=
vcs_args += -sverilog
vcs_args += -full64
vcs_args += -debug_access+all
vcs_args += -timescale=1ps/1ps
# DPI/SystemC shared libs
vcs_args += -LDFLAGS "-Wl,-rpath,$(dramsys_lib_path)"
vcs_args += -LDFLAGS "-L$(dramsys_lib_path)"
vcs_args += -LDFLAGS "-lDRAMSys_Simulator"
vcs_args += -LDFLAGS "-lsystemc"
vcs_args += $(dramsys_lib_path)/sc_main_dummy.o

run_vcs_args += +DRAMSYS_RES=$(dramsys_resouces_path)

all_vcs: compile_vcs
	export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$(dramsys_lib_path)
	cd vcs && ./simv $(run_vcs_args)

compile_vcs: sc_main_dummy vcs/filelist.f
	cd vcs && vcs \
		-f filelist.f \
		-top $(top_level) \
		-o simv \
		$(vcs_args)

sc_main_dummy:
	g++ -c ./$(dramsys_lib_path)/dummy_sc_main.cpp -I$(dramsys_lib_path)/DRAMSys/external/systemc/include -o ./$(dramsys_lib_path)/dummy_sc_main.o -std=c++17

vcs/filelist.f: Bender.yml Makefile $(shell find src -type f) $(shell find test -type f)
	mkdir -p vcs
	$(BENDER) script flist-plus -t test -t rtl -t simulation > $@

all: compile
	cd vsim && questa vsim -c $(library).$(top_level) -t 1ps -voptargs=+acc $(questa_args) -do start.tcl

gui: compile
	cd vsim && questa vsim $(library).$(top_level) -t 1ps -voptargs=+acc $(questa_args) -do start.tcl

compile: vsim/compile.tcl
	echo "exit" >> vsim/compile.tcl
	cd vsim && questa vsim -c -do compile.tcl

vsim/compile.tcl: Bender.yml Makefile $(shell find src -type f) $(shell find test -type f) 
	$(BENDER) script vsim -t test -t rtl --vlog-arg="$(VLOG_ARGS)" > $@

clean:
	cd vsim && rm -rf work/ vsim*  transcript  modelsim.ini compile.tcl .nfs* DRAM*
