#!/usr/bin/env python3
"""LAB-2212 · Write chapters.json for render.py: the opening (the chorus coding post: the compounding hook, chorus
coding, the four reasons, how it started; no app), then one chapter per place, from demo.py --stills captures.

  python3 app/scripts/demo/chapters.py <stills run folder> <out chapters.json> [--voice <dir of <chapter>.wav>]

With --voice, each chapter lasts its narration plus a pause (the narration is laid under it by render.py).
"""
import argparse, glob, json, os, subprocess

PAUSE = 1.2   # seconds after each line

# The compounding curve from the post (% of tasks right by number of steps).
STEPS = list(range(0, 52, 2))
CURVES = [("99 % per step", "#64D2FF", [100, 98, 96.1, 94.1, 92.3, 90.4, 88.6, 86.9, 85.1, 83.5, 81.8, 80.2, 78.6, 77, 75.5, 74, 72.5, 71.1, 69.6, 68.3, 66.9, 65.6, 64.3, 63, 61.7, 60.5]),
          ("95 % per step", "#0A84FF", [100, 90.2, 81.5, 73.5, 66.3, 59.9, 54, 48.8, 44, 39.7, 35.8, 32.4, 29.2, 26.4, 23.8, 21.5, 19.4, 17.5, 15.8, 14.2, 12.9, 11.6, 10.5, 9.4, 8.5, 7.7]),
          ("90 % per step", "#8E8E93", [100, 81, 65.6, 53.1, 43, 34.9, 28.2, 22.9, 18.5, 15, 12.2, 9.8, 8, 6.5, 5.2, 4.2, 3.4, 2.8, 2.3, 1.8, 1.5, 1.2, 1, 0.8, 0.6, 0.5])]


def chart():
    W, H, L, B = 980, 560, 70, 60
    px = lambda s: L + (W - L - 20) * s / 50
    py = lambda v: 20 + (H - B - 20) * (1 - v / 100)
    g = [f'<line x1="{L}" y1="{py(v)}" x2="{W - 20}" y2="{py(v)}" stroke="rgba(255,255,255,.08)"/>'
         f'<text x="{L - 14}" y="{py(v) + 7}" fill="rgba(255,255,255,.45)" font-size="20" text-anchor="end">{v}%</text>'
         for v in (0, 25, 50, 75, 100)]
    g += [f'<text x="{px(s)}" y="{H - 18}" fill="rgba(255,255,255,.45)" font-size="20" text-anchor="middle">{s}</text>'
          for s in (0, 10, 20, 30, 40, 50)]
    for name, col, vals in CURVES:
        pts = " ".join(f"{px(s):.1f},{py(v):.1f}" for s, v in zip(STEPS, vals))
        g.append(f'<polyline points="{pts}" fill="none" stroke="{col}" stroke-width="5" stroke-linejoin="round"/>')

    g.append(f'<circle cx="{px(50)}" cy="{py(60.5)}" r="9" fill="#64D2FF"/>')
    for k, (name, col, end) in enumerate([("99 % per step", "#64D2FF", "61 % right"), ("95 % per step", "#0A84FF", "8 % right"),
                                          ("90 % per step", "#8E8E93", "under 1 % right")]):
        y = 60 + k * 40   # top right, above the curves
        g.append(f'<rect x="{W - 400}" y="{y - 18}" width="28" height="6" rx="3" fill="{col}"/>'
                 f'<text x="{W - 360}" y="{y - 8}" fill="rgba(255,255,255,.85)" font-size="22">{name} → <tspan fill="{col}" font-weight="700">{end}</tspan></text>')
    g.append(f'<text x="{(L + W) / 2}" y="{H + 18}" fill="rgba(255,255,255,.55)" font-size="20" text-anchor="middle">steps in the task (right at 50 steps)</text>')
    return f'<svg width="{W}" height="{H + 30}" viewBox="0 0 {W} {H + 30}" font-family="-apple-system,sans-serif">{"".join(g)}</svg>'


