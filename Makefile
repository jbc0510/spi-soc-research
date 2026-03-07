# SPI Performance Research - Top Level Makefile
# Author: Jerry Conway (jbc0510)
# Hardware: Xilinx ZC702 (Zynq-7000 SoC)
# Usage: make <target>

# ─────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────
LINUX_DIR    := linux
BARE_DIR     := bare_metal
SCRIPTS_DIR  := scripts
RESULTS_DIR  := results
REPORT_DIR   := docs/findings

# ─────────────────────────────────────────
# Default target - shows help
# ─────────────────────────────────────────
.PHONY: help
help:
	@echo "SPI Performance Research Build System"
	@echo "======================================"
	@echo "make setup        - Install tools and build both environments"
	@echo "make build-linux  - Build PetaLinux SPI benchmark"
	@echo "make build-bare   - Build bare-metal SPI benchmark"
	@echo "make flash        - Flash firmware to ZC702 PS"
	@echo "make results      - Collect benchmark data from both targets"
	@echo "make compare      - Run results and show performance comparison"
	@echo "make report       - Generate report from simulation data"
	@echo "make clean        - Remove all build artifacts"

# ─────────────────────────────────────────
# Setup - builds everything from scratch
# ─────────────────────────────────────────
.PHONY: setup
setup: build-linux build-bare
	@echo "Environment setup complete"
	@echo "Run 'make flash' to program the ZC702"

# ─────────────────────────────────────────
# Build targets
# ─────────────────────────────────────────
.PHONY: build-linux
build-linux:
	@echo "Building Linux SPI benchmark..."
	$(MAKE) -C $(LINUX_DIR)

.PHONY: build-bare
build-bare:
	@echo "Building bare-metal SPI benchmark..."
	$(MAKE) -C $(BARE_DIR)

# ─────────────────────────────────────────
# Flash - program firmware to ZC702
# ─────────────────────────────────────────
.PHONY: flash
flash:
	@echo "Flashing firmware to ZC702 PS..."
	$(SCRIPTS_DIR)/setup/flash.sh

# ─────────────────────────────────────────
# Results and Comparison
# ─────────────────────────────────────────
.PHONY: results
results:
	@echo "Collecting benchmark results..."
	@mkdir -p $(RESULTS_DIR)
	$(SCRIPTS_DIR)/test/collect_results.sh

.PHONY: compare
compare: results
	@echo "Comparing Linux vs Bare-Metal performance..."
	$(SCRIPTS_DIR)/test/compare.sh

# ─────────────────────────────────────────
# Report generation
# ─────────────────────────────────────────
.PHONY: report
report:
	@echo "Generating performance report..."
	@mkdir -p $(REPORT_DIR)
	$(SCRIPTS_DIR)/test/generate_report.sh

# ─────────────────────────────────────────
# Clean - wipe all build artifacts
# ─────────────────────────────────────────
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	$(MAKE) -C $(LINUX_DIR) clean
	$(MAKE) -C $(BARE_DIR) clean
	rm -rf $(RESULTS_DIR)
	@echo "Clean complete - source files preserved"
