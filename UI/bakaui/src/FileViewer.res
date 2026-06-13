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

module Styles = {
  let backdrop = Html.css`
    position: fixed;
    inset: 0;
    background-color: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
  `

  let content = (colors: uiColors) =>
    Html.css`
    background-color: ${colors.bg};
    color: ${colors.fg};
    border: 1px solid ${colors.border};
    border-radius: 8px;
    width: 90vw;
    max-width: 1200px;
    height: 90vh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.3);
  `

  let header = (colors: uiColors) =>
    Html.css`
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 16px;
    border-bottom: 1px solid ${colors.border};
    background-color: ${colors.surfaceBg};
  `

  let headerTitle = Html.css`
    margin: 0;
    font-size: 14px;
    font-weight: 600;
    font-family: monospace;
  `

  let headerActions = Html.css`
    display: flex;
    align-items: center;
    gap: 8px;
  `

  let askButton = (colors: uiColors) =>
    Html.css`
    padding: 6px 12px;
    border-radius: 4px;
    border: 1px solid ${colors.focusBorder};
    background-color: ${colors.focusBorder};
    color: #ffffff;
    font-size: 13px;
    font-weight: 500;
    cursor: pointer;
    transition: opacity 0.2s ease;
    &:hover { opacity: 0.85; }
    &:disabled { opacity: 0.5; cursor: not-allowed; }
  `

  let closeButton = (colors: uiColors) =>
    Html.css`
    padding: 4px 10px;
    border-radius: 4px;
    border: 1px solid ${colors.border};
    background-color: transparent;
    color: ${colors.fg};
    font-size: 16px;
    line-height: 1;
    cursor: pointer;
    &:hover { background-color: ${colors.hoverBg}; }
  `

  let body = Html.css`
    flex: 1;
    min-height: 0;
    overflow: hidden;
    background-color: #ffffff;
  `

  let bodyDark = Html.css`
    flex: 1;
    min-height: 0;
    overflow: hidden;
    background-color: #0d1117;
  `

  let status = (colors: uiColors) =>
    Html.css`
    padding: 24px;
    color: ${colors.descriptionFg};
    font-size: 13px;
    text-align: center;
  `

  let error = (colors: uiColors) =>
    Html.css`
    padding: 12px 16px;
    margin: 12px;
    border-radius: 4px;
    background-color: ${colors.dangerBg};
    color: #ffffff;
    font-size: 13px;
  `
}

