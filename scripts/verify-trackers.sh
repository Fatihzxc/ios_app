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
        "abandonFailedSave",
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
        "--only-testing HealthChecksKitTests",
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
        'dependencies: ["CoreModels", "GuidanceKit", "HealthChecksKit", "MetricsKit", "NutritionKit", "ProgressPhotosKit", "SleepMoodKit", "TrainingKit"]',
        'name: "MetricsKitTests"',
        'dependencies: ["CoreModels", "HealthChecksKit", "MetricsKit", "NutritionKit", "ProgressPhotosKit", "SleepMoodKit", "TrainingKit", "PersistenceKit"]',
    },
    "project.yml": {
        "product: MetricsKit",
        "HealthTrackingModules/MetricsKitTests",
    },
    ".github/workflows/ios.yml": {
        "Targeted M3.6 bloodwork reference tests",
        "scripts/test-ios.sh --only-testing HealthChecksKitTests",
        '"HealthCheckFlowUITests"',
        '"m3-health-check-detail-ax5"',
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
        'dependencies: ["CoreModels", "GuidanceKit", "HealthChecksKit", "MetricsKit", "NutritionKit", "ProgressPhotosKit", "SleepMoodKit", "TrainingKit"]',
        'name: "SleepMoodKitTests"',
        'dependencies: ["CoreModels", "SleepMoodKit"]',
        'dependencies: ["CoreModels", "HealthChecksKit", "MetricsKit", "NutritionKit", "ProgressPhotosKit", "SleepMoodKit", "TrainingKit", "PersistenceKit"]',
    },
    "project.yml": {
        "product: SleepMoodKit",
        "HealthTrackingModules/SleepMoodKitTests",
    },
    ".github/workflows/ios.yml": {
        "Targeted M3.6 bloodwork reference tests",
        "scripts/test-ios.sh --only-testing HealthChecksKitTests",
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
        "Targeted M3.6 bloodwork reference tests",
        "scripts/test-ios.sh --only-testing HealthChecksKitTests",
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

m35_tests = {
    "Packages/HealthTrackingModules/Tests/HealthChecksKitTests/HealthCheckRecurrenceEngineTests.swift": {
        "HealthCheckRecurrenceEngine.nextDueDate",
        "Europe/Istanbul",
        "America/Los_Angeles",
        "testMonthlyClampsToTargetMonthAndUsesClampedResultAsNextAnchor",
        "testQuarterlyClampsInvalidDayAndPreservesLocalTime",
        "testYearlyLeapDayClampsOnceAndKeepsThatResultAsAnchor",
        "testLosAngelesDSTChangesOffsetWithoutMovingWallClockTime",
        "testNonGregorianCalendarFailsExplicitlyInsteadOfAssumingTwelveMonths",
        ".unsupportedCalendar",
    },
    "Packages/HealthTrackingModules/Tests/HealthChecksKitTests/HealthCheckReminderDomainTests.swift": {
        "HealthCheckReminderInput",
        "missingName",
        "dueState(at: now, calendar: calendar)",
        "HealthCheckReminderOrdering.dueFirst",
    },
    "Packages/HealthTrackingModules/Tests/HealthChecksKitTests/HealthChecksViewModelTests.swift": {
        "HealthChecksViewModel",
        "retryCompletion",
        "testSecondCompletionTapWhileSavingCannotReplacePendingRetry",
        "testSuccessfulUndoRemovesSuccessorAndRestoresOriginalSnapshot",
        "testFailedNewCompletionExpiresPreviousUndoPresentation",
        "failedCompletionID",
        "undoLastCompletion",
        "expectedUpdatedAt: first.updatedAt",
    },
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/HealthChecksRepositoryTests.swift": {
        "SwiftDataHealthChecksRepository",
        "createReminder",
        "updateReminder",
        "deleteReminder",
        "completeReminder",
        "duplicateReminderIDs",
        "duplicateSuccessorLinks",
        "testRecurringCompletionIsAtomicAndRetryResolvesTheOpaqueLink",
        "testCompletionSaveFailureRollsBackStatusSuccessorAndLinkForExactRetry",
        "testDeleteCleansOnlyItsOwnedSuccessorMetadata",
        "testCompletedRecurringReminderWithoutLinkCannotGenerateAnotherSuccessor",
        "testRecurringCompletionUndoRestoresPendingAndRemovesOnlySuccessorAndLink",
        "testUndoSaveFailureRollsBackThenExactTokenRetries",
    },
    "HealthTrackingAppUITests/HealthCheckFlowUITests.swift": {
        '"-ui-test-scenario", "m3-health-checks"',
        "today.health-check.summary",
        "today.health-check.action",
        "health-check.detail.complete-error",
        "health-check.detail.retry",
        "health-check.detail.successor",
        "health-check.detail.undo",
        "relaunchedGeneralRows.count",
        "health-check.history.loaded",
        "m3-health-check-detail-ax5",
        'buttons.matching(identifier: "health-check.close").firstMatch',
    },
    "HealthTrackingAppUITests/AccessibilitySmokeUITests.swift": {
        "var currentCount = query.count",
        "RunLoop.current.run(until:",
        "XCTAssertEqual(currentCount, expected",
    },
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/TrainingRepositoryContractTests.swift": {
        "testDedicatedHealthCheckRepositoryUsesDueDateThenUUIDForStableOrdering",
        'name: "Later"',
        'name: "Second"',
        'name: "First"',
    },
    "Packages/HealthTrackingModules/Tests/TrainingKitTests/TodayViewModelTests.swift": {
        "testHealthCheckDueLaterTodayUsesTheSameLocalDaySemanticsAsTrackerDetail",
        "dueLaterToday",
        "dueTomorrow",
    },
    "HealthTrackingAppUITests/TodayGuidanceUITests.swift": {
        "testBloodworkCardKeepsRemainingAlertCountWithoutDuplicateAlertCard",
        'scenario: "today-reminder"',
        'XCTAssertEqual(remaining.label, "+1")',
    },
}

for relative_path, tokens in m35_tests.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.5 test file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.5 RED contracts: {absent}")

m35_support = {
    "Packages/HealthTrackingModules/Package.swift": {
        '.library(name: "HealthChecksKit", targets: ["HealthChecksKit"])',
        'name: "HealthChecksKit"',
        'dependencies: ["CoreModels", "DesignSystem", "HealthSafetyKit"]',
        'resources: [.process("Resources")]',
        'name: "HealthChecksKitTests"',
        'dependencies: ["CoreModels", "HealthChecksKit"]',
        'dependencies: ["CoreModels", "GuidanceKit", "HealthChecksKit", "MetricsKit", "NutritionKit", "ProgressPhotosKit", "SleepMoodKit", "TrainingKit"]',
        'dependencies: ["CoreModels", "HealthChecksKit", "MetricsKit", "NutritionKit", "ProgressPhotosKit", "SleepMoodKit", "TrainingKit", "PersistenceKit"]',
    },
    "project.yml": {
        "product: HealthChecksKit",
        "HealthTrackingModules/HealthChecksKitTests",
    },
    ".github/workflows/ios.yml": {
        "Targeted M3.6 bloodwork reference tests",
        "scripts/test-ios.sh --only-testing HealthChecksKitTests",
    },
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/HealthChecksKitModule.swift": {
        "HealthChecksKitModuleMarker",
    },
}

for relative_path, tokens in m35_support.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.5 support file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.5 wiring: {absent}")

m36_tests = {
    "Packages/HealthTrackingModules/Tests/HealthChecksKitTests/BloodworkResultDomainTests.swift": {
        "BloodworkResultInput",
        "missingMarker",
        "missingUnit",
        "nonFiniteValue",
        "testInputRequiresFiniteValueButPermitsNegativeReferenceValues",
        "BloodworkResultOrdering.newestFirst",
        "testOrderingUsesNewestDateThenStableUUID",
    },
    "Packages/HealthTrackingModules/Tests/HealthChecksKitTests/BloodworkViewModelTests.swift": {
        "BloodworkViewModel",
        "retryCreate",
        "undoLastCreate",
        "testStaleLoadCompletionCannotReplaceNewerSnapshot",
        "testSecondCreateWhileSavingCannotReplacePendingRetryInput",
        "testFailedUpdateRetryKeepsExactTargetTimestampAndInput",
        "testFailedDeleteRetryCannotMoveToAnotherSelectedRecord",
        "testPreparingAnotherEditorExpiresFailedEditRetry",
        "expectedUpdatedAt: original.updatedAt",
        "repository.createRequests, [first, first]",
    },
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/BloodworkRepositoryTests.swift": {
        "SwiftDataBloodworkRepository",
        "createResult",
        "updateResult",
        "deleteResult",
        "undoResultCreation",
        "duplicateResultIDs",
        "resultIDCollision",
        "staleResult",
        "testCreateUpdateDeleteAndUndoFailuresRollback",
        "testUndoRequiresCreationTimestampAndIsIdempotentAfterSuccess",
    },
    "HealthTrackingAppUITests/BloodworkFlowUITests.swift": {
        '"-ui-test-scenario", "m3-bloodwork"',
        "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir.",
        "bloodwork.list.error",
        "bloodwork.list.empty",
        "bloodwork.editor.content",
        "bloodwork.detail.content",
        "bloodwork.detail.delete-confirm",
        "failedMarker.isEnabled",
        "health-check.history.error",
        "m3-bloodwork-editor-dark-high-contrast",
        "m3-bloodwork-editor-ax5",
    },
    "HealthTrackingAppTests/TrackerCompositionTests.swift": {
        "TrackerBloodworkRepositoryStub",
        "bloodworkRepository: bloodworkRepository",
        "bundle.bloodworkRepository",
    },
}

