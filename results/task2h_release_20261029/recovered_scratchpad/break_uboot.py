#!/usr/bin/env python3
import os,sys,termios,select,time,fcntl
PORT='/dev/ttyUSB0'; LOG='/tmp/claude-1001/-home-opentitan-msu2-verify-spi-soc-research/2ca6d9fb-76b2-4b09-878e-5e8d039d2474/scratchpad/uart_session_live.log'
f=os.open(PORT,os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK);fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
a=termios.tcgetattr(f);a[0]=a[1]=a[3]=0;a[2]=termios.CS8|termios.CREAD|termios.CLOCAL
a[4]=a[5]=termios.B115200;a[6][termios.VMIN]=a[6][termios.VTIME]=0;termios.tcsetattr(f,termios.TCSANOW,a)
log=open(LOG,'ab');buf=bytearray()
def drain(s):
 e=time.monotonic()+s
 while time.monotonic()<e:
  if select.select([f],[],[],0.02)[0]:
   try:b=os.read(f,65536)
   except BlockingIOError:continue
   if b:log.write(b);log.flush();sys.stdout.buffer.write(b);sys.stdout.flush();buf.extend(b)
print('\n>>> POWER-CYCLE THE ZCU102 NOW; I will hold it at the U-Boot prompt <<<\n',flush=True)
end=time.monotonic()+600;at=False
while time.monotonic()<end:
 try:os.write(f,b' ')
 except BlockingIOError:pass
 drain(0.2)
 if b'ZynqMP>' in buf:at=True;break
if not at:print('\n[!] no U-Boot prompt',flush=True);sys.exit(3)
# settle, send a couple newlines to get a clean prompt, probe load commands
drain(0.5)
for c in ['','help loady','help loadx','help loadb']:
 os.write(f,(c+'\r').encode());drain(0.6)
print('\n[*] holding at U-Boot prompt (board idle, not hung)',flush=True)
os.close(f)
