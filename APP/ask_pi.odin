#+ feature dynamic-literals

package main

import webview "./webview-odin"
import "base:runtime"
import "core:c"
import json "core:encoding/json"
import "core:fmt"
import "core:mem"
//import os "core:os/os2"
import "core:os"
import "core:os/old"
import "core:strings"
import "core:sys/posix"
import "core:thread"

Comment_Entry :: struct {
	comment_key: string `json:"commentKey"`,
	text:        string `json:"text"`,
}

Reply_Entry :: struct {
	comment_key: string `json:"commentKey"`,
	reply:       string `json:"reply"`,
}

AskPi_Result :: struct {
	result: [dynamic]Reply_Entry `json:"result"`,
}

// Request format for the "view full file" modal: the diff is provided by
// the caller (a -U999999 git diff for one file) so the AI gets the whole
// file as context instead of just the changed lines.
AskPiWithDiff_Request :: struct {
	diff:     string `json:"diff"`,
	comments: [dynamic]Comment_Entry `json:"comments"`,
}

// Carries state from the main-thread callback into the worker thread and
// back to the main thread for webview_return. `seq` and `req` are cloned
// because webview may free them once the callback returns. All owned
// strings are freed in `ask_pi_return_main` (runs on the main thread)
// after webview_return has shipped the response — keeping `req` alive
// for the full work + dispatch cycle.
AskPi_Job :: struct {
	seq:      cstring, // owned
	req:      cstring, // owned
	result:   cstring, // owned
	is_error: bool,
}

getGitDiffForFiles :: proc(file_names: [dynamic]string) -> (string, mem.Allocator_Error) {
	if len(file_names) == 0 {
		return "", nil
	}

	command := [dynamic]string{"git", "--no-pager", "diff", "HEAD", "--"}
	for fname in file_names {
		append(&command, fname)
	}
	defer delete(command)

	_, stdout, _, _ := os.process_exec(os.Process_Desc{command = command[:]}, context.allocator)
	defer delete(stdout)

	return strings.clone(string(stdout))
}

extractUniqueFiles :: proc(entries: [dynamic]Comment_Entry) -> [dynamic]string {
	seen := map[string]bool{}
	files := [dynamic]string{}
	defer delete(seen)

	for entry in entries {
		parts := strings.split(entry.comment_key, "|")
		if len(parts) < 1 {
			continue
		}
		file_name := string(parts[0])
		if !seen[file_name] {
			seen[file_name] = true
			append(&files, file_name)
		}
	}

	return files
}

buildPrompt :: proc(
	diff: string,
	entries: [dynamic]Comment_Entry,
) -> (
	string,
	mem.Allocator_Error,
) {
	prompt := strings.builder_make()
	defer strings.builder_destroy(&prompt)

	strings.write_string(
		&prompt,
		`You are an expert code reviewer helping a developer understand their changes.

Below is a git diff of the current working tree, followed by inline review notes
the developer wrote on specific lines. Each note has a file path, line number,
side (added or removed), and the developer's question or observation.

Your job:
- Address each review note individually, referencing its location clearly.
- Explain what the change does and why it matters based on the diff context.
- If the note expresses concern, evaluate whether it's valid and explain your reasoning.
- If the note asks "why", reconstruct the likely intent from the surrounding code.
- Point out real issues: correctness bugs, edge cases, performance problems, or style inconsistencies.
- Suggest concrete improvements when you see them - include code snippets if helpful.
- Be direct but constructive. Don't hedge with "appears" or "seems" - say what is there.
- If the diff doesn't give enough context to answer confidently, say so explicitly and state what's missing.

`,
	)

	if len(diff) > 0 {
		strings.write_string(&prompt, "## Git Diff\n\n```diff\n")
		strings.write_string(&prompt, diff)
		strings.write_string(&prompt, "\n```\n\n")
	}

	strings.write_string(&prompt, "## Review Notes\n\n")
	for i := 0; i < len(entries); i += 1 {
		entry := entries[i]
		parts := strings.split(entry.comment_key, "|")
		file_name := "unknown"
		side := "+"
		line_num := "?"
		if len(parts) >= 1 {file_name = string(parts[0])}
		if len(parts) >= 2 {side = string(parts[1])}
		if len(parts) >= 3 {line_num = string(parts[2])}

		fmt.sbprintf(
			&prompt,
			"%d. **File:** `%s` | **Line:** %s | **Side:** %s\n",
			i + 1,
			file_name,
			line_num,
			side,
		)
		fmt.sbprintf(&prompt, "   **Comment:** %s\n\n", entry.text)
	}

	strings.write_string(
		&prompt,
		`## Reply Format

For each review note, output a block starting with the marker [REPLY:<commentKey>]
followed by your response. The commentKey format is file|side|line where side is
"additions" or "deletions". Use markdown freely.

Example:
[REPLY:path/to/file.txt|additions|42]
Your analysis here...

[REPLY:path/to/other.txt|deletions|15]
Another analysis...
`,
	)

	return strings.clone(strings.to_string(prompt))
}

