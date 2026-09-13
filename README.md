# Homebrew tap for pi-shared

[![Homebrew package](https://github.com/GeorgeTheo99/homebrew-tap/actions/workflows/test.yml/badge.svg)](https://github.com/GeorgeTheo99/homebrew-tap/actions/workflows/test.yml)

Install a Pi coding-agent environment with explicit, modular setup. The public
package/command is **pi-shared**; installation orchestration lives in
[pi-setup](https://github.com/GeorgeTheo99/pi-setup). Shared resources and services
remain independent repositories, not vendored copies in Homebrew.

## Install

```sh
brew install GeorgeTheo99/tap/pi-shared
pi-shared setup
pi
```

Preview without changing anything:

```sh
pi-shared setup --help
pi-shared setup --mode cloud --plan
pi-shared status
```

The formula pins pi-setup **v0.1.3** and its source SHA-256, with a locked Pi
**0.85.1** runtime. Check the package CI above before relying on a new release.
Development installs can use `brew install --HEAD GeorgeTheo99/tap/pi-shared`.

## What gets installed

- macOS prerequisites: Homebrew Node (Pi requires >=22.19.0), `python@3.12`,
  `uv`, and Git. The core package does not require Apple Silicon.
- The Pi CLI and setup orchestrator under Homebrew `libexec`. npm uses the
  committed lockfile with lifecycle scripts disabled; its cache/config stay in
  the disposable build directory. The `pi` symlink preserves SDK discovery.
- **Nothing is provisioned automatically:** no Pi profile or shell changes,
  credential prompts, service registration, or LLM downloads during
  `brew install`. Homebrew still manages its normal prefix/cache/dependencies.

Only explicit `pi-shared setup` clones selected modules, installs their locked
dependencies, wires profiles and shell commands, starts their services, and runs
module checks. It shows a plan and asks before applying it. EOF/Ctrl-C cancels;
completed work is not rolled back. Cloud credentials remain yours to configure.

| Setup mode | Modules |
|---|---|
| Cloud | Shared resources, model-gateway, browser-worker |
| Local | Same modules, plus explicit oMLX choices |
| Both | Cloud and local choices |
| Later | Shared resources and browser-worker; configure models later |

`--without-browser` omits browser-worker and Chromium; `--with-search` adds the
search broker after its Brave key is provisioned. Optional private-app browser
binaries and PowerPoint preview tools are separate prerequisites.

After setup, open a new shell and run `pi-list`. Fresh setups provide
`pi-list`, `pi-regen`, `pi-shared-update`, `pi-restart`, `pi-default`, and
`pi-openai` before model configuration. No placeholder model catalog is created.
Once the gateway alias export is configured, `pi-regen` generates and reloads
model shortcuts. Existing launcher preferences and configured legacy launchers
are preserved. Older package installations need a brew upgrade and an explicit
setup rerun to enable bootstrap.

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

**Routine updates: `pi-shared update`.** The saved component selection is reused,
so there is no repeated questionnaire. The command upgrades its owning Homebrew
package, re-executes the updated CLI, applies changed selected components,
synchronizes shared dependencies, refreshes shortcuts and verifies everything.
Unchanged services are not restarted; prerequisite changes or repair retries may
reapply selected services. `pi-shared update --plan` is read-only.

Interactive prompts refresh changed local catalog/launcher data automatically,
without software upgrades, service restarts or model/provider calls. Manual model
edits are protected rather than overwritten. Older receipts require one setup
run with original custom overrides to capture missing update settings. See
[the update contract](https://github.com/GeorgeTheo99/pi-setup/blob/main/docs/updates.md).

The lower-level operations remain available:

- `brew upgrade GeorgeTheo99/tap/pi-shared` updates the packaged orchestrator
  and pinned Pi runtime. Use Homebrew, not `pi update` or global npm, for this
  runtime. For HEAD installs: `brew upgrade --fetch-HEAD GeorgeTheo99/tap/pi-shared`.
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
or HEAD according to its formula, and runs `brew test`. It then explicitly runs
Cloud-mode setup and status in a disposable HOME on the ephemeral CI runner,
checking the recommended gateway/browser services without provider/model calls.
It also verifies the saved update flow, unchanged-service PIDs, and the owning
Homebrew re-exec path.
It does not touch your machine's services or select oMLX/search/recovery.
Offline helper tests and Ruby syntax checks do not replace that installation
and setup gate. pi-setup's isolated minimal smoke separately tests real extension
dependencies and SDK profile loading. Module refs still include
`main`; full-stack immutable dependency pinning and bottles are not claimed.

License: Apache-2.0.
