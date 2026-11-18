#!/usr/bin/env python3
"""Attribute time between consecutive FN lines to the function entered last,
per traced window (DIAG_TRACE begin/end markers)."""
import re, sys, collections
section = None; prev = None; agg = collections.defaultdict(lambda: collections.Counter()); calls = collections.defaultdict(collections.Counter); total = {}
for line in open(sys.argv[1], errors='replace'):
    if line.startswith('DIAG_TRACE begin '):
        section = line.split()[2]; prev = None; continue
    if line.startswith('DIAG_TRACE end '):
        if prev and section: pass
        total[section] = line.strip(); section = None; prev = None; continue
    if section and line.startswith('FN '):
        parts = line.split()
        if len(parts) < 3: continue
        t = int(parts[1]); fn = parts[2]
        if prev: agg[section][prev[1]] += t - prev[0]
        calls[section][fn] += 1
        prev = (t, fn)
for sec, counter in agg.items():
    print(f'=== {sec}: {total.get(sec, "")}')
    for fn, us in counter.most_common(18):
        print(f'  {us/1000:>9.1f} ms  {calls[sec][fn]:>7} calls  {fn}')
    print('  most called:', ', '.join(f'{fn.split(":")[-1]}={n}' for fn, n in calls[sec].most_common(8)))
