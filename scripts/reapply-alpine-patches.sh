#!/bin/sh
set -eu

PREFIX="$HOME/.local"
PREFIX_SET=0
INSTALL_DIAGNOSTICS=0

for arg in "$@"; do
  case "$arg" in
    --with-diagnostics)
      INSTALL_DIAGNOSTICS=1
      ;;
    --without-diagnostics)
      INSTALL_DIAGNOSTICS=0
      ;;
    -h|--help)
      echo "Usage: $0 [PREFIX] [--with-diagnostics|--without-diagnostics]"
      echo "Default: apply Alpine patches only (diagnostics not installed)."
      exit 0
      ;;
    *)
      if [ "$PREFIX_SET" -eq 1 ]; then
        echo "unexpected extra argument: $arg" >&2
        exit 2
      fi
      PREFIX="$arg"
      PREFIX_SET=1
      ;;
  esac
done

ROOT="$PREFIX/lib/node_modules/@google/gemini-cli"
PACKAGE_JSON="$ROOT/package.json"
INDEX="$ROOT/dist/index.js"
CORE="$ROOT/node_modules/@google/gemini-cli-core/dist"
CLI_DIST="$ROOT/dist/src"
CLI_CONFIG_JS="$CLI_DIST/config/config.js"
CLI_GEMINI_JS="$CLI_DIST/gemini.js"
CLI_NONINTERACTIVE_JS="$CLI_DIST/nonInteractiveCli.js"
USE_QUOTA_FALLBACK_JS="$CLI_DIST/ui/hooks/useQuotaAndFallback.js"
SHELL_JS="$CORE/src/tools/shell.js"
GETPTY_JS="$CORE/src/utils/getPty.js"
POLICYCATALOG_JS="$CORE/src/availability/policyCatalog.js"
HANDLER_JS="$CORE/src/fallback/handler.js"
GEMINICHAT_JS="$CORE/src/core/geminiChat.js"
CLIENT_JS="$CORE/src/core/client.js"
TOOLEXECUTOR_JS="$CORE/src/scheduler/tool-executor.js"
CORE_CONFIG_JS="$CORE/src/config/config.js"
AUTH_JS="$CLI_DIST/core/auth.js"
INITIALIZER_JS="$CLI_DIST/core/initializer.js"
USEAUTH_JS="$CLI_DIST/ui/auth/useAuth.js"
APPCONTAINER_JS="$CLI_DIST/ui/AppContainer.js"
GOOGLE_QUOTA_ERRORS_JS="$CORE/src/utils/googleQuotaErrors.js"
SESSION_BROWSER_JS="$CLI_DIST/ui/components/SessionBrowser.js"
USE_SESSION_BROWSER_JS="$CLI_DIST/ui/hooks/useSessionBrowser.js"
TERMINAL_SETUP_JS="$CLI_DIST/ui/utils/terminalSetup.js"
BUNDLE_DIR="$ROOT/bundle"
BUNDLE_GEMINI="$BUNDLE_DIR/gemini.js"

[ -f "$PACKAGE_JSON" ] || { echo "missing $PACKAGE_JSON" >&2; exit 1; }

VERSION="$(python3 - "$PACKAGE_JSON" <<'PY'
import json
import sys
from pathlib import Path
pkg = json.loads(Path(sys.argv[1]).read_text())
print(pkg.get("version", "unknown"))
PY
)"
echo "detected gemini-cli version: $VERSION"

if [ ! -f "$INDEX" ] && [ -f "$BUNDLE_GEMINI" ]; then
  echo "patch mode: bundled layout (0.36+)"
  python3 - "$BUNDLE_GEMINI" "$BUNDLE_DIR" <<'PY'
from pathlib import Path
import re
import sys

entry = Path(sys.argv[1])
bundle_dir = Path(sys.argv[2])

def replace_once_or_skip(text, old, new):
    if new in text:
        return text
    if old in text:
        return text.replace(old, new, 1)
    return text

text = entry.read_text()
if text.startswith('#!/usr/bin/env -S node --no-warnings=DEP0040'):
    text = text.replace('#!/usr/bin/env -S node --no-warnings=DEP0040', '#!/usr/bin/node --no-warnings=DEP0040', 1)
elif text.startswith('#!/usr/bin/env node'):
    text = text.replace('#!/usr/bin/env node', '#!/usr/bin/node --no-warnings=DEP0040', 1)

if "GEMINI_CLI_FORCE_RELAUNCH" not in text:
    marker = "const require = (await import('node:module')).createRequire(import.meta.url); const __chunk_filename = (await import('node:url')).fileURLToPath(import.meta.url); const __chunk_dirname = (await import('node:path')).dirname(__chunk_filename);\n"
    injection = marker + "const existsSync = (await import('node:fs')).existsSync;\nif (process.platform === \"linux\" && existsSync(\"/etc/alpine-release\") && !process.env[\"GEMINI_CLI_NO_RELAUNCH\"] && !process.env[\"GEMINI_CLI_FORCE_RELAUNCH\"]) {\n  process.env[\"GEMINI_CLI_NO_RELAUNCH\"] = \"true\";\n}\n"
    if marker not in text:
        raise RuntimeError("critical patch missing marker: bundle_entry_header")
    text = text.replace(marker, injection, 1)

entry.write_text(text)

js_files = sorted(bundle_dir.glob("*.js"))
if not js_files:
    raise RuntimeError("critical patch missing marker: bundle_js_files")

parent_detect_hits = 0
pgrep_hits = 0
terminal_meta_hits = 0
getpty_hits = 0

