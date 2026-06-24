SHELL := /bin/sh

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD_DIR ?= $(ROOT)/build
WEBVIEW_BUILD_DIR := $(BUILD_DIR)/webview
WEBVIEW_LIB_DIR := $(WEBVIEW_BUILD_DIR)/core
APP_BIN ?= $(BUILD_DIR)/BAKA
UI_DIR := $(ROOT)/UI/bakaui
UI_DEPS_STAMP := $(UI_DIR)/node_modules/.yarn-integrity

CMAKE ?= cmake
ODIN ?= odin
YARN ?= yarn
ODIN_FLAGS ?=
ARGS ?=

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
WEBVIEW_LIBRARY := libwebview.dylib
APP_RPATH := @executable_path/webview/core
else ifeq ($(UNAME_S),Linux)
WEBVIEW_LIBRARY := libwebview.so
APP_RPATH := $$ORIGIN/webview/core
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

.PHONY: all ui webview app run clean help

all: app

$(UI_DEPS_STAMP): $(UI_DIR)/package.json $(UI_DIR)/yarn.lock
	cd "$(UI_DIR)" && $(YARN) install --frozen-lockfile

ui: $(UI_DEPS_STAMP)
	cd "$(UI_DIR)" && $(YARN) build
	@test -s "$(UI_DIR)/out.js"
	@test -s "$(UI_DIR)/out.css"

webview:
	$(CMAKE) -S "$(ROOT)/webview" -B "$(WEBVIEW_BUILD_DIR)" $(CMAKE_FLAGS)
	$(CMAKE) --build "$(WEBVIEW_BUILD_DIR)" --target webview_core_shared --parallel
	@test -e "$(WEBVIEW_LIB_DIR)/$(WEBVIEW_LIBRARY)"

app: ui webview
	cd "$(WEBVIEW_LIB_DIR)" && \
		$(ODIN) build "$(ROOT)/APP" \
			-define:SHARED=true \
			-define:LOCAL=false \
			-out:"$(APP_BIN)" \
			-extra-linker-flags='-Wl,-rpath,$(APP_RPATH)' \
			$(ODIN_FLAGS)

run: app
	"$(APP_BIN)" $(ARGS)

clean:
	rm -rf "$(BUILD_DIR)"
	rm -f "$(UI_DIR)/out.js" "$(UI_DIR)/out.css"

help:
	@echo "make            Build the UI, libwebview, and BAKA"
	@echo "make ui         Build the ReScript/esbuild UI bundle"
	@echo "make run        Build everything and run BAKA"
	@echo "make clean      Remove generated build output"
	@echo "make ODIN_FLAGS=-debug"
	@echo "make run ARGS='--verbose /path/to/repository'"
