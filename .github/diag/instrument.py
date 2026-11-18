#!/usr/bin/env python3
"""Diag only: add a function-entry trace line to every multi-line GDScript
function under <project>/scripts. The line prints only while
Engine.has_meta("diag_trace") (set by the diag driver around one call)."""
import os, re, sys
root = sys.argv[1]
func_re = re.compile(r'^(\s*)(static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(.*\)\s*(->\s*[^:]+)?:\s*(#.*)?$')
count = 0
for base, _, files in os.walk(os.path.join(root, 'scripts')):
    for name in files:
        if not name.endswith('.gd'): continue
        path = os.path.join(base, name)
        rel = os.path.relpath(path, root)
        lines = open(path, encoding='utf-8').read().split('\n')
        out = []
        i = 0
        changed = False
        while i < len(lines):
            line = lines[i]
            out.append(line)
            m = func_re.match(line)
            if m and i + 1 < len(lines):
                # Body indentation = indentation of the next non-empty line.
                j = i + 1
                while j < len(lines) and (not lines[j].strip() or lines[j].strip().startswith('#')):
                    j += 1
                if j < len(lines):
                    body = lines[j]
                    indent = body[:len(body) - len(body.lstrip())]
                    if len(indent) > len(m.group(1)):
                        tag = f"{rel}:{m.group(3)}"
                        out.append(f'{indent}if Engine.has_meta(&"diag_trace"): printerr("FN ", Time.get_ticks_usec(), " {tag}")')
                        count += 1
                        changed = True
            i += 1
        if changed:
            open(path, 'w', encoding='utf-8').write('\n'.join(out))
print('instrumented functions:', count)