for relative_path, tokens in m36_tests.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.6 test file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.6 RED contracts: {absent}")

m36_support = {
    ".github/workflows/ios.yml": {
        "Targeted M3.6 bloodwork reference tests",
        "scripts/test-ios.sh --only-testing HealthChecksKitTests",
        '"BloodworkFlowUITests"',
        '"m3-bloodwork-empty-light"',
        '"m3-bloodwork-editor-dark-high-contrast"',
        '"m3-bloodwork-editor-ax5"',
    },
    "Packages/HealthTrackingModules/Sources/HealthSafetyKit/HealthSafetyKitModule.swift": {
        "MedicalDisclaimerPresentation",
        "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir.",
        "isAlwaysVisible: true",
    },
}

for relative_path, tokens in m36_support.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.6 support file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.6 wiring: {absent}")

m36_production = {
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Domain/BloodworkResultDomain.swift": {
        "BloodworkResultInputError",
        "guard value.isFinite",
        "trimmingCharacters(in: .whitespacesAndNewlines)",
        "BloodworkResultSnapshot",
        "BloodworkResultOrdering",
        "BloodworkCreationUndoToken",
    },
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Repository/BloodworkRepository.swift": {
        "BloodworkRepositoryIntegrityError",
        "duplicateResultIDs",
        "resultIDCollision",
        "invalidPersistedResult",
        "BloodworkRepositoryMutationError",
        "staleResult",
        "expectedUpdatedAt",
        "undoResultCreation",
    },
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Bloodwork/BloodworkViewModel.swift": {
        "BloodworkEditFailure",
        "PendingBloodworkEditMutation",
        "QuickEntryMutationStateMachine<BloodworkCreationUndoToken>",
        "pendingCreate",
        "pendingEditMutation",
        "retryCreate",
        "retryEditMutation",
        "undoLastCreate",
        "retryUndo",
        "generation == loadGeneration",
        "expectedUpdatedAt: snapshot.updatedAt",
    },
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataBloodworkRepository.swift": {
        "validatedRows()",
        "duplicateResultIDs",
        "resultIDCollision",
        "expectedUpdatedAt",
        "rollbackOperation()",
        "undoResultCreation",
        "token.expectedUpdatedAt",
    },
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Bloodwork/BloodworkListView.swift": {
        "BloodworkListView",
        "MedicalDisclaimerPresentation.permanent.text",
        'accessibilityIdentifier("bloodwork.disclaimer.l1")',
        'accessibilityIdentifier("bloodwork.list.content")',
        'accessibilityIdentifier("bloodwork.list.error")',
        'accessibilityIdentifier("bloodwork.list.empty")',
        'accessibilityIdentifier("bloodwork.editor.content")',
        'accessibilityIdentifier("bloodwork.detail.content")',
        'accessibilityIdentifier("bloodwork.detail.delete-confirm")',
        "isEditorRetryLocked",
        "viewModel.editFailure == .delete(id: snapshot.id)",
        "viewModel.retryEditMutation()",
    },
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/HealthChecks/HealthCheckProgressSection.swift": {
        'accessibilityIdentifier("bloodwork.open")',
        "switch viewModel.loadPhase",
    },
    "App/Application/TrackerFeatureRouting.swift": {
        "makeBloodworkListView",
        "onOpenBloodwork",
    },
    "App/Application/TrackerFeatureBundle.swift": {
        "BloodworkRepository",
        "BloodworkViewModel",
        "SwiftDataBloodworkRepository",
        "UITestBloodworkRepository",
        "failsFirstLoad: true",
        "failsFirstCreate: true",
    },
    "App/Application/AppRootView.swift": {
        "case .bloodwork",
        "makeBloodworkListView",
        "onOpenBloodwork",
    },
    "App/Support/AppUITestLaunchConfiguration.swift": {
        'case m3Bloodwork = "m3-bloodwork"',
    },
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Resources/Localizable.xcstrings": {
        "bloodwork.title",
        "bloodwork.add",
        "bloodwork.editor.save",
        "bloodwork.detail.delete",
        "Kan değerleri",
    },
}

for relative_path, tokens in m36_production.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.6 production file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(
            f"{relative_path} is missing M3.6 production contracts: {absent}"
        )

health_check_progress_source = (
    root
    / "Packages/HealthTrackingModules/Sources/HealthChecksKit/HealthChecks/HealthCheckProgressSection.swift"
).read_text(encoding="utf-8")
bloodwork_access = health_check_progress_source.find(
    'accessibilityIdentifier("bloodwork.open")'
)
health_check_state = health_check_progress_source.find("switch viewModel.loadPhase")
if bloodwork_access < 0 or health_check_state < 0 or bloodwork_access > health_check_state:
    raise SystemExit(
        "M3.6 bloodwork access must remain outside the health-check load-state switch"
    )

bloodwork_source_paths = [
    root / "Packages/HealthTrackingModules/Sources/HealthChecksKit/Domain/BloodworkResultDomain.swift",
    root / "Packages/HealthTrackingModules/Sources/HealthChecksKit/Bloodwork/BloodworkViewModel.swift",
    root / "Packages/HealthTrackingModules/Sources/HealthChecksKit/Bloodwork/BloodworkListView.swift",
    root / "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataBloodworkRepository.swift",
]
bloodwork_source = "\n".join(
    path.read_text(encoding="utf-8") for path in bloodwork_source_paths
)
for prohibited in [
    "normal", "abnormal", "anormal", "referenceRange", "normalRange",
    "lowerBound", "upperBound", "threshold", "diagnosis", "diagnose",
    "teşhis", "tanı",
]:
    if prohibited.casefold() in bloodwork_source.casefold():
        raise SystemExit(
            f"M3.6 bloodwork production must not classify or diagnose values: {prohibited}"
        )

import re
if re.search(r"\bvalue\s*(?:<=|>=|<|>)", bloodwork_source):
    raise SystemExit("M3.6 bloodwork production must not compare values to medical ranges")

m37_tests = {
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/PhotoAssetStoreTests.swift": {
        "testImportNormalizesOrientationAndMetadataIntoBoundedProtectedAtomicFiles",
        "rightMirrored",
        "containsMetadata: false",
        'path.contains(".staging")',
        "writeProtectedAtomically",
        "testImportRejectsEmptyOversizedCorruptAndPixelBombInputsBeforeWriting",
        "testImportRejectsProcessorOutputThatRetainsMetadataOrientationOrExceedsBounds",
        "testLoadReturnsMissingOrCorruptFallbackWithoutExposingAPath",
        "testDeleteIsIdempotentAndProtectedDataFailureKeepsAssetForRetry",
        "testImportPurgesStaleStagingBeforeWritingNewProtectedAsset",
        "protectedWriteURLs",
    },
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/PhotoAssetCleanupJournalTests.swift": {
        "testOpaqueCleanupIntentSurvivesJournalRecreationAndExactRemoval",
        "testJournalRejectsPathsInsteadOfPersistingThem",
        "FilePhotoAssetCleanupJournal",
        "cleanup-journal.json",
    },
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/ProgressPhotoRepositoryTests.swift": {
        "SwiftDataProgressPhotoRepository",
        "testImportPersistsOnlyOpaqueAssetIDAndNormalizedMetadata",
        "testMetadataSaveFailureDeletesImportedAssetAndRollsBackModel",
        "testProtectedCleanupFailureRemainsPendingUntilExactRetrySucceeds",
        "testAssetDeleteFailureRestoresMetadataForExactRetry",
        "testThumbnailPassesThroughAvailableMissingAndCorruptFallbacks",
        "testAbsoluteOrMalformedPersistedImageRefFailsClosed",
        "PhotoAssetCleanupJournalFake",
        "testStartupReconciliationKeepsReferencedAssetAndDeletesCrashWindowOrphan",
        "testStartupInventoryDeletesUnjournaledOrphanFromRenameCrashWindow",
        "storedAssetIDs",
        "testDuplicateImageReferenceFailsClosedBeforeEitherOwnerCanDelete",
        "testReconciliationSerializesAConcurrentImportAcrossSuspension",
        "testJournalAndImmediateDeleteFailureQueuesOrphanForCurrentProcessRetry",
        "testJournalAndDeleteCompensationFailureQueuesOrphanForRetry",
    },
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/PhotoImportViewModelTests.swift": {
        "testCancelledSelectionPreservesDatePoseAndNoteWithoutRepositoryWrite",
        "testLoadFailureAndEmptyPayloadPreserveExactDraftForRetry",
        "testSuccessfulSelectionPassesBytesAndNormalizedDraftToRepository",
        "testDeniedLimitedAndUndeterminedBroaderAccessNeverDisableSystemPicker",
        "SystemPhotoPickerAvailability.isEnabled(for: .denied)",
        "SystemPhotoPickerAvailability.isEnabled(for: .limited)",
        "testSuspendedPickerCapturesImmutableDraftBeforeTransferCompletes",
        "testRepositoryFailureRetriesExactCapturedRequestAfterDraftChanges",
        "testCancelDuringSuspendedTransferLetsNewerRequestWin",
        "testUndoAndFailedUndoRetryUseExactSavedSnapshotIdentity",
        "testSelectionLoaderReceivesPreflightByteLimitAndOversizeNeverWrites",
        "testCappedFileReaderRejectsByResourceSizeBeforeReturningData",
        "testNewSelectionFailureReplacesOlderRepositoryRetryWithLatestSelection",
        "testPickerStagingSweepsStaleFilesAndNeverCopiesPastHardCap",
        "testCleanupFailureIsPublishedAndRetriedBeforeNextMutation",
        "testMetadataFailureCleanupIsRetriedBeforeExactImportRetry",
        "testFailedPickerStagingRemovalRetriesDuringCurrentProcess",
    },
    "HealthTrackingAppUITests/ProgressPhotoLifecycleUITests.swift": {
        '"-ui-test-scenario", "m3-progress-photos"',
        "photos.local-only.status",
        "photos.list.empty",
        "photos.picker",
        "photos.import.fixture",
        "photos.list.content",
        "photos.delete-confirm",
        "app.terminate()",
        "photos.import.undo",
    },
}

