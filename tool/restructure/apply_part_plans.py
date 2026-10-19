#!/usr/bin/env python3
"""Applies every plan in tool/restructure/m3_part_plans.json with split_parts.py.

    python tool/restructure/apply_part_plans.py [plans.json]

Stops at the first library whose proof fails. A declaration a plan names that no
longer exists (renamed in a bug fix) stops the run too; fix the plan and rerun on
a clean tree.
"""
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    plans_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'm3_part_plans.json')
    plans = json.load(open(plans_path, encoding='utf-8'))
    for lib, plan in plans.items():
        with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, encoding='utf-8') as f:
            json.dump(plan, f)
            tmp = f.name
        try:
            r = subprocess.run([sys.executable, os.path.join(HERE, 'split_parts.py'), lib, tmp], cwd=ROOT)
        finally:
            os.unlink(tmp)
        if r.returncode != 0:
            print('STOPPED at', lib)
            sys.exit(r.returncode)
    print('all', len(plans), 'libraries split')


if __name__ == '__main__':
    main()
