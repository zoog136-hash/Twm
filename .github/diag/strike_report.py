#!/usr/bin/env python3
"""What runs inside an attack: from each entry of the strike/impact handler
to the end of that frame (next frame probe / process tail), time between
consecutive FN lines goes to the function entered last."""
import sys, collections
START = ('world.gd:_release_player_attack_timed', 'world.gd:_impact_player_attack_timed')
END = ('frame_hitch_probe.gd:_notification', 'frame_hitch_log.gd:_mark_process_tail')
agg = collections.Counter(); calls = collections.Counter(); windows = []
cur = None; prev = None
for line in open(sys.argv[1], errors='replace'):
    if not line.startswith('FN '): continue
    parts = line.split()
    if len(parts) < 3: continue
    t = int(parts[1]); fn = parts[2]
    if cur is not None and prev is not None:
        cur['fns'][prev[1]] += t - prev[0]
    if cur is not None and fn.endswith(END):
        cur['us'] = t - cur['t0']; windows.append(cur); cur = None
    if cur is None and fn.endswith(START):
        cur = {'t0': t, 'start': fn.split(':')[-1], 'fns': collections.Counter()}
    if cur is not None: calls[fn] += 1
    prev = (t, fn)
for w in windows: agg.update(w['fns'])
total = sum(w['us'] for w in windows)
print(f'attack windows={len(windows)} total={total/1000:.1f} ms mean={total/1000/max(1,len(windows)):.1f} ms')
for fn, us in agg.most_common(45):
    print(f'  {us/1000:>9.1f} ms  {calls[fn]:>7} calls  {fn}')
print('----- longest attack windows')
for w in sorted(windows, key=lambda w: -w['us'])[:6]:
    print(f"  {w['us']/1000:.1f} ms from {w['start']}: " + ', '.join(f"{f.split('/')[-1]}={u/1000:.1f}" for f, u in w['fns'].most_common(10)))
