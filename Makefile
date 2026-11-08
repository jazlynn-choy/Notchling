.PHONY: build test app run lint format clean

build:          ## Debug build
	swift build

test:           ## Run unit tests
	scripts/test.sh

app:            ## Release build wrapped in build/Notchling.app
	scripts/bundle.sh

run: app        ## Build the app and (re)launch it
	-pkill -x Notchling
	open build/Notchling.app

lint:           ## SwiftLint, warnings are errors
	swiftlint lint --strict

format:         ## Auto-fix what SwiftLint can
	swiftlint lint --fix

clean:
	rm -rf .build build
