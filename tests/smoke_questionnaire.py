#!/usr/bin/env python3
"""Installed-package TTY cancellation smoke; no installs, keys, or services."""
import os
from pathlib import Path
import pty
import shutil
import subprocess
import tempfile


def main():
    executable = shutil.which("pi-shared")
    if not executable:
        raise RuntimeError("Installed pi-shared executable required")
    with tempfile.TemporaryDirectory(prefix="pi-questionnaire-") as directory:
        home = Path(directory).resolve()
        env = {"HOME": str(home), "PATH": os.environ["PATH"], "PI_OFFLINE": "1",
               "PYTHONDONTWRITEBYTECODE": "1", "HOMEBREW_NO_AUTO_UPDATE": "1"}
        master, slave = pty.openpty()
        try:
            process = subprocess.Popen([executable, "setup"], stdin=slave, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, text=True, env=env)
        finally:
            os.close(slave)
        try:
            os.write(master, b"later\nskip\nskip\nskip\nskip\nn\n")
            output, error = process.communicate(timeout=30)
        finally:
            os.close(master)
            if process.poll() is None:
                process.kill()
                process.wait()
        if process.returncode:
            raise RuntimeError(f"Questionnaire failed: {output}\n{error}")
        for expected in ("Model connection:", "Public browser automation:", "Omnigent",
                         "recovery", "Web search", "Setup plan", "Cancelled"):
            if expected not in output:
                raise RuntimeError(f"Missing questionnaire stage: {expected}")
        if list(home.iterdir()):
            raise RuntimeError("Declining setup changed isolated HOME")
    print("PASS installed TTY questionnaire: all component choices; declining writes nothing")


if __name__ == "__main__":
    main()
