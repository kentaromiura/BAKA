#+ feature dynamic-literals

package main

import webview "./webview-odin"
import "base:runtime"
import "core:c"
import "core:encoding/base64"
import json "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:os/old"
//import os "core:os/os2"
import "core:strings"
import "core:thread"

// UI assets embedded at compile time via #load
js_content := #load("../UI/bakaui/out.js", string) or_else ""
css_content := #load("../UI/bakaui/out.css", string) or_else ""
ioskeley_mono_font := #load("../UI/bakaui/assets/fonts/IoskeleyMono/IoskeleyMono-Regular.woff2")

w: webview.webview
baka_verbose: bool

WebView_Return_Ok :: 0
WebView_Return_Error :: 1

makeEmptyUntrackedFilePatch :: proc(filename: string) -> string {
	return fmt.tprintf(
		"diff --git a/%s b/%s\nnew file mode 100644\nindex 0000000..e69de29\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1 @@\n+\n",
		filename,
		filename,
		filename,
	)
}

isZeroByteFile :: proc(path: string) -> bool {
	info, err := os.stat(path, context.allocator)
	if err != nil {
		return false
	}
	defer os.file_info_delete(info, context.allocator)
	return info.size == 0
}

getCurrentGitPatch :: proc() -> string {
	repo_root := getRepoWorkingDirectory()
	defer delete(repo_root)

	patch: [dynamic]u8

	tracked_command: [dynamic]string = {"git", "-C", repo_root, "--no-pager", "diff", "HEAD"}
	_, stdout, _, _ := os.process_exec(
		os.Process_Desc{command = tracked_command[:]},
		context.allocator,
	)
	defer delete(tracked_command)
	defer delete(stdout)
	append(&patch, ..stdout[:])

	untracked_command: [dynamic]string = {
		"git",
		"-C",
		repo_root,
		"ls-files",
		"--others",
		"--exclude-standard",
	}
	_, untracked_stdout, _, _ := os.process_exec(
		os.Process_Desc{command = untracked_command[:]},
		context.allocator,
	)
	defer delete(untracked_command)
	defer delete(untracked_stdout)

	untracked_files, err := strings.split(strings.trim(string(untracked_stdout), "\r\n"), "\n")
	defer delete(untracked_files)
	if err == nil {
		for file in untracked_files {
			trimmed_file := strings.trim(file, "\r\n")
			if len(trimmed_file) == 0 {
				continue
			}

			file_path := fmt.tprintf("%s/%s", repo_root, trimmed_file)
			if !os.exists(file_path) {
				continue
			}
			is_empty_file := isZeroByteFile(file_path)

			if is_empty_file {
				append(&patch, u8('\n'))
				append(&patch, makeEmptyUntrackedFilePatch(trimmed_file))
			} else {
				untracked_diff_command := fmt.tprintf(
					"git --no-pager diff --no-index -- /dev/null %q; code=$?; if [ $code -gt 1 ]; then exit $code; fi",
					trimmed_file,
				)
				_, untracked_diff, _, proc_err := os.process_exec(
					os.Process_Desc {
						working_dir = repo_root,
						command = {"sh", "-c", untracked_diff_command[:]},
					},
					context.allocator,
				)
				if proc_err == nil && len(untracked_diff) > 0 {
					append(&patch, u8('\n'))
					append(&patch, ..untracked_diff[:])
				}
				delete(untracked_diff)
			}
		}
	}

	return string(patch[:])
}

// Resolve the absolute path of the git repository's top-level directory
// by running `git rev-parse --show-toplevel` from the current CWD.
// Returns "" if not in a git repo (so the caller can fall back to CWD).
// The returned string is heap-allocated via the default allocator and
// must be `delete`d by the caller.
getRepoRoot :: proc() -> string {
	command: [dynamic]string = {"git", "--no-pager", "rev-parse", "--show-toplevel"}
	_, stdout, _, _ := os.process_exec(os.Process_Desc{command = command[:]}, context.allocator)
	defer delete(stdout)
	trimmed := strings.trim_space(string(stdout))
	trimmed = strings.trim_right(trimmed, "\n")
	return strings.clone(trimmed, context.allocator)
}

// Return the repository root, or an owned "." fallback when the current
// directory is not inside a Git repository. The result must be deleted.
getRepoWorkingDirectory :: proc() -> string {
	repo_root := getRepoRoot()
	if repo_root != "" {
		return repo_root
	}
	delete(repo_root)

	working_dir, err := strings.clone(".", context.allocator)
	if err != nil {
		return ""
	}
	return working_dir
}

