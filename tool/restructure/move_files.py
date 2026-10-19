#!/usr/bin/env python3
"""Move Dart files to new homes and rewrite every reference to them.

Used for the 1.0 restructure (docs/superpowers/plans/2026-10-04-1.0-rebuild.md).

    python tool/restructure/move_files.py <mapping.json> [--dry-run]

<mapping.json> is {"lib/src/old/path.dart": "lib/new/path.dart", ...}.

What it does, in order:
1. checks the mapping: every source exists, no two sources share a target,
   no target already exists, every path is under lib/;
2. `git mv` each file (history follows the file);
3. rewrites, in lib/ and test/:
   - `package:lolisnatcher/<old>` imports/exports to the new URI,
   - relative imports/exports/parts (re-resolved from the file's NEW place),
   - string literals naming an old path ('lib/src/...dart') in tests;
4. verifies that every moved file is byte-identical to its old content once
   import/export/part lines are removed (the move changed nothing else).

Line endings are kept as they are (the working tree is CRLF on this PC).
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PKG = 'package:lolisnatcher/'
DIRECTIVE = re.compile(r"""^(\s*(?:import|export|part)\s+)(['"])([^'"]+)\2""", re.M)
PART_OF = re.compile(r"""^(\s*part\s+of\s+)(['"])([^'"]+)\2""", re.M)


def norm(p):
    return p.replace('\\', '/')


def lib_rel(path):
    """lib/src/a.dart -> src/a.dart (the part after package:lolisnatcher/)."""
    assert path.startswith('lib/'), path
    return path[len('lib/'):]


def dart_files(*dirs):
    for d in dirs:
        for base, _, files in os.walk(os.path.join(ROOT, d)):
            for f in files:
                if f.endswith('.dart'):
                    yield norm(os.path.relpath(os.path.join(base, f), ROOT))


def strip_directives(text):
    text = PART_OF.sub('', text)
    return DIRECTIVE.sub('', text)


def main():
    mapping_path = sys.argv[1]
    dry = '--dry-run' in sys.argv
    mapping = {norm(k): norm(v) for k, v in json.load(open(mapping_path, encoding='utf-8')).items() if norm(k) != norm(v)}

    # 1. checks
    targets = {}
    for old, new in mapping.items():
        assert old.startswith('lib/') and new.startswith('lib/'), (old, new)
        assert os.path.isfile(os.path.join(ROOT, old)), f'missing source {old}'
        assert new not in targets, f'two sources for {new}: {targets[new]} and {old}'
        targets[new] = old
        if new not in mapping:  # a target may be a source that also moves away
            assert not os.path.exists(os.path.join(ROOT, new)), f'target exists {new}'
    print(f'{len(mapping)} files to move')
    if dry:
        return

    before = {old: open(os.path.join(ROOT, old), encoding='utf-8', newline='').read() for old in mapping}

    # 2. git mv (two-step through a temp name so chains/swaps cannot collide)
    for old in mapping:
        tmp = old + '.__moving__'
        subprocess.run(['git', 'mv', old, tmp], cwd=ROOT, check=True)
    for old, new in mapping.items():
        os.makedirs(os.path.dirname(os.path.join(ROOT, new)), exist_ok=True)
        subprocess.run(['git', 'mv', old + '.__moving__', new], cwd=ROOT, check=True)

    uri_map = {PKG + lib_rel(o): PKG + lib_rel(n) for o, n in mapping.items()}
    inverse = {n: o for o, n in mapping.items()}

    # 3. rewrite references
    changed = 0
    for f in dart_files('lib', 'test'):
        path = os.path.join(ROOT, f)
        text = open(path, encoding='utf-8', newline='').read()
        orig = text
        old_self = inverse.get(f, f)  # where this file used to live

        def fix_directive(m):
            head, q, uri = m.group(1), m.group(2), m.group(3)
            if uri.startswith(PKG):
                return head + q + uri_map.get(uri, uri) + q
            if uri.startswith(('package:', 'dart:')):
                return m.group(0)
            # relative: resolve against the OLD location, map, re-relativise from the NEW one
            target_old = norm(os.path.normpath(os.path.join(os.path.dirname(old_self), uri)))
            target_new = mapping.get(target_old, target_old)
            rel = norm(os.path.relpath(target_new, os.path.dirname(f)))
            return head + q + rel + q

        text = DIRECTIVE.sub(fix_directive, text)
        text = PART_OF.sub(fix_directive, text)
        if f.startswith('test/'):
            for o, n in mapping.items():
                text = text.replace("'" + o + "'", "'" + n + "'").replace('"' + o + '"', '"' + n + '"')
        if text != orig:
            open(path, 'w', encoding='utf-8', newline='').write(text)
            changed += 1
    print(f'{changed} files had references rewritten')

    # 4. verify moved files changed only in their directives
    bad = []
    for old, new in mapping.items():
        after = open(os.path.join(ROOT, new), encoding='utf-8', newline='').read()
        if strip_directives(after) != strip_directives(before[old]):
            bad.append(new)
    if bad:
        print('CONTENT CHANGED BEYOND DIRECTIVES:', bad)
        sys.exit(1)
    print('verified: moved files differ only in import/export/part lines')


if __name__ == '__main__':
    main()
