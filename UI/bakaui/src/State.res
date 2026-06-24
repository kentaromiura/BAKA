type aiReplyState = AiIdle | AiStreaming(string) | AiDone(string) | AiError(string)

type commentData = {
  text: string,
  aiReply: aiReplyState,
}

type reviewSuggestion = {
  summary: string,
  severity: string,
  actionable: bool,
  suggestion: string,
  isApplying: bool,
  applyResult: option<string>,
  applyError: option<string>,
}

type themeType = {
  light: string,
  dark: string,
}

type uiColors = {
  bg: string,
  fg: string,
  border: string,
  buttonBg: string,
  buttonFg: string,
  buttonHoverBg: string,
  inputBg: string,
  inputFg: string,
  inputBorder: string,
  inputPlaceholder: string,
  focusBorder: string,
  selectionBg: string,
  hoverBg: string,
  activeSelectionBg: string,
  descriptionFg: string,
  surfaceBg: string,
  surfaceBorder: string,
  badgeBg: string,
  dangerBg: string,
  dangerHoverBg: string,
  themeType: string,
}

let counter = Jotai.Atom.make(0)

let commentsAtom: Jotai.Atom.t<Js.Dict.t<commentData>, _, _> = Jotai.Atom.make(Js.Dict.empty())

let reviewSuggestionsAtom: Jotai.Atom.t<Js.Dict.t<reviewSuggestion>, _, _> = Jotai.Atom.make(Js.Dict.empty())

let themeAtom: Jotai.Atom.t<themeType, _, _> = Jotai.Atom.make({
  light: "rose-pine-dawn",
  dark: "tokyo-night",
})

let isDarkAtom: Jotai.Atom.t<bool, _, _> = Jotai.Atom.make(true)

let defaultUiColors: uiColors = {
  bg: "#1f2937",
  fg: "#f9fafb",
  border: "#374151",
  buttonBg: "#374151",
  buttonFg: "#f9fafb",
  buttonHoverBg: "#4b5563",
  inputBg: "#111827",
  inputFg: "#f9fafb",
  inputBorder: "#4b5563",
  inputPlaceholder: "#6b7280",
  focusBorder: "#60a5fa",
  selectionBg: "#374151",
  hoverBg: "#4b5563",
  activeSelectionBg: "#4b5563",
  descriptionFg: "#9ca3af",
  surfaceBg: "#1f2937",
  surfaceBorder: "#374151",
  badgeBg: "#374151",
  dangerBg: "#ef4444",
  dangerHoverBg: "#dc2626",
  themeType: "dark",
}

let lightDefaultUiColors: uiColors = {
  bg: "#f9fafb",
  fg: "#1f2937",
  border: "#e5e7eb",
  buttonBg: "#ffffff",
  buttonFg: "#1f2937",
  buttonHoverBg: "#f3f4f6",
  inputBg: "#ffffff",
  inputFg: "#1f2937",
  inputBorder: "#d1d5db",
  inputPlaceholder: "#9ca3af",
  focusBorder: "#3b82f6",
  selectionBg: "#e5e7eb",
  hoverBg: "#f3f4f6",
  activeSelectionBg: "#e5e7eb",
  descriptionFg: "#9ca3af",
  surfaceBg: "#fafafa",
  surfaceBorder: "#e6e9ef",
  badgeBg: "#ccd0da",
  dangerBg: "#d20f39",
  dangerHoverBg: "#ff6b81",
  themeType: "light",
}

type loadedThemes = {
  light: uiColors,
  dark: uiColors,
}

let themeColorsAtom: Jotai.Atom.t<option<loadedThemes>, _, _> = Jotai.Atom.make(None)
