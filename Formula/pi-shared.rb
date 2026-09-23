require "uri"

class PiShared < Formula
  desc "Pi coding agent with explicit, modular pi-shared setup"
  homepage "https://github.com/GeorgeTheo99/pi-shared"
  # BEGIN STABLE RELEASE (populated only after a real release is verified)
  url "https://github.com/GeorgeTheo99/pi-setup/archive/refs/tags/v0.1.11.tar.gz"
  version "0.1.11"
  sha256 "4932a4e01150c9b17286f64d14c549ce30129e98339cf56ad38ef0d7050b6cc1"
  # END STABLE RELEASE
  license "Apache-2.0"
  head "https://github.com/GeorgeTheo99/pi-setup.git", branch: "main"

  depends_on "git"
  depends_on :macos
  depends_on "node"
  depends_on "python@3.12"
  depends_on "uv"

  def install
    %w[bin/pi bin/pi-shared runtime/package.json runtime/package-lock.json].each do |file|
      odie "Source is not packaging-ready: missing #{file}" unless (buildpath/file).file?
    end

    # Keep npm's cache/config in the disposable build tree, not the user's HOME.
    (buildpath/"empty-npmrc").write ""
    ENV["npm_config_userconfig"] = buildpath/"empty-npmrc"
    ENV["npm_config_globalconfig"] = buildpath/"empty-global-npmrc"
    (buildpath/"empty-global-npmrc").write ""
    ENV["npm_config_cache"] = buildpath/"npm-cache"
    # Homebrew 7 filters ordinary npm_* variables before formula evaluation.
    # A generic, explicit mirror override retains lockfile integrity checks.
    if (registry = ENV["HOMEBREW_NPM_REGISTRY"])
      uri = URI.parse(registry)
      odie "HOMEBREW_NPM_REGISTRY must be a credential-free HTTPS registry URL" unless
        registry.match?(%r{\Ahttps://[^/\s]+(?:/|\z)}i) &&
        uri.is_a?(URI::HTTPS) && !uri.host.to_s.empty? && !uri.userinfo && !uri.query && !uri.fragment
      ENV["npm_config_registry"] = registry
    end
    libexec.install "bin", "lib", "docs", "runtime", "install.sh", "manifest.yaml", "README.md", "LICENSE"
    (libexec/"homebrew.json").write <<~JSON
      {"manager":"homebrew","formula":"#{full_name}"}
    JSON
    cd libexec/"runtime" do
      system "npm", "ci", "--ignore-scripts", "--no-audit", "--no-fund"
    end

    # Keep an explicit stock-runtime entry point for recovery and SDK discovery.
    pi_cli = libexec/"runtime/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"
    inreplace pi_cli, "#!/usr/bin/env node", "#!#{Formula["node"].opt_bin}/node"
    bin.install_symlink pi_cli => "pi-upstream"

    inreplace libexec/"bin/pi", "#!/usr/bin/env python3",
              "#!#{Formula["python@3.12"].opt_bin}/python3.12"
    inreplace libexec/"bin/pi-shared", "#!/usr/bin/env python3",
              "#!#{Formula["python@3.12"].opt_bin}/python3.12"
    paths = [bin, Formula["node"].opt_bin, Formula["python@3.12"].opt_libexec/"bin",
             Formula["uv"].opt_bin, Formula["git"].opt_bin, HOMEBREW_PREFIX/"bin"]
    (bin/"pi-shared").write_env_script libexec/"bin/pi-shared", PATH: "#{paths.join(":")}:$PATH"
    (bin/"pi").write_env_script libexec/"bin/pi",
                               PATH: "#{paths.join(":")}:$PATH",
                               PI_UPSTREAM_BIN: (bin/"pi-upstream").to_s
  end

  def caveats
    <<~EOS
      Installation only packages Pi and the setup orchestrator. No profiles,
      shell configuration, services, credentials, or models are provisioned.
      Review and run setup explicitly:
        pi-shared setup --help
        pi-shared setup --plan --mode later
        pi-shared setup

      For native Pi subscriptions/API keys without a local gateway, run:
        pi-shared setup --mode direct
      For local Apple Silicon models, choose oMLX during setup, or run:
        pi-shared setup --local
      To connect directly to an existing server gateway (including Tailscale),
      choose Existing gateway in setup; no local gateway service is installed.
      pi-fallback is a separate optional recovery prototype, not a dependency.

      Setup can modify HOME and invoke independent module installers. Brew
      upgrade/uninstall does not update/delete those checkouts or stop their
      services. Manage them with pi-shared setup or their own operator tools.
      Use pi-shared update or bare pi update for the saved installation
      (including its owned Homebrew runtime). Explicit update options keep
      stock behavior; pi update --self cannot update this runtime.
      After setup, use pi openai or
      pi <model-alias>; pi <model-alias> --default saves your default.
      pi models lists model aliases; pi list continues to list packages.
      No generated shell functions or shell-startup hook are required.
    EOS
  end

  test do
    ENV["PI_OFFLINE"] = "1"
    assert_match "setup", shell_output("#{bin}/pi-shared --help")
    assert_match "--mode", shell_output("#{bin}/pi-shared setup --help")
    assert_match "0.1.11", shell_output("#{bin}/pi-shared --version")
    assert_match "Direct-only policy", shell_output("#{bin}/pi-shared setup --plan --mode direct --without-browser")
    assert_match "--gateway-key-file", shell_output("#{bin}/pi-shared setup --help")
    assert_match "Direct external gateway", shell_output(
      "#{bin}/pi-shared setup --plan --mode existing-gateway --without-browser " \
      "--gateway-url http://100.100.1.2:9111 --allow-private-http --gateway-key-file #{testpath}/missing.key"
    )
    refute_path_exists testpath/".config/pi-shared/setup.json"
    update_output = shell_output("#{bin}/pi update 2>&1", 1)
    assert_match "pi update: running pi-shared update", update_output
    assert_match "No safe setup receipt found", update_output
    refute_path_exists testpath/".config/pi-shared/setup.json"
    assert_match "--extensions", shell_output("#{bin}/pi update --help")
    assert_match "--with-omnigent", shell_output("#{bin}/pi-shared setup --help")
    assert_match "--require-omnigent", shell_output("#{bin}/pi-shared status --help")
    assert_match "--with-omnigent", shell_output("#{bin}/pi-shared setup --plan --mode later --without-browser --with-omnigent")
    assert_match "Setup plan", shell_output("#{bin}/pi-shared setup --plan --mode later")
    assert_match "0.87.1", shell_output("#{bin}/pi --version")
    assert_match "launcher support is not installed", shell_output("#{bin}/pi models 2>&1", 1)
    assert_match "launcher support is not installed", shell_output("#{bin}/pi models --json 2>&1", 1)
    assert_equal libexec/"runtime/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js",
                 (bin/"pi-upstream").realpath
    assert_match "0.87.1", shell_output("#{bin}/pi-upstream --version")
    refute_path_exists testpath/".zshrc"
  end
end
