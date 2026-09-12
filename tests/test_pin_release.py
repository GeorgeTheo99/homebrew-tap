import gzip
import hashlib
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("pin_release", ROOT / "scripts/pin-release.py")
pin = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pin)
URL = "https://example.com/pi-setup/archive/v1.2.3.tar.gz"
PAYLOAD = gzip.compress(b"offline checksum fixture", mtime=0)
DIGEST = hashlib.sha256(PAYLOAD).hexdigest()


class PinReleaseTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.formula = Path(self.directory.name) / "pi-shared.rb"
        self.original = (ROOT / "Formula/pi-shared.rb").read_text()
        self.formula.write_text(self.original)
        self.formula.chmod(0o644)
        self.target = patch.object(pin, "FORMULA", self.formula)
        self.target.start()
        self.addCleanup(self.target.stop)

    def download(self, args, **kwargs):
        self.assertEqual(args[:2], ["/usr/bin/curl", "--disable"])
        for flag, value in (("--proto", "=https"), ("--proto-redir", "=https"),
                            ("--max-time", "90"), ("--max-filesize", str(pin.MAX_BYTES)),
                            ("--limit-rate", "5M"), ("--max-redirs", "3")):
            self.assertEqual(args[args.index(flag) + 1], value)
        self.assertEqual(kwargs, {"check": True, "timeout": 95})
        Path(args[args.index("--output") + 1]).write_bytes(PAYLOAD)

    def test_pins_real_digest_and_keeps_head(self):
        with patch.object(pin.subprocess, "run", side_effect=self.download):
            self.assertEqual(pin.pin_release("1.2.3", URL, DIGEST.upper()), DIGEST)
        updated = self.formula.read_text()
        self.assertIn(f'  sha256 "{DIGEST}"', updated)
        self.assertIn(f'  url "{URL}"', updated)
        self.assertIn('  version "1.2.3"', updated)
        self.assertEqual(updated.split(pin.END)[1], self.original.split(pin.END)[1])
        self.assertEqual(self.formula.stat().st_mode & 0o777, 0o644)
        self.assertEqual(list(self.formula.parent.iterdir()), [self.formula])
        result = subprocess.run(["ruby", "-c", str(self.formula)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_repeat_replaces_only_one_stanza(self):
        with patch.object(pin.subprocess, "run", side_effect=self.download):
            pin.pin_release("1.2.3", URL)
            pin.pin_release("1.2.4", URL)
        self.assertEqual(self.formula.read_text().count('  sha256 "'), 1)
        self.assertNotIn('version "1.2.3"', self.formula.read_text())

    def test_unsafe_inputs_never_download(self):
        cases = [
            ("bad", URL, None), ("1.2.3", "http://example.com/file.tgz", None),
            ("1.2.3", "https://user:pass@example.com/file.tgz", None),
            ("1.2.3", "https://example.com/#{system('id')}.tgz", None),
            ("1.2.3", "https://example.com/file.tgz\n", None),
            ("1.2.3", "https://example.com/file.tgz#fragment", None),
            ("1.2.3", "https://example.com/file.tgz?token=not-a-real-secret", None),
            ("1.2.3", "https://@example.com/file.tgz", None),
            ("1.2.3", "https://example.com/file.zip", None),
            ("1.2.3", URL, "not-a-digest"),
        ]
        with patch.object(pin.subprocess, "run") as fetch:
            for args in cases:
                with self.subTest(args=args), self.assertRaises(ValueError):
                    pin.pin_release(*args)
            fetch.assert_not_called()
        self.assertEqual(self.formula.read_text(), self.original)

    def test_checksum_mismatch_keeps_formula(self):
        with patch.object(pin.subprocess, "run", side_effect=self.download):
            with self.assertRaisesRegex(ValueError, "does not match"):
                pin.pin_release("1.2.3", URL, "0" * 64)
        self.assertEqual(self.formula.read_text(), self.original)

    def test_fetch_failure_keeps_formula(self):
        for failure in (subprocess.CalledProcessError(22, "curl"),
                        subprocess.TimeoutExpired("curl", 95)):
            with patch.object(pin.subprocess, "run", side_effect=failure):
                with self.assertRaises(subprocess.SubprocessError):
                    pin.pin_release("1.2.3", URL)
            self.assertEqual(self.formula.read_text(), self.original)

    def test_empty_oversized_and_non_gzip_responses_rejected(self):
        for content in (b"", b"<html>Not an archive</html>", b"x" * 129):
            def fake_download(args, **kwargs):
                Path(args[args.index("--output") + 1]).write_bytes(content)
            with patch.object(pin, "MAX_BYTES", 128):
                with patch.object(pin.subprocess, "run", side_effect=fake_download):
                    with self.assertRaises(ValueError):
                        pin.pin_release("1.2.3", URL)
            self.assertEqual(self.formula.read_text(), self.original)

    def test_missing_or_duplicate_markers_rejected_without_download(self):
        for text in (self.original.replace(pin.BEGIN, ""), self.original + pin.END,
                     pin.END + pin.BEGIN):
            self.formula.write_text(text)
            with patch.object(pin.subprocess, "run") as fetch:
                with self.assertRaises(ValueError):
                    pin.pin_release("1.2.3", URL)
                fetch.assert_not_called()
            self.assertEqual(self.formula.read_text(), text)

    def test_symlink_and_hardlink_formula_rejected(self):
        target = self.formula.with_name("original.rb")
        self.formula.rename(target)
        self.formula.symlink_to(target)
        with patch.object(pin.subprocess, "run") as fetch:
            with self.assertRaises(ValueError):
                pin.pin_release("1.2.3", URL)
            self.formula.unlink()
            self.formula.hardlink_to(target)
            with self.assertRaises(ValueError):
                pin.pin_release("1.2.3", URL)
            fetch.assert_not_called()
        self.assertEqual(target.read_text(), self.original)

    def test_concurrent_edit_not_overwritten(self):
        def concurrent_download(args, **kwargs):
            self.download(args, **kwargs)
            self.formula.write_text(self.original + "# concurrent edit\n")
        with patch.object(pin.subprocess, "run", side_effect=concurrent_download):
            with self.assertRaisesRegex(ValueError, "changed while downloading"):
                pin.pin_release("1.2.3", URL)
        self.assertTrue(self.formula.read_text().endswith("# concurrent edit\n"))


if __name__ == "__main__":
    unittest.main()
