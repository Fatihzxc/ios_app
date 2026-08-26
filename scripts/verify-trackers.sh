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

required_tests = {
    "Packages/HealthTrackingModules/Tests/DesignSystemTests/QuickEntryMutationStateMachineTests.swift": {
        "QuickEntryMutationStateMachine",
        "requestID",
        "generation",
        "retrySave",
        "retryUndo",
        "completeSave",
        "completeUndo",
        "stale",
    },
    "Packages/HealthTrackingModules/Tests/DesignSystemTests/QuickEntryLayoutContractTests.swift": {
        "QuickEntryValidationIssue",
        "QuickEntryFormContract",
        "QuickEntryFormScaffold",
        "minimumActionHeight, 52",
        "quick-entry.keyboard.dismiss",
        "actionLayout(isAccessibilitySize: true)",
        "AppMotion.transition(reduceMotion: true)",
    },
}

for relative_path, tokens in required_tests.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.1 test file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.1 RED contracts: {absent}")

required_production = {
    "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryMutationStateMachine.swift": {
        "QuickEntryMutationAttempt",
        "QuickEntryMutationStateMachine",
        "generation += 1",
        "attempt == currentAttempt",
        "retrySave",
        "retryUndo",
        "expireUndo",
    },
    "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryValidationIssue.swift": {
        "QuickEntryValidationIssue",
        "fieldIdentifier",
        "localizedMessage",
        "accessibilityAnnouncement",
    },
    "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryFormScaffold.swift": {
        "QuickEntryFormScaffold",
        "minimumActionHeight: CGFloat = 52",
        "scrollDismissesKeyboard(.interactively)",
        "quick-entry.keyboard.dismiss",
        "accessibilityReduceMotion",
        "AppMotion.transition(reduceMotion:",
    },
}

for relative_path, tokens in required_production.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.1 production file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.1 production contracts: {absent}")

support = {
    "scripts/test-ios.sh": {
        '"$script_dir/verify-trackers.sh" --self-test',
        '"$script_dir/verify-trackers.sh"',
    },
    ".github/workflows/ios.yml": {
        "scripts/verify-trackers.sh --self-test",
        "scripts/verify-trackers.sh",
        "--only-testing MetricsKitTests",
    },
    "project.yml": {
        "HealthTrackingModules/DesignSystemTests",
    },
    "Packages/HealthTrackingModules/Sources/DesignSystem/Resources/Localizable.xcstrings": {
        "designSystem.quick-entry.keyboard.dismiss",
        "Klavyeyi kapat",
    },
}

for relative_path, tokens in support.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.1 support file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.1 gate wiring: {absent}")

m32_tests = {
    "Packages/HealthTrackingModules/Tests/MetricsKitTests/BodyMetricInputTests.swift": {
        "BodyMetricValueInput",
        "BodyMetricBatchInput",
        "invalidCanonicalUnit",
        "emptyBatch",
        "unexpectedBatchMetricType",
        "BodyMetricUnitConverter",
        "BodyMetricOrdering.newestFirst",
    },
    "Packages/HealthTrackingModules/Tests/MetricsKitTests/BodyMetricViewModelTests.swift": {
        "BodyMetricViewModel",
        "saveFailed",
        "retrySave",
        "retryFailedMutation",
        "prepareForCreation",
        "testDuplicateSaveWhileInFlightCannotReplaceThePendingRetryBatch",
        "undoLastSave",
        "expectedUpdatedAt",
    },
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/BodyMetricRepositoryTests.swift": {
        "SwiftDataMetricsRepository",
        "createBodyMetrics",
        "updateBodyMetric",
        "deleteBodyMetric",
        "undoBodyMetricCreation",
        "duplicateBodyMetricIDs",
        "bodyMetricIDCollision",
        "staleBodyMetric",
        "saveFailed",
    },
    "HealthTrackingAppTests/TrackerCompositionTests.swift": {
        "makeTrackerFeatureRouter",
        "factoryCalls",
        "firstRoute === progressRoute",
    },
    "HealthTrackingAppTests/AppBootstrapCompositionTests.swift": {
        "buildDependencies",
        "XCTAssertEqual(constructionAttempts, 1)",
        "XCTAssertEqual(constructionAttempts, 2)",
        "testDefaultDependencyPrewarmerPublishesTodayBeforeAsyncConsumption",
    },
    "Packages/HealthTrackingModules/Tests/TrainingKitTests/TodayViewModelTests.swift": {
        "testApplyingPreloadedSnapshotPublishesContentWithoutRepositoryFetch",
        "applyInitialSnapshot",
        "fetchTodaySnapshotCallCount, 0",
    },
    "HealthTrackingAppUITests/BodyMetricFlowUITests.swift": {
        "today.metrics.action",
        "metrics.entry.save-error",
        "metrics.entry.retry",
        "metrics.row.weight.",
        "m3-metrics-entry-dark",
        "m3-metrics-entry-ax5",
    },
}

