open State

let copyDict = (dict: Js.Dict.t<commentData>): Js.Dict.t<commentData> =>
  %raw(`Object.assign({}, dict)`)

let deleteProp = (dict, key) => {
  let _ = %raw(`delete dict[key]`)
}

let hexToRgba = (hex: string, alpha: float): string => {
  %raw(`((hex, alpha) => {
      const cleaned = hex.startsWith('#') ? hex.slice(1) : hex;
      if (cleaned.length < 6) return hex;
      const r = parseInt(cleaned.slice(0, 2), 16);
      const g = parseInt(cleaned.slice(2, 4), 16);
      const b = parseInt(cleaned.slice(4, 6), 16);
      if (isNaN(r) || isNaN(g) || isNaN(b)) return hex;
      return 'rgba(' + r + ', ' + g + ', ' + b + ', ' + alpha + ')';
    })(hex, alpha)`)
}

module Styles = {
  let box = (colors: uiColors) =>
    Html.css`
    display: flex;
    gap: 8px;
    margin-top: 4px;
    margin-bottom: 4px;
    padding: 8px;
    border-radius: 4px;
    background-color: ${colors.surfaceBg};
    border: 1px solid ${colors.border};
  `

  let textarea = (colors: uiColors) => {
    let focusShadow = hexToRgba(colors.focusBorder, 0.1)
    Html.css`
      flex: 1;
      min-height: 80px;
      max-height: 200px;
      padding: 6px;
      border-radius: 4px;
      border: 1px solid ${colors.inputBorder};
      background-color: ${colors.inputBg};
      color: ${colors.inputFg};
      font-family: "Ioskeley Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 14px;
      line-height: 1.5;
      resize: vertical;

      &::placeholder {
        color: ${colors.inputPlaceholder};
      }

      &:hover {
        border-color: ${colors.descriptionFg};
      }

      &:focus {
        outline: none;
        border-color: ${colors.focusBorder};
        box-shadow: 0 0 0 3px ${focusShadow};
      }
    `
  }

  let removeButton = (colors: uiColors) =>
    Html.css`
    padding: 8px 12px;
    border-radius: 4px;
    border: 1px solid transparent;
    background-color: ${colors.dangerBg};
    color: #ffffff;
    font-size: 13px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s ease;
    min-width: 80px;
    display: flex;
    align-items: center;
    justify-content: center;
  `

  let removeButtonHover = (colors: uiColors) =>
    Html.css`
    &:hover {
      background-color: ${colors.dangerHoverBg};
      box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
      transform: translateY(-1px);
    }
    &:active {
      background-color: ${colors.dangerBg};
      transform: translateY(0);
    }
  `

  let aiReply = (colors: uiColors) =>
    Html.css`
    margin-top: 8px;
    padding: 10px 12px;
    border-radius: 4px;
    background-color: ${colors.surfaceBg};
    border-left: 3px solid ${colors.focusBorder};
    font-size: 13px;
    line-height: 1.5;
    color: ${colors.fg};
    word-wrap: break-word;
    overflow-wrap: break-word;

    & h1, & h2, & h3, & h4, & h5, & h6 {
      margin: 12px 0 6px 0;
      font-weight: 600;
      color: ${colors.fg};
    }
    & h1 { font-size: 18px; }
    & h2 { font-size: 16px; }
    & h3 { font-size: 15px; }
    & h4, & h5, & h6 { font-size: 14px; }

    & p {
      margin: 4px 0;
      text-wrap: auto;
    }

    & ul, & ol {
      margin: 4px 0;
      padding-left: 24px;
      text-wrap: auto;
    }

    & li {
      margin: 1px 0;
    }

    & li > p {
      margin: 0;
    }

    & a {
      color: ${colors.focusBorder};
      text-decoration: underline;
    }

    & strong {
      font-weight: 600;
    }

    & em {
      font-style: italic;
    }

    & blockquote {
      margin: 6px 0;
      padding: 4px 12px;
      border-left: 2px solid ${colors.border};
      color: ${colors.descriptionFg};
    }

    & hr {
      border: none;
      border-top: 1px solid ${colors.border};
      margin: 12px 0;
    }

    & code {
      font-family: "Ioskeley Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 12.5px;
      padding: 1px 4px;
      border-radius: 3px;
      background-color: ${colors.inputBg};
      overflow-wrap: anywhere;
    }

    & pre {
      margin: 8px 0;
      padding: 10px 12px;
      border-radius: 4px;
      overflow-x: auto;
      font-size: 12.5px;
      line-height: 1.5;
    }

    & pre code {
      padding: 0;
      background-color: transparent;
      font-size: inherit;
      overflow-wrap: normal;
    }
  `

