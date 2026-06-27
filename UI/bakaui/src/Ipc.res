// Bridge to Odin via webview.bind
// Each bound function is exposed as a global async JS function that takes
// a JSON string argument and returns a JSON string promise.

@val external getPatch_raw: string => Js.Promise.t<string> = "getPatch"

let callGetPatch = (): Js.Promise.t<string> => {
  let parseResponse: string => Js.Promise.t<string> =
    %raw(`async raw => {
      console.log("[BAKA UI] getPatch raw response meta", raw && raw.error ? {error: raw.error} : {resultBytes: raw && raw.result ? raw.result.length : null});
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    }`)
  Js.Promise.then_(parseResponse)(getPatch_raw("{}"))
}

@val external getRepoRoot_raw: string => Js.Promise.t<string> = "getRepoRoot"

type repoInfo = {
  workingDirectory: string,
  repoRoot: string,
  isGitRepository: bool,
  canceled: bool,
}

let callGetRepoRoot = (): Js.Promise.t<string> => {
  let parseResponse: string => Js.Promise.t<string> =
    %raw(`async raw => {
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing repository root");
      return raw.result;
    }`)
  Js.Promise.then_(parseResponse)(getRepoRoot_raw("{}"))
}

@val external getRepositoryInfo_raw: string => Js.Promise.t<string> = "getRepositoryInfo"

let callGetRepositoryInfo = (): Js.Promise.t<repoInfo> => {
  let parseResponse: string => Js.Promise.t<repoInfo> =
    %raw(`async raw => {
      if (raw.error) throw new Error(raw.error);
      if (!raw.result) throw new Error("Missing repository info");
      return raw.result;
    }`)
  Js.Promise.then_(parseResponse)(getRepositoryInfo_raw("{}"))
}

@val external chooseWorkingFolder_raw: string => Js.Promise.t<string> = "chooseWorkingFolder"

let callChooseWorkingFolder = (): Js.Promise.t<repoInfo> => {
  let parseResponse: string => Js.Promise.t<repoInfo> =
    %raw(`async raw => {
      if (raw.error) throw new Error(raw.error);
      if (!raw.result) throw new Error("Missing repository info");
      return raw.result;
    }`)
  Js.Promise.then_(parseResponse)(chooseWorkingFolder_raw("{}"))
}

@val external getFilePatch_raw: string => Js.Promise.t<string> = "getFilePatch"

let callGetFilePatch = (path: string): Js.Promise.t<string> => {
  Js.log2("[BAKA UI] getFilePatch called", path)
  let parseResponse: string => Js.Promise.t<string> =
    %raw(`async raw => {
      console.log("[BAKA UI] getFilePatch raw response meta", raw && raw.error ? {error: raw.error} : {resultBytes: raw && raw.result ? raw.result.length : null});
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    }`)
  Js.Promise.then_(parseResponse)(getFilePatch_raw(path))
}

@val external getProjectFiles_raw: string => Js.Promise.t<string> = "getProjectFiles"

let callGetProjectFiles = (): Js.Promise.t<array<string>> => {
  let parseResponse: string => Js.Promise.t<array<string>> =
    %raw(`async raw => {
      console.log("[BAKA UI] getProjectFiles raw response meta", raw && raw.error ? {error: raw.error} : {fileCount: raw && raw.result ? raw.result.length : null});
      if (raw.error) throw new Error(raw.error);
      if (!Array.isArray(raw.result)) throw new Error("Missing project file list");
      return raw.result;
    }`)
  Js.Promise.then_(parseResponse)(getProjectFiles_raw("{}"))
}

type commitSummary = {
  hash: string,
  shortHash: string,
  author: string,
  date: string,
  subject: string,
}

@val external getCommitHistory_raw: string => Js.Promise.t<string> = "getCommitHistory"

let callGetCommitHistory = (): Js.Promise.t<array<commitSummary>> => {
  let parseResponse: string => Js.Promise.t<array<commitSummary>> =
    %raw(`async raw => {
      console.log("[BAKA UI] getCommitHistory raw response meta", raw && raw.error ? {error: raw.error} : {commitCount: raw && raw.result ? raw.result.length : null});
      if (raw.error) throw new Error(raw.error);
      if (!Array.isArray(raw.result)) throw new Error("Missing commit history");
      return raw.result;
    }`)
  Js.Promise.then_(parseResponse)(getCommitHistory_raw("{}"))
}

@val external getCommitPatch_raw: string => Js.Promise.t<string> = "getCommitPatch"

