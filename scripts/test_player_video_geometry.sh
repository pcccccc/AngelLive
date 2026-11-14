#!/bin/sh
set -eu
repo_root=$(git rev-parse --show-toplevel)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/player-geometry-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 6 \
    -module-cache-path "$test_dir/module-cache" \
    "$repo_root/iOS/AngelLive/AngelLive/FullUI/Views/Player/PlayerVideoGeometry.swift" \
    "$repo_root/scripts/tests/PlayerVideoGeometryTests.swift" \
    -o "$test_dir/geometry-tests"
"$test_dir/geometry-tests"
