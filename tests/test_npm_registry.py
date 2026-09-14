"""Exercise the formula's mirror-validation block without installing packages."""
import os
from pathlib import Path
import subprocess
import unittest

FORMULA = Path(__file__).resolve().parents[1] / "Formula/pi-shared.rb"
text = FORMULA.read_text()
start = text.index('    if (registry = ENV["HOMEBREW_NPM_REGISTRY"])')
end = text.index('    libexec.install', start)
BLOCK = text[start:end]


class NpmRegistryTests(unittest.TestCase):
    def run_block(self, value=None):
        env = {k: v for k, v in os.environ.items() if k not in {"HOMEBREW_NPM_REGISTRY", "npm_config_registry"}}
        if value is not None:
            env["HOMEBREW_NPM_REGISTRY"] = value
        program = 'require "uri"\ndef odie(message); raise ArgumentError, message; end\n' + BLOCK + '\nputs ENV.fetch("npm_config_registry", "unset")\n'
        return subprocess.run(["ruby", "-e", program], env=env, text=True, capture_output=True)

    def test_default_is_unchanged(self):
        result = self.run_block()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "unset")

    def test_explicit_https_mirror_is_forwarded(self):
        result = self.run_block("https://npm-mirror.example.com/registry/")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "https://npm-mirror.example.com/registry/")

    def test_credentials_and_non_https_or_ambiguous_urls_are_rejected(self):
        for url in ("http://example.com/", "https://user:example@example.com/", "https://example.com/?token=example",
                    "https://example.com/#fragment", "https:///registry", "not a URL"):
            with self.subTest(url=url):
                self.assertNotEqual(self.run_block(url).returncode, 0)


if __name__ == "__main__":
    unittest.main()
