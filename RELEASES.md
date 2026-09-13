# Releases

Push source changes to `main` normally. GitHub Actions builds the app and runs Swift and release-script tests on a hosted Mac with Xcode. Pull requests run these checks too; they never execute on the personal Mac.

To publish a version already committed and pushed to `main`:

```sh
git tag v0.1.1
git push origin v0.1.1
```

Use a new `vMAJOR.MINOR.PATCH` tag for each release. The tag supplies both the app's marketing version and build version. Do not move an existing release tag. The workflow requires the tagged commit to be on `main` and passing checks before using the personal Mac runner.

The release job builds from that exact checkout, verifies the code signature, creates `Computah.zip`, updates the website version/size labels, and writes `release.json` with the source commit and SHA-256 checksum. It deploys `website/` to the existing Vercel project, downloads the production manifest and ZIP to verify them, then installs the same app at `~/Applications/Computah.app` and opens it. The previous local installation is retained until the new process starts successfully. Reopening ends any active Computah conversation and browser tasks. If the previous Computah process ignores normal quit for 15 seconds, the installer force-quits that identified app before replacing it. A failed website deployment or checksum check prevents local installation. A local launch failure restores the local previous version; it does not roll back the already-published website.

GitHub Actions retains the ZIP and manifest as run artifacts. The public downloads remain at `https://computah2.anselmlong.com/downloads/Computah.zip`; the source repository can stay private. The workflow does not commit generated binaries to Git.

## Test without publishing

```sh
gh workflow run ci.yml --ref main -f mode=dry-run -f version=v0.1.1
gh run list --workflow ci.yml
gh run watch RUN_ID
```

This runs checks and builds/packages a real app on the Mac, but does not deploy, install, or restart it. Download the run's artifacts to inspect the ZIP and manifest. `mode=preview` also creates a Vercel preview deployment without changing the production domain or installed app. Preview access follows the project's Vercel protection settings.

For local packaging tests, run `python3 scripts/release.py --tag v0.1.1 --mode dry-run`. Script tests run with `python3 -m unittest discover -s scripts/tests -v`. CI does not send a real API request, record audio, or test a real application submission. The separate browser research smoke script does use the saved API credential.

## Personal Mac setup

The repo must remain private for this personal runner configuration. The runner is registered only to `anselmlong/computah2` and labeled `computah-release`. It uses the logged-in user's launch agent so it can open the app on that desktop. The Mac needs to be awake, online, and logged in; otherwise releases queue until the runner becomes available. Only trusted maintainers should be able to push version tags or modify the release workflow: those jobs run code as this Mac user.

The existing local Vercel helper and its credential stay on the Mac; no Vercel or Apple secrets are copied to GitHub. Setup requires an authenticated `gh`, Python 3, Node, Swift command-line tools, and the existing deployment helper:

```sh
python3 scripts/setup-release-runner.py \
  --deployment-home /Users/anselm/src/computah \
  --signing-identity=- \
  --project-file /Users/anselm/src/computah/static/computah2/.vercel/project.json
```

Configuration is in `~/Library/Application Support/ComputahRelease/config.json`. The current `-` identity preserves the prototype's ad hoc development signing. This is not Developer ID signing or notarization; macOS permission approvals may change after updates. Set `signing_identity` to an existing Apple identity when available. The website source is now tracked in this repository at `website/`; edit it here for subsequent tagged releases. The old site's directory only supplies the existing Vercel project settings during setup.

Manage or disable the runner:

```sh
cd ~/.local/share/computah-release-runner
./svc.sh status
./svc.sh stop
./svc.sh uninstall
```

Removing the launch agent does not remove the runner registration. Remove the offline runner in the repository's Settings → Actions → Runners when retiring this Mac. Vercel's deployment history retains earlier site/download versions for a deliberate production rollback.

## Verification record

On 2026-09-13, the Mac runner registered and came online. Local dry-run packaging produced a valid 0.1.1 app ZIP and matching manifest; a Vercel preview deployment succeeded without modifying production. Hosted CI at `88e2577` passed 53 Swift tests with one expected installed-Codex skip and five release tests. Initial CI exposed and prompted a fix to fake-worker executable discovery.
