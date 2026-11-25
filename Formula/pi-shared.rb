require "uri"
require "shellwords"

class PiShared < Formula
  desc "Pi coding agent with explicit, modular pi-shared setup"
  homepage "https://github.com/GeorgeTheo99/pi-shared"
  # BEGIN STABLE RELEASE (populated only after a real release is verified)
  url "https://github.com/GeorgeTheo99/pi-setup/archive/refs/tags/v0.1.57.tar.gz"
  version "0.1.57"
  sha256 "dec55fad5ef561faf9a153fc9d878898d1b9fd5174c938f1baf66a251a1bf870"
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

    # Share the packaged Pi and Homebrew Node, but keep the Claude bridge profile opt-in.
    launcher = bin/"pi-claude"
    launcher.write <<~SH
      #!/bin/sh
      export PATH=#{Formula["node"].opt_bin.to_s.shellescape}:"$PATH"
      export PI_CODING_AGENT_DIR="$HOME/.pi-claude/agent"
      unset ANTHROPIC_API_KEY ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN PI_CODING_AGENT_SESSION_DIR
      pi=#{(bin/"pi-upstream").to_s.shellescape}
      case "${1-}" in
        -h|--help)
          /bin/cat <<'HELP'
      Usage: pi claude [pi options] [prompt...]
             pi claude --list-models [search]
             pi claude install|list|remove ...
             pi claude --help | --version

      pi-claude remains available as a compatibility command.

      Launch Pi through the optional Claude Code bridge. Uses the Pi and Node
      installed by Homebrew's pi-shared package and the ~/.pi-claude/agent profile.
      This is separate from pi-anthropic (Pi's native Anthropic provider).

      First-time setup (requires Claude Code):
        claude auth login
        pi claude install npm:pi-claude-bridge@0.11.0
        pi claude --list-models
        pi claude

      Already configured? The launcher reuses your existing Claude profile.
      If a shell function shadows it, check the packaged executable first:
        "$(brew --prefix pi-shared)/bin/pi-claude" --list-models claude-bridge

      Upgrade the runtime with brew upgrade pi-shared. Use pi-upstream --help
      for Pi options. Setup and migration: https://github.com/GeorgeTheo99/homebrew-tap#optional-claude-code-bridge
      HELP
          exit 0
          ;;
        install|remove|uninstall|list|config|auth|mcp|-v|--version)
          exec "$pi" "$@"
          ;;
        update)
          echo 'pi-claude: upgrade the runtime with brew upgrade pi-shared; use pi claude install to select a bridge version.' >&2
          exit 1
          ;;
      esac
      if [ ! -f "$PI_CODING_AGENT_DIR/settings.json" ]; then
        echo 'pi claude: Claude bridge profile is not configured; run pi claude --help for opt-in setup.' >&2
        exit 1
      fi
      search=claude-bridge
      if [ "${1-}" = --list-models ]; then
        if [ "$#" -gt 2 ]; then
          echo 'Usage: pi claude --list-models [search]' >&2
          exit 1
        fi
        search="${2:-claude-bridge}"
      fi
      # An empty --models match falls back to other providers.
      models=$("$pi" --offline --no-approve --no-mcp --list-models "$search" </dev/null) || {
        status=$?
        echo 'pi claude: could not list models with the packaged Pi runtime. Check pi --version; if that fails, repair Homebrew pi-shared or its Node dependency.' >&2
        exit "$status"
      }
      matches=$(printf '%s\\n' "$models" | /usr/bin/awk 'NR == 1 && $1 == "provider" { header = $0 } $1 == "claude-bridge" { if (!found++ && header != "") print header; print } END { exit !found }') || {
        echo 'pi claude: no matching Claude bridge models. Try pi claude --list-models without a search, or see pi claude --help for setup.' >&2
        exit 1
      }
      if [ "${1-}" = --list-models ]; then
        printf '%s\\n' "$matches"
        exit 0
      fi
      # Pin the provider in the final process, not only in the discovery probe.
      # Otherwise Pi can fall back if the bridge disappears between launches.
      for arg do
        case "$arg" in
          --provider|--provider=*|--models|--models=*|--no-extensions|-ne)
            echo 'pi claude: this launcher requires the Claude bridge and does not accept provider, model-scope or extension-disable overrides. Use pi for those options.' >&2
            exit 1
            ;;
        esac
      done
      model=$(#{(Formula["python@3.12"].opt_bin/"python3.12").to_s.shellescape} -c '
      import json, sys
      from pathlib import Path
      try:
          settings = json.loads(Path(sys.argv[1]).read_text())
          if isinstance(settings, dict) and settings.get("defaultProvider") == "claude-bridge":
              print(settings.get("defaultModel", ""))
      except (OSError, ValueError):
          pass
      ' "$PI_CODING_AGENT_DIR/settings.json") || exit "$?"
      model=$(printf '%s\\n' "$matches" | /usr/bin/awk -v preferred="$model" '$1 == "claude-bridge" { if (!first) first = $2; if ($2 == preferred) chosen = $2 } END { print chosen ? chosen : first }')
      exec "$pi" --provider claude-bridge --model "$model" --models 'claude-bridge/*' "$@"
    SH
    launcher.chmod(0755)

    inreplace libexec/"bin/pi", "#!/usr/bin/env python3",
              "#!#{Formula["python@3.12"].opt_bin}/python3.12"
    inreplace libexec/"bin/pi-shared", "#!/usr/bin/env python3",
              "#!#{Formula["python@3.12"].opt_bin}/python3.12"
    inreplace libexec/"bin/pi-anthropic", "#!/usr/bin/env python3",
              "#!#{Formula["python@3.12"].opt_bin}/python3.12"
    paths = [bin, Formula["node"].opt_bin, Formula["python@3.12"].opt_libexec/"bin",
             Formula["uv"].opt_bin, Formula["git"].opt_bin, HOMEBREW_PREFIX/"bin"]
    (bin/"pi-shared").write_env_script libexec/"bin/pi-shared", PATH: "#{paths.join(":")}:$PATH"
    (bin/"pi").write_env_script libexec/"bin/pi",
                               PATH: "#{paths.join(":")}:$PATH",
                               PI_UPSTREAM_BIN: (bin/"pi-upstream").to_s
    (bin/"pi-anthropic").write_env_script libexec/"bin/pi-anthropic",
                                         PATH: "#{paths.join(":")}:$PATH",
                                         PI_UPSTREAM_BIN: (bin/"pi-upstream").to_s
  end

  def caveats
    <<~EOS
      Installation only packages Pi and the setup orchestrator. No profiles,
      shell configuration, services, credentials, or models are provisioned.
      Review and run setup explicitly:
        pi-shared -h
        pi-shared setup -h
        pi-shared setup --plan
        pi-shared setup

      Setup is CLI-first: flags and saved/default choices, then one approval.
      Optional arrow-key menus (Space toggles, Enter continues):
        pi-shared setup --guided
      Search can install a local Brave broker with private key-file input or
      connect to an existing compatible MCP endpoint. Guided mode also offers
      hidden key entry. No keys are saved before approval.
      Optional Mac computer use is separate from those defaults:
        pi-shared peekaboo plan --json
      In Pi, /setup offers search, browsers, MCP, development, documents,
      Apple prerequisites, private knowledge, models, diagnostics and Peekaboo.
      Missing project/KB configuration requires exact-plan approval; broader
      installers remain explicit terminal handoffs. /setup never grants trust.
      Peekaboo installation and macOS permission grants are never automatic.
      Fresh defaults: direct providers, browser enabled, search skipped.
      Use --without-browser to omit Chromium. Add a gateway:
        pi-shared setup --with model-gateway
      For local Apple Silicon model choices, run:
        pi-shared setup --local --guided
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
      The optional pi claude launcher uses the same packaged runtime and a
      separate ~/.pi-claude/agent profile. Bridge installation and Claude
      Code login remain explicit; run pi claude --help for setup and migration.
      The pi-claude executable remains available for compatibility.
    EOS
  end

  test do
    ENV["PI_OFFLINE"] = "1"
    assert_match "Setup paths", shell_output("#{bin}/pi-shared -h")
    assert_match "--expected-plan", shell_output("#{bin}/pi-shared peekaboo --help")
    peekaboo_plan = JSON.parse(shell_output("#{bin}/pi-shared peekaboo plan --json"))
    assert_equal 2, peekaboo_plan.fetch("schemaVersion")
    assert_equal "peekaboo", peekaboo_plan.fetch("component")
    assert_equal "not-tested", peekaboo_plan.fetch("evidence").fetch("desktop")
    assert_equal "not-tested", peekaboo_plan.fetch("evidence").fetch("mcp")
    assert_equal "not-tested", peekaboo_plan.fetch("evidence").fetch("runnable")
    assert_equal "direct", peekaboo_plan.fetch("evidence").fetch("mode")
    bridge_socket = testpath.realpath/"missing-peekaboo.sock"
    bridge_plan = JSON.parse(shell_output(
      [bin/"pi-shared", "peekaboo", "plan", "--json", "--mode", "bridge", "--bridge-socket", bridge_socket].map(&:to_s).shelljoin
    ))
    assert_equal 2, bridge_plan.fetch("schemaVersion")
    assert_equal true, bridge_plan.fetch("ok")
    assert_equal "bridge", bridge_plan.fetch("evidence").fetch("mode")
    assert_equal "missing", bridge_plan.fetch("evidence").fetch("bridgeSocketState")
    assert_nil bridge_plan.fetch("evidence").fetch("permissionSource")
    assert_equal "not-tested", bridge_plan.fetch("evidence").fetch("desktop")
    refute_path_exists bridge_socket
    refute_path_exists testpath/".config/mcp/mcp.json"
    refute_path_exists testpath/".local/share/peekaboo"
    assert_match "--expected-plan", shell_output("#{bin}/pi-shared capability --help")
    %w[project profile shared].each { |name| (testpath/"capabilities"/name).mkpath }
    metadata = testpath/"capabilities/shared/knowledge/software-engineering"
    (metadata/"corpus").mkpath
    (metadata/"sources.json").write "{}\n"
    (metadata/"documents.json").write "{}\n"
    (metadata/"corpus/source-cards.md").write "# Synthetic metadata\n"
    context = ["--json", "--project", (testpath/"capabilities/project").realpath.to_s,
               "--agent-dir", (testpath/"capabilities/profile").realpath.to_s,
               "--shared-root", (testpath/"capabilities/shared").realpath.to_s,
               "--node-executable", (Formula["node"].opt_bin/"node").realpath.to_s]
    %w[search browser mcp development documents apple knowledge models diagnostics].each do |component|
      preview = JSON.parse(shell_output(([bin/"pi-shared", "capability", component, "plan"] + context).map(&:to_s).shelljoin))
      assert_equal 1, preview.fetch("schemaVersion")
      assert_equal component, preview.fetch("component")
      assert_equal "plan", preview.fetch("action")
      assert_equal true, preview.fetch("ok")
      refute_equal "verified", preview.fetch("status")
    end
    refute_path_exists testpath/"capabilities/project/.pi"
    refute_path_exists testpath/".pi/knowledge/software-engineering"
    assert_match "Preview and approval", shell_output("#{bin}/pi-shared setup -h")
    assert_match "--mode", shell_output("#{bin}/pi-shared setup --help")
    assert_match "--guided", shell_output("#{bin}/pi-shared setup --help")
    assert_match "Setup plan", shell_output("#{bin}/pi-shared setup --guided --plan --without-browser")
    assert_match "--guided cannot be combined with --yes", shell_output("#{bin}/pi-shared setup --guided --yes 2>&1", 1)
    assert_match "--search-key-file", shell_output("#{bin}/pi-shared setup --help")
    assert_match "Search: existing", shell_output(
      "#{bin}/pi-shared setup --plan --search existing --search-url https://search.example/mcp " \
      "--search-key-file #{testpath}/missing-search.key --without-browser"
    )
    assert_match "Search: local", shell_output(
      "#{bin}/pi-shared setup --plan --search local --brave-key-file #{testpath}/missing-brave.key --without-browser"
    )
    refute_path_exists testpath/".pi/research/config.json"
    refute_path_exists testpath/".local/share/pi-shared/search"
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
    assert_match "direct launcher is unavailable", shell_output("#{bin}/pi-anthropic 2>&1", 1)
    assert_equal libexec/"runtime/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js",
                 (bin/"pi-upstream").realpath
    assert_equal expected_pi, shell_output("#{bin}/pi-upstream --version").strip

    # Simulate a stale Node earlier on the user's PATH.
    wrong_runtime = testpath/"wrong-runtime"
    wrong_runtime.mkpath
    %w[node pi-upstream].each do |name|
      (wrong_runtime/name).write "#!/bin/sh\nexit 42\n"
      (wrong_runtime/name).chmod(0755)
    end
    claude = ["/usr/bin/env", "PATH=#{wrong_runtime}:#{ENV.fetch("PATH")}", bin/"pi-claude"].map(&:to_s).shelljoin
    assert_equal expected_pi, shell_output("#{claude} --version").strip
    help = shell_output("#{claude} --help")
    assert_equal help, shell_output("#{claude} -h")
    canonical_claude = ["/usr/bin/env", "PATH=#{wrong_runtime}:#{ENV.fetch("PATH")}", bin/"pi", "claude"].map(&:to_s).shelljoin
    assert_equal help, shell_output("#{canonical_claude} --help")
    assert_match "pi claude --help", shell_output("#{bin}/pi --help")
    assert_match "Usage: pi claude", help
    assert_match "~/.pi-claude/agent", help
    assert_match "claude auth login", help
    assert_match "pi claude install npm:pi-claude-bridge@", help
    assert_match "brew upgrade pi-shared", help
    assert_match "Install a package", shell_output("#{claude} install --help")
    assert_match "upgrade the runtime with brew upgrade pi-shared", shell_output("#{claude} update 2>&1", 1)
    assert_match "Claude bridge profile is not configured", shell_output("#{claude} --list-models 2>&1", 1)
    refute_path_exists testpath/".pi-claude"
    (testpath/".pi-claude/agent").mkpath
    (testpath/".pi-claude/agent/settings.json").write "{}\n"
    # A different authenticated provider must not become the fallback.
    assert_match "no matching Claude bridge models",
                 shell_output("OPENAI_API_KEY=fixture #{canonical_claude} -p </dev/null 2>&1", 1)
    assert_match "no matching Claude bridge models", shell_output("#{canonical_claude} --list-models 2>&1", 1)
    refute_path_exists testpath/".zshrc"
  end
end
