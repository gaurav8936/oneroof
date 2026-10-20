#!/usr/bin/env python3
"""roofd spike harness (LAB-10, T14 §5): M1–M8, headless, against a direct PTY, herdr and roofd.

  python3 spike.py <roofd binary> [M1 M2 ...]      writes results as Markdown to stdout

M3 compares the screen a terminal rebuilds from the reattach stream (`roofd vt-replay`) with the holder's own
never-detached state. M7's scroll and copy and M3's libghostty comparison need the app and are checked there (P3).
Uses ROOFD_DIR=/tmp/roofd-spike-<pid> and starts its own daemon; herdr is used only for M1 when it is running.
"""
import fcntl, json, os, pty, re, select, signal, socket, statistics, struct, subprocess, sys, termios, time

ROOFD = os.path.abspath(sys.argv[1])
WANT = set(sys.argv[2:]) or {f"M{i}" for i in range(1, 9)}
DIR = f"/tmp/roofd-spike-{os.getpid()}"
os.environ["ROOFD_DIR"] = DIR
os.environ["ROOFD_LINGER"] = "5"
ZSH = ["/bin/zsh", "-f", "-i"]
ENV = {"TERM": "xterm-256color", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin", "HOME": os.environ["HOME"],
       "PS1": "spike%% ", "LANG": "en_US.UTF-8"}
results = []


def log(m, ok, detail):
    results.append((m, "PASS" if ok is True else ("FAIL" if ok is False else ok), detail))
    print(f"{m}: {'PASS' if ok is True else ('FAIL' if ok is False else ok)}  {detail}", file=sys.stderr)


def rd(*args, check=True):
    r = subprocess.run([ROOFD, *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"roofd {' '.join(args[:2])}: {r.stderr.strip()}")
    return r.stdout


def rdj(*args):
    return json.loads(rd(*args))


def control(method, **params):
    s = socket.socket(socket.AF_UNIX)
    s.connect(f"{DIR}/roofd.sock")
    s.sendall((json.dumps({"method": method, "params": params}) + "\n").encode())
    d = b""
    while not d.endswith(b"\n"):
        c = s.recv(65536)
        if not c: break
        d += c
    s.close()
    return json.loads(d)


def create(sid, argv=ZSH, cols=120, rows=40, env=ENV):
    r = control("create", id=sid, cwd="/tmp", argv=argv, env=env, cols=cols, rows=rows)
    if "error" in r: raise RuntimeError(r["error"])
    return r


def set_winsize(fd, cols, rows):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


class Term:
    """A program running on a PTY we hold the master of (stand-in for a libghostty surface)."""

    def __init__(self, argv, cols=120, rows=40, env=None):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            if env is not None: os.execve(argv[0], argv, env)
            os.execv(argv[0], argv)
        set_winsize(self.fd, cols, rows)
        self.buf = b""

    def pump(self, timeout=0.05):
        """Bytes read (0 on a quiet timeout), or -1 once the program has gone."""
        r, _, _ = select.select([self.fd], [], [], timeout)
        if not r: return 0
        try:
            d = os.read(self.fd, 1 << 20)
        except OSError:
            return -1
        if not d: return -1
        self.buf += d
        return len(d)

    def wait_for(self, needle, timeout=5.0, start=0):
        t0 = time.time()
        while time.time() - t0 < timeout:
            if needle in self.buf[start:]: return True
            if self.pump(0.02) < 0: return needle in self.buf[start:]
        return False

    def send(self, b):
        os.write(self.fd, b)

    def kill(self, sig=signal.SIGKILL):
        try: os.kill(self.pid, sig)
        except ProcessLookupError: pass
        try: os.waitpid(self.pid, 0)
        except ChildProcessError: pass
        try: os.close(self.fd)
        except OSError: pass


def attach(sid, cols=120, rows=40):
    return Term([ROOFD, "attach", sid], cols, rows)


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(len(xs) * p / 100))]


# ---------------------------------------------------------------- M1 latency
def echo_latency(t, n=2000, settle=b"spike% "):
    t.wait_for(settle, 5)
    time.sleep(0.3)
    while t.pump(0.05) > 0: pass
    samples = []
    for i in range(n):
        ch = b"x" if i % 2 == 0 else b"\x7f"
        start = len(t.buf)
        t0 = time.perf_counter()
        t.send(ch)
        # "x" must come back as an x; a backspace is erased differently per path (BS, or a repaint), so any output.
        while time.perf_counter() - t0 < 2:
            if (b"x" in t.buf[start:]) if ch == b"x" else len(t.buf) > start: break
            if t.pump(0.5) < 0: break
        if ch == b"x": samples.append((time.perf_counter() - t0) * 1000)
        else: time.sleep(0.002)
    return samples