for file_path in js_files:
    src = file_path.read_text()
    out = src

    if "pgrep -g 0" in out:
        c = out.count("pgrep -g 0")
        pgrep_hits += c
        out = out.replace("pgrep -g 0", "pgrep -P $$")

    old_parent_cmd = 'execAsync("ps -o comm= -p $PPID")'
    new_parent_cmd = 'execAsync("sh -c \'if [ -r /proc/$PPID/comm ]; then cat /proc/$PPID/comm; else ps -o comm= -p $PPID; fi\'")'
    if old_parent_cmd in out:
        c = out.count(old_parent_cmd)
        parent_detect_hits += c
        out = out.replace(old_parent_cmd, new_parent_cmd)

    if "return TERMINAL_DATA[terminal] || null;" in out:
        c = out.count("return TERMINAL_DATA[terminal] || null;")
        terminal_meta_hits += c
        out = out.replace("return TERMINAL_DATA[terminal] || null;", "return TERMINAL_DATA[terminal];")

    first_pat = re.compile(
        r'const lydell = "@lydell/node-pty";\n    const (\w+) = await import\(lydell\);\n    return \{ module: \1, name: "lydell-node-pty" \};'
    )
    if first_pat.search(out):
        getpty_hits += 1
        out = first_pat.sub(
            'const firstChoice = process.platform === "linux" ? "node-pty" : "@lydell/node-pty";\n    const firstName = process.platform === "linux" ? "node-pty" : "lydell-node-pty";\n    const \\1 = await import(firstChoice);\n    return { module: \\1, name: firstName };',
            out,
        )

    second_pat = re.compile(
        r'const nodePty = "node-pty";\n      const (\w+) = await import\(nodePty\);\n      return \{ module: \1, name: "node-pty" \};'
    )
    if second_pat.search(out):
        out = second_pat.sub(
            'const secondChoice = process.platform === "linux" ? "@lydell/node-pty" : "node-pty";\n      const secondName = process.platform === "linux" ? "lydell-node-pty" : "node-pty";\n      const \\1 = await import(secondChoice);\n      return { module: \\1, name: secondName };',
            out,
        )

    if out != src:
        file_path.write_text(out)

if parent_detect_hits == 0:
    raise RuntimeError("critical patch verification failed: bundle_terminal_parent_detect")
if pgrep_hits == 0:
    raise RuntimeError("critical patch verification failed: bundle_shell_pgrep_fix")

print(
    f"bundle_patch_stats parent_detect={parent_detect_hits} pgrep={pgrep_hits} terminal_meta={terminal_meta_hits} getpty={getpty_hits}"
)
PY

  SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
  if [ "$INSTALL_DIAGNOSTICS" -eq 1 ]; then
    "$SCRIPT_DIR/install-gemini-diagnostics.sh" "$PREFIX"
  else
    echo "diagnostics not installed (use --with-diagnostics to enable)"
  fi

  echo "patched $ROOT"
  exit 0
fi

echo "patch mode: legacy dist layout (0.35.x and earlier)"
[ -f "$INDEX" ] || { echo "missing $INDEX" >&2; exit 1; }
[ -f "$SHELL_JS" ] || { echo "missing $SHELL_JS" >&2; exit 1; }
[ -f "$GETPTY_JS" ] || { echo "missing $GETPTY_JS" >&2; exit 1; }
[ -f "$POLICYCATALOG_JS" ] || { echo "missing $POLICYCATALOG_JS" >&2; exit 1; }
[ -f "$HANDLER_JS" ] || { echo "missing $HANDLER_JS" >&2; exit 1; }
[ -f "$GEMINICHAT_JS" ] || { echo "missing $GEMINICHAT_JS" >&2; exit 1; }
[ -f "$CLIENT_JS" ] || { echo "missing $CLIENT_JS" >&2; exit 1; }
[ -f "$TOOLEXECUTOR_JS" ] || { echo "missing $TOOLEXECUTOR_JS" >&2; exit 1; }
[ -f "$CORE_CONFIG_JS" ] || { echo "missing $CORE_CONFIG_JS" >&2; exit 1; }
[ -f "$AUTH_JS" ] || { echo "missing $AUTH_JS" >&2; exit 1; }
[ -f "$INITIALIZER_JS" ] || { echo "missing $INITIALIZER_JS" >&2; exit 1; }
[ -f "$USEAUTH_JS" ] || { echo "missing $USEAUTH_JS" >&2; exit 1; }
[ -f "$APPCONTAINER_JS" ] || { echo "missing $APPCONTAINER_JS" >&2; exit 1; }
[ -f "$GOOGLE_QUOTA_ERRORS_JS" ] || { echo "missing $GOOGLE_QUOTA_ERRORS_JS" >&2; exit 1; }
[ -f "$SESSION_BROWSER_JS" ] || { echo "missing $SESSION_BROWSER_JS" >&2; exit 1; }
[ -f "$USE_SESSION_BROWSER_JS" ] || { echo "missing $USE_SESSION_BROWSER_JS" >&2; exit 1; }
[ -f "$TERMINAL_SETUP_JS" ] || { echo "missing $TERMINAL_SETUP_JS" >&2; exit 1; }
[ -f "$CLI_CONFIG_JS" ] || { echo "missing $CLI_CONFIG_JS" >&2; exit 1; }
[ -f "$CLI_GEMINI_JS" ] || { echo "missing $CLI_GEMINI_JS" >&2; exit 1; }
[ -f "$CLI_NONINTERACTIVE_JS" ] || { echo "missing $CLI_NONINTERACTIVE_JS" >&2; exit 1; }
[ -f "$USE_QUOTA_FALLBACK_JS" ] || { echo "missing $USE_QUOTA_FALLBACK_JS" >&2; exit 1; }

python3 - "$INDEX" "$SHELL_JS" "$GETPTY_JS" "$POLICYCATALOG_JS" "$HANDLER_JS" "$GEMINICHAT_JS" "$CLIENT_JS" "$TOOLEXECUTOR_JS" "$AUTH_JS" "$INITIALIZER_JS" "$USEAUTH_JS" "$APPCONTAINER_JS" "$CLI_CONFIG_JS" "$CLI_GEMINI_JS" "$CLI_NONINTERACTIVE_JS" "$GOOGLE_QUOTA_ERRORS_JS" "$CORE_CONFIG_JS" "$USE_QUOTA_FALLBACK_JS" "$SESSION_BROWSER_JS" "$USE_SESSION_BROWSER_JS" "$TERMINAL_SETUP_JS" <<'PY'
from pathlib import Path
import sys
import re

index = Path(sys.argv[1])
shell = Path(sys.argv[2])
getpty = Path(sys.argv[3])
policycatalog = Path(sys.argv[4])
handler = Path(sys.argv[5])
geminichat = Path(sys.argv[6])
client = Path(sys.argv[7])
toolexecutor = Path(sys.argv[8])
auth = Path(sys.argv[9])
initializer = Path(sys.argv[10])
useauth = Path(sys.argv[11])
appcontainer = Path(sys.argv[12])
cli_config = Path(sys.argv[13])
cli_gemini = Path(sys.argv[14])
cli_noninteractive = Path(sys.argv[15])
google_quota_errors = Path(sys.argv[16])
core_config = Path(sys.argv[17])
use_quota_fallback = Path(sys.argv[18])
session_browser = Path(sys.argv[19])
use_session_browser = Path(sys.argv[20])
terminal_setup = Path(sys.argv[21])

