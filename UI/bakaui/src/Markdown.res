@module("./Markdown.mjs")
external preloadMarkdown: unit => Js.Promise.t<unit> = "preloadMarkdown"

@module("./Markdown.mjs")
external renderMarkdown: (string, string) => string = "renderMarkdown"

@react.component
let make = (~text: string, ~themeType: string) => {
  let html = renderMarkdown(text, themeType)
  <div dangerouslySetInnerHTML={"__html": html} />
}