  let aiLoading = Html.css`
    margin-top: 8px;
    padding: 8px 12px;
    font-size: 13px;
    color: #9ca3af;
    font-style: italic;
  `

  let aiError = (colors: uiColors) =>
    Html.css`
    margin-top: 8px;
    padding: 8px 12px;
    border-radius: 4px;
    background-color: ${colors.dangerBg};
    color: #ffffff;
    font-size: 13px;
  `

  let reviewMeta = (colors: uiColors) =>
    Html.css`
    margin-top: 8px;
    padding: 10px 12px;
    border-radius: 4px;
    border: 1px solid ${colors.border};
    background-color: ${colors.inputBg};
    color: ${colors.fg};
    font-size: 13px;
    line-height: 1.45;
  `

  let suggestionPre = (colors: uiColors) =>
    Html.css`
    margin: 8px 0 0 0;
    padding: 8px;
    border-radius: 4px;
    overflow-x: auto;
    white-space: pre-wrap;
    background-color: ${colors.surfaceBg};
    border: 1px solid ${colors.border};
    font-family: "Ioskeley Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 12px;
  `

  let applyButton = (colors: uiColors) =>
    Html.css`
    margin-top: 8px;
    padding: 6px 10px;
    border-radius: 4px;
    border: 1px solid ${colors.focusBorder};
    background-color: ${colors.buttonBg};
    color: ${colors.buttonFg};
    font-size: 13px;
    cursor: pointer;
    &:hover { background-color: ${colors.buttonHoverBg}; }
    &:disabled { opacity: 0.6; cursor: not-allowed; }
  `

  let applyResult = (colors: uiColors) =>
    Html.css`
    margin-top: 8px;
    color: ${colors.descriptionFg};
    font-size: 12px;
  `
}

