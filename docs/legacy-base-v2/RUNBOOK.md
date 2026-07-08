# BASE v2.0 — Run22 Tape-Out & FPGA Emulation Runbook
## Branch: `base-v2.0` | Commit: `123697a` | PDK: Sky130A | Tool: LibreLane 2.4.6

---

## Context: What the Documents Tell Us

### Architecture (v2.0 vs v1.0)
v1.0 used `caravel_secure_boot` as the macro wrapping `secure_boot_system_wrapper`.
v2.0 **replaces** `caravel_secure_boot` with `secure_boot_control_plane`, which adds a
4-register Wishbone slave interface (GLOBAL_STATE, STATUS_FLAGS, TIMEOUTS, CONTROL) and
`user_irq[0]`. The core FSMs (`secure_boot_fsm` + `group_fsm`) are unchanged.

### Harden Run History
- **Runs 1-12:** Hold violations (resizer steps disabled). Fixed with `RUN_POST_CTS_RESIZER_TIMING`/`RUN_POST_GRT_RESIZER_TIMING`.
- **Run 13:** First successful harden. 348 FEOL, 8044 Magic DRC.
- **Run 15:** `FP_PDN_CORE_RING=False` experiment. Magic DRC = 0, but XOR fails (161 diffs). **Ring is mandatory for XOR.**
- **Runs 17-20:** Various experiments, FEOL stayed 357-399.
- **Run 21:** Fixed `io_oeb[21:28]` from HIGH→LOW (conb_1 .HI→.LO). OEB now passes. 369 FEOL, 8035 Magic DRC.
- **Feb 20 session (caravel_tapeout_status.docx):** Separate precheck run with already-hardened macro, showed 7035 Magic DRC, OEB FAIL (stat=6), Consistency FAIL.

### The Ring Paradox (Critical Understanding)
The PDN core ring intentionally extends ~43µm outside the die boundary to connect to
Caravel harness power rails. This creates an irreconcilable conflict:
- Ring present → XOR passes, Magic DRC fails (8000+ false positives)
- Ring absent → Magic DRC passes, XOR fails (161 differences)

**No GDS post-processing can fix both simultaneously.** This was exhaustively tested
(clipping met4/met5, clipping all layers, clipping drawing layers only — all fail).

### Key Config Discoveries (Hard-Won)
| Key | Value | Why |
|-----|-------|-----|
| `ERROR_ON_NL_ASSIGN_STATEMENTS` | `false` | Correct LibreLane key name. NOT `ERROR_ON_ASSIGN` or `QUIT_ON_ASSIGN`. Required because Yosys generates assign for bus concatenations in elaborate-only mode. |
| `LVS_INCLUDE_MARCO_NETLISTS` | `true` | **'MARCO' is a typo in LibreLane 2.4.6 source.** Must match exactly. |
| `SYNTH_ELABORATE_ONLY` | `true` | Treats macro as black box during synthesis. |
| `RUN_POST_CTS_RESIZER_TIMING` | `true` | Required for hold fixing. Without it, hold violations abort the flow. |
| `RUN_POST_GRT_RESIZER_TIMING` | `true` | Same — both needed. |
| `ERROR_ON_LVS_ERROR` | `false` | Wrapper LVS will never be fully clean (Caravel architecture). |
| `MAGIC_EXT_USE_GDS` | `false` | When `true`, causes S9_ cell prefix problems. |

---

## Track 1 — Run22 Tape-Out (Macro-First Approach)

### Goal
Harden `secure_boot_control_plane` as a standalone macro (replacing `caravel_secure_boot`),
then black-box instantiate it in `user_project_wrapper`. Macro Y placement increased from
200→400µm to give wrapper tap rows clearance → fixes FEOL nwell violations.

### Step 1: Harden the Macro

```bash
cd ~/Caravel/secure_boot_caravel

# Create macro config directory
mkdir -p openlane/secure_boot_control_plane

# Copy config (provided in this deliverable)
cp <deliverable>/openlane/secure_boot_control_plane/config.json \
   openlane/secure_boot_control_plane/

# Harden
cf harden secure_boot_control_plane
```

**What to verify after macro hardening:**
- DRC clean (the macro itself should be clean, like `caravel_secure_boot` was: 333 devices, 344 nets)
- No setup/hold violations in STA
- GDS, LEF, LIB, GL netlist, and SPEF (min/nom/max) all generated

**Expected outputs:**
```
runs/<tag>/results/final/gds/secure_boot_control_plane.gds
runs/<tag>/results/final/lef/secure_boot_control_plane.lef
runs/<tag>/results/final/lib/secure_boot_control_plane.lib
runs/<tag>/results/final/verilog/gl/secure_boot_control_plane.v
runs/<tag>/results/final/spef/multicorner/secure_boot_control_plane.{min,nom,max}.spef
```

