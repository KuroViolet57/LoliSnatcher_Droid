"""Extract the two mpvlibAndroid 1.1.1 arm64 trees into build assets.

The archives are not Gradle dependencies. Both contain libmpv.so, and so does
media_kit, so only one of them may be a packaged JNI library. This script
checks the published SHA-256, keeps arm64-v8a, and writes a load order from
each library's NEEDED list.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "build" / "mpvlib-cache"
OUT = ROOT / "build" / "mpvlib-assets" / "mpvlib"

VULKAN_URL = "https://github.com/Riteshp2001/mpvlibAndroid/releases/download/v1.1.1/mpvlib-1.1.1.aar"
VULKAN_SHA = "2c0b77bcbee2796fefde61f5abf9d90e1c5f36e1b6a3cf4925ce8e222454c818"
OPENGL_URL = "https://github.com/Riteshp2001/mpvlibAndroid/releases/download/v1.1.1/mpvlib-no-vulkan-1.1.1.aar"
OPENGL_SHA = "86dd920a6ddd936db4caced7ca436917781b5e82ab8d67ebff549c79ca835ed8"

READOBJ_CANDIDATES = [
    Path(os.environ.get("LLVM_READOBJ", "")),
    Path(r"C:\Users\alexb\AppData\Local\Android\Sdk\ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readobj.exe"),
    Path.home() / "AppData/Local/Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-readobj.exe",
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_archive(url: str, name: str, expected: str) -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    dest = CACHE / name
    if dest.exists() and sha256(dest) == expected:
        print(f"mpvlib cache hit {name}")
        return dest
    fallback = Path(os.environ.get("TEMP", "")) / "mpvlib-inspect" / name
    if fallback.exists() and sha256(fallback) == expected:
        shutil.copyfile(fallback, dest)
        print(f"mpvlib copied cached download {name}")
        return dest
    import urllib.request

    print(f"mpvlib downloading {url}")
    tmp = dest.with_suffix(".tmp")
    urllib.request.urlretrieve(url, tmp)
    got = sha256(tmp)
    if got != expected:
        tmp.unlink(missing_ok=True)
        raise SystemExit(f"{name} hash {got} != {expected}")
    tmp.replace(dest)
    return dest


def readobj() -> Path:
    for candidate in READOBJ_CANDIDATES:
        if candidate and candidate.is_file():
            return candidate
    sdk = Path(os.environ.get("ANDROID_HOME", os.environ.get("ANDROID_SDK_ROOT", "")))
    if sdk:
        found = sorted(sdk.glob("ndk/*/toolchains/llvm/prebuilt/*/bin/llvm-readobj*"))
        if found:
            return found[-1]
    raise SystemExit("llvm-readobj was not found. Set LLVM_READOBJ.")


def needed_names(tool: Path, library: Path) -> list[str]:
    text = subprocess.check_output([str(tool), "--needed-libs", str(library)], text=True, errors="replace")
    names = []
    in_needed = False
    for line in text.splitlines():
        if "NeededLibraries" in line:
            in_needed = True
            continue
        if not in_needed:
            continue
        if "]" in line:
            break
        item = line.strip()
        if item.endswith(".so") or ".so." in item:
            names.append(item.split()[-1])
    return names


def load_order(tool: Path, directory: Path) -> tuple[list[str], list[str]]:
    libraries = sorted(path.name for path in directory.glob("*.so"))
    bundled = set(libraries)
    deps = {name: [] for name in libraries}
    skipped = []
    for name in libraries:
        for needed in needed_names(tool, directory / name):
            if needed in bundled:
                deps[name].append(needed)
            else:
                skipped.append(f"{name} -> {needed}")
    remaining = {name: set(items) for name, items in deps.items()}
    ready = sorted(name for name, items in remaining.items() if not items)
    order = []
    while ready:
        name = ready.pop(0)
        order.append(name)
        for other, items in remaining.items():
            if name in items:
                items.remove(name)
                if not items and other not in order and other not in ready:
                    ready.append(other)
        ready.sort()
    if len(order) != len(libraries):
        missing = set(libraries) - set(order)
        raise SystemExit(f"cycle in {directory.name}: {missing}")
    return order, skipped


def extract(archive: Path, variant: str, digest: str, tool: Path) -> None:
    dest = OUT / variant
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    with zipfile.ZipFile(archive) as bundle:
        extracted = 0
        for info in bundle.infolist():
            name = info.filename.replace("\\", "/")
            if "/arm64-v8a/" not in name or not name.endswith(".so"):
                continue
            target = dest / Path(name).name
            with bundle.open(info) as source, target.open("wb") as sink:
                shutil.copyfileobj(source, sink)
            extracted += 1
    if extracted == 0:
        raise SystemExit(f"{archive.name} has no arm64-v8a libraries")
    order, skipped = load_order(tool, dest)
    lines = [f"# {archive.name} {digest}", "# skipped NEEDED (system or not bundled):"]
    lines.extend(f"# {item}" for item in skipped)
    lines.extend(order)
    (dest / "order.txt").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    (dest / "STAMP").write_text(digest + "\n", encoding="utf-8", newline="\n")
    print(f"mpvlib {variant}: {extracted} libraries")
    print("  " + " ".join(order))


def main() -> None:
    tool = readobj()
    vulkan = ensure_archive(VULKAN_URL, "mpvlib-1.1.1.aar", VULKAN_SHA)
    opengl = ensure_archive(OPENGL_URL, "mpvlib-no-vulkan-1.1.1.aar", OPENGL_SHA)
    extract(vulkan, "vulkan", VULKAN_SHA, tool)
    extract(opengl, "opengl", OPENGL_SHA, tool)
    print("PREPARE_MPVLIB_DONE")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"prepare_mpvlib failed: {error}", file=sys.stderr)
        raise
