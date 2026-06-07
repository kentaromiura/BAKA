open State
open Diffs

let styled = Html.styled
let str = React.string

type patchState = PatchLoading | PatchReady(array<parsedPatch>) | PatchError(string)

@val external document: {..} = "document"
@val external requestAnimationFrame: (unit => unit) => float = "requestAnimationFrame"
@val external cancelAnimationFrame: float => unit = "cancelAnimationFrame"

module Styles = {
  let header = (colors: uiColors) => Html.css`
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px;
    background-color: ${colors.surfaceBg};
    border-bottom: 1px solid ${colors.border};
    transition: all 0.2s ease;
  `

  let button = (colors: uiColors) => Html.css`
    padding: 6px 12px;
    border-radius: 4px;
    border: 1px solid ${colors.border};
    background-color: ${colors.buttonBg};
    color: ${colors.buttonFg};
    cursor: pointer;
    transition: all 0.2s ease;

    &:hover {
      background-color: ${colors.hoverBg};
    }

    &:active {
      transform: translateY(1px);
    }
  `

  let askPiButton = (colors: uiColors, disabled: bool) => Html.css`
    padding: 6px 12px;
    border-radius: 4px;
    border: 1px solid ${if disabled { colors.border } else { colors.focusBorder }};
    background-color: ${if disabled { colors.buttonBg } else { colors.selectionBg }};
    color: ${colors.buttonFg};
    cursor: ${if disabled { "not-allowed" } else { "pointer" }};
    opacity: ${disabled ? "0.6" : "1"};
    transition: all 0.2s ease;

    &:hover {
      background-color: ${if disabled { colors.buttonBg } else { colors.hoverBg }};
    }

    &:active {
      transform: translateY(1px);
    }
  `

  let container = Html.css`display: flex; flex-direction: column; height: 100vh;`

  let loadingContainer = Html.css`
    display: flex;
    align-items: center;
    justify-content: center;
    flex: 1;
    font-family: monospace;
    font-size: 14px;
  `

  let errorContainer = (colors: uiColors) => Html.css`
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    flex: 1;
    font-family: monospace;
    color: ${colors.dangerBg};
    padding: 24px;
  `

  let errorMessage = Html.css`
    text-align: center;
    max-width: 400px;
    white-space: pre-wrap;
  `
}

