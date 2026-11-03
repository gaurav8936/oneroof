#!/usr/bin/env python3
"""LAB-2212 · The launch demo: a scripted One Roof run on made-up data, filmed by the agent.

Four windows of three or four stand-in sessions each (Claude Code on two accounts, Codex, Antigravity), made-up
projects, a made-up night of loop runs for Home, then the scenes of the demo video, each marked with a `cue` in the
self-test log. The window-only recorder (record.swift) films the test copy's windows from the first cue to the last;
edit.py cuts the film at the cues and adds the captions.

  python3 app/scripts/demo/demo.py                     # warm up 6 min, then film (~1.5 min)
  python3 app/scripts/demo/demo.py --warmup 2 --no-film   # a quick look: snaps only, no recording

Built on the simulator (../sim/simulate.py): the same test copy (app/build/One Roof.app), its own profile, store,
roofd and a scratch shared folder; the installed app, the live store and the owner's roofd are never touched.
Standard library only; a dev tool, never shipped in the app.
"""
import argparse, datetime, os, re, shutil, signal, sqlite3, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "sim"))
import simulate  # noqa: E402

AGENT_BIN = ["claude", "codex", "kimi", "gemini", "agy"]

# Window → sessions: (name, agent, account, scenario, persona). Persona "away" leaves its asks in the Inbox.
WINDOWS = [
    ("Checkout", [("Checkout flow fixes", "claude", "Claude1", "builder", "away"),
                  ("Billing webhook retries", "codex", "", "builder", "prompt"),
                  ("Flaky login test", "claude", "Claude2", "asker", "away"),
                  ("Image upload limits", "agy", "", "mixed", "prompt")]),
    ("Platform", [("Search index rebuild", "claude", "Claude2", "mixed", "prompt"),
                  ("Nightly usage export", "agy", "", "builder", "away"),
                  ("Rate limiter tuning", "codex", "", "asker", "slow")]),
    ("Docs", [("Docs site navigation", "claude", "Claude1", "asker", "prompt"),
              ("Release notes 2.4", "codex", "", "builder", "away"),
              ("API reference examples", "agy", "", "mixed", "slow")]),
    ("Mobile", [("Onboarding emails", "claude", "Claude1", "mixed", "slow"),
                ("Push notification settings", "claude", "Claude2", "builder", "prompt"),
                ("Offline sync bug", "codex", "", "mixed", "away"),
                ("Dark mode polish", "agy", "", "asker", "prompt")]),
]

# Made-up loops and a night of their runs (hour, minute, result, summary), for Home's overnight timeline.
LOOPS = [("nightly-tests", "Nightly tests"), ("cost-watch", "Cost watch"), ("dependency-check", "Dependency check"),
         ("docs-drift", "Docs drift"), ("flaky-test-hunter", "Flaky test hunter"), ("security-audit", "Security audit")]
NIGHT = [(0, 30, "cost-watch", "pass", "Spend is on budget: $3.10 of $5 today."),
         (1, 0, "nightly-tests", "fail", "2 of 214 tests failed in checkout: the coupon total rounds the wrong way."),
         (1, 30, "cost-watch", "pass", "Spend is on budget."),
         (2, 0, "dependency-check", "pass", "No new advisories in 38 dependencies."),
         (2, 30, "cost-watch", "pass", "Spend is on budget."),
         (3, 0, "flaky-test-hunter", "fail", "test_login_redirect failed 3 times in 20 runs: a race on the session cookie."),
         (3, 30, "cost-watch", "pass", "Spend is on budget."),
         (4, 0, "docs-drift", "pass", "The API reference matches the code."),
         (4, 30, "cost-watch", "pass", "Spend is on budget."),
         (5, 0, "security-audit", "pass", "No secrets in the last 40 commits."),
         (5, 30, "cost-watch", "pass", "Spend is on budget."),
         (6, 0, "nightly-tests", "fail", "Still failing: the coupon total in checkout (2 tests)."),
         (6, 30, "cost-watch", "pass", "Spend is on budget.")]

# The filmed region (screen points, top-left origin) and the 2×2 tile inside it.
REGION = (760, 180, 1920, 1080)