def replace_once_or_skip(text, old, new):
    if new in text:
        return text
    if old in text:
        return text.replace(old, new, 1)
    return text

def replace_once_or_fail(text, old, new, label):
    if new in text:
        return text
    if old in text:
        return text.replace(old, new, 1)
    raise RuntimeError(f"critical patch missing marker: {label}")

def require_contains(text, needle, label):
    if needle not in text:
        raise RuntimeError(f"critical patch verification failed: {label}")

text = index.read_text()
if text.startswith('#!/usr/bin/env -S node --no-warnings=DEP0040'):
    text = text.replace('#!/usr/bin/env -S node --no-warnings=DEP0040', '#!/usr/bin/node --no-warnings=DEP0040', 1)
elif text.startswith('#!/usr/bin/env node'):
    text = text.replace('#!/usr/bin/env node', '#!/usr/bin/node --no-warnings=DEP0040', 1)
if "GEMINI_CLI_FORCE_RELAUNCH" not in text:
    marker = "import { createRequire } from 'node:module';\n"
    block = marker + "import { existsSync } from 'node:fs';\nif (process.platform === 'linux' &&\n    existsSync('/etc/alpine-release') &&\n    !process.env['GEMINI_CLI_NO_RELAUNCH'] &&\n    !process.env['GEMINI_CLI_FORCE_RELAUNCH']) {\n    process.env['GEMINI_CLI_NO_RELAUNCH'] = 'true';\n}\n"
    if marker in text:
        text = text.replace(marker, block, 1)
if "argv.length === 1 && (argv[0] === '--version' || argv[0] === '-v')" not in text:
    create_require = "import { createRequire } from 'node:module';\n"
    process_marker = "import process from 'node:process';\n"
    if create_require in text:
        block = create_require + "const argv = process.argv.slice(2);\nif (argv.length === 1 && (argv[0] === '--version' || argv[0] === '-v')) {\n    const require = createRequire(import.meta.url);\n    const { version } = require('../package.json');\n    process.stdout.write(`${version}\\n`);\n    process.exit(0);\n}\n"
        text = text.replace(create_require, block, 1)
    elif process_marker in text:
        block = process_marker + "\nif (process.argv.includes('--version') || process.argv.includes('-v')) {\n  const packageJson = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));\n  process.stdout.write(`${packageJson.version}\\n`);\n  process.exit(0);\n}\n"
        text = text.replace(process_marker, block, 1)
    else:
        # Newer upstream entrypoint layout; skip version fast-path injection
        # instead of aborting the whole reapply operation.
        pass

text = text.replace(
    "const cliArgs = process.argv.slice(2);\nconst isLikelyInteractiveSession = process.stdin.isTTY &&\n    process.stdout.isTTY &&\n    !cliArgs.includes('-p') &&\n    !cliArgs.includes('--prompt');\nlet didAutoRecoverInteractive = false;\n",
    "",
)
text = re.sub(
    r"    if \(isLikelyInteractiveSession &&[\s\S]*?    \}\n    if \(error instanceof FatalError\) \{",
    "    if (error instanceof FatalError) {",
    text,
    count=1,
)
require_contains(text, '#!/usr/bin/node --no-warnings=DEP0040', 'index_shebang')
index.write_text(text)

text = shell.read_text()
text = replace_once_or_fail(text, 'pgrep -g 0', 'pgrep -P $$', 'shell_pgrep_fix')
# Upstream shell tool has used multiple receiver forms across versions.
# Normalize all known callsites so patching remains version-tolerant.
text = text.replace(
    'this.config.getEnableInteractiveShell()',
    'this.config.isInteractiveShellEnabled()',
)
text = text.replace(
    'this.context.config.getEnableInteractiveShell()',
    'this.context.config.isInteractiveShellEnabled()',
)
text = text.replace(
    'context.config.getEnableInteractiveShell()',
    'context.config.isInteractiveShellEnabled()',
)
require_contains(text, 'isInteractiveShellEnabled()', 'shell_interactive_getter_fix')
shell.write_text(text)

text = getpty.read_text()
old = "    const candidates = [\n        ['@lydell/node-pty', 'lydell-node-pty'],\n        ['node-pty', 'node-pty'],\n    ];"
new = "    const preferNodePty = process.platform === 'linux' && (await import('node:fs')).existsSync('/etc/alpine-release');\n    const candidates = preferNodePty\n        ? [\n            ['node-pty', 'node-pty'],\n            ['@lydell/node-pty', 'lydell-node-pty'],\n        ]\n        : [\n            ['@lydell/node-pty', 'lydell-node-pty'],\n            ['node-pty', 'node-pty'],\n        ];"
alt_new = "    const preferNodePty = process.platform === 'linux' && existsSync('/etc/alpine-release');\n    const candidates = preferNodePty\n        ? [\n            ['node-pty', 'node-pty'],\n            ['@lydell/node-pty', 'lydell-node-pty'],\n        ]\n        : [\n            ['@lydell/node-pty', 'lydell-node-pty'],\n            ['node-pty', 'node-pty'],\n        ];"
old_legacy = "    try {\n        const lydell = '@lydell/node-pty';\n        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment\n        const module = await import(lydell);\n        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment\n        return { module, name: 'lydell-node-pty' };\n    }\n    catch (_e) {\n        try {\n            const nodePty = 'node-pty';\n            // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment\n            const module = await import(nodePty);\n            // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment\n            return { module, name: 'node-pty' };\n        }\n        catch (_e2) {\n            return null;\n        }\n    }"
new_legacy = "    const preferNodePty = process.platform === 'linux' && (await import('node:fs')).existsSync('/etc/alpine-release');\n    try {\n        const firstChoice = preferNodePty ? 'node-pty' : '@lydell/node-pty';\n        const firstName = preferNodePty ? 'node-pty' : 'lydell-node-pty';\n        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment\n        const module = await import(firstChoice);\n        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment\n        return { module, name: firstName };\n    }\n    catch (_e) {\n        try {\n            const secondChoice = preferNodePty ? '@lydell/node-pty' : 'node-pty';\n            const secondName = preferNodePty ? 'lydell-node-pty' : 'node-pty';\n            // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment\n            const module = await import(secondChoice);\n            // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment\n            return { module, name: secondName };\n        }\n        catch (_e2) {\n            return null;\n        }\n    }"
if old in text:
    text = text.replace(old, new, 1)