for relative_path, tokens in m32_tests.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.2 test file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.2 RED contracts: {absent}")

m32_support = {
    "Packages/HealthTrackingModules/Package.swift": {
        '.library(name: "MetricsKit", targets: ["MetricsKit"])',
        'name: "MetricsKit"',
        'dependencies: ["CoreModels", "DesignSystem"]',
        'dependencies: ["CoreModels", "GuidanceKit", "MetricsKit", "NutritionKit", "TrainingKit"]',
        'name: "MetricsKitTests"',
        'dependencies: ["CoreModels", "MetricsKit", "NutritionKit", "TrainingKit", "PersistenceKit"]',
    },
    "project.yml": {
        "product: MetricsKit",
        "HealthTrackingModules/MetricsKitTests",
    },
    ".github/workflows/ios.yml": {
        "Targeted M3.2 Metrics tests",
        "scripts/test-ios.sh --only-testing MetricsKitTests",
    },
    "Packages/HealthTrackingModules/Sources/MetricsKit/MetricsKitModule.swift": {
        "MetricsKitModuleMarker",
    },
    "Packages/HealthTrackingModules/Sources/MetricsKit/Resources/Localizable.xcstrings": {
        '"sourceLanguage" : "tr"',
    },
}

for relative_path, tokens in m32_support.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.2 support file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.2 wiring: {absent}")

m32_production = {
    "Packages/HealthTrackingModules/Sources/MetricsKit/Domain/BodyMetricDomain.swift": {
        "value.isFinite, value > 0",
        "invalidCanonicalUnit",
        "trimmingCharacters",
        "unexpectedBatchMetricType",
        "BodyMetricOrdering",
        "BodyMetricUnitConverter",
        "BodyMetricCreationUndoToken",
    },
    "Packages/HealthTrackingModules/Sources/MetricsKit/Repository/MetricsRepository.swift": {
        "MetricsRepositoryIntegrityError",
        "duplicateBodyMetricIDs",
        "bodyMetricIDCollision",
        "staleBodyMetric",
        "expectedUpdatedAt",
        "undoBodyMetricCreation",
    },
    "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricViewModel.swift": {
        "QuickEntryMutationStateMachine",
        "pendingBatch",
        "retrySave",
        "generation == loadGeneration",
        "expectedUpdatedAt: snapshot.updatedAt",
        "undoLastSave",
    },
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataMetricsRepository.swift": {
        "let existingIDs = Set",
        "generatedSet.insert(id).inserted",
        "for model in models",
        "rollbackOperation()",
        "duplicateBodyMetricIDs",
        "expectedUpdatedAt",
        "validatedSnapshot",
    },
    "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricEntryView.swift": {
        "QuickEntryFormScaffold",
        "metrics.entry.weight",
        "metrics.entry.waist",
        "metrics.entry.retry",
        "metrics.entry.saved",
        "NumberFormatter",
    },
    "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricProgressView.swift": {
        "root.progress",
        "metrics.history.loaded",
        "metrics.row.",
        "metrics.delete.",
    },
    "App/Application/TrackerFeatureRouting.swift": {
        "protocol TrackerFeatureRouting",
        "makeBodyMetricEntryView",
        "makeProgressView",
        "AnyView",
    },
    "App/Application/TrackerFeatureBundle.swift": {
        "TrackerFeatureBundle",
        "TrackerFeatureRouting",
        "BodyMetricViewModel",
        "repository",
        "DefaultTrackerFeatureFactory",
        "UITestMetricsRepository",
        "makeBodyMetricEntryView",
        "makeProgressView",
        "failsFirstCreate: true",
    },
    "App/Application/AppDependencies.swift": {
        "trackerFeatureBundleFactory",
        "private lazy var trackerFeatureRouter",
        "makeTrackerFeatureRouter",
        "TrackerFeatureRouting",
        "prepareInitialContentForLaunch",
        "SynchronousTodaySnapshotRepository",
        "todayViewModel.state == .loading",
    },
    "Packages/HealthTrackingModules/Sources/TrainingKit/Repository/TrainingRepository.swift": {
        "protocol SynchronousTodaySnapshotRepository",
        "fetchTodaySnapshotSynchronously",
    },
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataTrainingRepository.swift": {
        "SynchronousTodaySnapshotRepository",
        "fetchTodaySnapshotSynchronously",
    },
    "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayViewModel.swift": {
        "applyInitialSnapshot",
        "publish(snapshot, evaluatedAt: date)",
    },
    "App/Application/AppRootView.swift": {
        "onOpenTrackers: performTodayTrackerAction",
        "resolveTrackerFeatureBundle",
        "makeTrackerFeatureRouter",
        "makeBodyMetricEntryView",
        "makeProgressView",
    },
    "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift": {
        "onOpenTrackers",
        "today.metrics.action",
    },
    "App/Support/AppUITestLaunchConfiguration.swift": {
        'case m3BodyMetrics = "m3-body-metrics"',
    },
    "Packages/HealthTrackingModules/Sources/MetricsKit/Resources/Localizable.xcstrings": {
        "metrics.entry.title",
        "metrics.progress.title",
        "metrics.validation.empty",
        "İlerleme",
    },
}

