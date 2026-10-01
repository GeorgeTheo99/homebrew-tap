require "net/http"

class ModelGateway < Formula
  desc "Self-hosted OpenAI/Anthropic-compatible router for cloud and local models"
  homepage "https://github.com/GeorgeTheo99/model-gateway"
  url "https://github.com/GeorgeTheo99/model-gateway/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "0061133c163e7cc33845eef4c0f31624669dcdf7f87cce6d4c54909153deb9e1"
  license "Apache-2.0"
  head "https://github.com/GeorgeTheo99/model-gateway.git", branch: "main"

  depends_on :macos
  depends_on "python@3.12"
  depends_on "uv"

  def install
    libexec.install "bin", "src", "scripts", "config", "docs", "pyproject.toml", "uv.lock", "README.md", "LICENSE"
    # The CLI runs from the version-independent opt path, so the LaunchAgent
    # it writes keeps working across upgrades.
    (libexec/".package").write <<~EOS
      MANAGER=homebrew
      ROOT=#{opt_libexec}
      PYTHON=#{venv}/bin/python
      BASE_PYTHON=#{formula_opt_bin("python@3.12")}/python3.12
      UV=#{formula_opt_bin("uv")}/uv
      UPGRADE=brew upgrade #{name}
    EOS
    (bin/"model-gateway").write_env_script libexec/"bin/model-gateway",
                                          PATH: "#{formula_opt_libexec("python@3.12")}/bin:$PATH"
  end

  # Prebuilt wheels lack the Mach-O header padding Homebrew's keg relocation
  # needs, so the locked runtime environment lives outside the keg.
  def venv
    var/"model-gateway/venv"
  end

  post_install_steps do
    run "bin/model-gateway",
        base:           :opt_prefix,
        args:           ["_sync-packaged-env"],
        writable_paths: ["model-gateway"],
        writable_base:  :var,
        network_access: true
  end

  def caveats
    <<~EOS
      Installing the package does not start a service. Set up and start the
      gateway (LaunchAgent on 127.0.0.1:9111), then open the admin UI:
        model-gateway install
        model-gateway admin

      Config, catalog, secrets and the usage ledger live in
        ~/Library/Application Support/model-gateway
      and survive upgrades. The gateway keeps running the old code until it is
      restarted, so restart it after upgrading:
        brew upgrade model-gateway && model-gateway restart
      If the post-install step failed (for example offline), rebuild the
      Python environment with: brew postinstall model-gateway

      Before uninstalling the package, remove the LaunchAgent; afterwards the
      Python environment can be deleted too:
        model-gateway uninstall
        brew uninstall model-gateway
        rm -rf #{venv.parent}
    EOS
  end

  test do
    ENV["HOME"] = testpath
    app = testpath/"Library/Application Support/model-gateway"
    env = shell_output("#{bin}/model-gateway env")
    assert_match "PACKAGE_MANAGER=homebrew\n", env
    assert_match "ROOT_DIR=#{opt_libexec}\n", env
    assert_match "MODEL_GATEWAY_CONFIG=#{app}/config.yaml\n", env
    assert_match "MODEL_GATEWAY_LEDGER_PATH=#{app}/ledger.db\n", env
    assert_match "brew upgrade model-gateway", shell_output("#{bin}/model-gateway update 2>&1", 1)

    (testpath/"config.yaml").write <<~YAML
      auth:
        admin_keys: [test-admin-key]
      providers: {}
    YAML
    chmod 0600, testpath/"config.yaml"
    (testpath/"model-info.json").write <<~JSON
      {"llm": [{"name": "starter-placeholder", "provider": "starter",
                "provider_model_id": "starter-placeholder", "context": 8192, "max_output_tokens": 4096}]}
    JSON
    port = free_port
    server = spawn({
      "MODEL_GATEWAY_CONFIG"        => (testpath/"config.yaml").to_s,
      "MODEL_GATEWAY_MODEL_INFO"    => (testpath/"model-info.json").to_s,
      "MODEL_GATEWAY_LEDGER_PATH"   => (testpath/"ledger.db").to_s,
      "MODEL_GATEWAY_ENDPOINT_FILE" => "",
      "MODEL_GATEWAY_PORT"          => port.to_s,
    }, venv/"bin/python", "-m", "src.main", chdir: libexec, [:out, :err] => (testpath/"server.log").to_s)
    begin
      health = nil
      30.times do
        sleep 1
        health = Utils.popen_read("curl", "-fsS", "http://127.0.0.1:#{port}/health")
        break if $CHILD_STATUS.success?
      end
      assert_match '"service":"model-gateway"', health.delete(" "), (testpath/"server.log").read
      request = Net::HTTP::Get.new(URI("http://127.0.0.1:#{port}/admin/api/status"))
      request["x-api-key"] = "test-admin-key"
      response = Net::HTTP.start("127.0.0.1", port) { |http| http.request(request) }
      assert_equal "200", response.code
      status = JSON.parse(response.body)
      assert_equal (testpath/"config.yaml").realpath.to_s, status.fetch("config_path")
      assert_equal true, status.fetch("auth").fetch("admin_key_configured")
    ensure
      Process.kill("TERM", server)
      Process.wait(server)
    end
  end
end
