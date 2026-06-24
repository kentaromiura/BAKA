open State

let str = React.string

module Styles = {
  let container = (colors: uiColors) =>
    Html.css`
    display: flex;
    flex-direction: column;
    height: 100%;
    overflow: hidden;
    background-color: ${colors.surfaceBg};
  `

  let content = Html.css`
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 24px;
    gap: 16px;
  `

  let heading = (colors: uiColors) =>
    Html.css`
    color: ${colors.fg};
    font-size: 18px;
    font-weight: 600;
  `

  let description = (colors: uiColors) =>
    Html.css`
    color: ${colors.descriptionFg};
    font-size: 13px;
    line-height: 1.5;
  `

  let textarea = (colors: uiColors) =>
    Html.css`
    width: 100%;
    min-height: 200px;
    box-sizing: border-box;
    border: 1px solid ${colors.border};
    border-radius: 6px;
    background-color: ${colors.inputBg};
    color: ${colors.inputFg};
    font: inherit;
    font-size: 14px;
    line-height: 1.5;
    padding: 12px;
    outline: none;
    resize: vertical;

    &:focus {
      border-color: ${colors.focusBorder};
    }

    &::placeholder {
      color: ${colors.inputPlaceholder};
    }
  `

  let actions = Html.css`
    display: flex;
    gap: 8px;
    align-items: center;
  `

  let button = (colors: uiColors, disabled: bool) =>
    Html.css`
    padding: 8px 16px;
    border-radius: 4px;
    border: 1px solid ${colors.focusBorder};
    background-color: ${colors.buttonBg};
    color: ${colors.buttonFg};
    font-size: 13px;
    font-weight: 600;
    cursor: ${if disabled {
      "not-allowed"
    } else {
      "pointer"
    }};
    opacity: ${disabled ? "0.55" : "1"};
    transition: all 0.2s ease;

    &:hover {
      background-color: ${if disabled {
      colors.buttonBg
    } else {
      colors.buttonHoverBg
    }};
      border-color: ${if disabled {
      colors.focusBorder
    } else {
      colors.fg
    }};
    }

    &:active {
      transform: translateY(1px);
    }
  `

  let dangerButton = (colors: uiColors, disabled: bool) =>
    Html.css`
    padding: 8px 16px;
    border-radius: 4px;
    border: 1px solid ${colors.dangerBg};
    background-color: transparent;
    color: ${colors.dangerBg};
    font-size: 13px;
    font-weight: 600;
    cursor: ${if disabled {
      "not-allowed"
    } else {
      "pointer"
    }};
    opacity: ${disabled ? "0.55" : "1"};
    transition: all 0.2s ease;

    &:hover {
      background-color: ${if disabled {
      "transparent"
    } else {
      colors.dangerBg
    }};
      color: ${if disabled {
      colors.dangerBg
    } else {
      "#ffffff"
    }};
    }

    &:active {
      transform: translateY(1px);
    }
  `

  let planContainer = (colors: uiColors) =>
    Html.css`
    border: 1px solid ${colors.border};
    border-radius: 6px;
    background-color: ${colors.inputBg};
    color: ${colors.fg};
    font-size: 13px;
    line-height: 1.5;
    padding: 16px;
    white-space: pre-wrap;
    overflow-wrap: break-word;
    max-height: 400px;
    overflow-y: auto;
  `

  let statusBar = (colors: uiColors) =>
    Html.css`
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    border-top: 1px solid ${colors.border};
    background-color: ${colors.inputBg};
    color: ${colors.descriptionFg};
    font-size: 12px;
  `

  let spinner = Html.css`
    display: inline-block;
    animation: spin 1s linear infinite;
  `

  let successBar = (colors: uiColors) =>
    Html.css`
    padding: 12px;
    border-radius: 6px;
    background-color: ${colors.focusBorder}22;
    border: 1px solid ${colors.focusBorder}44;
    color: ${colors.fg};
    font-size: 13px;
    line-height: 1.5;
    white-space: pre-wrap;
  `

  let statusText = (colors: uiColors) =>
    Html.css`
    color: ${colors.descriptionFg};
  `

  let statusTextError = (colors: uiColors) =>
    Html.css`
    color: ${colors.dangerBg};
  `
}

