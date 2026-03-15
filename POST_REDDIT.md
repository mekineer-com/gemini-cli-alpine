Title:

Google Gemini CLI on Alpine Linux: BusyBox + musl fixes, faster startup, better fallback

Body:

I’ve been running Google’s official Gemini CLI on Alpine Linux and hit a cluster of issues that made it rough in practice:

- BusyBox-incompatible entrypoint
- slow startup
- PTY problems on Alpine
- noninteractive shell/tool issues
- ugly behavior when `gemini-3-pro-preview` quota is exhausted

I split the work into two repos:

- upstreamable source fork:
  - https://github.com/mekineer-com/gemini-cli
- Alpine companion repo with install + reapply scripts:
  - https://github.com/mekineer-com/gemini-cli-alpine

Current Alpine fixes include:

- BusyBox-safe entrypoint
- fast `--version`
- Alpine PTY preference
- noninteractive shell PTY fix
- auth-startup fix
- faster Alpine startup path
- silent preview fallback:
  - `gemini-3-pro-preview`
  - `gemini-3-flash-preview`
  - `gemini-2.5-flash-lite`

This does not increase Google quota. It just makes the CLI behave better on Alpine.

If anyone else is running Gemini CLI on Alpine, BusyBox, or a small VPS, I’d be interested in comparing notes.
