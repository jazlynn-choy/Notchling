.PHONY: build test app run lint format clean demo

build:          ## Debug build
	swift build

test:           ## Run unit tests
	scripts/test.sh

app:            ## Release build wrapped in build/Notchling.app
	scripts/bundle.sh

run: app        ## Build the app and (re)launch it
	-pkill -x Notchling
	@while pgrep -x Notchling >/dev/null; do sleep 0.1; done   # wait so open doesn't race the quit
	open build/Notchling.app

demo:           ## Re-render docs/demo.gif and docs/screenshot.png from the real views
	swift run -c release NotchlingDemo docs/demo.gif

# SwiftLint needs SourceKit, which ships with Xcode; with only the Command Line Tools it's here instead.
CLT_SOURCEKIT := /Library/Developer/CommandLineTools/usr/lib
LINT_ENV := $(if $(wildcard /Applications/Xcode.app),,DYLD_FRAMEWORK_PATH=$(CLT_SOURCEKIT))

lint:           ## SwiftLint, warnings are errors
	$(LINT_ENV) swiftlint lint --strict

format:         ## Auto-fix what SwiftLint can
	swiftlint lint --fix

clean:
	rm -rf .build build
