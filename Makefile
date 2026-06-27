SHELL := /bin/sh

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD_DIR ?= $(ROOT)/build
DIST_DIR ?= $(BUILD_DIR)/dist
WEBVIEW_BUILD_DIR := $(BUILD_DIR)/webview
WEBVIEW_LIB_DIR := $(WEBVIEW_BUILD_DIR)/core
WEBVIEW_BUILD_STAMP := $(WEBVIEW_BUILD_DIR)/.build-stamp
OSDIALOG_DIR := $(ROOT)/APP/osdialog
OSDIALOG_BUILD_STAMP := $(BUILD_DIR)/osdialog/.build-stamp
APP_BIN ?= $(BUILD_DIR)/BAKA
APP_NAME ?= BAKA
APP_VERSION ?= 0.1.0
APP_BUNDLE_ID ?= dev.baka.BAKA
MACOS_APP ?= $(DIST_DIR)/$(APP_NAME).app
MACOS_ICON_SRC ?= $(UI_DIR)/logo-index.png
PACKAGE_MACOS_SCRIPT := $(ROOT)/scripts/package_macos_app.sh
UI_DIR := $(ROOT)/UI/bakaui
UI_DEPS_STAMP := $(UI_DIR)/node_modules/.yarn-integrity
UI_BUILD_STAMP := $(UI_DIR)/.build-stamp
UI_SOURCES := $(shell find "$(UI_DIR)/src" "$(UI_DIR)/assets" -type f 2>/dev/null)
UI_BUILD_FILES := \
	$(UI_DIR)/build.mjs \
	$(UI_DIR)/babel.transform.extractStyles.js \
	$(UI_DIR)/rescript.json \
	$(UI_DIR)/package.json \
	$(UI_DIR)/yarn.lock
APP_SOURCES := $(shell find "$(ROOT)/APP" -type f -name '*.odin' 2>/dev/null)
WEBVIEW_SOURCES := $(shell find "$(ROOT)/webview" -type f ! -path '*/.git/*' ! -name .git 2>/dev/null)
OSDIALOG_SOURCES := $(shell find "$(OSDIALOG_DIR)" -type f ! -path '*/.git/*' ! -name .git ! -name '*.o' ! -name '*.obj' 2>/dev/null)

CMAKE ?= cmake
ODIN ?= odin
YARN ?= yarn
ODIN_FLAGS ?=
ARGS ?=

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
WEBVIEW_LIBRARY := libwebview.dylib
APP_RPATH := @executable_path/webview/core
APP_LINKER_FLAGS := -Wl,-rpath,$(APP_RPATH)
else ifeq ($(UNAME_S),Linux)
WEBVIEW_LIBRARY := libwebview.so
# Odin invokes the linker through another shell, so preserve $ORIGIN for it.
APP_RPATH := \$$ORIGIN/webview/core
APP_LINKER_FLAGS := -L"$(WEBVIEW_LIB_DIR)" -Wl,-rpath,$(APP_RPATH)
else
$(error Unsupported operating system: $(UNAME_S))
endif

CMAKE_FLAGS := \
	-DWEBVIEW_BUILD_SHARED_LIBRARY=ON \
	-DWEBVIEW_BUILD_STATIC_LIBRARY=OFF \
	-DWEBVIEW_BUILD_EXAMPLES=OFF \
	-DWEBVIEW_BUILD_TESTS=OFF \
	-DWEBVIEW_BUILD_DOCS=OFF \
	-DWEBVIEW_BUILD_AMALGAMATION=OFF \
	-DWEBVIEW_ENABLE_CHECKS=OFF \
	-DWEBVIEW_ENABLE_PACKAGING=OFF

.PHONY: all ui webview osdialog app run package macos-app osx-app appimage clean help

all: app

ifeq ($(UNAME_S),Darwin)
package: macos-app
else ifeq ($(UNAME_S),Linux)
package: appimage
else
package:
	@echo "Unsupported packaging platform: $(UNAME_S)"
	@exit 1
endif

$(UI_DEPS_STAMP): $(UI_DIR)/package.json $(UI_DIR)/yarn.lock
	cd "$(UI_DIR)" && $(YARN) install --frozen-lockfile

