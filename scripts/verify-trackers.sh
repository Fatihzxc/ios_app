#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

verify_repo() {
    local target_root="$1"
    python3 - "$target_root" <<'PY'
import sys
import re
from pathlib import Path

root = Path(sys.argv[1])

XCTEST_SYNC_AUTOCLOSURE_NAMES = (
    "XCTAssert",
    "XCTAssertEqual",
    "XCTAssertFalse",
    "XCTAssertGreaterThan",
    "XCTAssertGreaterThanOrEqual",
    "XCTAssertIdentical",
    "XCTAssertLessThan",
    "XCTAssertLessThanOrEqual",
    "XCTAssertNil",
    "XCTAssertNoThrow",
    "XCTAssertNotEqual",
    "XCTAssertNotIdentical",
    "XCTAssertNotNil",
    "XCTAssertThrowsError",
    "XCTAssertTrue",
    "XCTUnwrap",
)


def swift_code_mask(source: str) -> str:
    """Mask comments and string literals while preserving offsets/newlines."""
    masked = list(source)
    index = 0
    block_depth = 0
    while index < len(source):
        if block_depth:
            if source.startswith("/*", index):
                masked[index : index + 2] = "  "
                block_depth += 1
                index += 2
            elif source.startswith("*/", index):
                masked[index : index + 2] = "  "
                block_depth -= 1
                index += 2
            else:
                if source[index] != "\n":
                    masked[index] = " "
                index += 1
            continue
        if source.startswith("//", index):
            line_end = source.find("\n", index)
            if line_end < 0:
                line_end = len(source)
            masked[index:line_end] = " " * (line_end - index)
            index = line_end
            continue
        if source.startswith("/*", index):
            masked[index : index + 2] = "  "
            block_depth = 1
            index += 2
            continue
        if source.startswith('"""', index):
            masked[index : index + 3] = "   "
            index += 3
            while index < len(source) and not source.startswith('"""', index):
                if source[index] != "\n":
                    masked[index] = " "
                index += 1
            if index < len(source):
                masked[index : index + 3] = "   "
                index += 3
            continue
        if source[index] == '"':
            masked[index] = " "
            index += 1
            while index < len(source):
                if source[index] == "\\":
                    masked[index] = " "
                    index += 1
                    if index < len(source):
                        masked[index] = " "
                        index += 1
                elif source[index] == '"':
                    masked[index] = " "
                    index += 1
                    break
                else:
                    if source[index] != "\n":
                        masked[index] = " "
                    index += 1
            continue
        index += 1
    return "".join(masked)


def async_xctest_autoclosure_lines(source: str) -> list[int]:
    masked = swift_code_mask(source)
    names = "|".join(
        sorted(map(re.escape, XCTEST_SYNC_AUTOCLOSURE_NAMES), key=len, reverse=True)
    )
    calls = re.compile(rf"\b(?:{names})\s*\(")
    violation_lines = []
    for match in calls.finditer(masked):
        opening = masked.find("(", match.start(), match.end())
        depth = 0
        closing = None
        for cursor in range(opening, len(masked)):
            if masked[cursor] == "(":
                depth += 1
            elif masked[cursor] == ")":
                depth -= 1
                if depth == 0:
                    closing = cursor
                    break
        if closing is None:
            continue
        if re.search(r"\bawait\b", masked[opening + 1 : closing]):
            violation_lines.append(source.count("\n", 0, match.start()) + 1)
    return violation_lines

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
        "testThumbnailAndFullImageUseExplicitAssetVariants",
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
        "fullImage",
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
        "public func fullImage(assetID:",
        "variant: .full",
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
        "Targeted M3.7-M3.9 photo lifecycle, gallery, and cloud asset tests",
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
            "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/PhotoThumbnailView.swift",
            "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/ProgressPhotoAccessibilityAnnouncer.swift",
        }
        if relative not in allowed:
            raise SystemExit(
                f"M3.7 platform import {framework} escaped its named adapter: {relative}"
            )
    for forbidden in ("import SwiftData", "import PersistenceKit"):
        if forbidden in source:
            raise SystemExit(f"M3.7 feature source has forbidden dependency: {forbidden}")
    if "import CloudKit" in source:
        allowed_cloud_adapter = (
            "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/"
            "CloudKitPrivatePhotoAssetDatabase.swift"
        )
        if relative != allowed_cloud_adapter:
            raise SystemExit(
                f"M3.9 CloudKit import escaped its named adapter: {relative}"
            )
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

m38_tests = {
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/ProgressPhotoGalleryViewModelTests.swift": {
        "testLoadOrdersNewestDateThenFrontSideBackAndKeepsSafeAssetFallbacks",
        "testIndividualThumbnailErrorKeepsMetadataRowAsUnavailableFallback",
        "testThirdSelectionReplacesOldestChoiceAndOrdersComparisonChronologically",
        "testMissingCorruptUnknownAndUnavailablePhotosCannotBeSelected",
        "testReloadPrunesDeletedOrNewlyUnavailableSelections",
        "testLargeGalleryDefersEveryThumbnailAndLoadsFullImagesOnlyForCompare",
        "testProtectedDataFallbackRetriesAfterUnlockWithoutReloadingMetadata",
        "testCompareFullImageFallbacksRetryProtectedDataWithoutThumbnailReuse",
        "testThumbnailCacheEvictsLeastRecentUnselectedAsset",
        "replacedOldest(removedID:",
        "repository.thumbnailRequests",
        "repository.fullImageRequests",
        "loadComparisonImages()",
        "retryUnavailableAssets()",
    },
    "HealthTrackingAppUITests/ProgressPhotoGalleryUITests.swift": {
        '"-ui-test-scenario", "m3-photo-gallery"',
        "photos.gallery.content",
        "photos.gallery.missing",
        "photos.gallery.corrupt",
        "photos.gallery.select.",
        "photos.gallery.selected.",
        "photos.compare.content",
        "photos.compare.before",
        "photos.compare.after",
        "photos.compare.replaced",
        "first.label.contains(\"1970\")",
    },
}

for relative_path, tokens in m38_tests.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.8 test file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.8 RED contracts: {absent}")

m38_production = {
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoGalleryViewModel.swift": {
        "ProgressPhotoGalleryViewModel",
        "ProgressPhotoGalleryAssetState",
        "case available(Data)",
        "case unloaded",
        "case loading",
        "case missing",
        "case corrupt",
        "case unavailable",
        "ProgressPhotoGalleryOrdering.newestDateThenPose",
        "ProgressPhotoGalleryOrdering.chronological",
        "selectedPhotoIDs.count == 2",
        "selectedPhotoIDs.removeFirst()",
        "replacedOldest(removedID:",
        "selectedPhotoIDs.removeAll",
        "generation == loadGeneration",
        "thumbnailCacheLimit",
        "thumbnailLoadID",
        "comparisonLoadGeneration",
        "ProgressPhotoComparisonLoadID",
        "advancesLoadID: true",
        "loadThumbnail(id:",
        "loadComparisonImages()",
        "retryUnavailableAssets()",
        "repository.fullImage(",
        "comparisonAssetStates",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoGalleryView.swift": {
        "ProgressPhotoGalleryView",
        "GridItem(.adaptive(minimum: 160)",
        "PhotoThumbnailView",
        "photos.gallery.content",
        "photos.gallery.missing",
        "photos.gallery.corrupt",
        "photos.gallery.unavailable",
        "photos.gallery.select.",
        "photos.gallery.selected.",
        ".task(id: item.thumbnailLoadID)",
        "actionAccessibilityLabel",
        "accessibilityAnnouncer.announce(",
        "ViewThatFits(in: .horizontal)",
        "photos.compare.content",
        "photos.compare.before",
        "photos.compare.after",
        "photos.compare.replaced",
        "photos.gallery.loading",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/PhotoThumbnailView.swift": {
        "import UIKit",
        "UIImage(data: data)",
        ".scaledToFit()",
        ".accessibilityHidden(true)",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/ProgressPhotoAccessibilityAnnouncer.swift": {
        "import UIKit",
        "ProgressPhotoAccessibilityAnnouncing",
        "UIAccessibility.post(notification: .announcement",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Repository/ProgressPhotoRepository.swift": {
        "func fullImage(assetID:",
    },
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataProgressPhotoRepository.swift": {
        "public func fullImage(assetID:",
        "variant: .full",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoLifecycleView.swift": {
        "galleryViewModel: ProgressPhotoGalleryViewModel",
        "ProgressPhotoGalleryView(",
        "await galleryViewModel.load()",
        "galleryViewModel.retryUnavailableAssets()",
        "switch galleryViewModel.phase",
        "galleryViewModel.items.isEmpty",
    },
}

for relative_path, tokens in m38_production.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.8 production file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(
            f"{relative_path} is missing M3.8 production contracts: {absent}"
        )

m38_gallery_vm_source = (
    root
    / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoGalleryViewModel.swift"
).read_text(encoding="utf-8")
m38_metadata_load = m38_gallery_vm_source.split(
    "public func load() async {", 1
)[1].split("public func loadThumbnail", 1)[0]
if "repository.thumbnail(" in m38_metadata_load:
    raise SystemExit("M3.8 metadata load must not eagerly read every thumbnail")
m38_selection_sources = m38_gallery_vm_source + (
    root
    / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoGalleryView.swift"
).read_text(encoding="utf-8") + (
    root
    / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Resources/Localizable.xcstrings"
).read_text(encoding="utf-8")
for obsolete_selection_contract in (
    "selectionLimitReached",
    "photos.compare.limit",
):
    if obsolete_selection_contract in m38_selection_sources:
        raise SystemExit(
            f"M3.8 third selection must replace the oldest: {obsolete_selection_contract}"
        )

m38_support = {
    "App/Application/TrackerFeatureBundle.swift": {
        "import CoreModels",
        "ProgressPhotoGalleryViewModel",
        "progressPhotoGalleryViewModel",
        "UITestProgressPhotoGalleryRepository",
        "scenario == .m3PhotoGallery",
        "progressPhotoRepository: UITestProgressPhotoGalleryRepository()",
        "func fullImage(assetID:",
    },
    "App/Support/AppUITestLaunchConfiguration.swift": {
        'case m3PhotoGallery = "m3-photo-gallery"',
    },
    ".github/workflows/ios.yml": {
        "Targeted M3.7-M3.9 photo lifecycle, gallery, and cloud asset tests",
        "scripts/test-ios.sh --only-testing ProgressPhotosKitTests",
        "ProgressPhotoLifecycleUITests",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Resources/Localizable.xcstrings": {
        "photos.gallery.title",
        "photos.gallery.instructions",
        "photos.gallery.loading",
        "photos.gallery.select",
        "photos.gallery.deselect",
        "photos.gallery.selected",
        "photos.gallery.missing",
        "photos.gallery.corrupt",
        "photos.gallery.unavailable",
        "photos.compare.title",
        "photos.compare.before",
        "photos.compare.after",
        "photos.compare.replaced",
    },
}

for relative_path, tokens in m38_support.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.8 support file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.8 wiring: {absent}")

dependencies_source = (root / "App/Application/AppDependencies.swift").read_text(
    encoding="utf-8"
)


def m38_case_group(switch_source: str, scenario: str, boundary: str) -> tuple[str, str]:
    try:
        scenario_index = switch_source.index(scenario)
        case_start = switch_source.rindex("case ", 0, scenario_index)
        case_end = switch_source.index(":", scenario_index)
    except ValueError as error:
        raise SystemExit(
            f"M3.8 {boundary} switch must include {scenario} in a scenario case group"
        ) from error
    next_case = switch_source.find("case ", case_end + 1)
    return (
        switch_source[case_start:case_end],
        switch_source[case_end + 1 : next_case if next_case != -1 else len(switch_source)],
    )


try:
    launch_switch = dependencies_source.split(
        "switch launchConfiguration.scenario {", 1
    )[1].split("\n        } else {", 1)[0]
except IndexError as error:
    raise SystemExit("M3.8 app launch composition switch is missing") from error

launch_group, launch_body = m38_case_group(
    launch_switch,
    ".m3ProgressPhotos",
    "app launch composition",
)
if ".m3PhotoGallery" not in launch_group or (
    "trainingRepository = repository" not in launch_body
    or "shouldLoadFoundation = true" not in launch_body
):
    raise SystemExit(
        "M3.8 app launch composition must load normal training foundation for "
        ".m3PhotoGallery beside .m3ProgressPhotos"
    )

try:
    fixture_switch = dependencies_source.split(
        "static func install(scenario: AppUITestScenario, in modelContext: ModelContext) throws {",
        1,
    )[1]
except IndexError as error:
    raise SystemExit("M3.8 UI test fixture installation switch is missing") from error

fixture_group, fixture_body = m38_case_group(
    fixture_switch,
    ".m3ProgressPhotos",
    "UI test fixture installation",
)
if ".m3PhotoGallery" not in fixture_group or "return" not in fixture_body:
    raise SystemExit(
        "M3.8 UI test fixture installation must skip CoreModels seeding for "
        ".m3PhotoGallery beside .m3ProgressPhotos"
    )
m39_tests = {
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/CloudPhotoAssetContractTests.swift": {
        "testRecordContractUsesDeterministicOpaqueNameAndPrivacyAllowlist",
        "testChecksumIsStableAndValidationRejectsSizeOrDigestMismatch",
        "testOpaqueSyncStatePersistsQueuesKnownIDsAndChangeToken",
        "testTemporaryStoreOwnsUploadAndDownloadCopiesUntilExplicitCleanup",
        "testAdapterStagesDownloadIntoOwnedStorageBeforeSystemSourceDisappears",
        "testDownloadStagingRejectsOversizedMetadataBeforeOpeningSource",
        "testDownloadStagingBoundsActualBytesAndRejectsMetadataMismatch",
        "testRealBoundedStagerLimitsReadRequestsAndNeverWritesMaximumPlusOneByte",
        "testDownloadStagingDeletesOutputAndClosesReaderWhenWriterCloseFails",
        "XCTAssertEqual(snapshot.closeCallCount, 2)",
        "fileHandleFactory:",
        "testTemporaryStoreRecreationSweepsStaleTransferFiles",
        "CocoaError.Code.fileReadNoPermission.rawValue",
        "nestedUnrelated",
        "unrelatedAsset",
        "symlinkTarget",
        "testLegacyUnscopedSyncStateRecreatesWithNilAccountIdentity",
        "testDeletionIntentStoreSerializesAccountTransitionAndPersistsEveryScope",
        "testLegacyDeletionIntentSetMovesToQuarantineWithoutAuthorizingCurrentAccount",
        "testDeletionIntentStoreRecreationPromotesOnlyMatchingVerifiedAccountHint",
        "testExactIntentReceiptSurvivesPromotionAndDoesNotClearSameAssetABA",
        "testStaleAccountResolutionCannotAuthorizeAfterNewerEpochBegins",
        "testStaleAccountResolutionCannotAuthorizeAfterNewerEpochBegins",
        "testDeletionIntentStoreMigratesV1AndRejectsUnknownSchemaFailClosed",
        "receipt1.intentID",
        "receipt2.intentID",
        "pendingAfterFirstClear",
        "staleResolution",
        "newerResolution",
        "catch is CancellationError",
        "quarantineUnderB",
        "A consumed resolution epoch must never authorize a second account.",
        "receiptAfterResolutionReuse.accountIdentity",
        "staleResolution",
        "newerResolution",
        "catch is CancellationError",
        "quarantineUnderB",
        "quarantineIdentityHint",
        "lastVerifiedAccountIdentity",
        "quarantinedIntents",
        "unresolvedDeletionAssetIDs",
        "forAccountIdentity:",
        "FileCloudPhotoAssetSyncStateStore",
        "FileCloudPhotoAssetTemporaryStore",
    },
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/CloudPhotoAssetCoordinatorTests.swift": {
        "testEveryUnavailableAccountStateDefersWithoutTouchingLocalAssetsOrQueue",
        "testBackfillWaitsForServerResponseUsesPrivateZoneAndCleansUploadFile",
        "testMatchingExistingRecordIsIdempotentAndSkipsAssetSave",
        "testRetryableSaveUsesInjectedExponentialBackoffThenCommits",
        "testPaginatedChangesPersistOpaqueTokenRebuildDownloadAndApplyDeletion",
        "testExpiredChangeTokenClearsPersistedTokenAndRestartsFromNil",
        "testInvalidDownloadDoesNotAdvanceTokenOrMutateLocalStore",
        "testDeletionQueueTreatsMissingServerRecordAsIdempotentSuccess",
        "testStateOnlyDeletionQueueCannotAuthorizeServerDeletion",
        "testNewerSynchronizationWinsWhenOlderUploadCompletesLate",
        "testReferencedMissingAssetRestoresFromCloudWithoutInferringDeletion",
        "testOnlyExplicitCommittedMetadataDeletionQueuesServerDeletion",
        "testReferencedMetadataNeutralizesStaleDeletionIntentWithoutDeletingCloudAsset",
        "testReferencedSnapshotNeutralizesOnlyObservedIntentAcrossSameAssetABA",
        "observedStaleIntent",
        "replacementIntent",
        "XCTAssertEqual(remainingIntents.map",
        "retrySnapshot.deleteRequests",
        "intentsAfterRetry.isEmpty",
        "stateAfterRetry.pendingDeletionAssetIDs.isEmpty",
        "testAccountIdentityChangeResetsStateAndBackfillsNewAccount",
        "testAccountResetLoadsCurrentScopeAndPreservesOldAccountQueue",
        "testAccountTransitionProcessesOnlyCurrentScopeAndPreservesOldAndUnresolvedIntents",
        "testVerifiedAccountOfflineDeletionSurvivesFailureAndRelaunchRetry",
        "testDeferredAccountTransitionQuarantinesOldHintUntilMatchingAccountReturns",
        "postCancellationReceipt.quarantineIdentityHint",
        "postFailureReceipt.quarantineIdentityHint",
        "oldAccountIDs",
        "unresolvedIDs",
        "testLegacyUnscopedFileStateResetsFailClosedAndBackfillsCurrentAccount",
        "testCancelledSynchronizationCleansOwnedPageDiscardedAfterSuspendedFetch",
        "suspendedChangeCalls",
        "testIntentCommittedAfterReadIsNotClearedAgainstOlderReferenceSnapshot",
        "pendingAfterFirst",
        "testCorruptFullVariantWithPhysicalDirectoryReplaysNilTokenAndRepairsWithoutUpload",
        "testMissingThumbnailWithPhysicalDirectoryReplaysNilTokenAndRepairsWithoutUpload",
        "let localStore = LocalPhotoAssetStore(",
        "CloudRepairPhotoAssetFileSystem",
        "try Data([0xff]).write(to: fullURL, options: .atomic)",
        "try FileManager.default.removeItem(at: thumbnailURL)",
        "let physicalBeforeRepair = try await localStore.storedAssetIDs()",
        "let usableBeforeRepair = try await localStore.usableCloudAssetIDs()",
        "NilTokenOnlyRepairCloudPhotoAssetDatabase",
        "guard previousToken == nil else",
        "databaseSnapshot.changeTokens, [nil, repairedChangeToken]",
        "databaseSnapshot.nilTokenRepairResponseCount, 1",
        "pendingUploadAssetIDs: [assetID]",
        "databaseSnapshot.saveRequests.isEmpty",
        "databaseSnapshot.deleteRequests.isEmpty",
        "repairedFull, .available(Data([0x10]))",
        "repairedThumbnail, .available(Data([0x20]))",
        "physicalAfterRepair, [assetID]",
        "usableAfterRepair, [assetID]",
        "firstState, finalState",
        "CloudPhotoAssetLocalStoring",
        "func usableCloudAssetIDs()",
        "referenceSnapshotProvider:",
        "deletionIntentStore:",
        "inboundAssetJournal:",
        "try await coordinator.synchronize()",
        "PrivateCloudPhotoAssetDatabase",
        "CloudPhotoAssetDatabaseError",
    },
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/PhotoAssetStoreTests.swift": {
        "testCloudRestoreUsesExactOpaqueIDAndRebuildsBothVariantsIdempotently",
        "restoreCloudAsset(id:",
        "cloudAssetBytes(id:",
        "deleteCloudAsset(id:",
    },
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/ProgressPhotoGalleryViewModelTests.swift": {
        "testSuccessfulSyncReloadsExactMissingAndCorruptGalleryStatesInOpenLifecycle",
        "ProgressPhotoAssetSyncLifecycle",
        "comparison?.before.assetState",
        "fullImageRequests.filter",
    },
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/ProgressPhotoRepositoryTests.swift": {
        "testCommittedMetadataDeletionPersistsUntilCloudRetrySucceedsAfterRelaunch",
        "testRepositoryCloudReferenceSnapshotIsImmutableAcrossLaterMetadataChange",
        "testInboundCloudAssetSurvivesCoordinatorRestoreCrashAndRepositoryRelaunch",
        "testSuccessfulInboundSyncRetainsIntentUntilMetadataReferencesAsset",
        "testRepositoryConsumesOnlyInboundIDsMatchedByMetadataAcrossRelaunches",
        "testSnapshotReconcilesInboundOwnershipArrivingAfterInitialFetchPerID",
        "testInboundApplyFinishesBeforeQueuedDeleteAndFinalStateRemainsDeleted",
        "testRepositoryInboundApplyWithoutCommittedDeletionPreservesAssetBeforeMetadata",
        "testDeleteCommittedBeforeStaleChangedPageDiscardsInboundAndRetainsIntent",
        "testStaleChangedPageCannotRestoreDeletionQuarantinedByNewerAccountResolution",
        "testStaleGenerationCancelsPreparedInboundLeaseBeforeAnySideEffectAndRepositoryReacquires",
        "testInboundPreparationLeaseRejectsABAAndReleasesAfterCancellation",
        "PausingBeforeRecordCloudPhotoAssetDeletionIntentStore",
        "ObservedCloudPhotoAssetInboundApplier",
        "recordedReceipt.quarantineIdentityHint",
        "durableText.contains(recordedReceipt.intentID.uuidString)",
        "calls.commitLeaseAssetIDs.isEmpty",
        "calls.cancelLeaseAssetIDs, [inboundID]",
        "repository.cancelInboundApply(firstLease)",
        "repository.commitInboundApply(secondLease",
        "retryPreparation",
        "inboundAssetStore: assetStore",
        "inboundAssetApplier: repository",
        "waitForFetchCall(1)",
        "finishedWhileRestoreHeld",
        "transfersAfterRace.isEmpty",
        "pendingAfterDeferred, [assetID]",
        "testInboundRestoreProtectsPreviouslyFailedOrphanFromCleanupRetry",
        "testInitialOrphanSweepRereadsInboundOwnershipAtDeleteBoundary",
        "testInboundJournalReadFailureStopsPendingCleanupRetryBeforeDelete",
        "testCleanupRetryRechecksInboundOwnershipAfterEarlierAssetDeleteSuspends",
        "testInboundRecordWaitsForCleanupLeaseAndRestoreSurvivesDeleteBoundary",
        "testCancelledInboundRecordRemovesExactWaiterAndAllowsLaterCleanupLease",
        "waitForInboundRecordWaiter",
        "inboundRecordWaiterIDs",
        "A cancelled inbound record must finish before lease release.",
        "waitersAfterCancellation.isEmpty",
        "pendingBeforeLeaseRelease.isEmpty",
        "laterLease",
        "CleanupLeaseInterleavingAssetStore",
        "SequencedCloudPhotoAssetInboundJournal",
        "snapshotAfterA",
        "testMetadataDeleteSaveFailureNeverCreatesCloudDeletionIntent",
        "testCompensatedLocalDeleteFailureClearsCloudIntentBeforeReturning",
        "testCompensationClearsExactHintedIntentPromotedWhileReceiptIsPaused",
        "PausingAfterRecordCloudPhotoAssetDeletionIntentStore",
        "scopedAfterCompensation.isEmpty",
        "quarantineAfterCompensation.isEmpty",
        "XCTAssertEqual(intentCalls.recordCalls, [])",
        "XCTAssertEqual(intentCalls.clearCalls, [])",
        "let persistedContext = ModelContext(container)",
        "persistedPhotoIDs([])",
        "pendingAfterA, [assetB]",
        "pendingAfterARelaunch, [assetB]",
        "cloudAssets[assetB], bytesB",
        "FileCloudPhotoAssetDeletionIntentStore",
        "FileCloudPhotoAssetInboundJournal",
        "inboundAssetJournal:",
        "CloudPhotoAssetLocalStoring",
        "func usableCloudAssetIDs()",
    },
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/CloudKitPrivatePhotoAssetDatabaseTests.swift": {
        "testActualAdapterOwnsDownloadBeforeSystemURLDisappearsAtReturnBoundary",
        "testActualAdapterReturnsChangingOpaqueAccountIdentity",
        "testActualAdapterAndCoordinatorConsumeAndRemoveOneSharedOwnedTransfer",
        "testActualAdapterRepairsMatchingMetadataWithoutUsableBinaryAndKeepsValidAssetIdempotent",
        "CloudPhotoAssetSystemRecord",
        "hasUsableBinaryAsset: false",
        "hasUsableBinaryAsset: true",
        "missingBinary.saveRequests.map",
        "validBinary.saveRequests.isEmpty",
        "testActualCKRecordMappingRequiresReadableRegularCKAssetFile",
        "testExplicitChangedKeysModifyRepairsSameIDAssetAndPreservesUnknownFields",
        "testExplicitModifySurfacesExactPerRecordFailure",
        "ConflictAwareCloudKitPhotoAssetRecordModifier",
        "savePolicy: .ifServerRecordUnchanged",
        "RecordSavePolicy.changedKeys.rawValue",
        "serverOnly",
        "perRecordFailure",
        "CloudKitPhotoAssetRecordMapper.systemRecord",
        "missingAsset",
        "wrongTypeAsset",
        "invalidFileAsset",
        "directoryAsset",
        "validAsset",
        "CloudPhotoAssetSystemURLLifetimeOwner",
        "XCTAssertFalse(FileManager.default.fileExists(atPath: systemURL.path))",
        "CloudKitPrivatePhotoAssetDatabase",
        "systemDatabase:",
        "accountIdentityProvider:",
        "downloadStore:",
        "CloudPhotoAssetLocalStoring",
        "func usableCloudAssetIDs()",
    },
}

for relative_path, tokens in m39_tests.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.9 test file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.9 RED contracts: {absent}")

    async_autoclosure_lines = async_xctest_autoclosure_lines(text)
    if async_autoclosure_lines:
        locations = ", ".join(
            f"{relative_path}:{line}" for line in async_autoclosure_lines
        )
        raise SystemExit(
            "M3.9 XCTest autoclosures must evaluate async values first: "
            f"{locations}"
        )

m39_coordinator_tests_text = (
    root
    / "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/CloudPhotoAssetCoordinatorTests.swift"
).read_text(encoding="utf-8")
if "synchronize(snapshot:" in m39_coordinator_tests_text:
    raise SystemExit(
        "M3.9 RED must exercise shipped no-argument synchronize(), not an unused overload"
    )

m39_production = {
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/CloudPhotoAssetDomain.swift": {
        "CloudPhotoAssetRecordContract",
        'zoneName = "ProgressPhotoAssetsZone"',
        'recordType = "ProgressPhotoAsset"',
        "CloudPhotoAssetChecksum",
        "CloudPhotoAssetSyncState",
        "pendingUploadAssetIDs",
        "pendingDeletionAssetIDs",
        "uploadedAssetIDs",
        "changeToken",
        "PrivateCloudPhotoAssetDatabase",
        "CloudPhotoAssetSynchronizing",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/CloudPhotoAssetCoordinator.swift": {
        "public actor CloudPhotoAssetCoordinator",
        "database.accountStatus()",
        "database.ensureZone",
        "reconcile(",
        "temporaryStore.createUploadFile",
        "CloudPhotoAssetChecksum.validate",
        "CloudPhotoAssetDatabaseError.changeTokenExpired",
        "CloudPhotoAssetDatabaseError.recordNotFound",
        "retryPolicy.delay",
        "ensureCurrent",
        "generation &+= 1",
        "state.changeToken = page.changeToken",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/FileCloudPhotoAssetStores.swift": {
        "FileCloudPhotoAssetSyncStateStore",
        "FileCloudPhotoAssetTemporaryStore",
        ".completeFileProtection",
        "removeFile",
        "NoOpCloudPhotoAssetCoordinator",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/CloudKitPrivatePhotoAssetDatabase.swift": {
        "@preconcurrency import CloudKit",
        "public actor CloudKitPrivatePhotoAssetDatabase",
        "privateCloudDatabase",
        "CKRecordZone",
        "CKAsset(fileURL:",
        "recordZoneChanges(",
        "CKServerChangeToken",
        "requiringSecureCoding: true",
        "retryAfterSeconds",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/AssetStore/LocalPhotoAssetStore.swift": {
        "CloudPhotoAssetLocalStoring",
        "cloudAssetBytes(id:",
        "restoreCloudAsset(id:",
        "deleteCloudAsset(id:",
        "replacingExisting: true",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoLifecycleView.swift": {
        "assetSynchronizer: any CloudPhotoAssetSynchronizing",
        "await synchronizeAssets()",
    },
    "App/Application/TrackerFeatureBundle.swift": {
        "progressPhotoAssetSynchronizer",
        "makeProgressPhotoAssetSynchronizer",
        "guard case let .cloud(containerIdentifier, storeURL)",
        "NoOpCloudPhotoAssetCoordinator.shared",
        "CloudKitPrivatePhotoAssetDatabase",
        "FileCloudPhotoAssetSyncStateStore",
        "FileCloudPhotoAssetTemporaryStore",
    },
    ".github/workflows/ios.yml": {
        "Targeted M3.7-M3.9 photo lifecycle, gallery, and cloud asset tests",
        "scripts/test-ios.sh --only-testing ProgressPhotosKitTests",
    },
}

for relative_path, tokens in m39_production.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.9 production file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(
            f"{relative_path} is missing M3.9 production contracts: {absent}"
        )

m39_coordinator_path = root / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/CloudPhotoAssetCoordinator.swift"
m39_coordinator_text = m39_coordinator_path.read_text(encoding="utf-8")
if not any(
    token in m39_coordinator_text
    for token in ("temporaryStore.copyDownloadedFile", "record.stagedFileURL")
):
    raise SystemExit("M3.9 coordinator is missing a download consumption boundary")

m39_transfer_path = root / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/FileCloudPhotoAssetStores.swift"
m39_transfer_text = m39_transfer_path.read_text(encoding="utf-8")
if not any(
    token in m39_transfer_text
    for token in ("copyDownloadedFile", "stageDownload")
):
    raise SystemExit("M3.9 temporary store is missing a download staging boundary")

m39_lifecycle_path = root / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoLifecycleView.swift"
m39_lifecycle_text = m39_lifecycle_path.read_text(encoding="utf-8")
if not any(
    token in m39_lifecycle_text
    for token in ("await assetSynchronizer.synchronize()", "await assetSyncLifecycle.synchronize()")
):
    raise SystemExit("M3.9 lifecycle is missing cloud synchronization delegation")

m39_domain_source = (
    root
    / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/CloudPhotoAssetDomain.swift"
).read_text(encoding="utf-8")
m39_field_block = m39_domain_source.split("fieldNames = [", 1)[1].split("]", 1)[0]
m39_fields = set(re.findall(r'"([A-Za-z]+)"', m39_field_block))
m39_allowed_fields = {"assetID", "asset", "checksum", "byteCount"}
if m39_fields != m39_allowed_fields:
    raise SystemExit(
        f"M3.9 CKAsset record field allowlist changed: {sorted(m39_fields)}"
    )

m39_cloudkit_source = (
    root
    / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/CloudKitPrivatePhotoAssetDatabase.swift"
).read_text(encoding="utf-8")
m39_record_fields = set(re.findall(r'record\["([A-Za-z]+)"\]', m39_cloudkit_source))
if m39_record_fields != m39_allowed_fields:
    raise SystemExit(
        f"M3.9 CloudKit adapter persisted an unexpected field: {sorted(m39_record_fields)}"
    )
for forbidden_payload in ("date", "pose", "note", "filePath", "tracker", "health"):
    if re.search(rf'record\["{forbidden_payload}"\]', m39_cloudkit_source, re.I):
        raise SystemExit(
            f"M3.9 CKAsset record must not contain {forbidden_payload}"
        )

