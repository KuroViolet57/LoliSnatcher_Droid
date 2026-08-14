#!/usr/bin/env python3
"""
Drive uploader for LoliSnatcher test builds.

Looks at the existing `booruApk` folder on the configured Google Drive
account (or creates it the first time), then drops a per-build subfolder
under it named `<token>.apk (<descriptor>)`. Inside that subfolder it
writes the build's changes.txt and (optionally) the .apk itself.

Re-runnable: if a subfolder with the same name already exists, it's
reused — uploaded files just go alongside whatever's already there, so
this can be called multiple times for the same build without duplicating
the folder.

Reads creds from ~/.config/lolisnatcher-drive/oauth.json. The OAuth
client uses the narrow `drive.file` scope, so this script can only see /
modify files it itself creates — it cannot reach anything else in your
Drive even if the refresh token ever leaked.

Usage:
  scripts/drive_upload_build.py \\
      --token de7amf \\
      --descriptor "seen-post dimming" \\
      --apk build/app/outputs/flutter-apk/foo.apk \\
      --changelog-file build/changelog.txt
"""

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

CONFIG_PATH = Path.home() / ".config" / "lolisnatcher-drive" / "oauth.json"
ROOT_FOLDER_NAME = "booruApk"
TOKEN_URL = "https://oauth2.googleapis.com/token"
DRIVE_API = "https://www.googleapis.com/drive/v3"
DRIVE_UPLOAD_API = "https://www.googleapis.com/upload/drive/v3"


def _request(url, *, method="GET", headers=None, data=None, timeout=120):
    req = urllib.request.Request(url, method=method)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, data=data, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def get_access_token(creds):
    body = urllib.parse.urlencode({
        "client_id": creds["client_id"],
        "client_secret": creds["client_secret"],
        "refresh_token": creds["refresh_token"],
        "grant_type": "refresh_token",
    }).encode()
    status, resp = _request(
        TOKEN_URL,
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        data=body,
    )
    if status != 200:
        sys.exit(f"[fatal] token mint failed: HTTP {status}\n{resp.decode(errors='replace')}")
    return json.loads(resp)["access_token"]


def _drive_search(token, query):
    url = f"{DRIVE_API}/files?" + urllib.parse.urlencode({
        "q": query,
        "fields": "files(id,name)",
        "pageSize": 10,
    })
    status, resp = _request(url, headers={"Authorization": f"Bearer {token}"})
    if status != 200:
        sys.exit(f"[fatal] drive search failed: HTTP {status}\n{resp.decode(errors='replace')}")
    return json.loads(resp).get("files", [])


def _escape_drive_name(name):
    # Drive query strings use single quotes around values, so escape any
    # apostrophes inside the name itself.
    return name.replace("'", "\\'")


def find_folder(token, name, parent=None):
    q = (
        "mimeType = 'application/vnd.google-apps.folder'"
        f" and name = '{_escape_drive_name(name)}'"
        " and trashed = false"
    )
    if parent:
        q += f" and '{parent}' in parents"
    files = _drive_search(token, q)
    return files[0]["id"] if files else None


def create_folder(token, name, parent=None):
    payload = {"name": name, "mimeType": "application/vnd.google-apps.folder"}
    if parent:
        payload["parents"] = [parent]
    status, resp = _request(
        f"{DRIVE_API}/files",
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        data=json.dumps(payload).encode(),
    )
    if status not in (200, 201):
        sys.exit(f"[fatal] folder create failed: HTTP {status}\n{resp.decode(errors='replace')}")
    return json.loads(resp)["id"]


def ensure_folder(token, name, parent=None):
    found = find_folder(token, name, parent)
    if found:
        return found, False
    return create_folder(token, name, parent), True


def upload_file(token, name, parent, content_bytes, mime):
    """Multipart upload (good up to 5 GB, plenty for our 35 MB APKs)."""
    boundary = "===lolisnatcher_drive_boundary==="
    meta = {"name": name, "parents": [parent]}
    head = (
        f"--{boundary}\r\n"
        "Content-Type: application/json; charset=UTF-8\r\n\r\n"
        f"{json.dumps(meta)}\r\n"
        f"--{boundary}\r\n"
        f"Content-Type: {mime}\r\n\r\n"
    ).encode()
    tail = f"\r\n--{boundary}--\r\n".encode()
    body = head + content_bytes + tail

    url = (
        f"{DRIVE_UPLOAD_API}/files"
        "?uploadType=multipart&fields=id,name,webViewLink,size"
    )
    status, resp = _request(
        url,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": f"multipart/related; boundary={boundary}",
        },
        data=body,
        # APK uploads of ~35 MB need a generous read timeout on slow connections.
        timeout=600,
    )
    if status not in (200, 201):
        sys.exit(f"[fatal] file upload failed for {name}: HTTP {status}\n{resp.decode(errors='replace')}")
    return json.loads(resp)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--token", required=True, help="litterbox token, e.g. de7amf")
    ap.add_argument("--descriptor", required=True, help="short label shown in folder name")
    ap.add_argument("--apk", help="path to .apk to upload (optional — skip to only update the changelog)")
    ap.add_argument("--apk-name", help="filename to give the apk on Drive (default: local filename); scheme: {1-2 words}-{version}.apk")
    ap.add_argument("--extra", action="append", default=[], help="extra file to drop in the same build folder (repeatable)")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--changelog-file", help="path to a .txt file to upload as changes.txt")
    src.add_argument("--changelog-text", help="inline changelog content")
    args = ap.parse_args()

    if not CONFIG_PATH.exists():
        sys.exit(f"[fatal] missing creds at {CONFIG_PATH}")

    creds = json.loads(CONFIG_PATH.read_text())
    token = get_access_token(creds)

    changelog_bytes = (
        Path(args.changelog_file).read_bytes()
        if args.changelog_file
        else args.changelog_text.encode()
    )

    root_id, root_created = ensure_folder(token, ROOT_FOLDER_NAME)
    if root_created:
        print(f"[info] created root folder '{ROOT_FOLDER_NAME}'")

    sub_name = f"{args.token}.apk ({args.descriptor})"
    sub_id, sub_created = ensure_folder(token, sub_name, parent=root_id)
    print(f"folder ({'new' if sub_created else 'reused'}): https://drive.google.com/drive/folders/{sub_id}")

    cl_resp = upload_file(token, "changes.txt", sub_id, changelog_bytes, "text/plain")
    print(f"changes.txt: {cl_resp.get('webViewLink')}")

    if args.apk:
        apk_path = Path(args.apk)
        if not apk_path.exists():
            sys.exit(f"[fatal] apk not found: {apk_path}")
        apk_bytes = apk_path.read_bytes()
        apk_resp = upload_file(
            token,
            args.apk_name or apk_path.name,
            sub_id,
            apk_bytes,
            "application/vnd.android.package-archive",
        )
        size_mb = int(apk_resp.get("size", len(apk_bytes))) / (1024 * 1024)
        print(f"apk ({size_mb:.1f} MB): {apk_resp.get('webViewLink')}")

    for extra in args.extra:
        extra_path = Path(extra)
        if not extra_path.exists():
            sys.exit(f"[fatal] extra file not found: {extra_path}")
        mime = "application/json" if extra_path.suffix == ".json" else "application/octet-stream"
        resp = upload_file(token, extra_path.name, sub_id, extra_path.read_bytes(), mime)
        print(f"{extra_path.name}: {resp.get('webViewLink')}")


if __name__ == "__main__":
    main()
