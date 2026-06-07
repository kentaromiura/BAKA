# BAKA — Architecture

## Overview

BAKA is a diff review tool that displays current git changes and allows commenting on individual lines. It is split into two layers:

- **APP** (Odin) — Native backend that manages the webview, runs git commands, and bundles the UI at runtime
- **UI** (ReScript + React) — Frontend rendered inside an embedded webview, providing diff visualization and inline commenting

## Layer Diagram

```
┌─────────────────────────────────────────────┐
│  APP (Odin)                                  │
│                                              │
│  main()                                      │
│   ├── webview.bind("getPatch", handler)      │
│   │    └── getCurrentGitPatch() → git diff   │
│   │         HEAD → JSON response             │
│   ├── Embed out.js + out.css (#load, compile time) │
│   ├── Build HTML (inject JS/CSS only)        │
│   └── webview.create / set_html / run        │
└──────────────┬──────────────────────────────┘
               │  webview.bind IPC (JSON over promises)
               │  UI calls getPatch() → Odin returns {result: string}
               ▼
┌─────────────────────────────────────────────┐
│  UI (ReScript → React in Webview)            │
│                                              │
│  Main.res        Entry point, mount React    │
│  State.res       All Jotai atoms             │
│  App.res         Root layout + virtualizer   │
│  Ipc.res         IPC bridge to Odin          │
│  Diffs.res       FFI to @pierre/diffs        │
│  InlineComment   Per-file diff + comments    │
│  Html.res        CSS-in-JS helpers           │
│  ShikiTheme.mjs  Theme color extraction      │
└─────────────────────────────────────────────┘
```

## APP (Odin Backend)

### `APP/index.odin` — Entry Point

1. **Create webview** — Creates a debug webview window via `webview.create(true, nil)`
2. **Bind IPC handler** — Registers `getPatch` via `webview.bind(w, "getPatch", handle_get_patch, nil)`. When the UI calls `getPatch({})`, Odin runs `getCurrentGitPatch()` and returns a JSON response `{result: <diff string>}` through `webview.ret`
3. **Fetch git diff** — `getCurrentGitPatch()` runs `git --no-pager diff HEAD` via `os2.process_exec`, capturing stdout as a string (exit code/stderr currently ignored)
4. **Embed bundled UI** — `js_content` and `css_content` are loaded at compile time via Odin's `#load("path", string) or_else ""`, baking the files directly into the binary
5. **Build HTML payload** — Constructs an HTML document that injects the bundled ReScript JavaScript and CSS inline (no data embedded — patch is fetched on-demand via IPC)
6. **Launch webview** — Sets title/size (960x720), loads HTML, enters event loop

### `APP/webview-odin/` — Webview Binding

Git submodule pointing to [thechampagne/webview-odin](https://github.com/thechampagne/webview-odin). Provides Odin FFI bindings for the cross-platform webview library (create, destroy, set_html, bind, eval, ret, etc.).

**Currently used APIs:**
- `webview.bind` — Exposes `getPatch` to the JS side as an async function that returns a JSON promise
- `webview.ret` — Returns JSON responses (`{result: string}` or `{error: string}`) from bound handlers
- `webview.eval` — Available but not yet used (could push events from Odin → UI)

## UI (ReScript Frontend)

### IPC Bridge — `Ipc.res`

The UI communicates with Odin through **bound webview functions** exposed as async JavaScript APIs:

- **`getPatch_raw`** — External binding to the global `getPatch()` function (registered by Odin's `webview.bind`). Takes a JSON string argument and returns a JSON string promise.
- **`callGetPatch()`** — Wrapper that calls `getPatch_raw("{}")`, parses the JSON response, and either returns the `result` field or throws on `error`. Used by `App.res` to fetch the git diff on mount.

This pattern supports extending IPC with new handlers (e.g., `saveComment`, `watchFiles`) by adding a corresponding `webview.bind` in Odin and an external binding in ReScript.

### Build Pipeline

```
.res files → ReScript compiler → .res.mjs files
                              ↓
              esbuild bundles Main.res.mjs → out.js
```

- **`rescript.json`** — Compiles to ES modules, in-source with `.res.mjs` suffix, JSX v4
- **`build.mjs`** — esbuild entry point at `src/Main.res.mjs`, babel plugin for CSS template literals, minifies in production
- Output: single `out.js` file read by the Odin app

### State Management — All Atoms in `State.res`

All Jotai atoms are centralized in **`UI/bakaui/src/State.res`**:

| Atom | Type | Purpose |
|------|------|---------|
| `commentsAtom` | `Js.Dict.t<commentData>` | Inline comments keyed by `fileName\|side\|lineNumber` |
| `isDarkAtom` | `bool` | Light/dark theme toggle state |
| `themeAtom` | `themeType` | Shiki theme names (`rose-pine-dawn` / `tokyo-night`) |
| `themeColorsAtom` | `option<loadedThemes>` | Extracted UI colors from loaded Shiki themes |
| `counter` | `int` | Demo atom (used by Footer) |

Default color palettes (`defaultUiColors`, `lightDefaultUiColors`) are also defined here as fallbacks before Shiki themes load.

### Styling — `Html.css` Templates + `Html.cx` Composition

All UI styling uses **CSS-in-JS via tagged template literals** from `Html.res`:

- **`Html.css\`...\``** — Tagged template literal that produces a unique class name at build time (babel transforms the templates). Supports interpolation with `${values}` for dynamic colors.
- **`Html.cx([class1, class2])`** — Composes multiple style strings into a single `className` attribute by joining with spaces. Used to layer base styles + hover/active variants.

Style modules are co-located inside components (e.g., `InlineComment.res` has a `module Styles = { ... }` block). This keeps styling close to usage while remaining reusable via `Html.cx`.

### Component Hierarchy

```
Main.res (mount)
 └── App.res (root layout)
      ├── Header with theme toggle button
      └── Diffs.Virtualizer
           └── InlineComment.make (per file diff)
                ├── Diffs.FileDiff.makeRaw (@pierre/diffs/react binding)
                └── CommentBox.make (inline comment editor, rendered via renderAnnotation)

Footer.res (standalone, not currently mounted in App)
```

### Key Integrations

- **`@pierre/diffs`** — Parses git diff strings into structured patch data; provides `FileDiff` React component with syntax highlighting and virtualization
- **`@pierre/diffs/react`** — React bindings for `FileDiff` (with annotations) and `Virtualizer`
- **Shiki** — Syntax highlighting engine; themes are loaded asynchronously and their colors extracted to drive the entire UI palette
- **Custom language registration** — ReScript grammar (`rescript.tmLanguage.json`) is registered via `RegisterLanguages.mjs` so `.res`/`.resi` files get proper syntax highlighting in diffs

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
```

## Dependencies

### APP (Odin)
- `webview-odin` — Cross-platform webview bindings (git submodule)

### UI (ReScript/JS)
| Package | Purpose |
|---------|---------|
| `react` / `react-dom` | UI framework |
| `jotai` + `@fattafatta/rescript-jotai` | Atomic state management |
| `@pierre/diffs` + `@pierre/diffs/react` | Diff parsing, rendering, virtualization |
| `shiki` (via @pierre/diffs) | Syntax highlighting |
| `@emotion/css` (via babel plugin) | CSS template literal runtime |
