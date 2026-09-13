import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release", Path(__file__).parents[1] / "release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_rejects_invalid_tags(self):
        for tag in ["main", "v1", "v1.2.3;exit", "v01.2.3", "v1.2.3-beta", "../v1.2.3"]:
            with self.assertRaises(ValueError):
                release.version_from_tag(tag)
        self.assertEqual(release.version_from_tag("v0.1.1"), "0.1.1")

    def test_staged_site_matches_archive_and_leaves_source_untouched(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            original = '<span class="button-size">520 KB</span><p class="release">Old release</p>'
            (source / "index.html").write_text(original)
            archive = root / "Computah.zip"
            archive.write_bytes(b"test archive")
            metadata = release.stage_site(source, root / "stage", archive, dict(version="0.1.1", build="0.1.1"))
            self.assertEqual((source / "index.html").read_text(), original)
            self.assertEqual((root / "stage/downloads/Computah.zip").read_bytes(), archive.read_bytes())
            self.assertEqual(json.loads((root / "stage/release.json").read_text()), metadata)
            self.assertEqual(metadata["sha256"], release.hashlib.sha256(b"test archive").hexdigest())
            self.assertIn("Version 0.1.1 · Build 0.1.1", (root / "stage/index.html").read_text())

    def test_template_drift_stops_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "source").mkdir()
            (root / "source/index.html").write_text("Missing markers")
            (root / "app.zip").write_bytes(b"zip")
            with self.assertRaises(ValueError):
                release.stage_site(root / "source", root / "stage", root / "app.zip", dict(version="1.0.0", build="1"))

    def test_public_download_must_match_manifest_and_checksum(self):
        data = b"the exact shipped archive"
        metadata = dict(download="/downloads/Computah.zip", sha256=release.hashlib.sha256(data).hexdigest())
        for downloaded in [data, b"stale or corrupted archive"]:
            def response(url, **kwargs):
                return io.BytesIO(json.dumps(metadata).encode() if url.endswith("release.json") else downloaded)
            with patch.object(release.urllib.request, "urlopen", side_effect=response), patch.object(release.time, "sleep"):
                if downloaded == data:
                    release.verify_deployment("https://example.com", metadata)
                else:
                    with self.assertRaisesRegex(RuntimeError, "checksum"):
                        release.verify_deployment("https://example.com", metadata)

    def test_stale_public_manifest_blocks_installation(self):
        with patch.object(release.urllib.request, "urlopen", side_effect=lambda *args, **kwargs: io.BytesIO(b'{}')), patch.object(release.time, "sleep"):
            with self.assertRaisesRegex(RuntimeError, "manifest"):
                release.verify_deployment("https://example.com", dict(download="/downloads/Computah.zip", sha256="expected"))


if __name__ == "__main__":
    unittest.main()
