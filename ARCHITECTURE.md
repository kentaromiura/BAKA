# BAKA — Architecture

## Overview

BAKA is a diff review tool that displays current git changes and allows commenting on individual lines. It is split into two layers:

— **APP** (Odin) — Native backend that manages the webview, runs git commands, and bundles the UI at runtime
— **UI** (ReScript + React) — Frontend rendered inside an embedded webview, providing diff visualization and inline commenting

### Directory Structure

```
BAKA/
├── .gitmodules                  # Submodule: APP/webview-odin
├── ARCHITECTURE.md              # This file
├── README.md                    # Build notes
├── STATUS.md                    # Known issues and plans
├── SCREEN/                      # Screenshots
├── APP/                         # Native backend (Odin)
│   ├── index.odin               # Main entry point
│   ├── ask_pi.odin              # AI review integration
│   ├── watchman_watcher.odin    # Watchman filesystem watcher
│   ├── out.js / out.css         # Bundled UI (embedded at compile time)
│   ├── libwebview.dylib / .so   # Webview shared libraries
│   └── webview-odin/            # Git submodule — Odin FFI bindings
├── UI/                          # Frontend (ReScript + React)
│   └── bakaui/
│       └── src/                 # ReScript source files
├── APP.zip                      # Archive
└── UI.zip                       # Archive
```

## Layer Diagram

```
┌─────────────────────────────────────────────────────┐
│  APP (Odin)                                          │
│                                                      │
│  main()                                              │
│   ├── webview.bind("getPatch", handler)               │
│   │    └── getCurrentGitPatch() → git diff HEAD       │
│   ├── webview.bind("getFilePatch", handler)           │
│   │    └── getFilePatchFromGit() → full file diff     │
│   ├── webview.bind("getWatcherEvents", handler)       │
│   │    └── read_watcher_events() → event file         │
│   ├── webview.bind("askPi", handler)                  │
│   │    └── run pi CLI for AI review                   │
│   ├── webview.bind("askPiWithDiff", handler)          │
│   ├── Embed out.js + out.css (#load, compile time)   │
│   ├── Build HTML (inject JS/CSS + watcher polling)   │
│   ├── start_repo_watcher()                            │
│   └── webview.create / set_html / run                │
└──────────────────┬──────────────────────────────────┘
                   │  webview.bind IPC (JSON over promises)
                   │  UI calls getPatch() → Odin returns {result: string}
                   ▼
┌─────────────────────────────────────────────────────┐
│  UI (ReScript → React in Webview)                    │
│                                                      │
│  Main.res        Entry point, mount React            │
│  State.res       All Jotai atoms                     │
│  App.res         Root layout + virtualizer + watcher │
│  Ipc.res         IPC bridge to Odin                  │
│  Diffs.res       FFI to @pierre/diffs                │
│  InlineComment   Per-file diff + comments            │
│  Html.res        CSS-in-JS helpers                   │
│  ShikiTheme.mjs  Theme color extraction              │
└─────────────────────────────────────────────────────┘
```

## APP (Odin Backend)

### `APP/index.odin` — Entry Point (488 lines)

1. **Process CLI argument** — optionally `chdir` to a target directory
2. **Create webview** — Creates a debug webview window via `webview.create(true, nil)`
3. **Set window properties** — Title "BAKA", size 960x720
4. **Bind 5 IPC handlers** via `webview.bind`:
   - `getPatch` — Returns `git diff HEAD` including untracked files
   - `getFilePatch` — Full-context diff for a single file (with path traversal protection via `isPathSafe`)
   - `getWatcherEvents` — Reads watcher events from the shared temp file
   - `askPi` — Sends inline comments to external AI CLI (`pi`) for review
   - `askPiWithDiff` — Same as `askPi` but with a caller-provided diff
5. **Build HTML payload** — Constructs an HTML document that injects the bundled ReScript JavaScript and CSS inline, plus inline JavaScript for watcher polling
6. **Launch webview** — Sets HTML, starts repo watcher, enters event loop via `webview.run(w)` (blocks until window closes)

