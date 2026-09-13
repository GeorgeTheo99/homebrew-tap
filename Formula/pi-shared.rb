class PiShared < Formula
  desc "Pi coding agent with explicit, modular pi-shared setup"
  homepage "https://github.com/GeorgeTheo99/pi-setup"
  # BEGIN STABLE RELEASE (populated only after a real release is verified)
  url "https://github.com/GeorgeTheo99/pi-setup/archive/refs/tags/v0.1.3.tar.gz"
  version "0.1.3"
  sha256 "e222bbf093145d285932c0075416a0340587a93bad01e08b29e27ca6b1d70034"
  # END STABLE RELEASE
  license "Apache-2.0"
  head "https://github.com/GeorgeTheo99/pi-setup.git", branch: "main"

  depends_on "git"
  depends_on :macos
  depends_on "node"
  depends_on "python@3.12"
  depends_on "uv"

  def install
    %w[bin/pi-shared runtime/package.json runtime/package-lock.json].each do |file|
      odie "Source is not packaging-ready: missing #{file}" unless (buildpath/file).file?
    end

    # Keep npm's cache/config in the disposable build tree, not the user's HOME.
    (buildpath/"empty-npmrc").write ""
    ENV["npm_config_userconfig"] = buildpath/"empty-npmrc"
    ENV["npm_config_globalconfig"] = buildpath/"empty-global-npmrc"
    (buildpath/"empty-global-npmrc").write ""
    ENV["npm_config_cache"] = buildpath/"npm-cache"
    libexec.install "bin", "lib", "docs", "runtime", "install.sh", "manifest.yaml", "README.md", "LICENSE"
    (libexec/"homebrew.json").write <<~JSON
      {"manager":"homebrew","formula":"#{full_name}"}
    JSON
    cd libexec/"runtime" do
      system "npm", "ci", "--ignore-scripts", "--no-audit", "--no-fund"
    end

    # A real symlink lets pi-profile-check discover the installed Pi SDK.
    pi_cli = libexec/"runtime/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"
    inreplace pi_cli, "#!/usr/bin/env node", "#!#{Formula["node"].opt_bin}/node"
    bin.install_symlink pi_cli => "pi"

    inreplace libexec/"bin/pi-shared", "#!/usr/bin/env python3",
              "#!#{Formula["python@3.12"].opt_bin}/python3.12"
    paths = [bin, Formula["node"].opt_bin, Formula["python@3.12"].opt_libexec/"bin",
             Formula["uv"].opt_bin, Formula["git"].opt_bin, HOMEBREW_PREFIX/"bin"]
    (bin/"pi-shared").write_env_script libexec/"bin/pi-shared", PATH: "#{paths.join(":")}:$PATH"
  end

  def caveats
    <<~EOS
      Installation only packages Pi and the setup orchestrator. No profiles,
      shell configuration, services, credentials, or models are provisioned.
      Review and run setup explicitly:
        pi-shared setup --help
        pi-shared setup --plan --mode later
        pi-shared setup

      For local Apple Silicon models, choose oMLX during setup, or run:
        pi-shared setup --local
      pi-fallback is a separate optional recovery prototype, not a dependency.

      Setup can modify HOME and invoke independent module installers. Brew
      upgrade/uninstall does not update/delete those checkouts or stop their
      services. Manage them with pi-shared setup or their own operator tools.
      Use pi-shared update for the saved installation (including its owned
      Homebrew runtime), not pi update --self. Background prompt refresh never
      upgrades software, restarts services, or calls a model.
    EOS
  end

  test do
    ENV["PI_OFFLINE"] = "1"
    assert_match "setup", shell_output("#{bin}/pi-shared --help")
    assert_match "--mode", shell_output("#{bin}/pi-shared setup --help")
    assert_match "Setup plan", shell_output("#{bin}/pi-shared setup --plan --mode later")
    assert_match "0.85.1", shell_output("#{bin}/pi --version")
    assert_equal libexec/"runtime/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js",
                 (bin/"pi").realpath
  end
end