// Full-context diff for a single file. `-U999999` makes git include the
// entire file as context, so the resulting patch renders the whole file
// when fed to the diff viewer. Used by the "View full file" modal.
//
// Runs with `working_dir` set to the repo root so the filename (which is
// relative to the repo root, as produced by `git diff HEAD`) resolves
// correctly even when the BAKA binary is launched from a subdirectory
// (e.g. `APP/`).
getFilePatchFromGit :: proc(filename: string) -> string {
	repo_root := getRepoRoot()
	defer delete(repo_root)

	file_path := fmt.tprintf("%s/%s", repo_root, filename)
	is_empty_file := isZeroByteFile(file_path)
	if is_empty_file {
		return makeEmptyUntrackedFilePatch(filename)
	}

	tracked_command: [dynamic]string = {
		"git",
		"--no-pager",
		"diff",
		"HEAD",
		"-U999999",
		"--",
		filename,
	}
	tracked_desc := os.Process_Desc {
		working_dir = repo_root,
		command     = tracked_command[:],
	}
	_, tracked_stdout, _, tracked_err := os.process_exec(tracked_desc, context.allocator)
	defer delete(tracked_command)
	defer delete(tracked_stdout)
	if tracked_err == nil && len(tracked_stdout) > 0 {
		return strings.clone(string(tracked_stdout), context.allocator)
	}

	is_tracked_command: [dynamic]string = {"git", "ls-files", "--error-unmatch", "--", filename}
	is_tracked_desc := os.Process_Desc {
		working_dir = repo_root,
		command     = is_tracked_command[:],
	}
	_, _, _, is_tracked_err := os.process_exec(is_tracked_desc, context.allocator)
	defer delete(is_tracked_command)
	if is_tracked_err != nil {
		return ""
	}

	untracked_diff_command := fmt.tprintf(
		"git --no-pager diff --no-index -U999999 -- /dev/null %q; code=$?; if [ $code -gt 1 ]; then exit $code; fi",
		filename,
	)
	untracked_desc := os.Process_Desc {
		working_dir = repo_root,
		command     = {"sh", "-c", untracked_diff_command[:]},
	}
	_, untracked_stdout, _, untracked_err := os.process_exec(untracked_desc, context.allocator)
	defer delete(untracked_stdout)
	if untracked_err == nil && len(untracked_stdout) > 0 {
		return strings.clone(string(untracked_stdout), context.allocator)
	}

	return ""
}

// Reject absolute paths and `..` path components to keep the IPC from
// being used to read arbitrary files from disk.
isPathSafe :: proc(path: string) -> bool {
	if len(path) == 0 {
		return false
	}
	if path[0] == '/' {
		return false
	}
	parts := strings.split(path, "/")
	defer delete(parts)
	for part in parts {
		if part == ".." {
			return false
		}
	}
	return true
}

// Parses the JSON-array request the webview library produces from JS args,
// e.g. `["src/Foo.res"]` -> the first string element.
parseFilePatchRequest :: proc(req_str: string) -> (string, string) {
	arr: [dynamic]string
	defer delete(arr)
	if err := json.unmarshal(transmute([]byte)req_str, &arr); err != nil {
		return "", "Failed to parse request"
	}
	if len(arr) == 0 {
		return "", "Missing file path"
	}
	return strings.clone(arr[0]), ""
}

Ipc_Response :: struct {
	result: string,
}

Project_Files_Response :: struct {
	result: [dynamic]string,
}

CommitSelection_Request :: struct {
	message: string `json:"message"`,
	body:    string `json:"body"`,
	patch:   string `json:"patch"`,
}

CreateFeaturePlan_Result :: struct {
	plan: string `json:"plan"`,
}

CreateFeaturePlan_Response :: struct {
	result: CreateFeaturePlan_Result `json:"result"`,
}

ApplyFeaturePlan_Request :: struct {
	description: string `json:"description"`,
	plan:        string `json:"plan"`,
}

CreateFeaturePlan_Job :: struct {
	seq:      cstring, // owned
	req:      cstring, // owned
	result:   cstring, // owned
	is_error: bool,
}

feature_error_response :: proc(message: string) -> cstring {
	resp := Ipc_Error_Response {
		error = message,
	}
	data, err := json.marshal(resp)
	if err != nil {
		return strings.clone_to_cstring(`{"error": "feature plan failed"}`)
	}
	defer delete(data)
	return strings.clone_to_cstring(string(data))
}