for relative_path, tokens in m32_production.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.2 production file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(
            f"{relative_path} is missing M3.2 production contracts: {absent}"
        )

for source in (root / "Packages/HealthTrackingModules/Sources/MetricsKit").rglob("*.swift"):
    text = source.read_text(encoding="utf-8")
    forbidden = sorted(
        module
        for module in ("SwiftData", "PersistenceKit", "TrainingKit", "UserNotifications", "CloudKit")
        if f"import {module}" in text
    )
    if forbidden:
        relative = source.relative_to(root)
        raise SystemExit(f"{relative} has forbidden feature imports: {forbidden}")

for source in (root / "Packages/HealthTrackingModules/Sources/TrainingKit").rglob("*.swift"):
    if "import MetricsKit" in source.read_text(encoding="utf-8"):
        relative = source.relative_to(root)
        raise SystemExit(f"{relative} must not reverse-import MetricsKit")

body_metric_entry_source = (
    root
    / "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricEntryView.swift"
).read_text(encoding="utf-8")
if '.accessibilityIdentifier("metrics.entry.form")' in body_metric_entry_source:
    raise SystemExit(
        "BodyMetricEntryView must not place an identifier on the field container; "
        "SwiftUI propagates it over the individual text-field identifiers"
    )
if "Task { await viewModel.retryFailedMutation() }" not in body_metric_entry_source:
    raise SystemExit(
        "BodyMetricEntryView must route failed save and undo retries through the ViewModel"
    )
if "viewModel.prepareForCreation()" not in body_metric_entry_source:
    raise SystemExit(
        "BodyMetricEntryView must reset a completed creation lifecycle before reuse"
    )

body_metric_progress_source = (
    root
    / "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricProgressView.swift"
).read_text(encoding="utf-8")
if '.accessibilityIdentifier("root.progress.content")' in body_metric_progress_source:
    raise SystemExit(
        "BodyMetricProgressView must not place an identifier on the state container; "
        "SwiftUI propagates it over row and delete identifiers"
    )

dependencies_source = (root / "App/Application/AppDependencies.swift").read_text(
    encoding="utf-8"
)
if "Result<AppDependencies, Error>" not in dependencies_source:
    raise SystemExit(
        "AppDependencyPrewarmer must finish the initial dependency composition synchronously"
    )
if "PreparedContainer" in dependencies_source:
    raise SystemExit(
        "AppDependencyPrewarmer must not defer dependency composition after container creation"
    )
for forbidden_token in (
    "import MetricsKit",
    "MetricsRepository",
    "-> TrackerFeatureBundle",
    "TrackerFeatureBundle(",
    "BodyMetricViewModel",
    "BodyMetricSnapshot",
    "BodyMetricBatchInput",
):
    if forbidden_token in dependencies_source:
        raise SystemExit(
            "App/Application/AppDependencies.swift must keep the cold-launch "
            f"dependency path type-erased; found {forbidden_token!r}"
        )

