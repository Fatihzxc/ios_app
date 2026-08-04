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
cloud_compile_only=false

if (( $# > 0 )); then
    case "$1" in
        --only-testing)
            if (( $# != 2 )) || [[ -z "$2" ]]; then
                echo "Usage: $0 [--only-testing TestBundleName|--cloud-compile-only]" >&2
                exit 2
            fi
            xcodebuild_test_arguments+=("-only-testing:$2")
            ;;
        --cloud-compile-only)
            if (( $# != 1 )); then
                echo "Usage: $0 [--only-testing TestBundleName|--cloud-compile-only]" >&2
                exit 2
            fi
            cloud_compile_only=true
            ;;
        *)
            echo "Usage: $0 [--only-testing TestBundleName|--cloud-compile-only]" >&2
            exit 2
            ;;
    esac
fi

"$script_dir/bootstrap.sh"
destination="$("$script_dir/select-simulator.sh")"

if [[ "$cloud_compile_only" == true ]]; then
    echo "Cloud scheme compile-only: signing disabled; this does not validate CloudKit sync."
    xcodebuild build \
        -project HealthTrackingApp.xcodeproj \
        -scheme HealthTrackingApp-Cloud \
        -configuration "Cloud Debug" \
        -destination "$destination" \
        CODE_SIGNING_ALLOWED=NO
    exit 0
fi

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