create_feature_plan :: proc(description: string) -> (string, string) {
	prompt := fmt.tprintf(
		`You are an expert software architect. The user wants to implement the following in the current codebase:

%s

Analyze the project structure, current state, and provide a detailed step-by-step implementation plan. Include:
1. Files to create or modify
2. Key changes needed in each file
3. Architecture decisions
4. Potential risks and edge cases

Use your tools to inspect the codebase before writing the plan. After you finish
inspecting, return the final implementation plan as plain markdown.

Focus on concrete, actionable steps. Keep it practical.
	`,
		description,
	)

	plan_text, pi_err, pi_ok := runPiPrompt(prompt)
	if !pi_ok {
		return "", pi_err
	}
	defer delete(plan_text)

	plan := strip_pi_tool_call_blocks(plan_text)
	defer delete(plan)

	if strings.trim_space(plan) == "" {
		if is_pi_tool_call_only(plan_text) {
			return "", "pi returned a tool call but no final plan"
		}
		return "", "pi returned empty output"
	}

	owned_plan, clone_err := strings.clone(strings.trim_space(plan), context.allocator)
	if clone_err != nil {
		return "", "Failed to clone feature plan"
	}
	return owned_plan, ""
}

buildApplyFeaturePlanPrompt :: proc(
	repo_root, description, plan, current_diff: string,
) -> (
	string,
	mem.Allocator_Error,
) {
	prompt := strings.builder_make()
	defer strings.builder_destroy(&prompt)

	fmt.sbprintf(
		&prompt,
		`You are implementing an accepted feature/bug-fix plan in a local repository.

Use your tools to inspect the repository before writing the patch. Do not edit
files directly with tools. Return one unified git patch only. The patch must
apply cleanly with git apply from the repository root. Do not include commentary
outside [PATCH] markers.

Keep the implementation scoped to the accepted plan. Preserve existing behavior
outside the requested change. Include new files in the patch when needed.

Repo root: %s

Original user request:
%s

Accepted implementation plan:
%s

Current working-tree diff:
[DIFF]
%s
[END_DIFF]

[PATCH]
diff --git ...
[END_PATCH]
`,
		repo_root,
		description,
		plan,
		current_diff,
	)

	return strings.clone(strings.to_string(prompt))
}

apply_feature_plan :: proc(description, plan: string) -> (string, string) {
	if strings.trim_space(description) == "" {
		return "", "Feature description is required"
	}
	if strings.trim_space(plan) == "" {
		return "", "Feature plan is required"
	}

	repo_root := getRepoWorkingDirectory()
	defer delete(repo_root)

	current_diff := getCurrentGitPatch()
	defer delete(current_diff)

	prompt, perr := buildApplyFeaturePlanPrompt(repo_root, description, plan, current_diff)
	if perr != nil {
		return "", "Failed to build apply plan prompt"
	}
	pi_text, pi_err, pi_ok := runPiPrompt(prompt)
	delete(prompt)
	if !pi_ok {
		return "", pi_err
	}
	defer delete(pi_text)

	patch := extractPatchFromPiText(pi_text)
	if len(patch) == 0 {
		return "", "Pi did not return a patch"
	}
	defer delete(patch)
	debug_log(
		fmt.tprintf(
			"pi returned feature-plan patch with %d byte(s); preview: %s",
			len(patch),
			preview(patch),
		),
	)

	patch_path, ok := writeTempFile(patch)
	if !ok {
		return "", "Failed to write patch to temp file"
	}
	defer os.remove(patch_path)

	if ok, apply_msg := applyPatchFile(repo_root, patch_path); !ok {
		defer delete(apply_msg)
		return "", apply_msg
	}

	result := fmt.tprintf("Applied feature plan patch.\n\nPatch size: %d byte(s).", len(patch))
	return strings.clone(result, context.allocator), ""
}

is_pi_tool_call_only :: proc(text: string) -> bool {
	trimmed := strings.trim_space(text)
	return(
		strings.has_prefix(trimmed, "<pi_tool_call>") &&
		strings.contains(trimmed, "</pi_tool_call>") &&
		strings.last_index(trimmed, "</pi_tool_call>") + len("</pi_tool_call>") == len(trimmed) \
	)
}

strip_pi_tool_call_blocks :: proc(text: string) -> string {
	out := strings.builder_make()
	defer strings.builder_destroy(&out)

	cursor := 0
	for cursor < len(text) {
		start_rel := strings.index(text[cursor:], "<pi_tool_call>")
		if start_rel == -1 {
			strings.write_string(&out, text[cursor:])
			break
		}

		start := cursor + start_rel
		strings.write_string(&out, text[cursor:start])

		end_rel := strings.index(text[start:], "</pi_tool_call>")
		if end_rel == -1 {
			strings.write_string(&out, text[start:])
			break
		}

		cursor = start + end_rel + len("</pi_tool_call>")
	}

	cleaned := strings.trim_space(strings.to_string(out))
	owned, err := strings.clone(cleaned, context.allocator)
	if err != nil {
		return ""
	}
	return owned
}