**If it fails:**
- Check synthesis log first (90% of failures are RTL issues)
- If hold violations: verify `RUN_POST_CTS_RESIZER_TIMING` and `RUN_POST_GRT_RESIZER_TIMING` are true
- If die area too small: switch from `FP_SIZING: relative` to absolute and increase

### Step 2: Stage Macro Outputs

```bash
RUN=$(ls -t openlane/secure_boot_control_plane/runs/ | head -1)
BASE="openlane/secure_boot_control_plane/runs/$RUN/results/final"

cp $BASE/gds/secure_boot_control_plane.gds              gds/
cp $BASE/lef/secure_boot_control_plane.lef              lef/
cp $BASE/lib/secure_boot_control_plane.lib              lib/
cp $BASE/verilog/gl/secure_boot_control_plane.v         verilog/gl/
cp $BASE/spef/multicorner/secure_boot_control_plane.min.spef  spef/multicorner/
cp $BASE/spef/multicorner/secure_boot_control_plane.nom.spef  spef/multicorner/
cp $BASE/spef/multicorner/secure_boot_control_plane.max.spef  spef/multicorner/
```

### Step 3: Update `user_project_wrapper.v`

The wrapper must instantiate `secure_boot_control_plane` (replacing `caravel_secure_boot`).
Key changes from v1.0 wrapper (per Implementation Spec §6.1):

