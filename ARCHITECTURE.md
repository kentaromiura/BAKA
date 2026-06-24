# BAKA — Architecture

## Overview

BAKA is a diff review tool that displays current git changes and allows commenting on individual lines. It integrates with an external `pi` CLI for AI-powered code review, vulnerability checking, feature planning, and commit workflows. The application is split into two layers:

— **APP** (Odin) — Native backend that manages the webview, runs git commands, orchestrates pi-driven workflows, and bundles the UI at runtime
— **UI** (ReScript + React) — Frontend rendered inside an embedded webview, providing diff visualization, inline commenting, project file browsing, commit selection, and AI review integration

### Directory Structure

```
BAKA/
├── ARCHITECTURE.md              # This file
├── README.md                    # Build notes
├── Makefile                     # Top-level build orchestration
├── SCREEN/                      # Screenshots
├── webview/                     # Git submodule: Sergio Benitez's cross-platform webview (C/C++)
├── APP/                         # Native backend (Odin)
│   ├── index.odin               # Main entry point + IPC handlers (~1200 lines)
│   ├── ask_pi.odin              # AI review integration with pi CLI (~950 lines)
│   ├── watchman_watcher.odin    # Watchman filesystem watcher (~470 lines)
│   ├── encoding_base32/         # Base32 encoding utility (unused?)
│   └── webview-odin/            # Git submodule — Odin FFI bindings for libwebview
├── UI/bakaui/                   # Frontend (ReScript + React)
│   ├── src/                     # ReScript source files
│   │   ├── App.res              # Root layout, tab navigation, review summary
│   │   ├── CommentBox.res       # Inline comment editor
│   │   ├── CommitView.res       # Line-granular commit selection UI (~600 lines)
│   │   ├── Diffs.res            # FFI to @pierre/diffs + utility helpers
│   │   ├── FileViewer.res       # Full-file viewer with modal/embedded modes
│   │   ├── Footer.res           # Demo footer (not mounted in App)
│   │   ├── Html.res             # CSS-in-JS templates, cx() composition helper
│   │   ├── InlineComment.res    # Per-file diff + inline comments + AI replies
│   │   ├── Ipc.res              # IPC bridge to all Odin handlers
│   │   ├── Main.res             # Entry point, mount React
│   │   ├── Markdown.mjs         # markdown-it integration for rendered output
│   │   ├── NewFeatureView.res   # Feature/bug-fix planning + apply UI (~280 lines)
│   │   ├── ProjectView.res      # Full project file tree viewer (~130 lines)
│   │   ├── RegisterLanguages.mjs# Custom language registration (ReScript grammar)
│   │   ├── ShikiTheme.mjs       # Theme color extraction from Shiki themes
│   │   ├── State.res            # All Jotai atoms + types
│   │   └── Trees.res            # FFI to @pierre/trees for file tree sidebar
│   ├── assets/fonts/            # Ioskeley Mono font (embedded as base64)
│   ├── build.mjs                # esbuild bundler entry point
│   ├── babel.transform.extractStyles.js  # Babel plugin for CSS template extraction
│   └── out.js / out.css         # Bundled output (read by Odin at compile time)
└── build/                       # Build artifacts (webview lib, BAKA binary)
```

