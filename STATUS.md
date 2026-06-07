# BAKA — Status & Known Issues

## Current State: Working POC

The core flow works: Odin fetches `git diff HEAD`, embeds it in a webview, ReScript renders syntax-highlighted diffs with inline commenting. This document tracks known limitations and planned improvements.

---

## Bidirectional IPC

**Status:** Partially Implemented

UI → Odin: `Ipc.callGetPatch()` works via `webview.bind("getPatch", ...)` — the UI fetches the git diff on mount through a proper JSON-based IPC channel.

Odin → UI: **Not implemented yet.** There's no filesystem watcher, so Odin doesn't notify the webview when tracked files change. The diff is fetched once on mount and never refreshed.

### What Still Needs Work
- **Filesystem watcher** — Odin should watch for file changes and push updated diffs to the webview (e.g., via `webview.eval` or a new bound callback)
- **Comment persistence** — No IPC handler exists to persist comments back to the native layer (e.g., writing to a JSON file alongside the repo)
- This enables a proper review workflow where comments survive app restarts and diffs stay in sync with disk changes

---

## Known Issues

### 1. Comments Are In-Memory Only
**File:** `State.res` → `commentsAtom`

Comments live purely in Jotai state (browser memory). Closing the webview loses everything. No persistence layer exists yet — this is blocked on bidirectional IPC (see above).

### 2. Patch Re-Parsed on Every Render — ✅ FIXED
The call to `parsePatchFiles` now runs once inside a `useEffect` on mount, and the parsed result is stored in React state (`patchState`). The derived `diffChildren` array is wrapped in `React.useMemo2(..., (patchState, isDark))`, so theme toggles don't trigger re-parsing.


### 3. Array Index Used as React Key — ✅ FIXED
The `InlineComment` components now use `key={fileDiffName(fileDiff)}` instead of the array index.

### 4. Fragile JS Property Access in `toggleComment`
**File:** `InlineComment.res`, lines: `%raw(\`props["lineNumber"]\`)` and `%raw(\`props["annotationSide"]\`)`

The line click handler accesses properties directly from the `@pierre/diffs` callback object using raw JS property access. This couples to the internal shape of that library's API — a breaking change in `@pierre/diffs` would silently break comment toggling.

**Fix:** Define a proper ReScript type for the callback props and use field access instead of `%raw`.

### 5. No Error Handling for Git Diff Failure — PARTIALLY FIXED
**UI side (fixed):** `App.res` uses `Js.Promise2.catch` around `Ipc.callGetPatch()` and renders a styled `PatchError(msg)` view with the error message.

**Odin side (still open):** `getCurrentGitPatch()` ignores the exit code and stderr from `os2.process_exec` (`_, stdout, _, _`). If git fails (no HEAD, corrupted repo), the raw output is still returned as a JSON response without validation. The Odin handler should check the exit code and return an error through the IPC channel so the UI can display a meaningful message.

---

## Nice-to-Have (Not Blocking)
- **Scroll restoration on theme toggle** works but uses `requestAnimationFrame` + direct DOM manipulation — could be cleaner
- **Shiki preload is fire-and-forget** in `Main.res` — if it fails, diffs render without syntax highlighting and there's no fallback indication
- **960x720 default window size** may still be small for a diff review tool; should be configurable or auto-sized
