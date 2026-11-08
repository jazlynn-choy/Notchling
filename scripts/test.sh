#!/bin/zsh
# Runs the unit tests.
#
# With only the Command Line Tools installed (no Xcode), SwiftPM sometimes fails to load the
# Swift Testing macro plugin ("plugin for module 'TestingMacros' not found") at random.
# That's a toolchain bug, not a test failure, so retry on that exact error only.
# Real test failures are never retried.
set -u
cd "$(dirname "$0")/.."
log=$(mktemp)
for attempt in 1 2 3 4 5; do
    swift test "$@" 2>&1 | tee "$log" | grep -vE "^(\[|Compiling|Building|Write|Emitting|Linking|Planning)"
    test_status=${pipestatus[1]}
    if [[ $test_status -eq 0 ]]; then rm -f "$log"; exit 0; fi
    if ! grep -q "plugin for module 'TestingMacros' not found" "$log"; then rm -f "$log"; exit $test_status; fi
    echo "↻ Swift Testing macro plugin failed to load (toolchain bug), retrying ($attempt/5)…"
done
rm -f "$log"
exit 1
