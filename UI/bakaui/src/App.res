open State
open Diffs

let styled = Html.styled
let str = React.string

type patchState = PatchLoading | PatchReady(array<parsedPatch>) | PatchError(string)
type reviewSourceMode = Changed | History
type historyState = HistoryIdle | HistoryLoading | HistoryReady(array<Ipc.commitSummary>) | HistoryError(string)
type commitPatchState =
  | CommitPatchIdle
  | CommitPatchLoading
  | CommitPatchReady(string, array<parsedPatch>)
  | CommitPatchError(string)
type viewMode = Review | Project | Commit | Feature | Settings

@val external document: {..} = "document"
@val external getDiffReloadRequestCount: int = "__bakaDiffReloadRequestCount"
@val external requestAnimationFrame: (unit => unit) => float = "requestAnimationFrame"
@val external cancelAnimationFrame: float => unit = "cancelAnimationFrame"

module Styles = {
  let appFont = `"Ioskeley Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace`

  let header = (colors: uiColors) => Html.css`
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    padding: 12px;
    background-color: ${colors.surfaceBg};
    border-bottom: 1px solid ${colors.border};
    transition: all 0.2s ease;
  `

  let tabs = (colors: uiColors) => Html.css`
    display: inline-flex;
    align-items: center;
    flex-shrink: 0;
    padding: 3px;
    border: 1px solid ${colors.border};
    border-radius: 7px;
    background-color: ${colors.inputBg};
  `

  let tab = (colors: uiColors) => Html.css`
    padding: 6px 12px;
    border: 1px solid transparent;
    border-radius: 4px;
    background-color: transparent;
    color: ${colors.descriptionFg};
    font-family: ${appFont};
    font-weight: 500;
    cursor: pointer;
    transition: background-color 0.15s ease, color 0.15s ease, box-shadow 0.15s ease;

    &:hover {
      background-color: ${colors.hoverBg};
      color: ${colors.fg};
    }

    &[aria-selected="true"] {
      border-color: ${colors.focusBorder};
      background-color: ${colors.selectionBg};
      color: ${colors.fg};
      font-weight: 600;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.18);
    }

    &[aria-selected="true"]:hover {
      background-color: ${colors.selectionBg};
    }

    &:focus-visible {
      outline: 2px solid ${colors.focusBorder};
      outline-offset: 1px;
    }
  `

  let headerActions = Html.css`
    display: flex;
    align-items: center;
    gap: 8px;
    margin-left: auto;
  `

  let aiMenu = Html.css`
    position: relative;
    display: inline-flex;

    &:hover > div,
    &:focus-within > div {
      display: flex;
    }
  `

  let aiMenuPanel = (colors: uiColors) => Html.css`
    position: absolute;
    z-index: 50;
    top: 100%;
    right: -20px;
    display: none;
    width: 220px;
    flex-direction: column;
    gap: 3px;
    padding: 8px 20px 20px;

    &::before {
      content: "";
      position: absolute;
      z-index: -1;
      inset: 5px 20px 15px;
      border: 1px solid ${colors.border};
      border-radius: 7px;
      background: ${colors.surfaceBg};
      box-shadow: 0 12px 28px rgba(0, 0, 0, 0.28);
    }
  `

  let aiMenuItem = (colors: uiColors, disabled: bool) => Html.css`
    width: 100%;
    padding: 8px 10px;
    border: 0;
    border-radius: 4px;
    background: transparent;
    color: ${colors.fg};
    text-align: left;
    cursor: ${disabled ? "not-allowed" : "pointer"};
    opacity: ${disabled ? "0.55" : "1"};

    &:hover {
      background: ${disabled ? "transparent" : colors.hoverBg};
    }
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

  let iconButton = (colors: uiColors) => Html.css`
    width: 34px;
    height: 32px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    border-radius: 4px;
    border: 1px solid ${colors.border};
    background-color: ${colors.buttonBg};
    color: ${colors.buttonFg};
    font-size: 1.385rem;
    line-height: 1;
    cursor: pointer;
    transition: all 0.2s ease;

    &:hover,
    &[aria-pressed="true"] {
      background-color: ${colors.hoverBg};
      color: ${colors.fg};
    }

