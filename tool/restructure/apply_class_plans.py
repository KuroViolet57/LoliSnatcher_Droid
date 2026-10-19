#!/usr/bin/env python3
"""Applies tool/restructure/m3_class_plans.json with split_class_ext.py.

    python tool/restructure/apply_class_plans.py              # split every class
    python tool/restructure/apply_class_plans.py --fix-imports <analyze.log>

After the split, a file that calls an extension method but does not import the
class's library (it reached the object through another one) no longer compiles.
--fix-imports reads `flutter analyze` output and, for every
"The method/getter/setter 'x' isn't defined for the type 'C'" error where C is
a split class, adds `import '<C's library>';` to that file (once). Imports are
the only change; run analyze again afterwards.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
PLANS = os.path.join(HERE, 'm3_class_plans.json')


def split_all():
    plans = json.load(open(PLANS, encoding='utf-8'))
    for lib, spec in plans.items():
        with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, encoding='utf-8') as f:
            json.dump(spec['parts'], f)
            tmp = f.name
        try:
            r = subprocess.run([sys.executable, os.path.join(HERE, 'split_class_ext.py'), lib, spec['class'], tmp], cwd=ROOT)
        finally:
            os.unlink(tmp)
        if r.returncode != 0:
            print('STOPPED at', lib)
            sys.exit(r.returncode)


def fix_imports(log_path):
    plans = json.load(open(PLANS, encoding='utf-8'))
    lib_of = {spec['class']: lib for lib, spec in plans.items()}
    rx = re.compile(r"The (?:method|getter|setter|operator) '([^']+)' isn't defined for the type '(\w+)'.* - (\S+\.dart):(\d+):(\d+)")
    need = {}
    for line in open(log_path, encoding='utf-8', errors='replace'):
        m = rx.search(line)
        if m and m.group(2) in lib_of:
            f = m.group(3).replace('\\', '/')
            # a part cannot import: the import goes to its library
            src = open(os.path.join(ROOT, f), encoding='utf-8', newline='').read()
            po = re.search(r"^part of '([^']+)';", src, re.M)
            if po:
                f = os.path.normpath(os.path.join(os.path.dirname(f), po.group(1))).replace('\\', '/')
            need.setdefault(f, set()).add(lib_of[m.group(2)])
    for f, libs in sorted(need.items()):
        path = os.path.join(ROOT, f)
        text = open(path, encoding='utf-8', newline='').read()
        nl = '\r\n' if '\r\n' in text else '\n'
        lines = text.split(nl)
        last_import = max((i for i, l in enumerate(lines) if l.startswith('import ')), default=-1)
        added = []
        for lib in sorted(libs):
            uri = 'package:lolisnatcher/' + lib[len('lib/'):]
            if f"import '{uri}';" in text:
                continue
            lines.insert(last_import + 1, f"import '{uri}';")
            last_import += 1
            added.append(uri)
        if added:
            open(path, 'w', encoding='utf-8', newline='').write(nl.join(lines))
            print(f, '+', added)


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == '--fix-imports':
        fix_imports(sys.argv[2])
    else:
        split_all()
