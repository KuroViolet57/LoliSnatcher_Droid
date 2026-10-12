#!/bin/bash -e
# Builds our own libmpv (libmpvls.so) for arm64 inside WSL with Docker.
# Run from Windows:  wsl -d Ubuntu -- bash <repo>/third_party/libmpv-android/build/build_ls_libmpv.sh
# Work dir (Linux file system, fast): ~/lsbuild. Output: ~/lsbuild/out/ls-arm64-v8a.jar
# See third_party/libmpv-android/README.md for what this build is and why.

UPSTREAM="https://github.com/Predidit/libmpv-android-video-build.git"
UPSTREAM_COMMIT="dd2bfba8"   # v1.2.7 (2026-08-11): mpv 32a164cc, FFmpeg 7.1.3, libplacebo d4624cbf
CPUS="${LSBUILD_CPUS:-12}"   # leave room for the other containers on this machine

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$HOME/lsbuild"
mkdir -p "$work"
if [ ! -d "$work/src/.git" ]; then
  git clone -q "$UPSTREAM" "$work/src"
fi
git -C "$work/src" checkout -q "$UPSTREAM_COMMIT"
echo "LSBUILD upstream $(git -C "$work/src" log -1 --format='%h %cd %s')"
cp "$here/inner.sh" "$work/inner.sh"

docker run --rm --name lsbuild-libmpv --cpus "$CPUS" \
  -e HOST_UID="$(id -u)" \
  -v "$work:/work" \
  docker.io/debian:bookworm-slim bash /work/inner.sh
