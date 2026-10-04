#!/usr/bin/env bash
# Runs one flutter command at a time across every shell, worktree and agent on
# this PC. Two flutter commands at once hang on bin/cache/lockfile or resolve
# the wrong Dart SDK (seen 2026-09-17 and 2026-10-04), so everything goes
# through this queue:
#
#   tool/flutterw.sh test test/foo_test.dart
#   tool/flutterw.sh analyze --no-pub
#
# Uses the project's beta SDK. A lock left behind by a killed run is taken
# over after 45 minutes.
LOCK="${FLUTTERW_LOCK:-/c/Users/alexb/AppData/Local/Temp/flutter_serial.lock}"
export PATH="/c/Users/alexb/Documents/flutter/flutter-3.42-beta/bin:$PATH"
waited=0
until mkdir "$LOCK" 2>/dev/null; do
  if [ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +45 2>/dev/null)" ]; then
    echo "flutterw: taking over a stale lock" >&2
    rmdir "$LOCK" 2>/dev/null
    continue
  fi
  if [ $((waited % 30)) -eq 0 ]; then echo "flutterw: waiting for another flutter command ($waited s)" >&2; fi
  sleep 2
  waited=$((waited + 2))
done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM
flutter "$@"
