#!/usr/bin/env python3
"""LAB-2212 · Read the demo's narration with OpenAI text-to-speech, one WAV per chapter.

  OPENAI_API_KEY=… python3 app/scripts/demo/tts.py narration.json <out dir> [--model gpt-4o-mini-tts] [--voice ash]
         [--only home,inbox]

The key comes from the environment for this run only; it is never printed or written. Standard library only.
"""
import argparse, json, os, sys, urllib.request

INSTRUCTIONS = ("A calm, confident product narrator. Crisp diction, warm but not salesy, a measured pace with short "
                "natural pauses at commas and full stops. American English.")


def speak(text, model, voice, out):
    body = {"model": model, "voice": voice, "input": text, "response_format": "wav"}
    if model.startswith("gpt-4o"):
        body["instructions"] = INSTRUCTIONS
    req = urllib.request.Request("https://api.openai.com/v1/audio/speech", data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + os.environ["OPENAI_API_KEY"],
                                          "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r, open(out, "wb") as f:
        f.write(r.read())


def main():
    p = argparse.ArgumentParser()
    p.add_argument("spec")
    p.add_argument("out")
    p.add_argument("--model", default="gpt-4o-mini-tts")
    p.add_argument("--voice", default="ash")
    p.add_argument("--only", default="")
    a = p.parse_args()
    if not os.environ.get("OPENAI_API_KEY"):
        sys.exit("OPENAI_API_KEY is not set")
    os.makedirs(a.out, exist_ok=True)
    only = set(filter(None, a.only.split(",")))
    for key, text in json.load(open(a.spec))["lines"].items():
        if only and key not in only:
            continue
        out = os.path.join(a.out, f"{key}.wav")
        speak(text, a.model, a.voice, out)
        print(out, os.path.getsize(out))


if __name__ == "__main__":
    main()
