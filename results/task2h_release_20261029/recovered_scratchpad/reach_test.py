#!/usr/bin/env python3
"""Reboot the ZCU102, break into U-Boot, poke a reach-test stub at 0x00100980,
and `go` to it. RAM-only; writes nothing to the SD card."""
import os, sys, termios, select, time, fcntl

PORT = '/dev/ttyUSB0'
LOG = '/tmp/claude-1001/-home-opentitan-msu2-verify-spi-soc-research/2ca6d9fb-76b2-4b09-878e-5e8d039d2474/scratchpad/uart_session_live.log'
MW = ("mw.l 00100980 d2bfe001;mw.l 00100984 10000102;mw.l 00100988 d2800203;"
      "mw.l 0010098c 38401440;mw.l 00100990 3900c020;mw.l 00100994 f1000463;"
      "mw.l 00100998 54ffffa1;mw.l 0010099c d503205f;mw.l 001009a0 17ffffff;"
      "mw.l 001009a4 534d0a0d;mw.l 001009a8 472d3255;mw.l 001009ac 45522d4f;"
      "mw.l 001009b0 0d484341;mw.l 001009b4 0000000a")

def open_port():
    f = os.open(PORT, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    a = termios.tcgetattr(f)
    a[0] = a[1] = a[3] = 0
    a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    a[4] = a[5] = termios.B115200
    a[6][termios.VMIN] = a[6][termios.VTIME] = 0
    termios.tcsetattr(f, termios.TCSANOW, a)
    return f

def main():
    f = open_port(); log = open(LOG, 'ab')
    buf = bytearray()
    def drain(secs):
        end = time.monotonic() + secs
        while time.monotonic() < end:
            if select.select([f], [], [], 0.02)[0]:
                try: b = os.read(f, 65536)
                except BlockingIOError: continue
                if b:
                    log.write(b); log.flush()
                    sys.stdout.buffer.write(b); sys.stdout.flush()
                    buf.extend(b)
    def send(s):
        b = (s + '\r').encode()
        while b:
            select.select([], [f], [], 1)
            try: n = os.write(f, b)
            except BlockingIOError: continue
            b = b[n:]

    # 1) confirm Linux shell
    send(''); drain(1.5)
    if b'#' not in buf[-40:] and b'$' not in buf[-40:]:
        print('\n[!] no shell prompt; aborting', flush=True); os.close(f); return 2
    # 2) reboot
    print('\n[*] sending reboot', flush=True)
    buf.clear(); send('reboot');
    # 3) spam a key to break autoboot; watch for U-Boot prompt
    print('[*] waiting for U-Boot, spamming break key', flush=True)
    end = time.monotonic() + 75
    at_uboot = False
    while time.monotonic() < end:
        # tap space (harmless at prompt, interrupts autoboot)
        try: os.write(f, b' ')
        except BlockingIOError: pass
        drain(0.2)
        if b'ZynqMP>' in buf:
            at_uboot = True; break
    if not at_uboot:
        print('\n[!] never reached U-Boot prompt', flush=True); os.close(f); return 3
    drain(0.5)
    # 4) poke stub + go
    print('\n[*] poking reach-test stub via mw.l', flush=True)
    send(MW); drain(1.5)
    print('\n[*] verifying first words at 0x00100980', flush=True)
    send('md.l 00100980 4'); drain(1.0)
    print('\n[*] GO 0x00100980  (expect "MSU2-GO-REACH" then hang on success)', flush=True)
    buf.clear(); send('go 00100980'); drain(8.0)
    reached = b'MSU2-GO-REACH' in buf
    aborted = b'Synchronous Abort' in buf or b'Please RESET' in buf
    print('\n\n==== RESULT ====', flush=True)
    print('marker seen :', reached, flush=True)
    print('abort seen  :', aborted, flush=True)
    os.close(f)
    return 0

if __name__ == '__main__':
    sys.exit(main())
