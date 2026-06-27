open State
open Diffs

let str = React.string

type commitDraft
type reconciledDraft = {
  message: string,
  body: string,
  selectedFiles: Js.Dict.t<bool>,
  excludedLines: Js.Dict.t<bool>,
  activeFileName: string,
  resetCount: int,
}
type savedDraft = {
  message: string,
  body: string,
  selectedFiles: Js.Dict.t<bool>,
  excludedLines: Js.Dict.t<bool>,
  fingerprints: Js.Dict.t<string>,
  activeFileName: string,
}

@module("./CommitDraft.mjs") external draftStorageKey: string => string = "storageKey"
@module("./CommitDraft.mjs")
external fingerprintFiles: array<patchFile> => Js.Dict.t<string> = "fingerprintFiles"
@module("./CommitDraft.mjs")
external fingerprintSignature: Js.Dict.t<string> => string = "fingerprintSignature"
@module("./CommitDraft.mjs") external loadDraft: string => Js.Nullable.t<commitDraft> = "loadDraft"
@module("./CommitDraft.mjs")
external reconcileDraft: (
  Js.Nullable.t<commitDraft>,
  array<string>,
  Js.Dict.t<string>,
) => reconciledDraft = "reconcileDraft"
@module("./CommitDraft.mjs") external saveDraft: (string, savedDraft) => unit = "saveDraft"
@module("./CommitDraft.mjs") external clearDraft: string => unit = "clearDraft"

let lineKey = (fileName: string, side: string, lineNumber: int): string =>
  fileName ++ "|" ++ side ++ "|" ++ Int.toString(lineNumber)

let copyBoolDict: Js.Dict.t<bool> => Js.Dict.t<bool> = Raw.copyDict
let containsWhitespace: string => bool = %raw(`value => /\s/.test(value)`)

let clearFileLineKeys: (Js.Dict.t<bool>, string) => unit =
  %raw(`(dict, fileName) => {
    const prefix = fileName + "|";
    for (const key of Object.keys(dict)) {
      if (key.startsWith(prefix)) delete dict[key];
    }
  }`)

let isTruthy = value =>
  switch value {
  | Some(true) => true
  | _ => false
  }