elif alt_new in text:
    pass
elif old_legacy in text:
    text = text.replace(old_legacy, new_legacy, 1)
elif new_legacy in text:
    pass
else:
    raise RuntimeError("critical patch missing marker: getpty_candidate_order")
require_contains(text, "existsSync('/etc/alpine-release')", 'getpty_alpine_preference')
getpty.write_text(text)

text = policycatalog.read_text()
text = text.replace(
    "const DEFAULT_CHAIN = [\n    definePolicy({ model: DEFAULT_GEMINI_MODEL }),\n    definePolicy({ model: DEFAULT_GEMINI_FLASH_MODEL, isLastResort: true }),\n];",
    "const DEFAULT_CHAIN = [\n    definePolicy({ model: DEFAULT_GEMINI_MODEL }),\n    definePolicy({ model: DEFAULT_GEMINI_FLASH_MODEL }),\n    definePolicy({ model: DEFAULT_GEMINI_FLASH_LITE_MODEL, isLastResort: true }),\n];",
)
canonical_preview_block = "if (options.previewEnabled) {\n        const previewModel = resolveModel(PREVIEW_GEMINI_MODEL, options.useGemini31, options.useCustomToolModel);\n        return [\n            definePolicy({ model: previewModel }),\n            definePolicy({ model: PREVIEW_GEMINI_FLASH_MODEL }),\n            definePolicy({ model: DEFAULT_GEMINI_FLASH_MODEL }),\n            definePolicy({ model: DEFAULT_GEMINI_FLASH_LITE_MODEL, isLastResort: true }),\n        ];\n    }"
text = re.sub(
    r"if \(options\.previewEnabled\) \{\n[\s\S]*?        \];\n    \}",
    canonical_preview_block,
    text,
    count=1,
)
require_contains(text, "definePolicy({ model: PREVIEW_GEMINI_FLASH_MODEL })", 'policy_preview_flash_present')
require_contains(text, "definePolicy({ model: DEFAULT_GEMINI_FLASH_LITE_MODEL, isLastResort: true })", 'policy_preview_last_resort_present')
policycatalog.write_text(text)

text = google_quota_errors.read_text()
text = replace_once_or_skip(
    text,
    "                if (errorInfo.reason === 'QUOTA_EXHAUSTED') {\n                    return new TerminalQuotaError(`${googleApiError.message}`, googleApiError, delaySeconds, errorInfo.reason);\n                }\n",
    "                if (errorInfo.reason === 'MODEL_CAPACITY_EXHAUSTED') {\n                    return new TerminalQuotaError(`${googleApiError.message}`, googleApiError, delaySeconds, errorInfo.reason);\n                }\n                if (errorInfo.reason === 'QUOTA_EXHAUSTED') {\n                    return new TerminalQuotaError(`${googleApiError.message}`, googleApiError, delaySeconds, errorInfo.reason);\n                }\n",
)
require_contains(text, "if (errorInfo.reason === 'MODEL_CAPACITY_EXHAUSTED')", 'quota_model_capacity_terminal')
google_quota_errors.write_text(text)

text = core_config.read_text()
text = replace_once_or_skip(
    text,
    "import { DEFAULT_GEMINI_EMBEDDING_MODEL, DEFAULT_GEMINI_FLASH_MODEL, DEFAULT_GEMINI_MODEL, DEFAULT_GEMINI_MODEL_AUTO, isAutoModel, isPreviewModel, PREVIEW_GEMINI_FLASH_MODEL, PREVIEW_GEMINI_MODEL, PREVIEW_GEMINI_MODEL_AUTO, resolveModel, } from './models.js';",
    "import { DEFAULT_GEMINI_EMBEDDING_MODEL, DEFAULT_GEMINI_FLASH_MODEL, DEFAULT_GEMINI_MODEL, DEFAULT_GEMINI_MODEL_AUTO, isAutoModel, isPreviewModel, PREVIEW_GEMINI_FLASH_MODEL, PREVIEW_GEMINI_MODEL, PREVIEW_GEMINI_3_1_MODEL, PREVIEW_GEMINI_MODEL_AUTO, resolveModel, } from './models.js';",
)
text = replace_once_or_skip(
    text,
    "    setHasAccessToPreviewModel(hasAccess) {\n        this.hasAccessToPreviewModel = hasAccess;\n    }\n",
    "    setHasAccessToPreviewModel(hasAccess) {\n        this.hasAccessToPreviewModel = hasAccess;\n    }\n    normalizeQuotaModelId(modelId) {\n        switch (modelId) {\n            case 'gemini-3-pro':\n                return PREVIEW_GEMINI_MODEL;\n            case 'gemini-3-flash':\n                return PREVIEW_GEMINI_FLASH_MODEL;\n            case 'gemini-3.1-pro':\n                return PREVIEW_GEMINI_3_1_MODEL;\n            default:\n                return modelId;\n        }\n    }\n",
)
text = replace_once_or_skip(
    text,
    "                        const remaining = parseInt(bucket.remainingAmount, 10);\n                        const limit = bucket.remainingFraction > 0\n                            ? Math.round(remaining / bucket.remainingFraction)\n                            : (this.modelQuotas.get(bucket.modelId)?.limit ?? 0);\n                        if (!isNaN(remaining) && Number.isFinite(limit) && limit > 0) {\n                            this.modelQuotas.set(bucket.modelId, {\n",
    "                        const quotaModelId = this.normalizeQuotaModelId(bucket.modelId);\n                        const remaining = parseInt(bucket.remainingAmount, 10);\n                        const limit = bucket.remainingFraction > 0\n                            ? Math.round(remaining / bucket.remainingFraction)\n                            : (this.modelQuotas.get(quotaModelId)?.limit ?? 0);\n                        if (!isNaN(remaining) && Number.isFinite(limit) && limit > 0) {\n                            this.modelQuotas.set(quotaModelId, {\n",
)
text = replace_once_or_skip(
    text,
    "            const hasAccess = quota.buckets?.some((b) => b.modelId && isPreviewModel(b.modelId)) ??\n                false;",
    "            const hasAccess = quota.buckets?.some((b) => {\n                if (!b.modelId) {\n                    return false;\n                }\n                return isPreviewModel(this.normalizeQuotaModelId(b.modelId));\n            }) ?? false;",
)
require_contains(text, "PREVIEW_GEMINI_3_1_MODEL", 'core_config_preview_model_import')
require_contains(text, "normalizeQuotaModelId(modelId)", 'core_config_quota_model_normalization')
core_config.write_text(text)

