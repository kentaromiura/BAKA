open State

let copyDict = Raw.copyDict

let deleteProp = Raw.deleteProp

let makeKey = (fileName: string, side: string, lineNumber: int): string =>
  fileName ++ "|" ++ side ++ "|" ++ Int.toString(lineNumber)

let cleanModelLine: string => string =
  %raw(`line => String(line || "").trim().split("-")[0].replace(/^[+-]/, "").replace(/[^0-9].*$/, "")`)

let parseKey = (key: string): option<(string, string, int)> => {
  let parts = key->String.split("|")
  switch parts {
  | [fileName, sideStr, lineStr] =>
    switch Belt.Int.fromString(lineStr) {
    | Some(lineNumber) => Some((fileName, sideStr, lineNumber))
    | None => None
    }
  | _ => None
  }
}

// Translates the model's diff-notation side (+/-) to the diff library's
// side names ("additions"/"deletions") so the reply's commentKey matches
// the dict key built by makeKey. Passes through anything else unchanged.
let normalizeModelKey = (key: string): string => {
  let parts = Js.String.split("|", key)
  switch Js.Array.length(parts) {
  | 3 =>
    let file = Js.Array.unsafe_get(parts, 0)
    let side = Js.Array.unsafe_get(parts, 1)->String.trim
    let rawLine = Js.Array.unsafe_get(parts, 2)->String.trim
    let line = cleanModelLine(rawLine)
    let translatedSide = switch side {
    | "+" => "additions"
    | "-" => "deletions"
    | "addition" => "additions"
    | "additions" => "additions"
    | "new" => "additions"
    | "deletion" => "deletions"
    | "deletions" => "deletions"
    | "old" => "deletions"
    | _ =>
      if Js.String2.startsWith(rawLine, "+") {
        "additions"
      } else if Js.String2.startsWith(rawLine, "-") {
        "deletions"
      } else {
        side
      }
    }
    `${file}|${translatedSide}|${line}`
  | _ => key
  }
}

module Styles = {
  let fullFileButton = (colors: uiColors) =>
    Html.css`
    padding: 4px 10px;
    border-radius: 4px;
    border: 1px solid ${colors.border};
    background-color: ${colors.surfaceBg};
    color: ${colors.fg};
    font-size: 0.923rem;
    cursor: pointer;
    transition: all 0.15s ease;
    &:hover {
      background-color: ${colors.hoverBg};
      border-color: ${colors.focusBorder};
    }
  `

  let emptyFileLabel = (colors: uiColors) =>
    Html.css`
    margin-left: 8px;
    color: ${colors.descriptionFg};
    font-size: 0.923rem;
  `

  let fileReviewList = (colors: uiColors) =>
    Html.css`
    margin: 0 0 12px 0;
    padding: 8px 12px 10px 12px;
    border-top: 1px solid ${colors.border};
    background-color: ${colors.bg};
  `

  let fileReviewHeader = (colors: uiColors) =>
    Html.css`
    margin: 0 0 6px 0;
    color: ${colors.descriptionFg};
    font-family: "Ioskeley Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 0.923rem;
    font-weight: 600;
  `
}

