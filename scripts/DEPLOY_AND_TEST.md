# Deploy & Test — after a successful bitstream rebuild

Once `rebuild_bitstream.tcl` produces a fresh `spi_benchmark_wrapper.bit.bin`,
this is the board-side procedure to deploy it and validate. Closes out both
Priority 1 (external loopback) and Priority 2 (SCK clock rate).

---

## 0. Sanity-check the new image BEFORE deploying

The known-good (stale-routing but valid-format) image is **~26 MB**
(26,510,880 bytes). Compare the freshly built one:

```bash
ls -l /tmp/spi_rebuild_out/spi_benchmark_wrapper.bit.bin
ls -l ~/spi-soc-research/sd-images/spi_benchmark_wrapper.bit.bin   # reference
```

- If the new file is **roughly the same size (~26 MB)** → format is right, proceed.
- If it is **very different** (e.g. a few MB, or has a `.bin.0`/extra suffix) →
  `write_cfgmem` produced the wrong shape. Use the **bootgen fallback** below.

### bootgen fallback (only if write_cfgmem output looks wrong)

```bash
# create a one-line bif
cat > /tmp/spi.bif << 'EOF'
all:
{
    [destination_device = pl] /tmp/spi_rebuild_out/spi_benchmark_wrapper.bit
}
EOF
bootgen -image /tmp/spi.bif -arch zynqmp -process_bitstream bin -w on
# produces spi_benchmark_wrapper.bit.bin next to the .bit
ls -l /tmp/spi_rebuild_out/spi_benchmark_wrapper.bit.bin
```

---

## 1. Put the new image on the SD card boot partition

Replace the stale `.bit.bin` on the card with the rebuilt one. Keep the old one
as a backup until the new one is confirmed working.

```bash
# with the SD card mounted at the boot partition, e.g. /mnt/sdboot
cp /mnt/sdboot/spi_benchmark_wrapper.bit.bin /mnt/sdboot/spi_benchmark_wrapper.bit.bin.stale-bak
cp /tmp/spi_rebuild_out/spi_benchmark_wrapper.bit.bin /mnt/sdboot/spi_benchmark_wrapper.bit.bin
sync
```

(Also update the repo copy once confirmed working:
`cp /tmp/spi_rebuild_out/spi_benchmark_wrapper.bit.bin ~/spi-soc-research/sd-images/` then commit.)

---

## 2. Boot the board and run the init sequence (as root)

SW6 = SD boot (0010). Serial console:
`sudo picocom -b 115200 --noreset --flow n --lower-rts --lower-dtr /dev/ttyUSB0`

Log in, `sudo -i`, then:

```bash
mkdir -p /lib/firmware
cp /run/media/boot-mmcblk0p1/spi_benchmark_wrapper.bit.bin /lib/firmware/
dumpimage -T flat_dt -p 2 -o /tmp/spi_pl.dtbo /run/media/boot-mmcblk0p1/image.ub
mkdir -p /sys/kernel/config/device-tree/overlays/spi-benchmark
cat /tmp/spi_pl.dtbo > /sys/kernel/config/device-tree/overlays/spi-benchmark/dtbo
ln -s /dev/spidev1.0 /dev/spidev0.0
cp /run/media/boot-mmcblk0p1/spi_loopback_test /tmp/ && chmod +x /tmp/spi_loopback_test
```

---

## 3. FIRST verify the rebuild actually drives the pins

This is the test that the rebuild fixed the root cause. With the board running a
transfer, put a multimeter on **J55 pin 1 (MOSI)** to GND:

- Run a continuous transfer:  `while true; do /tmp/spi_loopback_test 2>/dev/null; done`  (Ctrl-C to stop)
- Pin 1 should now show **activity** (not the dead flat reading from the stale bitstream).
- If still dead → the rebuild didn't take; stop and recheck the .bit.bin on the card.

---

## 4. External loopback test (Priority 1)

Jumper **J55 pin 1 (MOSI) ↔ pin 2 (MISO)**. Then:

```bash
devmem 0xa0000060 32 0x00000186   # external loopback (LOOP bit clear)
devmem 0xa0000060                  # confirm reads 0x...186
/tmp/spi_loopback_test
```

Expect **PASS** at all sizes. (Internal loopback `0x187` already validated the
data path; this confirms the physical I/O path end-to-end.)

---

## 5. Clock-rate confirmation (Priority 2)

With the pins now driven, probe **J55 pin 4 (SCK)** during an active transfer
using a logic analyzer or scope (>25 MHz bandwidth). Measure the actual SCK
frequency to settle the open paper item:

- Design prediction: **3.125 MHz** (C_SCK_RATIO=16, 100 MHz input)
- Empirical timing estimate: **~11.1 MHz**

The measured value is the number the paper's timing section should use. If the
two benchmarked interfaces ran at different clocks, normalize and re-run AXI at
the matched clock before finalizing the comparative dataset.

---

## Done = both items closed in one session

PASS on step 4 + a measured SCK on step 5 closes Priority 1 and Priority 2. Then
update the repo (`sd-images/` bitstream + a findings note) and finalize the paper
timing claims.
