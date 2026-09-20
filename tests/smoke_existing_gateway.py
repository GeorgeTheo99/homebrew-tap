#!/usr/bin/env python3
"""Exercise the installed package against a fake loopback gateway in disposable HOME.

Opt-in release smoke: runs actual setup and module dependency installs. No real
provider calls, credentials, gateway services, browser or model downloads.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading


def main():
    requests = []
    token = "release-smoke-only-token"

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            if self.path != "/v1/models/canonical" or self.headers.get("Authorization") != "Bearer " + token:
                self.send_error(403)
                return
            self.send_response(200)
            self.end_headers()
            self.wfile.write(json.dumps({"data": [{"id": "smoke-model", "available": True,
                "vision": False, "thinking_levels": ["off", "high"], "context_length": 32768,
                "max_output_tokens": 4096}]}).encode())

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    stopped = False
    try:
        with tempfile.TemporaryDirectory(prefix="pi-remote-release-") as directory:
            home = Path(directory).resolve()
            env = {k: v for k, v in os.environ.items() if not k.startswith(("PI_", "MODEL_GATEWAY_"))}
            env.update(HOME=str(home), PI_OFFLINE="1", PYTHONDONTWRITEBYTECODE="1")
            key = home / "client.key"
            key.write_text(token + "\n")
            key.chmod(0o600)
            url = f"http://127.0.0.1:{server.server_port}"

            def run(*command):
                subprocess.run(command, env=env, check=True, timeout=600)

            run("pi-shared", "setup", "--mode", "existing-gateway", "--without-browser", "--yes",
                "--gateway-url", url, "--gateway-key-file", str(key), "--allow-private-http")
            receipt_path = home / ".config/pi-shared/setup.json"
            receipt = json.loads(receipt_path.read_text())
            assert receipt["status"] == "module-checks-passed"
            assert receipt["modules"] == ["pi-shared"]
            assert receipt["services"] == {}
            assert not (Path(receipt["code_root"]) / "model-gateway").exists()
            launcher = json.loads(Path(receipt["cli_file"]).read_text())
            routes = {alias: row for alias, row in launcher["routes"].items() if row["gateway"]}
            assert len(routes) == 1
            alias, route = next(iter(routes.items()))
            assert route["model"] == "smoke-model"
            generation = launcher["generation"]["args"]
            models_path = Path(generation[generation.index("--models-out") + 1])
            models = json.loads(models_path.read_text())
            provider = models["providers"][route["provider"]]
            assert provider["baseUrl"] == url + "/v1"
            assert provider["apiKey"].startswith("!")
            for path in (receipt_path, Path(receipt["cli_file"]), models_path):
                assert token not in path.read_text()
            assert requests == ["/v1/models/canonical"]
            # With the server still live, count any accidental catalog reads.
            run("pi-shared", "status")
            run("pi-shared", "update", "--modules-only")
            assert requests == ["/v1/models/canonical"]
            # Also prove lifecycle succeeds when the server no longer exists.
            server.shutdown()
            thread.join()
            server.server_close()
            stopped = True
            run("pi", "models")
            run("pi", "--launcher-check")
            run("pi", alias, "--default")
            run("pi-shared", "status")
            run("pi-shared", "update", "--modules-only")
            run("pi-shared", "status")
            assert json.loads(receipt_path.read_text())["external_gateway"] == receipt["external_gateway"]
            assert requests == ["/v1/models/canonical"]
            assert not (home / ".zshrc").exists()
            print("PASS: installed direct-gateway setup, model listing/default and offline update/status")
    finally:
        if not stopped:
            server.shutdown()
            thread.join()
            server.server_close()


if __name__ == "__main__":
    main()
