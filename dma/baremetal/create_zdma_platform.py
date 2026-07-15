#!/usr/bin/env python3
# Creates the spi_bm_plat platform component from the tracked hardware handoff
# (hardware/xsa/spi_benchmark_wrapper.xsa). This is the FIRST step on a fresh
# machine, before create_zdma_app.py — the workspace (bare_metal/vitis/) is
# gitignored and does not exist on a new clone, so the platform must be built
# from the committed .xsa.
# Run from repo root:  vitis -s dma/baremetal/create_zdma_platform.py
import vitis, os

WS  = "bare_metal/vitis/ws2"
XSA = os.path.abspath("hardware/xsa/spi_benchmark_wrapper.xsa")

client = vitis.create_client()
client.set_workspace(path=WS)

plat = client.create_platform_component(
    name="spi_bm_plat",
    hw_design=XSA,
    os="standalone",
    cpu="psu_cortexa53_0",
    domain_name="standalone_psu_cortexa53_0",
)

plat = client.get_component(name="spi_bm_plat")
plat.build()
