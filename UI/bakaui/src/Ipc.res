// Bridge to Odin via webview.bind
// Each bound function is exposed as a global async JS function that takes
// a JSON string argument and returns a JSON string promise.

@val external getPatch_raw: string => Js.Promise.t<string> = "getPatch"

let callGetPatch = (): Js.Promise.t<string> => {
  let parseResponse = (raw: string): Js.Promise.t<string> => {
    let _ = %raw(`console.log("[BAKA UI] getPatch raw response meta", raw && raw.error ? {error: raw.error} : {resultBytes: raw && raw.result ? raw.result.length : null})`)
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
  Js.log2("[BAKA UI] getFilePatch called", path)
  let parseResponse = (raw: string): Js.Promise.t<string> => {
    let _ = %raw(`console.log("[BAKA UI] getFilePatch raw response meta", raw && raw.error ? {error: raw.error} : {resultBytes: raw && raw.result ? raw.result.length : null})`)
    %raw(`(async (raw) => {
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    })(raw)`)
  }
  Js.Promise.then_(parseResponse)(getFilePatch_raw(path))
}

@val external getProjectFiles_raw: string => Js.Promise.t<string> = "getProjectFiles"

let callGetProjectFiles = (): Js.Promise.t<array<string>> => {
  let parseResponse = (raw: string): Js.Promise.t<array<string>> => {
    let _ = %raw(`console.log("[BAKA UI] getProjectFiles raw response meta", raw && raw.error ? {error: raw.error} : {fileCount: raw && raw.result ? raw.result.length : null})`)
    %raw(`(async (raw) => {
      if (raw.error) throw new Error(raw.error);
      if (!Array.isArray(raw.result)) throw new Error("Missing project file list");
      return raw.result;
    })(raw)`)
  }
  Js.Promise.then_(parseResponse)(getProjectFiles_raw("{}"))
}

type askPiRequest = {commentKey: string, text: string}
type askPiReply = {commentKey: string, reply: string}
type fullReviewFinding = {
  commentKey: string,
  summary: string,
  body: string,
  severity: string,
  actionable: bool,
  suggestion: string,
}
type fullReviewResult = {
  summary: string,
  findings: array<fullReviewFinding>,
}
type fullReviewKind =
  | CodeReview
  | VulnerabilityCheck
type fullReviewRequest = {kind: string}
type applySuggestionRequest = {
  commentKey: string,
  suggestion: string,
}
type commitSelectionRequest = {
  message: string,
  body: string,
  patch: string,
}

// Ask Pi: send all comments as JSON, receive back {replies: [{commentKey, reply}]}
// Odin spawns `pi --mode json @prompt.txt`, parses [REPLY:key] blocks from output.
// The webview library JSON-stringifies all arguments and passes them as a JSON
// array to the C callback, so we spread `comments` as separate arguments.
@val external askPi_raw: string => Js.Promise.t<string> = "askPi"

let callAskPi = (comments: array<askPiRequest>): Js.Promise.t<array<askPiReply>> => {
  Js.log2("[BAKA UI] askPi called with comment count", comments->Array.length)
  let parseResponse = (raw: string): Js.Promise.t<array<askPiReply>> => {
    let _ = %raw(`console.log("[BAKA UI] askPi raw response meta", raw && raw.error ? {error: raw.error} : {replyCount: raw && raw.result ? raw.result.length : null})`)
    %raw(`(async (raw) => {
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    })(raw)`)
  }
  let promise = %raw(`askPi(...comments)`)
  Js.log2("[BAKA UI] askPi promise", promise)
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
  Js.log2("[BAKA UI] askPiWithDiff diff bytes", diff->String.length)
  Js.log2("[BAKA UI] askPiWithDiff comment count", comments->Array.length)
  let parseResponse = (raw: string): Js.Promise.t<array<askPiReply>> => {
    let _ = %raw(`console.log("[BAKA UI] askPiWithDiff raw response meta", raw && raw.error ? {error: raw.error} : {replyCount: raw && raw.result ? raw.result.length : null})`)
    %raw(`(async (raw) => {
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    })(raw)`)
  }
  let promise = %raw(`askPiWithDiff({diff, comments})`)
  Js.Promise.then_(parseResponse)(promise)
}

@val external startFullReview_raw: fullReviewRequest => Js.Promise.t<string> = "startFullReview"

let callStartFullReview = (kind: fullReviewKind): Js.Promise.t<fullReviewResult> => {
  let request = {
    kind: switch kind {
    | CodeReview => "code"
    | VulnerabilityCheck => "vulnerability"
    },
  }
  Js.log2("[BAKA UI] startFullReview called", request.kind)
  let parseResponse = (raw: string): Js.Promise.t<fullReviewResult> => {
    let _ = %raw(`console.log("[BAKA UI] startFullReview raw response meta", raw && raw.error ? {error: raw.error} : {summaryBytes: raw && raw.result && raw.result.summary ? raw.result.summary.length : null, findingCount: raw && raw.result && raw.result.findings ? raw.result.findings.length : null})`)
    %raw(`(async (raw) => {
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    })(raw)`)
  }
  Js.Promise.then_(parseResponse)(startFullReview_raw(request))
}

@val external applyReviewSuggestion_raw: string => Js.Promise.t<string> = "applyReviewSuggestion"

let callApplyReviewSuggestion = (
  request: applySuggestionRequest,
): Js.Promise.t<string> => {
  Js.log2("[BAKA UI] applyReviewSuggestion called", request)
  let parseResponse = (raw: string): Js.Promise.t<string> => {
    let _ = %raw(`console.log("[BAKA UI] applyReviewSuggestion raw response meta", raw && raw.error ? {error: raw.error} : {result: raw && raw.result ? raw.result : null})`)
    %raw(`(async (raw) => {
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    })(raw)`)
  }
  let promise = %raw(`applyReviewSuggestion(request)`)
  Js.Promise.then_(parseResponse)(promise)
}

type createFeaturePlanRequest = {description: string}
type createFeaturePlanResult = {plan: string}
type applyFeaturePlanRequest = {description: string, plan: string}

@val external createFeaturePlan_raw: string => Js.Promise.t<string> = "createFeaturePlan"

let callCreateFeaturePlan = (description: string): Js.Promise.t<createFeaturePlanResult> => {
  Js.log2("[BAKA UI] createFeaturePlan called", description)
  let parseResponse = (raw: string): Js.Promise.t<createFeaturePlanResult> => {
    let _ = %raw(`console.log("[BAKA UI] createFeaturePlan raw response meta", raw && raw.error ? {error: raw.error} : {planBytes: raw && raw.result && raw.result.plan ? raw.result.plan.length : null})`)
    %raw(`(async (raw) => {
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    })(raw)`)
  }
  let promise = createFeaturePlan_raw(description)
  Js.Promise.then_(parseResponse)(promise)
}

@val external applyFeaturePlan_raw: applyFeaturePlanRequest => Js.Promise.t<string> = "applyFeaturePlan"

let callApplyFeaturePlan = (request: applyFeaturePlanRequest): Js.Promise.t<string> => {
  Js.log2("[BAKA UI] applyFeaturePlan called", {
    "descriptionBytes": request.description->String.length,
    "planBytes": request.plan->String.length,
  })
  let parseResponse = (raw: string): Js.Promise.t<string> => {
    let _ = %raw(`console.log("[BAKA UI] applyFeaturePlan raw response meta", raw && raw.error ? {error: raw.error} : {result: raw && raw.result ? raw.result : null})`)
    %raw(`(async (raw) => {
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    })(raw)`)
  }
  let promise = applyFeaturePlan_raw(request)
  Js.Promise.then_(parseResponse)(promise)
}

@val external commitSelection_raw: string => Js.Promise.t<string> = "commitSelection"

let callCommitSelection = (request: commitSelectionRequest): Js.Promise.t<string> => {
  Js.log2("[BAKA UI] commitSelection called", {
    "messageBytes": request.message->String.length,
    "bodyBytes": request.body->String.length,
    "patchBytes": request.patch->String.length,
  })
  let parseResponse = (raw: string): Js.Promise.t<string> => {
    let _ = %raw(`console.log("[BAKA UI] commitSelection raw response meta", raw && raw.error ? {error: raw.error} : {result: raw && raw.result ? raw.result : null})`)
    %raw(`(async (raw) => {
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    })(raw)`)
  }
  let promise = %raw(`commitSelection(request)`)
  Js.Promise.then_(parseResponse)(promise)
}
