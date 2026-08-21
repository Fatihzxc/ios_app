#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

scan_swift() {
    local pattern="$1"
    shift

    local file
    local match
    while IFS= read -r -d '' file; do
        while IFS= read -r match; do
            printf '%s:%s\n' "$file" "$match"
        done < <(grep -nE "$pattern" "$file" || true)
    done < <(find "$@" -type f -name '*.swift' -print0)
}

verify_generator_boundary() {
    local target_root="$1"
    local adapter="$target_root/App/Platform/UIKitTrainingHapticClient.swift"
    local production_roots=(
        "$target_root/App"
        "$target_root/Packages/HealthTrackingModules/Sources"
    )

    if [[ ! -f "$adapter" ]]; then
        echo "Missing UIKit haptic adapter: App/Platform/UIKitTrainingHapticClient.swift" >&2
        return 1
    fi

    local generator
    for generator in UIImpactFeedbackGenerator UISelectionFeedbackGenerator UINotificationFeedbackGenerator; do
        if ! grep -Fq "$generator" "$adapter"; then
            echo "UIKit haptic adapter must own $generator." >&2
            return 1
        fi
    done

    local finding
    while IFS= read -r finding; do
        [[ -z "$finding" ]] && continue
        if [[ "$finding" != "$adapter:"* ]]; then
            echo "Direct UIKit feedback generator outside the live adapter: $finding" >&2
            return 1
        fi
    done < <(scan_swift \
        'UIImpactFeedbackGenerator|UISelectionFeedbackGenerator|UINotificationFeedbackGenerator' \
        "${production_roots[@]}")

    local training_kit_uikit_imports
    training_kit_uikit_imports="$(scan_swift \
        '^[[:space:]]*import[[:space:]]+UIKit[[:space:]]*$' \
        "$target_root/Packages/HealthTrackingModules/Sources/TrainingKit")"
    if [[ -n "$training_kit_uikit_imports" ]]; then
        echo "TrainingKit must remain independent of UIKit." >&2
        return 1
    fi
}

require_fixed() {
    local file="$1"
    local value="$2"
    local message="$3"
    if ! grep -Fq "$value" "$file"; then
        echo "$message" >&2
        return 1
    fi
}

verify_repo() {
    local target_root="$1"
    verify_generator_boundary "$target_root"

    local session="$target_root/Packages/HealthTrackingModules/Sources/TrainingKit/Session/SessionViewModel.swift"
    local phase="$target_root/Packages/HealthTrackingModules/Sources/TrainingKit/Phase/PhaseTransitionViewModel.swift"
    local dependencies="$target_root/App/Application/AppDependencies.swift"
    local settings="$target_root/Packages/HealthTrackingModules/Sources/SettingsKit/Foundation/SettingsFoundationView.swift"
    local preference_store="$target_root/Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataTrainingHapticPreferenceStore.swift"

    for event in setSaved stepperChanged personalRecord safetyStop deload validationError repositoryError; do
        require_fixed "$session" ".$event" "SessionViewModel must emit the .$event semantic haptic event."
    done
    require_fixed "$phase" '.phaseTransition(isConfirmed: isConfirmed)' \
        "PhaseTransitionViewModel must distinguish confirmed and manual phase changes."
    require_fixed "$dependencies" 'haptics: hapticController' \
        "App composition must inject one haptic controller into training view models."
    require_fixed "$dependencies" 'hapticController.loadPreference()' \
        "App composition must load the persisted haptic preference."
    require_fixed "$settings" 'accessibilityIdentifier("settings.haptics-toggle")' \
        "Settings must expose the persisted haptic kill switch."
    require_fixed "$preference_store" 'public static let key = "haptics.enabled"' \
        "The versioned haptic preference must use the documented AppSetting key."

    echo "Training haptic verification passed."
}

self_test() {
    local fixture
    fixture="$(mktemp -d)"
    trap "rm -rf -- '$fixture'" EXIT
    mkdir -p \
        "$fixture/App/Platform" \
        "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit"
    printf '%s\n' \
        'let impact = UIImpactFeedbackGenerator()' \
        'let selection = UISelectionFeedbackGenerator()' \
        'let notification = UINotificationFeedbackGenerator()' \
        > "$fixture/App/Platform/UIKitTrainingHapticClient.swift"

    verify_generator_boundary "$fixture"

    printf '%s\n' 'let bypass = UIImpactFeedbackGenerator()' \
        > "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Bypass.swift"
    if verify_generator_boundary "$fixture" >"$fixture/bypass.out" 2>&1; then
        echo "Haptic self-test expected a direct-generator bypass failure." >&2
        return 1
    fi
    grep -Fq 'Direct UIKit feedback generator outside the live adapter' "$fixture/bypass.out"
    echo "Training haptic verifier self-tests passed."
}

case "${1:-}" in
    "") verify_repo "$repo_root" ;;
    --self-test) self_test ;;
    *) echo "Usage: $0 [--self-test]" >&2; exit 2 ;;
esac
