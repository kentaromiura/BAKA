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

type jsObj

let fileDiffName = (fd: patchFile): string => %raw(`fd.name`)

module FileDiff = {
  type theme = {light: string, dark: string}

  @module("@pierre/diffs/react") @react.component
  external makeRaw: (
    ~fileDiff: patchFile,
    ~options: jsObj,
    ~lineAnnotations: array<lineAnnotation>,
    ~renderAnnotation: lineAnnotation => React.element,
    ~renderHeaderPrefix: (patchFile => React.element)=?,
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
