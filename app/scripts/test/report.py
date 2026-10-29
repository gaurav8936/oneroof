#!/usr/bin/env python3
"""oneroof-test report (LAB-1598): every suite's JSON in a run folder → report.md (to review) and report.html (one
self-contained file: inline CSS and SVG charts, screenshots linked relatively), plus summary.json.

  report.py <run dir> <required suites, comma list>      exit 0 every required suite passed · 1 otherwise"""
import html, json, pathlib, re, sys

out = pathlib.Path(sys.argv[1]); required = [s for s in sys.argv[2].split(',') if s]
env = json.loads((out / 'env.json').read_text()) if (out / 'env.json').exists() else {}


def load(n):
    p = out / f'{n}.json'
    return json.loads(p.read_text()) if p.exists() else None


S = {n: load(n) for n in ('functional', 'perf', 'compare', 'sim')}
times = env.get('suite_seconds', {})
status = {}
for n, j in S.items():
    if n not in env.get('suites', []): status[n] = 'not run'
    elif j is None: status[n] = 'FAIL (no result)' if n in required else 'no result'
    elif j.get('skipped'): status[n] = 'skipped'
    elif j.get('informational'): status[n] = 'done (informational)'
    else: status[n] = 'PASS' if j.get('ok') else 'FAIL'
failed = [n for n in required if not status.get(n, '').startswith('PASS')]
overall = 'PASS' if not failed else 'FAIL'
perf = S['perf'] or {}
regress = [r for r in perf.get('rows', []) if 'REGRESSION' in str(r[6]) or 'OVER BUDGET' in str(r[6])]
better = [r for r in perf.get('rows', []) if str(r[6]).startswith('better')]


def fmt(v):
    if v is None: return 'n/a'
    if isinstance(v, float): return f'{v:.1f}' if abs(v) < 100 else f'{v:.0f}'
    return str(v)


def was(r):
    return f' (was {fmt(r[4])}, {r[5]})' if r[4] not in (None, '–') else ''


# ── Markdown ──
md = [f"# One Roof {env.get('version', '?')} · test run · **{overall}**", '',
      f"{env.get('started', '')} · commit `{env.get('commit', '?')}` · {'quick' if env.get('quick') else 'full'} run · "
      f"total {env.get('total_seconds', '?')} s · screen {'LOCKED' if env.get('screen_locked') else 'unlocked'}", '',
      '## Summary', '', '| Suite | Result | Time | Detail |', '|---|---|---|---|']
f = S['functional']
detail = dict(
    functional=f"{f['passed']}/{f['checks']} checks in {len(f['journeys'])} journeys across three windows" if f else '',
    perf=(f"{len(perf.get('scenarios', {}))} scenarios + {len(perf.get('gestures', {}))} gestures vs baseline "
          f"{perf.get('baseline', {}).get('version') or '(none yet)'}") if perf else '',
    compare=('Warp vs One Roof, outside-in' if S['compare'] else ''),
    sim=(S['sim'] or {}).get('note', '') if S['sim'] else '')
for n in ('functional', 'perf', 'compare', 'sim'):
    md.append(f"| {n}{' (required)' if n in required else ''} | {status[n]} | {times.get(n, '–')} s | {detail.get(n, '')} |")
md += ['']
md.append('**Regressions and budget misses:** ' + ('none' if not regress else '; '.join(f'{r[1]} {r[2]} {fmt(r[3])}{was(r)} {r[6]}' for r in regress)))
md.append('')
md.append('**Changes vs last release:** ' + ('no baseline yet' if not perf.get('baseline', {}).get('version') else
          (f"{len(better)} measures better, {len(regress)} worse beyond limits; full table below")))
for fl in [x for n in required for x in ((S.get(n) or {}).get('fails') or [])][:20]: md.append(f'- ✗ {fl}')
if perf.get('notes') or (S['compare'] or {}).get('notes'):
    md += ['', '**Notes:**'] + [f'- {n}' for n in perf.get('notes', [])]
md += ['']

