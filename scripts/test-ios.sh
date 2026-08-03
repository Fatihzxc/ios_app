#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

xcodebuild_test_arguments=(
    test
    -project HealthTrackingApp.xcodeproj
    -scheme HealthTrackingApp-Local
)

if (( $# > 0 )); then
    if (( $# != 2 )) || [[ "$1" != "--only-testing" ]] || [[ -z "$2" ]]; then
        echo "Usage: $0 [--only-testing TestBundleName]" >&2
        exit 2
    fi
    xcodebuild_test_arguments+=("-only-testing:$2")
fi

"$script_dir/bootstrap.sh"
destination="$("$script_dir/select-simulator.sh")"
result_bundle_path="$repo_root/.build/HealthTrackingApp.xcresult"

mkdir -p "$(dirname "$result_bundle_path")"
rm -rf -- "$result_bundle_path"

xcodebuild "${xcodebuild_test_arguments[@]}" \
    -destination "$destination" \
    -resultBundlePath "$result_bundle_path" \
    CODE_SIGNING_ALLOWED=NO

xcodebuild build \
    -project HealthTrackingApp.xcodeproj \
    -scheme HealthTrackingApp-Local \
    -configuration Release \
    -destination "$destination" \
    CODE_SIGNING_ALLOWED=NO
