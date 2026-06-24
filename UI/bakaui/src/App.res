open State
open Diffs

let styled = Html.styled
let str = React.string

type patchState = PatchLoading | PatchReady(array<parsedPatch>) | PatchError(string)

@val external document: {..} = "document"
@val external getDiffReloadRequestCount: int = "__bakaDiffReloadRequestCount"
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
    border: 1px solid ${colors.focusBorder};
    background-color: ${colors.buttonBg};
    color: ${colors.buttonFg};
    cursor: ${if disabled { "not-allowed" } else { "pointer" }};
    opacity: ${disabled ? "0.6" : "1"};
    transition: all 0.2s ease;

    &:hover {
      background-color: ${if disabled { colors.buttonBg } else { colors.buttonHoverBg }};
    }

    &:active {
      transform: translateY(1px);
    }
  `

  let container = Html.css`display: flex; flex-direction: column; height: 100vh;`

  let content = Html.css`
    display: flex;
    flex-direction: row;
    flex: 1;
    min-height: 0;
    overflow: hidden;
  `

  let sidebar = (colors: uiColors) => Html.css`
    width: 280px;
    min-width: 220px;
    max-width: 360px;
    display: flex;
    flex-direction: column;
    min-height: 0;
    border-right: 1px solid ${colors.border};
    background-color: ${colors.surfaceBg};
    overflow: hidden;
  `

  let main = Html.css`
    flex: 1;
    min-width: 0;
    overflow: hidden;
  `

  let diffWrapper = Html.css`
    scroll-margin-top: 8px;
  `

  let treeHeader = (colors: uiColors) => Html.css`
    padding: 10px 12px;
    border-bottom: 1px solid ${colors.border};
    color: ${colors.fg};
    font-family: monospace;
    font-size: 12px;
    font-weight: 600;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  `

  let treeStyle = (colors: uiColors): Js.t<{..}> =>
    Obj.magic({
      "height": "100%",
      "--trees-fg-override": colors.fg,
      "--trees-bg-override": colors.surfaceBg,
      "--trees-border-color-override": colors.border,
      "--trees-selected-bg-override": colors.selectionBg,
      "--trees-selected-fg-override": colors.fg,
    })

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

  let reviewSummaryBar = (colors: uiColors) => Html.css`
    padding: 8px 12px;
    border-bottom: 1px solid ${colors.border};
    background-color: ${colors.inputBg};
    color: ${colors.fg};
    font-size: 13px;
    line-height: 1.45;
    white-space: pre-wrap;
    max-height: 120px;
    overflow: auto;
  `

  let reviewSummaryLabel = (colors: uiColors) => Html.css`
    color: ${colors.descriptionFg};
    font-size: 12px;
    font-weight: 600;
    margin-right: 8px;
    text-transform: uppercase;
  `
}

@react.component
let make = () => {
  let (isDark, setIsDark) = Jotai.Atom.useAtom(isDarkAtom)
  let (loadedThemes, _) = Jotai.Atom.useAtom(State.themeColorsAtom)
  let (comments, setComments) = Jotai.Atom.useAtom(State.commentsAtom)
  let (reviewSuggestions, setReviewSuggestions) = Jotai.Atom.useAtom(State.reviewSuggestionsAtom)
  let currentColors: uiColors = switch loadedThemes {
  | Some(themes) => if isDark { themes.dark } else { themes.light }
  | None => if isDark { State.defaultUiColors } else { State.lightDefaultUiColors }
  }

  // Pi request loading state
  let (isAskingPi, setIsAskingPi) = React.useState(() => false)
  let (isReviewing, setIsReviewing) = React.useState(() => false)
  let (reviewSummary, setReviewSummary) = React.useState(() => "No full review has run yet.")

  // Async patch loading state
  let (patchState, setPatchState) = React.useState(() => PatchLoading)
  let diffReloadPollVersionRef = React.useRef(0)
  let (diffReloadPollVersion, setDiffReloadPollVersion) = React.useState(() => 0)

  React.useEffect0(() => {
    let interval = Js.Global.setInterval(() => {
      let next = getDiffReloadRequestCount
      if next != diffReloadPollVersionRef.current {
        diffReloadPollVersionRef.current = next
        setDiffReloadPollVersion(_ => next)
      }
    }, 250)
    Some(() => Js.Global.clearInterval(interval))
  })

  // Fetch patch on mount and whenever the native watcher asks for a reload.
  React.useEffect1(() => {
    Js.log2("[BAKA UI] fetching patch; reload version", diffReloadPollVersion)
    let onSuccess = (rawPatch: string): Js.Promise.t<unit> => {
      let patches = parsePatchFiles(rawPatch)
      Js.log2("[BAKA UI] patch loaded bytes", rawPatch->String.length)
      Js.log2("[BAKA UI] parsed patch groups", patches->Array.length)
      setPatchState(_ => PatchReady(patches))
      Js.Promise2.resolve()
    }
    let onError = (err: Js.Promise2.error): Js.Promise.t<unit> => {
      let msg = %raw(`String(err).replace(/^Error: /, '')`)
      Js.log2("[BAKA UI] patch load error", msg)
      setPatchState(_ => PatchError(msg))
      Js.Promise2.resolve()
    }
    let _ = Js.Promise2.catch(
      Js.Promise2.then(Ipc.callGetPatch(), onSuccess),
      onError,
    )
    None
  }, [diffReloadPollVersion])

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

  let scrollToDiffFile = (fileName: string): unit => {
    let wrapper = virtualizerWrapperRef.current
    switch Js.Nullable.toOption(wrapper) {
    | Some(mainEl) =>
      let firstChild: Js.Nullable.t<Dom.element> = Obj.magic(mainEl)["firstElementChild"]
      switch Js.Nullable.toOption(firstChild) {
      | Some(scrollEl) =>
        %raw(`
          (function(scroller, fileName) {
            var el = document.getElementById(fileName);
            if (el != null && scroller.contains(el)) {
              var top = el.getBoundingClientRect().top - scroller.getBoundingClientRect().top + scroller.scrollTop;
              scroller.scrollTo({top: Math.max(0, Math.floor(top)), behavior: "instant"});
            }
          })
        `)(scrollEl, fileName)
      | None => ()
      }
    | None => ()
    }
  }

  let diffFilePaths = React.useMemo1(() => {
    switch patchState {
    | PatchReady(patches) =>
      patches->Array.flatMap(patch =>
        patch.files->Array.map(fileDiff => fileDiffName(fileDiff))
      )
    | _ => []
    }
  }, [patchState])

  let fileTree = Trees.useFileTree({
    paths: diffFilePaths,
    initialExpansion: "open",
    onSelectionChange: selectedPaths => {
      switch Belt.Array.get(selectedPaths, 0) {
      | Some(fileName) => scrollToDiffFile(fileName)
      | None => ()
      }
    },
  })

  React.useEffect1(() => {
    Trees.resetPaths(fileTree.model, diffFilePaths)
    None
  }, [diffFilePaths])

  let handleThemeToggle = _event => {
    captureScrollTop()
    setIsDark(prev => !prev)
  }

  // Collect all comments with non-empty text, send to pi for review
  let handleAskPi = _event => {
    if !isAskingPi {
      Js.log("[BAKA UI] Ask Pi button clicked")
      // Build payload: only comments that have text and no reply yet
      let payloadComments = Js.Dict.keys(comments)->Array.filterMap(key => {
        switch Js.Dict.get(comments, key) {
        | Some(c) if c.text->String.trim->String.length > 0 && c.aiReply == State.AiIdle =>
          Some({commentKey: key, text: c.text}: Ipc.askPiRequest)
        | _ => None
        }
      })

      if payloadComments->Array.length == 0 {
        Js.log("[BAKA UI] Ask Pi has no pending comments")
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
        Js.log2("[BAKA UI] Ask Pi sending comment count", payloadComments->Array.length)
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
          Js.log2("[BAKA UI] Ask Pi success replies", replies->Array.length)
          setComments(prev => {
            let newDict = InlineComment.copyDict(prev)
            replies->Array.forEach(reply => {
              let key = InlineComment.normalizeModelKey(reply.commentKey)
              Js.log2("[BAKA UI] Ask Pi applying reply key", key)
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
          Js.log2("[BAKA UI] Ask Pi error", msg)
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

  let handleFullReview = _event => {
    if !isReviewing {
      Js.log("[BAKA UI] Code Review button clicked")
      setIsReviewing(_ => true)
      setReviewSummary(_ => "Pi is reviewing the current diff...")

      let onSuccess = (review: Ipc.fullReviewResult): Js.Promise.t<unit> => {
        Js.log2("[BAKA UI] Full review success summary", review.summary)
        Js.log2("[BAKA UI] Full review finding count", review.findings->Array.length)
        setReviewSummary(_ => review.summary)
        setComments(prev => {
          let newDict = InlineComment.copyDict(prev)
          review.findings->Array.forEach(finding => {
            let key = InlineComment.normalizeModelKey(finding.commentKey)
            Js.log2("[BAKA UI] Full review inserting annotation", key)
            let text = "Pi review: " ++ finding.summary
            let body = if finding.body->String.trim->String.length > 0 {
              finding.body
            } else {
              finding.summary
            }
            Js.Dict.set(newDict, key, {text: text, aiReply: State.AiDone(body)})
          })
          newDict
        })
        setReviewSuggestions(prev => {
          let newDict: Js.Dict.t<State.reviewSuggestion> = %raw(`Object.assign({}, prev)`)
          review.findings->Array.forEach(finding => {
            let key = InlineComment.normalizeModelKey(finding.commentKey)
            Js.log2("[BAKA UI] Full review storing suggestion metadata", key)
            Js.Dict.set(newDict, key, {
              summary: finding.summary,
              severity: finding.severity,
              actionable: finding.actionable,
              suggestion: finding.suggestion,
              isApplying: false,
              applyResult: None,
              applyError: None,
            })
          })
          newDict
        })
        setIsReviewing(_ => false)
        Js.Promise2.resolve()
      }

      let onError = (err: Js.Promise2.error): Js.Promise.t<unit> => {
        let msg = %raw(`String(err).replace(/^Error: /, '')`)
        Js.log2("[BAKA UI] Full review error", msg)
        setReviewSummary(_ => "Review failed: " ++ msg)
        setIsReviewing(_ => false)
        Js.Promise2.resolve()
      }

      let _ = Js.Promise2.catch(
        Js.Promise2.then(Ipc.callStartFullReview(), onSuccess),
        onError,
      )
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

  let reviewCount = Js.Dict.keys(reviewSuggestions)->Array.length
  let actionableReviewCount =
    Js.Dict.keys(reviewSuggestions)->Array.reduce(0, (count, key) => {
      switch Js.Dict.get(reviewSuggestions, key) {
      | Some(item) if item.actionable => count + 1
      | _ => count
      }
    })
  let reviewButtonTitle =
    reviewSummary ++
    if reviewCount > 0 {
      "\n\n" ++ Int.toString(reviewCount) ++ " finding(s), " ++ Int.toString(actionableReviewCount) ++ " actionable."
    } else {
      ""
    }
  let shouldShowReviewSummary = isReviewing || reviewSummary != "No full review has run yet."
  let reviewSummaryText =
    reviewSummary ++
    if reviewCount > 0 {
      "\n" ++ Int.toString(reviewCount) ++ " finding(s), " ++ Int.toString(actionableReviewCount) ++ " actionable."
    } else {
      ""
    }

  let diffChildren = React.useMemo2((): array<React.element> => {
    switch patchState {
    | PatchReady(patches) =>
      patches->Array.flatMap(patch => {
        patch.files->Array.mapWithIndex((fileDiff, _i) => {
          let fileName = fileDiffName(fileDiff)
          <div key={fileName} id={fileName} className={Styles.diffWrapper}>
            <InlineComment
              fileDiff={fileDiff}
              theme={style}
              themeType={if (isDark) { "dark" } else { "light" }}
              uiColors={currentColors}
            />
          </div>
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
          onClick={handleFullReview}
          disabled={isReviewing}
          title={reviewButtonTitle}
          className={Styles.askPiButton(currentColors, isReviewing)}
        >
          {str(if isReviewing { "Reviewing..." } else { "Code Review" })}
        </button>
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
      {shouldShowReviewSummary
        ? <div className={Styles.reviewSummaryBar(currentColors)}>
            <span className={Styles.reviewSummaryLabel(currentColors)}>
              {str("Review")}
            </span>
            {str(reviewSummaryText)}
          </div>
        : React.null}
      <div className={Styles.content}>
        <aside className={Styles.sidebar(currentColors)}>
          <Trees.make
            model={fileTree.model}
            header={<div className={Styles.treeHeader(currentColors)}>{str("Changed files")}</div>}
            style={Styles.treeStyle(currentColors)}
          />
        </aside>
        <main ref={ReactDOM.Ref.domRef(virtualizerWrapperRef)} className={Styles.main}>
          <Virtualizer style={%raw(`{"height": "100%", "overflow-y": "auto"}`)}>
            {React.array(diffChildren)}
          </Virtualizer>
        </main>
      </div>
    </div>
  }
}
