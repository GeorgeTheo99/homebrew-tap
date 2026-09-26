#!/usr/bin/env python3
"""Real CLI/guided TTY cancellation smoke; never approves installs or services."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time


def read_chunk(master):
    try:
        return os.read(master, 65536)
    except OSError as error:
        if error.errno == errno.EIO:  # Linux PTY EOF (macOS returns b"").
            return b""
        raise


def terminal_case(executable, arguments, actions, expected_code):
    with tempfile.TemporaryDirectory(prefix="pi-setup-cli-smoke-") as directory:
        home = Path(directory).resolve()
        env = {"HOME": str(home), "PATH": os.environ["PATH"], "PI_OFFLINE": "1",
               "TERM": "xterm-256color", "PYTHONDONTWRITEBYTECODE": "1",
               "HOMEBREW_NO_AUTO_UPDATE": "1"}
        master, slave = pty.openpty()
        process = None
        output = bytearray()
        try:
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
            process = subprocess.Popen([executable, "setup", *arguments], stdin=slave,
                                       stdout=slave, stderr=slave, env=env, start_new_session=True)
            os.close(slave)
            slave = None

            def receive(timeout):
                if not select.select([master], [], [], timeout)[0]:
                    return None
                chunk = read_chunk(master)
                output.extend(chunk)
                if len(output) > 256 * 1024:
                    raise RuntimeError("TTY output exceeded smoke-test limit")
                return chunk

            for expected, keys in actions:
                start = len(output)
                deadline = time.monotonic() + 10
                while expected.encode() not in output[start:]:
                    if time.monotonic() >= deadline:
                        raise RuntimeError(f"Timed out waiting for {expected!r}: {output.decode(errors='replace')}")
                    chunk = receive(0.1)
                    if chunk == b"" or chunk is None and process.poll() is not None:
                        raise RuntimeError(f"Exited before {expected!r}: {output.decode(errors='replace')}")
                os.write(master, keys)

            deadline = time.monotonic() + 10
            while process.poll() is None:
                if time.monotonic() >= deadline:
                    raise RuntimeError("Setup did not finish after cancellation")
                receive(0.1)  # Drain while waiting; curses teardown can fill PTY buffers.
            while receive(0) not in (None, b""):
                pass
            text = output.decode(errors="replace")
            if process.returncode != expected_code:
                raise RuntimeError(f"Setup exited {process.returncode}, expected {expected_code}: {text}")
            if list(home.iterdir()):
                raise RuntimeError("Cancelled/read-only setup changed isolated HOME")
            return text
        finally:
            if process is not None:
                if process.poll() is None:
                    process.kill()
                process.wait()
            os.close(master)
            if slave is not None:
                os.close(slave)


def main():
    # An optional explicit executable allows the same smoke against source before release.
    if len(sys.argv) > 2:
        raise RuntimeError("Usage: smoke_questionnaire.py [pi-shared-executable]")
    executable = str(Path(sys.argv[1]).resolve()) if len(sys.argv) == 2 else shutil.which("pi-shared")
    if not executable:
        raise RuntimeError("Installed pi-shared executable required")

    output = terminal_case(executable, [], [("Apply this plan? [y/N]", b"n\r")], 0)
    if "Model connection:" in output or "Cancelled; no installation changes made." not in output:
        raise RuntimeError("Default setup must show only the plan and approval, not component menus")

    output = terminal_case(executable, ["--with", "existing-gateway"], [
        ("Existing gateway base URL", b"https://gateway.example/model-gateway\r"),
        ("Absolute path", b"/private/client.key\r"),
        ("Apply this plan? [y/N]", b"n\r"),
    ], 0)
    if any(prompt in output for prompt in ("Model connection:", "Public browser automation:",
                                           "Optional Omnigent", "Optional independent recovery",
                                           "Web search and page retrieval")):
        raise RuntimeError("Focused gateway setup asked unrelated questions")
    if "https://gateway.example/model-gateway" not in output:
        raise RuntimeError("Focused gateway setup lost the reverse-proxy prefix")

    down = b"\x1bOB"  # xterm application-mode Down, with curses keypad enabled.
    output = terminal_case(executable, ["--guided"], [
        ("Model connection", down * 5 + b"\r"),
        ("Public browser automation", down + b"\r"),
        ("Optional Omnigent", b"\r"),
        ("Optional independent recovery", b"\r"),
        ("Web search and page retrieval", down * 2 + b"\r"),
        ("Cancel without changes", b"\x1b[6~\x1bOH\r"),
    ], 0)
    if "Cancelled; no installation changes made." not in output or "Choice (or cancel)" in output:
        raise RuntimeError("Guided setup did not finish with keyboard-only cancellation")

    output = terminal_case(executable, ["--guided"], [("Model connection", b"\x1b")], 130)
    if "Cancelled" not in output:
        raise RuntimeError("Escape did not cancel guided setup")

    output = terminal_case(executable, ["--guided", "--plan"], [], 0)
    if "Setup plan" not in output or "\x1b[?1049h" in output or "Apply this plan?" in output:
        raise RuntimeError("--guided --plan must never open menus or ask for approval")
    print("PASS CLI-first and guided keyboard setup: plans, navigation and cancellation write nothing")


if __name__ == "__main__":
    main()
