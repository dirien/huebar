# HueBar developer tasks. Run `make` to list them.
#
# Tools: Swift 6 toolchain (Xcode 16+ or its Command Line Tools), which includes `swift format`,
# and SwiftLint (`brew install swiftlint`).

SWIFT ?= swift
SWIFT_FORMAT ?= $(SWIFT) format
SWIFTLINT ?= swiftlint
LINT_PATHS := Sources Tests Package.swift
# Release version: the latest v* tag without the "v", or 0.0.0 before the first release.
VERSION ?= $(patsubst v%,%,$(shell git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo v0.0.0))

.DEFAULT_GOAL := help
.PHONY: help build test app install dmg run lint format fix check icons app-icon social-preview clean tools

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Debug build
	$(SWIFT) build

test: ## Run the unit tests
	$(SWIFT) test

app: ## Build build/HueBar.app (set SIGN_IDENTITY to sign with a stable identity)
	VERSION=$(VERSION) ./build.sh

install: ## Build, copy to /Applications and launch
	VERSION=$(VERSION) ./build.sh --install

dmg: ## Universal release build packaged as build/HueBar-<version>.dmg and .zip
	UNIVERSAL=1 VERSION=$(VERSION) ./build.sh
	VERSION=$(VERSION) Scripts/package.sh

run: ## Run from the build directory without installing
	$(SWIFT) run

lint: tools ## Check formatting and lint rules without changing files
	$(SWIFT_FORMAT) lint --strict --recursive --parallel $(LINT_PATHS)
	$(SWIFTLINT) lint --strict --quiet

format: tools ## Reformat sources with swift-format
	$(SWIFT_FORMAT) format --in-place --recursive --parallel $(LINT_PATHS)

fix: format ## Format, apply SwiftLint auto-corrections, then report what's left
	$(SWIFTLINT) lint --fix --quiet
	$(SWIFTLINT) lint --strict --quiet

check: lint build test ## Everything CI should run

icons: ## Regenerate Sources/HueBar/Icons/PhosphorIcons.swift from Phosphor
	python3 Scripts/generate-phosphor-icons.py

app-icon: ## Regenerate Resources/AppIcon.icns from assets/logo.svg (needs librsvg)
	Scripts/generate-app-icon.sh

social-preview: ## Regenerate assets/social-preview.png (needs librsvg and the Inter font)
	python3 Scripts/generate-social-preview.py

clean: ## Remove build products
	rm -rf .build build

tools:
	@$(SWIFT_FORMAT) --version >/dev/null 2>&1 || { \
		echo "swift-format not found: install Xcode 16+ or a Swift 6 toolchain."; exit 1; }
	@command -v $(SWIFTLINT) >/dev/null 2>&1 || { \
		echo "SwiftLint not found: brew install swiftlint"; exit 1; }
