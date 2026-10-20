#!/usr/bin/env python3
"""LAB-16 (small run, owner 2026-10-20): the same short tasks per agent on herdr and on roofd, status timelines compared.

  python3 side_by_side.py <roofd binary> [agents...]        default: claude codex gemini kimi agy

Tasks: A = a plain reply, no tools (working → done/idle); B = a shell command that needs permission (blocked), which
the harness declines with Esc, so nothing runs. Each run happens in its own scratch git folder under
~/Projects/labs/labs-data/oneroof/side-by-side/ (inside ~/Projects: rule zero). A first-run folder-trust prompt in that
scratch folder is accepted with Enter. Writes a Markdown report to stdout; per-sample timelines to the log dir.
"""
import json, os, socket, subprocess, sys, threading, time

ROOFD = os.path.abspath(sys.argv[1])
AGENTS = sys.argv[2:] or ["claude", "codex", "gemini", "kimi", "agy"]
HERDR = "/opt/homebrew/bin/herdr"
HERDR_SOCK = os.path.expanduser("~/.config/herdr/herdr.sock")
RDIR = "/tmp/roofd-sbs"
SCRATCH = os.path.expanduser("~/Projects/labs/labs-data/oneroof/side-by-side")
LOGS = os.path.join(SCRATCH, "logs")
ACCOUNT_VARS = ["CLAUDE_CONFIG_DIR", "CODEX_HOME", "KIMI_HOME", "GEMINI_HOME"]
TASKS = {
    "A": "Reply with exactly the text SBS-OK and nothing else. Do not use any tools.",
    "B": "Use your shell tool to run exactly this command, nothing else: touch sbs-marker.txt",
}


def base_env():
    env = {k: v for k, v in os.environ.items() if k not in ACCOUNT_VARS and not k.startswith(("ONEROOF_", "ROOFD_", "CLAUDE_CODE")) and k != "CLAUDECODE"}
    env["TERM"] = "xterm-256color"
    return env


def jcall(path, req, timeout=15):
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(timeout)
    s.connect(path)
    s.sendall((json.dumps(req) + "\n").encode())
    d = b""
    while not d.endswith(b"\n"):
        c = s.recv(65536)
        if not c: break
        d += c
    s.close()
    return json.loads(d)


class Herdr:
    name = "herdr"

    def __init__(self, agent, task, cwd):
        self.agent, self.cwd = agent, cwd
        self.id = f"sbs-{agent[:6]}-{task.lower()}-{int(time.time()) % 100000}"
        r = self.call("workspace.create", {"cwd": cwd, "env": base_env(), "label": self.id, "focus": False})
        self.pane = r["root_pane"]["pane_id"]
        self.ws = r["root_pane"].get("workspace_id")
        for _ in range(40):
            try:
                self.call("agent.start", {"name": self.id, "kind": agent, "pane_id": self.pane, "args": [], "timeout_ms": 60000}, 70)
                break
            except RuntimeError as e:
                if "agent_not_ready" in str(e): break
                if "agent_pane_busy" in str(e): time.sleep(0.5); continue
                raise

    def call(self, method, params, timeout=15):
        r = jcall(HERDR_SOCK, {"id": "sbs", "method": method, "params": params}, timeout)
        if "error" in r: raise RuntimeError(f"{r['error'].get('code')}: {r['error'].get('message')}")
        return r.get("result", {})

    def state(self):
        snap = self.call("session.snapshot", {})["snapshot"]
        a = next((x for x in snap.get("agents", []) if x.get("name") == self.id), None)
        if not a: return ("exited", False)
        return (a.get("agent_status") or "unknown", bool(a.get("interactive_ready")))

    def submit(self, text): self.call("agent.prompt", {"target": self.id, "text": text})
    def enter(self): subprocess.run([HERDR, "pane", "send-keys", self.pane, "enter"], capture_output=True)
    def esc(self): subprocess.run([HERDR, "pane", "send-keys", self.pane, "esc"], capture_output=True)
    def keys(self, seq): subprocess.run([HERDR, "pane", "send-keys", self.pane, {"\x1b[B": "down", "\x1b[A": "up"}[seq]], capture_output=True)
    def screen(self): return subprocess.run([HERDR, "pane", "read", self.pane, "--source", "recent", "--lines", "30"], capture_output=True, text=True).stdout
    def close(self):
        try: self.call("workspace.close", {"workspace_id": self.ws})
        except Exception: pass