text = use_quota_fallback.read_text()
text = text.replace(
    "            const disableModelFallback = settings?.merged?.general?.disableModelFallback === true ||\n                process.env['GEMINI_CLI_DISABLE_MODEL_FALLBACK'] === '1';\n",
    "",
)
text = text.replace(
    "            if (disableModelFallback) {\n                return 'stop';\n            }\n",
    "            return 'stop'; // patched_no_auto_fallback_ui\n",
)
text = replace_once_or_skip(
    text,
    "            // In low verbosity mode, auto-retry transient capacity failures\n",
    "            return 'stop'; // patched_no_auto_fallback_ui\n            // In low verbosity mode, auto-retry transient capacity failures\n",
)
require_contains(text, "patched_no_auto_fallback_ui", 'disable_fallback_default_ui')
use_quota_fallback.write_text(text)

text = handler.read_text()
text = text.replace("import { AuthType } from '../core/contentGenerator.js';\n", "")
text = text.replace(
    "export async function handleFallback(config, failedModel, authType, error) {\n    if (authType !== AuthType.LOGIN_WITH_GOOGLE) {\n        return null;\n    }\n",
    "export async function handleFallback(config, failedModel, authType, error, options = {}) {\n",
)
text = text.replace(
    "export async function handleFallback(config, failedModel, authType, error) {\n",
    "export async function handleFallback(config, failedModel, authType, error, options = {}) {\n",
)
text = text.replace(
    "    if (process.env['GEMINI_CLI_DISABLE_MODEL_FALLBACK'] === '1') {\n        return false;\n    }\n",
    "",
)
if "patched_no_auto_fallback_core" not in text:
    text = text.replace(
        "export async function handleFallback(config, failedModel, authType, error, options = {}) {\n",
        "export async function handleFallback(config, failedModel, authType, error, options = {}) {\n    return false; // patched_no_auto_fallback_core\n",
        1,
    )
text = text.replace(
    "if (action === 'silent') {",
    "if (action === 'silent' || options.forceSilent) {",
)
require_contains(text, "options = {}", 'handler_options_signature')
require_contains(text, "patched_no_auto_fallback_core", 'handler_disable_fallback_default')
handler.write_text(text)

text = geminichat.read_text()
text = text.replace(
    "const onPersistent429Callback = async (authType, error) => handleFallback(this.config, lastModelToUse, authType, error);",
    "const onPersistent429Callback = async (authType, error) => handleFallback(this.config, lastModelToUse, authType, error, {\n            forceSilent: role === 'subagent',\n        });",
)
text = text.replace(
    "let hasToolCall = false;",
    "let hasUsableToolCall = false;",
)
text = text.replace(
    "if (content.parts.some((part) => part.functionCall)) {\n                        hasToolCall = true;\n                    }",
    "if ((chunk.functionCalls?.length ?? 0) > 0) {\n                        hasUsableToolCall = true;\n                    }",
)
text = text.replace(
    "if (responseText || hasThoughts || hasToolCall) {",
    "if (responseText || hasThoughts || hasUsableToolCall) {",
)
text = text.replace(
    "if (!hasToolCall) {\n            if (!finishReason) {\n                throw new InvalidStreamError('Model stream ended without a finish reason.', 'NO_FINISH_REASON');\n            }\n            if (finishReason === FinishReason.MALFORMED_FUNCTION_CALL) {\n                throw new InvalidStreamError('Model stream ended with malformed function call.', 'MALFORMED_FUNCTION_CALL');\n            }\n            if (finishReason === FinishReason.UNEXPECTED_TOOL_CALL) {\n                throw new InvalidStreamError('Model stream ended with unexpected tool call.', 'UNEXPECTED_TOOL_CALL');\n            }\n            if (!responseText) {\n                throw new InvalidStreamError('Model stream ended with empty response text.', 'NO_RESPONSE_TEXT');\n            }\n        }",
    "if (finishReason === FinishReason.MALFORMED_FUNCTION_CALL) {\n            throw new InvalidStreamError('Model stream ended with malformed function call.', 'MALFORMED_FUNCTION_CALL');\n        }\n        if (finishReason === FinishReason.UNEXPECTED_TOOL_CALL) {\n            throw new InvalidStreamError('Model stream ended with unexpected tool call.', 'UNEXPECTED_TOOL_CALL');\n        }\n        if (!hasUsableToolCall) {\n            if (!finishReason) {\n                throw new InvalidStreamError('Model stream ended without a finish reason.', 'NO_FINISH_REASON');\n            }\n            if (!responseText) {\n                throw new InvalidStreamError('Model stream ended with empty response text.', 'NO_RESPONSE_TEXT');\n            }\n        }",
)
text = text.replace(
    "if (!hasToolCall) {\n            if (!finishReason) {\n                throw new InvalidStreamError('Model stream ended without a finish reason.', 'NO_FINISH_REASON');\n            }\n            if (finishReason === FinishReason.MALFORMED_FUNCTION_CALL) {\n                throw new InvalidStreamError('Model stream ended with malformed function call.', 'MALFORMED_FUNCTION_CALL');\n            }\n            if (!responseText) {\n                throw new InvalidStreamError('Model stream ended with empty response text.', 'NO_RESPONSE_TEXT');\n            }\n        }",
    "if (finishReason === FinishReason.MALFORMED_FUNCTION_CALL) {\n            throw new InvalidStreamError('Model stream ended with malformed function call.', 'MALFORMED_FUNCTION_CALL');\n        }\n        if (!hasUsableToolCall) {\n            if (!finishReason) {\n                throw new InvalidStreamError('Model stream ended without a finish reason.', 'NO_FINISH_REASON');\n            }\n            if (!responseText) {\n                throw new InvalidStreamError('Model stream ended with empty response text.', 'NO_RESPONSE_TEXT');\n            }\n        }",
)
geminichat.write_text(text)

