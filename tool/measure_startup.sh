#!/usr/bin/env bash
# Cold-start the app N times on a device and print the app's own startup
# timeline line ("startup: ... total N ms", lib/src/utils/startup_timeline.dart)
# for each run, plus Android's activity launch time.
#
#   tool/measure_startup.sh <adb serial> <package> [runs=5] [--drop-caches]
#
# --drop-caches (root) empties the page cache before each run, for a truly
# cold start (it affects the whole device briefly; nothing is deleted).
# If Android's folder picker covers the app (a copied install without access
# to the download folder), it is closed with Back and the run is marked.
set -uo pipefail
export MSYS_NO_PATHCONV=1
SERIAL="${1:?adb serial}"
PKG="${2:?package}"
RUNS="${3:-5}"
DROP="${4:-}"
ADB="${ADB:-/c/Users/alexb/AppData/Local/Android/Sdk/platform-tools/adb.exe}"
ACT="$PKG/com.noaisu.loliSnatcher.MainActivity"

for i in $(seq 1 "$RUNS"); do
  "$ADB" -s "$SERIAL" shell am force-stop "$PKG"
  sleep 2
  if [ "$DROP" = "--drop-caches" ]; then
    "$ADB" -s "$SERIAL" shell "su -c 'sync; echo 3 > /proc/sys/vm/drop_caches'"
    sleep 1
  fi
  "$ADB" -s "$SERIAL" logcat -c
  LAUNCH=$("$ADB" -s "$SERIAL" shell am start -W -n "$ACT" 2>&1 | grep TotalTime | tr -d '\r')
  NOTE=""
  LINE=""
  for t in $(seq 1 120); do
    LINE=$("$ADB" -s "$SERIAL" logcat -d -s flutter 2>/dev/null | grep -o 'startup: .*' | tail -1 | tr -d '\r')
    [ -n "$LINE" ] && break
    TOP=$("$ADB" -s "$SERIAL" shell dumpsys activity activities 2>/dev/null | grep -m1 'mResumedActivity\|topResumedActivity' | tr -d '\r')
    if echo "$TOP" | grep -q documentsui; then
      "$ADB" -s "$SERIAL" shell input keyevent 4
      NOTE=" (folder picker closed)"
    fi
    sleep 0.5
  done
  echo "run $i: $LAUNCH | ${LINE:-no startup line within 60 s}$NOTE"
done
