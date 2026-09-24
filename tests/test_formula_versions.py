"""Exercise stable/HEAD CLI version assertions without installing packages."""
import os
from pathlib import Path
import subprocess
import unittest

FORMULA = Path(__file__).resolve().parents[1] / "Formula/pi-shared.rb"
text = FORMULA.read_text()
start = text.index('    setup_version = shell_output(')
end = text.index('    assert_match "Direct-only policy"', start)
BLOCK = text[start:end]


class FormulaVersionTests(unittest.TestCase):
    def run_block(self, head, actual):
        program = '''
def bin; "/fixture/bin"; end
def version; ENV.fetch("TEST_VERSION"); end
Build = Struct.new(:head) do
  def head?; head; end
end
def build; Build.new(ENV.fetch("TEST_HEAD") == "1"); end
def shell_output(_command); ENV.fetch("TEST_ACTUAL") + "\\n"; end
def assert_equal(expected, actual); raise "version mismatch" unless expected == actual; end
def assert_match(pattern, actual); raise "invalid version" unless pattern.match?(actual); end
''' + BLOCK
        return subprocess.run(["ruby", "-e", program], text=True, capture_output=True,
                              env={**os.environ, "TEST_VERSION": "HEAD" if head else "0.1.12",
                                   "TEST_HEAD": "1" if head else "0", "TEST_ACTUAL": actual})

    def test_stable_requires_exact_formula_version(self):
        result = self.run_block(False, "pi-shared setup 0.1.12")
        self.assertEqual(result.returncode, 0, result.stderr)
        for actual in ("pi-shared setup 0.1.11", "pi-shared setup 0.1.120", "pi-shared setup HEAD"):
            with self.subTest(actual=actual):
                self.assertNotEqual(self.run_block(False, actual).returncode, 0)

    def test_head_accepts_cli_semver_not_head_literal_or_extra_output(self):
        result = self.run_block(True, "pi-shared setup 0.1.12")
        self.assertEqual(result.returncode, 0, result.stderr)
        for actual in ("pi-shared setup HEAD", "pi-shared setup 0.1.12 extra", "prefix pi-shared setup 0.1.12"):
            with self.subTest(actual=actual):
                self.assertNotEqual(self.run_block(True, actual).returncode, 0)


if __name__ == "__main__":
    unittest.main()
