# Dormer — build tasks. Requires Xcode 16 or later (tested with Xcode 27.2).
#   make build   Debug build of Dormer.app
#   make run     Build and open the app
#   make test    Unit tests (DormerCore, WineManager, BottleManager)
#   make integration NPP=<installer.exe>   End-to-end with real Wine (downloads ~230 MB)
#   make lint    swift-format lint + SwiftLint (if installed)
#   make format  Apply swift-format in place
#   make icon    Re-render the app icon from Tools/make-icon.swift

PROJECT      := Dormer.xcodeproj
SCHEME       := Dormer
PACKAGE      := Packages/DormerKit
DERIVED      := build/DerivedData
APP          := $(DERIVED)/Build/Products/Debug/Dormer.app
FORMAT_PATHS := App $(PACKAGE)/Sources $(PACKAGE)/Tests $(PACKAGE)/Package.swift
ICONSET      := App/Assets.xcassets/AppIcon.appiconset

.PHONY: build run test integration lint format icon clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) build

run: build
	open "$(APP)"

test:
	swift test --package-path $(PACKAGE)

# Uses a fresh folder under $TMPDIR, never ~/Library/Application Support/Dormer.
integration:
	@test -n "$(NPP)" || { echo "usage: make integration NPP=/path/to/npp.x.y.z.Installer.x64.exe"; exit 1; }
	@root=$$(mktemp -d -t dormer-integration); echo "Scratch folder: $$root"; \
	DORMER_INTEGRATION_ROOT=$$root DORMER_NPP_INSTALLER="$(NPP)" \
		swift test --package-path $(PACKAGE) --filter WineIntegrationTests

lint:
	swift format lint --strict --recursive --configuration .swift-format $(FORMAT_PATHS)
	@if command -v swiftlint >/dev/null; then swiftlint lint --strict; \
	else echo "swiftlint not installed (brew install swiftlint); skipping"; fi

format:
	swift format --in-place --recursive --configuration .swift-format $(FORMAT_PATHS)

icon:
	@tmp=$$(mktemp -d); swift Tools/make-icon.swift $$tmp/icon.png; \
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s $$tmp/icon.png --out $(ICONSET)/icon_$$s.png >/dev/null; \
		sips -z $$((s*2)) $$((s*2)) $$tmp/icon.png --out $(ICONSET)/icon_$$s@2x.png >/dev/null; \
	done; rm -rf $$tmp; echo "Icon updated"

clean:
	rm -rf build $(PACKAGE)/.build
