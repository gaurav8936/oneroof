#!/usr/bin/env python3
"""One measured window of a One Roof test build (LAB-1325). Observe-only: never signals any process.

  measure.py <out dir> <secs> <app pid> [selftest log]

Groups: the app pid, and every roofd whose executable lives in the same bundle (daemon, session holders, attach relays).
Per group: CPU % from cumulative cpu-time deltas (ps, start/end), context switches/s (top CSW deltas, the wake-up
proxy), footprint (top MEM) and RSS. The app's direct children are polled every 5 ms (libproc) to count process
launches (git, launchctl, osascript, …) with their argv. With a self-test log, model changes/s are read from its
"perf: N model changes in 5 s" lines inside the window. Writes <out>/{measure.json,top.txt,children.txt}."""
import collections, ctypes, ctypes.util, json, pathlib, re, statistics as st, struct, subprocess, sys, threading, time

out = pathlib.Path(sys.argv[1]); secs = int(sys.argv[2]); app = int(sys.argv[3])
stlog = pathlib.Path(sys.argv[4]) if len(sys.argv) > 4 else None
out.mkdir(parents=True, exist_ok=True)


def psall():
    r = subprocess.run(['ps', '-axww', '-o', 'pid=,ppid=,rss=,time=,comm='], capture_output=True, text=True).stdout
    rows = []
    for line in r.splitlines():
        p = line.split(None, 4)
        if len(p) == 5: rows.append(dict(pid=int(p[0]), ppid=int(p[1]), rss=int(p[2]), time=p[3], comm=p[4]))
    return rows


def exe(pid):
    t = subprocess.run(['lsof', '-a', '-p', str(pid), '-d', 'txt', '-Fn'], capture_output=True, text=True).stdout
    return next((l[1:] for l in t.splitlines() if l.startswith('n') and l.endswith(('/roofd', '/OneRoof'))), '')


def tsec(t):
    s = 0.0
    for x in t.split(':'): s = s * 60 + float(x)
    return s


rows = psall()
me = next((r for r in rows if r['pid'] == app), None)
if not me: sys.exit(f'measure: pid {app} is not running')
bundle = me['comm'].split('/Contents/MacOS/')[0]
groups = {'app': [app], 'roofd': []}
for r in rows:
    c = r['comm']
    if r['pid'] == app: continue
    if c.startswith(bundle + '/Contents/MacOS/roofd') or ((c == 'roofd' or c.endswith('/roofd')) and exe(r['pid']).startswith(bundle)):
        groups['roofd'].append(r['pid'])
allp = [p for v in groups.values() for p in v]

# children of the app, polled every 5 ms through libproc, with argv (KERN_PROCARGS2)
lib = ctypes.CDLL('/usr/lib/libproc.dylib'); libc = ctypes.CDLL(ctypes.util.find_library('c'))
cbuf = (ctypes.c_int * 1024)()


def argv(p):
    mib = (ctypes.c_int * 3)(1, 49, p); size = ctypes.c_size_t(65536); b = ctypes.create_string_buffer(65536)
    if libc.sysctl(mib, 3, b, ctypes.byref(size), None, 0) != 0: return '(gone)'
    raw = b.raw[:size.value]; argc = struct.unpack('i', raw[:4])[0]
    parts = [x for x in raw[4:].split(b'\0') if x]
    return ' '.join(x.decode(errors='replace') for x in parts[1:1 + argc])


children, stop = [], threading.Event()


def poll():
    seen = None
    while not stop.is_set():
        n = lib.proc_listchildpids(app, cbuf, ctypes.sizeof(cbuf))
        cur = set(c for c in cbuf[:max(0, n)] if c)
        if seen is None: seen = set(cur)   # already running when the window opened: not launches
        for c in cur - seen:
            seen.add(c); children.append((round(time.time() - t0, 2), c, argv(c)))
        time.sleep(0.005)


def snap():
    return {r['pid']: r for r in psall() if r['pid'] in allp}


t0 = time.time()
a = snap()
th = threading.Thread(target=poll, daemon=True); th.start()
cmd = ['top', '-l', str(secs // 2 + 1), '-s', '2', '-stats', 'pid,command,cpu,csw,mem']
for p in allp: cmd += ['-pid', str(p)]
top = subprocess.run(cmd, capture_output=True, text=True).stdout
stop.set(); th.join()
b = snap()
t1 = time.time(); el = t1 - t0
(out / 'top.txt').write_text(top)
(out / 'children.txt').write_text('\n'.join(f'{t}\t{p}\t{c}' for t, p, c in children))


def mb(s):
    m = re.match(r'([\d.]+)([BKMG])', s)
    return float(m.group(1)) * {'B': 1 / 2**20, 'K': 1 / 1024, 'M': 1, 'G': 1024}[m.group(2)] if m else 0.0


blocks, cur = [], None
for line in top.splitlines():
    if line.startswith('Processes:'): cur = {}; blocks.append(cur); continue
    m = re.match(r'\s*(\d+)\*?\s+(.+?)\s+([\d.]+)\s+(\d+)\+?\s+(\S+)\s*$', line)
    if m and cur is not None:
        pid, _, cpu, csw, mem = m.groups()
        cur[int(pid)] = dict(cpu=float(cpu), csw=int(csw), mem=mb(mem))

res = dict(window_s=round(el, 1), bundle=pathlib.Path(bundle).name, load=subprocess.run(['sysctl', '-n', 'vm.loadavg'], capture_output=True, text=True).stdout.strip())
for g, pids in groups.items():
    first = blocks[1] if len(blocks) > 1 else {}; last = blocks[-1] if blocks else {}
    dt = 2.0 * (len(blocks) - 2) if len(blocks) > 2 else 1
    cput = sum(tsec(b[p]['time']) - tsec(a[p]['time']) for p in pids if p in a and p in b)
    cpus = sorted(sum(bl[p]['cpu'] for p in pids if p in bl) for bl in blocks[1:]) or [0]
    res[g] = dict(procs=len(pids), cpu_pct=round(cput / el * 100, 2), cpu_p95=cpus[min(len(cpus) - 1, int(.95 * len(cpus)))],
                  csw_per_s=round(sum(last[p]['csw'] - first[p]['csw'] for p in pids if p in first and p in last) / dt, 1),
                  footprint_mb=round(sum(last[p]['mem'] for p in pids if p in last)),
                  rss_mb=round(sum(b[p]['rss'] for p in pids if p in b) / 1024))
by = collections.Counter(re.sub(r'^.*/', '', (c or '(gone)').split()[0]) + ' ' + ' '.join((c or '').split()[1:3]) for _, _, c in children)
res['children'] = dict(total=len(children), per_min=round(len(children) / el * 60, 1), top=by.most_common(12))

# model changes per second from the self-test log ("<t> perf: N model changes in 5 s"; t = epoch mod 10000)
if stlog and stlog.exists():
    lo, hi = t0 % 10_000, t1 % 10_000
    vals = []
    for line in stlog.read_text().splitlines():
        m = re.match(r'([\d.]+) perf: (\d+) model changes in 5 s', line)
        if m:
            t = float(m.group(1))
            if (lo <= t <= hi) if lo <= hi else (t >= lo or t <= hi): vals.append(int(m.group(2)) / 5)
    res['model_changes_per_s'] = round(st.mean(vals), 2) if vals else None
(out / 'measure.json').write_text(json.dumps(res, indent=1))
print(json.dumps(res))
