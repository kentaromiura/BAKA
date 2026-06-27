# BAKA architecture

## Overview

BAKA is a native desktop application with an Odin backend and a ReScript React
frontend. The frontend runs inside an embedded webview. Communication between
the two layers uses functions registered with `webview.bind`, with JSON request
and response values passed through JavaScript promises.

The backend owns Git access, Pi processes, filesystem watching, and changes to
the working tree. The frontend owns presentation, interaction state, model
preferences, and rendering of diffs and Markdown.

## Main features

The Review view shows the current Git diff with a changed-file tree and inline
comments. Comments can be sent to Pi for contextual answers. Full code,
security, and specification reviews return structured findings that are
attached to lines or files.

Actionable findings can be applied as patches. BAKA asks Pi to create the
patch, applies it with Git, then runs a separate validation prompt. A failed
validation can produce one repair patch. If validation still fails, BAKA rolls
the generated changes back.

The Project view provides access to tracked and untracked repository files. The
Commit view supports selecting files and individual changed lines before
creating a commit. The New Feature view separates plan creation from plan
implementation.

Watchman monitors repository changes when it is available. A portable Odin
polling watcher is used when Watchman is missing or its connection fails.
Events are passed back to the webview and cause the displayed diff to reload.

## Pi integration

`APP/ask_pi.odin` contains the shared Pi process runner and the review,
suggestion, validation, and model-discovery workflows. Feature planning and
implementation are coordinated from `APP/index.odin`.

Normal actions start a short-lived Pi process in JSON mode:

```sh
pi --mode json --no-session --no-context-files --model provider/model @prompt
```

The `--model` argument is omitted when BAKA should use Pi's configured default.
Review actions disable tools. Planning and patch generation allow Pi to inspect
the repository.

Available models are discovered through Pi's RPC mode. BAKA sends
`get_available_models` and `get_state` requests over JSONL. This provides
structured model data and the model currently resolved as Pi's default without
linking the Pi Node package or parsing terminal output.

The UI stores one default model and optional overrides for:

* inline questions
* code review
* security review
* specification review
* suggestion implementation
* suggestion validation and repair
* plan creation
* plan implementation

An empty override inherits the BAKA default. An empty BAKA default inherits
Pi's own default. Preferences are stored in webview local storage by
`PiPreferences.mjs`. The selected model is included in each IPC request, so an
operation keeps the model chosen when it started.

## Backend

`APP/index.odin` creates the window, registers IPC handlers, embeds the bundled
JavaScript and CSS, starts repository watching, and enters the webview event
loop.

The main IPC surface includes:

* `getPatch`, `getFilePatch`, and `getProjectFiles` for repository data
* `getWatcherEvents` for repository refresh notifications
* `getPiModels` for RPC model discovery
* `askPi` and `askPiWithDiff` for inline questions
* `startFullReview` for code, security, and specification reviews
* `applyReviewSuggestion` for patch generation and validation
* `createFeaturePlan` and `applyFeaturePlan` for feature work
* `commitSelection` for committing the selected patch

Long-running Pi operations run on worker threads. Results are dispatched back
to the webview thread before calling `webview.ret`.

`APP/watchman_watcher.odin` connects to Watchman over its Unix socket protocol.
If Watchman is unavailable, it falls back to periodically comparing repository
filesystem metadata while excluding `.git`. Watcher events are transferred
through a temporary file and polled by the webview integration.

The active repository is selected through backend state instead of assuming the
process working directory. Command-line launches can still pass a repository
path, while desktop launches can use the native `osdialog` folder picker exposed
through the `chooseWorkingFolder` IPC binding. Selecting a new repository resets
repository-scoped UI state and starts a watcher for the new root.

## Frontend

`UI/bakaui/src/App.res` owns the main layout, navigation, review controls,
settings, model loading, and bottom-right model status.

`State.res` contains shared Jotai atoms and records. `Ipc.res` provides typed
wrappers around the native functions. `PiPreferences.res` and
`PiPreferences.mjs` load, save, and resolve model preferences.

The main feature components are:

* `InlineComment.res` and `CommentBox.res` for diff annotations and findings
* `FileViewer.res` and `ProjectView.res` for full-file browsing
* `CommitView.res` for line-level commit selection
* `SpecCheckView.res` for specification review and finding decisions
* `NewFeatureView.res` for planning and implementation

Diff parsing, rendering, and virtualization come from `@pierre/diffs`. File
trees come from `@pierre/trees`. Shiki provides syntax themes and colors.
Markdown output is rendered through `markdown-it`.

## Build

The top-level Makefile builds three parts in order:

1. ReScript source is compiled to ES modules and bundled with esbuild.
2. The webview shared library is built with CMake.
3. The osdialog native dialog bridge is compiled.
4. Odin embeds the UI bundle and links the native application.

The resulting executable and shared library are stored below `build/`. The
executable uses an rpath to locate the webview library there.

`make package` dispatches to the native package for the current platform. On
macOS it builds `build/dist/BAKA.app` with the Odin executable in
`Contents/MacOS`, the webview dylib tree next to it, an app `Info.plist`, and an
`.icns` generated from the UI logo when the standard macOS icon tools are
available. The Linux target is reserved for a future AppImage package.
