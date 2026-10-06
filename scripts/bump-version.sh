#!/usr/bin/env bash
# Bump Odysseus's marketing version and build number across the
# Xcode project. agvtool handles CFBundleVersion / CURRENT_PROJECT_VERSION,
# and a sed pass updates MARKETING_VERSION (the project doesn't have
# CFBundleShortVersionString hard-coded in Info.plist -- it inherits
# the build setting).
#
# Usage:
#   scripts/bump-version.sh 1.1.0           # marketing=1.1.0, auto-increment build
#   scripts/bump-version.sh 1.1.0 7         # marketing=1.1.0, build=7
#   scripts/bump-version.sh --show          # print current values

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="odysseus.xcodeproj/project.pbxproj"

current_marketing() {
    grep -m1 "MARKETING_VERSION" "$PROJECT" | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' | tr -d ' '
}

current_build() {
    xcrun agvtool what-version -terse 2>/dev/null | tail -1 | tr -d ' '
}

show() {
    echo "Marketing: $(current_marketing)"
    echo "Build:     $(current_build)"
}

case "${1:-}" in
    ""|--show|-h|--help)
        show
        if [[ "${1:-}" == "" ]]; then
            echo "Pass a marketing version (e.g. 1.1.0) to bump." >&2
        fi
        exit 0
        ;;
esac

NEW_MARKETING="$1"
NEW_BUILD="${2:-}"

if [[ ! "$NEW_MARKETING" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: marketing version must look like X.Y.Z (got: $NEW_MARKETING)" >&2
    exit 64
fi

if [[ -z "$NEW_BUILD" ]]; then
    NEW_BUILD=$(( $(current_build) + 1 ))
fi

if [[ ! "$NEW_BUILD" =~ ^[0-9]+$ ]]; then
    echo "ERROR: build number must be a positive integer (got: $NEW_BUILD)" >&2
    exit 64
fi

echo "Bumping marketing $(current_marketing) -> ${NEW_MARKETING}"
echo "Bumping build     $(current_build) -> ${NEW_BUILD}"

# MARKETING_VERSION lives in build settings, not Info.plist. Update every
# occurrence (main app, widget extension, test target -- they're kept in sync).
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${NEW_MARKETING};/g" "$PROJECT"

# CFBundleVersion / CURRENT_PROJECT_VERSION handled by agvtool.
xcrun agvtool new-version -all "${NEW_BUILD}" >/dev/null

echo "Done."
show
