#!/usr/bin/env python3
"""LAB-673: score an on-device model on the task classifier's test set.

Starts its own llama-server on a spare port with the given GGUF, sends each sentence in
scripts/route-eval/tasks.json with the same prompt and request body the app sends
(OneRoofCore/LocalModel.swift), and prints accuracy and latency. Stops the server when done.
Run one model at a time; it never touches the app's own server on port 8749.

  app/scripts/route-eval.py --model ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf
  app/scripts/route-eval.py --model ~/models/Arch-Router-1.5B-Q4_K_M.gguf --prompt arch

--prompt kinds  (default) the app's prompt since LAB-674: system prompt listing the kinds, JSON schema with the
                kinds as an enum, Qwen3 thinking off.
--prompt arch   the Arch-Router route prompt the app used up to 0.5.1.
Standard library only.
"""
import argparse
import json
import os
import re
import signal
import statistics
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
ROUTING = os.path.join(REPO, "app", "Resources", "agent-routing", "routing.json")  # LAB-1257: app config, not a skill

# Mirrors LocalModel.task / LocalModel.format (Arch-Router's own route prompt).
ARCH_TASK = """
You are a helpful assistant designed to find the best suited route.
You are provided with route description within <routes></routes> XML tags:
<routes>
{routes}
</routes>
<conversation>
{conversation}
</conversation>
"""
ARCH_FORMAT = """
Your task is to decide which route is best suit with user intent on the conversation in <conversation></conversation> XML tags.  Follow the instruction:
1. If the latest intent from user is irrelevant or user intent is full filled, response with other route {"route": "other"}.
2. You must analyze the route descriptions and find the best match route for user latest intent.
3. You only response the name of the route that best matches the user's request, use the exact name in the <routes></routes>.
Based on your analysis, provide your response in the following JSON formats if you decide to match any route:
{"route": "route_name"}
"""


EXAMPLES = """Examples:
"Add dark mode to the settings window" -> code
"Fix the login error when the token expires" -> code
"Figure out how Stripe webhooks retry" -> research
"Choose a schema for storing invoices before we build it" -> design
"Review Bob's change to the parser" -> review
"Write tests for the date formatter" -> test
"Write a getting-started guide" -> docs
"Upgrade Node and remove unused packages" -> chore"""


RULES = "New features, UI changes and bug fixes are code. Only pick test when the task is about tests or reproducing a failure. Only pick chore for maintenance that changes no behaviour."


def kinds_system_prompt(kinds):
    """Mirrors LocalModel.systemPrompt(kinds:). The examples are not in the test set."""
    lines = "\n".join(f"- {k}: {kinds[k]}" for k in sorted(kinds))
    return ("Classify a software task by the main work it asks for. Kinds:\n" + lines +
            "\n" + RULES + "\n" + EXAMPLES +
            "\nReply with JSON only: {\"route\": \"<kind>\"}.")


def request_body(prompt, text, kinds):
    if prompt == "arch":
        routes = json.dumps([{"name": k, "description": kinds[k]} for k in sorted(kinds)], separators=(",", ":"))
        conv = json.dumps([{"role": "user", "content": text}], separators=(",", ":"))
        content = ARCH_TASK.replace("{routes}", routes).replace("{conversation}", conv) + ARCH_FORMAT
        return {"messages": [{"role": "user", "content": content}], "temperature": 0, "max_tokens": 20}
    # Mirrors LocalModel.requestBody(text:kinds:).
    schema = {"type": "object", "properties": {"route": {"type": "string", "enum": sorted(kinds)}},
              "required": ["route"], "additionalProperties": False}
    return {"messages": [{"role": "system", "content": kinds_system_prompt(kinds)}, {"role": "user", "content": "Task: " + text}],
            "temperature": 0, "max_tokens": 20,
            "response_format": {"type": "json_schema", "json_schema": {"name": "route", "schema": schema}},
            "chat_template_kwargs": {"enable_thinking": False}}


