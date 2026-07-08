# PS SPI clock register verification (2026-06-04, LPS board)
- CRL_APB.SPI0_REF_CTRL (0xff5e007c) = 0x01001800 -> SRCSEL=IOPLL, DIVISOR0=24
- CRL_APB.SPI1_REF_CTRL (0xff5e0080) = 0x01001800 (identical)
- IOPLL = 1500 MHz (IOPLL_CTRL 0xff5e0020 = 0x00015A00: FBDIV=90, DIV2=1)
- SPI_REF_CLK = 1500/24 = 62.5 MHz, both controllers
- Cadence config reg (0xff040000/0xff050000) = 0x00020000 at fresh boot:
  BAUD_RATE_DIV [5:3] = 0 (driver programs at transfer time)
- Cadence SCK = SPI_REF / 2^(div+1); nearest achievable <= 1 MHz request:
  62.5/64 = 0.9766 MHz -> PS paths likely ran ~0.977 MHz, not exactly 1.000.
  This strengthens the matched-clock parity result (AXI at 0.997 was ~2% faster-clocked
  than PS and still measured ~1.6% slower).
