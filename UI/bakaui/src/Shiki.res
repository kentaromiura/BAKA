open State

@module("./ShikiTheme.mjs")
external loadThemeColors: string => Js.Promise.t<uiColors> = "loadThemeColors"

@module("./ShikiTheme.mjs")
external loadBothThemes: (string, string) => Js.Promise.t<option<loadedThemes>> = "loadBothThemes"

@module("./ShikiTheme.mjs")
external preloadShiki: (string, string) => Js.Promise.t<unit> = "preloadShiki"