OPEN_CSS = """
.big{font-size:150px;font-weight:800;letter-spacing:-.03em;line-height:1;margin:22px 0 26px}
.big span{color:#64D2FF}
.vis{position:absolute;right:90px;top:200px}
.agents{position:absolute;right:110px;top:230px;width:1000px;display:grid;grid-template-columns:repeat(3,1fr);gap:26px}
.agent{background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.12);border-radius:18px;padding:26px 28px}
.agent b{display:block;font-size:34px;margin-bottom:10px}.agent i{font-style:normal;font-size:24px;color:rgba(255,255,255,.62)}
.agent.you{grid-column:span 3;text-align:center;background:rgba(10,132,255,.16);border-color:rgba(10,132,255,.6)}
.tiles{position:absolute;left:96px;right:96px;top:330px;display:grid;grid-template-columns:repeat(4,1fr);gap:30px}
.tile{background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.12);border-radius:20px;padding:36px 32px;min-height:330px}
.tile .n{font:600 22px/1 "SF Mono",ui-monospace,monospace;color:#64D2FF;letter-spacing:.14em}
.tile h2{font-size:46px;margin:22px 0 18px;letter-spacing:-.01em}.tile p{font-size:26px}
.wide{position:absolute;left:96px;top:120px;width:1700px}
.tabs{position:absolute;right:90px;top:250px;width:1040px}
.tabrow{display:flex;gap:6px;margin-bottom:22px}
.tab{flex:1;background:#3A3A3C;border-radius:10px 10px 0 0;padding:14px 12px;font:500 19px/1.1 "SF Mono",ui-monospace,monospace;color:#AEAEB2;white-space:nowrap;overflow:hidden}
.tab.w{color:#FF9F0A}.tab.r{color:#FF453A}
.stats{display:flex;gap:46px;margin-top:40px}.stats div{font-size:26px;color:rgba(255,255,255,.62)}.stats b{display:block;font-size:72px;color:#fff;letter-spacing:-.02em}
"""


def opening():
    tabs = [["zsh", "zsh", "WIP: auth", "zsh", "zsh"], ["NEXT: billing", "zsh", "zsh", "waiting 40 min", "zsh"],
            ["zsh", "DONE: migration", "zsh", "zsh", "asked you?"], ["zsh", "zsh", "zsh", "zsh", "zsh"]]
    cls = lambda t: "tab r" if "waiting" in t or "?" in t else ("tab w" if ":" in t else "tab")
    rows = "".join('<div class="tabrow">' + "".join(f'<div class="{cls(t)}">{t}</div>' for t in r) + "</div>" for r in tabs)
    return [
        {"key": "hook", "css": OPEN_CSS, "html":
            '<div class="copy"><div class="kicker">WHY ONE AGENT ISN\'T ENOUGH</div>'
            '<div class="big">99% <span>→</span><br>61%</div>'
            '<p>An agent right 99% of the time at each step gets a fifty-step task right only 61% of the time. Errors compound.</p></div>'
            f'<div class="vis">{chart()}</div>'},
        {"key": "chorus", "css": OPEN_CSS, "html":
            '<div class="copy"><div class="kicker">CHORUS CODING</div><h1>Several agents on the same work.</h1>'
            '<p>Each doing the part it does best, one checking another.</p></div>'
            '<div class="agents"><div class="agent"><b>Claude Code</b><i>the careful refactor</i></div>'
            '<div class="agent"><b>Codex</b><i>reviews what it wrote</i></div>'
            '<div class="agent"><b>Open-weight</b><i>the routine work, for less</i></div>'
            '<div class="agent"><b>Gemini · Kimi</b><i>more seats, more at once</i></div>'
            '<div class="agent"><b>Antigravity</b><i>another point of view</i></div>'
            '<div class="agent"><b>Loops</b><i>re-run the tests overnight</i></div>'
            '<div class="agent you"><b>You</b><i>steer, decide, and catch what they miss</i></div></div>'},
        {"key": "reasons", "css": OPEN_CSS, "html":
            '<div class="wide"><div class="kicker">ONE AGENT CAN\'T DO IT ALL</div><h1>Four reasons for a chorus.</h1></div>'
            '<div class="tiles">'
            '<div class="tile"><div class="n">01</div><h2>Cost</h2><p>Most work doesn\'t need the most expensive model.</p></div>'
            '<div class="tile"><div class="n">02</div><h2>Capacity</h2><p>One subscription runs out: a five-hour window, a weekly cap.</p></div>'
            '<div class="tile"><div class="n">03</div><h2>Quality</h2><p>Different agents are best at different jobs.</p></div>'
            '<div class="tile"><div class="n">04</div><h2>Independent checks</h2><p>An agent shouldn\'t grade its own work.</p></div></div>'},
        {"key": "started", "css": OPEN_CSS, "html":
            '<div class="copy"><div class="kicker">HOW IT STARTED · OCTOBER 16</div><h1>Every tab looked the same.</h1>'
            '<p>Agents sat waiting for answers in tabs I wasn\'t watching, and context got lost between sessions.</p>'
            '<div class="stats"><div><b>22</b>tabs</div><div><b>5</b>windows</div><div><b>1</b>laptop</div></div></div>'
            f'<div class="tabs">{rows}</div>'},
    ]