strip_json_hostile_controls :: proc(text: string) -> string {
	out := strings.builder_make()
	defer strings.builder_destroy(&out)

	for i := 0; i < len(text); i += 1 {
		b := text[i]
		if b == '\n' || b == '\r' || b == '\t' || (b >= 0x20 && b != 0x7f) {
			strings.write_byte(&out, b)
		}
	}

	owned, err := strings.clone(strings.to_string(out), context.allocator)
	if err != nil {
		return ""
	}
	return owned
}

process_create_feature_plan :: proc(req_str: string) -> (cstring, bool) {
	description, parse_err := parseFilePatchRequest(req_str)
	if parse_err != "" {
		return feature_error_response(parse_err), true
	}
	defer delete(description)

	cleaned := strings.trim_space(description)
	if cleaned == "" {
		return feature_error_response("Feature description is required"), true
	}

	plan, err := create_feature_plan(cleaned)
	if err != "" {
		return feature_error_response(fmt.tprintf("Failed: %s", err)), true
	}
	defer delete(plan)
	safe_plan := strip_json_hostile_controls(plan)
	defer delete(safe_plan)

	resp := CreateFeaturePlan_Response {
		result = CreateFeaturePlan_Result{plan = safe_plan},
	}
	data, merr := json.marshal(resp)
	if merr != nil {
		return feature_error_response("marshal failed"), true
	}
	defer delete(data)
	debug_log(
		fmt.tprintf(
			"createFeaturePlan returning response=%d byte(s), plan=%d byte(s)",
			len(data),
			len(safe_plan),
		),
	)

	return strings.clone_to_cstring(string(data)), false
}

process_apply_feature_plan :: proc(req_str: string) -> (cstring, bool) {
	arr: [dynamic]ApplyFeaturePlan_Request
	defer delete(arr)

	if err := json.unmarshal(transmute([]byte)req_str, &arr); err != nil {
		return feature_error_response("Failed to parse apply feature plan request"), true
	}
	if len(arr) == 0 {
		return feature_error_response("Missing apply feature plan request"), true
	}

	result, err := apply_feature_plan(arr[0].description, arr[0].plan)
	if err != "" {
		return feature_error_response(fmt.tprintf("Failed: %s", err)), true
	}
	defer delete(result)

	resp := Ipc_Response {
		result = result,
	}
	data, merr := json.marshal(resp)
	if merr != nil {
		return feature_error_response("marshal failed"), true
	}
	defer delete(data)
	debug_log(fmt.tprintf("applyFeaturePlan returning response=%d byte(s)", len(data)))
	return strings.clone_to_cstring(string(data)), false
}

@(private = "file")
create_feature_plan_worker :: proc(data: rawptr) {
	context = runtime.default_context()
	job := cast(^CreateFeaturePlan_Job)data
	job.result, job.is_error = process_create_feature_plan(string(job.req))
	webview.dispatch(w, create_feature_plan_return_main, job)
}

@(private = "file")
apply_feature_plan_worker :: proc(data: rawptr) {
	context = runtime.default_context()
	job := cast(^CreateFeaturePlan_Job)data
	job.result, job.is_error = process_apply_feature_plan(string(job.req))
	webview.dispatch(w, create_feature_plan_return_main, job)
}

@(private = "file")
create_feature_plan_return_main :: proc "c" (wv: webview.webview, arg: rawptr) {
	context = runtime.default_context()
	job := cast(^CreateFeaturePlan_Job)arg
	status: c.int = WebView_Return_Error if job.is_error else WebView_Return_Ok
	debug_log(
		fmt.tprintf(
			"returning feature plan IPC response; is_error=%v, result=%d byte(s)",
			job.is_error,
			len(string(job.result)),
		),
	)
	webview.ret(wv, job.seq, status, job.result)
	delete(job.seq)
	delete(job.req)
	delete(job.result)
	free(job)
}

