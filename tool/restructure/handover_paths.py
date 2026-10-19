#!/usr/bin/env python3
"""Rewrites old lib/src paths in HANDOVER.md Part A to the 1.0 layout.

    python tool/restructure/handover_paths.py [--dry-run]

Part B (the build log) is history and stays verbatim. A path is rewritten when
it appears whole: `lib/src/x/y.dart`, or the lib/src-relative `x/y.dart` that
Part A uses, or a bare file name in backticks when exactly one file has it.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAPPING = json.load(open(os.path.join(ROOT, 'tool', 'restructure', 'mapping_m1.json'), encoding='utf-8'))


def main():
    path = os.path.join(ROOT, 'HANDOVER.md')
    text = open(path, encoding='utf-8', newline='').read()
    marker = '# PART B'
    cut = text.index(marker)
    part_a, part_b = text[:cut], text[cut:]

    pairs = []
    for old, new in MAPPING.items():
        rel_old = old[len('lib/src/'):] if old.startswith('lib/src/') else old[len('lib/'):]
        rel_new = new[len('lib/'):]
        pairs.append((old, new))
        pairs.append((rel_old, rel_new))
    # longest first so a/b/c.dart wins over b/c.dart
    pairs.sort(key=lambda p: -len(p[0]))
    counts = {}

    def repl_factory(old, new):
        def repl(m):
            counts[old] = counts.get(old, 0) + 1
            return m.group(1) + new
        return repl

    for old, new in pairs:
        if old == new:
            continue
        pat = re.compile(r'(^|[\s`(\[\'"])' + re.escape(old) + r'(?![\w/])', re.M)
        part_a = pat.sub(repl_factory(old, new), part_a)

    note = ('\n> **1.0 layout (2026-10-04):** the code moved from `lib/src/{boorus,data,handlers,pages,'
            'services,utils,widgets}` to `lib/{models,core,sources,features,app}` (docs/ARCHITECTURE.md). '
            'Paths in Part A below are the new ones; Part B keeps the old ones (old -> new for every '
            'file: `tool/restructure/mapping_m1.json`).\n')
    if '1.0 layout (2026-10-04)' not in part_a:
        part_a = part_a.replace('# PART A — the current state of the project\n',
                                '# PART A — the current state of the project\n' + note, 1)
    print('rewrites:', sum(counts.values()), 'distinct paths:', len(counts))
    if '--dry-run' not in sys.argv:
        open(path, 'w', encoding='utf-8', newline='').write(part_a + part_b)


if __name__ == '__main__':
    main()
