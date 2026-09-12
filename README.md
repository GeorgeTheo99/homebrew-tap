# Homebrew tap for pi-shared

**Local, unpublished draft.** The intended repository is
`GeorgeTheo99/homebrew-tap`, whose Homebrew tap name is `GeorgeTheo99/tap`.
The formula is named `pi-shared`, but packages the **pi-setup orchestrator**
and its locked Pi runtime; shared resources remain independently managed
source checkouts. It does not vendor those modules into Homebrew.

## Installation contract

After this tap and a verified stable pi-setup source release are published,
the intended command is:

```sh
brew install GeorgeTheo99/tap/pi-shared
pi-shared setup --help
pi-shared setup --plan --mode later
pi-shared setup
```

**That stable install is not available from this draft.** The formula is
HEAD-only and points to pi-setup's public `main` branch. Until the packaging
changes (`bin/pi-shared` and both `runtime/package*.json` files) are published
there, even the HEAD install will fail with a missing-source diagnostic.
After publication, development installs use:

```sh
brew install --HEAD GeorgeTheo99/tap/pi-shared
```

A maintainer can test an unpublished tap via Homebrew's explicit local Git
transport (`brew tap GeorgeTheo99/tap /absolute/path/to/homebrew-tap`), but
that still fetches the formula's public pi-setup HEAD, not a sibling checkout.
The local tap needs a committed Git revision first. No tap install, repository
publication, or source substitution is performed by this repository's helper.

### What Homebrew does — and does not do

- macOS only. Dependencies: Homebrew Node (Pi requires **>=22.19.0**),
  `python@3.12`, `uv`, and `git`. No Apple Silicon restriction is imposed on
  the core coding agent; optional oMLX has its own hardware requirements.
- Packages pi-setup under `libexec`, running only
  `npm ci --ignore-scripts --no-audit --no-fund` in `libexec/runtime` against
  its committed lockfile (Pi **0.85.1**). npm cache/config stay in the temporary
  build tree. There is no `post_install`, setup invocation, or services block.
- Exposes `pi` as a real symlink into its npm package, preserving Pi SDK
  discovery. Its shebang uses Homebrew Node. `pi-shared` uses Homebrew Python
  and supplies Node/Python/uv/git plus the packaged `pi` on its subprocess PATH.
- Does not configure HOME, edit shell files, request credentials, download
  models, or start launchd services. Homebrew itself still manages its normal
  prefix/cache/dependency state. Running Pi itself can create its own user data.
- **Only explicit `pi-shared setup` provisions the environment.** Review its
  help and plan first: selected module installers may write profiles/shell
  configuration, clone repositories, install dependencies, and start services.
  `pi-shared status` reports local setup evidence, not inference readiness.

If another npm/Homebrew/manual installation already owns `pi`, resolve the
conflict deliberately; do not use `brew link --overwrite` blindly.

## Optional components

- **oMLX is optional** and remains an independent installer/runtime choice.
  This formula neither installs it nor downloads local models. Cloud/direct
  providers do not require oMLX. Follow the module documentation for hardware,
  runtime, authentication, and model provisioning.
- **pi-fallback is an independent prototype**, not an installable formula in
  this tap and not a promised part of setup. No placeholder formula is provided.

## Updates and removal

- `brew update` refreshes tap metadata. Once a stable release exists,
  `brew upgrade GeorgeTheo99/tap/pi-shared` upgrades the packaged orchestrator
  and its pinned runtime. For development HEAD installations use
  `brew upgrade --fetch-HEAD GeorgeTheo99/tap/pi-shared`.
- Use Homebrew, **not `pi update --self` or global npm**, to update this packaged
  Pi. Maintain its version and lockfile together upstream in pi-setup; update
  the formula's version smoke assertion when intentionally changing Pi.
- Brew upgrades do **not** update setup-managed module checkouts or rerun their
  installers. Use the explicit setup workflow or module-specific operator tools.
  Avoid editing Homebrew's versioned `libexec` files.
- `brew uninstall GeorgeTheo99/tap/pi-shared` removes the packaged CLI/runtime,
  not `~/.pi`, shell configuration, cloned repositories, credentials, models,
  or external installer-managed services. It does **not stop** those services.
  Inspect each module's uninstall/stop instructions separately before removal;
  do not delete HOME directories wholesale. `brew untap GeorgeTheo99/tap`
  removes tap metadata only.

## Pinning a real stable release

First publish and independently review an immutable pi-setup release archive
containing the CLI, runtime manifest/lockfile, installer, and orchestration
sources. Pin module revisions upstream as appropriate. Then run the local
helper with that release's actual version and URL (no example URL is claimed
to exist):

```sh
python3 scripts/pin-release.py "$VERSION" "$HTTPS_TARBALL_URL" --sha256 "$EXPECTED_SHA256"
```

`--sha256` is optional when first computing a digest, but an independently
obtained checksum is preferred. The helper requires Python >=3.11 and macOS
curl, permits credential-free HTTPS URLs/redirects only, caps downloads at
25 MiB / 90 seconds / 5 MiB per second, checks gzip magic, hashes the fetched
bytes, optionally verifies the expected SHA-256, and atomically edits only the
marked stable stanza. It never extracts/executes the archive or publishes,
commits, pushes, creates tags, or installs anything. Network responses are
untrusted; a matching checksum is **not** proof of provenance, archive contents,
compatibility, or install readiness. Independently inspect and test the release.
Failed downloads/checks leave the formula unchanged. The `head` stanza remains
available after a stable stanza is added.

Before publishing, review the formula diff, run these offline checks, then
perform an explicitly authorized isolated Homebrew install/test against the
real release (not performed for this draft):

```sh
ruby -c Formula/pi-shared.rb
python3 -B -m unittest discover -s tests -v
# Release gate, after authorizing installation and making the tap available:
brew install --build-from-source GeorgeTheo99/tap/pi-shared
brew test GeorgeTheo99/tap/pi-shared
```

The offline tests validate helper safety with stubbed downloads; Ruby checks
formula syntax. Neither substitutes for a real Homebrew build or setup smoke test.
`.github/workflows/test.yml` stages a disposable local tap on a macOS runner,
installs the stable formula (or HEAD while staged), and runs `brew test`. It does
not run setup or start services. This workflow has not run while the tap remains
unpublished, and needs the packaging-ready pi-setup source published first.
Do not advertise stable availability until the source release and tap are
actually published and those release-gate checks pass.
