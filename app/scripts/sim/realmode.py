"""One Roof simulator · real-agent mode (LAB-1593), used by simulate.py --real.

The real `claude` plays the agent in a scratch git repo under <repo>/scratchpad/sim-real/ (inside ~/Projects: the
app and the workspace's own hooks start agents only there), with a cheap model (--model, default haiku, through
ANTHROPIC_MODEL). The simulator plays the user: it gets past Claude's first-run screens (folder trust, the project's
MCP servers, external imports), answers asks like the stand-in mode does, and writes follow-ups with the on-device
model (OneRoofCore LocalModel's llama-server on 127.0.0.1:8749) when it already answers, else canned ones. It never
starts llama-server itself. Uses the owner's Claude subscription: keep runs short (one session, a few turns).
"""
import json, os, re, sys, time, urllib.request


def real_cli(name):
    for d in ["/opt/homebrew/bin", os.path.expanduser("~/.local/bin"), "/usr/local/bin"]:
        p = os.path.join(d, name)
        if os.access(p, os.X_OK):
            return p
    sys.exit(f"--real: {name} not found in /opt/homebrew/bin, ~/.local/bin or /usr/local/bin")



def local_model_follow_up(screen):
    """The on-device model (llama-server, OneRoofCore LocalModel) writes the next instruction, if it is running."""
    try:
        urllib.request.urlopen("http://127.0.0.1:8749/health", timeout=1).read()
    except Exception:
        return None
    body = {"messages": [
        {"role": "system", "content": "You supervise a coding agent. Reply with ONE short next instruction for it "
                                      "(max 20 words), plain text, no quotes. /no_think"},
        {"role": "user", "content": "The agent's terminal ends with:\n" + screen[-2500:]}],
        "max_tokens": 60, "temperature": 0.7}
    try:
        req = urllib.request.Request("http://127.0.0.1:8749/v1/chat/completions", data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        r = json.loads(urllib.request.urlopen(req, timeout=20).read())
        t = r["choices"][0]["message"]["content"]
        t = re.sub(r"<think>.*?</think>", "", t, flags=re.S).strip().splitlines()
        return t[0][:200] if t and t[0] else None
    except Exception:
        return None



def handle_gate(sim, s, screen):
    """Real mode: Claude's first-run screens (folder trust, project MCP servers, external imports)."""
    if "Yes, I trust this folder" in screen:
        sim.roofd("input", s["id"], "\x1b[B"); time.sleep(0.4); sim.roofd("input", s["id"], "\r")
        return "trust folder"
    if "Esc to reject all" in screen:
        sim.roofd("input", s["id"], "\x1b")
        return "reject project MCP servers"
    if "external imports" in screen and "Enter to confirm" in screen:
        sim.roofd("input", s["id"], "\r")
        return "no external imports"
    return None
