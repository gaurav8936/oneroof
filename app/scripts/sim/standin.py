#!/usr/bin/env python3
"""One Roof simulator · stand-in agent (LAB-1590).

A small terminal program that behaves like an agent CLI closely enough for One Roof to treat it as that agent:
the driver copies this file into a private bin folder as `claude`, `codex`, `kimi` and `gemini`, so roofd sees the
agent's name in the process's argv (StatusEngine.agentKind). The name it is started as picks the look:
banner, input box, the "working" line, permission prompts with numbered choices, and question menus, drawn as each
CLI draws them (the screens One Roof's tests use as fixtures, Tests/OneRoofCoreTests/Fixtures).

It is reactive: it reads what is typed (Enter submits; digits, y/a/n, arrows + Enter and Esc answer a prompt) and
plays the next turn of its scenario. Claude's stand-in also calls `$ONEROOF_ROOFD_BIN report claude` with the hook
payloads the real CLI's hooks send (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Notification, Stop),
so the hook path runs too.

Scenario file (SIM_SCENARIO, else `.sim-scenario` in the folder it starts in, else the built-in one): one step per line, turns separated by a line `---`.
  work <seconds>                          the working line for that long
  say <text>                              an answer line ({answer} = the last choice picked, {prompt} = what was typed)
  tool <name> <arg>                       a tool call line (Claude: hooks PreToolUse / PostToolUse)
  permission <command|edit> | <what> | <description>    a permission prompt; waits for the answer
  choose <question> | <option>[:: description] | ...     Claude: its question menu, waits for a pick; the other
                                          CLIs ask it in their answer and end the turn (they have no question menu)
  maybe <p> <step>                        the step with probability p (0-1)
Turns play in order, one per submitted prompt, and start again from the first after the last.
Standard library only; a dev tool, never shipped in the app.
"""
import json, os, random, re, select, shutil, subprocess, sys, termios, time, tty

AGENT = os.path.basename(sys.argv[0]).lower()
if AGENT not in ("claude", "codex", "kimi", "gemini"):
    AGENT = os.environ.get("SIM_AGENT", "claude")
RNG = random.Random((os.environ.get("SIM_SEED") or "") + os.getcwd())
LOG = os.environ.get("SIM_LOG")          # one line per event, for the driver's report
ESC = "\x1b"

BUILTIN = """
work 2
tool Read README.md
say I read the repo: a small service with tests under tests/.
maybe 0.7 permission command | pytest -q | Run the test suite
say The tests pass. Next I would tidy the config loader.
---
work 3
choose Which config format should the loader keep? | TOML | YAML | Both, TOML first
say Going with {answer}.
maybe 0.5 permission edit | src/config.py | Update the loader
say Done: the loader reads {answer}.
---
work 2
say Shall I also update the README with the new option?
---
work 2
maybe 0.6 permission command | git push origin work | Push the branch so CI runs
say Pushed. That's everything from the plan.
"""


# LAB-1606: Claude's conversation file, as the real CLI keeps one: its Stop hook names it (transcript_path), and roofd
# reads the turn's last message there to see whether it ended with a question.
TRANSCRIPT = os.path.join(os.path.dirname(LOG) if LOG else os.getcwd(), f".sim-transcript-{os.getpid()}.jsonl")
LAST_SAID = [""]
ASKED = [""]   # the question the last turn ended with, while it waits for the owner


def transcript(role, text):
    if AGENT != "claude":
        return
    entry = {"type": role, "message": {"role": role, "content": text if role == "user" else [{"type": "text", "text": text}]}}
    with open(TRANSCRIPT, "a") as f:
        f.write(json.dumps(entry) + "\n")


def log(event, detail=""):
    if LOG:
        with open(LOG, "a") as f:
            f.write(f"{time.time():.2f}\t{os.environ.get('ONEROOF_SESSION', '-')}\t{AGENT}\t{event}\t{detail}\n")