    &:focus-visible {
      outline: 2px solid ${colors.focusBorder};
      outline-offset: 1px;
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

  let container = Html.css`
    display: flex;
    flex-direction: column;
    height: 100vh;
    font-family: ${appFont};
    font-size: 1rem;
    line-height: 1.25;

    & button,
    & input,
    & textarea,
    & select {
      font-family: inherit;
      font-size: inherit;
      line-height: inherit;
    }
  `

  let content = Html.css`
    display: flex;
    flex-direction: row;
    flex: 1;
    min-height: 0;
    overflow: hidden;
  `

  let commitViewHost = (hidden: bool) => Html.css`
    display: ${if hidden { "none" } else { "flex" }};
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

  let reviewModeTabs = (colors: uiColors) => Html.css`
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 4px;
    padding: 8px;
    border-bottom: 1px solid ${colors.border};
    background-color: ${colors.surfaceBg};
  `

  let reviewModeTab = (colors: uiColors) => Html.css`
    min-width: 0;
    padding: 6px 8px;
    border: 1px solid transparent;
    border-radius: 4px;
    background: transparent;
    color: ${colors.descriptionFg};
    cursor: pointer;
    font-weight: 600;

    &[aria-selected="true"] {
      border-color: ${colors.focusBorder};
      background: ${colors.selectionBg};
      color: ${colors.fg};
    }

    &:hover {
      background: ${colors.hoverBg};
      color: ${colors.fg};
    }
  `

  let commitList = Html.css`
    flex: 1;
    min-height: 0;
    overflow: auto;
  `

  let commitRow = (colors: uiColors, selected: bool) => Html.css`
    display: flex;
    flex-direction: column;
    gap: 3px;
    width: 100%;
    padding: 9px 10px;
    border: 0;
    border-bottom: 1px solid ${colors.border};
    background: ${if selected { colors.selectionBg } else { "transparent" }};
    color: ${colors.fg};
    text-align: left;
    cursor: pointer;

    &:hover {
      background: ${if selected { colors.selectionBg } else { colors.hoverBg }};
    }
  `

  let commitSubject = Html.css`
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-weight: 700;
  `

  let commitMeta = (colors: uiColors) => Html.css`
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    color: ${colors.descriptionFg};
    font-size: 0.846rem;
  `

  let historyFilesPanel = (colors: uiColors) => Html.css`
    width: 260px;
    min-width: 220px;
    max-width: 340px;
    display: flex;
    flex-direction: column;
    min-height: 0;
    border-right: 1px solid ${colors.border};
    background-color: ${colors.surfaceBg};
    overflow: hidden;
  `

  let fileList = Html.css`
    flex: 1;
    min-height: 0;
    overflow: auto;
  `

  let fileRow = (colors: uiColors, selected: bool) => Html.css`
    width: 100%;
    padding: 7px 10px;
    border: 0;
    border-bottom: 1px solid ${colors.border};
    background: ${if selected { colors.selectionBg } else { "transparent" }};
    color: ${colors.fg};
    text-align: left;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    cursor: pointer;

    &:hover {
      background: ${if selected { colors.selectionBg } else { colors.hoverBg }};
    }
  `

  let paneMessage = (colors: uiColors) => Html.css`
    padding: 14px 12px;
    color: ${colors.descriptionFg};
    white-space: pre-wrap;
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
    font-family: ${appFont};
    font-size: 1rem;
    font-weight: 600;
  `

  let treeStyle = (colors: uiColors): Js.t<{..}> =>
    Obj.magic({
      "height": "100%",
      "--trees-fg-override": colors.fg,
      "--trees-bg-override": colors.surfaceBg,
      "--trees-border-color-override": colors.border,
      "--trees-selected-bg-override": colors.selectionBg,
      "--trees-selected-fg-override": colors.fg,
      "--trees-font-family-override": appFont,
      "--trees-font-size-override": "1rem",
    })

  let loadingContainer = Html.css`
    display: flex;
    align-items: center;
    justify-content: center;
    flex: 1;
    font-family: ${appFont};
    font-size: 1.077rem;
  `

  let errorContainer = (colors: uiColors) => Html.css`
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    flex: 1;
    font-family: ${appFont};
    color: ${colors.dangerBg};
    padding: 24px;
  `

  let errorMessage = Html.css`
    text-align: center;
    max-width: 400px;
    white-space: pre-wrap;
  `

  let repositoryPicker = (colors: uiColors) => Html.css`
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 14px;
    flex: 1;
    padding: 32px;
    background: ${colors.bg};
    color: ${colors.fg};
    text-align: center;
  `

  let repositoryPickerTitle = Html.css`
    font-size: 1.231rem;
    font-weight: 700;
  `

  let repositoryPickerMessage = (colors: uiColors) => Html.css`
    max-width: 520px;
    color: ${colors.descriptionFg};
    line-height: 1.45;
    white-space: pre-wrap;
  `

  let repositoryPath = (colors: uiColors) => Html.css`
    max-width: min(680px, 100%);
    padding: 6px 8px;
    border: 1px solid ${colors.border};
    border-radius: 4px;
    background: ${colors.inputBg};
    color: ${colors.inputFg};
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  `

  let reviewSummaryBar = (colors: uiColors) => Html.css`
    padding: 8px 12px;
    border-bottom: 1px solid ${colors.border};
    background-color: ${colors.inputBg};
    color: ${colors.fg};
    font-family: ${appFont};
    font-size: 1rem;
    line-height: 1.45;
    white-space: pre-wrap;
    max-height: 120px;
    overflow: auto;
  `

  let reviewSummaryLabel = (colors: uiColors) => Html.css`
    color: ${colors.descriptionFg};
    font-family: ${appFont};
    font-size: 1rem;
    font-weight: 600;
    margin-right: 8px;
  `

  let settingsPage = (colors: uiColors) => Html.css`
    flex: 1;
    overflow: auto;
    padding: 32px;
    background-color: ${colors.bg};
    color: ${colors.fg};
  `

  let settingsContent = Html.css`
    width: min(720px, 100%);
    margin: 0 auto;
  `

  let settingsTitle = Html.css`
    margin: 0 0 8px;
    font-size: 1.846rem;
  `

  let settingsDescription = (colors: uiColors) => Html.css`
    margin: 0 0 24px;
    color: ${colors.descriptionFg};
    line-height: 1.5;
  `

  let settingsGrid = Html.css`
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
    gap: 16px;
  `

  let settingsCard = (colors: uiColors) => Html.css`
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 18px;
    border: 1px solid ${colors.border};
    border-radius: 8px;
    background-color: ${colors.surfaceBg};
  `

  let settingsLabel = Html.css`
    font-size: 1.077rem;
    font-weight: 700;
  `

  let settingsSelect = (colors: uiColors) => Html.css`
    width: 100%;
    padding: 9px 10px;
    border: 1px solid ${colors.inputBorder};
    border-radius: 5px;
    background-color: ${colors.inputBg};
    color: ${colors.inputFg};
    cursor: pointer;

    &:focus-visible {
      outline: 2px solid ${colors.focusBorder};
      outline-offset: 1px;
    }
  `

  let settingsHint = (colors: uiColors) => Html.css`
    min-height: 20px;
    margin: 16px 0 0;
    color: ${colors.descriptionFg};
    font-size: 0.923rem;
  `

  let settingsSectionTitle = Html.css`
    margin: 28px 0 12px;
    font-size: 1.23rem;
  `

  let settingsCardHint = (colors: uiColors) => Html.css`
    color: ${colors.descriptionFg};
    font-size: 0.846rem;
    line-height: 1.4;
  `

  let statusBar = (colors: uiColors) => Html.css`
    min-height: 26px;
    display: flex;
    align-items: center;
    justify-content: flex-end;
    padding: 3px 10px;
    border-top: 1px solid ${colors.border};
    background: ${colors.surfaceBg};
    color: ${colors.descriptionFg};
    font-size: 0.846rem;
  `
}

@react.component
let make = () => {
  let (isDark, setIsDark) = Jotai.Atom.useAtom(isDarkAtom)
  let (themeNames, setThemeNames) = Jotai.Atom.useAtom(State.themeAtom)
  let (loadedThemes, setLoadedThemes) = Jotai.Atom.useAtom(State.themeColorsAtom)
  let (comments, setComments) = Jotai.Atom.useAtom(State.commentsAtom)
  let (reviewSuggestions, setReviewSuggestions) = Jotai.Atom.useAtom(State.reviewSuggestionsAtom)
  let (piPreferences, setPiPreferences) = Jotai.Atom.useAtom(State.piPreferencesAtom)
  let (piModels, setPiModels) = Jotai.Atom.useAtom(State.piModelsAtom)
  let (piResolvedDefault, setPiResolvedDefault) = Jotai.Atom.useAtom(State.piResolvedDefaultAtom)
  let (activePiRun, setActivePiRun) = Jotai.Atom.useAtom(State.activePiRunAtom)
  let (featurePlan, _setFeaturePlan) = Jotai.Atom.useAtom(State.featurePlanAtom)
  let currentColors: uiColors = switch loadedThemes {
  | Some(themes) => if isDark { themes.dark } else { themes.light }
  | None => if isDark { State.defaultUiColors } else { State.lightDefaultUiColors }
  }

  // Pi request loading state
  let (isAskingPi, setIsAskingPi) = React.useState(() => false)
  let (activeReview, setActiveReview) = React.useState((): option<Ipc.fullReviewKind> => None)
  let (reviewSummary, setReviewSummary) = React.useState(() => "No full review has run yet.")
  let (reviewSummaryLabel, setReviewSummaryLabel) = React.useState(() => "Review")
  let (viewMode, setViewMode) = React.useState(() => Review)
  let (reviewSourceMode, setReviewSourceMode) = React.useState(() => Changed)
  let (historyState, setHistoryState) = React.useState(() => HistoryIdle)
  let (selectedCommitHash, setSelectedCommitHash) = React.useState(() => "")
  let (commitPatchState, setCommitPatchState) = React.useState(() => CommitPatchIdle)
  let (selectedCommitFile, setSelectedCommitFile) = React.useState(() => "")
  let (historyDiffStyles, setHistoryDiffStyles) = React.useState((): Js.Dict.t<string> => Js.Dict.empty())
  let (repoRoot, setRepoRoot) = React.useState(() => "")
  let (repoInfo, setRepoInfo) = React.useState((): option<Ipc.repoInfo> => None)
  let (isThemeLoading, setIsThemeLoading) = React.useState(() => false)
  let (isSpecCheckOpen, setIsSpecCheckOpen) = React.useState(() => false)
  let (piModelsError, setPiModelsError) = React.useState(() => "")
  let themeLoadVersionRef = React.useRef(0)
  let lightThemeOptions = React.useMemo0(() => ThemePreferences.getOptions("light"))
  let darkThemeOptions = React.useMemo0(() => ThemePreferences.getOptions("dark"))

  let loadPiModels = () => {
    let onSuccess = (result: Ipc.piModelResult): Js.Promise.t<unit> => {
      setPiModels(_ => result.models)
      setPiResolvedDefault(_ => result.resolvedDefault)
      setPiModelsError(_ => "")
      Js.Promise2.resolve()
    }
    let onError = (error: Js.Promise2.error): Js.Promise.t<unit> => {
      setPiModelsError(_ => Raw.errorMessage(error))
      Js.Promise2.resolve()
    }
    let _ = Js.Promise2.catch(Js.Promise2.then(Ipc.callGetPiModels(), onSuccess), onError)
  }

  React.useEffect0(() => {
    loadPiModels()
    None
  })

  React.useEffect1(() => {
    PiPreferences.save(piPreferences)
    None
  }, [piPreferences])

  React.useEffect1(() => {
    themeLoadVersionRef.current = themeLoadVersionRef.current + 1
    let loadVersion = themeLoadVersionRef.current
    ThemePreferences.save(themeNames)
    setIsThemeLoading(_ => true)

    let onMarkdownReady = _ => {
      if themeLoadVersionRef.current == loadVersion {
        setIsThemeLoading(_ => false)
      }
      Js.Promise2.resolve()
    }
    let onThemesReady = themes => {
      if themeLoadVersionRef.current == loadVersion {
        setLoadedThemes(_ => themes)
      }
      Js.Promise2.then(
        Markdown.preloadMarkdown(themeNames.light, themeNames.dark),
        onMarkdownReady,
      )
    }
    let onThemeError = (_error: Js.Promise2.error) => {
      if themeLoadVersionRef.current == loadVersion {
        setIsThemeLoading(_ => false)
      }
      Js.Promise2.resolve()
    }
    let _ = Js.Promise2.catch(
      Js.Promise2.then(
        Shiki.loadBothThemes(themeNames.light, themeNames.dark),
        onThemesReady,
      ),
      onThemeError,
    )
    None
  }, [themeNames])

  // Async patch loading state
  let (patchState, setPatchState) = React.useState(() => PatchLoading)
  let watcherReloadCountRef = React.useRef(getDiffReloadRequestCount)
  let (patchReloadVersion, setPatchReloadVersion) = React.useState(() => 0)

  let requestPatchReload = () => {
    setPatchReloadVersion(prev => prev + 1)
  }

  let applyRepositoryInfo = (info: Ipc.repoInfo) => {
    setRepoInfo(_ => Some(info))
    setRepoRoot(_ => info.repoRoot)
  }

  let resetRepositoryScopedState = () => {
    setComments(_ => Js.Dict.empty())
    setReviewSuggestions(_ => Js.Dict.empty())
    setReviewSummary(_ => "No full review has run yet.")
    setReviewSummaryLabel(_ => "Review")
    setActiveReview(_ => None)
    setIsSpecCheckOpen(_ => false)
    setReviewSourceMode(_ => Changed)
    setHistoryState(_ => HistoryIdle)
    setSelectedCommitHash(_ => "")
    setCommitPatchState(_ => CommitPatchIdle)
    setSelectedCommitFile(_ => "")
    setHistoryDiffStyles(_ => Js.Dict.empty())
  }

  let loadRepositoryInfo = () => {
    let onSuccess = (info: Ipc.repoInfo): Js.Promise.t<unit> => {
      applyRepositoryInfo(info)
      Js.Promise2.resolve()
    }
    let onError = (_error: Js.Promise2.error): Js.Promise.t<unit> => Js.Promise2.resolve()
    let _ = Js.Promise2.catch(
      Js.Promise2.then(Ipc.callGetRepositoryInfo(), onSuccess),
      onError,
    )
  }

  React.useEffect0(() => {
    loadRepositoryInfo()
    None
  })

  let handleChooseWorkingFolder = _event => {
    let onSuccess = (info: Ipc.repoInfo): Js.Promise.t<unit> => {
      if !info.canceled {
        setPatchState(_ => PatchLoading)
        applyRepositoryInfo(info)
        resetRepositoryScopedState()
        setViewMode(_ => Review)
        requestPatchReload()
      }
      Js.Promise2.resolve()
    }
    let onError = (error: Js.Promise2.error): Js.Promise.t<unit> => {
      let message = Raw.errorMessage(error)
      if message != "Folder selection canceled" {
        setPatchState(_ => PatchError(message))
      }
      Js.Promise2.resolve()
    }
    let _ = Js.Promise2.catch(
      Js.Promise2.then(Ipc.callChooseWorkingFolder(), onSuccess),
      onError,
    )
  }

  React.useEffect0(() => {
    let interval = Js.Global.setInterval(() => {
      let next = getDiffReloadRequestCount
      if next != watcherReloadCountRef.current {
        watcherReloadCountRef.current = next
        setPatchReloadVersion(prev => prev + 1)
      }
    }, 250)
    Some(() => Js.Global.clearInterval(interval))
  })

  // Fetch patch on mount and whenever the native watcher asks for a reload.
  React.useEffect1(() => {
    Js.log2("[BAKA UI] fetching patch; reload version", patchReloadVersion)
    let onSuccess = (rawPatch: string): Js.Promise.t<unit> => {
      let patches = parsePatchFiles(rawPatch)
      Js.log2("[BAKA UI] patch loaded bytes", rawPatch->String.length)
      Js.log2("[BAKA UI] parsed patch groups", patches->Array.length)
      setPatchState(_ => PatchReady(patches))
      Js.Promise2.resolve()
    }
    let onError = (err: Js.Promise2.error): Js.Promise.t<unit> => {
      let msg = Raw.errorMessage(err)
      Js.log2("[BAKA UI] patch load error", msg)
      setPatchState(_ => PatchError(msg))
      Js.Promise2.resolve()
    }
    let _ = Js.Promise2.catch(
      Js.Promise2.then(Ipc.callGetPatch(), onSuccess),
      onError,
    )
    None
  }, [patchReloadVersion])

  React.useEffect2(() => {
    switch (reviewSourceMode, historyState) {
    | (History, HistoryIdle) =>
      setHistoryState(_ => HistoryLoading)
      let onSuccess = (commits: array<Ipc.commitSummary>): Js.Promise.t<unit> => {
        setHistoryState(_ => HistoryReady(commits))
        switch Belt.Array.get(commits, 0) {
        | Some(commit) if selectedCommitHash == "" =>
          setSelectedCommitHash(_ => commit.hash)
        | _ => ()
        }
        Js.Promise2.resolve()
      }
      let onError = (err: Js.Promise2.error): Js.Promise.t<unit> => {
        setHistoryState(_ => HistoryError(Raw.errorMessage(err)))
        Js.Promise2.resolve()
      }
      let _ = Js.Promise2.catch(
        Js.Promise2.then(Ipc.callGetCommitHistory(), onSuccess),
        onError,
      )
      None
    | _ => None
    }
  }, (reviewSourceMode, historyState))

  React.useEffect2(() => {
    if reviewSourceMode == History && selectedCommitHash != "" {
      setCommitPatchState(_ => CommitPatchLoading)
      setSelectedCommitFile(_ => "")
      let hash = selectedCommitHash
      let onSuccess = (rawPatch: string): Js.Promise.t<unit> => {
        let parsed = parsePatchFiles(rawPatch)
        setCommitPatchState(_ => CommitPatchReady(rawPatch, parsed))
        let files = parsed->Array.flatMap(patch =>
          patch.files->Array.map(fileDiff => fileDiffName(fileDiff))
        )
        switch Belt.Array.get(files, 0) {
        | Some(fileName) => setSelectedCommitFile(_ => fileName)
        | None => setSelectedCommitFile(_ => "")
        }
        Js.Promise2.resolve()
      }
      let onError = (err: Js.Promise2.error): Js.Promise.t<unit> => {
        setCommitPatchState(_ => CommitPatchError(Raw.errorMessage(err)))
        Js.Promise2.resolve()
      }
      let _ = Js.Promise2.catch(
        Js.Promise2.then(Ipc.callGetCommitPatch(hash), onSuccess),
        onError,
      )
      None
    } else {
      None
    }
  }, (reviewSourceMode, selectedCommitHash))

  let headerStyle = Styles.header(currentColors)
  let buttonStyle = Styles.button(currentColors)
  let settingsAriaPressed = if viewMode == Settings {#"true"} else {#"false"}

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

	  let validReviewKeys = React.useMemo1(() => {
	    let keys: Js.Dict.t<bool> = Js.Dict.empty()
	    switch patchState {
	    | PatchReady(patches) =>
	      patches->Array.forEach(patch => {
	        patch.files->Array.forEach(fileDiff => {
	          let fileName = fileDiffName(fileDiff)
	          changedLineAnnotations(fileDiff)->Array.forEach((annotation: lineAnnotation) => {
	            Js.Dict.set(
	              keys,
	              InlineComment.makeKey(fileName, annotation.side, annotation.lineNumber),
	              true,
	            )
	          })
	        })
	      })
	    | _ => ()
	    }
	    keys
	  }, [patchState])

  let handleThemeToggle = _event => {
    captureScrollTop()
    setIsDark(prev => !prev)
  }

  let handleLightThemeChange = (event: JsxEvent.Form.t) => {
    let target = JsxEvent.Form.target(event)
    let themeName: string = target["value"]
    captureScrollTop()
    setThemeNames(previous => {...previous, light: themeName})
  }

  let handleDarkThemeChange = (event: JsxEvent.Form.t) => {
    let target = JsxEvent.Form.target(event)
    let themeName: string = target["value"]
    captureScrollTop()
    setThemeNames(previous => {...previous, dark: themeName})
  }

  let historyCommentPrefix = if selectedCommitHash != "" {
    "history:" ++ selectedCommitHash ++ "|"
  } else {
    ""
  }

  let historyDiffStyleKey = (fileName: string) => selectedCommitHash ++ "|" ++ fileName

  let historyDiffStyleFor = (fileName: string) => {
    switch Js.Dict.get(historyDiffStyles, historyDiffStyleKey(fileName)) {
    | Some(style) => style
    | None => "unified"
    }
  }

  let toggleHistoryDiffStyle = (fileName: string) => {
    let key = historyDiffStyleKey(fileName)
    setHistoryDiffStyles(prev => {
      let next: Js.Dict.t<string> = Raw.copyDict(prev)
      let current = switch Js.Dict.get(prev, key) {
      | Some(style) => style
      | None => "unified"
      }
      Js.Dict.set(next, key, if current == "unified" { "split" } else { "unified" })
      next
    })
  }

  let historyRawPatch = switch commitPatchState {
  | CommitPatchReady(rawPatch, _) => rawPatch
  | _ => ""
  }

  let scopedAskKey = (key: string) =>
    if reviewSourceMode == History {
      historyCommentPrefix ++ key
    } else {
      key
    }

  // Collect all comments with non-empty text, send to pi for review
  let handleAskPi = _event => {
    if !isAskingPi {
      Js.log("[BAKA UI] Ask Pi button clicked")
      // Build payload: only comments that have text and no reply yet
      let payloadComments = Js.Dict.keys(comments)->Array.filterMap(key => {
        switch Js.Dict.get(comments, key) {
        | Some(c) if c.text->String.trim->String.length > 0 && c.aiReply == State.AiIdle =>
          switch reviewSourceMode {
          | Changed =>
            switch InlineComment.parseKey(key) {
            | Some(_) => Some({commentKey: key, text: c.text}: Ipc.askPiRequest)
            | None => None
            }
          | History =>
            if historyCommentPrefix != "" && InlineComment.hasKeyPrefix(key, historyCommentPrefix) {
              Some({
                commentKey: InlineComment.stripKeyPrefix(key, historyCommentPrefix),
                text: c.text,
              }: Ipc.askPiRequest)
            } else {
              None
            }
          }
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
              let inScope = switch reviewSourceMode {
              | Changed => InlineComment.parseKey(key) != None
              | History => historyCommentPrefix != "" && InlineComment.hasKeyPrefix(key, historyCommentPrefix)
              }
              if inScope {
                Js.Dict.set(newDict, key, {text: c.text, aiReply: State.AiDone("No new questions — your comments are already reviewed.")})
              }
            | _ => ()
            }
          })
          newDict
        })
      } else {
        let model = PiPreferences.resolve(piPreferences, piPreferences.inlineReviewModel)
        Js.log2("[BAKA UI] Ask Pi sending comment count", payloadComments->Array.length)
        // Set all pending comments to streaming state
        setComments(prev => {
          let newDict = InlineComment.copyDict(prev)
          payloadComments->Array.forEach(pc => {
            let key = scopedAskKey(pc.commentKey)
            switch Js.Dict.get(newDict, key) {
            | Some(c) =>
              Js.Dict.set(newDict, key, {text: c.text, aiReply: State.AiStreaming("")})
            | None => ()
            }
          })
          newDict
        })

        setIsAskingPi(_ => true)
        setActivePiRun(_ => Some({action: "Inline Q&A", model}))

        let onSuccess = (replies: array<Ipc.askPiReply>): Js.Promise.t<unit> => {
          Js.log2("[BAKA UI] Ask Pi success replies", replies->Array.length)
          setComments(prev => {
            let newDict = InlineComment.copyDict(prev)
            replies->Array.forEach(reply => {
              let key = InlineComment.normalizeModelKey(reply.commentKey)
              let scopedKey = scopedAskKey(key)
              Js.log2("[BAKA UI] Ask Pi applying reply key", scopedKey)
              switch Js.Dict.get(newDict, scopedKey) {
              | Some(c) =>
                Js.Dict.set(newDict, scopedKey, {text: c.text, aiReply: State.AiDone(reply.reply)})
              | None => ()
              }
            })
            newDict
          })
          setIsAskingPi(_ => false)
          setActivePiRun(_ => None)
          Js.Promise2.resolve()
        }

        let onError = (_err: Js.Promise2.error): Js.Promise.t<unit> => {
          let msg = Raw.errorMessage(_err)
          Js.log2("[BAKA UI] Ask Pi error", msg)
          // Mark all streaming comments as error
          setComments(prev => {
          let newDict = InlineComment.copyDict(prev)
          payloadComments->Array.forEach(pc => {
            let key = scopedAskKey(pc.commentKey)
            switch Js.Dict.get(newDict, key) {
            | Some(c) =>
              Js.Dict.set(newDict, key, {text: c.text, aiReply: State.AiError(msg)})
            | None => ()
            }
          })
            newDict
          })
          setIsAskingPi(_ => false)
          setActivePiRun(_ => None)
          Js.Promise2.resolve()
        }

        let _ = Js.Promise2.catch(
          Js.Promise2.then(
            if reviewSourceMode == History {
              Ipc.callAskPiWithDiff(historyRawPatch, payloadComments, model)
            } else {
              Ipc.callAskPi(
                payloadComments,
                model,
              )
            },
            onSuccess,
          ),
          onError,
        )
      }
    }
  }

  let handleFullReview = (kind: Ipc.fullReviewKind, _event) => {
    if activeReview == None {
      let (label, progress, commentPrefix) = switch kind {
      | CodeReview => ("Review", "Pi is reviewing the current diff...", "Pi review: ")
      | VulnerabilityCheck => (
          "Vulnerability Check",
          "Pi is checking the current diff for vulnerabilities...",
          "Pi vulnerability check: ",
        )
      }
      Js.log2("[BAKA UI] Full review button clicked", label)
      let model = PiPreferences.resolve(
        piPreferences,
        switch kind {
        | CodeReview => piPreferences.codeReviewModel
        | VulnerabilityCheck => piPreferences.securityReviewModel
        },
      )
      setActiveReview(_ => Some(kind))
      setActivePiRun(_ => Some({action: label, model}))
      setReviewSummaryLabel(_ => label)
      setReviewSummary(_ => progress)

      let onSuccess = (review: Ipc.fullReviewResult): Js.Promise.t<unit> => {
        Js.log2("[BAKA UI] Full review success summary", review.summary)
        Js.log2("[BAKA UI] Full review finding count", review.findings->Array.length)
        setReviewSummary(_ => review.summary)
        setComments(prev => {
          let newDict = InlineComment.copyDict(prev)
          review.findings->Array.forEach(finding => {
            let key = InlineComment.normalizeModelKey(finding.commentKey)
            switch InlineComment.parseKey(key) {
            | Some(_) =>
              switch Js.Dict.get(validReviewKeys, key) {
              | Some(true) => Js.log2("[BAKA UI] Full review inserting annotation", key)
              | _ => Js.log2("[BAKA UI] Full review inserting file-level finding", key)
              }
              let text = commentPrefix ++ finding.summary
              let body = if finding.body->String.trim->String.length > 0 {
                finding.body
              } else {
                finding.summary
              }
              Js.Dict.set(newDict, key, {text: text, aiReply: State.AiDone(body)})
            | None => Js.log2("[BAKA UI] Full review skipping malformed finding", key)
            }
          })
          newDict
        })
        setReviewSuggestions(prev => {
          let newDict: Js.Dict.t<State.reviewSuggestion> = Raw.copyDict(prev)
          review.findings->Array.forEach(finding => {
            let key = InlineComment.normalizeModelKey(finding.commentKey)
            switch InlineComment.parseKey(key) {
            | Some(_) =>
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
            | None => ()
            }
          })
          newDict
        })
        setActiveReview(_ => None)
        setActivePiRun(_ => None)
        Js.Promise2.resolve()
      }

      let onError = (err: Js.Promise2.error): Js.Promise.t<unit> => {
        let msg = Raw.errorMessage(err)
        Js.log2("[BAKA UI] Full review error", msg)
        setReviewSummary(_ => label ++ " failed: " ++ msg)
        setActiveReview(_ => None)
        setActivePiRun(_ => None)
        Js.Promise2.resolve()
      }

      let _ = Js.Promise2.catch(
        Js.Promise2.then(
          Ipc.callStartFullReview(
            kind,
            model,
          ),
          onSuccess,
        ),
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
    light: themeNames.light,
    dark: themeNames.dark,
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
  let isReviewing = activeReview != None
  let isCodeReviewing = activeReview == Some(CodeReview)
  let isCheckingVulnerabilities = activeReview == Some(VulnerabilityCheck)
  let shouldShowReviewSummary = isReviewing || reviewSummary != "No full review has run yet."
  let reviewSummaryText =
    reviewSummary ++
    if reviewCount > 0 {
      "\n" ++ Int.toString(reviewCount) ++ " finding(s), " ++ Int.toString(actionableReviewCount) ++ " actionable."
    } else {
      ""
    }

  let diffChildren = React.useMemo4((): array<React.element> => {
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
  }, (patchState, isDark, themeNames, currentColors))

  let historyCommits = switch historyState {
  | HistoryReady(commits) => commits
  | _ => []
  }

  let selectedCommit = historyCommits->Array.find(commit => commit.hash == selectedCommitHash)

  let historyFileDiffs = switch commitPatchState {
  | CommitPatchReady(_, parsed) =>
    parsed->Array.flatMap(patch => patch.files)
  | _ => []
  }

  let historyFileNames = historyFileDiffs->Array.map(fileDiff => fileDiffName(fileDiff))

  let selectedHistoryFileDiffs =
    if selectedCommitFile == "" {
      historyFileDiffs
    } else {
      historyFileDiffs->Array.filter(fileDiff => fileDiffName(fileDiff) == selectedCommitFile)
    }

  let historyDiffChildren = React.useMemo((): array<React.element> =>
    selectedHistoryFileDiffs->Array.map(fileDiff => {
      let fileName = fileDiffName(fileDiff)
      let diffStyle = historyDiffStyleFor(fileName)
      <div key={selectedCommitHash ++ ":" ++ fileName} id={"history-" ++ fileName} className={Styles.diffWrapper}>
        <InlineComment
          fileDiff={fileDiff}
          theme={style}
          themeType={if (isDark) { "dark" } else { "light" }}
          uiColors={currentColors}
          commentKeyPrefix={historyCommentPrefix}
          showFullFileButton={false}
          diffStyle={diffStyle}
          onDiffStyleToggle={() => toggleHistoryDiffStyle(fileName)}
        />
      </div>
    })
  , (selectedHistoryFileDiffs, isDark, themeNames, currentColors, historyDiffStyles))

  let renderModelSelect = (~label, ~hint, ~value, ~inherit, ~onChange) =>
    <label className={Styles.settingsCard(currentColors)}>
      <span className={Styles.settingsLabel}>{str(label)}</span>
      <span className={Styles.settingsCardHint(currentColors)}>{str(hint)}</span>
      <select value onChange className={Styles.settingsSelect(currentColors)}>
        {inherit
          ? <option value="">
              {str(
                "Use default" ++
                if piPreferences.defaultModel != "" {
                  " (" ++ piPreferences.defaultModel ++ ")"
                } else if piResolvedDefault != "" {
                  " (" ++ piResolvedDefault ++ ")"
                } else {
                  ""
                },
              )}
            </option>
          : <option value="">
              {str(
                "Pi default" ++
                if piResolvedDefault != "" { " (" ++ piResolvedDefault ++ ")" } else { "" },
              )}
            </option>}
        {React.array(piModels->Array.map(model => {
          let id = model.provider ++ "/" ++ model.id
          <option key={id} value={id}>
            {str(model.provider ++ " / " ++ if model.name != "" { model.name } else { model.id })}
          </option>
        }))}
      </select>
    </label>

  let renderSettings = () =>
    <main className={Styles.settingsPage(currentColors)}>
      <div className={Styles.settingsContent}>
        <h1 className={Styles.settingsTitle}>{str("Settings")}</h1>
        <p className={Styles.settingsDescription(currentColors)}>
          {str("Choose the Shiki themes used throughout BAKA. Your selections are saved automatically.")}
        </p>
        <div className={Styles.settingsGrid}>
          <label className={Styles.settingsCard(currentColors)}>
            <span className={Styles.settingsLabel}>{str("Light theme")}</span>
            <select
              value={themeNames.light}
              onChange={handleLightThemeChange}
              className={Styles.settingsSelect(currentColors)}
            >
              {React.array(lightThemeOptions->Array.map(theme =>
                <option key={theme.id} value={theme.id}>
                  {str(theme.displayName)}
                </option>
              ))}
            </select>
          </label>
          <label className={Styles.settingsCard(currentColors)}>
            <span className={Styles.settingsLabel}>{str("Dark theme")}</span>
            <select
              value={themeNames.dark}
              onChange={handleDarkThemeChange}
              className={Styles.settingsSelect(currentColors)}
            >
              {React.array(darkThemeOptions->Array.map(theme =>
                <option key={theme.id} value={theme.id}>
                  {str(theme.displayName)}
                </option>
              ))}
            </select>
          </label>
        </div>
        <h2 className={Styles.settingsSectionTitle}>{str("Pi models")}</h2>
        <p className={Styles.settingsDescription(currentColors)}>
          {str("Choose a default model, then override individual actions where a specialized or lower-cost model is more appropriate.")}
        </p>
        <div className={Styles.settingsGrid}>
          {renderModelSelect(
            ~label="Default model",
            ~hint="Used by every action that does not have an explicit override.",
            ~value=piPreferences.defaultModel,
            ~inherit=false,
            ~onChange=event =>
              setPiPreferences(previous => {
                ...previous,
                defaultModel: JsxEvent.Form.target(event)["value"],
              }),
          )}
          {renderModelSelect(
            ~label="Inline Q&A",
            ~hint="Replies to comments in the diff and full-file viewer.",
            ~value=piPreferences.inlineReviewModel,
            ~inherit=true,
            ~onChange=event =>
              setPiPreferences(previous => {
                ...previous,
                inlineReviewModel: JsxEvent.Form.target(event)["value"],
              }),
          )}
          {renderModelSelect(
            ~label="Code review",
            ~hint="General correctness and maintainability review.",
            ~value=piPreferences.codeReviewModel,
            ~inherit=true,
            ~onChange=event =>
              setPiPreferences(previous => {
                ...previous,
                codeReviewModel: JsxEvent.Form.target(event)["value"],
              }),
          )}
          {renderModelSelect(
            ~label="Security review",
            ~hint="Vulnerability-focused analysis.",
            ~value=piPreferences.securityReviewModel,
            ~inherit=true,
            ~onChange=event =>
              setPiPreferences(previous => {
                ...previous,
                securityReviewModel: JsxEvent.Form.target(event)["value"],
              }),
          )}
          {renderModelSelect(
            ~label="Specification check",
            ~hint="Compares the current changes against a supplied specification.",
            ~value=piPreferences.specReviewModel,
            ~inherit=true,
            ~onChange=event =>
              setPiPreferences(previous => {
                ...previous,
                specReviewModel: JsxEvent.Form.target(event)["value"],
              }),
          )}
          {renderModelSelect(
            ~label="Suggestion implementation",
            ~hint="Generates patches for accepted review findings.",
            ~value=piPreferences.suggestionModel,
            ~inherit=true,
            ~onChange=event =>
              setPiPreferences(previous => {
                ...previous,
                suggestionModel: JsxEvent.Form.target(event)["value"],
              }),
          )}
          {renderModelSelect(
            ~label="Suggestion validation",
            ~hint="Validates generated patches and creates a repair patch when needed.",
            ~value=piPreferences.validationModel,
            ~inherit=true,
            ~onChange=event =>
              setPiPreferences(previous => {
                ...previous,
                validationModel: JsxEvent.Form.target(event)["value"],
              }),
          )}
          {renderModelSelect(
            ~label="Plan creation",
            ~hint="Inspects the repository and creates feature or bug-fix plans.",
            ~value=piPreferences.planModel,
            ~inherit=true,
            ~onChange=event =>
              setPiPreferences(previous => {
                ...previous,
                planModel: JsxEvent.Form.target(event)["value"],
              }),
          )}
          {renderModelSelect(
            ~label="Plan implementation",
            ~hint="Turns an accepted plan into an applicable patch.",
            ~value=piPreferences.implementationModel,
            ~inherit=true,
            ~onChange=event =>
              setPiPreferences(previous => {
                ...previous,
                implementationModel: JsxEvent.Form.target(event)["value"],
              }),
          )}
        </div>
        <p className={Styles.settingsHint(currentColors)}>
          {str(
            if piModelsError != "" {
              "Could not load Pi models: " ++ piModelsError
            } else if isThemeLoading {
              "Applying themes…"
            } else {
              "Preferences saved locally."
            },
          )}
        </p>
      </div>
    </main>

  let idlePiStatus = switch viewMode {
  | Feature =>
    switch featurePlan {
    | Applying(_) =>
      "Plan implementation · " ++
      PiPreferences.resolve(piPreferences, piPreferences.implementationModel)
    | _ =>
      "Plan creation · " ++ PiPreferences.resolve(piPreferences, piPreferences.planModel)
    }
  | Review =>
    switch activeReview {
    | Some(CodeReview) =>
      "Code review · " ++ PiPreferences.resolve(piPreferences, piPreferences.codeReviewModel)
    | Some(VulnerabilityCheck) =>
      "Security review · " ++
      PiPreferences.resolve(piPreferences, piPreferences.securityReviewModel)
    | None =>
      "Inline Q&A · " ++
      PiPreferences.resolve(piPreferences, piPreferences.inlineReviewModel)
    }
  | _ =>
    "Default · " ++
    if piPreferences.defaultModel == "" { piResolvedDefault } else { piPreferences.defaultModel }
  }

  let displayPiModel = model =>
    if model != "" {
      model
    } else if piResolvedDefault != "" {
      piResolvedDefault
    } else {
      "Pi default"
    }

  let piStatus = switch activePiRun {
  | Some(run) =>
    run.action ++ " · " ++ displayPiModel(run.model)
  | None =>
    let parts = idlePiStatus->String.split(" · ")
    switch (Array.get(parts, 0), Array.get(parts, 1)) {
    | (Some(action), Some(model)) => action ++ " · " ++ displayPiModel(model)
    | _ => idlePiStatus
    }
  }

  let hasGitRepository = switch repoInfo {
  | Some(info) => info.isGitRepository
  | None => repoRoot != ""
  }

  let activeRepositoryPath = switch repoInfo {
  | Some(info) if info.repoRoot != "" => info.repoRoot
  | Some(info) => info.workingDirectory
  | None => repoRoot
  }

  let renderRepositoryPicker = (message: string) =>
    <div className={Styles.repositoryPicker(currentColors)}>
      <div className={Styles.repositoryPickerTitle}>
        {str("Choose a repository")}
      </div>
      <div className={Styles.repositoryPickerMessage(currentColors)}>
        {str(message)}
      </div>
      {activeRepositoryPath != ""
        ? <div className={Styles.repositoryPath(currentColors)} title={activeRepositoryPath}>
            {str(activeRepositoryPath)}
          </div>
        : React.null}
      <button
        type_="button"
        onClick={handleChooseWorkingFolder}
        className={buttonStyle}
      >
        {str("Open Repository")}
      </button>
    </div>

  switch patchState {
  | PatchLoading =>
    <div className={Styles.container}>
      <div className={headerStyle}>
        <div className={Styles.headerActions}>
          <button
            type_="button"
            title="Choose repository"
            onClick={handleChooseWorkingFolder}
            className={buttonStyle}
          >
            {str("Open Repository")}
          </button>
          <button
            type_="button"
            onClick={handleThemeToggle}
            className={buttonStyle}
          >
            {str(if (isDark) { "Light Mode" } else { "Dark Mode" })}
          </button>
          <button
            type_="button"
            ariaLabel="Open settings"
            title="Settings"
            ariaPressed={settingsAriaPressed}
            onClick={_ => setViewMode(_ => Settings)}
            className={Styles.iconButton(currentColors)}
          >
            {str("⚙")}
          </button>
        </div>
      </div>
      {if viewMode == Settings {
        renderSettings()
      } else {
        <div className={Styles.loadingContainer}>
          {str("Loading diff...")}
        </div>
      }}
    </div>

  | PatchError(msg) =>
    <div className={Styles.container}>
      <div className={headerStyle}>
        <div className={Styles.headerActions}>
          <button
            type_="button"
            title="Choose repository"
            onClick={handleChooseWorkingFolder}
            className={buttonStyle}
          >
            {str("Open Repository")}
          </button>
          <button
            type_="button"
            onClick={handleThemeToggle}
            className={buttonStyle}
          >
            {str(if (isDark) { "Light Mode" } else { "Dark Mode" })}
          </button>
          <button
            type_="button"
            ariaLabel="Open settings"
            title="Settings"
            ariaPressed={settingsAriaPressed}
            onClick={_ => setViewMode(_ => Settings)}
            className={Styles.iconButton(currentColors)}
          >
            {str("⚙")}
          </button>
        </div>
      </div>
      {if viewMode == Settings {
        renderSettings()
      } else if !hasGitRepository {
        renderRepositoryPicker(msg)
      } else {
        <div className={Styles.errorContainer(currentColors)}>
          <div className={Styles.errorMessage}>
            {str("Failed to load diff:\n\n" ++ msg)}
          </div>
        </div>
      }}
    </div>

  | PatchReady(patches) =>
    <div className={Styles.container}>
      <div className={headerStyle}>
        <div className={Styles.tabs(currentColors)} role="tablist" ariaLabel="Main views">
          <button
            type_="button"
            role="tab"
            ariaSelected={viewMode == Review}
            onClick={_ => setViewMode(_ => Review)}
            className={Styles.tab(currentColors)}
          >
            {str("Review")}
          </button>
          <button
            type_="button"
            role="tab"
            ariaSelected={viewMode == Project}
            onClick={_ => setViewMode(_ => Project)}
            className={Styles.tab(currentColors)}
          >
            {str("Project")}
          </button>
          <button
            type_="button"
            role="tab"
            ariaSelected={viewMode == Commit}
            onClick={_ => setViewMode(_ => Commit)}
            className={Styles.tab(currentColors)}
          >
            {str("Commit")}
          </button>
          <button
            type_="button"
            role="tab"
            ariaSelected={viewMode == Feature}
            onClick={_ => setViewMode(_ => Feature)}
            className={Styles.tab(currentColors)}
          >
            {str("New Feature")}
          </button>
        </div>
        <div className={Styles.headerActions}>
          <button
            type_="button"
            title="Choose repository"
            onClick={handleChooseWorkingFolder}
            className={buttonStyle}
          >
            {str("Open Repository")}
          </button>
          {viewMode == Review
            ? <div className={Styles.aiMenu}>
                <button
                  type_="button"
                  ariaHaspopup=#menu
                  className={Styles.askPiButton(currentColors, isReviewing || isAskingPi)}
                >
                  {str(if isReviewing || isAskingPi { "AI working…" } else { "AI ▾" })}
                </button>
                <div className={Styles.aiMenuPanel(currentColors)} role="menu">
                  <button
                    type_="button"
                    role="menuitem"
                    onClick={handleAskPi}
                    disabled={isAskingPi}
                    className={Styles.aiMenuItem(currentColors, isAskingPi)}
                  >
                    {str(if isAskingPi { "Asking Pi…" } else { "Ask Pi" })}
                  </button>
                  <button
                    type_="button"
                    role="menuitem"
                    onClick={event => handleFullReview(CodeReview, event)}
                    disabled={isReviewing}
                    title={reviewButtonTitle}
                    className={Styles.aiMenuItem(currentColors, isReviewing)}
                  >
                    {str(if isCodeReviewing { "Reviewing…" } else { "Code Review" })}
                  </button>
                  <button
                    type_="button"
                    role="menuitem"
                    onClick={event => handleFullReview(VulnerabilityCheck, event)}
                    disabled={isReviewing}
                    title={reviewButtonTitle}
                    className={Styles.aiMenuItem(currentColors, isReviewing)}
                  >
                    {str(if isCheckingVulnerabilities { "Checking…" } else { "Vulnerability Check" })}
                  </button>
                  <button
                    type_="button"
                    role="menuitem"
                    onClick={_ => setIsSpecCheckOpen(_ => true)}
                    className={Styles.aiMenuItem(currentColors, false)}
                  >
                    {str("Check against spec")}
                  </button>
                </div>
              </div>
            : React.null}
          <button
            type_="button"
            onClick={handleThemeToggle}
            className={buttonStyle}
          >
            {str(if (isDark) { "Light Mode" } else { "Dark Mode" })}
          </button>
          <button
            type_="button"
            ariaLabel="Open settings"
            title="Settings"
            ariaPressed={settingsAriaPressed}
            onClick={_ => setViewMode(_ => Settings)}
            className={Styles.iconButton(currentColors)}
          >
            {str("⚙")}
          </button>
        </div>
      </div>
      {viewMode != Commit && shouldShowReviewSummary
        ? <div className={Styles.reviewSummaryBar(currentColors)}>
            <span className={Styles.reviewSummaryLabel(currentColors)}>
              {str(reviewSummaryLabel)}
            </span>
            {str(reviewSummaryText)}
          </div>
        : React.null}
      {isSpecCheckOpen
        ? <SpecCheckView
            uiColors={currentColors}
            themeType={if isDark { "dark" } else { "light" }}
            onClose={() => setIsSpecCheckOpen(_ => false)}
            onChanged={requestPatchReload}
          />
        : React.null}
      <div className={Styles.commitViewHost(viewMode != Commit)}>
        <CommitView
            patches={patches}
            repoRoot={repoRoot}
            theme={style}
            themeType={if (isDark) { "dark" } else { "light" }}
            uiColors={currentColors}
            onCommitted={requestPatchReload}
          />
      </div>
      {switch viewMode {
      | Settings => renderSettings()
      | Commit => React.null
      | Feature => <NewFeatureView uiColors={currentColors} onApplied={requestPatchReload} />
      | Project =>
        <ProjectView
          theme={style}
          themeType={if (isDark) { "dark" } else { "light" }}
          uiColors={currentColors}
        />
      | Review => <div className={Styles.content}>
            <aside className={Styles.sidebar(currentColors)}>
              <div className={Styles.reviewModeTabs(currentColors)} role="tablist" ariaLabel="Review source">
                <button
                  type_="button"
                  role="tab"
                  ariaSelected={reviewSourceMode == Changed}
                  onClick={_ => setReviewSourceMode(_ => Changed)}
                  className={Styles.reviewModeTab(currentColors)}
                >
                  {str("Changed")}
                </button>
                <button
                  type_="button"
                  role="tab"
                  ariaSelected={reviewSourceMode == History}
                  onClick={_ => setReviewSourceMode(_ => History)}
                  className={Styles.reviewModeTab(currentColors)}
                >
                  {str("History")}
                </button>
              </div>
              {switch reviewSourceMode {
              | Changed =>
                <Trees.make
                  model={fileTree.model}
                  header={<div className={Styles.treeHeader(currentColors)}>{str("Changed files")}</div>}
                  style={Styles.treeStyle(currentColors)}
                />
              | History =>
                <>
                  <div className={Styles.treeHeader(currentColors)}>{str("Commits")}</div>
                  <div className={Styles.commitList}>
                    {switch historyState {
                    | HistoryIdle | HistoryLoading =>
                      <div className={Styles.paneMessage(currentColors)}>{str("Loading commits...")}</div>
                    | HistoryError(message) =>
                      <div className={Styles.paneMessage(currentColors)}>{str(message)}</div>
                    | HistoryReady(commits) =>
                      commits->Array.length == 0
                        ? <div className={Styles.paneMessage(currentColors)}>{str("No commits found.")}</div>
                        : React.array(commits->Array.map(commit =>
                            <button
                              key={commit.hash}
                              type_="button"
                              title={commit.subject}
                              onClick={_ => setSelectedCommitHash(_ => commit.hash)}
                              className={Styles.commitRow(currentColors, commit.hash == selectedCommitHash)}
                            >
                              <span className={Styles.commitSubject}>{str(commit.subject)}</span>
                              <span className={Styles.commitMeta(currentColors)}>
                                {str(commit.author ++ " · " ++ commit.date ++ " · " ++ commit.shortHash)}
                              </span>
                            </button>
                          ))
                    }}
                  </div>
                </>
              }}
            </aside>
            {reviewSourceMode == History
              ? <aside className={Styles.historyFilesPanel(currentColors)}>
                  <div className={Styles.treeHeader(currentColors)}>
                    {switch selectedCommit {
                    | Some(commit) => str("Files in " ++ commit.shortHash)
                    | None => str("Files")
                    }}
                  </div>
                  <div className={Styles.fileList}>
                    {switch commitPatchState {
                    | CommitPatchIdle =>
                      <div className={Styles.paneMessage(currentColors)}>{str("Select a commit.")}</div>
                    | CommitPatchLoading =>
                      <div className={Styles.paneMessage(currentColors)}>{str("Loading files...")}</div>
                    | CommitPatchError(message) =>
                      <div className={Styles.paneMessage(currentColors)}>{str(message)}</div>
                    | CommitPatchReady(_, _) =>
                      historyFileNames->Array.length == 0
                        ? <div className={Styles.paneMessage(currentColors)}>{str("No changed files in this commit.")}</div>
                        : React.array(historyFileNames->Array.map(fileName =>
                            <button
                              key={fileName}
                              type_="button"
                              title={fileName}
                              onClick={_ => setSelectedCommitFile(_ => fileName)}
                              className={Styles.fileRow(currentColors, fileName == selectedCommitFile)}
                            >
                              {str(fileName)}
                            </button>
                          ))
                    }}
                  </div>
                </aside>
              : React.null}
            <main ref={ReactDOM.Ref.domRef(virtualizerWrapperRef)} className={Styles.main}>
              {switch reviewSourceMode {
              | Changed =>
                <Virtualizer style={%raw(`{"height": "100%", "overflow-y": "auto"}`)}>
                  {React.array(diffChildren)}
                </Virtualizer>
              | History =>
                switch commitPatchState {
                | CommitPatchIdle =>
                  <div className={Styles.paneMessage(currentColors)}>{str("Select a commit to review.")}</div>
                | CommitPatchLoading =>
                  <div className={Styles.paneMessage(currentColors)}>{str("Loading commit diff...")}</div>
                | CommitPatchError(message) =>
                  <div className={Styles.paneMessage(currentColors)}>{str(message)}</div>
                | CommitPatchReady(_, _) =>
                  <Virtualizer style={%raw(`{"height": "100%", "overflow-y": "auto"}`)}>
                    {React.array(historyDiffChildren)}
                  </Virtualizer>
                }
              }}
            </main>
          </div>
	      }}
      <div className={Styles.statusBar(currentColors)}>
        {str("Pi · " ++ piStatus)}
      </div>
	    </div>
	  }
	}
