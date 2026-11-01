#!/usr/bin/env python3
"""A/B confirmation for the perf gate (LAB-1903, LAB-1562): a busy Mac must not fail a release on its own.

The perf suite first compares the candidate with the previous release's stored baseline. When that finds a regression,
oneroof-test re-measures only the affected scenarios / gestures with the previous release app and the candidate
interleaved on the same Mac (B A B A), and the verdict comes from that same-time comparison: both sides see the same
load. Each measure's noise band is the spread of its repeat runs (previous release and candidate), so a difference
smaller than the Mac's own run-to-run noise never fails.

  ab.py plan  <out dir>                       → prints "SCEN=<a,b> GEST=<0|1> RESCUE=<0|1>" for the shell
  ab.py merge <out dir> <previous version>    → <out>/perf-ab/merged/perf/… + <out>/perf-ab/baseline.json
  ab.py --self-test                           → checks plan/merge/noise on synthetic runs (no app, no Mac load)

Layout written by oneroof-test: <out>/perf-ab/{prev,cand}-<r>/scenarios/result.json (perf-check) and
<out>/perf-ab/{prev,cand}-g<r>/st-log.txt (gesture journey), r = 1, 2."""
import json, pathlib, re, shutil, statistics, sys

SCEN_KEYS = ['app_cpu', 'roofd_cpu', 'main_busy', 'stalls_50_per_min', 'stall_ms_per_s', 'longest_stall_ms', 'model_changes_per_s',
             'children_per_min', 'footprint_mb', 'mb_per_terminal']
SCENARIOS = ('idle', 'home', 'places', 'places-sessions', 'places-others', 'spinners6', 'memory', 'learn', 'busy')
# Fails A/B can settle: a measure vs the previous release, or perf-check's comparison with its 1.9.3 study numbers.
# Anything else (a run that did not finish, a text check, a budget, no measurement) fails as before.
REGRESSION = re.compile(r'^(scenario|gesture) (\S+) (\w+) [\d.]+ vs [\d.]+ ')
STUDY = re.compile(r'^perf-check: (\S+) (\w+) [\d.]+ > baseline ')


def plan(out):
    perf = json.loads((pathlib.Path(out) / 'perf.json').read_text())
    scen, gest, other = set(), False, []
    for f in perf.get('fails', []):
        m = REGRESSION.match(f) or STUDY.match(f)
        if m and REGRESSION.match(f):
            if m.group(1) == 'scenario': scen.add(m.group(2))
            else: gest = True
        elif m:
            scen.add(m.group(1))
        else:
            other.append(f)
    scen = sorted(s for s in scen if s in SCENARIOS)
    rescue = bool(scen or gest) and not other
    return dict(scen=scen, gest=gest, rescue=rescue, other=other)


def scen_runs(dirs):
    runs = {}
    for d in dirs:
        p = pathlib.Path(d) / 'scenarios' / 'result.json'
        if not p.exists(): p = pathlib.Path(d) / 'result.json'
        if not p.exists(): continue
        for s, r in json.loads(p.read_text()).get('scenarios', {}).items():
            for k, v in r.items():
                if k in SCEN_KEYS and v is not None: runs.setdefault(s, {}).setdefault(k, []).append(float(v))
    return runs


def gest_runs(logs):
    runs = {}
    for gl in logs:
        gl = pathlib.Path(gl)
        if not gl.exists(): continue
        for line in gl.read_text().splitlines():
            m = re.match(r'^[\d.]+\s+PROBE (\S+) (.*)$', line)
            if m:
                for k, v in re.findall(r'(\w+)=([\d.]+)', m.group(2)): runs.setdefault(m.group(1), {}).setdefault(k, []).append(float(v))
    return runs


def median(d):
    return {n: {k: round(statistics.median(v), 3) for k, v in ks.items()} for n, ks in d.items()}


def spread(*ds):
    """Noise band per measure: the widest max−min over the repeat runs of either app."""
    out = {}
    for d in ds:
        for n, ks in d.items():
            for k, v in ks.items():
                if len(v) > 1: out.setdefault(n, {})[k] = round(max(out.get(n, {}).get(k, 0), max(v) - min(v)), 3)
    return out