root_source = (root / "App/Application/AppRootView.swift").read_text(encoding="utf-8")
for forbidden_token in (
    "import MetricsKit",
    ": TrackerFeatureBundle",
    "-> TrackerFeatureBundle",
):
    if forbidden_token in root_source:
        raise SystemExit(
            "App/Application/AppRootView.swift must keep the cold-launch route "
            f"type-erased; found {forbidden_token!r}"
        )

print("M3 tracker verification passed.")
PY
}

self_test() {
    python3 - "$repo_root" <<'PY'
import subprocess
import sys
import tempfile
from pathlib import Path

repo = Path(sys.argv[1])
script = repo / "scripts/verify-trackers.sh"

fixture_files = {
    "Packages/HealthTrackingModules/Tests/DesignSystemTests/QuickEntryMutationStateMachineTests.swift": " ".join(
        [
            "QuickEntryMutationStateMachine",
            "requestID",
            "generation",
            "retrySave",
            "retryUndo",
            "completeSave",
            "completeUndo",
            "stale",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/DesignSystemTests/QuickEntryLayoutContractTests.swift": " ".join(
        [
            "QuickEntryValidationIssue",
            "QuickEntryFormContract",
            "QuickEntryFormScaffold",
            "minimumActionHeight, 52",
            "quick-entry.keyboard.dismiss",
            "actionLayout(isAccessibilitySize: true)",
            "AppMotion.transition(reduceMotion: true)",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryMutationStateMachine.swift": " ".join(
        [
            "QuickEntryMutationAttempt",
            "QuickEntryMutationStateMachine",
            "generation += 1",
            "attempt == currentAttempt",
            "retrySave",
            "retryUndo",
            "expireUndo",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryValidationIssue.swift": " ".join(
        [
            "QuickEntryValidationIssue",
            "fieldIdentifier",
            "localizedMessage",
            "accessibilityAnnouncement",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryFormScaffold.swift": " ".join(
        [
            "QuickEntryFormScaffold",
            "minimumActionHeight: CGFloat = 52",
            "scrollDismissesKeyboard(.interactively)",
            "quick-entry.keyboard.dismiss",
            "accessibilityReduceMotion",
            "AppMotion.transition(reduceMotion:",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/DesignSystem/Resources/Localizable.xcstrings": " ".join(
        [
            "designSystem.quick-entry.keyboard.dismiss",
            "Klavyeyi kapat",
        ]
    ),
    "scripts/test-ios.sh": '\n'.join(
        [
            '"$script_dir/verify-trackers.sh" --self-test',
            '"$script_dir/verify-trackers.sh"',
        ]
    ),
    ".github/workflows/ios.yml": '\n'.join(
        [
            "scripts/verify-trackers.sh --self-test",
            "scripts/verify-trackers.sh",
            "Targeted M3.2 Metrics tests",
            "scripts/test-ios.sh --only-testing MetricsKitTests",
        ]
    ),
    "project.yml": "\n".join(
        [
            "HealthTrackingModules/DesignSystemTests",
            "product: MetricsKit",
            "HealthTrackingModules/MetricsKitTests",
        ]
    ),
    "Packages/HealthTrackingModules/Package.swift": "\n".join(
        [
            '.library(name: "MetricsKit", targets: ["MetricsKit"])',
            'name: "MetricsKit"',
            'dependencies: ["CoreModels", "DesignSystem"]',
            'dependencies: ["CoreModels", "GuidanceKit", "MetricsKit", "NutritionKit", "TrainingKit"]',
            'name: "MetricsKitTests"',
            'dependencies: ["CoreModels", "MetricsKit", "NutritionKit", "TrainingKit", "PersistenceKit"]',
        ]
    ),
    "Packages/HealthTrackingModules/Sources/MetricsKit/MetricsKitModule.swift": (
        "enum MetricsKitModuleMarker {}"
    ),
    "Packages/HealthTrackingModules/Sources/MetricsKit/Resources/Localizable.xcstrings": (
        '"sourceLanguage" : "tr" metrics.entry.title metrics.progress.title '
        'metrics.validation.empty İlerleme'
    ),
    "Packages/HealthTrackingModules/Tests/MetricsKitTests/BodyMetricInputTests.swift": " ".join(
        [
            "BodyMetricValueInput",
            "BodyMetricBatchInput",
            "invalidCanonicalUnit",
            "emptyBatch",
            "unexpectedBatchMetricType",
            "BodyMetricUnitConverter",
            "BodyMetricOrdering.newestFirst",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/MetricsKitTests/BodyMetricViewModelTests.swift": " ".join(
        [
            "BodyMetricViewModel",
            "saveFailed",
            "retrySave",
            "retryFailedMutation",
            "prepareForCreation",
            "testDuplicateSaveWhileInFlightCannotReplaceThePendingRetryBatch",
            "undoLastSave",
            "expectedUpdatedAt",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/BodyMetricRepositoryTests.swift": " ".join(
        [
            "SwiftDataMetricsRepository",
            "createBodyMetrics",
            "updateBodyMetric",
            "deleteBodyMetric",
            "undoBodyMetricCreation",
            "duplicateBodyMetricIDs",
            "bodyMetricIDCollision",
            "staleBodyMetric",
            "saveFailed",
        ]
    ),
    "HealthTrackingAppTests/TrackerCompositionTests.swift": " ".join(
        [
            "makeTrackerFeatureRouter",
            "factoryCalls",
            "firstRoute === progressRoute",
        ]
    ),
    "HealthTrackingAppTests/AppBootstrapCompositionTests.swift": " ".join(
        [
            "buildDependencies",
            "XCTAssertEqual(constructionAttempts, 1)",
            "XCTAssertEqual(constructionAttempts, 2)",
            "testDefaultDependencyPrewarmerPublishesTodayBeforeAsyncConsumption",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/TrainingKitTests/TodayViewModelTests.swift": " ".join(
        [
            "testApplyingPreloadedSnapshotPublishesContentWithoutRepositoryFetch",
            "applyInitialSnapshot",
            "fetchTodaySnapshotCallCount, 0",
        ]
    ),
    "HealthTrackingAppUITests/BodyMetricFlowUITests.swift": " ".join(
        [
            "today.metrics.action",
            "metrics.entry.save-error",
            "metrics.entry.retry",
            "metrics.row.weight.",
            "m3-metrics-entry-dark",
            "m3-metrics-entry-ax5",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/MetricsKit/Domain/BodyMetricDomain.swift": " ".join(
        [
            "value.isFinite, value > 0",
            "invalidCanonicalUnit",
            "trimmingCharacters",
            "unexpectedBatchMetricType",
            "BodyMetricOrdering",
            "BodyMetricUnitConverter",
            "BodyMetricCreationUndoToken",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/MetricsKit/Repository/MetricsRepository.swift": " ".join(
        [
            "MetricsRepositoryIntegrityError",
            "duplicateBodyMetricIDs",
            "bodyMetricIDCollision",
            "staleBodyMetric",
            "expectedUpdatedAt",
            "undoBodyMetricCreation",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricViewModel.swift": " ".join(
        [
            "QuickEntryMutationStateMachine",
            "pendingBatch",
            "retrySave",
            "retryFailedMutation",
            "prepareForCreation",
            "generation == loadGeneration",
            "expectedUpdatedAt: snapshot.updatedAt",
            "undoLastSave",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataMetricsRepository.swift": " ".join(
        [
            "let existingIDs = Set",
            "generatedSet.insert(id).inserted",
            "for model in models",
            "rollbackOperation()",
            "duplicateBodyMetricIDs",
            "expectedUpdatedAt",
            "validatedSnapshot",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricEntryView.swift": " ".join(
        [
            "QuickEntryFormScaffold",
            "metrics.entry.weight",
            "metrics.entry.waist",
            "metrics.entry.retry",
            "Task { await viewModel.retryFailedMutation() }",
            "viewModel.prepareForCreation()",
            "metrics.entry.saved",
            "NumberFormatter",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricProgressView.swift": " ".join(
        [
            "root.progress",
            "metrics.history.loaded",
            "metrics.row.",
            "metrics.delete.",
        ]
    ),
    "App/Application/TrackerFeatureRouting.swift": " ".join(
        [
            "protocol TrackerFeatureRouting",
            "makeBodyMetricEntryView",
            "makeProgressView",
            "AnyView",
        ]
    ),
    "App/Application/TrackerFeatureBundle.swift": " ".join(
        [
            "TrackerFeatureBundle",
            "TrackerFeatureRouting",
            "BodyMetricViewModel",
            "repository",
            "DefaultTrackerFeatureFactory",
            "UITestMetricsRepository",
            "makeBodyMetricEntryView",
            "makeProgressView",
            "failsFirstCreate: true",
        ]
    ),
    "App/Application/AppDependencies.swift": " ".join(
        [
            "trackerFeatureBundleFactory",
            "private lazy var trackerFeatureRouter",
            "makeTrackerFeatureRouter",
            "TrackerFeatureRouting",
            "Result<AppDependencies, Error>",
            "prepareInitialContentForLaunch",
            "SynchronousTodaySnapshotRepository",
            "todayViewModel.state == .loading",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/TrainingKit/Repository/TrainingRepository.swift": (
        "protocol SynchronousTodaySnapshotRepository fetchTodaySnapshotSynchronously"
    ),
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataTrainingRepository.swift": (
        "SynchronousTodaySnapshotRepository fetchTodaySnapshotSynchronously"
    ),
    "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayViewModel.swift": (
        "applyInitialSnapshot publish(snapshot, evaluatedAt: date)"
    ),
    "App/Application/AppRootView.swift": " ".join(
        [
            "onOpenTrackers: performTodayTrackerAction",
            "resolveTrackerFeatureBundle",
            "makeTrackerFeatureRouter",
            "makeBodyMetricEntryView",
            "makeProgressView",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift": (
        "onOpenTrackers today.metrics.action"
    ),
    "App/Support/AppUITestLaunchConfiguration.swift": (
        'case m3BodyMetrics = "m3-body-metrics"'
    ),
}


def make_fixture(root: Path) -> None:
    for relative_path, content in fixture_files.items():
        path = root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content + "\n", encoding="utf-8")


def run(root: Path, expected: str | None = None) -> None:
    completed = subprocess.run(
        [str(script), "--verify-root", str(root)],
        cwd=repo,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if expected is None:
        if completed.returncode != 0:
            raise SystemExit(
                f"M3 tracker verifier fixture unexpectedly failed:\n{completed.stdout}"
            )
    elif completed.returncode == 0 or expected not in completed.stdout:
        raise SystemExit(
            f"M3 tracker mutation did not fail closed for {expected!r}:\n{completed.stdout}"
        )


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    make_fixture(root)
    run(root)

    state_source = root / "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryMutationStateMachine.swift"
    original = state_source.read_text(encoding="utf-8")
    state_source.write_text(original.replace("attempt == currentAttempt", "attempt != currentAttempt"), encoding="utf-8")
    run(root, "attempt == currentAttempt")
    state_source.write_text(original, encoding="utf-8")

    scaffold = root / "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryFormScaffold.swift"
    original = scaffold.read_text(encoding="utf-8")
    scaffold.write_text(original.replace("minimumActionHeight: CGFloat = 52", "minimumActionHeight: CGFloat = 44"), encoding="utf-8")
    run(root, "minimumActionHeight: CGFloat = 52")
    scaffold.write_text(original, encoding="utf-8")

    scaffold.write_text(original.replace("quick-entry.keyboard.dismiss", ""), encoding="utf-8")
    run(root, "quick-entry.keyboard.dismiss")
    scaffold.write_text(original, encoding="utf-8")

    package = root / "Packages/HealthTrackingModules/Package.swift"
    original_package = package.read_text(encoding="utf-8")
    package.write_text(
        original_package.replace('name: "MetricsKitTests"', 'name: "MissingMetricsTests"'),
        encoding="utf-8",
    )
    run(root, 'name: "MetricsKitTests"')
    package.write_text(original_package, encoding="utf-8")

    persistence = root / "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataMetricsRepository.swift"
    original_persistence = persistence.read_text(encoding="utf-8")
    persistence.write_text(
        original_persistence.replace("rollbackOperation()", "rollbackWasRemoved()"),
        encoding="utf-8",
    )
    run(root, "rollbackOperation()")
    persistence.write_text(original_persistence, encoding="utf-8")

    dependencies = root / "App/Application/AppDependencies.swift"
    original_dependencies = dependencies.read_text(encoding="utf-8")
    dependencies.write_text(
        original_dependencies.replace(
            "private lazy var trackerFeatureRouter",
            "private var eagerTrackerFeatureRouter",
        ),
        encoding="utf-8",
    )
    run(root, "private lazy var trackerFeatureRouter")
    dependencies.write_text(original_dependencies, encoding="utf-8")

    dependencies.write_text(
        original_dependencies.replace(
            "Result<AppDependencies, Error>",
            "Result<PreparedContainer, Error>",
        ),
        encoding="utf-8",
    )
    run(root, "must finish the initial dependency composition synchronously")
    dependencies.write_text(original_dependencies, encoding="utf-8")

    dependencies.write_text(
        original_dependencies + "\nprivate struct PreparedContainer {}\n",
        encoding="utf-8",
    )
    run(root, "must not defer dependency composition after container creation")
    dependencies.write_text(original_dependencies, encoding="utf-8")

    dependencies.write_text(
        "import MetricsKit\n" + original_dependencies,
        encoding="utf-8",
    )
    run(root, "must keep the cold-launch dependency path type-erased")
    dependencies.write_text(original_dependencies, encoding="utf-8")

    root_view = root / "App/Application/AppRootView.swift"
    original_root_view = root_view.read_text(encoding="utf-8")
    root_view.write_text("import MetricsKit\n" + original_root_view, encoding="utf-8")
    run(root, "must keep the cold-launch route type-erased")
    root_view.write_text(original_root_view, encoding="utf-8")

    body_metric_entry = root / "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricEntryView.swift"
    original_body_metric_entry = body_metric_entry.read_text(encoding="utf-8")
    body_metric_entry.write_text(
        original_body_metric_entry
        + '\n.accessibilityIdentifier("metrics.entry.form")\n',
        encoding="utf-8",
    )
    run(root, "must not place an identifier on the field container")
    body_metric_entry.write_text(original_body_metric_entry, encoding="utf-8")

    body_metric_entry.write_text(
        original_body_metric_entry.replace(
            "viewModel.prepareForCreation()",
            "viewModel.prepareForEditing()",
        ),
        encoding="utf-8",
    )
    run(root, "must reset a completed creation lifecycle before reuse")
    body_metric_entry.write_text(original_body_metric_entry, encoding="utf-8")

    body_metric_entry.write_text(
        original_body_metric_entry.replace(
            "retryFailedMutation()",
            "retrySave()",
        ),
        encoding="utf-8",
    )
    run(root, "must route failed save and undo retries through the ViewModel")
    body_metric_entry.write_text(original_body_metric_entry, encoding="utf-8")

    body_metric_progress = root / "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricProgressView.swift"
    original_body_metric_progress = body_metric_progress.read_text(encoding="utf-8")
    body_metric_progress.write_text(
        original_body_metric_progress
        + '\n.accessibilityIdentifier("root.progress.content")\n',
        encoding="utf-8",
    )
    run(root, "must not place an identifier on the state container")
    body_metric_progress.write_text(original_body_metric_progress, encoding="utf-8")

    metrics_catalog = root / "Packages/HealthTrackingModules/Sources/MetricsKit/Resources/Localizable.xcstrings"
    original_catalog = metrics_catalog.read_text(encoding="utf-8")
    metrics_catalog.write_text(
        original_catalog.replace("İlerleme", ""),
        encoding="utf-8",
    )
    run(root, "İlerleme")
    metrics_catalog.write_text(original_catalog, encoding="utf-8")

    metrics_source = root / "Packages/HealthTrackingModules/Sources/MetricsKit/MetricsKitModule.swift"
    metrics_source.write_text("import SwiftData\nenum MetricsKitModuleMarker {}\n", encoding="utf-8")
    run(root, "forbidden feature imports")
    metrics_source.write_text("enum MetricsKitModuleMarker {}\n", encoding="utf-8")

    training_source = root / "Packages/HealthTrackingModules/Sources/TrainingKit/Forbidden.swift"
    training_source.parent.mkdir(parents=True, exist_ok=True)
    training_source.write_text("import MetricsKit\n", encoding="utf-8")
    run(root, "must not reverse-import MetricsKit")

print("M3 tracker verifier self-tests passed.")
PY
}

case "${1:-}" in
    "") verify_repo "$repo_root" ;;
    --self-test) self_test ;;
    --verify-root)
        if (( $# != 2 )) || [[ -z "$2" ]]; then
            echo "Usage: $0 [--self-test|--verify-root PATH]" >&2
            exit 2
        fi
        verify_repo "$2"
        ;;
    *)
        echo "Usage: $0 [--self-test|--verify-root PATH]" >&2
        exit 2
        ;;
esac
