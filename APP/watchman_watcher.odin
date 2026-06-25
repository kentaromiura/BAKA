#+ feature dynamic-literals

package main

import "base:runtime"
import json "core:encoding/json"
import "core:fmt"
import "core:hash"
//import os "core:os/os2"
import "core:os"
import "core:os/old"
import "core:strings"
import "core:sys/posix"
import "core:thread"
import "core:time"

Watchman_Sockname :: struct {
	sockname: string `json:"sockname"`,
}

Watchman_Error_Response :: struct {
	error: string `json:"error"`,
}

Watchman_Subscription_Response :: struct {
	files:             [dynamic]string `json:"files"`,
	is_fresh_instance: bool `json:"is_fresh_instance"`,
}

Watchman_Client :: struct {
	fd:              posix.FD,
	previous_buffer: [1024]u8,
	previous_len:    int,
}

Webview_Events_Response :: struct {
	result: [dynamic]string `json:"result"`,
}

Watcher_Event_File :: struct {
	result: [dynamic]string `json:"result"`,
}

Repo_Snapshot :: struct {
	file_count: int,
	hash_xor:   u64,
	hash_sum:   u64,
}

repo_watcher_started: bool

FALLBACK_WATCH_INTERVAL :: 1 * time.Second

watchman_log :: proc(message: string) {
	if !baka_verbose {
		return
	}
	fmt.eprintln("[BAKA watcher]", message)
}

dispatch_repo_changed_event :: proc(message: string) {
	write_watcher_event(message)
}

watcher_event_path :: proc() -> (string, string) {
	tmp_dir, ok := os.lookup_env_alloc("TMPDIR", context.allocator)
	if !ok || len(tmp_dir) == 0 {
		tmp_dir = strings.clone("/tmp", context.allocator)
	}

	path := fmt.aprintf("%s/baka_watcher_event.json", tmp_dir)
	return path, tmp_dir
}

write_watcher_event :: proc(message: string) {
	path, tmp_dir := watcher_event_path()
	defer delete(path)
	defer delete(tmp_dir)

	payload := fmt.aprintf("{{\"result\":[%q]}}", message)
	defer delete(payload)

	if err := os.write_entire_file(path, transmute([]byte)payload); err != nil {
		watchman_log(fmt.tprintf("Failed to write watcher event: %v", err))
	}
}

read_watcher_events :: proc() -> [dynamic]string {
	path, tmp_dir := watcher_event_path()
	defer delete(path)
	defer delete(tmp_dir)

	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return [dynamic]string{}
	}
	defer delete(data)

	file_events: Watcher_Event_File
	if json.unmarshal(data, &file_events) != nil {
		os.remove(path)
		return [dynamic]string{}
	}

	os.remove(path)
	return file_events.result
}

watchman_installed :: proc() -> bool {
	watchman_log("Checking for watchman")
	command: [dynamic]string = {"sh", "-c", "command -v watchman >/dev/null 2>&1"}
	_, _, _, proc_err := os.process_exec(os.Process_Desc{command = command[:]}, context.allocator)
	if proc_err == nil {
		watchman_log("watchman found")
		return true
	}

	watchman_log("watchman not found; using polling fallback")
	return false
}

watchman_sockname :: proc() -> string {
	watchman_log("Getting watchman socket name")
	command: [dynamic]string = {"watchman", "get-sockname"}
	_, stdout, _, proc_err := os.process_exec(
		os.Process_Desc{command = command[:]},
		context.allocator,
	)
	defer delete(stdout)
	if proc_err != nil {
		watchman_log("Failed to run watchman get-sockname")
		return ""
	}

	resp: Watchman_Sockname
	if err := json.unmarshal(transmute([]byte)string(stdout), &resp); err != nil {
		watchman_log("Failed to parse watchman sockname")
		return ""
	}
	defer delete(resp.sockname)

	if resp.sockname == "" {
		watchman_log("watchman did not return a socket path")
		return ""
	}

	watchman_log(fmt.tprintf("watchman socket: %s", resp.sockname))
	return strings.clone(resp.sockname, context.allocator)
}