writeTempFile :: proc(content: string) -> (string, bool) {
	tmp_dir, ok := os.lookup_env_alloc("TMPDIR", context.allocator)
	if !ok || len(tmp_dir) == 0 {
		tmp_dir = "/tmp"
	}
	defer delete(tmp_dir)

	borrowed_path := fmt.tprintf("%s/baka_prompt_%d.txt", tmp_dir, posix.getpid())
	owned_path, perr := strings.clone(borrowed_path)
	if perr != nil {
		return "", false
	}

	if os.write_entire_file(owned_path, transmute([]byte)content) != nil {
		delete(owned_path)
		return "", false
	}

	return owned_path, true
}

parsePiOutput :: proc(output: string) -> [dynamic]Reply_Entry {
	replies := [dynamic]Reply_Entry{}
	lines := strings.split(output, "\n")
	defer delete(lines)

	full_text := strings.builder_make()
	defer strings.builder_destroy(&full_text)

	for line in lines {
		if !strings.contains(line, `"type":"message_update"`) &&
		   !strings.contains(line, `"type": "message_update"`) {
			continue
		}
		if !strings.contains(line, `"delta"`) {
			continue
		}

		delta_start := strings.last_index(line, `"delta":"`)
		if delta_start == -1 {
			continue
		}

		pos := delta_start + len(`"delta":"`)
		rest := line[pos:]

		i := 0
		for i < len(rest) {
			c := rest[i]
			if c == '\\' && i + 1 < len(rest) {
				i += 2
				continue
			}
			if c == '"' {
				delta := rest[:i]
				strings.write_string(&full_text, delta)
				break
			}
			i += 1
		}
	}

	full := strings.to_string(full_text)
	parts := strings.split(full, "[REPLY:")
	defer delete(parts)

	for i := 1; i < len(parts); i += 1 {
		part := string(parts[i])
		bracket_pos := strings.index(part, "]")
		if bracket_pos == -1 {
			continue
		}
		comment_key := strings.trim_space(string(part[:bracket_pos]))
		reply_text := strings.trim_space(string(part[bracket_pos + 1:]))

		append(&replies, Reply_Entry{comment_key = comment_key, reply = reply_text})
	}

	return replies
}

// Pushes a string to the webview's devtools console. Used for debug
// logging from the worker thread.
log_to_webview :: proc(msg: string) {
	js := fmt.tprintf("console.log(%q)", msg)
	webview.eval(w, strings.clone_to_cstring(js) or_else "console.log('log overflow')")
}

