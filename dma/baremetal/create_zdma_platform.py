#!/usr/bin/env python3
# Creates the spi_bm_plat platform component from the tracked hardware handoff
# (hardware/xsa/spi_benchmark_wrapper.xsa). This is the FIRST step on a fresh
# machine, before create_zdma_app.py -- the workspace (bare_metal/vitis/) is
# gitignored and does not exist on a new clone, so the platform must be built
# from the committed .xsa.
#
# Creates the platform, adds a standalone a53 domain, then builds. Mirrors the
# Vitis 2025.1 shipped example
# Vitis/cli/examples/embedded/create_platform_add_domain_build.py
#
# UNTESTED as of 2026-08-20: the add_domain() form was written on 2026-07-15
# against a broken Vitis install (see f3633cb, e0b5e78) and has never been run
# to completion. Verify against a working install before trusting it.
# Run from repo root:  vitis -s dma/baremetal/create_zdma_platform.py
import vitis, os

WS  = "bare_metal/vitis/ws2"
XSA = os.path.abspath("hardware/xsa/spi_benchmark_wrapper.xsa")

client = vitis.create_client()
client.set_workspace(path=WS)

platform = client.create_platform_component(
    name="spi_bm_plat",
    hw_design=XSA,
    os="standalone",
    cpu="psu_cortexa53_0",
)

domain = platform.add_domain(
    cpu="psu_cortexa53_0",
    os="standalone",
    name="standalone_psu_cortexa53_0",
    display_name="standalone_psu_cortexa53_0",
)

status = platform.build()
