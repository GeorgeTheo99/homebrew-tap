require "uri"

class PiShared < Formula
  desc "Pi coding agent with explicit, modular pi-shared setup"
  homepage "https://github.com/GeorgeTheo99/pi-shared"
  # BEGIN STABLE RELEASE (populated only after a real release is verified)
  url "https://github.com/GeorgeTheo99/pi-setup/archive/refs/tags/v0.1.15.tar.gz"
  version "0.1.15"
  sha256 "fe0b10e9c6c16f76eb198dc9f47615d6e3d5fc3c537d229cc03c1ec08725a4b7"
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

      Direct native Pi providers are the default. Add a gateway alongside them:
        pi-shared setup --with model-gateway
      For local Apple Silicon models, choose oMLX during setup, or run:
        pi-shared setup --local
      To connect directly to an existing server gateway (including Tailscale),
      use setup --with existing-gateway; no local gateway service is installed.
      pi-fallback is a separate optional recovery prototype, not a dependency.

      Setup can modify HOME and invoke independent module installers. Brew
      upgrade/uninstall does not update/delete those checkouts or stop their
      services. Before removing the package, review and apply user setup teardown:
        pi-shared uninstall --plan
        pi-shared uninstall --yes
      Add --archive-config to detach Pi gateway model entries for a mode change.
      Teardown archives changed files privately, stops recorded shared services
      for all their clients, and preserves credentials, sessions, checkouts and
      gateway source configuration. See docs/uninstall.md for retained state.
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
    assert_match "Model access: direct", shell_output("#{bin}/pi-shared setup --plan --without-browser")
    assert_match "Model access: direct, model-gateway",
                 shell_output("#{bin}/pi-shared setup --with direct --with model-gateway --plan --without-browser")
    setup_version = shell_output("#{bin}/pi-shared --version").strip
    if build.head?
      assert_match(/\Api-shared setup \d+\.\d+\.\d+\z/, setup_version)
    else
      assert_equal "pi-shared setup #{version}", setup_version
    end
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
    assert_match "--archive-config", shell_output("#{bin}/pi-shared uninstall --help")
    assert_match "No managed setup receipt", shell_output("#{bin}/pi-shared uninstall --plan")
    assert_match "--require-omnigent", shell_output("#{bin}/pi-shared status --help")
    assert_match "--with-omnigent", shell_output("#{bin}/pi-shared setup --plan --mode later --without-browser --with-omnigent")
    assert_match "Setup plan", shell_output("#{bin}/pi-shared setup --plan --mode later")
    expected_pi = JSON.parse((libexec/"runtime/package.json").read).fetch("dependencies")
                      .fetch("@earendil-works/pi-coding-agent")
    assert_match(/\A\d+\.\d+\.\d+\z/, expected_pi)
    assert_equal expected_pi, shell_output("#{bin}/pi --version").strip
    assert_match "launcher support is not installed", shell_output("#{bin}/pi models 2>&1", 1)
    assert_match "launcher support is not installed", shell_output("#{bin}/pi models --json 2>&1", 1)
    assert_equal libexec/"runtime/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js",
                 (bin/"pi-upstream").realpath
    assert_equal expected_pi, shell_output("#{bin}/pi-upstream --version").strip
    refute_path_exists testpath/".zshrc"
  end
end
