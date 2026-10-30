#!/usr/bin/env python3
"""Perf suite result (LAB-1596): perf-check scenarios + gesture probes → perf.json, compared with the previous
release's baseline (scratchpad/perf/baseline-<version>.json) under limits.json; a passing full run stores this
version's baseline.

  perf.py <out dir> <version> <limits.json> <baseline: ''|version|file|dir> <baselines dir> <quick 0|1> <locked 0|1>

Reads <out>/perf/scenarios/result.json (perf-check) and <out>/perf/gestures/st-log.txt (PROBE / CHECK lines).
Exit 0 pass · 1 regression, budget miss, failed check or no measurement."""
import json, pathlib, re, sys, time

out, version, limits_p, base_arg, bdir = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], pathlib.Path(sys.argv[5])
quick, locked = sys.argv[6] == '1', sys.argv[7] == '1'
L = json.loads(pathlib.Path(limits_p).read_text())
PCT, MIN, LOWER = L['regression_pct'] / 100, L['min_delta'], set(L['lower_is_better'])
BUDGET = L.get('budgets', {}).get('gestures', {})
SCEN_KEYS = ['app_cpu', 'roofd_cpu', 'main_busy', 'stalls_50_per_min', 'stall_ms_per_s', 'longest_stall_ms', 'model_changes_per_s',
             'children_per_min', 'footprint_mb', 'mb_per_terminal']
GEST_KEYS = ['hitch_ms_per_s', 'longest_ms', 'gap_p99_ms', 'stalls_50', 'frames', 'frame_p50_ms', 'frame_p99_ms', 'size_changes', 'settle_ms', 'gesture_ms']
# Measures that need a screen that draws (terminal surfaces exist only then; the display link only ticks then).
NEEDS_SCREEN = {'size_changes', 'settle_ms', 'frames', 'frame_p50_ms', 'frame_p99_ms'}


def vkey(v):
    return tuple(int(x) if x.isdigit() else 0 for x in re.split(r'[.-]', v))


def find_baseline():
    if base_arg:
        p = pathlib.Path(base_arg)
        if p.is_file(): return p
        if p.is_dir():
            c = sorted(p.glob('baseline-*.json'), key=lambda q: vkey(q.stem[9:]))
            return c[-1] if c else None
        q = bdir / f'baseline-{base_arg}.json'
        return q if q.exists() else None
    c = [q for q in bdir.glob('baseline-*.json') if vkey(q.stem[9:]) < vkey(version)]
    return sorted(c, key=lambda q: vkey(q.stem[9:]))[-1] if c else None


notes, fails, rows = [], [], []
# perf-check scenarios
pc = out / 'perf' / 'scenarios' / 'result.json'
scen = {}
if pc.exists():
    j = json.loads(pc.read_text())
    scen = {s: {k: v for k, v in r.items() if k in SCEN_KEYS and v is not None} for s, r in j.get('scenarios', {}).items()}
    for f in j.get('fails', []):
        if 'baseline' in f and '1.9.3' in str(j.get('baseline')): notes.append(f'perf-check vs its 1.9.3 study numbers: {f}')
        fails.append(f'perf-check: {f}')
else:
    fails.append('perf-check produced no result.json')

# gesture probes + text checks
gest, checks = {}, []
gl = out / 'perf' / 'gestures' / 'st-log.txt'
if gl.exists():
    for line in gl.read_text().splitlines():
        m = re.match(r'^[\d.]+\s+PROBE (\S+) (.*)$', line)
        if m:
            gest[m.group(1)] = {k: float(v) for k, v in re.findall(r'(\w+)=([\d.]+)', m.group(2))}
        m = re.match(r'^[\d.]+\s+CHECK (PASS|FAIL) (.*)$', line)
        if m: checks.append(dict(ok=m.group(1) == 'PASS', what=m.group(2)))
    if not re.search(r'^[\d.]+ quit$', gl.read_text(), re.M): fails.append('gesture run did not finish')
else:
    fails.append('gesture run produced no log')
if not gest: fails.append('no gesture measurements')
for c in checks:
    if not c['ok']: fails.append(f"gesture text check: {c['what']}")