# These production-quality gates activate atomically when GREEN introduces the
# reference snapshot boundary. RED remains statically verifiable while the
# behavior tests fail to compile on the intentionally missing contracts.
if "CloudPhotoAssetReferenceSnapshotProviding" in m39_domain_source:
    for required in (
        "CloudPhotoAssetSystemRecord",
        "hasUsableBinaryAsset",
        "async throws -> CloudPhotoAssetSystemRecord?",
    ):
        if required not in m39_domain_source:
            raise SystemExit(
                f"M3.9 system record contract is missing binary presence: {required}"
            )
    for required in (
        "CloudPhotoAssetDeletionIntentReceipt",
        "public let intentID: UUID",
        "CloudPhotoAssetAccountAuthorization",
        "CloudPhotoAssetAccountResolution",
        "quarantineIdentityHint",
        "beginAccountResolution()",
        "activateAccountIdentity",
        "resolution: CloudPhotoAssetAccountResolution",
        "async throws -> CloudPhotoAssetAccountAuthorization",
        "suspendAccountAuthorization(_ authorization: CloudPhotoAssetAccountAuthorization)",
        "pendingDeletionIntents(",
        "async throws -> [CloudPhotoAssetDeletionIntentReceipt]",
        "pendingDeletionAssetIDs(",
        "forAccountIdentity accountIdentity: String",
        "unresolvedDeletionAssetIDs",
        "hasCommittedLocalDeletionIntent(assetID: String)",
        "-> CloudPhotoAssetDeletionIntentReceipt",
    ):
        if required not in m39_domain_source:
            raise SystemExit(
                f"M3.9 deletion intent protocol is missing account scope: {required}"
            )
    for required in (
        "CloudPhotoAssetInboundCleanupLease",
        "acquireCleanupLease(for assetID: String)",
        "releaseCleanupLease(_ lease: CloudPhotoAssetInboundCleanupLease)",
    ):
        if required not in m39_domain_source:
            raise SystemExit(
                f"M3.9 inbound cleanup journal is missing atomic lease contract: {required}"
            )
    for required in (
        "CloudPhotoAssetInboundApplyLease",
        "CloudPhotoAssetInboundApplyPreparation",
        "case prepared(CloudPhotoAssetInboundApplyLease)",
        "case discardedCommittedDeletion",
        "CloudPhotoAssetInboundApplying",
        "func prepareInboundApply(",
        "func commitInboundApply(",
        "func cancelInboundApply(",
    ):
        if required not in m39_domain_source:
            raise SystemExit(
                f"M3.9 domain is missing serialized inbound apply contract: {required}"
            )
    try:
        m39_inbound_protocol = m39_domain_source.split(
            "public protocol CloudPhotoAssetInboundApplying", 1
        )[1].split("public struct CloudPhotoAssetDeletionIntentReceipt", 1)[0]
    except IndexError as error:
        raise SystemExit(
            "M3.9 domain is missing serialized inbound apply signature"
        ) from error
    for required in (
        "id assetID: String",
        "forAccountIdentity accountIdentity: String",
        "async throws -> CloudPhotoAssetInboundApplyPreparation",
        "_ lease: CloudPhotoAssetInboundApplyLease",
        "bytes: Data",
    ):
        if required not in m39_inbound_protocol:
            raise SystemExit(
                f"M3.9 domain is missing serialized inbound apply signature: {required}"
            )
    if "clearAllCommittedDeletions" in m39_domain_source:
        raise SystemExit(
            "M3.9 deletion authority must not expose a destructive unscoped clear-all"
        )
    if "func suspendAccountAuthorization() async" in m39_domain_source:
        raise SystemExit(
            "M3.9 account resolution must use an opaque epoch instead of unqualified suspension"
        )

    for required in (
        "public protocol CloudPhotoAssetLocalStoring",
        "func storedAssetIDs()",
        "func usableCloudAssetIDs()",
    ):
        if required not in m39_domain_source:
            raise SystemExit(
                "M3.9 local cloud store must separate physical inventory from "
                f"usable availability: {required}"
            )
    try:
        m39_usable_inventory_body = local_photo_store_source.split(
            "public func usableCloudAssetIDs() async throws -> Set<String> {",
            1,
        )[1].split("private func prepareStorage", 1)[0]
    except IndexError as error:
        raise SystemExit(
            "M3.9 real local store is missing complete cloud asset availability"
        ) from error
    if "try!" in m39_usable_inventory_body:
        raise SystemExit(
            "M3.9 usable availability must propagate load errors without force-try"
        )
    for required in (
        "let physicalAssetIDs = try await storedAssetIDs()",
        "var usableAssetIDs: Set<String> = []",
        "for assetID in physicalAssetIDs.sorted()",
        "let full = try await loadAsset(id: assetID, variant: .full)",
        "guard case .available = full else { continue }",
        "let thumbnail = try await loadAsset(id: assetID, variant: .thumbnail)",
        "guard case .available = thumbnail else { continue }",
        "usableAssetIDs.insert(assetID)",
        "return usableAssetIDs",
    ):
        if required not in m39_usable_inventory_body:
            raise SystemExit(
                "M3.9 real local store must validate full and thumbnail before "
                f"reporting usable availability: {required}"
            )
    if "try?" in m39_usable_inventory_body or "catch" in m39_usable_inventory_body:
        raise SystemExit(
            "M3.9 usable availability must fail closed on protected-data and I/O errors"
        )
    for relative_path in (
        "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/AssetStore/LocalPhotoAssetStore.swift",
        "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/CloudPhotoAssetCoordinatorTests.swift",
        "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/CloudKitPrivatePhotoAssetDatabaseTests.swift",
        "Packages/HealthTrackingModules/Tests/PersistenceKitTests/ProgressPhotoRepositoryTests.swift",
    ):
        conformer_source = (root / relative_path).read_text(encoding="utf-8")
        if (
            "CloudPhotoAssetLocalStoring" in conformer_source
            and "func usableCloudAssetIDs()" not in conformer_source
        ):
            raise SystemExit(
                "M3.9 local cloud store conformer is missing explicit usable "
                f"availability: {relative_path}"
            )

    m39_coordinator_source = (
        root
        / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/CloudPhotoAssetCoordinator.swift"
    ).read_text(encoding="utf-8")
    for required in (
        "public func synchronize()",
        "referenceSnapshotProvider",
        "await referenceSnapshotProvider.snapshot()",
        "deletionIntentStore",
        "let accountResolution = await deletionIntentStore.beginAccountResolution()",
        "let accountAuthorization = try await deletionIntentStore.activateAccountIdentity(",
        "resolution: accountResolution",
        "await deletionIntentStore.suspendAccountAuthorization(accountAuthorization)",
        "pendingDeletionIntents(forAccountIdentity: accountIdentity)",
        "try validate(state: state)",
        "clearCommittedDeletion(",
        "clearCommittedDeletion(intent)",
        "forAccountIdentity: accountIdentity",
        "let deletions = committedDeletionIDs",
        "let referencedDeletionIntents = committedDeletionIntents.filter",
        "let referencedDeletionIDs = Set(referencedDeletionIntents.map(\\.assetID))",
        "onDiscard: { [temporaryStore = self.temporaryStore] page in",
        "inboundAssetApplier",
        "inboundAssetApplier.prepareInboundApply(",
        "inboundAssetApplier.commitInboundApply(",
        "inboundAssetApplier.cancelInboundApply(",
        "forAccountIdentity: accountIdentity",
        "case .discardedCommittedDeletion:",
        "temporaryStore.removeFile(at: record.stagedFileURL)",
    ):
        if required not in m39_coordinator_source:
            raise SystemExit(
                f"M3.9 shipped no-argument sync is missing injected quality contract: {required}"
            )
    if "localStore.storedAssetIDs()" in m39_coordinator_source:
        raise SystemExit(
            "M3.9 coordinator must not treat physical inventory as usable availability"
        )
    for required in (
        "let usableLocalAssetIDs = try await localStore.usableCloudAssetIDs()",
        "try validate(assetIDs: usableLocalAssetIDs)",
        "reconcile(usableLocalAssetIDs: usableLocalAssetIDs,",
    ):
        if required not in m39_coordinator_source:
            raise SystemExit(
                "M3.9 coordinator must reconcile complete usable availability: "
                f"{required}"
            )
    try:
        m39_cloud_reconcile_body = m39_coordinator_source.split(
            "private func reconcile(", 1
        )[1].split("private func markUploaded", 1)[0]
    except IndexError as error:
        raise SystemExit(
            "M3.9 coordinator is missing usable-availability reconciliation"
        ) from error
    for required in (
        "usableLocalAssetIDs: Set<String>",
        "let referencedUsable = usableLocalAssetIDs.intersection(referencedAssetIDs)",
        ".intersection(referencedUsable)",
        ".union(referencedUsable.subtracting(uploaded))",
        ".subtracting(usableLocalAssetIDs)",
        "state.changeToken = nil",
    ):
        if required not in m39_cloud_reconcile_body:
            raise SystemExit(
                "M3.9 incomplete uploaded assets must replay from nil without upload: "
                f"{required}"
            )
    try:
        m39_coordinator_init = m39_coordinator_source.split(
            "public init(", 1
        )[1].split(") {", 1)[0]
    except IndexError as error:
        raise SystemExit(
            "M3.9 coordinator must require an explicit inbound applier"
        ) from error
    if (
        "inboundAssetApplier: any CloudPhotoAssetInboundApplying"
        not in m39_coordinator_init
        or re.search(r"inboundAssetApplier\s*:[^,\n]*(?:\?|=)", m39_coordinator_init)
    ):
        raise SystemExit(
            "M3.9 coordinator must require an explicit inbound applier"
        )
    if (
        "recordInboundAssetID" in m39_coordinator_source
        or "restoreCloudAsset(id: record.assetID" in m39_coordinator_source
    ):
        raise SystemExit(
            "M3.9 coordinator must delegate inbound ownership to the serialized applier"
        )
    try:
        m39_apply_body = m39_coordinator_source.split(
            "private func apply(", 1
        )[1].split("private func performWithRetry", 1)[0]
    except IndexError as error:
        raise SystemExit(
            "M3.9 coordinator is missing deletion-aware inbound apply ordering"
        ) from error
    inbound_prepare = m39_apply_body.find(
        "inboundAssetApplier.prepareInboundApply("
    )
    precommit_generation_check = m39_apply_body.find(
        "try ensureCurrent(generation)",
        inbound_prepare,
    )
    inbound_commit = m39_apply_body.find(
        "inboundAssetApplier.commitInboundApply(",
        precommit_generation_check,
    )
    inbound_cancel = m39_apply_body.find(
        "inboundAssetApplier.cancelInboundApply(",
        inbound_prepare,
    )
    postcommit_generation_check = m39_apply_body.find(
        "try ensureCurrent(generation)",
        inbound_commit,
    )
    discard_case = m39_apply_body.find("case .discardedCommittedDeletion:")
    discard_return = m39_apply_body.find("return", discard_case)
    mark_uploaded = m39_apply_body.find("markUploaded(record.assetID, state: &state)")
    remove_deletion = m39_apply_body.find(
        "remove(record.assetID, from: &state.pendingDeletionAssetIDs)"
    )
    if not (
        0 <= inbound_prepare < discard_case < discard_return < mark_uploaded
        and discard_return < remove_deletion
    ):
        raise SystemExit(
            "M3.9 discarded committed deletion must not mutate uploaded/deletion state"
        )
    if not (
        0 <= inbound_prepare
        < precommit_generation_check
        < inbound_commit
        < postcommit_generation_check
        < mark_uploaded
        and inbound_prepare < inbound_cancel < mark_uploaded
    ):
        raise SystemExit(
            "M3.9 coordinator must generation-check and exact-cancel a prepared inbound lease"
        )
    if "inboundAssetApplier.applyInboundAsset(" in m39_apply_body:
        raise SystemExit(
            "M3.9 coordinator must not use the stale one-shot inbound apply boundary"
        )
    deletion_read = m39_coordinator_source.find(
        "pendingDeletionIntents(forAccountIdentity: accountIdentity)"
    )
    state_validation = m39_coordinator_source.find("try validate(state: state)")
    account_activation = m39_coordinator_source.find(
        "resolution: accountResolution"
    )
    reference_read = m39_coordinator_source.find(
        "await referenceSnapshotProvider.snapshot()"
    )
    if (
        state_validation < 0
        or account_activation < 0
        or state_validation > account_activation
        or account_activation > deletion_read
    ):
        raise SystemExit(
            "M3.9 account transition must validate state and activate the current "
            "scope before loading deletion intents"
        )
    neutralization_start = m39_coordinator_source.find(
        "let referencedDeletionIntents = committedDeletionIntents.filter"
    )
    neutralization_end = m39_coordinator_source.find(
        "committedDeletionIDs.subtract(referencedDeletionIDs)",
        neutralization_start,
    )
    neutralization_source = m39_coordinator_source[
        neutralization_start:neutralization_end
    ]
    if (
        neutralization_start < 0
        or neutralization_end < 0
        or "clearCommittedDeletion(intent)" not in neutralization_source
        or "assetID: assetID" in neutralization_source
        or "forAccountIdentity:" in neutralization_source
    ):
        raise SystemExit(
            "M3.9 referenced-intent neutralization must clear only exact observed receipts"
        )
    remote_delete_start = m39_coordinator_source.find(
        "private func processDeletions("
    )
    remote_delete_end = m39_coordinator_source.find(
        "private func processUploads(",
        remote_delete_start,
    )
    remote_delete_source = m39_coordinator_source[
        remote_delete_start:remote_delete_end
    ]
    if (
        remote_delete_start < 0
        or remote_delete_end < 0
        or "database.deleteRecord(" not in remote_delete_source
        or "clearCommittedDeletion(\n                assetID: assetID," not in remote_delete_source
        or "forAccountIdentity: accountIdentity" not in remote_delete_source
    ):
        raise SystemExit(
            "M3.9 confirmed remote deletion must clear all matching current-account intents"
        )
    account_resolution_begin = m39_coordinator_source.find(
        "let accountResolution = await deletionIntentStore.beginAccountResolution()"
    )
    account_status_read = m39_coordinator_source.find("database.accountStatus()")
    if (
        account_resolution_begin < 0
        or account_status_read < 0
        or account_resolution_begin > account_status_read
    ):
        raise SystemExit(
            "M3.9 coordinator must begin a fresh account-resolution epoch before status resolution"
        )
    if m39_coordinator_source.count(
        "await deletionIntentStore.suspendAccountAuthorization(accountAuthorization)"
    ) < 2:
        raise SystemExit(
            "M3.9 coordinator must close bounded account authorization on success and failure"
        )
    if deletion_read < 0 or reference_read < 0 or deletion_read > reference_read:
        raise SystemExit(
            "M3.9 coordinator must snapshot committed deletions before references"
        )
    if (
        "clearAllCommittedDeletions" in m39_coordinator_source
        or "pendingDeletionAssetIDs()" in m39_coordinator_source
    ):
        raise SystemExit(
            "M3.9 coordinator must never read or clear unscoped deletion authority"
        )

    m39_file_store_source = m39_transfer_text
    for required in (
        "activeAccountResolutionID",
        "public func beginAccountResolution()",
        "activeAccountAuthorization = nil",
        "activeAccountResolutionID = resolution.resolutionID",
        "guard activeAccountResolutionID == resolution.resolutionID else",
        "activeAccountResolutionID = nil",
        "throw CancellationError()",
    ):
        if required not in m39_file_store_source:
            raise SystemExit(
                f"M3.9 account activation is missing resolution-epoch CAS: {required}"
            )
    resolution_begin_start = m39_file_store_source.find(
        "public func beginAccountResolution()"
    )
    resolution_activate_start = m39_file_store_source.find(
        "public func activateAccountIdentity(",
        resolution_begin_start,
    )
    resolution_begin_source = m39_file_store_source[
        resolution_begin_start:resolution_activate_start
    ]
    if (
        resolution_begin_start < 0
        or resolution_activate_start < 0
        or "activeAccountAuthorization = nil" not in resolution_begin_source
        or "activeAccountResolutionID = resolution.resolutionID"
        not in resolution_begin_source
    ):
        raise SystemExit(
            "M3.9 account activation is missing resolution-epoch CAS: begin boundary"
        )
    for required in (
        "FileCloudPhotoAssetDeletionIntentRecord",
        "static let currentSchemaVersion = 3",
        "public func pendingDeletionIntents(",
        "async throws -> [CloudPhotoAssetDeletionIntentReceipt]",
        "intent.accountIdentity == accountIdentity",
        "intent.quarantineIdentityHint == nil",
        "intentID: intent.intentID",
        "intentID: UUID()",
        "state.intents",
        "$0.intentID == intent.intentID",
        "$0.assetID == canonicalID",
        "state.intents[index].accountIdentity = accountIdentity",
        "state.intents[index].quarantineIdentityHint = nil",
        "FileCloudPhotoAssetDeletionIntentV2State",
    ):
        if required not in m39_file_store_source:
            raise SystemExit(
                f"M3.9 deletion receipts are missing stable exact intent identity: {required}"
            )
    receipt_clear_start = m39_file_store_source.find(
        "public func clearCommittedDeletion(\n        _ intent:"
    )
    account_clear_start = m39_file_store_source.find(
        "public func clearCommittedDeletion(\n        assetID:",
        receipt_clear_start,
    )
    receipt_clear_source = m39_file_store_source[
        receipt_clear_start:account_clear_start
    ]
    if (
        receipt_clear_start < 0
        or account_clear_start < 0
        or "intent.intentID" not in receipt_clear_source
        or "storedIntent.assetID == canonicalID" not in receipt_clear_source
        or "intent.accountIdentity" in receipt_clear_source
        or "intent.quarantineIdentityHint" in receipt_clear_source
    ):
        raise SystemExit(
            "M3.9 deletion receipts are missing stable exact intent identity: "
            "receipt clear must locate one exact ID across promotion and validate asset"
        )
    for required in (
        "activeAccountIdentity",
        "activeAccountAuthorization",
        "accountAssetIDs",
        "unresolvedAssetIDs",
        "quarantinedIntents",
        "accountIdentityHint",
        "lastVerifiedAccountIdentity",
        "quarantineIdentityHint",
        "static let currentSchemaVersion = 3",
        "state.intents[index].quarantineIdentityHint == accountIdentity",
        "forAccountIdentity accountIdentity: String",
        "unresolvedDeletionAssetIDs",
        "JSONDecoder().decode([String].self",
    ):
        if required not in m39_file_store_source:
            raise SystemExit(
                f"M3.9 file deletion store is missing scoped/quarantine durability: {required}"
            )
    for required in (
        "if let activeAccountIdentity {",
        "accountIdentity: activeAccountIdentity",
    ):
        if required not in m39_file_store_source:
            raise SystemExit(
                "M3.9 file deletion store must serialize records into the exact "
                f"active or legacy-quarantine scope: {required}"
            )
    for required in (
        "cleanupLeasesByAssetID",
        "cleanupLeaseWaitersByAssetID",
        "waitForCleanupLeaseRelease",
        "waitForInboundRecordWaiter",
        "inboundRecordWaiterIDs",
        "CloudPhotoAssetInboundCleanupLease",
        "String: [UUID: CheckedContinuation<Void, Error>]",
        "cleanupLeaseWaitersByAssetID[canonicalID]?.isEmpty != false",
        "cleanupLeasesByAssetID[canonicalID] == lease.leaseID",
        "withTaskCancellationHandler",
        "waiterID: UUID",
        "cancelInboundRecordWaiter",
        "removeValue(forKey: waiterID)",
        "continuation.resume(throwing: CancellationError())",
        "try await waitForCleanupLeaseRelease(\n                for: canonicalID,\n                waiterID: waiterID\n            )\n            try Task.checkCancellation()",
        "waiter.resume(returning: ())",
    ):
        if required not in m39_file_store_source:
            raise SystemExit(
                f"M3.9 file inbound journal is missing serialized cleanup lease: {required}"
            )
    if "temporaryStore.copyDownloadedFile" in m39_coordinator_source:
        raise SystemExit(
            "M3.9 coordinator must not copy a system-owned download after adapter return"
        )
    if "clearInboundAssetID" in m39_coordinator_source:
        raise SystemExit(
            "M3.9 coordinator must retain inbound intent until repository metadata ownership"
        )
    if "hasCommittedLocalDeletionIntent" in m39_coordinator_source:
        raise SystemExit(
            "M3.9 all-scope local suppression must never authorize coordinator remote deletion"
        )
    try:
        m39_local_suppression_body = m39_file_store_source.split(
            "public func hasCommittedLocalDeletionIntent(assetID: String)", 1
        )[1].split("public func recordCommittedDeletion", 1)[0]
    except IndexError as error:
        raise SystemExit(
            "M3.9 file deletion store is missing all-scope local suppression"
        ) from error
    for required in (
        "canonicalAssetID(assetID)",
        "loadState()",
        "state.intents.contains { $0.assetID == canonicalID }",
    ):
        if required not in m39_local_suppression_body:
            raise SystemExit(
                f"M3.9 local suppression must inspect every persisted intent scope: {required}"
            )
    if "accountIdentity" in m39_local_suppression_body:
        raise SystemExit(
            "M3.9 local suppression must not filter scoped, hinted, or unresolved intents"
        )
    if m39_file_store_source.count(
        "public func hasCommittedLocalDeletionIntent(assetID: String)"
    ) < 2:
        raise SystemExit(
            "M3.9 no-op and durable deletion stores must expose local suppression"
        )
    for required in (
        "public actor DirectCloudPhotoAssetInboundApplier",
        "public func prepareInboundApply(",
        "public func commitInboundApply(",
        "public func cancelInboundApply(",
        "activeInboundApplyLeases",
        "activeInboundApplyLeases[lease.leaseID] = lease",
        "guard activeInboundApplyLeases[lease.leaseID] == lease else",
        "activeInboundApplyLeases.removeValue(forKey: lease.leaseID)",
    ):
        if required not in m39_file_store_source:
            raise SystemExit(
                f"M3.9 direct inbound applier is missing exact two-phase lease semantics: {required}"
            )

    for required in (
        "record.hasUsableBinaryAsset else { return nil }",
        "CloudPhotoAssetSystemRecord(",
        "CloudKitPhotoAssetRecordMapper.systemRecord(from: record)",
        "enum CloudKitPhotoAssetRecordMapper",
        "static func systemRecord(",
        "from record: CKRecord",
        "private static func hasUsableBinaryAsset(in record: CKRecord) -> Bool",
        'record["asset"] as? CKAsset',
        "fileURL.isFileURL",
        "resourceValues.isRegularFile == true",
        "resourceValues.isReadable == true",
    ):
        if required not in m39_cloudkit_source:
            raise SystemExit(
                f"M3.9 actual adapter is missing CKAsset binary-presence repair gate: {required}"
            )
    for required in (
        "CloudKitPhotoAssetRecordModifying",
        "CloudKitPhotoAssetRecordModifyResults",
        "CloudKitPhotoAssetRecordSaver",
        "recordModifier.modifyRecords(",
        "savePolicy: .changedKeys",
        "atomically: true",
        "saveResults[record.recordID]",
        "deleteResults.isEmpty",
        "try recordResult.get()",
        "CloudKitPhotoAssetRecordMapper.uploadRecord(",
        "database.modifyRecords(",
        "withExtendedLifetime(record)",
        "defer { withExtendedLifetime(record) {} }",
    ):
        if required not in m39_cloudkit_source:
            raise SystemExit(
                f"M3.9 CloudKit repair is missing explicit atomic changed-keys modify: {required}"
            )
    if "database.save(record)" in m39_cloudkit_source:
        raise SystemExit(
            "M3.9 same-ID asset repair must not use default change-tag save policy"
        )

    m39_repository_source = (
        root
        / "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataProgressPhotoRepository.swift"
    ).read_text(encoding="utf-8")
    for required in (
        "deletionIntentStore",
        "recordCommittedDeletion",
        "clearCommittedDeletion",
        "inboundAssetJournal",
        "pendingInboundAssetIDs",
        "CloudPhotoAssetInboundApplying",
        "inboundAssetStore",
        "public func prepareInboundApply(",
        "public func commitInboundApply(",
        "public func cancelInboundApply(",
    ):
        if required not in m39_repository_source:
            raise SystemExit(
                f"M3.9 repository is missing durable cloud handshake contract: {required}"
            )
    if (
        "let deletionIntent: CloudPhotoAssetDeletionIntentReceipt"
        not in m39_repository_source
        or m39_repository_source.count(
            "clearCommittedDeletion(deletionIntent)"
        ) < 2
    ):
        raise SystemExit(
            "M3.9 repository compensation must clear the exact recorded scoped receipt"
        )
    try:
        m39_snapshot_body = m39_repository_source.split(
            "public func snapshot() async throws -> CloudPhotoAssetReferenceSnapshot {",
            1,
        )[1].split("public func deletePhoto", 1)[0]
        m39_reconcile_body = m39_repository_source.split(
            "private func reconcileAssetStorageIfNeeded",
            1,
        )[1].split("private func recordPendingCleanup", 1)[0]
        m39_retry_body = m39_repository_source.split(
            "public func retryPendingAssetCleanup() async throws {",
            1,
        )[1].split("private func reconcileAssetStorageIfNeeded", 1)[0]
    except IndexError as error:
        raise SystemExit(
            "M3.9 repository is missing snapshot/inbound reconciliation boundaries"
        ) from error
    if "reconcileAssetStorageIfNeeded(rows: rows)" not in m39_snapshot_body:
        raise SystemExit(
            "M3.9 repository snapshot must reconcile inbound metadata ownership"
        )
    inbound_read = m39_reconcile_body.find(
        "loadPendingInboundAssetIDsFailClosed()"
    )
    orphan_guard = m39_reconcile_body.find(
        "guard !hasReconciledAssetStorage else { return }"
    )
    if inbound_read < 0 or orphan_guard < 0 or inbound_read > orphan_guard:
        raise SystemExit(
            "M3.9 inbound ownership reconciliation must precede one-shot orphan sweep"
        )
    fresh_inbound_call = "try await loadPendingInboundAssetIDsFailClosed()"
    fresh_inbound_guard = "freshPendingInboundAssetIDs.contains(assetID)"
    if (
        fresh_inbound_call not in m39_retry_body
        or fresh_inbound_guard not in m39_retry_body
    ):
        raise SystemExit(
            "M3.9 pending cleanup retry must reread and subtract fresh inbound ownership"
        )
    if (
        m39_reconcile_body.count(fresh_inbound_call) < 2
        or fresh_inbound_guard not in m39_reconcile_body
    ):
        raise SystemExit(
            "M3.9 orphan sweep must fail closed on a fresh inbound read at delete boundary"
        )
    if "private func loadPendingInboundAssetIDsFailClosed" not in m39_repository_source:
        raise SystemExit(
            "M3.9 repository is missing the fail-closed inbound journal read boundary"
        )
    for required in (
        "deleteAssetIfNotInbound",
        "acquireCleanupLease(for: assetID)",
        "releaseCleanupLease(lease)",
    ):
        if required not in m39_repository_source:
            raise SystemExit(
                f"M3.9 repository is missing atomic inbound-safe deletion: {required}"
            )
    if m39_repository_source.count("deleteAssetIfNotInbound(assetID)") < 2:
        raise SystemExit(
            "M3.9 retry and initial orphan sweep must share the atomic inbound-safe delete boundary"
        )
    if m39_repository_source.count("releaseCleanupLease(lease)") < 2:
        raise SystemExit(
            "M3.9 repository must release the inbound cleanup lease on success and failure"
        )
    try:
        m39_inbound_prepare_body = m39_repository_source.split(
            "public func prepareInboundApply(", 1
        )[1].split("public func commitInboundApply(", 1)[0]
        m39_inbound_commit_body = m39_repository_source.split(
            "public func commitInboundApply(", 1
        )[1].split("public func cancelInboundApply(", 1)[0]
        m39_inbound_cancel_body = m39_repository_source.split(
            "public func cancelInboundApply(", 1
        )[1].split("public func fetchPhotos()", 1)[0]
    except IndexError as error:
        raise SystemExit(
            "M3.9 repository is missing serialized inbound apply transaction"
        ) from error
    for required in (
        "await acquireExclusiveOperation()",
        "hasCommittedLocalDeletionIntent(assetID: assetID)",
        "return .discardedCommittedDeletion",
        "activeInboundApplyLease = lease",
        "return .prepared(lease)",
    ):
        if required not in m39_inbound_prepare_body:
            raise SystemExit(
                "M3.9 repository is missing retained inbound preparation transaction: "
                + required
            )
    if (
        "defer { releaseExclusiveOperation() }" in m39_inbound_prepare_body
        or m39_inbound_prepare_body.count("releaseExclusiveOperation()") < 2
    ):
        raise SystemExit(
            "M3.9 repository preparation must retain the lock only for an exact prepared lease"
        )
    for required in (
        "activeInboundApplyLease",
        "guard activeInboundApplyLease == lease else",
        "defer { releaseInboundApplyLease(lease) }",
        "inboundAssetJournal.recordInboundAssetID(lease.assetID)",
        "try Task.checkCancellation()",
        "inboundAssetStore.restoreCloudAsset(id: lease.assetID, bytes: bytes)",
    ):
        if required not in m39_inbound_commit_body:
            raise SystemExit(
                "M3.9 repository inbound commit must consume and release one exact lease: "
                + required
            )
    for required in (
        "guard activeInboundApplyLease == lease else { return }",
        "releaseInboundApplyLease(lease)",
    ):
        if required not in m39_inbound_cancel_body:
            raise SystemExit(
                "M3.9 repository inbound cancel must release only its exact lease: "
                + required
            )
    for required in (
        "private func releaseInboundApplyLease(",
        "activeInboundApplyLease = nil",
    ):
        if required not in m39_repository_source:
            raise SystemExit(
                "M3.9 repository inbound lease release must be exact and reusable: "
                + required
            )
    if m39_repository_source.count(
        "guard activeInboundApplyLease == lease else { return }"
    ) < 2:
        raise SystemExit(
            "M3.9 stale inbound lease cancellation must not release a newer lease"
        )
    intent_read = m39_inbound_prepare_body.find(
        "hasCommittedLocalDeletionIntent(assetID: assetID)"
    )
    discard = m39_inbound_prepare_body.find("return .discardedCommittedDeletion")
    prepared = m39_inbound_prepare_body.find("return .prepared(lease)")
    journal_record = m39_inbound_commit_body.find(
        "inboundAssetJournal.recordInboundAssetID(lease.assetID)"
    )
    cancellation_check = m39_inbound_commit_body.find(
        "try Task.checkCancellation()",
        journal_record,
    )
    restore = m39_inbound_commit_body.find(
        "inboundAssetStore.restoreCloudAsset(id: lease.assetID, bytes: bytes)"
    )
    if not (
        0 <= intent_read < discard < prepared
        and 0 <= journal_record < cancellation_check < restore
    ):
        raise SystemExit(
            "M3.9 repository inbound prepare/commit must fail closed before journal and restore"
        )
    if "releaseExclusiveOperation()" in m39_inbound_prepare_body.split(
        "return .prepared(lease)", 1
    )[0].rsplit("return .discardedCommittedDeletion", 1)[-1]:
        raise SystemExit(
            "M3.9 repository must retain its exclusive operation with a prepared lease"
        )
    if (
        "as? CloudPhotoAssetLocalStoring" in m39_repository_source
        or "as! CloudPhotoAssetLocalStoring" in m39_repository_source
    ):
        raise SystemExit(
            "M3.9 repository inbound restore dependency must be explicit and type-safe"
        )

    m39_factory_source = (
        root / "App/Application/TrackerFeatureBundle.swift"
    ).read_text(encoding="utf-8")
    for local_boundary in (
        "guard case .cloud = environment else",
        "NoOpCloudPhotoAssetDeletionIntentStore.shared",
        "NoOpCloudPhotoAssetInboundJournal.shared",
    ):
        if local_boundary not in m39_factory_source:
            raise SystemExit(
                "M3.9 local/UI composition must not persist cloud handshakes: "
                + local_boundary
            )
    for declaration in (
        "let deletionIntentStore = FileCloudPhotoAssetDeletionIntentStore(",
        "let inboundAssetJournal = FileCloudPhotoAssetInboundJournal(",
    ):
        if m39_factory_source.count(declaration) != 1:
            raise SystemExit(
                f"M3.9 app composition must create one shared provider: {declaration}"
            )
    for shared_argument in (
        "deletionIntentStore: deletionIntentStore",
    ):
        if m39_factory_source.count(shared_argument) != 2:
            raise SystemExit(
                f"M3.9 repository and coordinator must receive the same provider: {shared_argument}"
            )
    if m39_factory_source.count("inboundAssetJournal: inboundAssetJournal") != 1:
        raise SystemExit(
            "M3.9 repository must receive the one shared inbound journal"
        )
    if m39_factory_source.count(
        "referenceSnapshotProvider: progressPhotoRepository"
    ) != 1:
        raise SystemExit(
            "M3.9 shipped coordinator must receive the real repository snapshot provider"
        )
    for shared_inbound_contract in (
        "inboundAssetStore: progressPhotoAssetStore",
        "inboundAssetApplier: progressPhotoRepository",
        "any CloudPhotoAssetReferenceSnapshotProviding & CloudPhotoAssetInboundApplying",
    ):
        if shared_inbound_contract not in m39_factory_source:
            raise SystemExit(
                "M3.9 shipped composition must share one repository inbound transaction: "
                + shared_inbound_contract
            )
    transfer_declaration = (
        "let cloudPhotoAssetTransferStore = FileCloudPhotoAssetTemporaryStore("
    )
    if m39_factory_source.count(transfer_declaration) != 1:
        raise SystemExit(
            "M3.9 app composition must create exactly one shared cloud transfer store"
        )
    for shared_transfer_argument in (
        "downloadStore: cloudPhotoAssetTransferStore",
        "temporaryStore: cloudPhotoAssetTransferStore",
    ):
        if m39_factory_source.count(shared_transfer_argument) != 1:
            raise SystemExit(
                "M3.9 adapter and coordinator must receive the same transfer store: "
                + shared_transfer_argument
            )

    for required in (
        "downloadStore.stageDownload(",
        "accountIdentityProvider.accountIdentity()",
        "let owned = try withExtendedLifetime(record) {",
        "lifetimeOwner: asset",
    ):
        if required not in m39_cloudkit_source:
            raise SystemExit(
                f"M3.9 actual CloudKit adapter is missing ownership/account contract: {required}"
            )
    if "stagedFileURL: stagedFileURL" in m39_cloudkit_source:
        raise SystemExit(
            "M3.9 CloudKit adapter must not return the system CKAsset URL"
        )

    m39_file_store_source = (
        root
        / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/FileCloudPhotoAssetStores.swift"
    ).read_text(encoding="utf-8")
    m39_transfer_store = m39_file_store_source.split(
        "public final class FileCloudPhotoAssetTemporaryStore", 1
    )[1]
    for forbidden in (
        "fileManager.copyItem",
        "Data(contentsOf:",
        "readToEnd",
    ):
        if forbidden in m39_transfer_store:
            raise SystemExit(
                f"M3.9 download staging must not use unbounded I/O: {forbidden}"
            )
    for required in (
        "FileHandle",
        "fileHandleFactory",
        "read(upToCount: remaining + 1)",
        "isCanonicalTransferFileName",
    ):
        if required not in m39_transfer_store:
            raise SystemExit(
                f"M3.9 download staging is missing bounded streaming primitive: {required}"
            )
    if m39_transfer_store.count("isCanonicalTransferFileName(") < 3:
        raise SystemExit(
            "M3.9 canonical transfer ownership must gate both sweep and access"
        )
    if "guard isOwned(url) else" not in m39_transfer_store:
        raise SystemExit(
            "M3.9 coordinator reads must retain the app-owned transfer boundary"
        )
    try:
        m39_validated_copy = m39_transfer_store.split(
            "private func copyValidatedDownload", 1
        )[1].split("private func copyFile", 1)[0]
    except IndexError as error:
        raise SystemExit(
            "M3.9 download staging is missing its validated streaming boundary"
        ) from error
    if "try close(reader: reader, writer: writer)" not in m39_validated_copy:
        raise SystemExit(
            "M3.9 validated staging must propagate writer/reader close failure"
        )

    m39_lifecycle_source = (
        root
        / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoLifecycleView.swift"
    ).read_text(encoding="utf-8")
    if "await assetSyncLifecycle.synchronize()" not in m39_lifecycle_source:
        raise SystemExit(
            "M3.9 shipped lifecycle view must delegate successful sync cache repair"
        )
    if "await assetSynchronizer.synchronize()" in m39_lifecycle_source:
        raise SystemExit(
            "M3.9 lifecycle view must not bypass the tested sync lifecycle"
        )
    for required in (
        "accountIdentity",
        "CloudPhotoAssetReferenceSnapshotProviding",
        "CloudPhotoAssetDeletionIntentStoring",
        "CloudPhotoAssetInboundJournaling",
    ):
        if required not in m39_domain_source:
            raise SystemExit(
                f"M3.9 cloud domain is missing persisted identity/provider contract: {required}"
            )
m310_general_message = (
    "Hareketi durdur. Kalıcı veya kötüleşen belirtiler bir sağlık profesyoneli "
    "tarafından değerlendirilmelidir. Yeni veya belirgin şekilde kötüleşen kol veya "
    "bacakta güçsüzlük ya da uyuşma, el becerisinde kayıp, denge veya yürümede "
    "değişiklik ya da mesane veya bağırsak işlevinde değişiklik acil tıbbi "
    "değerlendirme gerektirir."
)
m310_urgent_message = (
    "Hareketi durdur. Yeni veya belirgin şekilde kötüleşen kol veya bacakta "
    "güçsüzlük ya da uyuşma, el becerisinde kayıp, denge veya yürümede "
    "değişiklik ya da mesane veya bağırsak işlevinde değişiklik acil tıbbi "
    "değerlendirme gerektirir."
)


def swift_assigned_string(source: str, name: str, seen: set[str] | None = None) -> str | None:
    match = re.search(
        rf"\b(?:private\s+)?(?:static\s+)?let\s+{re.escape(name)}\s*=",
        source,
    )
    if match is None:
        return None

    expression_lines = []
    started = False
    for line in source[match.end():].splitlines():
        stripped = line.strip()
        if not stripped and not started:
            continue
        if stripped.startswith('"') or stripped.startswith("+"):
            expression_lines.append(stripped)
            started = True
            continue
        break

    pieces = re.findall(r'"((?:\\.|[^"\\])*)"', "\n".join(expression_lines))
    if not pieces:
        return None
    value = "".join(pieces)

    visited = set() if seen is None else set(seen)
    if name in visited:
        return None
    visited.add(name)

    def resolve_interpolation(interpolation: re.Match[str]) -> str:
        dependency = interpolation.group(1)
        resolved = swift_assigned_string(source, dependency, visited)
        return interpolation.group(0) if resolved is None else resolved

    value = re.sub(r"\\\(([A-Za-z_][A-Za-z0-9_]*)\)", resolve_interpolation, value)
    return (
        value.replace(r"\n", "\n")
        .replace(r"\t", "\t")
        .replace(r'\"', '"')
        .replace(r"\\", "\\")
    )


