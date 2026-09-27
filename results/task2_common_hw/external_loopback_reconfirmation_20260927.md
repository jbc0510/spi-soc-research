# Task 2 Common-Controller External Loopback Reconfirmation — 2026-09-27

## Result

External AXI Quad SPI loopback on J55 remains NOT VALIDATED.

## Observations

- Linux `/dev/spidev1.0` enumerated from the PL AXI Quad SPI at `0xA0000000`.
- Mode 0 and 8-bit configuration read back correctly.
- Requested SPI speed: 6,249,375 Hz.
- Physical SCK remains unmeasured.
- SPI API transfers completed successfully without API errors during the RX-verification sweep.
- 1-byte transfers passed because the first TX byte is `0x00`.
- Payloads >= 8 bytes produced repeatable RX mismatches:
  - first mismatch offset: 1
  - expected: `0x01`
  - actual: `0x00`
- Failure reproduced with the historical XSA-derived runtime bitstream.
- Failure also reproduced with `sd-images/spi_benchmark_ila.bit.bin`.
- The ILA artifact was committed after the J55 XDC and its associated XDC maps:
  - MOSI: D12 / J55-1
  - MISO: E10 / J55-2
  - SCK: F11 / J55-4
  - SS0: D11 / J55-7
- Jumper wire measured approximately 0.3 ohm end-to-end.
- Installed J55 jumper connection measured approximately 0.1 ohm.
- Therefore the repeatable RX failure is not explained by an open/bad jumper.
- Existing `results/PHASE6_EXTERNAL_LOOPBACK_FINDINGS.md` documents the same class of failure and reports J55 electrical inactivity during transfers.

## Current blocker

The current Vivado 2025.1 reproducible hardware flow includes `hardware/zcu102_spi_benchmark.xdc`, but a fresh implementation/bitstream cannot currently be produced because the available synthesis license is expired.

## Engineering conclusion

Do not use the current external-loopback runs as performance evidence. Protocol correctness must remain open until a fresh current-design bitstream is synthesized and external MOSI-to-MISO loopback is verified with zero RX mismatches.
