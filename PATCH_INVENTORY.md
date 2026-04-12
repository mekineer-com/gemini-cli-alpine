# Patch Inventory

This file groups the Alpine patch set by impact so users can decide how close
to stock behavior they want.

Patch coverage is version-range aware:
- 0.35.x and earlier (`dist/` layout): full patch set below.
- 0.36+ (`bundle/` layout): bundled compatibility subset (entrypoint, relaunch guard, shell pgrep fix, terminal parent detection, PTY preference order).

## Required

These are required for correct/usable behavior on Alpine + BusyBox.

1. BusyBox-safe entrypoint (`env -S` removal) and fast `--version`
- Why: BusyBox `env` does not support `-S`, which breaks startup.
- Effect: Gemini CLI starts normally on Alpine and `--version` returns quickly.

2. Alpine PTY preference (`node-pty` first) and shell process-group fix
- Why: default PTY path is less reliable on Alpine; `pgrep -g 0` behavior is not portable.
- Effect: interactive shell/tool sessions are more stable on Alpine.

3. BusyBox-safe terminal parent detection (`/terminal-setup` path)
- Why: BusyBox `ps` does not support `-p`, so parent-process detection can fail/noise in debug flows.
- Effect: Linux uses `/proc/<ppid>/comm` for detection; avoids BusyBox `ps -p` errors.

## Recommended

These preserve functionality while improving reliability under real workloads.

1. Invalid/malformed stream recovery hardening
- What: stronger retry prompt, higher retry cap, retry on Gemini 3 path, fallback after retry exhaustion.
- Effect: fewer crash-like empty turns when model output is malformed.

2. Malformed tool-call guard (`orphan functionCall` protection)
- What: only accept parsed `response.functionCalls` as a valid tool-call turn.
- Effect: malformed tool-call parts no longer bypass recovery logic.

3. Oversized tool-output truncation before model replay
- What: truncate large string outputs for any tool (not just shell).
- Effect: avoids context blowups from huge grep/tool output payloads.

4. Startup/auth flow hardening
- What: avoid heavy extension/memory loading in pre-auth path; preserve auth state on startup.
- Effect: less startup friction and fewer auth/startup dead ends on Alpine.

5. Noninteractive error-output ordering fix
- What: handle noninteractive errors before unsubscribing `UserFeedback` listeners.
- Effect: avoids silent `exit 1` in JSON/headless flows when a turn fails mid-stream.

## Optional

These are behavior choices, not compatibility fixes.

1. Fallback model order policy
- Current order: `gemini-3-pro-preview -> gemini-2.5-pro -> gemini-3-flash-preview -> gemini-2.5-flash -> gemini-2.5-flash-lite`
- Effect: controls preference between capability and resilience during fallback.
- Can be changed without affecting Alpine compatibility.

2. Diagnostics wrapper/tooling
- What: launcher wrapper with per-run logs + optional Node crash-report flags, and `gemini-diag-last`.
- How to enable: `./scripts/reapply-alpine-patches.sh [PREFIX] --with-diagnostics`
- How to install only diagnostics: `./scripts/install-gemini-diagnostics.sh [PREFIX]`
- Effect: easier postmortem debugging without changing core Alpine compatibility patches.

## Stock-Like Profile

If you want to stay close to stock while remaining Alpine-safe:
- Keep all `Required` patches.
- Keep `Recommended` patches unless you are actively debugging upstream behavior.
- Tune only `Optional` fallback order.
