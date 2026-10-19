#!/usr/bin/env bash
# Copy the regular app's data into the side-by-side 1.0 install on a ROOTED
# test device, so both apps run on the same data for comparison.
#
#   tool/side_by_side_clone.sh <adb serial> [--with-cache] [--trust-filter]
#
# Copies <data>/LoliSnatcher (settings.json, store.db, vectors.db, boorus,
# models, doujinData.json, ...) and, with --with-cache, the thumbnail/media
# cache. NOT copied: shared_prefs (secure storage is keyed to each app's own
# Android keystore and cannot be read by the other app) and app_webview.
# Download-folder access (SAF) is per app, so the 1.0 app has to be given its
# folder again if it should save files.
#
# --trust-filter switches on Settings -> Network -> "Allow self-signed
# certificates" in the COPY only: an HTTPS-filtering app (AdGuard on the test
# handheld) re-signs traffic of newly installed apps, which the copy otherwise
# refuses with CERTIFICATE_VERIFY_FAILED.
#
# Both apps are force-stopped first so the databases are copied in a
# consistent state. The source app's data is only read.
set -euo pipefail
export MSYS_NO_PATHCONV=1  # Git Bash on Windows must not rewrite /data/... arguments
SERIAL="${1:?adb serial}"
WITH_CACHE=""; TRUST=""
for a in "${@:2}"; do
  case "$a" in --with-cache) WITH_CACHE="--with-cache";; --trust-filter) TRUST=1;; esac
done
ADB="${ADB:-/c/Users/alexb/AppData/Local/Android/Sdk/platform-tools/adb.exe}"
SRC=com.noaisu.loliSnatcher
DST=com.noaisu.loliSnatcher.v1

sh_root() { "$ADB" -s "$SERIAL" shell "su -c '$1'"; }

"$ADB" -s "$SERIAL" shell am force-stop "$SRC"
"$ADB" -s "$SERIAL" shell am force-stop "$DST"
UID_DST=$(sh_root "stat -c %u /data/data/$DST" | tr -d '\r')
CACHE_GID=$(sh_root "stat -c %g /data/data/$DST/cache" | tr -d '\r')
echo "destination uid=$UID_DST cache gid=$CACHE_GID"

sh_root "rm -rf /data/data/$DST/LoliSnatcher && cp -a /data/data/$SRC/LoliSnatcher /data/data/$DST/ && chown -R $UID_DST:$UID_DST /data/data/$DST/LoliSnatcher"
if [ "$WITH_CACHE" = "--with-cache" ]; then
  sh_root "rm -rf /data/data/$DST/cache/* && cp -a /data/data/$SRC/cache/. /data/data/$DST/cache/ && chown -R $UID_DST:$CACHE_GID /data/data/$DST/cache"
fi
if [ -n "$TRUST" ]; then
  CFG=/data/data/$DST/LoliSnatcher/config/settings.json
  TMP=$(cygpath -w "$(mktemp)")  # a Windows path: python and adb are Windows programs
  "$ADB" -s "$SERIAL" exec-out "su -c 'cat $CFG'" > "$TMP"
  python -c "import sys,json; p=sys.argv[1]; d=json.load(open(p,encoding='utf-8')); d['allowSelfSignedCerts']=True; json.dump(d,open(p,'w',encoding='utf-8'))" "$TMP"
  "$ADB" -s "$SERIAL" push "$TMP" /data/local/tmp/ls_settings.json >/dev/null
  rm -f "$TMP"
  sh_root "cp /data/local/tmp/ls_settings.json $CFG && chown $UID_DST:$UID_DST $CFG && rm /data/local/tmp/ls_settings.json"
  echo "allowSelfSignedCerts switched on in the copy"
fi
sh_root "restorecon -R /data/data/$DST"
sh_root "du -sh /data/data/$DST/LoliSnatcher /data/data/$DST/cache"
echo "cloned $SRC -> $DST"
