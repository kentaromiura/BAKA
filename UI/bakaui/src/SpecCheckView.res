open State

type phase =
  | Entering
  | Checking
  | Ready(Ipc.fullReviewResult)
  | Failed(string)

type decision =
  | Pending
  | Fixing
  | Fixed(string)
  | LeftOut
  | FixFailed(string)

type uploadedSpec = {
  name: string,
  text: string,
}

let readSelectedFile: JsxEvent.Form.t => Js.Promise.t<uploadedSpec> =
  %raw(`event => new Promise((resolve, reject) => {
    const file = event.target.files && event.target.files[0];
    if (!file) {
      reject(new Error("No file selected"));
      return;
    }
    const reader = new FileReader();
    reader.onload = () => resolve({name: file.name, text: String(reader.result || "")});
    reader.onerror = () => reject(new Error("Could not read the selected file"));
    reader.readAsText(file);
  })`)

module Styles = {
  let overlay = Html.css`
    position: fixed;
    inset: 0;
    z-index: 1000;
    display: grid;
    place-items: center;
    padding: 24px;
    background: rgba(0, 0, 0, 0.58);
  `

  let dialog = (colors: uiColors) => Html.css`
    width: min(820px, 100%);
    max-height: min(820px, calc(100vh - 48px));
    display: flex;
    flex-direction: column;
    overflow: hidden;
    border: 1px solid ${colors.border};
    border-radius: 10px;
    background: ${colors.surfaceBg};
    color: ${colors.fg};
    box-shadow: 0 24px 70px rgba(0, 0, 0, 0.38);
  `

  let header = (colors: uiColors) => Html.css`
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 16px;
    padding: 18px 20px;
    border-bottom: 1px solid ${colors.border};
  `

  let title = Html.css`
    margin: 0 0 5px;
    font-size: 1.25rem;
  `

  let subtitle = (colors: uiColors) => Html.css`
    margin: 0;
    color: ${colors.descriptionFg};
    line-height: 1.45;
  `

  let body = Html.css`
    display: flex;
    flex-direction: column;
    gap: 16px;
    padding: 20px;
    overflow: auto;
  `

  let textarea = (colors: uiColors) => Html.css`
    width: 100%;
    min-height: 260px;
    box-sizing: border-box;
    resize: vertical;
    padding: 12px;
    border: 1px solid ${colors.inputBorder};
    border-radius: 6px;
    background: ${colors.inputBg};
    color: ${colors.inputFg};
    line-height: 1.5;

    &:focus-visible {
      outline: 2px solid ${colors.focusBorder};
      outline-offset: 1px;
    }
  `

  let row = Html.css`
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 10px;
  `

  let button = (colors: uiColors, primary: bool, disabled: bool) => Html.css`
    padding: 7px 12px;
    border: 1px solid ${primary ? colors.focusBorder : colors.border};
    border-radius: 5px;
    background: ${primary ? colors.selectionBg : colors.buttonBg};
    color: ${colors.buttonFg};
    cursor: ${disabled ? "not-allowed" : "pointer"};
    opacity: ${disabled ? "0.55" : "1"};

    &:hover {
      background: ${disabled ? (primary ? colors.selectionBg : colors.buttonBg) : colors.buttonHoverBg};
    }
  `

  let fileButton = (colors: uiColors) => Html.css`
    position: relative;
    overflow: hidden;
    display: inline-flex;
    align-items: center;
    padding: 7px 12px;
    border: 1px solid ${colors.border};
    border-radius: 5px;
    background: ${colors.buttonBg};
    color: ${colors.buttonFg};
    cursor: pointer;

    &:hover {
      background: ${colors.buttonHoverBg};
    }

    & input {
      position: absolute;
      inset: 0;
      opacity: 0;
      cursor: pointer;
    }
  `

  let summary = (colors: uiColors) => Html.css`
    padding: 12px;
    border: 1px solid ${colors.border};
    border-radius: 6px;
    background: ${colors.inputBg};
    line-height: 1.5;
  `

  let finding = (colors: uiColors) => Html.css`
    display: flex;
    flex-direction: column;
    gap: 9px;
    padding: 14px;
    border: 1px solid ${colors.border};
    border-radius: 7px;
    background: ${colors.bg};
  `

  let findingHeader = Html.css`
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 12px;
  `

  let location = (colors: uiColors) => Html.css`
    color: ${colors.descriptionFg};
    font-size: 0.9rem;
  `

  let status = (colors: uiColors) => Html.css`
    color: ${colors.descriptionFg};
    font-size: 0.92rem;
  `

  let report = (colors: uiColors) => Html.css`
    padding: 16px;
    border: 1px solid ${colors.focusBorder};
    border-radius: 7px;
    background: ${colors.inputBg};
  `