ui: $(UI_DEPS_STAMP)
ui: $(UI_BUILD_STAMP)
	@test -s "$(UI_DIR)/out.js"
	@test -s "$(UI_DIR)/out.css"

$(UI_BUILD_STAMP): $(UI_DEPS_STAMP) $(UI_SOURCES) $(UI_BUILD_FILES)
	cd "$(UI_DIR)" && $(YARN) build
	@test -s "$(UI_DIR)/out.js"
	@test -s "$(UI_DIR)/out.css"
	@touch "$@"

webview: $(WEBVIEW_BUILD_STAMP)

$(WEBVIEW_BUILD_STAMP): $(WEBVIEW_SOURCES) Makefile
	$(CMAKE) -S "$(ROOT)/webview" -B "$(WEBVIEW_BUILD_DIR)" $(CMAKE_FLAGS)
	$(CMAKE) --build "$(WEBVIEW_BUILD_DIR)" --target webview_core_shared --parallel
	@test -e "$(WEBVIEW_LIB_DIR)/$(WEBVIEW_LIBRARY)"
	@touch "$@"

osdialog: $(OSDIALOG_BUILD_STAMP)

$(OSDIALOG_BUILD_STAMP): $(OSDIALOG_SOURCES) Makefile
	$(MAKE) -C "$(OSDIALOG_DIR)"
	@test -e "$(OSDIALOG_DIR)/osdialog.o"
	@if [ "$(UNAME_S)" = "Darwin" ]; then test -e "$(OSDIALOG_DIR)/osdialog_mac.o"; fi
	@if [ "$(UNAME_S)" = "Linux" ]; then test -e "$(OSDIALOG_DIR)/osdialog_gtk3.o"; fi
	@mkdir -p "$(dir $@)"
	@touch "$@"

app: $(APP_BIN)

$(APP_BIN): $(APP_SOURCES) $(UI_BUILD_STAMP) $(WEBVIEW_BUILD_STAMP) $(OSDIALOG_BUILD_STAMP) Makefile
	cd "$(WEBVIEW_LIB_DIR)" && \
		$(ODIN) build "$(ROOT)/APP" \
			-define:SHARED=true \
			-define:LOCAL=false \
			-out:"$(APP_BIN)" \
			-extra-linker-flags='$(APP_LINKER_FLAGS)' \
			$(ODIN_FLAGS)

run: app
	"$(APP_BIN)" $(ARGS)

macos-app: app $(PACKAGE_MACOS_SCRIPT)
	@if [ "$(UNAME_S)" != "Darwin" ]; then \
		echo "macos-app packaging requires macOS."; \
		exit 1; \
	fi
	APP_NAME="$(APP_NAME)" \
	APP_VERSION="$(APP_VERSION)" \
	APP_BUNDLE_ID="$(APP_BUNDLE_ID)" \
	APP_BIN="$(APP_BIN)" \
	WEBVIEW_LIB_DIR="$(WEBVIEW_LIB_DIR)" \
	MACOS_APP="$(MACOS_APP)" \
	MACOS_ICON_SRC="$(MACOS_ICON_SRC)" \
	"$(PACKAGE_MACOS_SCRIPT)"
	@echo "Created $(MACOS_APP)"

osx-app: macos-app

appimage:
	@echo "AppImage packaging is not implemented yet."
	@echo "The Linux packaging command is reserved here for a future AppImage target."
	@exit 1

clean:
	rm -rf "$(BUILD_DIR)"
	rm -f "$(OSDIALOG_DIR)"/*.o "$(OSDIALOG_DIR)"/*.obj
	rm -f "$(UI_DIR)/out.js" "$(UI_DIR)/out.css" "$(UI_BUILD_STAMP)"

help:
	@echo "make            Build the UI, libwebview, and BAKA"
	@echo "make ui         Build the ReScript/esbuild UI bundle"
	@echo "make osdialog   Build the native dialog bridge"
	@echo "make run        Build everything and run BAKA"
	@echo "make package    Build the native package for this platform"
	@echo "make macos-app  Build build/dist/BAKA.app on macOS"
	@echo "make clean      Remove generated build output"
	@echo "make ODIN_FLAGS=-debug"
	@echo "make run ARGS='--verbose /path/to/repository'"
