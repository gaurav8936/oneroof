#!/usr/bin/env python3
"""LAB-2212 · The launch video, concept A (owner-picked, Graphite): each chapter is a stage (the app's Graphite greys)
with the chapter's words on the left and the app window on the right; a chapter can show several captures of the
window, dissolving from one to the next. The camera pushes in slowly on every chapter; chapters cross-fade. 60 fps.

  python3 app/scripts/demo/render.py <chapters.json> <out dir>

chapters.json: {"chapters": [{"kicker": "01 · HOME", "title": "…", "line": "…", "shots": ["a.png", …], "secs": 10}, …],
                "title": {…same keys, no shots…}, "end": {…}}
Frames are drawn by headless Chrome at 2× (3840×2160), so the push-in stays sharp. Needs Google Chrome and ffmpeg.
"""
import html, json, os, subprocess, sys, tempfile

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FPS = 60
XFADE = 0.7          # between chapters
DISSOLVE = 0.6       # between shots inside a chapter
CHAPTERS = ["Home", "All windows", "Inbox", "Sessions", "Projects", "Resources", "Loops", "Learn", "Evals", "History"]

CSS = """
html,body{margin:0;width:1920px;height:1080px;overflow:hidden;font-family:-apple-system,"SF Pro Display",sans-serif}
body{background:linear-gradient(160deg,#3A3A3C 0%,#2C2C2E 45%,#1C1C1E 100%);color:#fff}
.copy{position:absolute;left:96px;top:150px;width:520px}
.kicker{font:600 22px/1 "SF Mono",ui-monospace,monospace;letter-spacing:.18em;color:#64D2FF}
h1{font-size:66px;line-height:1.05;font-weight:700;letter-spacing:-.02em;margin:26px 0 24px}
p{font-size:28px;line-height:1.42;color:rgba(255,255,255,.74);margin:0}
.win{position:absolute;right:80px;top:110px;width:1180px;border-radius:16px;overflow:hidden;
     box-shadow:0 40px 120px rgba(0,0,0,.5),0 0 0 1px rgba(255,255,255,.08)}
.win img{display:block;width:100%}
.chapters{position:absolute;left:96px;bottom:70px;display:flex;gap:26px;font:500 19px/1 -apple-system,sans-serif;color:rgba(255,255,255,.42)}
.chapters .on{color:#fff;border-bottom:3px solid #0A84FF;padding-bottom:8px}
.brand{position:absolute;right:80px;bottom:62px;font:600 22px/1 -apple-system,sans-serif;color:rgba(255,255,255,.6)}
.card{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center}
.card h1{font-size:110px;margin:0 0 28px}
.card p{font-size:40px;max-width:1300px}
.card .url{margin-top:40px;font:600 44px/1 -apple-system,"SF Pro Display",sans-serif;color:#64D2FF}
.card .blog{margin-top:22px;font:500 30px/1.2 -apple-system,"SF Pro Display",sans-serif;color:rgba(255,255,255,.74)}
.card .blog b{font-weight:600;color:#64D2FF}
.card .note{margin-top:34px;font-size:24px;color:rgba(255,255,255,.5)}
"""


# In-between clips are lossless: re-compressing them at every join stacked a quality pulse on each keyframe
# (every 4.17 s), seen as a flicker (owner 11-02). The final encode is the only lossy step.
TMP_ENC = ["-c:v", "libx264", "-qp", "0", "-preset", "ultrafast", "-pix_fmt", "yuv420p"]
FINAL_ENC = ["-c:v", "libx264", "-crf", "16", "-preset", "slow", "-pix_fmt", "yuv420p",
             "-x264-params", "keyint=600:min-keyint=60:ipratio=1.1:pbratio=1.1:aq-mode=3"]


def page(ch, shot, out_html):
    e = lambda s: html.escape(s or "")
    if ch.get("html"):   # an opening screen: its own words and visual, no app window (owner 11-02)
        body = ch["html"] + '<div class="brand">One Roof</div>'
    elif shot is None:   # title or end card
        body = f'<div class="card"><h1>{e(ch["title"])}</h1><p>{e(ch.get("line"))}</p>'
        if ch.get("url"):
            body += f'<div class="url">{e(ch["url"])}</div>'
        if ch.get("blog"):   # the chorus coding post, under the page link (owner 11-02)
            body += f'<div class="blog">The story: <b>{e(ch["blog"])}</b></div>'
        if ch.get("note"):
            body += f'<div class="note">{e(ch["note"])}</div>'
        body += "</div>"
    else:
        on = ch.get("chapter", "")
        strip = "".join(f'<span class="on">{c}</span>' if c == on else f"<span>{c}</span>" for c in CHAPTERS)
        body = (f'<div class="copy"><div class="kicker">{e(ch["kicker"])}</div><h1>{e(ch["title"])}</h1><p>{e(ch["line"])}</p></div>'
                f'<div class="win"><img src="file://{shot}"></div><div class="chapters">{strip}</div><div class="brand">One Roof</div>')
    with open(out_html, "w") as f:
        f.write(f"<!doctype html><html><head><meta charset='utf-8'><style>{CSS}{ch.get('css', '')}</style></head><body>{body}</body></html>")