class Roofd:
    name = "roofd"

    def __init__(self, agent, task, cwd):
        self.id = f"sbs-{agent[:6]}-{task.lower()}-{int(time.time()) % 100000}"
        r = jcall(RDIR + "/roofd.sock", {"method": "create", "params": {
            "id": self.id, "label": self.id, "cwd": cwd, "env": base_env(), "kind": agent, "cols": 120, "rows": 40,
            "argv": ["/bin/zsh", "-l", "-i", "-c", f"{agent}; exec /bin/zsh -l -i"]}})
        if "error" in r: raise RuntimeError(r["error"])

    def call(self, method, **p):
        r = jcall(RDIR + "/roofd.sock", {"method": method, "params": {"id": self.id, **p}})
        if "error" in r: raise RuntimeError(r["error"])
        return r

    def state(self):
        i = self.call("info")
        if "exited" in i: return ("exited", False)
        return (i.get("status") or "unknown", bool(i.get("ready")))

    def submit(self, text):
        self.call("input", text=text); time.sleep(0.15); self.call("input", text="\r")

    def enter(self): self.call("input", text="\r")
    def esc(self): self.call("input", text="\x1b")
    def keys(self, seq): self.call("input", text=seq)
    def screen(self): return self.call("read", lines=30).get("text", "")
    def close(self):
        try: self.call("close")
        except Exception: pass


def pick_startup_option(screen):
    """Which menu line to move to for a first-run screen in the scratch folder, and how many lines down it is from the
    selected one. Prefers keeping approvals on (Codex) and trusting only this folder."""
    lines = [l.strip(" │") for l in screen.splitlines() if l.strip(" │")]
    opts = [i for i, l in enumerate(lines) if l.lstrip().startswith(("❯", "›", ">", "●", "○")) or l.lstrip()[:3].rstrip(".").isdigit()
            or (i > 0 and lines[i - 1].lstrip().startswith(("❯", "›")) and not l.lower().startswith(("enter", "esc")))]
    sel = next((i for i in opts if lines[i].lstrip().startswith(("❯", "›", "●"))), opts[0] if opts else None)
    def score(l):
        l = l.lower()
        if "no, exit" in l or "don't trust" in l or "do not trust" in l or l.endswith("quit"): return -9
        if "ask me" in l or "approve edits" in l: return 9            # keep permission prompts on
        if "trust this folder" in l or "trust folder" in l or "yes, proceed" in l: return 5
        if "parent" in l: return -1
        if l.startswith(("yes", "1.", "› 1", "❯ 1")): return 3
        return 0
    if sel is None: return 0
    best = max(opts, key=lambda i: score(lines[i]))
    return opts.index(best) - opts.index(sel)


def norm(s):
    return {"working": "working", "blocked": "blocked", "done": "done", "idle": "idle"}.get(s, s)


