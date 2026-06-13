#+ feature dynamic-literals

package main

import webview "./webview-odin"
import "base:runtime"
import json "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:os/old"
//import os "core:os/os2"
import "core:strings"

// UI assets embedded at compile time via #load
js_content := #load("../UI/bakaui/out.js", string) or_else ""
css_content := #load("../UI/bakaui/out.css", string) or_else ""

w: webview.webview

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
	repo_root := getRepoRoot()
	if repo_root == "" {
		repo_root = "."
	}
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
	webview.bind(w, "getWatcherEvents", handle_get_watcher_events, nil)
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

	strings.write_string(
		&html,
		`</style>
	<script type="text/javascript">
(function() {
  if (window.__bakaRepoChangeNoticeInstalled) return;
  window.__bakaRepoChangeNoticeInstalled = true;
  window.__bakaDiffReloadRequestCount = window.__bakaDiffReloadRequestCount || 0;
  var notice = null;
  var logPanel = null;

  function ensureLogPanel() {
    if (logPanel) return;
    logPanel = document.createElement('div');
    logPanel.style.cssText = 'position:fixed;left:16px;bottom:16px;z-index:2147483647;width:420px;max-height:180px;overflow:hidden;padding:10px 12px;border:1px solid #d0d7de;border-radius:8px;background:rgba(255,255,255,0.94);color:#24292f;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px;line-height:1.35;box-shadow:0 8px 24px rgba(0,0,0,0.18);';
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
    console.log('[BAKA watcher]', message);
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
    console.log('[BAKA watcher] Reload diff requested');
    try {
      window.__bakaDiffReloadRequestCount = (window.__bakaDiffReloadRequestCount || 0) + 1;
    } catch (err) {
      console.error('[BAKA watcher] Failed to request diff reload', err);
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
      notice.style.cssText = 'position:fixed;top:12px;left:50%;transform:translateX(-50%);z-index:2147483647;padding:8px 12px;border:1px solid #0969da;border-radius:999px;background:#0969da;color:#ffffff;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:13px;font-weight:600;box-shadow:0 8px 24px rgba(0,0,0,0.18);cursor:pointer;';
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
