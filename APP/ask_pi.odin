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

Review_Finding :: struct {
	comment_key: string `json:"commentKey"`,
	summary:     string `json:"summary"`,
	body:        string `json:"body"`,
	severity:    string `json:"severity"`,
	actionable:  bool   `json:"actionable"`,
	suggestion:  string `json:"suggestion"`,
}

FullReview_Result_Data :: struct {
	summary:  string                   `json:"summary"`,
	findings: [dynamic]Review_Finding `json:"findings"`,
}

FullReview_Result :: struct {
	result: FullReview_Result_Data `json:"result"`,
}

ApplySuggestion_Request :: struct {
	comment_key: string `json:"commentKey"`,
	suggestion:  string `json:"suggestion"`,
}

ApplySuggestion_Result :: struct {
	result: string `json:"result"`,
}

Ipc_Error_Response :: struct {
	error: string `json:"error"`,
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

PI_REVIEW_BATCH_CHAR_LIMIT :: 24000

debug_log :: proc(msg: string) {
	fmt.eprintln("[BAKA pi]", msg)
}

preview :: proc(value: string, limit := 280) -> string {
	if len(value) <= limit {
		return value
	}
	return fmt.tprintf("%s... <truncated %d chars>", value[:limit], len(value) - limit)
}

make_error_cstring :: proc(msg: string) -> cstring {
	debug_log(fmt.tprintf("returning error to UI: %s", msg))
	resp := Ipc_Error_Response{error = msg}
	data, err := json.marshal(resp)
	if err != nil {
		return strings.clone_to_cstring(`{"error": "Failed to marshal error"}`)
	}
	defer delete(data)
	return strings.clone_to_cstring(string(data))
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

appendUniqueOwnedFile :: proc(files: ^[dynamic]string, file_name: string) -> bool {
	trimmed := strings.trim_space(file_name)
	if len(trimmed) == 0 {
		return true
	}
	for existing in files {
		if existing == trimmed {
			return true
		}
	}
	owned, err := strings.clone(trimmed, context.allocator)
	if err != nil {
		return false
	}
	append(files, owned)
	return true
}

deleteStringArray :: proc(files: [dynamic]string) {
	for file in files {
		delete(file)
	}
	delete(files)
}

getReviewFileNames :: proc() -> (files: [dynamic]string, ok: bool) {
	files = [dynamic]string{}
	debug_log("collecting review file names from git")

	tracked_command: [dynamic]string = {"git", "--no-pager", "diff", "--name-only", "HEAD"}
	_, tracked_stdout, _, tracked_err := os.process_exec(
		os.Process_Desc{command = tracked_command[:]},
		context.allocator,
	)
	defer delete(tracked_command)
	defer delete(tracked_stdout)
	if tracked_err != nil {
		debug_log("git diff --name-only failed")
		return files, false
	}

	tracked_lines := strings.split(strings.trim(string(tracked_stdout), "\r\n"), "\n")
	defer delete(tracked_lines)
	for line in tracked_lines {
		if !appendUniqueOwnedFile(&files, line) {
			return files, false
		}
	}

	untracked_command: [dynamic]string = {
		"git",
		"ls-files",
		"--others",
		"--exclude-standard",
	}
	_, untracked_stdout, _, untracked_err := os.process_exec(
		os.Process_Desc{command = untracked_command[:]},
		context.allocator,
	)
	defer delete(untracked_command)
	defer delete(untracked_stdout)
	if untracked_err != nil {
		debug_log("git ls-files --others failed")
		return files, false
	}

	untracked_lines := strings.split(strings.trim(string(untracked_stdout), "\r\n"), "\n")
	defer delete(untracked_lines)
	for line in untracked_lines {
		if !appendUniqueOwnedFile(&files, line) {
			return files, false
		}
	}

	debug_log(fmt.tprintf("collected %d review file(s)", len(files)))
	return files, true
}

getReviewDiffForFile :: proc(repo_root, filename: string) -> string {
	debug_log(fmt.tprintf("collecting diff for %s", filename))
	file_path := fmt.tprintf("%s/%s", repo_root, filename)
	if isZeroByteFile(file_path) {
		debug_log(fmt.tprintf("file %s is zero-byte; generating empty-file patch", filename))
		return makeEmptyUntrackedFilePatch(filename)
	}

	tracked_command: [dynamic]string = {
		"git",
		"--no-pager",
		"diff",
		"HEAD",
		"--",
		filename,
	}
	_, tracked_stdout, _, tracked_err := os.process_exec(
		os.Process_Desc{working_dir = repo_root, command = tracked_command[:]},
		context.allocator,
	)
	defer delete(tracked_command)
	defer delete(tracked_stdout)
	if tracked_err == nil && len(tracked_stdout) > 0 {
		debug_log(fmt.tprintf("tracked diff for %s has %d byte(s)", filename, len(tracked_stdout)))
		return strings.clone(string(tracked_stdout), context.allocator)
	}

	is_tracked_command: [dynamic]string = {"git", "ls-files", "--error-unmatch", "--", filename}
	_, _, _, is_tracked_err := os.process_exec(
		os.Process_Desc{working_dir = repo_root, command = is_tracked_command[:]},
		context.allocator,
	)
	defer delete(is_tracked_command)
	if is_tracked_err == nil {
		debug_log(fmt.tprintf("%s is tracked but has no diff output", filename))
		return ""
	}

	untracked_diff_command := fmt.tprintf(
		"git --no-pager diff --no-index -- /dev/null %q; code=$?; if [ $code -gt 1 ]; then exit $code; fi",
		filename,
	)
	_, untracked_stdout, _, untracked_err := os.process_exec(
		os.Process_Desc {
			working_dir = repo_root,
			command     = {"sh", "-c", untracked_diff_command[:]},
		},
		context.allocator,
	)
	defer delete(untracked_stdout)
	if untracked_err == nil && len(untracked_stdout) > 0 {
		debug_log(fmt.tprintf("untracked diff for %s has %d byte(s)", filename, len(untracked_stdout)))
		return strings.clone(string(untracked_stdout), context.allocator)
	}

	debug_log(fmt.tprintf("no diff available for %s", filename))
	return ""
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

buildDiffFileList :: proc(diff: string) -> string {
	lines := strings.split(diff, "\n")
	defer delete(lines)

	files := strings.builder_make()
	defer strings.builder_destroy(&files)
	seen := map[string]bool{}
	defer delete(seen)

	for line in lines {
		if !strings.has_prefix(line, "diff --git ") {
			continue
		}

		path := ""
		b_path_pos := strings.index(line, " b/")
		if b_path_pos != -1 {
			path = string(line[b_path_pos + len(" b/"):])
		} else {
			parts := strings.split(line, " ")
			if len(parts) >= 4 {
				path = string(parts[3])
				if strings.has_prefix(path, "b/") {
					path = string(path[2:])
				}
			}
			delete(parts)
		}

		path = strings.trim_space(path)
		if len(path) == 0 || seen[path] {
			continue
		}
		seen[path] = true
		fmt.sbprintf(&files, "- %s\n", path)
	}

	file_list := strings.to_string(files)
	if len(file_list) == 0 {
		return strings.clone("- (no file headers found)\n", context.allocator) or_else "- (no file headers found)\n"
	}
	return strings.clone(file_list, context.allocator) or_else "- (failed to list files)\n"
}

buildFullReviewPrompt :: proc(diff: string, batch_index, batch_count: int) -> (string, mem.Allocator_Error) {
	prompt := strings.builder_make()
	defer strings.builder_destroy(&prompt)
	file_list := buildDiffFileList(diff)
	defer delete(file_list)

	fmt.sbprintf(
		&prompt,
		`You are an expert code reviewer. Review batch %d of %d from the current git working tree.

You are running in a non-interactive review pipeline. Do not inspect files, use
tools, ask questions, or describe a plan. The git diff below is the complete
input. Return the review result immediately.

Hard output requirements:
- The first non-whitespace characters in your reply must be [SUMMARY].
- Do not write preamble such as "I'll review", "Let me inspect", or "I need to examine".
- Use only the exact markers and field names shown in Reply Format.
- If there are no real issues, return a concise [SUMMARY] block and no [FINDING] blocks.
- If a concern needs source context that is not present in the diff, omit it.

This batch may contain only part of the complete working-tree diff. Imports,
references, and related files can exist outside this batch. Do not report a file,
symbol, import, or dependency as missing merely because it is not shown in this
batch. Review only the changed lines present in this batch.

Focus on real issues only: correctness bugs, missed edge cases, security issues,
data loss risks, broken UX, performance problems, or maintainability problems
that would matter in this patch. Ignore tiny style preferences.

Return only findings that can be attached to changed lines in this diff. Use
the new-line side "additions" only for added lines and "deletions" only for
removed lines. Do not attach findings to unmodified context lines. Line numbers
must be the line numbers shown by the diff hunk.
Finding markers must have exactly this shape:
[FINDING:path/to/file|additions|42]
Do not put hunk ranges, relative offsets, +42, -42, line ranges, or slash
suffixes in the marker.

For actionable findings, include a concrete suggestion that another model can
apply later. Do not rewrite whole files.

## Files In This Review Batch

%s
## Git Diff

[DIFF]
%s
[END_DIFF]

## Reply Format

[SUMMARY]
One compact markdown summary for this batch.
[END_SUMMARY]

[FINDING:path/to/file|additions|42]
Severity: error|warning|note
Actionable: true|false
Summary: One short sentence.
Suggestion:
Concrete fix to apply, or leave blank.
Details:
Markdown explanation.
[END_FINDING]
`,
			batch_index,
			batch_count,
			file_list,
			diff,
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

Pi_Assistant_Message_Event :: struct {
	type:  string `json:"type"`,
	delta: string `json:"delta"`,
	text:  string `json:"text"`,
}

Pi_Event :: struct {
	type:                    string                     `json:"type"`,
	delta:                   string                     `json:"delta"`,
	assistant_message_event: Pi_Assistant_Message_Event `json:"assistantMessageEvent"`,
}

parsePiDeltaLine :: proc(line: string) -> (string, bool, bool) {
	if !strings.contains(line, `"type"`) || !strings.contains(line, `"delta"`) {
		return "", false, false
	}

	event: Pi_Event
	if err := json.unmarshal(transmute([]byte)line, &event); err != nil {
		return "", false, true
	}
	if event.type == "message_update" {
		if event.assistant_message_event.type == "text_delta" && len(event.assistant_message_event.delta) > 0 {
			return event.assistant_message_event.delta, true, false
		}
		if event.assistant_message_event.type == "text" && len(event.assistant_message_event.text) > 0 {
			return event.assistant_message_event.text, true, false
		}
		if len(event.delta) > 0 {
			return event.delta, true, false
		}
		return "", false, false
	}
	if event.type == "text_delta" && len(event.delta) > 0 {
		return event.delta, true, false
	}
	return "", false, false
}

extractPiOutputText :: proc(output: string) -> string {
	lines := strings.split(output, "\n")
	defer delete(lines)

	full_text := strings.builder_make()
	defer strings.builder_destroy(&full_text)
	message_updates := 0
	parse_failures := 0
	non_message_lines := 0

	for line in lines {
		delta, has_delta, parse_failed := parsePiDeltaLine(line)
		if parse_failed {
			parse_failures += 1
			continue
		}
		if has_delta {
			message_updates += 1
			strings.write_string(&full_text, delta)
			continue
		}
		if !strings.contains(line, `"type"`) || !strings.contains(line, `"delta"`) {
			if len(strings.trim_space(line)) > 0 {
				non_message_lines += 1
			}
		}
	}

	text := strings.to_string(full_text)
	debug_log(
		fmt.tprintf(
			"pi stream parsed: %d line(s), %d message delta(s), %d parse failure(s), %d non-message line(s), extracted %d byte(s)",
			len(lines),
			message_updates,
			parse_failures,
			non_message_lines,
			len(text),
		),
	)
	if len(text) > 0 {
		debug_log(fmt.tprintf("pi extracted preview: %s", preview(text)))
	} else if len(output) > 0 {
		debug_log(fmt.tprintf("pi raw output preview with no extracted text: %s", preview(output)))
	}
	return strings.clone(text, context.allocator)
}

consumePiStreamChunk :: proc(
	chunk: string,
	line_buffer: ^strings.Builder,
	full_text: ^strings.Builder,
	stdout_capture: ^strings.Builder,
	message_updates: ^int,
	parse_failures: ^int,
	non_message_lines: ^int,
) {
	strings.write_string(stdout_capture, chunk)

	for i := 0; i < len(chunk); i += 1 {
		c := chunk[i]
		if c == '\n' {
			line := strings.to_string(line_buffer^)
			strings.builder_reset(line_buffer)

			delta, has_delta, parse_failed := parsePiDeltaLine(line)
			if parse_failed {
				parse_failures^ += 1
				continue
			}
			if has_delta {
				message_updates^ += 1
				strings.write_string(full_text, delta)
				fmt.eprint(delta)
				continue
			}
			if len(strings.trim_space(line)) > 0 {
				non_message_lines^ += 1
			}
		} else {
			strings.write_byte(line_buffer, c)
		}
	}
}

flushPiStreamLine :: proc(
	line_buffer: ^strings.Builder,
	full_text: ^strings.Builder,
	message_updates: ^int,
	parse_failures: ^int,
	non_message_lines: ^int,
) {
	line := strings.to_string(line_buffer^)
	if len(line) == 0 {
		return
	}
	strings.builder_reset(line_buffer)

	delta, has_delta, parse_failed := parsePiDeltaLine(line)
	if parse_failed {
		parse_failures^ += 1
		return
	}
	if has_delta {
		message_updates^ += 1
		strings.write_string(full_text, delta)
		fmt.eprint(delta)
		return
	}
	if len(strings.trim_space(line)) > 0 {
		non_message_lines^ += 1
	}
}

runPiPrompt :: proc(prompt: string, disable_tools := false) -> (string, string, bool) {
	prompt_path, ok := writeTempFile(prompt)
	if !ok {
		return "", "Failed to write prompt to temp file", false
	}
	defer os.remove(prompt_path)
	debug_log(fmt.tprintf("wrote pi prompt %s (%d byte(s))", prompt_path, len(prompt)))

	borrowed_pi_arg := fmt.tprintf("@%s", prompt_path)
	pi_arg, aerr := strings.clone(borrowed_pi_arg)
	if aerr != nil {
		return "", "Failed to format pi argument", false
	}
	defer delete(pi_arg)

	pi_command := [dynamic]string {
		"pi",
		"--mode",
		"json",
		"--print",
		"--no-session",
		"--no-context-files",
	}
	if disable_tools {
		append(&pi_command, "--no-tools")
	}
	append(&pi_command, pi_arg)
	defer delete(pi_command)

	pipe_read, pipe_write, pipe_err := os.pipe()
	if pipe_err != nil {
		return "", "Failed to create pi stdout pipe", false
	}
	defer os.close(pipe_read)

	debug_log("starting pi --mode json")
	process, start_err := os.process_start(
		os.Process_Desc {
			command = pi_command[:],
			stdout  = pipe_write,
			stderr  = pipe_write,
		},
	)
	os.close(pipe_write)
	if start_err != nil {
		return "", "pi process failed to start", false
	}

	full_text := strings.builder_make()
	defer strings.builder_destroy(&full_text)
	stdout_capture := strings.builder_make()
	defer strings.builder_destroy(&stdout_capture)
	line_buffer := strings.builder_make()
	defer strings.builder_destroy(&line_buffer)

	message_updates := 0
	parse_failures := 0
	non_message_lines := 0
	read_buf: [4096]byte

	debug_log("pi text delta stream follows")
	for {
		n, read_err := os.read(pipe_read, read_buf[:])
		if n > 0 {
			consumePiStreamChunk(
				string(read_buf[:n]),
				&line_buffer,
				&full_text,
				&stdout_capture,
				&message_updates,
				&parse_failures,
				&non_message_lines,
			)
		}
		if n == 0 || read_err != nil {
			break
		}
	}
	flushPiStreamLine(
		&line_buffer,
		&full_text,
		&message_updates,
		&parse_failures,
		&non_message_lines,
	)
	fmt.eprintln("")
	debug_log("pi text delta stream ended")

	state, wait_err := os.process_wait(process)
	if wait_err != nil {
		return "", "pi process wait failed", false
	}
	stdout_text := strings.to_string(stdout_capture)
	text := strings.to_string(full_text)
	debug_log(
		fmt.tprintf(
			"pi finished; success=%v, exit_code=%d, captured=%d byte(s), extracted=%d byte(s)",
			state.success,
			state.exit_code,
			len(stdout_text),
			len(text),
		),
	)
	debug_log(
		fmt.tprintf(
			"pi stream parsed live: %d message delta(s), %d parse failure(s), %d non-message line(s)",
			message_updates,
			parse_failures,
			non_message_lines,
		),
	)
	if len(text) > 0 {
		debug_log(fmt.tprintf("pi extracted preview: %s", preview(text)))
	} else if len(stdout_text) > 0 {
		debug_log(fmt.tprintf("pi raw output preview with no extracted text: %s", preview(stdout_text)))
	}

	if !state.success {
		err_msg := "pi process failed"
		if len(stdout_text) > 0 {
			err_msg = preview(stdout_text)
		}
		return "", err_msg, false
	}

	return strings.clone(text, context.allocator), "", true
}

parsePiOutput :: proc(output: string) -> [dynamic]Reply_Entry {
	replies := [dynamic]Reply_Entry{}
	full := output
	extracted := ""
	if !strings.contains(output, "[REPLY:") {
		extracted = extractPiOutputText(output)
		full = extracted
	}
	defer {
		if len(extracted) > 0 {
			delete(extracted)
		}
	}
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

	debug_log(fmt.tprintf("parsed %d inline reply/replies from pi output", len(replies)))
	return replies
}

lineValue :: proc(line, prefix: string) -> (string, bool) {
	if !strings.has_prefix(line, prefix) {
		return "", false
	}
	return strings.trim_space(line[len(prefix):]), true
}

cloneTrimmed :: proc(value: string) -> string {
	cloned, err := strings.clone(strings.trim_space(value), context.allocator)
	if err != nil {
		return ""
	}
	return cloned
}

parseReviewOutput :: proc(output: string) -> FullReview_Result_Data {
	debug_log(fmt.tprintf("parsing full review output (%d byte(s))", len(output)))
	result := FullReview_Result_Data{
		summary  = "",
		findings = [dynamic]Review_Finding{},
	}

	summary_start := strings.index(output, "[SUMMARY]")
	if summary_start != -1 {
		summary_body_start := summary_start + len("[SUMMARY]")
		summary_rest := output[summary_body_start:]
		summary_end := strings.index(summary_rest, "[END_SUMMARY]")
		if summary_end != -1 {
			result.summary = cloneTrimmed(string(summary_rest[:summary_end]))
		}
	}

	parts := strings.split(output, "[FINDING:")
	defer delete(parts)
	for i := 1; i < len(parts); i += 1 {
		part := string(parts[i])
		bracket_pos := strings.index(part, "]")
		if bracket_pos == -1 {
			continue
		}

		comment_key := cloneTrimmed(string(part[:bracket_pos]))
		if len(comment_key) == 0 {
			delete(comment_key)
			continue
		}

		rest := part[bracket_pos + 1:]
		end_pos := strings.index(rest, "[END_FINDING]")
		if end_pos != -1 {
			rest = rest[:end_pos]
		}

		severity := "warning"
		actionable := false
		summary := ""
		suggestion := strings.builder_make()
		details := strings.builder_make()
		mode := ""

		lines := strings.split(rest, "\n")
		for line in lines {
			trimmed := strings.trim_space(line)
			if value, ok := lineValue(trimmed, "Severity:"); ok {
				severity = cloneTrimmed(value)
				mode = ""
				continue
			}
			if value, ok := lineValue(trimmed, "Actionable:"); ok {
				lower := strings.to_lower(value)
				actionable = lower == "true" || lower == "yes"
				mode = ""
				continue
			}
			if value, ok := lineValue(trimmed, "Summary:"); ok {
				summary = cloneTrimmed(value)
				mode = ""
				continue
			}
			if value, ok := lineValue(trimmed, "Suggestion:"); ok {
				mode = "suggestion"
				if len(value) > 0 {
					strings.write_string(&suggestion, value)
					strings.write_string(&suggestion, "\n")
				}
				continue
			}
			if value, ok := lineValue(trimmed, "Details:"); ok {
				mode = "details"
				if len(value) > 0 {
					strings.write_string(&details, value)
					strings.write_string(&details, "\n")
				}
				continue
			}

			if mode == "suggestion" {
				strings.write_string(&suggestion, line)
				strings.write_string(&suggestion, "\n")
			} else if mode == "details" {
				strings.write_string(&details, line)
				strings.write_string(&details, "\n")
			}
		}
		delete(lines)

		suggestion_raw := strings.to_string(suggestion)
		details_raw := strings.to_string(details)
		suggestion_text := cloneTrimmed(suggestion_raw)
		details_text := cloneTrimmed(details_raw)
		strings.builder_destroy(&suggestion)
		strings.builder_destroy(&details)

		if len(summary) == 0 {
			summary = strings.clone("Code review finding", context.allocator) or_else "Code review finding"
		}

		append(
			&result.findings,
			Review_Finding {
				comment_key = comment_key,
				summary     = summary,
				body        = details_text,
				severity    = severity,
				actionable  = actionable && len(suggestion_text) > 0,
				suggestion  = suggestion_text,
			},
		)
	}

	if len(result.summary) == 0 {
		if len(result.findings) == 0 {
			trimmed_output := strings.trim_space(output)
			if len(trimmed_output) > 0 {
				fallback_summary := fmt.tprintf(
					"Pi returned a response, but BAKA could not parse any attachable findings:\n\n%s",
					preview(trimmed_output, 2000),
				)
				result.summary = strings.clone(fallback_summary, context.allocator) or_else "Pi returned an unparseable review response."
			} else {
				result.summary = strings.clone("Pi did not find review issues in the current diff.", context.allocator) or_else "Pi did not find review issues in the current diff."
			}
		} else {
			result.summary = strings.clone(fmt.tprintf("Pi found %d review item(s).", len(result.findings)), context.allocator) or_else "Pi found review items."
		}
	}

	debug_log(fmt.tprintf("parsed full review: summary=%d byte(s), findings=%d", len(result.summary), len(result.findings)))
	return result
}

buildApplySuggestionPrompt :: proc(file_name, diff, suggestion: string) -> (string, mem.Allocator_Error) {
	prompt := strings.builder_make()
	defer strings.builder_destroy(&prompt)

	fmt.sbprintf(
		&prompt,
		`You are applying a code review suggestion to one file.

Return a unified git patch only. The patch must apply cleanly with git apply
from the repository root. Do not include commentary outside [PATCH] markers.
Keep the change minimal and only implement the suggestion.

The result must compile. Before returning the patch, mentally check syntax,
imports, variant names, JSX structure, generated bindings, and any affected
type signatures. Preserve existing behavior outside the suggestion.

File: %s

Suggestion:
%s

Current diff/context:
[DIFF]
%s
[END_DIFF]

[PATCH]
diff --git ...
[END_PATCH]
`,
		file_name,
		suggestion,
		diff,
	)

	return strings.clone(strings.to_string(prompt))
}

buildApplyValidationPrompt :: proc(repo_root, file_name, diff, suggestion: string, attempt: int) -> (string, mem.Allocator_Error) {
	prompt := strings.builder_make()
	defer strings.builder_destroy(&prompt)

	fmt.sbprintf(
		&prompt,
		`You are validating a code review suggestion that BAKA already applied to a generic repository.

Use your tools to inspect the repository and run the appropriate validation for
this project. Do not assume a language, framework, package manager, or command.
Infer the right checks from the changed files and repo conventions such as
README files, package/build manifests, lockfiles, CI config, test config, and
existing scripts.

Run the smallest useful validation that gives confidence the applied patch did
not break the project. Prefer existing project scripts over invented commands.
If there is no obvious validation command, perform the best available static
inspection and say that no runnable validation was discovered.

Do not edit files directly with tools. If validation fails and you can repair the
applied patch, return a unified git patch inside [PATCH] markers. The repair
patch must apply cleanly with git apply from the repository root and must be
minimal. If validation passes, do not return a patch.

Repo root: %s
Validation attempt: %d
Original target file: %s

Original suggestion:
%s

Current working-tree diff:
[DIFF]
%s
[END_DIFF]

Reply format:

When validation passes:
[VALIDATION_OK]
Commands or checks run, and a concise result.
[END_VALIDATION_OK]

When validation fails and you can repair it:
[VALIDATION_FAILED]
Commands or checks run, failure output summary, and why the repair is needed.
[END_VALIDATION_FAILED]
[PATCH]
diff --git ...
[END_PATCH]

When validation fails and you cannot repair it:
[VALIDATION_FAILED]
Commands or checks run and failure output summary. Explain why no safe repair
patch is available.
[END_VALIDATION_FAILED]
`,
		repo_root,
		attempt,
		file_name,
		suggestion,
		diff,
	)

	return strings.clone(strings.to_string(prompt))
}

extractPatchFromPiText :: proc(text: string) -> string {
	start := strings.index(text, "[PATCH]")
	if start != -1 {
		body_start := start + len("[PATCH]")
		rest := text[body_start:]
		end := strings.index(rest, "[END_PATCH]")
		if end != -1 {
			return strings.clone(strings.trim_space(string(rest[:end])), context.allocator)
		}
		return strings.clone(strings.trim_space(string(rest)), context.allocator)
	}

	diff_start := strings.index(text, "diff --git ")
	if diff_start != -1 {
		return strings.clone(strings.trim_space(string(text[diff_start:])), context.allocator)
	}

	return ""
}

getWorkingTreeDiff :: proc(repo_root: string) -> string {
	command: [dynamic]string = {"git", "--no-pager", "diff", "HEAD", "--"}
	defer delete(command)
	_, stdout, stderr, err := os.process_exec(
		os.Process_Desc{working_dir = repo_root, command = command[:]},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)

	if err != nil {
		if len(stderr) > 0 {
			return strings.clone(string(stderr), context.allocator) or_else ""
		}
		return ""
	}
	return strings.clone(string(stdout), context.allocator) or_else ""
}

runPiApplyValidation :: proc(repo_root, file_name, suggestion: string, attempt: int) -> (bool, string, string, bool) {
	diff := getWorkingTreeDiff(repo_root)
	defer delete(diff)

	prompt, prompt_err := buildApplyValidationPrompt(repo_root, file_name, diff, suggestion, attempt)
	if prompt_err != nil {
		return false, "", "Failed to build validation prompt", false
	}

	validation_text, pi_err, pi_ok := runPiPrompt(prompt)
	delete(prompt)
	if !pi_ok {
		return false, "", pi_err, false
	}

	validation_ok := strings.contains(validation_text, "[VALIDATION_OK]")
	debug_log(fmt.tprintf("pi validation attempt %d ok=%v preview=%s", attempt, validation_ok, preview(validation_text)))
	return validation_ok, validation_text, "", true
}

applyPatchFile :: proc(repo_root, patch_path: string, reverse := false) -> (bool, string) {
	apply_command: [dynamic]string = {
		"git",
		"apply",
		"--whitespace=nowarn",
	}
	if reverse {
		append(&apply_command, "--reverse")
	}
	append(&apply_command, patch_path)
	defer delete(apply_command)

	_, _, stderr, apply_err := os.process_exec(
		os.Process_Desc{working_dir = repo_root, command = apply_command[:]},
		context.allocator,
	)
	defer delete(stderr)
	if apply_err == nil {
		return true, ""
	}

	err_msg := "git apply failed"
	if reverse {
		err_msg = "git apply --reverse failed"
	}
	if len(stderr) > 0 {
		err_msg = string(stderr)
	}
	return false, strings.clone(err_msg, context.allocator) or_else "git apply failed"
}

rollbackAppliedPatches :: proc(repo_root, primary_patch_path, repair_patch_path: string, repair_applied: bool) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	if repair_applied && len(repair_patch_path) > 0 {
		if ok, msg := applyPatchFile(repo_root, repair_patch_path, reverse = true); !ok {
			fmt.sbprintf(&builder, "Failed to roll back repair patch: %s\n", msg)
			delete(msg)
		}
	}
	if ok, msg := applyPatchFile(repo_root, primary_patch_path, reverse = true); !ok {
		fmt.sbprintf(&builder, "Failed to roll back original patch: %s\n", msg)
		delete(msg)
	}

	message := strings.to_string(builder)
	return strings.clone(message, context.allocator) or_else ""
}

process_full_review :: proc() -> (cstring, bool) {
	debug_log("process_full_review started")
	file_names, ok := getReviewFileNames()
	defer deleteStringArray(file_names)
	if !ok {
		return make_error_cstring("Failed to collect changed files"), true
	}

	if len(file_names) == 0 {
		debug_log("process_full_review found no changed files")
		empty := FullReview_Result {
			result = FullReview_Result_Data {
				summary  = "There are no changed files to review.",
				findings = [dynamic]Review_Finding{},
			},
		}
		data, merr := json.marshal(empty)
		if merr != nil {
			return make_error_cstring("Failed to marshal empty review"), true
		}
		defer delete(data)
		return strings.clone_to_cstring(string(data)), false
	}

	repo_root := getRepoRoot()
	if len(repo_root) == 0 {
		repo_root = "."
	}
	defer delete(repo_root)

	batches := [dynamic]string{}
	defer {
		for batch in batches {
			delete(batch)
		}
		delete(batches)
	}

	current := strings.builder_make()
	defer strings.builder_destroy(&current)
	current_len := 0

	flush_batch :: proc(builder: ^strings.Builder, current_len: ^int, batches: ^[dynamic]string) -> bool {
		if current_len^ == 0 {
			return true
		}
		batch_text, berr := strings.clone(strings.to_string(builder^), context.allocator)
		if berr != nil {
			return false
		}
		append(batches, batch_text)
		strings.builder_reset(builder)
		current_len^ = 0
		return true
	}

	for file in file_names {
		diff := getReviewDiffForFile(repo_root, file)
		if len(diff) == 0 {
			debug_log(fmt.tprintf("skipping %s because diff is empty", file))
			continue
		}
		if current_len > 0 && current_len + len(diff) > PI_REVIEW_BATCH_CHAR_LIMIT {
			debug_log(fmt.tprintf("flushing review batch at %d byte(s)", current_len))
			if !flush_batch(&current, &current_len, &batches) {
				delete(diff)
				return make_error_cstring("Failed to build review batches"), true
			}
		}
		strings.write_string(&current, diff)
		strings.write_string(&current, "\n")
		current_len += len(diff) + 1
		delete(diff)
	}
	if !flush_batch(&current, &current_len, &batches) {
		return make_error_cstring("Failed to build review batches"), true
	}
	debug_log(fmt.tprintf("built %d review batch(es)", len(batches)))

	if len(batches) == 0 {
		debug_log("process_full_review found no diff hunks")
		empty := FullReview_Result {
			result = FullReview_Result_Data {
				summary  = "There are no diff hunks to review.",
				findings = [dynamic]Review_Finding{},
			},
		}
		data, merr := json.marshal(empty)
		if merr != nil {
			return make_error_cstring("Failed to marshal empty review"), true
		}
		defer delete(data)
		return strings.clone_to_cstring(string(data)), false
	}

	merged := FullReview_Result_Data {
		summary  = "",
		findings = [dynamic]Review_Finding{},
	}
	summary_builder := strings.builder_make()
	defer strings.builder_destroy(&summary_builder)

	for batch, idx in batches {
		debug_log(fmt.tprintf("review batch %d/%d has %d byte(s)", idx + 1, len(batches), len(batch)))
		prompt, perr := buildFullReviewPrompt(batch, idx + 1, len(batches))
		if perr != nil {
			return make_error_cstring("Failed to build review prompt"), true
		}
		pi_text, pi_err, pi_ok := runPiPrompt(prompt, disable_tools = true)
		delete(prompt)
		if !pi_ok {
			return make_error_cstring(pi_err), true
		}

		parsed := parseReviewOutput(pi_text)
		delete(pi_text)
		debug_log(fmt.tprintf("review batch %d/%d returned %d finding(s)", idx + 1, len(batches), len(parsed.findings)))

		if len(parsed.summary) > 0 {
			if len(batches) > 1 {
				fmt.sbprintf(&summary_builder, "Batch %d: %s\n", idx + 1, parsed.summary)
			} else {
				strings.write_string(&summary_builder, parsed.summary)
			}
		}
		for finding in parsed.findings {
			append(&merged.findings, finding)
		}
		delete(parsed.findings)
	}

	if len(merged.findings) == 0 {
		merged_summary_raw := strings.to_string(summary_builder)
		merged.summary = cloneTrimmed(merged_summary_raw)
		if len(merged.summary) == 0 {
			merged.summary = strings.clone("Pi did not find review issues in the current diff.", context.allocator) or_else "Pi did not find review issues in the current diff."
		}
	} else {
		merged_summary_raw := strings.to_string(summary_builder)
		merged.summary = cloneTrimmed(merged_summary_raw)
		if len(merged.summary) == 0 {
			merged.summary = strings.clone(fmt.tprintf("Pi found %d review item(s).", len(merged.findings)), context.allocator) or_else "Pi found review items."
		}
	}

	resp := FullReview_Result{result = merged}
	data, merr := json.marshal(resp)
	if merr != nil {
		return make_error_cstring("Failed to marshal review result"), true
	}
	defer delete(data)
	debug_log(fmt.tprintf("process_full_review returning %d finding(s), response=%d byte(s)", len(merged.findings), len(data)))

	return strings.clone_to_cstring(string(data)), false
}

process_apply_suggestion :: proc(req_str: string) -> (cstring, bool) {
	debug_log(fmt.tprintf("process_apply_suggestion started; req=%s", preview(req_str)))
	arr: [dynamic]ApplySuggestion_Request
	defer delete(arr)

	if err := json.unmarshal(transmute([]byte)req_str, &arr); err != nil {
		return make_error_cstring("Failed to parse apply request JSON"), true
	}
	if len(arr) == 0 {
		return make_error_cstring("Missing apply request body"), true
	}

	request := arr[0]
	parts := strings.split(request.comment_key, "|")
	defer delete(parts)
	if len(parts) < 1 {
		return make_error_cstring("Invalid review comment key"), true
	}

	file_name := string(parts[0])
	debug_log(fmt.tprintf("apply suggestion target=%s, suggestion=%d byte(s)", file_name, len(request.suggestion)))
	if !isPathSafe(file_name) {
		return make_error_cstring("Invalid file path"), true
	}
	if len(strings.trim_space(request.suggestion)) == 0 {
		return make_error_cstring("Missing suggestion text"), true
	}

	repo_root := getRepoRoot()
	if len(repo_root) == 0 {
		repo_root = "."
	}
	defer delete(repo_root)

	diff := getFilePatchFromGit(file_name)
	if len(diff) == 0 {
		delete(diff)
		diff = getReviewDiffForFile(repo_root, file_name)
	}
	defer delete(diff)
	if len(diff) == 0 {
		return make_error_cstring("Failed to fetch file diff for suggestion"), true
	}

	prompt, perr := buildApplySuggestionPrompt(file_name, diff, request.suggestion)
	if perr != nil {
		return make_error_cstring("Failed to build apply prompt"), true
	}
	pi_text, pi_err, pi_ok := runPiPrompt(prompt)
	delete(prompt)
	if !pi_ok {
		return make_error_cstring(pi_err), true
	}
	defer delete(pi_text)

	patch := extractPatchFromPiText(pi_text)
	if len(patch) == 0 {
		return make_error_cstring("Pi did not return a patch"), true
	}
	defer delete(patch)
	debug_log(fmt.tprintf("pi returned apply patch with %d byte(s); preview: %s", len(patch), preview(patch)))

	patch_path, ok := writeTempFile(patch)
	if !ok {
		return make_error_cstring("Failed to write patch to temp file"), true
	}
	defer os.remove(patch_path)

	if ok, apply_msg := applyPatchFile(repo_root, patch_path); !ok {
		defer delete(apply_msg)
		return make_error_cstring(apply_msg), true
	}
	debug_log(fmt.tprintf("git apply succeeded for %s", file_name))

	validation_ok, validation_message, validation_err, validation_call_ok := runPiApplyValidation(repo_root, file_name, request.suggestion, 1)
	defer delete(validation_message)
	if !validation_call_ok {
		rollback_msg := rollbackAppliedPatches(repo_root, patch_path, "", false)
		defer delete(rollback_msg)
		return make_error_cstring(fmt.tprintf("Applied patch, but Pi validation failed to run: %s\n\n%s", validation_err, rollback_msg)), true
	}
	if !validation_ok {
		debug_log(fmt.tprintf("validation failed after apply; attempting repair: %s", preview(validation_message)))

		repair_patch := extractPatchFromPiText(validation_message)
		defer delete(repair_patch)
		if len(repair_patch) == 0 {
			rollback_msg := rollbackAppliedPatches(repo_root, patch_path, "", false)
			defer delete(rollback_msg)
			return make_error_cstring(fmt.tprintf("Applied patch failed Pi-selected validation and Pi did not return a repair patch. The patch was rolled back.\n\n%s", validation_message)), true
		}

		repair_patch_path, repair_patch_ok := writeTempFile(repair_patch)
		if !repair_patch_ok {
			rollback_msg := rollbackAppliedPatches(repo_root, patch_path, "", false)
			defer delete(rollback_msg)
			return make_error_cstring("Applied patch failed validation, and BAKA could not write the repair patch. The patch was rolled back."), true
		}
		defer os.remove(repair_patch_path)

		repair_applied := false
		if ok, repair_apply_msg := applyPatchFile(repo_root, repair_patch_path); !ok {
			defer delete(repair_apply_msg)
			rollback_msg := rollbackAppliedPatches(repo_root, patch_path, "", false)
			defer delete(rollback_msg)
			return make_error_cstring(fmt.tprintf("Applied patch failed validation, and the repair patch did not apply: %s\n\n%s", repair_apply_msg, rollback_msg)), true
		} else {
			repair_applied = true
		}

		second_validation_ok, second_validation_message, second_validation_err, second_validation_call_ok := runPiApplyValidation(repo_root, file_name, request.suggestion, 2)
		defer delete(second_validation_message)
		if !second_validation_call_ok {
			rollback_msg := rollbackAppliedPatches(repo_root, patch_path, repair_patch_path, repair_applied)
			defer delete(rollback_msg)
			return make_error_cstring(fmt.tprintf("Applied patch repair was attempted, but Pi validation failed to run: %s\n\n%s", second_validation_err, rollback_msg)), true
		}
		if !second_validation_ok {
			rollback_msg := rollbackAppliedPatches(repo_root, patch_path, repair_patch_path, repair_applied)
			defer delete(rollback_msg)
			return make_error_cstring(
				fmt.tprintf(
					"Applied patch still failed Pi-selected validation after one repair attempt. BAKA rolled back the generated patch.\n\n%s\n%s",
					second_validation_message,
					rollback_msg,
				),
			), true
		}

		resp := ApplySuggestion_Result{result = fmt.tprintf("Applied suggestion to %s, repaired validation errors, and Pi-selected validation passed.\n\n%s", file_name, second_validation_message)}
		data, merr := json.marshal(resp)
		if merr != nil {
			return make_error_cstring("Failed to marshal apply result"), true
		}
		defer delete(data)
		return strings.clone_to_cstring(string(data)), false
	}

	resp := ApplySuggestion_Result{result = fmt.tprintf("Applied suggestion to %s and Pi-selected validation passed.\n\n%s", file_name, validation_message)}
	data, merr := json.marshal(resp)
	if merr != nil {
		return make_error_cstring("Failed to marshal apply result"), true
	}
	defer delete(data)
	return strings.clone_to_cstring(string(data)), false
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
	debug_log(fmt.tprintf("process_ask_pi started; req=%s", preview(req_str)))
	entries := [dynamic]Comment_Entry{}
	defer delete(entries)

	if err := json.unmarshal(transmute([]byte)req_str, &entries); err != nil {
		return strings.clone_to_cstring(`{"error": "Failed to parse comments JSON"}`), true
	}

	if len(entries) == 0 {
		debug_log("process_ask_pi received zero entries")
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
	debug_log(fmt.tprintf("process_ask_pi reviewing %d comment(s) across %d file(s)", len(entries), len(file_names)))

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

	pi_text, pi_err, pi_ok := runPiPrompt(prompt)
	if !pi_ok {
		return make_error_cstring(pi_err), true
	}
	defer delete(pi_text)

	replies := parsePiOutput(pi_text)
	defer delete(replies)

	result := AskPi_Result {
		result = replies,
	}
	data, merr := json.marshal(result)
	if merr != nil {
		return strings.clone_to_cstring(`{"error": "Failed to marshal replies"}`), true
	}
	defer delete(data)
	debug_log(fmt.tprintf("process_ask_pi returning %d replie(s), response=%d byte(s)", len(replies), len(data)))

	return strings.clone_to_cstring(string(data)), false
}

// Runs on a worker thread. Performs the long work, then bounces back to
// the UI thread via webview_dispatch so webview_return is invoked safely
// on the main loop. Self-cleanup: the thread struct is freed automatically.
@(private = "file")
ask_pi_worker :: proc(data: rawptr) {
	context = runtime.default_context()
	job := cast(^AskPi_Job)data

	debug_log("ask_pi_worker started")
	job.result, job.is_error = process_ask_pi(string(job.req))
	debug_log(fmt.tprintf("ask_pi_worker finished; is_error=%v", job.is_error))

	webview.dispatch(w, ask_pi_return_main, job)
}

// Runs on the main thread (via webview_dispatch). Calls webview_return and
// releases everything the job owned.
@(private = "file")
ask_pi_return_main :: proc "c" (wv: webview.webview, arg: rawptr) {
	context = runtime.default_context()
	job := cast(^AskPi_Job)arg
	status: c.int = WebView_Return_Error if job.is_error else WebView_Return_Ok
	debug_log(fmt.tprintf("returning IPC response to webview; is_error=%v, result=%d byte(s)", job.is_error, len(string(job.result))))
	webview.ret(wv, job.seq, status, job.result)
	delete(job.seq)
	delete(job.req)
	delete(job.result)
	free(job)
}

handle_ask_pi :: proc "c" (seq: cstring, req: cstring, arg: rawptr) {
	context = runtime.default_context()
	debug_log(fmt.tprintf("handle_ask_pi called; req=%s", preview(string(req))))

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
	debug_log(fmt.tprintf("process_ask_pi_with_diff started; req=%s", preview(req_str)))
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
	debug_log(fmt.tprintf("process_ask_pi_with_diff comments=%d, diff=%d byte(s)", len(comments), len(diff)))

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

	pi_text, pi_err, pi_ok := runPiPrompt(prompt)
	if !pi_ok {
		return make_error_cstring(pi_err), true
	}
	defer delete(pi_text)

	replies := parsePiOutput(pi_text)
	defer delete(replies)

	result := AskPi_Result {
		result = replies,
	}
	data, merr := json.marshal(result)
	if merr != nil {
		return strings.clone_to_cstring(`{"error": "Failed to marshal replies"}`), true
	}
	defer delete(data)
	debug_log(fmt.tprintf("process_ask_pi_with_diff returning %d replie(s), response=%d byte(s)", len(replies), len(data)))
	return strings.clone_to_cstring(string(data)), false
}

@(private = "file")
ask_pi_with_diff_worker :: proc(data: rawptr) {
	context = runtime.default_context()
	job := cast(^AskPi_Job)data
	debug_log("ask_pi_with_diff_worker started")
	job.result, job.is_error = process_ask_pi_with_diff(string(job.req))
	debug_log(fmt.tprintf("ask_pi_with_diff_worker finished; is_error=%v", job.is_error))
	webview.dispatch(w, ask_pi_return_main, job)
}

handle_ask_pi_with_diff :: proc "c" (seq: cstring, req: cstring, arg: rawptr) {
	context = runtime.default_context()
	debug_log(fmt.tprintf("handle_ask_pi_with_diff called; req=%s", preview(string(req))))

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

@(private = "file")
full_review_worker :: proc(data: rawptr) {
	context = runtime.default_context()
	job := cast(^AskPi_Job)data
	debug_log("full_review_worker started")
	job.result, job.is_error = process_full_review()
	debug_log(fmt.tprintf("full_review_worker finished; is_error=%v", job.is_error))
	webview.dispatch(w, ask_pi_return_main, job)
}

handle_start_full_review :: proc "c" (seq: cstring, req: cstring, arg: rawptr) {
	context = runtime.default_context()
	debug_log(fmt.tprintf("handle_start_full_review called; req=%s", preview(string(req))))

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

	t := thread.create_and_start_with_data(job, full_review_worker, self_cleanup = true)
	if t == nil {
		delete(seq_owned)
		delete(req_owned)
		free(job)
		webview.ret(w, seq, WebView_Return_Error, `{"error": "Failed to create thread"}`)
		return
	}
}

@(private = "file")
apply_suggestion_worker :: proc(data: rawptr) {
	context = runtime.default_context()
	job := cast(^AskPi_Job)data
	debug_log("apply_suggestion_worker started")
	job.result, job.is_error = process_apply_suggestion(string(job.req))
	debug_log(fmt.tprintf("apply_suggestion_worker finished; is_error=%v", job.is_error))
	webview.dispatch(w, ask_pi_return_main, job)
}

handle_apply_review_suggestion :: proc "c" (seq: cstring, req: cstring, arg: rawptr) {
	context = runtime.default_context()
	debug_log(fmt.tprintf("handle_apply_review_suggestion called; req=%s", preview(string(req))))

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

	t := thread.create_and_start_with_data(job, apply_suggestion_worker, self_cleanup = true)
	if t == nil {
		delete(seq_owned)
		delete(req_owned)
		free(job)
		webview.ret(w, seq, WebView_Return_Error, `{"error": "Failed to create thread"}`)
		return
	}
}