let buildSelectedPatch: (
  array<patchFile>,
  Js.Dict.t<bool>,
  Js.Dict.t<bool>,
) => string =
  %raw(`(fileDiffs, selectedFiles, excludedLines) => {
    const isFileSelected = (name) => selectedFiles[name] !== false;
    const isExcluded = (fileName, side, lineNumber) =>
      excludedLines[fileName + "|" + side + "|" + lineNumber] === true;
    const newline = String.fromCharCode(10);
    const withoutTrailingNewline = (line) => String(line ?? "").replace(/\n$/, "");
    const countLine = (hunk, prefix) => {
      hunk.oldCount += prefix === "+" ? 0 : 1;
      hunk.newCount += prefix === "-" ? 0 : 1;
      if (prefix === "+" || prefix === "-") hunk.hasChange = true;
    };
    const pushLine = (hunk, prefix, line) => {
      hunk.lines.push(prefix + withoutTrailingNewline(line));
      countLine(hunk, prefix);
    };
    const pushNoNewlineMarker = (hunk) => {
      hunk.lines.push("\\ No newline at end of file");
    };
    const formatRange = (start, count) => count === 1 ? String(start) : String(start) + "," + String(count);
    const pushHeader = (out, fd) => {
      const name = fd.name || "";
      const prevName = fd.prevName || name;
      out.push("diff --git a/" + prevName + " b/" + name);
      if (fd.type === "new") {
        out.push("new file mode " + (fd.mode || "100644"));
      } else if (fd.type === "deleted") {
        out.push("deleted file mode " + (fd.mode || "100644"));
      }
      if (fd.prevObjectId || fd.newObjectId) {
        const prev = fd.prevObjectId || "0000000";
        const next = fd.newObjectId || "0000000";
        const mode = fd.mode && fd.type === "change" ? " " + fd.mode : "";
        out.push("index " + prev + ".." + next + mode);
      }
      out.push("--- " + (fd.type === "new" ? "/dev/null" : "a/" + prevName));
      out.push("+++ " + (fd.type === "deleted" ? "/dev/null" : "b/" + name));
    };
    const isEmptyFile = (fd) =>
      fd && fd.type === "new" &&
      String(fd.newObjectId || "").startsWith("e69de29") &&
      (!Array.isArray(fd.additionLines) || fd.additionLines.length === 0 ||
        (fd.additionLines.length === 1 && fd.additionLines[0] === "\n"));
    const pushEmptyFile = (out, fd) => {
      const name = fd.name || "";
      const prevName = fd.prevName || name;
      out.push("diff --git a/" + prevName + " b/" + name);
      out.push("new file mode " + (fd.mode || "100644"));
      out.push("index " + (fd.prevObjectId || "0000000") + ".." + (fd.newObjectId || "e69de29"));
    };

    const out = [];
    for (const fd of fileDiffs) {
      const fileName = fd.name || "";
      if (!fileName || !isFileSelected(fileName)) continue;
      if (isEmptyFile(fd)) {
        if (out.length > 0) out.push("");
        pushEmptyFile(out, fd);
        continue;
      }

      const fileHunks = [];
      let selectedDelta = 0;
      for (const hunk of fd.hunks || []) {
        const built = {
          oldStart: hunk.deletionStart || 0,
          newStart: (hunk.deletionStart || 0) === 0
            ? (hunk.additionStart || 0) + selectedDelta
            : (hunk.deletionStart || 0) + selectedDelta,
          oldCount: 0,
          newCount: 0,
          lines: [],
          hasChange: false,
          selectedAdds: 0,
          selectedDeletes: 0,
        };
        let deletionLineNumber = hunk.deletionStart || 0;
        let additionLineNumber = hunk.additionStart || 0;
        let deletionIndex = hunk.deletionLineIndex || 0;
        let additionIndex = hunk.additionLineIndex || 0;

        for (const item of hunk.hunkContent || []) {
          if (item.type === "context") {
            const lines = item.lines || 0;
            for (let i = 0; i < lines; i += 1) {
              pushLine(built, " ", (fd.deletionLines || [])[deletionIndex + i]);
              const isOldEof = deletionIndex + i === (fd.deletionLines || []).length - 1;
              const isNewEof = additionIndex + i === (fd.additionLines || []).length - 1;
              if (
                (hunk.noEOFCRDeletions && isOldEof) ||
                (hunk.noEOFCRAdditions && isNewEof)
              ) {
                pushNoNewlineMarker(built);
              }
            }
            deletionLineNumber += lines;
            additionLineNumber += lines;
            deletionIndex += lines;
            additionIndex += lines;
          } else if (item.type === "change") {
            const deletions = item.deletions || 0;
            const additions = item.additions || 0;
            for (let i = 0; i < deletions; i += 1) {
              const lineNumber = deletionLineNumber + i;
              const line = (fd.deletionLines || [])[deletionIndex + i];
              if (isExcluded(fileName, "deletions", lineNumber)) {
                pushLine(built, " ", line);
              } else {
                pushLine(built, "-", line);
                built.selectedDeletes += 1;
              }
              if (
                hunk.noEOFCRDeletions &&
                deletionIndex + i === (fd.deletionLines || []).length - 1
              ) {
                pushNoNewlineMarker(built);
              }
            }
            for (let i = 0; i < additions; i += 1) {
              const lineNumber = additionLineNumber + i;
              if (!isExcluded(fileName, "additions", lineNumber)) {
                pushLine(built, "+", (fd.additionLines || [])[additionIndex + i]);
                built.selectedAdds += 1;
                if (
                  hunk.noEOFCRAdditions &&
                  additionIndex + i === (fd.additionLines || []).length - 1
                ) {
                  pushNoNewlineMarker(built);
                }
              }
            }
            deletionLineNumber += deletions;
            additionLineNumber += additions;
            deletionIndex += deletions;
            additionIndex += additions;
          }
        }

        selectedDelta += built.selectedAdds - built.selectedDeletes;
        if (built.hasChange) {
          fileHunks.push(built);
        }
      }

      if (fileHunks.length === 0) continue;
      if (out.length > 0) out.push("");
      pushHeader(out, fd);
      for (const hunk of fileHunks) {
        out.push("@@ -" + formatRange(hunk.oldStart, hunk.oldCount) + " +" + formatRange(hunk.newStart, hunk.newCount) + " @@");
        out.push(...hunk.lines);
      }
    }

    return out.length === 0 ? "" : out.join(newline) + newline;
  }`)

let syncExcludedLineHighlights: (
  Js.Nullable.t<Dom.element>,
  array<lineAnnotation>,
) => (unit => unit) =
  %raw(`(root, excludedLines) => {
    if (root == null) return () => {};

    const observed = new WeakSet();
    let frame = 0;

    const collectRoots = () => {
      const roots = [root];
      for (const el of root.querySelectorAll("*")) {
        if (el.shadowRoot) roots.push(el.shadowRoot);
      }
      return roots;
    };

    const apply = () => {
      frame = 0;
      const roots = collectRoots();
      for (const currentRoot of roots) {
        for (const el of currentRoot.querySelectorAll("[data-selected-line]")) {
          el.removeAttribute("data-selected-line");
        }
        for (const el of currentRoot.querySelectorAll("[data-baka-excluded-line]")) {
          el.removeAttribute("data-baka-excluded-line");
        }
      }

      for (const line of excludedLines) {
        const type = line.side === "deletions" ? "change-deletion" : "change-addition";
        const lineNumber = String(line.lineNumber);
        const selector = '[data-column-number="' + lineNumber + '"][data-line-type="' + type + '"]';
        for (const currentRoot of roots) {
          for (const el of currentRoot.querySelectorAll(selector)) {
            el.setAttribute("data-baka-excluded-line", "");
          }
        }
      }
    };

    const schedule = () => {
      if (frame !== 0) cancelAnimationFrame(frame);
      frame = requestAnimationFrame(apply);
    };

    const observer = new MutationObserver(() => {
      for (const currentRoot of collectRoots()) {
        if (!observed.has(currentRoot)) {
          observer.observe(currentRoot, {childList: true, subtree: true});
          observed.add(currentRoot);
        }
      }
      schedule();
    });

    for (const currentRoot of collectRoots()) {
      observer.observe(currentRoot, {childList: true, subtree: true});
      observed.add(currentRoot);
    }

    schedule();
    return () => {
      if (frame !== 0) cancelAnimationFrame(frame);
      observer.disconnect();
    };
  }`)

