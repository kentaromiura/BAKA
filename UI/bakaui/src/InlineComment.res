open State

let copyDict = (dict: Js.Dict.t<commentData>): Js.Dict.t<commentData> =>
  %raw(`Object.assign({}, dict)`)

let deleteProp = (dict, key) => {
  let _ = %raw(`delete dict[key]`)
}

let makeKey = (fileName: string, side: string, lineNumber: int): string =>
  fileName ++ "|" ++ side ++ "|" ++ Int.toString(lineNumber)

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
    let side = Js.Array.unsafe_get(parts, 1)
    let line = Js.Array.unsafe_get(parts, 2)
    let translatedSide = switch side {
    | "+" => "additions"
    | "-" => "deletions"
    | _ => side
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
    font-size: 12px;
    cursor: pointer;
    transition: all 0.15s ease;
    &:hover {
      background-color: ${colors.hoverBg};
      border-color: ${colors.focusBorder};
    }
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
  let (showFullFile, setShowFullFile) = React.useState(_ => false)

  let toggleComment = React.useCallback0(props => {
    let lineNumber = int_of_float(%raw(`props["lineNumber"]`))
    let sideStr: string = %raw(`props["annotationSide"]`)
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

  let annotations = React.useMemo(() => {
    Js.Dict.keys(comments)->Array.filterMap(key => {
      switch parseKey(key) {
      | Some((kFileName, side, lineNumber)) if kFileName == fileName =>
        Some(({side, lineNumber}: Diffs.lineAnnotation))
      | _ => None
      }
    })
  }, [comments])

  let optionsObj = React.useMemo3((): Diffs.jsObj =>
    Obj.magic({
      "theme": {"light": theme.light, "dark": theme.dark},
      "themeType": themeType,
      "onLineClick": toggleComment,
    })
  , (theme, themeType, toggleComment))

  let fullFileButton = React.useCallback0((_fd: Diffs.patchFile) =>
    <button
      onClick={ev => {
        let _ = ReactEvent.Mouse.stopPropagation(ev)
        setShowFullFile(_ => true)
      }}
      className={Styles.fullFileButton(uiColors)}>
      {React.string("View full file")}
    </button>
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