def parse_route(s, allowed):
    """Mirrors LocalModel.parseRoute."""
    if not s:
        return None
    m = re.search(r"""route['"]?\s*:\s*['"]([a-z_]+)['"]""", s)
    return m.group(1) if m and m.group(1) in allowed else None


def post(port, body, timeout=30):
    req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        j = json.load(r)
    return j["choices"][0]["message"].get("content") or ""


def healthy(port):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=1) as r:
            return b"ok" in r.read()
    except Exception:
        return False


def rss_mb(pid):
    try:
        out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
        return int(out) // 1024 if out else None
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", required=True)
    ap.add_argument("--prompt", choices=["kinds", "arch"], default="kinds")
    ap.add_argument("--port", type=int, default=8761)
    ap.add_argument("--server", default=next((p for p in ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"]
                                              if os.access(p, os.X_OK)), "llama-server"))
    ap.add_argument("--tasks", default=os.path.join(HERE, "route-eval", "tasks.json"))
    ap.add_argument("--routing", default=ROUTING)
    ap.add_argument("--json", help="write per-task results here")
    a = ap.parse_args()
    if a.port == 8749:
        sys.exit("port 8749 is the app's own server; pick another")

    kinds = json.load(open(a.routing))["kind_descriptions"]
    tasks = json.load(open(a.tasks))["tasks"]
    model = os.path.expanduser(a.model)
    if healthy(a.port):
        sys.exit(f"something already answers on port {a.port}")

    # Same server flags as LocalModel.ensureRunning.
    srv = subprocess.Popen([a.server, "-m", model, "--port", str(a.port), "--host", "127.0.0.1", "-c", "4096", "--log-disable"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        t0 = time.time()
        while not healthy(a.port):
            if srv.poll() is not None or time.time() - t0 > 120:
                sys.exit("llama-server did not start")
            time.sleep(0.25)
        load_s = time.time() - t0
        post(a.port, request_body(a.prompt, "warm up", kinds))  # not timed
        rows, lat = [], []
        for t in tasks:
            s = time.time()
            raw = post(a.port, request_body(a.prompt, t["text"], kinds))
            ms = (time.time() - s) * 1000
            lat.append(ms)
            got = parse_route(raw, set(kinds))
            rows.append({"text": t["text"], "expected": t["kind"], "accept": t.get("accept", []), "got": got,
                         "raw": raw, "ms": round(ms)})
        rss = rss_mb(srv.pid)
    finally:
        srv.send_signal(signal.SIGTERM)
        try:
            srv.wait(timeout=10)
        except subprocess.TimeoutExpired:
            srv.kill()

    strict = sum(r["got"] == r["expected"] for r in rows)
    lenient = sum(r["got"] == r["expected"] or r["got"] in r["accept"] for r in rows)
    for r in rows:
        mark = "ok " if r["got"] == r["expected"] else ("~  " if r["got"] in r["accept"] else "XX ")
        print(f"{mark}{r['expected']:8} got {str(r['got']):8} {r['ms']:5} ms  {r['text'][:70]}")
    n = len(rows)
    lat.sort()
    print(f"\nmodel     {os.path.basename(model)} ({os.path.getsize(model) / 1e9:.2f} GB), prompt {a.prompt}")
    print(f"strict    {strict}/{n} = {100 * strict / n:.1f}%")
    print(f"lenient   {lenient}/{n} = {100 * lenient / n:.1f}%")
    print(f"latency   median {statistics.median(lat):.0f} ms, p90 {lat[int(0.9 * (n - 1))]:.0f} ms, max {lat[-1]:.0f} ms")
    print(f"load      {load_s:.1f} s; server RSS after run {rss} MB")
    if a.json:
        json.dump({"model": os.path.basename(model), "prompt": a.prompt, "strict": strict, "lenient": lenient, "n": n,
                   "median_ms": statistics.median(lat), "rss_mb": rss, "rows": rows}, open(a.json, "w"), indent=1)


if __name__ == "__main__":
    main()
