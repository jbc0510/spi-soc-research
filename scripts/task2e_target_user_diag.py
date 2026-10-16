#!/usr/bin/env python3
"""Read-only identity and privilege diagnostics on the target console."""
from pathlib import Path
import re
import sys
import time
import serial

ROOT=Path(__file__).resolve().parents[1]
PORT="/dev/serial/by-id/usb-Silicon_Labs_CP2108_Quad_USB_to_UART_Bridge_Controller_B66A78CB12A648B611E661AF58A7182-if00-port0"
OUT=ROOT/"results/task2e_sustainable_runner_20261016/target_user_diag.log"
PROMPT=rb"(?:root@newQspi:~#|petalinux@newQspi:~\$|newQspi:~\$)\s*$"
def readuntil(s,pat,timeout=8):
 d=bytearray(); end=time.monotonic()+timeout
 while time.monotonic()<end:
  b=s.read(4096)
  if b:
   d+=b
   if re.search(pat,d): return bytes(d)
 raise TimeoutError(bytes(d).decode("utf8","replace"))
def main():
 out=[]
 with serial.Serial(PORT,115200,timeout=.15,write_timeout=3,exclusive=True) as s:
  s.dtr=False;s.rts=False;s.write(b"\r");out.append(readuntil(s,PROMPT))
  for i,c in enumerate(["sudo -n -l 2>&1 || true", "sudo -n id 2>&1 || true", "ls -l /dev/spidev1.0 2>&1"]):
   m=f"__DIAG_{i}__";s.write((c+f"; printf '\\n{m}\\n'\r").encode())
   out.append(readuntil(s,m.encode(), timeout=5)); time.sleep(.2); out.append(s.read(s.in_waiting or 1))
 OUT.write_bytes(b"".join(out));print(OUT)
if __name__=="__main__":
 try:main()
 except Exception as e:print(f"ERROR: {e}",file=sys.stderr);sys.exit(1)