let callGetCommitPatch = (hash: string): Js.Promise.t<string> => {
  Js.log2("[BAKA UI] getCommitPatch called", hash)
  let parseResponse: string => Js.Promise.t<string> =
    %raw(`async raw => {
      console.log("[BAKA UI] getCommitPatch raw response meta", raw && raw.error ? {error: raw.error} : {resultBytes: raw && raw.result ? raw.result.length : null});
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    }`)
  Js.Promise.then_(parseResponse)(getCommitPatch_raw(hash))
}

type askPiRequest = {commentKey: string, text: string}
type askPiBatchRequest = {comments: array<askPiRequest>, model: string}
type askPiWithDiffRequest = {diff: string, comments: array<askPiRequest>, model: string}
type askPiReply = {commentKey: string, reply: string}
type piModelResult = {
  models: array<State.piModel>,
  resolvedDefault: string,
}
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
type fullReviewRequest = {
  kind: string,
  spec: option<string>,
  model: string,
}
type applySuggestionRequest = {
  commentKey: string,
  suggestion: string,
  model: string,
  validationModel: string,
}
type commitSelectionRequest = {
  message: string,
  body: string,
  patch: string,
  branch: string,
}
type branchInfo = {
  currentBranch: string,
  branches: array<string>,
}

// Ask Pi: send all comments as JSON, receive back {replies: [{commentKey, reply}]}
// Odin spawns `pi --mode json @prompt.txt`, parses [REPLY:key] blocks from output.
// The webview library JSON-stringifies all arguments and passes them as a JSON
// array to the C callback, so we spread `comments` as separate arguments.
@val external getPiModels_raw: string => Js.Promise.t<string> = "getPiModels"

let callGetPiModels = (): Js.Promise.t<piModelResult> => {
  let parseResponse: string => Js.Promise.t<piModelResult> =
    %raw(`async raw => {
      if (raw.error) throw new Error(raw.error);
      if (!raw.result || !Array.isArray(raw.result.models)) throw new Error("Invalid Pi model response");
      return raw.result;
    }`)
  Js.Promise.then_(parseResponse)(getPiModels_raw("{}"))
}

@val external askPi_raw: askPiBatchRequest => Js.Promise.t<string> = "askPi"

let callAskPi = (comments: array<askPiRequest>, model: string): Js.Promise.t<array<askPiReply>> => {
  Js.log2("[BAKA UI] askPi called with comment count", comments->Array.length)
  let parseResponse: string => Js.Promise.t<array<askPiReply>> =
    %raw(`async raw => {
      console.log("[BAKA UI] askPi raw response meta", raw && raw.error ? {error: raw.error} : {replyCount: raw && raw.result ? raw.result.length : null});
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    }`)
  let promise = askPi_raw({comments, model})
  Js.log2("[BAKA UI] askPi promise", promise)
  Js.Promise.then_(parseResponse)(promise)
}

@val external askPiWithDiff_raw: askPiWithDiffRequest => Js.Promise.t<string> = "askPiWithDiff"

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
  model: string,
): Js.Promise.t<array<askPiReply>> => {
  Js.log2("[BAKA UI] askPiWithDiff diff bytes", diff->String.length)
  Js.log2("[BAKA UI] askPiWithDiff comment count", comments->Array.length)
  let parseResponse: string => Js.Promise.t<array<askPiReply>> =
    %raw(`async raw => {
      console.log("[BAKA UI] askPiWithDiff raw response meta", raw && raw.error ? {error: raw.error} : {replyCount: raw && raw.result ? raw.result.length : null});
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    }`)
  let promise = askPiWithDiff_raw({diff, comments, model})
  Js.Promise.then_(parseResponse)(promise)
}

@val external startFullReview_raw: fullReviewRequest => Js.Promise.t<string> = "startFullReview"

let callStartFullReview = (kind: fullReviewKind, model: string): Js.Promise.t<fullReviewResult> => {
  let request = {
    kind: switch kind {
    | CodeReview => "code"
    | VulnerabilityCheck => "vulnerability"
    },
    spec: None,
    model,
  }
  Js.log2("[BAKA UI] startFullReview called", request.kind)
  let parseResponse: string => Js.Promise.t<fullReviewResult> =
    %raw(`async raw => {
      console.log("[BAKA UI] startFullReview raw response meta", raw && raw.error ? {error: raw.error} : {summaryBytes: raw && raw.result && raw.result.summary ? raw.result.summary.length : null, findingCount: raw && raw.result && raw.result.findings ? raw.result.findings.length : null});
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    }`)
  Js.Promise.then_(parseResponse)(startFullReview_raw(request))
}

