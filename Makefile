.PHONY: all rust ui bundle clean install test daemon cli

CARGO = cargo
SWIFT = swift
APP_NAME = wsteam
BUILD_DIR = $(PWD)/build
RUST_TARGET = release

all: rust ui bundle

# ── Rust ──────────────────────────────────────────────────────────────
rust:
	$(CARGO) build --release

daemon: rust
	@echo "Daemon built at: target/release/wsteamd"

cli: rust
	@echo "CLI built at: target/release/wsteam"

# ── Swift UI ──────────────────────────────────────────────────────────
ui:
	cd ui && $(SWIFT) build -c release

# ── App Bundle ────────────────────────────────────────────────────────
bundle: rust ui
	@mkdir -p "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS"
	@mkdir -p "$(BUILD_DIR)/$(APP_NAME).app/Contents/Resources"
	
	@# Copy binaries
	cp target/release/wsteamd "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS/"
	cp target/release/wsteam  "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS/"
	cp ui/.build/release/wsteam "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS/wsteam-ui"
	
	@# Info.plist (no signing required for personal use)
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > "$(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist"
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> "$(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist"
	@echo '<plist version="1.0"><dict>' >> "$(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist"
	@echo '  <key>CFBundleName</key><string>wsteam</string>' >> "$(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist"
	@echo '  <key>CFBundleIdentifier</key><string>local.wsteam</string>' >> "$(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist"
	@echo '  <key>CFBundleVersion</key><string>0.1.0</string>' >> "$(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist"
	@echo '  <key>CFBundleExecutable</key><string>wsteam-ui</string>' >> "$(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist"
	@echo '  <key>NSPrincipalClass</key><string>NSApplication</string>' >> "$(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist"
	@echo '  <key>LSMinimumSystemVersion</key><string>14.0</string>' >> "$(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist"
	@echo '  <key>NSHighResolutionCapable</key><true/>' >> "$(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist"
	@echo '</dict></plist>' >> "$(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist"
	
	@echo "App bundle: $(BUILD_DIR)/$(APP_NAME).app"

# ── Install CLI tools ─────────────────────────────────────────────────
install: rust
	sudo cp target/release/wsteam /usr/local/bin/wsteam
	sudo cp target/release/wsteamd /usr/local/bin/wsteamd
	@echo "Installed wsteam and wsteamd to /usr/local/bin"

# ── Tests ─────────────────────────────────────────────────────────────
test:
	$(CARGO) test --all

# ── Clean ─────────────────────────────────────────────────────────────
clean:
	$(CARGO) clean
	rm -rf ui/.build build