for relative_path, tokens in m37_tests.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.7 test file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.7 RED contracts: {absent}")

m37_production = {
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Domain/ProgressPhotoDomain.swift": {
        "ProgressPhotoInput",
        "trimmingCharacters(in: .whitespacesAndNewlines)",
        "ProgressPhotoSnapshot",
        "isOpaquePhotoAssetID",
        "UUID(uuidString:",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/AssetStore/PhotoAssetStore.swift": {
        "PhotoAssetPolicy",
        "maximumInputBytes",
        "maximumPixelCount",
        "fullMaximumDimension",
        "thumbnailMaximumDimension",
        "encodingQuality",
        "PhotoImageOrientation",
        "PhotoImageProcessing",
        "PhotoAssetFileSystem",
        "PhotoAssetStoring",
        "PhotoAssetLoadResult",
        "protectedDataUnavailable",
        "writeProtectedAtomically",
        "storedAssetIDs",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/AssetStore/PhotoAssetCleanupJournal.swift": {
        "PhotoAssetCleanupJournaling",
        "FilePhotoAssetCleanupJournal",
        "cleanup-journal.json",
        ".completeFileProtection",
        "isOpaquePhotoAssetID",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/AssetStore/LocalPhotoAssetStore.swift": {
        "LocalPhotoAssetStore",
        "bytes.count <= policy.maximumInputBytes",
        "metadata.pixelWidth <= policy.maximumPixelCount / metadata.pixelHeight",
        'appendingPathComponent("ProgressPhotos"',
        'appendingPathComponent(".staging"',
        "writeProtectedAtomically",
        "moveItem(at:",
        "removeItemIfExists",
        "invalidNormalizedOutput",
        "protectedDataUnavailable",
        "public actor LocalPhotoAssetStore",
        "prepareStorage",
        "storedAssetIDs",
        "error as? PhotoAssetStoreError",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/ImageIOPhotoImageProcessor.swift": {
        "import ImageIO",
        "ImageIOPhotoImageProcessor",
        "CGImageSourceCreateWithData",
        "kCGImagePropertyOrientation",
        "CGImageDestinationCreateWithData",
        "kCGImageDestinationLossyCompressionQuality",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Repository/ProgressPhotoRepository.swift": {
        "ProgressPhotoRepository",
        "importPhoto",
        "thumbnail",
        "deletePhoto",
        "retryPendingAssetCleanup",
        "ProgressPhotoRepositoryIntegrityError",
        "ProgressPhotoRepositoryOperationError",
        "duplicateImageRefs",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Import/ProgressPhotoImportViewModel.swift": {
        "ProgressPhotoImportViewModel",
        "PhotoSelectionLoading",
        "SystemPhotoPickerAvailability",
        "case .denied, .limited, .notDetermined, .authorized",
        "importSelection",
        "lastImportedSnapshot",
        "QuickEntryMutationStateMachine<ProgressPhotoCreationUndoToken>",
        "maximumSelectionBytes",
        "cancelPendingSelection",
        "retryImport",
        "undoLastImport",
        "retryUndo",
        "repository.retryPendingAssetCleanup()",
        "PhotoAssetCleanupPhase",
        "pendingSelection",
        "abandonFailedSave",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/SystemPhotosPickerView.swift": {
        "import PhotosUI",
        "PhotosPicker",
        "PhotosPickerItem",
        "ImportedPhotoFile.self",
        "CappedPhotoFileReader",
        "FileRepresentation(importedContentType: .image)",
        "Task.detached",
        "maximumBytes + 1",
        "CappedPhotoStagingStore",
        "ProgressPhotoPickerStaging",
        "copyWithHardCap",
        "createProtectedEmptyFile",
        "pendingRemovalDirectories",
        'accessibilityIdentifier("photos.picker")',
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoLifecycleView.swift": {
        "ProgressPhotoLifecycleView",
        "photos.lifecycle.content",
        "photos.local-only.status",
        "photos.list.empty",
        "photos.list.content",
        "photos.import.fixture",
        "photos.delete-confirm",
        "photos.import.retry",
        "photos.import.undo",
        ".disabled(viewModel.isMutationInFlight)",
        "scenePhase",
        "viewModel.retryPendingAssetCleanup()",
    },
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataProgressPhotoRepository.swift": {
        "SwiftDataProgressPhotoRepository",
        "assetStore.importAsset",
        "assetStore.deleteAsset",
        "pendingAssetCleanupIDs",
        "retryPendingAssetCleanup",
        "rollbackOperation()",
        "compensateDeletedMetadata",
        "isOpaquePhotoAssetID",
        "cleanupJournal",
        "reconcileAssetStorageIfNeeded",
        "storedAssetIDs",
        "recordPendingCleanup",
        "duplicateImageRefs",
        "acquireExclusiveOperation",
        "pendingCleanup.insert(reference.assetID)",
        "pendingCleanup.insert(row.snapshot.imageRef)",
    },
    "App/Application/TrackerFeatureRouting.swift": {
        "makeProgressPhotoLifecycleView",
        "onOpenProgressPhotos",
    },
    "App/Application/TrackerFeatureBundle.swift": {
        "ProgressPhotoRepository",
        "ProgressPhotoImportViewModel",
        "LocalPhotoAssetStore",
        "ImageIOPhotoImageProcessor",
        "SwiftDataProgressPhotoRepository",
        "FilePhotoAssetCleanupJournal",
        "makeProgressPhotoLifecycleView",
    },
    "App/Application/AppRootView.swift": {
        "case .progressPhotos",
        "makeProgressPhotoLifecycleView",
        "onOpenProgressPhotos",
    },
    "App/Support/AppUITestLaunchConfiguration.swift": {
        'case m3ProgressPhotos = "m3-progress-photos"',
    },
}

for relative_path, tokens in m37_production.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.7 production file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(
            f"{relative_path} is missing M3.7 production contracts: {absent}"
        )

m37_support = {
    "Packages/HealthTrackingModules/Package.swift": {
        '.library(name: "ProgressPhotosKit", targets: ["ProgressPhotosKit"])',
        'name: "ProgressPhotosKit"',
        'dependencies: ["CoreModels", "DesignSystem"]',
        'dependencies: ["CoreModels", "GuidanceKit", "HealthChecksKit", "MetricsKit", "NutritionKit", "ProgressPhotosKit", "SleepMoodKit", "TrainingKit"]',
        'name: "ProgressPhotosKitTests"',
        'dependencies: ["CoreModels", "ProgressPhotosKit"]',
        'dependencies: ["CoreModels", "HealthChecksKit", "MetricsKit", "NutritionKit", "ProgressPhotosKit", "SleepMoodKit", "TrainingKit", "PersistenceKit"]',
    },
    "project.yml": {
        "product: ProgressPhotosKit",
        "HealthTrackingModules/ProgressPhotosKitTests",
    },
    ".github/workflows/ios.yml": {
        "Targeted M3.7 local photo lifecycle tests",
        "scripts/test-ios.sh --only-testing ProgressPhotosKitTests",
        "ProgressPhotoLifecycleUITests",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Resources/Localizable.xcstrings": {
        '"sourceLanguage" : "tr"',
        "photos.title",
        "photos.local-only.status",
        "Fotoğraflar bu cihazda çalışır",
        "photos.import.retry",
        "photos.import.undo",
    },
}

for relative_path, tokens in m37_support.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.7 support file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.7 wiring: {absent}")

