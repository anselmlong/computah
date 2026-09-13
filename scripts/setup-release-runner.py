#!/usr/bin/env python3
"""Install this private repository's release runner in the current Mac login session."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.request


def command(*args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, **kwargs)


def api(path, method="GET"):
    return json.loads(command("gh", "api", "--method", method, path, capture_output=True, text=True).stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deployment-home", type=Path, required=True, help="Directory containing the authenticated scripts/vercel.js helper")
    parser.add_argument("--signing-identity", required=True, help="Existing code-signing identity, or - for development ad hoc signing")
    parser.add_argument("--project-file", type=Path, required=True, help="Existing Vercel .vercel/project.json")
    args = parser.parse_args()
    repository = "anselmlong/computah2"
    if not api(f"repos/{repository}")["private"]:
        raise RuntimeError("This personal release runner is configured for a private repository")
    runner = Path.home() / ".local/share/computah-release-runner"
    if (runner / ".runner").exists():
        raise RuntimeError(f"Runner already registered at {runner}; use its svc.sh to manage it")
    if not (args.deployment_home / "scripts/vercel.js").is_file():
        raise ValueError("Vercel deployment helper is missing")
    release = api("repos/actions/runner/releases/latest")
    asset = next(asset for asset in release["assets"] if asset["name"].startswith("actions-runner-osx-arm64-"))
    expected = asset.get("digest", "")
    if not expected.startswith("sha256:"):
        raise RuntimeError("GitHub did not provide the runner checksum")
    runner.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temporary:
        archive = Path(temporary) / "runner.tar.gz"
        urllib.request.urlretrieve(asset["browser_download_url"], archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != expected[7:]:
            raise RuntimeError("Runner download checksum mismatch")
        command("tar", "xzf", archive, "-C", runner)
    configuration = Path.home() / "Library/Application Support/ComputahRelease"
    configuration.mkdir(parents=True, exist_ok=True, mode=0o700)
    settings = dict(deployment_home=str(args.deployment_home.resolve()), signing_identity=args.signing_identity,
                    vercel_project=json.loads(args.project_file.read_text()),
                    production_url="https://computah.anselmlong.com",
                    install_directory=str(Path.home() / "Applications"))
    config = configuration / "config.json"
    config.write_text(json.dumps(settings, indent=2) + "\n")
    config.chmod(0o600)
    token = api(f"repos/{repository}/actions/runners/registration-token", "POST")["token"]
    # Capture setup output: the registration token must never enter task logs.
    result = subprocess.run([str(runner / "config.sh"), "--unattended", "--url", f"https://github.com/{repository}",
                             "--token", token, "--name", "computah-personal-mac", "--labels", "computah-release", "--work", "_work"],
                            cwd=runner, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("Runner registration failed; check repository administration access")
    command("./svc.sh", "install", cwd=runner)
    command("./svc.sh", "start", cwd=runner)
    print(f"Runner installed at {runner}; configuration at {config}")


if __name__ == "__main__":
    main()
