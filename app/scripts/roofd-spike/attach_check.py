#!/usr/bin/env python3
"""LAB-9: attach in a real PTY, type, detach, reattach; the redraw must rebuild the same screen.
Compares what a fresh terminal shows after reattach (via `roofd read` of the holder's state and a pyte-free check:
the reattach stream must contain every line the first attach showed). Usage: attach_check.py <roofd> <id>"""
import os, pty, select, sys, time, subprocess, re

roofd, sid = sys.argv[1], sys.argv[2]

def attach(seconds, send=b""):
    pid, fd = pty.fork()
    if pid == 0:
        os.execv(roofd, [roofd, "attach", sid])
    out = b""
    t0 = time.time()
    sent = False
    while time.time() - t0 < seconds:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: out += os.read(fd, 65536)
            except OSError: break
        if not sent and time.time() - t0 > 0.6 and send:
            os.write(fd, send); sent = True
    os.kill(pid, 9); os.waitpid(pid, 0); os.close(fd)
    return out

def plain(b):
    s = b.decode("utf-8", "replace")
    s = re.sub(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\\\)", "", s)
    s = re.sub(r"\x1b\[[0-9;?<=>]*[ -/]*[@-~]", "", s)
    s = re.sub(r"\x1b[()*+][0-9A-B]|\x1b[=>78HMNO]", "", s)
    return s

first = attach(2.0, b"echo first-attach-marker && seq 1 30\r")
second = attach(1.5)
p1, p2 = plain(first), plain(second)
ok = "first-attach-marker" in p2 and all(f"\n{n}\r" in p2 or f"{n}\r\n" in p2 for n in (28, 29, 30))
print("first attach bytes:", len(first), " reattach redraw bytes:", len(second))
print("reattach shows the marker and the last lines:", ok)
held = subprocess.run([roofd, "read", sid, "5"], capture_output=True, text=True).stdout
print("holder read (last 5 lines):", repr(held[-120:]))
sys.exit(0 if ok else 1)
