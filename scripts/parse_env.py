import binascii, sys, os
for p in sys.argv[1:]:
    b = open(p,'rb').read()
    stored   = int.from_bytes(b[0:4],'little')
    c_noflag = binascii.crc32(b[4:]) & 0xffffffff
    c_flag   = binascii.crc32(b[5:]) & 0xffffffff
    n = os.path.basename(p)
    print(n)
    print("  size           %d" % len(b))
    print("  stored crc32   0x%08x" % stored)
    print("  crc over [4:]  0x%08x  %s" % (c_noflag, "MATCH" if c_noflag==stored else "no"))
    print("  crc over [5:]  0x%08x  %s" % (c_flag,   "MATCH" if c_flag==stored   else "no"))
    print("  byte[4]        0x%02x" % b[4])
    off = 5 if c_flag==stored else (4 if c_noflag==stored else None)
    if off is None:
        print("  NO LAYOUT MATCHED - vars not parsed")
        continue
    data = b[off:]
    e = data.find(b'\x00\x00')
    body = data if e < 0 else data[:e]
    v = [x.decode('utf-8','replace') for x in body.split(b'\x00') if x]
    print("  data offset    %d" % off)
    print("  vars           %d" % len(v))
    open('/tmp/vars_'+n+'.txt','w').write("\n".join(sorted(v))+"\n")
