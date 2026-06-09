type fileTree

type useFileTreeOptions = {
  initialExpansion?: string,
  paths?: array<string>,
  onSelectionChange?: array<string> => unit,
}

type useFileTreeResult = {
  model: fileTree,
}

@module("@pierre/trees/react")
external useFileTree: useFileTreeOptions => useFileTreeResult = "useFileTree"

let resetPaths = (model: fileTree, paths: array<string>): unit =>
  %raw(`(model, paths) => { model.resetPaths(paths); }`)(model, paths)

@module("@pierre/trees/react") @react.component
external make: (
  ~model: fileTree,
  ~header: React.element =?,
  ~style: Js.t<{..}> =?,
) => React.element = "FileTree"