## Layer Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  APP (Odin)                                                                 │
│                                                                              │
│  main()                                                                      │
│   ├── webview.bind("getPatch", handler)                                      │
│   │    └── getCurrentGitPatch() → git diff HEAD + untracked files            │
│   ├── webview.bind("getFilePatch", handler)                                  │
│   │    └── getFilePatchFromGit() → -U999999 full-context diff                │
│   ├── webview.bind("getProjectFiles", handler)                               │
│   │    └── git ls-files --cached --others --exclude-standard                 │
│   ├── webview.bind("getWatcherEvents", handler)                              │
│   │    └── read_watcher_events() → shared event file                         │
│   ├── webview.bind("askPi", handler)                                         │
│   │    └── process_ask_pi() → pi --mode json, [REPLY:key] parsing            │
│   ├── webview.bind("askPiWithDiff", handler)                                 │
│   │    └── ask with caller-provided full-file diff                           │
│   ├── webview.bind("startFullReview", handler)                               │
│   │    └── process_full_review() → batched pi review, structured output      │
│   ├── webview.bind("applyReviewSuggestion", handler)                         │
│   │    └── generate patch + apply + validate (with repair loop)              │
│   ├── webview.bind("commitSelection", handler)                               │
│   │    └── git reset --mixed HEAD → git apply --cached → git commit          │
│   ├── webview.bind("createFeaturePlan", worker→thread)                       │
│   │    └── process_create_feature_plan() → pi architect prompt               │
│   ├── webview.bind("applyFeaturePlan", worker→thread)                        │
│   │    └── process_apply_feature_plan() → generate + apply patch             │
│   ├── Embed out.js + out.css (#load, compile time)                           │
│   ├── Build HTML (inject JS/CSS + font base64 + watcher polling)            │
│   ├── start_repo_watcher()                                                   │
│   └── webview.create / set_html / run                                        │
└─────────────┬────────────────────────────────────────────────────────────────┘
              │  webview.bind IPC (JSON over promises)
              │  UI calls getPatch() → Odin returns {result: string}
              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  UI (ReScript → React in Webview)                                           │
│                                                                              │
│  Main.res          Entry point, mount React                                  │
│  State.res         All Jotai atoms + shared types                            │
│  App.res           Tab navigation (Review/Project/Commit/New Feature),       │
│                    review summary bar, file tree sidebar                     │
│  Ipc.res           IPC bridge — bindings for all 10 native handlers          │
│  Diffs.res         FFI to @pierre/diffs + parsePatchFiles utility            │
│  InlineComment     Per-file diff with inline comments and AI replies         │
│  CommentBox        Inline comment editor widget                              │
│  FileViewer        Full-file viewer (modal or embedded)                      │
│  CommitView        Line-granular commit selection, patch builder             │
│  ProjectView       Full project file tree + file viewer integration          │
│  NewFeatureView    Feature/bug-fix description → plan → apply workflow       │
│  Trees.res         FFI to @pierre/trees for collapsible file trees           │
│  Markdown.mjs      markdown-it rendering for AI output                       │
│  Html.res          CSS-in-JS templates + cx() class composition              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## APP (Odin Backend)

### `APP/index.odin` — Entry Point (~1200 lines)

Main entry point that creates the webview, binds 10 IPC handlers, embeds UI assets at compile time, and enters the event loop.

**IPC Handlers:**

| Handler | Worker? | Purpose |
|---|---|---|
| `getPatch` | No | Returns `git diff HEAD` + untracked file diffs |
| `getFilePatch` | No | Full-context (`-U999999`) diff for a single file |
| `getProjectFiles` | No | Lists all tracked + untracked files via `git ls-files` |
| `getWatcherEvents` | No | Reads watcher events from shared temp file |
| `askPi` | Yes (threaded) | Sends inline comments to pi for review |
| `askPiWithDiff` | Yes (threaded) | Same as askPi but with caller-provided diff |
| `startFullReview` | No | Triggers full code/vulnerability review on entire working tree |
| `applyReviewSuggestion` | No | Generates, applies, and validates a suggestion patch via pi |
| `commitSelection` | No | Commits selected lines/files from the current diff |
| `createFeaturePlan` | Yes (threaded) | Architect-mode prompt → implementation plan |
| `applyFeaturePlan` | Yes (threaded) | Generate + apply feature/fix patch to working tree |

**Asset Embedding:**
- `js_content := #load("../UI/bakaui/out.js", string)` — Bundled ReScript JavaScript
- `css_content := #load("../UI/bakaui/out.css", string)` — Extracted CSS
- Font embedded as base64: Ioskeley Mono `.woff2` → base64 → `@font-face` in HTML

**HTML Construction:** The HTML document injects JS/CSS inline, embeds the font as a data URI, sets `__BAKA_VERBOSE__` for debug mode, and includes inline JavaScript for watcher event polling (500ms interval) and custom DOM events (`baka-watcher-log`, `baka-repo-changed`).

### `APP/ask_pi.odin` — AI Review Integration (~950 lines)

Comprehensive integration with the external `pi` CLI tool. Handles:

1. **Inline comment review** (`process_ask_pi`) — Sends user comments to pi, parses `[REPLY:key]` blocks
2. **Full code/vulnerability review** (`process_full_review`) — Batches diff into chunks (~24KB), runs pi with structured output parsing (`[SUMMARY]`, `[FINDING:key]`)
3. **Suggestion application** (`process_apply_suggestion`) — Generates a patch from a suggestion, applies it via `git apply`, validates with pi (with one repair attempt and rollback on failure)
4. **Feature planning** (`create_feature_plan` / `apply_feature_plan`) — Architect-mode prompts for implementation plans

**pi CLI Integration:**
- Runs `pi --mode json @prompt_file.txt` (tools disabled for reviews, enabled for feature work)
- Streams JSON output via pipe, parses `message_update` delta events in real-time
- Extracts final text from `turn_end`/`message_end` events as the definitive response
- Helper functions: `strip_pi_tool_call_blocks`, `extractPiOutputText`, `writeTempFile`

**Structured Review Output:** The full review uses a strict format with `[FINDING:path|side|line]` markers, severity levels, actionable flags, and concrete suggestions — all parseable by the UI.

### `APP/watchman_watcher.odin` — Watchman Filesystem Watcher (~470 lines)

Complete Watchman client implementation in Odin using Unix domain sockets. Key components:

| Function/Type | Purpose |
|---|---|
| `Watchman_Client` struct | Holds a Unix socket FD and receive buffer |
| `watchman_installed()` | Checks if `watchman` CLI is available via `command -v` |
| `watchman_sockname()` | Runs `watchman get-sockname`, parses JSON for socket path |
| `watchman_client_connect()` | Creates Unix domain socket, connects to Watchman |
| `watchman_client_send/receive_line()` | Line-delimited JSON communication over socket |
| `watch_repo_worker()` | Main watcher loop — `watch-project` + `subscribe`, reads events |
| `start_repo_watcher()` | Spawns `watch_repo_worker` in a background thread |

**Watcher event data flow (3-layer IPC chain):**
```
Watchman daemon → Unix socket → Odin worker thread
    → /tmp/baka_watcher_event.json (shared file)
        → Odin main thread (polled via getWatcherEvents IPC)
            → JS polling interval (500ms, inline in HTML)
                → React diff reload (polls __bakaDiffReloadRequestCount every 250ms)
```

### `APP/webview-odin/` — Webview Binding

Git submodule pointing to [thechampagne/webview-odin](https://github.com/thechampagne/webview-odin). Provides Odin FFI bindings for the cross-platform webview library.

**Currently used APIs:**
- `webview.bind` — Exposes IPC handlers to JS as async functions returning JSON promises
- `webview.ret` — Returns JSON responses (`{result: string}` or `{error: string}`)
- `webview.dispatch` — Bounces worker thread results back to main thread for safe `ret` calls
- `webview.eval` — Pushes debug logs to webview console from workers

### Build Process

The top-level Makefile orchestrates a three-stage build:

```sh
make           # Build everything (UI → libwebview → BAKA binary)
make ui        # Build only the ReScript/esbuild UI bundle
make run       # Build and execute, pass ARGS for --verbose /path/to/repo
make clean     # Remove all generated artifacts
```

**Build stages:**
1. `yarn install` in UI/bakaui (frozen lockfile)
2. `rescript build` → `.res.mjs` files, then esbuild bundles to `out.js`
3. CMake builds webview as a shared library (`libwebview.dylib` / `.so`)
4. Odin compiler embeds JS/CSS via `#load`, links against libwebview with rpath

## UI (ReScript Frontend)

### IPC Bridge — `Ipc.res`

The UI communicates with Odin through **bound webview functions** exposed as async JavaScript APIs. All handlers follow the pattern of taking a JSON-string argument and returning a JSON-string promise, parsed into typed ReScript responses.

| Method | Native Handler | Request Type | Response Type |
|---|---|---|---|
| `callGetPatch()` | `getPatch` | `{}` | `string` (unified diff) |
| `callGetFilePatch(path)` | `getFilePatch` | `path: string` | `string` (full-context diff) |
| `callGetProjectFiles()` | `getProjectFiles` | `{}` | `array<string>` (file paths) |
| `callAskPi(comments)` | `askPi` | `array<askPiRequest>` | `array<askPiReply>` |
| `callAskPiWithDiff(diff, comments)` | `askPiWithDiff` | `{diff: string, comments}` | `array<askPiReply>` |
| `callStartFullReview(kind)` | `startFullReview` | `{kind: "code"|"vulnerability"}` | `{summary, findings}` |
| `callApplyReviewSuggestion(req)` | `applyReviewSuggestion` | `{commentKey, suggestion}` | `string` (status) |
| `callCreateFeaturePlan(desc)` | `createFeaturePlan` | `description: string` | `{plan: string}` |
| `callApplyFeaturePlan(req)` | `applyFeaturePlan` | `{description, plan}` | `string` (status) |
| `callCommitSelection(req)` | `commitSelection` | `{message, body, patch}` | `string` (git output) |

### Build Pipeline

```
.res files → ReScript compiler → .res.mjs files
                              ↓
              esbuild bundles Main.res.mjs → out.js (+ babel CSS extraction → out.css)
```

— **`rescript.json`** — Compiles to ES modules, in-source with `.res.mjs` suffix, JSX v4
— **`build.mjs`** — esbuild entry point at `src/Main.res.mjs`, babel plugin for CSS template literals, minifies in production
— Output: single `out.js` + extracted `out.css` file read by the Odin app via `#load`

### State Management — All Atoms in `State.res`

All Jotai atoms are centralized in **`UI/bakaui/src/State.res`**:

| Atom | Type | Purpose |
|---|---|---|
| `commentsAtom` | `Js.Dict.t<commentData>` | Inline comments keyed by `fileName\|side\|lineNumber`, with `aiReply` lifecycle state (`AiIdle` → `AiStreaming(string)` → `AiDone(string)` / `AiError(string)`) |
| `reviewSuggestionsAtom` | `Js.Dict.t<reviewSuggestion>` | Full review findings with severity, actionable flag, suggestion text, and apply state |
| `featurePlanAtom` | `featurePlanPhase` | Feature/bug-fix workflow phase (`Idle` → `GeneratingPlan` → `PlanReady(string)` → `Applying` → `ApplyDone/Error`) |
| `featureDescriptionAtom` | `string` | User's feature/bug description text |
| `isDarkAtom` | `bool` | Light/dark theme toggle state |
| `themeColorsAtom` | `option<loadedThemes>` | Extracted UI colors from loaded Shiki themes (light + dark) |

Default color palettes (`defaultUiColors`, `lightDefaultUiColors`) are also defined here as fallbacks before Shiki themes load. The `uiColors` record type has 21 color fields for consistent theming across all components.

### Tab Views — Four Modes in App.res

The root `App` component provides tab-based navigation between four views:

| View | Component | Description |
|---|---|---|
| **Review** (default) | Inline diff virtualizer + file tree sidebar | The primary diff viewer with inline comments and AI review buttons |
| **Project** | `ProjectView` | Full project file tree + embedded file viewer for any tracked/untracked file |
| **Commit** | `CommitView` | Line-granular commit selection — click lines to include/exclude, then commit selected changes |
| **New Feature** | `NewFeatureView` | Describe a feature/bug → AI generates implementation plan → Apply plan as patch |

### Review Summary Bar

The review summary bar (shown in Review and Project modes) displays the results of full code/vulnerability reviews. It shows:
- The review label ("Review" or "Vulnerability Check")
- Pi's summary text from the last run
- Finding count and actionable suggestion count (e.g., "3 finding(s), 2 actionable.")

### Styling — CSS-in-JS via Tagged Templates

All UI styling uses **CSS-in-JS via tagged template literals** from `Html.res`:

— **`Html.css\`...\``** — Produces a unique class name at build time (babel transforms the templates). Supports interpolation with `${colors.field}` for dynamic theme colors.
— **`Html.cx([class1, class2])`** — Composes multiple style strings into a single `className`.

Style modules are co-located inside components (e.g., `InlineComment.res` has a `module Styles = { ... }` block). The entire UI is themed via the `uiColors` record passed down from App.

### Key Integrations

— **`@pierre/diffs`** — Parses git diff strings into structured patch data; provides `FileDiff` React component with syntax highlighting and virtualization
— **`@pierre/diffs/react`** — React bindings for `FileDiff` (with annotations) and `Virtualizer`
— **`@pierre/trees`** / **`Trees.res`** — Collapsible file tree sidebar used in both Review and Project views
— **Shiki** — Syntax highlighting engine; themes are loaded asynchronously and their colors extracted to drive the entire UI palette
— **markdown-it** (via `Markdown.mjs`) — Renders markdown output from AI responses in review summaries and finding details

### Data Flow

```
Odin:  webview.bind("getPatch", handle_get_patch) + set_html + run
                                      ↓
JS:    App mounts → useEffect → Ipc.callGetPatch() → Promise
                                      ↓
Odin:  getCurrentGitPatch() → git diff HEAD → JSON {result}
                                      ↓
JS:    parsePatchFiles(rawPatch) → PatchReady state → FileDiff components
                                      ↓
User clicks line → toggleComment → Jotai commentsAtom update → CommentBox render

Full review flow:
App header "Code Review" button → Ipc.callStartFullReview(CodeReview)
  → Odin process_full_review() → batch diff into ~24KB chunks
    → runPiPrompt (batch by batch, --no-tools)
      → parse [SUMMARY] + [FINDING:key] blocks from output
        → return {summary, findings} to UI
          → Insert findings into commentsAtom + reviewSuggestionsAtom

Commit flow:
CommitView line click → toggle excludedLines state
  → buildSelectedPatch() generates unified diff from selected lines
    → Ipc.callCommitSelection({message, body, patch})
      → Odin git reset --mixed HEAD → git apply --cached → git commit
        → onCommitted callback → re-fetch diff

Feature plan flow:
NewFeatureView "Create Plan" → Ipc.callCreateFeaturePlan(description)
  → Odin create_feature_plan() (threaded worker + webview.dispatch)
    → runPiPrompt with architect prompt, strip <pi_tool_call> blocks
      → return {plan} to UI → PlanReady state
        → User clicks "Start Applying" → Ipc.callApplyFeaturePlan({description, plan})
          → Odin apply_feature_plan() (threaded worker)
            → buildApplyFeaturePlanPrompt + runPiPrompt (with tools enabled)
              → extract [PATCH] block → write temp file → git apply
                → return status to UI

Watcher flow:
Watchman → Odin worker → /tmp/baka_watcher_event.json → Odin main thread (getWatcherEvents IPC)
    → JS polling (500ms) → DOM event baka-repo-changed → React polling (250ms) → re-fetch patch
```

## Dependencies

### APP (Odin)
| Package | Purpose |
|---|---|
| `webview-odin` (submodule) | Cross-platform webview bindings |
| `pi` CLI (external) | AI-powered code review, vulnerability checking, feature planning |
| `watchman` (external) | Filesystem change detection via Unix domain sockets |

### UI (ReScript/JS)
| Package | Purpose |
|---|---|
| `react` / `react-dom` 19.x | UI framework |
| `jotai` + `@fattafatta/rescript-jotai` | Atomic state management |
| `@pierre/diffs` + `@pierre/diffs/react` | Diff parsing, rendering, virtualization |
| `@pierre/trees` / `Trees.res` | Collapsible file tree sidebar |
| `shiki` (via @pierre/diffs) | Syntax highlighting engine |
| `markdown-it` + `@shikijs/markdown-it` | Markdown rendering for AI output |
| `@emotion/css` (via babel plugin) | CSS template literal runtime extraction |
