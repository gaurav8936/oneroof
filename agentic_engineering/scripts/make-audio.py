#!/usr/bin/env python3
"""Record the course narration: one MP3 per `##` section of each lesson in course/.

    OPENAI_API_KEY=... python3 scripts/make-audio.py [--force] [lesson ...]

Clips go to course/audio/<lesson file name>/<NN>-<section slug>.mp3. A small manifest (audio/<lesson>/.hashes.json)
remembers what text each clip was made from, so only edited sections are recorded again. Standard library only.
"""
import hashlib, json, os, re, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COURSE = os.path.join(ROOT, "course")
MODEL, VOICE = os.environ.get("AE_TTS_MODEL", "gpt-4o-mini-tts"), os.environ.get("AE_TTS_VOICE", "alloy")


def sections(md):
    """[(heading, spoken text)] for every ## section; the lesson title opens the first one."""
    body = re.sub(r"\A---\n.*?\n---\n", "", md, flags=re.S)
    title = (re.search(r"^# (.+)$", body, re.M) or [None, ""])[1]
    out = []
    for m in re.finditer(r"^## ([^\n]+)\n(.*?)(?=^## |\Z)", body, re.M | re.S):
        text = " ".join(m.group(2).split())
        text = re.sub(r"`([^`]*)`", r"\1", text).replace("**", "")
        spoken = f"{m.group(1)}. {text}"
        if not out and title:
            spoken = f"{title}. {spoken}"
        out.append((m.group(1), spoken))
    return out


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def speak(text, path, key):
    req = urllib.request.Request("https://api.openai.com/v1/audio/speech", method="POST",
                                 data=json.dumps({"model": MODEL, "voice": VOICE, "input": text,
                                                  "response_format": "mp3"}).encode(),
                                 headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r, open(path + ".part", "wb") as f:
        f.write(r.read())
    os.replace(path + ".part", path)


def main(argv):
    force = "--force" in argv
    wanted = [a for a in argv if not a.startswith("--")]
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        sys.exit("OPENAI_API_KEY is not set")
    made = kept = 0
    for name in sorted(os.listdir(COURSE)):
        if not re.match(r"\d\d-.*\.md$", name) or (wanted and name[:-3] not in wanted and name not in wanted):
            continue
        outdir = os.path.join(COURSE, "audio", name[:-3])
        os.makedirs(outdir, exist_ok=True)
        manifest_path = os.path.join(outdir, ".hashes.json")
        manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}
        current = {}
        for i, (heading, text) in enumerate(sections(open(os.path.join(COURSE, name)).read()), 1):
            clip = f"{i:02d}-{slug(heading)}.mp3"
            digest = hashlib.sha256(f"{MODEL}|{VOICE}|{text}".encode()).hexdigest()[:16]
            current[clip] = digest
            if not force and manifest.get(clip) == digest and os.path.exists(os.path.join(outdir, clip)):
                kept += 1
                continue
            print(f"recording {name[:-3]}/{clip}")
            speak(text, os.path.join(outdir, clip), key)
            made += 1
        for old in set(os.listdir(outdir)) - set(current) - {".hashes.json"}:
            os.remove(os.path.join(outdir, old))
        json.dump(current, open(manifest_path, "w"), indent=1, sort_keys=True)
    print(f"make-audio: {made} recorded · {kept} unchanged")


if __name__ == "__main__":
    main(sys.argv[1:])
