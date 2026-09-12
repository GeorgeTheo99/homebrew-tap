#!/usr/bin/env python3
"""Download and checksum an already-reviewed release; edit only the local formula."""

import argparse
import hashlib
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
from urllib.parse import urlsplit

FORMULA = Path(__file__).resolve().parents[1] / "Formula/pi-shared.rb"
BEGIN = "  # BEGIN STABLE RELEASE (populated only after a real release is verified)\n"
END = "  # END STABLE RELEASE\n"
MAX_BYTES = 25 * 1024 * 1024


def validate(version, url, expected):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?", version):
        raise ValueError("version must be X.Y.Z (optionally with a prerelease suffix)")
    # Restrict to printable URL characters safe inside a Ruby double-quoted string.
    if not url.isascii() or re.search(r'[\s\x00-\x1f\x7f"\'\\#{}]', url):
        raise ValueError("URL contains unsafe characters; percent-encode them")
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username is not None
            or parsed.password is not None or parsed.query or parsed.fragment):
        raise ValueError("a credential-free HTTPS archive URL without a query or fragment is required")
    if not parsed.path.endswith((".tar.gz", ".tgz")):
        raise ValueError("URL path must identify a .tar.gz or .tgz archive")
    if expected is not None and not re.fullmatch(r"[a-fA-F0-9]{64}", expected):
        raise ValueError("--sha256 must contain exactly 64 hexadecimal characters")


def pin_release(version, url, expected=None):
    validate(version, url, expected)
    info = FORMULA.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise ValueError("formula must be a regular, non-linked file")
    original = FORMULA.read_text()
    if original.count(BEGIN) != 1 or original.count(END) != 1:
        raise ValueError("formula must contain exactly one stable release marker pair")
    before, remainder = original.split(BEGIN)
    _, after = remainder.split(END)  # Also refuses an END preceding BEGIN.

    with tempfile.TemporaryDirectory(prefix="pi-shared-release-") as temporary:
        archive = Path(temporary) / "source.tar.gz"
        subprocess.run(
            ["/usr/bin/curl", "--disable", "--fail", "--silent", "--show-error", "--location",
             "--proto", "=https", "--proto-redir", "=https", "--max-redirs", "3",
             "--connect-timeout", "10", "--max-time", "90", "--max-filesize", str(MAX_BYTES),
             "--limit-rate", "5M", "--output", str(archive), "--url", url],
            check=True, timeout=95,
        )
        if not 0 < archive.stat().st_size <= MAX_BYTES:
            raise ValueError("download is empty or exceeds 25 MiB")
        with archive.open("rb") as stream:
            if stream.read(2) != b"\x1f\x8b":
                raise ValueError("download is not a gzip archive")
            stream.seek(0)
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        if expected is not None and digest != expected.lower():
            raise ValueError("downloaded SHA-256 does not match --sha256")

    stanza = f'  url "{url}"\n  version "{version}"\n  sha256 "{digest}"\n'
    updated = before + BEGIN + stanza + END + after
    current = FORMULA.lstat()
    if FORMULA.read_text() != original or (current.st_dev, current.st_ino) != (info.st_dev, info.st_ino):
        raise ValueError("formula changed while downloading; retry after review")
    staged = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=FORMULA.parent, delete=False) as stream:
            staged = Path(stream.name)
            stream.write(updated)
            stream.flush()
            os.fchmod(stream.fileno(), stat.S_IMODE(info.st_mode))
        os.replace(staged, FORMULA)
    finally:
        if staged is not None:
            staged.unlink(missing_ok=True)
    return digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="pi-setup release version, e.g. 1.2.3 (not Pi's npm version)")
    parser.add_argument("url", help="reviewed HTTPS .tar.gz/.tgz source URL")
    parser.add_argument("--sha256", help="optional independently obtained expected SHA-256")
    args = parser.parse_args()
    try:
        digest = pin_release(args.version, args.url, args.sha256)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Release pinning failed: {error}\n")
    print(f"Updated only {FORMULA}\nSHA-256: {digest}\nReview the diff and test; nothing was published.")


if __name__ == "__main__":
    main()