def shoot(html_path, png):
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=2",
                    "--window-size=1920,1080", f"--screenshot={png}", f"file://{html_path}"],
                   capture_output=True, check=True)


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit("ffmpeg failed:\n" + r.stderr[-3000:])


def still(png, secs, out):
    """A 2× still as a 60 fps clip (the push-in is applied per chapter after the dissolves)."""
    run(["ffmpeg", "-y", "-loop", "1", "-framerate", str(FPS), "-t", f"{secs:.3f}", "-i", png,
         *TMP_ENC, out])


def xfade(a, b, dur, out, d=DISSOLVE):
    """Join two clips with a dissolve of d seconds; `dur` is a's length."""
    run(["ffmpeg", "-y", "-i", a, "-i", b, "-filter_complex",
         f"[0][1]xfade=transition=fade:duration={d}:offset={dur - d:.3f}",
         *TMP_ENC, out])


def length(clip):
    return float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", clip],
                                capture_output=True, text=True).stdout)


def chapter_clip(ch, tmp, k, push=0.05):
    shots = ch.get("shots") or [None]
    secs = ch["secs"]
    per = (secs + DISSOLVE * (len(shots) - 1)) / len(shots)
    clips = []
    for i, s in enumerate(shots):
        h, png, mp4 = (os.path.join(tmp, f"{k:02d}-{i}.{x}") for x in ("html", "png", "mp4"))
        page(ch, os.path.abspath(s) if s else None, h)
        shoot(h, png)
        still(png, per, mp4)
        clips.append(mp4)
    cur = clips[0]
    for i, c in enumerate(clips[1:], 1):
        nxt = os.path.join(tmp, f"{k:02d}-x{i}.mp4")
        xfade(cur, c, length(cur), nxt)
        cur = nxt
    # The push-in: from the whole stage to `push` closer, towards the window (or the centre on a card), 2× → 1×.
    n = int(round(length(cur) * FPS))
    fx, fy = (0.62, 0.42) if ch.get("shots") else (0.5, 0.5)
    # zoompan moves in whole pixels, so the push stepped every few frames (a flicker, owner 11-02); perspective
    # samples the shrinking box at sub-pixel positions with bicubic filtering, so it glides.
    z = f"(1+{push}*in/{max(1, n - 1)})"
    w, h = f"(W/{z})", f"(H/{z})"
    x0, y0 = f"((W-{w})*{fx})", f"((H-{h})*{fy})"
    x1, y1 = f"({x0}+{w})", f"({y0}+{h})"
    out = os.path.join(tmp, f"{k:02d}-chapter.mp4")
    run(["ffmpeg", "-y", "-i", cur, "-vf",
         f"perspective=x0='{x0}':y0='{y0}':x1='{x1}':y1='{y0}':x2='{x0}':y2='{y1}':x3='{x1}':y3='{y1}'"
         f":interpolation=cubic:eval=frame,scale=1920:1080:flags=lanczos,fps={FPS}",
         *TMP_ENC, out])
    return out


def main():
    spec = json.load(open(sys.argv[1]))
    out_dir = sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="demo-render.")
    # The short cut opens straight on the hook: no title card ("title": null).
    parts = [chapter_clip(dict(spec["title"], secs=spec["title"].get("secs", 4)), tmp, 0, push=0.02)] if spec.get("title") else []
    for k, ch in enumerate(spec["chapters"], 1):
        parts.append(chapter_clip(ch, tmp, k))
        print(f"chapter {k}: {ch['kicker']}", flush=True)
    parts.append(chapter_clip(dict(spec["end"], secs=spec["end"].get("secs", 5)), tmp, 99, push=0.02))
    # Where each chapter starts once the cross-fades overlap them: its narration starts there (+0.35 s).
    starts, t = [], 0.0
    for p in parts:
        starts.append(t)
        t += length(p) - XFADE
    cur = parts[0]
    for i, p in enumerate(parts[1:], 1):
        nxt = os.path.join(tmp, f"join-{i:02d}.mp4")
        xfade(cur, p, length(cur), nxt, d=XFADE)
        cur = nxt
    final = os.path.join(out_dir, "one-roof-demo.mp4")
    specs = ([spec["title"]] if spec.get("title") else []) + spec["chapters"] + [spec["end"]]
    voices = [(st, c["voice"]) for st, c in zip(starts, specs) if c.get("voice")]
    if voices:
        ins, legs = [], []
        for k, (st, wav) in enumerate(voices):
            ins += ["-i", wav]
            ms = int((st + 0.35) * 1000)
            legs.append(f"[{k + 1}:a]aresample=48000,adelay={ms}|{ms}[a{k}]")
        mix = ";".join(legs) + ";" + "".join(f"[a{k}]" for k in range(len(voices))) + \
            f"amix=inputs={len(voices)}:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[a]"
        run(["ffmpeg", "-y", "-i", cur, *ins, "-filter_complex", mix, "-map", "0:v", "-map", "[a]",
             *FINAL_ENC, "-r", str(FPS),
             "-c:a", "aac", "-b:a", "256k", "-shortest", "-movflags", "+faststart", final])
    else:
        run(["ffmpeg", "-y", "-i", cur, *FINAL_ENC,
             "-movflags", "+faststart", "-r", str(FPS), final])
    print(final, f"{length(final):.1f} s", f"{os.path.getsize(final) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
