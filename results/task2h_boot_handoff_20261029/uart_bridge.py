import os,sys,termios,select,fcntl
f=os.open('/dev/ttyUSB0',os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK)
fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
a=termios.tcgetattr(f); a[0]=a[1]=a[3]=0;a[2]=termios.CS8|termios.CREAD|termios.CLOCAL;a[4]=a[5]=termios.B115200;a[6][termios.VMIN]=a[6][termios.VTIME]=0
termios.tcsetattr(f,termios.TCSANOW,a)
log=open('results/task2h_boot_handoff_20261029/uart_session.log','ab')
print('UART ready',flush=True)
while True:
 for r in select.select([f,sys.stdin],[],[],1)[0]:
  if r==f:
   try:b=os.read(f,65536)
   except BlockingIOError:continue
   log.write(b);log.flush();sys.stdout.buffer.write(b);sys.stdout.flush()
  else:
   line=sys.stdin.readline()
   if not line:sys.exit()
   os.write(f,line.rstrip('\n').encode()+b'\r')