handle_create_feature_plan :: proc "c" (seq: cstring, req: cstring, arg: rawptr) {
	context = runtime.default_context()

	seq_owned, seq_err := strings.clone_to_cstring(string(seq))
	if seq_err != nil {
		webview.ret(w, seq, WebView_Return_Error, feature_error_response("Failed to clone seq"))
		return
	}
	req_owned, req_err := strings.clone_to_cstring(string(req))
	if req_err != nil {
		delete(seq_owned)
		webview.ret(w, seq, WebView_Return_Error, feature_error_response("Failed to clone req"))
		return
	}

	job := new(CreateFeaturePlan_Job)
	job.seq = seq_owned
	job.req = req_owned
	job.result = nil
	job.is_error = false

	t := thread.create_and_start_with_data(job, create_feature_plan_worker, self_cleanup = true)
	if t == nil {
		delete(seq_owned)
		delete(req_owned)
		free(job)
		webview.ret(
			w,
			seq,
			WebView_Return_Error,
			feature_error_response("Failed to create thread"),
		)
		return
	}
}

handle_apply_feature_plan :: proc "c" (seq: cstring, req: cstring, arg: rawptr) {
	context = runtime.default_context()

	seq_owned, seq_err := strings.clone_to_cstring(string(seq))
	if seq_err != nil {
		webview.ret(w, seq, WebView_Return_Error, feature_error_response("Failed to clone seq"))
		return
	}
	req_owned, req_err := strings.clone_to_cstring(string(req))
	if req_err != nil {
		delete(seq_owned)
		webview.ret(w, seq, WebView_Return_Error, feature_error_response("Failed to clone req"))
		return
	}

	job := new(CreateFeaturePlan_Job)
	job.seq = seq_owned
	job.req = req_owned
	job.result = nil
	job.is_error = false

	t := thread.create_and_start_with_data(job, apply_feature_plan_worker, self_cleanup = true)
	if t == nil {
		delete(seq_owned)
		delete(req_owned)
		free(job)
		webview.ret(
			w,
			seq,
			WebView_Return_Error,
			feature_error_response("Failed to create thread"),
		)
		return
	}
}

commit_error_response :: proc(message: string) -> cstring {
	resp := Ipc_Error_Response {
		error = message,
	}
	data, err := json.marshal(resp)
	if err != nil {
		return strings.clone_to_cstring(`{"error": "commit failed"}`)
	}
	defer delete(data)
	return strings.clone_to_cstring(string(data))
}

parseCommitSelectionRequest :: proc(req_str: string) -> (CommitSelection_Request, string) {
	arr: [dynamic]CommitSelection_Request
	defer delete(arr)
	if err := json.unmarshal(transmute([]byte)req_str, &arr); err != nil {
		return {}, "Failed to parse commit request"
	}
	if len(arr) == 0 {
		return {}, "Missing commit request"
	}
	request := CommitSelection_Request {
		message = strings.clone(arr[0].message, context.allocator),
		body    = strings.clone(arr[0].body, context.allocator),
		patch   = strings.clone(arr[0].patch, context.allocator),
	}
	return request, ""
}

run_git_command :: proc(repo_root: string, command: []string) -> (string, string, bool) {
	desc := os.Process_Desc {
		working_dir = repo_root,
		command     = command,
	}
	_, stdout, stderr, proc_err := os.process_exec(desc, context.allocator)
	defer delete(stdout)
	defer delete(stderr)
	if proc_err != nil {
		message := strings.trim_space(string(stderr))
		if message == "" {
			message = strings.trim_space(string(stdout))
		}
		return strings.clone(string(stdout), context.allocator),
			strings.clone(message, context.allocator),
			false
	}
	return strings.clone(string(stdout), context.allocator),
		strings.clone(string(stderr), context.allocator),
		true
}

commitSelectedPatch :: proc(request: CommitSelection_Request) -> (string, string) {
	message := strings.trim_space(request.message)
	body := strings.trim_space(request.body)
	patch := strings.trim_space(request.patch)
	if message == "" {
		return "", "Commit message is required"
	}
	if patch == "" {
		return "", "No selected changes to commit"
	}

	repo_root := getRepoRoot()
	defer delete(repo_root)
	if repo_root == "" {
		return "", "Not inside a git repository"
	}

	patch_path := "/tmp/baka-commit-selection.patch"
	if err := os.write_entire_file(patch_path, request.patch); err != nil {
		return "", "Failed to write selected patch"
	}
	defer os.remove(patch_path)

	fmt.eprintln("[BAKA commit] resetting index to HEAD")
	reset_cmd: [dynamic]string = {"git", "reset", "--mixed", "HEAD"}
	_, reset_err, reset_ok := run_git_command(repo_root, reset_cmd[:])
	defer delete(reset_cmd)
	defer delete(reset_err)
	if !reset_ok {
		return "", fmt.tprintf("Failed to reset index: %s", reset_err)
	}

	fmt.eprintln("[BAKA commit] applying selected patch to index")
	apply_cmd: [dynamic]string = {"git", "apply", "--cached", "--whitespace=nowarn", patch_path}
	_, apply_err, apply_ok := run_git_command(repo_root, apply_cmd[:])
	defer delete(apply_cmd)
	defer delete(apply_err)
	if !apply_ok {
		return "", fmt.tprintf("Failed to apply selected patch: %s", apply_err)
	}

	commit_cmd: [dynamic]string = {"git", "commit", "-m", message}
	if body != "" {
		append(&commit_cmd, "-m")
		append(&commit_cmd, body)
	}
	fmt.eprintln("[BAKA commit] creating commit")
	commit_stdout, commit_err, commit_ok := run_git_command(repo_root, commit_cmd[:])
	defer delete(commit_cmd)
	defer delete(commit_stdout)
	defer delete(commit_err)
	if !commit_ok {
		return "", fmt.tprintf("Failed to create commit: %s", commit_err)
	}

	result := strings.trim_space(commit_stdout)
	if result == "" {
		result = "Commit created."
	}
	return strings.clone(result, context.allocator), ""
}

