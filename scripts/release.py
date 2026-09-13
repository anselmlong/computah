#!/usr/bin/env python3
"""Build one tagged app, stage its website, optionally deploy and open that same app."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CONFIG = Path.home() / "Library/Application Support/ComputahRelease/config.json"


def run(*args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, **kwargs)


def version_from_tag(tag):
    if not re.fullmatch(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", tag):
        raise ValueError("Use a version tag such as v0.1.1")
    return tag[1:]


def stage_site(source, destination, archive, metadata):
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns(".vercel", "downloads", "release.json"))
    (destination / "downloads").mkdir()
    shutil.copy2(archive, destination / "downloads/Computah.zip")
    metadata = dict(metadata, sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
                    bytes=archive.stat().st_size, download="/downloads/Computah.zip")
    html = (destination / "index.html").read_text()
    html, count = re.subn(r'<span class="button-size">[^<]*</span>',
                         f'<span class="button-size">{metadata["bytes"] / 1024:.0f} KB</span>', html)
    if count != 1:
        raise ValueError("Website download-size marker changed")
    html, count = re.subn(r'<p class="release">[^<]*</p>',
                         f'<p class="release">Version {metadata["version"]} · Build {metadata["build"]} · Apple silicon · macOS 14+</p>', html)
    if count != 1:
        raise ValueError("Website release marker changed")
    html = html.replace("the available ZIP remains version 0.1.0, build 6", "the available ZIP is the release shown above")
    (destination / "index.html").write_text(html)
    (destination / "release.json").write_text(json.dumps(metadata, indent=2) + "\n")
    return metadata


def verify_deployment(base_url, metadata):
    # Verify the actual download, not just a successful CLI exit.
    last_error = None
    for _ in range(6):
        try:
            with urllib.request.urlopen(base_url + "/release.json", timeout=30) as response:
                deployed = json.load(response)
            if deployed != metadata:
                raise ValueError("Deployed manifest differs from this release")
            with urllib.request.urlopen(base_url + metadata["download"], timeout=60) as response:
                checksum = hashlib.sha256()
                for chunk in iter(lambda: response.read(1024 * 1024), b""):
                    checksum.update(chunk)
                digest = checksum.hexdigest()
            if digest != metadata["sha256"]:
                raise ValueError("Deployed ZIP checksum differs from this release")
            return
        except (OSError, ValueError) as error:
            last_error = error
            time.sleep(3)
    raise RuntimeError(f"Deployment verification failed: {last_error}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--mode", choices=["dry-run", "preview", "publish"], default="dry-run")
    parser.add_argument("--config", type=Path, default=CONFIG)
    args = parser.parse_args()
    version = version_from_tag(args.tag)
    config = json.loads(args.config.read_text())
    commit = run("git", "rev-parse", "HEAD", cwd=ROOT, capture_output=True, text=True).stdout.strip()
    if args.mode == "publish":
        tagged = run("git", "rev-parse", f"refs/tags/{args.tag}^{{commit}}", cwd=ROOT, capture_output=True, text=True).stdout.strip()
        if tagged != commit:
            raise ValueError("Publishing requires the exact tagged source checkout")
    env = dict(os.environ, COMPUTAH_SIGNING_IDENTITY=config["signing_identity"],
               COMPUTAH_RELEASE_VERSION=version, COMPUTAH_BUILD_VERSION=version)
    run("zsh", ROOT / "scripts/build.sh", cwd=ROOT, env=env)
    app = ROOT / "dist/Computah.app"
    run("codesign", "--verify", "--strict", app)
    with (app / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if info["CFBundleIdentifier"] != "com.lvl8.computah" or info["CFBundleShortVersionString"] != version:
        raise ValueError("Built bundle does not match the release")
    archive = ROOT / "dist/Computah.zip"
    archive.unlink(missing_ok=True)
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive)
    metadata = dict(version=version, build=info["CFBundleVersion"], tag=args.tag, commit=commit,
                    built_at=info["ComputahBuildDate"], signing="ad-hoc" if config["signing_identity"] == "-" else "identity")
    with tempfile.TemporaryDirectory(prefix="computah-release-") as temporary:
        site = Path(temporary) / "site"
        metadata = stage_site(ROOT / "website", site, archive, metadata)
        (ROOT / "dist/release.json").write_text(json.dumps(metadata, indent=2) + "\n")
        print(json.dumps(metadata, indent=2), flush=True)
        if args.mode == "dry-run":
            print("Dry run passed: built and packaged; no deployment or app restart.")
            return
        (site / ".vercel").mkdir()
        (site / ".vercel/project.json").write_text(json.dumps(config["vercel_project"]))
        deployment_home = Path(config["deployment_home"])
        command = ["node", str(deployment_home / "scripts/vercel.js"), "deploy", "--yes", "--cwd", str(site),
                   "--local-config", str(site / "vercel.json")]
        if args.mode == "publish":
            command.append("--prod")
        deployed = run(*command, cwd=deployment_home, capture_output=True, text=True)
        urls = re.findall(r"https://[a-zA-Z0-9.-]+\.vercel\.app", deployed.stdout)
        if not urls:
            raise ValueError("Vercel did not return a deployment URL")
        url = urls[-1]
        print(f"Deployment: {url}", flush=True)
        if args.mode == "preview":
            # Vercel previews may be protected; production verification is mandatory below.
            print("Preview deployed; production and installed app unchanged.")
            return
        verify_deployment(config["production_url"].rstrip("/"), metadata)
        installer = ROOT / ".build/install-release"
        run("swiftc", ROOT / "scripts/InstallRelease.swift", "-o", installer)
        # This GUI app must outlive the Actions job's child-process cleanup.
        install_env = {key: value for key, value in os.environ.items() if key != "RUNNER_TRACKING_ID"}
        run(installer, app, Path(config["install_directory"]) / "Computah.app", env=install_env)
        print("Production download verified; the same app is installed and running.")


if __name__ == "__main__":
    main()