text = client.read_text()
text = text.replace(
    "        if (this.config.getContinueOnFailedApiCall() &&\n            isGemini2Model(modelToUse)) {",
    "        if (this.config.getContinueOnFailedApiCall()) {",
)
text = text.replace('if (isInvalidStreamRetry) {', 'if (isInvalidStreamRetry >= 5) {')
text = text.replace('if (isInvalidStreamRetry >= 3) {', 'if (isInvalidStreamRetry >= 5) {')
text = text.replace(
    "turn = yield* this.sendMessageStream(nextRequest, signal, prompt_id, boundedTurns - 1, true, displayContent);",
    "turn = yield* this.sendMessageStream(nextRequest, signal, prompt_id, boundedTurns - 1, isInvalidStreamRetry + 1, displayContent);",
)
text = text.replace(
    "const nextRequest = [{ text: 'System: Please continue.' }];",
    "const nextRequest = [{ text: 'System: Your previous response ended empty or malformed. Continue the same task without restarting, and if you use tools, emit a complete valid tool call.' }];",
)
text = text.replace(
    "        if (isInvalidStreamRetry >= 5) {\n            logContentRetryFailure(",
    "        if (isInvalidStreamRetry >= 5) {\n            const didFallback = await handleFallback(this.config, modelToUse, undefined, new Error('Invalid stream retry limit reached.'), { forceSilent: true });\n            if (didFallback) {\n                const nextRequest = [{ text: 'System: Your previous response ended empty or malformed. Continue the same task without restarting, and if you use tools, emit a complete valid tool call.' }];\n                turn = yield* this.sendMessageStream(nextRequest, signal, prompt_id, boundedTurns - 1, 0, displayContent);\n                return turn;\n            }\n            logContentRetryFailure(",
)
text = text.replace(
    "if (isInvalidStream) {\n            if (this.config.getContinueOnFailedApiCall()) {\n                if (isInvalidStreamRetry >= 5) {\n                    logContentRetryFailure(this.config, new ContentRetryFailureEvent(4, 'FAILED_AFTER_PROMPT_INJECTION', modelToUse));\n                    return turn;\n                }\n                const nextRequest = [{ text: 'System: Your previous response ended empty or malformed. Continue the same task without restarting, and if you use tools, emit a complete valid tool call.' }];\n                // Recursive call - update turn with result\n                turn = yield* this.sendMessageStream(nextRequest, signal, prompt_id, boundedTurns - 1, isInvalidStreamRetry + 1, displayContent);\n                return turn;\n            }\n        }",
    "if (isInvalidStream) {\n            if (this.config.getContinueOnFailedApiCall()) {\n                if (isInvalidStreamRetry >= 5) {\n                    const didFallback = await handleFallback(this.config, modelToUse, undefined, new Error('Invalid stream retry limit reached.'), { forceSilent: true });\n                    if (didFallback) {\n                        const nextRequest = [{ text: 'System: Your previous response ended empty or malformed. Continue the same task without restarting, and if you use tools, emit a complete valid tool call.' }];\n                        turn = yield* this.sendMessageStream(nextRequest, signal, prompt_id, boundedTurns - 1, 0, displayContent);\n                        return turn;\n                    }\n                    logContentRetryFailure(this.config, new ContentRetryFailureEvent(6, 'FAILED_AFTER_PROMPT_INJECTION', modelToUse));\n                    return turn;\n                }\n                const nextRequest = [{ text: 'System: Your previous response ended empty or malformed. Continue the same task without restarting, and if you use tools, emit a complete valid tool call.' }];\n                // Recursive call - update turn with result\n                turn = yield* this.sendMessageStream(nextRequest, signal, prompt_id, boundedTurns - 1, isInvalidStreamRetry + 1, displayContent);\n                return turn;\n            }\n        }",
)
text = text.replace(
    "async *sendMessageStream(request, signal, prompt_id, turns = MAX_TURNS, isInvalidStreamRetry = false, displayContent) {",
    "async *sendMessageStream(request, signal, prompt_id, turns = MAX_TURNS, isInvalidStreamRetry = 0, displayContent) {",
)
text = text.replace('if (!isInvalidStreamRetry) {', 'if (isInvalidStreamRetry === 0) {')
client.write_text(text)

text = toolexecutor.read_text()
text = text.replace(
    "if (typeof content === 'string' && toolName === SHELL_TOOL_NAME) {",
    "if (typeof content === 'string') {",
)
toolexecutor.write_text(text)

text = auth.read_text()
text = replace_once_or_skip(
    text,
    "        return { authError: null, accountSuspensionInfo: null };",
    "        return { authError: null, accountSuspensionInfo: null, authSucceeded: false };",
)
text = replace_once_or_skip(
    text,
    "            return { authError: null, accountSuspensionInfo: null };",
    "            return { authError: null, accountSuspensionInfo: null, authSucceeded: false };",
)
text = replace_once_or_skip(
    text,
    "            return {\n                authError: null,\n                accountSuspensionInfo: {\n                    message: suspendedError.message,\n                    appealUrl: suspendedError.appealUrl,\n                    appealLinkText: suspendedError.appealLinkText,\n                },\n            };",
    "            return {\n                authError: null,\n                accountSuspensionInfo: {\n                    message: suspendedError.message,\n                    appealUrl: suspendedError.appealUrl,\n                    appealLinkText: suspendedError.appealLinkText,\n                },\n                authSucceeded: false,\n            };",
)
text = replace_once_or_skip(
    text,
    "        return {\n            authError: `Failed to login. Message: ${getErrorMessage(e)}`,\n            accountSuspensionInfo: null,\n        };",
    "        return {\n            authError: `Failed to login. Message: ${getErrorMessage(e)}`,\n            accountSuspensionInfo: null,\n            authSucceeded: false,\n        };",
)
text = replace_once_or_skip(
    text,
    "    return { authError: null, accountSuspensionInfo: null };",
    "    return { authError: null, accountSuspensionInfo: null, authSucceeded: true };",
)
auth.write_text(text)

