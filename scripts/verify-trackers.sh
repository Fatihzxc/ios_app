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
        "actionPlacement(isAccessibilitySize: true)",
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
        "QuickEntryActionPlacement",
        "isAccessibilitySize ? .afterForm : .pinned",
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
        "--only-testing HealthSafetyKitTests",
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
        "delete.frame.height",
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
        'dependencies: ["CoreModels", "GuidanceKit", "MetricsKit", "NutritionKit", "SleepMoodKit", "TrainingKit"]',
        'name: "MetricsKitTests"',
        'dependencies: ["CoreModels", "MetricsKit", "NutritionKit", "SleepMoodKit", "TrainingKit", "PersistenceKit"]',
    },
    "project.yml": {
        "product: MetricsKit",
        "HealthTrackingModules/MetricsKitTests",
    },
    ".github/workflows/ios.yml": {
        "Targeted M3.4 medical safety tests",
        "scripts/test-ios.sh --only-testing HealthSafetyKitTests",
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

m33_tests = {
    "Packages/HealthTrackingModules/Tests/SleepMoodKitTests/LifestyleInputTests.swift": {
        "SleepEntryInput",
        "MoodEntryInput",
        "missingMoodSignal",
        "turkishCasePairs",
        "LifestyleDayInput",
        "SleepLogSnapshot",
        ".infinity",
    },
    "Packages/HealthTrackingModules/Tests/SleepMoodKitTests/LifestyleViewModelTests.swift": {
        "LifestyleViewModel",
        "saveFailed",
        "retrySave",
        "testDuplicateSaveWhileInFlightCannotReplaceThePendingCombinedRetry",
        "upserts[0]",
        "lifestyle.validation.empty",
    },
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/LifestyleRepositoryTests.swift": {
        "SwiftDataLifestyleRepository",
        "America/New_York",
        "25 * 60 * 60",
        "Europe/Istanbul",
        "multipleSleepLogs",
        "multipleMoodLogs",
        "upsertLifestyleDay",
        "testSingleSectionUpsertPreservesTheExistingOtherSectionExactly",
        "testCombinedCreateFailureRollsBackBothNewRows",
        "saveFailed",
        "staleMood",
        "dayMismatch",
        "invalidPersistedMoodLog",
    },
    "HealthTrackingAppUITests/LifestyleFlowUITests.swift": {
        "m3-sleep-mood",
        "today.lifestyle.action",
        "lifestyle.sleep.duration",
        "lifestyle.mood.tags",
        "lifestyle.entry.save-error",
        "lifestyle.entry.retry",
        "lifestyle.entry.saved",
        "assertReadingOrder",
        "m3-lifestyle-combined-light",
        "lifestyle.progress.loaded",
        "m3-lifestyle-entry-dark",
        "m3-lifestyle-entry-ax5",
    },
    "HealthTrackingAppTests/TrackerCompositionTests.swift": {
        "TrackerLifestyleRepositoryStub",
        "metricsRepository: repository",
        "lifestyleRepository: lifestyleRepository",
        "makeTrackerFeatureRouter",
        "firstRoute === progressRoute",
        "firstRoute as? TrackerFeatureBundle",
        "bundle.lifestyleRepository",
    },
}

for relative_path, tokens in m33_tests.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.3 test file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.3 RED contracts: {absent}")

m33_support = {
    "Packages/HealthTrackingModules/Package.swift": {
        '.library(name: "SleepMoodKit", targets: ["SleepMoodKit"])',
        'name: "SleepMoodKit"',
        'dependencies: ["CoreModels", "GuidanceKit", "MetricsKit", "NutritionKit", "SleepMoodKit", "TrainingKit"]',
        'name: "SleepMoodKitTests"',
        'dependencies: ["CoreModels", "SleepMoodKit"]',
        'dependencies: ["CoreModels", "MetricsKit", "NutritionKit", "SleepMoodKit", "TrainingKit", "PersistenceKit"]',
    },
    "project.yml": {
        "product: SleepMoodKit",
        "HealthTrackingModules/SleepMoodKitTests",
    },
    ".github/workflows/ios.yml": {
        "Targeted M3.4 medical safety tests",
        "scripts/test-ios.sh --only-testing HealthSafetyKitTests",
        '"BodyMetricFlowUITests"',
        '"LifestyleFlowUITests"',
        '"m3-lifestyle-progress-light"',
    },
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/SleepMoodKitModule.swift": {
        "SleepMoodKitModuleMarker",
    },
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Resources/Localizable.xcstrings": {
        '"sourceLanguage" : "tr"',
    },
    "App/Support/AppUITestLaunchConfiguration.swift": {
        'case m3SleepMood = "m3-sleep-mood"',
    },
}

for relative_path, tokens in m33_support.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.3 support file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.3 wiring: {absent}")

