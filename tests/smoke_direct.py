#!/usr/bin/env python3
"""Installed direct-only setup/update smoke in disposable HOME; no inference.

Explicitly installs public shared resources/dependencies, not gateway/browser
services or model weights. Native credentials below are synthetic fixture data.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    with tempfile.TemporaryDirectory(prefix="pi-direct-release-") as directory:
        home = Path(directory).resolve()
        env = {k: v for k, v in os.environ.items() if not k.startswith(("PI_", "MODEL_GATEWAY_"))}
        profile = home / "custom-native-profile"
        profile.mkdir(mode=0o700)
        native = {
            "auth.json": '{"test-provider":{"type":"api_key","key":"synthetic-only"}}',
            "models.json": '{"providers":{}}',
        }
        for name, content in native.items():
            path = profile / name
            path.write_text(content)
            path.chmod(0o600)
        env.update(HOME=str(home), PI_OFFLINE="1", PYTHONDONTWRITEBYTECODE="1",
                   PI_SHARED_AGENT_DIR=str(profile))
        # A malformed gateway catalog must not be consulted in direct mode.
        aliases = home / ".pi/model-aliases.json"
        aliases.parent.mkdir(mode=0o700)
        aliases.write_text("INVALID GATEWAY CATALOG MUST NOT BE READ")

        def run(*command):
            subprocess.run(command, env=env, check=True, timeout=600)

        run("pi-shared", "setup", "--mode", "direct", "--without-browser", "--yes")
        receipt_path = home / ".config/pi-shared/setup.json"
        receipt = json.loads(receipt_path.read_text())
        assert receipt["status"] == "module-checks-passed"
        assert receipt["mode"] == "direct"
        assert receipt["modules"] == ["pi-shared"]
        assert receipt["services"] == {}
        assert receipt["settings"]["PI_SHARED_DIRECT_ONLY"] == "1"
        assert Path(receipt["agent_dir"]) == profile
        del env["PI_SHARED_AGENT_DIR"]  # Subsequent operations must use saved paths.
        run("pi", "models")
        listing = json.loads(subprocess.check_output(["pi", "models", "--direct", "--json"], env=env, text=True))
        assert [row["alias"] for row in listing["models"]] == ["openai"]
        assert listing["models"][0]["group"] == "direct"
        assert json.loads(subprocess.check_output(["pi", "models", "--local", "--json"], env=env, text=True))["models"] == []
        assert "Route: openai-codex/" in subprocess.check_output(["pi", "models", "--verbose"], env=env, text=True)
        run("pi", "--launcher-check")
        run("pi", "openai", "--default")
        expected_default = json.loads((profile / "settings.json").read_text())
        assert expected_default["defaultProvider"] == "openai-codex"
        listing = json.loads(subprocess.check_output(["pi", "models", "--json"], env=env, text=True))
        assert listing["models"][0]["default"] is True
        assert listing["savedDefault"]["profile"] == str(profile)
        run("pi-shared", "setup", "--mode", "direct", "--without-browser", "--yes")
        run("pi-shared", "status")
        run("pi-shared", "update", "--modules-only")
        run("pi-shared", "status")
        run("pi", "--launcher-refresh")
        run("pi", "--version")
        after = json.loads(receipt_path.read_text())
        for key in ("mode", "modules", "agent_dir", "cli_file", "settings"):
            assert after[key] == receipt[key], key
        launcher = json.loads(Path(after["cli_file"]).read_text())
        assert launcher["generation"]["args"] == [
            "--direct-only", "--shared-dir", str(Path(after["code_root"]) / "pi-shared"), "--direct-launchers"]
        assert all(not row["gateway"] for row in launcher["routes"].values())
        assert json.loads((profile / "settings.json").read_text()) == expected_default
        for name, content in native.items():
            assert (profile / name).read_text() == content
        assert aliases.read_text() == "INVALID GATEWAY CATALOG MUST NOT BE READ"
        for path in (home / ".zshrc", home / ".pi-omlx", home / "Library/LaunchAgents",
                     home / ".pi/agent/settings.json", Path(after["code_root"]) / "model-gateway"):
            assert not path.exists(), path
        print("PASS: installed direct-only setup, custom native profile/default, rerun, update and status; native auth/models unchanged")


if __name__ == "__main__":
    main()