text = initializer.read_text()
text = text.replace(
    "const { authError, accountSuspensionInfo } = await performInitialAuth(config, settings.merged.security.auth.selectedType);",
    "const { authError, accountSuspensionInfo, authSucceeded } = await performInitialAuth(config, settings.merged.security.auth.selectedType);",
)
text = text.replace(
    "        accountSuspensionInfo,\n        themeError,",
    "        accountSuspensionInfo,\n        initialAuthSucceeded: authSucceeded,\n        themeError,",
)
initializer.write_text(text)

text = useauth.read_text()
text = text.replace(
    "export const useAuthCommand = (settings, config, initialAuthError = null, initialAccountSuspensionInfo = null) => {\n    const [authState, setAuthState] = useState(initialAuthError ? AuthState.Updating : AuthState.Unauthenticated);",
    "export const useAuthCommand = (settings, config, initialAuthError = null, initialAccountSuspensionInfo = null, initialAuthSucceeded = false) => {\n    const [authState, setAuthState] = useState(initialAuthError\n        ? AuthState.Updating\n        : initialAuthSucceeded\n            ? AuthState.Authenticated\n            : AuthState.Unauthenticated);",
)
useauth.write_text(text)

text = appcontainer.read_text()
text = text.replace(
    "useAuthCommand(settings, config, initializationResult.authError, initializationResult.accountSuspensionInfo)",
    "useAuthCommand(settings, config, initializationResult.authError, initializationResult.accountSuspensionInfo, initializationResult.initialAuthSucceeded)",
)
appcontainer.write_text(text)

text = terminal_setup.read_text()
text = replace_once_or_skip(
    text,
    "function getSupportedTerminalData(terminal) {\n    return TERMINAL_DATA[terminal] || null;\n}",
    "function getSupportedTerminalData(terminal) {\n    return TERMINAL_DATA[terminal];\n}",
)
text = replace_once_or_skip(
    text,
    "return null;\n}\n// Terminal detection",
    "return null;\n}\nfunction detectFromParentName(parentName) {\n    const normalized = parentName.toLowerCase();\n    if (normalized.includes('windsurf'))\n        return 'windsurf';\n    if (normalized.includes('antigravity'))\n        return 'antigravity';\n    if (normalized.includes('cursor'))\n        return 'cursor';\n    if (normalized.includes('code'))\n        return 'vscode';\n    return null;\n}\n// Terminal detection",
)
terminal_detect_block = (
    "// Terminal detection\n"
    "async function detectTerminal() {\n"
    "    const envTerminal = getTerminalProgram();\n"
    "    if (envTerminal) {\n"
    "        return envTerminal;\n"
    "    }\n"
    "    const platform = os.platform();\n"
    "    if (platform === 'win32') {\n"
    "        return null;\n"
    "    }\n"
    "    if (platform === 'linux') {\n"
    "        const ppid = process.ppid;\n"
    "        if (!Number.isInteger(ppid) || ppid <= 1) {\n"
    "            return null;\n"
    "        }\n"
    "        try {\n"
    "            const comm = await fs.readFile(`/proc/${ppid}/comm`, 'utf8');\n"
    "            return detectFromParentName(comm.trim());\n"
    "        }\n"
    "        catch (error) {\n"
    "            debugLogger.debug('Parent process detection failed:', error);\n"
    "            return null;\n"
    "        }\n"
    "    }\n"
    "    try {\n"
    "        const { stdout } = await execAsync(`ps -o comm= -p ${process.ppid}`);\n"
    "        return detectFromParentName(stdout.trim());\n"
    "    }\n"
    "    catch (error) {\n"
    "        debugLogger.debug('Parent process detection failed:', error);\n"
    "        return null;\n"
    "    }\n"
    "}\n"
)
text = re.sub(
    r"(?s)// Terminal detection\nasync function detectTerminal\(\) \{.*?\n\}\n// Backup file helper",
    terminal_detect_block + "// Backup file helper",
    text,
    count=1,
)
text = text.replace(
    "    if (!terminalData) {\n        return false;\n    }\n",
    "",
)
text = text.replace(
    "    if (!terminalData) {\n        return {\n            success: false,\n            message: `Terminal \"${terminal}\" is not supported yet.`,\n        };\n    }\n",
    "",
)
require_contains(text, "/proc/${ppid}/comm", 'terminal_setup_linux_proc_detect')
require_contains(text, "return TERMINAL_DATA[terminal];", 'terminal_setup_single_path_metadata')
terminal_setup.write_text(text)

text = cli_config.read_text()
old = "export async function loadCliConfig(settings, sessionId, argv, options = {}) {\n    const { cwd = process.cwd(), projectHooks } = options;"
new = "export async function loadCliConfig(settings, sessionId, argv, options = {}) {\n    const { cwd = process.cwd(), projectHooks, skipMemoryLoad = false, skipExtensionLoad = false } = options;"
text = replace_once_or_skip(text, old, new)

# Normalize loadExtensions guard to one canonical block even if older runs nested it.
text = re.sub(
    r"(?ms)^[ \t]*if \(!skipExtensionLoad\) \{\n(?:[ \t]*if \(!skipExtensionLoad\) \{\n)*[ \t]*await extensionManager\.loadExtensions\(\);\n(?:[ \t]*\}\n)+",
    "    if (!skipExtensionLoad) {\n        await extensionManager.loadExtensions();\n    }\n",
    text,
    count=1,
)
if "    if (!skipExtensionLoad) {\n        await extensionManager.loadExtensions();\n    }\n" not in text:
    text = replace_once_or_skip(
        text,
        "    await extensionManager.loadExtensions();\n",
        "    if (!skipExtensionLoad) {\n        await extensionManager.loadExtensions();\n    }\n",
    )

# Keep exactly one extensionPlanSettings declaration in a canonical form.
canonical_extension_plan = (
    "    const extensionPlanSettings = skipExtensionLoad\n"
    "        ? undefined\n"
    "        : extensionManager\n"
    "            .getExtensions()\n"
    "            .find((ext) => ext.isActive && ext.plan?.directory)?.plan;\n"
)
if canonical_extension_plan not in text:
    text = re.sub(
        r"(?ms)^[ \t]*const extensionPlanSettings =[\s\S]*?;\n",
        canonical_extension_plan,
        text,
        count=1,
    )

