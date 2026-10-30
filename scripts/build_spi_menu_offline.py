#!/usr/bin/env python3
"""Build the handoff menu using an existing SDT BSP; never touch boot files."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--bsp', type=Path, required=True)
    p.add_argument('--linker', type=Path, required=True)
    p.add_argument('--gcc', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    bsp, gcc, output = a.bsp.resolve(), a.gcc.resolve(), a.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    linker = output / 'lscript.ld'
    shutil.copy2(a.linker, linker)
    source = ROOT / 'bare_metal/src/spi_sustainable_benchmark_bare_axi.c'
    elf = output / 'spi_axi_bm_menu_aarch64.elf'
    cmd = [str(gcc), '-DSDT', '-O2', '-g3', '-Wall', '-Wextra',
           '-specs=' + str(bsp / 'Xilinx.spec'), '-I' + str(bsp / 'include'),
           '-I' + str(ROOT / 'common'), str(source), '-o', str(elf),
           '-Wl,-T,' + str(linker), '-Wl,-e,msu2_el2_entry',
           '-Wl,-Map,' + str(output / 'menu.map'), '-L' + str(bsp / 'lib'),
           '-Wl,--start-group', '-lxilstandalone', '-lxiltimer', '-lxil',
           '-lgcc', '-lc', '-lm', '-Wl,--end-group']
    subprocess.run(cmd, check=True)
    objdump = gcc.with_name(gcc.name.replace('gcc', 'objdump'))
    header = subprocess.check_output([str(objdump), '-f', str(elf)], text=True)
    (output / 'elf_header.txt').write_text(header)
    if 'start address 0x0000000000100940' not in header:
        raise RuntimeError('Entry changed: do not deploy with existing boot.scr. See elf_header.txt')
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    manifest = {'validation': 'BUILD_ONLY_NOT_HARDWARE_VALIDATED',
                'command': cmd, 'elf_sha256': sha(elf),
                'source_sha256': sha(source), 'linker_sha256': sha(linker),
                'bsp_libxil_sha256': sha(bsp / 'lib/libxil.a'),
                'entry': '0x00100940'}
    (output / 'build_inputs.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (output / 'SHA256SUMS').write_text(''.join(
        f'{sha(f)}  {f.name}\n' for f in sorted(output.iterdir())
        if f.is_file() and f.name != 'SHA256SUMS'))
    print(header)
    print('BUILD ONLY:', elf, sha(elf))

if __name__ == '__main__':
    main()
