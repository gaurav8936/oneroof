#!/usr/bin/env python3
"""One Roof simulator · driver (LAB-1591, LAB-1592, LAB-1593).

Starts a test copy of One Roof (build/One Roof.app from scripts/bundle.sh) on a fresh profile with its OWN roofd,
opens N agent sessions over 3 windows through the app's self-test script (so the app's own state and Needs you see
them), and plays the user: after each answer it sends a follow-up, answers permission asks and questions after a
delay, or leaves some unanswered so Needs you fills up. Every turn is logged with a timestamp, and the app writes
what Needs you holds every few seconds; at the end report.md says, ask by ask, whether Needs you showed it.

  python3 app/scripts/sim/simulate.py                       # 9 stand-in sessions (claude/codex/kimi/gemini), 5 min
  python3 app/scripts/sim/simulate.py --sessions 12 --minutes 10 --seed 7
  python3 app/scripts/sim/simulate.py --real --minutes 3    # ONE real Claude session (uses the owner's subscription)

Stand-in mode puts copies of standin.py named claude, codex, kimi and gemini first on a PATH only these sessions
see (their own zsh dot-folder), so the owner's real CLIs are never started. Each session gets a scratch git repo under
<repo>/scratchpad/ (git-ignored; inside ~/Projects, where the app and the workspace's agents agree to start agents).
Real mode starts the real `claude` there
with a cheap model; follow-ups come from the on-device model when llama-server already answers on 127.0.0.1:8749,
else from a canned list. Never touches the installed app, the live store or the owner's roofd: the app runs under
`env -i` with ONEROOF_FRESH_PROFILE, its own ONEROOF_STORE and ROOFD_DIR.
Standard library only (a dev tool; never shipped in the app).
"""
import argparse, json, os, plistlib, random, re, shutil, signal, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
APPDIR = os.path.abspath(os.path.join(HERE, "..", ".."))
REPO = os.path.dirname(APPDIR)
BUNDLE = os.path.join(APPDIR, "build", "One Roof.app")
APPBIN = os.path.join(BUNDLE, "Contents", "MacOS", "OneRoof")
ROOFD = os.path.join(BUNDLE, "Contents", "MacOS", "roofd")
AGENTS = ["claude", "codex", "kimi", "gemini"]
SCENARIOS = ["builder", "asker", "mixed"]
# Who the simulated owner is per session: how soon they answer an ask (None = never: it stays in Needs you).
PERSONAS = {"prompt": (4, 15), "slow": (40, 90), "away": None}

# LAB-1924: --pretty names for public screenshots (made-up projects; no real repo or person).
PRETTY = ["Checkout flow fixes", "Search index rebuild", "Billing webhook retries", "Docs site navigation",
          "Flaky login test", "Release notes 2.4", "Image upload limits", "Nightly usage export", "Onboarding emails"]

FOLLOW_UPS = [
    "Thanks. Now add a test for that.",
    "Looks good. What's left before we can ship?",
    "Can you explain that change in one line?",
    "Go ahead with the next step.",
    "Please tidy the README to match.",
    "Run the tests again and tell me the count.",
    "Good. Check the config loader next.",
    "Keep going, and ask me before anything risky.",
    "Push it when the tests are green.",
    "Summarise where we are.",
]