  let error = (colors: uiColors) => Html.css`
    color: ${colors.dangerBg};
    white-space: pre-wrap;
  `
}

let decisionLabel = decision =>
  switch decision {
  | Pending => "Awaiting your decision"
  | Fixing => "Applying and validating the fix…"
  | Fixed(result) => "Fixed — " ++ result
  | LeftOut => "Left out by request"
  | FixFailed(message) => "Fix failed — " ++ message
  }

let buildReport = (review: Ipc.fullReviewResult, decisions: Js.Dict.t<decision>) => {
  let fixed = ref(0)
  let leftOut = ref(0)
  let unresolved = ref(0)
  let details = review.findings->Array.mapWithIndex((finding, index) => {
    let state = Js.Dict.get(decisions, Int.toString(index))->Option.getOr(Pending)
    let outcome = switch state {
    | Fixed(_) =>
      fixed.contents = fixed.contents + 1
      "Fixed"
    | LeftOut =>
      leftOut.contents = leftOut.contents + 1
      "Left out"
    | FixFailed(message) =>
      unresolved.contents = unresolved.contents + 1
      "Not fixed: " ++ message
    | Pending | Fixing =>
      unresolved.contents = unresolved.contents + 1
      "Unresolved"
    }
    "- **" ++ outcome ++ "** — " ++ finding.summary ++ " (`" ++ finding.commentKey ++ "`)"
  })->Array.join("\n")

  "# Specification check report\n\n" ++
  review.summary ++ "\n\n" ++
  "- Fixed: " ++ Int.toString(fixed.contents) ++ "\n" ++
  "- Left out: " ++ Int.toString(leftOut.contents) ++ "\n" ++
  "- Unresolved: " ++ Int.toString(unresolved.contents) ++ "\n\n" ++
  "## Outcomes\n\n" ++
  if details == "" { "No differences were found." } else { details }
}

