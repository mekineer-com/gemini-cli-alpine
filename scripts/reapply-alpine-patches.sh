#!/bin/sh
set -eu

PREFIX=${1:-$HOME/.local}
ROOT="$PREFIX/lib/node_modules/@google/gemini-cli"
INDEX="$ROOT/dist/index.js"
CORE="$ROOT/node_modules/@google/gemini-cli-core/dist"
CLI_DIST="$ROOT/dist/src"
CLI_CONFIG_JS="$CLI_DIST/config/config.js"
CLI_GEMINI_JS="$CLI_DIST/gemini.js"
SHELL_JS="$CORE/src/tools/shell.js"
GETPTY_JS="$CORE/src/utils/getPty.js"
POLICYCATALOG_JS="$CORE/src/availability/policyCatalog.js"
HANDLER_JS="$CORE/src/fallback/handler.js"
GEMINICHAT_JS="$CORE/src/core/geminiChat.js"
CLIENT_JS="$CORE/src/core/client.js"
TOOLEXECUTOR_JS="$CORE/src/scheduler/tool-executor.js"
AUTH_JS="$CLI_DIST/core/auth.js"
INITIALIZER_JS="$CLI_DIST/core/initializer.js"
USEAUTH_JS="$CLI_DIST/ui/auth/useAuth.js"
APPCONTAINER_JS="$CLI_DIST/ui/AppContainer.js"

[ -f "$INDEX" ] || { echo "missing $INDEX" >&2; exit 1; }
[ -f "$SHELL_JS" ] || { echo "missing $SHELL_JS" >&2; exit 1; }
[ -f "$GETPTY_JS" ] || { echo "missing $GETPTY_JS" >&2; exit 1; }
[ -f "$POLICYCATALOG_JS" ] || { echo "missing $POLICYCATALOG_JS" >&2; exit 1; }
[ -f "$HANDLER_JS" ] || { echo "missing $HANDLER_JS" >&2; exit 1; }
[ -f "$GEMINICHAT_JS" ] || { echo "missing $GEMINICHAT_JS" >&2; exit 1; }
[ -f "$CLIENT_JS" ] || { echo "missing $CLIENT_JS" >&2; exit 1; }
[ -f "$TOOLEXECUTOR_JS" ] || { echo "missing $TOOLEXECUTOR_JS" >&2; exit 1; }
[ -f "$AUTH_JS" ] || { echo "missing $AUTH_JS" >&2; exit 1; }
[ -f "$INITIALIZER_JS" ] || { echo "missing $INITIALIZER_JS" >&2; exit 1; }
[ -f "$USEAUTH_JS" ] || { echo "missing $USEAUTH_JS" >&2; exit 1; }
[ -f "$APPCONTAINER_JS" ] || { echo "missing $APPCONTAINER_JS" >&2; exit 1; }
[ -f "$CLI_CONFIG_JS" ] || { echo "missing $CLI_CONFIG_JS" >&2; exit 1; }
[ -f "$CLI_GEMINI_JS" ] || { echo "missing $CLI_GEMINI_JS" >&2; exit 1; }

python3 - "$INDEX" "$SHELL_JS" "$GETPTY_JS" "$POLICYCATALOG_JS" "$HANDLER_JS" "$GEMINICHAT_JS" "$CLIENT_JS" "$TOOLEXECUTOR_JS" "$AUTH_JS" "$INITIALIZER_JS" "$USEAUTH_JS" "$APPCONTAINER_JS" "$CLI_CONFIG_JS" "$CLI_GEMINI_JS" <<'PY'
from pathlib import Path
import sys

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

text = index.read_text()
if text.startswith('#!/usr/bin/env -S node --no-warnings=DEP0040'):
    text = text.replace('#!/usr/bin/env -S node --no-warnings=DEP0040', '#!/usr/bin/node --no-warnings=DEP0040', 1)
elif text.startswith('#!/usr/bin/env node'):
    text = text.replace('#!/usr/bin/env node', '#!/usr/bin/node --no-warnings=DEP0040', 1)