m34_tests = {
    "Packages/HealthTrackingModules/Tests/HealthSafetyKitTests/MedicalSafetyPresentationTests.swift": {
        "MedicalDisclaimerPresentation.permanent",
        "MedicalSafetyPresentation.resolve",
        "overheadPressSymptom",
        "increasingSymptom",
        "cervicalRedFlags",
        "urgentAssessmentInformation",
        "Hareketi durdur.",
    },
    "Packages/HealthTrackingModules/Tests/MetricsKitTests/PostureMetricInputTests.swift": {
        "PostureMetricInput",
        "invalidSymptomScore",
        "PostureMetricOrdering.newestFirst",
        "PostureSymptomTrend.compare",
        "safetyTrigger",
    },
    "Packages/HealthTrackingModules/Tests/MetricsKitTests/PostureViewModelTests.swift": {
        "PostureViewModel",
        "retrySave",
        "testSecondTapWhileSavingCannotReplaceTheRetryPayload",
        "previousExplicitSymptomScore",
        "expectedUpdatedAt",
        "posture.validation.empty",
    },
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/PostureRepositoryTests.swift": {
        "createPostureMetric",
        "fetchPostureMetrics",
        "updatePostureMetric",
        "deletePostureMetric",
        "upsertPostureMetric",
        "duplicatePostureMetricIDs",
        "postureMetricUpsertCollision",
        "testExternalEventSaveFailureRollsBackSoTheSameStableEventCanRetry",
    },
    "Packages/HealthTrackingModules/Tests/TrainingKitTests/SymptomEventContractTests.swift": {
        "SymptomJournalEvent",
        r'Set(Mirror(reflecting: event).children.compactMap(\.label))',
        '["id", "occurredAt", "source"]',
        "NoOpSymptomEventClient.shared",
    },
    "Packages/HealthTrackingModules/Tests/TrainingKitTests/SessionViewModelTests.swift": {
        "SymptomEventClientSpy",
        "symptomJournalState",
        "retrySymptomJournal",
        "testJournalFailureKeepsOHPStoppedAndRetryDoesNotRewriteTrainingState",
        "testRestoringSymptomPresentSessionReemitsTheSameStableEvent",
    },
    "HealthTrackingAppTests/SymptomJournalAdapterTests.swift": {
        "TrainingSymptomMetricsAdapter",
        "TrainingSymptomSafetyMapper.overheadPressSymptom",
        'XCTAssertEqual(repository.upserts[0], repository.upserts[1])',
        'XCTAssertEqual(repository.upserts[0].input.region, "OHP")',
    },
    "HealthTrackingAppUITests/PostureFlowUITests.swift": {
        '"-ui-test-scenario", "m3-posture"',
        "today.posture.action",
        "posture.entry.save-error",
        "posture.entry.retry",
        "posture.history.loaded",
        "medical.disclaimer.l1",
        "medical.safety.l2",
        "m3-posture-entry-ax5",
        "m3-posture-high-contrast",
    },
    "HealthTrackingAppUITests/OHPSafetyFlowUITests.swift": {
        "session.ohp.journal.error",
        "session.ohp.journal.retry",
        "session.ohp.journal.recorded",
        "medical.disclaimer.l1",
        "medical.safety.l2",
    },
}

for relative_path, tokens in m34_tests.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.4 test file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.4 RED contracts: {absent}")

m34_support = {
    "Packages/HealthTrackingModules/Package.swift": {
        '.library(name: "HealthSafetyKit", targets: ["HealthSafetyKit"])',
        'name: "HealthSafetyKit"',
        'dependencies: ["CoreModels", "DesignSystem", "HealthSafetyKit"]',
        'name: "HealthSafetyKitTests"',
        'dependencies: ["HealthSafetyKit"]',
        'dependencies: ["CoreModels", "HealthSafetyKit", "MetricsKit"]',
    },
    "project.yml": {
        "product: HealthSafetyKit",
        "HealthTrackingModules/HealthSafetyKitTests",
    },
    ".github/workflows/ios.yml": {
        "Targeted M3.4 medical safety tests",
        "scripts/test-ios.sh --only-testing HealthSafetyKitTests",
        '"PostureFlowUITests"',
        '"OHPSafetyFlowUITests"',
        '"m3-posture-high-contrast"',
    },
    "Packages/HealthTrackingModules/Sources/HealthSafetyKit/HealthSafetyKitModule.swift": {
        "HealthSafetyKitModule",
    },
    "Packages/HealthTrackingModules/Sources/HealthSafetyKit/Resources/Localizable.xcstrings": {
        '"sourceLanguage" : "tr"',
    },
    "App/Support/AppUITestLaunchConfiguration.swift": {
        'case m3Posture = "m3-posture"',
    },
}

for relative_path, tokens in m34_support.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.4 support file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.4 wiring: {absent}")

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
        "root.progress.content",
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