Helper functions:
- `getCurrentGitPatch()` — Runs `git --no-pager diff HEAD` plus untracked file diffs via `os2.process_exec`
- `getFilePatchFromGit()` — Full-context diff for a single file with `isPathSafe` guards
- `getRepoRoot()` — Resolves git working tree root
- `parseFilePatchRequest()` — Parses JSON array from webview IPC

### `APP/ask_pi.odin` — AI Review Integration

Calls an external `pi` CLI tool for AI-powered code review. Used by the `askPi` and `askPiWithDiff` IPC handlers.

### `APP/watchman_watcher.odin` — Watchman Filesystem Watcher (471 lines)

Complete Watchman client implementation in Odin. Key components:

| Function/Type | Purpose |
|---|---|
| `Watchman_Client` struct | Holds a Unix socket FD and receive buffer |
| `watchman_installed()` | Checks if `watchman` CLI is available (`command -v`) |
| `watchman_sockname()` | Runs `watchman get-sockname`, parses JSON for socket path |
| `watchman_client_connect()` | Creates Unix domain socket, connects to Watchman |
| `watchman_client_send()` | Sends JSON commands over socket |
| `watchman_client_receive_line()` | Reads line-delimited JSON responses |
| `watchman_read_ok_response()` | Reads/validates a command response |
| `watch_repo_worker()` | Main watcher loop — `watch-project` + `subscribe`, reads events |
| `start_repo_watcher()` | Detects repo root, spawns `watch_repo_worker` in background thread |
| `dispatch_repo_changed_event()` | Writes JSON event to `/tmp/baka_watcher_event.json` |
| `read_watcher_events()` | Reads/removes event file (called via IPC on main thread) |
| `is_git_internal_path()` | Filters out `.git/` paths |
| `format_non_git_files()` | Formats changed paths for logging (max 5) |

**Watcher event data flow (3-layer IPC chain):**

```
Watchman daemon → Unix socket → Odin worker thread
    → /tmp/baka_watcher_event.json (shared file)
        → Odin main thread (polled via getWatcherEvents IPC)
            → JS polling interval (500ms, inline in HTML)
                → React diff reload (polls __bakaDiffReloadRequestCount every 250ms)
```

The inline JavaScript in `index.odin` installs event listeners for `baka-watcher-log` and `baka-repo-changed` custom DOM events, implements `__bakaShowRepoChangeNotice` (a floating "See latest changes" button), and polls `getWatcherEvents` every 500ms.

### `APP/webview-odin/` — Webview Binding

