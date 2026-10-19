#!/usr/bin/env python3
"""oneroof · merge (or remove) our keys in Claude Code's user settings, idempotently.

    claude_settings.py install   <settings.json> <memory-dir> <hook-script>
    claude_settings.py uninstall <settings.json> <hook-script>
    claude_settings.py check     <settings.json> <memory-dir> <hook-script>   # exit 0 = all present

Adds: "autoMemoryDirectory" (layer 5, the memory pin) and two hooks (layer 3): SessionStart → "<hook> start",
UserPromptSubmit → "<hook> prompt". Every other key and hook is left exactly as it was. A timestamped backup is
written next to the file before any change. Our hook entries are recognised by the hook script path.
"""
from __future__ import annotations

import json
import pathlib
import shutil
import sys
import time

EVENTS = {"SessionStart": "start", "UserPromptSubmit": "prompt"}


def load(p: pathlib.Path) -> dict:
    if not p.exists() or not p.read_text().strip():
        return {}
    return json.loads(p.read_text())


def ours(entry: dict, hook: str) -> bool:
    return any(hook in (h.get("command") or "") for h in entry.get("hooks", []))


def save(p: pathlib.Path, data: dict, before: str | None) -> None:
    after = json.dumps(data, indent=2) + "\n"
    if before is not None and after == before:
        return
    p.parent.mkdir(parents=True, exist_ok=True)
    if p.exists():
        shutil.copy2(p, p.with_name(f"{p.name}.before-oneroof-{time.strftime('%Y%m%d-%H%M%S')}"))
    p.write_text(after)


def main() -> int:
    cmd, path = sys.argv[1], pathlib.Path(sys.argv[2]).expanduser()
    before = path.read_text() if path.exists() else None
    data = load(path)
    hooks = data.setdefault("hooks", {}) if cmd != "check" else data.get("hooks", {})
    if cmd == "install":
        mem, hook = sys.argv[3], sys.argv[4]
        data["autoMemoryDirectory"] = mem
        for ev, mode in EVENTS.items():
            lst = [e for e in hooks.get(ev, []) if not ours(e, hook)]
            lst.insert(0, {"hooks": [{"type": "command", "command": f"{hook} {mode}", "timeout": 10}]})
            hooks[ev] = lst
        save(path, data, before)
        return 0
    if cmd == "uninstall":
        hook = sys.argv[3]
        for ev in EVENTS:
            if ev in hooks:
                hooks[ev] = [e for e in hooks[ev] if not ours(e, hook)]
                if not hooks[ev]:
                    del hooks[ev]
        if not hooks:
            data.pop("hooks", None)
        data.pop("autoMemoryDirectory", None)
        save(path, data, before)
        return 0
    if cmd == "check":
        mem, hook = sys.argv[3], sys.argv[4]
        ok = data.get("autoMemoryDirectory") == mem and all(any(ours(e, hook) for e in hooks.get(ev, [])) for ev in EVENTS)
        return 0 if ok else 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
