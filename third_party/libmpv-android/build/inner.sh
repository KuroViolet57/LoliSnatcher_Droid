#!/bin/bash -e
# Runs inside docker.io/debian:bookworm-slim (see build.sh). Reproduces the CI
# recipe of Predidit/libmpv-android-video-build (.github/workflows/build.yaml)
# for arm64 only, plus our changes:
#   1. mpv's library is called "mpvls": file libmpvls.so, SONAME libmpvls.so,
#      so it can sit next to the classic libmpv.so in one APK.
#   2. Only arm64-v8a is built; libmediakitandroidhelper.so is not rebuilt
#      (the APK keeps the one from the classic jar).
# Output: /work/out/ls-arm64-v8a.jar holding lib/arm64-v8a/libmpvls.so.

NDK_ZIP_URL="https://dl.google.com/android/repository/android-ndk-r27c-linux.zip"
NDK_VERSION="27.2.12479018"

cd /work
echo "LSBUILD step=apt $(date -u +%T)"
echo "deb http://deb.debian.org/debian bookworm-backports main" > /etc/apt/sources.list.d/bookworm-backports.list
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo git gcc-multilib libc-dev make automake \
  pkg-config libtool nasm python3-jsonschema wget python3-jinja2 zip unzip python3-pip ca-certificates >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -t bookworm-backports meson >/dev/null
meson --version

cd /work/src/buildscripts
if [ ! -x "sdk/android-sdk-linux/ndk/$NDK_VERSION/ndk-build" ]; then
  echo "LSBUILD step=ndk $(date -u +%T)"
  mkdir -p /work/cache sdk/android-sdk-linux/ndk
  [ -f /work/cache/ndk.zip ] || wget -q -O /work/cache/ndk.zip "$NDK_ZIP_URL"
  sha256sum /work/cache/ndk.zip
  rm -rf /tmp/ndk && mkdir /tmp/ndk && unzip -q /work/cache/ndk.zip -d /tmp/ndk
  mv /tmp/ndk/android-ndk-r27c "sdk/android-sdk-linux/ndk/$NDK_VERSION"
fi
grep Pkg.Revision "sdk/android-sdk-linux/ndk/$NDK_VERSION/source.properties"

# The CI's own edits (build.yaml "Bundle (default)").
sed -i -e 's/sudo//g' *.sh
sed -i 's/download-sdk\.sh/download-sdk-debian\.sh/g' download.sh
sed -i -e '/git reset --hard/d' patch.sh
chmod +x include/*.sh *.sh scripts/*.sh

echo "LSBUILD step=download $(date -u +%T)"
./download.sh
if [ ! -f /work/.patched ]; then
  echo "LSBUILD step=patch $(date -u +%T)"
  ./patch.sh
  # Ours: rename the library (exactly one match, or stop).
  n=$(grep -c "^libmpv = library('mpv'," deps/mpv/meson.build || true)
  [ "$n" = "1" ] || { echo "LSBUILD mpv meson.build anchor count $n"; exit 1; }
  sed -i "s/^libmpv = library('mpv',/libmpv = library('mpvls',/" deps/mpv/meson.build
  touch /work/.patched
fi
rm -f scripts/ffmpeg.sh
cp flavors/default.sh scripts/ffmpeg.sh

echo "LSBUILD step=build $(date -u +%T)"
./build.sh --arch arm64

echo "LSBUILD step=bundle $(date -u +%T)"
lib=prefix/arm64-v8a/lib/libmpvls.so
[ -f "$lib" ] || { echo "LSBUILD missing $lib"; ls prefix/arm64-v8a/lib; exit 1; }
rm -rf /work/out && mkdir -p /work/out/temp/lib/arm64-v8a
cp "$lib" /work/out/temp/lib/arm64-v8a/
cd /work/out/temp
find lib -exec touch -d "2025-01-01 00:00:00" {} +
find lib -type f | sort | zip -q -r -X ../ls-arm64-v8a.jar -@
cd /work/out
rm -rf temp
sha256sum ls-arm64-v8a.jar
chown -R "${HOST_UID:-1000}:${HOST_UID:-1000}" /work/out
echo "LSBUILD_DONE $(date -u +%T)"
