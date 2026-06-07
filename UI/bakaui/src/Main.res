@val external window: {..} = "window"

@module("./RegisterLanguages.mjs")
external registerRescript: unit => unit = "registerRescript"

@module("./RegisterLanguages.mjs")
external registerOdinExtension: unit => unit = "registerOdinExtension"

let store = Jotai.Store.make()
let start = () => {
  registerRescript()
  registerOdinExtension()
  let _ = Shiki.preloadShiki()
  let _ = Markdown.preloadMarkdown()
  switch ReactDOM.querySelector("#root") {
  | Some(domElement) =>
    let themeNames = Jotai.Store.get(store, State.themeAtom)
    let root = ReactDOM.Client.createRoot(domElement)
    let render = () =>
      ReactDOM.Client.Root.render(
        root,
        <React.StrictMode>
          <Jotai.Provider store={store}>
            <App />
          </Jotai.Provider>
        </React.StrictMode>,
      )
    let resolveThemes = themes => {
      Jotai.Store.set(store, State.themeColorsAtom, themes)
      render()
      Js.Promise2.resolve()
    }
    let handleError = _ => {
      render()
      Js.Promise2.resolve()
    }
    let _ = Js.Promise2.catch(
      Js.Promise2.then(
        Shiki.loadBothThemes(themeNames.light, themeNames.dark),
        resolveThemes,
      ),
      handleError,
    )
    ()
  | None => ()
  }
}

window["addEventListener"]("DOMContentLoaded", start)