@react.component
let make = () => {
  let (isDark, setIsDark) = Jotai.Atom.useAtom(isDarkAtom)
  let (loadedThemes, _) = Jotai.Atom.useAtom(State.themeColorsAtom)
  let (comments, setComments) = Jotai.Atom.useAtom(State.commentsAtom)
  let currentColors: uiColors = switch loadedThemes {
  | Some(themes) => if isDark { themes.dark } else { themes.light }
  | None => if isDark { State.defaultUiColors } else { State.lightDefaultUiColors }
  }

  // Pi request loading state
  let (isAskingPi, setIsAskingPi) = React.useState(() => false)

  // Async patch loading state
  let (patchState, setPatchState) = React.useState(() => PatchLoading)

  // Fetch patch on mount
  React.useEffect0(() => {
    let onSuccess = (rawPatch: string): Js.Promise.t<unit> => {
      let patches = parsePatchFiles(rawPatch)
      setPatchState(_ => PatchReady(patches))
      Js.Promise2.resolve()
    }
    let onError = (err: Js.Promise2.error): Js.Promise.t<unit> => {
      let msg = %raw(`String(err).replace(/^Error: /, '')`)
      setPatchState(_ => PatchError(msg))
      Js.Promise2.resolve()
    }
    let _ = Js.Promise2.catch(
      Js.Promise2.then(Ipc.callGetPatch(), onSuccess),
      onError,
    )
    None
  })

  let headerStyle = Styles.header(currentColors)
  let buttonStyle = Styles.button(currentColors)

  let virtualizerWrapperRef: React.ref<Js.Nullable.t<Dom.element>> =
    React.useRef(Js.Nullable.null)
  let savedScrollTop: React.ref<float> = React.useRef(0.0)
  let isInitialRender = React.useRef(true)

  let captureScrollTop = () => {
    let wrapper = virtualizerWrapperRef.current
    switch Js.Nullable.toOption(wrapper) {
    | Some(el) =>
      let firstChild: Js.Nullable.t<Dom.element> = Obj.magic(el)["firstElementChild"]
      switch Js.Nullable.toOption(firstChild) {
      | Some(scrollEl) => savedScrollTop.current = Obj.magic(scrollEl)["scrollTop"]
      | None => ()
      }
    | None => ()
    }
  }

  let handleThemeToggle = _event => {
    captureScrollTop()
    setIsDark(prev => !prev)
  }

  // Collect all comments with non-empty text, send to pi for review
  let handleAskPi = _event => {
    if !isAskingPi {
      // Build payload: only comments that have text and no reply yet
      let payloadComments = Js.Dict.keys(comments)->Array.filterMap(key => {
        switch Js.Dict.get(comments, key) {
        | Some(c) if c.text->String.trim->String.length > 0 && c.aiReply == State.AiIdle =>
          Some({commentKey: key, text: c.text}: Ipc.askPiRequest)
        | _ => None
        }
      })

      if payloadComments->Array.length == 0 {
        // Nothing to ask about — mark all non-empty comments as done with empty reply
        setComments(prev => {
          let newDict = InlineComment.copyDict(prev)
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
        // Set all pending comments to streaming state
        setComments(prev => {
          let newDict = InlineComment.copyDict(prev)
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

        let onSuccess = (replies: array<Ipc.askPiReply>): Js.Promise.t<unit> => {
          setComments(prev => {
            let newDict = InlineComment.copyDict(prev)
            replies->Array.forEach(reply => {
              let key = InlineComment.normalizeModelKey(reply.commentKey)
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

        let onError = (_err: Js.Promise2.error): Js.Promise.t<unit> => {
          let msg = %raw(`String(_err).replace(/^Error: /, '')`)
          // Mark all streaming comments as error
          setComments(prev => {
            let newDict = InlineComment.copyDict(prev)
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
          Js.Promise2.then(Ipc.callAskPi(payloadComments), onSuccess),
          onError,
        )
      }
    }
  }

  React.useEffect1(() => {
    if isInitialRender.current {
      isInitialRender.current = false
      None
    } else {
      let savedTop = savedScrollTop.current
      let handle = requestAnimationFrame(() => {
        let wrapper = virtualizerWrapperRef.current
        switch Js.Nullable.toOption(wrapper) {
        | Some(el) =>
          let firstChild: Js.Nullable.t<Dom.element> = Obj.magic(el)["firstElementChild"]
          switch Js.Nullable.toOption(firstChild) {
          | Some(scrollEl) =>
            let _ = Obj.magic(scrollEl)["scrollTo"]({"top": savedTop, "behavior": "instant"})
          | None => ()
          }
        | None => ()
        }
      })
      Some(() => {
        cancelAnimationFrame(handle)
      })
    }
  }, [isDark])

  // Build diff children from loaded patches (memoized)
  let style: FileDiff.theme = {
    light: "rose-pine-dawn",
    dark: "tokyo-night",
  }

  let diffChildren = React.useMemo2((): array<React.element> => {
    switch patchState {
    | PatchReady(patches) =>
      patches->Array.flatMap(patch => {
        patch.files->Array.mapWithIndex((fileDiff, _i) => {
          <InlineComment
            key={fileDiffName(fileDiff)}
            fileDiff={fileDiff}
            theme={style}
            themeType={if (isDark) { "dark" } else { "light" }}
            uiColors={currentColors}
          />
        })
      })
    | _ => []
    }
  }, (patchState, isDark))

  switch patchState {
  | PatchLoading =>
    <div className={Styles.container}>
      <div className={headerStyle}>
        <button
          type_="button"
          onClick={handleThemeToggle}
          className={buttonStyle}
        >
          {str(if (isDark) { "Light Mode" } else { "Dark Mode" })}
        </button>
      </div>
      <div className={Styles.loadingContainer}>
        {str("Loading diff...")}
      </div>
    </div>

  | PatchError(msg) =>
    <div className={Styles.container}>
      <div className={headerStyle}>
        <button
          type_="button"
          onClick={handleThemeToggle}
          className={buttonStyle}
        >
          {str(if (isDark) { "Light Mode" } else { "Dark Mode" })}
        </button>
      </div>
      <div className={Styles.errorContainer(currentColors)}>
        <div className={Styles.errorMessage}>
          {str("Failed to load diff:\n\n" ++ msg)}
        </div>
      </div>
    </div>

  | PatchReady(_) =>
    <div className={Styles.container}>
      <div className={headerStyle}>
        <button
          type_="button"
          onClick={handleAskPi}
          disabled={isAskingPi}
          className={Styles.askPiButton(currentColors, isAskingPi)}
        >
          {str(if isAskingPi { "⠋ Asking Pi..." } else { "🤖 Ask Pi" })}
        </button>
        <button
          type_="button"
          onClick={handleThemeToggle}
          className={buttonStyle}
        >
          {str(if (isDark) { "Light Mode" } else { "Dark Mode" })}
        </button>
      </div>
      <div ref={ReactDOM.Ref.domRef(virtualizerWrapperRef)}>
        <Virtualizer style={%raw(`{"height": "100vh", "overflow-y": "auto"}`)}>
          {React.array(diffChildren)}
        </Virtualizer>
      </div>
    </div>
  }
}
