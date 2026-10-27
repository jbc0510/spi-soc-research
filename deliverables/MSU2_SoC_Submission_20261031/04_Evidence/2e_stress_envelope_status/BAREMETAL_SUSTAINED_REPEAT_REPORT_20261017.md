# Task 2e bare-metal sustained-run repeat

**Disposition:** supporting repeatability evidence; Task 2e remains partial pending the payload/clock operating-envelope stress test.

## Run and evidence source

The operator supplied the complete serial-console output from a fresh boot into the bare-metal AXI sustained benchmark. The transcript was received on 17 October 2026 at 17:07:40 UTC and is preserved in `baremetal_sustained_uart_capture_20261017.raw.log`. The supplied text does not include the console start timestamp or a live image hash; neither is inferred here.

The runner reported 11 payloads (1 through 65,536 bytes), three repetitions, and a 60-second window for each point. It reported timer frequency 99,990,005 Hz, `IOPLL_CTRL=0x00015a00`, and `PL0_REF_CTRL=0x01010f00`. Existing read-only clock analysis associates these values with a register-derived 99.990 MHz PL0 clock, but that post-run analysis does not instrument each window. The application reports `topology=UNVERIFIED` and `physical_sck_hz=NOT_MEASURED`.

## Result

All **33 of 33** points completed. The rows sum to **46,240,175** byte-verified transfers and **1,542,507,195** verified payload bytes. There were zero API errors and zero receive mismatches. The reported application rate is verified payload bytes divided by each measured window; it is not physical wire throughput. The 100% busy-wait core occupancy is the benchmark’s execution-model metric, not a PMU reading.

| Payload | Repeat median (MB/s) | Prior set median (MB/s) | Change |
|---:|---:|---:|---:|
| 1 B | 0.142166 | 0.141830 | +0.237% |
| 8 B | 0.468107 | 0.467718 | +0.083% |
| 16 B | 0.560671 | 0.560646 | +0.004% |
| 64 B | 0.655917 | 0.655889 | +0.004% |
| 128 B | 0.674975 | 0.674999 | -0.004% |
| 256 B | 0.684918 | 0.684938 | -0.003% |
| 512 B | 0.868008 | 0.865134 | +0.332% |
| 1,024 B | 1.005298 | 0.999455 | +0.585% |
| 4,096 B | 1.140618 | 1.131241 | +0.829% |
| 16,384 B | 1.180318 | 1.169754 | +0.903% |
| 65,536 B | 1.190595 | 1.179696 | +0.924% |

The medians are within -0.004% to +0.924% of the earlier bare-metal set. This supports repeatability for the tested payload ladder and run settings. The derived CSV is `baremetal_sustained_runs_20261017.csv`; the previous comparison values are from `../task2e_sustainable_runner_20261016/baremetal_sustained_medians_20261016.csv`.

## Boundaries and next test

This run repeats the existing 1–65,536-byte workload. It does not increase the payload beyond 65,536 bytes or vary the synthesized clock. The validated design has fixed `C_SCK_RATIO=2`; Linux speed-request arguments cannot create a clock sweep for this hardware. No physical SCK reading was taken during this run, and the runner itself marks the loopback topology unverified. Therefore the repeat does not establish the maximum reliable payload or clock and does not close Task 2e.

The next experiment should test a controlled payload ladder above 65,536 bytes at the fixed, separately verified clock configuration, stopping on the first API failure, timeout, or mismatch. Record the actual SCK with a scope or logic analyzer at J55. Any clock-frequency sweep needs a deliberate, identified hardware clock configuration; do not treat a changed Linux speed request as a changed SCK.

## Reproduction and integrity

The run metrics are a direct transcription of the supplied UART output. `baremetal_sustained_runs_20261017.csv` is generated from that saved transcript and contains all 33 rows. SHA-256 digests for both files are in `SHA256SUMS_20261017`. Since the transcript does not report image or executable hashes, the artifacts are not claimed as live target hash attestation.