m310_tests = {
    "Packages/HealthTrackingModules/Tests/HealthSafetyKitTests/MedicalSafetyPresentationTests.swift": {
        "testOHPAndIncreasingSymptomsPublishCompleteGeneralLevelTwoInformation",
        "testMissingSymptomAnswerPublishesCompleteNonUrgentFailClosedLevelTwo",
        ".missingSymptomAnswer",
        "expectedGeneralMessage",
        "expectedUrgentMessage",
        "notice.message,\n            expectedGeneralMessage",
        "testEachCervicalRedFlagAlonePublishesExactUrgentMessageAndOverridesEveryGeneralTrigger",
        "for flag in CervicalRedFlag.allCases",
        "triggers: [.cervicalRedFlags([flag])]",
        "for generalTrigger in generalTriggers",
        "triggers: [generalTrigger, .cervicalRedFlags([flag])]",
        "XCTAssertEqual(notice.kind, .urgentAssessmentInformation",
        "XCTAssertTrue(notice.requiresUrgentAssessment",
        "XCTAssertEqual(notice.message, expectedUrgentMessage",
        "assertContainsNoNumericMedicalThreshold",
    },
    "Packages/HealthTrackingModules/Tests/DesignSystemTests/MedicalSafetyMotionPolicyTests.swift": {
        "testReduceMotionSelectsIdentityAndDefaultSelectsOpacity",
        "TransitionProbe.identity",
        "TransitionProbe.opacity",
        "identity:",
        "opacity:",
    },
    "Packages/HealthTrackingModules/Tests/DesignSystemTests/MedicalSafetyFocusPolicyTests.swift": {
        "testLevelTwoAppearanceActivatesHeadingFocusAndRemovalClearsIt",
        "MedicalSafetyFocusPolicy.headingFocused(isLevelTwoPresented: true)",
        "MedicalSafetyFocusPolicy.headingFocused(isLevelTwoPresented: false)",
        "XCTAssertTrue(",
        "XCTAssertFalse(",
    },
    "Packages/HealthTrackingModules/Tests/MetricsKitTests/PostureViewModelTests.swift": {
        "testLoadOrdersHistoryAndWallTestOnlyRecordDoesNotTriggerSafety",
        "XCTAssertNil(viewModel.safetyPresentation.levelTwo)",
        "viewModel.previousExplicitSymptomScore, 3",
    },
    "Packages/HealthTrackingModules/Tests/GuidanceKitTests/OHPSafetyGateTests.swift": {
        "testOnlyExplicitSymptomFreeResponseAllowsLoadIncrease",
        "safetyStop: OHPSafetyGate.SafetyStop?",
        ".symptomsPresent,",
        ".blocked(.previousSymptomsPresent),",
        ".uncertain,",
        ".blocked(.previousResponseUncertain),",
        ".init(alternative: .halfKneelingDBPress)",
        "XCTAssertEqual(decision.safetyStop, expectation.safetyStop)",
    },
    "Packages/HealthTrackingModules/Tests/TrainingKitTests/SessionViewModelTests.swift": {
        "TrainingSymptomSafetyContext",
        "symptomSafetyPresentationProvider",
        ".priorOverheadPressResponse(.notAsked)",
        ".priorOverheadPressResponse(.uncertain)",
        "missingAnswerSafetyPresentation",
        "An explicit symptom-free answer must clear only the fail-closed missing-answer L2.",
        ".stopped(alternative: heldRepository.ohpSafeAlternative)",
        "testStoredPriorSymptomsAndUncertaintyStopOHPAtTheSafeAlternative",
        "testAnsweringPriorSymptomsOrUncertaintyStopsOHPAtTheSafeAlternative",
        "testCurrentOHPSymptomStopsBeforeTheRepositoryWriteCompletes",
        "waitUntilOHPSymptomUpdateIsSuspended",
        ".saving(request: expectedRequest)",
        "A pending exact write must reject a second write or retry.",
        "testCurrentOHPSymptomWriteFailureRetainsStopAndRetriesTheExactRequestOnce",
        ".failed(request: request)",
        "XCTAssertTrue(viewModel.hasPendingCurrentOHPSymptomWrite)",
        "Pending current-symptom persistence must block exercise progress and completion.",
        "A failed pending write must keep route actions fail closed until exact retry succeeds.",
        "repository.deletedSessionIDs.count",
        "retryCurrentOHPSymptomWrite",
        "[request.repositoryUpdate, request.repositoryUpdate]",
        "Retry must preserve the original session, response, and timestamp.",
        "XCTAssertEqual(symptomClient.events, [expectedEvent])",
        "testAdvanceRouteFirstRejectsSymptomAndDuplicateRoutesUntilChosenProgressCompletes",
        "testGoBackRouteFirstRejectsSymptomUntilChosenProgressCompletes",
        "testFinishRouteFirstKeepsTheLockThroughProgressAndTransition",
        "testRouteLockClearsAfterAppliedProgressFailureWithoutAcceptingSymptom",
        "waitUntilProgressUpdateIsSuspended",
        "waitUntilTransitionIsSuspended",
        "XCTAssertTrue(viewModel.isSessionRouteMutationInFlight)",
        "XCTAssertFalse(viewModel.canReportCurrentOHPSymptom)",
        "XCTAssertTrue(repository.ohpSymptomUpdates.isEmpty)",
        "XCTAssertEqual(repository.progressUpdates.count, progressCount + 1)",
        "XCTAssertEqual(repository.progress?.stage, .cooldown)",
        "XCTAssertEqual(repository.progress?.stage, .warmup)",
        "XCTAssertEqual(repository.progress?.stage, .summary)",
        "XCTAssertEqual(viewModel.state, .failed(.progress))",
        "testDeletionFailurePreservesStoppedSymptomRetryAndExactRequest",
        "testSuccessfulDeletionIsTheOnlyDeletionPathThatDiscardsPendingSymptomRetry",
        "testDeleteFirstLeaseRejectsSymptomRoutesAndDuplicateDeleteUntilSuccess",
        "testSuspendedDeletionFailureRetainsStoppedExactRetryUntilLeaseReleases",
        "testRouteFirstLeaseRejectsDeletionRequestAndConfirmationBeforeRepositoryAwait",
        "testCancelledDeletionReleasesLeaseAndPreservesExactStoppedRetry",
        "waitUntilDeletionIsSuspended",
        "repository.suspendNextDeletion()",
        "repository.resumeSuspendedDeletion()",
        "deletion.cancel()",
        "try Task.checkCancellation()",
        "deleteAttempts.append(id)",
        "XCTAssertTrue(viewModel.isSessionDeletionInFlight)",
        "XCTAssertEqual(repository.deleteAttempts, [sessionID])",
        "XCTAssertTrue(viewModel.hasSessionDeletionFailure)",
        "XCTAssertEqual(viewModel.state, stoppedState)",
        "XCTAssertTrue(repository.deletedSessionIDs.isEmpty)",
        "XCTAssertEqual(repository.deletedSessionIDs, [sessionID])",
        "testOrdinaryDeletionFailureRetainsTheExistingRecoverableFailureRoute",
        "XCTAssertEqual(viewModel.state, .failed(.deletion))",
        "testStartTailOwnsSessionUntilInitialProgressFinishesAndDeleteFirstRejectsRestart",
        "testRestoredStartKeepsItsOwnerThroughTheActiveSymptomJournalTail",
        "testWarmupAndCooldownChecklistOwnersBlockDeletionUntilProgressReturns",
        "testPriorResponseAndDeloadOwnersBlockDeletionThroughRepositoryStateWrites",
        "testSetSaveAndExactRetryEachOwnTheirWholeRepositoryLifetime",
        "testSummarySaveOwnerBlocksDeletionUntilItsDismissalCommits",
        "testOverlappingOwnersReleaseOnlyTheirExactTokenBeforeDeletionBecomesAvailable",
        "testCancelledSessionMutationReleasesOnlyItsOwnerAndAllowsDeletion",
        "testJournalRetryMayFinishAfterDeletionWithoutRepublishingSessionState",
        "XCTAssertEqual(viewModel.activeSessionMutationCount, 2)",
        '"The first completion must remove only its exact owner token."',
        '"Metrics-only journal retry must not own the session deletion boundary."',
        "assertDeletionRejectedWhileSessionMutationOwned",
        "suspendNextDeloadUpdate",
        "suspendNextSetSave",
        "suspendNextSummaryUpdate",
        "suspendNextRecord",
        "OneShotSuspensionGate",
    },
    "HealthTrackingAppTests/TodayCompositionTests.swift": {
        "testAppRootExplicitInitializerSupportsComposedAndDefaultMedicalSafetyController",
        "testMedicalSafetyFirstUseEvidenceRequiresOneExplicitUITestFlag",
        "AppUITestLaunchConfiguration.medicalSafetyFirstUseEvidenceFlag",
        ".exposesMedicalSafetyFirstUseEvidence",
        "Duplicate medical-safety evidence flags must fail closed.",
        "rootInitializerIsTypeChecked",
        "rootInitializerWithMedicalSafetyControllerIsTypeChecked",
        "medicalSafetyAcknowledgementController:",
        "dependencies.medicalSafetyAcknowledgementController",
    },
    "HealthTrackingAppTests/SymptomJournalAdapterTests.swift": {
        "testStructuredMissingOHPSessionResponsesMapToCentralFailClosedPresentation",
        "OHPSymptomResponse.notAsked, .uncertain",
        "TrainingSymptomSafetyMapper.presentation",
        ".priorOverheadPressResponse(response)",
        ".priorOverheadPressResponse(.symptomFree)",
        "expectedGeneralMessage",
        "XCTAssertEqual(presentation.levelTwoMessage, expectedGeneralMessage)",
        "testAppDependenciesComposesStructuredSafetyProviderIntoSessionViewModel",
        "AppDependencies(environment: .uiTesting)",
        "dependencies.makeSessionViewModel()",
        "session.resolveSymptomSafetyPresentation(for: context)",
        "session.resolveSymptomSafetyPresentation(",
    },
    "HealthTrackingAppTests/MedicalSafetyAcknowledgementTests.swift": {
        "testSuccessfulAcknowledgementPersistsAcrossControllerRecreationWithoutChangingLevelOne",
        "testFailedAcknowledgementWriteKeepsLevelZeroVisibleAndLevelOnePermanent",
        "MedicalSafetyAcknowledgementController",
        "MedicalSafetyAcknowledgementStore",
        "XCTAssertFalse(controller.acknowledge())",
        "XCTAssertTrue(controller.isLevelZeroVisible)",
        "levelOnePresentation, .permanent",
    },
    "HealthTrackingAppUITests/MedicalSafetyFlowUITests.swift": {
        "testFirstUseExplanationPersistsIndependentlyFromPermanentReminderDisclaimer",
        "-ui-test-medical-safety-first-use-evidence",
        "medical.explanation.l0",
        "medical.explanation.l0.acknowledge",
        "acknowledgement.frame.height + 0.01",
        "The shipped L0 acknowledgement target must remain at least 52 points high.",
        "firstLaunch.terminate()",
        "medical.disclaimer.l1",
    },
    "HealthTrackingAppUITests/TrainingAccessibilityUITests.swift": {
        "acknowledgeFirstUseExplanationIfNeeded(in: app)",
        "-ui-test-medical-safety-first-use-evidence",
        "The first-use L0 acknowledgement must retain its 52-point target at AX5.",
    },
    "HealthTrackingAppUITests/OHPSafetyFlowUITests.swift": {
        "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir.",
        "medical.safety.l2.heading",
        "-UIAccessibilityReduceMotionEnabled",
        "assertCompleteGeneralLevelTwo",
        "An unanswered prior OHP response must fail closed before it is answered.",
        "An explicit symptom-free answer must clear the missing-answer L2.",
        "The stable heading must not replace the complete L2 message.",
        "expectedGeneralMessage",
        "XCTAssertEqual(",
        "testAnsweredPriorSymptomsAndUncertaintyRenderTheShippedStoppedRoute",
        "-ui-test-store-identifier",
        "A stored prior response must not reopen the unanswered question.",
        "must restore the stopped route.",
        "session.ohp.prior.symptoms-present",
        "session.ohp.prior.uncertain",
        "A prior safety stop must not expose the current-symptom action.",
        "session.ohp.persistence.error",
        "session.ohp.persistence.retry",
        "persistenceRetry.frame.height + 0.01",
        "The shipped persistence retry target must remain at least 52 points high.",
        "session.exercise.finish-incomplete",
        "session.close",
        "app.buttons.matching(identifier: identifier).firstMatch",
        "Pending OHP persistence must disable the route control:",
        "Successful exact retry must re-enable the route control:",
        "session.delete.confirm.action",
        "session.delete.error",
        "A failed deletion must stay on the stopped route and expose a separate error.",
        "A failed deletion must not replace the current OHP safety stop.",
        "A failed deletion must preserve the exact symptom persistence retry.",
        "Deletion failure must keep the pending route control disabled:",
        "The journal must start only after the exact pending training-state write succeeds.",
    },
    "HealthTrackingAppUITests/PostureFlowUITests.swift": {
        "medical.disclaimer.l1",
        '.matching(identifier: "medical.disclaimer.l1")',
        ".firstMatch",
        "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir.",
        "assertDisclaimer(in: app)",
        "assertCompleteGeneralLevelTwo",
        "The final symptom input must immediately publish the complete L2.",
        "medical.safety.l2.heading",
        "dismissKeyboardAfterTyping: false",
        "The stable heading must not replace the complete L2 message.",
        "expectedGeneralMessage",
        "XCTAssertEqual(",
        "-UIAccessibilityReduceMotionEnabled",
    },
    "HealthTrackingAppUITests/BloodworkFlowUITests.swift": {
        "bloodwork.disclaimer.l1",
        "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir.",
        "assertDisclaimer(in: app)",
    },
    "HealthTrackingAppUITests/HealthCheckFlowUITests.swift": {
        "medical.disclaimer.l1",
        "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir.",
        "assertDisclaimer(in: app)",
    },
}

for relative_path, tokens in m310_tests.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.10 RED test file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.10 RED contracts: {absent}")
    async_autoclosure_lines = async_xctest_autoclosure_lines(text)
    if async_autoclosure_lines:
        locations = ", ".join(
            f"{relative_path}:{line}" for line in async_autoclosure_lines
        )
        raise SystemExit(
            "M3.10 XCTest autoclosures must evaluate async values first: "
            f"{locations}"
        )

medical_safety_ui_test_text = (
    root / "HealthTrackingAppUITests/MedicalSafetyFlowUITests.swift"
).read_text(encoding="utf-8")
compact_medical_safety_ui_test = re.sub(r"\s+", "", medical_safety_ui_test_text)
if (
    "XCTAssertGreaterThanOrEqual(acknowledgement.frame.height+0.01,52,"
    not in compact_medical_safety_ui_test
):
    raise SystemExit(
        "M3.10 shipped L0 acknowledgement UI test must measure a real 52-point target"
    )

ohp_safety_ui_test_text = (
    root / "HealthTrackingAppUITests/OHPSafetyFlowUITests.swift"
).read_text(encoding="utf-8")
compact_ohp_safety_ui_test = re.sub(r"\s+", "", ohp_safety_ui_test_text)
if (
    "XCTAssertGreaterThanOrEqual(persistenceRetry.frame.height+0.01,52,"
    not in compact_ohp_safety_ui_test
):
    raise SystemExit(
        "M3.10 shipped OHP persistence retry UI test must measure a real 52-point target"
    )
required_pending_route_test = {
    'letblockedRouteControls=["session.exercise.next","session.exercise.back",'
    '"session.exercise.finish-incomplete","session.close",]',
    "PendingOHPpersistencemustdisabletheroutecontrol:\\(identifier).",
    "Successfulexactretrymustre-enabletheroutecontrol:\\(identifier).",
}
absent = sorted(
    token for token in required_pending_route_test
    if token not in compact_ohp_safety_ui_test
)
if absent:
    raise SystemExit(
        "M3.10 shipped OHP UI test must keep every normal route control disabled "
        f"until the exact pending write succeeds: {absent}"
    )
scoped_route_query = "app.buttons.matching(identifier: identifier).firstMatch"
if ohp_safety_ui_test_text.count(scoped_route_query) != 3:
    raise SystemExit(
        "M3.10 OHP route assertions must use the exact button-scoped query in all "
        "three pending/deletion/retry loops"
    )

motion_policy_test_text = (
    root
    / "Packages/HealthTrackingModules/Tests/DesignSystemTests/MedicalSafetyMotionPolicyTests.swift"
).read_text(encoding="utf-8")
compact_motion_test = re.sub(r"\s+", "", motion_policy_test_text)
for reduce_motion, expected_transition in (("true", "identity"), ("false", "opacity")):
    expected_contract = (
        "XCTAssertEqual(MedicalSafetyMotionPolicy.transition("
        f"reduceMotion:{reduce_motion},"
        "identity:TransitionProbe.identity,"
        "opacity:TransitionProbe.opacity"
        f"),.{expected_transition})"
    )
    if expected_contract not in compact_motion_test:
        raise SystemExit(
            "M3.10 motion behavior test must require Reduce Motion true -> identity "
            "and false -> opacity through the production-facing selector"
        )

focus_policy_test_text = (
    root
    / "Packages/HealthTrackingModules/Tests/DesignSystemTests/MedicalSafetyFocusPolicyTests.swift"
).read_text(encoding="utf-8")
compact_focus_test = re.sub(r"\s+", "", focus_policy_test_text)
required_focus_behavior = {
    "XCTAssertTrue(MedicalSafetyFocusPolicy.headingFocused(isLevelTwoPresented:true))",
    "XCTAssertFalse(MedicalSafetyFocusPolicy.headingFocused(isLevelTwoPresented:false))",
}
absent = sorted(
    contract for contract in required_focus_behavior
    if contract not in compact_focus_test
)
if absent:
    raise SystemExit(
        "M3.10 focus behavior test must activate heading focus when L2 appears "
        "and clear it when L2 is removed"
    )

for relative_path in (
    "HealthTrackingAppUITests/OHPSafetyFlowUITests.swift",
    "HealthTrackingAppUITests/PostureFlowUITests.swift",
):
    ui_test_text = (root / relative_path).read_text(encoding="utf-8")
    for unsupported_focus_claim in (
        "hasFocus",
        "UIAccessibilityVoiceOver",
        "VoiceOverEnabled",
    ):
        if unsupported_focus_claim in ui_test_text:
            raise SystemExit(
                f"{relative_path} must not claim focus through inactive or "
                f"unverified VoiceOver state: {unsupported_focus_claim}"
            )

posture_ui_test_text = (
    root / "HealthTrackingAppUITests/PostureFlowUITests.swift"
).read_text(encoding="utf-8")
posture_order_tokens = (
    'in: textField("posture.entry.region"',
    'in: textField("posture.entry.note"',
    'in: textField("posture.entry.symptom"',
    "assertCompleteGeneralLevelTwo(",
)
posture_positions = [posture_ui_test_text.find(token) for token in posture_order_tokens]
if any(position < 0 for position in posture_positions) or posture_positions != sorted(
    posture_positions
):
    raise SystemExit(
        "M3.10 posture UI must enter region/note first, make symptom the final "
        "trigger, then assert the L2 immediately"
    )
symptom_to_assertion = posture_ui_test_text[
    posture_positions[2]:posture_positions[3]
]
symptom_call_start = posture_ui_test_text.rfind(
    "replaceText(", 0, posture_positions[2]
)
symptom_call_end = None
depth = 0
for index in range(symptom_call_start, posture_positions[3]):
    character = posture_ui_test_text[index]
    if character == "(":
        depth += 1
    elif character == ")":
        depth -= 1
        if depth == 0:
            symptom_call_end = index
            break
if (
    "dismissKeyboardAfterTyping: false" not in symptom_to_assertion
    or symptom_call_start < 0
    or symptom_call_end is None
    or ".tap(" in symptom_to_assertion
    or posture_ui_test_text[symptom_call_end + 1:posture_positions[3]].strip()
):
    raise SystemExit(
        "M3.10 posture UI must perform no focus-stealing tap between the final "
        "symptom trigger and the immediate L2 assertion"
    )

medical_safety_test_text = (
    root
    / "Packages/HealthTrackingModules/Tests/HealthSafetyKitTests/MedicalSafetyPresentationTests.swift"
).read_text(encoding="utf-8")
for message_name, expected_message in (
    ("expectedGeneralMessage", m310_general_message),
    ("expectedUrgentMessage", m310_urgent_message),
):
    actual_message = swift_assigned_string(medical_safety_test_text, message_name)
    if actual_message != expected_message:
        raise SystemExit(
            f"M3.10 RED test {message_name} must freeze the complete exact Turkish copy"
        )

m310_support = {
    ".github/workflows/ios.yml": {
        "Targeted M3.10 pure medical safety tests",
        "scripts/test-ios.sh --only-testing HealthSafetyKitTests",
        "Targeted M3.10 medical safety focus and motion policy tests",
        "scripts/test-ios.sh --only-testing DesignSystemTests",
        "Targeted M3.10 shipped session safety tests",
        "scripts/test-ios.sh --only-testing TrainingKitTests",
        "Targeted M3.10 app safety composition tests",
        "scripts/test-ios.sh --only-testing HealthTrackingAppTests",
    },
}

for relative_path, tokens in m310_support.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.10 support file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.10 test wiring: {absent}")

medical_safety_source = (
    root / "Packages/HealthTrackingModules/Sources/HealthSafetyKit/HealthSafetyKitModule.swift"
)
medical_safety_text = medical_safety_source.read_text(encoding="utf-8")
frozen_l1_copy = "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."
if frozen_l1_copy not in medical_safety_text:
    raise SystemExit("M3.10 frozen L1 Turkish safety copy changed or is missing")

if "case missingSymptomAnswer" in medical_safety_text:
    required_m310_safety_copy = {
        "Kalıcı veya kötüleşen belirtiler",
        "sağlık profesyoneli tarafından değerlendirilmelidir.",
        "Yeni veya belirgin şekilde kötüleşen",
        "kol veya bacakta güçsüzlük ya da uyuşma",
        "el becerisinde kayıp",
        "denge veya yürümede değişiklik",
        "mesane veya bağırsak işlevinde değişiklik",
        "requiresUrgentAssessment: false",
        "requiresUrgentAssessment: true",
    }
    absent = sorted(
        token for token in required_m310_safety_copy
        if token not in medical_safety_text
    )
    if absent:
        raise SystemExit(f"M3.10 required general/urgent safety copy is incomplete: {absent}")

    for message_name, expected_message in (
        ("generalStopMessage", m310_general_message),
        ("urgentMessage", m310_urgent_message),
    ):
        actual_message = swift_assigned_string(medical_safety_text, message_name)
        if actual_message != expected_message:
            raise SystemExit(
                f"M3.10 {message_name} must match the complete exact Turkish safety copy"
            )

for prohibited in (
    "diagnosis", "diagnose", "diagnostic", "disease", "condition",
    "normal", "abnormal", "threshold", "tanı", "teşhis", "hastalık",
    "durumunuz",
):
    if prohibited.casefold() in medical_safety_text.casefold():
        raise SystemExit(
            "M3.10 safety presentation must not diagnose, classify, or interpret: "
            f"{prohibited}"
        )

m310_training_mapper = (
    root / "App/Application/TrainingSymptomMetricsAdapter.swift"
)
m310_training_mapper_text = m310_training_mapper.read_text(encoding="utf-8")
if "static func presentation(" in m310_training_mapper_text:
    required_mapping = {
        ".priorOverheadPressResponse(.notAsked)",
        ".priorOverheadPressResponse(.uncertain)",
        ".currentOverheadPressResponse(.symptomsPresent)",
        ".missingSymptomAnswer",
        ".overheadPressSymptom",
    }
    absent = sorted(
        token for token in required_mapping
        if token not in m310_training_mapper_text
    )
    if absent:
        raise SystemExit(f"M3.10 structured OHP safety mapping is incomplete: {absent}")