class Demo(simulate.Sim):
    def prepare(self):
        if not os.access(simulate.APPBIN, os.X_OK):
            sys.exit(f"No test build at {simulate.BUNDLE}: run `bash app/scripts/bundle.sh` first.")
        self.bindir = os.path.join(self.run, "bin")
        os.makedirs(self.bindir, exist_ok=True)
        for ag in AGENT_BIN:
            dst = os.path.join(self.bindir, ag)
            shutil.copy(os.path.join(simulate.HERE, "standin.py"), dst)
            os.chmod(dst, 0o755)
        self.zdot = os.path.join(self.run, "zdot")
        os.makedirs(self.zdot, exist_ok=True)
        for f in (".zshenv", ".zprofile"):
            open(os.path.join(self.zdot, f), "w").close()
        with open(os.path.join(self.zdot, ".zshrc"), "w") as f:
            f.write(f'export PATH="{self.bindir}:$PATH"\nPS1="%~ %# "\n')
        # A fresh profile with no settings of the owner's: new users' defaults (every agent in Manual).
        import plistlib
        with open(os.path.join(self.run, "seed.plist"), "wb") as f:
            plistlib.dump({}, f)
        self.shared()
        root = os.path.join(simulate.REPO, "scratchpad", "demo-repos")
        self.repo_root = root
        shutil.rmtree(root, ignore_errors=True)
        os.makedirs(root)
        for win, rows in WINDOWS:
            for name, agent, account, scen, persona in rows:
                slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
                repo = os.path.join(root, slug)
                os.makedirs(repo)
                subprocess.run(["git", "init", "-q", repo], check=False)
                with open(os.path.join(repo, "README.md"), "w") as f:
                    f.write(f"# {name}\n")
                shutil.copy(os.path.join(simulate.HERE, "scenarios", scen + ".txt"), os.path.join(repo, ".sim-scenario"))
                self.sessions.append({"name": name, "agent": agent, "account": account, "repo": repo, "window": win,
                                      "persona": persona, "scenario": scen, "id": None, "status": None, "since": time.time(),
                                      "turn": 0, "worked": False, "next_at": None, "answer_at": None, "blocked_at": None,
                                      "opening": "Look around the repo and start on the plan."})
        self.stills_script() if self.a.stills else self.write_script()

    def shared(self):
        """A made-up shared folder: six loops (off) and a night of their runs in the outcome ledger."""
        d = os.path.join(self.run, "shared")
        loops = os.path.join(d, "loops")
        os.makedirs(loops, exist_ok=True)
        for lid, title in LOOPS:
            with open(os.path.join(loops, f"{lid}.loop.yaml"), "w") as f:
                f.write(f"name: {lid}\norigin: user\nversion: 1\ntitle: {title}\ngoal: '{title}, every night.'\n"
                        "check:\n  run: 'true'\n  pass: exit 0\nstop:\n  when: check passes\n  max_iterations: 1\n"
                        "  max_minutes: 10\ncost_cap:\n  usd: 0.5\nagent:\n  use: config\n  headless: true\n")
        db = sqlite3.connect(os.path.join(loops, "ledger.sqlite"))
        db.executescript("""
            CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
            CREATE TABLE IF NOT EXISTS runs(id TEXT PRIMARY KEY, loop TEXT NOT NULL,
              engine TEXT NOT NULL CHECK(engine IN ('ae', 'roofd')),
              mode TEXT NOT NULL DEFAULT 'live' CHECK(mode IN ('live', 'shadow', 'dry')),
              started TEXT NOT NULL, ended TEXT, result TEXT, cost_usd REAL, summary TEXT, journal_ref TEXT);""")
        today = datetime.datetime.now().astimezone().replace(second=0, microsecond=0)
        for k, (h, m, lid, result, summary) in enumerate(NIGHT):
            st = today.replace(hour=h, minute=m)
            en = st + datetime.timedelta(minutes=4)
            db.execute("INSERT OR REPLACE INTO runs VALUES(?,?,?,?,?,?,?,?,?,?)",
                       (f"demo-{k:02d}", lid, "roofd", "live", st.isoformat(timespec="seconds"),
                        en.isoformat(timespec="seconds"), result, 0.04, summary, None))
        db.commit()
        db.close()
        os.environ["ONEROOF_SHARED"] = d

    def write_script(self):
        x, y, w, h = REGION
        tw, th = w // 2, h // 2
        L = ["# LAB-2212 · the launch demo", "wait 4", "windowname Checkout", f"frame {x} {y} {w} {h}"]
        for i, (win, rows) in enumerate(WINDOWS):
            if i:
                L += [f"window {win}", "wait 1"]
            for s in [s for s in self.sessions if s["window"] == win]:
                L += [f"plan {s['name']}|{s['agent']}|{s['repo']}|{s['opening']}|1|{s['account']}", "wait 1.5"]
            L += ["place sessions", "layout grid", "wait 1"]
        L += [f"wait {int(self.a.warmup * 60)}"]
        # The scenes. Every `cue` is a cut point for edit.py.
        tiles = [(x, y), (x + tw, y), (x, y + th), (x + tw, y + th)]
        for (win, _), (tx, ty) in zip(WINDOWS, tiles):
            L += [f"activate {win}", f"frame {tx} {ty} {tw} {th}", "layout single"]
        L += ["wait 2", "cue film-start", f"film start {x} {y} {w} {h} 15", "cue windows", "wait 9", "snap scene-windows"]
        L += ["activate Checkout", f"frame {x} {y} {w} {h}", "place sessions", "layout grid", "wait 2",
              "cue sessions", "wait 10", "snap scene-sessions"]
        L += ["place needsYou", "wait 2", "cue inbox", "wait 4", "snap scene-inbox", "pick 0", "wait 6", "snap scene-inbox-after"]
        L += ["place home", "wait 3", "cue home", "wait 10", "snap scene-home"]
        L += ["place history", "wait 3", "cue history", "wait 8", "snap scene-history"]
        L += ["place machine", "wait 3", "cue resources", "wait 8", "snap scene-resources"]
        L += ["cue film-end", "film stop", "wait 2", "quit"]
        self.script = os.path.join(self.run, "script.txt")
        with open(self.script, "w") as f:
            f.write("\n".join(L) + "\n")

    def env_base(self):
        env = super().env_base()
        env.update({"SIM_CWD_FROM": self.repo_root, "SIM_CWD_TO": "~/code"})   # no real path on screen
        if self.a.stills:
            # The fake Linear's LAB team carries real project names: fold it. Evals opens on Explore at MMLU-Pro;
            # the New session sheet starts on the WEB team's checkout project; the Plan panel on its Plan tab.
            env.update({"ONEROOF_SELFTEST_PROJECTSFOLD": "LAB", "ONEROOF_SELFTEST_EVALS_TAB": "explore",
                        "ONEROOF_SELFTEST_EVALS_BENCH": "mmlu_pro", "ONEROOF_SELFTEST_TEAM": "WEB",
                        "ONEROOF_SELFTEST_PROJECT": "WEB-CHECKOUT", "ONEROOF_SELFTEST_PLANTAB": "plan"})
        return env

    def stills_script(self):
        """LAB-2212 v2 (owner: concept A, Graphite): one window, every chapter as sharp stills (render.py animates)."""
        x, y, w, h = 760, 180, 1440, 900
        L = ["# LAB-2212 · launch video stills", "wait 4", "windowname Checkout", f"frame {x} {y} {w} {h}"]
        for i, (win, rows) in enumerate(WINDOWS):
            if i:
                L += [f"window {win}", "wait 1", f"frame {x} {y} {w} {h}"]
            for s in [s for s in self.sessions if s["window"] == win]:
                L += [f"plan {s['name']}|{s['agent']}|{s['repo']}|{s['opening']}|1|{s['account']}", "wait 1.5"]
            L += ["place sessions", "layout single", "wait 1"]
        L += [f"wait {int(self.a.warmup * 60)}", "activate Checkout", "front", f"frame {x} {y} {w} {h}"]
        snap = lambda n, wait=3: [f"wait {wait}", f"snap ch-{n}"]
        L += ["place home", "homemode front"] + snap("home") + ["homemode windows"] + snap("windows")
        L += ["homemode front", "place needsYou"] + snap("inbox-1") + ["pick 0"] + snap("inbox-2")
        L += ["place sessions", "layout single", "select Checkout flow fixes", "menu View/Plan"] + snap("session-1", 2) + \
             snap("session-2", 5) + snap("session-3", 5)
        # The fake Linear only now: Home and All windows above show no tracker tickets.
        # The fixture also saves a planned session tagged with a real project: delete it from this test store.
        L += ["projects", "select Projects page hierarchy", "delete", "wait 1", "place work", "workselect WEB-CHECKOUT"] + snap("projects", 4)
        L += ["place sessions", "newsession claude"] + snap("new-1") + \
             ["keys Saved cards: show the card brand and last four digits on the review step"] + snap("new-2", 2) + ["esc", "wait 1"]
        L += ["place machine"] + snap("resources", 5)
        L += ["place loops"] + snap("loops-1") + ["loop release-verify"] + snap("loops-2", 2) + ["esc", "wait 1"]
        L += ["place learn"] + snap("learn-1", 8) + ["learngo #ae/band/context"] + snap("learn-2", 5) + \
             ["learngo #ae/card/krieger"] + snap("learn-3", 5)
        L += ["place evals"] + snap("evals", 5)
        L += ["place history"] + snap("history", 3)
        L += ["wait 2", "quit"]
        self.script = os.path.join(self.run, "script.txt")
        with open(self.script, "w") as f:
            f.write("\n".join(L) + "\n")

    def launch(self):
        super().launch()
        if not self.a.no_film:
            threading.Thread(target=self.film, daemon=True).start()

    def film(self):
        """Start the recorder at `cue film-start`, stop it at `cue film-end`; keep every cue with its time."""
        log = os.path.join(self.shots, "sim-log.txt")
        rec, seen, cues = None, 0, []
        out = os.path.join(self.run, "film.mp4")
        while self.app.poll() is None:
            text = open(log).read() if os.path.exists(log) else ""
            for line in text.splitlines()[seen:]:
                m = re.search(r"CUE (\S+) ([0-9.]+)", line)
                if not m:
                    continue
                cues.append((m.group(1), float(m.group(2))))
                if m.group(1) == "film-start" and rec is None and self.a.recorder:
                    x, y, w, h = REGION
                    rec = subprocess.Popen([self.a.recorder, str(self.app.pid), out, str(x), str(y), str(w), str(h)],
                                           stdout=open(os.path.join(self.run, "record.log"), "w"), stderr=subprocess.STDOUT)
                if m.group(1) == "film-end" and rec:
                    rec.send_signal(signal.SIGINT)
                    rec.wait(30)
                    rec = None
            seen = len(text.splitlines())
            with open(os.path.join(self.run, "cues.tsv"), "w") as f:
                f.write("".join(f"{n}\t{t:.2f}\n" for n, t in cues))
            time.sleep(0.2)
        if rec:
            rec.send_signal(signal.SIGINT)
            rec.wait(30)

    def go(self):
        self.prepare()
        print(f"run folder: {self.run}\nroofd dir:  {self.roofd_dir}", flush=True)
        self.launch()
        end = time.time() + self.a.warmup * 60 + 240
        try:
            while time.time() < end and self.app.poll() is None:
                self.poll()
                time.sleep(1)
        finally:
            self.stop()
        print(f"done: {self.run}", flush=True)


def main():
    p = argparse.ArgumentParser(description="LAB-2212: the One Roof launch demo, scripted and filmed.")
    p.add_argument("--warmup", type=float, default=6, help="minutes the sessions run before filming")
    p.add_argument("--no-film", action="store_true")
    p.add_argument("--stills", action="store_true", help="v2: every chapter as stills, one 1440×900 window (no film)")
    p.add_argument("--recorder", default=os.environ.get("DEMO_RECORDER", ""), help="optional: compiled record.swift (needs Screen Recording for the process that runs it)")
    p.add_argument("--out")
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("-v", "--verbose", action="store_true")
    a = p.parse_args()
    # What the simulator's owner loop reads.
    a.real, a.turns, a.gap, a.deny, a.minutes, a.pretty = False, 8, (6, 20), 0.1, a.warmup + 3, True
    a.tour = a.scroll = a.visuals = a.each = False
    a.every = 5
    # Filming is in-app (`film` in the script: no Screen Recording permission); --recorder adds record.swift's film.mp4.
    if a.recorder and not os.access(a.recorder, os.X_OK):
        sys.exit(f"--recorder {a.recorder}: not executable")
    Demo(a).go()


if __name__ == "__main__":
    main()
