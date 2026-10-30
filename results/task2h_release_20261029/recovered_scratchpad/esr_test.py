#!/usr/bin/env python3
import os,sys,termios,select,time,fcntl
PORT='/dev/ttyUSB0'
LOG='/tmp/claude-1001/-home-opentitan-msu2-verify-spi-soc-research/2ca6d9fb-76b2-4b09-878e-5e8d039d2474/scratchpad/uart_session_live.log'
MW=open('/tmp/claude-1001/-home-opentitan-msu2-verify-spi-soc-research/2ca6d9fb-76b2-4b09-878e-5e8d039d2474/scratchpad/esr_mw.txt').read().strip()
def op():
 f=os.open(PORT,os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK);fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
 a=termios.tcgetattr(f);a[0]=a[1]=a[3]=0;a[2]=termios.CS8|termios.CREAD|termios.CLOCAL
 a[4]=a[5]=termios.B115200;a[6][termios.VMIN]=a[6][termios.VTIME]=0;termios.tcsetattr(f,termios.TCSANOW,a);return f
f=op();log=open(LOG,'ab');buf=bytearray()
def drain(s):
 e=time.monotonic()+s
 while time.monotonic()<e:
  if select.select([f],[],[],0.02)[0]:
   try:b=os.read(f,65536)
   except BlockingIOError:continue
   if b:log.write(b);log.flush();sys.stdout.buffer.write(b);sys.stdout.flush();buf.extend(b)
def send(x):
 b=(x+'\r').encode()
 while b:
  select.select([],[f],[],1)
  try:n=os.write(f,b)
  except BlockingIOError:continue
  b=b[n:]
print('\n>>> POWER-CYCLE / RESET THE ZCU102 NOW (up to 10 min) <<<\n',flush=True)
end=time.monotonic()+600;at=False
while time.monotonic()<end:
 try:os.write(f,b' ')
 except BlockingIOError:pass
 drain(0.2)
 if b'ZynqMP>' in buf:at=True;break
if not at:print('\n[!] no U-Boot prompt',flush=True);sys.exit(3)
drain(0.5)
print('\n[*] load ELF for MMU table',flush=True)
send('fatload mmc 0:1 08000000 msu2_demo/spi_axi_bm_menu_aarch64.elf');drain(2)
send('setenv autostart no');drain(0.4);send('bootelf -p 08000000');drain(1.5)
print('\n[*] poke ESR-capture stub',flush=True)
send(MW);drain(2.5)
send('md.l 02002000 1; md.l 02002200 1');drain(1)
print('\n[*] GO 0x02000000 (expect A D then > ESR/FAR, then PSCI reset to Linux)',flush=True)
buf.clear();send('go 02000000');drain(10)
print('\n\n==== RESULT (tail) ====',flush=True)
sys.stdout.buffer.write(bytes(buf)[-400:]);print(flush=True)
os.close(f)