def run(rt_cls, agent, task, out):
    cwd = os.path.join(SCRATCH, f"{agent}-{rt_cls.name}")
    os.makedirs(cwd, exist_ok=True)
    if not os.path.isdir(os.path.join(cwd, ".git")):
        subprocess.run(["git", "init", "-q", cwd]); open(os.path.join(cwd, "README.md"), "w").write("side-by-side scratch\n")
    try: os.remove(os.path.join(cwd, "sbs-marker.txt"))
    except FileNotFoundError: pass
    res = {"timeline": [], "notes": []}
    t0 = time.time()
    try:
        rt = rt_cls(agent, task, cwd)
    except Exception as e:
        res["notes"].append(f"start failed: {e}"); out[rt_cls.name] = res; return
    def sample():
        try: st, ready = rt.state()
        except Exception as e: st, ready = (f"error", False)
        res["timeline"].append((round(time.time() - t0, 1), norm(st), ready))
        return norm(st), ready
    try:
        # 1. Ready (accept a first-run trust prompt in the scratch folder).
        trust = 0
        ready_at = None
        while time.time() - t0 < 120:
            st, ready = sample()
            if st == "blocked" and trust < 3:
                trust += 1
                scr = rt.screen()
                if "esc to reject" in scr.lower():            # e.g. "new MCP servers found": enable none
                    rt.esc(); res["notes"].append("start-up menu rejected with Esc (MCP servers)"); time.sleep(3); continue
                moves = pick_startup_option(scr)
                for _ in range(abs(moves)): rt.keys("\x1b[B" if moves > 0 else "\x1b[A"); time.sleep(0.15)
                rt.enter()
                res["notes"].append(f"start-up menu answered ({moves:+d} lines): {[l.strip() for l in scr.splitlines() if l.strip()][-6:][:2]}")
                time.sleep(3); continue
            if ready and st in ("idle", "done"):
                ready_at = time.time(); break
            if st == "exited": break
            time.sleep(0.5)
        if ready_at is None:
            res["notes"].append("never became ready"); return
        res["ready_s"] = round(ready_at - t0, 1)
        time.sleep(2)
        if "esc to reject" in rt.screen().lower():   # a menu the runtime read as idle (herdr): clear it first
            rt.esc(); res["notes"].append("MCP menu cleared before the task"); time.sleep(2)
        # 2. The task.
        sent = time.time(); rt.submit(TASKS[task])
        saw_work = saw_block = declined = False
        quiet_since = None
        while time.time() - sent < 150:
            st, _ = sample()
            if st == "working": saw_work = True; quiet_since = None
            if st == "blocked":
                saw_block = True
                if task == "B" and not declined:
                    time.sleep(1); rt.esc(); declined = True; res["notes"].append(f"declined the prompt at {round(time.time()-t0,1)} s")
                quiet_since = None
            if st in ("idle", "done") and (saw_work or saw_block):
                quiet_since = quiet_since or time.time()
                if time.time() - quiet_since >= 4: break
            if st == "exited": res["notes"].append("agent exited"); break
            time.sleep(0.5)
        res.update(saw_work=saw_work, saw_block=saw_block, took=round(time.time() - sent, 1))
        res["marker_created"] = os.path.exists(os.path.join(cwd, "sbs-marker.txt"))
        res["screen_tail"] = rt.screen()[-400:]
    finally:
        rt.close()
        out[rt_cls.name] = res


def phases(timeline):
    """Distinct statuses in order, dropping runs shorter than 1 s."""
    seq, cur, start = [], None, 0
    for t, s, _ in timeline:
        if s != cur:
            if cur is not None and t - start >= 1.0: seq.append(cur)
            cur, start = s, t
    if cur is not None: seq.append(cur)
    out = []
    for s in seq:
        if not out or out[-1] != s: out.append(s)
    return out


def main():
    os.makedirs(LOGS, exist_ok=True)
    os.makedirs(RDIR, exist_ok=True)
    os.environ["ROOFD_DIR"] = RDIR
    daemon = subprocess.Popen([ROOFD, "daemon"], env={**os.environ, "ROOFD_DIR": RDIR}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)
    rows = []
    try:
        for agent in AGENTS:
            for task in TASKS:
                out = {}
                th = [threading.Thread(target=run, args=(cls, agent, task, out)) for cls in (Herdr, Roofd)]
                for t in th: t.start()
                for t in th: t.join()
                json.dump(out, open(os.path.join(LOGS, f"{agent}-{task}.json"), "w"), indent=1, default=str)
                h, r = out.get("herdr", {}), out.get("roofd", {})
                ph, pr = phases(h.get("timeline", [])), phases(r.get("timeline", []))
                key = lambda x: [s for s in x if s in ("working", "blocked", "done", "idle")]
                agree = key(ph)[-3:] == key(pr)[-3:]
                rows.append((agent, task, ph, pr, agree, h, r))
                print(f"{agent} {task}: herdr {ph} | roofd {pr} | {'agree' if agree else 'DIFFER'}", file=sys.stderr, flush=True)
    finally:
        daemon.terminate()
    print("| Agent | Task | herdr | roofd | Same shape | Notes |\n|---|---|---|---|---|---|")
    for agent, task, ph, pr, agree, h, r in rows:
        notes = "; ".join([f"herdr: {n}" for n in h.get("notes", [])] + [f"roofd: {n}" for n in r.get("notes", [])])
        extra = f"ready {h.get('ready_s','?')} s / {r.get('ready_s','?')} s; blocked seen {h.get('saw_block')} / {r.get('saw_block')}"
        print(f"| {agent} | {task} | {' → '.join(ph)} | {' → '.join(pr)} | {'yes' if agree else '**no**'} | {extra}{'; ' + notes if notes else ''} |")


main()
