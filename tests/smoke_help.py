#!/usr/bin/env python3
"""Verify installed help and every documented preview recipe in disposable HOMEs.

No setup application, services, credentials or provider requests are required.
"""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile


def main():
    with tempfile.TemporaryDirectory(prefix="pi-help-release-") as directory:
        root = Path(directory).resolve()
        base_env = {k: v for k, v in os.environ.items()
                    if not k.startswith(("PI_", "MODEL_GATEWAY_"))}

        def run(home, *args):
            env = dict(base_env, HOME=str(home), PI_OFFLINE="1",
                       PYTHONDONTWRITEBYTECODE="1", COLUMNS="80")
            result = subprocess.run(["pi-shared", *args], env=env,
                                    stdin=subprocess.DEVNULL, capture_output=True,
                                    text=True, timeout=30, check=True)
            assert list(home.iterdir()) == [], "Help/plan wrote into fresh HOME"
            return result.stdout

        home = root / "help"
        home.mkdir()
        for command in ([], ["setup"], ["update"], ["status"], ["uninstall"]):
            short = run(home, *command, "-h")
            assert short == run(home, *command, "--help")
            assert all(len(line) <= 80 for line in short.splitlines())
        overview = run(home, "-h")
        for text in ("Setup paths", "Remote gateway", "Web search", "pi-shared setup -h",
                     "Help never runs setup"):
            assert text in overview
        help_text = run(home, "setup", "-h")
        examples = help_text.split("Examples (", 1)[1].split("Apply and verify:", 1)[0]
        recipes = [line.strip() for line in examples.replace("\\\n", "").splitlines()
                   if line.strip().startswith("pi-shared setup ")]
        assert len(recipes) == 12
        for number, recipe in enumerate(recipes):
            home = root / f"recipe-{number}"
            home.mkdir()
            args = shlex.split(recipe.replace("$HOME", str(home)))
            assert args[0] == "pi-shared" and "--plan" in args
            assert "Setup plan" in run(home, *args[1:])
        print("PASS: installed help and all 12 setup recipes in empty homes")


if __name__ == "__main__":
    main()
