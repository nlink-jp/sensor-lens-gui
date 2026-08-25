APP_NAME    := SensorLens
NAME        := sensor-lens-gui
BUNDLE_ID   := jp.nlink.sensor-lens-gui
VERSION     := $(shell git describe --tags --always --dirty 2>/dev/null || echo "0.1.0")
BUILD_DIR   := .build/release
DIST_DIR    := dist
APP_BUNDLE  := $(DIST_DIR)/$(APP_NAME).app

# The sensor-lens CLI is the engine: it holds the credentials, polls the API and
# owns the database. build-app bundles it into Contents/Resources so the .app is
# self-contained. Override CLI_BIN to point at a freshly built binary.
CLI_BIN ?= ../sensor-lens/dist/sensor-lens

# macOS Developer ID signing / notarization (see nlink-jp/.github CONVENTIONS.md
# §Code Signing → GUI apps). Pure SwiftUI/AppKit needs no JIT entitlements —
# Hardened Runtime alone suffices. --deep also signs the bundled CLI binary.
CODESIGN_IDENTITY ?= Developer ID Application
NOTARY_PROFILE    ?= nlink-jp-notary
CODESIGN_SCRIPT := scripts/codesign-darwin-app.sh
NOTARIZE_SCRIPT := scripts/notarize-darwin-app.sh

# App icon: a 1024x1024 source PNG; build-app generates AppIcon.icns into the
# bundle's Resources (sips + iconutil). Missing source → app builds without icon.
ICON_SRC := assets/AppIcon-1024.png

BREW_KIND      := cask
BREW_DESC      := Menu-bar readout of your SwitchBot temperature, humidity and CO2
BREW_NAME      := $(NAME)
BREW_APP       := $(APP_NAME).app
BREW_BUNDLE_ID := $(BUNDLE_ID)
include scripts/release-brew.mk

.PHONY: build build-app package verify-release test clean run

## build: build the release binary
build:
	@mkdir -p $(DIST_DIR)
	swift build -c release

## build-app: assemble the signed .app bundle (with the CLI bundled in)
build-app: build
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@sed 's/$${VERSION}/$(VERSION)/g; s/$${BUNDLE_ID}/$(BUNDLE_ID)/g; s/$${APP_NAME}/$(APP_NAME)/g' \
		Info.plist > $(APP_BUNDLE)/Contents/Info.plist
	@if [ -x "$(CLI_BIN)" ]; then \
		cp "$(CLI_BIN)" $(APP_BUNDLE)/Contents/Resources/sensor-lens; \
		echo "[bundle] embedded CLI from $(CLI_BIN)"; \
	else \
		echo "[bundle] WARN: CLI binary $(CLI_BIN) not found — app will locate it via PATH / \$$SENSOR_LENS_BIN at runtime"; \
	fi
	@if [ -f "$(ICON_SRC)" ]; then \
		scripts/make-icns.sh "$(ICON_SRC)" $(APP_BUNDLE)/Contents/Resources/AppIcon.icns; \
	else \
		echo "[icon] WARN: $(ICON_SRC) not found — building without an app icon"; \
	fi
	@$(CODESIGN_SCRIPT) $(APP_BUNDLE) "$(CODESIGN_IDENTITY)"
	@echo "Built $(APP_BUNDLE) ($(VERSION))"

## package: build-app, notarize + staple the .app, then zip for release
package: build-app
	@$(NOTARIZE_SCRIPT) $(APP_BUNDLE) "$(NOTARY_PROFILE)"
	@cd $(DIST_DIR) && /usr/bin/ditto -c -k --keepParent $(APP_NAME).app $(NAME)-$(VERSION)-darwin-arm64.zip
	@ls -la $(DIST_DIR)/$(NAME)-$(VERSION)-darwin-arm64.zip

## verify-release: refuse to release an un-notarized build (marker + staple gate)
verify-release:
	@test -f "$(APP_BUNDLE).notarized" || { \
		echo "verify-release: FAIL — $(APP_BUNDLE) has no notarization marker."; \
		echo "  make package must end with '[notarize-app] ...: Accepted and stapled'. Do not upload."; \
		exit 1; }
	@xcrun stapler validate $(APP_BUNDLE)
	@test -f "$(DIST_DIR)/$(NAME)-$(VERSION)-darwin-arm64.zip" || { \
		echo "verify-release: FAIL — release zip missing: $(DIST_DIR)/$(NAME)-$(VERSION)-darwin-arm64.zip"; exit 1; }
	@echo "verify-release: OK ($(VERSION) — marker present, ticket stapled)"

## test: run tests
test:
	swift test

## run: build and run (debug)
run:
	swift run

## clean: remove build artifacts
clean:
	rm -rf $(DIST_DIR) .build
