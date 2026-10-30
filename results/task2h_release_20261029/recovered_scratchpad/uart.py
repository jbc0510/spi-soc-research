#!/usr/bin/env python3
"""Minimal scripted UART driver for the ZCU102 console on /dev/ttyUSB0.

Usage:
  uart.py read SECONDS                 # just drain and print for SECONDS
  uart.py cmd SECONDS -- "cmd1" "cmd2" # send each cmd (CR), read SECONDS after each
Everything is mirrored to results/task2h_boot_handoff_20261029/uart_session.log
"""
import os, sys, termios, select, time, fcntl

PORT = '/dev/ttyUSB0'
LOG = '/tmp/claude-1001/-home-opentitan-msu2-verify-spi-soc-research/2ca6d9fb-76b2-4b09-878e-5e8d039d2474/scratchpad/uart_session_live.log'

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

def read_for(f, seconds, log):
    data = bytearray()
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if select.select([f], [], [], 0.02)[0]:
            try:
                b = os.read(f, 65536)
            except BlockingIOError:
                continue
            if b:
                log.write(b); log.flush()
                data.extend(b)
    return bytes(data)

def send(f, s):
    b = (s + '\r').encode()
    while b:
        select.select([], [f], [], 1)
        try:
            n = os.write(f, b)
        except BlockingIOError:
            continue
        b = b[n:]

def main():
    mode = sys.argv[1]
    f = open_port()
    log = open(LOG, 'ab')
    try:
        if mode == 'read':
            out = read_for(f, float(sys.argv[2]), log)
            sys.stdout.buffer.write(out)
        elif mode == 'cmd':
            secs = float(sys.argv[2])
            cmds = sys.argv[sys.argv.index('--') + 1:]
            # settle / show current prompt
            send(f, '')
            sys.stdout.buffer.write(read_for(f, 1, log))
            for c in cmds:
                send(f, c)
                out = read_for(f, secs, log)
                sys.stdout.buffer.write(b'\n==> ' + c.encode() + b'\n')
                sys.stdout.buffer.write(out)
        sys.stdout.flush()
    finally:
        os.close(f)

if __name__ == '__main__':
    main()
