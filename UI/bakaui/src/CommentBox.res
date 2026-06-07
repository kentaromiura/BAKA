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
      font-family: monospace;
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
      font-family: monospace;
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
  let comment =
    Js.Dict.get(comments, commentKey)->Belt.Option.getWithDefault({text: "", aiReply: AiIdle})
  let initialText: string = comment.text
  let (localText, setLocalText) = React.useState(() => initialText)

  React.useEffect1(() => {
    setLocalText(_ => initialText)
    None
  }, [initialText])

  let saveComment = _event => {
    onSave(prev => {
      let newDict = copyDict(prev)
      let existing =
        Js.Dict.get(prev, commentKey)->Belt.Option.getWithDefault({text: "", aiReply: AiIdle})
      Js.Dict.set(newDict, commentKey, {text: localText, aiReply: existing.aiReply})
      newDict
    })
  }

  let removeComment = _event => {
    onRemove(prev => {
      let newDict = copyDict(prev)
      deleteProp(newDict, commentKey)
      newDict
    })
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

  <>
    <div className={Styles.box(uiColors)}>
      <textarea
        value={localText}
        onChange={(ev: JsxEvent.Form.t) => {
          let target = JsxEvent.Form.target(ev)
          setLocalText(_ => target["value"])
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
  </>
}
