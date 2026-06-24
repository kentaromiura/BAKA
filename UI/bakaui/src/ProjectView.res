open State

type projectState =
  | Loading
  | Ready(array<string>)
  | Failed(string)

module Styles = {
  let appFont = `"Ioskeley Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace`

  let content = Html.css`
    display: flex;
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

  let treeHeader = (colors: uiColors) => Html.css`
    padding: 10px 12px;
    border-bottom: 1px solid ${colors.border};
    color: ${colors.fg};
    font-family: ${appFont};
    font-size: 13px;
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
    })

  let main = (colors: uiColors) => Html.css`
    flex: 1;
    min-width: 0;
    min-height: 0;
    overflow: hidden;
    background-color: ${colors.bg};
  `

  let status = (colors: uiColors) => Html.css`
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px;
    color: ${colors.descriptionFg};
    font-family: ${appFont};
    font-size: 13px;
    text-align: center;
  `

  let error = (colors: uiColors) => Html.css`
    color: ${colors.dangerBg};
  `
}

@react.component
let make = (
  ~theme: Diffs.FileDiff.theme,
  ~themeType: string,
  ~uiColors: uiColors,
) => {
  let (state, setState) = React.useState(() => Loading)
  let (selectedFile, setSelectedFile) = React.useState((): option<string> => None)

  React.useEffect0(() => {
    Ipc.callGetProjectFiles()
      ->Js.Promise2.then(files => {
        setState(_ => Ready(files))
        setSelectedFile(current =>
          switch current {
          | Some(path) if files->Array.includes(path) => current
          | _ => Belt.Array.get(files, 0)
          }
        )
        Js.Promise2.resolve()
      })
      ->Js.Promise2.catch(err => {
        let message = %raw(`String(err).replace(/^Error: /, '')`)
        setState(_ => Failed(message))
        Js.Promise2.resolve()
      })
      ->ignore
    None
  })

  let paths = switch state {
  | Ready(files) => files
  | _ => []
  }

  let fileTree = Trees.useFileTree({
    paths: paths,
    initialExpansion: "open",
    onSelectionChange: selectedPaths =>
      setSelectedFile(_ => Belt.Array.get(selectedPaths, 0)),
  })

  React.useEffect1(() => {
    Trees.resetPaths(fileTree.model, paths)
    None
  }, [paths])

  <div className={Styles.content}>
    <aside className={Styles.sidebar(uiColors)}>
      <Trees.make
        model={fileTree.model}
        header={<div className={Styles.treeHeader(uiColors)}>{React.string("Project files")}</div>}
        style={Styles.treeStyle(uiColors)}
      />
    </aside>
    <main className={Styles.main(uiColors)}>
      {switch (state, selectedFile) {
      | (Loading, _) =>
        <div className={Styles.status(uiColors)}>{React.string("Loading project files...")}</div>
      | (Failed(message), _) =>
        <div className={Styles.status(uiColors) ++ " " ++ Styles.error(uiColors)}>
          {React.string("Failed to load project files: " ++ message)}
        </div>
      | (Ready([]), _) =>
        <div className={Styles.status(uiColors)}>{React.string("No project files found.")}</div>
      | (Ready(_), Some(fileName)) =>
        <FileViewer
          key={fileName}
          fileName={fileName}
          theme={theme}
          themeType={themeType}
          uiColors={uiColors}
          embedded=true
        />
      | (Ready(_), None) =>
        <div className={Styles.status(uiColors)}>{React.string("Select a file to view it.")}</div>
      }}
    </main>
  </div>
}