def herdr_shell():
    """A herdr workspace running zsh -f; returns (attach argv, workspace id) or None if herdr is not running."""
    sock = os.path.expanduser("~/.config/herdr/herdr.sock")
    def call(method, params):
        s = socket.socket(socket.AF_UNIX)
        s.connect(sock)
        s.sendall((json.dumps({"id": "spike", "method": method, "params": params}) + "\n").encode())
        d = b""
        while not d.endswith(b"\n"): d += s.recv(65536)
        return json.loads(d).get("result", {})
    try:
        r = call("workspace.create", {"cwd": "/tmp", "env": ENV, "label": "roofd-spike", "focus": False})
    except OSError:
        return None
    pane = r["root_pane"]["pane_id"]; ws = r["root_pane"].get("workspace_id")
    snap = call("session.snapshot", {})["snapshot"]
    term = next(p["terminal_id"] for p in snap["panes"] if p["pane_id"] == pane)
    herdr = "/opt/homebrew/bin/herdr"
    subprocess.run([herdr, "pane", "run", pane, "exec /bin/zsh -f -i"], capture_output=True)
    time.sleep(0.5)
    subprocess.run([herdr, "pane", "run", pane, "PS1='spike%% '"], capture_output=True)
    return [herdr, "terminal", "attach", term], (lambda: call("workspace.close", {"workspace_id": ws}))


def m1():
    rows = []
    direct = Term(ZSH, env=ENV)
    d = echo_latency(direct); direct.kill()
    rows.append(("direct PTY", d))
    h = herdr_shell()
    if h:
        argv, close = h
        ht = Term(argv)
        ht.send(b"\x0c")
        hs = echo_latency(ht, settle=b"spike")
        ht.kill(); close()
        rows.append(("herdr terminal attach", hs))
    create("m1")
    rt = attach("m1")
    r = echo_latency(rt); rt.kill()
    rows.append(("roofd attach", r))
    # Under load (T14: ProcessType trap): a busy CPU must not show up as typing latency.
    load = [subprocess.Popen(["/usr/bin/yes"], stdout=subprocess.DEVNULL) for _ in range(os.cpu_count() or 4)]
    rt = attach("m1")
    rl = echo_latency(rt, n=600); rt.kill()
    for p in load: p.kill()
    rows.append(("roofd attach, all cores busy", rl))
    detail = "; ".join(f"{name}: p50 {pct(s,50):.2f} / p95 {pct(s,95):.2f} / p99 {pct(s,99):.2f} ms" for name, s in rows)
    ok = pct(r, 95) <= pct(d, 95) + 2 and (not h or pct(r, 95) < pct(rows[1][1], 50))
    log("M1", ok, detail)


