#!/usr/bin/env python3
"""Moves whole top-level declarations of a Dart library into `part` files.

    python tool/restructure/split_parts.py <lib/.../big.dart> <plan.json>

<plan.json>: {"<part name>": ["DeclName", "_OtherDecl", ...], ...}
Each part becomes <dir>/<big>/<part name>.dart holding `part of '../big.dart';`
and the listed declarations, in their original order and with their doc comments
and annotations. The library keeps its imports, gains one `part` line per part
and keeps every declaration not listed.

Parts share the library's imports and privacy, so nothing else changes: same
classes, same private names, same behaviour. The script proves it: the multiset
of declaration texts across the library and its parts must equal the original's
exactly (whitespace around chunks aside), and every listed name must exist once.
Line endings are kept.
"""
import collections
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dart_chunks import chunks  # noqa: E402


def norm(t):
    return t.strip().replace('\r\n', '\n')


def main():
    path, plan_path = sys.argv[1], sys.argv[2]
    plan = json.load(open(plan_path, encoding='utf-8'))
    src = open(path, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in src else '\n'
    cs, tail = chunks(src)
    assert ''.join(c.text for c in cs) + tail == src

    by_name = collections.defaultdict(list)
    for c in cs:
        if c.kind == 'decl':
            by_name[c.name].append(c)
    owner = {}
    for part, names in plan.items():
        for n in names:
            assert len(by_name.get(n, [])) == 1, f'{n}: found {len(by_name.get(n, []))} times'
            assert n not in owner, f'{n} listed twice'
            owner[n] = part

    base = os.path.splitext(os.path.basename(path))[0]
    folder = os.path.join(os.path.dirname(path), base)
    os.makedirs(folder, exist_ok=True)

    kept, parts = [], collections.OrderedDict((p, []) for p in plan)
    for c in cs:
        if c.kind == 'decl' and c.name in owner:
            parts[owner[c.name]].append(c)
        else:
            kept.append(c)

    # library: directives, then the part lines, then the remaining declarations
    last_directive = max((i for i, c in enumerate(kept) if c.kind == 'directive'), default=-1)
    part_lines = ''.join(f"{nl}part '{base}/{p}.dart';" for p in plan)
    lib_text = ''.join(c.text for c in kept[:last_directive + 1]) + nl + part_lines + ''.join(c.text for c in kept[last_directive + 1:]) + tail
    for p, items in parts.items():
        body = (nl + nl).join(c.text.strip() for c in items)
        text = f"part of '../{base}.dart';{nl}{nl}{body.strip()}{nl}"
        out = os.path.join(folder, f'{p}.dart')
        assert not os.path.exists(out), f'exists: {out}'
        open(out, 'w', encoding='utf-8', newline='').write(text)
    open(path, 'w', encoding='utf-8', newline='').write(lib_text)

    # proof: same declarations, each exactly once
    before = collections.Counter(norm(c.text) for c in cs if c.kind == 'decl')
    after = collections.Counter()
    for f in [path] + [os.path.join(folder, f'{p}.dart') for p in plan]:
        t = open(f, encoding='utf-8', newline='').read()
        for c in chunks(t)[0]:
            if c.kind == 'decl':
                after[norm(c.text)] += 1
    if before != after:
        missing = before - after
        extra = after - before
        print('MISMATCH: missing', len(missing), 'extra', len(extra))
        for t in list(missing)[:3]:
            print('missing:', t[:200])
        for t in list(extra)[:3]:
            print('extra:', t[:200])
        sys.exit(1)
    sizes = {p: sum(c.text.count('\n') for c in items) for p, items in parts.items()}
    print(f'{path}: {sum(before.values())} declarations, proof ok; library now {lib_text.count(chr(10))} lines; parts {sizes}')


if __name__ == '__main__':
    main()
