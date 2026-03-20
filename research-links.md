# Gemini CLI Research Links (Bug Fixing + memU Usage)

This file tracks high-value sources for understanding Gemini internals failures and optimizing usage for memU workflows.

## Recommended Goal

Reliable long-running Gemini sessions for memU tasks, with reproducible failure capture and predictable token/runtime behavior in both interactive and headless modes.

## Official Docs (Primary)

- Troubleshooting guide: https://google-gemini.github.io/gemini-cli/docs/troubleshooting.html
  - Why useful: Defines exit codes (41/42/44/52/53), CI/non-interactive detection caveats, and baseline debug workflow.
  - Use in practice: Map wrapper crash codes directly to root-cause classes before patching behavior.

- Telemetry (OpenTelemetry): https://google-gemini.github.io/gemini-cli/docs/cli/telemetry.html
  - Why useful: Official instrumentation surface for logs/metrics/traces.
  - Use in practice: For hard-to-repro failures, enable local telemetry output for correlation with wrapper run logs.

- Headless mode: https://google-gemini.github.io/gemini-cli/docs/cli/headless.html
  - Why useful: Stable automation interface (`-p`, structured JSON output, consistent scripting semantics).
  - Use in practice: Use headless mode for deterministic memU diagnostics pipelines and regression checks.

- CLI commands: https://google-gemini.github.io/gemini-cli/docs/cli/commands.html
  - Why useful: `/bug`, `/about`, `/stats`, `/memory`, `/settings` are official diagnostics and reproducibility helpers.
  - Use in practice: Include `/about` metadata and `/stats` snapshot in every upstream bug report.

- Token caching + cost optimization: https://google-gemini.github.io/gemini-cli/docs/cli/token-caching.html
  - Why useful: Caching works with API-key auth, not OAuth.
  - Use in practice: For repeated large memU planning/diagnostics runs, API key auth is better for token efficiency.

- GEMINI.md context behavior: https://google-gemini.github.io/gemini-cli/docs/cli/gemini-md.html
  - Why useful: Explains hierarchical context loading and how context bloat is introduced.
  - Use in practice: Keep project context tight to reduce malformed/empty-response risk under large workloads.

- Trusted folders: https://google-gemini.github.io/gemini-cli/docs/cli/trusted-folders.html
  - Why useful: Untrusted mode ignores local `.gemini/settings.json` and `.env`, which can look like random breakage.
  - Use in practice: Verify trust state first when behavior appears inconsistent across folders.

- Architecture overview: https://google-gemini.github.io/gemini-cli/docs/architecture.html
  - Why useful: Clean split of `packages/cli` (UI) and `packages/core` (agent/tool/api orchestration).
  - Use in practice: Route bug reports/patches to the correct layer quickly.

## Upstream PRs (High Relevance)

- AbortError stream crash fix (#21123): https://github.com/google-gemini/gemini-cli/pull/21123
  - Relevance: Prevents unhandled `AbortError` from killing process during stream-loop detection.

- PTY descendant cleanup on abort (#21124): https://github.com/google-gemini/gemini-cli/pull/21124
  - Relevance: Prevents orphaned subprocesses after PTY abort paths.

- `/clear` + `/resume` cleanup (#22007): https://github.com/google-gemini/gemini-cli/pull/22007
  - Relevance: Session and telemetry consistency improvements after context clearing.

- API key load caching perf fix (#21520): https://github.com/google-gemini/gemini-cli/pull/21520
  - Relevance: Reduces redundant keychain access (startup path improvement).

- Releases feed: https://github.com/google-gemini/gemini-cli/releases
  - Relevance: Track whether local patches can be dropped because upstream merged equivalent fixes.

## Real-World Failure Evidence (Issue Examples)

- Full `/tmp/gemini-client-error-...json` artifact pattern appears in real reports:
  - https://github.com/google-gemini/gemini-cli/issues/12697
  - https://github.com/google-gemini/gemini-cli/issues/12660
  - https://github.com/google-gemini/gemini-cli/issues/7209
  - Why useful: Confirms that preserving/collecting these JSON artifacts is essential for actionable debugging.

## Practical Workflow For memU

1. Keep wrapper in fail-fast diagnostics mode (no silent auto-retries by default).
2. For every crash, capture:
   - wrapper run log path,
   - `/tmp/gemini-client-error-*.json` artifact,
   - `/about` and `/stats` output.
3. Prefer API key auth for heavy repeated runs if token caching value is important.
4. Keep GEMINI.md context lean and scoped to current task area.
5. Use headless JSON mode for reproducible benchmark/regression loops.