if f:
    md += ['## Functional journeys', '', '| Journey | Checks | Result | Screenshots |', '|---|---|---|---|']
    for j in f['journeys']:
        md.append(f"| {j['name']} | {sum(c['ok'] for c in j['checks'])}/{len(j['checks'])} | {'PASS' if j['ok'] else 'FAIL'} | "
                  + ' '.join(f'[{pathlib.Path(s).stem.replace("st-", "")}]({s})' for s in j['shots']
                             if not re.search(r'-window\d+\.png$', s)) + ' |')   # the other windows' captures: in the HTML
    bad = [(j['name'], c) for j in f['journeys'] for c in j['checks'] if not c['ok']]
    if bad: md += ['', 'Failed checks:'] + [f'- {n}: `{c["what"]}`' for n, c in bad]
    md += ['']
if perf:
    md += ['## Performance vs baseline', '',
           f"Baseline: {perf.get('baseline', {}).get('version') or 'none'} · limits: worse than baseline by >{env.get('regression_pct', 25)} % "
           'and the per-measure minimum fails; budgets in scripts/test/limits.json', '',
           '| Kind | Name | Measure | Now | Baseline | Change | Verdict |', '|---|---|---|---|---|---|---|']
    md += [f'| {g} | {n} | {k} | {fmt(v)} | {fmt(b)} | {d} | {vd} |' for g, n, k, v, b, d, vd in perf.get('rows', [])]
    tc = perf.get('text_checks', [])
    if tc: md += ['', 'Terminal text after resizes: ' + '; '.join(('✓ ' if c['ok'] else '✗ ') + c['what'] for c in tc)]
    md += ['']
c = S['compare']
if c:
    md += ['## Compared with Warp (outside-in, informational)', '']
    if c.get('warp') == 'not installed': md.append('Warp is not installed: skipped.')
    apps = c.get('apps', {})
    keys = ['idle CPU %', 'idle RSS MB', 'processes', 'resize burst CPU s (20 resizes)', 'redraw settle ms', 'in-between frames']
    get = {'idle CPU %': lambda a: a.get('idle', {}).get('cpu_pct'), 'idle RSS MB': lambda a: a.get('idle', {}).get('rss_mb'),
           'processes': lambda a: a.get('idle', {}).get('procs'), 'resize burst CPU s (20 resizes)': lambda a: a.get('resize_burst_cpu_s'),
           'redraw settle ms': lambda a: a.get('redraw_settle_ms'), 'in-between frames': lambda a: a.get('in_between_frames')}
    if apps:
        md += ['| Measure | ' + ' | '.join(apps) + ' |', '|---|' + '---|' * len(apps)]
        md += [f'| {k} | ' + ' | '.join(fmt(get[k](a)) for a in apps.values()) + ' |' for k in keys]
    md += [''] + [f'- {n}' for n in c.get('notes', []) + c.get('fairness', [])] + ['']
SIM = S['sim']
if SIM is not None or 'sim' in env.get('suites', []):
    md += ['## Simulator', '', (SIM or {}).get('note', 'no result'), '']
(out / 'report.md').write_text('\n'.join(md) + '\n')

# ── HTML ──
E = html.escape


def bars(title, items, unit=''):
    """items: [(label, now, base)] → a horizontal bar chart, now (solid) over baseline (outline)."""
    items = [(l, n, b) for l, n, b in items if isinstance(n, (int, float))]
    if not items: return ''
    mx = max([n for _, n, _ in items] + [b for _, _, b in items if isinstance(b, (int, float))] + [1e-9])
    rh, lw, W = 26, 190, 640
    h = rh * len(items) + 30
    g = [f'<svg viewBox="0 0 {W} {h}" width="100%" role="img" aria-label="{E(title)}"><text x="0" y="14" class="ct">{E(title)}</text>']
    for i, (l, n, b) in enumerate(items):
        y = 24 + i * rh; bw = (W - lw - 70)
        g.append(f'<text x="0" y="{y + 13}" class="cl">{E(str(l))}</text>')
        if isinstance(b, (int, float)):
            g.append(f'<rect x="{lw}" y="{y + 1}" width="{max(1, b / mx * bw):.1f}" height="16" class="cb"/>')
        g.append(f'<rect x="{lw}" y="{y + 5}" width="{max(1, n / mx * bw):.1f}" height="8" class="cn"/>')
        g.append(f'<text x="{lw + max(1, n / mx * bw) + 6:.1f}" y="{y + 13}" class="cv">{fmt(n)}{unit}</text>')
    g.append('</svg>')
    return ''.join(g)