def swift_braced_declaration(source: str, name: str) -> str | None:
    declaration = re.search(rf"\b(?:var|func)\s+{re.escape(name)}\b[^{{]*{{", source)
    if declaration is None:
        return None
    opening = declaration.end() - 1
    depth = 0
    for index in range(opening, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[opening:index + 1]
    return None


if "case missingSymptomAnswer" in medical_safety_text:
    ui_test_launch_configuration_text = (
        root / "App/Support/AppUITestLaunchConfiguration.swift"
    ).read_text(encoding="utf-8")
    compact_ui_test_launch_configuration = re.sub(
        r"\s+", "", ui_test_launch_configuration_text
    )
    required_first_use_evidence_configuration = {
        'staticletmedicalSafetyFirstUseEvidenceFlag="-ui-test-medical-safety-first-use-evidence"',
        "letexposesMedicalSafetyFirstUseEvidence:Bool",
        "arguments.filter({$0==medicalSafetyFirstUseEvidenceFlag}).count<=1",
        "exposesMedicalSafetyFirstUseEvidence:arguments.contains(medicalSafetyFirstUseEvidenceFlag)",
    }
    absent = sorted(
        token for token in required_first_use_evidence_configuration
        if token not in compact_ui_test_launch_configuration
    )
    if absent:
        raise SystemExit(
            "M3.10 UI-test medical-safety first-use evidence configuration is incomplete: "
            f"{absent}"
        )

    dependencies_text = (root / "App/Application/AppDependencies.swift").read_text(
        encoding="utf-8"
    )
    debug_ui_test_acknowledgement = re.compile(
        r"#if\s+DEBUG\s+"
        r"if\s+environment\s*==\s*\.uiTesting\s*,\s*"
        r"let\s+launchConfiguration\s*=\s*"
        r"AppUITestLaunchConfiguration\.resolve\(\)\s*,\s*"
        r"!launchConfiguration\.exposesMedicalSafetyFirstUseEvidence\s*\{\s*"
        r"_\s*=\s*medicalSafetyAcknowledgementController\.acknowledge\(\)\s*"
        r"\}\s*#endif",
        re.DOTALL,
    )
    if debug_ui_test_acknowledgement.search(dependencies_text) is None:
        raise SystemExit(
            "M3.10 ordinary valid UI tests must acknowledge L0 only inside DEBUG "
            "while the explicit medical-safety evidence launch remains unacknowledged"
        )

    app_root_text = (root / "App/Application/AppRootView.swift").read_text(
        encoding="utf-8"
    )
    compact_app_root = re.sub(r"\s+", "", app_root_text)
    required_app_root_init = {
        "medicalSafetyAcknowledgementController:MedicalSafetyAcknowledgementController?=nil",
        "self.medicalSafetyAcknowledgementController=medicalSafetyAcknowledgementController",
    }
    absent = sorted(
        token for token in required_app_root_init if token not in compact_app_root
    )
    if absent or re.search(
        r"\blet\s+medicalSafetyAcknowledgementController\s*:[^\n=]+\s*=\s*nil",
        app_root_text,
    ):
        raise SystemExit(
            "M3.10 AppRootView must expose an explicit immutable initializer with "
            "a defaulted medical safety acknowledgement controller"
        )
    bootstrap_text = (root / "App/Application/AppBootstrapView.swift").read_text(
        encoding="utf-8"
    )
    if (
        "medicalSafetyAcknowledgementController:" not in bootstrap_text
        or "dependencies.medicalSafetyAcknowledgementController" not in bootstrap_text
    ):
        raise SystemExit(
            "M3.10 AppBootstrapView must pass the composed acknowledgement controller "
            "through the explicit AppRootView initializer"
        )
    l0_acknowledgement_label_contract = (
        'Button{controller.acknowledge()}label:{Text(String(localized:'
        '"medical.explanation.l0.acknowledge")).frame(maxWidth:.infinity,'
        'minHeight:52).contentShape(Rectangle())}'
    )
    if l0_acknowledgement_label_contract not in compact_app_root:
        raise SystemExit(
            "M3.10 L0 acknowledgement must place the 52-point frame and content "
            "shape inside the explicit Button label"
        )

    ohp_gate_text = (
        root / "Packages/HealthTrackingModules/Sources/GuidanceKit/Safety/OHPSafetyGate.swift"
    ).read_text(encoding="utf-8")
    for response_case, next_case in (
        ("case .symptomsPresent:", "case .uncertain:"),
        ("case .uncertain:", None),
    ):
        start = ohp_gate_text.find(response_case)
        end = len(ohp_gate_text) if next_case is None else ohp_gate_text.find(next_case, start)
        segment = ohp_gate_text[start:end] if start >= 0 and end > start else ""
        if "safetyStop: SafetyStop(alternative: .halfKneelingDBPress)" not in segment:
            raise SystemExit(
                "M3.10 prior OHP symptoms and uncertainty must produce the reviewed "
                "half-kneeling safety stop"
            )

    session_snapshot_text = (
        root / "Packages/HealthTrackingModules/Sources/TrainingKit/Snapshots/TrainingSnapshots.swift"
    ).read_text(encoding="utf-8")
    required_write_contract = {
        "SessionOHPSymptomWriteRequest",
        "let sessionID: UUID",
        "let response: OHPSymptomResponse",
        "let reportedAt: Date",
        "SessionOHPSymptomWriteState",
        "case idle",
        "case saving(request: SessionOHPSymptomWriteRequest)",
        "case failed(request: SessionOHPSymptomWriteRequest)",
    }
    absent = sorted(
        token for token in required_write_contract if token not in session_snapshot_text
    )
    if absent:
        raise SystemExit(
            f"M3.10 current OHP write state must retain one exact retry request: {absent}"
        )

    session_view_model_text = (
        root / "Packages/HealthTrackingModules/Sources/TrainingKit/Session/SessionViewModel.swift"
    ).read_text(encoding="utf-8")
    route_lock_contract = "public private(set) var isSessionRouteMutationInFlight = false"
    if route_lock_contract not in session_view_model_text:
        raise SystemExit(
            "M3.10 reverse-order OHP safety requires an observable MainActor route lock"
        )
    deletion_lock_contract = "public private(set) var isSessionDeletionInFlight = false"
    if deletion_lock_contract not in session_view_model_text:
        raise SystemExit(
            "M3.10 deletion arbitration requires an observable MainActor deletion lease"
        )
    broad_owner_contracts = {
        "private var sessionMutationOwners: Set<UUID> = []",
        "public var activeSessionMutationCount: Int",
        "sessionMutationOwners.count",
        "public var isSessionMutationInFlight: Bool",
        "!sessionMutationOwners.isEmpty",
        "private func beginSessionMutation() -> UUID?",
        "private func endSessionMutation(_ owner: UUID)",
    }
    absent = sorted(
        token for token in broad_owner_contracts
        if token not in session_view_model_text
    )
    if absent:
        raise SystemExit(
            "M3.10 deletion finality requires exact broad session mutation owners: "
            f"{absent}"
        )
    begin_mutation_body = swift_braced_declaration(
        session_view_model_text, "beginSessionMutation"
    ) or ""
    end_mutation_body = swift_braced_declaration(
        session_view_model_text, "endSessionMutation"
    ) or ""
    if (
        "guard !isSessionDeletionInFlight else { return nil }" not in begin_mutation_body
        or "let owner = UUID()" not in begin_mutation_body
        or "sessionMutationOwners.insert(owner)" not in begin_mutation_body
        or "return owner" not in begin_mutation_body
        or "sessionMutationOwners.remove(owner)" not in end_mutation_body
        or "removeAll" in end_mutation_body
    ):
        raise SystemExit(
            "M3.10 broad session mutation owner must be an exact inserted/removed token"
        )

    session_mutation_entries = (
        "start",
        "toggleWarmupItem",
        "completeWarmup",
        "skipWarmup",
        "answerPreviousOHPSymptom",
        "respondToDeload",
        "reportCurrentOHPSymptom",
        "retryCurrentOHPSymptomWrite",
        "advanceExercise",
        "goBack",
        "toggleCooldownItem",
        "completeCooldown",
        "skipCooldown",
        "finishIncomplete",
        "saveCurrentSet",
        "retrySetSave",
        "saveSummary",
    )
    owner_acquire = (
        "guard let sessionMutationOwner = beginSessionMutation() else { return }"
    )
    owner_release = "defer { endSessionMutation(sessionMutationOwner) }"
    for action_name in session_mutation_entries:
        action_body = swift_braced_declaration(session_view_model_text, action_name) or ""
        acquire_position = action_body.find(owner_acquire)
        release_position = action_body.find(owner_release)
        first_await = action_body.find("await ")
        if (
            min(acquire_position, release_position, first_await) < 0
            or not acquire_position < release_position < first_await
            or action_body.count(owner_acquire) != 1
            or action_body.count(owner_release) != 1
        ):
            raise SystemExit(
                "M3.10 session mutation entry must acquire and defer-release one exact "
                f"broad owner before awaiting: {action_name}"
            )

    retry_journal_body = swift_braced_declaration(
        session_view_model_text, "retrySymptomJournal"
    ) or ""
    if "beginSessionMutation" in retry_journal_body or "state =" in retry_journal_body:
        raise SystemExit(
            "M3.10 metrics-only symptom journal retry must not own or republish session state"
        )
    for action_name in (
        "selectRecovery",
        "selectPerformedVariant",
        "stepperChanged",
        "updateSummaryNote",
    ):
        action_body = swift_braced_declaration(session_view_model_text, action_name) or ""
        if "guard !isSessionDeletionInFlight else { return }" not in action_body:
            raise SystemExit(
                "M3.10 delete-first safety must reject synchronous session mutation: "
                f"{action_name}"
            )
    can_report_body = swift_braced_declaration(
        session_view_model_text, "canReportCurrentOHPSymptom"
    ) or ""
    if (
        "!isSessionRouteMutationInFlight" not in can_report_body
        or "!isSessionDeletionInFlight" not in can_report_body
    ):
        raise SystemExit(
            "M3.10 shipped symptom action availability must close during route or deletion ownership"
        )
    report_body = swift_braced_declaration(
        session_view_model_text, "reportCurrentOHPSymptom"
    ) or ""
    report_lock = report_body.find("!isSessionRouteMutationInFlight")
    report_delete_lock = report_body.find("!isSessionDeletionInFlight")
    report_request = report_body.find("let request = SessionOHPSymptomWriteRequest(")
    if (
        min(report_lock, report_delete_lock, report_request) < 0
        or report_lock > report_request
        or report_delete_lock > report_request
    ):
        raise SystemExit(
            "M3.10 current OHP report must reject route-first and delete-first races before creating a request"
        )
    report_order = (
        "pendingOHPSymptomWriteRequest == nil",
        "let request = SessionOHPSymptomWriteRequest(",
        "pendingOHPSymptomWriteRequest = request",
        "replaceActiveSession(",
        "resolveOHPSafety(",
        "ohpSymptomWriteState = .saving(request: request)",
        "await persistCurrentOHPSymptomWrite(request)",
    )
    report_positions = [report_body.find(token) for token in report_order]
    if any(position < 0 for position in report_positions) or report_positions != sorted(
        report_positions
    ):
        raise SystemExit(
            "M3.10 current OHP action must publish and retain the exact stopped request "
            "before awaiting persistence"
        )
    persist_body = swift_braced_declaration(
        session_view_model_text, "persistCurrentOHPSymptomWrite"
    ) or ""
    required_persist_tokens = {
        "coordinator.recordOHPSymptomResponse(",
        "pendingOHPSymptomWriteRequest = nil",
        "ohpSymptomWriteState = .idle",
        "ohpSymptomWriteState = .failed(request: request)",
        "await recordSymptomEvent(",
        "occurredAt: request.reportedAt",
    }
    absent = sorted(
        token for token in required_persist_tokens if token not in persist_body
    )
    if absent or "state = .failed" in persist_body:
        raise SystemExit(
            "M3.10 current OHP write failure must retain the active stopped route and "
            f"journal only after durable success: {absent}"
        )
    repository_write = persist_body.find("coordinator.recordOHPSymptomResponse(")
    journal_write = persist_body.find("await recordSymptomEvent(")
    if repository_write < 0 or journal_write < repository_write:
        raise SystemExit(
            "M3.10 current OHP symptom journal must start only after repository success"
        )
    retry_body = swift_braced_declaration(
        session_view_model_text, "retryCurrentOHPSymptomWrite"
    ) or ""
    if (
        "pendingOHPSymptomWriteRequest" not in retry_body
        or "await persistCurrentOHPSymptomWrite(request)" not in retry_body
        or "!isSessionDeletionInFlight" not in retry_body
        or "now()" in retry_body
    ):
        raise SystemExit(
            "M3.10 current OHP retry must reject deletion ownership and reuse the exact pending request"
        )

    pending_flag_body = swift_braced_declaration(
        session_view_model_text, "hasPendingCurrentOHPSymptomWrite"
    ) or ""
    compact_pending_flag = re.sub(r"\s+", "", pending_flag_body)
    required_pending_flag = {
        "guardpendingOHPSymptomWriteRequest!=nilelse{returnfalse}",
        "case.saving,.failed:returntrue",
        "case.idle:returnfalse",
    }
    absent = sorted(
        token for token in required_pending_flag if token not in compact_pending_flag
    )
    if absent:
        raise SystemExit(
            "M3.10 pending current OHP write flag must derive fail-closed from the "
            f"exact retained request and write state: {absent}"
        )

    saving_flag_body = swift_braced_declaration(
        session_view_model_text, "isCurrentOHPSymptomWriteSaving"
    ) or ""
    compact_saving_flag = re.sub(r"\s+", "", saving_flag_body)
    if (
        "guardpendingOHPSymptomWriteRequest!=nilelse{returnfalse}"
        not in compact_saving_flag
        or "case.saving=ohpSymptomWriteState" not in compact_saving_flag
    ):
        raise SystemExit(
            "M3.10 destructive deletion guard must distinguish the exact saving "
            "window from a failed retry-visible write"
        )

    for action_name in ("advanceExercise", "goBack", "finishSession"):
        action_body = swift_braced_declaration(session_view_model_text, action_name) or ""
        if "!hasPendingCurrentOHPSymptomWrite" not in action_body:
            raise SystemExit(
                "M3.10 pending current OHP write must block normal session route "
                f"action: {action_name}"
            )
        if "!isSessionDeletionInFlight" not in action_body:
            raise SystemExit(
                "M3.10 delete-first safety must block normal session route action: "
                f"{action_name}"
            )
        route_guard = action_body.find("!isSessionRouteMutationInFlight")
        route_acquire = action_body.find("isSessionRouteMutationInFlight = true")
        route_release = action_body.find(
            "defer { isSessionRouteMutationInFlight = false }"
        )
        first_await = action_body.find("await ")
        if (
            min(route_guard, route_acquire, route_release, first_await) < 0
            or not route_guard < route_acquire < route_release < first_await
        ):
            raise SystemExit(
                "M3.10 route-first safety must acquire and defer-release the lock "
                f"before awaiting: {action_name}"
            )
    for action_name in ("requestDeletion", "confirmDeletion"):
        action_body = swift_braced_declaration(session_view_model_text, action_name) or ""
        if "!isCurrentOHPSymptomWriteSaving" not in action_body:
            raise SystemExit(
                "M3.10 saving current OHP write must block destructive deletion race: "
                f"{action_name}"
            )
        if (
            "!isSessionRouteMutationInFlight" not in action_body
            or "!isSessionDeletionInFlight" not in action_body
            or "!isSessionMutationInFlight" not in action_body
        ):
            raise SystemExit(
                "M3.10 deletion entry must reject route, broad mutation, and duplicate deletion ownership: "
                f"{action_name}"
            )

    deletion_failure_contract = (
        "public private(set) var hasSessionDeletionFailure = false"
    )
    if deletion_failure_contract not in session_view_model_text:
        raise SystemExit(
            "M3.10 deletion failure must remain observable without replacing the stopped route"
        )
    confirm_deletion_body = swift_braced_declaration(
        session_view_model_text, "confirmDeletion"
    ) or ""
    delete_call = confirm_deletion_body.find("try await repository.deleteWorkoutSession(")
    deletion_acquire = confirm_deletion_body.find("isSessionDeletionInFlight = true")
    deletion_release = confirm_deletion_body.find(
        "defer { isSessionDeletionInFlight = false }"
    )
    first_delete_await = confirm_deletion_body.find("await ")
    if (
        min(deletion_acquire, deletion_release, first_delete_await) < 0
        or not deletion_acquire < deletion_release < first_delete_await
    ):
        raise SystemExit(
            "M3.10 confirm deletion must acquire and defer-release its lease before the first await"
        )
    catch_start = confirm_deletion_body.find("} catch {")
    success_clear_request = confirm_deletion_body.find(
        "pendingOHPSymptomWriteRequest = nil"
    )
    success_clear_state = confirm_deletion_body.find("ohpSymptomWriteState = .idle")
    if (
        min(delete_call, catch_start, success_clear_request, success_clear_state) < 0
        or not delete_call < success_clear_request < catch_start
        or not delete_call < success_clear_state < catch_start
    ):
        raise SystemExit(
            "M3.10 only successful session deletion may discard the exact symptom retry"
        )
    deletion_catch = confirm_deletion_body[catch_start:]
    pending_branch = deletion_catch.find("if hasPendingCurrentOHPSymptomWrite {")
    preserve_stopped = deletion_catch.find("hasSessionDeletionFailure = true")
    ordinary_branch = deletion_catch.find("} else {")
    ordinary_failure = deletion_catch.find("state = .failed(.deletion)")
    if (
        min(pending_branch, preserve_stopped, ordinary_branch, ordinary_failure) < 0
        or not pending_branch < preserve_stopped < ordinary_branch < ordinary_failure
        or "isDeleteConfirmationPresented = false" not in deletion_catch
        or "pendingOHPSymptomWriteRequest = nil" in deletion_catch
        or "ohpSymptomWriteState = .idle" in deletion_catch
    ):
        raise SystemExit(
            "M3.10 deletion failure must preserve pending OHP safety without regressing ordinary failure recovery"
        )

    exercise_stage_text = (
        root / "Packages/HealthTrackingModules/Sources/TrainingKit/Session/ExerciseStageView.swift"
    ).read_text(encoding="utf-8")
    required_write_ui = {
        "ohpSymptomWriteState",
        'accessibilityIdentifier("session.ohp.persistence.saving")',
        'accessibilityIdentifier("session.ohp.persistence.error")',
        'accessibilityIdentifier("session.ohp.persistence.retry")',
        "retryCurrentOHPSymptomWrite",
        "if viewModel.canReportCurrentOHPSymptom {",
        "viewModel.hasSessionDeletionFailure",
        'accessibilityIdentifier("session.delete.error")',
    }
    absent = sorted(token for token in required_write_ui if token not in exercise_stage_text)
    if absent:
        raise SystemExit(
            f"M3.10 shipped stopped UI must expose current-response write retry: {absent}"
        )
    compact_exercise_stage = re.sub(r"\s+", "", exercise_stage_text)
    retry_label_contract = (
        'Button{Task{awaitviewModel.retryCurrentOHPSymptomWrite()}}label:{'
        'Text(localized("session.ohp.persistence.retry")).frame('
        'maxWidth:.infinity,minHeight:52).contentShape(Rectangle())}'
    )
    if retry_label_contract not in compact_exercise_stage:
        raise SystemExit(
            "M3.10 persistence retry must place the 52-point frame and content "
            "shape inside the explicit Button label"
        )
    retry_delete_lock = (
        'accessibilityIdentifier("session.ohp.persistence.retry").disabled('
        'viewModel.isSessionDeletionInFlight)'
    )
    if retry_delete_lock not in compact_exercise_stage:
        raise SystemExit(
            "M3.10 shipped OHP retry must be disabled while deletion owns the session"
        )
    required_exercise_route_locks = {
        'accessibilityIdentifier("session.exercise.next").disabled('
        'viewModel.hasPendingCurrentOHPSymptomWrite||'
        'viewModel.isSessionDeletionInFlight)',
        'accessibilityIdentifier("session.exercise.back").disabled('
        'viewModel.hasPendingCurrentOHPSymptomWrite||'
        'viewModel.isSessionDeletionInFlight)',
        'accessibilityIdentifier("session.exercise.finish-incomplete").disabled('
        'viewModel.hasPendingCurrentOHPSymptomWrite||'
        'viewModel.isSessionDeletionInFlight)',
    }
    absent = sorted(
        token for token in required_exercise_route_locks
        if token not in compact_exercise_stage
    )
    if absent:
        raise SystemExit(
            "M3.10 shipped exercise route controls must remain disabled while the "
            f"exact OHP write is pending: {absent}"
        )

    training_session_text = (
        root / "Packages/HealthTrackingModules/Sources/TrainingKit/Session/TrainingSessionView.swift"
    ).read_text(encoding="utf-8")
    compact_training_session = re.sub(r"\s+", "", training_session_text)
    if 'accessibilityIdentifier("session.delete.confirm.action")' not in training_session_text:
        raise SystemExit(
            "M3.10 shipped deletion failure regression requires an addressable confirm action"
        )
    required_session_toolbar_locks = {
        'accessibilityIdentifier("session.close").disabled('
        'viewModel.hasPendingCurrentOHPSymptomWrite||'
        'viewModel.isSessionMutationInFlight||'
        'viewModel.isSessionDeletionInFlight)',
        'accessibilityIdentifier("session.delete").disabled('
        'viewModel.isCurrentOHPSymptomWriteSaving||'
        'viewModel.isSessionRouteMutationInFlight||'
        'viewModel.isSessionMutationInFlight||'
        'viewModel.isSessionDeletionInFlight)',
        'accessibilityIdentifier("session.delete.confirm.action").disabled('
        'viewModel.isSessionRouteMutationInFlight||'
        'viewModel.isSessionMutationInFlight||'
        'viewModel.isSessionDeletionInFlight)',
    }
    absent = sorted(
        token for token in required_session_toolbar_locks
        if token not in compact_training_session
    )
    if absent:
        raise SystemExit(
            "M3.10 shipped session toolbar must preserve the pending write and block "
            f"saving-time deletion races: {absent}"
        )
    active_content_body = swift_braced_declaration(
        training_session_text, "activeContent"
    ) or ""
    if ".disabled(viewModel.isSessionDeletionInFlight)" not in re.sub(
        r"\s+", "", active_content_body
    ):
        raise SystemExit(
            "M3.10 shipped active session content must be disabled for the full deletion lease"
        )

    dependencies_text = (root / "App/Application/AppDependencies.swift").read_text(
        encoding="utf-8"
    )
    required_ui_write_fixture = {
        "case .ohpSafety:",
        "failsFirstCurrentOHPSymptomWrite: true",
        "private var failsNextCurrentOHPSymptomWrite",
        "private var currentSessionID: UUID?",
        "currentSessionID = session?.id",
        "response == .symptomsPresent",
        "id == currentSessionID",
        "UITestFoundationRepositoryError.ohpSymptomWrite",
        "failsFirstSessionDeletion: true",
        "private var failsNextSessionDeletion",
        "failsNextSessionDeletion = failsFirstSessionDeletion",
        "if failsNextSessionDeletion, id == currentSessionID",
        "UITestFoundationRepositoryError.sessionDeletion",
    }
    absent = sorted(
        token for token in required_ui_write_fixture if token not in dependencies_text
    )
    if absent:
        raise SystemExit(
            f"M3.10 OHP UI fixture must fail the first current-response write: {absent}"
        )
    ui_fixture_write_body = swift_braced_declaration(
        dependencies_text, "updateWorkoutSessionOHPSymptomResponse"
    ) or ""
    if (
        "return try await repository.updateWorkoutSessionOHPSymptomResponse("
        not in ui_fixture_write_body
    ):
        raise SystemExit(
            "M3.10 DEBUG OHP UI repository must return its delegated snapshot"
        )

    focus_policy_path = (
        root
        / "Packages/HealthTrackingModules/Sources/DesignSystem/Accessibility/MedicalSafetyFocusPolicy.swift"
    )
    if not focus_policy_path.is_file():
        raise SystemExit("Missing M3.10 MedicalSafetyFocusPolicy production contract")
    focus_policy_text = focus_policy_path.read_text(encoding="utf-8")
    required_focus_policy = {
        "MedicalSafetyFocusPolicy",
        "headingFocused",
        "isLevelTwoPresented",
    }
    absent = sorted(
        token for token in required_focus_policy if token not in focus_policy_text
    )
    if absent:
        raise SystemExit(f"M3.10 focus policy contract is incomplete: {absent}")

    motion_policy_path = (
        root
        / "Packages/HealthTrackingModules/Sources/DesignSystem/Motion/MedicalSafetyMotionPolicy.swift"
    )
    if not motion_policy_path.is_file():
        raise SystemExit("Missing M3.10 MedicalSafetyMotionPolicy production contract")
    motion_policy_text = motion_policy_path.read_text(encoding="utf-8")
    required_motion_policy = {
        "MedicalSafetyMotionPolicy",
        "transition",
        "reduceMotion",
        "identity",
        "opacity",
    }
    absent = sorted(
        token for token in required_motion_policy if token not in motion_policy_text
    )
    if absent:
        raise SystemExit(f"M3.10 motion policy contract is incomplete: {absent}")

    m310_safety_ui_paths = (
        "Packages/HealthTrackingModules/Sources/MetricsKit/Posture/PostureEntryView.swift",
        "Packages/HealthTrackingModules/Sources/TrainingKit/Session/OHPPriorSymptomQuestionView.swift",
        "Packages/HealthTrackingModules/Sources/TrainingKit/Session/ExerciseStageView.swift",
    )
    prohibited_transition_patterns = {
        "move": r"\.move\s*\(",
        "slide": r"\.slide\b",
        "scale": r"\.scale(?:\s*\(|\b)",
        "scaleEffect": r"\.scaleEffect\s*\(",
        "offset": r"\.offset\s*\(",
        "zoom": r"\.zoom\b",
        "push": r"\.push\s*\(",
    }
    for relative_path in m310_safety_ui_paths:
        source = root / relative_path
        if not source.is_file():
            raise SystemExit(f"Missing required M3.10 L2 UI consumer: {relative_path}")
        text = source.read_text(encoding="utf-8")
        required_focus_and_motion = {
            "@AccessibilityFocusState",
            "levelTwoHeadingFocused",
            '"medical.safety.l2.heading"',
            '"medical.safety.l2"',
            ".accessibilityFocused($levelTwoHeadingFocused)",
            ".accessibilityAddTraits(.isHeader)",
            ".onAppear",
            ".onChange(of: isLevelTwoPresented)",
            "updateLevelTwoHeadingFocus(isPresented: true)",
            "updateLevelTwoHeadingFocus(isPresented: isPresented)",
            "accessibilityReduceMotion",
            ".transition(levelTwoTransition)",
        }
        absent = sorted(
            token for token in required_focus_and_motion if token not in text
        )
        if absent:
            raise SystemExit(
                f"{relative_path} must provide stable L2 heading focus, complete message, "
                f"programmatic activation, and scoped motion: {absent}"
            )
        compact_consumer = re.sub(r"\s+", "", text)
        expected_focus_assignment = (
            "levelTwoHeadingFocused="
            "MedicalSafetyFocusPolicy.headingFocused(isLevelTwoPresented:isPresented)"
        )
        if expected_focus_assignment not in compact_consumer:
            raise SystemExit(
                f"{relative_path} must bind L2 appearance/removal to the tested "
                "MedicalSafetyFocusPolicy result"
            )

        transition_scope = swift_braced_declaration(text, "levelTwoTransition")
        if transition_scope is None:
            raise SystemExit(
                f"{relative_path} must define a dedicated levelTwoTransition policy scope"
            )
        compact_transition_scope = re.sub(r"\s+", "", transition_scope)
        required_scoped_motion = {
            "MedicalSafetyMotionPolicy.transition(",
            "reduceMotion:accessibilityReduceMotion",
        }
        absent = sorted(
            token for token in required_scoped_motion
            if token not in compact_transition_scope
        )
        if absent:
            raise SystemExit(
                f"{relative_path} must use the tested motion selector directly with "
                f"identity/opacity mapped correctly: {absent}"
            )
        correct_identity_mapping = (
            "identity:.identity" in compact_transition_scope
            or "identity:AnyTransition.identity" in compact_transition_scope
        )
        correct_opacity_mapping = (
            "opacity:.opacity" in compact_transition_scope
            or "opacity:AnyTransition.opacity" in compact_transition_scope
        )
        if not correct_identity_mapping or not correct_opacity_mapping:
            raise SystemExit(
                f"{relative_path} must use the tested motion selector directly with "
                "identity/opacity mapped correctly"
            )
        if (
            "case.identity" in compact_transition_scope
            or "case.opacity" in compact_transition_scope
        ):
            raise SystemExit(
                f"{relative_path} must not remap motion policy cases in levelTwoTransition"
            )
        for transition_name, pattern in prohibited_transition_patterns.items():
            if re.search(pattern, transition_scope):
                raise SystemExit(
                    f"{relative_path} must not use {transition_name} in levelTwoTransition"
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

m310_safety_ui_fixture = "\n".join(
    [
        "@Environment(\\.accessibilityReduceMotion) var accessibilityReduceMotion",
        "@AccessibilityFocusState var levelTwoHeadingFocused: Bool",
        "let isLevelTwoPresented = true",
        'Text("Güvenlik")',
        '.accessibilityIdentifier("medical.safety.l2.heading")',
        ".accessibilityAddTraits(.isHeader)",
        ".accessibilityFocused($levelTwoHeadingFocused)",
        'Text("Complete safety message")',
        '.accessibilityIdentifier("medical.safety.l2")',
        ".onAppear {",
        "updateLevelTwoHeadingFocus(isPresented: true)",
        "}",
        ".onChange(of: isLevelTwoPresented) { _, isPresented in",
        "updateLevelTwoHeadingFocus(isPresented: isPresented)",
        "}",
        ".transition(levelTwoTransition)",
        ".scaleEffect(1.05) // unrelated layout effect outside the L2 transition scope",
        "private func updateLevelTwoHeadingFocus(isPresented: Bool) {",
        "levelTwoHeadingFocused = MedicalSafetyFocusPolicy.headingFocused(",
        "isLevelTwoPresented: isPresented",
        ")",
        "}",
        "private var levelTwoTransition: AnyTransition {",
        "MedicalSafetyMotionPolicy.transition(",
        "reduceMotion: accessibilityReduceMotion,",
        "identity: .identity,",
        "opacity: .opacity",
        ")",
        "}",
    ]
)

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
            "Targeted M3.7-M3.9 photo lifecycle, gallery, and cloud asset tests",
            "scripts/test-ios.sh --only-testing ProgressPhotosKitTests",
            '"ProgressPhotoLifecycleUITests"',
            "Targeted M3.10 pure medical safety tests",
            "scripts/test-ios.sh --only-testing HealthSafetyKitTests",
            "Targeted M3.10 medical safety focus and motion policy tests",
            "scripts/test-ios.sh --only-testing DesignSystemTests",
            "Targeted M3.10 shipped session safety tests",
            "scripts/test-ios.sh --only-testing TrainingKitTests",
            "Targeted M3.10 app safety composition tests",
            "scripts/test-ios.sh --only-testing HealthTrackingAppTests",
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
    "Packages/HealthTrackingModules/Tests/HealthSafetyKitTests/MedicalSafetyPresentationTests.swift": "\n".join(
        [
            "MedicalDisclaimerPresentation.permanent",
            "MedicalSafetyPresentation.resolve",
            "overheadPressSymptom",
            "increasingSymptom",
            "cervicalRedFlags",
            "urgentAssessmentInformation",
            "Hareketi durdur.",
            "testOHPAndIncreasingSymptomsPublishCompleteGeneralLevelTwoInformation",
            "testMissingSymptomAnswerPublishesCompleteNonUrgentFailClosedLevelTwo",
            ".missingSymptomAnswer",
            "private let expectedGeneralMessage =",
            '"Hareketi durdur. Kalıcı veya kötüleşen belirtiler bir sağlık profesyoneli tarafından değerlendirilmelidir. Yeni veya belirgin şekilde kötüleşen kol veya bacakta güçsüzlük ya da uyuşma, el becerisinde kayıp, denge veya yürümede değişiklik ya da mesane veya bağırsak işlevinde değişiklik acil tıbbi değerlendirme gerektirir."',
            "private let expectedUrgentMessage =",
            '"Hareketi durdur. Yeni veya belirgin şekilde kötüleşen kol veya bacakta güçsüzlük ya da uyuşma, el becerisinde kayıp, denge veya yürümede değişiklik ya da mesane veya bağırsak işlevinde değişiklik acil tıbbi değerlendirme gerektirir."',
            "notice.message,",
            "            expectedGeneralMessage",
            "testEachCervicalRedFlagAlonePublishesExactUrgentMessageAndOverridesEveryGeneralTrigger",
            "for flag in CervicalRedFlag.allCases",
            "triggers: [.cervicalRedFlags([flag])]",
            "for generalTrigger in generalTriggers",
            "triggers: [generalTrigger, .cervicalRedFlags([flag])]",
            "XCTAssertEqual(notice.kind, .urgentAssessmentInformation",
            "XCTAssertTrue(notice.requiresUrgentAssessment",
            "XCTAssertEqual(notice.message, expectedUrgentMessage",
            "assertContainsNoNumericMedicalThreshold",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/DesignSystemTests/MedicalSafetyMotionPolicyTests.swift": "\n".join(
        [
            "private enum TransitionProbe: Equatable { case identity, opacity }",
            "func testReduceMotionSelectsIdentityAndDefaultSelectsOpacity() {",
            "XCTAssertEqual(",
            "MedicalSafetyMotionPolicy.transition(",
            "reduceMotion: true,",
            "identity: TransitionProbe.identity,",
            "opacity: TransitionProbe.opacity",
            "),",
            ".identity",
            ")",
            "XCTAssertEqual(",
            "MedicalSafetyMotionPolicy.transition(",
            "reduceMotion: false,",
            "identity: TransitionProbe.identity,",
            "opacity: TransitionProbe.opacity",
            "),",
            ".opacity",
            ")",
            "}",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/DesignSystemTests/MedicalSafetyFocusPolicyTests.swift": "\n".join(
        [
            "func testLevelTwoAppearanceActivatesHeadingFocusAndRemovalClearsIt() {",
            "XCTAssertTrue(",
            "MedicalSafetyFocusPolicy.headingFocused(isLevelTwoPresented: true)",
            ")",
            "XCTAssertFalse(",
            "MedicalSafetyFocusPolicy.headingFocused(isLevelTwoPresented: false)",
            ")",
            "}",
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
            "testLoadOrdersHistoryAndWallTestOnlyRecordDoesNotTriggerSafety",
            "XCTAssertNil(viewModel.safetyPresentation.levelTwo)",
            "viewModel.previousExplicitSymptomScore, 3",
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
            "TrainingSymptomSafetyContext",
            "symptomSafetyPresentationProvider",
            ".priorOverheadPressResponse(.notAsked)",
            ".priorOverheadPressResponse(.uncertain)",
            "missingAnswerSafetyPresentation",
            "An explicit symptom-free answer must clear only the fail-closed missing-answer L2.",
            ".stopped(alternative: heldRepository.ohpSafeAlternative)",
            "testStoredPriorSymptomsAndUncertaintyStopOHPAtTheSafeAlternative",
            "testAnsweringPriorSymptomsOrUncertaintyStopsOHPAtTheSafeAlternative",
            "testCurrentOHPSymptomStopsBeforeTheRepositoryWriteCompletes",
            "waitUntilOHPSymptomUpdateIsSuspended",
            ".saving(request: expectedRequest)",
            "A pending exact write must reject a second write or retry.",
            "testCurrentOHPSymptomWriteFailureRetainsStopAndRetriesTheExactRequestOnce",
            ".failed(request: request)",
            "XCTAssertTrue(viewModel.hasPendingCurrentOHPSymptomWrite)",
            "Pending current-symptom persistence must block exercise progress and completion.",
            "A failed pending write must keep route actions fail closed until exact retry succeeds.",
            "repository.deletedSessionIDs.count",
            "retryCurrentOHPSymptomWrite",
            "[request.repositoryUpdate, request.repositoryUpdate]",
            "Retry must preserve the original session, response, and timestamp.",
            "XCTAssertEqual(symptomClient.events, [expectedEvent])",
            "testAdvanceRouteFirstRejectsSymptomAndDuplicateRoutesUntilChosenProgressCompletes",
            "testGoBackRouteFirstRejectsSymptomUntilChosenProgressCompletes",
            "testFinishRouteFirstKeepsTheLockThroughProgressAndTransition",
            "testRouteLockClearsAfterAppliedProgressFailureWithoutAcceptingSymptom",
            "waitUntilProgressUpdateIsSuspended",
            "waitUntilTransitionIsSuspended",
            "XCTAssertTrue(viewModel.isSessionRouteMutationInFlight)",
            "XCTAssertFalse(viewModel.canReportCurrentOHPSymptom)",
            "XCTAssertTrue(repository.ohpSymptomUpdates.isEmpty)",
            "XCTAssertEqual(repository.progressUpdates.count, progressCount + 1)",
            "XCTAssertEqual(repository.progress?.stage, .cooldown)",
            "XCTAssertEqual(repository.progress?.stage, .warmup)",
            "XCTAssertEqual(repository.progress?.stage, .summary)",
            "XCTAssertEqual(viewModel.state, .failed(.progress))",
            "testDeletionFailurePreservesStoppedSymptomRetryAndExactRequest",
            "testSuccessfulDeletionIsTheOnlyDeletionPathThatDiscardsPendingSymptomRetry",
            "testDeleteFirstLeaseRejectsSymptomRoutesAndDuplicateDeleteUntilSuccess",
            "testSuspendedDeletionFailureRetainsStoppedExactRetryUntilLeaseReleases",
            "testRouteFirstLeaseRejectsDeletionRequestAndConfirmationBeforeRepositoryAwait",
            "testCancelledDeletionReleasesLeaseAndPreservesExactStoppedRetry",
            "waitUntilDeletionIsSuspended",
            "repository.suspendNextDeletion()",
            "repository.resumeSuspendedDeletion()",
            "deletion.cancel()",
            "try Task.checkCancellation()",
            "deleteAttempts.append(id)",
            "XCTAssertTrue(viewModel.isSessionDeletionInFlight)",
            "XCTAssertEqual(repository.deleteAttempts, [sessionID])",
            "XCTAssertTrue(viewModel.hasSessionDeletionFailure)",
            "XCTAssertEqual(viewModel.state, stoppedState)",
            "XCTAssertTrue(repository.deletedSessionIDs.isEmpty)",
            "XCTAssertEqual(repository.deletedSessionIDs, [sessionID])",
            "testOrdinaryDeletionFailureRetainsTheExistingRecoverableFailureRoute",
            "XCTAssertEqual(viewModel.state, .failed(.deletion))",
            "testStartTailOwnsSessionUntilInitialProgressFinishesAndDeleteFirstRejectsRestart",
            "testRestoredStartKeepsItsOwnerThroughTheActiveSymptomJournalTail",
            "testWarmupAndCooldownChecklistOwnersBlockDeletionUntilProgressReturns",
            "testPriorResponseAndDeloadOwnersBlockDeletionThroughRepositoryStateWrites",
            "testSetSaveAndExactRetryEachOwnTheirWholeRepositoryLifetime",
            "testSummarySaveOwnerBlocksDeletionUntilItsDismissalCommits",
            "testOverlappingOwnersReleaseOnlyTheirExactTokenBeforeDeletionBecomesAvailable",
            "testCancelledSessionMutationReleasesOnlyItsOwnerAndAllowsDeletion",
            "testJournalRetryMayFinishAfterDeletionWithoutRepublishingSessionState",
            "XCTAssertEqual(viewModel.activeSessionMutationCount, 2)",
            '"The first completion must remove only its exact owner token."',
            '"Metrics-only journal retry must not own the session deletion boundary."',
            "assertDeletionRejectedWhileSessionMutationOwned",
            "suspendNextDeloadUpdate",
            "suspendNextSetSave",
            "suspendNextSummaryUpdate",
            "suspendNextRecord",
            "OneShotSuspensionGate",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/GuidanceKitTests/OHPSafetyGateTests.swift": " ".join(
        [
            "testOnlyExplicitSymptomFreeResponseAllowsLoadIncrease",
            "safetyStop: OHPSafetyGate.SafetyStop?",
            ".symptomsPresent,",
            ".blocked(.previousSymptomsPresent),",
            ".uncertain,",
            ".blocked(.previousResponseUncertain),",
            ".init(alternative: .halfKneelingDBPress)",
            "XCTAssertEqual(decision.safetyStop, expectation.safetyStop)",
        ]
    ),
    "HealthTrackingAppTests/TodayCompositionTests.swift": " ".join(
        [
            "testAppRootExplicitInitializerSupportsComposedAndDefaultMedicalSafetyController",
            "testMedicalSafetyFirstUseEvidenceRequiresOneExplicitUITestFlag",
            "AppUITestLaunchConfiguration.medicalSafetyFirstUseEvidenceFlag",
            ".exposesMedicalSafetyFirstUseEvidence",
            "Duplicate medical-safety evidence flags must fail closed.",
            "rootInitializerIsTypeChecked",
            "rootInitializerWithMedicalSafetyControllerIsTypeChecked",
            "medicalSafetyAcknowledgementController:",
            "dependencies.medicalSafetyAcknowledgementController",
        ]
    ),
    "HealthTrackingAppTests/SymptomJournalAdapterTests.swift": " ".join(
        [
            "TrainingSymptomMetricsAdapter",
            "TrainingSymptomSafetyMapper.overheadPressSymptom",
            "XCTAssertEqual(repository.upserts[0], repository.upserts[1])",
            'XCTAssertEqual(repository.upserts[0].input.region, "OHP")',
            "testStructuredMissingOHPSessionResponsesMapToCentralFailClosedPresentation",
            "OHPSymptomResponse.notAsked, .uncertain",
            "TrainingSymptomSafetyMapper.presentation",
            ".priorOverheadPressResponse(response)",
            ".priorOverheadPressResponse(.symptomFree)",
            "expectedGeneralMessage",
            "XCTAssertEqual(presentation.levelTwoMessage, expectedGeneralMessage)",
            "testAppDependenciesComposesStructuredSafetyProviderIntoSessionViewModel",
            "AppDependencies(environment: .uiTesting)",
            "dependencies.makeSessionViewModel()",
            "session.resolveSymptomSafetyPresentation(for: context)",
            "session.resolveSymptomSafetyPresentation(",
        ]
    ),
    "HealthTrackingAppTests/MedicalSafetyAcknowledgementTests.swift": " ".join(
        [
            "testSuccessfulAcknowledgementPersistsAcrossControllerRecreationWithoutChangingLevelOne",
            "testFailedAcknowledgementWriteKeepsLevelZeroVisibleAndLevelOnePermanent",
            "MedicalSafetyAcknowledgementController",
            "MedicalSafetyAcknowledgementStore",
            "XCTAssertFalse(controller.acknowledge())",
            "XCTAssertTrue(controller.isLevelZeroVisible)",
            "levelOnePresentation, .permanent",
        ]
    ),
    "HealthTrackingAppUITests/PostureFlowUITests.swift": "\n".join(
        [
            '"-ui-test-scenario", "m3-posture"',
            "today.posture.action",
            "posture.entry.save-error",
            "posture.entry.retry",
            "posture.history.loaded",
            "medical.disclaimer.l1",
            '.matching(identifier: "medical.disclaimer.l1")',
            ".firstMatch",
            "medical.safety.l2",
            "m3-posture-entry-ax5",
            "m3-posture-high-contrast",
            "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir.",
            "assertDisclaimer(in: app)",
            "replaceText(",
            'in: textField("posture.entry.region", in: app),',
            'with: "Boyun"',
            ")",
            "replaceText(",
            'in: textField("posture.entry.note", in: app),',
            'with: "OHP sonrası takip"',
            ")",
            "replaceText(",
            'in: textField("posture.entry.symptom", in: app),',
            'with: "6",',
            "dismissKeyboardAfterTyping: false",
            ")",
            "assertCompleteGeneralLevelTwo(",
            "The final symptom input must immediately publish the complete L2.",
            "medical.safety.l2.heading",
            "The stable heading must not replace the complete L2 message.",
            "expectedGeneralMessage",
            "XCTAssertEqual(",
            "-UIAccessibilityReduceMotionEnabled",
        ]
    ),
    "HealthTrackingAppUITests/OHPSafetyFlowUITests.swift": " ".join(
        [
            "session.ohp.journal.error",
            "session.ohp.journal.retry",
            "session.ohp.journal.recorded",
            "medical.disclaimer.l1",
            "medical.safety.l2",
            "medical.safety.l2.heading",
            "-UIAccessibilityReduceMotionEnabled",
            "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir.",
            "assertCompleteGeneralLevelTwo",
            "An unanswered prior OHP response must fail closed before it is answered.",
            "An explicit symptom-free answer must clear the missing-answer L2.",
            "The stable heading must not replace the complete L2 message.",
            "expectedGeneralMessage",
            "XCTAssertEqual(",
            "testAnsweredPriorSymptomsAndUncertaintyRenderTheShippedStoppedRoute",
            "-ui-test-store-identifier",
            "A stored prior response must not reopen the unanswered question.",
            "must restore the stopped route.",
            "session.ohp.prior.symptoms-present",
            "session.ohp.prior.uncertain",
            "A prior safety stop must not expose the current-symptom action.",
            "session.ohp.persistence.error",
            "session.ohp.persistence.retry",
            "persistenceRetry.frame.height + 0.01",
            "The shipped persistence retry target must remain at least 52 points high.",
            "session.exercise.finish-incomplete",
            "session.close",
            "app.buttons.matching(identifier: identifier).firstMatch",
            "app.buttons.matching(identifier: identifier).firstMatch",
            "app.buttons.matching(identifier: identifier).firstMatch",
            "Pending OHP persistence must disable the route control:",
            "Successful exact retry must re-enable the route control:",
            '"Pending OHP persistence must disable the route control: \\(identifier)."',
            '"Successful exact retry must re-enable the route control: \\(identifier)."',
            'let blockedRouteControls = ["session.exercise.next", '
            '"session.exercise.back", "session.exercise.finish-incomplete", '
            '"session.close", ]',
            "XCTAssertGreaterThanOrEqual(persistenceRetry.frame.height + 0.01, 52,",
            "The journal must start only after the exact pending training-state write succeeds.",
            "session.delete.confirm.action",
            "session.delete.error",
            "A failed deletion must stay on the stopped route and expose a separate error.",
            "A failed deletion must not replace the current OHP safety stop.",
            "A failed deletion must preserve the exact symptom persistence retry.",
            "Deletion failure must keep the pending route control disabled:",
        ]
    ),
    "HealthTrackingAppUITests/MedicalSafetyFlowUITests.swift": " ".join(
        [
            "testFirstUseExplanationPersistsIndependentlyFromPermanentReminderDisclaimer",
            "-ui-test-medical-safety-first-use-evidence",
            "medical.explanation.l0",
            "medical.explanation.l0.acknowledge",
            "acknowledgement.frame.height + 0.01",
            "The shipped L0 acknowledgement target must remain at least 52 points high.",
            "XCTAssertGreaterThanOrEqual(acknowledgement.frame.height + 0.01, 52,",
            "firstLaunch.terminate()",
            "medical.disclaimer.l1",
        ]
    ),
    "HealthTrackingAppUITests/TrainingAccessibilityUITests.swift": " ".join(
        [
            "acknowledgeFirstUseExplanationIfNeeded(in: app)",
            "-ui-test-medical-safety-first-use-evidence",
            "The first-use L0 acknowledgement must retain its 52-point target at AX5.",
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
            "medical.disclaimer.l1",
            "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir.",
            "assertDisclaimer(in: app)",
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
            "bloodwork.disclaimer.l1",
            "bloodwork.list.error",
            "bloodwork.list.empty",
            "bloodwork.editor.content",
            "bloodwork.detail.content",
            "bloodwork.detail.delete-confirm",
            "failedMarker.isEnabled",
            "health-check.history.error",
            "m3-bloodwork-editor-dark-high-contrast",
            "m3-bloodwork-editor-ax5",
            "assertDisclaimer(in: app)",
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
    "App/Application/TrainingSymptomMetricsAdapter.swift": "\n".join(
        [
            "enum TrainingSymptomSafetyMapper {",
            "static func presentation(for context: TrainingSymptomSafetyContext) {",
            "case .priorOverheadPressResponse(.notAsked)",
            "case .priorOverheadPressResponse(.uncertain)",
            "case .currentOverheadPressResponse(.symptomsPresent)",
            "let missing = MedicalSafetyTrigger.missingSymptomAnswer",
            "let current = MedicalSafetyTrigger.overheadPressSymptom",
            "}",
            "}",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/DesignSystem/Accessibility/MedicalSafetyFocusPolicy.swift": "\n".join(
        [
            "enum MedicalSafetyFocusPolicy {",
            "static func headingFocused(isLevelTwoPresented: Bool) -> Bool {",
            "isLevelTwoPresented",
            "}",
            "}",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/DesignSystem/Motion/MedicalSafetyMotionPolicy.swift": "\n".join(
        [
            "enum MedicalSafetyMotionPolicy {",
            "static func transition<Value>(",
            "reduceMotion: Bool,",
            "identity: Value,",
            "opacity: Value",
            ") -> Value {",
            "guard !reduceMotion else { return identity }",
            "return opacity",
            "}",
            "}",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/MetricsKit/Posture/PostureEntryView.swift": (
        m310_safety_ui_fixture
    ),
    "Packages/HealthTrackingModules/Sources/TrainingKit/Session/OHPPriorSymptomQuestionView.swift": (
        m310_safety_ui_fixture
    ),
    "Packages/HealthTrackingModules/Sources/TrainingKit/Session/ExerciseStageView.swift": (
        m310_safety_ui_fixture
        + "\n"
        + "ohpSymptomWriteState\n"
        + 'accessibilityIdentifier("session.ohp.persistence.saving")\n'
        + 'accessibilityIdentifier("session.ohp.persistence.error")\n'
        + "Button { Task { await viewModel.retryCurrentOHPSymptomWrite() } } label: {\n"
        + 'Text(localized("session.ohp.persistence.retry"))\n'
        + ".frame(maxWidth: .infinity, minHeight: 52)\n"
        + ".contentShape(Rectangle())\n"
        + "}\n"
        + 'accessibilityIdentifier("session.ohp.persistence.retry")\n'
        + ".disabled(viewModel.isSessionDeletionInFlight)\n"
        + "if viewModel.canReportCurrentOHPSymptom { }\n"
        + "if viewModel.hasSessionDeletionFailure {\n"
        + 'Text("delete failed").accessibilityIdentifier("session.delete.error")\n'
        + "}\n"
        + 'accessibilityIdentifier("session.exercise.next")\n'
        + ".disabled(viewModel.hasPendingCurrentOHPSymptomWrite || viewModel.isSessionDeletionInFlight)\n"
        + 'accessibilityIdentifier("session.exercise.back")\n'
        + ".disabled(viewModel.hasPendingCurrentOHPSymptomWrite || viewModel.isSessionDeletionInFlight)\n"
        + 'accessibilityIdentifier("session.exercise.finish-incomplete")\n'
        + ".disabled(viewModel.hasPendingCurrentOHPSymptomWrite || viewModel.isSessionDeletionInFlight)"
    ),
    "Packages/HealthTrackingModules/Sources/TrainingKit/Session/TrainingSessionView.swift": "\n".join(
        [
            'accessibilityIdentifier("session.close")',
            ".disabled(viewModel.hasPendingCurrentOHPSymptomWrite || viewModel.isSessionMutationInFlight || viewModel.isSessionDeletionInFlight)",
            'accessibilityIdentifier("session.delete")',
            ".disabled(viewModel.isCurrentOHPSymptomWriteSaving || viewModel.isSessionRouteMutationInFlight || viewModel.isSessionMutationInFlight || viewModel.isSessionDeletionInFlight)",
            'accessibilityIdentifier("session.delete.confirm.action")',
            ".disabled(viewModel.isSessionRouteMutationInFlight || viewModel.isSessionMutationInFlight || viewModel.isSessionDeletionInFlight)",
            "func activeContent() {",
            "let content = true",
            ".disabled(viewModel.isSessionDeletionInFlight)",
            "}",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/GuidanceKit/Safety/OHPSafetyGate.swift": "\n".join(
        [
            "switch previousSession.response {",
            "case .symptomsPresent:",
            "let priorSymptoms = Decision(",
            "safetyStop: SafetyStop(alternative: .halfKneelingDBPress)",
            ")",
            "case .uncertain:",
            "let priorUncertain = Decision(",
            "safetyStop: SafetyStop(alternative: .halfKneelingDBPress)",
            ")",
            "}",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/TrainingKit/Snapshots/TrainingSnapshots.swift": "\n".join(
        [
            "public struct SessionOHPSymptomWriteRequest {",
            "public let sessionID: UUID",
            "public let response: OHPSymptomResponse",
            "public let reportedAt: Date",
            "}",
            "public enum SessionOHPSymptomWriteState {",
            "case idle",
            "case saving(request: SessionOHPSymptomWriteRequest)",
            "case failed(request: SessionOHPSymptomWriteRequest)",
            "}",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/TrainingKit/Session/SessionViewModel.swift": "\n".join(
        [
            "var ohpSymptomWriteState = SessionOHPSymptomWriteState.idle",
            "var pendingOHPSymptomWriteRequest: SessionOHPSymptomWriteRequest?",
            "public private(set) var isSessionRouteMutationInFlight = false",
            "public private(set) var isSessionDeletionInFlight = false",
            "public private(set) var hasSessionDeletionFailure = false",
            "private var sessionMutationOwners: Set<UUID> = []",
            "public var activeSessionMutationCount: Int { sessionMutationOwners.count }",
            "public var isSessionMutationInFlight: Bool { !sessionMutationOwners.isEmpty }",
            "private func beginSessionMutation() -> UUID? {",
            "guard !isSessionDeletionInFlight else { return nil }",
            "let owner = UUID()",
            "sessionMutationOwners.insert(owner)",
            "return owner",
            "}",
            "private func endSessionMutation(_ owner: UUID) {",
            "sessionMutationOwners.remove(owner)",
            "}",
            "var canReportCurrentOHPSymptom: Bool {",
            "guard !isSessionRouteMutationInFlight, !isSessionDeletionInFlight else { return false }",
            "return true",
            "}",
            "var hasPendingCurrentOHPSymptomWrite: Bool {",
            "guard pendingOHPSymptomWriteRequest != nil else { return false }",
            "switch ohpSymptomWriteState {",
            "case .saving, .failed: return true",
            "case .idle: return false",
            "}",
            "}",
            "var isCurrentOHPSymptomWriteSaving: Bool {",
            "guard pendingOHPSymptomWriteRequest != nil else { return false }",
            "if case .saving = ohpSymptomWriteState { return true }",
            "return false",
            "}",
            "func reportCurrentOHPSymptom() async {",
            "guard !isSessionRouteMutationInFlight, !isSessionDeletionInFlight, pendingOHPSymptomWriteRequest == nil else { return }",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "let request = SessionOHPSymptomWriteRequest(",
            "pendingOHPSymptomWriteRequest = request",
            "replaceActiveSession(optimistic)",
            "resolveOHPSafety(currentSession: optimistic, previousSession: nil)",
            "ohpSymptomWriteState = .saving(request: request)",
            "await persistCurrentOHPSymptomWrite(request)",
            "}",
            "func persistCurrentOHPSymptomWrite(_ request: SessionOHPSymptomWriteRequest) async {",
            "do {",
            "let updated = try await coordinator.recordOHPSymptomResponse(",
            "pendingOHPSymptomWriteRequest = nil",
            "ohpSymptomWriteState = .idle",
            "await recordSymptomEvent(",
            "occurredAt: request.reportedAt",
            ")",
            "} catch {",
            "ohpSymptomWriteState = .failed(request: request)",
            "}",
            "}",
            "func retryCurrentOHPSymptomWrite() async {",
            "guard !isSessionDeletionInFlight, let request = pendingOHPSymptomWriteRequest else { return }",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "await persistCurrentOHPSymptomWrite(request)",
            "}",
            "func retrySymptomJournal() async {",
            "await recordSymptomEvent(event)",
            "}",
            "func start() async {",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "await loadSession()",
            "}",
            "func toggleWarmupItem() async {",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "await persistProgress()",
            "}",
            "func completeWarmup() async {",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "await leaveWarmup()",
            "}",
            "func skipWarmup() async {",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "await leaveWarmup()",
            "}",
            "func answerPreviousOHPSymptom() async {",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "await savePreviousResponse()",
            "}",
            "func respondToDeload() async {",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "await saveDeloadResponse()",
            "}",
            "func advanceExercise() async {",
            "guard !hasPendingCurrentOHPSymptomWrite, !isSessionRouteMutationInFlight, !isSessionDeletionInFlight else { return }",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "isSessionRouteMutationInFlight = true",
            "defer { isSessionRouteMutationInFlight = false }",
            "await persistProgress()",
            "}",
            "func goBack() async {",
            "guard !hasPendingCurrentOHPSymptomWrite, !isSessionRouteMutationInFlight, !isSessionDeletionInFlight else { return }",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "isSessionRouteMutationInFlight = true",
            "defer { isSessionRouteMutationInFlight = false }",
            "await persistProgress()",
            "}",
            "func finishSession() async {",
            "guard !hasPendingCurrentOHPSymptomWrite, !isSessionRouteMutationInFlight, !isSessionDeletionInFlight else { return }",
            "isSessionRouteMutationInFlight = true",
            "defer { isSessionRouteMutationInFlight = false }",
            "await persistProgress()",
            "}",
            "func toggleCooldownItem() async {",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "await persistProgress()",
            "}",
            "func completeCooldown() async {",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "await finishSession()",
            "}",
            "func skipCooldown() async {",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "await finishSession()",
            "}",
            "func finishIncomplete() async {",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "await finishSession()",
            "}",
            "func saveCurrentSet() async {",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "await performSave()",
            "}",
            "func retrySetSave() async {",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "await performSave()",
            "}",
            "func saveSummary() async {",
            "guard let sessionMutationOwner = beginSessionMutation() else { return }",
            "defer { endSessionMutation(sessionMutationOwner) }",
            "await updateSummary()",
            "}",
            "func selectRecovery() { guard !isSessionDeletionInFlight else { return } }",
            "func selectPerformedVariant() { guard !isSessionDeletionInFlight else { return } }",
            "func stepperChanged() { guard !isSessionDeletionInFlight else { return } }",
            "func updateSummaryNote() { guard !isSessionDeletionInFlight else { return } }",
            "func requestDeletion() {",
            "guard !isCurrentOHPSymptomWriteSaving, !isSessionRouteMutationInFlight, !isSessionMutationInFlight, !isSessionDeletionInFlight else { return }",
            "}",
            "func confirmDeletion() async {",
            "guard !isCurrentOHPSymptomWriteSaving, !isSessionRouteMutationInFlight, !isSessionMutationInFlight, !isSessionDeletionInFlight else { return }",
            "isSessionDeletionInFlight = true",
            "defer { isSessionDeletionInFlight = false }",
            "do {",
            "try await repository.deleteWorkoutSession(id: sessionID)",
            "pendingOHPSymptomWriteRequest = nil",
            "ohpSymptomWriteState = .idle",
            "hasSessionDeletionFailure = false",
            "state = .dismissed",
            "} catch {",
            "if hasPendingCurrentOHPSymptomWrite {",
            "hasSessionDeletionFailure = true",
            "} else {",
            "hasSessionDeletionFailure = false",
            "state = .failed(.deletion)",
            "}",
            "isDeleteConfirmationPresented = false",
            "}",
            "}",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/HealthSafetyKit/HealthSafetyKitModule.swift": "\n".join(
        [
            "enum HealthSafetyKitModule {}",
            "struct MedicalDisclaimerPresentation {}",
            'let disclaimer = "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."',
            "let permanent = MedicalDisclaimerPresentation() // isAlwaysVisible: true",
            "enum MedicalSafetyTrigger { case missingSymptomAnswer }",
            "private static let redFlagInformation =",
            '"Yeni veya belirgin şekilde kötüleşen kol veya bacakta güçsüzlük ya da uyuşma, el becerisinde kayıp, denge veya yürümede değişiklik ya da mesane veya bağırsak işlevinde değişiklik acil tıbbi değerlendirme gerektirir."',
            "private static let generalStopMessage =",
            '"Hareketi durdur. Kalıcı veya kötüleşen belirtiler bir sağlık profesyoneli tarafından değerlendirilmelidir. "',
            '+ "\\(redFlagInformation)"',
            "private static let urgentMessage =",
            '"Hareketi durdur. \\(redFlagInformation)"',
            "let generalUrgency = (requiresUrgentAssessment: false)",
            "let explicitUrgency = (requiresUrgentAssessment: true)",
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
            "import CoreModels",
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
            "ProgressPhotoGalleryViewModel",
            "progressPhotoGalleryViewModel",
            "UITestProgressPhotoGalleryRepository",
            "scenario == .m3PhotoGallery",
            "progressPhotoRepository: UITestProgressPhotoGalleryRepository()",
            "func fullImage(assetID:",
            "progressPhotoAssetSynchronizer",
            "makeProgressPhotoAssetSynchronizer",
            "guard case let .cloud(containerIdentifier, storeURL)",
            "NoOpCloudPhotoAssetCoordinator.shared",
            "guard case .cloud = environment else",
            "NoOpCloudPhotoAssetDeletionIntentStore.shared",
            "NoOpCloudPhotoAssetInboundJournal.shared",
            "CloudKitPrivatePhotoAssetDatabase",
            "FileCloudPhotoAssetSyncStateStore",
            "FileCloudPhotoAssetTemporaryStore",
            "let deletionIntentStore = FileCloudPhotoAssetDeletionIntentStore(",
            "let inboundAssetJournal = FileCloudPhotoAssetInboundJournal(",
            "deletionIntentStore: deletionIntentStore",
            "deletionIntentStore: deletionIntentStore",
            "inboundAssetJournal: inboundAssetJournal",
            "inboundAssetStore: progressPhotoAssetStore",
            "referenceSnapshotProvider: progressPhotoRepository",
            "inboundAssetApplier: progressPhotoRepository",
            "any CloudPhotoAssetReferenceSnapshotProviding & CloudPhotoAssetInboundApplying",
            "let cloudPhotoAssetTransferStore = FileCloudPhotoAssetTemporaryStore(",
            "downloadStore: cloudPhotoAssetTransferStore",
            "temporaryStore: cloudPhotoAssetTransferStore",
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
            "testCloudRestoreUsesExactOpaqueIDAndRebuildsBothVariantsIdempotently",
            "restoreCloudAsset(id:",
            "cloudAssetBytes(id:",
            "deleteCloudAsset(id:",
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
            "testThumbnailAndFullImageUseExplicitAssetVariants",
            "testAbsoluteOrMalformedPersistedImageRefFailsClosed",
            "PhotoAssetCleanupJournalFake",
            "testStartupReconciliationKeepsReferencedAssetAndDeletesCrashWindowOrphan",
            "testStartupInventoryDeletesUnjournaledOrphanFromRenameCrashWindow",
            "storedAssetIDs",
            "testDuplicateImageReferenceFailsClosedBeforeEitherOwnerCanDelete",
            "testReconciliationSerializesAConcurrentImportAcrossSuspension",
            "testJournalAndImmediateDeleteFailureQueuesOrphanForCurrentProcessRetry",
            "testJournalAndDeleteCompensationFailureQueuesOrphanForRetry",
            "testCommittedMetadataDeletionPersistsUntilCloudRetrySucceedsAfterRelaunch",
            "testRepositoryCloudReferenceSnapshotIsImmutableAcrossLaterMetadataChange",
            "testInboundCloudAssetSurvivesCoordinatorRestoreCrashAndRepositoryRelaunch",
            "testSuccessfulInboundSyncRetainsIntentUntilMetadataReferencesAsset",
            "testRepositoryConsumesOnlyInboundIDsMatchedByMetadataAcrossRelaunches",
            "testSnapshotReconcilesInboundOwnershipArrivingAfterInitialFetchPerID",
            "testInboundApplyFinishesBeforeQueuedDeleteAndFinalStateRemainsDeleted",
            "testRepositoryInboundApplyWithoutCommittedDeletionPreservesAssetBeforeMetadata",
            "testDeleteCommittedBeforeStaleChangedPageDiscardsInboundAndRetainsIntent",
            "testStaleChangedPageCannotRestoreDeletionQuarantinedByNewerAccountResolution",
            "testStaleGenerationCancelsPreparedInboundLeaseBeforeAnySideEffectAndRepositoryReacquires",
            "testInboundPreparationLeaseRejectsABAAndReleasesAfterCancellation",
            "PausingBeforeRecordCloudPhotoAssetDeletionIntentStore",
            "ObservedCloudPhotoAssetInboundApplier",
            "recordedReceipt.quarantineIdentityHint",
            "durableText.contains(recordedReceipt.intentID.uuidString)",
            "calls.commitLeaseAssetIDs.isEmpty",
            "calls.cancelLeaseAssetIDs, [inboundID]",
            "repository.cancelInboundApply(firstLease)",
            "repository.commitInboundApply(secondLease",
            "retryPreparation",
            "inboundAssetStore: assetStore",
            "inboundAssetApplier: repository",
            "waitForFetchCall(1)",
            "finishedWhileRestoreHeld",
            "transfersAfterRace.isEmpty",
            "pendingAfterDeferred, [assetID]",
            "testInboundRestoreProtectsPreviouslyFailedOrphanFromCleanupRetry",
            "testInitialOrphanSweepRereadsInboundOwnershipAtDeleteBoundary",
            "testInboundJournalReadFailureStopsPendingCleanupRetryBeforeDelete",
            "testCleanupRetryRechecksInboundOwnershipAfterEarlierAssetDeleteSuspends",
            "testInboundRecordWaitsForCleanupLeaseAndRestoreSurvivesDeleteBoundary",
            "testCancelledInboundRecordRemovesExactWaiterAndAllowsLaterCleanupLease",
            "waitForInboundRecordWaiter",
            "inboundRecordWaiterIDs",
            "A cancelled inbound record must finish before lease release.",
            "waitersAfterCancellation.isEmpty",
            "pendingBeforeLeaseRelease.isEmpty",
            "laterLease",
            "CleanupLeaseInterleavingAssetStore",
            "SequencedCloudPhotoAssetInboundJournal",
            "snapshotAfterA",
            "testMetadataDeleteSaveFailureNeverCreatesCloudDeletionIntent",
            "testCompensatedLocalDeleteFailureClearsCloudIntentBeforeReturning",
            "testCompensationClearsExactHintedIntentPromotedWhileReceiptIsPaused",
            "PausingAfterRecordCloudPhotoAssetDeletionIntentStore",
            "scopedAfterCompensation.isEmpty",
            "quarantineAfterCompensation.isEmpty",
            "XCTAssertEqual(intentCalls.recordCalls, [])",
            "XCTAssertEqual(intentCalls.clearCalls, [])",
            "let persistedContext = ModelContext(container)",
            "persistedPhotoIDs([])",
            "pendingAfterA, [assetB]",
            "pendingAfterARelaunch, [assetB]",
            "cloudAssets[assetB], bytesB",
            "FileCloudPhotoAssetDeletionIntentStore",
            "FileCloudPhotoAssetInboundJournal",
            "inboundAssetJournal:",
            "CloudPhotoAssetLocalStoring",
            "func usableCloudAssetIDs()",
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
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/ProgressPhotoGalleryViewModelTests.swift": " ".join(
        [
            "testLoadOrdersNewestDateThenFrontSideBackAndKeepsSafeAssetFallbacks",
            "testIndividualThumbnailErrorKeepsMetadataRowAsUnavailableFallback",
            "testThirdSelectionReplacesOldestChoiceAndOrdersComparisonChronologically",
            "testMissingCorruptUnknownAndUnavailablePhotosCannotBeSelected",
            "testReloadPrunesDeletedOrNewlyUnavailableSelections",
            "testLargeGalleryDefersEveryThumbnailAndLoadsFullImagesOnlyForCompare",
            "testProtectedDataFallbackRetriesAfterUnlockWithoutReloadingMetadata",
            "testCompareFullImageFallbacksRetryProtectedDataWithoutThumbnailReuse",
            "testThumbnailCacheEvictsLeastRecentUnselectedAsset",
            "replacedOldest(removedID:",
            "repository.thumbnailRequests",
            "repository.fullImageRequests",
            "loadComparisonImages()",
            "retryUnavailableAssets()",
            "testSuccessfulSyncReloadsExactMissingAndCorruptGalleryStatesInOpenLifecycle",
            "ProgressPhotoAssetSyncLifecycle",
            "comparison?.before.assetState",
            "fullImageRequests.filter",
        ]
    ),
    "HealthTrackingAppUITests/ProgressPhotoGalleryUITests.swift": " ".join(
        [
            '"-ui-test-scenario", "m3-photo-gallery"',
            "photos.gallery.content",
            "photos.gallery.missing",
            "photos.gallery.corrupt",
            "photos.gallery.select.",
            "photos.gallery.selected.",
            "photos.compare.content",
            "photos.compare.before",
            "photos.compare.after",
            "photos.compare.replaced",
            "first.label.contains(\"1970\")",
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
            "public func usableCloudAssetIDs() async throws -> Set<String> {",
            "let physicalAssetIDs = try await storedAssetIDs()",
            "var usableAssetIDs: Set<String> = []",
            "for assetID in physicalAssetIDs.sorted()",
            "let full = try await loadAsset(id: assetID, variant: .full)",
            "guard case .available = full else { continue }",
            "let thumbnail = try await loadAsset(id: assetID, variant: .thumbnail)",
            "guard case .available = thumbnail else { continue }",
            "usableAssetIDs.insert(assetID)",
            "return usableAssetIDs",
            "private func prepareStorage",
            "error as? PhotoAssetStoreError",
            "CloudPhotoAssetLocalStoring",
            "cloudAssetBytes(id:",
            "restoreCloudAsset(id:",
            "deleteCloudAsset(id:",
            "replacingExisting: true",
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
            "func fullImage(assetID:",
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
            "galleryViewModel: ProgressPhotoGalleryViewModel",
            "ProgressPhotoGalleryView(",
            "await galleryViewModel.load()",
            "galleryViewModel.retryUnavailableAssets()",
            "switch galleryViewModel.phase",
            "galleryViewModel.items.isEmpty",
            "assetSynchronizer: any CloudPhotoAssetSynchronizing",
            "assetSyncLifecycle",
            "await assetSyncLifecycle.synchronize()",
            "await synchronizeAssets()",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/CloudPhotoAssetContractTests.swift": " ".join(
        [
            "testRecordContractUsesDeterministicOpaqueNameAndPrivacyAllowlist",
            "testChecksumIsStableAndValidationRejectsSizeOrDigestMismatch",
            "testOpaqueSyncStatePersistsQueuesKnownIDsAndChangeToken",
            "testTemporaryStoreOwnsUploadAndDownloadCopiesUntilExplicitCleanup",
            "testAdapterStagesDownloadIntoOwnedStorageBeforeSystemSourceDisappears",
            "testDownloadStagingRejectsOversizedMetadataBeforeOpeningSource",
            "testDownloadStagingBoundsActualBytesAndRejectsMetadataMismatch",
            "testRealBoundedStagerLimitsReadRequestsAndNeverWritesMaximumPlusOneByte",
            "testDownloadStagingDeletesOutputAndClosesReaderWhenWriterCloseFails",
            "XCTAssertEqual(snapshot.closeCallCount, 2)",
            "fileHandleFactory:",
            "testTemporaryStoreRecreationSweepsStaleTransferFiles",
            "CocoaError.Code.fileReadNoPermission.rawValue",
            "nestedUnrelated",
            "unrelatedAsset",
            "symlinkTarget",
            "testLegacyUnscopedSyncStateRecreatesWithNilAccountIdentity",
            "testDeletionIntentStoreSerializesAccountTransitionAndPersistsEveryScope",
            "testLegacyDeletionIntentSetMovesToQuarantineWithoutAuthorizingCurrentAccount",
            "testDeletionIntentStoreRecreationPromotesOnlyMatchingVerifiedAccountHint",
            "testExactIntentReceiptSurvivesPromotionAndDoesNotClearSameAssetABA",
            "testStaleAccountResolutionCannotAuthorizeAfterNewerEpochBegins",
            "testDeletionIntentStoreMigratesV1AndRejectsUnknownSchemaFailClosed",
            "receipt1.intentID",
            "receipt2.intentID",
            "pendingAfterFirstClear",
            "staleResolution",
            "newerResolution",
            "catch is CancellationError",
            "quarantineUnderB",
            "A consumed resolution epoch must never authorize a second account.",
            "receiptAfterResolutionReuse.accountIdentity",
            "quarantineIdentityHint",
            "lastVerifiedAccountIdentity",
            "quarantinedIntents",
            "unresolvedDeletionAssetIDs",
            "forAccountIdentity:",
            "FileCloudPhotoAssetSyncStateStore",
            "FileCloudPhotoAssetTemporaryStore",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/CloudPhotoAssetCoordinatorTests.swift": " ".join(
        [
            "testEveryUnavailableAccountStateDefersWithoutTouchingLocalAssetsOrQueue",
            "testBackfillWaitsForServerResponseUsesPrivateZoneAndCleansUploadFile",
            "testMatchingExistingRecordIsIdempotentAndSkipsAssetSave",
            "testRetryableSaveUsesInjectedExponentialBackoffThenCommits",
            "testPaginatedChangesPersistOpaqueTokenRebuildDownloadAndApplyDeletion",
            "testExpiredChangeTokenClearsPersistedTokenAndRestartsFromNil",
            "testInvalidDownloadDoesNotAdvanceTokenOrMutateLocalStore",
            "testDeletionQueueTreatsMissingServerRecordAsIdempotentSuccess",
            "testStateOnlyDeletionQueueCannotAuthorizeServerDeletion",
            "testNewerSynchronizationWinsWhenOlderUploadCompletesLate",
            "testReferencedMissingAssetRestoresFromCloudWithoutInferringDeletion",
            "testOnlyExplicitCommittedMetadataDeletionQueuesServerDeletion",
            "testReferencedMetadataNeutralizesStaleDeletionIntentWithoutDeletingCloudAsset",
            "testReferencedSnapshotNeutralizesOnlyObservedIntentAcrossSameAssetABA",
            "observedStaleIntent",
            "replacementIntent",
            "XCTAssertEqual(remainingIntents.map",
            "retrySnapshot.deleteRequests",
            "intentsAfterRetry.isEmpty",
            "stateAfterRetry.pendingDeletionAssetIDs.isEmpty",
            "testAccountIdentityChangeResetsStateAndBackfillsNewAccount",
            "testAccountResetLoadsCurrentScopeAndPreservesOldAccountQueue",
            "testAccountTransitionProcessesOnlyCurrentScopeAndPreservesOldAndUnresolvedIntents",
            "testVerifiedAccountOfflineDeletionSurvivesFailureAndRelaunchRetry",
            "testDeferredAccountTransitionQuarantinesOldHintUntilMatchingAccountReturns",
            "postCancellationReceipt.quarantineIdentityHint",
            "postFailureReceipt.quarantineIdentityHint",
            "oldAccountIDs",
            "unresolvedIDs",
            "testLegacyUnscopedFileStateResetsFailClosedAndBackfillsCurrentAccount",
            "testCancelledSynchronizationCleansOwnedPageDiscardedAfterSuspendedFetch",
            "suspendedChangeCalls",
            "testIntentCommittedAfterReadIsNotClearedAgainstOlderReferenceSnapshot",
            "pendingAfterFirst",
            "testCorruptFullVariantWithPhysicalDirectoryReplaysNilTokenAndRepairsWithoutUpload",
            "testMissingThumbnailWithPhysicalDirectoryReplaysNilTokenAndRepairsWithoutUpload",
            "let localStore = LocalPhotoAssetStore(",
            "CloudRepairPhotoAssetFileSystem",
            "try Data([0xff]).write(to: fullURL, options: .atomic)",
            "try FileManager.default.removeItem(at: thumbnailURL)",
            "let physicalBeforeRepair = try await localStore.storedAssetIDs()",
            "let usableBeforeRepair = try await localStore.usableCloudAssetIDs()",
            "NilTokenOnlyRepairCloudPhotoAssetDatabase",
            "guard previousToken == nil else",
            "databaseSnapshot.changeTokens, [nil, repairedChangeToken]",
            "databaseSnapshot.nilTokenRepairResponseCount, 1",
            "pendingUploadAssetIDs: [assetID]",
            "databaseSnapshot.saveRequests.isEmpty",
            "databaseSnapshot.deleteRequests.isEmpty",
            "repairedFull, .available(Data([0x10]))",
            "repairedThumbnail, .available(Data([0x20]))",
            "physicalAfterRepair, [assetID]",
            "usableAfterRepair, [assetID]",
            "firstState, finalState",
            "CloudPhotoAssetLocalStoring",
            "func usableCloudAssetIDs()",
            "referenceSnapshotProvider:",
            "deletionIntentStore:",
            "inboundAssetJournal:",
            "try await coordinator.synchronize()",
            "PrivateCloudPhotoAssetDatabase",
            "CloudPhotoAssetDatabaseError",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/CloudKitPrivatePhotoAssetDatabaseTests.swift": " ".join(
        [
            "testActualAdapterOwnsDownloadBeforeSystemURLDisappearsAtReturnBoundary",
            "testActualAdapterReturnsChangingOpaqueAccountIdentity",
            "testActualAdapterAndCoordinatorConsumeAndRemoveOneSharedOwnedTransfer",
            "testActualAdapterRepairsMatchingMetadataWithoutUsableBinaryAndKeepsValidAssetIdempotent",
            "CloudPhotoAssetSystemRecord",
            "hasUsableBinaryAsset: false",
            "hasUsableBinaryAsset: true",
            "missingBinary.saveRequests.map",
            "validBinary.saveRequests.isEmpty",
            "testActualCKRecordMappingRequiresReadableRegularCKAssetFile",
            "testExplicitChangedKeysModifyRepairsSameIDAssetAndPreservesUnknownFields",
            "testExplicitModifySurfacesExactPerRecordFailure",
            "ConflictAwareCloudKitPhotoAssetRecordModifier",
            "savePolicy: .ifServerRecordUnchanged",
            "RecordSavePolicy.changedKeys.rawValue",
            "serverOnly",
            "perRecordFailure",
            "CloudKitPhotoAssetRecordMapper.systemRecord",
            "missingAsset",
            "wrongTypeAsset",
            "invalidFileAsset",
            "directoryAsset",
            "validAsset",
            "CloudPhotoAssetSystemURLLifetimeOwner",
            "XCTAssertFalse(FileManager.default.fileExists(atPath: systemURL.path))",
            "CloudKitPrivatePhotoAssetDatabase",
            "systemDatabase:",
            "accountIdentityProvider:",
            "downloadStore:",
            "CloudPhotoAssetLocalStoring",
            "func usableCloudAssetIDs()",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/CloudPhotoAssetDomain.swift": "\n".join(
        [
            'public static let fieldNames = ["assetID", "asset", "checksum", "byteCount"]',
            'zoneName = "ProgressPhotoAssetsZone"',
            'recordType = "ProgressPhotoAsset"',
            "CloudPhotoAssetRecordContract",
            "CloudPhotoAssetChecksum",
            "CloudPhotoAssetSyncState",
            "pendingUploadAssetIDs",
            "pendingDeletionAssetIDs",
            "uploadedAssetIDs",
            "changeToken",
            "accountIdentity",
            "CloudPhotoAssetReferenceSnapshotProviding",
            "CloudPhotoAssetDeletionIntentStoring",
            "CloudPhotoAssetDeletionIntentReceipt",
            "public let intentID: UUID",
            "CloudPhotoAssetAccountAuthorization",
            "CloudPhotoAssetAccountResolution",
            "quarantineIdentityHint",
            "beginAccountResolution()",
            "activateAccountIdentity",
            "resolution: CloudPhotoAssetAccountResolution",
            "async throws -> CloudPhotoAssetAccountAuthorization",
            "suspendAccountAuthorization(_ authorization: CloudPhotoAssetAccountAuthorization)",
            "pendingDeletionIntents(",
            "async throws -> [CloudPhotoAssetDeletionIntentReceipt]",
            "pendingDeletionAssetIDs(",
            "forAccountIdentity accountIdentity: String",
            "unresolvedDeletionAssetIDs",
            "hasCommittedLocalDeletionIntent(assetID: String)",
            "-> CloudPhotoAssetDeletionIntentReceipt",
            "CloudPhotoAssetSystemRecord",
            "hasUsableBinaryAsset",
            "async throws -> CloudPhotoAssetSystemRecord?",
            "CloudPhotoAssetInboundJournaling",
            "CloudPhotoAssetInboundCleanupLease",
            "acquireCleanupLease(for assetID: String)",
            "releaseCleanupLease(_ lease: CloudPhotoAssetInboundCleanupLease)",
            "CloudPhotoAssetInboundApplyLease",
            "CloudPhotoAssetInboundApplyPreparation",
            "case prepared(CloudPhotoAssetInboundApplyLease)",
            "case discardedCommittedDeletion",
            "CloudPhotoAssetInboundApplying",
            "public protocol CloudPhotoAssetLocalStoring",
            "func storedAssetIDs()",
            "func usableCloudAssetIDs()",
            "public protocol CloudPhotoAssetInboundApplying",
            "func prepareInboundApply(",
            "func commitInboundApply(",
            "func cancelInboundApply(",
            "id assetID: String",
            "bytes: Data",
            "forAccountIdentity accountIdentity: String",
            "async throws -> CloudPhotoAssetInboundApplyPreparation",
            "_ lease: CloudPhotoAssetInboundApplyLease",
            "public struct CloudPhotoAssetDeletionIntentReceipt",
            "PrivateCloudPhotoAssetDatabase",
            "CloudPhotoAssetSynchronizing",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/CloudPhotoAssetCoordinator.swift": " ".join(
        [
            "public actor CloudPhotoAssetCoordinator",
            "public init( inboundAssetApplier: any CloudPhotoAssetInboundApplying ) {",
            "let accountResolution = await deletionIntentStore.beginAccountResolution()",
            "database.accountStatus()",
            "database.ensureZone",
            "let usableLocalAssetIDs = try await localStore.usableCloudAssetIDs()",
            "try validate(assetIDs: usableLocalAssetIDs)",
            "reconcile(usableLocalAssetIDs: usableLocalAssetIDs,",
            "private func reconcile(",
            "usableLocalAssetIDs: Set<String>",
            "let referencedUsable = usableLocalAssetIDs.intersection(referencedAssetIDs)",
            ".intersection(referencedUsable)",
            ".union(referencedUsable.subtracting(uploaded))",
            ".subtracting(usableLocalAssetIDs)",
            "state.changeToken = nil",
            "private func markUploaded",
            "temporaryStore.createUploadFile",
            "record.stagedFileURL",
            "CloudPhotoAssetChecksum.validate",
            "CloudPhotoAssetDatabaseError.changeTokenExpired",
            "CloudPhotoAssetDatabaseError.recordNotFound",
            "retryPolicy.delay",
            "ensureCurrent",
            "generation &+= 1",
            "state.changeToken = page.changeToken",
            "public func synchronize()",
            "deletionIntentStore",
            "try validate(state: state)",
            "let accountAuthorization = try await deletionIntentStore.activateAccountIdentity(",
            "resolution: accountResolution",
            "pendingDeletionIntents(forAccountIdentity: accountIdentity)",
            "await deletionIntentStore.suspendAccountAuthorization(accountAuthorization)",
            "await deletionIntentStore.suspendAccountAuthorization(accountAuthorization)",
            "referenceSnapshotProvider",
            "await referenceSnapshotProvider.snapshot()",
            "clearCommittedDeletion(",
            "forAccountIdentity: accountIdentity",
            "let deletions = committedDeletionIDs",
            "let referencedDeletionIntents = committedDeletionIntents.filter",
            "clearCommittedDeletion(intent)",
            "let referencedDeletionIDs = Set(referencedDeletionIntents.map(\\.assetID))",
            "committedDeletionIDs.subtract(referencedDeletionIDs)",
            "private func processDeletions(",
            "database.deleteRecord(",
            "clearCommittedDeletion(\n                assetID: assetID,",
            "forAccountIdentity: accountIdentity",
            "private func processUploads(",
            "onDiscard: { [temporaryStore = self.temporaryStore] page in",
            "private func apply(",
            "private let inboundAssetApplier: any CloudPhotoAssetInboundApplying",
            "inboundAssetApplier: any CloudPhotoAssetInboundApplying",
            "inboundAssetApplier.prepareInboundApply(",
            "forAccountIdentity: accountIdentity",
            "case .discardedCommittedDeletion:\n            return",
            "case let .prepared(lease):",
            "try ensureCurrent(generation)",
            "inboundAssetApplier.commitInboundApply(",
            "try ensureCurrent(generation)",
            "inboundAssetApplier.cancelInboundApply(",
            "markUploaded(record.assetID, state: &state)",
            "remove(record.assetID, from: &state.pendingDeletionAssetIDs)",
            "private func performWithRetry",
            "temporaryStore.removeFile(at: record.stagedFileURL)",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/FileCloudPhotoAssetStores.swift": " ".join(
        [
            "FileCloudPhotoAssetSyncStateStore",
            "public final class FileCloudPhotoAssetTemporaryStore",
            ".completeFileProtection",
            "stageDownload",
            "FileHandle",
            "fileHandleFactory",
            "read(upToCount: remaining + 1)",
            "isCanonicalTransferFileName",
            "isCanonicalTransferFileName(",
            "isCanonicalTransferFileName(",
            "isCanonicalTransferFileName(",
            "guard isOwned(url) else",
            "private func copyValidatedDownload",
            "try close(reader: reader, writer: writer)",
            "private func copyFile",
            "removeFile",
            "NoOpCloudPhotoAssetCoordinator",
            "activeAccountIdentity",
            "activeAccountAuthorization",
            "activeAccountResolutionID",
            "public func beginAccountResolution()",
            "activeAccountAuthorization = nil",
            "activeAccountResolutionID = resolution.resolutionID",
            "public func activateAccountIdentity(",
            "guard activeAccountResolutionID == resolution.resolutionID else",
            "activeAccountResolutionID = nil",
            "throw CancellationError()",
            "FileCloudPhotoAssetDeletionIntentRecord",
            "static let currentSchemaVersion = 3",
            "public func pendingDeletionIntents(",
            "async throws -> [CloudPhotoAssetDeletionIntentReceipt]",
            "intent.accountIdentity == accountIdentity",
            "intent.quarantineIdentityHint == nil",
            "intentID: intent.intentID",
            "intentID: UUID()",
            "state.intents",
            "$0.intentID == intent.intentID",
            "$0.assetID == canonicalID",
            "state.intents[index].accountIdentity = accountIdentity",
            "state.intents[index].quarantineIdentityHint = nil",
            "FileCloudPhotoAssetDeletionIntentV2State",
            "public func hasCommittedLocalDeletionIntent(assetID: String)",
            "canonicalAssetID(assetID)",
            "loadState()",
            "state.intents.contains { $0.assetID == canonicalID }",
            "public func recordCommittedDeletion",
            "public func hasCommittedLocalDeletionIntent(assetID: String)",
            "public func clearCommittedDeletion(\n        _ intent: CloudPhotoAssetDeletionIntentReceipt) { intent.intentID storedIntent.assetID == canonicalID } public func clearCommittedDeletion(\n        assetID:",
            "CloudPhotoAssetInboundCleanupLease",
            "cleanupLeasesByAssetID",
            "cleanupLeaseWaitersByAssetID",
            "waitForCleanupLeaseRelease",
            "waitForInboundRecordWaiter",
            "inboundRecordWaiterIDs",
            "String: [UUID: CheckedContinuation<Void, Error>]",
            "cleanupLeaseWaitersByAssetID[canonicalID]?.isEmpty != false",
            "cleanupLeasesByAssetID[canonicalID] == lease.leaseID",
            "withTaskCancellationHandler",
            "waiterID: UUID",
            "cancelInboundRecordWaiter",
            "removeValue(forKey: waiterID)",
            "continuation.resume(throwing: CancellationError())",
            "try await waitForCleanupLeaseRelease(\n                for: canonicalID,\n                waiterID: waiterID\n            )\n            try Task.checkCancellation()",
            "waiter.resume(returning: ())",
            "accountAssetIDs",
            "unresolvedAssetIDs",
            "quarantinedIntents",
            "accountIdentityHint",
            "lastVerifiedAccountIdentity",
            "quarantineIdentityHint",
            "static let currentSchemaVersion = 3",
            "state.intents[index].quarantineIdentityHint == accountIdentity",
            "forAccountIdentity accountIdentity: String",
            "unresolvedDeletionAssetIDs",
            "JSONDecoder().decode([String].self",
            "if let activeAccountIdentity {",
            "accountIdentity: activeAccountIdentity",
            "public actor DirectCloudPhotoAssetInboundApplier",
            "activeInboundApplyLeases",
            "activeInboundApplyLeases[lease.leaseID] = lease",
            "guard activeInboundApplyLeases[lease.leaseID] == lease else",
            "activeInboundApplyLeases.removeValue(forKey: lease.leaseID)",
            "public func prepareInboundApply(",
            "public func commitInboundApply(",
            "public func cancelInboundApply(",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/CloudKitPrivatePhotoAssetDatabase.swift": "\n".join(
        [
            "@preconcurrency import CloudKit",
            "public actor CloudKitPrivatePhotoAssetDatabase",
            "privateCloudDatabase",
            "CKRecordZone",
            "CKAsset(fileURL:",
            "recordZoneChanges(",
            "CKServerChangeToken",
            "requiringSecureCoding: true",
            "retryAfterSeconds",
            "downloadStore.stageDownload(",
            "accountIdentityProvider.accountIdentity()",
            "let owned = try withExtendedLifetime(record) {",
            "lifetimeOwner: asset",
            "record.hasUsableBinaryAsset else { return nil }",
            "CloudPhotoAssetSystemRecord(",
            "CloudKitPhotoAssetRecordMapper.systemRecord(from: record)",
            "enum CloudKitPhotoAssetRecordMapper",
            "static func systemRecord(",
            "from record: CKRecord",
            "private static func hasUsableBinaryAsset(in record: CKRecord) -> Bool",
            'record["asset"] as? CKAsset',
            "fileURL.isFileURL",
            "resourceValues.isRegularFile == true",
            "resourceValues.isReadable == true",
            "CloudKitPhotoAssetRecordModifying",
            "CloudKitPhotoAssetRecordModifyResults",
            "CloudKitPhotoAssetRecordSaver",
            "recordModifier.modifyRecords(",
            "savePolicy: .changedKeys",
            "atomically: true",
            "saveResults[record.recordID]",
            "deleteResults.isEmpty",
            "try recordResult.get()",
            "CloudKitPhotoAssetRecordMapper.uploadRecord(",
            "database.modifyRecords(",
            "withExtendedLifetime(record)",
            "defer { withExtendedLifetime(record) {} }",
            'record["assetID"]',
            'record["asset"]',
            'record["checksum"]',
            'record["byteCount"]',
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoGalleryViewModel.swift": " ".join(
        [
            "ProgressPhotoGalleryViewModel",
            "ProgressPhotoGalleryAssetState",
            "case available(Data)",
            "case unloaded",
            "case loading",
            "case missing",
            "case corrupt",
            "case unavailable",
            "ProgressPhotoGalleryOrdering.newestDateThenPose",
            "ProgressPhotoGalleryOrdering.chronological",
            "selectedPhotoIDs.count == 2",
            "selectedPhotoIDs.removeFirst()",
            "replacedOldest(removedID:",
            "selectedPhotoIDs.removeAll",
            "generation == loadGeneration",
            "public func load() async {",
            "public func loadThumbnail",
            "thumbnailCacheLimit",
            "thumbnailLoadID",
            "comparisonLoadGeneration",
            "ProgressPhotoComparisonLoadID",
            "advancesLoadID: true",
            "loadThumbnail(id:",
            "loadComparisonImages()",
            "retryUnavailableAssets()",
            "repository.fullImage(",
            "comparisonAssetStates",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoGalleryView.swift": " ".join(
        [
            "ProgressPhotoGalleryView",
            "GridItem(.adaptive(minimum: 160)",
            "PhotoThumbnailView",
            "photos.gallery.content",
            "photos.gallery.missing",
            "photos.gallery.corrupt",
            "photos.gallery.unavailable",
            "photos.gallery.select.",
            "photos.gallery.selected.",
            ".task(id: item.thumbnailLoadID)",
            "actionAccessibilityLabel",
            "accessibilityAnnouncer.announce(",
            "ViewThatFits(in: .horizontal)",
            "photos.compare.content",
            "photos.compare.before",
            "photos.compare.after",
            "photos.compare.replaced",
            "photos.gallery.loading",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/PhotoThumbnailView.swift": " ".join(
        [
            "import UIKit",
            "UIImage(data: data)",
            ".scaledToFit()",
            ".accessibilityHidden(true)",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/ProgressPhotoAccessibilityAnnouncer.swift": " ".join(
        [
            "import UIKit",
            "ProgressPhotoAccessibilityAnnouncing",
            "UIAccessibility.post(notification: .announcement",
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
            "public func fullImage(assetID:",
            "variant: .full",
            "deletionIntentStore",
            "recordCommittedDeletion",
            "clearCommittedDeletion",
            "let deletionIntent: CloudPhotoAssetDeletionIntentReceipt",
            "clearCommittedDeletion(deletionIntent)",
            "clearCommittedDeletion(deletionIntent)",
            "inboundAssetJournal",
            "pendingInboundAssetIDs",
            "CloudPhotoAssetInboundApplying",
            "inboundAssetStore",
            "activeInboundApplyLease",
            "public func prepareInboundApply(",
            "await acquireExclusiveOperation()",
            "hasCommittedLocalDeletionIntent(assetID: assetID)",
            "releaseExclusiveOperation()",
            "releaseExclusiveOperation()",
            "return .discardedCommittedDeletion",
            "activeInboundApplyLease = lease",
            "return .prepared(lease)",
            "public func commitInboundApply(",
            "guard activeInboundApplyLease == lease else",
            "defer { releaseInboundApplyLease(lease) }",
            "inboundAssetJournal.recordInboundAssetID(lease.assetID)",
            "try Task.checkCancellation()",
            "inboundAssetStore.restoreCloudAsset(id: lease.assetID, bytes: bytes)",
            "public func cancelInboundApply(",
            "guard activeInboundApplyLease == lease else { return }",
            "releaseInboundApplyLease(lease)",
            "private func releaseInboundApplyLease(",
            "guard activeInboundApplyLease == lease else { return }",
            "activeInboundApplyLease = nil",
            "public func fetchPhotos()",
            "deleteAssetIfNotInbound",
            "deleteAssetIfNotInbound(assetID)",
            "deleteAssetIfNotInbound(assetID)",
            "acquireCleanupLease(for: assetID)",
            "releaseCleanupLease(lease)",
            "releaseCleanupLease(lease)",
            "public func snapshot() async throws -> CloudPhotoAssetReferenceSnapshot {",
            "reconcileAssetStorageIfNeeded(rows: rows)",
            "public func deletePhoto",
            "public func retryPendingAssetCleanup() async throws {",
            "let freshPendingInboundAssetIDs = try await loadPendingInboundAssetIDsFailClosed()",
            "freshPendingInboundAssetIDs.contains(assetID)",
            "private func reconcileAssetStorageIfNeeded",
            "let pendingInboundAssetIDs = try await loadPendingInboundAssetIDsFailClosed()",
            "guard !hasReconciledAssetStorage else { return }",
            "let freshPendingInboundAssetIDs = try await loadPendingInboundAssetIDsFailClosed()",
            "freshPendingInboundAssetIDs.contains(assetID)",
            "private func loadPendingInboundAssetIDsFailClosed",
            "pendingInboundAssetIDs()",
            "private func recordPendingCleanup",
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
            "photos.gallery.title",
            "photos.gallery.instructions",
            "photos.gallery.loading",
            "photos.gallery.select",
            "photos.gallery.deselect",
            "photos.gallery.selected",
            "photos.gallery.missing",
            "photos.gallery.corrupt",
            "photos.gallery.unavailable",
            "photos.compare.title",
            "photos.compare.before",
            "photos.compare.after",
            "photos.compare.replaced",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/CoreModels/Models/ProgressPhoto.swift": (
        "ProgressPhoto imageRef String pose note"
    ),
    "App/Application/AppDependencies.swift": """
        trackerFeatureBundleFactory
        private lazy var trackerFeatureRouter
        makeTrackerFeatureRouter
        TrackerFeatureRouting
        Result<AppDependencies, Error>
        prepareInitialContentForLaunch
        SynchronousTodaySnapshotRepository
        todayViewModel.state == .loading
        symptomSafetyPresentationProvider: { context in TrainingSymptomSafetyMapper.presentation(for: context) }
        case .ohpSafety:
            trainingRepository = UITestFoundationRepository(
                repository: repository,
                failsFirstCurrentOHPSymptomWrite: true,
                failsFirstSessionDeletion: true
            )
        private var failsNextCurrentOHPSymptomWrite
        private var failsNextSessionDeletion
        private var currentSessionID: UUID?
        failsNextSessionDeletion = failsFirstSessionDeletion
        currentSessionID = session?.id
        response == .symptomsPresent
        id == currentSessionID
        UITestFoundationRepositoryError.ohpSymptomWrite
        if failsNextSessionDeletion, id == currentSessionID
        UITestFoundationRepositoryError.sessionDeletion
        func updateWorkoutSessionOHPSymptomResponse() async throws {
            return try await repository.updateWorkoutSessionOHPSymptomResponse(
                id: id,
                response: response,
                at: date
            )
        }
        switch launchConfiguration.scenario {
        case .m3BodyMetrics, .m3SleepMood, .m3Posture, .m3HealthChecks,
             .m3Bloodwork, .m3ProgressPhotos, .m3PhotoGallery:
            trainingRepository = repository
            shouldLoadFoundation = true
        }
        } else {
        static func install(scenario: AppUITestScenario, in modelContext: ModelContext) throws {
            switch scenario {
            case .seeded, .m3BodyMetrics, .m3SleepMood, .m3Bloodwork,
                 .m3ProgressPhotos, .m3PhotoGallery:
                return
            }
        }
        medicalSafetyAcknowledgementController = MedicalSafetyAcknowledgementController(
            store: SwiftDataMedicalSafetyAcknowledgementStore(modelContext: mainContext)
        )
        #if DEBUG
        if environment == .uiTesting,
           let launchConfiguration = AppUITestLaunchConfiguration.resolve(),
           !launchConfiguration.exposesMedicalSafetyFirstUseEvidence {
            _ = medicalSafetyAcknowledgementController.acknowledge()
        }
        #endif
    """,
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
    "App/Application/AppRootView.swift": "\n".join(
        [
            "let medicalSafetyAcknowledgementController: MedicalSafetyAcknowledgementController?",
            "init(",
            "medicalSafetyAcknowledgementController: MedicalSafetyAcknowledgementController? = nil",
            "self.medicalSafetyAcknowledgementController = medicalSafetyAcknowledgementController",
            "Button { controller.acknowledge() } label: {",
            'Text(String(localized: "medical.explanation.l0.acknowledge"))',
            ".frame(maxWidth: .infinity, minHeight: 52)",
            ".contentShape(Rectangle())",
            "}",
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
    "App/Application/AppBootstrapView.swift": (
        "AppRootView( medicalSafetyAcknowledgementController: "
        "dependencies.medicalSafetyAcknowledgementController"
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
            'static let medicalSafetyFirstUseEvidenceFlag = "-ui-test-medical-safety-first-use-evidence"',
            "let exposesMedicalSafetyFirstUseEvidence: Bool",
            "arguments.filter({ $0 == medicalSafetyFirstUseEvidenceFlag }).count <= 1",
            "exposesMedicalSafetyFirstUseEvidence: arguments.contains(medicalSafetyFirstUseEvidenceFlag)",
            'case m3BodyMetrics = "m3-body-metrics"',
            'case m3SleepMood = "m3-sleep-mood"',
            'case m3Posture = "m3-posture"',
            'case m3HealthChecks = "m3-health-checks"',
            'case m3Bloodwork = "m3-bloodwork"',
            'case m3ProgressPhotos = "m3-progress-photos"',
            'case m3PhotoGallery = "m3-photo-gallery"',
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

    launch_configuration = root / "App/Support/AppUITestLaunchConfiguration.swift"
    original_launch_configuration = launch_configuration.read_text(encoding="utf-8")
    launch_configuration.write_text(
        original_launch_configuration.replace(
            "arguments.filter({ $0 == medicalSafetyFirstUseEvidenceFlag }).count <= 1",
            "arguments.contains(medicalSafetyFirstUseEvidenceFlag)",
        ),
        encoding="utf-8",
    )
    run(root, "M3.10 UI-test medical-safety first-use evidence configuration is incomplete")
    launch_configuration.write_text(original_launch_configuration, encoding="utf-8")

    launch_configuration.write_text(
        original_launch_configuration.replace(
            "exposesMedicalSafetyFirstUseEvidence: arguments.contains(medicalSafetyFirstUseEvidenceFlag)",
            "exposesMedicalSafetyFirstUseEvidence: false",
        ),
        encoding="utf-8",
    )
    run(root, "M3.10 UI-test medical-safety first-use evidence configuration is incomplete")
    launch_configuration.write_text(original_launch_configuration, encoding="utf-8")

    dependencies_first_use = root / "App/Application/AppDependencies.swift"
    original_dependencies_first_use = dependencies_first_use.read_text(encoding="utf-8")
    dependencies_first_use.write_text(
        original_dependencies_first_use.replace("#if DEBUG", "#if RELEASE", 1),
        encoding="utf-8",
    )
    run(root, "must acknowledge L0 only inside DEBUG")
    dependencies_first_use.write_text(original_dependencies_first_use, encoding="utf-8")

    dependencies_first_use.write_text(
        original_dependencies_first_use.replace(
            "!launchConfiguration.exposesMedicalSafetyFirstUseEvidence",
            "launchConfiguration.exposesMedicalSafetyFirstUseEvidence",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "explicit medical-safety evidence launch remains unacknowledged")
    dependencies_first_use.write_text(original_dependencies_first_use, encoding="utf-8")

    today_composition_test = root / "HealthTrackingAppTests/TodayCompositionTests.swift"
    original_today_composition_test = today_composition_test.read_text(encoding="utf-8")
    today_composition_test.write_text(
        original_today_composition_test.replace(
            "testMedicalSafetyFirstUseEvidenceRequiresOneExplicitUITestFlag",
            "medicalSafetyEvidenceCoverageWasRemoved",
        ),
        encoding="utf-8",
    )
    run(root, "testMedicalSafetyFirstUseEvidenceRequiresOneExplicitUITestFlag")
    today_composition_test.write_text(original_today_composition_test, encoding="utf-8")

    today_composition_test.write_text(
        original_today_composition_test.replace(
            "testAppRootExplicitInitializerSupportsComposedAndDefaultMedicalSafetyController",
            "explicitRootInitializerCoverageWasRemoved",
        ),
        encoding="utf-8",
    )
    run(root, "testAppRootExplicitInitializerSupportsComposedAndDefaultMedicalSafetyController")
    today_composition_test.write_text(original_today_composition_test, encoding="utf-8")

    training_accessibility_test = (
        root / "HealthTrackingAppUITests/TrainingAccessibilityUITests.swift"
    )
    original_training_accessibility_test = training_accessibility_test.read_text(
        encoding="utf-8"
    )
    training_accessibility_test.write_text(
        original_training_accessibility_test.replace(
            "-ui-test-medical-safety-first-use-evidence",
            "-ui-test-medical-safety-evidence-was-removed",
        ),
        encoding="utf-8",
    )
    run(root, "-ui-test-medical-safety-first-use-evidence")
    training_accessibility_test.write_text(
        original_training_accessibility_test,
        encoding="utf-8",
    )

    ohp_gate_test = (
        root / "Packages/HealthTrackingModules/Tests/GuidanceKitTests/OHPSafetyGateTests.swift"
    )
    original_ohp_gate_test = ohp_gate_test.read_text(encoding="utf-8")
    ohp_gate_test.write_text(
        original_ohp_gate_test.replace(
            "XCTAssertEqual(decision.safetyStop, expectation.safetyStop)",
            "XCTAssertNil(decision.safetyStop)",
        ),
        encoding="utf-8",
    )
    run(root, "XCTAssertEqual(decision.safetyStop, expectation.safetyStop)")
    ohp_gate_test.write_text(original_ohp_gate_test, encoding="utf-8")

    session_review_test = (
        root / "Packages/HealthTrackingModules/Tests/TrainingKitTests/SessionViewModelTests.swift"
    )
    original_session_review_test = session_review_test.read_text(encoding="utf-8")
    session_review_test.write_text(
        original_session_review_test
        + "\nfunc invalidM310Autoclosure() async {\n"
        + "XCTAssertEqual(await loadPendingWrite(), .idle)\n"
        + "}\n",
        encoding="utf-8",
    )
    run(root, "M3.10 XCTest autoclosures must evaluate async values first")
    session_review_test.write_text(original_session_review_test, encoding="utf-8")
    for removed in (
        "testStoredPriorSymptomsAndUncertaintyStopOHPAtTheSafeAlternative",
        "testAnsweringPriorSymptomsOrUncertaintyStopsOHPAtTheSafeAlternative",
        "testCurrentOHPSymptomStopsBeforeTheRepositoryWriteCompletes",
        "A pending exact write must reject a second write or retry.",
        "testCurrentOHPSymptomWriteFailureRetainsStopAndRetriesTheExactRequestOnce",
        "Pending current-symptom persistence must block exercise progress and completion.",
        "A failed pending write must keep route actions fail closed until exact retry succeeds.",
        "repository.deletedSessionIDs.count",
        "[request.repositoryUpdate, request.repositoryUpdate]",
        "XCTAssertEqual(symptomClient.events, [expectedEvent])",
        "testAdvanceRouteFirstRejectsSymptomAndDuplicateRoutesUntilChosenProgressCompletes",
        "testGoBackRouteFirstRejectsSymptomUntilChosenProgressCompletes",
        "testFinishRouteFirstKeepsTheLockThroughProgressAndTransition",
        "testRouteLockClearsAfterAppliedProgressFailureWithoutAcceptingSymptom",
        "waitUntilProgressUpdateIsSuspended",
        "waitUntilTransitionIsSuspended",
        "XCTAssertTrue(viewModel.isSessionRouteMutationInFlight)",
        "XCTAssertTrue(repository.ohpSymptomUpdates.isEmpty)",
        "XCTAssertEqual(repository.progressUpdates.count, progressCount + 1)",
        "testDeletionFailurePreservesStoppedSymptomRetryAndExactRequest",
        "testSuccessfulDeletionIsTheOnlyDeletionPathThatDiscardsPendingSymptomRetry",
        "testDeleteFirstLeaseRejectsSymptomRoutesAndDuplicateDeleteUntilSuccess",
        "testSuspendedDeletionFailureRetainsStoppedExactRetryUntilLeaseReleases",
        "testRouteFirstLeaseRejectsDeletionRequestAndConfirmationBeforeRepositoryAwait",
        "testCancelledDeletionReleasesLeaseAndPreservesExactStoppedRetry",
        "waitUntilDeletionIsSuspended",
        "repository.suspendNextDeletion()",
        "repository.resumeSuspendedDeletion()",
        "deletion.cancel()",
        "try Task.checkCancellation()",
        "deleteAttempts.append(id)",
        "XCTAssertTrue(viewModel.isSessionDeletionInFlight)",
        "XCTAssertEqual(repository.deleteAttempts, [sessionID])",
        "XCTAssertTrue(viewModel.hasSessionDeletionFailure)",
        "XCTAssertEqual(viewModel.state, stoppedState)",
        "XCTAssertTrue(repository.deletedSessionIDs.isEmpty)",
        "XCTAssertEqual(repository.deletedSessionIDs, [sessionID])",
        "testOrdinaryDeletionFailureRetainsTheExistingRecoverableFailureRoute",
        "XCTAssertEqual(viewModel.state, .failed(.deletion))",
        "testStartTailOwnsSessionUntilInitialProgressFinishesAndDeleteFirstRejectsRestart",
        "testRestoredStartKeepsItsOwnerThroughTheActiveSymptomJournalTail",
        "testWarmupAndCooldownChecklistOwnersBlockDeletionUntilProgressReturns",
        "testPriorResponseAndDeloadOwnersBlockDeletionThroughRepositoryStateWrites",
        "testSetSaveAndExactRetryEachOwnTheirWholeRepositoryLifetime",
        "testSummarySaveOwnerBlocksDeletionUntilItsDismissalCommits",
        "testOverlappingOwnersReleaseOnlyTheirExactTokenBeforeDeletionBecomesAvailable",
        "testCancelledSessionMutationReleasesOnlyItsOwnerAndAllowsDeletion",
        "testJournalRetryMayFinishAfterDeletionWithoutRepublishingSessionState",
        "XCTAssertEqual(viewModel.activeSessionMutationCount, 2)",
        '"The first completion must remove only its exact owner token."',
        '"Metrics-only journal retry must not own the session deletion boundary."',
        "assertDeletionRejectedWhileSessionMutationOwned",
        "suspendNextDeloadUpdate",
        "suspendNextSetSave",
        "suspendNextSummaryUpdate",
        "suspendNextRecord",
        "OneShotSuspensionGate",
    ):
        session_review_test.write_text(
            original_session_review_test.replace(removed, "coverageWasRemoved"),
            encoding="utf-8",
        )
        run(root, removed)
        session_review_test.write_text(original_session_review_test, encoding="utf-8")

    ohp_ui_review_test = root / "HealthTrackingAppUITests/OHPSafetyFlowUITests.swift"
    original_ohp_ui_review_test = ohp_ui_review_test.read_text(encoding="utf-8")
    ohp_ui_review_test.write_text(
        original_ohp_ui_review_test.replace(
            "app.buttons.matching(identifier: identifier).firstMatch",
            "app.descendants(matching: .any)[identifier]",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "exact button-scoped query in all three pending/deletion/retry loops")
    ohp_ui_review_test.write_text(original_ohp_ui_review_test, encoding="utf-8")

    for removed in (
        "testAnsweredPriorSymptomsAndUncertaintyRenderTheShippedStoppedRoute",
        "A stored prior response must not reopen the unanswered question.",
        "must restore the stopped route.",
        "session.ohp.persistence.error",
        "session.ohp.persistence.retry",
        "persistenceRetry.frame.height + 0.01",
        "Pending OHP persistence must disable the route control:",
        "Successful exact retry must re-enable the route control:",
        "session.delete.confirm.action",
        "session.delete.error",
        "A failed deletion must stay on the stopped route and expose a separate error.",
        "A failed deletion must not replace the current OHP safety stop.",
        "A failed deletion must preserve the exact symptom persistence retry.",
        "Deletion failure must keep the pending route control disabled:",
    ):
        ohp_ui_review_test.write_text(
            original_ohp_ui_review_test.replace(removed, "coverageWasRemoved"),
            encoding="utf-8",
        )
        run(root, removed)
        ohp_ui_review_test.write_text(original_ohp_ui_review_test, encoding="utf-8")

    ohp_ui_review_test.write_text(
        original_ohp_ui_review_test.replace(
            "XCTAssertGreaterThanOrEqual(persistenceRetry.frame.height + 0.01, 52,",
            "XCTAssertGreaterThanOrEqual(persistenceRetry.frame.height + 0.01, 44,",
        ),
        encoding="utf-8",
    )
    run(root, "shipped OHP persistence retry UI test must measure a real 52-point target")
    ohp_ui_review_test.write_text(original_ohp_ui_review_test, encoding="utf-8")

    medical_ui_review_test = root / "HealthTrackingAppUITests/MedicalSafetyFlowUITests.swift"
    original_medical_ui_review_test = medical_ui_review_test.read_text(encoding="utf-8")
    medical_ui_review_test.write_text(
        original_medical_ui_review_test.replace(
            "-ui-test-medical-safety-first-use-evidence",
            "-ui-test-medical-safety-evidence-was-removed",
        ),
        encoding="utf-8",
    )
    run(root, "-ui-test-medical-safety-first-use-evidence")
    medical_ui_review_test.write_text(original_medical_ui_review_test, encoding="utf-8")

    medical_ui_review_test.write_text(
        original_medical_ui_review_test.replace(
            "XCTAssertGreaterThanOrEqual(acknowledgement.frame.height + 0.01, 52,",
            "XCTAssertGreaterThanOrEqual(acknowledgement.frame.height + 0.01, 44,",
        ),
        encoding="utf-8",
    )
    run(root, "shipped L0 acknowledgement UI test must measure a real 52-point target")
    medical_ui_review_test.write_text(original_medical_ui_review_test, encoding="utf-8")

    app_root_review = root / "App/Application/AppRootView.swift"
    original_app_root_review = app_root_review.read_text(encoding="utf-8")
    app_root_review.write_text(
        original_app_root_review.replace(
            "self.medicalSafetyAcknowledgementController = medicalSafetyAcknowledgementController",
            "let ignoredAcknowledgementController = medicalSafetyAcknowledgementController",
        ),
        encoding="utf-8",
    )
    run(root, "M3.10 AppRootView must expose an explicit immutable initializer")
    app_root_review.write_text(original_app_root_review, encoding="utf-8")

    app_root_review.write_text(
        original_app_root_review.replace(
            ".frame(maxWidth: .infinity, minHeight: 52)\n.contentShape(Rectangle())\n}",
            ".contentShape(Rectangle())\n}\n.frame(minHeight: 52)",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "52-point frame and content shape inside the explicit Button label")
    app_root_review.write_text(original_app_root_review, encoding="utf-8")

    app_bootstrap_review = root / "App/Application/AppBootstrapView.swift"
    original_app_bootstrap_review = app_bootstrap_review.read_text(encoding="utf-8")
    app_bootstrap_review.write_text(
        original_app_bootstrap_review.replace(
            "dependencies.medicalSafetyAcknowledgementController",
            "nil",
        ),
        encoding="utf-8",
    )
    run(root, "must pass the composed acknowledgement controller")
    app_bootstrap_review.write_text(original_app_bootstrap_review, encoding="utf-8")

    ohp_gate_review = (
        root / "Packages/HealthTrackingModules/Sources/GuidanceKit/Safety/OHPSafetyGate.swift"
    )
    original_ohp_gate_review = ohp_gate_review.read_text(encoding="utf-8")
    stop_contract = "safetyStop: SafetyStop(alternative: .halfKneelingDBPress)"
    first_stop = original_ohp_gate_review.find(stop_contract)
    second_stop = original_ohp_gate_review.find(stop_contract, first_stop + 1)
    for stop_index in (first_stop, second_stop):
        mutated = (
            original_ohp_gate_review[:stop_index]
            + "safetyStop: nil"
            + original_ohp_gate_review[stop_index + len(stop_contract):]
        )
        ohp_gate_review.write_text(mutated, encoding="utf-8")
        run(root, "prior OHP symptoms and uncertainty must produce")
        ohp_gate_review.write_text(original_ohp_gate_review, encoding="utf-8")

    session_review_source = (
        root / "Packages/HealthTrackingModules/Sources/TrainingKit/Session/SessionViewModel.swift"
    )
    original_session_review_source = session_review_source.read_text(encoding="utf-8")

    def replace_in_swift_function(
        source: str, name: str, old: str, new: str
    ) -> str:
        declaration = source.index(f"func {name}")
        opening = source.index("{", declaration)
        depth = 0
        closing = -1
        for index in range(opening, len(source)):
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
                if depth == 0:
                    closing = index + 1
                    break
        if closing < 0:
            raise RuntimeError(f"Unclosed fixture function: {name}")
        body = source[declaration:closing]
        if old not in body:
            raise RuntimeError(f"Missing fixture mutation token in {name}: {old}")
        mutated_body = body.replace(old, new, 1)
        return source[:declaration] + mutated_body + source[closing:]

    session_review_source.write_text(
        original_session_review_source.replace(
            "public private(set) var isSessionDeletionInFlight = false",
            "private var deletionLeaseWasRemoved = false",
        ),
        encoding="utf-8",
    )
    run(root, "deletion arbitration requires an observable MainActor deletion lease")
    session_review_source.write_text(original_session_review_source, encoding="utf-8")

    for contract, replacement, expected in (
        (
            "private var sessionMutationOwners: Set<UUID> = []",
            "private var sessionMutationOwners: [UUID] = []",
            "deletion finality requires exact broad session mutation owners",
        ),
        (
            "public var activeSessionMutationCount: Int { sessionMutationOwners.count }",
            "public var activeSessionMutationCount: Int { 0 }",
            "deletion finality requires exact broad session mutation owners",
        ),
        (
            "public var isSessionMutationInFlight: Bool { !sessionMutationOwners.isEmpty }",
            "public var isSessionMutationInFlight: Bool { false }",
            "deletion finality requires exact broad session mutation owners",
        ),
    ):
        session_review_source.write_text(
            original_session_review_source.replace(contract, replacement, 1),
            encoding="utf-8",
        )
        run(root, expected)
        session_review_source.write_text(original_session_review_source, encoding="utf-8")

    for function_name, contract, replacement in (
        (
            "beginSessionMutation",
            "guard !isSessionDeletionInFlight else { return nil }",
            "let deletionWasIgnored = true",
        ),
        (
            "beginSessionMutation",
            "let owner = UUID()",
            "let owner = UUID.zero",
        ),
        (
            "beginSessionMutation",
            "sessionMutationOwners.insert(owner)",
            "let ownerWasNotInserted = owner",
        ),
        (
            "endSessionMutation",
            "sessionMutationOwners.remove(owner)",
            "sessionMutationOwners.removeAll()",
        ),
    ):
        session_review_source.write_text(
            replace_in_swift_function(
                original_session_review_source,
                function_name,
                contract,
                replacement,
            ),
            encoding="utf-8",
        )
        run(root, "broad session mutation owner must be an exact inserted/removed token")
        session_review_source.write_text(original_session_review_source, encoding="utf-8")

    for action_name in (
        "start",
        "toggleWarmupItem",
        "completeWarmup",
        "skipWarmup",
        "answerPreviousOHPSymptom",
        "respondToDeload",
        "reportCurrentOHPSymptom",
        "retryCurrentOHPSymptomWrite",
        "advanceExercise",
        "goBack",
        "toggleCooldownItem",
        "completeCooldown",
        "skipCooldown",
        "finishIncomplete",
        "saveCurrentSet",
        "retrySetSave",
        "saveSummary",
    ):
        expected = (
            "session mutation entry must acquire and defer-release one exact broad "
            f"owner before awaiting: {action_name}"
        )
        for contract, replacement in (
            (
                "guard let sessionMutationOwner = beginSessionMutation() else { return }",
                "let sessionMutationOwner = UUID()",
            ),
            (
                "defer { endSessionMutation(sessionMutationOwner) }",
                "let ownerWasNotReleased = sessionMutationOwner",
            ),
        ):
            session_review_source.write_text(
                replace_in_swift_function(
                    original_session_review_source,
                    action_name,
                    contract,
                    replacement,
                ),
                encoding="utf-8",
            )
            run(root, expected)
            session_review_source.write_text(
                original_session_review_source,
                encoding="utf-8",
            )

    for action_name in (
        "selectRecovery",
        "selectPerformedVariant",
        "stepperChanged",
        "updateSummaryNote",
    ):
        session_review_source.write_text(
            replace_in_swift_function(
                original_session_review_source,
                action_name,
                "guard !isSessionDeletionInFlight else { return }",
                "let deletionWasIgnored = true",
            ),
            encoding="utf-8",
        )
        run(root, "delete-first safety must reject synchronous session mutation: " + action_name)
        session_review_source.write_text(original_session_review_source, encoding="utf-8")

    session_review_source.write_text(
        replace_in_swift_function(
            original_session_review_source,
            "retrySymptomJournal",
            "await recordSymptomEvent(event)",
            "guard let owner = beginSessionMutation() else { return }; defer { endSessionMutation(owner) }; await recordSymptomEvent(event)",
        ),
        encoding="utf-8",
    )
    run(root, "metrics-only symptom journal retry must not own or republish session state")
    session_review_source.write_text(original_session_review_source, encoding="utf-8")

    session_review_source.write_text(
        original_session_review_source.replace(
            "replaceActiveSession(optimistic)",
            "let deferredSnapshot = optimistic",
        ),
        encoding="utf-8",
    )
    run(root, "must publish and retain the exact stopped request before awaiting persistence")
    session_review_source.write_text(original_session_review_source, encoding="utf-8")

    session_review_source.write_text(
        original_session_review_source.replace(
            "guard !isSessionRouteMutationInFlight, !isSessionDeletionInFlight else { return false }",
            "guard !isSessionDeletionInFlight else { return false }",
        ),
        encoding="utf-8",
    )
    run(root, "shipped symptom action availability must close")
    session_review_source.write_text(original_session_review_source, encoding="utf-8")

    session_review_source.write_text(
        original_session_review_source.replace(
            "guard !isSessionRouteMutationInFlight, !isSessionDeletionInFlight else { return false }",
            "guard !isSessionRouteMutationInFlight else { return false }",
        ),
        encoding="utf-8",
    )
    run(root, "shipped symptom action availability must close")
    session_review_source.write_text(original_session_review_source, encoding="utf-8")

    report_guard = (
        "guard !isSessionRouteMutationInFlight, !isSessionDeletionInFlight, "
        "pendingOHPSymptomWriteRequest == nil else { return }"
    )
    for replacement in (
        "guard !isSessionDeletionInFlight, pendingOHPSymptomWriteRequest == nil else { return }",
        "guard !isSessionRouteMutationInFlight, pendingOHPSymptomWriteRequest == nil else { return }",
    ):
        session_review_source.write_text(
            original_session_review_source.replace(report_guard, replacement),
            encoding="utf-8",
        )
        run(root, "current OHP report must reject route-first and delete-first races")
        session_review_source.write_text(original_session_review_source, encoding="utf-8")

    for action_name in ("advanceExercise", "goBack", "finishSession"):
        action_lines = [
            f"func {action_name}() async {{",
            "guard !hasPendingCurrentOHPSymptomWrite, !isSessionRouteMutationInFlight, !isSessionDeletionInFlight else { return }",
        ]
        if action_name != "finishSession":
            action_lines.extend(
                [
                    "guard let sessionMutationOwner = beginSessionMutation() else { return }",
                    "defer { endSessionMutation(sessionMutationOwner) }",
                ]
            )
        action_lines.extend(
            [
                "isSessionRouteMutationInFlight = true",
                "defer { isSessionRouteMutationInFlight = false }",
            ]
        )
        action_prefix = "\n".join(action_lines)
        without_acquire = action_prefix.replace(
            "isSessionRouteMutationInFlight = true",
            "let routeMutationWasNotLocked = true",
        )
        session_review_source.write_text(
            original_session_review_source.replace(action_prefix, without_acquire),
            encoding="utf-8",
        )
        run(root, "route-first safety must acquire and defer-release the lock before awaiting: " + action_name)
        session_review_source.write_text(original_session_review_source, encoding="utf-8")

        session_review_source.write_text(
            original_session_review_source.replace(
                action_prefix,
                action_prefix.replace(", !isSessionDeletionInFlight", ""),
            ),
            encoding="utf-8",
        )
        run(root, "delete-first safety must block normal session route action: " + action_name)
        session_review_source.write_text(original_session_review_source, encoding="utf-8")

        without_release = action_prefix.replace(
            "defer { isSessionRouteMutationInFlight = false }",
            "let routeMutationWasNotReleased = true",
        )
        session_review_source.write_text(
            original_session_review_source.replace(action_prefix, without_release),
            encoding="utf-8",
        )
        run(root, "route-first safety must acquire and defer-release the lock before awaiting: " + action_name)
        session_review_source.write_text(original_session_review_source, encoding="utf-8")

    session_review_source.write_text(
        original_session_review_source.replace(
            "hasSessionDeletionFailure = true",
            "state = .failed(.deletion)",
        ),
        encoding="utf-8",
    )
    run(root, "deletion failure must preserve pending OHP safety without regressing ordinary failure recovery")
    session_review_source.write_text(original_session_review_source, encoding="utf-8")

    session_review_source.write_text(
        original_session_review_source.replace(
            "state = .failed(.deletion)",
            "let ordinaryFailureWasHidden = true",
        ),
        encoding="utf-8",
    )
    run(root, "deletion failure must preserve pending OHP safety without regressing ordinary failure recovery")
    session_review_source.write_text(original_session_review_source, encoding="utf-8")

    confirm_success_prefix = "\n".join(
        [
            "try await repository.deleteWorkoutSession(id: sessionID)",
            "pendingOHPSymptomWriteRequest = nil",
            "ohpSymptomWriteState = .idle",
        ]
    )
    session_review_source.write_text(
        original_session_review_source.replace(
            confirm_success_prefix,
            "try await repository.deleteWorkoutSession(id: sessionID)",
        ),
        encoding="utf-8",
    )
    run(root, "only successful session deletion may discard the exact symptom retry")
    session_review_source.write_text(original_session_review_source, encoding="utf-8")

    session_review_source.write_text(
        original_session_review_source.replace(
            "guard pendingOHPSymptomWriteRequest != nil else { return false }",
            "guard ohpSymptomWriteState != .idle else { return false }",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "pending current OHP write flag must derive fail-closed")
    session_review_source.write_text(original_session_review_source, encoding="utf-8")

    for signature, action_name in (
        ("func advanceExercise() async {", "advanceExercise"),
        ("func goBack() async {", "goBack"),
        ("func finishSession() async {", "finishSession"),
    ):
        session_review_source.write_text(
            original_session_review_source.replace(
                signature
                + "\nguard !hasPendingCurrentOHPSymptomWrite, "
                + "!isSessionRouteMutationInFlight, "
                + "!isSessionDeletionInFlight else { return }",
                signature
                + "\nguard !isSessionRouteMutationInFlight, "
                + "!isSessionDeletionInFlight else { return }",
            ),
            encoding="utf-8",
        )
        run(
            root,
            "pending current OHP write must block normal session route action: "
            + action_name,
        )
        session_review_source.write_text(original_session_review_source, encoding="utf-8")

    session_review_source.write_text(
        original_session_review_source.replace(
            "if case .saving = ohpSymptomWriteState { return true }",
            "if case .failed = ohpSymptomWriteState { return true }",
        ),
        encoding="utf-8",
    )
    run(root, "destructive deletion guard must distinguish the exact saving window")
    session_review_source.write_text(original_session_review_source, encoding="utf-8")

    for signature, action_name in (
        ("func requestDeletion() {", "requestDeletion"),
        ("func confirmDeletion() async {", "confirmDeletion"),
    ):
        deletion_entry_guard = (
            signature
            + "\nguard !isCurrentOHPSymptomWriteSaving, "
            + "!isSessionRouteMutationInFlight, !isSessionMutationInFlight, "
            + "!isSessionDeletionInFlight else { return }"
        )
        session_review_source.write_text(
            original_session_review_source.replace(
                deletion_entry_guard,
                deletion_entry_guard.replace(
                    "!isCurrentOHPSymptomWriteSaving, ", ""
                ),
            ),
            encoding="utf-8",
        )
        run(
            root,
            "saving current OHP write must block destructive deletion race: "
            + action_name,
        )
        session_review_source.write_text(original_session_review_source, encoding="utf-8")

        for removed_lock in (
            "!isSessionRouteMutationInFlight, ",
            "!isSessionMutationInFlight, ",
            "!isSessionDeletionInFlight",
        ):
            session_review_source.write_text(
                original_session_review_source.replace(
                    deletion_entry_guard,
                    deletion_entry_guard.replace(removed_lock, ""),
                ),
                encoding="utf-8",
            )
            run(root, "deletion entry must reject route, broad mutation, and duplicate deletion ownership: " + action_name)
            session_review_source.write_text(original_session_review_source, encoding="utf-8")

    for lease_contract in (
        "isSessionDeletionInFlight = true",
        "defer { isSessionDeletionInFlight = false }",
    ):
        session_review_source.write_text(
            original_session_review_source.replace(
                lease_contract,
                "let deletionLeaseContractWasRemoved = true",
                1,
            ),
            encoding="utf-8",
        )
        run(root, "confirm deletion must acquire and defer-release its lease before the first await")
        session_review_source.write_text(original_session_review_source, encoding="utf-8")

    session_review_source.write_text(
        original_session_review_source.replace(
            "ohpSymptomWriteState = .failed(request: request)",
            "ohpSymptomWriteState = .idle",
        ),
        encoding="utf-8",
    )
    run(root, "write failure must retain the active stopped route")
    session_review_source.write_text(original_session_review_source, encoding="utf-8")

    session_review_source.write_text(
        original_session_review_source.replace(
            "guard !isSessionDeletionInFlight, let request = pendingOHPSymptomWriteRequest else { return }",
            "guard let request = pendingOHPSymptomWriteRequest else { return }",
        ),
        encoding="utf-8",
    )
    run(root, "retry must reject deletion ownership and reuse the exact pending request")
    session_review_source.write_text(original_session_review_source, encoding="utf-8")

    session_review_source.write_text(
        original_session_review_source.replace(
            "func retryCurrentOHPSymptomWrite() async {",
            "func retryCurrentOHPSymptomWrite() async { let replacementTimestamp = now()",
        ),
        encoding="utf-8",
    )
    run(root, "retry must reject deletion ownership and reuse the exact pending request")
    session_review_source.write_text(original_session_review_source, encoding="utf-8")

    exercise_review_source = (
        root / "Packages/HealthTrackingModules/Sources/TrainingKit/Session/ExerciseStageView.swift"
    )
    original_exercise_review_source = exercise_review_source.read_text(encoding="utf-8")
    exercise_review_source.write_text(
        original_exercise_review_source.replace(
            'accessibilityIdentifier("session.ohp.persistence.retry")',
            'accessibilityIdentifier("session.ohp.persistence.dismiss")',
        ),
        encoding="utf-8",
    )
    run(root, "shipped stopped UI must expose current-response write retry")
    exercise_review_source.write_text(original_exercise_review_source, encoding="utf-8")

    exercise_review_source.write_text(
        original_exercise_review_source.replace(
            "if viewModel.canReportCurrentOHPSymptom { }",
            "if true { }",
        ),
        encoding="utf-8",
    )
    run(root, "shipped stopped UI must expose current-response write retry")
    exercise_review_source.write_text(original_exercise_review_source, encoding="utf-8")

    exercise_review_source.write_text(
        original_exercise_review_source.replace(
            'accessibilityIdentifier("session.delete.error")',
            'accessibilityIdentifier("session.delete.hidden-error")',
        ),
        encoding="utf-8",
    )
    run(root, "shipped stopped UI must expose current-response write retry")
    exercise_review_source.write_text(original_exercise_review_source, encoding="utf-8")

    exercise_review_source.write_text(
        original_exercise_review_source.replace(
            ".frame(maxWidth: .infinity, minHeight: 52)\n.contentShape(Rectangle())\n}",
            ".contentShape(Rectangle())\n}\n.frame(minHeight: 52)",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "52-point frame and content shape inside the explicit Button label")
    exercise_review_source.write_text(original_exercise_review_source, encoding="utf-8")

    exercise_review_source.write_text(
        original_exercise_review_source.replace(
            'accessibilityIdentifier("session.ohp.persistence.retry")\n'
            + ".disabled(viewModel.isSessionDeletionInFlight)",
            'accessibilityIdentifier("session.ohp.persistence.retry")',
        ),
        encoding="utf-8",
    )
    run(root, "shipped OHP retry must be disabled while deletion owns the session")
    exercise_review_source.write_text(original_exercise_review_source, encoding="utf-8")

    for identifier in (
        "session.exercise.next",
        "session.exercise.back",
        "session.exercise.finish-incomplete",
    ):
        identifier_contract = f'accessibilityIdentifier("{identifier}")'
        exercise_review_source.write_text(
            original_exercise_review_source.replace(
                identifier_contract
                + "\n.disabled(viewModel.hasPendingCurrentOHPSymptomWrite || "
                + "viewModel.isSessionDeletionInFlight)",
                identifier_contract,
            ),
            encoding="utf-8",
        )
        run(root, "shipped exercise route controls must remain disabled")
        exercise_review_source.write_text(original_exercise_review_source, encoding="utf-8")

        exercise_review_source.write_text(
            original_exercise_review_source.replace(
                identifier_contract
                + "\n.disabled(viewModel.hasPendingCurrentOHPSymptomWrite || "
                + "viewModel.isSessionDeletionInFlight)",
                identifier_contract
                + "\n.disabled(viewModel.hasPendingCurrentOHPSymptomWrite)",
            ),
            encoding="utf-8",
        )
        run(root, "shipped exercise route controls must remain disabled")
        exercise_review_source.write_text(original_exercise_review_source, encoding="utf-8")

    training_session_review_source = root / (
        "Packages/HealthTrackingModules/Sources/TrainingKit/Session/TrainingSessionView.swift"
    )
    original_training_session_review_source = training_session_review_source.read_text(
        encoding="utf-8"
    )
    for lock_contract in (
        ".disabled(viewModel.hasPendingCurrentOHPSymptomWrite || viewModel.isSessionMutationInFlight || viewModel.isSessionDeletionInFlight)",
        ".disabled(viewModel.isCurrentOHPSymptomWriteSaving || viewModel.isSessionRouteMutationInFlight || viewModel.isSessionMutationInFlight || viewModel.isSessionDeletionInFlight)",
        ".disabled(viewModel.isSessionRouteMutationInFlight || viewModel.isSessionMutationInFlight || viewModel.isSessionDeletionInFlight)",
    ):
        training_session_review_source.write_text(
            original_training_session_review_source.replace(
                lock_contract,
                ".disabled(false)",
                1,
            ),
            encoding="utf-8",
        )
        run(root, "shipped session toolbar must preserve the pending write")
        training_session_review_source.write_text(
            original_training_session_review_source,
            encoding="utf-8",
        )

    for lock_contract, weakened_contract in (
        (
            ".disabled(viewModel.hasPendingCurrentOHPSymptomWrite || viewModel.isSessionMutationInFlight || viewModel.isSessionDeletionInFlight)",
            ".disabled(viewModel.hasPendingCurrentOHPSymptomWrite || viewModel.isSessionDeletionInFlight)",
        ),
        (
            ".disabled(viewModel.isCurrentOHPSymptomWriteSaving || viewModel.isSessionRouteMutationInFlight || viewModel.isSessionMutationInFlight || viewModel.isSessionDeletionInFlight)",
            ".disabled(viewModel.isCurrentOHPSymptomWriteSaving || viewModel.isSessionRouteMutationInFlight || viewModel.isSessionDeletionInFlight)",
        ),
        (
            ".disabled(viewModel.isSessionRouteMutationInFlight || viewModel.isSessionMutationInFlight || viewModel.isSessionDeletionInFlight)",
            ".disabled(viewModel.isSessionRouteMutationInFlight || viewModel.isSessionDeletionInFlight)",
        ),
    ):
        training_session_review_source.write_text(
            original_training_session_review_source.replace(
                lock_contract, weakened_contract, 1
            ),
            encoding="utf-8",
        )
        run(root, "shipped session toolbar must preserve the pending write")
        training_session_review_source.write_text(
            original_training_session_review_source,
            encoding="utf-8",
        )

    training_session_review_source.write_text(
        original_training_session_review_source.replace(
            ".disabled(viewModel.isSessionDeletionInFlight)",
            ".disabled(false)",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "shipped active session content must be disabled for the full deletion lease")
    training_session_review_source.write_text(
        original_training_session_review_source,
        encoding="utf-8",
    )

    training_session_review_source.write_text(
        original_training_session_review_source.replace(
            'accessibilityIdentifier("session.delete.confirm.action")',
            'accessibilityIdentifier("session.delete.confirm.hidden")',
        ),
        encoding="utf-8",
    )
    run(root, "shipped deletion failure regression requires an addressable confirm action")
    training_session_review_source.write_text(
        original_training_session_review_source,
        encoding="utf-8",
    )

    dependencies_review_source = root / "App/Application/AppDependencies.swift"
    original_dependencies_review_source = dependencies_review_source.read_text(
        encoding="utf-8"
    )
    dependencies_review_source.write_text(
        original_dependencies_review_source.replace(
            "failsFirstCurrentOHPSymptomWrite: true",
            "failsFirstCurrentOHPSymptomWrite: false",
        ),
        encoding="utf-8",
    )
    run(root, "OHP UI fixture must fail the first current-response write")
    dependencies_review_source.write_text(
        original_dependencies_review_source,
        encoding="utf-8",
    )

    dependencies_review_source.write_text(
        original_dependencies_review_source.replace(
            "failsFirstSessionDeletion: true",
            "failsFirstSessionDeletion: false",
        ),
        encoding="utf-8",
    )
    run(root, "OHP UI fixture must fail the first current-response write")
    dependencies_review_source.write_text(
        original_dependencies_review_source,
        encoding="utf-8",
    )

    dependencies_review_source.write_text(
        original_dependencies_review_source.replace(
            "if failsNextSessionDeletion, id == currentSessionID",
            "if false, id == currentSessionID",
        ),
        encoding="utf-8",
    )
    run(root, "OHP UI fixture must fail the first current-response write")
    dependencies_review_source.write_text(
        original_dependencies_review_source,
        encoding="utf-8",
    )
    dependencies_review_source.write_text(
        original_dependencies_review_source.replace(
            "return try await repository.updateWorkoutSessionOHPSymptomResponse(",
            "try await repository.updateWorkoutSessionOHPSymptomResponse(",
        ),
        encoding="utf-8",
    )
    run(root, "DEBUG OHP UI repository must return its delegated snapshot")
    dependencies_review_source.write_text(
        original_dependencies_review_source,
        encoding="utf-8",
    )
    dependencies_review_source.write_text(
        original_dependencies_review_source.replace(
            "id == currentSessionID",
            "id != currentSessionID",
        ),
        encoding="utf-8",
    )
    run(root, "OHP UI fixture must fail the first current-response write")
    dependencies_review_source.write_text(
        original_dependencies_review_source,
        encoding="utf-8",
    )

    autoclosure_repository_tests = root / (
        "Packages/HealthTrackingModules/Tests/PersistenceKitTests/"
        "ProgressPhotoRepositoryTests.swift"
    )
    original_autoclosure_repository_tests = autoclosure_repository_tests.read_text(
        encoding="utf-8"
    )
    autoclosure_repository_tests.write_text(
        original_autoclosure_repository_tests
        + "\nfunc invalidAsyncAutoclosure() async throws {\n"
        + "    _ = try XCTUnwrap(\n"
        + "        try await inboundJournal.acquireCleanupLease(for: assetID)\n"
        + "    )\n"
        + "}\n",
        encoding="utf-8",
    )
    run(root, "M3.9 XCTest autoclosures must evaluate async values first")
    autoclosure_repository_tests.write_text(
        original_autoclosure_repository_tests,
        encoding="utf-8",
    )

    cloud_domain = root / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/CloudPhotoAssetDomain.swift"
    original_cloud_domain = cloud_domain.read_text(encoding="utf-8")
    cloud_domain.write_text(
        original_cloud_domain.replace('"byteCount"', '"pose"', 1),
        encoding="utf-8",
    )
    run(root, "CKAsset record field allowlist changed")
    cloud_domain.write_text(original_cloud_domain, encoding="utf-8")

    cloud_adapter = root / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/CloudKitPrivatePhotoAssetDatabase.swift"
    original_cloud_adapter = cloud_adapter.read_text(encoding="utf-8")
    cloud_adapter.write_text(
        original_cloud_adapter.replace('record["byteCount"]', 'record["note"]', 1),
        encoding="utf-8",
    )
    run(root, "CloudKit adapter persisted an unexpected field")
    cloud_adapter.write_text(original_cloud_adapter, encoding="utf-8")

    cloud_contract_tests = root / "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/CloudPhotoAssetContractTests.swift"
    original_cloud_contract_tests = cloud_contract_tests.read_text(encoding="utf-8")
    cloud_contract_tests.write_text(
        original_cloud_contract_tests.replace(
            "testAdapterStagesDownloadIntoOwnedStorageBeforeSystemSourceDisappears",
            "ownedDownloadRegressionRemoved",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "testAdapterStagesDownloadIntoOwnedStorageBeforeSystemSourceDisappears")
    cloud_contract_tests.write_text(original_cloud_contract_tests, encoding="utf-8")

    cloud_contract_tests.write_text(
        original_cloud_contract_tests.replace(
            "testRealBoundedStagerLimitsReadRequestsAndNeverWritesMaximumPlusOneByte",
            "realBoundedStagerRegressionRemoved",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "testRealBoundedStagerLimitsReadRequestsAndNeverWritesMaximumPlusOneByte")
    cloud_contract_tests.write_text(original_cloud_contract_tests, encoding="utf-8")

    for close_regression in (
        "testDownloadStagingDeletesOutputAndClosesReaderWhenWriterCloseFails",
        "XCTAssertEqual(snapshot.closeCallCount, 2)",
    ):
        cloud_contract_tests.write_text(
            original_cloud_contract_tests.replace(
                close_regression,
                "writerCloseRegressionRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, close_regression)
        cloud_contract_tests.write_text(
            original_cloud_contract_tests,
            encoding="utf-8",
        )

    for ownership_evidence in (
        "CocoaError.Code.fileReadNoPermission.rawValue",
        "nestedUnrelated",
        "unrelatedAsset",
        "symlinkTarget",
    ):
        cloud_contract_tests.write_text(
            original_cloud_contract_tests.replace(
                ownership_evidence,
                "ownershipEvidenceRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, ownership_evidence)
        cloud_contract_tests.write_text(
            original_cloud_contract_tests,
            encoding="utf-8",
        )

    for scoped_intent_regression in (
        "testDeletionIntentStoreSerializesAccountTransitionAndPersistsEveryScope",
        "testLegacyDeletionIntentSetMovesToQuarantineWithoutAuthorizingCurrentAccount",
        "testDeletionIntentStoreRecreationPromotesOnlyMatchingVerifiedAccountHint",
        "testExactIntentReceiptSurvivesPromotionAndDoesNotClearSameAssetABA",
        "testStaleAccountResolutionCannotAuthorizeAfterNewerEpochBegins",
        "testDeletionIntentStoreMigratesV1AndRejectsUnknownSchemaFailClosed",
        "receipt1.intentID",
        "receipt2.intentID",
        "pendingAfterFirstClear",
        "staleResolution",
        "newerResolution",
        "catch is CancellationError",
        "quarantineUnderB",
        "A consumed resolution epoch must never authorize a second account.",
        "receiptAfterResolutionReuse.accountIdentity",
        "quarantineIdentityHint",
        "lastVerifiedAccountIdentity",
        "quarantinedIntents",
        "unresolvedDeletionAssetIDs",
        "forAccountIdentity:",
    ):
        cloud_contract_tests.write_text(
            original_cloud_contract_tests.replace(
                scoped_intent_regression,
                "scopedIntentRegressionRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, scoped_intent_regression)
        cloud_contract_tests.write_text(
            original_cloud_contract_tests,
            encoding="utf-8",
        )

    cloud_coordinator_tests = root / "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/CloudPhotoAssetCoordinatorTests.swift"
    original_cloud_coordinator_tests = cloud_coordinator_tests.read_text(encoding="utf-8")
    for local_repair_regression in (
        "testCorruptFullVariantWithPhysicalDirectoryReplaysNilTokenAndRepairsWithoutUpload",
        "testMissingThumbnailWithPhysicalDirectoryReplaysNilTokenAndRepairsWithoutUpload",
        "let localStore = LocalPhotoAssetStore(",
        "CloudRepairPhotoAssetFileSystem",
        "try Data([0xff]).write(to: fullURL, options: .atomic)",
        "try FileManager.default.removeItem(at: thumbnailURL)",
        "let physicalBeforeRepair = try await localStore.storedAssetIDs()",
        "let usableBeforeRepair = try await localStore.usableCloudAssetIDs()",
        "NilTokenOnlyRepairCloudPhotoAssetDatabase",
        "guard previousToken == nil else",
        "databaseSnapshot.changeTokens, [nil, repairedChangeToken]",
        "databaseSnapshot.nilTokenRepairResponseCount, 1",
        "pendingUploadAssetIDs: [assetID]",
        "databaseSnapshot.saveRequests.isEmpty",
        "databaseSnapshot.deleteRequests.isEmpty",
        "repairedFull, .available(Data([0x10]))",
        "repairedThumbnail, .available(Data([0x20]))",
        "physicalAfterRepair, [assetID]",
        "usableAfterRepair, [assetID]",
        "firstState, finalState",
    ):
        cloud_coordinator_tests.write_text(
            original_cloud_coordinator_tests.replace(
                local_repair_regression,
                "localRepairRegressionRemoved",
            ),
            encoding="utf-8",
        )
        run(root, local_repair_regression)
        cloud_coordinator_tests.write_text(
            original_cloud_coordinator_tests,
            encoding="utf-8",
        )
    cloud_coordinator_tests.write_text(
        original_cloud_coordinator_tests.replace(
            "testReferencedMissingAssetRestoresFromCloudWithoutInferringDeletion",
            "referencedMissingRegressionRemoved",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "testReferencedMissingAssetRestoresFromCloudWithoutInferringDeletion")
    cloud_coordinator_tests.write_text(original_cloud_coordinator_tests, encoding="utf-8")

    cloud_coordinator_tests.write_text(
        original_cloud_coordinator_tests.replace(
            "testReferencedMetadataNeutralizesStaleDeletionIntentWithoutDeletingCloudAsset",
            "staleReferencedDeletionRegressionRemoved",
            1,
        ),
        encoding="utf-8",
    )
    run(
        root,
        "testReferencedMetadataNeutralizesStaleDeletionIntentWithoutDeletingCloudAsset",
    )
    cloud_coordinator_tests.write_text(original_cloud_coordinator_tests, encoding="utf-8")

    for exact_neutralization_regression in (
        "testReferencedSnapshotNeutralizesOnlyObservedIntentAcrossSameAssetABA",
        "observedStaleIntent",
        "replacementIntent",
        "XCTAssertEqual(remainingIntents.map",
        "retrySnapshot.deleteRequests",
        "intentsAfterRetry.isEmpty",
        "stateAfterRetry.pendingDeletionAssetIDs.isEmpty",
    ):
        cloud_coordinator_tests.write_text(
            original_cloud_coordinator_tests.replace(
                exact_neutralization_regression,
                "exactNeutralizationRegressionRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, exact_neutralization_regression)
        cloud_coordinator_tests.write_text(
            original_cloud_coordinator_tests,
            encoding="utf-8",
        )

    cloud_coordinator_tests.write_text(
        original_cloud_coordinator_tests.replace(
            "testStateOnlyDeletionQueueCannotAuthorizeServerDeletion",
            "stateOnlyDeletionAuthorityRegressionRemoved",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "testStateOnlyDeletionQueueCannotAuthorizeServerDeletion")
    cloud_coordinator_tests.write_text(original_cloud_coordinator_tests, encoding="utf-8")

    for concurrency_regression in (
        "testCancelledSynchronizationCleansOwnedPageDiscardedAfterSuspendedFetch",
        "testIntentCommittedAfterReadIsNotClearedAgainstOlderReferenceSnapshot",
        "pendingAfterFirst",
    ):
        cloud_coordinator_tests.write_text(
            original_cloud_coordinator_tests.replace(
                concurrency_regression,
                "cloudConcurrencyRegressionRemoved",
            ),
            encoding="utf-8",
        )
        run(root, concurrency_regression)
        cloud_coordinator_tests.write_text(
            original_cloud_coordinator_tests,
            encoding="utf-8",
        )

    for account_reset_regression in (
        "testAccountResetLoadsCurrentScopeAndPreservesOldAccountQueue",
        "testAccountTransitionProcessesOnlyCurrentScopeAndPreservesOldAndUnresolvedIntents",
        "testVerifiedAccountOfflineDeletionSurvivesFailureAndRelaunchRetry",
        "testDeferredAccountTransitionQuarantinesOldHintUntilMatchingAccountReturns",
        "postCancellationReceipt.quarantineIdentityHint",
        "postFailureReceipt.quarantineIdentityHint",
        "oldAccountIDs",
        "unresolvedIDs",
    ):
        cloud_coordinator_tests.write_text(
            original_cloud_coordinator_tests.replace(
                account_reset_regression,
                "accountResetOrderingRegressionRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, account_reset_regression)
        cloud_coordinator_tests.write_text(
            original_cloud_coordinator_tests,
            encoding="utf-8",
        )

    cloud_coordinator_tests.write_text(
        original_cloud_coordinator_tests.replace(
            "try await coordinator.synchronize()",
            "try await coordinator.synchronize(snapshot: fixture)",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "try await coordinator.synchronize()")
    cloud_coordinator_tests.write_text(original_cloud_coordinator_tests, encoding="utf-8")

    gallery_tests = root / "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/ProgressPhotoGalleryViewModelTests.swift"
    original_gallery_tests = gallery_tests.read_text(encoding="utf-8")
    gallery_tests.write_text(
        original_gallery_tests.replace(
            "testSuccessfulSyncReloadsExactMissingAndCorruptGalleryStatesInOpenLifecycle",
            "openLifecycleSyncRegressionRemoved",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "testSuccessfulSyncReloadsExactMissingAndCorruptGalleryStatesInOpenLifecycle")
    gallery_tests.write_text(original_gallery_tests, encoding="utf-8")

    photo_repository_tests = root / "Packages/HealthTrackingModules/Tests/PersistenceKitTests/ProgressPhotoRepositoryTests.swift"
    original_photo_repository_tests = photo_repository_tests.read_text(encoding="utf-8")
    photo_repository_tests.write_text(
        original_photo_repository_tests.replace(
            "testInboundCloudAssetSurvivesCoordinatorRestoreCrashAndRepositoryRelaunch",
            "inboundCrashHandshakeRegressionRemoved",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "testInboundCloudAssetSurvivesCoordinatorRestoreCrashAndRepositoryRelaunch")
    photo_repository_tests.write_text(original_photo_repository_tests, encoding="utf-8")

    for regression in (
        "testSuccessfulInboundSyncRetainsIntentUntilMetadataReferencesAsset",
        "testRepositoryConsumesOnlyInboundIDsMatchedByMetadataAcrossRelaunches",
        "testSnapshotReconcilesInboundOwnershipArrivingAfterInitialFetchPerID",
        "testInboundApplyFinishesBeforeQueuedDeleteAndFinalStateRemainsDeleted",
        "testRepositoryInboundApplyWithoutCommittedDeletionPreservesAssetBeforeMetadata",
        "testDeleteCommittedBeforeStaleChangedPageDiscardsInboundAndRetainsIntent",
        "testStaleChangedPageCannotRestoreDeletionQuarantinedByNewerAccountResolution",
        "testStaleGenerationCancelsPreparedInboundLeaseBeforeAnySideEffectAndRepositoryReacquires",
        "testInboundPreparationLeaseRejectsABAAndReleasesAfterCancellation",
        "PausingBeforeRecordCloudPhotoAssetDeletionIntentStore",
        "ObservedCloudPhotoAssetInboundApplier",
        "recordedReceipt.quarantineIdentityHint",
        "durableText.contains(recordedReceipt.intentID.uuidString)",
        "calls.commitLeaseAssetIDs.isEmpty",
        "calls.cancelLeaseAssetIDs, [inboundID]",
        "repository.cancelInboundApply(firstLease)",
        "repository.commitInboundApply(secondLease",
        "retryPreparation",
        "inboundAssetStore: assetStore",
        "inboundAssetApplier: repository",
        "waitForFetchCall(1)",
        "finishedWhileRestoreHeld",
        "transfersAfterRace.isEmpty",
        "pendingAfterDeferred, [assetID]",
        "testInboundRestoreProtectsPreviouslyFailedOrphanFromCleanupRetry",
        "testInitialOrphanSweepRereadsInboundOwnershipAtDeleteBoundary",
        "testInboundJournalReadFailureStopsPendingCleanupRetryBeforeDelete",
        "testCleanupRetryRechecksInboundOwnershipAfterEarlierAssetDeleteSuspends",
        "testInboundRecordWaitsForCleanupLeaseAndRestoreSurvivesDeleteBoundary",
        "testCancelledInboundRecordRemovesExactWaiterAndAllowsLaterCleanupLease",
        "waitForInboundRecordWaiter",
        "inboundRecordWaiterIDs",
        "A cancelled inbound record must finish before lease release.",
        "waitersAfterCancellation.isEmpty",
        "pendingBeforeLeaseRelease.isEmpty",
        "laterLease",
        "testMetadataDeleteSaveFailureNeverCreatesCloudDeletionIntent",
        "testCompensatedLocalDeleteFailureClearsCloudIntentBeforeReturning",
        "testCompensationClearsExactHintedIntentPromotedWhileReceiptIsPaused",
        "PausingAfterRecordCloudPhotoAssetDeletionIntentStore",
        "scopedAfterCompensation.isEmpty",
        "quarantineAfterCompensation.isEmpty",
    ):
        photo_repository_tests.write_text(
            original_photo_repository_tests.replace(
                regression,
                "roundTwoRegressionRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, regression)
        photo_repository_tests.write_text(
            original_photo_repository_tests,
            encoding="utf-8",
        )

    for required_evidence, weakened_evidence in (
        (
            "XCTAssertEqual(intentCalls.recordCalls, [])",
            "XCTAssertEqual(intentCalls.recordCalls, [assetID])",
        ),
        (
            "XCTAssertEqual(intentCalls.clearCalls, [])",
            "XCTAssertEqual(intentCalls.clearCalls, [assetID])",
        ),
        (
            "let persistedContext = ModelContext(container)",
            "let persistedContext = context",
        ),
        (
            "pendingAfterA, [assetB]",
            "pendingAfterA, []",
        ),
        (
            "pendingAfterARelaunch, [assetB]",
            "pendingAfterARelaunch, []",
        ),
        (
            "cloudAssets[assetB], bytesB",
            "cloudAssets[assetB], Data()",
        ),
        (
            "snapshotAfterA",
            "snapshotEvidenceRemoved",
        ),
    ):
        photo_repository_tests.write_text(
            original_photo_repository_tests.replace(
                required_evidence,
                weakened_evidence,
                1,
            ),
            encoding="utf-8",
        )
        run(root, required_evidence)
        photo_repository_tests.write_text(
            original_photo_repository_tests,
            encoding="utf-8",
        )

    quality_domain = root / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/CloudPhotoAssetDomain.swift"
    original_quality_domain = quality_domain.read_text(encoding="utf-8")
    quality_domain.write_text(
        original_quality_domain.replace(
            "func usableCloudAssetIDs()",
            "func physicalInventoryMistakenForUsableAvailability()",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 local cloud store must separate physical inventory from usable availability")
    quality_domain.write_text(original_quality_domain, encoding="utf-8")

    quality_local_store = root / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/AssetStore/LocalPhotoAssetStore.swift"
    original_quality_local_store = quality_local_store.read_text(encoding="utf-8")
    for safe_load, forced_load in (
        (
            "let full = try await loadAsset(id: assetID, variant: .full)",
            "let full = try! await loadAsset(id: assetID, variant: .full)",
        ),
        (
            "let thumbnail = try await loadAsset(id: assetID, variant: .thumbnail)",
            "let thumbnail = try! await loadAsset(id: assetID, variant: .thumbnail)",
        ),
    ):
        quality_local_store.write_text(
            original_quality_local_store.replace(safe_load, forced_load, 1),
            encoding="utf-8",
        )
        run(root, "M3.9 usable availability must propagate load errors without force-try")
        quality_local_store.write_text(
            original_quality_local_store,
            encoding="utf-8",
        )
    for usable_inventory_contract in (
        "let physicalAssetIDs = try await storedAssetIDs()",
        "for assetID in physicalAssetIDs.sorted()",
        "loadAsset(id: assetID, variant: .full)",
        "guard case .available = full else { continue }",
        "loadAsset(id: assetID, variant: .thumbnail)",
        "guard case .available = thumbnail else { continue }",
        "usableAssetIDs.insert(assetID)",
        "return usableAssetIDs",
    ):
        quality_local_store.write_text(
            original_quality_local_store.replace(
                usable_inventory_contract,
                "usableInventoryContractRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 real local store must validate full and thumbnail")
        quality_local_store.write_text(
            original_quality_local_store,
            encoding="utf-8",
        )
    quality_local_store.write_text(
        original_quality_local_store.replace(
            "return usableAssetIDs",
            "try? ignoredAvailabilityError()\n        return usableAssetIDs",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 usable availability must fail closed")
    quality_local_store.write_text(original_quality_local_store, encoding="utf-8")

    for lease_contract in (
        "CloudPhotoAssetInboundCleanupLease",
        "acquireCleanupLease(for assetID: String)",
        "releaseCleanupLease(_ lease: CloudPhotoAssetInboundCleanupLease)",
    ):
        quality_domain.write_text(
            original_quality_domain.replace(
                lease_contract,
                "atomicInboundLeaseContractRemoved",
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 inbound cleanup journal is missing atomic lease contract")
        quality_domain.write_text(original_quality_domain, encoding="utf-8")

    for inbound_apply_contract in (
        "CloudPhotoAssetInboundApplyLease",
        "CloudPhotoAssetInboundApplyPreparation",
        "case prepared(CloudPhotoAssetInboundApplyLease)",
        "case discardedCommittedDeletion",
        "CloudPhotoAssetInboundApplying",
        "func prepareInboundApply(",
        "func commitInboundApply(",
        "func cancelInboundApply(",
    ):
        quality_domain.write_text(
            original_quality_domain.replace(
                inbound_apply_contract,
                "serializedInboundApplyContractRemoved",
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 domain is missing serialized inbound apply contract")
        quality_domain.write_text(original_quality_domain, encoding="utf-8")

    for inbound_signature_contract in (
        "id assetID: String",
        "bytes: Data",
        "async throws -> CloudPhotoAssetInboundApplyPreparation",
        "_ lease: CloudPhotoAssetInboundApplyLease",
    ):
        quality_domain.write_text(
            original_quality_domain.replace(
                inbound_signature_contract,
                "serializedInboundApplySignatureRemoved",
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 domain is missing serialized inbound apply signature")
        quality_domain.write_text(original_quality_domain, encoding="utf-8")

    quality_domain.write_text(
        original_quality_domain.replace(
            "forAccountIdentity accountIdentity: String",
            "serializedInboundAccountIdentityRemoved",
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 deletion intent protocol is missing account scope")
    quality_domain.write_text(original_quality_domain, encoding="utf-8")

    for account_authorization_contract in (
        "CloudPhotoAssetAccountAuthorization",
        "CloudPhotoAssetAccountResolution",
        "quarantineIdentityHint",
        "beginAccountResolution()",
        "resolution: CloudPhotoAssetAccountResolution",
        "pendingDeletionIntents(",
        "async throws -> [CloudPhotoAssetDeletionIntentReceipt]",
        "hasCommittedLocalDeletionIntent(assetID: String)",
    ):
        quality_domain.write_text(
            original_quality_domain.replace(
                account_authorization_contract,
                "boundedAccountAuthorizationContractRemoved",
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 deletion intent protocol is missing account scope")
        quality_domain.write_text(original_quality_domain, encoding="utf-8")

    quality_coordinator = root / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/CloudPhotoAssetCoordinator.swift"
    original_quality_coordinator = quality_coordinator.read_text(encoding="utf-8")
    for usable_reconcile_contract, expected_failure in (
        (
            "let usableLocalAssetIDs = try await localStore.usableCloudAssetIDs()",
            "M3.9 coordinator must reconcile complete usable availability",
        ),
        (
            "try validate(assetIDs: usableLocalAssetIDs)",
            "M3.9 coordinator must reconcile complete usable availability",
        ),
        (
            "reconcile(usableLocalAssetIDs: usableLocalAssetIDs,",
            "M3.9 coordinator must reconcile complete usable availability",
        ),
        (
            "let referencedUsable = usableLocalAssetIDs.intersection(referencedAssetIDs)",
            "M3.9 incomplete uploaded assets must replay from nil without upload",
        ),
        (
            ".intersection(referencedUsable)",
            "M3.9 incomplete uploaded assets must replay from nil without upload",
        ),
        (
            ".union(referencedUsable.subtracting(uploaded))",
            "M3.9 incomplete uploaded assets must replay from nil without upload",
        ),
        (
            ".subtracting(usableLocalAssetIDs)",
            "M3.9 incomplete uploaded assets must replay from nil without upload",
        ),
    ):
        quality_coordinator.write_text(
            original_quality_coordinator.replace(
                usable_reconcile_contract,
                "usableReconcileContractRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, expected_failure)
        quality_coordinator.write_text(
            original_quality_coordinator,
            encoding="utf-8",
        )
    quality_coordinator.write_text(
        original_quality_coordinator.replace(
            "localStore.usableCloudAssetIDs()",
            "localStore.storedAssetIDs()",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 coordinator must not treat physical inventory as usable availability")
    quality_coordinator.write_text(original_quality_coordinator, encoding="utf-8")

    for inbound_coordinator_contract, expected_failure in (
        (
            "inboundAssetApplier: any CloudPhotoAssetInboundApplying",
            "M3.9 coordinator must require an explicit inbound applier",
        ),
        (
            "inboundAssetApplier.prepareInboundApply(",
            "M3.9 shipped no-argument sync is missing injected quality contract",
        ),
        (
            "inboundAssetApplier.commitInboundApply(",
            "M3.9 shipped no-argument sync is missing injected quality contract",
        ),
        (
            "inboundAssetApplier.cancelInboundApply(",
            "M3.9 shipped no-argument sync is missing injected quality contract",
        ),
        (
            "case .discardedCommittedDeletion:",
            "M3.9 shipped no-argument sync is missing injected quality contract",
        ),
    ):
        quality_coordinator.write_text(
            original_quality_coordinator.replace(
                inbound_coordinator_contract,
                "serializedInboundCoordinatorContractRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, expected_failure)
        quality_coordinator.write_text(original_quality_coordinator, encoding="utf-8")

    quality_coordinator.write_text(
        original_quality_coordinator.replace(
            "case .discardedCommittedDeletion:\n            return",
            "case .discardedCommittedDeletion:\n            break",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 discarded committed deletion must not mutate uploaded/deletion state")
    quality_coordinator.write_text(original_quality_coordinator, encoding="utf-8")
    quality_coordinator.write_text(
        original_quality_coordinator.replace(
            "try ensureCurrent(generation)",
            "preparedInboundGenerationCheckRemoved",
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 coordinator must generation-check and exact-cancel a prepared inbound lease")
    quality_coordinator.write_text(original_quality_coordinator, encoding="utf-8")
    for coordinator_authorization_contract, expected_failure in (
        (
            "let accountResolution = await deletionIntentStore.beginAccountResolution()",
            "M3.9 shipped no-argument sync is missing injected quality contract",
        ),
        (
            "resolution: accountResolution",
            "M3.9 shipped no-argument sync is missing injected quality contract",
        ),
        (
            "let accountAuthorization = try await deletionIntentStore.activateAccountIdentity(",
            "M3.9 shipped no-argument sync is missing injected quality contract",
        ),
        (
            "await deletionIntentStore.suspendAccountAuthorization(accountAuthorization)",
            "M3.9 coordinator must close bounded account authorization on success and failure",
        ),
    ):
        quality_coordinator.write_text(
            original_quality_coordinator.replace(
                coordinator_authorization_contract,
                "boundedAccountAuthorizationRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, expected_failure)
        quality_coordinator.write_text(original_quality_coordinator, encoding="utf-8")

    quality_coordinator.write_text(
        original_quality_coordinator.replace(
            "public func synchronize()",
            "public func synchronize(snapshot:)",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 shipped no-argument sync is missing injected quality contract")
    quality_coordinator.write_text(original_quality_coordinator, encoding="utf-8")

    quality_coordinator.write_text(
        original_quality_coordinator.replace(
            "let deletions = committedDeletionIDs",
            "let deletions = Set(state.pendingDeletionAssetIDs).union(committedDeletionIDs)",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 shipped no-argument sync is missing injected quality contract")
    quality_coordinator.write_text(original_quality_coordinator, encoding="utf-8")

    quality_coordinator.write_text(
        original_quality_coordinator.replace(
            "let referencedDeletionIDs = Set(referencedDeletionIntents.map(\\.assetID))",
            "let referencedDeletionIDs = Set(state.pendingDeletionAssetIDs)",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 shipped no-argument sync is missing injected quality contract")
    quality_coordinator.write_text(original_quality_coordinator, encoding="utf-8")

    for exact_neutralization_contract in (
        "let referencedDeletionIntents = committedDeletionIntents.filter",
        "clearCommittedDeletion(intent)",
        "let referencedDeletionIDs = Set(referencedDeletionIntents.map(\\.assetID))",
    ):
        quality_coordinator.write_text(
            original_quality_coordinator.replace(
                exact_neutralization_contract,
                "exactObservedNeutralizationRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 shipped no-argument sync is missing injected quality contract")
        quality_coordinator.write_text(
            original_quality_coordinator,
            encoding="utf-8",
        )

    quality_coordinator.write_text(
        original_quality_coordinator.replace(
            "clearCommittedDeletion(\n                assetID: assetID,",
            "clearCommittedDeletion(intent)",
            1,
        ),
        encoding="utf-8",
    )
    run(
        root,
        "M3.9 confirmed remote deletion must clear all matching current-account intents",
    )
    quality_coordinator.write_text(original_quality_coordinator, encoding="utf-8")

    quality_coordinator.write_text(
        original_quality_coordinator.replace(
            "onDiscard: { [temporaryStore = self.temporaryStore] page in",
            "onDiscard: { _ in",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 shipped no-argument sync is missing injected quality contract")
    quality_coordinator.write_text(original_quality_coordinator, encoding="utf-8")

    quality_coordinator.write_text(
        original_quality_coordinator.replace(
            "try validate(state: state)",
            "resolution: accountResolution try validate(state: state)",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 account transition must validate state and activate the current scope")
    quality_coordinator.write_text(original_quality_coordinator, encoding="utf-8")

    quality_coordinator.write_text(
        original_quality_coordinator.replace(
            "resolution: accountResolution",
            "clearAllCommittedDeletions()",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 shipped no-argument sync is missing injected quality contract")
    quality_coordinator.write_text(original_quality_coordinator, encoding="utf-8")

    quality_coordinator.write_text(
        original_quality_coordinator.replace(
            "pendingDeletionIntents(forAccountIdentity: accountIdentity)",
            "await referenceSnapshotProvider.snapshot() pendingDeletionIntents(forAccountIdentity: accountIdentity)",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 coordinator must snapshot committed deletions before references")
    quality_coordinator.write_text(original_quality_coordinator, encoding="utf-8")

    quality_repository = root / "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataProgressPhotoRepository.swift"
    original_quality_repository = quality_repository.read_text(encoding="utf-8")
    for inbound_repository_contract, expected_failure in (
        (
            "await acquireExclusiveOperation()",
            "M3.9 repository is missing retained inbound preparation transaction",
        ),
        (
            "hasCommittedLocalDeletionIntent(assetID: assetID)",
            "M3.9 repository is missing retained inbound preparation transaction",
        ),
        (
            "return .discardedCommittedDeletion",
            "M3.9 repository is missing retained inbound preparation transaction",
        ),
        (
            "releaseExclusiveOperation()",
            "M3.9 repository preparation must retain the lock only for an exact prepared lease",
        ),
        (
            "activeInboundApplyLease = lease",
            "M3.9 repository is missing retained inbound preparation transaction",
        ),
        (
            "return .prepared(lease)",
            "M3.9 repository is missing retained inbound preparation transaction",
        ),
        (
            "guard activeInboundApplyLease == lease else",
            "M3.9 repository inbound commit must consume and release one exact lease",
        ),
        (
            "defer { releaseInboundApplyLease(lease) }",
            "M3.9 repository inbound commit must consume and release one exact lease",
        ),
        (
            "inboundAssetJournal.recordInboundAssetID(lease.assetID)",
            "M3.9 repository inbound commit must consume and release one exact lease",
        ),
        (
            "try Task.checkCancellation()",
            "M3.9 repository inbound commit must consume and release one exact lease",
        ),
        (
            "inboundAssetStore.restoreCloudAsset(id: lease.assetID, bytes: bytes)",
            "M3.9 repository inbound commit must consume and release one exact lease",
        ),
        (
            "guard activeInboundApplyLease == lease else { return }",
            "M3.9 stale inbound lease cancellation must not release a newer lease",
        ),
        (
            "private func releaseInboundApplyLease(",
            "M3.9 repository inbound lease release must be exact and reusable",
        ),
        (
            "activeInboundApplyLease = nil",
            "M3.9 repository inbound lease release must be exact and reusable",
        ),
    ):
        quality_repository.write_text(
            original_quality_repository.replace(
                inbound_repository_contract,
                "serializedInboundRepositoryContractRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, expected_failure)
        quality_repository.write_text(original_quality_repository, encoding="utf-8")
    for repository_lease_contract, expected_failure in (
        (
            "acquireCleanupLease(for: assetID)",
            "M3.9 repository is missing atomic inbound-safe deletion",
        ),
        (
            "releaseCleanupLease(lease)",
            "M3.9 repository must release the inbound cleanup lease on success and failure",
        ),
        (
            "deleteAssetIfNotInbound(assetID)",
            "M3.9 retry and initial orphan sweep must share the atomic inbound-safe delete boundary",
        ),
    ):
        quality_repository.write_text(
            original_quality_repository.replace(
                repository_lease_contract,
                "atomicInboundDeletionContractRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, expected_failure)
        quality_repository.write_text(original_quality_repository, encoding="utf-8")

    quality_repository.write_text(
        original_quality_repository.replace(
            "recordCommittedDeletion",
            "skipDurableCloudIntentRecord",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 repository is missing durable cloud handshake contract")
    quality_repository.write_text(original_quality_repository, encoding="utf-8")

    quality_repository.write_text(
        original_quality_repository.replace(
            "clearCommittedDeletion(deletionIntent)",
            "clearCommittedDeletion(CloudPhotoAssetDeletionIntentReceipt(assetID: deletionIntent.assetID, accountIdentity: nil))",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 repository compensation must clear the exact recorded scoped receipt")
    quality_repository.write_text(original_quality_repository, encoding="utf-8")

    quality_repository.write_text(
        original_quality_repository.replace(
            "reconcileAssetStorageIfNeeded(rows: rows)",
            "skipInboundSnapshotReconciliation(rows: rows)",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 repository snapshot must reconcile inbound metadata ownership")
    quality_repository.write_text(original_quality_repository, encoding="utf-8")

    quality_repository.write_text(
        original_quality_repository.replace(
            "let pendingInboundAssetIDs = try await loadPendingInboundAssetIDsFailClosed() guard !hasReconciledAssetStorage else { return }",
            "guard !hasReconciledAssetStorage else { return } let pendingInboundAssetIDs = try await loadPendingInboundAssetIDsFailClosed()",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 inbound ownership reconciliation must precede one-shot orphan sweep")
    quality_repository.write_text(original_quality_repository, encoding="utf-8")

    quality_repository.write_text(
        original_quality_repository.replace(
            "let freshPendingInboundAssetIDs = try await loadPendingInboundAssetIDsFailClosed()",
            "let freshPendingInboundAssetIDs = Set<String>()",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 pending cleanup retry must reread and subtract fresh inbound ownership")
    quality_repository.write_text(original_quality_repository, encoding="utf-8")

    reconcile_boundary = original_quality_repository.rfind(
        "let freshPendingInboundAssetIDs = try await loadPendingInboundAssetIDsFailClosed()"
    )
    if reconcile_boundary < 0:
        raise SystemExit("M3.9 orphan-sweep inbound mutation fixture is missing")
    quality_repository.write_text(
        original_quality_repository[:reconcile_boundary]
        + original_quality_repository[reconcile_boundary:].replace(
            "let freshPendingInboundAssetIDs = try await loadPendingInboundAssetIDsFailClosed()",
            "let freshPendingInboundAssetIDs = Set<String>()",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 orphan sweep must fail closed on a fresh inbound read at delete boundary")
    quality_repository.write_text(original_quality_repository, encoding="utf-8")

    quality_coordinator.write_text(
        original_quality_coordinator.replace(
            "temporaryStore.removeFile(at: record.stagedFileURL)",
            "leaveAdapterOwnedTransferForRelaunch",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 shipped no-argument sync is missing injected quality contract")
    quality_coordinator.write_text(original_quality_coordinator, encoding="utf-8")

    quality_factory = root / "App/Application/TrackerFeatureBundle.swift"
    original_quality_factory = quality_factory.read_text(encoding="utf-8")
    for local_boundary in (
        "guard case .cloud = environment else",
        "NoOpCloudPhotoAssetDeletionIntentStore.shared",
        "NoOpCloudPhotoAssetInboundJournal.shared",
    ):
        quality_factory.write_text(
            original_quality_factory.replace(
                local_boundary,
                "unsafePersistentLocalCloudHandshake",
                1,
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 local/UI composition must not persist cloud handshakes")
        quality_factory.write_text(original_quality_factory, encoding="utf-8")

    quality_factory.write_text(
        original_quality_factory.replace(
            "deletionIntentStore: deletionIntentStore",
            "deletionIntentStore: isolatedDeletionIntentStore",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 repository and coordinator must receive the same provider")
    quality_factory.write_text(original_quality_factory, encoding="utf-8")

    quality_factory.write_text(
        original_quality_factory.replace(
            "inboundAssetJournal: inboundAssetJournal",
            "inboundAssetJournal: isolatedInboundAssetJournal",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 repository must receive the one shared inbound journal")
    quality_factory.write_text(original_quality_factory, encoding="utf-8")

    for inbound_composition_contract in (
        "inboundAssetStore: progressPhotoAssetStore",
        "inboundAssetApplier: progressPhotoRepository",
        "any CloudPhotoAssetReferenceSnapshotProviding & CloudPhotoAssetInboundApplying",
    ):
        quality_factory.write_text(
            original_quality_factory.replace(
                inbound_composition_contract,
                "sharedInboundRepositoryCompositionRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 shipped composition must share one repository inbound transaction")
        quality_factory.write_text(original_quality_factory, encoding="utf-8")

    quality_factory.write_text(
        original_quality_factory.replace(
            "referenceSnapshotProvider: progressPhotoRepository",
            "referenceSnapshotProvider: emptySnapshotProvider",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 shipped coordinator must receive the real repository snapshot provider")
    quality_factory.write_text(original_quality_factory, encoding="utf-8")

    quality_factory.write_text(
        original_quality_factory.replace(
            "downloadStore: cloudPhotoAssetTransferStore",
            "downloadStore: isolatedAdapterTransferStore",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 adapter and coordinator must receive the same transfer store")
    quality_factory.write_text(original_quality_factory, encoding="utf-8")

    quality_factory.write_text(
        original_quality_factory.replace(
            "temporaryStore: cloudPhotoAssetTransferStore",
            "temporaryStore: isolatedCoordinatorTransferStore",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 adapter and coordinator must receive the same transfer store")
    quality_factory.write_text(original_quality_factory, encoding="utf-8")

    quality_adapter = root / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/CloudKitPrivatePhotoAssetDatabase.swift"
    original_quality_adapter = quality_adapter.read_text(encoding="utf-8")
    quality_adapter.write_text(
        original_quality_adapter.replace(
            "downloadStore.stageDownload(",
            "coordinatorStagesDownload(",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 actual CloudKit adapter is missing ownership/account contract")
    quality_adapter.write_text(original_quality_adapter, encoding="utf-8")

    for lifetime_contract in (
        "let owned = try withExtendedLifetime(record) {",
        "lifetimeOwner: asset",
    ):
        quality_adapter.write_text(
            original_quality_adapter.replace(
                lifetime_contract,
                "droppedSystemAssetLifetime",
                1,
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 actual CloudKit adapter is missing ownership/account contract")
        quality_adapter.write_text(original_quality_adapter, encoding="utf-8")

    for binary_presence_contract in (
        "record.hasUsableBinaryAsset else { return nil }",
        "CloudKitPhotoAssetRecordMapper.systemRecord(from: record)",
        "private static func hasUsableBinaryAsset(in record: CKRecord) -> Bool",
        "resourceValues.isRegularFile == true",
        "resourceValues.isReadable == true",
    ):
        quality_adapter.write_text(
            original_quality_adapter.replace(
                binary_presence_contract,
                "binaryPresenceContractRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 actual adapter is missing CKAsset binary-presence repair gate")
        quality_adapter.write_text(original_quality_adapter, encoding="utf-8")

    for explicit_modify_contract in (
        "CloudKitPhotoAssetRecordModifying",
        "recordModifier.modifyRecords(",
        "savePolicy: .changedKeys",
        "atomically: true",
        "saveResults[record.recordID]",
        "deleteResults.isEmpty",
        "try recordResult.get()",
        "CloudKitPhotoAssetRecordMapper.uploadRecord(",
        "database.modifyRecords(",
        "defer { withExtendedLifetime(record) {} }",
    ):
        quality_adapter.write_text(
            original_quality_adapter.replace(
                explicit_modify_contract,
                "explicitCloudKitRepairPolicyRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 CloudKit repair is missing explicit atomic changed-keys modify")
        quality_adapter.write_text(original_quality_adapter, encoding="utf-8")

    quality_adapter.write_text(
        original_quality_adapter.replace(
            "database.modifyRecords(",
            "database.save(record)",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 CloudKit repair is missing explicit atomic changed-keys modify")
    quality_adapter.write_text(original_quality_adapter, encoding="utf-8")

    quality_transfer_store = root / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Cloud/FileCloudPhotoAssetStores.swift"
    original_quality_transfer_store = quality_transfer_store.read_text(encoding="utf-8")
    for account_resolution_contract in (
        "public func beginAccountResolution()",
        "activeAccountAuthorization = nil",
        "activeAccountResolutionID = resolution.resolutionID",
        "guard activeAccountResolutionID == resolution.resolutionID else",
        "activeAccountResolutionID = nil",
        "throw CancellationError()",
    ):
        quality_transfer_store.write_text(
            original_quality_transfer_store.replace(
                account_resolution_contract,
                "accountResolutionCASRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 account activation is missing resolution-epoch CAS")
        quality_transfer_store.write_text(
            original_quality_transfer_store,
            encoding="utf-8",
        )

    for stable_intent_contract in (
        "FileCloudPhotoAssetDeletionIntentRecord",
        "static let currentSchemaVersion = 3",
        "public func pendingDeletionIntents(",
        "intent.accountIdentity == accountIdentity",
        "intent.quarantineIdentityHint == nil",
        "intentID: intent.intentID",
        "intentID: UUID()",
        "state.intents[index].accountIdentity = accountIdentity",
        "state.intents[index].quarantineIdentityHint = nil",
        "$0.intentID == intent.intentID",
        "storedIntent.assetID == canonicalID",
        "FileCloudPhotoAssetDeletionIntentV2State",
    ):
        quality_transfer_store.write_text(
            original_quality_transfer_store.replace(
                stable_intent_contract,
                "stableIntentIdentityContractRemoved",
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 deletion receipts are missing stable exact intent identity")
        quality_transfer_store.write_text(
            original_quality_transfer_store,
            encoding="utf-8",
        )

    for local_suppression_contract in (
        "canonicalAssetID(assetID)",
        "loadState()",
        "state.intents.contains { $0.assetID == canonicalID }",
    ):
        quality_transfer_store.write_text(
            original_quality_transfer_store.replace(
                local_suppression_contract,
                "allScopeLocalSuppressionRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 local suppression must inspect every persisted intent scope")
        quality_transfer_store.write_text(
            original_quality_transfer_store,
            encoding="utf-8",
        )

    for direct_inbound_lease_contract in (
        "activeInboundApplyLeases[lease.leaseID] = lease",
        "guard activeInboundApplyLeases[lease.leaseID] == lease else",
        "activeInboundApplyLeases.removeValue(forKey: lease.leaseID)",
    ):
        quality_transfer_store.write_text(
            original_quality_transfer_store.replace(
                direct_inbound_lease_contract,
                "directInboundExactLeaseRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 direct inbound applier is missing exact two-phase lease semantics")
        quality_transfer_store.write_text(
            original_quality_transfer_store,
            encoding="utf-8",
        )

    for journal_lease_contract in (
        "cleanupLeaseWaitersByAssetID[canonicalID]?.isEmpty != false",
        "cleanupLeasesByAssetID[canonicalID] == lease.leaseID",
        "withTaskCancellationHandler",
        "waiterID: UUID",
        "cancelInboundRecordWaiter",
        "removeValue(forKey: waiterID)",
        "continuation.resume(throwing: CancellationError())",
        "try await waitForCleanupLeaseRelease(\n                for: canonicalID,\n                waiterID: waiterID\n            )\n            try Task.checkCancellation()",
        "waiter.resume(returning: ())",
    ):
        quality_transfer_store.write_text(
            original_quality_transfer_store.replace(
                journal_lease_contract,
                "serializedInboundLeaseSemanticsRemoved",
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 file inbound journal is missing serialized cleanup lease")
        quality_transfer_store.write_text(
            original_quality_transfer_store,
            encoding="utf-8",
        )

    for account_provenance_contract in (
        "quarantinedIntents",
        "accountIdentityHint",
        "lastVerifiedAccountIdentity",
        "state.intents[index].quarantineIdentityHint == accountIdentity",
    ):
        quality_transfer_store.write_text(
            original_quality_transfer_store.replace(
                account_provenance_contract,
                "accountProvenanceContractRemoved",
            ),
            encoding="utf-8",
        )
        run(root, "M3.9 file deletion store is missing scoped/quarantine durability")
        quality_transfer_store.write_text(
            original_quality_transfer_store,
            encoding="utf-8",
        )

    quality_transfer_store.write_text(
        original_quality_transfer_store.replace("remaining + 1", "remaining", 1),
        encoding="utf-8",
    )
    run(root, "M3.9 download staging is missing bounded streaming primitive")
    quality_transfer_store.write_text(original_quality_transfer_store, encoding="utf-8")

    quality_transfer_store.write_text(
        original_quality_transfer_store.replace(
            "accountIdentity: activeAccountIdentity",
            "accountIdentity: nil",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 file deletion store must serialize records into the exact active or legacy-quarantine scope")
    quality_transfer_store.write_text(original_quality_transfer_store, encoding="utf-8")

    quality_transfer_store.write_text(
        original_quality_transfer_store.replace(
            "fileHandleFactory",
            "replacementCopier",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 download staging is missing bounded streaming primitive")
    quality_transfer_store.write_text(original_quality_transfer_store, encoding="utf-8")

    quality_transfer_store.write_text(
        original_quality_transfer_store.replace(
            "read(upToCount: remaining + 1)",
            "readToEnd",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 download staging must not use unbounded I/O")
    quality_transfer_store.write_text(original_quality_transfer_store, encoding="utf-8")

    quality_transfer_store.write_text(
        original_quality_transfer_store.replace(
            "guard isOwned(url) else",
            "guard true else",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 coordinator reads must retain the app-owned transfer boundary")
    quality_transfer_store.write_text(original_quality_transfer_store, encoding="utf-8")

    quality_transfer_store.write_text(
        original_quality_transfer_store.replace(
            "isCanonicalTransferFileName(",
            "hasAssetSuffix(",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 canonical transfer ownership must gate both sweep and access")
    quality_transfer_store.write_text(original_quality_transfer_store, encoding="utf-8")

    quality_transfer_store.write_text(
        original_quality_transfer_store.replace(
            "try close(reader: reader, writer: writer)",
            "try? close(reader: reader, writer: writer)",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 validated staging must propagate writer/reader close failure")
    quality_transfer_store.write_text(original_quality_transfer_store, encoding="utf-8")

    quality_lifecycle = root / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoLifecycleView.swift"
    original_quality_lifecycle = quality_lifecycle.read_text(encoding="utf-8")
    quality_lifecycle.write_text(
        original_quality_lifecycle.replace(
            "await assetSyncLifecycle.synchronize()",
            "await assetSynchronizer.synchronize()",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.9 shipped lifecycle view must delegate successful sync cache repair")
    quality_lifecycle.write_text(original_quality_lifecycle, encoding="utf-8")

    gallery_tests.write_text(
        original_gallery_tests.replace(
            "fullImageRequests.filter",
            "comparisonReloadEvidenceRemoved",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "fullImageRequests.filter")
    gallery_tests.write_text(original_gallery_tests, encoding="utf-8")

    cloud_contract_tests.write_text(
        original_cloud_contract_tests.replace(
            "testLegacyUnscopedSyncStateRecreatesWithNilAccountIdentity",
            "legacyIdentityRegressionRemoved",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "testLegacyUnscopedSyncStateRecreatesWithNilAccountIdentity")
    cloud_contract_tests.write_text(original_cloud_contract_tests, encoding="utf-8")

    cloudkit_adapter_tests = root / "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/CloudKitPrivatePhotoAssetDatabaseTests.swift"
    original_cloudkit_adapter_tests = cloudkit_adapter_tests.read_text(encoding="utf-8")
    cloudkit_adapter_tests.write_text(
        original_cloudkit_adapter_tests.replace(
            "testActualAdapterReturnsChangingOpaqueAccountIdentity",
            "adapterIdentityRegressionRemoved",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "testActualAdapterReturnsChangingOpaqueAccountIdentity")
    cloudkit_adapter_tests.write_text(original_cloudkit_adapter_tests, encoding="utf-8")

    cloudkit_adapter_tests.write_text(
        original_cloudkit_adapter_tests.replace(
            "testActualAdapterAndCoordinatorConsumeAndRemoveOneSharedOwnedTransfer",
            "sharedTransferIntegrationRegressionRemoved",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "testActualAdapterAndCoordinatorConsumeAndRemoveOneSharedOwnedTransfer")
    cloudkit_adapter_tests.write_text(original_cloudkit_adapter_tests, encoding="utf-8")

    for binary_presence_regression in (
        "testActualAdapterRepairsMatchingMetadataWithoutUsableBinaryAndKeepsValidAssetIdempotent",
        "hasUsableBinaryAsset: false",
        "hasUsableBinaryAsset: true",
        "missingBinary.saveRequests.map",
        "validBinary.saveRequests.isEmpty",
        "testActualCKRecordMappingRequiresReadableRegularCKAssetFile",
        "testExplicitChangedKeysModifyRepairsSameIDAssetAndPreservesUnknownFields",
        "testExplicitModifySurfacesExactPerRecordFailure",
        "ConflictAwareCloudKitPhotoAssetRecordModifier",
        "savePolicy: .ifServerRecordUnchanged",
        "RecordSavePolicy.changedKeys.rawValue",
        "serverOnly",
        "perRecordFailure",
        "CloudKitPhotoAssetRecordMapper.systemRecord",
        "missingAsset",
        "wrongTypeAsset",
        "invalidFileAsset",
        "directoryAsset",
        "validAsset",
    ):
        cloudkit_adapter_tests.write_text(
            original_cloudkit_adapter_tests.replace(
                binary_presence_regression,
                "binaryPresenceRegressionRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, binary_presence_regression)
        cloudkit_adapter_tests.write_text(
            original_cloudkit_adapter_tests,
            encoding="utf-8",
        )

    for lifetime_evidence in (
        "CloudPhotoAssetSystemURLLifetimeOwner",
        "XCTAssertFalse(FileManager.default.fileExists(atPath: systemURL.path))",
    ):
        cloudkit_adapter_tests.write_text(
            original_cloudkit_adapter_tests.replace(
                lifetime_evidence,
                "systemAssetLifetimeEvidenceRemoved",
                1,
            ),
            encoding="utf-8",
        )
        run(root, lifetime_evidence)
        cloudkit_adapter_tests.write_text(
            original_cloudkit_adapter_tests,
            encoding="utf-8",
        )

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
            ".m3Bloodwork, .m3ProgressPhotos, .m3PhotoGallery:",
            ".m3Bloodwork, .m3ProgressPhotos:",
        ),
        encoding="utf-8",
    )
    run(root, "M3.8 app launch composition must load normal training foundation")
    dependencies.write_text(original_dependencies, encoding="utf-8")

    dependencies.write_text(
        original_dependencies.replace(
            ".m3ProgressPhotos, .m3PhotoGallery:\n                return",
            ".m3ProgressPhotos:\n                return",
        ),
        encoding="utf-8",
    )
    run(root, "M3.8 UI test fixture installation must skip CoreModels seeding")
    dependencies.write_text(original_dependencies, encoding="utf-8")

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

    medical_safety_test = root / "Packages/HealthTrackingModules/Tests/HealthSafetyKitTests/MedicalSafetyPresentationTests.swift"
    original_medical_safety_test = medical_safety_test.read_text(encoding="utf-8")
    medical_safety_test.write_text(
        original_medical_safety_test.replace(
            "testMissingSymptomAnswerPublishesCompleteNonUrgentFailClosedLevelTwo",
            "missingAnswerCoverageWasRemoved",
        ),
        encoding="utf-8",
    )
    run(root, "testMissingSymptomAnswerPublishesCompleteNonUrgentFailClosedLevelTwo")
    medical_safety_test.write_text(original_medical_safety_test, encoding="utf-8")

    medical_safety_test.write_text(
        original_medical_safety_test.replace(
            "değişiklik acil tıbbi değerlendirme gerektirir.\"",
            "değişiklik acil tıbbi değerlendirme gerektirir. Ek öneri.\"",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.10 RED test expectedGeneralMessage must freeze the complete exact Turkish copy")
    medical_safety_test.write_text(original_medical_safety_test, encoding="utf-8")

    medical_safety_test.write_text(
        original_medical_safety_test.replace(
            "private let expectedUrgentMessage =\n"
            '"Hareketi durdur. Yeni veya belirgin şekilde kötüleşen kol veya bacakta '
            "güçsüzlük ya da uyuşma, el becerisinde kayıp, denge veya yürümede "
            "değişiklik ya da mesane veya bağırsak işlevinde değişiklik acil tıbbi "
            'değerlendirme gerektirir."',
            "private let expectedUrgentMessage =\n"
            '"Hareketi durdur. Yeni veya belirgin şekilde kötüleşen kol veya bacakta '
            "güçsüzlük ya da uyuşma, el becerisinde kayıp, denge veya yürümede "
            "değişiklik ya da mesane veya bağırsak işlevinde değişiklik acil tıbbi "
            'değerlendirme gerektirir. Ek öneri."',
        ),
        encoding="utf-8",
    )
    run(root, "M3.10 RED test expectedUrgentMessage must freeze the complete exact Turkish copy")
    medical_safety_test.write_text(original_medical_safety_test, encoding="utf-8")

    for removed, expected in (
        (
            "for flag in CervicalRedFlag.allCases",
            "for flag in CervicalRedFlag.allCases",
        ),
        (
            "triggers: [.cervicalRedFlags([flag])]",
            "triggers: [.cervicalRedFlags([flag])]",
        ),
        (
            "for generalTrigger in generalTriggers",
            "for generalTrigger in generalTriggers",
        ),
        (
            "XCTAssertEqual(notice.kind, .urgentAssessmentInformation",
            "XCTAssertEqual(notice.kind, .urgentAssessmentInformation",
        ),
        (
            "XCTAssertTrue(notice.requiresUrgentAssessment",
            "XCTAssertTrue(notice.requiresUrgentAssessment",
        ),
        (
            "XCTAssertEqual(notice.message, expectedUrgentMessage",
            "XCTAssertEqual(notice.message, expectedUrgentMessage",
        ),
    ):
        medical_safety_test.write_text(
            original_medical_safety_test.replace(removed, "coverageWasRemoved"),
            encoding="utf-8",
        )
        run(root, expected)
        medical_safety_test.write_text(
            original_medical_safety_test,
            encoding="utf-8",
        )

    posture_safety_test = root / "Packages/HealthTrackingModules/Tests/MetricsKitTests/PostureViewModelTests.swift"
    original_posture_safety_test = posture_safety_test.read_text(encoding="utf-8")
    posture_safety_test.write_text(
        original_posture_safety_test.replace(
            "testLoadOrdersHistoryAndWallTestOnlyRecordDoesNotTriggerSafety",
            "wallTestOnlyRulingWasRemoved",
        ),
        encoding="utf-8",
    )
    run(root, "testLoadOrdersHistoryAndWallTestOnlyRecordDoesNotTriggerSafety")
    posture_safety_test.write_text(original_posture_safety_test, encoding="utf-8")

    session_safety_test = root / "Packages/HealthTrackingModules/Tests/TrainingKitTests/SessionViewModelTests.swift"
    original_session_safety_test = session_safety_test.read_text(encoding="utf-8")
    session_safety_test.write_text(
        original_session_safety_test.replace(
            ".priorOverheadPressResponse(.uncertain)",
            ".priorResponseCoverageWasRemoved",
        ),
        encoding="utf-8",
    )
    run(root, ".priorOverheadPressResponse(.uncertain)")
    session_safety_test.write_text(original_session_safety_test, encoding="utf-8")

    app_safety_mapper_test = root / "HealthTrackingAppTests/SymptomJournalAdapterTests.swift"
    original_app_safety_mapper_test = app_safety_mapper_test.read_text(encoding="utf-8")
    app_safety_mapper_test.write_text(
        original_app_safety_mapper_test.replace(
            "OHPSymptomResponse.notAsked, .uncertain",
            "OHPSymptomResponse.symptomFree",
        ),
        encoding="utf-8",
    )
    run(root, "OHPSymptomResponse.notAsked, .uncertain")
    app_safety_mapper_test.write_text(original_app_safety_mapper_test, encoding="utf-8")

    app_safety_mapper_test.write_text(
        original_app_safety_mapper_test.replace(
            "session.resolveSymptomSafetyPresentation(for: context)",
            "TrainingSymptomSafetyMapper.presentation(for: context)",
        ),
        encoding="utf-8",
    )
    run(root, "session.resolveSymptomSafetyPresentation(for: context)")
    app_safety_mapper_test.write_text(original_app_safety_mapper_test, encoding="utf-8")

    acknowledgement_test = root / "HealthTrackingAppTests/MedicalSafetyAcknowledgementTests.swift"
    original_acknowledgement_test = acknowledgement_test.read_text(encoding="utf-8")
    acknowledgement_test.write_text(
        original_acknowledgement_test.replace(
            "XCTAssertTrue(controller.isLevelZeroVisible)",
            "XCTAssertFalse(controller.isLevelZeroVisible)",
        ),
        encoding="utf-8",
    )
    run(root, "XCTAssertTrue(controller.isLevelZeroVisible)")
    acknowledgement_test.write_text(original_acknowledgement_test, encoding="utf-8")

    motion_policy_test = (
        root
        / "Packages/HealthTrackingModules/Tests/DesignSystemTests/MedicalSafetyMotionPolicyTests.swift"
    )
    original_motion_policy_test = motion_policy_test.read_text(encoding="utf-8")
    motion_policy_test.write_text(
        original_motion_policy_test.replace(
            "),\n.identity\n)",
            "),\n.opacity\n)",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "M3.10 motion behavior test must require Reduce Motion true -> identity")
    motion_policy_test.write_text(original_motion_policy_test, encoding="utf-8")

    focus_policy_test = (
        root
        / "Packages/HealthTrackingModules/Tests/DesignSystemTests/MedicalSafetyFocusPolicyTests.swift"
    )
    original_focus_policy_test = focus_policy_test.read_text(encoding="utf-8")
    focus_policy_test.write_text(
        original_focus_policy_test.replace(
            "isLevelTwoPresented: true",
            "isLevelTwoPresented: false",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "MedicalSafetyFocusPolicy.headingFocused(isLevelTwoPresented: true)")
    focus_policy_test.write_text(original_focus_policy_test, encoding="utf-8")

    frozen_l1 = "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."
    for relative_path in (
        "HealthTrackingAppUITests/PostureFlowUITests.swift",
        "HealthTrackingAppUITests/OHPSafetyFlowUITests.swift",
        "HealthTrackingAppUITests/BloodworkFlowUITests.swift",
        "HealthTrackingAppUITests/HealthCheckFlowUITests.swift",
    ):
        l1_test = root / relative_path
        original_l1_test = l1_test.read_text(encoding="utf-8")
        l1_test.write_text(
            original_l1_test.replace(frozen_l1, "Bu bir sağlık notudur.", 1),
            encoding="utf-8",
        )
        run(root, relative_path)
        l1_test.write_text(original_l1_test, encoding="utf-8")

    for relative_path, trigger_contract in (
        (
            "HealthTrackingAppUITests/OHPSafetyFlowUITests.swift",
            "An unanswered prior OHP response must fail closed before it is answered.",
        ),
        (
            "HealthTrackingAppUITests/PostureFlowUITests.swift",
            "The final symptom input must immediately publish the complete L2.",
        ),
    ):
        safety_ui_test = root / relative_path
        original_safety_ui_test = safety_ui_test.read_text(encoding="utf-8")
        safety_ui_test.write_text(
            original_safety_ui_test.replace(trigger_contract, "triggerCoverageWasRemoved"),
            encoding="utf-8",
        )
        run(root, trigger_contract)
        safety_ui_test.write_text(original_safety_ui_test, encoding="utf-8")

        safety_ui_test.write_text(
            original_safety_ui_test + "\nXCTAssertTrue(heading.hasFocus)\n",
            encoding="utf-8",
        )
        run(root, "must not claim focus through inactive or unverified VoiceOver state")
        safety_ui_test.write_text(original_safety_ui_test, encoding="utf-8")

        safety_ui_test.write_text(
            original_safety_ui_test.replace("expectedGeneralMessage", "messageWasNotCompared"),
            encoding="utf-8",
        )
        run(root, "expectedGeneralMessage")
        safety_ui_test.write_text(original_safety_ui_test, encoding="utf-8")

    posture_ui_test = root / "HealthTrackingAppUITests/PostureFlowUITests.swift"
    original_posture_ui_test = posture_ui_test.read_text(encoding="utf-8")
    posture_ui_test.write_text(
        original_posture_ui_test.replace(
            '.matching(identifier: "medical.disclaimer.l1")',
            '["medical.disclaimer.l1"]',
            1,
        ),
        encoding="utf-8",
    )
    run(root, '.matching(identifier: "medical.disclaimer.l1")')
    posture_ui_test.write_text(original_posture_ui_test, encoding="utf-8")

    posture_ui_test.write_text(
        original_posture_ui_test
        .replace("posture.entry.region", "__region__", 1)
        .replace("posture.entry.symptom", "posture.entry.region", 1)
        .replace("__region__", "posture.entry.symptom", 1),
        encoding="utf-8",
    )
    run(root, "must enter region/note first, make symptom the final trigger")
    posture_ui_test.write_text(original_posture_ui_test, encoding="utf-8")

    posture_ui_test.write_text(
        original_posture_ui_test.replace(
            "dismissKeyboardAfterTyping: false",
            "dismissKeyboardAfterTyping: true",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "dismissKeyboardAfterTyping: false")
    posture_ui_test.write_text(original_posture_ui_test, encoding="utf-8")

    posture_ui_test.write_text(
        original_posture_ui_test.replace(
            "dismissKeyboardAfterTyping: false",
            "dismissKeyboardAfterTyping: false\napp.buttons[\"other\"].tap()",
            1,
        ),
        encoding="utf-8",
    )
    run(root, "must perform no focus-stealing tap")
    posture_ui_test.write_text(original_posture_ui_test, encoding="utf-8")

    health_safety_source = root / "Packages/HealthTrackingModules/Sources/HealthSafetyKit/HealthSafetyKitModule.swift"
    original_health_safety_source = health_safety_source.read_text(encoding="utf-8")
    health_safety_source.write_text(
        "import MetricsKit\n" + original_health_safety_source,
        encoding="utf-8",
    )
    run(root, "must remain dependency-neutral")
    health_safety_source.write_text(original_health_safety_source, encoding="utf-8")

    health_safety_source.write_text(
        original_health_safety_source + "\nlet forbiddenSafetyDiagnosis = \\\"tanı\\\"\n",
        encoding="utf-8",
    )
    run(root, "M3.10 safety presentation must not diagnose")
    health_safety_source.write_text(original_health_safety_source, encoding="utf-8")

    health_safety_source.write_text(
        original_health_safety_source.replace(
            "sağlık profesyoneli tarafından değerlendirilmelidir.",
            "izlenmelidir.",
        ),
        encoding="utf-8",
    )
    run(root, "M3.10 required general/urgent safety copy is incomplete")
    health_safety_source.write_text(original_health_safety_source, encoding="utf-8")

    health_safety_source.write_text(
        original_health_safety_source.replace(
            r'+ "\(redFlagInformation)"',
            r'+ "\(redFlagInformation) Ek öneri."',
        ),
        encoding="utf-8",
    )
    run(root, "M3.10 generalStopMessage must match the complete exact Turkish safety copy")
    health_safety_source.write_text(original_health_safety_source, encoding="utf-8")

    health_safety_source.write_text(
        original_health_safety_source.replace(
            r'"Hareketi durdur. \(redFlagInformation)"',
            r'"Hareketi durdur. \(redFlagInformation) Ek öneri."',
        ),
        encoding="utf-8",
    )
    run(root, "M3.10 urgentMessage must match the complete exact Turkish safety copy")
    health_safety_source.write_text(original_health_safety_source, encoding="utf-8")

    health_safety_source.write_text(
        original_health_safety_source.replace(
            "Yeni veya belirgin şekilde kötüleşen",
            "Belirti olan",
        ),
        encoding="utf-8",
    )
    run(root, "M3.10 required general/urgent safety copy is incomplete")
    health_safety_source.write_text(original_health_safety_source, encoding="utf-8")

    health_safety_source.write_text(
        original_health_safety_source.replace(
            "requiresUrgentAssessment: true",
            "requiresUrgentAssessment: false",
        ),
        encoding="utf-8",
    )
    run(root, "M3.10 required general/urgent safety copy is incomplete")
    health_safety_source.write_text(original_health_safety_source, encoding="utf-8")

    training_mapper_source = root / "App/Application/TrainingSymptomMetricsAdapter.swift"
    original_training_mapper_source = training_mapper_source.read_text(encoding="utf-8")
    training_mapper_source.write_text(
        original_training_mapper_source.replace(
            ".missingSymptomAnswer",
            ".overheadPressSymptom",
        ),
        encoding="utf-8",
    )
    run(root, "M3.10 structured OHP safety mapping is incomplete")
    training_mapper_source.write_text(original_training_mapper_source, encoding="utf-8")

    motion_policy = (
        root
        / "Packages/HealthTrackingModules/Sources/DesignSystem/Motion/MedicalSafetyMotionPolicy.swift"
    )
    original_motion_policy = motion_policy.read_text(encoding="utf-8")
    motion_policy.write_text(
        original_motion_policy.replace(
            "guard !reduceMotion else { return identity }\nreturn opacity",
            "if reduceMotion { return identity }\nreturn opacity",
        ),
        encoding="utf-8",
    )
    run(root)
    motion_policy.write_text(original_motion_policy, encoding="utf-8")

    missing_consumer = (
        root
        / "Packages/HealthTrackingModules/Sources/TrainingKit/Session/OHPPriorSymptomQuestionView.swift"
    )
    original_missing_consumer = missing_consumer.read_text(encoding="utf-8")
    missing_consumer.unlink()
    run(root, "Missing required M3.10 L2 UI consumer")
    missing_consumer.write_text(original_missing_consumer, encoding="utf-8")

    for relative_path in (
        "Packages/HealthTrackingModules/Sources/MetricsKit/Posture/PostureEntryView.swift",
        "Packages/HealthTrackingModules/Sources/TrainingKit/Session/OHPPriorSymptomQuestionView.swift",
        "Packages/HealthTrackingModules/Sources/TrainingKit/Session/ExerciseStageView.swift",
    ):
        safety_ui_source = root / relative_path
        original_safety_ui_source = safety_ui_source.read_text(encoding="utf-8")
        safety_ui_source.write_text(
            original_safety_ui_source.replace(
                ".accessibilityFocused($levelTwoHeadingFocused)",
                ".focusBindingWasRemoved",
            ),
            encoding="utf-8",
        )
        run(root, "must provide stable L2 heading focus")
        safety_ui_source.write_text(original_safety_ui_source, encoding="utf-8")

        safety_ui_source.write_text(
            original_safety_ui_source.replace(
                ".onAppear",
                ".appearanceActivationWasRemoved",
            ),
            encoding="utf-8",
        )
        run(root, ".onAppear")
        safety_ui_source.write_text(original_safety_ui_source, encoding="utf-8")

        safety_ui_source.write_text(
            original_safety_ui_source.replace(
                ".onChange",
                ".changeActivationWasRemoved",
            ),
            encoding="utf-8",
        )
        run(root, ".onChange")
        safety_ui_source.write_text(original_safety_ui_source, encoding="utf-8")

        safety_ui_source.write_text(
            original_safety_ui_source.replace(
                "levelTwoHeadingFocused = MedicalSafetyFocusPolicy.headingFocused(\n"
                "isLevelTwoPresented: isPresented\n"
                ")",
                "levelTwoHeadingFocused = false",
            ),
            encoding="utf-8",
        )
        run(root, "must bind L2 appearance/removal to the tested MedicalSafetyFocusPolicy")
        safety_ui_source.write_text(original_safety_ui_source, encoding="utf-8")

        safety_ui_source.write_text(
            original_safety_ui_source.replace(
                "identity: .identity,\nopacity: .opacity",
                "identity: .opacity,\nopacity: .identity",
            ),
            encoding="utf-8",
        )
        run(root, "identity/opacity mapped correctly")
        safety_ui_source.write_text(original_safety_ui_source, encoding="utf-8")

    safety_ui_source = (
        root
        / "Packages/HealthTrackingModules/Sources/MetricsKit/Posture/PostureEntryView.swift"
    )
    original_safety_ui_source = safety_ui_source.read_text(encoding="utf-8")
    safety_ui_source.write_text(
        original_safety_ui_source + "\nlet unrelated = Color.clear.scaleEffect(2)\n",
        encoding="utf-8",
    )
    run(root)
    safety_ui_source.write_text(original_safety_ui_source, encoding="utf-8")

    for unsafe_transition, expected in (
        (".move(edge: .top)", "must not use move in levelTwoTransition"),
        (".slide", "must not use slide in levelTwoTransition"),
        (".scale", "must not use scale in levelTwoTransition"),
        (".scaleEffect(2)", "must not use scaleEffect in levelTwoTransition"),
        (".offset(x: 1)", "must not use offset in levelTwoTransition"),
        (".zoom", "must not use zoom in levelTwoTransition"),
        (".push(from: .top)", "must not use push in levelTwoTransition"),
    ):
        safety_ui_source.write_text(
            original_safety_ui_source.replace(
                "private var levelTwoTransition: AnyTransition {",
                "private var levelTwoTransition: AnyTransition {\n"
                f"let unsafe = {unsafe_transition}",
            ),
            encoding="utf-8",
        )
        run(root, expected)
        safety_ui_source.write_text(original_safety_ui_source, encoding="utf-8")

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