let syncLineNumberSelection: (
  Js.Nullable.t<Dom.element>,
  string,
  bool,
  ((Js.Dict.t<bool> => Js.Dict.t<bool>) => unit),
) => (unit => unit) =
  %raw(`(root, fileName, enabled, setExcludedLines) => {
    if (root == null || !enabled) return () => {};

    const observed = new WeakSet();
    const cleanups = [];
    let session = null;

    const collectRoots = () => {
      const roots = [root];
      for (const el of root.querySelectorAll("*")) {
        if (el.shadowRoot) roots.push(el.shadowRoot);
      }
      return roots;
    };

    const sideFromType = (type) => {
      if (type === "change-deletion") return "deletions";
      if (type === "change-addition") return "additions";
    };

    const lineFromElement = (element) => {
      if (!(element instanceof HTMLElement)) return null;
      const numberElement = element.closest("[data-column-number]");
      if (!(numberElement instanceof HTMLElement)) return null;
      const side = sideFromType(numberElement.getAttribute("data-line-type"));
      const lineNumber = Number.parseInt(numberElement.getAttribute("data-column-number") || "", 10);
      if (side == null || !Number.isFinite(lineNumber)) return null;
      const key = fileName + "|" + side + "|" + lineNumber;
      const ownerRoot = numberElement.getRootNode();
      return {element: numberElement, root: ownerRoot, side, lineNumber, key};
    };

    const lineFromEvent = (event) => {
      for (const item of event.composedPath()) {
        const line = lineFromElement(item);
        if (line != null) return line;
      }
      for (const currentRoot of collectRoots()) {
        if (typeof currentRoot.elementFromPoint !== "function") continue;
        const line = lineFromElement(currentRoot.elementFromPoint(event.clientX, event.clientY));
        if (line != null) return line;
      }
      return null;
    };

    const changedNumberElements = (ownerRoot) =>
      Array.from(ownerRoot.querySelectorAll(
        '[data-column-number][data-line-type="change-deletion"],' +
        '[data-column-number][data-line-type="change-addition"]'
      )).filter((element) => lineFromElement(element) != null);

    const linesBetween = (start, end) => {
      if (start == null) return [];
      if (end == null || start.root !== end.root) return [start];
      const elements = changedNumberElements(start.root);
      const startIndex = elements.indexOf(start.element);
      const endIndex = elements.indexOf(end.element);
      if (startIndex < 0 || endIndex < 0) return [start];
      const from = Math.min(startIndex, endIndex);
      const to = Math.max(startIndex, endIndex);
      const seen = new Set();
      const lines = [];
      for (const element of elements.slice(from, to + 1)) {
        const line = lineFromElement(element);
        if (line != null && !seen.has(line.key)) {
          seen.add(line.key);
          lines.push(line);
        }
      }
      return lines;
    };

    const applyLines = (lines) => {
      if (lines.length === 0) return;
      setExcludedLines((prev) => {
        const next = Object.assign({}, prev);
        const allExcluded = lines.every((line) => next[line.key] === true);
        const shouldExclude = !allExcluded;
        for (const line of lines) next[line.key] = shouldExclude;
        return next;
      });
    };

    const onPointerDown = (event) => {
      if (event.button !== 0) return;
      const start = lineFromEvent(event);
      if (start == null) return;
      event.preventDefault();
      event.stopPropagation();
      session = {pointerId: event.pointerId, start, current: start};
      document.addEventListener("pointermove", onPointerMove);
      document.addEventListener("pointerup", onPointerUp);
      document.addEventListener("pointercancel", onPointerCancel);
    };

    const onPointerMove = (event) => {
      if (session == null || event.pointerId !== session.pointerId) return;
      event.preventDefault();
      const current = lineFromEvent(event);
      if (current != null) session.current = current;
    };

    const endSession = () => {
      document.removeEventListener("pointermove", onPointerMove);
      document.removeEventListener("pointerup", onPointerUp);
      document.removeEventListener("pointercancel", onPointerCancel);
      session = null;
    };

    const onPointerUp = (event) => {
      if (session == null || event.pointerId !== session.pointerId) return;
      event.preventDefault();
      applyLines(linesBetween(session.start, session.current));
      endSession();
    };

    const onPointerCancel = (event) => {
      if (session == null || event.pointerId !== session.pointerId) return;
      endSession();
    };

    const attach = () => {
      for (const currentRoot of collectRoots()) {
        if (observed.has(currentRoot)) continue;
        currentRoot.addEventListener("pointerdown", onPointerDown, true);
        cleanups.push(() => currentRoot.removeEventListener("pointerdown", onPointerDown, true));
        observed.add(currentRoot);
      }
    };

    const observer = new MutationObserver(attach);
    observer.observe(root, {childList: true, subtree: true});
    cleanups.push(() => observer.disconnect());
    attach();

    return () => {
      endSession();
      for (const cleanup of cleanups.splice(0)) cleanup();
    };
  }`)