@react.component
let make = (
  ~fileName: string,
  ~theme: Diffs.FileDiff.theme,
  ~themeType: string,
  ~uiColors: uiColors,
  ~onClose: unit => unit,
) => {
  // Local comment state — discarded on close, does not touch Jotai
  let initialComments: Js.Dict.t<commentData> = Js.Dict.empty()
  let (comments, setComments) = React.useState(() => initialComments)
  let (patch, setPatch) = React.useState(() => None)
  let (error, setError) = React.useState(() => None)
  let (isAskingPi, setIsAskingPi) = React.useState(() => false)

  // Fetch the full-context patch on mount
  React.useEffect0(() => {
    Ipc.callGetFilePatch(fileName)
      ->Js.Promise2.then(p => {
        setPatch(_ => Some(p))
        Js.Promise2.resolve()
      })
      ->Js.Promise2.catch(e => {
        setError(_ => Some(Js.String.make(e)))
        Js.Promise2.resolve()
      })
      ->ignore
    None
  })

  // Close on Escape. The whole effect lives in one %raw block so the
  // handler closure can capture onClose and the cleanup can reference
  // the same handler instance. The IIFE returns a cleanup function
  // which we return from the effect so React calls it on unmount.
  React.useEffect0(() => {
    let cleanup = %raw(`
      (function() {
        var handler = function(ev) {
          if (ev.key === "Escape") onClose();
        };
        window.addEventListener("keydown", handler);
        return function() { window.removeEventListener("keydown", handler); };
      })()
    `)
    Some(cleanup)
  })

  // Parse the patch into a single fileDiff
  let fileDiff = React.useMemo1(() =>
    switch patch {
    | Some(p) =>
      let parsed = Diffs.parsePatchFiles(p)
      switch Belt.Array.get(parsed, 0) {
      | Some(first) =>
        switch Belt.Array.get(first.files, 0) {
        | Some(fd) => fd
        | None => Obj.magic(Js.null)
        }
      | None => Obj.magic(Js.null)
      }
    | None => Obj.magic(Js.null)
    }
  , [patch])

  // Derive lineAnnotations from local comments
  let annotations = React.useMemo1(() => {
    Js.Dict.keys(comments)->Array.filterMap(key => {
      switch parseKey(key) {
      | Some((kFileName, side, lineNumber)) if kFileName == fileName =>
        Some(({side, lineNumber}: Diffs.lineAnnotation))
      | _ => None
      }
    })
  }, [comments])

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

  let optionsObj = React.useMemo3((): Diffs.jsObj =>
    Obj.magic({
      "theme": {"light": theme.light, "dark": theme.dark},
      "themeType": themeType,
      "onLineClick": toggleComment,
    })
  , (theme, themeType, toggleComment))

  // Ask AI for all non-empty local comments. Passes the full file patch
  // (downloaded once at mount) so the AI sees the whole file as context.
  let handleAskPi = _event => {
    if !isAskingPi {
      let payloadComments = Js.Dict.keys(comments)->Array.filterMap(key => {
        switch Js.Dict.get(comments, key) {
        | Some(c) if c.text->String.trim->String.length > 0 && c.aiReply == State.AiIdle =>
          Some({commentKey: key, text: c.text}: Ipc.askPiRequest)
        | _ => None
        }
      })

      if payloadComments->Array.length == 0 {
        setComments(prev => {
          let newDict = copyDict(prev)
          Js.Dict.keys(newDict)->Array.forEach(key => {
            switch Js.Dict.get(newDict, key) {
            | Some(c) if c.text->String.trim->String.length > 0 && c.aiReply == State.AiIdle =>
              Js.Dict.set(newDict, key, {text: c.text, aiReply: State.AiDone("No new questions — your comments are already reviewed.")})
            | _ => ()
            }
          })
          newDict
        })
      } else {
        setComments(prev => {
          let newDict = copyDict(prev)
          payloadComments->Array.forEach(pc => {
            switch Js.Dict.get(newDict, pc.commentKey) {
            | Some(c) =>
              Js.Dict.set(newDict, pc.commentKey, {text: c.text, aiReply: State.AiStreaming("")})
            | None => ()
            }
          })
          newDict
        })
        setIsAskingPi(_ => true)

        let diffText = Belt.Option.getWithDefault(patch, "")
        let onSuccess = (replies: array<Ipc.askPiReply>): Js.Promise.t<unit> => {
          setComments(prev => {
            let newDict = copyDict(prev)
            replies->Array.forEach(reply => {
              let key = reply.commentKey
              switch Js.Dict.get(newDict, key) {
              | Some(c) =>
                Js.Dict.set(newDict, key, {text: c.text, aiReply: State.AiDone(reply.reply)})
              | None => ()
              }
            })
            newDict
          })
          setIsAskingPi(_ => false)
          Js.Promise2.resolve()
        }
        let onError = (err: Js.Promise2.error): Js.Promise.t<unit> => {
          let msg = %raw(`String(err).replace(/^Error: /, '')`)
          setComments(prev => {
            let newDict = copyDict(prev)
            payloadComments->Array.forEach(pc => {
              switch Js.Dict.get(newDict, pc.commentKey) {
              | Some(c) =>
                Js.Dict.set(newDict, pc.commentKey, {text: c.text, aiReply: State.AiError(msg)})
              | None => ()
              }
            })
            newDict
          })
          setIsAskingPi(_ => false)
          Js.Promise2.resolve()
        }

        let _ = Js.Promise2.catch(
          Js.Promise2.then(Ipc.callAskPiWithDiff(diffText, payloadComments), onSuccess),
          onError,
        )
      }
    }
  }

  let stopProp = (ev: JsxEvent.Mouse.t) => {
    let _ = ReactEvent.Mouse.stopPropagation(ev)
  }

  let hasPending = Js.Dict.keys(comments)->Array.some(key => {
    switch Js.Dict.get(comments, key) {
    | Some(c) => c.text->String.trim->String.length > 0 && c.aiReply == State.AiIdle
    | None => false
    }
  })

  <div className={Styles.backdrop} onClick={_ => onClose()}>
    <div className={Styles.content(uiColors)} onClick={stopProp}>
      <div className={Styles.header(uiColors)}>
        <h3 className={Styles.headerTitle}>
          {React.string(fileName ++ " (full file)" ++ if (Diffs.isEmptyFile(fileDiff)) { " (empty file)" } else { "" })}
        </h3>
        <div className={Styles.headerActions}>
          <button
            onClick={handleAskPi}
            disabled={isAskingPi || !hasPending}
            className={Styles.askButton(uiColors)}>
            {React.string(isAskingPi ? "Asking..." : "Ask AI")}
          </button>
          <button onClick={_ => onClose()} className={Styles.closeButton(uiColors)}>
            {React.string("✕")}
          </button>
        </div>
      </div>
      <div className={themeType === "dark" ? Styles.bodyDark : Styles.body}>
        {switch (patch, error) {
         | (Some(_), None) =>
           <Diffs.Virtualizer
             style={%raw(`{"height": "100%", "overflow-y": "auto"}`)}>
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
             />
           </Diffs.Virtualizer>
         | (None, Some(e)) =>
           <div className={Styles.error(uiColors)}>
             {React.string("Failed to load file: " ++ e)}
           </div>
         | (None, None) =>
           <div className={Styles.status(uiColors)}>
             {React.string("Loading...")}
           </div>
         | (Some(_), Some(_)) =>
           <div className={Styles.status(uiColors)}>
             {React.string("Loaded")}
           </div>
         }}
      </div>
    </div>
  </div>
}