handle_get_patch :: proc "c" (seq: cstring, req: cstring, arg: rawptr) {
	context = runtime.default_context()
	patch := getCurrentGitPatch()
	resp := Ipc_Response {
		result = patch,
	}
	data, err := json.marshal(resp)
	if err != nil {
		webview.ret(w, seq, WebView_Return_Error, "{\"error\": \"marshal failed\"}")
		return
	}
	defer delete(data)
	result_string := string(data)
	c_result := strings.clone_to_cstring(result_string)
	webview.ret(w, seq, WebView_Return_Ok, c_result)
}

handle_commit_selection :: proc "c" (seq: cstring, req: cstring, arg: rawptr) {
	context = runtime.default_context()

	request, perr := parseCommitSelectionRequest(string(req))
	if perr != "" {
		webview.ret(w, seq, WebView_Return_Error, commit_error_response(perr))
		return
	}
	defer delete(request.message)
	defer delete(request.body)
	defer delete(request.patch)

	result, cerr := commitSelectedPatch(request)
	if cerr != "" {
		webview.ret(w, seq, WebView_Return_Error, commit_error_response(cerr))
		return
	}
	defer delete(result)

	resp := Ipc_Response {
		result = result,
	}
	data, err := json.marshal(resp)
	if err != nil {
		webview.ret(w, seq, WebView_Return_Error, commit_error_response("marshal failed"))
		return
	}
	defer delete(data)
	webview.ret(w, seq, WebView_Return_Ok, strings.clone_to_cstring(string(data)))
}

handle_get_file_patch :: proc "c" (seq: cstring, req: cstring, arg: rawptr) {
	context = runtime.default_context()

	filename, perr := parseFilePatchRequest(string(req))
	if perr != "" {
		webview.ret(
			w,
			seq,
			WebView_Return_Error,
			strings.clone_to_cstring(fmt.tprintf(`{{"error": "%s"}}`, perr)),
		)
		return
	}
	defer delete(filename)

	if !isPathSafe(filename) {
		webview.ret(
			w,
			seq,
			WebView_Return_Error,
			strings.clone_to_cstring(`{"error": "Invalid file path"}`),
		)
		return
	}

	patch := getFilePatchFromGit(filename)
	defer delete(patch)
	resp := Ipc_Response {
		result = patch,
	}
	data, err := json.marshal(resp)
	if err != nil {
		webview.ret(
			w,
			seq,
			WebView_Return_Error,
			strings.clone_to_cstring(`{"error": "marshal failed"}`),
		)
		return
	}
	defer delete(data)
	result_string := string(data)
	c_result := strings.clone_to_cstring(result_string)
	webview.ret(w, seq, WebView_Return_Ok, c_result)
}

