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
# Who enters the hot functions: the function entered just before each call
# that is not itself one of them (approximate caller).
WATCH = ('current523_native_item_projection.gd:record', 'patch523_monster_drops.gd:_current_native_bindings', 'skill_catalog.gd:enabled', 'reference_sp2_bank.gd:valid_sha', 'current523_native_fields.gd:field_view', 'current523_aden_play_renderer.gd:_read_chunk', 'current523_tile_pack.gd:texture_for')
prev_other = None; callers = collections.defaultdict(collections.Counter)
for line in open(sys.argv[1], errors='replace'):
    if not line.startswith('FN '): continue
    parts = line.split()
    if len(parts) < 3: continue
    fn = parts[2]
    hit = next((w for w in WATCH if fn.endswith(w)), None)
    if hit:
        callers[hit][prev_other] += 1
    elif not fn.endswith(('_integer', 'integer', 'field', 'field_view', 'valid_sha', 'label', 'row', 'identity', 'trail', 'detail', 'count', 'now')):
        prev_other = fn
for w, c in callers.items():
    print(f'--- callers of {w}:', ', '.join(f'{(k or "-").split("/")[-1]}={n}' for k, n in c.most_common(6)))
