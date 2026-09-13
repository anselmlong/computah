import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
spec = importlib.util.spec_from_file_location("deploy_site", Path(__file__).parents[1] / "deploy-site.py")
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class WebsiteDeploymentTests(unittest.TestCase):
    def test_rejects_changed_archive_or_download_location(self):
        archive = b"published app"
        metadata = dict(download="/downloads/Computah.zip", bytes=len(archive), sha256=hashlib.sha256(archive).hexdigest())
        deploy.validate_archive(metadata, archive)
        for changed in [dict(metadata, download="https://elsewhere.example/app.zip"), dict(metadata, bytes=1), dict(metadata, sha256="incorrect")]:
            with self.assertRaises(ValueError):
                deploy.validate_archive(changed, archive)

    def test_preparation_preserves_app_and_records_actual_site_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "app.zip"
            archive.write_bytes(b"published app")
            metadata = dict(version="0.1.2", build="0.1.2", download="/downloads/Computah.zip",
                            bytes=archive.stat().st_size, sha256=hashlib.sha256(archive.read_bytes()).hexdigest())
            manifest = deploy.prepare(deploy.ROOT / "website", root / "site", archive, metadata, "source-commit")
            self.assertEqual(json.loads((root / "site/release.json").read_text()), metadata)
            self.assertEqual((root / "site/downloads/Computah.zip").read_bytes(), archive.read_bytes())
            self.assertEqual(manifest["commit"], "source-commit")
            for name, checksum in manifest["files"].items():
                self.assertEqual(hashlib.sha256((root / "site" / name).read_bytes()).hexdigest(), checksum)

    def test_verification_rejects_stale_manifest_or_changed_live_content(self):
        data = b"expected homepage"
        manifest = dict(commit="abc", files={"index.html": hashlib.sha256(data).hexdigest()})
        def fetch(url):
            return json.dumps(manifest).encode() if url.endswith("website-release.json") else data
        with patch.object(deploy, "fetch", side_effect=fetch):
            deploy.verify_site("https://example.com", manifest)
        with patch.object(deploy, "fetch", return_value=json.dumps(dict(manifest, commit="stale")).encode()):
            with self.assertRaisesRegex(ValueError, "manifest"):
                deploy.verify_site("https://example.com", manifest)
        with patch.object(deploy, "fetch", side_effect=[json.dumps(manifest).encode(), b"stale homepage"]):
            with self.assertRaisesRegex(ValueError, "index.html"):
                deploy.verify_site("https://example.com", manifest)
