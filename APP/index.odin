#+ feature dynamic-literals

package main

import webview "./webview-odin"
import "base:runtime"
import json "core:encoding/json"
import "core:fmt"
import "core:os"
// import "core:os/os2"
import "core:strings"

// UI assets embedded at compile time via #load
js_content := #load("../UI/bakaui/out.js", string) or_else ""
css_content := #load("../UI/bakaui/out.css", string) or_else ""

w: webview.webview

WebView_Return_Ok :: 0
WebView_Return_Error :: 1

getCurrentGitPatch :: proc() -> string {
	command: [dynamic]string = {"git", "--no-pager", "diff", "HEAD"}

	_, stdout, _, _ := os.process_exec(os.Process_Desc{command = command[:]}, context.allocator)
	defer delete(stdout)

	return strings.clone(string(stdout), context.allocator)
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

// Full-context diff for a single file. `-U999999` makes git include the
// entire file as context, so the resulting patch renders the whole file
// when fed to the diff viewer. Used by the "View full file" modal.
//
// Runs with `working_dir` set to the repo root so the filename (which is
// relative to the repo root, as produced by `git diff HEAD`) resolves
// correctly even when the BAKA binary is launched from a subdirectory
// (e.g. `APP/`).
getFilePatchFromGit :: proc(filename: string) -> string {
	command: [dynamic]string = {"git", "--no-pager", "diff", "HEAD", "-U999999", "--", filename}
	repo_root := getRepoRoot()
	defer delete(repo_root)
	desc := os.Process_Desc {
		working_dir = repo_root,
		command     = command[:],
	}
	_, stdout, _, _ := os.process_exec(desc, context.allocator)
	defer delete(stdout)
	return strings.clone(string(stdout), context.allocator)
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

handle_get_file_patch :: proc "c" (seq: cstring, req: cstring, arg: rawptr) {
	context = runtime.default_context()

	filename, perr := parseFilePatchRequest(string(req))
	if perr != "" {
		webview.ret(
			w,
			seq,
			WebView_Return_Error,
			strings.clone_to_cstring(fmt.tprintf(`{"error": "%s"}`, perr)),
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

main :: proc() {
	defer webview.destroy(w)

	w = webview.create(true, nil)

	// Optional first CLI argument: a directory to use as the working
	// directory. If provided, we chdir into it before any git operations
	// run, so `getRepoRoot` finds the right repo and so the binary can be
	// launched from anywhere. If omitted, the process inherits the CWD
	// it was launched from.
	if len(os.args) > 1 {
		target := os.args[1]
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
	webview.bind(w, "askPi", handle_ask_pi, nil)
	webview.bind(w, "askPiWithDiff", handle_ask_pi_with_diff, nil)

	html := strings.builder_make()
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
            }
        </style>
        <style>`,
	)
	strings.write_string(&html, css_content)

	strings.write_string(&html, `</style>
	    </head>
	    <body id="root"></body>
	</html>`)
	webview.set_html(w, strings.to_cstring(&html))
	webview.run(w)
}

// current diff
// git --no-pager format-patch -1 HEAD --stdout
// not added
// git ls-files --others --exclude-standard
