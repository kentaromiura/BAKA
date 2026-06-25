open State

@module("./PiPreferences.mjs")
external load: unit => piPreferences = "loadPiPreferences"

@module("./PiPreferences.mjs")
external save: piPreferences => unit = "savePiPreferences"

@module("./PiPreferences.mjs")
external resolve: (piPreferences, string) => string = "resolvePiModel"