let callCheckAgainstSpec = (spec: string, model: string): Js.Promise.t<fullReviewResult> => {
  let request = {
    kind: "spec",
    spec: Some(spec),
    model,
  }
  Js.log2("[BAKA UI] checkAgainstSpec called; spec bytes", spec->String.length)
  let parseResponse: string => Js.Promise.t<fullReviewResult> =
    %raw(`async raw => {
      console.log("[BAKA UI] checkAgainstSpec raw response meta", raw && raw.error ? {error: raw.error} : {summaryBytes: raw && raw.result && raw.result.summary ? raw.result.summary.length : null, findingCount: raw && raw.result && raw.result.findings ? raw.result.findings.length : null});
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    }`)
  Js.Promise.then_(parseResponse)(startFullReview_raw(request))
}

@val external applyReviewSuggestion_raw: string => Js.Promise.t<string> = "applyReviewSuggestion"

let callApplyReviewSuggestion = (
  request: applySuggestionRequest,
): Js.Promise.t<string> => {
  Js.log2("[BAKA UI] applyReviewSuggestion called", request)
  let parseResponse: string => Js.Promise.t<string> =
    %raw(`async raw => {
      console.log("[BAKA UI] applyReviewSuggestion raw response meta", raw && raw.error ? {error: raw.error} : {result: raw && raw.result ? raw.result : null});
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    }`)
  let promise = %raw(`applyReviewSuggestion(request)`)
  Js.Promise.then_(parseResponse)(promise)
}

type createFeaturePlanRequest = {description: string, model: string}
type createFeaturePlanResult = {plan: string}
type applyFeaturePlanRequest = {description: string, plan: string, model: string}

@val external createFeaturePlan_raw: createFeaturePlanRequest => Js.Promise.t<string> = "createFeaturePlan"

let callCreateFeaturePlan = (description: string, model: string): Js.Promise.t<createFeaturePlanResult> => {
  Js.log2("[BAKA UI] createFeaturePlan called", description)
  let parseResponse: string => Js.Promise.t<createFeaturePlanResult> =
    %raw(`async raw => {
      console.log("[BAKA UI] createFeaturePlan raw response meta", raw && raw.error ? {error: raw.error} : {planBytes: raw && raw.result && raw.result.plan ? raw.result.plan.length : null});
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    }`)
  let promise = createFeaturePlan_raw({description, model})
  Js.Promise.then_(parseResponse)(promise)
}

@val external applyFeaturePlan_raw: applyFeaturePlanRequest => Js.Promise.t<string> = "applyFeaturePlan"

let callApplyFeaturePlan = (request: applyFeaturePlanRequest): Js.Promise.t<string> => {
  Js.log2("[BAKA UI] applyFeaturePlan called", {
    "descriptionBytes": request.description->String.length,
    "planBytes": request.plan->String.length,
  })
  let parseResponse: string => Js.Promise.t<string> =
    %raw(`async raw => {
      console.log("[BAKA UI] applyFeaturePlan raw response meta", raw && raw.error ? {error: raw.error} : {result: raw && raw.result ? raw.result : null});
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      const result = raw.result;
      if (typeof result === "string") return result;
      if (result && typeof result.result === "string") return result.result;
      throw new Error("Invalid apply feature response");
    }`)
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
  let parseResponse: string => Js.Promise.t<string> =
    %raw(`async raw => {
      console.log("[BAKA UI] commitSelection raw response meta", raw && raw.error ? {error: raw.error} : {result: raw && raw.result ? raw.result : null});
      if (raw.error) throw new Error(raw.error);
      if (raw.result === undefined) throw new Error("Missing result field in response");
      return raw.result;
    }`)
  let promise = %raw(`commitSelection(request)`)
  Js.Promise.then_(parseResponse)(promise)
}

@val external getGitBranches_raw: string => Js.Promise.t<string> = "getGitBranches"

let callGetGitBranches = (): Js.Promise.t<branchInfo> => {
  let parseResponse: string => Js.Promise.t<branchInfo> =
    %raw(`async raw => {
      console.log("[BAKA UI] getGitBranches raw response meta", raw && raw.error ? {error: raw.error} : {branchCount: raw && raw.result && raw.result.branches ? raw.result.branches.length : null});
      if (raw.error) throw new Error(raw.error);
      if (!raw.result || !Array.isArray(raw.result.branches)) throw new Error("Missing branch list");
      return raw.result;
    }`)
  Js.Promise.then_(parseResponse)(getGitBranches_raw("{}"))
}