watchman_client_connect :: proc() -> (Watchman_Client, bool) {
	client: Watchman_Client
	client.fd = -1

	sockname := watchman_sockname()
	if sockname == "" {
		return client, false
	}
	defer delete(sockname)

	fd := posix.socket(posix.AF.UNIX, posix.Sock.STREAM)
	if fd < 0 {
		watchman_log("Failed to create watchman socket")
		return client, false
	}
	client.fd = fd

	addr: posix.sockaddr_un
	when ODIN_OS == .Darwin || ODIN_OS == .FreeBSD || ODIN_OS == .NetBSD || ODIN_OS == .OpenBSD {
		addr.sun_len = u8(size_of(addr))
	}
	addr.sun_family = .UNIX

	path_bytes := transmute([]byte)sockname
	if len(path_bytes) >= len(addr.sun_path) {
		watchman_log(fmt.tprintf("watchman socket path is too long: %s", sockname))
		posix.close(fd)
		client.fd = -1
		return client, false
	}
	copy(addr.sun_path[:], path_bytes)
	addr.sun_path[len(path_bytes)] = 0

	if posix.connect(fd, cast(^posix.sockaddr)(&addr), size_of(addr)) != .OK {
		watchman_log(fmt.tprintf("Failed to connect to watchman socket: %s", sockname))
		posix.close(fd)
		client.fd = -1
		return client, false
	}

	watchman_log("Connected to watchman socket")
	return client, true
}

watchman_client_send :: proc(client: ^Watchman_Client, message: string) -> bool {
	if len(message) == 0 {
		return true
	}

	bytes := transmute([]byte)message
	offset := 0
	for offset < len(bytes) {
		remaining := len(bytes[offset:])
		n := int(posix.send(client.fd, raw_data(bytes[offset:]), uint(remaining), {}))
		if n < 0 {
			watchman_log(fmt.tprintf("watchman send failed, errno=%d", int(posix.errno())))
			return false
		}
		if n == 0 {
			watchman_log("watchman send returned 0 bytes")
			return false
		}
		offset += n
	}
	return true
}

watchman_client_receive_line :: proc(client: ^Watchman_Client) -> (string, bool) {
	out := strings.builder_make()
	defer strings.builder_destroy(&out)

	if client.previous_len > 0 {
		previous := client.previous_buffer[:client.previous_len]
		newline_idx := -1
		for i := 0; i < len(previous); i += 1 {
			if previous[i] == '\n' {
				newline_idx = i
				break
			}
		}

		if newline_idx >= 0 {
			strings.write_string(&out, string(previous[:newline_idx + 1]))
			remaining := previous[newline_idx + 1:]
			if len(remaining) > 0 {
				if len(remaining) > len(client.previous_buffer) {
					remaining = remaining[:len(client.previous_buffer)]
				}
				copy(client.previous_buffer[:], remaining)
				client.previous_len = len(remaining)
			} else {
				client.previous_len = 0
			}
			return strings.clone(strings.to_string(out), context.allocator), true
		}

		strings.write_string(&out, string(previous))
		client.previous_len = 0
	}

	for {
		buf: [1024]u8
		n := int(posix.recv(client.fd, rawptr(&buf), len(buf), {}))
		if n < 0 {
			return "", false
		}
		if n == 0 {
			return "", false
		}

		chunk := buf[:n]
		newline_idx := -1
		for i := 0; i < len(chunk); i += 1 {
			if chunk[i] == '\n' {
				newline_idx = i
				break
			}
		}

		if newline_idx >= 0 {
			strings.write_string(&out, string(chunk[:newline_idx + 1]))
			rest := chunk[newline_idx + 1:]
			if len(rest) > 0 {
				if len(rest) > len(client.previous_buffer) {
					rest = rest[:len(client.previous_buffer)]
				}
				copy(client.previous_buffer[:], rest)
				client.previous_len = len(rest)
			}
			return strings.clone(strings.to_string(out), context.allocator), true
		}

		strings.write_string(&out, string(chunk))
	}
}

