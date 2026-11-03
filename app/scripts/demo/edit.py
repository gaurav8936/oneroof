#!/usr/bin/env python3
"""LAB-2212 · Cut the demo film at its cues, caption each scene, add the title and end cards: an .mp4 and a .gif.

  python3 app/scripts/demo/edit.py <run folder from demo.py> [--out <dir>]

Reads <run>/film.mp4, <run>/cues.tsv and the start time in <run>/record.log. Writes <out>/one-roof-demo.mp4
(1920×1080, 30 fps, H.264, no sound) and <out>/one-roof-demo.gif (960 wide, the Sessions and Inbox scenes).
Captions are burned in: feeds play videos muted. Needs ffmpeg. A dev tool, never shipped in the app.
"""
import argparse, os, re, subprocess, sys, tempfile

FONT = "/System/Library/Fonts/SFNS.ttf"
W, H = 1920, 1080

# (cue, seconds from the cue, length, caption)
SCENES = [
    ("windows", 0.5, 8.0, "Many coding agents at once: Claude Code on two accounts, Codex, Antigravity."),
    ("sessions", 0.5, 9.0, "Every session is the real agent in a real terminal."),
    ("inbox", 0.3, 9.5, "Everything they ask you lands in one Inbox. Nothing is approved for you."),
    ("home", 0.5, 9.0, "In the morning: what ran overnight, what went wrong, what to do next."),
    ("history", 0.5, 7.0, "History: what happened while you were away."),
    ("resources", 0.5, 7.0, "Resources: memory and CPU per session, so you can see what slows your Mac."),
]
TITLE = ("One Roof", "Mission control for many coding agents. You stay in charge.")
END = ("Free and open source", "gaurav8936.github.io/oneroof", "Demo with simulated agent sessions.")


def esc(t):
    return t.replace("\\", "\\\\").replace(":", "\\:").replace("'", "’").replace("%", "\\%")


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit("ffmpeg failed:\n" + r.stderr[-2000:])


def card(path, lines, secs):
    """A dark card with centred lines (first line large)."""
    draws, y0 = [], H // 2 - 80
    for i, (t, size, colour) in enumerate(lines):
        draws.append(f"drawtext=fontfile={FONT}:text='{esc(t)}':fontsize={size}:fontcolor={colour}:x=(w-text_w)/2:y={y0}")
        y0 += size + 40
    vf = ",".join(draws) + f",fade=t=in:st=0:d=0.4,fade=t=out:st={secs - 0.4}:d=0.4"
    run(["ffmpeg", "-y", "-f", "lavfi", "-i", f"color=c=0x101418:s={W}x{H}:r=30:d={secs}", "-vf", vf,
         "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "30", path])


def main():
    p = argparse.ArgumentParser()
    p.add_argument("run")
    p.add_argument("--out")
    a = p.parse_args()
    out = a.out or a.run
    os.makedirs(out, exist_ok=True)
    # Cue times in the log are seconds mod 10 000 (SelfTestScript.log); the CUE line carries the full time.
    cues = dict(l.split("\t") for l in open(os.path.join(a.run, "cues.tsv")).read().split("\n") if "\t" in l)
    tmp = tempfile.mkdtemp(prefix="demo-edit.")
    frames = os.path.join(a.run, "shots", "sim-film")
    if os.path.isdir(frames):
        # In-app frames (SelfTestFilm), named by ms since `film start`: each shown until the next one, as 30 fps.
        fs = sorted(f for f in os.listdir(frames) if f.endswith(".jpg"))
        ms = [int(f[1:-4]) for f in fs]
        lst = os.path.join(tmp, "frames.txt")
        with open(lst, "w") as f:
            for k, name in enumerate(fs):
                d = ((ms[k + 1] if k + 1 < len(ms) else ms[k] + 66) - ms[k]) / 1000
                f.write(f"file '{os.path.join(frames, name)}'\nduration {d:.3f}\n")
            f.write(f"file '{os.path.join(frames, fs[-1])}'\n")
        film = os.path.join(tmp, "film.mp4")
        run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-vsync", "cfr", "-r", "30",
             "-c:v", "libx264", "-crf", "14", "-pix_fmt", "yuv420p", film])
        start = float(cues["film-start"])
        print(f"{len(fs)} frames over {ms[-1] / 1000:.0f} s ({len(fs) / max(1, ms[-1] / 1000):.1f} fps)")
    else:
        film = os.path.join(a.run, "film.mp4")
        start = float(re.search(r"recording started ([0-9.]+)", open(os.path.join(a.run, "record.log")).read()).group(1))
    parts = []
    t = os.path.join(tmp, "00-title.mp4")
    card(t, [(TITLE[0], 120, "white"), (TITLE[1], 48, "0xC9D1D9")], 4.0)
    parts.append(t)
    for k, (cue, off, length, caption) in enumerate(SCENES):
        if cue not in cues:
            sys.exit(f"no cue {cue} in cues.tsv")
        ss = max(0.0, float(cues[cue]) - start + off)
        seg = os.path.join(tmp, f"{k + 1:02d}-{cue}.mp4")
        vf = (f"scale={W}:{H},drawbox=x=0:y=ih-150:w=iw:h=150:color=black@0.62:t=fill,"
              f"drawtext=fontfile={FONT}:text='{esc(caption)}':fontsize=44:fontcolor=white:x=(w-text_w)/2:y=h-102,"
              f"fade=t=in:st=0:d=0.3,fade=t=out:st={length - 0.3}:d=0.3")
        run(["ffmpeg", "-y", "-ss", f"{ss:.2f}", "-i", film, "-t", f"{length}", "-vf", vf, "-an",
             "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "30", seg])
        parts.append(seg)
    e = os.path.join(tmp, "99-end.mp4")
    card(e, [(END[0], 84, "white"), (END[1], 56, "0x58A6FF"), (END[2], 30, "0x8B949E")], 5.0)
    parts.append(e)
    lst = os.path.join(tmp, "list.txt")
    with open(lst, "w") as f:
        f.write("".join(f"file '{x}'\n" for x in parts))
    mp4 = os.path.join(out, "one-roof-demo.mp4")
    run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c:v", "libx264", "-crf", "18", "-preset", "slow",
         "-pix_fmt", "yuv420p", "-movflags", "+faststart", mp4])
    # The GIF: the Sessions and Inbox scenes, 960 wide, 12 fps, one palette.
    gif = os.path.join(out, "one-roof-demo.gif")
    src = [x for x in parts if re.search(r"-(sessions|inbox)\.mp4$", x)]
    glst = os.path.join(tmp, "gif.txt")
    with open(glst, "w") as f:
        f.write("".join(f"file '{x}'\n" for x in src))
    run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", glst, "-vf",
         "fps=12,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4",
         gif])
    for f in (mp4, gif):
        print(f, f"{os.path.getsize(f) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
