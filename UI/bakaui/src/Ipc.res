// Bridge to Odin via webview.bind
// Each bound function is exposed as a global async JS function that takes
// a JSON string argument and returns a JSON string promise.

@val external getPatch_raw: string => Js.Promise.t<string> = "getPatch"

let callGetPatch = (): Js.Promise.t<string> => {
  let parseResponse = (raw: string): Js.Promise.t<string> => {
    %raw(`(async (raw) => {
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    })(raw)`)
  }
  Js.Promise.then_(parseResponse)(getPatch_raw("{}"))
}

@val external getFilePatch_raw: string => Js.Promise.t<string> = "getFilePatch"

let callGetFilePatch = (path: string): Js.Promise.t<string> => {
  let parseResponse = (raw: string): Js.Promise.t<string> => {
    %raw(`(async (raw) => {
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    })(raw)`)
  }
  Js.Promise.then_(parseResponse)(getFilePatch_raw(path))
}

type askPiRequest = {commentKey: string, text: string}
type askPiReply = {commentKey: string, reply: string}

// Ask Pi: send all comments as JSON, receive back {replies: [{commentKey, reply}]}
// Odin spawns `pi --mode json @prompt.txt`, parses [REPLY:key] blocks from output.
// The webview library JSON-stringifies all arguments and passes them as a JSON
// array to the C callback, so we spread `comments` as separate arguments.
@val external askPi_raw: string => Js.Promise.t<string> = "askPi"

let callAskPi = (comments: array<askPiRequest>): Js.Promise.t<array<askPiReply>> => {
  let parseResponse = (raw: string): Js.Promise.t<array<askPiReply>> => {
    Js.log2("response", raw)
    %raw(`(async (raw) => {
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    })(raw)`)
  }
  let promise = %raw(`askPi(...comments)`)
  Js.log(promise)
  Js.Promise.then_(parseResponse)(promise)
}

// Ask Pi with a caller-provided diff. Used by the "view full file" modal
// so the AI sees the whole file as context instead of just the changed
// lines. The request body is a JSON object {diff, comments}.
//
// The webview library JSON-stringifies every argument before handing it
// to the native callback, so we pass the object directly (not a
// pre-stringified version) to avoid double-encoding. The C callback then
// receives a JSON array of one object: [{diff, comments}].
let callAskPiWithDiff = (
  diff: string,
  comments: array<askPiRequest>,
): Js.Promise.t<array<askPiReply>> => {
  let parseResponse = (raw: string): Js.Promise.t<array<askPiReply>> => {
    %raw(`(async (raw) => {
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    })(raw)`)
  }
  let promise = %raw(`askPiWithDiff({diff, comments})`)
  Js.Promise.then_(parseResponse)(promise)
}