def table(head, rows, cls=''):
    t = [f'<table class="{cls}"><tr>' + ''.join(f'<th>{E(h)}</th>' for h in head) + '</tr>']
    for r in rows:
        t.append('<tr>' + ''.join(f'<td>{c}</td>' for c in r) + '</tr>')
    return ''.join(t) + '</table>'


def badge(s):
    k = 'ok' if s.startswith('PASS') or s.startswith('done') else 'bad' if s.startswith('FAIL') else 'mute'
    return f'<span class="b {k}">{E(s)}</span>'


H = [f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>One Roof Test Run</title><style>
:root{{--bg:#fbfbfa;--fg:#1d1d1f;--mute:#6e6e73;--line:#e3e3e0;--card:#fff;--ok:#1f7a3d;--okbg:#e3f4e8;--bad:#b42318;--badbg:#fde8e7;
--bar:#2f6fde;--base:#b9c6dc}}
@media (prefers-color-scheme:dark){{:root{{--bg:#151517;--fg:#ececee;--mute:#9a9aa0;--line:#2c2c30;--card:#1d1d20;--ok:#5ad17f;--okbg:#173322;
--bad:#ff7b72;--badbg:#3a1a19;--bar:#6aa1ff;--base:#3c4a63}}}}
body{{margin:0;background:var(--bg);color:var(--fg);font:14px/1.45 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif}}
main{{max-width:1100px;margin:0 auto;padding:24px 16px 64px}} h1{{font-size:24px;margin:0 0 4px}} h2{{font-size:18px;margin:32px 0 10px}}
.meta{{color:var(--mute)}} .card{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 16px;margin:12px 0}}
table{{border-collapse:collapse;width:100%;font-size:13px}} th,td{{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top}}
th{{color:var(--mute);font-weight:600}} td.n{{font-family:"SF Mono",ui-monospace,monospace}} .wrap{{overflow-x:auto}}
.b{{display:inline-block;padding:1px 8px;border-radius:999px;font-size:12px;font-weight:600}} .ok{{color:var(--ok);background:var(--okbg)}}
.bad{{color:var(--bad);background:var(--badbg)}} .mute{{color:var(--mute);border:1px solid var(--line)}}
.shots{{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:10px}} .shots a{{color:inherit;text-decoration:none;font-size:12px}}
.shots img{{width:100%;border:1px solid var(--line);border-radius:9px;display:block;margin-bottom:4px}}
svg text{{fill:var(--fg);font-size:12px}} .ct{{font-weight:600}} .cl,.cv{{fill:var(--mute)}} .cn{{fill:var(--bar)}} .cb{{fill:none;stroke:var(--base);stroke-width:2}}
ul{{padding-left:20px}} code{{font-family:"SF Mono",ui-monospace,monospace;font-size:12px}}
</style></head><body><main>
<h1>One Roof {E(str(env.get('version', '?')))} · test run {badge(overall)}</h1>
<div class="meta">{E(env.get('started', ''))} · commit <code>{E(env.get('commit', '?'))}</code> · {'quick' if env.get('quick') else 'full'} run ·
total {E(str(env.get('total_seconds', '?')))} s · screen {'<b>locked</b>' if env.get('screen_locked') else 'unlocked'}</div>
<h2>Summary</h2><div class="card wrap">''']
H.append(table(['Suite', 'Result', 'Time', 'Detail'],
               [[E(n) + (' <span class="meta">(required)</span>' if n in required else ''), badge(status[n]), f'{times.get(n, "–")} s', E(detail.get(n, ''))]
                for n in ('functional', 'perf', 'compare', 'sim')]))
H.append('<p><b>Regressions and budget misses:</b> ' + ('none' if not regress else '; '.join(E(f'{r[1]} {r[2]} {fmt(r[3])}{was(r)} {r[6]}') for r in regress)) + '</p>')
fl = [x for n in required for x in ((S.get(n) or {}).get('fails') or [])]
if fl: H.append('<ul>' + ''.join(f'<li>{E(x)}</li>' for x in fl[:30]) + '</ul>')
if perf.get('notes'): H.append('<p><b>Notes</b></p><ul>' + ''.join(f'<li>{E(n)}</li>' for n in perf['notes']) + '</ul>')
H.append('</div>')
if f:
    H.append('<h2>Functional journeys</h2><div class="card wrap">')
    H.append(table(['Journey', 'Checks', 'Result', 'Failed checks'],
                   [[E(j['name']), f"{sum(c['ok'] for c in j['checks'])}/{len(j['checks'])}", badge('PASS' if j['ok'] else 'FAIL'),
                     '<br>'.join(f'<code>{E(c["what"])}</code>' for c in j['checks'] if not c['ok'])] for j in f['journeys']]))
    H.append('</div><div class="shots">')
    for j in f['journeys']:
        for s in j['shots']:
            H.append(f'<a href="{E(s)}"><img loading="lazy" src="{E(s)}" alt="{E(j["name"])}">{E(pathlib.Path(s).stem.replace("st-", ""))}</a>')
    H.append('</div>')
if perf:
    gest = perf.get('gestures', {}); bg = {}
    if perf.get('baseline', {}).get('path'):
        try: bg = json.loads(pathlib.Path(perf['baseline']['path']).read_text())
        except OSError: bg = {}
    H.append('<h2>Performance vs baseline</h2><div class="card">')
    H.append(bars('Main-thread hitch time during gestures (ms per s; bar = now, outline = baseline)',
                  [(g, r.get('hitch_ms_per_s'), bg.get('gestures', {}).get(g, {}).get('hitch_ms_per_s')) for g, r in gest.items()], ' ms/s'))
    H.append(bars('Longest main-thread gap per gesture (ms)',
                  [(g, r.get('longest_ms'), bg.get('gestures', {}).get(g, {}).get('longest_ms')) for g, r in gest.items()], ' ms'))
    H.append(bars('Terminal size changes per gesture',
                  [(g, r.get('size_changes'), bg.get('gestures', {}).get(g, {}).get('size_changes')) for g, r in gest.items()]))
    H.append(bars('App CPU % per scenario', [(s, r.get('app_cpu'), bg.get('scenarios', {}).get(s, {}).get('app_cpu'))
                                              for s, r in perf.get('scenarios', {}).items()], ' %'))
    H.append('</div><div class="card wrap">')
    H.append(table(['Kind', 'Name', 'Measure', 'Now', 'Baseline', 'Change', 'Verdict'],
                   [[E(g), E(n), E(k), f'<span class="n">{fmt(v)}</span>', f'<span class="n">{fmt(b)}</span>', E(d),
                     (badge(vd) if vd and ('REGRESSION' in vd or 'OVER' in vd) else E(vd))] for g, n, k, v, b, d, vd in perf.get('rows', [])]))
    H.append('</div>')
if c:
    apps = c.get('apps', {})
    H.append('<h2>Compared with Warp <span class="meta">(outside-in, informational)</span></h2><div class="card">')
    if apps:
        H.append(bars('Idle CPU % (two terminals open)', [(a, v.get('idle', {}).get('cpu_pct'), None) for a, v in apps.items()], ' %'))
        H.append(bars('Idle memory, RSS MB (all processes)', [(a, v.get('idle', {}).get('rss_mb'), None) for a, v in apps.items()], ' MB'))
        H.append('<div class="wrap">' + table(['Measure'] + list(apps), [[E(k)] + [f'<span class="n">{fmt(get[k](a))}</span>' for a in apps.values()]
                                                                       for k in keys]) + '</div>')
    H.append('<ul>' + ''.join(f'<li>{E(n)}</li>' for n in c.get('notes', []) + c.get('fairness', [])) + '</ul></div>')
if SIM is not None or 'sim' in env.get('suites', []):
    H.append(f'<h2>Simulator</h2><div class="card">{E((SIM or {}).get("note", "no result"))}</div>')
H.append('<p class="meta">Made by app/scripts/oneroof-test (LAB-1594…1599). Markdown twin: report.md.</p></main></body></html>')
(out / 'report.html').write_text('\n'.join(H))
(out / 'summary.json').write_text(json.dumps(dict(version=env.get('version'), overall=overall, status=status, required=required,
                                                  failed=failed, regressions=[list(map(str, r)) for r in regress]), indent=1))
print(f'report: {overall} · ' + ' · '.join(f'{n} {st}' for n, st in status.items()))
sys.exit(0 if overall == 'PASS' else 1)