m33_production = {
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Domain/LifestyleDomain.swift": {
        "durationHours.isFinite",
        "durationHours <= 24",
        "(1...10).contains(quality)",
        'Locale(identifier: "tr_TR")',
        "lowercased(with: locale)",
        "seen.insert(comparisonKey).inserted",
        "trimmingCharacters(in: .whitespacesAndNewlines)",
        "LifestyleDaySnapshot",
    },
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Repository/LifestyleRepository.swift": {
        "LifestyleRepositoryIntegrityError",
        "multipleSleepLogs",
        "multipleMoodLogs",
        "invalidPersistedSleepLog",
        "invalidPersistedMoodLog",
        "staleSleep",
        "staleMood",
        "dayMismatch",
        "upsertLifestyleDay",
    },
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataLifestyleRepository.swift": {
        "calendar.startOfDay(for: date)",
        "calendar.date(byAdding: .day, value: 1, to: start)",
        "log.date >= start && log.date < end",
        "validateExpected(expected, against: current.snapshot)",
        "let timestamp = now()",
        "rollbackOperation()",
        "generatedIDCollision",
        "validatedSleepSnapshot",
        "validatedMoodSnapshot",
    },
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleViewModel.swift": {
        "QuickEntryMutationStateMachine<UUID>",
        "pendingSave = PendingSave(input: input, expected: expected)",
        "mutationMachine.retrySave()",
        "pendingSave.input",
        "pendingSave.expected",
        "generation == loadGeneration",
        "lifestyle.validation.empty",
    },
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleEntryView.swift": {
        "QuickEntryFormScaffold",
        'accessibilityIdentifier("lifestyle.entry.loaded")',
        'accessibilityIdentifier("lifestyle.entry.date.label")',
        'accessibilityIdentifier("lifestyle.entry.date")',
        '"lifestyle.entry.retry"',
        'accessibilityIdentifier("lifestyle.entry.saved")',
        ".labelsHidden()",
        "NumberFormatter",
    },
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleProgressSection.swift": {
        "LifestyleProgressSection",
        'accessibilityIdentifier("lifestyle.progress.loaded")',
        ".monospacedDigit()",
        ".fixedSize(horizontal: true, vertical: true)",
    },
    "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricProgressView.swift": {
        "AdditionalContent: View",
        "@ViewBuilder additionalContent",
        "additionalContent",
        "AdditionalContent == EmptyView",
    },
    "App/Application/TrackerFeatureRouting.swift": {
        "makeLifestyleEntryView",
        "makeProgressView",
    },
    "App/Application/TrackerFeatureBundle.swift": {
        "LifestyleRepository",
        "LifestyleViewModel",
        "SwiftDataLifestyleRepository",
        "UITestLifestyleRepository",
        "failsFirstUpsert: true",
        "makeLifestyleEntryView",
        "LifestyleProgressSection",
    },
    "App/Application/AppRootView.swift": {
        "TrackerEntryRoute",
        "makeLifestyleEntryView",
        "onOpenLifestyle: performTodayLifestyleAction",
        "trackerEntryRoute = .lifestyle",
    },
    "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift": {
        "onOpenLifestyle",
        "today.lifestyle.action",
        "today.lifestyle.action.hint",
    },
    "Packages/HealthTrackingModules/Sources/TrainingKit/Resources/Localizable.xcstrings": {
        "today.lifestyle.action",
        "Uyku ve ruh hali ekle",
    },
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Resources/Localizable.xcstrings": {
        "lifestyle.entry.title",
        "lifestyle.validation.empty",
        "lifestyle.progress.heading",
        "Uyku ve ruh hali",
    },
}

for relative_path, tokens in m33_production.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.3 production file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(
            f"{relative_path} is missing M3.3 production contracts: {absent}"
        )

lifestyle_persistence_source = (
    root
    / "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataLifestyleRepository.swift"
).read_text(encoding="utf-8")
if lifestyle_persistence_source.count("log.date >= start && log.date < end") != 2:
    raise SystemExit(
        "SwiftDataLifestyleRepository must use one half-open local-day predicate for "
        "each sleep and mood section"
    )
for forbidden_clock in ("Calendar.current", "Date.now", "86_400"):
    if forbidden_clock in lifestyle_persistence_source:
        raise SystemExit(
            "SwiftDataLifestyleRepository must inject calendar/clock and must not use "
            f"a fixed-day shortcut: {forbidden_clock}"
        )

lifestyle_view_model_source = (
    root
    / "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleViewModel.swift"
).read_text(encoding="utf-8")
accepted_attempt = lifestyle_view_model_source.find(
    "guard let attempt = mutationMachine.beginSave"
)
pending_assignment = lifestyle_view_model_source.find(
    "pendingSave = PendingSave(input: input, expected: expected)"
)
if accepted_attempt < 0 or pending_assignment <= accepted_attempt:
    raise SystemExit(
        "LifestyleViewModel must assign the pending combined request only after the "
        "state machine accepts beginSave"
    )