1. Remove `u_tie_wbs_ack` (conb_1 tie cell for Wishbone ACK) — control plane drives ACK
2. Remove `gen_wbs_dat` (32-bit wbs_dat_o tie to LOW) — control plane drives data
3. Modify `gen_irq` to only tie `user_irq[2:1]` LOW; `user_irq[0]` comes from control plane
4. Replace `caravel_secure_boot u_secure_boot` with `secure_boot_control_plane u_secure_boot_cp`
5. Connect all Wishbone, GPIO, and IRQ ports
6. Remove VPWR/VGND ports from instantiation (control plane doesn't expose power pins)
7. Verify `io_oeb[21:28]` driven LOW (output-enabled) — this was the run21 fix

```verilog
// The wrapper instantiation should look like this:
secure_boot_control_plane u_secure_boot_cp (
    .wb_clk_i   (wb_clk_i),
    .wb_rst_i   (wb_rst_i),
    .wbs_stb_i  (wbs_stb_i),
    .wbs_cyc_i  (wbs_cyc_i),
    .wbs_we_i   (wbs_we_i),
    .wbs_sel_i  (wbs_sel_i),
    .wbs_dat_i  (wbs_dat_i),
    .wbs_adr_i  (wbs_adr_i),
    .wbs_ack_o  (wbs_ack_o),
    .wbs_dat_o  (wbs_dat_o),
    .io_in      (io_in),
    .io_out     (io_out),
    .io_oeb     (io_oeb),       // if control plane manages OEB
    .user_irq   (user_irq)      // if control plane manages IRQ
);
```

**Note:** If `secure_boot_control_plane` does NOT have `io_oeb` and `user_irq` ports
(i.e., those are still managed by wrapper tie-off logic), keep the existing tie-off
assigns and only connect Wishbone + `io_in` + `io_out`.

### Step 4: Install Wrapper Config

```bash
# Copy config (provided in this deliverable)
cp <deliverable>/openlane/user_project_wrapper/config.json \
   openlane/user_project_wrapper/config.json
```

**Critical config details in the provided file:**
- `MACROS` dict format (not `EXTRA_LEFS`/`EXTRA_GDS_FILES`) — this is LibreLane 2.4.6 format
- Macro Y placement: **400µm** (up from 200µm) — gives bottom tap rows clearance
- `PDN_MACRO_CONNECTIONS` (not `FP_PDN_MACRO_HOOKS`)
- All the hard-won config keys listed above

### Step 5: Update LVS Config

```bash
# Update lvs/user_project_wrapper/lvs_config.json
python3 -c "
import json
with open('lvs/user_project_wrapper/lvs_config.json') as f:
    c = json.load(f)
c['LVS_VERILOG_FILES'] = [
    '\$UPRJ_ROOT/verilog/gl/secure_boot_control_plane.v',
    '\$UPRJ_ROOT/verilog/gl/user_project_wrapper.v'
]
with open('lvs/user_project_wrapper/lvs_config.json', 'w') as f:
    json.dump(c, f, indent=4)
print('Done')
"
```

### Step 6: Add SPDX Headers

```bash
# Add to all RTL files missing headers:
for f in verilog/rtl/control_plane/secure_boot_control_plane.sv \
         verilog/rtl/secure_boot_core/secure_boot_fsm.sv \
         verilog/rtl/secure_boot_core/group_fsm.sv \
         verilog/rtl/secure_boot_core/secure_boot_system_wrapper.sv \
         verilog/rtl/user_project_wrapper.v; do
    if ! grep -q 'SPDX-License-Identifier' "$f" 2>/dev/null; then
        sed -i '1i // SPDX-FileCopyrightText: 2026 <Your Name>\n// SPDX-License-Identifier: Apache-2.0' "$f"
        echo "Added SPDX header to $f"
    fi
done
```

### Step 7: Harden Wrapper

```bash
cf harden user_project_wrapper
```

### Step 8: Copy Wrapper Outputs

```bash
RUN=$(ls -t openlane/user_project_wrapper/runs/ | head -1)

cp openlane/user_project_wrapper/runs/$RUN/50-magic-streamout/user_project_wrapper.gds gds/
cp openlane/user_project_wrapper/runs/$RUN/52-magic-writelef/user_project_wrapper.lef lef/
cp openlane/user_project_wrapper/runs/$RUN/39-openroad-detailedrouting/user_project_wrapper.pnl.v \
   verilog/gl/user_project_wrapper.v
```

### Step 9: Run Precheck

```bash
make run-precheck
# Or: cf precheck

# View results:
grep -E 'PASS|FAIL|CHECK' precheck_results/*/logs/precheck.log | tail -40
```

### Expected Run22 Precheck Results

| Check | Expected | Notes |
|-------|----------|-------|
| License / SPDX | ⚠️ WARN | Binary .so files will still be flagged (benign). RTL files should pass after Step 6. |
| Makefile | ✅ PASS | |
| Default / README | ✅ PASS | |
| Documentation | ✅ PASS | |
| Top Cell | ✅ PASS | |
| Consistency | ✅ PASS | **Should fix** — GL netlist now references `secure_boot_control_plane` correctly |
| GPIO Defines | ✅ PASS | |
| XOR | ✅ PASS | Ring still present → 0 differences |
| Magic DRC | ⚠️ REDUCED | Y=400µm placement should eliminate y≈13-15µm violations. Ring violations remain. Expect significant reduction from 7035-8035. |
| Klayout FEOL | ⚠️ REDUCED | Same mechanism — increased clearance should reduce tap cell nwell violations |
| Klayout BEOL | ✅ PASS | |
| OEB | ✅ PASS | Fixed in run21 (conb_1 .LO wiring) |
| LVS | ❌ N/A | Disabled on platform — not a submission gate check |

### Debugging Commands

```bash
# Check if resizer step actually ran
RUN=$(ls -t openlane/user_project_wrapper/runs/ | head -1)
ls openlane/user_project_wrapper/runs/$RUN/ | grep -iE 'resiz|hold|repair'

# Check resolved config
grep -E 'HOLD|RESIZER|MARCO|ASSIGN|ELABORATE' \
  openlane/user_project_wrapper/runs/$RUN/resolved.json

# DRC violation type summary
grep 'um (' openlane/user_project_wrapper/runs/$RUN/56-magic-drc/reports/drc_violations.magic.rpt \
  | grep -v '^[[:space:]]*[0-9]' | sort -u

# DRC violation count
grep -c 'um (' openlane/user_project_wrapper/runs/$RUN/56-magic-drc/reports/drc_violations.magic.rpt

# LVS mismatch details (informational only)
grep -E 'Mismatch|disconnected|Flatten|equivalent|devices' \
  openlane/user_project_wrapper/runs/$RUN/62-netgen-lvs/reports/lvs.netgen.rpt | head -30

# Inspect what files Netgen actually loaded
cat openlane/user_project_wrapper/runs/$RUN/62-netgen-lvs/lvs_script.lvs
```

---

## Track 2 — FPGA Emulation on Terasic DE25-Standard

### Prerequisites
- Quartus Pro installed (free license bundled with DE25-Standard)
- DE25-Standard board connected via USB-Blaster II
- Board manual for pin assignments (Terasic provides a `.qsf` template)

### Step 1: Create FPGA Directory & Copy Files

```bash
cd ~/Caravel/secure_boot_caravel
mkdir -p fpga
cp <deliverable>/fpga/top_de25.sv       fpga/
cp <deliverable>/fpga/setup_quartus.tcl  fpga/
cp <deliverable>/fpga/base_v2_de25.sdc  fpga/
```

### Step 2: Update Pin Assignments

The TCL script has **placeholder pins**. You MUST update from the DE25-Standard manual.
Terasic typically provides a `.qsf` template — import it after creating the project.

### Step 3: Compile

```bash
cd fpga
quartus_sh -t setup_quartus.tcl
quartus_sh --flow compile base_v2_de25
```

**Expected resource usage:** <5% of 138K LEs. 50 MHz timing should close easily.

### Step 4: Program & Test

```bash
quartus_pgm -c USB-Blaster -m jtag -o "p;output_files/base_v2_de25.sof"
```

### Test Sequence

| Step | Action | Expected |
|------|--------|----------|
| 1 | Power on / reset | LEDR[9] blinks (heartbeat), HEX shows 000000, LEDR[7:0] = FSM initial state |
| 2 | SW[9:8]=00 | HEX shows GLOBAL_STATE register (live polling) |
| 3 | SW[9:8]=01 | HEX shows STATUS_FLAGS register |
| 4 | SW[9:8]=10 | HEX shows TIMEOUTS register |
| 5 | SW[0]=1 (fw_ok) | FSM transitions BOOT→LOCKED, LEDs update, GLOBAL_STATE changes |
| 6 | SW[8]=1 (global_pin_ok), SW[9]=1 (unlock_req) | FSM progresses toward AUTHORIZED |
| 7 | Press KEY[1] (tamper_in) | LEDR[8] lights (IRQ), STATUS_FLAGS shows sticky_tamper |
| 8 | Press KEY[0] (illegal_in) | security_breach asserts, FSM enters ESCALATED |

### Port Mapping Reference

| Board Element | Maps To | Function |
|--------------|---------|----------|
| CLOCK_50 | wb_clk_i | System clock |
| KEY_RESET_N | wb_rst_i (inverted) | Active-high reset |
| SW[0] | io_in[7] = fw_ok | Firmware OK |
| SW[1] | io_in[8] = fw_fail | Firmware fail |
| SW[2] | io_in[9] = size_mismatch | Size mismatch |
| SW[3] | io_in[10] = hdr_parse_fail | Header parse fail |
| SW[4] | io_in[11] = power_glitch | Power glitch detect |
| SW[5] | io_in[12] = clock_glitch | Clock glitch detect |
| SW[6] | io_in[13] = warm_reset_req | Warm reset request |
| SW[7] | io_in[14] = cold_reset_req | Cold reset request |
| SW[8] | io_in[15] = global_pin_ok | Global pin OK |
| SW[9] | io_in[16] = unlock_req | Unlock request |
| KEY[3] (press) | io_in[17] = file_denied | File denied |
| KEY[2] (press) | io_in[18] = group_autolock | Group autolock |
| KEY[1] (press) | io_in[19] = tamper_in | Tamper input |
| KEY[0] (press) | io_in[20] = illegal_in | Illegal input |
| SW[9:8] | WB address select | Selects which register HEX displays |
| HEX5-HEX0 | wb_read_data[23:0] | Live register readback |
| LEDR[7:0] | io_out[28:21] | FSM output signals |
| LEDR[8] | user_irq[0] | IRQ indicator |
| LEDR[9] | heartbeat | Clock running indicator |

### Design Decisions in `top_de25.sv`

**Auto-polling Wishbone master** instead of button-triggered reads: The FPGA master
continuously reads the register selected by SW[9:8], so the 7-seg display is always
live. This is much more useful for debugging than requiring a button press per read.

**KEY buttons map to io_in (not Wishbone writes):** Since the 4 remaining FSM inputs
(file_denied, group_autolock, tamper_in, illegal_in) need to be directly controllable
and these are event signals (not register values), mapping them to active-low pushbuttons
is more natural than requiring a Wishbone write sequence.

**Dual use of SW[9:8]:** These bits select both the Wishbone read address AND map to
io_in[15:16] (global_pin_ok, unlock_req). This is fine because the FSM inputs are
directly wired from io_in, not from the Wishbone bus. The SW→io_in mapping is always
active regardless of which register is being read.

---

## File Manifest

| File | Track | Purpose |
|------|-------|---------|
| `openlane/secure_boot_control_plane/config.json` | 1 | Macro hardening config |
| `openlane/user_project_wrapper/config.json` | 1 | Wrapper config (MACROS dict, Y=400µm) |
| `fpga/top_de25.sv` | 2 | FPGA top-level with auto-poll WB master |
| `fpga/setup_quartus.tcl` | 2 | Quartus project setup |
| `fpga/base_v2_de25.sdc` | 2 | Timing constraints |

---

## Things That Are NOT in v2.0
- Anomaly detection (future version)
- Hardware accelerator / MMIO engine (identified as integration point, out of scope)
- `archive_v1/` RTL (superseded — do not reference)
- HPS Wishbone bridge for FPGA (stubbed — using auto-poll master for bringup)
