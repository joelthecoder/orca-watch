.PHONY: check test lint format build install app signed-app install-widget icons previews clean

INSTALL_DIR ?= $(HOME)/.local/bin
TEAM_ID ?=

check: test lint
	python3 scripts/test-terminal.py

test:
	swift test

lint:
	xcrun swift-format lint --strict --recursive Sources Tests App Widget Shared Package.swift
	swift build -Xswiftc -warnings-as-errors
	git diff --check

format:
	xcrun swift-format format --in-place --recursive Sources Tests App Widget Shared Package.swift

build:
	swift build -c release

install: build
	install -d "$(INSTALL_DIR)"
	install .build/release/orca-watch "$(INSTALL_DIR)/orca-watch"

icons:
	sh scripts/export-icons.sh

app:
	xcodegen generate
	xcodebuild -project OrcaWatch.xcodeproj -scheme OrcaWatch -configuration Debug -derivedDataPath .build-app/DerivedData CODE_SIGNING_ALLOWED=NO build

signed-app:
	test -n "$(TEAM_ID)" || (echo 'Set TEAM_ID to your Apple development team ID.'; exit 1)
	xcodegen generate
	xcodebuild -project OrcaWatch.xcodeproj -scheme OrcaWatch -configuration Debug -derivedDataPath .build-app/SignedData DEVELOPMENT_TEAM="$(TEAM_ID)" build

install-widget: signed-app install
	mkdir -p "$(HOME)/Applications"
	"$(INSTALL_DIR)/orca-watch" widget stop
	ditto ".build-app/SignedData/Build/Products/Debug/Orca Watch.app" "$(HOME)/Applications/Orca Watch.app"
	"$(INSTALL_DIR)/orca-watch" widget start

previews: app
	".build-app/DerivedData/Build/Products/Debug/Orca Watch.app/Contents/MacOS/Orca Watch" --render-previews .build-app/previews

clean:
	rm -rf .build .build-app OrcaWatch.xcodeproj