for g in gest.values():
    for k in list(g):
        if k in ('frames', 'stalls_50', 'size_changes'): g[k] = int(g[k])
if locked:
    notes.append('The screen was locked during this run: nothing draws, so terminal surfaces, display frames, terminal size '
                 'changes and settle time could not be measured (shown as n/a). Main-thread gaps and hitches are still measured.')
    for g in gest.values():
        for k in NEEDS_SCREEN: g[k] = None

# baseline comparison
bp = find_baseline()
base = json.loads(bp.read_text()) if bp else {}
if not bp: notes.append('No earlier baseline in scratchpad/perf/: nothing to compare yet (a passing full run stores the baseline for this version).')
elif base.get('screen_locked') != locked:
    notes.append(f"Baseline {base.get('version')} was taken with the screen {'locked' if base.get('screen_locked') else 'unlocked'}, "
                 f"this run with it {'locked' if locked else 'unlocked'}: CPU and timing differ for that reason alone, so "
                 'regressions are reported but do not fail the run.')
if base and base.get('quick') != quick:
    notes.append('Baseline and this run used different lengths (--quick vs full): differences are indicative only.')
soft = bool(base) and (base.get('screen_locked') != locked)


def judge(group, name, k, v, bv, budget=None):
    verdict = ''
    if v is None:
        rows.append((group, name, k, 'n/a', bv if bv is not None else '–', '', 'not measured')); return
    delta = f'{(v - bv) / bv * 100:+.0f} %' if bv not in (None, 0) else ''
    if bv is not None and k in LOWER and v > bv * (1 + PCT) and v - bv > MIN.get(k, 0):
        verdict = 'REGRESSION' + (' (not failing: see notes)' if soft else '')
        if not soft: fails.append(f'{group} {name} {k} {v} vs {bv} (+{PCT * 100:.0f} % and +{MIN.get(k, 0)})')
    elif bv is not None and k in LOWER and v < bv * (1 - PCT) and bv - v > MIN.get(k, 0):
        verdict = 'better'
    if budget is not None:
        if v > budget:
            verdict = (verdict + ' ' if verdict else '') + f'OVER BUDGET (≤{budget})'; fails.append(f'{group} {name} {k} {v} > budget {budget}')
        else:
            verdict = (verdict + ' ' if verdict else '') + f'≤{budget} ✓'
    rows.append((group, name, k, v, bv if bv is not None else '–', delta, verdict))


for s, r in scen.items():
    for k, v in r.items(): judge('scenario', s, k, v, base.get('scenarios', {}).get(s, {}).get(k))
for g, r in gest.items():
    for k in GEST_KEYS:
        if k in r: judge('gesture', g, k, r[k], base.get('gestures', {}).get(g, {}).get(k), BUDGET.get(g, {}).get(k) if r[k] is not None else None)

res = dict(suite='perf', ok=not fails, version=version, quick=quick, screen_locked=locked,
           baseline=dict(version=base.get('version'), path=str(bp) if bp else None, screen_locked=base.get('screen_locked'), quick=base.get('quick')),
           scenarios=scen, gestures=gest, text_checks=checks, rows=rows, notes=notes, fails=fails)
(out / 'perf.json').write_text(json.dumps(res, indent=1))
# A passing full run is this version's baseline (the next release compares with it).
if not fails and not quick:
    bdir.mkdir(parents=True, exist_ok=True)
    (bdir / f'baseline-{version}.json').write_text(json.dumps(dict(
        version=version, date=time.strftime('%Y-%m-%d %H:%M'), quick=quick, screen_locked=locked, run=str(out),
        scenarios=scen, gestures={g: {k: v for k, v in r.items() if v is not None} for g, r in gest.items()}), indent=1))
    res['baseline_saved'] = str(bdir / f'baseline-{version}.json'); (out / 'perf.json').write_text(json.dumps(res, indent=1))
print(f"perf: {len(scen)} scenarios, {len(gest)} gestures vs baseline {base.get('version') or '(none)'}" + ('' if not fails else ' — FAIL'))
for f in fails: print('  ✗ ' + f)
sys.exit(0 if not fails else 1)
