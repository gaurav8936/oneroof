#!/usr/bin/env python3
"""Side-by-side with Warp (LAB-1597): the same outside-in measures on Warp and on One Roof's test copy.

  compare.py <out dir> <One Roof test copy .app> <profile dir> <run-app.sh> <secs> <locked 0|1>

Outside only: Warp is driven with `open -a`, System Events (window size, through osascript) and measured with ps and
screencapture of its window's rectangle. Warp's own files, settings and data are never read. One Roof's test copy gets
exactly the same treatment (its window found by process id, so the installed One Roof is never touched).

Measures (each says when it could not be taken fairly):
  idle CPU % and RSS of every process of the app over <secs> s with two terminal windows/sessions open
  resize burst: 20 window resizes through System Events, CPU seconds the app spent on them
  redraw after resize: time until the window's pixels settle after one resize, and how many in-between captures
  differed from both the start and the final image (half-drawn frames), sampled with screencapture (~coarse)
Writes <out>/compare.json. Informational: exit 0 unless the script itself breaks."""
import hashlib, json, os, pathlib, subprocess, sys, time

out, app, profile, runapp, secs, locked = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]), sys.argv[6] == '1'
WARP = '/Applications/Warp.app'
cdir = out / 'compare'; cdir.mkdir(parents=True, exist_ok=True)
notes = []; res = dict(suite='compare', informational=True, screen_locked=locked, apps={}, notes=notes)


def sh(cmd, timeout=30):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 124, '', 'timeout')


def osa(script, timeout=30):
    r = sh(['osascript', '-e', script], timeout)
    return r.stdout.strip(), (r.stderr.strip() if r.returncode else '')


def procs(prefix):
    """pid → (cpu seconds, rss MB) for every process whose executable lives under prefix."""
    r = sh(['ps', '-axww', '-o', 'pid=,rss=,time=,comm='])
    d = {}
    for line in r.stdout.splitlines():
        p = line.split(None, 3)
        if len(p) == 4 and p[3].startswith(prefix):
            t = 0.0
            for x in p[2].split(':'): t = t * 60 + float(x)
            d[int(p[0])] = (t, int(p[1]) / 1024)
    return d


def cpu_window(prefix, s):
    a = procs(prefix); t0 = time.time(); time.sleep(s); b = procs(prefix); el = time.time() - t0
    cpu = sum(b[p][0] - a[p][0] for p in b if p in a)
    return dict(procs=len(b), cpu_pct=round(cpu / el * 100, 2), rss_mb=round(sum(v[1] for v in b.values())))


def window_of(pid):
    o, e = osa(f'tell application "System Events" to tell (first process whose unix id is {pid}) to get {{position, size}} of window 1')
    if e or not o: return None, e
    v = [int(float(x)) for x in o.replace(' ', '').split(',')]
    return v, ''


def set_size(pid, w, h):
    return osa(f'tell application "System Events" to tell (first process whose unix id is {pid}) to set size of window 1 to {{{w}, {h}}}')[1]


def grab(rect, path):
    x, y, w, h = rect
    sh(['screencapture', '-x', '-R', f'{x},{y},{w},{h}', str(path)], 10)
    try: return hashlib.md5(path.read_bytes()).hexdigest()
    except OSError: return None