@react.component
let make = (
  ~fileDiff: Diffs.patchFile,
  ~theme: Diffs.FileDiff.theme,
  ~themeType: string,
  ~uiColors: uiColors,
) => {
  let (comments, setComments) = Jotai.Atom.useAtom(State.commentsAtom)
  let fileName = Diffs.fileDiffName(fileDiff)
  let isEmptyFile = Diffs.isEmptyFile(fileDiff)
  let (showFullFile, setShowFullFile) = React.useState(_ => false)

  let toggleComment = React.useCallback0((props: Diffs.lineClickProps) => {
    let lineNumber = int_of_float(props.lineNumber)
    let sideStr = props.annotationSide
    let key = makeKey(fileName, sideStr, lineNumber)

    setComments(prev => {
      switch Js.Dict.get(prev, key) {
      | Some(_) => {
          let newDict = copyDict(prev)
          deleteProp(newDict, key)
          newDict
        }
      | None => {
          let newDict = copyDict(prev)
          Js.Dict.set(newDict, key, {text: "", aiReply: AiIdle})
          newDict
        }
      }
    })
  })

  let validAnnotationKeys = React.useMemo(() => {
    let keys: Js.Dict.t<bool> = Js.Dict.empty()
    Diffs.changedLineAnnotations(fileDiff)->Array.forEach((annotation: Diffs.lineAnnotation) => {
      Js.Dict.set(keys, makeKey(fileName, annotation.side, annotation.lineNumber), true)
    })
    keys
  }, [fileDiff])

  let annotations = React.useMemo(() => {
    Js.Dict.keys(comments)->Array.filterMap(key => {
      switch parseKey(key) {
      | Some((kFileName, side, lineNumber)) if kFileName == fileName =>
        switch Js.Dict.get(validAnnotationKeys, makeKey(fileName, side, lineNumber)) {
        | Some(true) => Some(({side, lineNumber}: Diffs.lineAnnotation))
        | _ => None
        }
      | _ => None
      }
    })
  }, (comments, validAnnotationKeys))

  let fileReviewCommentKeys = React.useMemo(() => {
    Js.Dict.keys(comments)->Array.filter(key => {
      switch parseKey(key) {
      | Some((kFileName, side, lineNumber)) if kFileName == fileName =>
        switch Js.Dict.get(validAnnotationKeys, makeKey(fileName, side, lineNumber)) {
        | Some(true) => false
        | _ => true
        }
      | _ => false
      }
    })
  }, (comments, validAnnotationKeys))

  let optionsObj = React.useMemo3((): Diffs.jsObj =>
    Obj.magic({
      "theme": {"light": theme.light, "dark": theme.dark},
      "themeType": themeType,
      "onLineClick": toggleComment,
      "unsafeCSS": Diffs.fontUnsafeCss,
    })
  , (theme, themeType, toggleComment))

  let fullFileButton = React.useCallback0((_fd: Diffs.patchFile) =>
    <>
      <button
        onClick={ev => {
          let _ = ReactEvent.Mouse.stopPropagation(ev)
          setShowFullFile(_ => true)
        }}
        className={Styles.fullFileButton(uiColors)}>
        {React.string("View full file")}
      </button>
      {isEmptyFile
        ? <span className={Styles.emptyFileLabel(uiColors)}>
            {React.string("(empty file)")}
          </span>
        : React.null}
    </>
  )

  <>
    <Diffs.FileDiff.makeRaw
      fileDiff={fileDiff}
      options={optionsObj}
      lineAnnotations={annotations}
      renderAnnotation={(annotation: Diffs.lineAnnotation) => {
            let ckey = makeKey(fileName, annotation.side, annotation.lineNumber)
            switch Js.Dict.get(comments, ckey) {
            | Some(_) =>
              <CommentBox
                commentKey={ckey}
                lineNumber={annotation.lineNumber}
                comments={comments}
                onSave={setComments}
                onRemove={setComments}
                uiColors={uiColors}
                themeType={themeType}
              />
            | None => <div />
            }
          }}
          renderHeaderPrefix={fullFileButton}
        />
    {fileReviewCommentKeys->Array.length > 0
      ? <div className={Styles.fileReviewList(uiColors)}>
          <div className={Styles.fileReviewHeader(uiColors)}>
            {React.string("File-level review")}
          </div>
          {React.array(
            fileReviewCommentKeys->Array.map(key => {
              switch parseKey(key) {
              | Some((_, _, lineNumber)) =>
                <CommentBox
                  key={key}
                  commentKey={key}
                  lineNumber={lineNumber}
                  comments={comments}
                  onSave={setComments}
                  onRemove={setComments}
                  uiColors={uiColors}
                  themeType={themeType}
                />
              | None => React.null
              }
            }),
          )}
        </div>
      : React.null}
    {showFullFile
      ? <FileViewer
          fileName={fileName}
          theme={theme}
          themeType={themeType}
          uiColors={uiColors}
          onClose={_ => setShowFullFile(_ => false)}
        />
      : React.null}
  </>
}