module Styles = {
  let treeFont = `"Ioskeley Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace`

  let excludedLineUnsafeCss = `
    [data-selected-line] {
      --diffs-line-bg: var(--diffs-computed-diff-line-bg);
      color: inherit;
    }

    [data-selected-line][data-line] span {
      background-color: transparent !important;
    }

    [data-baka-excluded-line] {
      --baka-selection-bg: light-dark(#1f2937, #f3f4f6);
      --baka-selection-fg: light-dark(#ffffff, #111827);
      --diffs-computed-selected-line-bg: var(--baka-selection-bg);
      --diffs-line-bg: var(--baka-selection-bg);
      color: var(--baka-selection-fg);
    }

    [data-column-number][data-line-type="change-deletion"],
    [data-column-number][data-line-type="change-addition"] {
      cursor: pointer;
      touch-action: none;
    }
  `

  let shell = Html.css`
    display: flex;
    flex: 1;
    min-height: 0;
    overflow: hidden;
    font-family: ${treeFont};
    font-size: 1rem;
  `

  let sidebar = (colors: uiColors) => Html.css`
    width: 320px;
    min-width: 260px;
    max-width: 420px;
    display: flex;
    flex-direction: column;
    min-height: 0;
    border-right: 1px solid ${colors.border};
    background-color: ${colors.surfaceBg};
  `

  let sidebarHeader = (colors: uiColors) => Html.css`
    padding: 10px 12px;
    border-bottom: 1px solid ${colors.border};
    color: ${colors.fg};
    font-size: 1rem;
    font-weight: 600;
  `

  let sidebarActions = Html.css`
    display: flex;
    gap: 8px;
    padding: 8px 12px;
    border-bottom: 1px solid rgba(127, 127, 127, 0.18);
  `

  let smallButton = (colors: uiColors) => Html.css`
    padding: 4px 8px;
    border-radius: 4px;
    border: 1px solid ${colors.border};
    background-color: ${colors.buttonBg};
    color: ${colors.buttonFg};
    font-size: 0.923rem;
    cursor: pointer;
    &:hover { background-color: ${colors.buttonHoverBg}; }
  `

  let fileList = Html.css`
    overflow: auto;
    min-height: 0;
    flex: 1;
  `

  let fileRow = (colors: uiColors, active: bool) => Html.css`
    display: grid;
    grid-template-columns: 22px minmax(0, 1fr);
    align-items: center;
    gap: 6px;
    width: 100%;
    padding: 7px 10px;
    border-bottom: 1px solid rgba(127, 127, 127, 0.12);
    background-color: ${if active { colors.selectionBg } else { "transparent" }};
    color: ${colors.fg};
    text-align: left;
    cursor: pointer;
    &:hover { background-color: ${colors.hoverBg}; }
  `

  let fileName = Html.css`
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 1rem;
  `

  let lineCount = (colors: uiColors) => Html.css`
    color: ${colors.descriptionFg};
    font-size: 0.923rem;
  `

  let main = Html.css`
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  `

  let toolbar = (colors: uiColors) => Html.css`
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 8px 12px;
    border-bottom: 1px solid ${colors.border};
    background-color: ${colors.inputBg};
    color: ${colors.fg};
    font-size: 1rem;
  `

  let toolbarActions = Html.css`
    display: flex;
    gap: 8px;
    align-items: center;
  `

  let activeTitle = Html.css`
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-weight: 600;
  `

  let diffPane = Html.css`
    flex: 1;
    min-height: 0;
    overflow: hidden;
  `

  let emptyFile = (colors: uiColors) => Html.css`
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: ${colors.descriptionFg};
    font-size: 1rem;
  `

  let emptyState = (colors: uiColors) => Html.css`
    display: flex;
    align-items: center;
    justify-content: center;
    flex: 1;
    padding: 24px;
    color: ${colors.descriptionFg};
    font-size: 1rem;
  `

  let commitForm = (colors: uiColors) => Html.css`
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 10px 12px 12px;
    border-top: 1px solid ${colors.border};
    background-color: ${colors.inputBg};
  `

