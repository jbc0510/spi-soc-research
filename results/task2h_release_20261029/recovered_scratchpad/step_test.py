#!/usr/bin/env python3
"""Wait for a board reset, break into U-Boot, load the real ELF (for its MMU table),
then run the staged step-test stub at 0x02000000. RAM-only; no SD writes.
Markers A..E localize the faulting boot.S init instruction."""
import os, sys, termios, select, time, fcntl

PORT = '/dev/ttyUSB0'
LOG = '/tmp/claude-1001/-home-opentitan-msu2-verify-spi-soc-research/2ca6d9fb-76b2-4b09-878e-5e8d039d2474/scratchpad/uart_session_live.log'
MW = ("mw.l 02000000 d2bfe001;mw.l 02000004 52800820;mw.l 02000008 3940b022;mw.l 0200000c 3727ffe2;"
      "mw.l 02000010 3900c020;mw.l 02000014 d53b9c05;mw.l 02000018 52800840;mw.l 0200001c 3940b022;"
      "mw.l 02000020 3727ffe2;mw.l 02000024 3900c020;mw.l 02000028 b24000a5;mw.l 0200002c d51b9c05;"
      "mw.l 02000030 52800860;mw.l 02000034 3940b022;mw.l 02000038 3727ffe2;mw.l 0200003c 3900c020;"
      "mw.l 02000040 58000442;mw.l 02000044 d5182002;mw.l 02000048 58000442;mw.l 0200004c d518a202;"
      "mw.l 02000050 58000442;mw.l 02000054 d5182042;mw.l 02000058 d5033fdf;mw.l 0200005c 52800880;"
      "mw.l 02000060 3940b022;mw.l 02000064 3727ffe2;mw.l 02000068 3900c020;mw.l 0200006c d2800002;"
      "mw.l 02000070 b26e0042;mw.l 02000074 b26f0042;mw.l 02000078 b27b0042;mw.l 0200007c b2740042;"
      "mw.l 02000080 b27e0042;mw.l 02000084 b2400042;mw.l 02000088 d5181002;mw.l 0200008c d5033fdf;"
      "mw.l 02000090 528008a0;mw.l 02000094 3940b022;mw.l 02000098 3727ffe2;mw.l 0200009c 3900c020;"
      "mw.l 020000a0 528001a0;mw.l 020000a4 3940b022;mw.l 020000a8 3727ffe2;mw.l 020000ac 3900c020;"
      "mw.l 020000b0 52800140;mw.l 020000b4 3940b022;mw.l 020000b8 3727ffe2;mw.l 020000bc 3900c020;"
      "mw.l 020000c0 d503205f;mw.l 020000c4 17ffffff;mw.l 020000c8 00117000;mw.l 020000cc 00000000;"
      "mw.l 020000d0 0400ff44;mw.l 020000d4 000000bb;mw.l 020000d8 85800518;mw.l 020000dc 00000002")

def open_port():
    f = os.open(PORT, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    a = termios.tcgetattr(f)
    a[0]=a[1]=a[3]=0; a[2]=termios.CS8|termios.CREAD|termios.CLOCAL
    a[4]=a[5]=termios.B115200; a[6][termios.VMIN]=a[6][termios.VTIME]=0
    termios.tcsetattr(f, termios.TCSANOW, a); return f

def main():
    f=open_port(); log=open(LOG,'ab'); buf=bytearray()
    def drain(secs):
        end=time.monotonic()+secs
        while time.monotonic()<end:
            if select.select([f],[],[],0.02)[0]:
                try:b=os.read(f,65536)
                except BlockingIOError:continue
                if b: log.write(b);log.flush();sys.stdout.buffer.write(b);sys.stdout.flush();buf.extend(b)
    def send(s):
        b=(s+'\r').encode()
        while b:
            select.select([],[f],[],1)
            try:n=os.write(f,b)
            except BlockingIOError:continue
            b=b[n:]
    print('\n>>> TAP THE RESET BUTTON ON THE ZCU102 NOW (waiting up to 10 min) <<<\n', flush=True)
    end=time.monotonic()+600; at=False
    while time.monotonic()<end:
        try:os.write(f,b' ')
        except BlockingIOError:pass
        drain(0.2)
        if b'ZynqMP>' in buf: at=True; break
    if not at:
        print('\n[!] no U-Boot prompt seen', flush=True); os.close(f); return 3
    drain(0.5)
    print('\n[*] loading real ELF (for MMU table @0x117000)', flush=True)
    send('fatload mmc 0:1 08000000 msu2_demo/spi_axi_bm_menu_aarch64.elf'); drain(2)
    send('setenv autostart no'); drain(0.4)
    send('bootelf -p 08000000'); drain(1.5)
    print('\n[*] poking step-test stub at 0x02000000', flush=True)
    send(MW); drain(2)
    send('md.l 02000000 4'); drain(1)
    print('\n[*] GO 0x02000000  (markers A..E; last letter = fault point)', flush=True)
    buf.clear(); send('go 02000000'); drain(8)
    txt=bytes(buf)
    marks=[c for c in b'ABCDE' if bytes([c]) in txt]
    print('\n\n==== RESULT ====', flush=True)
    print('markers seen :', bytes(marks).decode() or '(none)', flush=True)
    print('abort seen   :', b'Synchronous Abort' in txt or b'Please RESET' in txt, flush=True)
    os.close(f); return 0

if __name__=='__main__':
    sys.exit(main())
