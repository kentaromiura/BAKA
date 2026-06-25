type patchFile
type parsedPatch = {files: array<patchFile>}

@module("@pierre/diffs")
external parsePatchFiles: string => array<parsedPatch> = "parsePatchFiles"

type fileDiff
type fileDiffProps = {
  dark: string,
  light: string,
}
@module("@pierre/diffs") @new external file: fileDiffProps => fileDiff = "FileDiff"

type renderProps = {
  fileDiff: patchFile,
  containerWrapper: Dom.htmlElement,
}

@send external render: (fileDiff, renderProps) => unit = "render"

type lineAnnotation = {
  side: string,
  lineNumber: int,
}

type selectedLineRange = {
  start: int,
  side?: string,
  end: int,
  endSide?: string,
}

type jsObj
type lineClickProps = {
  lineNumber: float,
  annotationSide: string,
}

let fontFamily = `"Ioskeley Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace`

let fontUnsafeCss = `
  :host {
    --diffs-font-family: ${fontFamily};
    --diffs-header-font-family: ${fontFamily};
    --diffs-font-size: 1rem;
  }
`

let fileDiffName: patchFile => string = %raw(`fd => fd.name || ""`)
let fileDiffType: patchFile => string = %raw(`fd => fd.type || ""`)
let fileDiffAdditionLines: patchFile => array<string> = %raw(`fd => fd.additionLines || []`)
let fileDiffNewObjectId: patchFile => string = %raw(`fd => fd.newObjectId || ""`)
let changedLineAnnotations: patchFile => array<lineAnnotation> =
  %raw(`fd => {
    if (!fd || !Array.isArray(fd.hunks)) return [];
    const annotations = [];
    for (const hunk of fd.hunks) {
      const content = Array.isArray(hunk.hunkContent) ? hunk.hunkContent : [];
      let deletionLine = hunk.deletionStart || 0;
      let additionLine = hunk.additionStart || 0;
      for (const item of content) {
        if (item.type === "context") {
          const lines = item.lines || 0;
          deletionLine += lines;
          additionLine += lines;
        } else if (item.type === "change") {
          const deletions = item.deletions || 0;
          const additions = item.additions || 0;
          for (let i = 0; i < deletions; i += 1) {
            annotations.push({side: "deletions", lineNumber: deletionLine + i});
          }
          for (let i = 0; i < additions; i += 1) {
            annotations.push({side: "additions", lineNumber: additionLine + i});
          }
          deletionLine += deletions;
          additionLine += additions;
        }
      }
    }
    return annotations;
  }`)
let isEmptyFile: patchFile => bool =
  %raw(`fd => !!fd && fd.type === "new" && fd.newObjectId === "e69de29" && Array.isArray(fd.additionLines) && fd.additionLines.length === 1 && fd.additionLines[0] === "\n"`)

module FileDiff = {
  type theme = {light: string, dark: string}

  @module("@pierre/diffs/react") @react.component
  external makeRaw: (
    ~fileDiff: patchFile,
    ~options: jsObj,
    ~lineAnnotations: array<lineAnnotation>=?,
    ~selectedLines: selectedLineRange=?,
    ~renderAnnotation: (lineAnnotation => React.element)=?,
    ~renderHeaderPrefix: (patchFile => React.element)=?,
    ~disableWorkerPool: bool=?,
  ) => React.element = "FileDiff"
}

module Virtualizer = {
  @module("@pierre/diffs/react") @react.component
  external make: (
    ~children: React.element,
    ~className: string=?,
    ~style: Js.t<{..}> = ?,
  ) => React.element = "Virtualizer"
}
