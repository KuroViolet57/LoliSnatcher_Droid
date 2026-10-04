#!/usr/bin/env python3
"""Build the arm64 APK and park it on the K: drive BEFORE the tests run.

The user's workflow (2026-09-14): the tests take time and tokens, and a
session can run out of tokens before a build is delivered. So: apply the
change, run this script (it builds, waits, and copies the APK plus the
changelog into the delivery folder labelled "not tested"), THEN run the
tests, and when they pass rename the folder to "tested" with --mark-tested.

    python tool/deliver_build.py <token> "<descriptor>" <changelog.md>
        builds, then creates  K:\\My Drive\\booruApk\\<token>.apk (<descriptor> - not tested)\\
        holding <codename>-<version>.apk and changes.txt

    python tool/deliver_build.py <token> "<descriptor>" --mark-tested
        renames that folder to  <token>.apk (<descriptor> - tested)

    python tool/deliver_build.py <token> "<descriptor>" <changelog.md> --no-build
        copies an APK already built (build/app/outputs/flutter-apk/app-arm64-v8a-release.apk)

    python tool/deliver_build.py <token> "<descriptor>" <changelog.md> --both
        (1.0) builds twice: the regular APK (updates the installed app in place)
        and the side-by-side APK (--dart-define=LS_SIDE_BY_SIDE=true, package
        com.noaisu.loliSnatcher.v1, launcher label "... 1.0"), and parks both:
        <codename>-<version>.apk and <codename>-<version>-side-by-side.apk.
        Every copy is checked against its source by SHA-256.

The codename comes from lib/src/data/constants.dart (buildCodename), the
version from the same file (versionName). The Flutter beta toolchain is put
on PATH here so the script works from any shell.
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FLUTTER_BIN = r'C:\Users\alexb\Documents\flutter\flutter-3.42-beta\bin'
DELIVERY_ROOT = r'K:\My Drive\booruApk'
APK = os.path.join(REPO, 'build', 'app', 'outputs', 'flutter-apk', 'app-arm64-v8a-release.apk')
CONSTANTS = os.path.join(REPO, 'lib', 'src', 'data', 'constants.dart')


def read_constants():
    src = open(CONSTANTS, encoding='utf-8').read()
    codename = re.search(r"buildCodename = '([^']+)'", src).group(1)
    version = re.search(r"versionName: '([^']+)'", src).group(1)
    return codename, version


def folder(token, descriptor, label):
    return os.path.join(DELIVERY_ROOT, f'{token}.apk ({descriptor} - {label})')


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def copy_checked(src, dst):
    shutil.copyfile(src, dst)
    a, b = sha256(src), sha256(dst)
    if a != b:
        print(f'HASH MISMATCH copying {src} -> {dst}', flush=True)
        sys.exit(4)
    print(f'copied {os.path.basename(dst)} sha256={a[:16]}...', flush=True)


def build(side_by_side=False):
    env = dict(os.environ)
    env['PATH'] = FLUTTER_BIN + os.pathsep + env.get('PATH', '')
    cmd = ['flutter', 'build', 'apk', '--release', '--split-per-abi', '--target-platform', 'android-arm64']
    if side_by_side:
        cmd.append('--dart-define=LS_SIDE_BY_SIDE=true')
    print('building:', ' '.join(cmd), flush=True)
    started = time.time()
    proc = subprocess.run(cmd, cwd=REPO, env=env, shell=True)
    if proc.returncode != 0:
        print(f'BUILD FAILED (exit {proc.returncode}) after {time.time() - started:.0f}s', flush=True)
        sys.exit(proc.returncode)
    print(f'build done in {time.time() - started:.0f}s', flush=True)


def deliver(token, descriptor, changelog, do_build, both=False):
    codename, version = read_constants()
    if both:
        deliver_both(token, descriptor, changelog, codename, version)
        return
    if do_build:
        build()
    if not os.path.exists(APK):
        print('no APK at', APK)
        sys.exit(2)
    if not os.path.exists(changelog):
        print('no changelog at', changelog)
        sys.exit(2)
    target = folder(token, descriptor, 'not tested')
    tested = folder(token, descriptor, 'tested')
    if os.path.isdir(tested):
        print('a tested folder already exists:', tested)
        sys.exit(3)
    os.makedirs(target, exist_ok=True)
    apk_name = f'{codename}-{version}.apk'
    shutil.copyfile(APK, os.path.join(target, apk_name))
    shutil.copyfile(changelog, os.path.join(target, 'changes.txt'))
    size = os.path.getsize(os.path.join(target, apk_name))
    print(f'delivered: {target}\\{apk_name} ({size / 1e6:.1f} MB) + changes.txt', flush=True)


def deliver_both(token, descriptor, changelog, codename, version):
    if not os.path.exists(changelog):
        print('no changelog at', changelog)
        sys.exit(2)
    target = folder(token, descriptor, 'not tested')
    if os.path.isdir(folder(token, descriptor, 'tested')):
        print('a tested folder already exists')
        sys.exit(3)
    os.makedirs(target, exist_ok=True)
    build(side_by_side=False)
    copy_checked(APK, os.path.join(target, f'{codename}-{version}.apk'))
    build(side_by_side=True)
    copy_checked(APK, os.path.join(target, f'{codename}-{version}-side-by-side.apk'))
    copy_checked(changelog, os.path.join(target, 'changes.txt'))
    print(f'delivered both APKs + changes.txt to {target}', flush=True)


def mark_tested(token, descriptor):
    src = folder(token, descriptor, 'not tested')
    dst = folder(token, descriptor, 'tested')
    if not os.path.isdir(src):
        print('no "not tested" folder at', src)
        sys.exit(2)
    os.rename(src, dst)
    print('renamed to:', dst, flush=True)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        sys.exit(1)
    token, descriptor = argv[1], argv[2]
    rest = argv[3:]
    if '--mark-tested' in rest:
        mark_tested(token, descriptor)
        return
    if not rest:
        print(__doc__)
        sys.exit(1)
    changelog = rest[0]
    deliver(token, descriptor, changelog, do_build='--no-build' not in rest, both='--both' in rest)


if __name__ == '__main__':
    main(sys.argv)