def merge(out, prev_version):
    out = pathlib.Path(out); ab = out / 'perf-ab'; mg = ab / 'merged'
    if mg.exists(): shutil.rmtree(mg)
    first = json.loads((out / 'perf.json').read_text())
    rounds = sorted({int(p.name.split('-')[1]) for p in ab.glob('prev-[0-9]*')})
    groups = sorted({int(p.name.split('-g')[1]) for p in ab.glob('prev-g[0-9]*')})
    # Candidate: the first measurement plus every A/B round (median); previous release: its A/B rounds only.
    c_scen = scen_runs([out / 'perf'] + [ab / f'cand-{r}' for r in rounds])
    p_scen = scen_runs([ab / f'prev-{r}' for r in rounds])
    c_logs = [ab / f'cand-g{r}' / 'st-log.txt' for r in groups]
    first_g = [out / 'perf' / d / 'st-log.txt' for d in ('gestures', 'gestures-2', 'gestures-3')]
    c_gest_runs = gest_runs(c_logs + first_g[:1]) if groups else {}
    p_gest = gest_runs([ab / f'prev-g{r}' / 'st-log.txt' for r in groups])
    re_scen = set(p_scen)
    # perf.py input: scenarios result.json (the study-number comparison is left out: the A/B governs) …
    cand_scen = {s: v for s, v in first.get('scenarios', {}).items()}
    cand_scen.update({s: v for s, v in median(c_scen).items() if s in re_scen})
    (mg / 'perf' / 'scenarios').mkdir(parents=True)
    (mg / 'perf' / 'scenarios' / 'result.json').write_text(json.dumps(dict(
        version=first.get('version'), baseline=f'{prev_version} (A/B)', scenarios=cand_scen, fails=[]), indent=1))
    # … and up to three gesture logs (A/B candidate runs + the first run, or the first runs unchanged).
    logs = (c_logs + first_g[:1]) if groups else first_g
    for i, src in enumerate([p for p in logs if p.exists()][:3]):
        dst = mg / 'perf' / ('gestures' if i == 0 else f'gestures-{i + 1}'); dst.mkdir(parents=True)
        shutil.copy(src, dst / 'st-log.txt')
    # Baseline: the stored one, with every re-measured scenario / gesture replaced by the previous release's A/B median.
    bp = (first.get('baseline') or {}).get('path')
    base = json.loads(pathlib.Path(bp).read_text()) if bp and pathlib.Path(bp).exists() else {}
    scen = dict(base.get('scenarios', {})); scen.update(median(p_scen))
    # LAB-2115: only gestures the stored baseline already had are re-judged against the previous release. A gesture new
    # in this release (a step the previous app may not even run: 2.0.0 has no scrollgesture, so its "fling" scrolls
    # nothing and reads 0) has no fair A/B; it is held to its absolute budget only, as the first comparison did.
    known = set(base.get('gestures', {}))
    gest = dict(base.get('gestures', {})); gest.update({g: v for g, v in median(p_gest).items() if g in known})
    noise = dict(scenarios=spread(p_scen, {s: v for s, v in c_scen.items() if s in re_scen}),
                 gestures=spread(p_gest, c_gest_runs))
    ab_base = dict(version=f'{prev_version} (A/B, same run)', date=first.get('date'), quick=first.get('quick'),
                   screen_locked=first.get('screen_locked'), scenarios=scen, gestures=gest, noise=noise,
                   ab=dict(rounds=len(rounds), gesture_rounds=len(groups), rescanned=sorted(re_scen), gestures=bool(groups),
                           first_fails=first.get('fails', [])))
    (ab / 'baseline.json').write_text(json.dumps(ab_base, indent=1))
    return ab / 'baseline.json'