class Sim:
    # --real (LAB-1593) lives in realmode.py, imported only when asked for.

    def __init__(self, a):
        self.a = a
        self.rng = random.Random(a.seed)
        stamp = time.strftime("%Y%m%d-%H%M%S")
        self.run = os.path.abspath(a.out or os.path.join(tempfile.gettempdir(), f"oneroof-sim-{stamp}"))
        os.makedirs(self.run, exist_ok=True)
        self.roofd_dir = tempfile.mkdtemp(prefix="rs.", dir="/tmp")    # short: unix socket paths stop at 104 chars
        self.shots = os.path.join(self.run, "shots")
        os.makedirs(self.shots, exist_ok=True)
        self.turns = open(os.path.join(self.run, "turns.tsv"), "a", buffering=1)
        self.sessions = []      # dicts: name agent repo persona scenario state...
        self.app = None

    # ------------------------------------------------------------ logging

    def log(self, session, event, detail=""):
        t = time.time()
        self.turns.write(f"{t:.2f}\t{time.strftime('%H:%M:%S', time.localtime(t))}\t{session}\t{event}\t{detail}\n")
        if self.a.verbose:
            print(f"{time.strftime('%H:%M:%S')} {session:18} {event:12} {detail}", flush=True)

    # ------------------------------------------------------------ setup

    def env_base(self):
        return {"HOME": os.environ["HOME"], "USER": os.environ.get("USER", ""), "LOGNAME": os.environ.get("LOGNAME", ""),
                "SHELL": "/bin/zsh", "LANG": "en_US.UTF-8", "TMPDIR": os.environ.get("TMPDIR", "/tmp/"),
                "ROOFD_DIR": self.roofd_dir}

    def roofd(self, *args, timeout=10):
        try:
            return subprocess.run([ROOFD, *args], env=self.env_base(), capture_output=True, text=True, timeout=timeout).stdout
        except subprocess.TimeoutExpired:
            return ""

    def prepare(self):
        if not os.access(APPBIN, os.X_OK) or not os.access(ROOFD, os.X_OK):
            sys.exit(f"No test build at {BUNDLE}: run `bash app/scripts/bundle.sh` first.")
        bindir = os.path.join(self.run, "bin")
        os.makedirs(bindir, exist_ok=True)
        if self.a.real:
            os.symlink(realmode.real_cli("claude"), os.path.join(bindir, "claude"))
        else:
            for ag in AGENTS:
                dst = os.path.join(bindir, ag)
                shutil.copy(os.path.join(HERE, "standin.py"), dst)
                os.chmod(dst, 0o755)
        # The sessions' own zsh setup: the private bin first on PATH, nothing of the owner's shell.
        zdot = os.path.join(self.run, "zdot")
        os.makedirs(zdot, exist_ok=True)
        for f in (".zshenv", ".zprofile"):
            open(os.path.join(zdot, f), "w").close()
        with open(os.path.join(zdot, ".zshrc"), "w") as f:
            f.write(f'export PATH="{bindir}:$PATH"\nPS1="%~ %# "\n')
        self.bindir, self.zdot = bindir, zdot
        # A fresh profile seeded only with the owner's settings and themes (no windows, sessions or store).
        seed = {}
        try:
            with open(os.path.expanduser("~/Library/Preferences/io.github.gaurav8936.oneroof.plist"), "rb") as f:
                d = plistlib.load(f)
            seed = {k: d[k] for k in ("settings", "panelThemes", "panelThemes.v2", "migratedFromLegacy") if k in d}
        except Exception:
            pass
        with open(os.path.join(self.run, "seed.plist"), "wb") as f:
            plistlib.dump(seed, f)
        # Repos: one scratch folder per session, each with its scenario.
        # Inside ~/Projects (the app starts agents only there), in the repo's git-ignored scratchpad/.
        root = os.path.join(REPO, "scratchpad", "sim-real" if self.a.real else "sim-repos", time.strftime("%Y%m%d-%H%M%S"))
        os.makedirs(root, exist_ok=True)
        n = 1 if self.a.real else self.a.sessions
        if self.a.real:
            self.a.turns = min(self.a.turns, 3)    # a proof run on the owner's subscription: a few turns
        windows = ["Main", "Web", "API"] if self.a.pretty else ["Main", "Sim B", "Sim C"]
        personas = list(PERSONAS)
        for i in range(n):
            agent = "claude" if self.a.real else AGENTS[i % len(AGENTS)]
            scen = SCENARIOS[(i // len(AGENTS) + i) % len(SCENARIOS)]
            name = PRETTY[i % len(PRETTY)] if self.a.pretty else f"sim-{i + 1:02d}-{agent}-{scen}"
            repo = os.path.join(root, name)
            os.makedirs(repo, exist_ok=True)
            subprocess.run(["git", "init", "-q", repo], check=False)
            if self.a.real:
                # Something small for the real agent to work on, so it stays in its repo.
                with open(os.path.join(repo, "README.md"), "w") as f:
                    f.write("# greeter\n\nA tiny script that prints a greeting. Run: python3 hello.py\n")
                with open(os.path.join(repo, "hello.py"), "w") as f:
                    f.write('print("hello")\n')
            else:
                with open(os.path.join(repo, "README.md"), "w") as f:
                    f.write(f"# {name}\n\nScratch repo for the One Roof simulator.\n")
                shutil.copy(os.path.join(HERE, "scenarios", scen + ".txt"), os.path.join(repo, ".sim-scenario"))
            persona = "prompt" if self.a.real else personas[i % len(personas)]
            opening = ("Read README.md and hello.py in this folder and tell me in two lines what they do. Then ask me, with "
                       "your question tool, which of two small next steps I want." if self.a.real
                       else "Look around the repo and start on the plan.")
            self.sessions.append({"name": name, "agent": agent, "repo": repo, "window": windows[i % 3], "persona": persona,
                                  "scenario": scen, "id": None, "status": None, "since": time.time(), "turn": 0,
                                  "worked": False, "next_at": None, "answer_at": None, "blocked_at": None,
                                  "opening": opening})
        self.write_script()

    def write_script(self):
        lines = ["# One Roof simulator (LAB-1591): sessions over 3 windows, then Needs you watched", "wait 4"]
        for w in (["Main", "Web", "API"] if self.a.pretty else ["Main", "Sim B", "Sim C"]):
            mine = [s for s in self.sessions if s["window"] == w]
            if not mine:
                continue
            lines.append("activate Main" if w == "Main" else f"window {w}")
            for s in mine:
                lines.append(f"plan {s['name']}|{s['agent']}|{s['repo']}|{s['opening']}|1")
                lines.append("wait 1")
        lines += ["activate Main", "place needsYou", "wait 2"]
        total = int(self.a.minutes * 60) + 30
        k = 0
        while k * self.a.every < total:
            lines += [f"needs t{k:04d}"]
            if k % max(1, int(30 / self.a.every)) == 0:
                lines += [f"snap needs-{k:04d}"]
                if self.a.each:   # LAB-1907: every open entry, and a blocked session's terminal (no card over it)
                    for i in range(6):
                        lines += [f"needspick {i}", f"snap needs-{k:04d}-e{i}"]
                    lines += ["place sessions", "selectblocked", "wait 1", f"snap term-{k:04d}", "place needsYou", "wait 1"]
            lines += [f"wait {self.a.every}"]
            k += 1
        if self.a.tour:   # LAB-1924: one capture of every place at the end, for the README and the site
            first = self.sessions[0]["name"]
            lines += ["activate Main", "place home", "wait 2", "snap tour-home",
                      "place sessions", f"select {first}", "wait 2", "snap tour-sessions",
                      "place needsYou", "wait 1", "snap tour-needs"]
            lines += [x for i in range(4) for x in (f"needspick {i}", f"snap tour-needs-e{i}")]
            lines += ["place work", "wait 2", "snap tour-work", "place machine", "wait 2", "snap tour-machine",
                      "place loops", "wait 2", "snap tour-loops", "place learn", "wait 3", "snap tour-learn",
                      "place sessions", "newsession", "wait 2", "snap tour-newsession"]
        lines += ["place sessions", "snap end-sessions", "quit"]
        self.script = os.path.join(self.run, "script.txt")
        with open(self.script, "w") as f:
            f.write("\n".join(lines) + "\n")

    def launch(self):
        env = self.env_base()
        env.update({
            "PATH": f"{self.bindir}:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin",
            "ZDOTDIR": self.zdot, "SIM_LOG": os.path.join(self.run, "agents.tsv"),
            "ONEROOF_FRESH_PROFILE": "1", "ONEROOF_PROFILE_SEED": os.path.join(self.run, "seed.plist"),
            "ONEROOF_STORE": os.path.join(self.run, "sessions.sqlite"), "ONEROOF_SELFTEST_DEMO": "0",
            "ONEROOF_SELFTEST_UI2": "1",    # the v2 window the owner runs (Needs you place)
            "ONEROOF_SELFTEST_SCRIPT": self.script, "ONEROOF_SELFTEST_OUT": os.path.join(self.shots, "sim"),
        })
        if self.a.real:
            env["SIM_REAL"] = "1"
            env["ANTHROPIC_MODEL"] = self.a.model   # a cheap model for the proof run
        self.applog = open(os.path.join(self.run, "app.log"), "w")
        self.app = subprocess.Popen([APPBIN], env=env, stdout=self.applog, stderr=subprocess.STDOUT)
        self.log("-", "app-start", f"pid {self.app.pid} roofd {self.roofd_dir} run {self.run}")

    # ------------------------------------------------------------ the simulated owner

    def screen(self, s, n=40):
        return self.roofd("read", s["id"], str(n))

    def follow_up(self, s):
        if self.a.real:
            text = realmode.local_model_follow_up(self.screen(s, 60))
            if text:
                return text, "local-model"
        return self.rng.choice(FOLLOW_UPS), "canned"

    def pick_answer(self, s, screen):
        """What the owner picks for the ask on screen: (option number, why), or (None, why) when none can be read."""
        bottom = screen.strip().splitlines()[-40:]
        opts = []
        for l in bottom:
            m = re.match(r"^[\s│]*[❯›▶●>]?\s*(\d+)\.\s+(.+?)\s*│?\s*$", l)
            if m:
                opts.append((m.group(1), m.group(2)))
        if not opts:
            return None, "no options found"
        labels = " / ".join(o[1][:24] for o in opts)
        real = [o for o in opts if not o[1].startswith(("Type something", "Chat about this"))] or opts
        text = "\n".join(bottom)
        permission = re.search(r"Do you want to|Would you like to|Allow execution|Apply this|Run this|Edit this|Allow\?", text)
        if permission and self.rng.random() < self.a.deny:
            return real[-1][0], f"deny {real[-1][0]} of [{labels}]"
        o = real[0] if permission else self.rng.choice(real)
        return o[0], f"{'allow' if permission else 'pick'} {o[0]} of [{labels}]"

    def press(self, s, key):
        """Like a person: sometimes the number, sometimes arrow keys down to it, a beat apart, then Enter."""
        n = int(key)
        if n > 1 and self.rng.random() < 0.5:
            for _ in range(n - 1):
                self.roofd("input", s["id"], "\x1b[B")
                time.sleep(0.6)
            self.roofd("input", s["id"], "\r")
            return f"↓×{n - 1} ⏎"
        self.roofd("input", s["id"], key)
        return key

    def poll(self):
        out = self.roofd("list")
        try:
            live = json.loads(out).get("sessions", [])
        except Exception:
            return
        by_cwd = {}
        for r in live:
            by_cwd[os.path.realpath(r.get("cwd") or "")] = r
        now = time.time()
        for s in self.sessions:
            r = by_cwd.get(os.path.realpath(s["repo"]))
            if not r:
                continue
            if s["id"] is None:
                s["id"] = r["id"]
                self.log(s["name"], "session", f"roofd {r['id']} window {s['window']} persona {s['persona']} scenario {s['scenario']}")
            st = r.get("status") if "exited" not in r else "exited"
            if st != s["status"]:
                self.log(s["name"], "status", f"{s['status']} -> {st}")
                s["status"], s["since"] = st, now
                if st == "working":
                    s["worked"] = True
                if st == "blocked":
                    s["blocked_at"] = now
                    rng = PERSONAS[s["persona"]]
                    s["answer_at"] = None if rng is None else now + self.rng.uniform(*rng)
                    self.log(s["name"], "ask-seen", "answer in %s" % ("never (left for Needs you)" if rng is None else f"{s['answer_at'] - now:.0f}s"))
                    s["next_at"] = None
                if st in ("done", "idle") and s["worked"]:
                    s["worked"] = False
                    s["turn"] += 1
                    if s["turn"] < self.a.turns:
                        s["next_at"] = now + self.rng.uniform(*self.a.gap)
                        self.log(s["name"], "turn-done", f"turn {s['turn']}; follow-up in {s['next_at'] - now:.0f}s")
                    else:
                        self.log(s["name"], "turn-done", f"turn {s['turn']}; conversation finished")
            if st == "blocked":
                scr = None
                if self.a.real:
                    scr = self.screen(s)
                    g = realmode.handle_gate(self, s, scr)
                    if g:
                        self.log(s["name"], "gate", g)
                        continue
                if (s["answer_at"] is None and s.get("answered_at") and now - s["answered_at"] > 6
                        and PERSONAS[s["persona"]] is not None):
                    # Still blocked after an answer: the next ask came at once (real Claude asks for one tool after
                    # another faster than a 1 s poll sees a change).
                    s["answered_at"] = None
                    s["answer_at"] = now + self.rng.uniform(*PERSONAS[s["persona"]])
                    self.log(s["name"], "ask-seen", f"next ask, no status change between; answer in {s['answer_at'] - now:.0f}s")
                if s["answer_at"] and now >= s["answer_at"] and r.get("question"):
                    # LAB-1606: the turn ended with a question (no menu): the owner answers it as the next message.
                    s["answer_at"] = None
                    reply = self.rng.choice(FOLLOW_UPS)
                    self.roofd("input", s["id"], reply)
                    time.sleep(0.3)
                    self.roofd("input", s["id"], "\r")
                    s["answered_at"] = time.time()
                    self.log(s["name"], "answer", f"replied to the question: {reply}")
                    continue
                if s["answer_at"] and now >= s["answer_at"]:
                    scr = scr or self.screen(s)
                    key, why = self.pick_answer(s, scr)
                    s["answer_at"] = None
                    if key:
                        how = self.press(s, key)
                        s["answered_at"] = time.time()
                        self.log(s["name"], "answer", f"{why} (typed {how})")
                    else:
                        self.log(s["name"], "answer-skip", why)
            elif s["next_at"] and now >= s["next_at"] and st in ("done", "idle"):
                text, src = self.follow_up(s)
                # Text, then Enter a moment later (as the app's opening does): sent together, a CLI takes it as a paste.
                self.roofd("input", s["id"], text)
                time.sleep(0.3)
                self.roofd("input", s["id"], "\r")
                s["next_at"] = None
                self.log(s["name"], "follow-up", f"[{src}] {text}")
            elif self.a.real and st in ("idle",) and s["turn"] == 0 and not s["worked"] and now - s["since"] > 20:
                g = realmode.handle_gate(self, s, self.screen(s))
                if g:
                    self.log(s["name"], "gate", g)

    # ------------------------------------------------------------ run + report

    def go(self):
        if self.a.real:
            global realmode
            import realmode
        self.prepare()
        print(f"run folder: {self.run}\nroofd dir:  {self.roofd_dir}", flush=True)
        self.launch()
        end = time.time() + self.a.minutes * 60 + 25 + (180 if self.a.tour else 0)   # the tour runs after the reads
        try:
            while time.time() < end and self.app.poll() is None:
                self.poll()
                time.sleep(1)
        finally:
            self.stop()
        self.report()

    def stop(self):
        if self.app and self.app.poll() is None:
            self.app.send_signal(signal.SIGTERM)
            try:
                self.app.wait(10)
            except subprocess.TimeoutExpired:
                self.app.kill()
        for s in self.sessions:
            if s["id"]:
                self.roofd("close", s["id"], timeout=5)
        subprocess.run(["bash", os.path.join(APPDIR, "scripts", "stop-test-roofd.sh"), os.path.join(APPDIR, "build")],
                       capture_output=True)
        subprocess.run(["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                        "-u", BUNDLE], capture_output=True)
        self.log("-", "app-stop", "")

    def report(self):
        dumps = []
        for f in sorted(os.listdir(self.shots)):
            if f.endswith(".needs.json"):
                try:
                    dumps.append(json.load(open(os.path.join(self.shots, f))))
                except Exception:
                    pass
        by_id = {s["id"]: s for s in self.sessions if s["id"]}
        events = {}
        for r in self._agent_log():
            if len(r) >= 5 and r[1] in by_id and r[3] in ("ask", "answered"):
                events.setdefault(r[1], []).append((float(r[0]), r[3], r[4]))
        if self.a.real:
            # Real agents keep no log of their own: an ask is a stretch roofd reported blocked (gates and asks shorter
            # than a Needs you read are listed as answered before a read).
            ids = {x["name"]: i for i, x in by_id.items()}
            for r in (l.rstrip("\n").split("\t") for l in open(os.path.join(self.run, "turns.tsv"))):
                if len(r) >= 5 and r[2] in ids and r[3] == "status":
                    old_st, new_st = r[4].split(" -> ")
                    if new_st == "blocked":
                        events.setdefault(ids[r[2]], []).append((float(r[0]), "ask", "roofd blocked"))
                    elif old_st == "blocked":
                        events.setdefault(ids[r[2]], []).append((float(r[0]), "answered", new_st))
        end = max([d["at"] for d in dumps] + [time.time()])
        lines = ["# One Roof simulator run", "", f"Run folder: `{self.run}`", "",
                 f"Sessions: {len(self.sessions)} · minutes: {self.a.minutes} · mode: {'real' if self.a.real else 'stand-in'}"
                 f" · Needs you read every {self.a.every} s ({len(dumps)} reads)", "",
                 "## Every ask, and whether Needs you showed it while it waited", "",
                 "| session | asked | ask | waited | Needs you reads while waiting | shown |", "|---|---|---|---|---|---|"]
        shown = missed = text_q = 0
        for sid, evs in sorted(events.items(), key=lambda kv: by_id[kv[0]]["name"]):
            name = by_id[sid]["name"]
            for k, (t, ev, det) in enumerate(evs):
                if ev != "ask":
                    continue
                if det.startswith("text-question"):
                    text_q += 1
                    continue
                t1 = next((u for u, e2, _ in evs[k + 1:] if e2 == "answered"), end)
                during = [d for d in dumps if t + 3 <= d["at"] <= t1 - 1]
                hits = [d for d in during if any(o["session"] == name for o in d["open"])]
                if not during:
                    verdict = "answered before a read"
                elif hits:
                    verdict = f"yes ({len(hits)}/{len(during)})"; shown += 1
                else:
                    st = sorted({r["status"] for d in during for r in d["rows"] if r["name"] == name})
                    verdict = f"**NO** (status {', '.join(st) or '-'})"; missed += 1
                lines.append(f"| {name} | {time.strftime('%H:%M:%S', time.localtime(t))} | {det[:48]} | "
                             f"{'still waiting' if t1 == end else f'{t1 - t:.0f} s'} | {len(during)} | {verdict} |")
        # Stale: Needs you still lists a session whose ask was answered (or cancelled) more than 5 s before the read.
        stale = []
        for d in dumps:
            for o in d["open"]:
                if o.get("finished"):   # LAB-1827: a finished turn waits in Needs you on purpose
                    continue
                sid = next((i for i, x in by_id.items() if x["name"] == o["session"]), None)
                last = [e for e in events.get(sid, []) if e[0] <= d["at"]]
                if last and last[-1][1] == "answered" and d["at"] - last[-1][0] > 5:
                    stale.append((o["session"], d["at"] - last[-1][0]))
        # LAB-1827: finished turns in Needs you; LAB-1839: asks shown with the prompt's own options.
        finished = sorted({o["session"] for d in dumps for o in d["open"] if o.get("finished")})
        with_options = [o for d in dumps for o in d["open"] if not o.get("finished") and o.get("choices")]
        max_opts = max([len(o["choices"]) for o in with_options] or [0])
        # The run's own store: every decision the app made, and the ones that closed within 2 s (status flapping).
        flaps = total = 0
        try:
            import sqlite3
            db = sqlite3.connect(os.path.join(self.run, "sessions.sqlite"))
            for asked, answered, reply in db.execute("select asked_at, answered_at, reply from decisions"):
                total += 1
                if answered and answered - asked < 2 and reply == "answered in the terminal":
                    flaps += 1
        except Exception:
            pass
        lines += ["", f"Asks with a menu: {shown + missed} read while waiting · shown in Needs you: {shown} · missing: {missed}",
                  f"Questions other CLIs ask in plain text at the end of a turn (no menu, no hook: they end as Done): {text_q}"
                  " · Claude's plain-text questions at the end of a turn are asks above (`end-question`, LAB-1606)",
                  f"Stale Needs you entries (ask already answered > 5 s before the read): {len(stale)}"
                  + (" · " + ", ".join(sorted({n for n, _ in stale})) if stale else ""),
                  f"Finished turns shown in Needs you (LAB-1827): {len(finished)} session(s)" + (" · " + ", ".join(finished) if finished else ""),
                  f"Asks shown with the prompt's own options (LAB-1839): {len(with_options)} reads · most options on one ask: {max_opts}",
                  f"Decisions the app recorded: {total} · closed within 2 s as 'answered in the terminal' (flapping): {flaps}", "",
                  "Files: `turns.tsv` (every turn, status and answer), `agents.tsv` (what each stand-in asked and heard), "
                  "`shots/sim-t*.needs.json` (Needs you at each read), `shots/sim-needs-*.png` (screenshots), `app.log`."]
        with open(os.path.join(self.run, "report.md"), "w") as f:
            f.write("\n".join(lines) + "\n")
        print("\n".join(lines))

    def _agent_log(self):
        p = os.path.join(self.run, "agents.tsv")
        return [l.rstrip("\n").split("\t") for l in open(p)] if os.path.exists(p) else []


def main():
    p = argparse.ArgumentParser(description="One Roof simulator: agents asking, a simulated owner answering, Needs you watched.")
    p.add_argument("--sessions", type=int, default=9, help="stand-in sessions (spread over 3 windows and 4 agents)")
    p.add_argument("--minutes", type=float, default=5)
    p.add_argument("--turns", type=int, default=6, help="follow-ups per session before it stops")
    p.add_argument("--gap", type=float, nargs=2, default=(5, 25), metavar=("MIN", "MAX"), help="seconds before a follow-up")
    p.add_argument("--every", type=int, default=5, help="seconds between Needs you checks")
    p.add_argument("--seed", type=int, default=None)
    p.add_argument("--deny", type=float, default=0.15, help="share of permission asks the simulated owner denies")
    p.add_argument("--real", action="store_true", help="one real Claude session instead of stand-ins")
    p.add_argument("--model", default="haiku", help="--real: the Claude model (ANTHROPIC_MODEL)")
    p.add_argument("--out", help="run folder (default $TMPDIR/oneroof-sim-<time>)")
    p.add_argument("--pretty", action="store_true", help="LAB-1924: realistic session and window names (screenshots)")
    p.add_argument("--tour", action="store_true", help="LAB-1924: snap every place at the end of the run")
    p.add_argument("--each", action="store_true", help="LAB-1907: snap every open Needs you entry and a blocked terminal")
    p.add_argument("-v", "--verbose", action="store_true")
    a = p.parse_args()
    Sim(a).go()


if __name__ == "__main__":
    main()
