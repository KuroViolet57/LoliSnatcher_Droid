#!/usr/bin/env python3
"""Layer-rule report (same rule as test/architecture_test.dart).

    python tool/restructure/layer_report.py            # counts per layer pair
    python tool/restructure/layer_report.py --write    # rewrite test/architecture_allowlist.txt
    python tool/restructure/layer_report.py --list     # every violation, one per line
"""
import collections
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LAYERS = ['models', 'core', 'sources', 'logic', 'ui', 'app']
RX = re.compile(r'''^\s*(?:import|export)\s+['"]package:lolisnatcher/([^'"]+)['"]''', re.M)
HEADER = '''# Imports that broke the 1.0 layer rule when the app was restructured
# (models < core < sources < features/*/logic < features/*/ui < app).
# test/architecture_test.dart fails on any violation NOT listed here and on
# any listed line that is no longer a violation, so this list only shrinks.
# Fix one by moving the code down a layer or passing it in from above.
'''


def layer(p):
    if p.startswith('gen/'):
        return -2
    if p == 'main.dart' or p.startswith('app/'):
        return 5
    if p.startswith('models/'):
        return 0
    if p.startswith('core/'):
        return 1
    if p.startswith('sources/'):
        return 2
    if p.startswith('features/'):
        parts = p.split('/')
        if len(parts) > 2 and parts[2] == 'logic':
            return 3
        if len(parts) > 2 and parts[2] == 'ui':
            return 4
    return -1


def violations():
    found, unknown = set(), []
    lib = os.path.join(ROOT, 'lib')
    for d, _, fs in os.walk(lib):
        for f in fs:
            if not f.endswith('.dart'):
                continue
            rel = os.path.relpath(os.path.join(d, f), lib).replace(os.sep, '/')
            if rel.startswith('gen/'):
                continue
            if layer(rel) < 0:
                unknown.append(rel)
            src = open(os.path.join(d, f), encoding='utf-8').read()
            for m in RX.finditer(src):
                to = m.group(1)
                if layer(to) > layer(rel):
                    found.add(f'{rel} -> {to}')
    return found, unknown


def main():
    found, unknown = violations()
    if unknown:
        print('files outside the layers:', unknown)
    if '--list' in sys.argv:
        print('\n'.join(sorted(found)))
        return
    c = collections.Counter((LAYERS[layer(a.split(' -> ')[0])], LAYERS[layer(a.split(' -> ')[1])]) for a in found)
    for k, v in sorted(c.items(), key=lambda x: -x[1]):
        print(f'{v:4d}  {k[0]} -> {k[1]}')
    print('total', len(found))
    if '--write' in sys.argv:
        path = os.path.join(ROOT, 'test', 'architecture_allowlist.txt')
        with open(path, 'w', encoding='utf-8', newline='\n') as out:
            out.write(HEADER + '\n'.join(sorted(found)) + '\n')
        print('wrote', path)


if __name__ == '__main__':
    main()