  let commitField = (colors: uiColors) => Html.css`
    width: 100%;
    box-sizing: border-box;
    border: 1px solid ${colors.border};
    border-radius: 4px;
    background-color: ${colors.inputBg};
    color: ${colors.fg};
    font: inherit;
    font-size: 1rem;
    padding: 6px 8px;
    outline: none;
    &:focus { border-color: ${colors.focusBorder}; }
  `

  let commitTextArea = (colors: uiColors) => Html.css`
    width: 100%;
    min-height: 64px;
    resize: vertical;
    box-sizing: border-box;
    border: 1px solid ${colors.border};
    border-radius: 4px;
    background-color: ${colors.inputBg};
    color: ${colors.fg};
    font: inherit;
    font-size: 1rem;
    padding: 6px 8px;
    outline: none;
    &:focus { border-color: ${colors.focusBorder}; }
  `

  let commitButton = (colors: uiColors, disabled: bool) => Html.css`
    padding: 6px 10px;
    border-radius: 4px;
    border: 1px solid ${colors.focusBorder};
    background-color: ${colors.buttonBg};
    color: ${colors.buttonFg};
    font-size: 1rem;
    cursor: ${if disabled { "not-allowed" } else { "pointer" }};
    opacity: ${if disabled { "0.55" } else { "1" }};
    &:hover { background-color: ${if disabled { colors.buttonBg } else { colors.buttonHoverBg }}; }
  `

  let commitStatus = (colors: uiColors, isError: bool) => Html.css`
    color: ${colors.descriptionFg};
    font-size: 0.923rem;
    line-height: 1.4;
    white-space: pre-wrap;
    ${if isError { "color: " ++ colors.dangerBg ++ ";" } else { "" }}
  `

  let fieldError = (colors: uiColors) => Html.css`
    color: ${colors.dangerBg};
    font-size: 0.923rem;
    line-height: 1.3;
  `
}

