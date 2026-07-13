#!/usr/bin/env python3
# Incremental rebuild of spi_bm_zdma. Run from repo root:
#   /tools/Xilinx/2025.1/Vitis/bin/vitis -s dma/baremetal/build_zdma_app.py
import vitis
client = vitis.create_client()
client.set_workspace(path="bare_metal/vitis/ws2")
comp = client.get_component(name="spi_bm_zdma")
comp.build()
