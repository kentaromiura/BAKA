open State

type themeOption = {
  id: string,
  displayName: string,
}

@module("./ThemePreferences.mjs")
external load: unit => themeType = "loadThemePreferences"

@module("./ThemePreferences.mjs")
external save: themeType => unit = "saveThemePreferences"

@module("./ThemePreferences.mjs")
external getOptions: string => array<themeOption> = "getThemeOptions"
