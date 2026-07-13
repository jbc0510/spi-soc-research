#!/usr/bin/env python3
# Creates the spi_bm_zdma application component against the existing
# spi_bm_plat platform, mirroring how spi_bm_app was structured.
# Run from repo root:
#   /tools/Xilinx/2025.1/Vitis/bin/vitis -s dma/baremetal/create_zdma_app.py
import vitis, os, shutil

WS  = "bare_metal/vitis/ws2"
SRC = "dma/baremetal/spi_benchmark_zdma.c"

client = vitis.create_client()
client.set_workspace(path=WS)

comp = client.create_app_component(
    name="spi_bm_zdma",
    platform=os.path.abspath(
        WS + "/spi_bm_plat/export/spi_bm_plat/spi_bm_plat.xpfm"),
    domain="standalone_psu_cortexa53_0",
    template="empty_application",
)

shutil.copy(SRC, WS + "/spi_bm_zdma/src/spi_benchmark_zdma.c")

comp = client.get_component(name="spi_bm_zdma")
comp.build()
