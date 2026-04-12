# gemini-cli-alpine

Alpine Linux companion repo for running Google Gemini CLI reliably on BusyBox + musl.

This is not a replacement for the upstream fork. It is the operational layer:

- install Gemini CLI in a user-owned location
- reapply Alpine compatibility patches after reinstalls
- document Alpine-specific failure modes and workarounds

Upstreamable source changes live in:

- `https://github.com/mekineer-com/gemini-cli`

Current scope:

- BusyBox-safe entrypoint
- fast `--version`
- Alpine PTY preference
- noninteractive shell PTY fix
- auth-startup fix
- faster Alpine startup path
- noninteractive JSON error-output fix
- BusyBox-safe terminal parent detection for `/terminal-setup`
- no automatic model demotion (fallback disabled by patch default)

## Quick Start

User-local install:

```sh
./scripts/install-user-local.sh
```

Install a specific version (default is `0.34.0`):

```sh
GEMINI_CLI_VERSION=0.34.0 ./scripts/install-user-local.sh
```

Reapply patches after reinstall:

```sh
./scripts/reapply-alpine-patches.sh [PREFIX]
```

Patch mode is selected automatically by installed package layout:
- legacy `dist/` layout (0.35.x and earlier): full Alpine patch set
- bundled `bundle/` layout (0.36+): Alpine compatibility subset for the bundled build

Reapply patches and also install diagnostics wrapper/helper:

```sh
./scripts/reapply-alpine-patches.sh [PREFIX] --with-diagnostics
```

Install diagnostics only (no patch reapply):

```sh
./scripts/install-gemini-diagnostics.sh [PREFIX]
```

Read latest diagnostics quickly:

```sh
gemini-diag-last
```

Create a reproducible diagnostics bundle (latest failing run + artifacts):

```sh
gemini-diag-bundle
```

Run a deterministic reliability smoke pass (headless + PTY failure checks):

```sh
./scripts/gemini-reliability-smoke.sh
```

Smoke history is appended to:

```sh
~/.gemini/diagnostics/smoke/history.tsv
```

Debug mode to suppress relaunch/retry-style behavior during repro sessions:

```sh
GEMINI_DEBUG_DISABLE_RETRY=1 gemini
```

Force old parent/child relaunch behavior for debugging:

```sh
GEMINI_CLI_FORCE_RELAUNCH=true gemini
```

## Why this repo exists

The upstream Gemini CLI repo is large and active, but Alpine-specific fixes are unlikely to get fast attention. This repo gives Alpine users something immediately usable while the source fork stays PR-ready.

Patch groups and rollback guidance:

- see [`PATCH_INVENTORY.md`](PATCH_INVENTORY.md)

## Current practical model guidance

- default behavior: no automatic fallback/demotion
- if `gemini-3.x` capacity is exhausted, the turn fails explicitly instead of silently switching models

## Architecture Map

- quick internal map for upstream `gemini-cli` flow and Alpine patch/debug entry points:
  - see [`architecture.md`](architecture.md)

## License

- Repository license:
  - GPL-3.0-only
- Upstream roots acknowledged:
  - the operational patching here is derived from Apache-licensed Gemini CLI work
  - see `NOTICE`
  - see `licenses/Apache-2.0.txt`