handle_get_project_files :: proc "c" (seq: cstring, req: cstring, arg: rawptr) {
	context = runtime.default_context()

	repo_root := getRepoWorkingDirectory()
	defer delete(repo_root)

	command: [dynamic]string = {
		"git",
		"ls-files",
		"--cached",
		"--others",
		"--exclude-standard",
	}
	_, stdout, _, process_err := os.process_exec(
		os.Process_Desc {
			working_dir = repo_root,
			command = command[:],
		},
		context.allocator,
	)
	defer delete(command)
	defer delete(stdout)
	if process_err != nil {
		webview.ret(
			w,
			seq,
			WebView_Return_Error,
			strings.clone_to_cstring(`{"error": "Failed to list project files"}`),
		)
		return
	}

	files := [dynamic]string{}
	defer deleteStringArray(files)
	lines := strings.split(strings.trim(string(stdout), "\r\n"), "\n")
	defer delete(lines)
	for line in lines {
		path := strings.trim(line, "\r\n")
		if len(path) == 0 || !isPathSafe(path) {
			continue
		}
		full_path := fmt.aprintf("%s/%s", repo_root, path)
		exists := os.exists(full_path)
		delete(full_path)
		if !exists {
			continue
		}
		owned, clone_err := strings.clone(path, context.allocator)
		if clone_err != nil {
			webview.ret(
				w,
				seq,
				WebView_Return_Error,
				strings.clone_to_cstring(`{"error": "Failed to collect project files"}`),
			)
			return
		}
		append(&files, owned)
	}

	resp := Project_Files_Response {
		result = files,
	}
	data, err := json.marshal(resp)
	if err != nil {
		webview.ret(
			w,
			seq,
			WebView_Return_Error,
			strings.clone_to_cstring(`{"error": "marshal failed"}`),
		)
		return
	}
	defer delete(data)
	webview.ret(w, seq, WebView_Return_Ok, strings.clone_to_cstring(string(data)))
}

handle_get_watcher_events :: proc "c" (seq: cstring, req: cstring, arg: rawptr) {
	context = runtime.default_context()

	messages := read_watcher_events()
	resp := Webview_Events_Response {
		result = messages,
	}
	data, err := json.marshal(resp)
	if err != nil {
		webview.ret(w, seq, WebView_Return_Error, `{"error": "marshal failed"}`)
		return
	}
	defer delete(data)

	result_string := string(data)
	c_result := strings.clone_to_cstring(result_string)
	webview.ret(w, seq, WebView_Return_Ok, c_result)
}

