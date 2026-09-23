# Homebrew tap for pi-shared

[![Homebrew package](https://github.com/GeorgeTheo99/homebrew-tap/actions/workflows/test.yml/badge.svg)](https://github.com/GeorgeTheo99/homebrew-tap/actions/workflows/test.yml)

Install a Pi coding-agent environment with explicit, modular setup. The public
package/command is **pi-shared**; start with the
[main project README](https://github.com/GeorgeTheo99/pi-shared).
Installation orchestration lives in
[pi-setup](https://github.com/GeorgeTheo99/pi-setup). Shared resources and services
remain independent repositories, not vendored copies in Homebrew.

## Install

Review [the formula](Formula/pi-shared.rb) and its source before granting trust.
The first command persistently trusts only this formula, including future
revisions—not the entire tap. On older Homebrew versions without `brew trust`,
omit that first command.

```sh
brew trust --formula georgetheo99/tap/pi-shared
brew install georgetheo99/tap/pi-shared
pi-shared setup
pi
```

### Homebrew trust errors

If Homebrew refuses to load `georgetheo99/tap/pi-shared` from an **untrusted
tap**, review [the formula](Formula/pi-shared.rb) and its source before granting
trust. If you trust this package, run:

```sh
brew trust --formula georgetheo99/tap/pi-shared
brew install georgetheo99/tap/pi-shared
pi-shared setup
```

The explicit `--formula` command works even before the tap is installed, so run
it first if `brew tap` failed. It persistently trusts this formula, including
future revisions, without trusting every formula, cask, and command in the tap.
No separate `brew tap` or global trust bypass is needed.

On Homebrew 6.0.22, repeated trust rejections during tap validation can end with
`Cannot tap georgetheo99/tap: invalid syntax in tap!`. When preceded by those
trust errors, that final message does not establish a Ruby syntax defect. If
installation still fails after granting trust, inspect the new error rather
than broadening trust.

### Optional npm mirror

On networks that require an approved npm mirror, set the generic
`HOMEBREW_NPM_REGISTRY` override before installing or upgrading. Use a
credential-free HTTPS registry URL (no userinfo, query, or fragment):

```sh
HOMEBREW_NPM_REGISTRY=https://npm-mirror.example.com/ brew install georgetheo99/tap/pi-shared
```

Homebrew 7 filters ordinary `npm_config_registry` variables. This explicit
Homebrew-prefixed setting is forwarded to npm without reading user npmrc files;
the committed lockfile and integrity verification remain unchanged. Persist it
in your own Homebrew environment configuration when required for future upgrades.
Without the setting, npm's public registry remains the default. No organization
or private overlay is assumed by this formula.

### Preview setup

Preview without changing anything:

```sh
pi-shared setup --help
pi-shared setup --mode cloud --plan
pi-shared status
```

The formula pins pi-setup **v0.1.10** and its source SHA-256, with a locked Pi
**0.87.1** runtime. Check the package CI above before relying on a new release.
Development installs can use `brew install --HEAD GeorgeTheo99/tap/pi-shared`.

## What gets installed

- macOS prerequisites: Homebrew Node (Pi requires >=22.19.0), `python@3.12`,
  `uv`, and Git. The core package does not require Apple Silicon.
- The Pi CLI and setup orchestrator under Homebrew `libexec`. npm uses the
  committed lockfile with lifecycle scripts disabled; its cache/config stay in
  the disposable build directory. `pi` is a thin dispatcher; `pi-upstream` is
  the stock-runtime symlink used for recovery and SDK discovery.
- **Nothing is provisioned automatically:** no Pi profile or shell changes,
  credential prompts, service registration, or LLM downloads during
  `brew install`. Homebrew still manages its normal prefix/cache/dependencies.

Only explicit `pi-shared setup` clones selected modules, installs their locked
dependencies, wires profiles and CLI configuration, starts their services, and runs
module checks. It shows a plan and asks before applying it. EOF/Ctrl-C cancels;
completed work is not rolled back. Cloud credentials remain yours to configure.

| Setup mode | Modules |
|---|---|
| Direct | Shared resources and browser-worker; native subscriptions/API keys, no gateway/oMLX |
| Cloud | Shared resources, model-gateway, browser-worker |
| Local | Same modules, plus explicit oMLX choices |
| Both | Cloud and local choices |
| Later | Shared resources and browser-worker; configure models later |
| Existing gateway | Shared resources and browser-worker; direct remote server access, no local gateway/oMLX |

For native Pi subscriptions/API keys without model-gateway, choose **Direct** or
run `pi-shared setup --mode direct`. Authentication and model selection remain in
Pi (`/login`, `/model`); `pi openai` is the existing Codex subscription shortcut,
not API-key billing. Existing gateway selections are not migrated automatically.
See [direct providers](https://github.com/GeorgeTheo99/pi-shared/blob/main/docs/direct-providers.md).

For an existing server gateway, choose **Existing gateway** during setup or run:

```sh
pi-shared setup --mode existing-gateway \
  --gateway-url https://server.example-tailnet.ts.net \
  --gateway-key-file "$HOME/.config/pi-shared/gateway.key"
```

Use an already-provisioned client key in an owned, non-symlinked `0600` file.
Trusted private/Tailscale HTTP requires a numeric private IP and explicit
`--allow-private-http`. Setup reads the authenticated catalog but does not modify
or manage the server; updates/status check the saved connection offline. See
[remote gateway setup](https://github.com/GeorgeTheo99/pi-shared/blob/main/docs/existing-gateway.md).

Omnigent compatibility is opt-in, not a dependency of normal setup:

```sh
pi-shared setup --mode cloud --with-omnigent --plan
pi-shared setup --mode cloud --with-omnigent
pi-shared status --require-omnigent
```

This adds native-Pi prerequisite/package checks only. It does not install
Omnigent, launch sessions, or verify inference; see the
[compatibility contract](https://github.com/GeorgeTheo99/pi-setup/blob/main/docs/omnigent-compatibility.md).

`--without-browser` omits browser-worker and Chromium; `--with-search` adds the
search broker after its Brave key is provisioned. Optional private-app browser
binaries and PowerPoint preview tools are separate prerequisites.

After setup, use `pi models`, `pi openai`, or `pi <model-alias>`.
Package **0.1.9+** and the updated shared module display grouped model aliases;
`pi models --local|--cloud|--direct` filters groups, `--verbose` shows routes,
and `--json` emits structured data. `pi --launcher-list` retains legacy TSV.
Older shared modules keep list/help translation; new options require
`pi-shared update`. Unconfigured `pi models` never starts a model session.
`pi openai --default` saves the default and exits; bare `pi` starts with your
saved choice. `pi --launcher-refresh` refreshes local routing metadata. No
placeholder model catalog or generated shell functions are needed. Setup/update
migrates recognized legacy launcher wiring with a private backup, preserving
unrelated shell content. Existing shells need one restart to drop old functions.
Normal Pi commands remain available, including `pi list` for packages; use
`pi -- openai` to send the literal prompt rather than select the alias.

If another installation already owns `pi`, reconcile the link conflict
deliberately—never use `brew link --overwrite` blindly.

## Local models and recovery

```sh
pi-shared setup --local
```

Choose existing local oMLX discovery, a **new** Homebrew oMLX installation
(Apple Silicon/macOS 15+), or instructions for later. Setup does not replace an
existing oMLX service manager. Review model download size and memory needs in
oMLX before downloading; **no LLM weights are downloaded by pi-shared**.
Discovery is not inference: local Pi/gateway routing and an actual model smoke
remain explicit. The gateway's HTTPS cloud onboarding generator is not suitable
for local HTTP oMLX URLs.

`pi-fallback` is an independent optional **recovery prototype**. Setup can show
preparation guidance, but this tap does not yet provide a recovery formula or
claim offline readiness. Its independent runtime, compatible weights, and real
model/tool test are required before it can be relied on.

See [full setup documentation](https://github.com/GeorgeTheo99/pi-setup/blob/main/docs/homebrew.md)
for exact flags, service ownership, credentials, readiness boundaries and tests.

## Update or uninstall

**Routine updates: `pi-shared update`, or bare `pi update` with package 0.1.11+.**
Both use the owning package's updater for the runtime and saved modules.
Explicit `pi update` arguments retain stock behavior: for example,
`pi update --extensions` updates Pi packages only. Use `pi-shared update --plan`
for a managed preview. The saved component selection is reused,
so there is no repeated questionnaire. The command upgrades its owning Homebrew
package, re-executes the updated CLI, applies changed selected components,
synchronizes shared dependencies, refreshes shortcuts and verifies everything.
Unchanged services are not restarted; prerequisite changes or repair retries may
reapply selected services. `pi-shared update --plan` is read-only.
The runtime follows the published formula pin, not npm's latest release.
Restart running Pi sessions after a runtime upgrade; `/reload` is not sufficient.

Alias launches refresh changed local routing data without software upgrades,
service restarts or model/provider calls. Manual model edits are protected rather
than overwritten; no shell prompt hook is installed. Older receipts require one setup
run with original custom overrides to capture missing update settings. See
[the update contract](https://github.com/GeorgeTheo99/pi-setup/blob/main/docs/updates.md).

The lower-level operations remain available:

- `brew upgrade GeorgeTheo99/tap/pi-shared` updates the packaged orchestrator
  and pinned Pi runtime. Bare `pi update` delegates to the managed updater in
  package 0.1.11+; explicit stock self-update flags and global npm do not manage
  this runtime. For HEAD installs: `brew upgrade --fetch-HEAD GeorgeTheo99/tap/pi-shared`.
- `pi-shared setup --mode ... --update` explicitly updates/reinstalls selected
  writable modules. Include optional selections again. Homebrew upgrades do not
  run these installers or restart their services.
- `brew uninstall GeorgeTheo99/tap/pi-shared` removes the packaged CLI/runtime,
  **not** your modules, profiles, sessions, credentials, models or services.
  Manage/stop services with their own documented operators before removing
  prerequisites; do not delete HOME directories wholesale. `brew untap
  GeorgeTheo99/tap` removes tap metadata only.
- There is no `brew services start pi-shared`: gateway/browser/search keep
  their own service managers. Opt-in oMLX uses its upstream Homebrew service.

## Maintainers

Publish an approved immutable pi-setup archive, inspect its contents, and pin it:

```sh
python3 scripts/pin-release.py "$VERSION" "$HTTPS_TARBALL_URL" --sha256 "$EXPECTED_SHA256"
ruby -c Formula/pi-shared.rb
python3 -B -m unittest discover -s tests -v
```

The helper requires Python >=3.11 and macOS curl. It rejects URL credentials,
queries, and fragments; permits HTTPS redirects only; caps downloads at 25 MiB,
90 seconds and 5 MiB/s; checks gzip magic; optionally verifies an independently
obtained checksum; and atomically edits only the stable formula stanza. It never
extracts, executes, installs or publishes. A checksum is not provenance or
compatibility proof: inspect the actual source and test it independently.

The macOS workflow installs this exact committed tap checkout, chooses stable
or HEAD according to its formula, and runs `brew test`. It exercises native
direct-only setup with a custom saved profile and unchanged native auth/models,
then verifies rerun/update/status without gateway services. It also exercises direct
remote setup against an authenticated fake loopback gateway in disposable HOME,
then stops that server and verifies offline update/status. No real provider is
contacted. It also explicitly runs Cloud-mode setup and status in another
disposable HOME on the ephemeral CI runner,
checking the recommended gateway/browser services without provider/model calls.
It also verifies the saved update flow, unchanged-service PIDs, and the owning
Homebrew re-exec path.
It does not touch your machine's services or select oMLX/search/recovery.
Offline helper tests and Ruby syntax checks do not replace that installation
and setup gate. pi-setup's isolated minimal smoke separately tests real extension
dependencies and SDK profile loading. Module refs still include
`main`; full-stack immutable dependency pinning and bottles are not claimed.

License: Apache-2.0.