@react.component
let make = (~uiColors: uiColors, ~themeType: string, ~onClose: unit => unit, ~onChanged: unit => unit) => {
  let (spec, setSpec) = React.useState(() => "")
  let (sourceName, setSourceName) = React.useState(() => "Pasted specification")
  let (phase, setPhase) = React.useState(() => Entering)
  let (decisions, setDecisions) = React.useState((): Js.Dict.t<decision> => Js.Dict.empty())
  let (report, setReport) = React.useState((): option<string> => None)

  let handleFile = event => {
    let onSuccess = (uploaded: uploadedSpec) => {
      setSpec(_ => uploaded.text)
      setSourceName(_ => uploaded.name)
      setPhase(_ => Entering)
      setReport(_ => None)
      Js.Promise2.resolve()
    }
    let onError = (error: Js.Promise2.error) => {
      setPhase(_ => Failed(Raw.errorMessage(error)))
      Js.Promise2.resolve()
    }
    let _ = Js.Promise2.catch(Js.Promise2.then(readSelectedFile(event), onSuccess), onError)
  }

  let handleCheck = _ => {
    let trimmed = spec->String.trim
    if trimmed->String.length > 0 {
      setPhase(_ => Checking)
      setReport(_ => None)
      let onSuccess = (review: Ipc.fullReviewResult) => {
        let initial: Js.Dict.t<decision> = Js.Dict.empty()
        review.findings->Array.forEachWithIndex((_, index) =>
          Js.Dict.set(initial, Int.toString(index), Pending)
        )
        setDecisions(_ => initial)
        setPhase(_ => Ready(review))
        Js.Promise2.resolve()
      }
      let onError = (error: Js.Promise2.error) => {
        setPhase(_ => Failed(Raw.errorMessage(error)))
        Js.Promise2.resolve()
      }
      let _ = Js.Promise2.catch(Js.Promise2.then(Ipc.callCheckAgainstSpec(trimmed), onSuccess), onError)
    }
  }

  let leaveOut = index => {
    setDecisions(previous => {
      let next = Raw.copyDict(previous)
      Js.Dict.set(next, Int.toString(index), LeftOut)
      next
    })
    setReport(_ => None)
  }

  let applyFix = (index, finding: Ipc.fullReviewFinding) => {
    let key = Int.toString(index)
    setDecisions(previous => {
      let next = Raw.copyDict(previous)
      Js.Dict.set(next, key, Fixing)
      next
    })
    setReport(_ => None)
    let onSuccess = result => {
      setDecisions(previous => {
        let next = Raw.copyDict(previous)
        Js.Dict.set(next, key, Fixed(result))
        next
      })
      onChanged()
      Js.Promise2.resolve()
    }
    let onError = (error: Js.Promise2.error) => {
      setDecisions(previous => {
        let next = Raw.copyDict(previous)
        Js.Dict.set(next, key, FixFailed(Raw.errorMessage(error)))
        next
      })
      Js.Promise2.resolve()
    }
    let request: Ipc.applySuggestionRequest = {
      commentKey: finding.commentKey,
      suggestion: finding.suggestion,
    }
    let _ = Js.Promise2.catch(Js.Promise2.then(Ipc.callApplyReviewSuggestion(request), onSuccess), onError)
  }

  <div className={Styles.overlay} role="presentation">
    <section className={Styles.dialog(uiColors)} role="dialog" ariaModal=true ariaLabelledby="spec-check-title">
      <header className={Styles.header(uiColors)}>
        <div>
          <h2 id="spec-check-title" className={Styles.title}>{React.string("Check against specification")}</h2>
          <p className={Styles.subtitle(uiColors)}>
            {React.string("Paste Markdown or upload a .md file. Pi will compare the current modifications with the requirements.")}
          </p>
        </div>
        <button type_="button" className={Styles.button(uiColors, false, false)} onClick={_ => onClose()}>
          {React.string("Close")}
        </button>
      </header>
      <div className={Styles.body}>
        {switch phase {
        | Entering | Failed(_) =>
          <>
            <div className={Styles.row}>
              <label className={Styles.fileButton(uiColors)}>
                {React.string("Upload Markdown")}
                <input type_="file" accept=".md,.markdown,text/markdown,text/plain" onChange={handleFile} />
              </label>
              <span className={Styles.status(uiColors)}>{React.string(sourceName)}</span>
            </div>
            <textarea
              className={Styles.textarea(uiColors)}
              value={spec}
              placeholder="Paste the specification here…"
              onChange={event => {
                setSpec(_ => JsxEvent.Form.target(event)["value"])
                setSourceName(_ => "Pasted specification")
                setPhase(_ => Entering)
                setReport(_ => None)
              }}
            />
            {switch phase {
            | Failed(message) => <div className={Styles.error(uiColors)}>{React.string(message)}</div>
            | _ => React.null
            }}
            <div className={Styles.row}>
              <button
                type_="button"
                disabled={spec->String.trim->String.length == 0}
                className={Styles.button(uiColors, true, spec->String.trim->String.length == 0)}
                onClick={handleCheck}
              >
                {React.string("Check modifications")}
              </button>
            </div>
          </>
        | Checking =>
          <div className={Styles.summary(uiColors)}>
            {React.string("Pi is comparing the current diff with the specification…")}
          </div>
        | Ready(review) =>
          <>
            <div className={Styles.summary(uiColors)}><Markdown text={review.summary} themeType={themeType} /></div>
            {review.findings->Array.length == 0
              ? <div className={Styles.summary(uiColors)}>
                  {React.string("No differences from the specification were found.")}
                </div>
              : React.array(review.findings->Array.mapWithIndex((finding, index) => {
                  let state = Js.Dict.get(decisions, Int.toString(index))->Option.getOr(Pending)
                  let busy = state == Fixing
                  <article key={Int.toString(index)} className={Styles.finding(uiColors)}>
                    <div className={Styles.findingHeader}>
                      <strong>{React.string(finding.summary)}</strong>
                      <span className={Styles.location(uiColors)}>{React.string(finding.commentKey)}</span>
                    </div>
                    <Markdown text={finding.body} themeType={themeType} />
                    <div className={Styles.status(uiColors)}>{React.string(decisionLabel(state))}</div>
                    <div className={Styles.row}>
                      {finding.actionable
                        ? <button
                            type_="button"
                            disabled={busy}
                            className={Styles.button(uiColors, true, busy)}
                            onClick={_ => applyFix(index, finding)}
                          >
                            {React.string(switch state {
                            | Fixing => "Fixing…"
                            | Fixed(_) => "Fix again"
                            | _ => "Fix this"
                            })}
                          </button>
                        : React.null}
                      <button
                        type_="button"
                        disabled={busy}
                        className={Styles.button(uiColors, false, busy)}
                        onClick={_ => leaveOut(index)}
                      >
                        {React.string("Leave out")}
                      </button>
                    </div>
                  </article>
                }))}
            <div className={Styles.row}>
              <button
                type_="button"
                className={Styles.button(uiColors, true, false)}
                onClick={_ => setReport(_ => Some(buildReport(review, decisions)))}
              >
                {React.string("Produce report")}
              </button>
              <button type_="button" className={Styles.button(uiColors, false, false)} onClick={_ => setPhase(_ => Entering)}>
                {React.string("Change specification")}
              </button>
            </div>
            {switch report {
            | Some(text) => <div className={Styles.report(uiColors)}><Markdown text themeType={themeType} /></div>
            | None => React.null
            }}
          </>
        }}
      </div>
    </section>
  </div>
}
