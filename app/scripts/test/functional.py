#!/usr/bin/env python3
"""Functional journeys result (LAB-1595): the self-test log of a run-app.sh run → functional.json.

  functional.py <run dir>        exit 0 every check passed · 1 a check failed or the run did not finish

Journeys are the "## <name>" headings of the run's script.txt; each step's CHECK lines and `snap` screenshots are
filed under the journey it belongs to. A run that never reached its last step (crash, timeout) fails."""
import json, pathlib, re, sys

run = pathlib.Path(sys.argv[1])
script = (run / 'script.txt').read_text().splitlines()
logp = run / 'st-log.txt'
log = logp.read_text().splitlines() if logp.exists() else []

# step number (1-based, as the app counts them: comments and blank lines skipped) → journey, line
journeys, step_of, cur, n = [], {}, None, 0
for line in script:
    t = line.strip()
    if t.startswith('## '):
        cur = dict(name=t[3:].strip(), checks=[], shots=[], steps=0); journeys.append(cur); continue
    if not t or t.startswith('#'): continue
    n += 1
    if cur is None: cur = dict(name='setup', checks=[], shots=[], steps=0); journeys.append(cur)
    cur['steps'] += 1
    step_of[n] = (cur, t)

step, finished, timeout = None, False, False
for line in log:
    m = re.match(r'^[\d.]+ (\d+): (.*)$', line)
    if m:
        step = int(m.group(1)); j, text = step_of.get(step, (None, ''))
        if j is not None and text.startswith('snap '):
            name = text.split(None, 1)[1]
            shots = sorted(p.name for p in run.glob(f'st-{name}*.png'))
            j['shots'] += [f'{run.name}/{s}' for s in shots]
        continue
    m = re.match(r'^[\d.]+\s+CHECK (PASS|FAIL) (.*)$', line)
    if m and step in step_of:
        step_of[step][0]['checks'].append(dict(step=step, ok=m.group(1) == 'PASS', what=m.group(2)))
        continue
    if re.match(r'^[\d.]+ (quit|done)$', line): finished = True
    if 'TIMEOUT' in line: timeout = True

fails = []
journeys = [j for j in journeys if j['checks'] or j['shots']]   # e.g. the warm-up before the first journey
for j in journeys:
    j['ok'] = all(c['ok'] for c in j['checks'])
    fails += [f"{j['name']}: {c['what']}" for c in j['checks'] if not c['ok']]
if not finished: fails.append('the run did not reach its last step' + (' (timeout)' if timeout else ' (the app exited or stopped)'))
checks = [c for j in journeys for c in j['checks']]
if not checks: fails.append('no checks ran')
secs = (run / 'seconds.txt').read_text().strip() if (run / 'seconds.txt').exists() else '?'
res = dict(suite='functional', ok=not fails, seconds=secs, journeys=journeys, checks=len(checks),
           passed=sum(c['ok'] for c in checks), failed=sum(not c['ok'] for c in checks), finished=finished, fails=fails)
(run.parent / 'functional.json').write_text(json.dumps(res, indent=1))
print(f"functional: {res['passed']}/{res['checks']} checks passed in {len(journeys)} journeys, {secs} s" + ('' if res['ok'] else ' — FAIL'))
for f in fails: print('  ✗ ' + f)
sys.exit(0 if res['ok'] else 1)
