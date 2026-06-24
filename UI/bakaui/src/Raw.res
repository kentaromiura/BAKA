let copyDict: Js.Dict.t<'value> => Js.Dict.t<'value> =
  %raw(`dict => Object.assign({}, dict)`)

let deleteProp: (Js.Dict.t<'value>, string) => unit =
  %raw(`(dict, key) => { delete dict[key]; }`)

let errorMessage: Js.Promise2.error => string =
  %raw(`error => String(error).replace(/^Error: /, '')`)
