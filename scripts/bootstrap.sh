#!/usr/bin/env bash
set -euo pipefail

required_version="2.46.0"

version_at_least() {
    local actual="$1"
    local required="$2"
    local actual_major actual_minor actual_patch required_major required_minor required_patch

    IFS=. read -r actual_major actual_minor actual_patch <<< "$actual"
    IFS=. read -r required_major required_minor required_patch <<< "$required"
    actual_minor="${actual_minor:-0}"
    actual_patch="${actual_patch:-0}"
    required_minor="${required_minor:-0}"
    required_patch="${required_patch:-0}"

    (( actual_major > required_major )) ||
        (( actual_major == required_major && actual_minor > required_minor )) ||
        (( actual_major == required_major && actual_minor == required_minor && actual_patch >= required_patch ))
}

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen ${required_version} or newer is required." >&2
    exit 1
fi

xcodegen_version_output="$(xcodegen --version)"
xcodegen_version="$(printf '%s\n' "$xcodegen_version_output" | grep -Eo '[0-9]+(\.[0-9]+){1,2}' | head -n 1)"
if [[ -z "$xcodegen_version" ]] || ! version_at_least "$xcodegen_version" "$required_version"; then
    echo "xcodegen ${required_version} or newer is required; found: ${xcodegen_version_output}" >&2
    exit 1
fi

xcodegen generate --spec project.yml
xcodebuild -list -project HealthTrackingApp.xcodeproj
