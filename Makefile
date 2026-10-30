# sView build entry points. Every command a session needs is a target here.

VERSION := $(shell cat VERSION)
BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
PREFIX ?= $(HOME)/.local
CLT := /Library/Developer/CommandLineTools

# Use Xcode when it is usable (licence accepted), else fall back to the
# Command Line Tools, whose Swift Testing macros need an explicit plugin path.
XCODE_OK := $(shell xcrun swift --version >/dev/null 2>&1 && echo yes)
ifeq ($(XCODE_OK),yes)
SWIFT := swift
TEST_FLAGS :=
else
SWIFT := DEVELOPER_DIR=$(CLT) swift
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc $(CLT)/usr/lib/swift/host/plugins/testing
endif
XCODEGEN := $(shell command -v xcodegen 2>/dev/null)

.PHONY: gen build app run test test-common coverage smoke bench hostile idle fixtures icon cheatsheet release notarize cask screenshots install clean version

gen:
	@test -n "$(XCODEGEN)" || { echo "xcodegen missing: brew install xcodegen"; exit 1; }
	xcodegen generate

build:
	$(SWIFT) build

# swift test does not run a dependency's tests, so the shared code's run first
# when it is checked out beside this repository.
test: test-common
	$(SWIFT) test $(TEST_FLAGS)

test-common:
	@if [ -f ../scommon/Package.swift ]; then $(MAKE) -C ../scommon test; else echo "test-common: no ../scommon, its tests run in its own repository"; fi

coverage:
	$(SWIFT) test $(TEST_FLAGS) --enable-code-coverage
	scripts/coverage.sh

# Xcode path when Xcode and XcodeGen are both usable, otherwise an SPM build
# wrapped into a bundle by scripts/bundle.sh. Both produce build/sView.app.
app:
ifeq ($(XCODE_OK)$(if $(XCODEGEN),yes,),yesyes)
	xcodegen generate
	xcodebuild -project sView.xcodeproj -scheme sView -configuration Debug \
		-destination "platform=macOS,arch=$(shell uname -m)" \
		-derivedDataPath build/DerivedData \
		MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) build
	rm -rf build/sView.app
	cp -R build/DerivedData/Build/Products/Debug/sView.app build/sView.app
else
	SWIFT="$(SWIFT)" VERSION=$(VERSION) BUILD_NUMBER=$(BUILD_NUMBER) scripts/bundle.sh
endif

run: app
	open -n build/sView.app --args "$(CURDIR)/fixtures/sample"

smoke: app
	scripts/smoke.sh

bench: app
	scripts/bench.sh

hostile: app
	scripts/hostile.sh

idle: app
	scripts/idle.sh

fixtures:
	rm -rf fixtures/sample fixtures/poc
	xcrun swift scripts/make-fixtures.swift fixtures

icon:
	xcrun swift scripts/make-icon.swift build/AppIcon.iconset brand/sview-1024.png
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

cheatsheet:
	$(SWIFT) run -q sview-cheatsheet > docs/keys.md

release:
	scripts/release.sh

notarize:
	scripts/notarize.sh

cask:
	scripts/cask.sh

screenshots: app
	scripts/screenshots.sh

install:
	mkdir -p "$(PREFIX)/bin"
	ln -sf "$(CURDIR)/scripts/sview" "$(PREFIX)/bin/sview"
	@echo "installed $(PREFIX)/bin/sview"

clean:
	rm -rf .build build sView.xcodeproj

version:
	@echo $(VERSION)