@react.component
let make = (~uiColors: uiColors) => {
  let (featureDescription, setFeatureDescription) = Jotai.Atom.useAtom(State.featureDescriptionAtom)
  let (featurePlan, setFeaturePlan) = Jotai.Atom.useAtom(State.featurePlanAtom)

  let isGenerating = switch featurePlan {
  | GeneratingPlan => true
  | _ => false
  }
  let isApplying = switch featurePlan {
  | Applying => true
  | _ => false
  }
  let planText = switch featurePlan {
  | PlanReady(t) => t
  | _ => ""
  }

  let handleGenerate = _event => {
    let trimmed = featureDescription->String.trim
    if trimmed != "" {
      setFeaturePlan(_ => GeneratingPlan)
      let onSuccess = (result: Ipc.createFeaturePlanResult): Js.Promise.t<unit> => {
        setFeaturePlan(_ => PlanReady(result.plan))
        Js.Promise2.resolve()
      }
      let onError = (err: Js.Promise2.error): Js.Promise.t<unit> => {
        let msg = Raw.errorMessage(err)
        setFeaturePlan(_ => State.Error(msg))
        Js.Promise2.resolve()
      }
      let _ = Js.Promise2.catch(
        Js.Promise2.then(Ipc.callCreateFeaturePlan(trimmed), onSuccess),
        onError,
      )
    }
  }

  let handleRefine = _event => {
    setFeaturePlan(_ => State.Idle)
    setFeatureDescription(_ => "")
  }

  let handleApply = _event => {
    let description = featureDescription->String.trim
    let plan = planText->String.trim
    if description != "" && plan != "" {
      setFeaturePlan(_ => State.Applying)
      let onSuccess = (result: string): Js.Promise.t<unit> => {
        setFeaturePlan(_ => State.ApplyDone(result))
        Js.Promise2.resolve()
      }
      let onError = (err: Js.Promise2.error): Js.Promise.t<unit> => {
        let msg = Raw.errorMessage(err)
        setFeaturePlan(_ => State.Error(msg))
        Js.Promise2.resolve()
      }
      let _ = Js.Promise2.catch(
        Js.Promise2.then(Ipc.callApplyFeaturePlan({description, plan}), onSuccess),
        onError,
      )
    }
  }

  let canGenerate = !isGenerating && !isApplying && featureDescription->String.trim != ""
  let statusMessage = switch featurePlan {
  | Idle => ""
  | GeneratingPlan => "Pi is generating a plan... this may take a moment."
  | PlanReady(_) => "Plan ready. You can refine or apply it."
  | Applying => "Applying the plan to your codebase..."
  | ApplyDone(msg) => msg
  | State.Error(msg) => msg
  }

  let statusIsError = switch featurePlan {
  | State.Error(_) => true
  | _ => false
  }
  let placeholder = `Describe the new feature or bug fix in detail...

Example: 'Add a dark mode toggle button to the sidebar'
Or: 'Fix the issue where undo sometimes crashes when the file has unsaved changes'`

  <div className={Styles.container(uiColors)}>
    <div className={Styles.content}>
      <div className={Styles.heading(uiColors)}> {str("New Feature / Bug Fix")} </div>
      <div className={Styles.description(uiColors)}>
        {str(
          "Describe the feature or bug fix you want to implement. Pi will analyze the current codebase and create a plan to guide the implementation.",
        )}
      </div>
      {switch featurePlan {
      | Idle | GeneratingPlan | Applying | State.Error(_) | ApplyDone(_) =>
        <>
          <textarea
            className={Styles.textarea(uiColors)}
            placeholder={placeholder}
            value={featureDescription}
            disabled={isGenerating || isApplying}
            onChange={(ev: JsxEvent.Form.t) => {
              let target = JsxEvent.Form.target(ev)
              setFeatureDescription(_ => target["value"])
            }}
          />
          <div className={Styles.actions}>
            <button
              type_="button"
              className={Styles.button(uiColors, !canGenerate)}
              disabled={!canGenerate}
              onClick={handleGenerate}>
              {str(
                if isGenerating {
                  "Loading... Generating..."
                } else if isApplying {
                  "Loading... Applying..."
                } else {
                  "Create Plan  →"
                },
              )}
            </button>
          </div>
        </>
      | PlanReady(plan) =>
        <>
          <div className={Styles.planContainer(uiColors)}> {str(plan)} </div>
          <div className={Styles.actions}>
            <button
              type_="button"
              className={Styles.dangerButton(uiColors, false)}
              onClick={handleRefine}>
              {str("↩ Refine")}
            </button>
            <button type_="button" className={Styles.button(uiColors, false)} onClick={handleApply}>
              {str("✓ Start Applying")}
            </button>
          </div>
        </>
      }}
    </div>
    {statusMessage == ""
      ? React.null
      : <div className={Styles.statusBar(uiColors)}>
          {if isGenerating || isApplying {
            <span className={Styles.spinner}> {str("*")} </span>
          } else {
            React.null
          }}
          <span
            className={if statusIsError {
              Styles.statusTextError(uiColors)
            } else {
              Styles.statusText(uiColors)
            }}>
            {str(statusMessage)}
          </span>
        </div>}
  </div>
}