APP = [  # key, chapter strip name, kicker, title, line, stills (ch-<name>.png)
    ("home", "Home", "01 · HOME", "Your morning, on one page.", "What ran overnight, what broke, and what to do next.", ["home"]),
    ("windows", "All windows", "02 · ALL WINDOWS", "The heart of it.", "Every window, every session, and one live feed of what the agents did.", ["windows"]),
    ("inbox", "Inbox", "03 · INBOX", "Every ask, one Inbox.", "Urgent first. Each agent's own options as buttons. Nothing is approved for you.", ["inbox-1", "inbox-2"]),
    ("session", "Sessions", "04 · SESSIONS", "The real agent, in a real terminal.", "Claude works through its plan; you can always type straight into it.", ["session-1", "session-2", "session-3"]),
    ("newsession", "Sessions", "05 · NEW SESSION", "A new session in seconds.", "Agent and account, Linear project and issue, and what done looks like.", ["new-1", "new-2"]),
    ("projects", "Projects", "06 · PROJECTS", "Plan in Linear. Execute here.", "Tickets in, sessions out, results written back. With many kinds of agents.", ["projects"]),
    ("resources", "Resources", "07 · RESOURCES", "Agents can clog a laptop.", "What every session and app uses, what's hanging, and the buttons to fix it.", ["resources"]),
    ("loops", "Loops", "08 · LOOPS", "About 25 loops, ready to run.", "Watch, check, improve, report. Each with its limits and gates.", ["loops-1", "loops-2"]),
    ("learn", "Learn", "09 · LEARN", "So much new to learn.", "Context, loops, evidence, procedure, and the people worth hearing. Narrated.", ["learn-1", "learn-2", "learn-3"]),
    ("evals", "Evals", "10 · EVALS · DRAFT", "Measure your own agents.", "Beyond benchmarks: questions from your repo's real bugs.", ["evals"]),
    ("history", "History", "11 · HISTORY", "What happened while you were away.", "The important moments of every session.", ["history"]),
]


def with_sheet(png):
    """A sheet (New session) is its own window in the capture: put it over the dimmed window, where macOS shows it."""
    base = png[:-4]
    sheets = []
    for f in sorted(glob.glob(base + "-window*.png")):
        w, h = (int(v) for v in subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", f], capture_output=True,
                                                text=True).stdout.split()[-3::2])
        if 700 <= w <= 1100 and h >= 600:
            sheets.append((f, w))
    if not sheets:
        return png
    f, w = sheets[-1]
    out = base + "-composite.png"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", png, "-i", f, "-filter_complex", f"[0][1]overlay=x=(W-w)/2:y=52",
                    out], check=True)
    return out


def dur(wav):
    return float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", wav],
                                capture_output=True, text=True).stdout)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("stills")
    p.add_argument("out")
    p.add_argument("--voice")
    a = p.parse_args()
    shots = os.path.join(a.stills, "shots")
    secs = lambda k, d: round(dur(os.path.join(a.voice, f"{k}.wav")) + PAUSE, 2) if a.voice else d
    voice = lambda k: os.path.join(a.voice, f"{k}.wav") if a.voice else None
    chapters = []
    for o in opening():
        chapters.append(dict(o, kicker="", title="", line="", secs=secs(o["key"], 9), voice=voice(o["key"])))
    for key, strip, kicker, title, line, stills in APP:
        chapters.append({"key": key, "chapter": strip, "kicker": kicker, "title": title, "line": line,
                         "shots": [with_sheet(os.path.join(shots, f"sim-ch-{s}.png")) if s.startswith("new") else
                                   os.path.join(shots, f"sim-ch-{s}.png") for s in stills],
                         "secs": secs(key, 8), "voice": voice(key)})
    spec = {"title": {"title": "One Roof", "line": "Mission control for many coding agents. You stay in charge.", "secs": 3},
            "end": {"key": "end", "title": "One Roof", "line": "Many coding agents. One place to keep up. You stay in charge.",
                    "url": "gaurav8936.github.io/oneroof", "blog": "console.zibajoon.com/blog/chorus-coding", "note": "Free and open source",
                    "secs": secs("end", 6), "voice": voice("end")},
            "chapters": chapters}
    json.dump(spec, open(a.out, "w"), indent=1)
    print(a.out, f"{sum(c['secs'] for c in chapters) + 9:.0f} s before cross-fades")


if __name__ == "__main__":
    main()
