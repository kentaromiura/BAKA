#!/bin/sh
set -eu

APP_NAME=${APP_NAME:-BAKA}
APP_VERSION=${APP_VERSION:-0.1.0}
APP_BUNDLE_ID=${APP_BUNDLE_ID:-dev.baka.BAKA}
MACOS_ICON_SRC=${MACOS_ICON_SRC:-}

: "${APP_BIN:?APP_BIN is required}"
: "${WEBVIEW_LIB_DIR:?WEBVIEW_LIB_DIR is required}"
: "${MACOS_APP:?MACOS_APP is required}"

CONTENTS_DIR="$MACOS_APP/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_EXECUTABLE="$MACOS_DIR/$APP_NAME"
APP_WEBVIEW_DIR="$MACOS_DIR/webview/core"

xml_escape() {
	printf '%s' "$1" | sed \
		-e 's/&/\&amp;/g' \
		-e 's/</\&lt;/g' \
		-e 's/>/\&gt;/g' \
		-e 's/"/\&quot;/g' \
		-e "s/'/\&apos;/g"
}

make_icon() {
	icon_src=$1
	iconset_dir="$RESOURCES_DIR/AppIcon.iconset"

	if [ ! -f "$icon_src" ] || ! command -v sips >/dev/null 2>&1 || ! command -v iconutil >/dev/null 2>&1; then
		return 0
	fi

	rm -rf "$iconset_dir"
	mkdir -p "$iconset_dir"

	base_icon="$iconset_dir/icon_512x512@2x.png"
	sips --padToHeightWidth 1024 1024 "$icon_src" --out "$base_icon" >/dev/null
	sips -z 16 16 "$base_icon" --out "$iconset_dir/icon_16x16.png" >/dev/null
	sips -z 32 32 "$base_icon" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
	sips -z 32 32 "$base_icon" --out "$iconset_dir/icon_32x32.png" >/dev/null
	sips -z 64 64 "$base_icon" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
	sips -z 128 128 "$base_icon" --out "$iconset_dir/icon_128x128.png" >/dev/null
	sips -z 256 256 "$base_icon" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
	sips -z 256 256 "$base_icon" --out "$iconset_dir/icon_256x256.png" >/dev/null
	sips -z 512 512 "$base_icon" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
	sips -z 512 512 "$base_icon" --out "$iconset_dir/icon_512x512.png" >/dev/null

	iconutil -c icns "$iconset_dir" -o "$RESOURCES_DIR/AppIcon.icns" >/dev/null
	rm -rf "$iconset_dir"
}

write_info_plist() {
	escaped_name=$(xml_escape "$APP_NAME")
	escaped_bundle_id=$(xml_escape "$APP_BUNDLE_ID")
	escaped_version=$(xml_escape "$APP_VERSION")

	{
		printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
		printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
		printf '%s\n' '<plist version="1.0">'
		printf '%s\n' '<dict>'
		printf '\t%s\n\t<string>%s</string>\n' '<key>CFBundleName</key>' "$escaped_name"
		printf '\t%s\n\t<string>%s</string>\n' '<key>CFBundleDisplayName</key>' "$escaped_name"
		printf '\t%s\n\t<string>%s</string>\n' '<key>CFBundleExecutable</key>' "$escaped_name"
		printf '\t%s\n\t<string>%s</string>\n' '<key>CFBundleIdentifier</key>' "$escaped_bundle_id"
		printf '\t%s\n\t<string>APPL</string>\n' '<key>CFBundlePackageType</key>'
		printf '\t%s\n\t<string>%s</string>\n' '<key>CFBundleShortVersionString</key>' "$escaped_version"
		printf '\t%s\n\t<string>%s</string>\n' '<key>CFBundleVersion</key>' "$escaped_version"
		if [ -f "$RESOURCES_DIR/AppIcon.icns" ]; then
			printf '\t%s\n\t<string>AppIcon</string>\n' '<key>CFBundleIconFile</key>'
		fi
		printf '\t%s\n\t<true/>\n' '<key>NSHighResolutionCapable</key>'
		printf '\t%s\n\t<string>NSApplication</string>\n' '<key>NSPrincipalClass</key>'
		printf '%s\n' '</dict>'
		printf '%s\n' '</plist>'
	} > "$CONTENTS_DIR/Info.plist"
}

rm -rf "$MACOS_APP"
mkdir -p "$APP_WEBVIEW_DIR" "$RESOURCES_DIR"

cp "$APP_BIN" "$APP_EXECUTABLE"
chmod 755 "$APP_EXECUTABLE"

found_webview_dylib=false
for dylib in "$WEBVIEW_LIB_DIR"/libwebview*.dylib; do
	if [ -e "$dylib" ]; then
		cp -R "$dylib" "$APP_WEBVIEW_DIR/"
		found_webview_dylib=true
	fi
done

if [ "$found_webview_dylib" = false ]; then
	echo "No libwebview dylib files found in $WEBVIEW_LIB_DIR" >&2
	exit 1
fi

if [ -n "$MACOS_ICON_SRC" ]; then
	make_icon "$MACOS_ICON_SRC"
fi

write_info_plist

if command -v plutil >/dev/null 2>&1; then
	plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
fi

touch "$MACOS_APP"