if "GEMINI_CLI_FORCE_RELAUNCH" not in text:
    marker = "import { createRequire } from 'node:module';\n"
    block = marker + "import { existsSync } from 'node:fs';\nif (process.platform === 'linux' &&\n    existsSync('/etc/alpine-release') &&\n    !process.env['GEMINI_CLI_NO_RELAUNCH'] &&\n    !process.env['GEMINI_CLI_FORCE_RELAUNCH']) {\n    process.env['GEMINI_CLI_NO_RELAUNCH'] = 'true';\n}\n"
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
        raise SystemExit('index.js marker not found')
index.write_text(text)

text = shell.read_text()
text = text.replace('pgrep -g 0', 'pgrep -P $$')
text = text.replace('this.config.getEnableInteractiveShell()', 'this.config.isInteractiveShellEnabled()')
shell.write_text(text)

text = getpty.read_text()
old = "    const candidates = [\n        ['@lydell/node-pty', 'lydell-node-pty'],\n        ['node-pty', 'node-pty'],\n    ];"
new = "    const preferNodePty = process.platform === 'linux' && (await import('node:fs')).existsSync('/etc/alpine-release');\n    const candidates = preferNodePty\n        ? [\n            ['node-pty', 'node-pty'],\n            ['@lydell/node-pty', 'lydell-node-pty'],\n        ]\n        : [\n            ['@lydell/node-pty', 'lydell-node-pty'],\n            ['node-pty', 'node-pty'],\n        ];"
alt_new = "    const preferNodePty = process.platform === 'linux' && existsSync('/etc/alpine-release');\n    const candidates = preferNodePty\n        ? [\n            ['node-pty', 'node-pty'],\n            ['@lydell/node-pty', 'lydell-node-pty'],\n        ]\n        : [\n            ['@lydell/node-pty', 'lydell-node-pty'],\n            ['node-pty', 'node-pty'],\n        ];"
if old in text:
    text = text.replace(old, new, 1)
elif alt_new in text:
    pass
getpty.write_text(text)

text = policycatalog.read_text()
text = text.replace(
    "const DEFAULT_CHAIN = [\n    definePolicy({ model: DEFAULT_GEMINI_MODEL }),\n    definePolicy({ model: DEFAULT_GEMINI_FLASH_MODEL, isLastResort: true }),\n];",
    "const DEFAULT_CHAIN = [\n    definePolicy({ model: DEFAULT_GEMINI_MODEL }),\n    definePolicy({ model: DEFAULT_GEMINI_FLASH_MODEL }),\n    definePolicy({ model: DEFAULT_GEMINI_FLASH_LITE_MODEL, isLastResort: true }),\n];",
)
old = "        return [\n            definePolicy({ model: previewModel }),\n            definePolicy({ model: PREVIEW_GEMINI_FLASH_MODEL, isLastResort: true }),\n        ];"
new = "        return [\n            definePolicy({\n                model: previewModel,\n                actions: SILENT_ACTIONS,\n            }),\n            definePolicy({\n                model: DEFAULT_GEMINI_MODEL,\n                actions: SILENT_ACTIONS,\n            }),\n            definePolicy({\n                model: DEFAULT_GEMINI_FLASH_MODEL,\n                actions: SILENT_ACTIONS,\n            }),\n            definePolicy({\n                model: DEFAULT_GEMINI_FLASH_LITE_MODEL,\n                isLastResort: true,\n                actions: SILENT_ACTIONS,\n            }),\n        ];"
if old in text:
    text = text.replace(old, new, 1)
text = text.replace(
    "            definePolicy({\n                model: PREVIEW_GEMINI_FLASH_MODEL,\n                actions: SILENT_ACTIONS,\n            }),\n            definePolicy({\n                model: DEFAULT_GEMINI_FLASH_LITE_MODEL,\n                isLastResort: true,\n                actions: SILENT_ACTIONS,\n            }),",
    "            definePolicy({\n                model: DEFAULT_GEMINI_MODEL,\n                actions: SILENT_ACTIONS,\n            }),\n            definePolicy({\n                model: DEFAULT_GEMINI_FLASH_MODEL,\n                actions: SILENT_ACTIONS,\n            }),\n            definePolicy({\n                model: DEFAULT_GEMINI_FLASH_LITE_MODEL,\n                isLastResort: true,\n                actions: SILENT_ACTIONS,\n            }),",
)
policycatalog.write_text(text)

