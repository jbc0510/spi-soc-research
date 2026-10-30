import os,termios,select,time,fcntl,hashlib
from pathlib import Path
root=Path(__file__).resolve().parent
payload=(root/'rebuilt/spi_axi_bm_menu_uart.elf.gz').read_bytes()
f=os.open('/dev/ttyUSB0',os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK);fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
a=termios.tcgetattr(f);a[0]=a[1]=a[3]=0;a[2]=termios.CS8|termios.CREAD|termios.CLOCAL;a[4]=a[5]=termios.B115200;a[6][termios.VMIN]=a[6][termios.VTIME]=0;termios.tcsetattr(f,termios.TCSANOW,a)
log=open(root/'uart_upload.log','ab')
def read_for(seconds):
 data=bytearray();end=time.monotonic()+seconds
 while time.monotonic()<end:
  if select.select([f],[],[],.01)[0]:
   try:b=os.read(f,65536)
   except BlockingIOError:continue
   log.write(b);log.flush();data.extend(b)
 return bytes(data)
def send(s):
 b=(s+'\r').encode()
 while b:
  select.select([],[f],[],1)
  try:n=os.write(f,b)
  except BlockingIOError:continue
  b=b[n:]
os.write(f,b'\r');r=read_for(1)
if b'# ' not in r:raise RuntimeError('Expected root shell: '+repr(r))
send('stty -echo');read_for(.3)
send("cat > /tmp/msu2_upload_20261029.sh <<'MSU2_UPLOAD_END'");read_for(.3)
send("{");read_for(.1)
for i in range(0,len(payload),96):
 chunk=payload[i:i+96]
 send("printf '%b' '"+''.join('\\%03o'%b for b in chunk)+"'")
 read_for(.065)
 if i%15360==0:print('Uploaded',i,'of',len(payload),flush=True)
send('} > /tmp/msu2_candidate_20261029.elf.gz');read_for(.1)
send('MSU2_UPLOAD_END');read_for(.3)
send('sh /tmp/msu2_upload_20261029.sh; gzip -dc /tmp/msu2_candidate_20261029.elf.gz > /tmp/msu2_candidate_20261029.elf; sha256sum /tmp/msu2_candidate_20261029.elf; stty echo')
r=read_for(5);print(r.decode('utf8','replace'))
expected=hashlib.sha256((root/'rebuilt/spi_axi_bm_menu_uart.elf').read_bytes()).hexdigest().encode()
if expected not in r:raise RuntimeError('Target ELF hash mismatch; not staged')
print('TARGET HASH VERIFIED',flush=True)
os.close(f)