def self_test():
    import tempfile
    t = pathlib.Path(tempfile.mkdtemp())
    def scen(d, idle_cpu):
        (d / 'scenarios').mkdir(parents=True, exist_ok=True)
        (d / 'scenarios' / 'result.json').write_text(json.dumps({'scenarios': {'idle': {'app_cpu': idle_cpu, 'footprint_mb': 80}}}))
    def gest(d, hitch):
        d.mkdir(parents=True, exist_ok=True); (d / 'st-log.txt').write_text(f'1.0 PROBE resize-grow hitch_ms_per_s={hitch} longest_ms=40\n2.0 quit\n')
    stored = t / 'baseline-1.0.json'
    stored.write_text(json.dumps({'version': '1.0', 'scenarios': {'idle': {'app_cpu': 1.0, 'footprint_mb': 80}, 'places': {'app_cpu': 3}},
                                  'gestures': {'resize-grow': {'hitch_ms_per_s': 20, 'longest_ms': 40}}}))
    # A busy Mac: the first candidate run looks 3x worse than the stored baseline.
    scen(t / 'perf', 3.0); gest(t / 'perf' / 'gestures', 60)
    (t / 'perf.json').write_text(json.dumps({'version': '1.1', 'quick': False, 'screen_locked': False, 'scenarios': {'idle': {'app_cpu': 3.0, 'footprint_mb': 80}},
        'baseline': {'version': '1.0', 'path': str(stored)},
        'fails': ['scenario idle app_cpu 3.0 vs 1.0 (+25 % and +1.0)', 'gesture resize-grow hitch_ms_per_s 60 vs 20 (+25 % and +10)',
                  'perf-check: places app_cpu 9 > baseline 3 +15 %']}))
    p = plan(t)
    assert p == dict(scen=['idle', 'places'], gest=True, rescue=True, other=[]), p
    # Interleaved: the previous release is just as slow on this Mac right now.
    for r, (pc, cc, pg, cg) in enumerate([(2.9, 3.1, 58, 61), (3.2, 3.0, 64, 59)], 1):
        scen(t / 'perf-ab' / f'prev-{r}', pc); scen(t / 'perf-ab' / f'cand-{r}', cc)
        gest(t / 'perf-ab' / f'prev-g{r}', pg); gest(t / 'perf-ab' / f'cand-g{r}', cg)
    b = json.loads(merge(t, '1.0').read_text())
    assert b['scenarios']['idle']['app_cpu'] == 3.05, b['scenarios']['idle']
    assert b['scenarios']['places'] == {'app_cpu': 3}, 'a scenario with no A/B run keeps its stored numbers'
    assert b['gestures']['resize-grow']['hitch_ms_per_s'] == 61.0
    assert b['noise']['scenarios']['idle']['app_cpu'] == 0.3 and b['noise']['gestures']['resize-grow']['hitch_ms_per_s'] == 6.0
    r = json.loads((t / 'perf-ab' / 'merged' / 'perf' / 'scenarios' / 'result.json').read_text())
    assert r['scenarios']['idle']['app_cpu'] == 3.0 and r['fails'] == []
    assert sorted(p.name for p in (t / 'perf-ab' / 'merged' / 'perf').iterdir()) == ['gestures', 'gestures-2', 'gestures-3', 'scenarios']
    # The real perf.py judges the merged run: same-time numbers pass …
    import subprocess
    here = pathlib.Path(__file__).resolve().parent
    def judge():
        return subprocess.run([sys.executable, str(here / 'perf.py'), str(t / 'perf-ab' / 'merged'), '1.1', str(here / 'limits.json'),
                               str(t / 'perf-ab' / 'baseline.json'), str(t / 'bl'), '0', '0'], capture_output=True, text=True)
    j = judge()
    assert j.returncode == 0 and 'not failing' not in (t / 'perf-ab' / 'merged' / 'perf.json').read_text(), j.stdout + j.stderr
    # … while a real regression (the previous release stays fast in the same rounds) still fails.
    for r in (1, 2):
        scen(t / 'perf-ab' / f'prev-{r}', 1.0); gest(t / 'perf-ab' / f'prev-g{r}', 20)
    merge(t, '1.0')
    j = judge()
    assert j.returncode == 1 and 'idle app_cpu' in j.stdout and 'resize-grow hitch_ms_per_s' in j.stdout, j.stdout
    # A failure A/B cannot settle (a run that did not finish) is never rescued.
    (t / 'perf.json').write_text(json.dumps({'fails': ['gesture run gestures-2 did not finish', 'scenario idle app_cpu 3 vs 1 (+25 % and +1.0)']}))
    assert plan(t)['rescue'] is False
    shutil.rmtree(t)
    print('ab.py self-test: ok')


if __name__ == '__main__':
    a = sys.argv[1:]
    if a[:1] == ['--self-test']: self_test()
    elif a[:1] == ['plan'] and len(a) == 2:
        p = plan(a[1]); print(f"SCEN={','.join(p['scen'])} GEST={int(p['gest'])} RESCUE={int(p['rescue'])}")
    elif a[:1] == ['merge'] and len(a) == 3: print(merge(a[1], a[2]))
    else: sys.exit(__doc__)