text = handler.read_text()
text = text.replace("import { AuthType } from '../core/contentGenerator.js';\n", "")
text = text.replace(
    "export async function handleFallback(config, failedModel, authType, error) {\n    if (authType !== AuthType.LOGIN_WITH_GOOGLE) {\n        return null;\n    }\n",
    "export async function handleFallback(config, failedModel, authType, error, options = {}) {\n",
)
text = text.replace(
    "if (action === 'silent') {",
    "if (action === 'silent' || options.forceSilent) {",
)
handler.write_text(text)

text = geminichat.read_text()
text = text.replace(
    "const onPersistent429Callback = async (authType, error) => handleFallback(this.config, lastModelToUse, authType, error);",
    "const onPersistent429Callback = async (authType, error) => handleFallback(this.config, lastModelToUse, authType, error, {\n            forceSilent: role === 'subagent',\n        });",
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
text = text.replace("return { authError: null, accountSuspensionInfo: null };", "return { authError: null, accountSuspensionInfo: null, authSucceeded: false };", 2)
text = text.replace(
    "                },\n            };",
    "                },\n                authSucceeded: false,\n            };",
    1,
)
text = text.replace(
    "        return {\n            authError: `Failed to login. Message: ${getErrorMessage(e)}`,\n            accountSuspensionInfo: null,\n        };",
    "        return {\n            authError: `Failed to login. Message: ${getErrorMessage(e)}`,\n            accountSuspensionInfo: null,\n            authSucceeded: false,\n        };",
)
text = text.replace(
    "    return { authError: null, accountSuspensionInfo: null };",
    "    return { authError: null, accountSuspensionInfo: null, authSucceeded: true };",
    1,
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

text = cli_config.read_text()
old = "export async function loadCliConfig(settings, sessionId, argv, options = {}) {\n    const { cwd = process.cwd(), projectHooks } = options;"
new = "export async function loadCliConfig(settings, sessionId, argv, options = {}) {\n    const { cwd = process.cwd(), projectHooks, skipMemoryLoad = false, skipExtensionLoad = false } = options;"
if old in text:
    text = text.replace(old, new, 1)
text = text.replace("    await extensionManager.loadExtensions();\n", "    if (!skipExtensionLoad) {\n        await extensionManager.loadExtensions();\n    }\n", 1)
if "const extensionPlanSettings = skipExtensionLoad" not in text:
    text = text.replace("    const experimentalJitContext = settings.experimental?.jitContext ?? false;\n", "    const extensionPlanSettings = skipExtensionLoad\n        ? undefined\n        : extensionManager\n            .getExtensions()\n            .find((ext) => ext.isActive && ext.plan?.directory)?.plan;\n    const experimentalJitContext = settings.experimental?.jitContext ?? false;\n", 1)
text = text.replace("    if (!experimentalJitContext) {\n", "    if (!skipMemoryLoad && !experimentalJitContext) {\n", 1)
cli_config.write_text(text)

text = cli_gemini.read_text()
old = "    const partialConfig = await loadCliConfig(settings.merged, sessionId, argv, {\n        projectHooks: settings.workspace.settings.hooks,\n    });"
new = "    const partialConfig = await loadCliConfig(settings.merged, sessionId, argv, {\n        projectHooks: settings.workspace.settings.hooks,\n        skipMemoryLoad: true,\n        skipExtensionLoad: true,\n    });"
if old in text:
    text = text.replace(old, new, 1)
if "const shouldPreAuthenticate = !settings.merged.security.auth.useExternal" not in text:
    text = text.replace("    adminControlsListner.setConfig(partialConfig);\n", "    adminControlsListner.setConfig(partialConfig);\n    const sandboxConfig = await loadSandboxConfig(settings.merged, argv);\n    const shouldPreAuthenticate = !settings.merged.security.auth.useExternal &&\n        (!!sandboxConfig || !process.env['GEMINI_CLI_NO_RELAUNCH']);\n", 1)
    text = text.replace("    if (!settings.merged.security.auth.useExternal) {\n", "    if (shouldPreAuthenticate) {\n", 1)
    text = text.replace("        const sandboxConfig = await loadSandboxConfig(settings.merged, argv);\n", "", 1)
cli_gemini.write_text(text)
PY

echo "patched $ROOT"
