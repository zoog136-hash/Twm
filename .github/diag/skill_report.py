#!/usr/bin/env python3
"""Per cast (DIAG_TRACE mark cast <label>) in fn_skills.txt: traced main-thread
time until the next cast, and the functions that took it."""
import sys, collections
casts = []; cur = None; prev = None; last_other = None
NOISE = ('trail', '_mark_process_tail', '_notification', 'now', 'detail', 'nested', 'count', 'detail_next', 'add', 'add_self')
for line in open(sys.argv[1], errors='replace'):
    if line.startswith('DIAG_TRACE mark cast '):
        cur = {'label': line[len('DIAG_TRACE mark cast '):].strip(), 'fn': collections.Counter(), 'calls': collections.Counter(), 'total': 0, 'call': True, 'cfn': collections.Counter(), 'ctotal': 0, 'callers': collections.defaultdict(collections.Counter), 'seq': []}
        casts.append(cur); prev = None; continue
    if line.startswith('DIAG_TRACE mark called'):
        if cur: cur['call'] = False
        prev = None; continue
    if line.startswith('DIAG_TRACE end'): cur = None; continue
    if cur is None or not line.startswith('FN '): continue
    parts = line.split()
    if len(parts) < 3: continue
    t = int(parts[1]); fn = parts[2]
    if prev:
        d = t - prev[0]
        if cur['call']:
            cur['cfn'][prev[1]] += d; cur['ctotal'] += d
        elif d < 3000 and not prev[1].endswith(('trail', '_mark_process_tail', '_notification', 'now', 'detail', 'nested')):
            # After the call: frames until the next cast. Gaps over 3 ms are
            # engine/idle time, and the frame probes themselves are not counted.
            cur['fn'][prev[1]] += d; cur['total'] += d
    cur['calls'][fn] += 1
    if cur['call']:
        short = fn.split('/')[-1]
        cur['callers'][short][last_other] += 1
        if not cur['seq'] or cur['seq'][-1][0] != short: cur['seq'].append([short, 1])
        else: cur['seq'][-1][1] += 1
        if not short.endswith(NOISE) and short not in ('current523_definition_rows.gd:row', 'current523_definition_rows.gd:_row_at', 'current523_definition_rows.gd:_view', 'current523_definition_rows.gd:_open', 'current523_definition_rows.gd:_store'):
            last_other = short
    prev = (t, fn)
print('=== cast() call itself (traced ms)')
for c in sorted(casts, key=lambda c: -c['ctotal'])[:12]:
    print(f"--- {c['ctotal']/1000:8.1f} ms  {c['label']}")
    for fn, us in c['cfn'].most_common(10):
        short = fn.split('/')[-1]
        who = ', '.join(f"{(k or '-')}={n}" for k, n in c['callers'][short].most_common(3))
        print(f"      {us/1000:8.1f} ms {c['calls'][fn]:>7}  {short}   <- {who}")
for c in sorted(casts, key=lambda c: -c['ctotal'])[:1]:
    print(f"=== call sequence of {c['label']} (first 260 entries, repeats folded)")
    for short, n in c['seq'][:260]:
        print(f"    {n:>5} {short}")
print('=== frames after the call (script time, ms)')
for c in sorted(casts, key=lambda c: -c['total'])[:int(sys.argv[2]) if len(sys.argv) > 2 else 16]:
    print(f"--- {c['total']/1000:8.1f} ms  {c['label']}")
    for fn, us in c['fn'].most_common(8):
        print(f"      {us/1000:8.1f} ms {c['calls'][fn]:>7}  {fn.split('/')[-1]}")
agg = collections.Counter(); calls = collections.Counter()
for c in casts:
    agg.update(c['fn']); calls.update(c['calls'])
print('=== all casts together')
for fn, us in agg.most_common(30):
    print(f"  {us/1000:9.1f} ms {calls[fn]:>8}  {fn.split('/')[-1]}")