watchman_read_ok_response :: proc(client: ^Watchman_Client) -> bool {
	line, ok := watchman_client_receive_line(client)
	if !ok {
		watchman_log("Watchman did not respond to command")
		return false
	}

	trimmed_line := strings.trim_right(line, "\r\n")
	if trimmed_line == "" {
		delete(line)
		watchman_log("Watchman command response ok")
		return true
	}

	resp: Watchman_Error_Response
	if err := json.unmarshal(transmute([]byte)trimmed_line, &resp); err != nil {
		delete(line)
		watchman_log("Failed to parse watchman command response")
		return false
	}
	defer delete(resp.error)

	if resp.error != "" {
		delete(line)
		watchman_log(fmt.tprintf("watchman error: %s", resp.error))
		return false
	}

	delete(line)
	watchman_log("Watchman command response ok")
	return true
}

is_git_internal_path :: proc(path: string) -> bool {
	return path == ".git" || strings.has_prefix(path, ".git/")
}

watchman_response_has_non_git_changes :: proc(files: [dynamic]string) -> bool {
	for path in files {
		if !is_git_internal_path(path) {
			return true
		}
	}
	return false
}

summarize_watchman_event :: proc(line: string) -> string {
	if len(line) <= 2000 {
		return strings.clone(line, context.allocator)
	}
	return fmt.aprintf("%s...", line[:2000])
}

format_non_git_files :: proc(files: [dynamic]string) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	shown := 0
	for path in files {
		if is_git_internal_path(path) {
			continue
		}

		if shown > 0 {
			strings.write_string(&builder, ", ")
		}
		if shown < 5 {
			strings.write_string(&builder, path)
		}
		shown += 1
	}

	if shown > 5 {
		fmt.sbprintf(&builder, ", ...%d more", shown - 5)
	}

	return strings.clone(strings.to_string(builder), context.allocator)
}

snapshot_mix :: proc(value, data: u64) -> u64 {
	mixed := value ~ data
	mixed *= 0x9e3779b185ebca87
	return mixed ~ (mixed >> 32)
}

repo_snapshot :: proc(repo_root: string) -> (Repo_Snapshot, bool) {
	snapshot: Repo_Snapshot
	walker := os.walker_create(repo_root)
	defer os.walker_destroy(&walker)

	for info in os.walker_walk(&walker) {
		if info.type == .Directory && info.name == ".git" {
			os.walker_skip_dir(&walker)
			continue
		}

		entry_hash := hash.fnv64a(transmute([]byte)info.fullpath)
		entry_hash = snapshot_mix(entry_hash, u64(info.size))
		entry_hash = snapshot_mix(entry_hash, u64(time.to_unix_nanoseconds(info.modification_time)))
		entry_hash = snapshot_mix(entry_hash, u64(info.type))

		snapshot.file_count += 1
		snapshot.hash_xor ~= entry_hash
		snapshot.hash_sum += entry_hash
	}

	if path, err := os.walker_error(&walker); err != nil {
		watchman_log(fmt.tprintf("Polling fallback failed to scan %s: %v", path, err))
		return {}, false
	}

	return snapshot, true
}

poll_repo_for_changes :: proc(repo_root: string) {
	watchman_log("Starting polling watcher fallback")
	write_watcher_event("Watcher using polling fallback")

	previous, has_previous := repo_snapshot(repo_root)
	for {
		time.sleep(FALLBACK_WATCH_INTERVAL)

		current, ok := repo_snapshot(repo_root)
		if !ok {
			continue
		}
		if !has_previous {
			previous = current
			has_previous = true
			continue
		}
		if current == previous {
			continue
		}

		previous = current
		watchman_log("Polling fallback detected repository changes")
		dispatch_repo_changed_event(
			"Repository files changed. Reload the diff to see the latest changes.",
		)
	}
}