# ---------------------------------------------------------------- M2 throughput
def m2():
    """50 MB through each path, timed from sending `cat` to seeing the end marker (works for herdr's repainting
    client too, which may never show the start). Best of two runs per path."""
    big = "/tmp/roofd-spike-50mb.txt"
    if not os.path.exists(big):
        with open(big, "wb") as f:
            line = b"the quick brown fox jumps over the lazy dog 0123456789\n"
            f.write(line * (52428800 // len(line)))
    cmd = f"cat {big}; echo DONE''-MARK\r".encode()

    def timed(t, settle=b"spike% "):
        t.wait_for(settle, 5); time.sleep(0.3)
        while t.pump(0.05) > 0: pass
        tail = b""
        t0 = time.perf_counter()
        t.send(cmd)
        deadline = t0 + 240
        while time.perf_counter() < deadline:
            r, _, _ = select.select([t.fd], [], [], 1)
            if not r: continue
            try: d = os.read(t.fd, 1 << 20)
            except OSError: break
            if not d: break
            tail = (tail + d)[-64:]
            if b"DONE-MARK" in tail: return time.perf_counter() - t0
        raise RuntimeError("no end marker within 240 s")

    res = {}
    direct = Term(ZSH, env=ENV); res["direct"] = min(timed(direct), timed(direct)); direct.kill()
    create("m2")
    rt = attach("m2"); res["roofd"] = min(timed(rt), timed(rt))
    ps = subprocess.run(["ps", "-o", "rss=,time=", "-p", str(holder_pid("m2"))], capture_output=True, text=True).stdout.split()
    rt.kill(); rd("close", "m2")
    # herdr is not measured here: its client repaints the final screen instead of passing the output on
    # (5 MB of cat reaches the terminal as ~5 KB of screen updates), which is the missing-scrollback problem.
    rss_mb = int(ps[0]) / 1024 if ps else -1
    ratio = res["roofd"] / res["direct"]
    ok = ratio <= 1.5 and rss_mb <= 8 + 20 + 30
    parts = [f"{k} {v:.2f} s ({52.4/v:.0f} MB/s)" for k, v in res.items()]
    log("M2", ok, "50 MB cat, best of 2: " + ", ".join(parts) + f"; roofd {ratio:.2f}x direct"
        + (f", {res['herdr']/res['roofd']:.1f}x faster than herdr" if "herdr" in res else "")
        + f"; holder RSS {rss_mb:.0f} MB, CPU {ps[1] if len(ps) > 1 else '?'}")


def holder_pid(sid):
    """The holder is the process listening on the session's socket."""
    out = subprocess.run(["lsof", "-t", f"{DIR}/{sid}.sock"], capture_output=True, text=True).stdout.split()
    for p in out:
        args = subprocess.run(["ps", "-o", "args=", "-p", p], capture_output=True, text=True).stdout
        if "roofd session" in args: return int(p)
    return -1


# ---------------------------------------------------------------- M3 redraw fidelity
SCENES = [
    ("256 + truecolor", r"for i in {0..255}; do printf '\e[38;5;%dm%3d' $i $i; done; printf '\e[0m\n'; printf '\e[38;2;255;100;0mtruecolor\e[0m\n'"),
    ("wide + emoji", r"printf '漢字テスト 한국어 ✅🚀 e\xcc\x81\n'"),
    ("OSC 8 link", r"printf '\e]8;;https://example.com\e\\link\e]8;;\e\\\n'"),
    ("title + OSC 7", r"printf '\e]0;Spike Title\a\e]7;file://localhost/tmp\a'; echo titled"),
    ("scroll region", r"printf '\e[5;10r\e[10;1H'; for i in {1..20}; do echo region $i; done; printf '\e[r'"),
    ("bracketed paste + mouse modes", r"printf '\e[?2004h\e[?1000h\e[?1006h'; echo modes-on"),
    ("history", r"for i in {1..2000}; do echo history line $i; done"),
]


def m3():
    create("m3", cols=100, rows=30)
    a = attach("m3", 100, 30)
    a.wait_for(b"spike% ")
    problems = []
    for name, cmd in SCENES[:4]:
        a.send(cmd.encode() + b"\r"); time.sleep(0.3)
    a.kill()
    # Detached: more output, then output still arriving while the next terminal attaches.
    control("input", id="m3", text=SCENES[4][1] + "; " + SCENES[5][1] + "; " + SCENES[6][1], submit=True)
    time.sleep(0.8)
    control("input", id="m3", text="for i in {1..40}; do echo during-reattach $i; sleep 0.02; done", submit=True)
    time.sleep(0.1)
    b = attach("m3", 100, 30)
    time.sleep(2.5)
    while b.pump(0.05) > 0: pass
    stream = b.buf
    replay = json.loads(subprocess.run([ROOFD, "vt-replay", "100", "30", "1000"], input=stream, capture_output=True).stdout)
    held = rdj("info", "m3")
    held_text = control("read", id="m3", lines=1000)["text"]
    if replay["text"].rstrip() != held_text.rstrip():
        import difflib
        diff = list(difflib.unified_diff(held_text.splitlines(), replay["text"].splitlines(), lineterm="", n=0))[:8]
        problems.append("text differs: " + " | ".join(diff))
    if (replay["x"], replay["y"]) != (held["x"], held["y"]): problems.append(f"cursor {replay['x'],replay['y']} vs {held['x'],held['y']}")
    if sorted(replay["modes"]) != sorted(held["modes"]): problems.append(f"modes {replay['modes']} vs {held['modes']}")
    dupes = [l for l in replay["text"].splitlines() if l.startswith("during-reattach")]
    if len(dupes) != len(set(dupes)): problems.append("output during reattach doubled")
    if "during-reattach 40" not in replay["text"]: problems.append("output during reattach lost")
    # Alternate screen: less on a file, detach, reattach.
    control("input", id="m3", text="seq 1 500 > /tmp/m3-less.txt; less /tmp/m3-less.txt", submit=True)
    time.sleep(0.8)
    b.kill()
    c = attach("m3", 100, 30)
    time.sleep(1.0)
    while c.pump(0.05) > 0: pass
    replay2 = json.loads(subprocess.run([ROOFD, "vt-replay", "100", "30", "30"], input=c.buf, capture_output=True).stdout)
    held2 = rdj("info", "m3")
    held2_text = control("read", id="m3", lines=30)["text"]
    if not replay2["alt"] or 1049 not in replay2["modes"]: problems.append("less: not on the alternate screen after reattach")
    if replay2["text"].rstrip().splitlines()[-29:] != held2_text.rstrip().splitlines()[-29:]: problems.append("less: screen differs")
    c.send(b"q"); time.sleep(0.3); c.kill()
    rd("close", "m3")
    log("M3", not problems, "scenes: " + ", ".join(n for n, _ in SCENES) + ", less on the alternate screen, output during reattach; "
        + ("identical text (1000 lines), cursor and modes" if not problems else "; ".join(problems)))


# ---------------------------------------------------------------- M4 resize
def m4():
    create("m4")
    a = attach("m4", 120, 40)
    a.wait_for(b"spike% ")
    a.send(b"n=0; trap 'n=$((n+1))' WINCH\r"); time.sleep(0.3)
    sizes = [(80, 24), (200, 60)] * 25
    for c, r in sizes:
        set_winsize(a.fd, c, r)
        os.kill(a.pid, signal.SIGWINCH)
        time.sleep(0.02)
        a.pump(0)
    time.sleep(0.5)
    s = len(a.buf)
    a.send(b"echo SIZE $(stty size) WINCH $n\r")
    a.wait_for(b"WINCH", 3, start=s)
    time.sleep(0.2)
    while a.pump(0.05) > 0: pass
    m = re.search(rb"SIZE (\d+) (\d+) WINCH (\d+)", a.buf[s:])
    a.kill(); rd("close", "m4")
    ok = bool(m) and m.group(1) == b"60" and m.group(2) == b"200"
    log("M4", ok, f"50 resizes in ~1 s; final stty size {m.group(1).decode()}x{m.group(2).decode()} (want 60x200), shell saw {m.group(3).decode()} SIGWINCH" if m else "no answer from the shell")


# ---------------------------------------------------------------- M5 signals and job control
def m5():
    create("m5")
    a = attach("m5")
    a.wait_for(b"spike% ")
    out = {}
    def run(cmd, key, after):
        s = len(a.buf)
        a.send(cmd); time.sleep(0.5); after()
        a.send(b"echo RC-" + key + b"=$?\r")
        ok = a.wait_for(b"RC-" + key + b"=", 3, start=s)
        time.sleep(0.1); a.pump(0.05)
        m = re.search(b"RC-" + key + rb"=(\d+)", a.buf[s:])
        out[key.decode()] = m.group(1).decode() if m else "none"
    run(b"sleep 100\r", b"ctrlc", lambda: a.send(b"\x03"))
    s = len(a.buf)
    a.send(b"sleep 100\r"); time.sleep(0.5); a.send(b"\x1a")
    suspended = a.wait_for(b"suspended", 2, start=s)
    a.send(b"fg\r"); time.sleep(0.4); a.send(b"\x03")
    a.send(b"echo RC-fg=$?\r"); a.wait_for(b"RC-fg=", 3, start=s)
    for sig, name in ((2, "SIGINT"), (15, "SIGTERM"), (1, "SIGHUP")):
        run(b"sleep 100\r", name.encode(), lambda sig=sig: control("signal", id="m5", signal=sig))
    a.kill(); rd("close", "m5")
    ok = out.get("ctrlc") == "130" and suspended and out.get("SIGINT") == "130" and out.get("SIGTERM") == "143" and out.get("SIGHUP") == "129"
    log("M5", ok, f"Ctrl-C rc {out.get('ctrlc')}; Ctrl-Z suspended {suspended}, fg resumed; signal SIGINT rc {out.get('SIGINT')}, SIGTERM {out.get('SIGTERM')}, SIGHUP {out.get('SIGHUP')}")


# ---------------------------------------------------------------- M6 crash recovery
def m6(daemon):
    create("m6a"); create("m6b")
    a = attach("m6a"); a.wait_for(b"spike% ")
    notes, ok = [], True
    # Daemon killed: attached terminal keeps working, holders keep running, a new daemon lists both.
    daemon.kill(); daemon.wait()
    s = len(a.buf); a.send(b"echo after-daemon-kill\r")
    alive = a.wait_for(b"after-daemon-kill\r\n", 2, start=s)
    new = start_daemon()
    listed = sorted(x["id"] for x in control("list")["sessions"] if x["id"].startswith("m6") and "exited" not in x)
    notes.append(f"daemon kill -9: attach alive {alive}, new daemon lists {listed}")
    ok &= alive and listed == ["m6a", "m6b"]
    # Attach client killed: session unaffected, reattach redraws.
    a.kill()
    control("input", id="m6a", text="echo while-detached", submit=True); time.sleep(0.3)
    b = attach("m6a"); redrawn = b.wait_for(b"while-detached", 2); b.kill()
    notes.append(f"attach kill -9: reattach redraw has detached output {redrawn}")
    ok &= redrawn
    # Holder killed: only that session ends.
    hp = holder_pid("m6b"); os.kill(hp, signal.SIGKILL); time.sleep(0.5)
    listed = sorted(x["id"] for x in control("list")["sessions"] if x["id"].startswith("m6") and "exited" not in x)
    notes.append(f"holder kill -9: list now {listed}")
    ok &= listed == ["m6a"]
    rd("close", "m6a")
    log("M6", ok if ok else False, "; ".join(notes) + "; app quit/reopen and reinstall are checked in P3/P4 (need the app and launchd)")
    return new


# ---------------------------------------------------------------- M7 prompt marks (pass-through)
def m7():
    create("m7")
    a = attach("m7"); a.wait_for(b"spike% ")
    s = len(a.buf)
    a.send(rb"printf '\e]133;A\a\e]133;B\a\e]133;C\a\e]133;D;0\a'; echo marks-sent" + b"\r")
    a.wait_for(b"marks-sent\r\n", 2, start=s); time.sleep(0.1); a.pump(0.05)
    marks = len(re.findall(rb"\x1b\]133;[ABCD]", a.buf[s:]))
    a.kill(); rd("close", "m7")
    log("M7", marks == 4, f"{marks} of 4 OSC 133 marks reach the terminal unchanged; trackpad scroll and plain drag-copy are checked in the app (P3)")


# ---------------------------------------------------------------- M8 queries while detached
def m8():
    create("m8")
    time.sleep(1.0)
    script = ("zmodload zsh/datetime; t0=$EPOCHREALTIME; printf '\\e[6n'; read -rs -d R r; t1=$EPOCHREALTIME; "
              "printf '\\e[c'; read -rs -d c d; t2=$EPOCHREALTIME; "
              "echo Q-DSR $(( (t1-t0)*1000 )) Q-DA $(( (t2-t1)*1000 )) Q-END")
    control("input", id="m8", text=script, submit=True)
    t0 = time.time(); text = ""
    while time.time() - t0 < 5:
        text = control("read", id="m8", lines=5)["text"]
        if re.search(r"Q-DSR [\d.]+ Q-DA [\d.]+ Q-END", text): break
        time.sleep(0.1)
    m = re.search(r"Q-DSR ([\d.]+) Q-DA ([\d.]+) Q-END", text)
    rd("close", "m8")
    ok = bool(m) and float(m.group(1)) <= 50 and float(m.group(2)) <= 50
    log("M8", ok, f"no terminal attached: cursor-position reply in {float(m.group(1)):.1f} ms, DA1 in {float(m.group(2)):.1f} ms" if m else "no reply: the shell hung")


def start_daemon():
    p = subprocess.Popen([ROOFD, "daemon"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        if os.path.exists(f"{DIR}/roofd.sock"):
            try:
                control("hello"); return p
            except OSError:
                pass
        time.sleep(0.05)
    raise RuntimeError("daemon did not start")


def main():
    os.makedirs(DIR, exist_ok=True)
    daemon = start_daemon()
    try:
        for m in sorted(WANT):
            try:
                if m == "M6": daemon = m6(daemon)
                else: globals()[m.lower()]()
            except Exception as e:
                log(m, False, f"harness error: {e}")
    finally:
        for s in control("list").get("sessions", []): control("close", id=s["id"])
        daemon.kill()
        subprocess.run(["pkill", "-f", f"ROOFD_DIR={DIR}"], capture_output=True)
    print("| # | Result | Detail |\n|---|---|---|")
    for m, r, d in results: print(f"| {m} | {r} | {d} |")


main()
