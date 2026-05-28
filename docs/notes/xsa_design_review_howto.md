# How to Review a Vivado Block Design from an XSA (Command Line)

A procedure for inspecting a hardware design when you only have the `.xsa` archive —
no editable `.xpr`/`.bd` project. This is the common situation on a remote build/test
machine where only the deliverable was committed, not the Vivado project sources.

> **Key fact:** An XSA does **not** contain the editable block-design canvas. It carries the
> *implemented* design: bitstream, hardware handoff (`.hwh`), PS init, and an address-map
> assembly file (`.bda`). The clickable BD lives only in the original project. But every
> *fact* the canvas shows is in the `.hwh`, so a full review is possible without the GUI.

---

## 0. Why not just open it in Vivado?

If you try, you'll hit these dead ends (all confirmed on stile, Vivado 2025.1):

- `open_hw_design <file>.xsa` → `invalid command name` (that command is Hardware-Manager-only).
- `create_project` then `open_bd_design [get_files *.bd]` → `No files matched '*.bd'`
  (creating a project does not extract a BD from an XSA).
- `git log --all -- '*.bd' '*.xpr'` → empty if the project was never committed.

Conclusion: when the `.bd` isn't on the machine or in git, you read the `.hwh`. To get the
visual canvas you must be on the machine with the original `.xpr`.

---

## 1. Extract the XSA (it's just a zip)

```bash
cd /tmp && rm -rf xsa_inspect && mkdir xsa_inspect && cd xsa_inspect
unzip -o /path/to/design.xsa
ls -la
```

**What you're looking for / what you'll see:**

| File | What it is |
|---|---|
| `*.hwh` | **Hardware handoff** — XML with every IP parameter, port, address, interrupt. The source of truth. |
| `*_smartconnect_*.hwh` | Per-IP handoff for the interconnect (its own file). |
| `*.bda` | Block-design **assembly** — small GraphML listing cells + the address map. Human-readable. |
| `*.bit` | The bitstream (large). |
| `psu_init.*` | PS configuration (clocks, DDR, MIO) generated for this design. |
| `sysdef.xml`, `xsa.xml`, `xsa.json` | Manifests tying the archive together. |

There may be more than one `.hwh`. The one named after the design (not a sub-IP) is the
top-level handoff.

---

## 2. AXI peripheral IP configuration

```bash
HWH=design.hwh   # the top-level .hwh
grep -iE "FIFO_DEPTH|FIFO_EXIST|SCK_RATIO|NUM_SS_BITS|NUM_TRANSFER_BITS|SPI_MODE|SPI_MEMORY|TYPE_OF_AXI4_INTERFACE|S_AXI4?_DATA_WIDTH" "$HWH"
```

**What each parameter tells you (SPI example):**

- `C_FIFO_DEPTH` — TX/RX FIFO size in elements. Bounds how the driver chunks large transfers.
- `C_SCK_RATIO` — fixed divider from the AXI/ext clock to SCK. With the clock (step 5) this
  gives the **actual on-wire SPI rate** — verify it matches what your benchmark claims.
- `C_NUM_SS_BITS` — number of slave selects (devices on the bus).
- `C_NUM_TRANSFER_BITS` — word size (8/16/32).
- `C_SPI_MODE` — 0 = standard single-bit; nonzero = dual/quad. Loopback needs standard mode.
- `C_TYPE_OF_AXI4_INTERFACE` / `C_S_AXI_DATA_WIDTH` — 0 + 32 = AXI4-Lite, 32-bit.

> Adapt the grep terms to whatever IP you're reviewing — every IP's parameters are `C_*` names
> in the same `<PARAMETER NAME=... VALUE=.../>` form.

---

## 3. Address map

```bash
cat design.bda          # GraphML — read the <node> blocks
# or pull straight from the hwh:
grep -iE "BASEADDR|HIGHADDR|ADDRESSBLOCK|RANGE" "$HWH" | head
```

**What you're looking for:** the `BA` (base) / `HA` (high) values, the master that reaches the
slave (`MX`/`MI` — e.g. PS `M_AXI_HPM0_FPD`), and the segment name. Cross-check the base
address against your device tree / overlay and your userspace binary.

---

## 4. Interconnect topology

```bash
grep -iE "smartconnect|axi_interconnect|S00_AXI|M00_AXI|NUM_SI|NUM_MI" "$HWH" | head -20
```

**What you're looking for:** whether it's a **SmartConnect** (newer) or **AXI Interconnect**
(older), and the master/slave count (`NUM_SI`/`NUM_MI`). A single master → single slave is the
simplest case. Trace `S00_AXI*` connections back to the PS master port to confirm the path.

---

## 5. Clocking

```bash
grep -iE "ext_spi_clk|s_axi_aclk|FREQ_HZ|CLKFREQUENCY|pl_clk" "$HWH" | head -20
```

**What you're looking for:** the `CLKFREQUENCY` / `FREQ_HZ` on the IP's clock ports, and which
`pl_clkN` drives them. **Then compute the real peripheral rate:** e.g. SPI `SCK = clock ÷
C_SCK_RATIO`. This is the single most common place a benchmark's stated rate diverges from the
hardware — always reconcile the two.

---

## 6. Interrupt routing

```bash
grep -iE "ip2intc|irpt|interrupt|pl_ps_irq|IRQ|xlconcat|concat" "$HWH" | head -20
```

**What you're looking for:**

- An interrupt output port (e.g. `ip2intc_irpt`) and where it `CONNECTION`s to — typically a
  `pl_ps_irqN` on the PS (into the GIC).
- `PSU__USE__IRQn = 1` confirming the PS leg is enabled.
- An `xlconcat` only if multiple interrupt sources are merged into one PS IRQ line.
- Presence of a real IRQ connection ⇒ the driver is **interrupt-driven**; absence ⇒ likely
  **polled**. This materially affects per-transaction latency.

---

## 7. External ports / pin signals

```bash
grep -iE "EXTERNALPORTS|EXTERNALINTERFACES|PORTMAP|EXTERNAL" "$HWH" | head -40
# physical package pins (often absent from an XSA):
grep -iE "PACKAGE_PIN|LOC|IOSTANDARD" "$HWH"
ls *.xdc 2>/dev/null || echo "no XDC in XSA"
```

**What you're looking for:** the named top-level ports (e.g. `SPI_0_io0/io1/sck/ss`) and the
logical→physical `PORTMAP`. This gives the **signal-level** wiring (io0=MOSI, io1=MISO in
standard SPI).

> **The usual gap:** physical **package pin LOCs** are in the **XDC**, which is frequently *not*
> packaged in the XSA. If `no XDC in XSA`, the physical pin numbers exist only in the original
> project's constraints file. You need those before any physical jumper/probe work.

---

## Review checklist

- [ ] IP version + key parameters (FIFO, mode, width, SS count)
- [ ] Real peripheral clock rate computed (clock ÷ ratio) and reconciled with benchmark
- [ ] Base address confirmed against device tree + userspace binary
- [ ] Interconnect type + topology traced master→slave
- [ ] Interrupt path confirmed (driver interrupt-driven vs. polled)
- [ ] Top-level signal ports mapped (which net = which function)
- [ ] Physical pin LOCs obtained (from XDC — likely needs the original project)

## The lesson

The canvas was unrecoverable on stile because the `.bd`/`.xpr` were never committed (only the
XSA was). **Fix going forward:** in the original project run
`write_bd_tcl -force ./hardware/tcl/<name>_bd.tcl` and commit it. That Tcl regenerates the full
block design on any machine — the git-friendly way to version a BD — and would have made this
entire workaround unnecessary.