// Pure work: parses the request, runs `pi`, and returns the JSON cstring
// to send back. Caller owns the returned cstring.
process_ask_pi :: proc(req_str: string) -> (cstring, bool) {
	entries := [dynamic]Comment_Entry{}
	defer delete(entries)

	if err := json.unmarshal(transmute([]byte)req_str, &entries); err != nil {
		return strings.clone_to_cstring(`{"error": "Failed to parse comments JSON"}`), true
	}

	if len(entries) == 0 {
		result := AskPi_Result {
			result = [dynamic]Reply_Entry{},
		}
		data, merr := json.marshal(result)
		if merr != nil {
			return strings.clone_to_cstring(`{"error": "Failed to marshal empty result"}`), true
		}
		defer delete(data)
		return strings.clone_to_cstring(string(data)), false
	}

	file_names := extractUniqueFiles(entries)
	defer delete(file_names)

	diff, derr := getGitDiffForFiles(file_names)
	if derr != nil {
		return strings.clone_to_cstring(`{"error": "Failed to fetch git diff"}`), true
	}
	defer delete(diff)

	prompt, perr := buildPrompt(diff, entries)
	if perr != nil {
		return strings.clone_to_cstring(`{"error": "Failed to build prompt"}`), true
	}
	defer delete(prompt)

	prompt_path, ok := writeTempFile(prompt)
	if !ok {
		return strings.clone_to_cstring(`{"error": "Failed to write prompt to temp file"}`), true
	}
	defer os.remove(prompt_path)

	borrowed_pi_arg := fmt.tprintf("@%s", prompt_path)
	pi_arg, aerr := strings.clone(borrowed_pi_arg)
	if aerr != nil {
		return strings.clone_to_cstring(`{"error": "Failed to format pi argument"}`), true
	}
	defer delete(pi_arg)

	pi_command := [dynamic]string {
		"pi",
		"--mode",
		"json",
		"--no-session",
		"--no-context-files",
		pi_arg,
	}
	defer delete(pi_command)

	_, stdout, stderr, proc_err := os.process_exec(
		os.Process_Desc{command = pi_command[:]},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)

	if proc_err != nil {
		err_msg := "pi process failed"
		if len(stderr) > 0 {
			err_msg = string(stderr)
		}
		return strings.clone_to_cstring(fmt.tprintf(`{{"error": "%s"}}`, err_msg)), true
	}

	replies := parsePiOutput(string(stdout))
	defer delete(replies)

	result := AskPi_Result {
		result = replies,
	}
	data, merr := json.marshal(result)
	if merr != nil {
		return strings.clone_to_cstring(`{"error": "Failed to marshal replies"}`), true
	}
	defer delete(data)

	return strings.clone_to_cstring(string(data)), false
}

// Runs on a worker thread. Performs the long work, then bounces back to
// the UI thread via webview_dispatch so webview_return is invoked safely
// on the main loop. Self-cleanup: the thread struct is freed automatically.
@(private = "file")
ask_pi_worker :: proc(data: rawptr) {
	context = runtime.default_context()
	job := cast(^AskPi_Job)data

	job.result, job.is_error = process_ask_pi(string(job.req))

	webview.dispatch(w, ask_pi_return_main, job)
}

// Runs on the main thread (via webview_dispatch). Calls webview_return and
// releases everything the job owned.
@(private = "file")
ask_pi_return_main :: proc "c" (wv: webview.webview, arg: rawptr) {
	context = runtime.default_context()
	job := cast(^AskPi_Job)arg
	status: c.int = WebView_Return_Error if job.is_error else WebView_Return_Ok
	webview.ret(wv, job.seq, status, job.result)
	delete(job.seq)
	delete(job.req)
	delete(job.result)
	free(job)
}

handle_ask_pi :: proc "c" (seq: cstring, req: cstring, arg: rawptr) {
	context = runtime.default_context()

	// Clone seq and req because webview may free them after we return.
	seq_owned, seq_err := strings.clone_to_cstring(string(seq))
	if seq_err != nil {
		webview.ret(w, seq, WebView_Return_Error, `{"error": "Failed to clone seq"}`)
		return
	}
	req_owned, req_err := strings.clone_to_cstring(string(req))
	if req_err != nil {
		delete(seq_owned)
		webview.ret(w, seq, WebView_Return_Error, `{"error": "Failed to clone req"}`)
		return
	}

	job := new(AskPi_Job)
	job.seq = seq_owned
	job.req = req_owned
	job.result = nil
	job.is_error = false

	t := thread.create_and_start_with_data(job, ask_pi_worker, self_cleanup = true)
	if t == nil {
		delete(seq_owned)
		delete(req_owned)
		free(job)
		webview.ret(w, seq, WebView_Return_Error, `{"error": "Failed to create thread"}`)
		return
	}
}