lifestyle_entry_source = (
    root
    / "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleEntryView.swift"
).read_text(encoding="utf-8")
if '.accessibilityIdentifier("lifestyle.entry.form")' in lifestyle_entry_source:
    raise SystemExit(
        "LifestyleEntryView must not propagate a container identifier over its fields"
    )
date_label_contract = """Text(localized(\"lifestyle.entry.date\"))
                .font(AppTypography.label)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(\"lifestyle.entry.date.label\")"""
if date_label_contract not in lifestyle_entry_source:
    raise SystemExit(
        "LifestyleEntryView must keep the visible date label in an AX5-safe row"
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

for source in (root / "Packages/HealthTrackingModules/Sources/SleepMoodKit").rglob("*.swift"):
    text = source.read_text(encoding="utf-8")
    forbidden = sorted(
        module
        for module in (
            "SwiftData", "PersistenceKit", "TrainingKit", "MetricsKit",
            "UserNotifications", "CloudKit",
        )
        if f"import {module}" in text
    )
    if forbidden:
        relative = source.relative_to(root)
        raise SystemExit(f"{relative} has forbidden feature imports: {forbidden}")

for source in (root / "Packages/HealthTrackingModules/Sources/TrainingKit").rglob("*.swift"):
    text = source.read_text(encoding="utf-8")
    for module in ("MetricsKit", "SleepMoodKit", "HealthSafetyKit"):
        if f"import {module}" in text:
            relative = source.relative_to(root)
            raise SystemExit(f"{relative} must not reverse-import {module}")

for source in (root / "Packages/HealthTrackingModules/Sources/HealthSafetyKit").rglob("*.swift"):
    text = source.read_text(encoding="utf-8")
    forbidden = sorted(
        module
        for module in (
            "CoreModels", "DesignSystem", "MetricsKit", "SleepMoodKit",
            "TrainingKit", "PersistenceKit", "SwiftData", "SwiftUI",
            "UserNotifications", "CloudKit",
        )
        if f"import {module}" in text
    )
    if forbidden:
        relative = source.relative_to(root)
        raise SystemExit(f"{relative} must remain dependency-neutral: {forbidden}")

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
date_field_contract = """Text(localized("metrics.entry.date"))
                            .font(AppTypography.label)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("metrics.entry.date.label")"""
if date_field_contract not in body_metric_entry_source:
    raise SystemExit(
        "BodyMetricEntryView must place the visible date label above the picker so "
        "accessibility Dynamic Type cannot collapse it into a one-letter column"
    )
if '.labelsHidden()' not in body_metric_entry_source:
    raise SystemExit(
        "BodyMetricEntryView must hide the picker label after publishing its separate "
        "visible accessibility label"
    )

body_metric_progress_source = (
    root
    / "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricProgressView.swift"
).read_text(encoding="utf-8")
progress_content_identifier = '.accessibilityIdentifier("root.progress.content")'
if body_metric_progress_source.count(progress_content_identifier) != 1:
    raise SystemExit(
        "BodyMetricProgressView must expose exactly one root.progress.content identifier"
    )
loaded_heading_contract = """.accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(\"root.progress.content\")"""
if loaded_heading_contract not in body_metric_progress_source:
    raise SystemExit(
        "BodyMetricProgressView must identify the loaded heading, not its state container; "
        "container identifiers propagate over row and delete identifiers"
    )
loaded_count_sizing_contract = """.monospacedDigit()
                    .fixedSize(horizontal: true, vertical: true)
                    .accessibilityLabel(localized(\"metrics.history.heading\"))"""
if loaded_count_sizing_contract not in body_metric_progress_source:
    raise SystemExit(
        "BodyMetricProgressView must keep the loaded count at its ideal size so "
        "accessibility Dynamic Type cannot clip it"
    )
if '.frame(minWidth: 52, minHeight: 52, alignment: .leading)' not in body_metric_progress_source:
    raise SystemExit(
        "BodyMetricProgressView must expand the delete label to a 52-point touch target"
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
            "actionPlacement(isAccessibilitySize: true)",
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
            "QuickEntryActionPlacement",
            "isAccessibilitySize ? .afterForm : .pinned",
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
            "Targeted M3.4 medical safety tests",
            "scripts/test-ios.sh --only-testing HealthSafetyKitTests",
            '"BodyMetricFlowUITests"',
            '"LifestyleFlowUITests"',
            '"m3-lifestyle-progress-light"',
            '"PostureFlowUITests"',
            '"OHPSafetyFlowUITests"',
            '"m3-posture-high-contrast"',
        ]
    ),
    "project.yml": "\n".join(
        [
            "HealthTrackingModules/DesignSystemTests",
            "product: MetricsKit",
            "HealthTrackingModules/MetricsKitTests",
            "product: SleepMoodKit",
            "HealthTrackingModules/SleepMoodKitTests",
            "product: HealthSafetyKit",
            "HealthTrackingModules/HealthSafetyKitTests",
        ]
    ),
    "Packages/HealthTrackingModules/Package.swift": "\n".join(
        [
            '.library(name: "MetricsKit", targets: ["MetricsKit"])',
            '.library(name: "SleepMoodKit", targets: ["SleepMoodKit"])',
            '.library(name: "HealthSafetyKit", targets: ["HealthSafetyKit"])',
            'name: "MetricsKit"',
            'name: "SleepMoodKit"',
            'name: "HealthSafetyKit"',
            'dependencies: ["CoreModels", "DesignSystem"]',
            'dependencies: ["CoreModels", "DesignSystem", "HealthSafetyKit"]',
            'dependencies: ["CoreModels", "GuidanceKit", "MetricsKit", "NutritionKit", "SleepMoodKit", "TrainingKit"]',
            'name: "MetricsKitTests"',
            'name: "SleepMoodKitTests"',
            'name: "HealthSafetyKitTests"',
            'dependencies: ["HealthSafetyKit"]',
            'dependencies: ["CoreModels", "HealthSafetyKit", "MetricsKit"]',
            'dependencies: ["CoreModels", "SleepMoodKit"]',
            'dependencies: ["CoreModels", "MetricsKit", "NutritionKit", "SleepMoodKit", "TrainingKit", "PersistenceKit"]',
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
            "TrackerLifestyleRepositoryStub",
            "metricsRepository: repository",
            "lifestyleRepository: lifestyleRepository",
            "firstRoute as? TrackerFeatureBundle",
            "bundle.lifestyleRepository",
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
            "delete.frame.height",
            "m3-metrics-entry-dark",
            "m3-metrics-entry-ax5",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/SleepMoodKitTests/LifestyleInputTests.swift": " ".join(
        [
            "SleepEntryInput",
            "MoodEntryInput",
            "missingMoodSignal",
            "turkishCasePairs",
            "LifestyleDayInput",
            "SleepLogSnapshot",
            ".infinity",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/SleepMoodKitTests/LifestyleViewModelTests.swift": " ".join(
        [
            "LifestyleViewModel",
            "saveFailed",
            "retrySave",
            "testDuplicateSaveWhileInFlightCannotReplaceThePendingCombinedRetry",
            "upserts[0]",
            "lifestyle.validation.empty",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/LifestyleRepositoryTests.swift": " ".join(
        [
            "SwiftDataLifestyleRepository",
            "America/New_York",
            "25 * 60 * 60",
            "Europe/Istanbul",
            "multipleSleepLogs",
            "multipleMoodLogs",
            "upsertLifestyleDay",
            "testSingleSectionUpsertPreservesTheExistingOtherSectionExactly",
            "testCombinedCreateFailureRollsBackBothNewRows",
            "saveFailed",
            "staleMood",
            "dayMismatch",
            "invalidPersistedMoodLog",
        ]
    ),
    "HealthTrackingAppUITests/LifestyleFlowUITests.swift": " ".join(
        [
            "m3-sleep-mood",
            "today.lifestyle.action",
            "lifestyle.sleep.duration",
            "lifestyle.mood.tags",
            "lifestyle.entry.save-error",
            "lifestyle.entry.retry",
            "lifestyle.entry.saved",
            "assertReadingOrder",
            "m3-lifestyle-combined-light",
            "lifestyle.progress.loaded",
            "m3-lifestyle-entry-dark",
            "m3-lifestyle-entry-ax5",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/HealthSafetyKitTests/MedicalSafetyPresentationTests.swift": " ".join(
        [
            "MedicalDisclaimerPresentation.permanent",
            "MedicalSafetyPresentation.resolve",
            "overheadPressSymptom",
            "increasingSymptom",
            "cervicalRedFlags",
            "urgentAssessmentInformation",
            "Hareketi durdur.",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/MetricsKitTests/PostureMetricInputTests.swift": " ".join(
        [
            "PostureMetricInput",
            "invalidSymptomScore",
            "PostureMetricOrdering.newestFirst",
            "PostureSymptomTrend.compare",
            "safetyTrigger",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/MetricsKitTests/PostureViewModelTests.swift": " ".join(
        [
            "PostureViewModel",
            "retrySave",
            "testSecondTapWhileSavingCannotReplaceTheRetryPayload",
            "previousExplicitSymptomScore",
            "expectedUpdatedAt",
            "posture.validation.empty",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/PostureRepositoryTests.swift": " ".join(
        [
            "createPostureMetric",
            "fetchPostureMetrics",
            "updatePostureMetric",
            "deletePostureMetric",
            "upsertPostureMetric",
            "duplicatePostureMetricIDs",
            "postureMetricUpsertCollision",
            "testExternalEventSaveFailureRollsBackSoTheSameStableEventCanRetry",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/TrainingKitTests/SymptomEventContractTests.swift": " ".join(
        [
            "SymptomJournalEvent",
            r"Set(Mirror(reflecting: event).children.compactMap(\.label))",
            '["id", "occurredAt", "source"]',
            "NoOpSymptomEventClient.shared",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/TrainingKitTests/SessionViewModelTests.swift": " ".join(
        [
            "SymptomEventClientSpy",
            "symptomJournalState",
            "retrySymptomJournal",
            "testJournalFailureKeepsOHPStoppedAndRetryDoesNotRewriteTrainingState",
            "testRestoringSymptomPresentSessionReemitsTheSameStableEvent",
        ]
    ),
    "HealthTrackingAppTests/SymptomJournalAdapterTests.swift": " ".join(
        [
            "TrainingSymptomMetricsAdapter",
            "TrainingSymptomSafetyMapper.overheadPressSymptom",
            "XCTAssertEqual(repository.upserts[0], repository.upserts[1])",
            'XCTAssertEqual(repository.upserts[0].input.region, "OHP")',
        ]
    ),
    "HealthTrackingAppUITests/PostureFlowUITests.swift": " ".join(
        [
            '"-ui-test-scenario", "m3-posture"',
            "today.posture.action",
            "posture.entry.save-error",
            "posture.entry.retry",
            "posture.history.loaded",
            "medical.disclaimer.l1",
            "medical.safety.l2",
            "m3-posture-entry-ax5",
            "m3-posture-high-contrast",
        ]
    ),
    "HealthTrackingAppUITests/OHPSafetyFlowUITests.swift": " ".join(
        [
            "session.ohp.journal.error",
            "session.ohp.journal.retry",
            "session.ohp.journal.recorded",
            "medical.disclaimer.l1",
            "medical.safety.l2",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/HealthSafetyKit/HealthSafetyKitModule.swift": (
        "enum HealthSafetyKitModule {}"
    ),
    "Packages/HealthTrackingModules/Sources/HealthSafetyKit/Resources/Localizable.xcstrings": (
        '"sourceLanguage" : "tr"'
    ),
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/SleepMoodKitModule.swift": (
        "enum SleepMoodKitModuleMarker {}"
    ),
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Resources/Localizable.xcstrings": " ".join(
        [
            '"sourceLanguage" : "tr"',
            "lifestyle.entry.title",
            "lifestyle.validation.empty",
            "lifestyle.progress.heading",
            "Uyku ve ruh hali",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Domain/LifestyleDomain.swift": " ".join(
        [
            "durationHours.isFinite",
            "durationHours <= 24",
            "(1...10).contains(quality)",
            'Locale(identifier: "tr_TR")',
            "lowercased(with: locale)",
            "seen.insert(comparisonKey).inserted",
            "trimmingCharacters(in: .whitespacesAndNewlines)",
            "LifestyleDaySnapshot",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Repository/LifestyleRepository.swift": " ".join(
        [
            "LifestyleRepositoryIntegrityError",
            "multipleSleepLogs",
            "multipleMoodLogs",
            "invalidPersistedSleepLog",
            "invalidPersistedMoodLog",
            "staleSleep",
            "staleMood",
            "dayMismatch",
            "upsertLifestyleDay",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataLifestyleRepository.swift": "\n".join(
        [
            "calendar.startOfDay(for: date)",
            "calendar.date(byAdding: .day, value: 1, to: start)",
            "log.date >= start && log.date < end",
            "log.date >= start && log.date < end",
            "validateExpected(expected, against: current.snapshot)",
            "let timestamp = now()",
            "rollbackOperation()",
            "generatedIDCollision",
            "validatedSleepSnapshot",
            "validatedMoodSnapshot",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleViewModel.swift": "\n".join(
        [
            "QuickEntryMutationStateMachine<UUID>",
            "generation == loadGeneration",
            "guard let attempt = mutationMachine.beginSave(requestID: makeRequestID()) else",
            "pendingSave = PendingSave(input: input, expected: expected)",
            "mutationMachine.retrySave()",
            "pendingSave.input",
            "pendingSave.expected",
            "lifestyle.validation.empty",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleEntryView.swift": "\n".join(
        [
            "QuickEntryFormScaffold",
            'accessibilityIdentifier("lifestyle.entry.loaded")',
            'Text(localized("lifestyle.entry.date"))',
            "                .font(AppTypography.label)",
            "                .fixedSize(horizontal: false, vertical: true)",
            '                .accessibilityIdentifier("lifestyle.entry.date.label")',
            'accessibilityIdentifier("lifestyle.entry.date")',
            '"lifestyle.entry.retry"',
            'accessibilityIdentifier("lifestyle.entry.saved")',
            ".labelsHidden()",
            "NumberFormatter",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleProgressSection.swift": " ".join(
        [
            "LifestyleProgressSection",
            'accessibilityIdentifier("lifestyle.progress.loaded")',
            ".monospacedDigit()",
            ".fixedSize(horizontal: true, vertical: true)",
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
    "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricEntryView.swift": "\n".join(
        [
            "QuickEntryFormScaffold",
            "metrics.entry.weight",
            "metrics.entry.waist",
            "metrics.entry.retry",
            "Task { await viewModel.retryFailedMutation() }",
            "viewModel.prepareForCreation()",
            "metrics.entry.saved",
            "NumberFormatter",
            'Text(localized("metrics.entry.date"))',
            "                            .font(AppTypography.label)",
            "                            .fixedSize(horizontal: false, vertical: true)",
            '                            .accessibilityIdentifier("metrics.entry.date.label")',
            ".labelsHidden()",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricProgressView.swift": "\n".join(
        [
            "AdditionalContent: View",
            "@ViewBuilder additionalContent",
            "additionalContent",
            "AdditionalContent == EmptyView",
            '.accessibilityIdentifier("root.progress")',
            ".accessibilityAddTraits(.isHeader)",
            '                    .accessibilityIdentifier("root.progress.content")',
            ".monospacedDigit()",
            "                    .fixedSize(horizontal: true, vertical: true)",
            '                    .accessibilityLabel(localized("metrics.history.heading"))',
            '.accessibilityIdentifier("metrics.history.loaded")',
            "metrics.row.",
            "metrics.delete.",
            ".frame(minWidth: 52, minHeight: 52, alignment: .leading)",
        ]
    ),
    "App/Application/TrackerFeatureRouting.swift": " ".join(
        [
            "protocol TrackerFeatureRouting",
            "makeBodyMetricEntryView",
            "makeLifestyleEntryView",
            "makeProgressView",
            "AnyView",
        ]
    ),
    "App/Application/TrackerFeatureBundle.swift": " ".join(
        [
            "TrackerFeatureBundle",
            "TrackerFeatureRouting",
            "BodyMetricViewModel",
            "LifestyleRepository",
            "LifestyleViewModel",
            "SwiftDataLifestyleRepository",
            "repository",
            "DefaultTrackerFeatureFactory",
            "UITestMetricsRepository",
            "UITestLifestyleRepository",
            "makeBodyMetricEntryView",
            "makeLifestyleEntryView",
            "makeProgressView",
            "failsFirstCreate: true",
            "failsFirstUpsert: true",
            "LifestyleProgressSection",
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
            "onOpenLifestyle: performTodayLifestyleAction",
            "resolveTrackerFeatureBundle",
            "makeTrackerFeatureRouter",
            "makeBodyMetricEntryView",
            "makeLifestyleEntryView",
            "makeProgressView",
            "TrackerEntryRoute",
            "trackerEntryRoute = .lifestyle",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift": (
        "onOpenTrackers today.metrics.action onOpenLifestyle "
        "today.lifestyle.action today.lifestyle.action.hint"
    ),
    "Packages/HealthTrackingModules/Sources/TrainingKit/Resources/Localizable.xcstrings": (
        "today.lifestyle.action Uyku ve ruh hali ekle"
    ),
    "App/Support/AppUITestLaunchConfiguration.swift": " ".join(
        [
            'case m3BodyMetrics = "m3-body-metrics"',
            'case m3SleepMood = "m3-sleep-mood"',
            'case m3Posture = "m3-posture"',
        ]
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

    scaffold.write_text(original.replace("isAccessibilitySize ? .afterForm : .pinned", "isAccessibilitySize ? .pinned : .afterForm"), encoding="utf-8")
    run(root, "isAccessibilitySize ? .afterForm : .pinned")
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

    lifestyle_test = root / "Packages/HealthTrackingModules/Tests/PersistenceKitTests/LifestyleRepositoryTests.swift"
    original_lifestyle_test = lifestyle_test.read_text(encoding="utf-8")
    lifestyle_test.write_text(
        original_lifestyle_test.replace("multipleMoodLogs", "duplicateMoodCheckRemoved"),
        encoding="utf-8",
    )
    run(root, "multipleMoodLogs")
    lifestyle_test.write_text(original_lifestyle_test, encoding="utf-8")

    lifestyle_persistence = root / "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataLifestyleRepository.swift"
    original_lifestyle_persistence = lifestyle_persistence.read_text(encoding="utf-8")
    lifestyle_persistence.write_text(
        original_lifestyle_persistence.replace(
            "log.date >= start && log.date < end",
            "log.date >= start && log.date <= end",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "must use one half-open local-day predicate")
    lifestyle_persistence.write_text(
        original_lifestyle_persistence,
        encoding="utf-8",
    )

    lifestyle_persistence.write_text(
        original_lifestyle_persistence.replace(
            "rollbackOperation()",
            "lifestyleRollbackWasRemoved()",
        ),
        encoding="utf-8",
    )
    run(root, "rollbackOperation()")
    lifestyle_persistence.write_text(
        original_lifestyle_persistence,
        encoding="utf-8",
    )

    lifestyle_view_model = root / "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleViewModel.swift"
    original_lifestyle_view_model = lifestyle_view_model.read_text(encoding="utf-8")
    accepted_then_pending = (
        "guard let attempt = mutationMachine.beginSave(requestID: makeRequestID()) else\n"
        "pendingSave = PendingSave(input: input, expected: expected)"
    )
    pending_then_accepted = (
        "pendingSave = PendingSave(input: input, expected: expected)\n"
        "guard let attempt = mutationMachine.beginSave(requestID: makeRequestID()) else"
    )
    lifestyle_view_model.write_text(
        original_lifestyle_view_model.replace(
            accepted_then_pending,
            pending_then_accepted,
        ),
        encoding="utf-8",
    )
    run(root, "must assign the pending combined request only after")
    lifestyle_view_model.write_text(
        original_lifestyle_view_model,
        encoding="utf-8",
    )

    lifestyle_entry = root / "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleEntryView.swift"
    original_lifestyle_entry = lifestyle_entry.read_text(encoding="utf-8")
    lifestyle_entry.write_text(
        original_lifestyle_entry.replace(
            'accessibilityIdentifier("lifestyle.entry.date.label")',
            'accessibilityIdentifier("lifestyle.entry.date.collapsed")',
        ),
        encoding="utf-8",
    )
    run(root, "lifestyle.entry.date.label")
    lifestyle_entry.write_text(original_lifestyle_entry, encoding="utf-8")

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

    body_metric_entry.write_text(
        original_body_metric_entry.replace(
            '.accessibilityIdentifier("metrics.entry.date.label")',
            '.accessibilityIdentifier("metrics.entry.date.collapsed")',
        ),
        encoding="utf-8",
    )
    run(root, "must place the visible date label above the picker")
    body_metric_entry.write_text(original_body_metric_entry, encoding="utf-8")

    body_metric_progress = root / "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricProgressView.swift"
    original_body_metric_progress = body_metric_progress.read_text(encoding="utf-8")
    body_metric_progress.write_text(
        original_body_metric_progress
        + '\n.accessibilityIdentifier("root.progress.content")\n',
        encoding="utf-8",
    )
    run(root, "must expose exactly one root.progress.content identifier")
    body_metric_progress.write_text(original_body_metric_progress, encoding="utf-8")

    body_metric_progress.write_text(
        original_body_metric_progress.replace(
            ".accessibilityAddTraits(.isHeader)\n"
            '                    .accessibilityIdentifier("root.progress.content")',
            ".accessibilityAddTraits(.isHeader)\n",
        )
        + '\n.accessibilityIdentifier("root.progress.content")\n',
        encoding="utf-8",
    )
    run(root, "must identify the loaded heading, not its state container")
    body_metric_progress.write_text(original_body_metric_progress, encoding="utf-8")

    body_metric_progress.write_text(
        original_body_metric_progress.replace(
            ".fixedSize(horizontal: true, vertical: true)",
            ".fixedSize(horizontal: false, vertical: false)",
        ),
        encoding="utf-8",
    )
    run(root, "must keep the loaded count at its ideal size")
    body_metric_progress.write_text(original_body_metric_progress, encoding="utf-8")

    body_metric_progress.write_text(
        original_body_metric_progress.replace(
            '.frame(minWidth: 52, minHeight: 52, alignment: .leading)',
            '.frame(minWidth: 44, minHeight: 44, alignment: .leading)',
        ),
        encoding="utf-8",
    )
    run(root, "must expand the delete label to a 52-point touch target")
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

    sleep_mood_source = root / "Packages/HealthTrackingModules/Sources/SleepMoodKit/SleepMoodKitModule.swift"
    original_sleep_mood_source = sleep_mood_source.read_text(encoding="utf-8")
    sleep_mood_source.write_text(
        "import MetricsKit\n" + original_sleep_mood_source,
        encoding="utf-8",
    )
    run(root, "forbidden feature imports")
    sleep_mood_source.write_text(original_sleep_mood_source, encoding="utf-8")

    symptom_event_test = root / "Packages/HealthTrackingModules/Tests/TrainingKitTests/SymptomEventContractTests.swift"
    original_symptom_event_test = symptom_event_test.read_text(encoding="utf-8")
    symptom_event_test.write_text(
        original_symptom_event_test.replace(
            '["id", "occurredAt", "source"]',
            '["id", "occurredAt", "region"]',
        ),
        encoding="utf-8",
    )
    run(root, '["id", "occurredAt", "source"]')
    symptom_event_test.write_text(original_symptom_event_test, encoding="utf-8")

    health_safety_source = root / "Packages/HealthTrackingModules/Sources/HealthSafetyKit/HealthSafetyKitModule.swift"
    original_health_safety_source = health_safety_source.read_text(encoding="utf-8")
    health_safety_source.write_text(
        "import MetricsKit\n" + original_health_safety_source,
        encoding="utf-8",
    )
    run(root, "must remain dependency-neutral")
    health_safety_source.write_text(original_health_safety_source, encoding="utf-8")

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