main :: proc() {
	defer webview.destroy(w)

	w = webview.create(true, nil)

	// Optional args: --verbose/-v enables diagnostic logs; the first
	// non-flag arg is a directory to use as the working directory.
	target := ""
	for arg in os.args[1:] {
		if arg == "--verbose" || arg == "-v" {
			baka_verbose = true
			continue
		}
		if target == "" {
			target = arg
		}
	}
	if target != "" {
		if err := os.set_working_directory(target); err != nil {
			fmt.eprintln("[BAKA] Failed to chdir to", target, ":", err)
			os.exit(1)
		}
		cwd, werr := os.get_working_directory(context.temp_allocator)
		if werr != nil {
			fmt.eprintln("[BAKA] Failed to get working directory:", werr)
			os.exit(1)
		}
		fmt.eprintln("[BAKA] Using working directory:", cwd)
	}

	webview.set_title(w, "BAKA")
	webview.set_size(w, 960, 720, .None)
	webview.bind(w, "getPatch", handle_get_patch, nil)
	webview.bind(w, "getFilePatch", handle_get_file_patch, nil)
	webview.bind(w, "getProjectFiles", handle_get_project_files, nil)
	webview.bind(w, "getWatcherEvents", handle_get_watcher_events, nil)
	webview.bind(w, "askPi", handle_ask_pi, nil)
	webview.bind(w, "askPiWithDiff", handle_ask_pi_with_diff, nil)
	webview.bind(w, "startFullReview", handle_start_full_review, nil)
	webview.bind(w, "applyReviewSuggestion", handle_apply_review_suggestion, nil)
	webview.bind(w, "commitSelection", handle_commit_selection, nil)
	webview.bind(w, "createFeaturePlan", handle_create_feature_plan, nil)
	webview.bind(w, "applyFeaturePlan", handle_apply_feature_plan, nil)

	html := strings.builder_make()
	ioskeley_mono_base64 := base64.encode(ioskeley_mono_font)
	defer delete(ioskeley_mono_base64)

	strings.write_string(&html, `<html>
    <head>
        <script type="text/javascript">`)
	strings.write_string(&html, js_content)
	strings.write_string(
		&html,
		`</script>
        <style>
            html, body {
                height: 100%;
                border: 0;
                padding: 0;
                margin: 0;
                background-image: url("data:image/png;base64,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");
                background-repeat: repeat;
            }
        </style>
        <style>`,
	)
	strings.write_string(
		&html,
		`/* Ioskeley Mono v2.0.0 — SIL Open Font License 1.1 */
@font-face{font-family:"Ioskeley Mono";src:url(data:font/woff2;base64,`,
	)
	strings.write_string(&html, ioskeley_mono_base64)
	strings.write_string(
		&html,
		`) format("woff2");font-style:normal;font-weight:400;font-display:swap;}
`,
	)
	strings.write_string(&html, css_content)

	fmt.sbprintf(
		&html,
		"\n</style>\n<script>window.__BAKA_VERBOSE__ = %v;</script>\n",
		baka_verbose,
	)
	strings.write_string(
		&html,
		`<script type="text/javascript">
(function() {
  if (window.__bakaRepoChangeNoticeInstalled) return;
  window.__bakaRepoChangeNoticeInstalled = true;
  window.__bakaDiffReloadRequestCount = window.__bakaDiffReloadRequestCount || 0;
  var notice = null;
  var logPanel = null;

  function ensureLogPanel() {
    if (logPanel) return;
    logPanel = document.createElement('div');
    logPanel.style.cssText = 'position:fixed;left:16px;bottom:16px;z-index:2147483647;width:420px;max-height:180px;overflow:hidden;padding:10px 12px;border:1px solid #d0d7de;border-radius:8px;background:rgba(255,255,255,0.94);color:#24292f;font-family:"Ioskeley Mono",ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px;line-height:1.35;box-shadow:0 8px 24px rgba(0,0,0,0.18);';
    document.body.appendChild(logPanel);
  }

  function addLogLine(message) {
    if (!document.body) return;
    ensureLogPanel();
    const line = document.createElement('div');
    line.textContent = message;
    line.style.transition = 'opacity 250ms ease, transform 250ms ease';
    logPanel.appendChild(line);
    window.setTimeout(function() {
      line.style.opacity = '0';
      line.style.transform = 'translateY(4px)';
      window.setTimeout(function() {
        if (line.parentNode) {
          line.parentNode.removeChild(line);
        }
        if (logPanel && logPanel.childNodes.length === 0) {
          if (logPanel.parentNode) {
            logPanel.parentNode.removeChild(logPanel);
          }
          logPanel = null;
        }
      }, 260);
    }, 2000);
  }

  window.__bakaAddLog = function(message) {
    if (window.__BAKA_VERBOSE__) console.log('[BAKA watcher]', message);
    addLogLine(message);
  };

  function hideNotice() {
    if (notice) {
      if (notice.parentNode) {
        notice.parentNode.removeChild(notice);
      }
      notice = null;
    }
  }

  function requestDiffReload() {
    if (window.__BAKA_VERBOSE__) console.log('[BAKA watcher] Reload diff requested');
    try {
      window.__bakaDiffReloadRequestCount = (window.__bakaDiffReloadRequestCount || 0) + 1;
    } catch (err) {
      if (window.__BAKA_VERBOSE__) console.error('[BAKA watcher] Failed to request diff reload', err);
    }
  }

  function reloadDiffFromWatcher() {
    requestDiffReload();
    hideNotice();
  }

  window.__bakaShowRepoChangeNotice = function(detail) {
    detail = detail || {};
    if (!document.body) return;
    if (!notice) {
      notice = document.createElement('button');
      notice.type = 'button';
      notice.textContent = 'See latest changes';
      notice.style.cssText = 'position:fixed;top:12px;left:50%;transform:translateX(-50%);z-index:2147483647;padding:8px 12px;border:1px solid #0969da;border-radius:999px;background:#0969da;color:#ffffff;font-family:"Ioskeley Mono",ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:13px;font-weight:600;box-shadow:0 8px 24px rgba(0,0,0,0.18);cursor:pointer;';
      notice.onclick = function() {
        reloadDiffFromWatcher();
      };
      document.body.appendChild(notice);
    }
  };

  window.addEventListener('baka-watcher-log', function(event) {
    var detail = event.detail || {};
    window.__bakaAddLog(detail.message || '');
  });
  window.addEventListener('baka-repo-changed', function(event) {
    window.__bakaShowRepoChangeNotice(event.detail);
  });
  setInterval(function() {
    if (!window.getWatcherEvents) return;
    window.getWatcherEvents('{}').then(function(raw) {
      var messages = raw && raw.result ? raw.result : [];
      messages.forEach(function(message) {
        if (message.indexOf('Repository files changed') >= 0) {
          window.__bakaShowRepoChangeNotice({message: message});
        } else {
          window.__bakaAddLog(message);
        }
      });
    }).catch(function(err) {
      window.__bakaAddLog('Watcher poll failed: ' + String(err));
    });
  }, 500);
})();
</script>
	</head>
	<body id="root"></body>
</html>`,
	)
	webview.set_html(w, strings.to_cstring(&html))
	start_repo_watcher()
	webview.run(w)
}

// current diff
// git --no-pager format-patch -1 HEAD --stdout
// not added
// git ls-files --others --exclude-standard
