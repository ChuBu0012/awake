# Makefile for Awake

SHELL := /usr/bin/env bash
APP_NAME := Awake
BUNDLE_NAME := $(APP_NAME).app
BUILD_DIR := build
BIN_SRC := bin/awake
GO_BIN := $(BUILD_DIR)/awake
GO_TOOLCHAIN := go1.26.4
GO_SOURCES := $(shell find cmd internal -name '*.go' 2>/dev/null)
SWIFT_SRC := src/Awake.swift
PLIST_SRC := config/Info.plist
ICNS_SRC := config/AppIcon.icns

INSTALL_BIN_DIR := $(HOME)/.local/bin
INSTALL_LIB_DIR := $(HOME)/.local/lib/awake
INSTALL_APP_DIR := $(HOME)/Applications

.PHONY: all build cli icon test clean install setup uninstall help

all: build

## icon: Generate AppIcon.icns from vector Swift renderer
icon:
	@echo "==> Generating AppIcon.icns..."
	@mkdir -p /tmp/swift-module-cache config
	swift -module-cache-path /tmp/swift-module-cache scripts/generate-icon.swift config

## build: Compile Native Swift Menu Bar App & package .app bundle
build: icon cli
	@echo "==> Building $(APP_NAME)..."
	@mkdir -p $(BUILD_DIR)/$(BUNDLE_NAME)/Contents/MacOS
	@mkdir -p $(BUILD_DIR)/$(BUNDLE_NAME)/Contents/Resources
	@mkdir -p /tmp/swift-module-cache
	@chmod +x bin/awake scripts/setup-sudoers.sh
	swiftc -O -module-cache-path /tmp/swift-module-cache $(SWIFT_SRC) -o $(BUILD_DIR)/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME)
	cp $(PLIST_SRC) $(BUILD_DIR)/$(BUNDLE_NAME)/Contents/Info.plist
	cp $(GO_BIN) $(BUILD_DIR)/$(BUNDLE_NAME)/Contents/Resources/awake
	cp $(ICNS_SRC) $(BUILD_DIR)/$(BUNDLE_NAME)/Contents/Resources/AppIcon.icns
	@chmod +x $(BUILD_DIR)/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME)
	@echo "==> Build successful: $(BUILD_DIR)/$(BUNDLE_NAME)"

## cli: Build the shared Go engine and CLI for macOS 12+
cli: $(GO_BIN)

$(GO_BIN): go.mod $(GO_SOURCES)
	@mkdir -p $(BUILD_DIR)
	@echo "==> Building Awake CLI with Go $(GO_TOOLCHAIN)..."
	GOTOOLCHAIN=$(GO_TOOLCHAIN) MACOSX_DEPLOYMENT_TARGET=12.0 go build -trimpath -o $(GO_BIN) ./cmd/awake

## test: Validate shell scripts syntax and build status
test:
	@echo "==> Validating shell scripts syntax..."
	bash -n bin/awake
	bash -n scripts/setup-sudoers.sh
	@echo "==> Running Go tests..."
	GOTOOLCHAIN=$(GO_TOOLCHAIN) go test ./...
	@echo "==> Running Go vet..."
	GOTOOLCHAIN=$(GO_TOOLCHAIN) go vet ./...
	@echo "==> Testing build..."
	@$(MAKE) build
	@echo "==> All checks passed!"

## setup: Configure passwordless sudo for pmset sleep toggle
setup:
	@./scripts/setup-sudoers.sh

## install: Install CLI to ~/.local/bin and Menu Bar app to ~/Applications
install: build
	@echo "==> Installing Awake CLI and App..."
	@mkdir -p $(INSTALL_BIN_DIR) $(INSTALL_LIB_DIR) $(INSTALL_APP_DIR)
	cp $(GO_BIN) $(INSTALL_BIN_DIR)/awake
	cp scripts/setup-sudoers.sh $(INSTALL_LIB_DIR)/setup-sudoers.sh
	@chmod +x $(INSTALL_BIN_DIR)/awake
	@chmod 700 $(INSTALL_LIB_DIR)
	@chmod 700 $(INSTALL_LIB_DIR)/setup-sudoers.sh
	@rm -rf $(INSTALL_APP_DIR)/$(BUNDLE_NAME)
	cp -R $(BUILD_DIR)/$(BUNDLE_NAME) $(INSTALL_APP_DIR)/
	@echo ""
	@echo "==> Installation complete!"
	@echo "  • CLI installed to: $(INSTALL_BIN_DIR)/awake"
	@echo "  • App installed to: $(INSTALL_APP_DIR)/$(BUNDLE_NAME)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. If ~/.local/bin is not in your PATH, add: export PATH=\"\$$HOME/.local/bin:\$$PATH\""
	@echo "  2. Run 'make setup' (once) to configure passwordless sudo for sleep toggles"
	@echo "  3. Launch app: open $(INSTALL_APP_DIR)/$(BUNDLE_NAME)"

## clean: Remove build artifacts
clean:
	@rm -rf $(BUILD_DIR)
	@echo "==> Cleaned build directory."

## uninstall: Remove installed app, CLI, and configuration
uninstall:
	@echo "==> Ending the menu bar session and checking active requests..."
	$(INSTALL_BIN_DIR)/awake session-end
	@if $(INSTALL_BIN_DIR)/awake status | grep -Eq '^Status: (Active|Suppressed)|^  • '; then \
		echo "An Awake command request is still active. Let 'awake run' finish, then run make uninstall again." >&2; \
		exit 1; \
	fi
	@echo "==> Removing installed files..."
	rm -f $(INSTALL_BIN_DIR)/awake
	rm -rf $(INSTALL_LIB_DIR)
	rm -rf $(INSTALL_APP_DIR)/$(BUNDLE_NAME)
	rm -rf $(HOME)/.config/awake $(HOME)/.config/mac-awake
	@if [ -f /etc/sudoers.d/awake ] || [ -f /etc/sudoers.d/mac-awake ]; then \
		echo "==> Removing sudoers rules (requires sudo)..."; \
		sudo rm -f /etc/sudoers.d/awake /etc/sudoers.d/mac-awake 2>/dev/null || true; \
	fi
	@echo "==> Uninstallation complete."

help:
	@echo "Awake Build System"
	@echo "Usage:"
	@echo "  make build      Build the .app bundle and CLI"
	@echo "  make cli        Build the shared CLI engine"
	@echo "  make setup      Configure passwordless sudo for pmset"
	@echo "  make install    Install to ~/.local/bin and ~/Applications"
	@echo "  make test       Validate script syntax and compile"
	@echo "  make clean      Remove build directory"
	@echo "  make uninstall  Uninstall everything and restore system"