// Variant of process_ask_pi that uses a caller-provided diff instead of
// running `git diff` itself. Used by the "view full file" modal so the AI
// gets the whole file as context.
//
// The frontend sends a single JSON-stringified object {diff, comments} as
// its only argument. The webview library wraps that single argument in a
// JSON array, so the C callback receives `["{\"diff\":...,\"comments\":...}"]`.
// We parse the array and then unmarshal the first element as the request.
process_ask_pi_with_diff :: proc(req_str: string) -> (cstring, bool) {
	arr: [dynamic]AskPiWithDiff_Request
	defer delete(arr)

	if err := json.unmarshal(transmute([]byte)req_str, &arr); err != nil {
		return strings.clone_to_cstring(`{"error": "Failed to parse request JSON"}`), true
	}

	if len(arr) == 0 {
		return strings.clone_to_cstring(`{"error": "Missing request body"}`), true
	}

	// Views into arr[0]'s memory — freed by the defer above.
	diff := arr[0].diff
	comments := arr[0].comments

	if len(comments) == 0 {
		result := AskPi_Result {
			result = [dynamic]Reply_Entry{},
		}
		data, merr := json.marshal(result)
		if merr != nil {
			return strings.clone_to_cstring(`{"error": "Failed to marshal empty result"}`), true
		}
		defer delete(data)
		return strings.clone_to_cstring(string(data)), false
	}

	prompt, perr := buildPrompt(diff, comments)
	if perr != nil {
		return strings.clone_to_cstring(`{"error": "Failed to build prompt"}`), true
	}
	defer delete(prompt)

	prompt_path, ok := writeTempFile(prompt)
	if !ok {
		return strings.clone_to_cstring(`{"error": "Failed to write prompt to temp file"}`), true
	}
	defer os.remove(prompt_path)

	borrowed_pi_arg := fmt.tprintf("@%s", prompt_path)
	pi_arg, aerr := strings.clone(borrowed_pi_arg)
	if aerr != nil {
		return strings.clone_to_cstring(`{"error": "Failed to format pi argument"}`), true
	}
	defer delete(pi_arg)

	pi_command := [dynamic]string {
		"pi",
		"--mode",
		"json",
		"--no-session",
		"--no-context-files",
		pi_arg,
	}
	defer delete(pi_command)

	_, stdout, stderr, proc_err := os.process_exec(
		os.Process_Desc{command = pi_command[:]},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)

	if proc_err != nil {
		err_msg := "pi process failed"
		if len(stderr) > 0 {
			err_msg = string(stderr)
		}
		return strings.clone_to_cstring(fmt.tprintf(`{{"error": "%s"}}`, err_msg)), true
	}

	replies := parsePiOutput(string(stdout))
	defer delete(replies)

	result := AskPi_Result {
		result = replies,
	}
	data, merr := json.marshal(result)
	if merr != nil {
		return strings.clone_to_cstring(`{"error": "Failed to marshal replies"}`), true
	}
	defer delete(data)
	return strings.clone_to_cstring(string(data)), false
}

@(private = "file")
ask_pi_with_diff_worker :: proc(data: rawptr) {
	context = runtime.default_context()
	job := cast(^AskPi_Job)data
	job.result, job.is_error = process_ask_pi_with_diff(string(job.req))
	webview.dispatch(w, ask_pi_return_main, job)
}

handle_ask_pi_with_diff :: proc "c" (seq: cstring, req: cstring, arg: rawptr) {
	context = runtime.default_context()

	seq_owned, seq_err := strings.clone_to_cstring(string(seq))
	if seq_err != nil {
		webview.ret(w, seq, WebView_Return_Error, `{"error": "Failed to clone seq"}`)
		return
	}
	req_owned, req_err := strings.clone_to_cstring(string(req))
	if req_err != nil {
		delete(seq_owned)
		webview.ret(w, seq, WebView_Return_Error, `{"error": "Failed to clone req"}`)
		return
	}

	job := new(AskPi_Job)
	job.seq = seq_owned
	job.req = req_owned
	job.result = nil
	job.is_error = false

	t := thread.create_and_start_with_data(job, ask_pi_with_diff_worker, self_cleanup = true)
	if t == nil {
		delete(seq_owned)
		delete(req_owned)
		free(job)
		webview.ret(w, seq, WebView_Return_Error, `{"error": "Failed to create thread"}`)
		return
	}
}
