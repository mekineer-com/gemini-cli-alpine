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
- silent preview-model fallback:
  - `gemini-3-pro-preview`
  - `gemini-2.5-pro`
  - `gemini-3-flash-preview`
  - `gemini-2.5-flash`
  - `gemini-2.5-flash-lite`

## Quick Start

User-local install:

```sh
./scripts/install-user-local.sh
```

Reapply patches after reinstall:

```sh
./scripts/reapply-alpine-patches.sh
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

- default working baseline:
  - `gemini-2.5-flash-lite`
- preview path now degrades automatically if quota/model access fails:
  - `gemini-3-pro-preview -> gemini-2.5-pro -> gemini-3-flash-preview -> gemini-2.5-flash -> gemini-2.5-flash-lite`

This improves reliability, but it does not increase preview quota.

## License

- Repository license:
  - GPL-3.0-only
- Upstream roots acknowledged:
  - the operational patching here is derived from Apache-licensed Gemini CLI work
  - see `NOTICE`
  - see `licenses/Apache-2.0.txt`
