#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

verify_repo() {
    local target_root="$1"
    python3 - "$target_root" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
root_view = root / "App/Application/AppRootView.swift"
view_model = root / "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayViewModel.swift"
today_view = root / "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift"
repository = root / "Packages/HealthTrackingModules/Sources/TrainingKit/Repository/TrainingRepository.swift"
scenarios = root / "App/Support/AppUITestLaunchConfiguration.swift"

required_files = [root_view, view_model, today_view, repository, scenarios]
missing_files = [str(path.relative_to(root)) for path in required_files if not path.is_file()]
if missing_files:
    raise SystemExit(f"Missing Today production files: {missing_files}")

swift_sources = list((root / "App").rglob("*.swift")) + list(
    (root / "Packages/HealthTrackingModules/Sources").rglob("*.swift")
)
source_text = "\n".join(path.read_text(encoding="utf-8") for path in swift_sources)
if (root / "App/Application/FoundationTodayView.swift").exists():
    raise SystemExit("FoundationTodayView.swift must be removed after the real Today route ships.")
if "FoundationTodayView" in source_text:
    raise SystemExit("Production code must not reference the retired FoundationTodayView.")
if "today.soon" in source_text:
    raise SystemExit("Production code must not retain the placeholder today.soon route.")

root_text = root_view.read_text(encoding="utf-8")
if "case .today:" not in root_text or "TodayView(" not in root_text:
    raise SystemExit("AppRootView must route the Today tab through TodayView.")
if "todayViewModel" not in root_text:
    raise SystemExit("AppRootView must receive the composed TodayViewModel.")

view_model_text = view_model.read_text(encoding="utf-8")
snapshot_call = "repository.fetchTodaySnapshot()"
if view_model_text.count(snapshot_call) != 1:
    raise SystemExit("TodayViewModel must perform exactly one compact snapshot call per load path.")
if "func fetchTodaySnapshot()" not in repository.read_text(encoding="utf-8"):
    raise SystemExit("TrainingRepository must expose the compact Today snapshot contract.")

today_text = today_view.read_text(encoding="utf-8")
required_identifiers = {
    "root.today.content",
    "today.phase",
    "today.directive.context",
    "today.action.primary",
    "today.state.loading",
    "today.state.empty",
    "today.state.error",
    "today.performance.firstMeaningful",
    "today.protein.consumed",
    "today.protein.progress",
    "today.nutrition.action",
}
missing_identifiers = sorted(identifier for identifier in required_identifiers if identifier not in today_text)
if missing_identifiers:
    raise SystemExit(f"TodayView is missing accessibility contracts: {missing_identifiers}")

training_sources = list(
    (root / "Packages/HealthTrackingModules/Sources/TrainingKit").rglob("*.swift")
)
nutrition_sources = list(
    (root / "Packages/HealthTrackingModules/Sources/NutritionKit").rglob("*.swift")
)
if any("import NutritionKit" in path.read_text(encoding="utf-8") for path in training_sources):
    raise SystemExit("TrainingKit must not import NutritionKit for Today composition.")
if any("import TrainingKit" in path.read_text(encoding="utf-8") for path in nutrition_sources):
    raise SystemExit("NutritionKit must not import TrainingKit for Today composition.")

scenario_text = scenarios.read_text(encoding="utf-8")
required_scenarios = {
    "today-train", "today-rest", "today-resume", "today-deload", "today-phase",
    "today-reminder", "today-priority", "today-empty-once", "today-error-once",
}
missing_scenarios = sorted(value for value in required_scenarios if value not in scenario_text)
if missing_scenarios:
    raise SystemExit(f"Missing deterministic Today scenarios: {missing_scenarios}")

print("Today route verification passed.")
PY
}

self_test() {
    self_test_fixture="$(mktemp -d)"
    trap 'rm -rf -- "$self_test_fixture"' EXIT
    local fixture="$self_test_fixture"
    mkdir -p \
        "$fixture/App/Application" \
        "$fixture/App/Support" \
        "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today" \
        "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Repository"
    printf '%s\n' 'case .today: TodayView(todayViewModel)' 'let todayViewModel = value' > "$fixture/App/Application/AppRootView.swift"
    printf '%s\n' 'repository.fetchTodaySnapshot()' > "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayViewModel.swift"
    printf '%s\n' \
        'root.today.content today.phase today.directive.context today.action.primary' \
        'today.state.loading today.state.empty today.state.error today.performance.firstMeaningful' \
        'today.protein.consumed today.protein.progress today.nutrition.action' \
        > "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift"
    printf '%s\n' 'func fetchTodaySnapshot() {}' > "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Repository/TrainingRepository.swift"
    printf '%s\n' \
        'today-train today-rest today-resume today-deload today-phase' \
        'today-reminder today-priority today-empty-once today-error-once' \
        > "$fixture/App/Support/AppUITestLaunchConfiguration.swift"
    verify_repo "$fixture"

    printf '%s\n' 'struct FoundationTodayView {}' > "$fixture/App/Application/FoundationTodayView.swift"
    if verify_repo "$fixture" >"$fixture/retired.out" 2>&1; then
        echo "Today verifier self-test expected the retired route to fail." >&2
        return 1
    fi
    grep -Fq "FoundationTodayView.swift must be removed" "$fixture/retired.out"
    rm "$fixture/App/Application/FoundationTodayView.swift"

    printf '%s\n' 'repository.fetchTodaySnapshot()' 'repository.fetchTodaySnapshot()' > "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayViewModel.swift"
    if verify_repo "$fixture" >"$fixture/double-fetch.out" 2>&1; then
        echo "Today verifier self-test expected duplicate snapshot calls to fail." >&2
        return 1
    fi
    grep -Fq "exactly one compact snapshot call" "$fixture/double-fetch.out"

    printf '%s\n' \
        'root.today.content today.phase today.directive.context today.action.primary' \
        'today.state.loading today.state.empty today.state.error today.performance.firstMeaningful' \
        'today.protein.consumed today.protein.progress' \
        > "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift"
    printf '%s\n' 'repository.fetchTodaySnapshot()' > "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayViewModel.swift"
    if verify_repo "$fixture" >"$fixture/missing-nutrition.out" 2>&1; then
        echo "Today verifier self-test expected a missing M2 nutrition contract to fail." >&2
        return 1
    fi
    grep -Fq "today.nutrition.action" "$fixture/missing-nutrition.out"

    printf '%s\n' \
        'root.today.content today.phase today.directive.context today.action.primary' \
        'today.state.loading today.state.empty today.state.error today.performance.firstMeaningful' \
        'today.protein.consumed today.protein.progress today.nutrition.action' \
        > "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift"
    printf '%s\n' 'import NutritionKit' > "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/ForbiddenImport.swift"
    if verify_repo "$fixture" >"$fixture/import-boundary.out" 2>&1; then
        echo "Today verifier self-test expected a cross-feature import to fail." >&2
        return 1
    fi
    grep -Fq "TrainingKit must not import NutritionKit" "$fixture/import-boundary.out"
    echo "Today verifier self-tests passed."
}

case "${1:-}" in
    "") verify_repo "$repo_root" ;;
    --self-test) self_test ;;
    *) echo "Usage: $0 [--self-test]" >&2; exit 2 ;;
esac