text = replace_once_or_skip(
    text,
    "    if (!experimentalJitContext) {\n",
    "    if (!skipMemoryLoad && !experimentalJitContext) {\n",
)
cli_config.write_text(text)

text = cli_gemini.read_text()
old = "    const partialConfig = await loadCliConfig(settings.merged, sessionId, argv, {\n        projectHooks: settings.workspace.settings.hooks,\n    });"
new = "    const partialConfig = await loadCliConfig(settings.merged, sessionId, argv, {\n        projectHooks: settings.workspace.settings.hooks,\n        skipMemoryLoad: true,\n        skipExtensionLoad: true,\n    });"
text = replace_once_or_skip(text, old, new)

anchor = "    adminControlsListner.setConfig(partialConfig);\n"
canonical_preauth_block = (
    "    adminControlsListner.setConfig(partialConfig);\n"
    "    const sandboxConfig = await loadSandboxConfig(settings.merged, argv);\n"
    "    const shouldPreAuthenticate = !settings.merged.security.auth.useExternal &&\n"
    "        (!!sandboxConfig || !process.env['GEMINI_CLI_NO_RELAUNCH']);\n"
)

# Keep exactly one sandboxConfig/shouldPreAuthenticate pair after adminControlsListner.setConfig.
pattern = (
    r"    adminControlsListner\.setConfig\(partialConfig\);\n"
    r"(?:    const sandboxConfig = await loadSandboxConfig\(settings\.merged, argv\);\n"
    r"    const shouldPreAuthenticate = !settings\.merged\.security\.auth\.useExternal &&\n"
    r"        \(\!\!sandboxConfig \|\| !process\.env\['GEMINI_CLI_NO_RELAUNCH'\]\);\n)+"
)
if re.search(pattern, text):
    text = re.sub(pattern, canonical_preauth_block, text, count=1)
elif anchor in text:
    text = text.replace(anchor, canonical_preauth_block, 1)

text = replace_once_or_skip(
    text,
    "    if (!settings.merged.security.auth.useExternal) {\n",
    "    if (shouldPreAuthenticate) {\n",
)
text = text.replace("        const sandboxConfig = await loadSandboxConfig(settings.merged, argv);\n", "", 1)

text = re.sub(
    r"        if \(config\.isInteractive\(\)\) \{\n            const renderInteractiveUi = async \(\) => startInteractiveUI\(config, settings, startupWarnings, process\.cwd\(\), resumedSessionData, initializationResult\);\n            try \{\n                await renderInteractiveUi\(\);\n                return;\n            \}\n            catch \(error\) \{\n                const message = error instanceof Error \? error\.message : String\(error \?\? 'Unknown'\);\n                coreEvents\.emitFeedback\('error', `Interactive session failed: \$\{message\}`\);\n                writeToStderr\(`Interactive session failed: \$\{message\}\\n`\);\n                writeToStderr\('Retrying interactive session once\.\.\.\\n'\);\n                debugLogger\.error\('Interactive session failed \(first attempt\)', error\);\n            \}\n            try \{\n                await renderInteractiveUi\(\);\n                return;\n            \}\n            catch \(error\) \{\n                const message = error instanceof Error \? error\.message : String\(error \?\? 'Unknown'\);\n                coreEvents\.emitFeedback\('error', `Interactive session failed again: \$\{message\}`\);\n                writeToStderr\(`Interactive session failed again: \$\{message\}\\n`\);\n                writeToStderr\('Gemini CLI is exiting after repeated interactive startup failure\.\\n'\);\n                debugLogger\.error\('Interactive session failed \(second attempt\)', error\);\n                await runExitCleanup\(\);\n                process\.exit\(1\);\n            \}\n        \}\n",
    "        if (config.isInteractive()) {\n            await startInteractiveUI(config, settings, startupWarnings, process.cwd(), resumedSessionData, initializationResult);\n            return;\n        }\n",
    text,
    count=1,
)
cli_gemini.write_text(text)

text = cli_noninteractive.read_text()
text = text.replace(
    "        catch (error) {\n            errorToHandle = error;\n        }\n        finally {\n            // Cleanup stdin cancellation before other cleanup\n            cleanupStdinCancellation();\n            consolePatcher.cleanup();\n            coreEvents.off(CoreEvent.UserFeedback, handleUserFeedback);\n        }\n        if (errorToHandle) {\n            handleError(errorToHandle, config);\n        }",
    "        catch (error) {\n            errorToHandle = error;\n            handleError(errorToHandle, config);\n        }\n        finally {\n            // Cleanup stdin cancellation before other cleanup\n            cleanupStdinCancellation();\n            consolePatcher.cleanup();\n            coreEvents.off(CoreEvent.UserFeedback, handleUserFeedback);\n        }",
)
require_contains(
    text,
    "catch (error) {\n            errorToHandle = error;\n            handleError(errorToHandle, config);\n        }",
    'noninteractive_error_ordering',
)
cli_noninteractive.write_text(text)

text = use_session_browser.read_text()
text = text.replace(
    "        handleDeleteSession: useCallback((session) => {",
    "        handleDeleteSession: useCallback(async (session) => {",
)
text = text.replace(
    "                    chatRecordingService.deleteSession(session.file);",
    "                    await Promise.resolve(chatRecordingService.deleteSession(session.file));",
)
require_contains(
    text,
    "handleDeleteSession: useCallback(async (session) => {",
    'session_delete_handler_async',
)
require_contains(
    text,
    "await Promise.resolve(chatRecordingService.deleteSession(session.file));",
    'session_delete_handler_promise_return',
)
use_session_browser.write_text(text)

text = session_browser.read_text()
text = replace_once_or_skip(
    text,
    "                if (selectedSession && !selectedSession.isCurrentSession) {\n",
    "                if (selectedSession?.isCurrentSession) {\n                    state.setError('Cannot delete the current active session.');\n                }\n                else if (selectedSession) {\n",
)
require_contains(
    text,
    "Cannot delete the current active session.",
    'session_delete_current_feedback',
)
session_browser.write_text(text)
PY

# Install diagnostics only when explicitly requested.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ "$INSTALL_DIAGNOSTICS" -eq 1 ]; then
  "$SCRIPT_DIR/install-gemini-diagnostics.sh" "$PREFIX"
else
  echo "diagnostics not installed (use --with-diagnostics to enable)"
fi

echo "patched $ROOT"