progress_photo_source_root = (
    root / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit"
)
for source_path in progress_photo_source_root.rglob("*.swift"):
    relative = source_path.relative_to(root).as_posix()
    source = source_path.read_text(encoding="utf-8")
    for framework in ("PhotosUI", "UIKit", "ImageIO"):
        if f"import {framework}" not in source:
            continue
        allowed = {
            "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/ImageIOPhotoImageProcessor.swift",
            "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/SystemPhotosPickerView.swift",
        }
        if relative not in allowed:
            raise SystemExit(
                f"M3.7 platform import {framework} escaped its named adapter: {relative}"
            )
    for forbidden in ("import SwiftData", "import PersistenceKit", "import CloudKit"):
        if forbidden in source:
            raise SystemExit(f"M3.7 feature source has forbidden dependency: {forbidden}")
    if "PHPhotoLibrary" in source or "requestAuthorization" in source:
        raise SystemExit("M3.7 system picker must not request broad Photo Library access")

system_picker_source = (
    root
    / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/SystemPhotosPickerView.swift"
).read_text(encoding="utf-8")
if "loadTransferable(type: Data.self)" in system_picker_source:
    raise SystemExit("M3.7 picker must preflight a file before materializing bytes")
if "Data(contentsOf: received.file)" in system_picker_source:
    raise SystemExit("M3.7 picker must not materialize the provider file before its byte cap")
if "copyItem(at: received.file" in system_picker_source:
    raise SystemExit("M3.7 picker staging must stream-copy with a hard byte cap")

local_photo_store_source = (
    root
    / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/AssetStore/LocalPhotoAssetStore.swift"
).read_text(encoding="utf-8")
for obsolete_write in ("fileSystem.write(", "applyCompleteProtection"):
    if obsolete_write in local_photo_store_source:
        raise SystemExit(
            f"M3.7 asset bytes must be protected at creation: {obsolete_write}"
        )
if "@MainActor\npublic final class LocalPhotoAssetStore" in local_photo_store_source:
    raise SystemExit("M3.7 ImageIO and file work must not run on the main actor")

project_source = (root / "project.yml").read_text(encoding="utf-8")
if "NSPhotoLibraryUsageDescription" in project_source:
    raise SystemExit("M3.7 system picker must not add NSPhotoLibraryUsageDescription")

progress_photo_model_source = (
    root / "Packages/HealthTrackingModules/Sources/CoreModels/Models/ProgressPhoto.swift"
).read_text(encoding="utf-8")
for forbidden in ("Data", "URL", "UIImage", "CGImage"):
    if re.search(rf"\b{re.escape(forbidden)}\b", progress_photo_model_source):
        raise SystemExit(
            f"M3.7 ProgressPhoto metadata must not persist binary/path types: {forbidden}"
        )

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

m35_production = {
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Domain/HealthCheckReminderDomain.swift": {
        "HealthCheckReminderInputError",
        "trimmingCharacters(in: .whitespacesAndNewlines)",
        "HealthCheckReminderSnapshot",
        "dueState(",
        "calendar.startOfDay(for: date)",
        "HealthCheckReminderOrdering",
        "HealthCheckCompletionUndoToken",
        "undoToken",
    },
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Domain/HealthCheckRecurrenceEngine.swift": {
        "HealthCheckRecurrenceEngine",
        "case .monthly",
        "case .quarterly",
        "case .yearly",
        "min(sourceDay, dayRange.count)",
        "target.timeZone = calendar.timeZone",
        "case unsupportedCalendar",
        "calendar.identifier == .gregorian",
    },
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Repository/HealthChecksRepository.swift": {
        "HealthChecksRepositoryIntegrityError",
        "duplicateReminderIDs",
        "duplicateSuccessorLinks",
        "HealthChecksRepositoryMutationError",
        "expectedUpdatedAt",
        "completeReminder",
        "completionRequiresPending",
        "undoCompletion",
    },
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/HealthChecks/HealthChecksViewModel.swift": {
        "pendingCompletion = request",
        "QuickEntryMutationStateMachine<HealthCheckCompletionUndoToken>",
        "makeRequestID",
        "failedCompletionID",
        "retryCompletion",
        "undoLastCompletion",
        "retryUndo",
        "expectedUpdatedAt: request.expectedUpdatedAt",
        "lastCompletion = mutation",
        "lastCompletion = nil",
    },
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataHealthChecksRepository.swift": {
        "validatedRows()",
        "resolveExistingCompletion",
        "HealthCheckRecurrenceEngine.nextDueDate",
        "successorLinkKey",
        "successorID.uuidString.lowercased()",
        "rollbackOperation()",
        "saveOrRollback()",
        "guard row.model.status == .pending",
        "undoCompletion",
        "token.completedUpdatedAt",
    },
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/HealthChecks/HealthCheckListView.swift": {
        "HealthCheckListView",
        'accessibilityIdentifier("health-check.list.loaded")',
        'accessibilityIdentifier("medical.disclaimer.l1")',
        'accessibilityIdentifier("health-check.detail.complete-error")',
        'accessibilityIdentifier("health-check.detail.retry")',
        'accessibilityIdentifier("health-check.detail.successor")',
        'accessibilityIdentifier("health-check.detail.undo")',
        'localized("health-check.status.due")',
        "onCommittedMutation",
    },
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/HealthChecks/HealthCheckProgressSection.swift": {
        "HealthCheckProgressSection",
        'accessibilityIdentifier("health-check.history.loaded")',
        '"health-check.row.',
        "snapshot.dueState(at: now(), calendar: calendar)",
    },
    "App/Application/TrackerFeatureRouting.swift": {
        "makeHealthCheckListView",
    },
    "App/Application/TrackerFeatureBundle.swift": {
        "HealthChecksRepository",
        "HealthChecksViewModel",
        "SwiftDataHealthChecksRepository",
        "UITestHealthChecksRepository",
        "failsFirstCompletion: true",
        "HealthCheckProgressSection",
        "calendar: calendar",
    },
    "App/Application/AppRootView.swift": {
        "onOpenHealthChecks: performTodayHealthCheckAction",
        "trackerEntryRoute = .healthChecks",
        "makeHealthCheckListView",
        "onCommittedMutation",
        "todayViewModel.load()",
    },
    "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift": {
        "onOpenHealthChecks",
        "today.health-check.action",
        'accessibilityIdentifier("today.health-check.summary")',
        "if case let .some(.bloodwork(title, dueDate))",
        "additionalCount: presentation.additionalAlertCount",
    },
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Resources/Localizable.xcstrings": {
        "health-check.detail.complete",
        "health-check.history.heading",
        "health-check.detail.undo",
        "health-check.status.due",
        "Sağlık kontrolleri",
    },
    "App/Application/AppDomainContext.swift": {
        "Calendar(identifier: .gregorian)",
        "calendar.timeZone = .autoupdatingCurrent",
    },
    "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayViewModel.swift": {
        "calendar.startOfDay(for: date)",
        "reminder.dueDate < $0",
    },
}

for relative_path, tokens in m35_production.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.5 production file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(
            f"{relative_path} is missing M3.5 production contracts: {absent}"
        )

for relative_path in (
    "Packages/HealthTrackingModules/Sources/TrainingKit/Repository/TrainingRepository.swift",
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataTrainingRepository.swift",
    "App/Application/AppDependencies.swift",
):
    text = (root / relative_path).read_text(encoding="utf-8")
    if "fetchHealthCheckReminders" in text:
        raise SystemExit(
            f"{relative_path} must not retain the legacy mutable health-check API"
        )

health_checks_persistence_text = (
    root
    / "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataHealthChecksRepository.swift"
).read_text(encoding="utf-8")
if "calendar: Calendar =" in health_checks_persistence_text:
    raise SystemExit(
        "SwiftDataHealthChecksRepository must require an explicitly injected Gregorian calendar"
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

for source in (root / "Packages/HealthTrackingModules/Sources/HealthChecksKit").rglob("*.swift"):
    text = source.read_text(encoding="utf-8")
    forbidden = sorted(
        module
        for module in (
            "SwiftData", "PersistenceKit", "TrainingKit", "MetricsKit",
            "SleepMoodKit", "UserNotifications", "CloudKit",
        )
        if f"import {module}" in text
    )
    if forbidden:
        relative = source.relative_to(root)
        raise SystemExit(f"{relative} has forbidden feature imports: {forbidden}")

for source in (root / "Packages/HealthTrackingModules/Sources/TrainingKit").rglob("*.swift"):
    text = source.read_text(encoding="utf-8")
    for module in ("MetricsKit", "SleepMoodKit", "HealthSafetyKit", "HealthChecksKit"):
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
    "import HealthChecksKit",
    "HealthChecksRepository",
    "HealthChecksViewModel",
):
    if forbidden_token in dependencies_source:
        raise SystemExit(
            "App/Application/AppDependencies.swift must keep the cold-launch "
            f"dependency path type-erased; found {forbidden_token!r}"
        )