def gestures(name, pid, prefix):
    """resize burst CPU + redraw settle, on the app's front window; the window is put back afterwards."""
    r = {}
    if locked:
        notes.append(f'{name}: resize measures not taken — the screen is locked, so windows are not drawn and a resize '
                     'costs neither app what it costs on screen'); return r
    win, err = window_of(pid)
    if not win:
        notes.append(f'{name}: no window through System Events ({err or "none"}) — resize measures not taken'); return r
    (x, y, w0, h0) = win
    a = procs(prefix); t0 = time.time()
    for i in range(20):
        e = set_size(pid, 1000 if i % 2 == 0 else 1400, 800)
        if e: notes.append(f'{name}: System Events could not resize ({e}) — resize measures not taken'); return r
    time.sleep(1.0)
    b = procs(prefix); el = time.time() - t0
    r['resize_burst_cpu_s'] = round(sum(b[p][0] - a[p][0] for p in b if p in a), 2)
    r['resize_burst_wall_s'] = round(el, 2)
    settles, halves = [], 0
    for i in range(3):
        set_size(pid, 1000, 800); time.sleep(1.2)
        rect = (x, y, 1400, 800)
        start = grab(rect, cdir / f'{name}-pre.png')
        set_size(pid, 1400, 800); t = time.time(); seen, last, stable_at = [], None, None
        for k in range(30):
            hsh = grab(rect, cdir / f'{name}-{i}-{k:02d}.png'); seen.append(hsh)
            if hsh == last and stable_at is None: stable_at = time.time() - t; break
            last = hsh
        final = seen[-1]
        halves += sum(1 for s in seen[:-1] if s not in (start, final))
        if stable_at is not None: settles.append(round(stable_at * 1000))
        for f in cdir.glob(f'{name}-{i}-*.png'):
            if f.name != f'{name}-{i}-00.png': f.unlink()
    r['redraw_settle_ms'] = sorted(settles)[len(settles) // 2] if settles else None
    r['in_between_frames'] = halves
    r['capture_note'] = 'screencapture samples every ~100-200 ms: settle is an upper bound, in-between frames a lower bound'
    set_size(pid, w0, h0)
    return r


# ── Warp ──
if not os.path.isdir(WARP):
    res['warp'] = 'not installed'; notes.append('Warp is not installed (/Applications/Warp.app): comparison skipped.')
else:
    running = bool(procs(WARP + '/'))
    if not running:
        sh(['open', '-a', 'Warp']); time.sleep(8)
    wp = procs(WARP + '/')
    main_pid = min(wp) if wp else None
    w = dict(launched_by_test=not running)
    if running:
        notes.append("Warp was already running (the owner's instance, with whatever tabs it has open): its idle CPU and memory "
                     'are for that workload, not a fresh two-terminal window, so they are not apples to apples. Its window '
                     'is put back to its size after the resize test.')
    if main_pid:
        w['idle'] = cpu_window(WARP + '/', secs)
        w.update(gestures('warp', main_pid, WARP + '/'))
    else:
        notes.append('Warp did not start.')
    if not running and main_pid: osa('tell application "Warp" to quit'); time.sleep(2)
    res['apps']['Warp'] = w

# ── One Roof test copy (same measures, its own copy of the profile and roofd) ──
script = cdir / 'or-idle.txt'
script.write_text(f'wait 4\nplace sessions\nterminal\nterminal\nwait {secs + 70}\nquit\n')
p = subprocess.Popen(['bash', runapp, app, str(script), str(cdir / 'oneroof-run'), profile, str(secs + 120)])
prefix = app + '/Contents/MacOS/'
pid = None
for _ in range(40):
    time.sleep(1)
    ps = procs(prefix + 'OneRoof')
    if ps: pid = min(ps); break
o = {}
if pid:
    time.sleep(12)
    o['idle'] = cpu_window(prefix, secs)
    o.update(gestures('oneroof', pid, prefix))
else:
    notes.append('One Roof test copy did not start for the comparison.')
res['apps']['One Roof (test copy)'] = o
p.wait()

res['fairness'] = [
    'Both apps are measured from the outside with the same tools (ps, System Events, screencapture).',
    'One Roof counts its app and every roofd process of the test copy; Warp counts every process in Warp.app.',
    'One Roof runs a copy of the owner\'s profile (sessions list, windows); its terminals are plain shells.',
]
(out / 'compare.json').write_text(json.dumps(res, indent=1))
print('compare: ' + '; '.join(f"{k} idle {v.get('idle', {}).get('cpu_pct', 'n/a')} % CPU, {v.get('idle', {}).get('rss_mb', 'n/a')} MB"
                              for k, v in res['apps'].items()))
for n in notes: print('  · ' + n)