@react.component
let make = (
  ~commentKey: string,
  ~lineNumber: int,
  ~comments: Js.Dict.t<commentData>,
  ~onSave: (Js.Dict.t<commentData> => Js.Dict.t<commentData>) => unit,
  ~onRemove: (Js.Dict.t<commentData> => Js.Dict.t<commentData>) => unit,
  ~uiColors: uiColors,
  ~themeType: string,
) => {
  let (reviewSuggestions, setReviewSuggestions) = Jotai.Atom.useAtom(State.reviewSuggestionsAtom)
  let comment =
    Js.Dict.get(comments, commentKey)->Belt.Option.getWithDefault({text: "", aiReply: AiIdle})
  let reviewSuggestion = Js.Dict.get(reviewSuggestions, commentKey)
  let isReviewComment = switch reviewSuggestion {
  | Some(_) => true
  | None => false
  }
  let initialText: string = comment.text
  let (localText, setLocalText) = React.useState(() => initialText)

  React.useEffect1(() => {
    setLocalText(_ => initialText)
    None
  }, [initialText])

  let saveText = (text: string) => {
    onSave(prev => {
      let newDict = copyDict(prev)
      let existing =
        Js.Dict.get(prev, commentKey)->Belt.Option.getWithDefault({text: "", aiReply: AiIdle})
      Js.Dict.set(newDict, commentKey, {text: text, aiReply: existing.aiReply})
      newDict
    })
  }

  let saveComment = _event => saveText(localText)

  let removeComment = _event => {
    onRemove(prev => {
      let newDict = copyDict(prev)
      deleteProp(newDict, commentKey)
      newDict
    })
  }

  let updateReviewSuggestion = (next: State.reviewSuggestion): unit => {
    setReviewSuggestions(prev => {
      let newDict: Js.Dict.t<State.reviewSuggestion> = %raw(`Object.assign({}, prev)`)
      Js.Dict.set(newDict, commentKey, next)
      newDict
    })
  }

  let handleApplySuggestion = (item: State.reviewSuggestion, _event) => {
    if !item.isApplying {
      Js.log2("[BAKA UI] Apply suggestion clicked", commentKey)
      Js.log2("[BAKA UI] Apply suggestion bytes", item.suggestion->String.length)
      updateReviewSuggestion({...item, isApplying: true, applyResult: None, applyError: None})
      let onSuccess = (message: string): Js.Promise.t<unit> => {
        Js.log2("[BAKA UI] Apply suggestion success", message)
        updateReviewSuggestion({
          ...item,
          isApplying: false,
          applyResult: Some(message),
          applyError: None,
        })
        let _ = %raw(`window.__bakaDiffReloadRequestCount = (window.__bakaDiffReloadRequestCount || 0) + 1`)
        Js.Promise2.resolve()
      }
      let onError = (err: Js.Promise2.error): Js.Promise.t<unit> => {
        let msg = %raw(`String(err).replace(/^Error: /, '')`)
        Js.log2("[BAKA UI] Apply suggestion error", msg)
        updateReviewSuggestion({
          ...item,
          isApplying: false,
          applyResult: None,
          applyError: Some(msg),
        })
        Js.Promise2.resolve()
      }
      let _ = Js.Promise2.catch(
        Js.Promise2.then(
          Ipc.callApplyReviewSuggestion({
            commentKey: commentKey,
            suggestion: item.suggestion,
          }),
          onSuccess,
        ),
        onError,
      )
    }
  }

  let aiReplyContent = switch comment.aiReply {
  | AiIdle => <> </>
  | AiStreaming(partial) =>
    <div className={Styles.aiLoading}> {React.string("Pi is thinking" ++ "..." ++ partial)} </div>
  | AiDone(replyText) =>
    <div className={Styles.aiReply(uiColors)}>
      <Markdown text={replyText} themeType={themeType} />
    </div>
  | AiError(errMsg) => {
      Js.log(errMsg)
      <div className={Styles.aiError(uiColors)}> {React.string("Pi error: " ++ errMsg)} </div>
    }
  }

  let reviewSuggestionContent = switch reviewSuggestion {
  | Some(item) if item.actionable =>
    <div className={Styles.reviewMeta(uiColors)}>
      <div>
        {React.string("Severity: " ++ item.severity)}
      </div>
      <details>
        <summary>{React.string("Suggested fix")}</summary>
        <pre className={Styles.suggestionPre(uiColors)}>
          {React.string(item.suggestion)}
        </pre>
      </details>
      <button
        onClick={ev => handleApplySuggestion(item, ev)}
        disabled={item.isApplying}
        className={Styles.applyButton(uiColors)}>
        {React.string(if item.isApplying { "Applying..." } else { "Apply suggestion" })}
      </button>
      {switch item.applyResult {
       | Some(message) =>
         <div className={Styles.applyResult(uiColors)}>{React.string(message)}</div>
       | None => React.null
       }}
      {switch item.applyError {
       | Some(message) =>
         <div className={Styles.aiError(uiColors)}>{React.string("Apply failed: " ++ message)}</div>
       | None => React.null
       }}
    </div>
  | Some(item) =>
    <div className={Styles.reviewMeta(uiColors)}>
      {React.string("Severity: " ++ item.severity)}
    </div>
  | None => React.null
  }

  <>
    <div className={Styles.box(uiColors)}>
      <textarea
        value={localText}
        readOnly={isReviewComment}
        onChange={(ev: JsxEvent.Form.t) => {
          if !isReviewComment {
            let target = JsxEvent.Form.target(ev)
            let nextText: string = target["value"]
            setLocalText(_ => nextText)
            saveText(nextText)
          }
        }}
        onBlur={saveComment}
        placeholder={"Add a comment for line " ++ Int.toString(lineNumber) ++ "..."}
        className={Styles.textarea(uiColors)}
      />
      <button
        onClick={removeComment}
        className={Html.cx([Styles.removeButton(uiColors), Styles.removeButtonHover(uiColors)])}>
        {React.string("Remove")}
      </button>
    </div>
    {aiReplyContent}
    {reviewSuggestionContent}
  </>
}