@react.component
let make = (
  ~patches: array<parsedPatch>,
  ~repoRoot: string,
  ~theme: FileDiff.theme,
  ~themeType: string,
  ~uiColors: uiColors,
  ~onCommitted: unit => unit,
) => {
  let fileDiffs = React.useMemo1(() => {
    patches->Array.flatMap(patch => patch.files)
  }, [patches])

  let fileNames = React.useMemo1(() => {
    fileDiffs->Array.map(fileDiffName)
  }, [fileDiffs])

  let fileFingerprints = React.useMemo1(() => fingerprintFiles(fileDiffs), [fileDiffs])
  let fingerprintVersion =
    React.useMemo1(() => fingerprintSignature(fileFingerprints), [fileFingerprints])
  let storageKey = React.useMemo1(() => draftStorageKey(repoRoot), [repoRoot])

  let (selectedFiles, setSelectedFiles) = React.useState((): Js.Dict.t<bool> => Js.Dict.empty())
  let (excludedLines, setExcludedLines) = React.useState((): Js.Dict.t<bool> => Js.Dict.empty())
  let (activeFileName, setActiveFileName) = React.useState(() => "")
  let (commitMessage, setCommitMessage) = React.useState(() => "")
  let (commitBody, setCommitBody) = React.useState(() => "")
  let (branchName, setBranchName) = React.useState(() => "")
  let (branchOptions, setBranchOptions) = React.useState((): array<string> => [])
  let (branchValidationTarget, setBranchValidationTarget) = React.useState(() => "")
  let (branchValidationError, setBranchValidationError) = React.useState(() => "")
  let (isBranchValidating, setIsBranchValidating) = React.useState(() => false)
  let (commitStatus, setCommitStatus) = React.useState(() => "")
  let (commitStatusIsError, setCommitStatusIsError) = React.useState(() => false)
  let (isCommitting, setIsCommitting) = React.useState(() => false)
  let (draftReady, setDraftReady) = React.useState(() => false)
  let diffPaneRef: React.ref<Js.Nullable.t<Dom.element>> = React.useRef(Js.Nullable.null)
  let skipPersistRef = React.useRef(false)
  let committedRef = React.useRef(false)
  let draftReadyRef = React.useRef(false)
  let branchValidationSeqRef = React.useRef(0)
  let latestDraftRef: React.ref<savedDraft> = React.useRef({
    message: "",
    body: "",
    selectedFiles: Js.Dict.empty(),
    excludedLines: Js.Dict.empty(),
    fingerprints: Js.Dict.empty(),
    activeFileName: "",
  })

  React.useEffect1(() => {
    let onSuccess = (info: Ipc.branchInfo): Js.Promise.t<unit> => {
      setBranchOptions(_ => info.branches)
      setBranchName(current => if current->String.trim == "" {info.currentBranch} else {current})
      setBranchValidationTarget(_ => info.currentBranch)
      setBranchValidationError(_ => "")
      Js.Promise2.resolve()
    }
    let onError = (_err: Js.Promise2.error): Js.Promise.t<unit> => Js.Promise2.resolve()
    let _ = Js.Promise2.catch(
      Js.Promise2.then(Ipc.callGetGitBranches(), onSuccess),
      onError,
    )
    None
  }, [repoRoot])

  React.useEffect2(() => {
    if storageKey != "" {
      skipPersistRef.current = true
      committedRef.current = false
      let restored = reconcileDraft(loadDraft(storageKey), fileNames, fileFingerprints)
      setCommitMessage(_ => restored.message)
      setCommitBody(_ => restored.body)
      setSelectedFiles(_ => restored.selectedFiles)
      setExcludedLines(_ => restored.excludedLines)
      setActiveFileName(_ => restored.activeFileName)
      draftReadyRef.current = true
      setDraftReady(_ => true)
      if restored.resetCount > 0 {
        setCommitStatus(_ =>
          "Selection reset for " ++
          Int.toString(restored.resetCount) ++
          " file(s) whose diff changed."
        )
        setCommitStatusIsError(_ => false)
      }
    }
    None
  }, (storageKey, fingerprintVersion))

  latestDraftRef.current = {
    message: commitMessage,
    body: commitBody,
    selectedFiles: selectedFiles,
    excludedLines: excludedLines,
    fingerprints: fileFingerprints,
    activeFileName: activeFileName,
  }

  React.useEffect(() => {
    if draftReady && storageKey != "" && !committedRef.current {
      if skipPersistRef.current {
        skipPersistRef.current = false
      } else {
        saveDraft(storageKey, latestDraftRef.current)
      }
    }
    None
  }, (
    draftReady,
    storageKey,
    commitMessage,
    commitBody,
    selectedFiles,
    excludedLines,
    fileFingerprints,
    activeFileName,
  ))

  React.useEffect1(() => {
    Some(() => {
      if draftReadyRef.current && storageKey != "" && !committedRef.current {
        saveDraft(storageKey, latestDraftRef.current)
      }
    })
  }, [storageKey])

  let activeFile = fileDiffs->Array.find(fd => fileDiffName(fd) == activeFileName)

  let changedLinesForFile = (fd: patchFile): array<lineAnnotation> => changedLineAnnotations(fd)

  let activeChangedLines = React.useMemo2(() => {
    switch activeFile {
    | Some(fd) => changedLinesForFile(fd)
    | None => []
    }
  }, (activeFileName, fileDiffs))

  let isFileSelected = (name: string): bool =>
    switch Js.Dict.get(selectedFiles, name) {
    | Some(value) => value
    | None => true
    }

  let isLineExcluded = (key: string): bool => isTruthy(Js.Dict.get(excludedLines, key))

  let selectedFileCount = fileNames->Array.reduce(0, (count, name) =>
    if isFileSelected(name) { count + 1 } else { count }
  )

  let selectedChangedLineCount =
    fileDiffs->Array.reduce(0, (count, fd) => {
      let name = fileDiffName(fd)
      if !isFileSelected(name) {
        count
      } else if isEmptyFile(fd) {
        count + 1
      } else {
        let changed = changedLinesForFile(fd)
        let excluded = changed->Array.reduce(0, (excludedCount, annotation) => {
          let key = lineKey(name, annotation.side, annotation.lineNumber)
          if isLineExcluded(key) { excludedCount + 1 } else { excludedCount }
        })
        count + changed->Array.length - excluded
      }
    })

  let trimmedCommitMessage = commitMessage->String.trim
  let trimmedBranchName = branchName->String.trim
  let localBranchError =
    if trimmedBranchName == "" {
      "Branch name is required."
    } else if containsWhitespace(branchName) {
      "Branch names cannot contain spaces."
    } else if String.startsWith(trimmedBranchName, "-") {
      "Branch names cannot start with '-'."
    } else {
      ""
    }
  let gitBranchError =
    if branchValidationTarget == trimmedBranchName {
      branchValidationError
    } else {
      ""
    }
  let branchError = if localBranchError != "" {localBranchError} else {gitBranchError}
  let branchIsValidated =
    trimmedBranchName != "" &&
    localBranchError == "" &&
    branchValidationTarget == trimmedBranchName &&
    branchValidationError == "" &&
    !isBranchValidating
  let canCommit =
    !isCommitting &&
    trimmedCommitMessage != "" &&
    branchIsValidated &&
    selectedChangedLineCount > 0

  let excludedHighlightLines =
    activeChangedLines->Array.filter(annotation =>
      isLineExcluded(lineKey(activeFileName, annotation.side, annotation.lineNumber))
    )

  React.useEffect2(() => {
    let cleanup = syncExcludedLineHighlights(diffPaneRef.current, excludedHighlightLines)
    Some(cleanup)
  }, (activeFileName, excludedHighlightLines))

  let activeFileSelected = isFileSelected(activeFileName)

  React.useEffect2(() => {
    let cleanup = syncLineNumberSelection(
      diffPaneRef.current,
      activeFileName,
      activeFileSelected,
      setExcludedLines,
    )
    Some(cleanup)
  }, (activeFileName, activeFileSelected))

  let toggleFile = (name: string, checked: bool) => {
    setSelectedFiles(prev => {
      let next = copyBoolDict(prev)
      Js.Dict.set(next, name, checked)
      next
    })
    setExcludedLines(prev => {
      let next = copyBoolDict(prev)
      clearFileLineKeys(next, name)
      next
    })
  }

  let setAllFiles = (checked: bool) => {
    setSelectedFiles(_ => {
      let next: Js.Dict.t<bool> = Js.Dict.empty()
      fileNames->Array.forEach(name => Js.Dict.set(next, name, checked))
      next
    })
    setExcludedLines(_ => Js.Dict.empty())
  }

  let includeActiveLines = _event => {
    if isFileSelected(activeFileName) {
      setExcludedLines(prev => {
        let next = copyBoolDict(prev)
        activeChangedLines->Array.forEach(annotation => {
          Js.Dict.set(next, lineKey(activeFileName, annotation.side, annotation.lineNumber), false)
        })
        next
      })
    }
  }

  let excludeActiveLines = _event => {
    if isFileSelected(activeFileName) {
      setExcludedLines(prev => {
        let next = copyBoolDict(prev)
        activeChangedLines->Array.forEach(annotation => {
          Js.Dict.set(next, lineKey(activeFileName, annotation.side, annotation.lineNumber), true)
        })
        next
      })
    }
  }

  let validateBranch = _event => {
    let target = trimmedBranchName
    if target == "" {
      setBranchValidationTarget(_ => "")
      setBranchValidationError(_ => "")
      setIsBranchValidating(_ => false)
    } else if localBranchError != "" {
      setBranchValidationTarget(_ => target)
      setBranchValidationError(_ => localBranchError)
      setIsBranchValidating(_ => false)
    } else {
      let seq = branchValidationSeqRef.current + 1
      branchValidationSeqRef.current = seq
      setBranchValidationTarget(_ => target)
      setBranchValidationError(_ => "")
      setIsBranchValidating(_ => true)
      let onSuccess = (_: unit): Js.Promise.t<unit> => {
        if branchValidationSeqRef.current == seq {
          setBranchValidationTarget(_ => target)
          setBranchValidationError(_ => "")
          setIsBranchValidating(_ => false)
        }
        Js.Promise2.resolve()
      }
      let onError = (err: Js.Promise2.error): Js.Promise.t<unit> => {
        if branchValidationSeqRef.current == seq {
          setBranchValidationTarget(_ => target)
          setBranchValidationError(_ => Raw.errorMessage(err))
          setIsBranchValidating(_ => false)
        }
        Js.Promise2.resolve()
      }
      let _ = Js.Promise2.catch(
        Js.Promise2.then(Ipc.callValidateGitBranch(target), onSuccess),
        onError,
      )
    }
  }

  let handleCommit = _event => {
    if canCommit {
      let patch = buildSelectedPatch(fileDiffs, selectedFiles, excludedLines)
      if patch->String.trim == "" {
        setCommitStatus(_ => "No selected changes to commit.")
        setCommitStatusIsError(_ => true)
      } else {
        setIsCommitting(_ => true)
        setCommitStatus(_ => "Committing selected changes...")
        setCommitStatusIsError(_ => false)
        let request: Ipc.commitSelectionRequest = {
          message: trimmedCommitMessage,
          body: commitBody,
          patch,
          branch: trimmedBranchName,
        }
        let onSuccess = (result: string): Js.Promise.t<unit> => {
          committedRef.current = true
          clearDraft(storageKey)
          setIsCommitting(_ => false)
          setCommitStatus(_ => result)
          setCommitStatusIsError(_ => false)
          setCommitMessage(_ => "")
          setCommitBody(_ => "")
          setBranchOptions(options =>
            switch options->Array.find(branch => branch == trimmedBranchName) {
            | Some(_) => options
            | None => Array.concat(options, [trimmedBranchName])
            }
          )
          onCommitted()
          Js.Promise2.resolve()
        }
        let onError = (err: Js.Promise2.error): Js.Promise.t<unit> => {
          let msg = Raw.errorMessage(err)
          setIsCommitting(_ => false)
          setCommitStatus(_ => msg)
          setCommitStatusIsError(_ => true)
          Js.Promise2.resolve()
        }
        let _ = Js.Promise2.catch(
          Js.Promise2.then(Ipc.callCommitSelection(request), onSuccess),
          onError,
        )
      }
    }
  }

  let optionsObj = React.useMemo2((): Diffs.jsObj =>
    Obj.magic({
      "theme": {"light": theme.light, "dark": theme.dark},
      "themeType": themeType,
      "diffStyle": "unified",
      "lineHoverHighlight": true,
      "unsafeCSS": Diffs.fontUnsafeCss ++ Styles.excludedLineUnsafeCss,
    })
  , (theme, themeType))

  <div className={Styles.shell}>
    <aside className={Styles.sidebar(uiColors)}>
      <div className={Styles.sidebarHeader(uiColors)}>
        {str(
          Int.toString(selectedFileCount) ++ "/" ++
          Int.toString(fileNames->Array.length) ++
          " files selected",
        )}
      </div>
      <div className={Styles.sidebarActions}>
        <button className={Styles.smallButton(uiColors)} onClick={_ => setAllFiles(true)}>
          {str("All")}
        </button>
        <button className={Styles.smallButton(uiColors)} onClick={_ => setAllFiles(false)}>
          {str("None")}
        </button>
      </div>
      <div className={Styles.fileList}>
        {React.array(
          fileDiffs->Array.map(fd => {
            let name = fileDiffName(fd)
            let selected = isFileSelected(name)
            <div
              key={name}
              className={Styles.fileRow(uiColors, name == activeFileName)}
              onClick={_ => setActiveFileName(_ => name)}
            >
              <input
                type_="checkbox"
                checked={selected}
                onClick={ev => ReactEvent.Mouse.stopPropagation(ev)}
                onChange={(ev: JsxEvent.Form.t) => {
                  let target = JsxEvent.Form.target(ev)
                  toggleFile(name, target["checked"])
                }}
              />
              <span className={Styles.fileName}>{str(name)}</span>
            </div>
          })
        )}
      </div>
      <div className={Styles.commitForm(uiColors)}>
        <input
          className={Styles.commitField(uiColors)}
          type_="text"
          list="commit-branch-options"
          placeholder="Branch"
          value={branchName}
          disabled={isCommitting}
          onBlur={validateBranch}
          onChange={(ev: JsxEvent.Form.t) => {
            let target = JsxEvent.Form.target(ev)
            setBranchName(_ => target["value"])
          }}
        />
        <datalist id="commit-branch-options">
          {React.array(
            branchOptions->Array.map(branch =>
              <option key={branch} value={branch} />
            )
          )}
        </datalist>
        {branchName != "" && branchError != ""
          ? <div className={Styles.fieldError(uiColors)}>{str(branchError)}</div>
          : React.null}
        <input
          className={Styles.commitField(uiColors)}
          type_="text"
          placeholder="Commit message"
          value={commitMessage}
          disabled={isCommitting}
          onChange={(ev: JsxEvent.Form.t) => {
            let target = JsxEvent.Form.target(ev)
            setCommitMessage(_ => target["value"])
          }}
        />
        <textarea
          className={Styles.commitTextArea(uiColors)}
          placeholder="Commit comment"
          value={commitBody}
          disabled={isCommitting}
          onChange={(ev: JsxEvent.Form.t) => {
            let target = JsxEvent.Form.target(ev)
            setCommitBody(_ => target["value"])
          }}
        />
        <button
          type_="button"
          className={Styles.commitButton(uiColors, !canCommit)}
          disabled={!canCommit}
          onClick={handleCommit}
        >
          {str(if isCommitting { "Committing..." } else { "Commit selected" })}
        </button>
        {commitStatus == ""
          ? React.null
          : <div className={Styles.commitStatus(uiColors, commitStatusIsError)}>
              {str(commitStatus)}
            </div>}
      </div>
    </aside>
    <main className={Styles.main}>
      <div className={Styles.toolbar(uiColors)}>
        <div className={Styles.activeTitle}>
          {str(
            if activeFileName == "" {
              "No file selected"
            } else {
              activeFileName
            },
          )}
        </div>
        <div className={Styles.toolbarActions}>
          <span className={Styles.lineCount(uiColors)}>
            {str(Int.toString(selectedChangedLineCount) ++ " changes selected")}
          </span>
          {switch activeFile {
          | Some(fd) if isEmptyFile(fd) => React.null
          | _ =>
            <>
              <button className={Styles.smallButton(uiColors)} onClick={includeActiveLines}>
                {str("Include file lines")}
              </button>
              <button className={Styles.smallButton(uiColors)} onClick={excludeActiveLines}>
                {str("Exclude file lines")}
              </button>
            </>
          }}
        </div>
      </div>
      {switch activeFile {
      | Some(fd) if isEmptyFile(fd) =>
        <div key={activeFileName} className={Styles.diffPane}>
          <div className={Styles.emptyFile(uiColors)}>
            {str("(empty file)")}
          </div>
        </div>
      | Some(fd) =>
        <>
          <div key={activeFileName} ref={ReactDOM.Ref.domRef(diffPaneRef)} className={Styles.diffPane}>
            <Virtualizer style={%raw(`{"height": "100%", "overflow-y": "auto"}`)}>
              <FileDiff.makeRaw
                fileDiff={fd}
                options={optionsObj}
              />
            </Virtualizer>
          </div>
        </>
      | None =>
        <div className={Styles.emptyState(uiColors)}>
          {str("No changed files to commit.")}
        </div>
      }}
    </main>
  </div>
}
