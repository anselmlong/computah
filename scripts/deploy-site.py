#!/usr/bin/env python3
"""Deploy the website from CI while preserving the current published app archive."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import urllib.request

from release import stage_site, verify_deployment

ROOT = Path(__file__).resolve().parents[1]
PUBLIC_URL = "https://computah.anselmlong.com"
MAX_ARCHIVE_BYTES = 128 * 1024 * 1024
SITE_FILES = ("index.html", "docs.html", "site.js", "style.css", "assets/icon.svg")


def fetch(url):
    request = urllib.request.Request(url, headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read(MAX_ARCHIVE_BYTES + 1)
    if len(data) > MAX_ARCHIVE_BYTES:
        raise ValueError("Published file exceeds the download limit")
    return data


def validate_archive(metadata, archive):
    if metadata.get("download") != "/downloads/Computah.zip":
        raise ValueError("Unexpected app download path")
    if len(archive) != metadata.get("bytes") or hashlib.sha256(archive).hexdigest() != metadata.get("sha256"):
        raise ValueError("Published app archive does not match its manifest")


def prepare(source, destination, archive_path, metadata, commit):
    validate_archive(metadata, archive_path.read_bytes())
    release = stage_site(source, destination, archive_path, metadata)
    if release != metadata:
        raise ValueError("Website deployment must preserve app release metadata")
    manifest = {"commit": commit, "files": {
        name: hashlib.sha256((destination / name).read_bytes()).hexdigest() for name in SITE_FILES
    }}
    (destination / "website-release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def verify_site(base_url, expected):
    deployed = json.loads(fetch(base_url + "/website-release.json"))
    if deployed != expected:
        raise ValueError("Website manifest does not match this commit")
    for name, checksum in expected["files"].items():
        if hashlib.sha256(fetch(base_url + "/" + name)).hexdigest() != checksum:
            raise ValueError(f"Published website file differs: {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    metadata = json.loads(fetch(PUBLIC_URL + "/release.json"))
    archive = fetch(PUBLIC_URL + "/downloads/Computah.zip")
    validate_archive(metadata, archive)
    working = ROOT / ".build/website-deploy"
    if working.exists():
        shutil.rmtree(working)
    working.mkdir(parents=True)
    archive_path = working / "Computah.zip"
    archive_path.write_bytes(archive)
    site = working / "site"
    manifest = prepare(ROOT / "website", site, archive_path, metadata, commit)
    if args.prepare_only:
        print(f"Prepared website for {commit}; existing app {metadata['version']} preserved.")
        return
    project = {"projectId": os.environ["VERCEL_PROJECT_ID"], "orgId": os.environ["VERCEL_ORG_ID"]}
    (site / ".vercel").mkdir()
    (site / ".vercel/project.json").write_text(json.dumps(project))
    # The Node wrapper adds the token without printing it in Python error messages.
    subprocess.run(["node", str(ROOT / "scripts/vercel-ci.mjs"), "deploy", "--yes", "--prod",
                    "--cwd", str(site), "--local-config", str(site / "vercel.json")],
                   cwd=ROOT, check=True, timeout=600)
    for attempt in range(6):
        try:
            verify_site(PUBLIC_URL, manifest)
            break
        except (OSError, ValueError):
            if attempt == 5:
                raise
            time.sleep(3)
    verify_deployment(PUBLIC_URL, metadata)
    print(f"Verified {PUBLIC_URL} at {commit}; app {metadata['version']} unchanged.")


if __name__ == "__main__":
    main()
