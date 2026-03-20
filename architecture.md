# Gemini CLI Architecture Map (for gemini-cli-alpine maintainers)

Last updated: 2026-03-20
Target upstream: `gemini-cli` v0.34.x layout

## Purpose
This file is a fast orientation map for debugging and patching Gemini CLI behavior on Alpine.
Use it to avoid re-discovering where stream/tool/PTY failures are handled.

## Repo Split (upstream)
- `packages/cli`: process entrypoint, TUI/headless UX, session/UI orchestration.
- `packages/core`: model streaming, turn execution, tool calls (shell/MCP/etc), retry/error handling.

## High-Level Runtime Flow
1. `packages/cli/index.ts`
- Node entrypoint.
- Alpine relaunch guard (`GEMINI_CLI_NO_RELAUNCH`) is set here.
- Calls `main()` and includes top-level interactive auto-retry-on-unexpected-error logic.

2. `packages/cli/src/gemini.tsx`
- Central CLI mode/router:
- interactive TUI
- prompt-interactive
- non-interactive (`-p`)
- command handling (`mcp`, `extensions`, etc.).

3. `packages/cli/src/interactiveCli.tsx`
- Interactive boot path and app startup wiring.

4. `packages/cli/src/ui/AppContainer.tsx`
- Main TUI state container.
- Uses hooks for slash commands + streaming.

5. `packages/cli/src/ui/hooks/useGeminiStream.ts`
- Sends user turns to core client stream and renders tool/model events.
- Key place where "looks hung/stuck in UI" issues surface.

6. `packages/core/src/core/client.ts`
- `GeminiClient` orchestration around turn processing and `sendMessageStream`.
- Handles recoverable stream conditions and fallbacks.

7. `packages/core/src/core/turn.ts`
- Turn state machine: model stream events + tool call events + error mapping.
- Handles `InvalidStreamError` paths and emits structured error events.

8. `packages/core/src/core/geminiChat.ts`
- Direct interaction with GenAI stream.
- Detects malformed stream conditions (`InvalidStreamError` reasons).
- Wraps calls with retry/backoff behavior.

9. `packages/core/src/services/shellExecutionService.ts`
- Shell tool execution implementation.
- PTY path + fallback subprocess path + abort/cleanup.

10. `packages/core/src/utils/getPty.ts`
- Runtime loading of PTY implementation and platform behavior gates.

## Error/Crash Taxonomy (practical)
- Non-fatal API/tool errors:
- Often stay in-session and render as UI/API errors (no process exit).
- Process exits (`rc != 0`):
- Can happen in CLI/main catch, uncaught exception path, or hard runtime failures.
- Interactive auto-retry:
- Upstream currently retries once in `packages/cli/index.ts` when non-fatal unexpected interactive failure is caught.
- Malformed stream:
- Normally handled in `core` as recoverable (`InvalidStreamError`) before becoming fatal.

## Alpine Patch Layer (this repo)
- Scripted patch/reinstall entry:
- `scripts/reapply-alpine-patches.sh`
- Diagnostics wrapper installer:
- `scripts/install-gemini-diagnostics.sh`
- Installed wrapper target (user install):
- `~/.local/bin/gemini`

Wrapper responsibilities:
- Preserve TTY for interactive runs.
- Capture per-run diagnostics log under `~/.gemini/diagnostics/runs/`.
- Show on-screen crash notice for unexpected exits.
- Track noninteractive failures.
- Copy fresh `/tmp/gemini-client-error-*.json` into per-run `.artifacts/` on failure.

## Current Known Good Diagnostics Workflow
1. Reinstall wrapper after edits:
- `./scripts/install-gemini-diagnostics.sh ~/.local`

2. Reproduce issue live (avoid `--resume` when diagnosing fresh crash behavior).

3. Inspect latest failing run first:
- `gemini-diag-last`

4. Check copied artifacts:
- `~/.gemini/diagnostics/runs/<run-id>.artifacts/`

5. If needed, inspect upstream session JSON:
- `~/.gemini/tmp/<project>/chats/session-*.json`

## Fast “Where to Patch” Guide
- Crash restarts / retry confusion:
- `packages/cli/index.ts` + wrapper crash notices.
- UI says "thinking" but no visible failure:
- `useGeminiStream.ts` + `turn.ts` emitted events.
- Tool-call crash on shell:
- `shellExecutionService.ts` + `getPty.ts`.
- Malformed function call / stream anomalies:
- `geminiChat.ts`, `turn.ts`, `client.ts`.
- Headless (`-p`) odd exits:
- `packages/cli/src/nonInteractiveCli.ts`.

## Minimal Repro Patterns
- Force API error + `/tmp` report:
- `gemini -m definitely-not-a-real-model -p 'hi' --output-format text`
- Force argument/CLI error path:
- `gemini --badflag`
- Nextcloud-related shell-tool repro (interactive):
- `gemini --approval-mode yolo -m gemini-3-pro-preview -i 'Run shell: ls -F ~/Nextcloud/ "Memory.txt" "Mira test.txt" 2>/dev/null || ls -F ~/Nextcloud/'`

## Open Gaps (still worth doing)
- Deterministic repro harness for interactive `rc=1` runtime failures.
- One-command diagnostics bundle generator for upstream issues:
- run log + copied `/tmp` report + `/about` + `/stats`.
- Optional toggle to disable upstream interactive auto-retry for cleaner crash visibility during debug sessions.
