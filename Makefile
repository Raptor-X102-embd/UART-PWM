# ============================================================
# Tools
# ============================================================
YOSYS     ?= yosys
NEXTPNR   ?= nextpnr-ecp5
ECPPACK   ?= ecppack
ICESPROG  ?= icesprog
VERILATOR ?= verilator

# ============================================================
# Directories and files
# ============================================================
BUILD_DIR   := build
SYNTH_DIR   := synthesis
CONSTR_DIR  := constraints
SYNTH_SCRIPT := $(SYNTH_DIR)/synth_ecp5.ys
LPF         := $(CONSTR_DIR)/constraints.lpf
TOP         := top
JSON        := $(BUILD_DIR)/$(TOP).json
CONFIG      := $(BUILD_DIR)/$(TOP).config
BIT         := $(BUILD_DIR)/$(TOP).bit

# ---------- Source files for simulation ----------
SRC_DIRS := rtl/src rtl/axi/src rtl/uart/Verilog/source
ALL_SRC  := $(foreach dir,$(SRC_DIRS),$(wildcard $(dir)/*.sv) $(wildcard $(dir)/*.v))
ALL_SRC  := $(filter-out %UART_To_Bus16.v %UART_To_Bus8.v, $(ALL_SRC))
ALL_SRC  := $(filter-out %.svh,$(ALL_SRC))

HDR_DIRS := rtl/axi/headers rtl/headers
ALL_HDR  := $(foreach dir,$(HDR_DIRS),$(wildcard $(dir)/*.svh))

INCDIRS  := $(addprefix -I, $(HDR_DIRS))

TB       := tb/tb_top.sv

# ---------- Verilator flags ----------
VERILATOR_FLAGS  = -sv --timing --trace --binary -Wall
VERILATOR_FLAGS += -Wno-fatal
VERILATOR_FLAGS += -Wno-TIMESCALEMOD
VERILATOR_FLAGS += -Wno-IMPORTSTAR
VERILATOR_FLAGS += -Wno-ASCRANGE
VERILATOR_FLAGS += -Wno-PROCASSINIT
VERILATOR_FLAGS += -Wno-UNUSEDPARAM
VERILATOR_FLAGS += $(INCDIRS)

SIM_BIN := $(BUILD_DIR)/tb_top

# ---------- Nextpnr flags ----------
NEXTPNR_FLAGS  = --speed 6 --25k --package CABGA256
NEXTPNR_FLAGS += --json $(JSON)
NEXTPNR_FLAGS += --lpf $(LPF)
NEXTPNR_FLAGS += --textcfg $(CONFIG)

# ============================================================
# Targets
# ============================================================
.PHONY: all synth place bit prog sim clean

all: bit

synth: $(JSON)
$(JSON): $(SYNTH_SCRIPT) $(ALL_SRC) $(ALL_HDR)
	@mkdir -p $(BUILD_DIR)
	$(YOSYS) -s $(SYNTH_SCRIPT) > $(BUILD_DIR)/synth.log 2>&1
	@echo "Synthesis completed. JSON written to $(JSON)"

place: $(CONFIG)
$(CONFIG): $(JSON) $(LPF)
	$(NEXTPNR) $(NEXTPNR_FLAGS) > $(BUILD_DIR)/pnr.log 2>&1 ; \
	cat $(BUILD_DIR)/pnr.log ; \
	exit $$?

bit: $(BIT)
$(BIT): $(CONFIG)
	$(ECPPACK) $< $@

prog: $(BIT)
	$(ICESPROG) $<

sim: $(SIM_BIN)
	./$(SIM_BIN)

$(SIM_BIN): $(ALL_SRC) $(TB) $(ALL_HDR)
	@mkdir -p $(BUILD_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module tb_top --Mdir $(BUILD_DIR) -o tb_top $(ALL_SRC) $(TB)

clean:
	rm -rf $(BUILD_DIR)
