package main

import webview "./webview-odin"
import "core:encoding/base64"
import "core:fmt"
import "core:os"
import "core:strings"

app_icon_png := #load("../UI/bakaui/logo-index.png")

when ODIN_OS == .Linux {
	foreign import gtk4 "system:gtk-4"

	GList :: struct {
		data: rawptr,
		next: ^GList,
		prev: ^GList,
	}

	app_icon_texture: rawptr
	app_icon_textures: GList

	@(default_calling_convention = "c")
	foreign gtk4 {
		gdk_texture_new_from_filename :: proc(path: cstring, error: rawptr) -> rawptr ---
		gdk_toplevel_set_icon_list :: proc(toplevel: rawptr, textures: ^GList) ---
		gtk_native_get_surface :: proc(native: rawptr) -> rawptr ---
	}

	set_app_icon :: proc(w: webview.webview) {
		window := webview.get_window(w)
		if window == nil {
			fmt.eprintln("[BAKA] Failed to get native window for app icon")
			return
		}

		tmp_dir, found := os.lookup_env_alloc("TMPDIR", context.allocator)
		if !found || len(tmp_dir) == 0 {
			delete(tmp_dir)
			tmp_dir = strings.clone("/tmp", context.allocator)
		}
		defer delete(tmp_dir)

		icon_path := fmt.aprintf("%s/baka_app_icon_%d.svg", tmp_dir, os.get_pid())
		defer delete(icon_path)
		defer os.remove(icon_path)

		encoded_png := base64.encode(app_icon_png)
		defer delete(encoded_png)
		square_icon := fmt.aprintf(
			`<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><image href="data:image/png;base64,%s" x="0" y="128" width="1024" height="768"/></svg>`,
			string(encoded_png),
		)
		defer delete(square_icon)

		if err := os.write_entire_file(icon_path, transmute([]byte)square_icon); err != nil {
			fmt.eprintln("[BAKA] Failed to prepare app icon:", err)
			return
		}

		c_icon_path := strings.clone_to_cstring(icon_path)
		defer delete(c_icon_path)
		app_icon_texture = gdk_texture_new_from_filename(c_icon_path, nil)
		if app_icon_texture == nil {
			fmt.eprintln("[BAKA] Failed to load app icon")
			return
		}

		surface := gtk_native_get_surface(window)
		if surface == nil {
			fmt.eprintln("[BAKA] Failed to get native surface for app icon")
			return
		}

		app_icon_textures = GList{data = app_icon_texture}
		gdk_toplevel_set_icon_list(surface, &app_icon_textures)
	}
} else {
	set_app_icon :: proc(w: webview.webview) {
		_ = w
	}
}