Git submodule pointing to [thechampagne/webview-odin](https://github.com/thechampagne/webview-odin). Provides Odin FFI bindings for the cross-platform webview library (create, destroy, set_html, bind, eval, ret, etc.).

**Currently used APIs:**
- `webview.bind` — Exposes IPC handlers to JS as async functions returning JSON promises
- `webview.ret` — Returns JSON responses (`{result: string}` or `{error: string}`)
- `webview.eval` — Available but not yet used (could push events from Odin → UI)

### Build Process

No Makefile exists. The project uses the Odin compiler directly with `#config(SHARED, true)` and `#config(LOCAL, true)` compile-time flags:
- On macOS: use the provided `libwebview.dylib`, compile with `SHARED=true LOCAL=true`
- On Linux: manually compile the webview library, copy `.so` files

## UI (ReScript Frontend)

### IPC Bridge — `Ipc.res`

The UI communicates with Odin through **bound webview functions** exposed as async JavaScript APIs:

— **`getPatch_raw`** / **`callGetPatch()`** — External binding to the global `getPatch()` function. Takes a JSON string argument, returns a JSON string promise. Wrapper parses response and returns the `result` field.
— **`getWatcherEvents`** — Binding for polling watcher events (though primary watcher polling is done via inline JS in the HTML).

This pattern supports extending IPC with new handlers (e.g., `saveComment`, `watchFiles`) by adding a corresponding `webview.bind` in Odin and an external binding in ReScript.

### Build Pipeline

```
.res files → ReScript compiler → .res.mjs files
                              ↓
              esbuild bundles Main.res.mjs → out.js
```

— **`rescript.json`** — Compiles to ES modules, in-source with `.res.mjs` suffix, JSX v4
— **`build.mjs`** — esbuild entry point at `src/Main.res.mjs`, babel plugin for CSS template literals, minifies in production
— Output: single `out.js` file read by the Odin app

### State Management — All Atoms in `State.res`

All Jotai atoms are centralized in **`UI/bakaui/src/State.res`**:

| Atom | Type | Purpose |
|---|---|---|
| `commentsAtom` | `Js.Dict.t<commentData>` | Inline comments keyed by `fileName\|side\|lineNumber` |
| `isDarkAtom` | `bool` | Light/dark theme toggle state |
| `themeAtom` | `themeType` | Shiki theme names (`rose-pine-dawn` / `tokyo-night`) |
| `themeColorsAtom` | `option<loadedThemes>` | Extracted UI colors from loaded Shiki themes |
| `counter` | `int` | Demo atom (used by Footer) |

Default color palettes (`defaultUiColors`, `lightDefaultUiColors`) are also defined here as fallbacks before Shiki themes load.

### Styling — `Html.css` Templates + `Html.cx` Composition

All UI styling uses **CSS-in-JS via tagged template literals** from `Html.res`:

— **`Html.css\`...\``** — Tagged template literal that produces a unique class name at build time (babel transforms the templates). Supports interpolation with `${values}` for dynamic colors.
— **`Html.cx([class1, class2])`** — Composes multiple style strings into a single `className` attribute by joining with spaces. Used to layer base styles + hover/active variants.

Style modules are co-located inside components (e.g., `InlineComment.res` has a `module Styles = { ... }` block). This keeps styling close to usage while remaining reusable via `Html.cx`.

### Component Hierarchy

```
Main.res (mount)
 └── App.res (root layout)
      ├── Header with theme toggle button
      ├── Watcher polling (polls __bakaDiffReloadRequestCount every 250ms)
      └── Diffs.Virtualizer
           └── InlineComment.make (per file diff)
                ├── Diffs.FileDiff.makeRaw (@pierre/diffs/react binding)
                └── CommentBox.make (inline comment editor, rendered via renderAnnotation)

Footer.res (standalone, not currently mounted in App)
```

### Key Integrations

— **`@pierre/diffs`** — Parses git diff strings into structured patch data; provides `FileDiff` React component with syntax highlighting and virtualization
— **`@pierre/diffs/react`** — React bindings for `FileDiff` (with annotations) and `Virtualizer`
— **Shiki** — Syntax highlighting engine; themes are loaded asynchronously and their colors extracted to drive the entire UI palette
— **Custom language registration** — ReScript grammar (`rescript.tmLanguage.json`) is registered via `RegisterLanguages.mjs` so `.res`/`.resi` files get proper syntax highlighting in diffs

### Data Flow (Current)

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

Watcher flow:
Watchman → Odin worker → /tmp/baka_watcher_event.json → Odin main thread (getWatcherEvents IPC)
    → JS polling (500ms) → DOM event baka-repo-changed → React polling (250ms) → re-fetch patch
```

## Dependencies

### APP (Odin)
— `webview-odin` — Cross-platform webview bindings (git submodule)

### UI (ReScript/JS)
| Package | Purpose |
|---|---|
| `react` / `react-dom` | UI framework |
| `jotai` + `@fattafatta/rescript-jotai` | Atomic state management |
| `@pierre/diffs` + `@pierre/diffs/react` | Diff parsing, rendering, virtualization |
| `shiki` (via @pierre/diffs) | Syntax highlighting |
| `@emotion/css` (via babel plugin) | CSS template literal runtime |