root_source = (root / "App/Application/AppRootView.swift").read_text(encoding="utf-8")
for forbidden_token in (
    "import MetricsKit",
    "import HealthChecksKit",
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
            "abandonFailedSave",
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
            "Targeted M3.6 bloodwork reference tests",
            "scripts/test-ios.sh --only-testing HealthChecksKitTests",
            '"BodyMetricFlowUITests"',
            '"LifestyleFlowUITests"',
            '"m3-lifestyle-progress-light"',
            '"PostureFlowUITests"',
            '"OHPSafetyFlowUITests"',
            '"m3-posture-high-contrast"',
            '"HealthCheckFlowUITests"',
            '"m3-health-check-detail-ax5"',
            '"BloodworkFlowUITests"',
            '"m3-bloodwork-empty-light"',
            '"m3-bloodwork-editor-dark-high-contrast"',
            '"m3-bloodwork-editor-ax5"',
            "Targeted M3.7 local photo lifecycle tests",
            "scripts/test-ios.sh --only-testing ProgressPhotosKitTests",
            '"ProgressPhotoLifecycleUITests"',
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
            "product: HealthChecksKit",
            "HealthTrackingModules/HealthChecksKitTests",
            "product: ProgressPhotosKit",
            "HealthTrackingModules/ProgressPhotosKitTests",
        ]
    ),
    "Packages/HealthTrackingModules/Package.swift": "\n".join(
        [
            '.library(name: "MetricsKit", targets: ["MetricsKit"])',
            '.library(name: "SleepMoodKit", targets: ["SleepMoodKit"])',
            '.library(name: "HealthSafetyKit", targets: ["HealthSafetyKit"])',
            '.library(name: "HealthChecksKit", targets: ["HealthChecksKit"])',
            '.library(name: "ProgressPhotosKit", targets: ["ProgressPhotosKit"])',
            'name: "MetricsKit"',
            'name: "SleepMoodKit"',
            'name: "HealthSafetyKit"',
            'name: "HealthChecksKit"',
            'name: "ProgressPhotosKit"',
            'resources: [.process("Resources")]',
            'dependencies: ["CoreModels", "DesignSystem"]',
            'dependencies: ["CoreModels", "DesignSystem", "HealthSafetyKit"]',
            'dependencies: ["CoreModels", "HealthChecksKit"]',
            'dependencies: ["CoreModels", "GuidanceKit", "HealthChecksKit", "MetricsKit", "NutritionKit", "ProgressPhotosKit", "SleepMoodKit", "TrainingKit"]',
            'name: "MetricsKitTests"',
            'name: "SleepMoodKitTests"',
            'name: "HealthSafetyKitTests"',
            'name: "HealthChecksKitTests"',
            'name: "ProgressPhotosKitTests"',
            'dependencies: ["HealthSafetyKit"]',
            'dependencies: ["CoreModels", "HealthSafetyKit", "MetricsKit"]',
            'dependencies: ["CoreModels", "SleepMoodKit"]',
            'dependencies: ["CoreModels", "ProgressPhotosKit"]',
            'dependencies: ["CoreModels", "HealthChecksKit", "MetricsKit", "NutritionKit", "ProgressPhotosKit", "SleepMoodKit", "TrainingKit", "PersistenceKit"]',
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
            "TrackerBloodworkRepositoryStub",
            "bloodworkRepository: bloodworkRepository",
            "bundle.bloodworkRepository",
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
            "testHealthCheckDueLaterTodayUsesTheSameLocalDaySemanticsAsTrackerDetail",
            "dueLaterToday",
            "dueTomorrow",
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
    "Packages/HealthTrackingModules/Tests/HealthChecksKitTests/HealthCheckRecurrenceEngineTests.swift": " ".join(
        [
            "HealthCheckRecurrenceEngine.nextDueDate",
            "Europe/Istanbul",
            "America/Los_Angeles",
            "testMonthlyClampsToTargetMonthAndUsesClampedResultAsNextAnchor",
            "testQuarterlyClampsInvalidDayAndPreservesLocalTime",
            "testYearlyLeapDayClampsOnceAndKeepsThatResultAsAnchor",
            "testLosAngelesDSTChangesOffsetWithoutMovingWallClockTime",
            "testNonGregorianCalendarFailsExplicitlyInsteadOfAssumingTwelveMonths",
            ".unsupportedCalendar",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/HealthChecksKitTests/HealthCheckReminderDomainTests.swift": " ".join(
        [
            "HealthCheckReminderInput",
            "missingName",
            "dueState(at: now, calendar: calendar)",
            "HealthCheckReminderOrdering.dueFirst",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/HealthChecksKitTests/HealthChecksViewModelTests.swift": " ".join(
        [
            "HealthChecksViewModel",
            "retryCompletion",
            "testSecondCompletionTapWhileSavingCannotReplacePendingRetry",
            "testSuccessfulUndoRemovesSuccessorAndRestoresOriginalSnapshot",
            "testFailedNewCompletionExpiresPreviousUndoPresentation",
            "failedCompletionID",
            "undoLastCompletion",
            "expectedUpdatedAt: first.updatedAt",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/HealthChecksRepositoryTests.swift": " ".join(
        [
            "SwiftDataHealthChecksRepository",
            "createReminder",
            "updateReminder",
            "deleteReminder",
            "completeReminder",
            "duplicateReminderIDs",
            "duplicateSuccessorLinks",
            "testRecurringCompletionIsAtomicAndRetryResolvesTheOpaqueLink",
            "testCompletionSaveFailureRollsBackStatusSuccessorAndLinkForExactRetry",
            "testDeleteCleansOnlyItsOwnedSuccessorMetadata",
            "testCompletedRecurringReminderWithoutLinkCannotGenerateAnotherSuccessor",
            "testRecurringCompletionUndoRestoresPendingAndRemovesOnlySuccessorAndLink",
            "testUndoSaveFailureRollsBackThenExactTokenRetries",
        ]
    ),
    "HealthTrackingAppUITests/HealthCheckFlowUITests.swift": " ".join(
        [
            '"-ui-test-scenario", "m3-health-checks"',
            "today.health-check.summary",
            "today.health-check.action",
            "health-check.detail.complete-error",
            "health-check.detail.retry",
            "health-check.detail.successor",
            "health-check.detail.undo",
            "relaunchedGeneralRows.count",
            "health-check.history.loaded",
            "m3-health-check-detail-ax5",
            'buttons.matching(identifier: "health-check.close").firstMatch',
        ]
    ),
    "HealthTrackingAppUITests/AccessibilitySmokeUITests.swift": " ".join(
        [
            "var currentCount = query.count",
            "RunLoop.current.run(until:",
            "XCTAssertEqual(currentCount, expected",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/TrainingRepositoryContractTests.swift": " ".join(
        [
            "testDedicatedHealthCheckRepositoryUsesDueDateThenUUIDForStableOrdering",
            'name: "Later"',
            'name: "Second"',
            'name: "First"',
        ]
    ),
    "HealthTrackingAppUITests/TodayGuidanceUITests.swift": " ".join(
        [
            "testBloodworkCardKeepsRemainingAlertCountWithoutDuplicateAlertCard",
            'scenario: "today-reminder"',
            'XCTAssertEqual(remaining.label, "+1")',
        ]
    ),
    "Packages/HealthTrackingModules/Tests/HealthChecksKitTests/BloodworkResultDomainTests.swift": " ".join(
        [
            "BloodworkResultInput",
            "missingMarker",
            "missingUnit",
            "nonFiniteValue",
            "testInputRequiresFiniteValueButPermitsNegativeReferenceValues",
            "BloodworkResultOrdering.newestFirst",
            "testOrderingUsesNewestDateThenStableUUID",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/HealthChecksKitTests/BloodworkViewModelTests.swift": " ".join(
        [
            "BloodworkViewModel",
            "retryCreate",
            "undoLastCreate",
            "testStaleLoadCompletionCannotReplaceNewerSnapshot",
            "testSecondCreateWhileSavingCannotReplacePendingRetryInput",
            "testFailedUpdateRetryKeepsExactTargetTimestampAndInput",
            "testFailedDeleteRetryCannotMoveToAnotherSelectedRecord",
            "testPreparingAnotherEditorExpiresFailedEditRetry",
            "expectedUpdatedAt: original.updatedAt",
            "repository.createRequests, [first, first]",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/BloodworkRepositoryTests.swift": " ".join(
        [
            "SwiftDataBloodworkRepository",
            "createResult",
            "updateResult",
            "deleteResult",
            "undoResultCreation",
            "duplicateResultIDs",
            "resultIDCollision",
            "staleResult",
            "testCreateUpdateDeleteAndUndoFailuresRollback",
            "testUndoRequiresCreationTimestampAndIsIdempotentAfterSuccess",
        ]
    ),
    "HealthTrackingAppUITests/BloodworkFlowUITests.swift": " ".join(
        [
            '"-ui-test-scenario", "m3-bloodwork"',
            "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir.",
            "bloodwork.list.error",
            "bloodwork.list.empty",
            "bloodwork.editor.content",
            "bloodwork.detail.content",
            "bloodwork.detail.delete-confirm",
            "failedMarker.isEnabled",
            "health-check.history.error",
            "m3-bloodwork-editor-dark-high-contrast",
            "m3-bloodwork-editor-ax5",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/HealthChecksKitModule.swift": (
        "enum HealthChecksKitModuleMarker {}"
    ),
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Domain/HealthCheckReminderDomain.swift": " ".join(
        [
            "HealthCheckReminderInputError",
            "trimmingCharacters(in: .whitespacesAndNewlines)",
            "HealthCheckReminderSnapshot",
            "dueState(",
            "calendar.startOfDay(for: date)",
            "HealthCheckReminderOrdering",
            "HealthCheckCompletionUndoToken",
            "undoToken",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Domain/HealthCheckRecurrenceEngine.swift": " ".join(
        [
            "HealthCheckRecurrenceEngine",
            "case .monthly",
            "case .quarterly",
            "case .yearly",
            "min(sourceDay, dayRange.count)",
            "target.timeZone = calendar.timeZone",
            "case unsupportedCalendar",
            "calendar.identifier == .gregorian",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Repository/HealthChecksRepository.swift": " ".join(
        [
            "HealthChecksRepositoryIntegrityError",
            "duplicateReminderIDs",
            "duplicateSuccessorLinks",
            "HealthChecksRepositoryMutationError",
            "expectedUpdatedAt",
            "completeReminder",
            "completionRequiresPending",
            "undoCompletion",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/HealthChecks/HealthChecksViewModel.swift": " ".join(
        [
            "pendingCompletion = request",
            "QuickEntryMutationStateMachine<HealthCheckCompletionUndoToken>",
            "makeRequestID",
            "failedCompletionID",
            "retryCompletion",
            "undoLastCompletion",
            "retryUndo",
            "expectedUpdatedAt: request.expectedUpdatedAt",
            "lastCompletion = mutation",
            "lastCompletion = nil",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataHealthChecksRepository.swift": " ".join(
        [
            "validatedRows()",
            "resolveExistingCompletion",
            "HealthCheckRecurrenceEngine.nextDueDate",
            "successorLinkKey",
            "successorID.uuidString.lowercased()",
            "rollbackOperation()",
            "saveOrRollback()",
            "guard row.model.status == .pending",
            "undoCompletion",
            "token.completedUpdatedAt",
            "calendar: Calendar,",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/HealthChecks/HealthCheckListView.swift": " ".join(
        [
            "HealthCheckListView",
            'accessibilityIdentifier("health-check.list.loaded")',
            'accessibilityIdentifier("medical.disclaimer.l1")',
            'accessibilityIdentifier("health-check.detail.complete-error")',
            'accessibilityIdentifier("health-check.detail.retry")',
            'accessibilityIdentifier("health-check.detail.successor")',
            'accessibilityIdentifier("health-check.detail.undo")',
            'localized("health-check.status.due")',
            "onCommittedMutation",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/HealthChecks/HealthCheckProgressSection.swift": " ".join(
        [
            "HealthCheckProgressSection",
            'accessibilityIdentifier("health-check.history.loaded")',
            '"health-check.row.',
            "snapshot.dueState(at: now(), calendar: calendar)",
            'accessibilityIdentifier("bloodwork.open")',
            "switch viewModel.loadPhase",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Domain/BloodworkResultDomain.swift": " ".join(
        [
            "BloodworkResultInputError",
            "guard value.isFinite",
            "trimmingCharacters(in: .whitespacesAndNewlines)",
            "BloodworkResultSnapshot",
            "BloodworkResultOrdering",
            "BloodworkCreationUndoToken",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Repository/BloodworkRepository.swift": " ".join(
        [
            "BloodworkRepositoryIntegrityError",
            "duplicateResultIDs",
            "resultIDCollision",
            "invalidPersistedResult",
            "BloodworkRepositoryMutationError",
            "staleResult",
            "expectedUpdatedAt",
            "undoResultCreation",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Bloodwork/BloodworkViewModel.swift": " ".join(
        [
            "BloodworkEditFailure",
            "PendingBloodworkEditMutation",
            "QuickEntryMutationStateMachine<BloodworkCreationUndoToken>",
            "pendingCreate",
            "pendingEditMutation",
            "retryCreate",
            "retryEditMutation",
            "undoLastCreate",
            "retryUndo",
            "generation == loadGeneration",
            "expectedUpdatedAt: snapshot.updatedAt",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataBloodworkRepository.swift": " ".join(
        [
            "validatedRows()",
            "duplicateResultIDs",
            "resultIDCollision",
            "expectedUpdatedAt",
            "rollbackOperation()",
            "undoResultCreation",
            "token.expectedUpdatedAt",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Bloodwork/BloodworkListView.swift": " ".join(
        [
            "BloodworkListView",
            "MedicalDisclaimerPresentation.permanent.text",
            'accessibilityIdentifier("bloodwork.disclaimer.l1")',
            'accessibilityIdentifier("bloodwork.list.content")',
            'accessibilityIdentifier("bloodwork.list.error")',
            'accessibilityIdentifier("bloodwork.list.empty")',
            'accessibilityIdentifier("bloodwork.editor.content")',
            'accessibilityIdentifier("bloodwork.detail.content")',
            'accessibilityIdentifier("bloodwork.detail.delete-confirm")',
            "isEditorRetryLocked",
            "viewModel.editFailure == .delete(id: snapshot.id)",
            "viewModel.retryEditMutation()",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/HealthChecksKit/Resources/Localizable.xcstrings": " ".join(
        [
            "health-check.detail.complete",
            "health-check.history.heading",
            "health-check.detail.undo",
            "health-check.status.due",
            "Sağlık kontrolleri",
            "bloodwork.title",
            "bloodwork.add",
            "bloodwork.editor.save",
            "bloodwork.detail.delete",
            "Kan değerleri",
        ]
    ),
    "App/Application/AppDomainContext.swift": (
        "Calendar(identifier: .gregorian) calendar.timeZone = .autoupdatingCurrent"
    ),
    "Packages/HealthTrackingModules/Sources/HealthSafetyKit/HealthSafetyKitModule.swift": " ".join(
        [
            "enum HealthSafetyKitModule {}",
            "MedicalDisclaimerPresentation",
            "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir.",
            "isAlwaysVisible: true",
        ]
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
            "makeHealthCheckListView",
            "makeBloodworkListView",
            "makeProgressPhotoLifecycleView",
            "makeProgressView",
            "onOpenBloodwork",
            "onOpenProgressPhotos",
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
            "HealthChecksRepository",
            "HealthChecksViewModel",
            "SwiftDataHealthChecksRepository",
            "UITestHealthChecksRepository",
            "failsFirstCompletion: true",
            "HealthCheckProgressSection",
            "calendar: calendar",
            "BloodworkRepository",
            "BloodworkViewModel",
            "SwiftDataBloodworkRepository",
            "UITestBloodworkRepository",
            "failsFirstLoad: true",
            "failsFirstCreate: true",
            "ProgressPhotoRepository",
            "ProgressPhotoImportViewModel",
            "LocalPhotoAssetStore",
            "ImageIOPhotoImageProcessor",
            "SwiftDataProgressPhotoRepository",
            "FilePhotoAssetCleanupJournal",
            "makeProgressPhotoLifecycleView",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/PhotoAssetStoreTests.swift": " ".join(
        [
            "testImportNormalizesOrientationAndMetadataIntoBoundedProtectedAtomicFiles",
            "rightMirrored",
            "containsMetadata: false",
            'path.contains(".staging")',
            "writeProtectedAtomically",
            "testImportRejectsEmptyOversizedCorruptAndPixelBombInputsBeforeWriting",
            "testImportRejectsProcessorOutputThatRetainsMetadataOrientationOrExceedsBounds",
            "testLoadReturnsMissingOrCorruptFallbackWithoutExposingAPath",
            "testDeleteIsIdempotentAndProtectedDataFailureKeepsAssetForRetry",
            "testImportPurgesStaleStagingBeforeWritingNewProtectedAsset",
            "protectedWriteURLs",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/PhotoAssetCleanupJournalTests.swift": " ".join(
        [
            "testOpaqueCleanupIntentSurvivesJournalRecreationAndExactRemoval",
            "testJournalRejectsPathsInsteadOfPersistingThem",
            "FilePhotoAssetCleanupJournal",
            "cleanup-journal.json",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/ProgressPhotoRepositoryTests.swift": " ".join(
        [
            "SwiftDataProgressPhotoRepository",
            "testImportPersistsOnlyOpaqueAssetIDAndNormalizedMetadata",
            "testMetadataSaveFailureDeletesImportedAssetAndRollsBackModel",
            "testProtectedCleanupFailureRemainsPendingUntilExactRetrySucceeds",
            "testAssetDeleteFailureRestoresMetadataForExactRetry",
            "testThumbnailPassesThroughAvailableMissingAndCorruptFallbacks",
            "testAbsoluteOrMalformedPersistedImageRefFailsClosed",
            "PhotoAssetCleanupJournalFake",
            "testStartupReconciliationKeepsReferencedAssetAndDeletesCrashWindowOrphan",
            "testStartupInventoryDeletesUnjournaledOrphanFromRenameCrashWindow",
            "storedAssetIDs",
            "testDuplicateImageReferenceFailsClosedBeforeEitherOwnerCanDelete",
            "testReconciliationSerializesAConcurrentImportAcrossSuspension",
            "testJournalAndImmediateDeleteFailureQueuesOrphanForCurrentProcessRetry",
            "testJournalAndDeleteCompensationFailureQueuesOrphanForRetry",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/PhotoImportViewModelTests.swift": " ".join(
        [
            "testCancelledSelectionPreservesDatePoseAndNoteWithoutRepositoryWrite",
            "testLoadFailureAndEmptyPayloadPreserveExactDraftForRetry",
            "testSuccessfulSelectionPassesBytesAndNormalizedDraftToRepository",
            "testDeniedLimitedAndUndeterminedBroaderAccessNeverDisableSystemPicker",
            "SystemPhotoPickerAvailability.isEnabled(for: .denied)",
            "SystemPhotoPickerAvailability.isEnabled(for: .limited)",
            "testSuspendedPickerCapturesImmutableDraftBeforeTransferCompletes",
            "testRepositoryFailureRetriesExactCapturedRequestAfterDraftChanges",
            "testCancelDuringSuspendedTransferLetsNewerRequestWin",
            "testUndoAndFailedUndoRetryUseExactSavedSnapshotIdentity",
            "testSelectionLoaderReceivesPreflightByteLimitAndOversizeNeverWrites",
            "testCappedFileReaderRejectsByResourceSizeBeforeReturningData",
            "testNewSelectionFailureReplacesOlderRepositoryRetryWithLatestSelection",
            "testPickerStagingSweepsStaleFilesAndNeverCopiesPastHardCap",
            "testCleanupFailureIsPublishedAndRetriedBeforeNextMutation",
            "testMetadataFailureCleanupIsRetriedBeforeExactImportRetry",
            "testFailedPickerStagingRemovalRetriesDuringCurrentProcess",
        ]
    ),
    "HealthTrackingAppUITests/ProgressPhotoLifecycleUITests.swift": " ".join(
        [
            '"-ui-test-scenario", "m3-progress-photos"',
            "photos.local-only.status",
            "photos.list.empty",
            "photos.picker",
            "photos.import.fixture",
            "photos.list.content",
            "photos.delete-confirm",
            "app.terminate()",
            "photos.import.undo",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Domain/ProgressPhotoDomain.swift": " ".join(
        [
            "ProgressPhotoInput",
            "trimmingCharacters(in: .whitespacesAndNewlines)",
            "ProgressPhotoSnapshot",
            "isOpaquePhotoAssetID",
            "UUID(uuidString:",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/AssetStore/PhotoAssetStore.swift": " ".join(
        [
            "PhotoAssetPolicy",
            "maximumInputBytes",
            "maximumPixelCount",
            "fullMaximumDimension",
            "thumbnailMaximumDimension",
            "encodingQuality",
            "PhotoImageOrientation",
            "PhotoImageProcessing",
            "PhotoAssetFileSystem",
            "PhotoAssetStoring",
            "PhotoAssetLoadResult",
            "protectedDataUnavailable",
            "writeProtectedAtomically",
            "storedAssetIDs",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/AssetStore/PhotoAssetCleanupJournal.swift": " ".join(
        [
            "PhotoAssetCleanupJournaling",
            "FilePhotoAssetCleanupJournal",
            "cleanup-journal.json",
            ".completeFileProtection",
            "isOpaquePhotoAssetID",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/AssetStore/LocalPhotoAssetStore.swift": " ".join(
        [
            "LocalPhotoAssetStore",
            "bytes.count <= policy.maximumInputBytes",
            "metadata.pixelWidth <= policy.maximumPixelCount / metadata.pixelHeight",
            'appendingPathComponent("ProgressPhotos"',
            'appendingPathComponent(".staging"',
            "writeProtectedAtomically",
            "moveItem(at:",
            "removeItemIfExists",
            "invalidNormalizedOutput",
            "protectedDataUnavailable",
            "public actor LocalPhotoAssetStore",
            "prepareStorage",
            "storedAssetIDs",
            "error as? PhotoAssetStoreError",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/ImageIOPhotoImageProcessor.swift": " ".join(
        [
            "import ImageIO",
            "ImageIOPhotoImageProcessor",
            "CGImageSourceCreateWithData",
            "kCGImagePropertyOrientation",
            "CGImageDestinationCreateWithData",
            "kCGImageDestinationLossyCompressionQuality",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Repository/ProgressPhotoRepository.swift": " ".join(
        [
            "ProgressPhotoRepository",
            "importPhoto",
            "thumbnail",
            "deletePhoto",
            "retryPendingAssetCleanup",
            "ProgressPhotoRepositoryIntegrityError",
            "ProgressPhotoRepositoryOperationError",
            "duplicateImageRefs",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Import/ProgressPhotoImportViewModel.swift": " ".join(
        [
            "ProgressPhotoImportViewModel",
            "PhotoSelectionLoading",
            "SystemPhotoPickerAvailability",
            "case .denied, .limited, .notDetermined, .authorized",
            "importSelection",
            "lastImportedSnapshot",
            "QuickEntryMutationStateMachine<ProgressPhotoCreationUndoToken>",
            "maximumSelectionBytes",
            "cancelPendingSelection",
            "retryImport",
            "undoLastImport",
            "retryUndo",
            "repository.retryPendingAssetCleanup()",
            "PhotoAssetCleanupPhase",
            "pendingSelection",
            "abandonFailedSave",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/SystemPhotosPickerView.swift": " ".join(
        [
            "import PhotosUI",
            "PhotosPicker",
            "PhotosPickerItem",
            "ImportedPhotoFile.self",
            "CappedPhotoFileReader",
            "FileRepresentation(importedContentType: .image)",
            "Task.detached",
            "maximumBytes + 1",
            "CappedPhotoStagingStore",
            "ProgressPhotoPickerStaging",
            "copyWithHardCap",
            "createProtectedEmptyFile",
            "pendingRemovalDirectories",
            'accessibilityIdentifier("photos.picker")',
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoLifecycleView.swift": " ".join(
        [
            "ProgressPhotoLifecycleView",
            "photos.lifecycle.content",
            "photos.local-only.status",
            "photos.list.empty",
            "photos.list.content",
            "photos.import.fixture",
            "photos.delete-confirm",
            "photos.import.retry",
            "photos.import.undo",
            ".disabled(viewModel.isMutationInFlight)",
            "scenePhase",
            "viewModel.retryPendingAssetCleanup()",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataProgressPhotoRepository.swift": " ".join(
        [
            "SwiftDataProgressPhotoRepository",
            "assetStore.importAsset",
            "assetStore.deleteAsset",
            "pendingAssetCleanupIDs",
            "retryPendingAssetCleanup",
            "rollbackOperation()",
            "compensateDeletedMetadata",
            "isOpaquePhotoAssetID",
            "cleanupJournal",
            "reconcileAssetStorageIfNeeded",
            "storedAssetIDs",
            "recordPendingCleanup",
            "duplicateImageRefs",
            "acquireExclusiveOperation",
            "pendingCleanup.insert(reference.assetID)",
            "pendingCleanup.insert(row.snapshot.imageRef)",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Resources/Localizable.xcstrings": " ".join(
        [
            '"sourceLanguage" : "tr"',
            "photos.title",
            "photos.local-only.status",
            "Fotoğraflar bu cihazda çalışır",
            "photos.import.retry",
            "photos.import.undo",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/CoreModels/Models/ProgressPhoto.swift": (
        "ProgressPhoto imageRef String pose note"
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
        "applyInitialSnapshot publish(snapshot, evaluatedAt: date) "
        "calendar.startOfDay(for: date) reminder.dueDate < $0"
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
            "onOpenHealthChecks: performTodayHealthCheckAction",
            "trackerEntryRoute = .healthChecks",
            "makeHealthCheckListView",
            "onCommittedMutation",
            "todayViewModel.load()",
            "case .bloodwork",
            "makeBloodworkListView",
            "onOpenBloodwork",
            "case .progressPhotos",
            "makeProgressPhotoLifecycleView",
            "onOpenProgressPhotos",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift": (
        "onOpenTrackers today.metrics.action onOpenLifestyle "
        "today.lifestyle.action today.lifestyle.action.hint "
        "onOpenHealthChecks today.health-check.action "
        'accessibilityIdentifier("today.health-check.summary") '
        "if case let .some(.bloodwork(title, dueDate)) "
        "additionalCount: presentation.additionalAlertCount"
    ),
    "Packages/HealthTrackingModules/Sources/TrainingKit/Resources/Localizable.xcstrings": (
        "today.lifestyle.action Uyku ve ruh hali ekle"
    ),
    "App/Support/AppUITestLaunchConfiguration.swift": " ".join(
        [
            'case m3BodyMetrics = "m3-body-metrics"',
            'case m3SleepMood = "m3-sleep-mood"',
            'case m3Posture = "m3-posture"',
            'case m3HealthChecks = "m3-health-checks"',
            'case m3Bloodwork = "m3-bloodwork"',
            'case m3ProgressPhotos = "m3-progress-photos"',
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

    bloodwork_domain_test = root / "Packages/HealthTrackingModules/Tests/HealthChecksKitTests/BloodworkResultDomainTests.swift"
    original_bloodwork_domain_test = bloodwork_domain_test.read_text(encoding="utf-8")
    bloodwork_domain_test.write_text(
        original_bloodwork_domain_test.replace(
            "testInputRequiresFiniteValueButPermitsNegativeReferenceValues",
            "finiteCoverageWasRemoved",
        ),
        encoding="utf-8",
    )
    run(root, "testInputRequiresFiniteValueButPermitsNegativeReferenceValues")
    bloodwork_domain_test.write_text(original_bloodwork_domain_test, encoding="utf-8")

    bloodwork_domain_source = root / "Packages/HealthTrackingModules/Sources/HealthChecksKit/Domain/BloodworkResultDomain.swift"
    original_bloodwork_domain_source = bloodwork_domain_source.read_text(encoding="utf-8")
    bloodwork_domain_source.write_text(
        original_bloodwork_domain_source.replace(
            "guard value.isFinite",
            "guard true",
        ),
        encoding="utf-8",
    )
    run(root, "guard value.isFinite")
    bloodwork_domain_source.write_text(original_bloodwork_domain_source, encoding="utf-8")

    bloodwork_view_model_source = root / "Packages/HealthTrackingModules/Sources/HealthChecksKit/Bloodwork/BloodworkViewModel.swift"
    original_bloodwork_view_model_source = bloodwork_view_model_source.read_text(
        encoding="utf-8"
    )
    bloodwork_view_model_source.write_text(
        original_bloodwork_view_model_source.replace(
            "retryEditMutation",
            "retryCurrentSelection",
        ),
        encoding="utf-8",
    )
    run(root, "retryEditMutation")
    bloodwork_view_model_source.write_text(
        original_bloodwork_view_model_source,
        encoding="utf-8",
    )

    health_check_progress_source = root / "Packages/HealthTrackingModules/Sources/HealthChecksKit/HealthChecks/HealthCheckProgressSection.swift"
    original_health_check_progress_source = health_check_progress_source.read_text(
        encoding="utf-8"
    )
    bloodwork_identifier = 'accessibilityIdentifier("bloodwork.open")'
    health_check_progress_source.write_text(
        original_health_check_progress_source.replace(bloodwork_identifier, "")
        + "\n"
        + bloodwork_identifier,
        encoding="utf-8",
    )
    run(root, "must remain outside the health-check load-state switch")
    health_check_progress_source.write_text(
        original_health_check_progress_source,
        encoding="utf-8",
    )

    bloodwork_view_source = root / "Packages/HealthTrackingModules/Sources/HealthChecksKit/Bloodwork/BloodworkListView.swift"
    original_bloodwork_view_source = bloodwork_view_source.read_text(encoding="utf-8")
    bloodwork_view_source.write_text(
        original_bloodwork_view_source + "\nnormalRange\n",
        encoding="utf-8",
    )
    run(root, "must not classify or diagnose values")
    bloodwork_view_source.write_text(original_bloodwork_view_source, encoding="utf-8")

    workflow = root / ".github/workflows/ios.yml"
    original_workflow = workflow.read_text(encoding="utf-8")
    workflow.write_text(
        original_workflow.replace('"m3-bloodwork-editor-ax5"', '"removed-bloodwork-ax5"'),
        encoding="utf-8",
    )
    run(root, '"m3-bloodwork-editor-ax5"')
    workflow.write_text(original_workflow, encoding="utf-8")

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

    package.write_text(
        original_package.replace(
            'name: "HealthChecksKitTests"',
            'name: "MissingHealthChecksTests"',
        ),
        encoding="utf-8",
    )
    run(root, 'name: "HealthChecksKitTests"')
    package.write_text(original_package, encoding="utf-8")

    recurrence_test = root / "Packages/HealthTrackingModules/Tests/HealthChecksKitTests/HealthCheckRecurrenceEngineTests.swift"
    original_recurrence_test = recurrence_test.read_text(encoding="utf-8")
    recurrence_test.write_text(
        original_recurrence_test.replace(
            "testLosAngelesDSTChangesOffsetWithoutMovingWallClockTime",
            "dstCoverageWasRemoved",
        ),
        encoding="utf-8",
    )
    run(root, "testLosAngelesDSTChangesOffsetWithoutMovingWallClockTime")
    recurrence_test.write_text(original_recurrence_test, encoding="utf-8")

    recurrence_test.write_text(
        original_recurrence_test.replace(
            "testNonGregorianCalendarFailsExplicitlyInsteadOfAssumingTwelveMonths",
            "nonGregorianCoverageWasRemoved",
        ),
        encoding="utf-8",
    )
    run(root, "testNonGregorianCalendarFailsExplicitlyInsteadOfAssumingTwelveMonths")
    recurrence_test.write_text(original_recurrence_test, encoding="utf-8")

    health_checks_view_model_test = root / "Packages/HealthTrackingModules/Tests/HealthChecksKitTests/HealthChecksViewModelTests.swift"
    original_health_checks_view_model_test = health_checks_view_model_test.read_text(
        encoding="utf-8"
    )
    health_checks_view_model_test.write_text(
        original_health_checks_view_model_test.replace(
            "testSuccessfulUndoRemovesSuccessorAndRestoresOriginalSnapshot",
            "undoCoverageWasRemoved",
        ),
        encoding="utf-8",
    )
    run(root, "testSuccessfulUndoRemovesSuccessorAndRestoresOriginalSnapshot")
    health_checks_view_model_test.write_text(
        original_health_checks_view_model_test,
        encoding="utf-8",
    )

    health_checks_repository_test = root / "Packages/HealthTrackingModules/Tests/PersistenceKitTests/HealthChecksRepositoryTests.swift"
    original_health_checks_repository_test = health_checks_repository_test.read_text(
        encoding="utf-8"
    )
    health_checks_repository_test.write_text(
        original_health_checks_repository_test.replace(
            "testCompletionSaveFailureRollsBackStatusSuccessorAndLinkForExactRetry",
            "transactionRollbackCoverageWasRemoved",
        ),
        encoding="utf-8",
    )
    run(root, "testCompletionSaveFailureRollsBackStatusSuccessorAndLinkForExactRetry")
    health_checks_repository_test.write_text(
        original_health_checks_repository_test,
        encoding="utf-8",
    )

    health_checks_persistence = root / "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataHealthChecksRepository.swift"
    original_health_checks_persistence = health_checks_persistence.read_text(
        encoding="utf-8"
    )
    health_checks_persistence.write_text(
        original_health_checks_persistence.replace(
            "resolveExistingCompletion",
            "completionRetryResolutionWasRemoved",
        ),
        encoding="utf-8",
    )
    run(root, "resolveExistingCompletion")
    health_checks_persistence.write_text(
        original_health_checks_persistence,
        encoding="utf-8",
    )

    health_checks_persistence.write_text(
        original_health_checks_persistence.replace(
            "undoCompletion",
            "undoWasRemoved",
        ),
        encoding="utf-8",
    )
    run(root, "undoCompletion")
    health_checks_persistence.write_text(
        original_health_checks_persistence,
        encoding="utf-8",
    )

    health_checks_persistence.write_text(
        original_health_checks_persistence.replace(
            "calendar: Calendar,",
            "calendar: Calendar = .current,",
        ),
        encoding="utf-8",
    )
    run(root, "must require an explicitly injected Gregorian calendar")
    health_checks_persistence.write_text(
        original_health_checks_persistence,
        encoding="utf-8",
    )

    today_view_model = root / "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayViewModel.swift"
    original_today_view_model = today_view_model.read_text(encoding="utf-8")
    today_view_model.write_text(
        original_today_view_model.replace(
            "reminder.dueDate < $0",
            "reminder.dueDate <= date",
        ),
        encoding="utf-8",
    )
    run(root, "reminder.dueDate < $0")
    today_view_model.write_text(original_today_view_model, encoding="utf-8")

    training_repository = root / "Packages/HealthTrackingModules/Sources/TrainingKit/Repository/TrainingRepository.swift"
    original_training_repository = training_repository.read_text(encoding="utf-8")
    training_repository.write_text(
        original_training_repository + "\nfunc fetchHealthCheckReminders() {}\n",
        encoding="utf-8",
    )
    run(root, "must not retain the legacy mutable health-check API")
    training_repository.write_text(original_training_repository, encoding="utf-8")

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

    health_checks_source = root / "Packages/HealthTrackingModules/Sources/HealthChecksKit/HealthChecksKitModule.swift"
    original_health_checks_source = health_checks_source.read_text(encoding="utf-8")
    health_checks_source.write_text(
        "import SwiftData\n" + original_health_checks_source,
        encoding="utf-8",
    )
    run(root, "forbidden feature imports")
    health_checks_source.write_text(original_health_checks_source, encoding="utf-8")

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
