let copyDict: Js.Dict.t<'value> => Js.Dict.t<'value> =
  %raw(`dict => Object.assign({}, dict)`)

let deleteProp: (Js.Dict.t<'value>, string) => unit =
  %raw(`(dict, key) => { delete dict[key]; }`)

let errorMessage: Js.Promise2.error => string =
  %raw(`error => {
    if (error == null) return "Unknown error";
    if (typeof error === "string") return error.replace(/^Error: /, "");
    if (typeof error.message === "string") return error.message.replace(/^Error: /, "");
    if (typeof error.error === "string") return error.error;
    try {
      const json = JSON.stringify(error);
      if (json && json !== "{}") return json;
    } catch (_err) {}
    return String(error).replace(/^Error: /, "");
  }`)