def out(s):
    sys.stdout.write(s)
    sys.stdout.flush()


def width():
    return max(40, min(shutil.get_terminal_size((100, 40)).columns, 120))


# ---------------------------------------------------------------- hooks (Claude)

def hook(event, **extra):
    """What the owner's Claude hook script runs: `"$ONEROOF_ROOFD_BIN" report claude` with the payload on stdin."""
    if AGENT != "claude":
        return
    roofd = os.environ.get("ONEROOF_ROOFD_BIN")
    if not (roofd and os.environ.get("ONEROOF_SESSION") and os.access(roofd, os.X_OK)):
        return
    payload = {"hook_event_name": event, "session_id": "sim", "cwd": os.getcwd(), **extra}
    if event == "Stop":
        payload.setdefault("transcript_path", TRANSCRIPT)
    try:
        subprocess.run([roofd, "report", "claude"], input=json.dumps(payload).encode(), timeout=2,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
    log("hook", event)


# ---------------------------------------------------------------- drawing per CLI

BULLET = {"claude": "⏺", "codex": "•", "kimi": "•", "gemini": "✦"}[AGENT]


def banner():
    w = min(width(), 70)
    name = {"claude": "Claude Code (stand-in)", "codex": "OpenAI Codex (stand-in)", "kimi": "Kimi Code (stand-in)",
            "gemini": "Gemini CLI (stand-in)"}[AGENT]
    out("╭" + "─" * (w - 2) + "╮\r\n")
    out(("│ ✻ Welcome to " + name).ljust(w - 1) + "│\r\n")
    out(("│   cwd: " + os.getcwd())[: w - 1].ljust(w - 1) + "│\r\n")
    out("╰" + "─" * (w - 2) + "╯\r\n\r\n")


def input_box(text=""):
    """The idle input box; the cursor waits after the prompt marker."""
    w = width()
    mark = {"claude": "❯", "codex": "›", "kimi": ">", "gemini": ">"}[AGENT]
    hint = {"claude": "  ? for shortcuts", "codex": "  ⏎ send   ⌃J newline   ⌃C quit",
            "kimi": "  ctrl-x: toggle mode", "gemini": "  ~/scratch    no sandbox    gemini-stand-in"}[AGENT]
    out("─" * w + "\r\n")
    out(f"{mark} {text}\r\n")
    out("─" * w + "\r\n")
    out(hint + f"\x1b[3A\r\x1b[{len(mark) + 2 + len(text)}C")


def clear_box():
    """Remove the input box before printing a turn (cursor is on the box's text line)."""
    out("\r\x1b[1A\x1b[J")


def working_line(n):
    frames = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    f = frames[n % len(frames)]
    secs = n // 4
    if AGENT == "claude":
        return f"✻ Thinking… ({secs}s · esc to interrupt)"
    if AGENT == "codex":
        return f"• Working ({secs}s • esc to interrupt)"
    if AGENT == "kimi":
        return f"{f} Thinking..."
    return f"{f} Generating witty retort (esc to cancel, {secs}s)"


def permission_screen(kind, what, desc):
    """Each CLI's permission prompt, as One Roof's fixtures record them. Returns (lines, options)."""
    if AGENT == "claude":
        if kind == "edit":
            lines = [" Edit file", "", f"   {what}", f"   {desc}", "", f" Do you want to make this edit to {os.path.basename(what)}?"]
            opts = ["Yes", "Yes, allow all edits during this session (shift+tab)", "No, and tell Claude what to do differently (esc)"]
        else:
            # Claude Code 2.1.287 (captured 2026-10-29): description first, the command between dashed rules, a long
            # option wrapped over several lines, "Esc to cancel · Tab to amend" under it.
            rule = "╌" * width()
            lines = ["─" * width(), " Bash command", f" {desc}", rule, f" {what}", rule, " Do you want to proceed?"]
            opts = ["Yes", "Yes, and always allow access to\r\n      " + os.getcwd() + " from\r\n      this project", "No"]
        return lines, opts, "❯"
    if AGENT == "codex":
        if kind == "edit":
            lines = ["Would you like to make the following edits?", "", f"  └ {what} (+4 -1)", ""]
            opts = ["Yes, proceed (y)", "Yes, and don't ask again for these files (a)", "No, and tell Codex what to do differently (esc)"]
        else:
            lines = ["Would you like to run the following command?", "", f"  $ {what}", ""]
            opts = ["Yes, proceed (y)", "Yes, and don't ask again for this command (a)", "No, and tell Codex what to do differently (esc)"]
        return lines, opts, "›"
    if AGENT == "kimi":
        q = "▶ Edit this file?" if kind == "edit" else "▶ Run this command?"
        lines = [q, f"cwd: {os.getcwd()}", (f"path: {what}" if kind == "edit" else f"$ {what}"), ""]
        opts = ["Approve once", "Approve for this session", "Reject", "Reject with feedback"]
        return lines, opts, "▶"
    # gemini
    tool = "Edit" if kind == "edit" else "Shell"
    q = "Apply this change?" if kind == "edit" else f"Allow execution of: '{what.split()[0]}'?"
    lines = [f"?  {tool} {what} ({desc})", "", what, "", q, ""]
    opts = ["Yes, allow once", "Yes, allow always ...", "No, suggest changes (esc)"]
    return lines, opts, "●"


def draw_menu(head, opts, marker, sel, hint):
    for l in head:
        out(l + "\r\n")
    for i, o in enumerate(opts):
        lead = f" {marker} " if i == sel else "   "
        out(f"{lead}{i + 1}. {o}\r\n")
    if hint:
        out("\r\n" + hint + "\r\n")


# ---------------------------------------------------------------- input

class Keys:
    def __init__(self):
        self.buf = ""

    def read(self, timeout):
        r, _, _ = select.select([sys.stdin], [], [], timeout)
        if not r:
            return None
        data = os.read(sys.stdin.fileno(), 4096).decode("utf-8", "replace")
        if data == "":
            raise EOFError
        return data


def wait_choice(keys, n_opts, redraw):
    """Digits pick; y / a / n (Codex, Kimi-inline style); arrows + Enter; Esc cancels (= the last option)."""
    sel = 0
    while True:
        k = keys.read(None)
        if k is None:
            continue
        if k in ("\x1b[A", "\x1bOA"):
            sel = max(0, sel - 1); redraw(sel); continue
        if k in ("\x1b[B", "\x1bOB"):
            sel = min(n_opts - 1, sel + 1); redraw(sel); continue
        if k in ("\r", "\n"):
            return sel
        if k == ESC:
            return n_opts - 1
        if k == "\x03":
            raise KeyboardInterrupt
        c = k.strip()[:1].lower()
        if c.isdigit() and 1 <= int(c) <= n_opts:
            return int(c) - 1
        if c in ("y", "a", "n"):
            return {"y": 0, "a": 1, "n": n_opts - 1}[c]


# ---------------------------------------------------------------- turns

def parse(text):
    turns, cur = [], []
    for raw in text.splitlines():
        l = raw.strip()
        if not l or l.startswith("#"):
            continue
        if l == "---":
            if cur:
                turns.append(cur)
            cur = []
        else:
            cur.append(l)
    if cur:
        turns.append(cur)
    return turns or [["say (empty scenario)"]]


def work(keys, seconds):
    """The working line, redrawn 4 times a second; Esc interrupts (as in the real CLIs)."""
    n = 0
    end = time.time() + seconds
    while time.time() < end:
        out("\r\x1b[2K" + working_line(n))
        n += 1
        k = keys.read(0.25)
        if k == ESC:
            out("\r\x1b[2K" + f"  ⎿  Interrupted by user\r\n")
            return False
    out("\r\x1b[2K")
    return True


def play(turn, keys, prompt):
    answer = ""
    hook("UserPromptSubmit", prompt=prompt)
    out(f"> {prompt}\r\n\r\n")
    for step in turn:
        verb, _, rest = step.partition(" ")
        if verb == "maybe":
            p, _, step2 = rest.partition(" ")
            if RNG.random() > float(p):
                continue
            verb, _, rest = step2.partition(" ")
        rest = rest.replace("{answer}", answer).replace("{prompt}", prompt)
        if verb == "work":
            if not work(keys, float(rest or 2) * (0.7 + RNG.random() * 0.6)):
                return
        elif verb == "say":
            out(f"{BULLET} {rest}\r\n\r\n")
            transcript("assistant", rest)
            LAST_SAID[0] = rest
        elif verb == "tool":
            name, _, arg = rest.partition(" ")
            hook("PreToolUse", tool_name=name, tool_input={"file_path": arg})
            out(f"{BULLET} {name}({arg})\r\n  ⎿  done\r\n\r\n")
            hook("PostToolUse", tool_name=name)
        elif verb == "permission":
            parts = [x.strip() for x in rest.split("|")]
            kind, what, desc = (parts + ["", "", ""])[:3]
            tool = "Edit" if kind == "edit" else "Bash"
            hook("PreToolUse", tool_name=tool, tool_input={"command": what})
            head, opts, marker = permission_screen(kind, what, desc)
            hint = {"codex": "Press enter to confirm or esc to cancel", "claude": " Esc to cancel · Tab to amend"}.get(AGENT, "")
            draw_menu(head, opts, marker, 0, hint)
            hook("Notification", message="Claude needs your permission", notification_type="permission_prompt")
            log("ask", f"permission {what}")
            start_row = len(head) + sum(1 + o.count("\r\n") for o in opts) + (2 if hint else 0)

            def redraw(sel, head=head, opts=opts, marker=marker, hint=hint, rows=start_row):
                out(f"\x1b[{rows}A\r\x1b[J"); draw_menu(head, opts, marker, sel, hint)
            pick = wait_choice(keys, len(opts), redraw)
            log("answered", f"permission {what} -> {pick + 1}")
            out(f"\x1b[{start_row}A\r\x1b[J")
            if pick < len(opts) - 1 and not (AGENT == "kimi" and pick >= 2):
                out(f"{BULLET} {tool}({what})\r\n  ⎿  ok\r\n\r\n")
                hook("PostToolUse", tool_name=tool)
            else:
                # As the real CLI: a denial ends the turn with no further hook (no PostToolUse, no Stop).
                out(f"  ⎿  User rejected {tool.lower()} of {what}\r\n\r\n{BULLET} Understood, I did not run it. What should I do instead?\r\n\r\n")
                return
        elif verb == "choose":
            parts = [x.strip() for x in rest.split("|")]
            q, opts = parts[0], parts[1:]
            if AGENT != "claude":
                # Only Claude has a question tool with a menu; the other CLIs ask in their answer and end the turn.
                out(f"{BULLET} {q} Options: " + " · ".join(opts) + "\r\n\r\n")
                log("ask", f"text-question {q}")
                hook("Stop")
                return
            # Claude's question tool, as Claude Code 2.1 draws it (captured from a real session, 2026-10-29):
            # each option with a description line, "Type something." and, under a rule, "Chat about this".
            hook("PreToolUse", tool_name="AskUserQuestion", tool_input={"questions": [{"question": q}]})
            hook("Notification", message="Claude needs your permission", notification_type="permission_prompt")
            descs = [o.split("::", 1)[1].strip() if "::" in o else "" for o in opts]
            opts = [o.split("::", 1)[0].strip() for o in opts]
            head = ["─" * width(), " ☐ Choice", "", q, ""]
            hint = "Enter to select · ↑/↓ to navigate · Esc to cancel"
            marker = "❯"
            menu = []
            for i, o in enumerate(opts):
                menu.append((o, descs[i]))
            menu.append(("Type something.", ""))

            def draw_q(sel, head=head, menu=menu):
                for l in head:
                    out(l + "\r\n")
                for i, (o, d) in enumerate(menu):
                    out(("❯ " if i == sel else "  ") + f"{i + 1}. {o}\r\n")
                    for dl in wrap(d, width() - 6):
                        out("     " + dl + "\r\n")
                out("─" * width() + "\r\n" + ("❯ " if sel == len(menu) else "  ") + f"{len(menu) + 1}. Chat about this\r\n")
                out("\r\n" + hint + "\r\n")
            draw_q(0)
            log("ask", f"question {q}")
            rows = len(head) + sum(1 + len(wrap(d, width() - 6)) for _, d in menu) + 4
            opts = [o for o, _ in menu] + ["Chat about this"]

            def redraw(sel, rows=rows):
                out(f"\x1b[{rows}A\r\x1b[J"); draw_q(sel)
            pick = wait_choice(keys, len(opts), redraw)
            out(f"\x1b[{rows}A\r\x1b[J")
            answer = "your own answer" if pick >= len(opts) - 2 else opts[pick]
            log("answered", f"question {q} -> {answer}")
            out(f"{BULLET} User answered Claude's questions:\r\n  ⎿  · {q} → {answer}\r\n\r\n")
            hook("PostToolUse", tool_name="AskUserQuestion")
    # LAB-1606: a Claude turn that ends with a plain-text question waits in Needs you until the next prompt.
    if AGENT == "claude" and LAST_SAID[0].rstrip().endswith("?"):
        ASKED[0] = LAST_SAID[0]
        log("ask", f"end-question {LAST_SAID[0]}")
    hook("Stop")


def wrap(text, w):
    """Word-wrap a description the way the CLI wraps it at the terminal width."""
    words, lines, cur = text.split(), [], ""
    for wd in words:
        if cur and len(cur) + 1 + len(wd) > w:
            lines.append(cur); cur = wd
        else:
            cur = (cur + " " + wd).strip()
    if cur:
        lines.append(cur)
    return lines


def main():
    path = os.environ.get("SIM_SCENARIO") or ".sim-scenario"
    text = open(path).read() if path and os.path.exists(path) else BUILTIN
    turns = parse(text)
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd) if os.isatty(fd) else None
    if old:
        tty.setraw(fd)
    keys = Keys()
    i = 0
    try:
        hook("SessionStart", source="startup")
        log("start", " ".join(sys.argv[1:]))
        time.sleep(0.4 + RNG.random() * 0.6)     # start-up
        banner()
        line = ""
        input_box(line)
        while True:
            k = keys.read(None)
            if k is None:
                continue
            for ch in re.findall(r"\x1b\[[0-9;]*[A-Za-z~]|\x1b.|.", k, re.S):
                if ch in ("\r", "\n"):
                    if not line.strip():
                        continue
                    prompt, line = line.strip(), ""
                    clear_box()
                    log("prompt", prompt)
                    if ASKED[0]:
                        log("answered", f"end-question {ASKED[0]}")
                        ASKED[0] = ""
                    transcript("user", prompt)
                    LAST_SAID[0] = ""
                    if prompt in ("/exit", "/quit", "exit"):
                        hook("SessionEnd")
                        return
                    play(turns[i % len(turns)], keys, prompt)
                    i += 1
                    input_box(line)
                elif ch in ("\x7f", "\b"):
                    if line:
                        line = line[:-1]
                        out("\b \b")
                elif ch == "\x03":
                    hook("SessionEnd")
                    return
                elif ch == "\x04":
                    hook("SessionEnd")
                    return
                elif ch.startswith(ESC):
                    continue
                elif ch.isprintable():
                    line += ch
                    out(ch)
    except (EOFError, KeyboardInterrupt):
        pass
    finally:
        if old:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
        out("\r\n")


if __name__ == "__main__":
    main()