watch_repo_worker :: proc(repo_root: string) {
	context = runtime.default_context()
	defer delete(repo_root)

	watchman_log(fmt.tprintf("Repository watcher starting for: %s", repo_root))

	if !watchman_installed() {
		poll_repo_for_changes(repo_root)
		return
	}

	client, ok := watchman_client_connect()
	if !ok {
		watchman_log("Failed to connect to watchman; using polling fallback")
		poll_repo_for_changes(repo_root)
		return
	}

	watchman_log("Sending watch-project command")
	watch_project := fmt.aprintf("[\"watch-project\",%q]\n", repo_root)
	defer delete(watch_project)
	if !watchman_client_send(&client, watch_project) || !watchman_read_ok_response(&client) {
		watchman_log(fmt.tprintf("Failed to start watchman watch for: %s", repo_root))
		posix.close(client.fd)
		poll_repo_for_changes(repo_root)
		return
	}
	watchman_log("Started watchman watch-project")

	watchman_log("Sending subscribe command")
	subscribe := fmt.aprintf("[\"subscribe\",%q,\"baka\",{{\"fields\":[\"name\"]}}]\n", repo_root)
	defer delete(subscribe)
	if !watchman_client_send(&client, subscribe) || !watchman_read_ok_response(&client) {
		watchman_log(fmt.tprintf("Failed to subscribe to watchman changes for: %s", repo_root))
		posix.close(client.fd)
		poll_repo_for_changes(repo_root)
		return
	}

	watchman_log("Subscribed to repository changes")
	write_watcher_event("Watcher listening for repository changes")
	watchman_log("Watching repository for changes")

	for {
		line, ok := watchman_client_receive_line(&client)
		if !ok {
			watchman_log("Watchman connection closed; using polling fallback")
			break
		}

		line = strings.trim_right(line, "\r\n")
		if line == "" {
			delete(line)
			continue
		}

		event_summary := summarize_watchman_event(line)
		watchman_log(fmt.tprintf("Watchman event: %s", event_summary))
		delete(event_summary)

		resp: Watchman_Subscription_Response
		if err := json.unmarshal(transmute([]byte)line, &resp); err != nil {
			watchman_log("Failed to parse watchman event")
			delete(line)
			continue
		}

		if resp.is_fresh_instance {
			watchman_log(
				fmt.tprintf("Ignoring Watchman fresh instance with %d files", len(resp.files)),
			)
			delete(resp.files)
			delete(line)
			continue
		}

		if !watchman_response_has_non_git_changes(resp.files) {
			watchman_log("Ignoring Watchman event: only .git/internal files")
			delete(resp.files)
			delete(line)
			continue
		}

		changed_files := format_non_git_files(resp.files)
		watchman_log(fmt.tprintf("Non-git changes detected: %s", changed_files))
		delete(changed_files)

		dispatch_repo_changed_event(
			"Repository files changed. Reload the diff to see the latest changes.",
		)
		delete(resp.files)
		delete(line)
	}

	posix.close(client.fd)
	poll_repo_for_changes(repo_root)
}

start_repo_watcher :: proc() {
	if repo_watcher_started {
		watchman_log("Repository watcher already started")
		return
	}
	repo_watcher_started = true

	repo_root := getRepoRoot()
	if repo_root == "" {
		watchman_log("Not a git repository; repository watcher disabled")
		return
	}

	watchman_log(fmt.tprintf("Repository root: %s", repo_root))

	path, tmp_dir := watcher_event_path()
	defer delete(path)
	defer delete(tmp_dir)
	os.remove(path)
	write_watcher_event("Repository watcher started")

	t := thread.create_and_start_with_poly_data(repo_root, watch_repo_worker, self_cleanup = true)
	if t == nil {
		delete(repo_root)
		write_watcher_event("Watcher failed to start thread")
		watchman_log("Failed to start repository watcher thread")
		return
	}

	watchman_log("Repository watcher thread started")
}
