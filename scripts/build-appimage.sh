#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RELEASE_DIR=${RELEASE_DIR:-"$ROOT/release"}
APPDIR="$RELEASE_DIR/BAKA.AppDir"
APPIMAGE_ICON="$RELEASE_DIR/baka-appimage-icon.svg"
TOOLS_DIR=${APPIMAGE_TOOLS_DIR:-"${XDG_CACHE_HOME:-$HOME/.cache}/baka-appimage"}
VERSION=${VERSION:-$(git -C "$ROOT" describe --tags --always 2>/dev/null || printf 'dev')}

case "$(uname -m)" in
	x86_64)
		APPIMAGE_ARCH=x86_64
		;;
	aarch64|arm64)
		APPIMAGE_ARCH=aarch64
		;;
	armv7l|armhf)
		APPIMAGE_ARCH=armhf
		;;
	i386|i486|i586|i686)
		APPIMAGE_ARCH=i386
		;;
	*)
		printf 'Unsupported AppImage architecture: %s\n' "$(uname -m)" >/dev/stderr
		exit 1
		;;
+esac
+
+download_tool() {
+    name=$1
+    url=$2
+    path="$TOOLS_DIR/$name"
+
+    if [ ! -x "$path" ]; then
+        command -v curl >/dev/null 2>&1 || {
+            printf 'curl is required to download %s\n' "$name" >/dev/stderr
+            exit 1
+        }
+        mkdir -p "$TOOLS_DIR"
+        printf 'Downloading %s...\n' "$name" >/dev/stderr
+        curl -L --fail --silent --show-error "$url" -o "$path"
+        chmod +x "$path"
+    fi
+
+    printf '%s\n' "$path"
+}
+
+if command -v linuxdeploy >/dev/null 2>&1; then
+    LINUXDEPLOY=$(command -v linuxdeploy)
+else
+    LINUXDEPLOY=$(download_tool \
+        "linuxdeploy-$APPIMAGE_ARCH.AppImage" \
+        "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$APPIMAGE_ARCH.AppImage")
+fi
+
+if command -v appimagetool >/dev/null 2>&1; then
+    APPIMAGETOOL=$(command -v appimagetool)
+else
+    APPIMAGETOOL=$(download_tool \
+        "appimagetool-$APPIMAGE_ARCH.AppImage" \
+        "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-$APPIMAGE_ARCH.AppImage")
+fi
+
+run_appimage_tool() {
+    APPIMAGE_EXTRACT_AND_RUN=1 "$@"
+}
+
+printf 'Building BAKA...\n'
+make -C "$ROOT" app
+
+WEBVIEW_LIBRARY=$(readlink -f "$ROOT/build/webview/core/libwebview.so")
+WEBKIT_HELPERS=${WEBKIT_HELPERS:-/usr/lib/webkitgtk-6.0}
+if [ ! -d "$WEBKIT_HELPERS" ]; then
+    printf 'WebKitGTK helper directory not found: %s\n' "$WEBKIT_HELPERS" >/dev/stderr
+    exit 1
+fi
+
+rm -rf "$APPDIR"
+mkdir -p "$APPDIR/usr/lib"
+cp -a "$WEBKIT_HELPERS" "$APPDIR/usr/lib/webkitgtk-6.0"
+
+ICON_DATA=$(base64 < "$ROOT/UI/bakaui/logo-index.png" | tr -d '\n')
+{
+    printf '%s' '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"'>
+    printf '%s' '<image href="data:image/png;base64,'
+    printf '%s' "$ICON_DATA"
+    printf '%s\n' '" x="0" y="64" width="512" height="384"/></svg>'
+} > "$APPIMAGE_ICON"
+
+NO_STRIP=1 run_appimage_tool "$LINUXDEPLOY" \
+    --appdir "$APPDIR" \
+    --exclude-library libgnutls.so.30 \
+    --exclude-library libleancrypto.so.1 \
+    --exclude-library libhogweed.so.7 \
+    --exclude-library libnettle.so.9 \
+    --exclude-library libgmp.so.10 \
+    --exclude-library libp11-kit.so.0 \
+    --exclude-library libtasn1.so.6 \
+    --executable "$ROOT/build/BAKA" \
+    --library "$WEBVIEW_LIBRARY" \
+    --deploy-deps-only "$APPDIR/usr/lib/webkitgtk-6.0" \
+    --desktop-file "$ROOT/packaging/linux/baka.desktop" \
+    --icon-file "$APPIMAGE_ICON" \
+    --icon-filename baka \
+    --custom-apprun "$ROOT/packaging/linux/AppRun"
+
+ # Instead of brittle in-place binary substitution of hardcoded paths inside
+ # WebKit libraries, AppRun (created in packaging/linux/AppRun)
+ # will create a per-user runtime directory and symlink the AppDir's
+ # webkitgtk-6.0 tree there, then export WEBKIT_TMP and LD_LIBRARY_PATH.
+ # The old substitution approach assumed an identical-length replacement
+ # and was fragile and unsafe; do not perform it here.
+
+ # Sanity-check: ensure the AppDir webkit helper directory exists
+ if [ ! -d "$APPDIR/usr/lib/webkitgtk-6.0" ]; then
+    printf 'WebKit helper directory not found inside AppDir: %s\n' "$APPDIR/usr/lib/webkitgtk-6.0" >/dev/stderr
+    exit 1
+ fi
+
+desktop-file-validate "$APPDIR/usr/share/applications/baka.desktop" 2>/dev/null || true
+
+OUTPUT="$RELEASE_DIR/BAKA-$VERSION-$APPIMAGE_ARCH.AppImage"
+rm -f "$OUTPUT"
+printf 'Creating %s...\n' "$OUTPUT"
+ARCH="$APPIMAGE_ARCH" VERSION="$VERSION" \
+	run_appimage_tool "$APPIMAGETOOL" "$APPDIR" "$OUTPUT"
+chmod +x "$OUTPUT"
+
+printf 'Created %s\n' "$OUTPUT"
