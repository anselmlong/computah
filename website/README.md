# Computah website

This directory is the version-controlled source for `computah2.anselmlong.com`. It was moved from the sibling `computah` repository so each version tag can publish its website and app together.

There is no frontend build step. `scripts/release.py` copies the static source into temporary staging, adds `downloads/Computah.zip` and `release.json`, and updates the version/size labels from the actual bundle and ZIP. Generated download files are ignored by Git.

See [RELEASES.md](../RELEASES.md) for preview testing, production publishing, and the personal Mac runner. Native screenshots retain the illustrative-data provenance in `assets/screenshots.json`; a release does not regenerate them or claim they demonstrate the latest version.
