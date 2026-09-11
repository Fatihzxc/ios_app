#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

python3 - "$repo_root" "${1:-}" <<'PY'
from __future__ import annotations

import re
import shlex
import shutil
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
mode = sys.argv[2]
EVIDENCE_REQUIRED = True
ACCEPTED_M312_SHA = "88ceee1a58db6f8447155996ae62194fa837a8fe"
ACCEPTED_M312_RUN = "33167202851"
EVIDENCE_RELATIVE = "docs/evidence/M3/acceptance.md"
EVIDENCE_TASKS = tuple(f"M3.{index}" for index in range(1, 13))
EVIDENCE_ARTIFACTS = (
    "9689212849",
    "9684192968",
    "9684190776",
)

RED_REQUIRED = {
    "docs/superpowers/plans/2026-08-27-m3.12-integration-acceptance.md": {
        "test-only RED commit amended to GREEN",
        "testTodayAndProgressExposeEveryM3TrackerEntryThroughOneLazyRouter",
        "testDeniedAndLimitedBroaderAccessKeepActualSystemPickerOperable",
        "Evidence-gate RED then GREEN",
        "Merge M3 to main",
    },
    "HealthTrackingAppUITests/M3AcceptanceUITests.swift": {
        "testTodayAndProgressExposeEveryM3TrackerEntryThroughOneLazyRouter",
        "testUS6AndUS8SummariesSurviveProgressSameDayEditAndRelaunch",
        'identified("progress.metrics.action", in: probe)',
        '"progress.lifestyle.action"',
        '"progress.posture.action"',
        '"progress.health-check.action"',
        '"progress.bloodwork.action"',
        '"progress.photos.action"',
        '"today.bloodwork.action"',
        '"m3.tracker-router.instantiation-count"',
        "assertRouterInstantiationCount(0, in: app)",
        "assertRouterInstantiationCount(1, in: app)",
        "assertExactlyOneProgressEntryActionPerTracker(in: probe)",
        'assertFixedNowEvidence("2026-08-27T10:00:00Z", in: app)',
        'identified("m3.fixed-now", in: app)',
        '"lifestyle.progress.sleep.summary"',
        '"lifestyle.progress.mood.summary"',
        'moodScore: "6"',
        'moodScore: "7"',
        '"-ui-test-now", "2026-08-27T10:00:00Z"',
        '"m3-acceptance-us6-progress-light"',
        '"m3-acceptance-us8-today-light"',
        "app.terminate()",
    },
    "HealthTrackingAppUITests/M3AccessibilityUITests.swift": {
        "testProgressHubLightDarkDefaultXXLAX3AX5Matrix",
        "testEveryMetricTextFieldExposesFiftyTwoPointInteractionGeometry",
        "testReduceMotionAndHighContrastTrackerRoutesRemainOperable",
        "testSmallPhoneAX5TrackerRoutesRemainOperable",
        "case `default`",
        "case xxl",
        "case ax3",
        "case ax5",
        '"-UIAccessibilityReduceMotionEnabled", "YES"',
        '"-UIAccessibilityDarkerSystemColorsEnabled", "YES"',
        'ProcessInfo.processInfo.environment["M3_SMALL_PHONE_GATE"] == "1"',
        "XCTAssertLessThanOrEqual(",
        '"m3-progress-\\(appearance.rawValue)-\\(textSize.rawValue)"',
        '"m3-progress-reduce-motion"',
        '"m3-progress-high-contrast"',
        '"m3-progress-small-ax5"',
        "element.frame.height + 0.01",
        "element.isHittable",
        "element.label.isEmpty",
        "for _ in 0..<24",
        "metricClose.isHittable",
        "metricClose.frame.midY",
        "app.frame.midY",
        'app.buttons["metrics.entry.close"]',
    },
    "HealthTrackingAppUITests/ProgressPhotoLifecycleUITests.swift": {
        "testDeniedAndLimitedBroaderAccessKeepActualSystemPickerOperable",
        'for accessState in ["denied", "limited"]',
        '"-ui-test-photo-library-access"',
        'identified("photos.picker", in: app)',
        "picker.isEnabled",
        "picker.value as? String",
        "accessState,",
        "The shipped picker must consume the exact injected broader-access state.",
        "picker.isHittable",
        "picker.frame.height + 0.01",
        '"m3-photo-local-lifecycle-light"',
    },
    "HealthTrackingAppUITests/ProgressPhotoGalleryUITests.swift": {
        '"m3-photo-gallery-light"',
        "XCTAttachment(screenshot:",
    },
    "scripts/test-ios.sh": {
        "--m312-red-only",
        '"$script_dir/verify-m3-acceptance.sh" --self-test',
        '"$script_dir/verify-m3-acceptance.sh" --red',
        '"$script_dir/verify-m3-acceptance.sh"',
        "HealthTrackingAppUITests/M3AcceptanceUITests/testTodayAndProgressExposeEveryM3TrackerEntryThroughOneLazyRouter",
    },
    ".github/workflows/ios.yml": {
        "Qualifying M3.12 integration RED",
        "scripts/test-ios.sh --m312-red-only",
        "Targeted M3.12 tracker acceptance tests",
        "scripts/test-ios.sh --only-testing HealthTrackingAppUITests/M3AcceptanceUITests",
        "Targeted M3.12 text-field touch-target regression",
        "scripts/test-ios.sh --only-testing HealthTrackingAppUITests/M3AccessibilityUITests",
        "Reset selected simulator before complete functional suite",
        'xcrun simctl erase "$simulator_udid"',
        "scripts/test-ios.sh --skip-testing HealthTrackingAppUITests/TodayGuidanceUITests/testColdLaunchPublishesFirstMeaningfulDirectiveWithinOneSecondMedian",
        "scripts/verify-m3-acceptance.sh --self-test",
        "scripts/verify-m3-acceptance.sh",
        '"M3AcceptanceUITests"',
        '"M3AccessibilityUITests"',
        '"ProgressPhotoLifecycleUITests"',
        '"ProgressPhotoGalleryUITests"',
        '"m3-acceptance-us6-progress-light"',
        '"m3-acceptance-us8-today-light"',
        '"m3-progress-small-ax5"',
        'M3_SMALL_PHONE_GATE: "1"',
        "testSmallPhoneAX5TrackerRoutesRemainOperable",
    },
    "project.yml": {
        "HealthTrackingApp-Local:",
        'M3_SMALL_PHONE_GATE: "$(M3_SMALL_PHONE_GATE)"',
        "HealthTrackingAppUITests",
    },
}

PRODUCTION_REQUIRED = {
    "HealthTrackingAppTests/TrackerCompositionTests.swift": {
        "testUITestPhotoLibraryAccessStateParsesDeniedAndLimitedAndRejectsAmbiguity",
        "configuration?.broaderPhotoLibraryAccessState.rawValue",
        "configuration?.fixedNow",
        '"-ui-test-photo-library-access", "denied"',
        '"-ui-test-photo-library-access", "limited"',
        '"-ui-test-photo-library-access", "unsupported"',
    },
    "App/Application/TrackerFeatureRouting.swift": {
        "onOpenBodyMetric",
        "onOpenLifestyle",
        "onOpenPosture",
        "onOpenHealthChecks",
        "onOpenBloodwork",
        "onOpenProgressPhotos",
    },
    "App/Application/TrackerFeatureBundle.swift": {
        "ProgressTrackerQuickActions",
        'accessibilityIdentifier("progress.metrics.action")',
        'accessibilityIdentifier("progress.lifestyle.action")',
        'accessibilityIdentifier("progress.posture.action")',
        'accessibilityIdentifier("progress.health-check.action")',
        'accessibilityIdentifier("progress.bloodwork.action")',
        'accessibilityIdentifier("progress.photos.action")',
        "onOpenBodyMetric: onOpenBodyMetric",
        "onOpenLifestyle: onOpenLifestyle",
        "onOpenPosture: onOpenPosture",
        "onOpenHealthChecks: onOpenHealthChecks",
        "broaderPhotoLibraryAccessState",
    },
    "App/Application/AppRootView.swift": {
        "performTodayBloodworkAction",
        "onOpenBloodwork: performTodayBloodworkAction",
        "onOpenBodyMetric: { trackerEntryRoute = .bodyMetric }",
        "onOpenLifestyle: { trackerEntryRoute = .lifestyle }",
        "onOpenPosture: { trackerEntryRoute = .posture }",
        "onOpenHealthChecks: { trackerEntryRoute = .healthChecks }",
        '"m3.tracker-router.instantiation-count"',
        "trackerFeatureRouterInstantiationCount()",
        'accessibilityIdentifier("m3.fixed-now")',
        "ISO8601DateFormatter().string(from: AppDomainContext.now())",
    },
    "App/Application/AppBootstrapView.swift": {
        "trackerFeatureRouterInstantiationCount:",
        "dependencies.trackerFeatureRouterInstantiationCount",
    },
    "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift": {
        "onOpenBloodwork",
        'accessibilityIdentifier("today.bloodwork.action")',
        'text("today.bloodwork.action")',
        'text("today.bloodwork.action.hint")',
    },
    "Packages/HealthTrackingModules/Sources/TrainingKit/Resources/Localizable.xcstrings": {
        '"today.bloodwork.action"',
        '"today.bloodwork.action.hint"',
        '"Kan sonuçlarını aç"',
    },
    "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricEntryView.swift": {
        "@Environment(\\.dynamicTypeSize) private var dynamicTypeSize",
        "metricEntryTouchTarget",
        "shouldOfferDraftClose",
        "shouldOfferSecondaryDraftClose",
        "shouldOfferToolbarDraftClose",
        'return localized("metrics.entry.close")',
        'return "metrics.entry.close"',
        "ToolbarItem(placement: .cancellationAction)",
        'Button(localized("metrics.entry.close"), action: onClose)',
        '.accessibilityIdentifier("metrics.entry.close")',
        "onClose()",
    },
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleEntryView.swift": {
        "draftCloseTitle",
        'localized("lifestyle.entry.close")',
        '"lifestyle.entry.close"',
        "onClose()",
    },
    "App/Resources/Localizable.xcstrings": {
        '"progress.quick-actions.heading"',
        '"progress.metrics.action"',
        '"progress.lifestyle.action"',
        '"progress.posture.action"',
        '"progress.health-check.action"',
        '"progress.bloodwork.action"',
        '"progress.photos.action"',
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/SystemPhotosPickerView.swift": {
        "private let accessState: PhotoLibraryAccessState",
        "accessState: PhotoLibraryAccessState = .authorized",
        ".disabled(!SystemPhotoPickerAvailability.isEnabled(for: accessState))",
    },
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoLifecycleView.swift": {
        "broaderPhotoLibraryAccessState: PhotoLibraryAccessState = .authorized",
        "accessState: broaderPhotoLibraryAccessState",
    },
    "App/Support/AppUITestLaunchConfiguration.swift": {
        'photoLibraryAccessFlag = "-ui-test-photo-library-access"',
        'fixedNowFlag = "-ui-test-now"',
        "let broaderPhotoLibraryAccessState: PhotoLibraryAccessState",
        "PhotoLibraryAccessState(rawValue:",
        "let fixedNow: Date?",
        "ISO8601DateFormatter().date(from:",
    },
    "App/Application/AppDomainContext.swift": {
        "configuration.fixedNow",
        "return fixedNow",
    },
    "App/Application/AppDependencies.swift": {
        "installM3HealthChecks",
        "AppDomainContext.now()",
    },
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleProgressSection.swift": {
        'identifier: "lifestyle.progress.sleep.summary"',
        'identifier: "lifestyle.progress.mood.summary"',
        ".accessibilityValue(lines.joined(separator:",
    },
}

PRIVACY_ROOTS = (
    "App",
    "Packages/HealthTrackingModules/Sources/MetricsKit",
    "Packages/HealthTrackingModules/Sources/SleepMoodKit",
    "Packages/HealthTrackingModules/Sources/HealthChecksKit",
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit",
    "Packages/HealthTrackingModules/Sources/NotificationsKit",
    "Packages/HealthTrackingModules/Sources/HealthSafetyKit",
    "Packages/HealthTrackingModules/Sources/TrainingKit",
    "Packages/HealthTrackingModules/Sources/PersistenceKit",
)
PRIVACY_APP_FILES: tuple[str, ...] = ()
FORBIDDEN_PRIVACY = re.compile(
    r"\b(?:Logger|os_log|print|debugPrint|NSLog|analytics|telemetry)\b",
    re.IGNORECASE,
)

PRODUCTION_SELF_TEST_FILES = {
    "HealthTrackingAppTests/TrackerCompositionTests.swift": """
func testUITestPhotoLibraryAccessStateParsesDeniedAndLimitedAndRejectsAmbiguity() {
    let configuration: FixtureConfiguration? = nil
    _ = configuration?.broaderPhotoLibraryAccessState.rawValue
    _ = configuration?.fixedNow
    _ = ["-ui-test-photo-library-access", "denied"]
    _ = ["-ui-test-photo-library-access", "limited"]
    _ = ["-ui-test-photo-library-access", "unsupported"]
}
""",
    "App/Application/TrackerFeatureRouting.swift": """
protocol TrackerFeatureRoutingFixture {
    func route(
        onOpenBodyMetric: () -> Void,
        onOpenLifestyle: () -> Void,
        onOpenPosture: () -> Void,
        onOpenHealthChecks: () -> Void,
        onOpenBloodwork: () -> Void,
        onOpenProgressPhotos: () -> Void
    )
}
""",
    "App/Application/TrackerFeatureBundle.swift": """
func makeProgressView(
    onOpenBodyMetric: () -> Void,
    onOpenLifestyle: () -> Void,
    onOpenPosture: () -> Void,
    onOpenHealthChecks: () -> Void,
    onOpenBloodwork: () -> Void,
    onOpenProgressPhotos: () -> Void
) {
    ProgressTrackerQuickActions(
        onOpenBodyMetric: onOpenBodyMetric,
        onOpenLifestyle: onOpenLifestyle,
        onOpenPosture: onOpenPosture,
        onOpenHealthChecks: onOpenHealthChecks,
        onOpenBloodwork: onOpenBloodwork,
        onOpenProgressPhotos: onOpenProgressPhotos
    )
    accessibilityIdentifier("progress.metrics.action")
    accessibilityIdentifier("progress.lifestyle.action")
    accessibilityIdentifier("progress.posture.action")
    accessibilityIdentifier("progress.health-check.action")
    accessibilityIdentifier("progress.bloodwork.action")
    accessibilityIdentifier("progress.photos.action")
    let broaderPhotoLibraryAccessState = "authorized"
    _ = broaderPhotoLibraryAccessState
}

func makePhotoFixture(scenario: AppUITestScenario) {
    if scenario == .m3ProgressPhotos {
        TrackerFeatureBundle(
            broaderPhotoLibraryAccessState:
                AppUITestLaunchConfiguration.resolve()?
                    .broaderPhotoLibraryAccessState ?? .authorized
        )
    }
}
""",
    "App/Application/AppRootView.swift": """
struct RootFixture {
var body: some View {
    Text(ISO8601DateFormatter().string(from: AppDomainContext.now()))
        .accessibilityIdentifier("m3.fixed-now")
        .accessibilityIdentifier("m3.tracker-router.instantiation-count")
        .accessibilityValue(String(trackerFeatureRouterInstantiationCount()))
        .onAppear {
            performTodayBloodworkAction()
            route(onOpenBloodwork: performTodayBloodworkAction)
            route(onOpenBodyMetric: { trackerEntryRoute = .bodyMetric })
            route(onOpenLifestyle: { trackerEntryRoute = .lifestyle })
            route(onOpenPosture: { trackerEntryRoute = .posture })
            route(onOpenHealthChecks: { trackerEntryRoute = .healthChecks })
        }
}
}
""",
    "App/Application/AppBootstrapView.swift": """
func composeBootstrap() {
    root(
        trackerFeatureRouterInstantiationCount:
            dependencies.trackerFeatureRouterInstantiationCount
    )
}
""",
    "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift": """
func todayFixture(onOpenBloodwork: () -> Void) {
    onOpenBloodwork()
    accessibilityIdentifier("today.bloodwork.action")
    _ = text("today.bloodwork.action")
    _ = text("today.bloodwork.action.hint")
}
""",
    "Packages/HealthTrackingModules/Sources/TrainingKit/Resources/Localizable.xcstrings": """
{"strings":{"today.bloodwork.action":{"value":"Kan sonuçlarını aç"},"today.bloodwork.action.hint":{}}}
""",
    "App/Resources/Localizable.xcstrings": """
{"strings":{"progress.quick-actions.heading":{},"progress.metrics.action":{},"progress.lifestyle.action":{},"progress.posture.action":{},"progress.health-check.action":{},"progress.bloodwork.action":{},"progress.photos.action":{}}}
""",
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/SystemPhotosPickerView.swift": """
struct PickerFixture {
    private let accessState: PhotoLibraryAccessState

    init(accessState: PhotoLibraryAccessState = .authorized) {
        self.accessState = accessState
    }

    public var body: some View {
        PhotosPicker()
            .accessibilityIdentifier("photos.picker")
            .disabled(!SystemPhotoPickerAvailability.isEnabled(for: accessState))
            .photoLibraryAccessEvidence(accessState)
    }
}
""",
    "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoLifecycleView.swift": """
func lifecycle(
    broaderPhotoLibraryAccessState: PhotoLibraryAccessState = .authorized
) {
    picker(accessState: broaderPhotoLibraryAccessState)
}
""",
    "App/Support/AppUITestLaunchConfiguration.swift": """
struct LaunchFixture {
    static let photoLibraryAccessFlag = "-ui-test-photo-library-access"
    static let fixedNowFlag = "-ui-test-now"

    static func resolve(arguments: [String]) -> Self? {
        let broaderPhotoLibraryAccessState: PhotoLibraryAccessState
        _ = PhotoLibraryAccessState(rawValue: arguments.first ?? "")
        let fixedNow: Date?
        _ = ISO8601DateFormatter().date(from: arguments.last ?? "")
        return Self(
            broaderPhotoLibraryAccessState: broaderPhotoLibraryAccessState,
            fixedNow: fixedNow
        )
    }
}
""",
    "App/Application/AppDomainContext.swift": """
func now(configuration: LaunchFixture) -> Date {
    if let fixedNow = configuration.fixedNow {
        return fixedNow
    }
    return Date()
}
""",
    "App/Application/AppDependencies.swift": """
private static func installM3HealthChecks(in modelContext: ModelContext) throws {
    let now = AppDomainContext.now()
    reminder.dueDate = now.addingTimeInterval(-60)
    reminder.updatedAt = now
}
""",
    "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/BodyMetricEntryView.swift": """
import SwiftUI
@MainActor
public struct BodyMetricEntryView: View {
@Environment(\\.dynamicTypeSize) private var dynamicTypeSize
public init() {}
public var body: some View {
    NavigationStack {
        QuickEntryFormScaffold { focus in
            VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    TextField(
                        localized("metrics.entry.custom.name"),
                        text: $customName
                    )
                    .textFieldStyle(.roundedBorder)
                    .metricEntryTouchTarget()
                    .focused(focus)
                    .accessibilityLabel(localized("metrics.entry.custom.name"))
                    .accessibilityIdentifier("metrics.entry.custom.name")
                    TextField(
                        localized("metrics.entry.custom.value"),
                        text: $customValueText
                    )
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .metricEntryTouchTarget()
                    .focused(focus)
                    .accessibilityLabel(localized("metrics.entry.custom.value"))
                    .accessibilityIdentifier("metrics.entry.custom.value")
                    TextField(
                        localized("metrics.entry.custom.unit"),
                        text: $customUnit
                    )
                    .textFieldStyle(.roundedBorder)
                    .metricEntryTouchTarget()
                    .focused(focus)
                    .accessibilityLabel(localized("metrics.entry.custom.unit"))
                    .accessibilityIdentifier("metrics.entry.custom.unit")
                }
                statePresentation
            }
        }
        .toolbar {
            if shouldOfferToolbarDraftClose {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("metrics.entry.close"), action: onClose)
                        .accessibilityIdentifier("metrics.entry.close")
                }
            }
        }
    }
    .interactiveDismissDisabled(isSaving)
    .task {
        prepareOnce()
    }
}
private func metricField(
    title: String,
    unit: String,
    text: Binding<String>,
    identifier: String,
    focus: FocusState<Bool>.Binding
) -> some View {
    VStack(alignment: .leading, spacing: AppSpacing.small) {
        HStack {
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .metricEntryTouchTarget()
                .focused(focus)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
            Text(unit)
                .accessibilityHidden(true)
        }
    }
}
private var shouldOfferDraftClose: Bool { !isSaving && !isSaved }
private var shouldOfferSecondaryDraftClose: Bool {
    shouldOfferDraftClose && !dynamicTypeSize.isAccessibilitySize
}
private var shouldOfferToolbarDraftClose: Bool {
    shouldOfferDraftClose && dynamicTypeSize.isAccessibilitySize
}
private var secondaryTitle: String? {
    if shouldOfferSecondaryDraftClose { return localized("metrics.entry.close") }
    return nil
}
private var secondaryIdentifier: String? {
    if shouldOfferSecondaryDraftClose { return "metrics.entry.close" }
    return nil
}
private var secondaryAction: (() -> Void)? {
    guard shouldOfferSecondaryDraftClose else { return nil }
    return { onClose() }
}
}
private extension View {
    func metricEntryTouchTarget() -> some View {
        frame(minHeight: 52)
            .contentShape(.interaction, Rectangle())
    }
}
""",
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleEntryView.swift": """
QuickEntryFormScaffold(
    secondaryActionTitle: draftCloseTitle,
    secondaryActionAccessibilityLabel: draftCloseTitle,
    secondaryActionAccessibilityIdentifier: draftCloseIdentifier,
    secondaryAction: draftCloseAction
)
private var draftCloseTitle: String? {
    guard !isSaving, !isSaved else { return nil }
    return localized("lifestyle.entry.close")
}
private var draftCloseIdentifier: String? {
    draftCloseTitle == nil ? nil : "lifestyle.entry.close"
}
private var draftCloseAction: (() -> Void)? {
    guard draftCloseTitle != nil else { return nil }
    return { onClose() }
}
""",
    "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleProgressSection.swift": """
func lifestyleFixture() {
    summaryCard(identifier: "lifestyle.progress.sleep.summary")
    summaryCard(identifier: "lifestyle.progress.mood.summary")
}

private func summaryCard(identifier: String, lines: [String] = []) {
    card()
        .accessibilityValue(lines.joined(separator: ", "))
        .accessibilityIdentifier(identifier)
}
""",
}


def active_source(text: str, comment_style: str = "swift") -> str:
    if comment_style == "swift":
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    active_lines: list[str] = []
    for line in text.splitlines():
        stripped = line.lstrip()
        if comment_style == "swift" and stripped.startswith("//"):
            continue
        if comment_style == "hash" and stripped.startswith("#"):
            continue
        if comment_style == "swift" and "//" in line:
            line = line.split("//", 1)[0]
        active_lines.append(line)
    return "\n".join(active_lines)


def source_without_string_literals(text: str) -> str:
    result: list[str] = []
    in_string = False
    escaped = False
    for character in text:
        if in_string:
            if character == "\n":
                result.append(character)
            else:
                result.append(" ")
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
            result.append(" ")
        else:
            result.append(character)
    return "".join(result)


def swift_code_only(text: str, mask_literals: bool = True) -> str:
    result = (
        ["\n" if character == "\n" else " " for character in text]
        if mask_literals
        else list(text)
    )

    def mask_comment(start: int, end: int) -> None:
        if mask_literals:
            return
        for position in range(start, end):
            result[position] = "\n" if text[position] == "\n" else " "

    def string_start(index: int) -> tuple[int, str] | None:
        cursor = index
        while cursor < len(text) and text[cursor] == "#":
            cursor += 1
        hashes = cursor - index
        if text.startswith('"""', cursor):
            return hashes, '"""'
        if cursor < len(text) and text[cursor] == '"':
            return hashes, '"'
        return None

    def regex_start(index: int) -> int | None:
        cursor = index
        while cursor < len(text) and text[cursor] == "#":
            cursor += 1
        hashes = cursor - index
        if cursor >= len(text) or text[cursor] != "/":
            return None
        if text.startswith("//", cursor) or text.startswith("/*", cursor):
            return None
        if hashes > 0:
            return hashes
        previous = index - 1
        while previous >= 0 and text[previous].isspace():
            previous -= 1
        if previous < 0 or text[previous] in "=([{,:;!?":
            return 0
        prefix = text[:index]
        if re.search(r"\b(?:return|case)\s*$", prefix):
            return 0
        return None

    def parse_block_comment(index: int) -> int:
        depth = 1
        index += 2
        while index < len(text) and depth:
            if text.startswith("/*", index):
                depth += 1
                index += 2
            elif text.startswith("*/", index):
                depth -= 1
                index += 2
            else:
                index += 1
        return index

    def parse_string(index: int, hashes: int, quote: str) -> int:
        opening_length = hashes + len(quote)
        index += opening_length
        closing = quote + ("#" * hashes)
        interpolation = "\\" + ("#" * hashes) + "("
        while index < len(text):
            if text.startswith(closing, index):
                return index + len(closing)
            if text.startswith(interpolation, index):
                index = parse_code(index + len(interpolation), parenthesis_depth=1)
                continue
            if hashes == 0 and text[index] == "\\":
                index = min(index + 2, len(text))
            else:
                index += 1
        return index

    def parse_regex(index: int, hashes: int) -> int:
        index += hashes + 1
        closing = "/" + ("#" * hashes)
        interpolation = "\\" + ("#" * hashes) + "("
        while index < len(text):
            if text.startswith(closing, index):
                return index + len(closing)
            if text.startswith(interpolation, index):
                index = parse_code(index + len(interpolation), parenthesis_depth=1)
                continue
            if hashes == 0 and text[index] == "\\":
                index = min(index + 2, len(text))
            else:
                index += 1
        return index

    def parse_code(index: int, parenthesis_depth: int | None = None) -> int:
        while index < len(text):
            if text.startswith("//", index):
                comment_start = index
                newline = text.find("\n", index + 2)
                index = len(text) if newline < 0 else newline + 1
                mask_comment(comment_start, index)
                continue
            if text.startswith("/*", index):
                comment_start = index
                index = parse_block_comment(index)
                mask_comment(comment_start, index)
                continue
            start = string_start(index)
            if start is not None:
                index = parse_string(index, *start)
                continue
            regex_hashes = regex_start(index)
            if regex_hashes is not None:
                index = parse_regex(index, regex_hashes)
                continue

            character = text[index]
            if parenthesis_depth is not None:
                if character == "(":
                    parenthesis_depth += 1
                elif character == ")":
                    parenthesis_depth -= 1
                    if parenthesis_depth == 0:
                        return index + 1
            result[index] = character
            index += 1
        return index

    parse_code(0)
    return "".join(result)


def require_tokens(target_root: Path, contracts: dict[str, set[str]], label: str) -> None:
    for relative, tokens in contracts.items():
        path = target_root / relative
        if not path.is_file():
            raise ValueError(f"Missing {label} file: {relative}")
        if path.suffix == ".swift":
            comment_style = "swift"
        elif path.suffix in {".sh", ".yml", ".yaml"}:
            comment_style = "hash"
        else:
            comment_style = "none"
        text = active_source(
            path.read_text(encoding="utf-8"),
            comment_style=comment_style,
        )
        missing = sorted(token for token in tokens if token not in text)
        if missing:
            raise ValueError(
                f"{relative} is missing {label} contracts: {', '.join(missing)}"
            )


def braced_scope(text: str, anchor: str, label: str) -> str:
    active = active_source(text, comment_style="swift")
    start = active.find(anchor)
    if start < 0:
        raise ValueError(f"Missing scoped {label}: {anchor}")
    opening = active.find("{", start + len(anchor))
    if opening < 0:
        raise ValueError(f"Missing opening brace for scoped {label}: {anchor}")
    depth = 0
    in_string = False
    escaped = False
    for index in range(opening, len(active)):
        character = active[index]
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
        elif character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return active[opening + 1:index]
    raise ValueError(f"Unclosed scoped {label}: {anchor}")


def swift_braced_scope(text: str, anchor: str, label: str) -> str:
    code = swift_code_only(text)
    start = code.find(anchor)
    if start < 0:
        raise ValueError(f"Missing scoped {label}: {anchor}")
    opening = code.find("{", start + len(anchor))
    if opening < 0:
        raise ValueError(f"Missing opening brace for scoped {label}: {anchor}")
    end = balanced_delimiter_end(code, opening, "{", "}", label)
    return text[opening + 1:end - 1]


def balanced_delimiter_end(
    code: str,
    opening_index: int,
    opening: str,
    closing: str,
    label: str,
) -> int:
    if opening_index >= len(code) or code[opening_index] != opening:
        raise ValueError(f"Missing opening {opening!r} for {label}")
    depth = 0
    for index in range(opening_index, len(code)):
        if code[index] == opening:
            depth += 1
        elif code[index] == closing:
            depth -= 1
            if depth == 0:
                return index + 1
    raise ValueError(f"Unclosed {opening!r} for {label}")


def swift_array_initializer(
    text: str,
    declaration_pattern: str,
    label: str,
    following_statement_pattern: str,
) -> str:
    code = swift_code_only(text)
    declarations = list(re.finditer(declaration_pattern, code, flags=re.MULTILINE))
    if len(declarations) != 1:
        raise ValueError(f"{label} must have exactly one active initializer")

    cursor = declarations[0].end()
    while cursor < len(code) and code[cursor].isspace():
        cursor += 1
    if cursor >= len(code) or code[cursor] != "=":
        raise ValueError(f"{label} is missing its direct assignment")
    cursor += 1
    while cursor < len(code) and code[cursor].isspace():
        cursor += 1
    if cursor >= len(code) or code[cursor] != "[":
        raise ValueError(f"{label} must use a direct array literal")

    opening = cursor
    end = balanced_delimiter_end(code, opening, "[", "]", label)
    if re.match(
        rf"\s*(?:{following_statement_pattern})",
        code[end:],
        flags=re.MULTILINE,
    ) is None:
        raise ValueError(f"{label} must end after its direct array literal")
    return text[opening + 1:end - 1]


def swift_view_modifier_arguments(
    text: str,
    view_name: str,
    label: str,
) -> tuple[list[tuple[str, str]], str]:
    code = swift_code_only(text)
    match = re.search(rf"\b{re.escape(view_name)}\s*\(", code)
    if match is None or code[:match.start()].strip():
        raise ValueError(f"{label} must directly render {view_name}")

    opening = code.find("(", match.start())
    cursor = balanced_delimiter_end(code, opening, "(", ")", label)

    def skip_whitespace(index: int) -> int:
        while index < len(code) and code[index].isspace():
            index += 1
        return index

    cursor = skip_whitespace(cursor)
    if cursor < len(code) and code[cursor] == "{":
        cursor = balanced_delimiter_end(code, cursor, "{", "}", label)

    modifiers: list[tuple[str, str]] = []
    while True:
        cursor = skip_whitespace(cursor)
        if cursor >= len(code) or code[cursor] != ".":
            break
        name_match = re.match(r"\.([A-Za-z_][A-Za-z0-9_]*)", code[cursor:])
        if name_match is None:
            break
        name = name_match.group(1)
        cursor += name_match.end()
        cursor = skip_whitespace(cursor)
        arguments = ""
        if cursor < len(code) and code[cursor] == "(":
            end = balanced_delimiter_end(
                code,
                cursor,
                "(",
                ")",
                f"{label} .{name} modifier",
            )
            arguments = text[cursor + 1:end - 1]
            cursor = end
        cursor = skip_whitespace(cursor)
        while cursor < len(code) and code[cursor] == "{":
            cursor = balanced_delimiter_end(
                code,
                cursor,
                "{",
                "}",
                f"{label} .{name} trailing closure",
            )
            cursor = skip_whitespace(cursor)
        modifiers.append((name, arguments))
    return modifiers, code[cursor:]


def swift_view_modifier_chains(
    text: str,
    view_name: str,
    label: str,
) -> list[
    tuple[
        str,
        list[tuple[str, str]],
        str,
        tuple[int, int, int],
        tuple[str, ...],
        tuple[tuple[str, str], ...],
        str,
    ]
]:
    code = swift_code_only(text)
    matches = list(re.finditer(rf"\b{re.escape(view_name)}\s*\(", code))
    chains: list[
        tuple[
            str,
            list[tuple[str, str]],
            str,
            tuple[int, int, int],
            tuple[str, ...],
            tuple[tuple[str, str], ...],
            str,
        ]
    ] = []

    def skip_whitespace(index: int) -> int:
        while index < len(code) and code[index].isspace():
            index += 1
        return index

    def postfix_modifier_chain(
        index: int,
        context_label: str,
    ) -> tuple[str, str]:
        cursor = skip_whitespace(index)
        start = cursor
        while cursor < len(code) and code[cursor] == ".":
            name_match = re.match(r"\.([A-Za-z_][A-Za-z0-9_]*)", code[cursor:])
            if name_match is None:
                raise ValueError(
                    f"{context_label} contains an unparsed Swift modifier"
                )
            name = name_match.group(1)
            cursor += name_match.end()
            if (
                cursor < len(code)
                and not code[cursor].isspace()
                and code[cursor] not in "({."
            ):
                raise ValueError(
                    f"{context_label} contains an unparsed Swift modifier"
                )
            cursor = skip_whitespace(cursor)
            if cursor < len(code) and code[cursor] == "(":
                cursor = balanced_delimiter_end(
                    code,
                    cursor,
                    "(",
                    ")",
                    f"{context_label} .{name} modifier",
                )
                cursor = skip_whitespace(cursor)
            while cursor < len(code) and code[cursor] == "{":
                cursor = balanced_delimiter_end(
                    code,
                    cursor,
                    "{",
                    "}",
                    f"{context_label} .{name} trailing closure",
                )
                cursor = skip_whitespace(cursor)
        return text[start:cursor], code[cursor:cursor + 1]

    for chain_index, match in enumerate(matches):
        chain_label = f"{label} chain {chain_index + 1}"
        line_start = code.rfind("\n", 0, match.start()) + 1
        line_prefix = code[line_start:match.start()]
        brace_stack: list[int] = []
        parenthesis_stack: list[int] = []
        bracket_stack: list[int] = []
        for position, character in enumerate(code[:match.start()]):
            if character == "{":
                brace_stack.append(position)
            elif character == "}" and brace_stack:
                brace_stack.pop()
            elif character == "(":
                parenthesis_stack.append(position)
            elif character == ")" and parenthesis_stack:
                parenthesis_stack.pop()
            elif character == "[":
                bracket_stack.append(position)
            elif character == "]" and bracket_stack:
                bracket_stack.pop()
        if not brace_stack:
            raise ValueError(f"{chain_label} must be inside a ViewBuilder closure")
        enclosing_headers: list[str] = []
        ancestor_expressions: list[tuple[str, str]] = []
        for ancestor_index, enclosing_opening in enumerate(brace_stack, start=1):
            enclosing_line_start = code.rfind("\n", 0, enclosing_opening) + 1
            enclosing_headers.append(
                code[enclosing_line_start:enclosing_opening]
            )
            enclosing_end = balanced_delimiter_end(
                code,
                enclosing_opening,
                "{",
                "}",
                f"{chain_label} ancestor {ancestor_index}",
            )
            ancestor_expressions.append(
                postfix_modifier_chain(
                    enclosing_end,
                    f"{chain_label} ancestor {ancestor_index}",
                )
            )
        nesting = (
            len(brace_stack),
            len(parenthesis_stack),
            len(bracket_stack),
        )
        opening = code.find("(", match.start())
        invocation_end = balanced_delimiter_end(
            code,
            opening,
            "(",
            ")",
            chain_label,
        )
        invocation_arguments = text[opening + 1:invocation_end - 1]
        cursor = invocation_end
        cursor = skip_whitespace(cursor)
        if cursor < len(code) and code[cursor] == "{":
            cursor = balanced_delimiter_end(code, cursor, "{", "}", chain_label)

        modifiers: list[tuple[str, str]] = []
        while True:
            cursor = skip_whitespace(cursor)
            if cursor >= len(code) or code[cursor] != ".":
                break
            name_match = re.match(r"\.([A-Za-z_][A-Za-z0-9_]*)", code[cursor:])
            if name_match is None:
                raise ValueError(
                    f"{chain_label} contains an unparsed Swift modifier"
                )
            name = name_match.group(1)
            cursor += name_match.end()
            cursor = skip_whitespace(cursor)
            arguments = ""
            if cursor < len(code) and code[cursor] == "(":
                end = balanced_delimiter_end(
                    code,
                    cursor,
                    "(",
                    ")",
                    f"{chain_label} .{name} modifier",
                )
                arguments = text[cursor + 1:end - 1]
                cursor = end
            cursor = skip_whitespace(cursor)
            while cursor < len(code) and code[cursor] == "{":
                cursor = balanced_delimiter_end(
                    code,
                    cursor,
                    "{",
                    "}",
                    f"{chain_label} .{name} trailing closure",
                )
                cursor = skip_whitespace(cursor)
            modifiers.append((name, arguments))
        if cursor < len(code) and code[cursor] in {")", "]", ","}:
            raise ValueError(
                f"{chain_label} must be a direct, unenclosed View expression"
            )
        chains.append(
            (
                invocation_arguments,
                modifiers,
                line_prefix,
                nesting,
                tuple(enclosing_headers),
                tuple(ancestor_expressions),
                code[cursor:cursor + 1],
            )
        )
    return chains


def require_scoped_tokens(
    target_root: Path,
    relative: str,
    anchor: str,
    tokens: set[str],
    label: str,
    reject_early_return: bool = False,
) -> None:
    path = target_root / relative
    if not path.is_file():
        raise ValueError(f"Missing scoped {label} file: {relative}")
    scope = braced_scope(path.read_text(encoding="utf-8"), anchor, label)
    missing = sorted(token for token in tokens if token not in scope)
    if missing:
        raise ValueError(
            f"{relative} scoped {label} is missing: {', '.join(missing)}"
        )
    if reject_early_return and re.search(
        r"\breturn\b|\bXCTSkip(?:If|Unless)?\b",
        source_without_string_literals(scope),
    ):
        raise ValueError(
            f"{relative} scoped {label} exits before assertions via a return path or skip"
        )


def require_ordered_swift_code_tokens(
    target_root: Path,
    relative: str,
    anchor: str,
    tokens: list[str],
    label: str,
    forbidden_pattern: str | None = None,
) -> str:
    path = target_root / relative
    if not path.is_file():
        raise ValueError(f"Missing scoped {label} file: {relative}")
    scope = braced_scope(path.read_text(encoding="utf-8"), anchor, label)
    code = swift_code_only(scope)
    cursor = 0
    for token in tokens:
        position = code.find(token, cursor)
        if position < 0:
            raise ValueError(f"{relative} scoped {label} is missing ordered code: {token}")
        cursor = position + len(token)
    if forbidden_pattern and re.search(forbidden_pattern, code):
        raise ValueError(f"{relative} scoped {label} contains a bypass control path")
    return code


def workflow_step(text: str, name: str, indent: int = 6) -> str:
    active = active_source(text, comment_style="hash")
    prefix = " " * indent
    matches = list(re.finditer(
        rf"^{re.escape(prefix)}- name:\s*{re.escape(name)}\s*$",
        active,
        flags=re.MULTILINE,
    ))
    if len(matches) != 1:
        raise ValueError(
            f"Workflow scope must contain exactly one active named step {name!r}; "
            f"found {len(matches)}"
    )
    match = matches[0]
    following = active[match.end():]
    next_step = re.search(
        rf"^{re.escape(prefix)}- name:\s*",
        following,
        re.MULTILINE,
    )
    return following[:next_step.start()] if next_step else following


def yaml_key_pattern(key: str) -> str:
    escaped = re.escape(key)
    return rf'(?:{escaped}|"{escaped}"|\'{escaped}\')'


def require_canonical_workflow_mapping_keys(text: str, label: str) -> None:
    active = active_source(text, comment_style="hash")
    populated_lines = [line for line in active.splitlines() if line.strip()]
    if not populated_lines:
        raise ValueError(f"{label} must contain workflow mapping keys")
    mapping_indent = min(
        len(line) - len(line.lstrip(" ")) for line in populated_lines
    )
    for line in populated_lines:
        indentation = len(line) - len(line.lstrip(" "))
        if indentation != mapping_indent:
            continue
        mapping_entry = line[mapping_indent:]
        if re.fullmatch(
            r"[A-Za-z][A-Za-z0-9_-]*[ ]*:[^\r\n]*",
            mapping_entry,
        ) is None:
            raise ValueError(
                f"{label} must use canonical unquoted workflow keys"
            )


def require_unconditional_workflow_step(step: str, label: str) -> None:
    if_key = yaml_key_pattern("if")
    continue_key = yaml_key_pattern("continue-on-error")
    if re.search(rf"^[ ]*{if_key}[ ]*:", step, flags=re.MULTILINE):
        raise ValueError(f"{label} must run unconditionally")
    shell_key = yaml_key_pattern("shell")
    if re.search(rf"^[ ]*{shell_key}[ ]*:", step, flags=re.MULTILINE):
        raise ValueError(f"{label} must not override its execution shell")
    for match in re.finditer(
        rf"^[ ]*{continue_key}[ ]*:[ ]*([^\r\n]*?)[ ]*$",
        step,
        flags=re.MULTILINE,
    ):
        if match.group(1) != "false":
            raise ValueError(f"{label} must not continue on error")
    require_canonical_workflow_mapping_keys(step, label)


def require_exact_workflow_step_keys(
    step: str,
    expected: tuple[str, ...],
    label: str,
) -> None:
    active = active_source(step, comment_style="hash")
    populated_lines = [line for line in active.splitlines() if line.strip()]
    if not populated_lines:
        raise ValueError(f"{label} must contain workflow step keys")
    mapping_indent = min(
        len(line) - len(line.lstrip(" ")) for line in populated_lines
    )
    keys: list[str] = []
    for line in populated_lines:
        indentation = len(line) - len(line.lstrip(" "))
        if indentation != mapping_indent:
            continue
        match = re.fullmatch(
            r"([A-Za-z][A-Za-z0-9_-]*)[ ]*:[^\r\n]*",
            line[mapping_indent:],
        )
        if match is None:
            raise ValueError(f"{label} must use canonical unquoted workflow keys")
        keys.append(match.group(1))
    if tuple(keys) != expected:
        raise ValueError(
            f"{label} must use exact ordered keys {list(expected)}; found {keys}"
        )


M4_SAFE_FULL_JOB_GUARD = (
    "${{ github.event_name != 'push' || !startsWith(github.ref_name, "
    "'test/m4.') || startsWith(github.ref_name, 'test/m4.9-') }}"
)


def require_unconditional_workflow_job(
    text: str,
    name: str,
    expected_if: str | None = None,
) -> str:
    active = active_source(text, comment_style="hash")
    job_matches = list(
        re.finditer(rf"^  {re.escape(name)}:\s*$", active, flags=re.MULTILINE)
    )
    if len(job_matches) != 1:
        raise ValueError(
            f"M3 workflow must contain exactly one canonical job {name!r}; "
            f"found {len(job_matches)}"
        )
    job = yaml_mapping_entry(text, name, indent=2)
    if_key = yaml_key_pattern("if")
    continue_key = yaml_key_pattern("continue-on-error")
    if expected_if is None:
        if re.search(rf"^ {{4}}{if_key}[ ]*:", job, flags=re.MULTILINE):
            raise ValueError(f"M3 required workflow job {name} must run unconditionally")
    elif re.findall(
        rf"^ {{4}}{if_key}[ ]*:[ ]*(.*?)[ ]*$",
        job,
        flags=re.MULTILINE,
    ) != [expected_if]:
        raise ValueError(
            f"M3 required workflow job {name} must use the exact M4-safe full-job guard"
        )
    defaults_key = yaml_key_pattern("defaults")
    if re.search(rf"^ {{4}}{defaults_key}[ ]*:", job, flags=re.MULTILINE):
        raise ValueError(
            f"M3 required workflow job {name} must not override run defaults"
        )
    for match in re.finditer(
        rf"^ {{4}}{continue_key}[ ]*:[ ]*([^\r\n]*?)[ ]*$",
        job,
        flags=re.MULTILINE,
    ):
        if match.group(1) != "false":
            raise ValueError(f"M3 required workflow job {name} must not continue on error")
    require_canonical_workflow_mapping_keys(
        job,
        f"M3 required workflow job {name}",
    )
    return job


def workflow_run_block(step: str, label: str) -> str:
    matches = list(
        re.finditer(r"^(?P<indent>[ ]*)run:\s*\|\s*$", step, flags=re.MULTILINE)
    )
    if len(matches) != 1:
        raise ValueError(f"{label} must contain exactly one run block")
    match = matches[0]
    base_indent = len(match.group("indent"))
    lines: list[str] = []
    for line in step[match.end():].splitlines()[1:]:
        if not line.strip():
            lines.append("")
            continue
        indentation = len(line) - len(line.lstrip())
        if indentation <= base_indent:
            break
        lines.append(line[min(base_indent + 2, len(line)):])
    return "\n".join(lines)


def shell_logical_commands(script: str) -> list[str]:
    commands: list[str] = []
    current: list[str] = []
    for line in active_source(script, comment_style="hash").splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        continued = stripped.endswith("\\")
        current.append(stripped[:-1].rstrip() if continued else stripped)
        if not continued:
            commands.append(" ".join(current))
            current = []
    if current:
        commands.append(" ".join(current))
    return commands


def yaml_mapping_entry(text: str, key: str, indent: int) -> str:
    active = active_source(text, comment_style="hash")
    prefix = " " * indent
    match = re.search(
        rf"^{re.escape(prefix + key)}:\s*$",
        active,
        flags=re.MULTILINE,
    )
    if not match:
        raise ValueError(f"Missing active YAML mapping entry: {key}")
    following = active[match.end():]
    next_entry = re.search(
        rf"^{re.escape(prefix)}\S[^\n]*:\s*$",
        following,
        flags=re.MULTILINE,
    )
    return following[:next_entry.start()] if next_entry else following


def shell_case(text: str, case_label: str) -> str:
    active = active_source(text, comment_style="hash")
    start = active.find(case_label)
    if start < 0:
        raise ValueError(f"Missing active shell case: {case_label}")
    end = active.find(";;", start)
    if end < 0:
        raise ValueError(f"Unclosed active shell case: {case_label}")
    return active[start:end]


def verify_red_structure(target_root: Path) -> None:
    accessibility_relative = "HealthTrackingAppUITests/M3AccessibilityUITests.swift"
    accessibility_path = target_root / accessibility_relative
    accessibility_code = swift_code_only(
        accessibility_path.read_text(encoding="utf-8")
    )
    accessibility_imports = [
        " ".join(match.group(0).split())
        for match in re.finditer(r"\bimport\b[^\n]*", accessibility_code)
    ]
    if accessibility_imports != ["import Foundation", "import XCTest"]:
        raise ValueError(
            "M3 accessibility UI tests must import only Foundation and XCTest"
        )

    assertion_identifier = re.compile(
        r"(?<![A-Za-z0-9_])`?XCTAssert[A-Za-z0-9_]*`?(?![A-Za-z0-9_])"
    )
    ui_test_root = target_root / "HealthTrackingAppUITests"
    for path in sorted(ui_test_root.rglob("*.swift")):
        code = swift_code_only(path.read_text(encoding="utf-8"))
        for match in assertion_identifier.finditer(code):
            cursor = match.end()
            while cursor < len(code) and code[cursor].isspace():
                cursor += 1
            declaration_prefix = re.search(
                r"\b(?:case|func|macro)\s*$",
                code[:match.start()],
            )
            if (
                cursor >= len(code)
                or code[cursor] != "("
                or declaration_prefix is not None
            ):
                relative = path.relative_to(target_root)
                raise ValueError(
                    "M3 UI tests must not shadow XCTest assertions; "
                    f"found an active non-call binding in {relative}"
                )

    acceptance = "HealthTrackingAppUITests/M3AcceptanceUITests.swift"
    route_anchor = "func testTodayAndProgressExposeEveryM3TrackerEntryThroughOneLazyRouter()"
    require_scoped_tokens(
        target_root,
        acceptance,
        route_anchor,
        {
            '"progress.metrics.action"',
            '"progress.lifestyle.action"',
            '"progress.posture.action"',
            '"progress.health-check.action"',
            '"progress.bloodwork.action"',
            '"progress.photos.action"',
            '"today.bloodwork.action"',
            "assertRouterInstantiationCount(0, in: app)",
            "assertRouterInstantiationCount(1, in: app)",
            "assertExactlyOneProgressEntryActionPerTracker(in: probe)",
            "for route in routes",
            "action: route.action",
            "content: route.content",
            "close: route.close",
        },
        "M3 route acceptance test",
        reject_early_return=True,
    )
    route_scope = braced_scope(
        (target_root / acceptance).read_text(encoding="utf-8"),
        route_anchor,
        "M3 route acceptance test",
    )
    route_bindings = {
        "Today body metric route binding": (
            r'openAndCloseSheet\(\s*action:\s*"today\.metrics\.action"\s*,'
            r'\s*content:\s*"metrics\.entry\.weight"\s*,'
            r'\s*close:\s*"metrics\.entry\.close"\s*,\s*in:\s*app\s*\)'
        ),
        "Today lifestyle route binding": (
            r'openAndCloseSheet\(\s*action:\s*"today\.lifestyle\.action"\s*,'
            r'\s*content:\s*"lifestyle\.entry\.loaded"\s*,'
            r'\s*close:\s*"lifestyle\.entry\.close"\s*,\s*in:\s*app\s*\)'
        ),
        "Today posture route binding": (
            r'openAndCloseSheet\(\s*action:\s*"today\.posture\.action"\s*,'
            r'\s*content:\s*"posture\.entry\.loaded"\s*,'
            r'\s*close:\s*"posture\.entry\.close"\s*,\s*in:\s*app\s*\)'
        ),
        "Today health-check route binding": (
            r'openAndCloseSheet\(\s*action:\s*"today\.health-check\.action"\s*,'
            r'\s*content:\s*"health-check\.list\.loaded"\s*,'
            r'\s*close:\s*"health-check\.close"\s*,\s*in:\s*app\s*\)'
        ),
        "Today bloodwork route binding": (
            r'openAndCloseSheet\(\s*action:\s*"today\.bloodwork\.action"\s*,'
            r'\s*content:\s*"bloodwork\.list\.content"\s*,'
            r'\s*close:\s*"bloodwork\.close"\s*,\s*in:\s*app\s*\)'
        ),
        "Progress body metric route binding": (
            r'\(\s*"progress\.metrics\.action"\s*,\s*"metrics\.entry\.weight"'
            r'\s*,\s*"metrics\.entry\.close"\s*\)'
        ),
        "Progress lifestyle route binding": (
            r'\(\s*"progress\.lifestyle\.action"\s*,\s*"lifestyle\.entry\.loaded"'
            r'\s*,\s*"lifestyle\.entry\.close"\s*\)'
        ),
        "Progress posture route binding": (
            r'\(\s*"progress\.posture\.action"\s*,\s*"posture\.entry\.loaded"'
            r'\s*,\s*"posture\.entry\.close"\s*\)'
        ),
        "Progress health-check route binding": (
            r'\(\s*"progress\.health-check\.action"\s*,'
            r'\s*"health-check\.list\.loaded"\s*,\s*"health-check\.close"\s*\)'
        ),
        "Progress bloodwork route binding": (
            r'\(\s*"progress\.bloodwork\.action"\s*,\s*"bloodwork\.list\.content"'
            r'\s*,\s*"bloodwork\.close"\s*\)'
        ),
        "Progress photos route binding": (
            r'\(\s*"progress\.photos\.action"\s*,\s*"photos\.lifecycle\.content"'
            r'\s*,\s*"photos\.close"\s*\)'
        ),
    }
    for label, pattern in route_bindings.items():
        if re.search(pattern, route_scope, flags=re.DOTALL) is None:
            raise ValueError(f"M3 route acceptance is missing {label}")

    routes_initializer = swift_array_initializer(
        route_scope,
        (
            r"\blet\s+routes\s*:\s*\[\s*\(\s*action\s*:\s*String\s*,"
            r"\s*content\s*:\s*String\s*,\s*close\s*:\s*String\s*\)\s*\]"
        ),
        "M3 routes initializer",
        r"for\s+route\s+in\s+routes\s*\{",
    )
    route_tuple_pattern = re.compile(
        r'\(\s*"([^"\n]+)"\s*,\s*"([^"\n]+)"\s*,\s*"([^"\n]+)"\s*\)'
    )
    route_tuples = [
        (action, content, close)
        for action, content, close in route_tuple_pattern.findall(routes_initializer)
    ]
    initializer_residue = route_tuple_pattern.sub("", routes_initializer)
    expected_route_tuples = [
        ("progress.metrics.action", "metrics.entry.weight", "metrics.entry.close"),
        (
            "progress.lifestyle.action",
            "lifestyle.entry.loaded",
            "lifestyle.entry.close",
        ),
        ("progress.posture.action", "posture.entry.loaded", "posture.entry.close"),
        (
            "progress.health-check.action",
            "health-check.list.loaded",
            "health-check.close",
        ),
        ("progress.bloodwork.action", "bloodwork.list.content", "bloodwork.close"),
        ("progress.photos.action", "photos.lifecycle.content", "photos.close"),
    ]
    route_labels = {
        expected_route_tuples[0]: "Progress body metric route binding",
        expected_route_tuples[1]: "Progress lifestyle route binding",
        expected_route_tuples[2]: "Progress posture route binding",
        expected_route_tuples[3]: "Progress health-check route binding",
        expected_route_tuples[4]: "Progress bloodwork route binding",
        expected_route_tuples[5]: "Progress photos route binding",
    }
    for expected in expected_route_tuples:
        if route_tuples.count(expected) != 1:
            raise ValueError(
                f"M3 routes initializer is missing exact {route_labels[expected]}"
            )
    if (
        len(route_tuples) != len(expected_route_tuples)
        or re.sub(r"[\s,]", "", initializer_residue)
    ):
        raise ValueError("M3 routes initializer must contain exactly six route tuples")

    route_code = swift_code_only(route_scope)
    route_loops = list(
        re.finditer(r"\bfor\s+route\s+in\s+routes\s*\{", route_code)
    )
    if len(route_loops) != 1:
        raise ValueError(
            "M3 route acceptance must consume the complete routes initializer"
        )
    loop_opening = route_loops[0].end() - 1
    loop_end = balanced_delimiter_end(
        route_code,
        loop_opening,
        "{",
        "}",
        "M3 routes loop",
    )
    loop_body = route_scope[loop_opening + 1:loop_end - 1]
    loop_code = swift_code_only(loop_body)
    if re.fullmatch(
        r"\s*openAndCloseSheet\(\s*action:\s*route\.action\s*,"
        r"\s*content:\s*route\.content\s*,\s*close:\s*route\.close\s*,"
        r"\s*in:\s*app\s*\)\s*"
        r"assertRouterInstantiationCount\(\s*1\s*,\s*in:\s*app\s*\)\s*",
        loop_code,
    ) is None:
        raise ValueError(
            "M3 routes loop must explicitly close every route and assert one cached router"
        )

    close_helper_code = require_ordered_swift_code_tokens(
        target_root,
        acceptance,
        "private func openAndCloseSheet(",
        [
            "let actionElement = require(",
            "identified(action, in: app)",
            "makeHittable(actionElement, in: app)",
            "actionElement.tap()",
            "let contentElement = require(",
            "identified(content, in: app)",
            "let closeElement = require(",
            "app.buttons[close]",
            "makeHittable(closeElement, in: app)",
            "closeElement.tap()",
            "waitForDisappearance(",
        ],
        "M3 explicit-close route helper",
        forbidden_pattern=(
            r"\b(?:return|guard|if|switch|for|while|XCTSkip(?:If|Unless)?)\b"
        ),
    )
    for token in (
        "actionElement.tap()",
        "closeElement.tap()",
        "waitForDisappearance(",
    ):
        if close_helper_code.count(token) != 1:
            raise ValueError(
                "M3 explicit-close route helper must execute each UI action exactly once"
            )
    if (
        "{" in close_helper_code
        or "}" in close_helper_code
        or "#if" in close_helper_code
        or "?" in close_helper_code
    ):
        raise ValueError("M3 explicit-close route helper must execute at top level")
    if "openAndDismissSwipeSheet" in swift_code_only(
        (target_root / acceptance).read_text(encoding="utf-8")
    ):
        raise ValueError("M3 route acceptance must not depend on swipe-only sheet dismissal")

    require_scoped_tokens(
        target_root,
        acceptance,
        "private func assertRouterInstantiationCount(_ expected: String",
        {
            'identified("m3.tracker-router.instantiation-count", in: app)',
            "evidence.value as? String",
            "expected",
        },
        "M3 router-count observation helper",
        reject_early_return=True,
    )
    router_count_code = require_ordered_swift_code_tokens(
        target_root,
        acceptance,
        "private func assertRouterInstantiationCount(_ expected: String",
        [
            "let evidence = require(",
            "identified(",
            "XCTAssertEqual(evidence.value as? String, expected)",
        ],
        "M3 router-count observation helper",
        forbidden_pattern=(
            r"\b(?:return|guard|if|switch|for|while|XCTSkip(?:If|Unless)?)\b"
        ),
    )
    if (
        "{" in router_count_code
        or "}" in router_count_code
        or "#if" in router_count_code
        or router_count_code.count("?") != 1
    ):
        raise ValueError("M3 router-count observation helper must execute at top level")
    integer_router_count_code = require_ordered_swift_code_tokens(
        target_root,
        acceptance,
        "private func assertRouterInstantiationCount(_ expected: Int",
        ["assertRouterInstantiationCount(String(expected), in: app)"],
        "M3 integer router-count delegation helper",
        forbidden_pattern=(
            r"\b(?:return|guard|if|switch|for|while|XCTSkip(?:If|Unless)?)\b"
        ),
    )
    if (
        "{" in integer_router_count_code
        or "}" in integer_router_count_code
        or "#if" in integer_router_count_code
        or "?" in integer_router_count_code
    ):
        raise ValueError("M3 integer router-count helper must execute at top level")
    require_scoped_tokens(
        target_root,
        acceptance,
        "private func assertExactlyOneProgressEntryActionPerTracker(",
        {
            '"progress.metrics.action"',
            '"progress.lifestyle.action"',
            '"progress.posture.action"',
            '"progress.health-check.action"',
            '"progress.bloodwork.action"',
            '"progress.photos.action"',
            '"photos.open"',
            "app.buttons.matching(identifier: identifier).count",
            "XCTAssertEqual(",
            "visibleEntryActionCount,",
            "6,",
        },
        "M3 unique Progress entry action assertion",
        reject_early_return=True,
    )
    same_day_anchor = "func testUS6AndUS8SummariesSurviveProgressSameDayEditAndRelaunch()"
    require_scoped_tokens(
        target_root,
        acceptance,
        same_day_anchor,
        {
            'moodScore: "6"',
            'moodScore: "7"',
            "assertLifestyleSummary(",
            'assertFixedNowEvidence("2026-08-27T10:00:00Z", in: app)',
            '"today.bloodwork.action"',
            "app.terminate()",
        },
        "M3 same-day and relaunch test",
        reject_early_return=True,
    )
    same_day_scope = braced_scope(
        (target_root / acceptance).read_text(encoding="utf-8"),
        same_day_anchor,
        "M3 same-day and relaunch test",
    )
    expected_summary_assertions = {
        'moodScore: "6"': 1,
        'moodScore: "7"': 2,
        'duration: "7"': 3,
        'quality: "8"': 1,
        'quality: "9"': 2,
    }
    for token, expected_count in expected_summary_assertions.items():
        actual_count = same_day_scope.count(token)
        if actual_count != expected_count:
            raise ValueError(
                "M3 same-day and relaunch test must assert "
                f"{token} exactly {expected_count} time(s); found {actual_count}"
            )
    require_scoped_tokens(
        target_root,
        acceptance,
        "private func assertFixedNowEvidence(",
        {
            'identified("m3.fixed-now", in: app)',
            "evidence.value as? String",
            "expected",
        },
        "M3 fixed clock observation helper",
        reject_early_return=True,
    )
    fixed_clock_code = require_ordered_swift_code_tokens(
        target_root,
        acceptance,
        "private func assertFixedNowEvidence(",
        [
            "let evidence = require(",
            "identified(",
            "XCTAssertEqual(evidence.value as? String, expected)",
        ],
        "M3 fixed clock observation helper",
        forbidden_pattern=(
            r"\b(?:return|guard|if|switch|for|while|XCTSkip(?:If|Unless)?)\b"
        ),
    )
    if (
        "{" in fixed_clock_code
        or "}" in fixed_clock_code
        or "#if" in fixed_clock_code
        or fixed_clock_code.count("?") != 1
    ):
        raise ValueError("M3 fixed clock observation helper must execute at top level")
    require_scoped_tokens(
        target_root,
        acceptance,
        "private func assertLifestyleSummary(",
        {
            '"lifestyle.progress.sleep.summary"',
            '"lifestyle.progress.mood.summary"',
            "sleepValue.contains(duration)",
            "sleepValue.contains(quality)",
            ".contains(moodScore)",
        },
        "M3 exact lifestyle summary assertion helper",
        reject_early_return=True,
    )
    lifestyle_summary_code = require_ordered_swift_code_tokens(
        target_root,
        acceptance,
        "private func assertLifestyleSummary(",
        [
            "let loaded = require(",
            "makeHittable(loaded, in: app)",
            "XCTAssertEqual(loaded.value as? String, sectionCount)",
            "let sleep = require(",
            "makeHittable(sleep, in: app)",
            "let sleepValue = (sleep.value as? String) ?? sleep.label",
            "XCTAssertTrue(",
            "sleepValue.contains(duration)",
            "XCTAssertTrue(",
            "sleepValue.contains(quality)",
            "let mood = require(",
            "makeHittable(mood, in: app)",
            "XCTAssertTrue(",
            ".contains(moodScore)",
        ],
        "M3 exact lifestyle summary assertion helper",
        forbidden_pattern=(
            r"\b(?:return|guard|if|switch|for|while|XCTSkip(?:If|Unless)?)\b"
        ),
    )
    if (
        "{" in lifestyle_summary_code
        or "}" in lifestyle_summary_code
        or "#if" in lifestyle_summary_code
        or lifestyle_summary_code.count("?") != 7
    ):
        raise ValueError("M3 lifestyle summary helper must execute at top level")
    require_scoped_tokens(
        target_root,
        "HealthTrackingAppUITests/ProgressPhotoLifecycleUITests.swift",
        "func testDeniedAndLimitedBroaderAccessKeepActualSystemPickerOperable()",
        {
            'for accessState in ["denied", "limited"]',
            'identified("photos.picker", in: app)',
            "picker.isEnabled",
            "picker.value as? String",
            "picker.isHittable",
        },
        "M3 picker access-state test",
        reject_early_return=True,
    )
    require_scoped_tokens(
        target_root,
        "HealthTrackingAppUITests/M3AccessibilityUITests.swift",
        "func testProgressHubLightDarkDefaultXXLAX3AX5Matrix()",
        {
            "for appearance in Appearance.allCases",
            "for textSize in TextSize.allCases",
            '"progress.metrics.action"',
            '"m3-progress-\\(appearance.rawValue)-\\(textSize.rawValue)"',
        },
        "M3 accessibility appearance and type-size matrix",
        reject_early_return=True,
    )
    require_scoped_tokens(
        target_root,
        "HealthTrackingAppUITests/M3AccessibilityUITests.swift",
        "func testEveryMetricTextFieldExposesFiftyTwoPointInteractionGeometry()",
        {
            '"metrics.entry.weight"',
            '"metrics.entry.waist"',
            '"metrics.entry.custom.name"',
            '"metrics.entry.custom.value"',
            '"metrics.entry.custom.unit"',
            '"Vücut ağırlığı"',
            '"Bel çevresi"',
            '"Ölçüm adı"',
            '"Değer"',
            '"Birim"',
            "for contract in fields",
            "let field = require(app.textFields[contract.identifier])",
            "makeHittable(field, in: app)",
            "field.isHittable",
            "XCTAssertEqual(field.label, contract.label)",
            "field.frame.height + 0.01",
        },
        "M3 Metrics complete text-field interaction geometry UI test",
        reject_early_return=True,
    )
    accessibility_source = (
        target_root / "HealthTrackingAppUITests/M3AccessibilityUITests.swift"
    ).read_text(encoding="utf-8")
    metric_geometry_scope = braced_scope(
        accessibility_source,
        "func testEveryMetricTextFieldExposesFiftyTwoPointInteractionGeometry()",
        "M3 Metrics complete text-field interaction geometry UI test",
    )
    fields_initializer = swift_array_initializer(
        metric_geometry_scope,
        (
            r"\blet\s+fields\s*:\s*\[\s*\(\s*identifier\s*:\s*String\s*,"
            r"\s*label\s*:\s*String\s*\)\s*\]"
        ),
        "M3 Metrics text-field contract initializer",
        r"for\s+contract\s+in\s+fields\s*\{",
    )
    active_fields_initializer = swift_code_only(
        fields_initializer,
        mask_literals=False,
    )
    field_contract_pattern = re.compile(
        r'\(\s*"([^"\n]+)"\s*,\s*"([^"\n]+)"\s*\)'
    )
    field_contracts = field_contract_pattern.findall(active_fields_initializer)
    expected_field_contracts = [
        ("metrics.entry.weight", "Vücut ağırlığı"),
        ("metrics.entry.waist", "Bel çevresi"),
        ("metrics.entry.custom.name", "Ölçüm adı"),
        ("metrics.entry.custom.value", "Değer"),
        ("metrics.entry.custom.unit", "Birim"),
    ]
    initializer_residue = field_contract_pattern.sub("", active_fields_initializer)
    if (
        field_contracts != expected_field_contracts
        or re.sub(r"[\s,]", "", initializer_residue)
    ):
        raise ValueError(
            "M3 Metrics interaction geometry UI test must enumerate exactly five "
            "identifier-label contracts"
        )

    metric_geometry_code = swift_code_only(metric_geometry_scope)
    geometry_loops = list(
        re.finditer(
            r"\bfor\s+contract\s+in\s+fields\s*\{",
            metric_geometry_code,
        )
    )
    if len(geometry_loops) != 1:
        raise ValueError(
            "M3 Metrics interaction geometry UI test must consume the complete field contracts"
        )
    geometry_loop_opening = geometry_loops[0].end() - 1
    geometry_loop_end = balanced_delimiter_end(
        metric_geometry_code,
        geometry_loop_opening,
        "{",
        "}",
        "M3 Metrics interaction geometry loop",
    )
    geometry_prefix = metric_geometry_code[:geometry_loops[0].start()]
    geometry_suffix = metric_geometry_code[geometry_loop_end:]
    if "{" in geometry_prefix or "}" in geometry_prefix or geometry_suffix.strip():
        raise ValueError(
            "M3 Metrics interaction geometry loop must execute directly at test scope"
        )
    geometry_loop_body = metric_geometry_scope[
        geometry_loop_opening + 1:geometry_loop_end - 1
    ]
    geometry_loop_code = swift_code_only(geometry_loop_body)
    if re.fullmatch(
        r"\s*let\s+field\s*=\s*require\(app\.textFields\[contract\.identifier\]\)\s*"
        r"makeHittable\(field,\s*in:\s*app\)\s*"
        r"XCTAssertTrue\(field\.isHittable\)\s*"
        r"XCTAssertEqual\(field\.label,\s*contract\.label\)\s*"
        r"XCTAssertGreaterThanOrEqual\(field\.frame\.height\s*\+\s*0\.01,\s*52\)\s*",
        geometry_loop_code,
    ) is None:
        raise ValueError(
            "M3 Metrics interaction geometry loop must execute every exact field assertion"
        )
    require_scoped_tokens(
        target_root,
        "HealthTrackingAppUITests/M3AccessibilityUITests.swift",
        "func testReduceMotionAndHighContrastTrackerRoutesRemainOperable()",
        {
            '"-UIAccessibilityReduceMotionEnabled", "YES"',
            '"-UIAccessibilityDarkerSystemColorsEnabled", "YES"',
            '"m3-progress-reduce-motion"',
            '"m3-progress-high-contrast"',
        },
        "M3 accessibility settings matrix",
        reject_early_return=True,
    )
    require_scoped_tokens(
        target_root,
        "HealthTrackingAppUITests/M3AccessibilityUITests.swift",
        "func testSmallPhoneAX5TrackerRoutesRemainOperable() throws",
        {
            'ProcessInfo.processInfo.environment["M3_SMALL_PHONE_GATE"] == "1"',
            "XCTAssertLessThanOrEqual(",
            '"progress.metrics.action"',
            '"progress.health-check.action"',
            '"m3-progress-small-ax5"',
            "let metricField = require(",
            "let metricClose = require(",
            'app.buttons["metrics.entry.close"]',
            "metricClose.isHittable",
            "metricClose.frame.midY",
            "app.frame.midY",
            "metricClose.tap()",
            "waitForDisappearance(",
        },
        "M3 dedicated small-phone test",
    )
    small_phone_scope = braced_scope(
        (
            target_root
            / "HealthTrackingAppUITests/M3AccessibilityUITests.swift"
        ).read_text(encoding="utf-8"),
        "func testSmallPhoneAX5TrackerRoutesRemainOperable() throws",
        "M3 dedicated small-phone test",
    )
    if small_phone_scope.count("throw XCTSkip(") != 1:
        raise ValueError(
            "M3 dedicated small-phone test must contain exactly one environment-gate skip"
        )
    small_phone_without_strings = source_without_string_literals(small_phone_scope)
    if re.search(r"\breturn\b|\bXCTSkip(?:If|Unless)\b", small_phone_without_strings):
        raise ValueError("M3 dedicated small-phone test contains an extra bypass path")
    if (
        "swipeDown" in small_phone_scope
        or "makeHittable(metricClose" in small_phone_scope
        or small_phone_scope.count("metricClose.tap()") != 1
        or small_phone_scope.count("waitForDisappearance(") != 1
        or re.search(r"\bif\b", small_phone_without_strings)
        or "?" in small_phone_without_strings
    ):
        raise ValueError(
            "M3 dedicated small-phone test must execute its exact explicit-close lifecycle"
        )
    require_scoped_tokens(
        target_root,
        "HealthTrackingAppUITests/M3AccessibilityUITests.swift",
        "private func waitForDisappearance(of element: XCUIElement, message: String)",
        {
            'NSPredicate(format: "exists == false")',
            "XCTWaiter.wait(for: [expectation], timeout: 5)",
            ".completed",
            "message",
        },
        "M3 accessibility disappearance waiter",
        reject_early_return=True,
    )

    project = (target_root / "project.yml").read_text(encoding="utf-8")
    local_scheme = yaml_mapping_entry(
        project,
        "HealthTrackingApp-Local",
        indent=2,
    )
    local_test_action = yaml_mapping_entry(
        local_scheme,
        "test",
        indent=4,
    )
    if "- HealthTrackingAppUITests" not in local_test_action:
        raise ValueError("M3 Local scheme is detached from the UI test target")
    test_environment = yaml_mapping_entry(
        local_test_action,
        "environmentVariables",
        indent=6,
    )
    if re.search(
        r'^\s{8}M3_SMALL_PHONE_GATE:\s*"\$\(M3_SMALL_PHONE_GATE\)"\s*$',
        test_environment,
        flags=re.MULTILINE,
    ) is None:
        raise ValueError(
            "M3 Local scheme must forward its small-phone gate into the XCTest process"
        )

    workflow = (target_root / ".github/workflows/ios.yml").read_text(encoding="utf-8")
    test_job = require_unconditional_workflow_job(
        workflow,
        "test",
        expected_if=M4_SAFE_FULL_JOB_GUARD,
    )
    small_phone_job = require_unconditional_workflow_job(workflow, "test-small-phone")
    qualifying = workflow_step(test_job, "Qualifying M3.12 integration RED")
    require_unconditional_workflow_step(
        qualifying,
        "M3.12 qualifying workflow step",
    )
    require_exact_workflow_step_keys(
        qualifying,
        ("timeout-minutes", "run"),
        "M3.12 qualifying workflow step",
    )
    if re.search(
        r"^\s*run:\s*scripts/test-ios\.sh --m312-red-only\s*$",
        qualifying,
        flags=re.MULTILINE,
    ) is None:
        raise ValueError("M3.12 qualifying workflow step is detached from its RED command")
    targeted = workflow_step(test_job, "Targeted M3.12 tracker acceptance tests")
    require_unconditional_workflow_step(
        targeted,
        "M3.12 targeted workflow step",
    )
    require_exact_workflow_step_keys(
        targeted,
        ("timeout-minutes", "run"),
        "M3.12 targeted workflow step",
    )
    if re.search(
        r"^\s*run:\s*scripts/test-ios\.sh --only-testing "
        r"HealthTrackingAppUITests/M3AcceptanceUITests\s*$",
        targeted,
        flags=re.MULTILINE,
    ) is None:
        raise ValueError("M3.12 targeted workflow step is detached from acceptance tests")
    touch_target = workflow_step(
        test_job,
        "Targeted M3.12 text-field touch-target regression",
    )
    require_unconditional_workflow_step(
        touch_target,
        "M3.12 text-field touch-target workflow step",
    )
    require_exact_workflow_step_keys(
        touch_target,
        ("timeout-minutes", "run"),
        "M3.12 text-field touch-target workflow step",
    )
    if re.search(
        r"^\s*run:\s*scripts/test-ios\.sh --only-testing "
        r"HealthTrackingAppUITests/M3AccessibilityUITests\s*$",
        touch_target,
        flags=re.MULTILINE,
    ) is None:
        raise ValueError(
            "M3.12 text-field touch-target workflow step is detached from its exact UI test"
        )
    reset_simulator = workflow_step(
        test_job,
        "Reset selected simulator before complete functional suite",
    )
    require_unconditional_workflow_step(
        reset_simulator,
        "M3 complete-suite simulator reset workflow step",
    )
    require_exact_workflow_step_keys(
        reset_simulator,
        ("run",),
        "M3 complete-suite simulator reset workflow step",
    )
    reset_script = workflow_run_block(
        reset_simulator,
        "M3 complete-suite simulator reset workflow step",
    )
    reset_commands = shell_logical_commands(reset_script)
    expected_reset_commands = [
        "set -euo pipefail",
        'destination="$(scripts/select-simulator.sh)"',
        'case "$destination" in',
        '*,id=*) simulator_udid="${destination##*,id=}" ;;',
        '*) echo "Selected simulator destination has no UDID: $destination" >&2; exit 1 ;;',
        "esac",
        'xcrun simctl shutdown "$simulator_udid" 2>/dev/null || :',
        'xcrun simctl erase "$simulator_udid"',
    ]
    if reset_commands != expected_reset_commands:
        raise ValueError(
            "M3 complete-suite simulator reset must use only its approved "
            "fail-closed command graph"
        )
    complete_suite = workflow_step(test_job, "Test iOS app")
    require_unconditional_workflow_step(
        complete_suite,
        "M3 complete functional-suite workflow step",
    )
    require_exact_workflow_step_keys(
        complete_suite,
        ("timeout-minutes", "run"),
        "M3 complete functional-suite workflow step",
    )
    if re.search(
        r"^\s*run:\s*scripts/test-ios\.sh --skip-testing "
        r"HealthTrackingAppUITests/TodayGuidanceUITests/"
        r"testColdLaunchPublishesFirstMeaningfulDirectiveWithinOneSecondMedian\s*$",
        complete_suite,
        flags=re.MULTILINE,
    ) is None:
        raise ValueError(
            "M3 complete functional-suite workflow step is detached from its exact test command"
        )
    active_test_job = active_source(test_job, comment_style="hash")
    touch_target_position = active_test_job.find(
        "- name: Targeted M3.12 text-field touch-target regression"
    )
    reset_position = active_test_job.find(
        "- name: Reset selected simulator before complete functional suite"
    )
    complete_suite_position = active_test_job.find("- name: Test iOS app")
    if (
        touch_target_position < 0
        or reset_position < 0
        or complete_suite_position < 0
        or touch_target_position >= reset_position
        or reset_position >= complete_suite_position
    ):
        raise ValueError(
            "M3 touch-target gate, simulator reset, and complete suite must run in order"
        )
    small_phone = workflow_step(
        small_phone_job,
        "Test M1 and M3 on small iPhone at AX5",
    )
    require_unconditional_workflow_step(
        small_phone,
        "M3 small-phone workflow step",
    )
    for token in (
        'M3_SMALL_PHONE_GATE: "1"',
        "testSmallPhoneAX5TrackerRoutesRemainOperable",
    ):
        if token not in small_phone:
            raise ValueError(f"M3 small-phone workflow step is missing {token}")
    small_phone_script = workflow_run_block(
        small_phone,
        "M3 small-phone workflow step",
    )
    small_phone_commands = shell_logical_commands(small_phone_script)
    if not small_phone_commands or small_phone_commands[0] != "set -euo pipefail":
        raise ValueError("M3 small-phone workflow must begin with fail-closed shell options")
    active_small_phone_script = active_source(
        small_phone_script,
        comment_style="hash",
    )
    if re.search(
        r"(?<![A-Za-z0-9_])set\s+(?:\+e|\+o\s+(?:errexit|pipefail|nounset))\b",
        active_small_phone_script,
    ):
        raise ValueError("M3 small-phone workflow must not disable shell error handling")
    if re.search(r"^\s*trap(?:\s|$)", active_small_phone_script, flags=re.MULTILINE):
        raise ValueError("M3 small-phone workflow must not trap shell failures")
    xcodebuild_commands = [
        command
        for command in small_phone_commands
        if command.startswith("xcodebuild test ")
    ]
    if len(xcodebuild_commands) != 1:
        raise ValueError(
            "M3 small-phone workflow must execute exactly one xcodebuild test command"
        )
    xcodebuild_command = xcodebuild_commands[0]
    expected_command_graph = [
        "set -euo pipefail",
        "scripts/bootstrap.sh",
        'destination="$(scripts/select-simulator.sh --small)"',
        'result_bundle=".build/HealthTrackingApp-small.xcresult"',
        'rm -rf "$result_bundle"',
        xcodebuild_command,
    ]
    if small_phone_commands != expected_command_graph:
        raise ValueError(
            "M3 small-phone workflow must use only its approved fail-closed command graph"
        )
    if (
        any(operator in xcodebuild_command for operator in ("&&", "||", ";"))
        or re.search(r"(?<!&)&(?!&)", xcodebuild_command)
    ):
        raise ValueError("M3 small-phone xcodebuild command must fail closed")
    try:
        xcodebuild_arguments = shlex.split(xcodebuild_command)
    except ValueError as error:
        raise ValueError("M3 small-phone xcodebuild command is not valid shell") from error
    if xcodebuild_arguments.count("-scheme") != 1:
        raise ValueError("M3 small-phone xcodebuild command must select one scheme")
    scheme_index = xcodebuild_arguments.index("-scheme")
    if (
        scheme_index + 1 >= len(xcodebuild_arguments)
        or xcodebuild_arguments[scheme_index + 1] != "HealthTrackingApp-Local"
    ):
        raise ValueError("M3 small-phone xcodebuild command must use the Local scheme")
    gate_arguments = [
        argument
        for argument in xcodebuild_arguments
        if argument.startswith("M3_SMALL_PHONE_GATE=")
    ]
    if gate_arguments != ["M3_SMALL_PHONE_GATE=1"]:
        raise ValueError(
            "M3 small-phone xcodebuild command must pass exact M3_SMALL_PHONE_GATE=1"
        )
    if (
        "-only-testing:HealthTrackingAppUITests/M3AccessibilityUITests/"
        "testSmallPhoneAX5TrackerRoutesRemainOperable"
    ) not in xcodebuild_arguments:
        raise ValueError(
            "M3 small-phone xcodebuild command is detached from its tracker acceptance test"
        )
    screenshot_export = workflow_step(test_job, "Export screenshot evidence")
    for owner in (
        '"M3AcceptanceUITests"',
        '"M3AccessibilityUITests"',
        '"ProgressPhotoLifecycleUITests"',
        '"ProgressPhotoGalleryUITests"',
    ):
        if owner not in screenshot_export:
            raise ValueError(f"M3 screenshot export is missing active owner {owner}")

    test_ios = (target_root / "scripts/test-ios.sh").read_text(encoding="utf-8")
    m312_case = shell_case(test_ios, "--m312-red-only)")
    for token in (
        "m312_red_only=true",
        "M3AcceptanceUITests/testTodayAndProgressExposeEveryM3TrackerEntryThroughOneLazyRouter",
    ):
        if token not in m312_case:
            raise ValueError(f"M3.12 test runner case is missing active wiring {token}")


def verify_production_structure(target_root: Path) -> None:
    require_scoped_tokens(
        target_root,
        "App/Application/AppRootView.swift",
        "var body: some View",
        {
            'accessibilityIdentifier("m3.fixed-now")',
            "ISO8601DateFormatter().string(from: AppDomainContext.now())",
        },
        "M3 fixed clock evidence binding",
    )
    require_scoped_tokens(
        target_root,
        "App/Application/TrackerFeatureBundle.swift",
        "func makeProgressView(",
        {
            "ProgressTrackerQuickActions(",
            "onOpenBodyMetric: onOpenBodyMetric",
            "onOpenLifestyle: onOpenLifestyle",
            "onOpenPosture: onOpenPosture",
            "onOpenHealthChecks: onOpenHealthChecks",
            "onOpenBloodwork: onOpenBloodwork",
            "onOpenProgressPhotos: onOpenProgressPhotos",
        },
        "M3 Progress routing composition",
    )
    require_scoped_tokens(
        target_root,
        "App/Support/AppUITestLaunchConfiguration.swift",
        "static func resolve(arguments:",
        {
            "PhotoLibraryAccessState(rawValue:",
            "ISO8601DateFormatter().date(from:",
            "broaderPhotoLibraryAccessState:",
            "fixedNow:",
        },
        "M3 deterministic launch parser",
    )
    require_scoped_tokens(
        target_root,
        "App/Application/TrackerFeatureBundle.swift",
        "if scenario == .m3ProgressPhotos",
        {
            "TrackerFeatureBundle(",
            "broaderPhotoLibraryAccessState:",
            "AppUITestLaunchConfiguration.resolve()?",
            ".broaderPhotoLibraryAccessState ?? .authorized",
        },
        "M3 progress-photo fixture access-state injection",
    )
    require_scoped_tokens(
        target_root,
        "App/Application/AppDependencies.swift",
        "private static func installM3HealthChecks(",
        {
            "let now = AppDomainContext.now()",
            "reminder.dueDate = now.addingTimeInterval(-60)",
            "reminder.updatedAt = now",
        },
        "M3 fixed-clock health-check fixture",
    )
    metric_entry_relative = (
        "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/"
        "BodyMetricEntryView.swift"
    )
    metric_entry_source = (target_root / metric_entry_relative).read_text(
        encoding="utf-8"
    )
    metric_entry_code = swift_code_only(metric_entry_source)
    conditional_directive = re.compile(
        r"(?m)^\s*#(?:if|elseif|else|endif)\b"
    )
    if conditional_directive.search(metric_entry_code):
        raise ValueError(
            "M3 Metrics canonical BodyMetricEntryView must not use conditional "
            "compilation in its source file"
        )
    metrics_module_root = (
        target_root / "Packages/HealthTrackingModules/Sources/MetricsKit"
    )
    metrics_module_sources = sorted(metrics_module_root.rglob("*.swift"))
    if not metrics_module_sources:
        raise ValueError("M3 MetricsKit module has no compiled Swift sources")
    protected_metric_symbols = (
        "TextField",
        "VStack",
        "HStack",
        "NavigationStack",
        "QuickEntryFormScaffold",
        "ToolbarItem",
        "Button",
        "accessibilityHidden",
        "accessibilityIdentifier",
        "accessibilityLabel",
        "contentShape",
        "focused",
        "frame",
        "interactiveDismissDisabled",
        "keyboardType",
        "task",
        "textFieldStyle",
        "toolbar",
    )
    protected_metric_view_types = (
        "TextField",
        "VStack",
        "HStack",
        "NavigationStack",
        "QuickEntryFormScaffold",
        "ToolbarItem",
        "Button",
    )
    protected_symbol_pattern = "(?:" + "|".join(
        re.escape(symbol) for symbol in protected_metric_symbols
    ) + ")"
    protected_binding = re.compile(
        r"`?" + protected_symbol_pattern + r"`?(?!\w)"
    )

    def declaration_boundary(
        source_code: str,
        start: int,
        terminators: set[str],
    ) -> tuple[int, str]:
        cursor = start
        stack: list[str] = []
        while cursor < len(source_code):
            character = source_code[cursor]
            if not stack and character in terminators:
                return cursor, character
            if character in "([{":
                stack.append(character)
            elif character in ")]}" and stack:
                stack.pop()
            cursor += 1
        return cursor, ""

    def shadows_protected_metric_symbol(source_code: str) -> bool:
        if re.search(
            r"\b(?:actor|associatedtype|class|enum|func|macro|protocol|"
            r"struct|typealias)\s+`?"
            + protected_symbol_pattern
            + r"`?(?!\w)",
            source_code,
        ):
            return True
        if re.search(
            r"\bimport\s+(?:class|enum|func|protocol|struct|typealias|var)\s+"
            r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*\."
            + protected_symbol_pattern
            + r"(?!\w)",
            source_code,
        ):
            return True
        protected_view_type_pattern = "(?:" + "|".join(
            re.escape(symbol) for symbol in protected_metric_view_types
        ) + ")"
        if re.search(
            r"\bextension\s+(?:SwiftUI\s*\.\s*)?`?"
            + protected_view_type_pattern
            + r"`?(?!\w)",
            source_code,
        ):
            return True
        for binding_declaration in re.finditer(r"\b(?:let|var)\b", source_code):
            cursor = binding_declaration.end()
            while cursor < len(source_code):
                while cursor < len(source_code) and source_code[cursor].isspace():
                    cursor += 1
                pattern_end, terminator = declaration_boundary(
                    source_code,
                    cursor,
                    {"=", ":", ",", "\n", ";", "{"},
                )
                if protected_binding.search(source_code[cursor:pattern_end]):
                    return True
                cursor = pattern_end
                if terminator == ":":
                    cursor, terminator = declaration_boundary(
                        source_code,
                        cursor + 1,
                        {"=", ",", "\n", ";", "{"},
                    )
                if terminator == "=":
                    cursor, terminator = declaration_boundary(
                        source_code,
                        cursor + 1,
                        {",", "\n", ";"},
                    )
                if terminator != ",":
                    break
                cursor += 1
        return False

    for module_source in metrics_module_sources:
        module_code = swift_code_only(module_source.read_text(encoding="utf-8"))
        if shadows_protected_metric_symbol(module_code):
            relative_module_source = module_source.relative_to(target_root)
            raise ValueError(
                "M3 Metrics must not shadow required SwiftUI symbols in "
                + str(relative_module_source)
            )

    body_metric_type_declarations: list[tuple[Path, re.Match[str]]] = []
    for module_source in metrics_module_sources:
        module_code = swift_code_only(module_source.read_text(encoding="utf-8"))
        body_metric_type_declarations.extend(
            (module_source, declaration)
            for declaration in re.finditer(
                r"\b(?:actor|class|enum|protocol|struct|typealias)\s+`?"
                r"BodyMetricEntryView`?(?!\w)",
                module_code,
            )
        )
    if (
        len(body_metric_type_declarations) != 1
        or body_metric_type_declarations[0][0]
        != target_root / metric_entry_relative
    ):
        raise ValueError(
            "M3 Metrics must define exactly one BodyMetricEntryView declaration "
            "across compiled MetricsKit sources"
        )
    body_metric_type_declaration = body_metric_type_declarations[0][1]
    canonical_body_metric_types = list(
        re.finditer(
            r"(?m)^[ \t]*@MainActor[ \t]*\n[ \t]*public[ \t]+struct[ \t]+"
            r"BodyMetricEntryView[ \t]*:[ \t]*View[ \t]*\{",
            metric_entry_code,
        )
    )

    def swift_brace_depth_at(source_code: str, position: int) -> int:
        depth = 0
        for character in source_code[:position]:
            if character == "{":
                depth += 1
            elif character == "}":
                depth -= 1
            if depth < 0:
                raise ValueError("M3 Metrics Swift scope has an unmatched closing brace")
        return depth

    if (
        len(canonical_body_metric_types) != 1
        or not (
            canonical_body_metric_types[0].start()
            <= body_metric_type_declaration.start()
            < canonical_body_metric_types[0].end()
        )
        or swift_brace_depth_at(
            metric_entry_code,
            canonical_body_metric_types[0].start(),
        ) != 0
    ):
        raise ValueError(
            "M3 Metrics must define exactly one canonical @MainActor public "
            "BodyMetricEntryView: View"
        )
    metric_type_opening = canonical_body_metric_types[0].end() - 1
    metric_type_end = balanced_delimiter_end(
        metric_entry_code,
        metric_type_opening,
        "{",
        "}",
        "M3 Metrics BodyMetricEntryView",
    )
    metric_type_source = metric_entry_source[
        metric_type_opening + 1:metric_type_end - 1
    ]
    metric_type_code = swift_code_only(metric_type_source)
    metric_body_anchor = "public var body: some View"
    metric_helper_anchor = "private func metricField("

    def unique_direct_metric_member(anchor: str, label: str) -> int:
        declarations = list(re.finditer(re.escape(anchor), metric_type_code))
        direct_declarations = [
            declaration
            for declaration in declarations
            if swift_brace_depth_at(metric_type_code, declaration.start()) == 0
        ]
        if len(declarations) != 1 or len(direct_declarations) != 1:
            raise ValueError(
                "M3 Metrics "
                + label
                + " must be one direct BodyMetricEntryView member"
            )
        return direct_declarations[0].start()

    def require_plain_metric_declaration(anchor: str, label: str) -> None:
        declaration_start = unique_direct_metric_member(anchor, label)
        preceding_declaration_end = metric_type_code.rfind(
            "}",
            0,
            declaration_start,
        )
        if (
            preceding_declaration_end < 0
            or metric_type_code[
                preceding_declaration_end + 1:declaration_start
            ].strip()
        ):
            raise ValueError(
                "M3 Metrics "
                + label
                + " declaration must not use custom result-builder attributes"
            )

    require_plain_metric_declaration(metric_body_anchor, "body")
    require_plain_metric_declaration(metric_helper_anchor, "metricField")
    metric_body_scope = swift_braced_scope(
        metric_type_source,
        metric_body_anchor,
        "M3 Metrics body",
    )
    metric_helper_scope = swift_braced_scope(
        metric_type_source,
        metric_helper_anchor,
        "M3 Metrics shared field helper",
    )
    if conditional_directive.search(swift_code_only(metric_type_source)):
        raise ValueError(
            "M3 Metrics canonical BodyMetricEntryView must not use conditional "
            "compilation around its members"
        )
    for scope_label, scope in (
        ("body", metric_body_scope),
        ("metricField", metric_helper_scope),
    ):
        if conditional_directive.search(swift_code_only(scope)):
            raise ValueError(
                "M3 Metrics "
                + scope_label
                + " must not use conditional compilation around required fields"
            )
    body_text_field_chains = swift_view_modifier_chains(
        metric_body_scope,
        "TextField",
        "M3 Metrics custom-field construction",
    )
    helper_text_field_chains = swift_view_modifier_chains(
        metric_helper_scope,
        "TextField",
        "M3 Metrics shared-field construction",
    )
    if len(body_text_field_chains) != 3 or len(helper_text_field_chains) != 1:
        raise ValueError(
            "M3 Metrics must keep exactly three custom fields in body and one "
            "generic field in metricField"
        )

    def require_direct_metric_context(
        chain: tuple[
            str,
            list[tuple[str, str]],
            str,
            tuple[int, int, int],
            tuple[str, ...],
            tuple[tuple[str, str], ...],
            str,
        ],
        expected_nesting: tuple[int, int, int],
        expected_outer_container: str,
        expected_containers: tuple[str, ...],
        expected_ancestor_postfixes: tuple[str, ...],
        expected_ancestor_boundaries: tuple[str, ...],
    ) -> None:
        (
            _,
            _,
            line_prefix,
            nesting,
            enclosing_headers,
            ancestor_expressions,
            terminator,
        ) = chain
        normalized_headers = tuple(
            re.sub(r"\s+", "", header)
            for header in enclosing_headers
        )
        normalized_ancestor_postfixes = tuple(
            re.sub(
                r"\s+",
                "",
                swift_code_only(postfix, mask_literals=False),
            )
            for postfix, _ in ancestor_expressions
        )
        ancestor_boundaries = tuple(
            boundary for _, boundary in ancestor_expressions
        )
        normalized_expected_postfixes = tuple(
            re.sub(
                r"\s+",
                "",
                swift_code_only(postfix, mask_literals=False),
            )
            for postfix in expected_ancestor_postfixes
        )
        if (
            line_prefix.strip()
            or nesting != expected_nesting
            or not normalized_headers
            or normalized_headers[0] != expected_outer_container
            or normalized_headers[-len(expected_containers):]
            != expected_containers
            or normalized_ancestor_postfixes != normalized_expected_postfixes
            or ancestor_boundaries != expected_ancestor_boundaries
            or not terminator
            or not (terminator == "}" or terminator == "@" or terminator.isalpha())
        ):
            raise ValueError(
                "M3 Metrics TextField must remain a direct ViewBuilder expression "
                "in its exact container"
            )

    for chain in body_text_field_chains:
        require_direct_metric_context(
            chain,
            (4, 0, 0),
            "NavigationStack",
            (
                "VStack(alignment:.leading,spacing:AppSpacing.comfortable)",
                "VStack(alignment:.leading,spacing:AppSpacing.compact)",
            ),
            (
                ".interactiveDismissDisabled(isSaving)"
                ".task { prepareOnce() }",
                ".toolbar {"
                "if shouldOfferToolbarDraftClose {"
                "ToolbarItem(placement: .cancellationAction) {"
                'Button(localized("metrics.entry.close"), action: onClose)'
                '.accessibilityIdentifier("metrics.entry.close")'
                "}"
                "}"
                "}",
                "",
                "",
            ),
            ("", "}", "}", "s"),
        )
    for chain in helper_text_field_chains:
        require_direct_metric_context(
            chain,
            (2, 0, 0),
            "VStack(alignment:.leading,spacing:AppSpacing.small)",
            (
                "VStack(alignment:.leading,spacing:AppSpacing.small)",
                "HStack",
            ),
            ("", ""),
            ("", "}"),
        )

    contextual_metric_text_field_chains = (
        body_text_field_chains + helper_text_field_chains
    )
    metric_text_field_chains = [
        (invocation_arguments, modifiers)
        for invocation_arguments, modifiers, *_ in contextual_metric_text_field_chains
    ]
    for chain_index, (_, modifiers) in enumerate(
        metric_text_field_chains,
        start=1,
    ):
        modifier_names = [name for name, _ in modifiers]
        if modifier_names.count("metricEntryTouchTarget") != 1:
            raise ValueError(
                "M3 Metrics TextField construction site "
                f"{chain_index} must attach exactly one shared touch-target geometry modifier"
            )

    def normalized_swift_fragment(fragment: str) -> str:
        return re.sub(
            r"\s+",
            "",
            swift_code_only(fragment, mask_literals=False),
        )

    expected_metric_fields = {
        '"metrics.entry.custom.name"': (
            'localized("metrics.entry.custom.name"), text: $customName',
            (
                ("textFieldStyle", ".roundedBorder"),
                ("metricEntryTouchTarget", ""),
                ("focused", "focus"),
                ("accessibilityLabel", 'localized("metrics.entry.custom.name")'),
                ("accessibilityIdentifier", '"metrics.entry.custom.name"'),
            ),
        ),
        '"metrics.entry.custom.value"': (
            'localized("metrics.entry.custom.value"), text: $customValueText',
            (
                ("keyboardType", ".decimalPad"),
                ("textFieldStyle", ".roundedBorder"),
                ("metricEntryTouchTarget", ""),
                ("focused", "focus"),
                ("accessibilityLabel", 'localized("metrics.entry.custom.value")'),
                ("accessibilityIdentifier", '"metrics.entry.custom.value"'),
            ),
        ),
        '"metrics.entry.custom.unit"': (
            'localized("metrics.entry.custom.unit"), text: $customUnit',
            (
                ("textFieldStyle", ".roundedBorder"),
                ("metricEntryTouchTarget", ""),
                ("focused", "focus"),
                ("accessibilityLabel", 'localized("metrics.entry.custom.unit")'),
                ("accessibilityIdentifier", '"metrics.entry.custom.unit"'),
            ),
        ),
        "identifier": (
            "title, text: text",
            (
                ("keyboardType", ".decimalPad"),
                ("textFieldStyle", ".roundedBorder"),
                ("metricEntryTouchTarget", ""),
                ("focused", "focus"),
                ("accessibilityLabel", "title"),
                ("accessibilityIdentifier", "identifier"),
            ),
        ),
    }
    seen_metric_identifiers: set[str] = set()
    for chain_index, (invocation_arguments, modifiers) in enumerate(
        metric_text_field_chains,
        start=1,
    ):
        identifier_arguments = [
            arguments
            for name, arguments in modifiers
            if name == "accessibilityIdentifier"
        ]
        if len(identifier_arguments) != 1:
            raise ValueError(
                "M3 Metrics TextField construction site "
                f"{chain_index} must attach exactly one direct accessibility identifier"
            )
        identifier_key = normalized_swift_fragment(identifier_arguments[0])
        if (
            identifier_key not in expected_metric_fields
            or identifier_key in seen_metric_identifiers
        ):
            raise ValueError(
                "M3 Metrics TextField construction sites must expose each exact "
                "identifier once"
            )
        seen_metric_identifiers.add(identifier_key)
        expected_invocation, expected_modifiers = expected_metric_fields[identifier_key]
        actual_modifiers = tuple(
            (name, normalized_swift_fragment(arguments))
            for name, arguments in modifiers
        )
        normalized_expected_modifiers = tuple(
            (name, normalized_swift_fragment(arguments))
            for name, arguments in expected_modifiers
        )
        if (
            normalized_swift_fragment(invocation_arguments)
            != normalized_swift_fragment(expected_invocation)
            or actual_modifiers != normalized_expected_modifiers
        ):
            raise ValueError(
                "M3 Metrics TextField must bind its exact initializer, state, "
                "modifier order, label, and identifier: "
                f"{identifier_key}"
            )
    if seen_metric_identifiers != set(expected_metric_fields):
        raise ValueError(
            "M3 Metrics TextField construction sites must expose every exact identifier"
        )
    touch_target_anchor = "func metricEntryTouchTarget() -> some View"
    touch_target_declarations: list[tuple[Path, re.Match[str]]] = []
    for module_source in metrics_module_sources:
        module_code = swift_code_only(module_source.read_text(encoding="utf-8"))
        touch_target_declarations.extend(
            (module_source, declaration)
            for declaration in re.finditer(
                r"\bfunc\s+`?metricEntryTouchTarget`?\s*\(",
                module_code,
            )
        )
    touch_target_start = metric_entry_code.find(touch_target_anchor)
    touch_target_owner_candidates: list[tuple[int, int]] = []
    for owner_match in re.finditer(
        r"(?m)^[ \t]*private[ \t]+extension[ \t]+View[ \t]*\{",
        metric_entry_code,
    ):
        owner_opening = owner_match.end() - 1
        owner_end = balanced_delimiter_end(
            metric_entry_code,
            owner_opening,
            "{",
            "}",
            "M3 Metrics private View extension",
        )
        if owner_opening < touch_target_start < owner_end:
            touch_target_owner_candidates.append((owner_opening, owner_end))
    if len(touch_target_owner_candidates) == 1:
        touch_target_owner_opening, touch_target_owner_end = (
            touch_target_owner_candidates[0]
        )
        touch_target_owner_code = metric_entry_code[
            touch_target_owner_opening + 1:touch_target_owner_end - 1
        ]
        touch_target_owner_source = metric_entry_source[
            touch_target_owner_opening + 1:touch_target_owner_end - 1
        ]
    else:
        touch_target_owner_opening = -1
        touch_target_owner_code = ""
        touch_target_owner_source = ""
    owner_touch_target_start = touch_target_owner_code.find(touch_target_anchor)
    owner_touch_target_declarations = list(
        re.finditer(
            r"\bfunc\s+`?metricEntryTouchTarget`?\s*\(",
            touch_target_owner_code,
        )
    )
    if (
        len(touch_target_declarations) != 1
        or touch_target_declarations[0][0] != target_root / metric_entry_relative
        or touch_target_start < 0
        or touch_target_owner_opening < 0
        or len(owner_touch_target_declarations) != 1
        or owner_touch_target_start < 0
        or touch_target_owner_code[:owner_touch_target_start].strip()
    ):
        raise ValueError(
            "M3 Metrics touch-target helper must have one plain declaration in "
            "its exact private View extension"
        )
    touch_target_scope = swift_braced_scope(
        touch_target_owner_source,
        touch_target_anchor,
        "M3 Metrics touch-target helper",
    )
    touch_target_function_opening = touch_target_owner_code.find(
        "{",
        owner_touch_target_start + len(touch_target_anchor),
    )
    touch_target_function_end = balanced_delimiter_end(
        touch_target_owner_code,
        touch_target_function_opening,
        "{",
        "}",
        "M3 Metrics touch-target helper",
    )
    if touch_target_owner_code[touch_target_function_end:].strip():
        raise ValueError(
            "M3 Metrics touch-target helper must be the only member of its "
            "exact private View extension"
        )
    if conditional_directive.search(swift_code_only(touch_target_scope)):
        raise ValueError(
            "M3 Metrics touch-target helper must not use conditional compilation"
        )
    normalized_touch_target_scope = re.sub(
        r"\s+",
        "",
        swift_code_only(touch_target_scope, mask_literals=False),
    )
    if normalized_touch_target_scope != (
        "frame(minHeight:52)"
        ".contentShape(.interaction,Rectangle())"
    ):
        raise ValueError(
            "M3 Metrics touch-target helper must remain the exact direct "
            "frame and contentShape chain"
        )
    def require_metric_type_tokens(
        anchor: str,
        tokens: set[str],
        label: str,
    ) -> None:
        unique_direct_metric_member(anchor, label)
        scope = swift_braced_scope(metric_type_source, anchor, label)
        active_scope = active_source(scope, comment_style="swift")
        missing = sorted(token for token in tokens if token not in active_scope)
        if missing:
            raise ValueError(
                "BodyMetricEntryView scoped "
                + label
                + " is missing: "
                + ", ".join(missing)
            )

    require_metric_type_tokens(
        "private var shouldOfferDraftClose: Bool",
        {"!isSaving && !isSaved"},
        "M3 Metrics draft-close policy",
    )
    require_metric_type_tokens(
        "private var shouldOfferSecondaryDraftClose: Bool",
        {"shouldOfferDraftClose && !dynamicTypeSize.isAccessibilitySize"},
        "M3 Metrics inline draft-close placement policy",
    )
    require_metric_type_tokens(
        "private var shouldOfferToolbarDraftClose: Bool",
        {"shouldOfferDraftClose && dynamicTypeSize.isAccessibilitySize"},
        "M3 Metrics AX draft-close placement policy",
    )
    require_metric_type_tokens(
        "private var secondaryTitle: String?",
        {
            "if shouldOfferSecondaryDraftClose",
            'return localized("metrics.entry.close")',
        },
        "M3 Metrics draft-close title",
    )
    require_metric_type_tokens(
        "private var secondaryIdentifier: String?",
        {
            "if shouldOfferSecondaryDraftClose",
            'return "metrics.entry.close"',
        },
        "M3 Metrics draft-close identifier",
    )
    require_metric_type_tokens(
        "private var secondaryAction: (() -> Void)?",
        {"guard shouldOfferSecondaryDraftClose", "onClose()"},
        "M3 Metrics draft-close action",
    )
    require_metric_type_tokens(
        "public var body: some View",
        {
            ".toolbar",
            "if shouldOfferToolbarDraftClose",
            "ToolbarItem(placement: .cancellationAction)",
            'Button(localized("metrics.entry.close"), action: onClose)',
            '.accessibilityIdentifier("metrics.entry.close")',
        },
        "M3 Metrics immediately operable AX draft close",
    )
    require_scoped_tokens(
        target_root,
        "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleEntryView.swift",
        "private var draftCloseTitle: String?",
        {
            "guard !isSaving, !isSaved",
            'return localized("lifestyle.entry.close")',
        },
        "M3 Lifestyle draft-close title",
    )
    require_scoped_tokens(
        target_root,
        "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleEntryView.swift",
        "private var draftCloseAction: (() -> Void)?",
        {"guard draftCloseTitle != nil", "onClose()"},
        "M3 Lifestyle draft-close action",
    )
    require_scoped_tokens(
        target_root,
        "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/SystemPhotosPickerView.swift",
        "public var body: some View",
        {
            ".disabled(!SystemPhotoPickerAvailability.isEnabled(for: accessState))",
            "photoLibraryAccessEvidence(accessState)",
        },
        "M3 shipped picker policy binding",
    )
    picker_source = (
        target_root
        / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/"
        "SystemPhotosPickerView.swift"
    ).read_text(encoding="utf-8")
    picker_body = braced_scope(
        picker_source,
        "public var body: some View",
        "M3 shipped picker body",
    )
    picker_modifiers, picker_residue = swift_view_modifier_arguments(
        picker_body,
        "PhotosPicker",
        "M3 shipped picker body",
    )
    picker_code = swift_code_only(picker_body)
    if len(re.findall(r"\bPhotosPicker\s*\(", picker_code)) != 1:
        raise ValueError("M3 shipped picker body must contain exactly one active PhotosPicker")
    disabled_arguments = [
        re.sub(r"\s+", "", arguments)
        for name, arguments in picker_modifiers
        if name == "disabled"
    ]
    expected_disabled_argument = (
        "!SystemPhotoPickerAvailability.isEnabled(for:accessState)"
    )
    if disabled_arguments != [expected_disabled_argument]:
        raise ValueError(
            "M3 shipped picker must attach its exact access-state policy to PhotosPicker"
        )
    evidence_arguments = [
        re.sub(r"\s+", "", arguments)
        for name, arguments in picker_modifiers
        if name == "photoLibraryAccessEvidence"
    ]
    if evidence_arguments != ["accessState"]:
        raise ValueError(
            "M3 shipped picker must attach exact access-state evidence to PhotosPicker"
        )
    identifier_arguments = [
        re.sub(r"\s+", "", arguments)
        for name, arguments in picker_modifiers
        if name == "accessibilityIdentifier"
    ]
    if identifier_arguments != ['"photos.picker"']:
        raise ValueError(
            "M3 shipped picker must attach its exact accessibility identifier to PhotosPicker"
        )
    allowed_picker_modifiers = {
        "buttonStyle",
        "accessibilityIdentifier",
        "photoLibraryAccessEvidence",
        "disabled",
        "onChange",
        "task",
    }
    unexpected_picker_modifiers = sorted(
        name for name, _ in picker_modifiers if name not in allowed_picker_modifiers
    )
    if unexpected_picker_modifiers:
        raise ValueError(
            "M3 shipped picker contains visibility-changing or unknown modifiers: "
            + ", ".join(unexpected_picker_modifiers)
        )
    if picker_residue.strip():
        raise ValueError("M3 shipped picker body must contain only its PhotosPicker chain")
    require_scoped_tokens(
        target_root,
        "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/LifestyleProgressSection.swift",
        "private func summaryCard(",
        {
            ".accessibilityValue(lines.joined(separator:",
            ".accessibilityIdentifier(identifier)",
        },
        "M3 lifestyle summary accessibility",
    )


def verify_privacy(target_root: Path) -> None:
    sources: list[Path] = []
    for relative in PRIVACY_ROOTS:
        path = target_root / relative
        if path.is_dir():
            sources.extend(path.rglob("*.swift"))
    for relative in PRIVACY_APP_FILES:
        path = target_root / relative
        if path.is_file():
            sources.append(path)
    for path in sorted(set(sources)):
        text = swift_code_only(path.read_text(encoding="utf-8"))
        match = FORBIDDEN_PRIVACY.search(text)
        if match:
            relative = path.relative_to(target_root)
            raise ValueError(
                f"M3 production privacy scan rejected {match.group(0)!r} in {relative}"
            )


def verify_evidence(target_root: Path) -> None:
    if not EVIDENCE_REQUIRED:
        return
    path = target_root / EVIDENCE_RELATIVE
    if not path.is_file():
        raise ValueError(f"Missing M3 acceptance evidence: {EVIDENCE_RELATIVE}")
    text = path.read_text(encoding="utf-8")
    accepted_line = (
        f"Accepted M3.12 implementation SHA: `{ACCEPTED_M312_SHA}`"
    )
    if accepted_line not in text:
        raise ValueError(
            f"{EVIDENCE_RELATIVE} must name the exact accepted M3.12 "
            f"implementation SHA {ACCEPTED_M312_SHA}"
        )

    run_url = (
        "https://github.com/Fatihzxc/ios_app/actions/runs/"
        f"{ACCEPTED_M312_RUN}"
    )
    required = {
        "# M3 acceptance evidence",
        "## RED/GREEN task history",
        "## Final GitHub Actions run",
        "## Screenshot and artifact evidence",
        "## Privacy scan",
        "## Review record",
        "## Remote record",
        run_url,
        "Privacy scan: PASS",
        "Critical: 0; Important: 0; Minor: 0; verdict: READY",
        "Fable review: NOT RUN",
    }
    required.update(EVIDENCE_ARTIFACTS)
    missing = sorted(token for token in required if token not in text)
    if missing:
        raise ValueError(
            f"{EVIDENCE_RELATIVE} is missing evidence contracts: {missing}"
        )

    for task in EVIDENCE_TASKS:
        if re.search(
            rf"^\|\s*{re.escape(task)}\s*\|",
            text,
            flags=re.MULTILINE,
        ) is None:
            raise ValueError(
                f"{EVIDENCE_RELATIVE} is missing the exact {task} evidence row"
            )

    for label in (
        "CloudKit signed two-device transfer",
        "Real notification delivery",
    ):
        expected = f"- {label}: NOT RUN"
        matching = [line.strip() for line in text.splitlines() if label in line]
        if matching != [expected]:
            raise ValueError(
                f"{EVIDENCE_RELATIVE} must record only the honest device/service "
                f"claim {expected!r}; found {matching}"
            )


def verify(target_root: Path, verification_mode: str) -> None:
    require_tokens(target_root, RED_REQUIRED, "M3.12 RED")
    verify_red_structure(target_root)
    verify_privacy(target_root)
    if verification_mode != "red":
        require_tokens(target_root, PRODUCTION_REQUIRED, "M3.12 production")
        verify_production_structure(target_root)
        verify_evidence(target_root)


def expect_failure(target_root: Path, verification_mode: str, expected: str) -> None:
    try:
        verify(target_root, verification_mode)
    except ValueError as error:
        if expected not in str(error):
            raise SystemExit(
                f"M3.12 mutation failed for the wrong reason; expected {expected!r}: {error}"
            ) from error
    else:
        raise SystemExit(f"M3.12 verifier mutation escaped: {expected}")


def copy_real_fixture(source_root: Path, fixture: Path) -> None:
    for relative in (
        ".github",
        "App",
        "Packages/HealthTrackingModules/Sources",
        "HealthTrackingAppTests",
        "HealthTrackingAppUITests",
        "scripts",
        "docs",
        "project.yml",
    ):
        source = source_root / relative
        destination = fixture / relative
        if source.is_dir():
            shutil.copytree(source, destination, dirs_exist_ok=True)
        elif source.is_file():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)


def materialize_production_self_test_fixture(fixture: Path) -> None:
    expected = set(PRODUCTION_REQUIRED)
    actual = set(PRODUCTION_SELF_TEST_FILES)
    if actual != expected:
        missing = sorted(expected - actual)
        unexpected = sorted(actual - expected)
        raise SystemExit(
            "M3.12 production self-test fixture does not match its contracts; "
            f"missing={missing}, unexpected={unexpected}"
        )
    for relative, content in PRODUCTION_SELF_TEST_FILES.items():
        path = fixture / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content.strip() + "\n", encoding="utf-8")


def write_evidence_self_test_fixture(fixture: Path) -> None:
    evidence = fixture / EVIDENCE_RELATIVE
    evidence.parent.mkdir(parents=True, exist_ok=True)
    task_rows = "\n".join(
        f"| {task} | RED SHA/run | accepted SHA/run |" for task in EVIDENCE_TASKS
    )
    artifact_rows = "\n".join(
        f"- Artifact `{artifact}`" for artifact in EVIDENCE_ARTIFACTS
    )
    evidence.write_text(
        "\n".join(
            (
                "# M3 acceptance evidence",
                "",
                f"Accepted M3.12 implementation SHA: `{ACCEPTED_M312_SHA}`",
                "",
                "## RED/GREEN task history",
                "",
                "| Task | RED | Accepted implementation |",
                "| --- | --- | --- |",
                task_rows,
                "",
                "## Final GitHub Actions run",
                "",
                (
                    "https://github.com/Fatihzxc/ios_app/actions/runs/"
                    f"{ACCEPTED_M312_RUN}"
                ),
                "",
                "## Screenshot and artifact evidence",
                "",
                artifact_rows,
                "",
                "## Privacy scan",
                "",
                "- Privacy scan: PASS",
                "",
                "## Review record",
                "",
                "- Critical: 0; Important: 0; Minor: 0; verdict: READY",
                "- Fable review: NOT RUN",
                "",
                "## Remote record",
                "",
                f"- GitHub implementation tip: `{ACCEPTED_M312_SHA}`",
                "- Gitea reconciliation: bounded and non-blocking",
                "",
                "## Device and external-service limits",
                "",
                "- CloudKit signed two-device transfer: NOT RUN",
                "- Real notification delivery: NOT RUN",
            )
        )
        + "\n",
        encoding="utf-8",
    )


def mutate_once(path: Path, before: str, after: str) -> str:
    original = path.read_text(encoding="utf-8")
    if before not in original:
        raise SystemExit(f"M3.12 self-test mutation source is missing: {before}")
    path.write_text(original.replace(before, after, 1), encoding="utf-8")
    return original


def mutate_all(path: Path, before: str, after: str) -> str:
    original = path.read_text(encoding="utf-8")
    if before not in original:
        raise SystemExit(f"M3.12 self-test mutation source is missing: {before}")
    path.write_text(original.replace(before, after), encoding="utf-8")
    return original


def replace_swift_braced_body(path: Path, anchor: str, replacement: str) -> str:
    original = path.read_text(encoding="utf-8")
    code = swift_code_only(original)
    start = code.find(anchor)
    if start < 0:
        raise SystemExit(f"M3.12 self-test braced mutation anchor is missing: {anchor}")
    opening = code.find("{", start + len(anchor))
    if opening < 0:
        raise SystemExit(f"M3.12 self-test braced mutation opening is missing: {anchor}")
    end = balanced_delimiter_end(
        code,
        opening,
        "{",
        "}",
        f"M3.12 self-test {anchor}",
    )
    path.write_text(
        original[:opening + 1] + "\n" + replacement + "\n" + original[end - 1:],
        encoding="utf-8",
    )
    return original


def wrap_swift_braced_body_in_uninvoked_closure(path: Path, anchor: str) -> str:
    original = path.read_text(encoding="utf-8")
    code = swift_code_only(original)
    start = code.find(anchor)
    if start < 0:
        raise SystemExit(f"M3.12 self-test closure anchor is missing: {anchor}")
    opening = code.find("{", start + len(anchor))
    end = balanced_delimiter_end(
        code,
        opening,
        "{",
        "}",
        f"M3.12 self-test closure {anchor}",
    )
    body = original[opening + 1:end - 1]
    replacement = (
        "\n        let m312UninvokedContract = {"
        + body
        + "\n        }\n        _ = m312UninvokedContract\n"
    )
    path.write_text(
        original[:opening + 1] + replacement + original[end - 1:],
        encoding="utf-8",
    )
    return original


def self_test(source_root: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="m3-acceptance-verifier-") as directory:
        fixture = Path(directory)
        copy_real_fixture(source_root, fixture)
        verify(fixture, "red")

        acceptance = fixture / "HealthTrackingAppUITests/M3AcceptanceUITests.swift"
        for mutation_index, token in enumerate((
            "progress.metrics.action",
            "progress.lifestyle.action",
            "progress.posture.action",
            "progress.health-check.action",
            "progress.bloodwork.action",
            "progress.photos.action",
            "today.bloodwork.action",
        )):
            original = mutate_once(
                acceptance,
                token,
                f"removed-route-{mutation_index}",
            )
            expect_failure(fixture, "red", token)
            acceptance.write_text(original, encoding="utf-8")

        for mutation_index, token in enumerate((
            "assertRouterInstantiationCount(0, in: app)",
            "assertRouterInstantiationCount(1, in: app)",
        )):
            original = mutate_all(
                acceptance,
                token,
                f"removed-lazy-count-{mutation_index}",
            )
            expect_failure(fixture, "red", token)
            acceptance.write_text(original, encoding="utf-8")

        route_anchor = (
            "    func testTodayAndProgressExposeEveryM3TrackerEntryThroughOneLazyRouter() {\n"
        )
        original = mutate_once(acceptance, route_anchor, route_anchor + "        return\n")
        expect_failure(fixture, "red", "exits before assertions")
        acceptance.write_text(original, encoding="utf-8")

        original = mutate_once(
            acceptance,
            route_anchor,
            route_anchor + "        let bypass = true; if bypass { return }\n",
        )
        expect_failure(fixture, "red", "return path")
        acceptance.write_text(original, encoding="utf-8")

        original = acceptance.read_text(encoding="utf-8")
        decoy_route = original.replace(
            '("progress.photos.action", "photos.lifecycle.content", "photos.close"),',
            '("progress.photos.detached", "photos.lifecycle.content", "photos.close"),',
            1,
        ).replace(
            route_anchor,
            route_anchor
            + '        let ignoredProgressRoute = '
            + '("progress.photos.action", "photos.lifecycle.content", "photos.close")\n',
            1,
        )
        if decoy_route == original:
            raise SystemExit("M3.12 self-test route-decoy mutation source is missing")
        acceptance.write_text(decoy_route, encoding="utf-8")
        expect_failure(fixture, "red", "Progress photos route binding")
        acceptance.write_text(original, encoding="utf-8")

        original = mutate_once(
            acceptance,
            "for route in routes {",
            "for route in routes.prefix(0) {",
        )
        expect_failure(fixture, "red", "must end after its direct array literal")
        acceptance.write_text(original, encoding="utf-8")

        original = mutate_once(
            acceptance,
            "for route in routes {",
            (
                "for route in routes {\n"
                '            if route.action == "progress.photos.action" { continue }'
            ),
        )
        expect_failure(fixture, "red", "must explicitly close every route")
        acceptance.write_text(original, encoding="utf-8")

        original = replace_swift_braced_body(
            acceptance,
            "private func openAndCloseSheet(",
            "        _ = (action, content, close, app)",
        )
        expect_failure(fixture, "red", "M3 explicit-close route helper")
        acceptance.write_text(original, encoding="utf-8")

        original = mutate_once(
            acceptance,
            "app.buttons[close]",
            "identified(close, in: app)",
        )
        expect_failure(fixture, "red", "app.buttons[close]")
        acceptance.write_text(original, encoding="utf-8")

        original = mutate_once(
            acceptance,
            "        actionElement.tap()\n        let contentElement",
            "        _ = false ? actionElement.tap() : ()\n        let contentElement",
        )
        expect_failure(fixture, "red", "M3 explicit-close route helper")
        acceptance.write_text(original, encoding="utf-8")

        original = wrap_swift_braced_body_in_uninvoked_closure(
            acceptance,
            "private func openAndCloseSheet(",
        )
        expect_failure(fixture, "red", "must execute at top level")
        acceptance.write_text(original, encoding="utf-8")

        original = wrap_swift_braced_body_in_uninvoked_closure(
            acceptance,
            "private func assertRouterInstantiationCount(_ expected: String",
        )
        expect_failure(fixture, "red", "must execute at top level")
        acceptance.write_text(original, encoding="utf-8")

        original = wrap_swift_braced_body_in_uninvoked_closure(
            acceptance,
            "private func assertLifestyleSummary(",
        )
        expect_failure(fixture, "red", "must execute at top level")
        acceptance.write_text(original, encoding="utf-8")

        original = mutate_once(
            acceptance,
            (
                "    private func assertRouterInstantiationCount("
                "_ expected: String, in app: XCUIApplication) {\n"
            ),
            (
                "    private func assertRouterInstantiationCount("
                "_ expected: String, in app: XCUIApplication) {\n"
                "        return\n"
            ),
        )
        expect_failure(fixture, "red", "return path or skip")
        acceptance.write_text(original, encoding="utf-8")

        original = mutate_once(
            acceptance,
            (
                "        in app: XCUIApplication\n"
                "    ) {\n"
                "        let loaded = require("
            ),
            (
                "        in app: XCUIApplication\n"
                "    ) {\n"
                "        return\n"
                "        let loaded = require("
            ),
        )
        expect_failure(fixture, "red", "return path or skip")
        acceptance.write_text(original, encoding="utf-8")

        original = mutate_once(
            acceptance,
            "assertExactlyOneProgressEntryActionPerTracker(in: probe)",
            "removedDuplicateProgressEntryAssertion(in: probe)",
        )
        expect_failure(
            fixture,
            "red",
            "assertExactlyOneProgressEntryActionPerTracker(in: probe)",
        )
        acceptance.write_text(original, encoding="utf-8")

        original = mutate_once(
            acceptance,
            'assertFixedNowEvidence("2026-08-27T10:00:00Z", in: app)',
            'removedFixedNowEvidence("2026-08-27T10:00:00Z", in: app)',
        )
        expect_failure(fixture, "red", "assertFixedNowEvidence")
        acceptance.write_text(original, encoding="utf-8")

        original = acceptance.read_text(encoding="utf-8")
        detached = original.replace(
            '"progress.photos.action"',
            '"progress.photos.detached"',
            1,
        ) + '\nprivate let detachedProgressPhotosToken = "progress.photos.action"\n'
        acceptance.write_text(detached, encoding="utf-8")
        expect_failure(fixture, "red", "progress.photos.action")
        acceptance.write_text(original, encoding="utf-8")

        for token in ('moodScore: "6"', 'moodScore: "7"'):
            original = mutate_once(acceptance, token, token.replace("moodScore", "removedMood"))
            expect_failure(fixture, "red", token)
            acceptance.write_text(original, encoding="utf-8")

        picker_test = fixture / "HealthTrackingAppUITests/ProgressPhotoLifecycleUITests.swift"
        original = mutate_once(
            picker_test,
            "picker.value as? String",
            "picker.label as String",
        )
        expect_failure(fixture, "red", "picker.value as? String")
        picker_test.write_text(original, encoding="utf-8")

        accessibility_test = fixture / "HealthTrackingAppUITests/M3AccessibilityUITests.swift"
        for mutation_index, token in enumerate((
            '"m3-progress-\\(appearance.rawValue)-\\(textSize.rawValue)"',
            '"m3-progress-reduce-motion"',
            '"m3-progress-high-contrast"',
            '"m3-progress-small-ax5"',
        )):
            original = mutate_once(
                accessibility_test,
                token,
                f'"removed-accessibility-evidence-{mutation_index}"',
            )
            expect_failure(fixture, "red", token)
            accessibility_test.write_text(original, encoding="utf-8")

        original = mutate_once(
            accessibility_test,
            "        metricClose.tap()\n",
            "        if false { metricClose.tap() }\n",
        )
        expect_failure(
            fixture,
            "red",
            "M3 dedicated small-phone test must execute its exact explicit-close lifecycle",
        )
        accessibility_test.write_text(original, encoding="utf-8")

        original = mutate_once(
            accessibility_test,
            "            metricClose.isHittable,\n",
            "            true,\n",
        )
        expect_failure(fixture, "red", "metricClose.isHittable")
        accessibility_test.write_text(original, encoding="utf-8")

        original = mutate_once(
            accessibility_test,
            'app.buttons["metrics.entry.close"]',
            'identified("metrics.entry.close", in: app)',
        )
        expect_failure(fixture, "red", 'app.buttons["metrics.entry.close"]')
        accessibility_test.write_text(original, encoding="utf-8")

        original = mutate_once(
            accessibility_test,
            "            metricClose.frame.midY,\n",
            "            0,\n",
        )
        expect_failure(fixture, "red", "metricClose.frame.midY")
        accessibility_test.write_text(original, encoding="utf-8")

        original = mutate_once(
            accessibility_test,
            'NSPredicate(format: "exists == false")',
            'NSPredicate(format: "exists == true")',
        )
        expect_failure(fixture, "red", 'NSPredicate(format: "exists == false")')
        accessibility_test.write_text(original, encoding="utf-8")

        original = mutate_once(
            accessibility_test,
            "for contract in fields {",
            "for contract in fields.prefix(0) {",
        )
        expect_failure(
            fixture,
            "red",
            "must end after its direct array literal",
        )
        accessibility_test.write_text(original, encoding="utf-8")

        original = accessibility_test.read_text(encoding="utf-8")
        fields_opening = (
            "        let fields: [(identifier: String, label: String)] = [\n"
        )
        fields_closing = (
            '            ("metrics.entry.custom.unit", "Birim"),\n'
            "        ]\n"
            "        for contract in fields {"
        )
        if fields_opening not in original or fields_closing not in original:
            raise SystemExit(
                "M3.12 self-test direct-array wrapper mutation anchors are missing"
            )
        accessibility_test.write_text(
            original.replace(
                fields_opening,
                "        let fields: [(identifier: String, label: String)] = Array([\n",
                1,
            ).replace(
                fields_closing,
                '            ("metrics.entry.custom.unit", "Birim"),\n'
                "        ].prefix(0))\n"
                "        for contract in fields {",
                1,
            ),
            encoding="utf-8",
        )
        expect_failure(fixture, "red", "must use a direct array literal")
        accessibility_test.write_text(original, encoding="utf-8")

        original = accessibility_test.read_text(encoding="utf-8")
        if fields_closing not in original:
            raise SystemExit(
                "M3.12 self-test trailing-array expression mutation anchor is missing"
            )
        accessibility_test.write_text(
            original.replace(
                fields_closing,
                '            ("metrics.entry.custom.unit", "Birim"),\n'
                "        ].prefix(0).map { $0 }\n"
                "        for contract in fields {",
                1,
            ),
            encoding="utf-8",
        )
        expect_failure(fixture, "red", "must end after its direct array literal")
        accessibility_test.write_text(original, encoding="utf-8")

        original = mutate_once(
            accessibility_test,
            fields_opening,
            (
                "        let fields: [(identifier: String, label: String)] = Array()\n"
                "        let detachedFields = [\n"
            ),
        )
        expect_failure(fixture, "red", "must use a direct array literal")
        accessibility_test.write_text(original, encoding="utf-8")

        original = accessibility_test.read_text(encoding="utf-8")
        accessibility_test.write_text(
            original.replace(
                '("metrics.entry.custom.name", "Ölçüm adı")',
                '("metrics.entry.custom.name", "Değer")',
                1,
            ).replace(
                '("metrics.entry.custom.value", "Değer")',
                '("metrics.entry.custom.value", "Ölçüm adı")',
                1,
            ),
            encoding="utf-8",
        )
        expect_failure(fixture, "red", "identifier-label contracts")
        accessibility_test.write_text(original, encoding="utf-8")

        original = accessibility_test.read_text(encoding="utf-8")
        import_anchor = "import XCTest\n"
        if import_anchor not in original:
            raise SystemExit("M3.12 self-test XCTest import mutation anchor is missing")
        assertion_shadow_mutations = (
            original
            + "\nprivate extension M3AccessibilityUITests {\n"
            + "    func XCTAssertGreaterThanOrEqual(_ lhs: CGFloat, _ rhs: CGFloat) {}\n"
            + "}\n",
            original
            + "\nprivate let XCTAssertTrue: (Bool) -> Void = { _ in }\n",
            original
            + "\nprivate let (XCTAssertFalse, m312ShadowTupleSentinel): "
            + "((Bool) -> Void, Int) = ({ _ in }, 0)\n",
            original
            + "\nlet (\n"
            + "    (m312NestedSentinelA, m312NestedSentinelB),\n"
            + "    XCTAssertGreaterThanOrEqual\n"
            + "): ((Int, Int), (CGFloat, CGFloat) -> Void) = (\n"
            + "    (0, 0),\n"
            + "    { _, _ in }\n"
            + ")\n",
            original
            + "\nlet (\n"
            + "    sentinels: (m312LabeledSentinelA, m312LabeledSentinelB),\n"
            + "    assertion: XCTAssertGreaterThanOrEqual\n"
            + "): ((Int, Int), (CGFloat, CGFloat) -> Void) = (\n"
            + "    (0, 0),\n"
            + "    { _, _ in }\n"
            + ")\n",
            original
            + "\nlet (`XCTAssertGreaterThanOrEqual`, m312BacktickSentinel): "
            + "((CGFloat, CGFloat) -> Void, Int) = ({ _, _ in }, 0)\n",
            original.replace(
                import_anchor,
                import_anchor
                + "import func M312ShadowAssertions.XCTAssertGreaterThanOrEqual\n",
                1,
            ),
        )
        for mutated in assertion_shadow_mutations:
            accessibility_test.write_text(mutated, encoding="utf-8")
            expect_failure(
                fixture,
                "red",
                (
                    "must import only Foundation and XCTest"
                    if "import func M312ShadowAssertions" in mutated
                    else "must not shadow XCTest assertions"
                ),
            )
        accessibility_test.write_text(original, encoding="utf-8")

        accessibility_test.write_text(
            original.replace(
                import_anchor,
                import_anchor + "import M312ShadowAssertions\n",
                1,
            ),
            encoding="utf-8",
        )
        expect_failure(fixture, "red", "must import only Foundation and XCTest")
        accessibility_test.write_text(original, encoding="utf-8")

        accessibility_test.write_text(
            original
            + "\n// func XCTAssertGreaterThanOrEqual(_ lhs: CGFloat, _ rhs: CGFloat) {}\n"
            + 'private let m312AssertionShadowDecoy = "func XCTAssertTrue(_ value: Bool) {}"\n',
            encoding="utf-8",
        )
        verify(fixture, "red")
        accessibility_test.write_text(original, encoding="utf-8")

        original = mutate_once(
            accessibility_test,
            "            XCTAssertTrue(field.isHittable)\n",
            "            if false { XCTAssertTrue(field.isHittable) }\n",
        )
        expect_failure(
            fixture,
            "red",
            "execute every exact field assertion",
        )
        accessibility_test.write_text(original, encoding="utf-8")

        original = mutate_once(
            accessibility_test,
            "            XCTAssertEqual(field.label, contract.label)\n",
            "            XCTAssertFalse(field.label.isEmpty)\n",
        )
        expect_failure(
            fixture,
            "red",
            "XCTAssertEqual(field.label, contract.label)",
        )
        accessibility_test.write_text(original, encoding="utf-8")

        workflow_path = fixture / ".github/workflows/ios.yml"
        original = mutate_once(
            workflow_path,
            f"    if: {M4_SAFE_FULL_JOB_GUARD}",
            "    if: false",
        )
        expect_failure(
            fixture,
            "red",
            "must use the exact M4-safe full-job guard",
        )
        workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            "        run: scripts/test-ios.sh --m312-red-only",
            "        # run: scripts/test-ios.sh --m312-red-only",
        )
        expect_failure(fixture, "red", "scripts/test-ios.sh --m312-red-only")
        workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            "        run: scripts/test-ios.sh --m312-red-only",
            "        run: echo bypassed # scripts/test-ios.sh --m312-red-only",
        )
        expect_failure(fixture, "red", "detached from its RED command")
        workflow_path.write_text(original, encoding="utf-8")

        touch_target_command = (
            "        run: scripts/test-ios.sh --only-testing "
            "HealthTrackingAppUITests/M3AccessibilityUITests"
        )
        original = mutate_once(
            workflow_path,
            touch_target_command,
            "        run: echo bypassed # " + touch_target_command.strip(),
        )
        expect_failure(fixture, "red", "detached from its exact UI test")
        workflow_path.write_text(original, encoding="utf-8")

        touch_target_step = (
            "      - name: Targeted M3.12 text-field touch-target regression\n"
            "        timeout-minutes: 20\n"
            + touch_target_command
            + "\n"
        )
        workflow_source = workflow_path.read_text(encoding="utf-8")
        if touch_target_step not in workflow_source:
            raise SystemExit("M3.12 self-test touch-target step source is missing")
        workflow_path.write_text(
            workflow_source.replace(touch_target_step, "", 1)
            + "\n  detached-m3-touch-target:\n"
            + "    if: false\n"
            + "    runs-on: macos-15\n"
            + "    steps:\n"
            + touch_target_step,
            encoding="utf-8",
        )
        expect_failure(
            fixture,
            "red",
            "exactly one active named step",
        )
        workflow_path.write_text(workflow_source, encoding="utf-8")

        indented_touch_target_step = "".join(
            "    " + line if line.strip() else line
            for line in touch_target_step.splitlines(keepends=True)
        )
        touch_target_carrier = (
            "      - name: M3 touch-target metadata carrier\n"
            "        run: |\n"
            "          cat <<'YAML' >/dev/null\n"
            + indented_touch_target_step
            + "          YAML\n"
        )
        workflow_path.write_text(
            workflow_source.replace(
                touch_target_step,
                touch_target_carrier,
                1,
            ),
            encoding="utf-8",
        )
        expect_failure(
            fixture,
            "red",
            "exactly one active named step",
        )
        workflow_path.write_text(workflow_source, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            (
                "      - name: Targeted M3.12 text-field touch-target regression\n"
                "        timeout-minutes: 20\n"
            ),
            (
                "      - name: Targeted M3.12 text-field touch-target regression\n"
                "        timeout-minutes: 20\n"
                "        shell: /usr/bin/true {0}\n"
            ),
        )
        expect_failure(fixture, "red", "must not override its execution shell")
        workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            (
                "  test:\n"
                f"    if: {M4_SAFE_FULL_JOB_GUARD}\n"
                "    runs-on: macos-15\n"
            ),
            (
                "  test:\n"
                f"    if: {M4_SAFE_FULL_JOB_GUARD}\n"
                "    runs-on: macos-15\n"
                "    defaults:\n"
                "      run:\n"
                "        shell: /usr/bin/true {0}\n"
            ),
        )
        expect_failure(fixture, "red", "must not override run defaults")
        workflow_path.write_text(original, encoding="utf-8")

        workflow_source = workflow_path.read_text(encoding="utf-8")
        workflow_path.write_text(
            workflow_source
            + "\n  test:\n"
            + "    runs-on: macos-15\n"
            + "    steps: []\n",
            encoding="utf-8",
        )
        expect_failure(fixture, "red", "exactly one canonical job")
        workflow_path.write_text(workflow_source, encoding="utf-8")

        reset_erase_command = '          xcrun simctl erase "$simulator_udid"'
        original = mutate_once(
            workflow_path,
            reset_erase_command,
            "          echo bypassed # " + reset_erase_command.strip(),
        )
        expect_failure(
            fixture,
            "red",
            "approved fail-closed command graph",
        )
        workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            '          destination="$(scripts/select-simulator.sh)"\n',
            (
                "          exit 0\n"
                '          destination="$(scripts/select-simulator.sh)"\n'
            ),
        )
        expect_failure(fixture, "red", "approved fail-closed command graph")
        workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            "      - name: Reset selected simulator before complete functional suite\n",
            (
                "      - name: Reset selected simulator before complete functional suite\n"
                "        continue-on-error: true\n"
            ),
        )
        expect_failure(fixture, "red", "must not continue on error")
        workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            "      - name: Qualifying M3.12 integration RED\n",
            (
                "      - name: Qualifying M3.12 integration RED\n"
                "        if: false\n"
            ),
        )
        expect_failure(fixture, "red", "must run unconditionally")
        workflow_path.write_text(original, encoding="utf-8")

        for quoted_if_key in ('"if"', "'if'"):
            original = mutate_once(
                workflow_path,
                "      - name: Qualifying M3.12 integration RED\n",
                (
                    "      - name: Qualifying M3.12 integration RED\n"
                    f"        {quoted_if_key}: false\n"
                ),
            )
            expect_failure(fixture, "red", "must run unconditionally")
            workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            "      - name: Qualifying M3.12 integration RED\n",
            (
                "      - name: Qualifying M3.12 integration RED\n"
                '        "\\u0069f": false\n'
            ),
        )
        expect_failure(fixture, "red", "canonical unquoted workflow keys")
        workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            (
                "      - name: Test M1 and M3 on small iPhone at AX5\n"
                "        timeout-minutes: 20\n"
            ),
            (
                "      - name: Test M1 and M3 on small iPhone at AX5\n"
                "        timeout-minutes: 20\n"
                "        continue-on-error: true\n"
            ),
        )
        expect_failure(fixture, "red", "must not continue on error")
        workflow_path.write_text(original, encoding="utf-8")

        for quoted_continue_key in ('"continue-on-error"', "'continue-on-error'"):
            original = mutate_once(
                workflow_path,
                (
                    "      - name: Test M1 and M3 on small iPhone at AX5\n"
                    "        timeout-minutes: 20\n"
                ),
                (
                    "      - name: Test M1 and M3 on small iPhone at AX5\n"
                    "        timeout-minutes: 20\n"
                    f"        {quoted_continue_key}: true\n"
                ),
            )
            expect_failure(fixture, "red", "must not continue on error")
            workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            "  test-small-phone:\n    runs-on: macos-15\n",
            (
                "  test-small-phone:\n"
                "    !!str continue-on-error: true\n"
                "    runs-on: macos-15\n"
            ),
        )
        expect_failure(fixture, "red", "canonical unquoted workflow keys")
        workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            (
                "      - name: Test M1 and M3 on small iPhone at AX5\n"
                "        timeout-minutes: 20\n"
            ),
            (
                "      - name: Test M1 and M3 on small iPhone at AX5\n"
                "        timeout-minutes: 20\n"
                "        continue-on-error: false\n"
            ),
        )
        verify(fixture, "red")
        workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            "  test-small-phone:\n    runs-on: macos-15\n",
            (
                "  test-small-phone:\n"
                "    continue-on-error: true\n"
                "    runs-on: macos-15\n"
            ),
        )
        expect_failure(fixture, "red", "job test-small-phone must not continue on error")
        workflow_path.write_text(original, encoding="utf-8")

        for quoted_continue_key in ('"continue-on-error"', "'continue-on-error'"):
            original = mutate_once(
                workflow_path,
                "  test-small-phone:\n    runs-on: macos-15\n",
                (
                    "  test-small-phone:\n"
                    f"    {quoted_continue_key}: true\n"
                    "    runs-on: macos-15\n"
                ),
            )
            expect_failure(
                fixture,
                "red",
                "job test-small-phone must not continue on error",
            )
            workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            "  test-small-phone:\n    runs-on: macos-15\n",
            (
                "  test-small-phone:\n"
                "    continue-on-error: false\n"
                "    runs-on: macos-15\n"
            ),
        )
        verify(fixture, "red")
        workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            "  test-small-phone:\n    runs-on: macos-15\n",
            (
                "  test-small-phone:\n"
                "    if: false\n"
                "    runs-on: macos-15\n"
            ),
        )
        expect_failure(fixture, "red", "job test-small-phone must run unconditionally")
        workflow_path.write_text(original, encoding="utf-8")

        for quoted_if_key in ('"if"', "'if'"):
            original = mutate_once(
                workflow_path,
                "  test-small-phone:\n    runs-on: macos-15\n",
                (
                    "  test-small-phone:\n"
                    f"    {quoted_if_key}: false\n"
                    "    runs-on: macos-15\n"
                ),
            )
            expect_failure(
                fixture,
                "red",
                "job test-small-phone must run unconditionally",
            )
            workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            (
                "      - name: Test M1 and M3 on small iPhone at AX5\n"
                "        timeout-minutes: 20\n"
                "        env:\n"
                '          M3_SMALL_PHONE_GATE: "1"\n'
                "        run: |\n"
                "          set -euo pipefail\n"
            ),
            (
                "      - name: Test M1 and M3 on small iPhone at AX5\n"
                "        timeout-minutes: 20\n"
                "        env:\n"
                '          M3_SMALL_PHONE_GATE: "1"\n'
                "        run: |\n"
                "          set +e\n"
            ),
        )
        expect_failure(fixture, "red", "fail-closed shell options")
        workflow_path.write_text(original, encoding="utf-8")

        small_phone_run_prefix = (
            "      - name: Test M1 and M3 on small iPhone at AX5\n"
            "        timeout-minutes: 20\n"
            "        env:\n"
            '          M3_SMALL_PHONE_GATE: "1"\n'
            "        run: |\n"
            "          set -euo pipefail\n"
        )
        original = mutate_once(
            workflow_path,
            small_phone_run_prefix,
            small_phone_run_prefix + "          set +o errexit\n",
        )
        expect_failure(fixture, "red", "must not disable shell error handling")
        workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            (
                "      - name: Test M1 and M3 on small iPhone at AX5\n"
                "        timeout-minutes: 20\n"
                "        env:\n"
                '          M3_SMALL_PHONE_GATE: "1"\n'
                "        run: |\n"
                "          set -euo pipefail\n"
            ),
            (
                "      - name: Test M1 and M3 on small iPhone at AX5\n"
                "        timeout-minutes: 20\n"
                "        env:\n"
                '          M3_SMALL_PHONE_GATE: "1"\n'
                "        run: |\n"
                "          set -euo pipefail\n"
                "          trap 'exit 0' ERR\n"
            ),
        )
        expect_failure(fixture, "red", "must not trap shell failures")
        workflow_path.write_text(original, encoding="utf-8")

        for bypass_command in (
            "          alias xcodebuild=true\n",
            "          function xcodebuild() { true; }\n",
        ):
            original = mutate_once(
                workflow_path,
                small_phone_run_prefix,
                small_phone_run_prefix + bypass_command,
            )
            expect_failure(fixture, "red", "approved fail-closed command graph")
            workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            (
                "            M3_SMALL_PHONE_GATE=1 \\\n"
                "            CODE_SIGNING_ALLOWED=NO\n"
            ),
            (
                "            M3_SMALL_PHONE_GATE=1 \\\n"
                "            CODE_SIGNING_ALLOWED=NO\n"
                "          true\n"
            ),
        )
        expect_failure(fixture, "red", "approved fail-closed command graph")
        workflow_path.write_text(original, encoding="utf-8")

        for mutation_index, owner in enumerate((
            '"M3AcceptanceUITests"',
            '"M3AccessibilityUITests"',
            '"ProgressPhotoLifecycleUITests"',
            '"ProgressPhotoGalleryUITests"',
        )):
            original = mutate_once(
                workflow_path,
                owner,
                f'"removed-screenshot-owner-{mutation_index}"',
            )
            expect_failure(fixture, "red", owner)
            workflow_path.write_text(original, encoding="utf-8")

        test_ios_path = fixture / "scripts/test-ios.sh"
        original = mutate_once(
            test_ios_path,
            "M3AcceptanceUITests/testTodayAndProgressExposeEveryM3TrackerEntryThroughOneLazyRouter",
            "M3AcceptanceUITests/removedQualifyingRoute",
        )
        expect_failure(fixture, "red", "testTodayAndProgressExposeEveryM3TrackerEntryThroughOneLazyRouter")
        test_ios_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            '          M3_SMALL_PHONE_GATE: "1"',
            '          # M3_SMALL_PHONE_GATE: "1"',
        )
        expect_failure(fixture, "red", 'M3_SMALL_PHONE_GATE: "1"')
        workflow_path.write_text(original, encoding="utf-8")

        project_path = fixture / "project.yml"
        original = project_path.read_text(encoding="utf-8")
        mutated_project = original.replace(
            '        M3_SMALL_PHONE_GATE: "$(M3_SMALL_PHONE_GATE)"',
            '        M3_SMALL_PHONE_GATE: "0"',
            1,
        ) + '\nm3_gate_decoy: \'M3_SMALL_PHONE_GATE: "$(M3_SMALL_PHONE_GATE)"\'\n'
        if mutated_project == original:
            raise SystemExit(
                "M3.12 self-test Local scheme gate mutation source is missing"
            )
        project_path.write_text(
            mutated_project,
            encoding="utf-8",
        )
        expect_failure(fixture, "red", "forward its small-phone gate into the XCTest process")
        project_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            "            M3_SMALL_PHONE_GATE=1 \\",
            "            M3_SMALL_PHONE_GATE=0 \\",
        )
        expect_failure(fixture, "red", "M3_SMALL_PHONE_GATE=1")
        workflow_path.write_text(original, encoding="utf-8")

        original = mutate_once(
            workflow_path,
            (
                "            CODE_SIGNING_ALLOWED=NO\n\n"
                "      - name: Export small-phone screenshot evidence"
            ),
            (
                "            CODE_SIGNING_ALLOWED=NO||true\n\n"
                "      - name: Export small-phone screenshot evidence"
            ),
        )
        expect_failure(fixture, "red", "xcodebuild command must fail closed")
        workflow_path.write_text(original, encoding="utf-8")

        original = workflow_path.read_text(encoding="utf-8")
        gate_decoy = original.replace(
            "            M3_SMALL_PHONE_GATE=1 \\",
            "            M3_SMALL_PHONE_GATE=0 \\",
            1,
        ).replace(
            (
                "            CODE_SIGNING_ALLOWED=NO\n\n"
                "      - name: Export small-phone screenshot evidence"
            ),
            (
                "            CODE_SIGNING_ALLOWED=NO\n"
                '          echo "M3_SMALL_PHONE_GATE=1"\n\n'
                "      - name: Export small-phone screenshot evidence"
            ),
            1,
        )
        if gate_decoy == original:
            raise SystemExit("M3.12 self-test workflow gate-decoy source is missing")
        workflow_path.write_text(gate_decoy, encoding="utf-8")
        expect_failure(fixture, "red", "approved fail-closed command graph")
        workflow_path.write_text(original, encoding="utf-8")

        for relative in (
            "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataMetricsRepository.swift",
            "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataLifestyleRepository.swift",
            "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataBloodworkRepository.swift",
            "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataProgressPhotoRepository.swift",
        ):
            persistence_source = fixture / relative
            original = persistence_source.read_text(encoding="utf-8")
            persistence_source.write_text(
                original + '\nprivate func leakedPayload() { print("payload") }\n',
                encoding="utf-8",
            )
            expect_failure(fixture, "red", "privacy scan rejected")
            persistence_source.write_text(original, encoding="utf-8")

        training_source = fixture / (
            "Packages/HealthTrackingModules/Sources/TrainingKit/Session/"
            "SessionViewModel.swift"
        )
        original = training_source.read_text(encoding="utf-8")
        training_source.write_text(
            original + '\nprivate func leakedSymptom() { print("symptom") }\n',
            encoding="utf-8",
        )
        expect_failure(fixture, "red", "privacy scan rejected")
        training_source.write_text(original, encoding="utf-8")

        training_source.write_text(
            original
            + '\nprivate let fakeCommentStart = "/*"\n'
            + 'private func leakedBehindString() { print("symptom") }\n'
            + 'private let fakeCommentEnd = "*/"\n',
            encoding="utf-8",
        )
        expect_failure(fixture, "red", "privacy scan rejected")
        training_source.write_text(original, encoding="utf-8")

        training_source.write_text(
            original
            + "\nprivate let privateHealthValue = 7\n"
            + 'private let interpolatedLeak = "\\(print(privateHealthValue))"\n',
            encoding="utf-8",
        )
        expect_failure(fixture, "red", "privacy scan rejected")
        training_source.write_text(original, encoding="utf-8")

        training_source.write_text(
            original
            + "\nprivate let privateHealthValue = 7\n"
            + 'private let rawInterpolatedLeak = #"\\#(print(privateHealthValue))"#\n',
            encoding="utf-8",
        )
        expect_failure(fixture, "red", "privacy scan rejected")
        training_source.write_text(original, encoding="utf-8")

        training_source.write_text(
            original
            + '\n// Never print health values.\n'
            + 'private let privacyRule = "Never print health values."\n',
            encoding="utf-8",
        )
        verify(fixture, "red")
        training_source.write_text(original, encoding="utf-8")

        training_source.write_text(
            original
            + '\nprivate let rawPrivacyRule = #"Never "print" health values."#\n',
            encoding="utf-8",
        )
        verify(fixture, "red")
        training_source.write_text(original, encoding="utf-8")

        training_source.write_text(
            original
            + "\nprivate let privacyRegexRule = /print/\n"
            + "private let rawPrivacyRegexRule = #/print/#\n",
            encoding="utf-8",
        )
        verify(fixture, "red")
        training_source.write_text(original, encoding="utf-8")

        production_fixture = fixture / "production-contracts"
        copy_real_fixture(source_root, production_fixture)
        materialize_production_self_test_fixture(production_fixture)
        write_evidence_self_test_fixture(production_fixture)
        verify(production_fixture, "production")

        evidence = production_fixture / EVIDENCE_RELATIVE
        valid_evidence = evidence.read_text(encoding="utf-8")

        evidence.unlink()
        expect_failure(
            production_fixture,
            "production",
            "Missing M3 acceptance evidence",
        )
        evidence.write_text(valid_evidence, encoding="utf-8")

        evidence.write_text(
            valid_evidence.replace(ACCEPTED_M312_SHA, "0" * 40),
            encoding="utf-8",
        )
        expect_failure(
            production_fixture,
            "production",
            "must name the exact accepted M3.12 implementation SHA",
        )
        evidence.write_text(valid_evidence, encoding="utf-8")

        for task in EVIDENCE_TASKS:
            evidence.write_text(
                valid_evidence.replace(f"| {task} |", "| removed task |", 1),
                encoding="utf-8",
            )
            expect_failure(
                production_fixture,
                "production",
                f"missing the exact {task} evidence row",
            )
        evidence.write_text(valid_evidence, encoding="utf-8")

        evidence.write_text(
            valid_evidence.replace("Privacy scan: PASS", "Privacy scan: pending", 1),
            encoding="utf-8",
        )
        expect_failure(production_fixture, "production", "Privacy scan: PASS")
        evidence.write_text(valid_evidence, encoding="utf-8")

        evidence.write_text(
            valid_evidence + "- Real notification delivery: PASS\n",
            encoding="utf-8",
        )
        expect_failure(
            production_fixture,
            "production",
            "honest device/service claim",
        )
        evidence.write_text(valid_evidence, encoding="utf-8")

        def exercise_production_contract_mutations() -> None:
            fixture = production_fixture
            bundle = fixture / "App/Application/TrackerFeatureBundle.swift"
            for mutation_index, token in enumerate((
                "onOpenBodyMetric: onOpenBodyMetric",
                "onOpenLifestyle: onOpenLifestyle",
                "onOpenPosture: onOpenPosture",
                "onOpenHealthChecks: onOpenHealthChecks",
                "onOpenBloodwork: onOpenBloodwork",
                "onOpenProgressPhotos: onOpenProgressPhotos",
            )):
                original = mutate_all(
                    bundle,
                    token,
                    f"removed-production-route-{mutation_index}",
                )
                expect_failure(fixture, "production", token)
                bundle.write_text(original, encoding="utf-8")

            configuration_test = fixture / "HealthTrackingAppTests/TrackerCompositionTests.swift"
            original = mutate_once(
                configuration_test,
                "unsupported",
                "removed-invalid-state",
            )
            expect_failure(fixture, "production", "unsupported")
            configuration_test.write_text(original, encoding="utf-8")

            launch_configuration = fixture / "App/Support/AppUITestLaunchConfiguration.swift"
            for mutation_index, token in enumerate((
                "PhotoLibraryAccessState(rawValue:",
                "ISO8601DateFormatter().date(from:",
            )):
                original = mutate_once(
                    launch_configuration,
                    token,
                    f"removed-parser-boundary-{mutation_index}(",
                )
                expect_failure(fixture, "production", token)
                launch_configuration.write_text(original, encoding="utf-8")

            original = mutate_once(
                bundle,
                "if scenario == .m3ProgressPhotos",
                "if scenario == .m3HealthChecks",
            )
            expect_failure(
                fixture,
                "production",
                "M3 progress-photo fixture access-state injection",
            )
            bundle.write_text(original, encoding="utf-8")

            dependencies = fixture / "App/Application/AppDependencies.swift"
            original = dependencies.read_text(encoding="utf-8")
            dependencies.write_text(
                original.replace(
                    "let now = AppDomainContext.now()",
                    "let now = Date.now",
                    1,
                )
                + "\nfunc fixedClockDecoy() { _ = AppDomainContext.now() }\n",
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "M3 fixed-clock health-check fixture",
            )
            dependencies.write_text(original, encoding="utf-8")

            metric_entry = fixture / (
                "Packages/HealthTrackingModules/Sources/MetricsKit/BodyMetric/"
                "BodyMetricEntryView.swift"
            )
            original = metric_entry.read_text(encoding="utf-8")
            shadowed_text_field = original + (
                "\nprivate struct TextField: View {\n"
                "    init(_ title: String, text: Binding<String>) {}\n"
                "    var body: some View { EmptyView() }\n"
                "}\n"
            )
            metric_entry.write_text(shadowed_text_field, encoding="utf-8")
            expect_failure(
                fixture,
                "production",
                "must not shadow required SwiftUI symbols",
            )
            metric_entry.write_text(original, encoding="utf-8")

            cross_file_shadow = metric_entry.parent / "M312ShadowTextField.swift"
            cross_file_shadow.write_text(
                "import SwiftUI\n"
                "struct TextField: View {\n"
                "    init(_ title: String, text: Binding<String>) {}\n"
                "    var body: some View { EmptyView() }\n"
                "}\n",
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "must not shadow required SwiftUI symbols",
            )
            cross_file_shadow.unlink()

            cross_file_overload = metric_entry.parent / "M312TextFieldOverload.swift"
            cross_file_overload.write_text(
                "import SwiftUI\n"
                "extension SwiftUI.TextField where Label == Text {\n"
                "    init(_ title: String, text: Binding<String>) {\n"
                "        self.init(text: .constant(\"\"), prompt: nil) {\n"
                "            Text(title)\n"
                "        }\n"
                "    }\n"
                "}\n",
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "must not shadow required SwiftUI symbols",
            )
            cross_file_overload.unlink()

            cross_file_decoys = metric_entry.parent / "M312ShadowDecoys.swift"
            cross_file_decoys.write_text(
                "// struct TextField: View {}\n"
                "/* extension SwiftUI.TextField where Label == Text {} */\n"
                "let m312ShadowDecoy = \"func accessibilityLabel\"\n",
                encoding="utf-8",
            )
            verify(fixture, "production")
            cross_file_decoys.unlink()

            shadowed_vstack = original + (
                "\nprivate struct VStack<Content: View>: View {\n"
                "    private let content: Content\n"
                "    init(\n"
                "        alignment: HorizontalAlignment = .center,\n"
                "        spacing: CGFloat? = nil,\n"
                "        @ViewBuilder content: () -> Content\n"
                "    ) { self.content = content() }\n"
                "    var body: some View {\n"
                "        content.accessibilityHidden(true)\n"
                "    }\n"
                "}\n"
            )
            metric_entry.write_text(shadowed_vstack, encoding="utf-8")
            expect_failure(
                fixture,
                "production",
                "must not shadow required SwiftUI symbols",
            )
            metric_entry.write_text(original, encoding="utf-8")

            destructured_text_field_shadow = original + (
                "\n@MainActor private struct HiddenTextFieldFactory {\n"
                "    func callAsFunction(\n"
                "        _ title: String,\n"
                "        text: Binding<String>\n"
                "    ) -> some View { EmptyView() }\n"
                "}\n"
                "@MainActor private let (TextField, m312ShadowSentinel) = "
                "(HiddenTextFieldFactory(), ())\n"
            )
            metric_entry.write_text(
                destructured_text_field_shadow,
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "must not shadow required SwiftUI symbols",
            )
            metric_entry.write_text(original, encoding="utf-8")

            comma_bound_text_field_shadow = original + (
                "\n@MainActor private struct HiddenTextFieldFactory {\n"
                "    func callAsFunction(\n"
                "        _ title: String,\n"
                "        text: Binding<String>\n"
                "    ) -> some View { EmptyView() }\n"
                "}\n"
                "@MainActor private let m312ShadowSentinel = (), "
                "TextField = HiddenTextFieldFactory()\n"
            )
            metric_entry.write_text(
                comma_bound_text_field_shadow,
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "must not shadow required SwiftUI symbols",
            )
            metric_entry.write_text(original, encoding="utf-8")

            shadowed_accessibility_label = original + (
                "\nprivate extension View {\n"
                "    func accessibilityLabel(_ label: String) -> some View {\n"
                "        accessibilityHidden(true)\n"
                "    }\n"
                "}\n"
            )
            metric_entry.write_text(
                shadowed_accessibility_label,
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "must not shadow required SwiftUI symbols",
            )
            metric_entry.write_text(original, encoding="utf-8")

            shadowing_decoys = original + (
                "\n/* private struct TextField: View {} */\n"
                "// private let (TextField, decoy) = (factory, ())\n"
                "// private let decoy = (), TextField = factory\n"
                'private let shadowingStringDecoy = "func accessibilityLabel"\n'
            )
            metric_entry.write_text(shadowing_decoys, encoding="utf-8")
            verify(fixture, "production")
            metric_entry.write_text(original, encoding="utf-8")

            renamed_decoy_and_empty_real = original.replace(
                "public struct BodyMetricEntryView: View",
                "public struct M312VerifierDecoy: View",
                1,
            ) + (
                "\n@MainActor\n"
                "public struct BodyMetricEntryView: View {\n"
                "    public init(\n"
                "        viewModel: BodyMetricViewModel,\n"
                "        editingSnapshot: BodyMetricSnapshot? = nil,\n"
                "        onClose: @escaping @MainActor () -> Void\n"
                "    ) {}\n"
                "    public var body: some View { EmptyView() }\n"
                "}\n"
            )
            metric_entry.write_text(
                renamed_decoy_and_empty_real,
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "M3 Metrics metricField must be one direct BodyMetricEntryView member",
            )
            metric_entry.write_text(original, encoding="utf-8")

            original_metric_code = swift_code_only(original)
            original_metric_type = re.search(
                r"(?m)^[ \t]*@MainActor[ \t]*\n[ \t]*public[ \t]+struct[ \t]+"
                r"BodyMetricEntryView[ \t]*:[ \t]*View[ \t]*\{",
                original_metric_code,
            )
            if original_metric_type is None:
                raise SystemExit(
                    "M3.12 self-test canonical metric type anchor is missing"
                )
            original_metric_opening = original_metric_type.end() - 1
            original_metric_end = balanced_delimiter_end(
                original_metric_code,
                original_metric_opening,
                "{",
                "}",
                "M3.12 self-test canonical metric type",
            )
            original_metric_body = original[
                original_metric_opening + 1:original_metric_end - 1
            ].strip()
            nested_metric_body = "\n".join(
                "        " + line
                for line in original_metric_body.splitlines()
            )
            nested_complete_decoy = (
                original[:original_metric_opening + 1]
                + "\n    public init() {}\n"
                + "    private struct M312NestedContractDecoy: View {\n"
                + nested_metric_body
                + "\n    }\n"
                + original[original_metric_end - 1:]
                + "\n@MainActor\n"
                + "extension BodyMetricEntryView {\n"
                + "    public var body: some View { EmptyView() }\n"
                + "}\n"
            )
            metric_entry.write_text(nested_complete_decoy, encoding="utf-8")
            expect_failure(
                fixture,
                "production",
                "M3 Metrics body must be one direct BodyMetricEntryView member",
            )
            metric_entry.write_text(original, encoding="utf-8")

            inactive_complete_contract = (
                original[:original_metric_opening + 1]
                + "\n#if M312Never\n"
                + original_metric_body
                + "\n#endif\n"
                + "public init() {}\n"
                + original[original_metric_end - 1:]
                + "\n@MainActor\n"
                + "extension BodyMetricEntryView {\n"
                + "    public var body: some View { EmptyView() }\n"
                + "}\n"
            )
            metric_entry.write_text(
                inactive_complete_contract,
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "canonical BodyMetricEntryView must not use conditional compilation",
            )
            metric_entry.write_text(original, encoding="utf-8")

            cross_file_body_metric = (
                metric_entry.parent / "M312BodyMetricEntryView.swift"
            )
            cross_file_body_metric_source = (
                "import SwiftUI\n"
                "@MainActor\n"
                "public struct BodyMetricEntryView: View {\n"
                "    public init(\n"
                "        viewModel: BodyMetricViewModel,\n"
                "        editingSnapshot: BodyMetricSnapshot? = nil,\n"
                "        onClose: @escaping @MainActor () -> Void\n"
                "    ) {}\n"
                "    public var body: some View { EmptyView() }\n"
                "}\n"
            )
            cross_file_body_metric.write_text(
                cross_file_body_metric_source,
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "exactly one BodyMetricEntryView declaration across compiled MetricsKit",
            )
            cross_file_body_metric.unlink()

            outer_inactive_contract = (
                original[:original_metric_type.start()]
                + "#if M312Never\n"
                + original[
                    original_metric_type.start():original_metric_end
                ]
                + "\n#endif\n"
                + original[original_metric_end:]
            )
            metric_entry.write_text(
                outer_inactive_contract,
                encoding="utf-8",
            )
            cross_file_body_metric.write_text(
                cross_file_body_metric_source,
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "canonical BodyMetricEntryView must not use conditional compilation",
            )
            cross_file_body_metric.unlink()
            metric_entry.write_text(original, encoding="utf-8")

            nested_policy_anchor = (
                "private var shouldOfferDraftClose: Bool { "
                "!isSaving && !isSaved }"
            )
            if nested_policy_anchor not in original:
                raise SystemExit(
                    "M3.12 self-test nested policy anchor is missing"
                )
            nested_policy_decoy = original.replace(
                nested_policy_anchor,
                "private struct M312NestedPolicyDecoy {\n"
                "    private let isSaving = false\n"
                "    private let isSaved = false\n"
                "    private var shouldOfferDraftClose: Bool {\n"
                "        !isSaving && !isSaved\n"
                "    }\n"
                "}",
                1,
            ) + (
                "\n@MainActor\n"
                "private var shouldOfferDraftClose: Bool { true }\n"
            )
            metric_entry.write_text(nested_policy_decoy, encoding="utf-8")
            expect_failure(
                fixture,
                "production",
                "draft-close policy must be one direct BodyMetricEntryView member",
            )
            metric_entry.write_text(original, encoding="utf-8")

            hidden_result_builder_declaration = (
                "\n@resultBuilder private enum HiddenMetricBuilder {\n"
                "    @MainActor static func buildBlock<Content: View>(\n"
                "        _ content: Content\n"
                "    ) -> some View {\n"
                "        content.accessibilityHidden(true)\n"
                "    }\n"
                "}\n"
            )
            custom_result_builder_body = original.replace(
                "public var body: some View",
                "@HiddenMetricBuilder\npublic var body: some View",
                1,
            ) + hidden_result_builder_declaration
            metric_entry.write_text(
                custom_result_builder_body,
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "body declaration must not use custom result-builder attributes",
            )
            metric_entry.write_text(original, encoding="utf-8")

            commented_result_builder_decoy = original.replace(
                "public var body: some View",
                "// @HiddenMetricBuilder\npublic var body: some View",
                1,
            )
            if commented_result_builder_decoy == original:
                raise SystemExit(
                    "M3.12 self-test result-builder decoy anchor is missing"
                )
            metric_entry.write_text(
                commented_result_builder_decoy,
                encoding="utf-8",
            )
            verify(fixture, "production")
            metric_entry.write_text(original, encoding="utf-8")

            custom_result_builder_helper = original.replace(
                "private func metricField(",
                "@HiddenMetricBuilder\nprivate func metricField(",
                1,
            ) + hidden_result_builder_declaration
            metric_entry.write_text(
                custom_result_builder_helper,
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "metricField declaration must not use custom result-builder attributes",
            )
            metric_entry.write_text(original, encoding="utf-8")

            commented_helper_builder_decoy = original.replace(
                "private func metricField(",
                "// @HiddenMetricBuilder\nprivate func metricField(",
                1,
            )
            if commented_helper_builder_decoy == original:
                raise SystemExit(
                    "M3.12 self-test helper builder decoy anchor is missing"
                )
            metric_entry.write_text(
                commented_helper_builder_decoy,
                encoding="utf-8",
            )
            verify(fixture, "production")
            metric_entry.write_text(original, encoding="utf-8")

            metric_entry.write_text(
                original.replace(
                    ".metricEntryTouchTarget()",
                    ".removedMetricEntryTouchTarget()",
                    1,
                ),
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "must attach exactly one shared touch-target geometry modifier",
            )
            metric_entry.write_text(original, encoding="utf-8")

            metric_name_label = (
                '.accessibilityLabel(localized("metrics.entry.custom.name"))'
            )
            metric_entry.write_text(
                original.replace(
                    metric_name_label,
                    '.accessibilityLabel(localized("metrics.entry.custom.value"))'
                    + " /* "
                    + metric_name_label
                    + " */",
                    1,
                ),
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "must bind its exact initializer, state, modifier order, label, and identifier",
            )
            metric_entry.write_text(original, encoding="utf-8")

            metric_entry.write_text(
                original.replace(metric_name_label, "", 1)
                + "\nText(\"decoy\")"
                + metric_name_label
                + "\n",
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "must bind its exact initializer, state, modifier order, label, and identifier",
            )
            metric_entry.write_text(original, encoding="utf-8")

            metric_name_identifier = (
                '.accessibilityIdentifier("metrics.entry.custom.name")'
            )
            metric_value_identifier = (
                '.accessibilityIdentifier("metrics.entry.custom.value")'
            )
            metric_unit_identifier = (
                '.accessibilityIdentifier("metrics.entry.custom.unit")'
            )

            def field_source_positions(identifier: str) -> tuple[int, int, str]:
                identifier_position = original.find(identifier)
                if identifier_position < 0:
                    raise SystemExit(
                        "M3.12 self-test metric identifier anchor is missing: "
                        + identifier
                    )
                field_start = original.rfind(
                    "TextField(",
                    0,
                    identifier_position,
                )
                if field_start < 0:
                    raise SystemExit(
                        "M3.12 self-test TextField anchor is missing: " + identifier
                    )
                line_start = original.rfind("\n", 0, field_start) + 1
                indentation = original[line_start:field_start]
                if indentation.strip():
                    raise SystemExit(
                        "M3.12 self-test TextField anchor is not a direct line"
                    )
                return field_start, line_start, indentation

            name_field_start, name_line_start, name_indentation = (
                field_source_positions(metric_name_identifier)
            )
            swapped_identifiers = (
                original.replace(
                    metric_name_identifier,
                    ".m312IdentifierSwapSentinel()",
                    1,
                )
                .replace(metric_value_identifier, metric_name_identifier, 1)
                .replace(".m312IdentifierSwapSentinel()", metric_value_identifier, 1)
            )
            metric_entry.write_text(swapped_identifiers, encoding="utf-8")
            expect_failure(
                fixture,
                "production",
                "must bind its exact initializer, state, modifier order, label, and identifier",
            )
            metric_entry.write_text(original, encoding="utf-8")

            swapped_bindings = (
                original.replace("text: $customName", "text: $m312BindingSentinel", 1)
                .replace("text: $customValueText", "text: $customName", 1)
                .replace("text: $m312BindingSentinel", "text: $customValueText", 1)
            )
            metric_entry.write_text(swapped_bindings, encoding="utf-8")
            expect_failure(
                fixture,
                "production",
                "must bind its exact initializer, state, modifier order, label, and identifier",
            )
            metric_entry.write_text(original, encoding="utf-8")

            metric_entry.write_text(
                original.replace(
                    metric_name_identifier,
                    metric_name_identifier
                    + "\n            .modifier(M312WrongMetricLabelModifier())",
                    1,
                )
                + "\nprivate struct M312WrongMetricLabelModifier: ViewModifier {\n"
                + "    func body(content: Content) -> some View {\n"
                + "        content.accessibilityLabel(\"Değer\")\n"
                + "    }\n"
                + "}\n",
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "must bind its exact initializer, state, modifier order, label, and identifier",
            )
            metric_entry.write_text(original, encoding="utf-8")

            for wrapper_name, wrapper_declaration in (
                ("AnyView", ""),
                (
                    "m312Identity",
                    "\nprivate func m312Identity<Content: View>("
                    "_ content: Content"
                    ") -> some View { content }\n",
                ),
            ):
                wrapped_metric_name = (
                    original[:name_line_start]
                    + name_indentation
                    + f"{wrapper_name}(\n"
                    + name_indentation
                    + "    "
                    + original[name_field_start:]
                ).replace(
                    metric_name_identifier,
                    metric_name_identifier
                    + "\n"
                    + name_indentation
                    + ")\n"
                    + name_indentation
                    + '.accessibilityLabel("Değer")',
                    1,
                )
                metric_entry.write_text(
                    wrapped_metric_name + wrapper_declaration,
                    encoding="utf-8",
                )
                expect_failure(
                    fixture,
                    "production",
                    "must be a direct, unenclosed View expression",
                )
            metric_entry.write_text(original, encoding="utf-8")

            grouped_metric_name = (
                original[:name_line_start]
                + name_indentation
                + "Group {\n"
                + name_indentation
                + "    "
                + original[name_field_start:]
            ).replace(
                metric_name_identifier,
                metric_name_identifier
                + "\n"
                + name_indentation
                + "}\n"
                + name_indentation
                + '.accessibilityLabel("Değer")',
                1,
            )
            metric_entry.write_text(grouped_metric_name, encoding="utf-8")
            expect_failure(
                fixture,
                "production",
                "must remain a direct ViewBuilder expression in its exact container",
            )
            metric_entry.write_text(original, encoding="utf-8")

            aliased_metric_name = (
                original[:name_line_start]
                + name_indentation
                + "let nameField = "
                + original[name_field_start:]
            ).replace(
                metric_name_identifier,
                metric_name_identifier
                + "\n"
                + name_indentation
                + "nameField\n"
                + name_indentation
                + '    .accessibilityLabel("Değer")',
                1,
            )
            metric_entry.write_text(aliased_metric_name, encoding="utf-8")
            expect_failure(
                fixture,
                "production",
                "must remain a direct ViewBuilder expression in its exact container",
            )
            metric_entry.write_text(original, encoding="utf-8")

            unit_identifier_end = (
                original.find(metric_unit_identifier) + len(metric_unit_identifier)
            )
            unit_container_close = re.match(
                r"\n(?P<indent>[ \t]*)\}",
                original[unit_identifier_end:],
            )
            if unit_container_close is None:
                raise SystemExit(
                    "M3.12 self-test custom-field container anchor is missing"
                )
            container_close_end = unit_identifier_end + unit_container_close.end()
            container_indentation = unit_container_close.group("indent")
            hidden_metric_container = (
                original[:container_close_end]
                + "\n"
                + container_indentation
                + ".accessibilityHidden(true)"
                + original[container_close_end:]
            )
            metric_entry.write_text(hidden_metric_container, encoding="utf-8")
            expect_failure(
                fixture,
                "production",
                "must remain a direct ViewBuilder expression in its exact container",
            )
            metric_entry.write_text(original, encoding="utf-8")

            parent_container_close = re.match(
                r"\n(?:[ \t]*statePresentation[ \t]*\n)?"
                r"(?P<indent>[ \t]*)\}",
                original[container_close_end:],
            )
            if parent_container_close is None:
                raise SystemExit(
                    "M3.12 self-test parent metric container anchor is missing"
                )
            parent_close_end = container_close_end + parent_container_close.end()
            parent_indentation = parent_container_close.group("indent")
            hidden_parent_metric_container = (
                original[:parent_close_end]
                + "\n"
                + parent_indentation
                + ".accessibilityHidden(true)"
                + original[parent_close_end:]
            )
            metric_entry.write_text(
                hidden_parent_metric_container,
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "must remain a direct ViewBuilder expression in its exact container",
            )
            metric_entry.write_text(original, encoding="utf-8")

            task_mutated_metric_container = (
                original[:container_close_end]
                + "\n"
                + container_indentation
                + ".task(id: customName) {\n"
                + container_indentation
                + '    customName = ""\n'
                + container_indentation
                + "}"
                + original[container_close_end:]
            )
            metric_entry.write_text(
                task_mutated_metric_container,
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "must remain a direct ViewBuilder expression in its exact container",
            )
            metric_entry.write_text(original, encoding="utf-8")

            unicode_task_metric_container = (
                original[:container_close_end]
                + "\n"
                + container_indentation
                + ".taskşüpheli()"
                + original[container_close_end:]
                + "\nprivate extension View {\n"
                + "    func taskşüpheli() -> some View {\n"
                + "        accessibilityHidden(true)\n"
                + "    }\n"
                + "}\n"
            )
            metric_entry.write_text(
                unicode_task_metric_container,
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "contains an unparsed Swift modifier",
            )
            metric_entry.write_text(original, encoding="utf-8")

            operator_metric_container = (
                original[:container_close_end]
                + " |> true"
                + original[container_close_end:]
                + "\ninfix operator |>: AdditionPrecedence\n"
                + "@MainActor private func |> <Content: View>("
                + "content: Content, hidden: Bool"
                + ") -> some View {\n"
                + "    content.accessibilityHidden(hidden)\n"
                + "}\n"
            )
            metric_entry.write_text(operator_metric_container, encoding="utf-8")
            expect_failure(
                fixture,
                "production",
                "must remain a direct ViewBuilder expression in its exact container",
            )
            metric_entry.write_text(original, encoding="utf-8")

            original_code = swift_code_only(original)
            toolbar_start = original_code.find(".toolbar")
            toolbar_opening = original_code.find("{", toolbar_start)
            if toolbar_start < 0 or toolbar_opening < 0:
                raise SystemExit(
                    "M3.12 self-test toolbar trailing-closure anchor is missing"
                )
            toolbar_end = balanced_delimiter_end(
                original_code,
                toolbar_opening,
                "{",
                "}",
                "M3.12 self-test toolbar trailing closure",
            )
            labeled_toolbar_closure = (
                original[:toolbar_end]
                + " malicious: { EmptyView() }"
                + original[toolbar_end:]
                + "\nprivate extension View {\n"
                + "    func toolbar<Content: View, Malicious: View>(\n"
                + "        @ViewBuilder content: () -> Content,\n"
                + "        @ViewBuilder malicious: () -> Malicious\n"
                + "    ) -> some View {\n"
                + "        accessibilityHidden(true)\n"
                + "    }\n"
                + "}\n"
            )
            metric_entry.write_text(labeled_toolbar_closure, encoding="utf-8")
            expect_failure(
                fixture,
                "production",
                "must not shadow required SwiftUI symbols",
            )
            metric_entry.write_text(original, encoding="utf-8")

            mutated_root_postfix = original.replace(
                ".interactiveDismissDisabled(isSaving)\n"
                "    .task {\n"
                "        prepareOnce()\n"
                "    }",
                ".interactiveDismissDisabled(false)\n"
                "    .task {\n"
                '        customName = ""\n'
                "    }",
                1,
            )
            if mutated_root_postfix == original:
                raise SystemExit(
                    "M3.12 self-test root postfix mutation anchor is missing"
                )
            metric_entry.write_text(mutated_root_postfix, encoding="utf-8")
            expect_failure(
                fixture,
                "production",
                "must remain a direct ViewBuilder expression in its exact container",
            )
            metric_entry.write_text(original, encoding="utf-8")

            commented_ancestor_postfix = original.replace(
                ".interactiveDismissDisabled(isSaving)",
                ".interactiveDismissDisabled("
                "/* outer /* nested */ still outer */ isSaving)",
                1,
            )
            if commented_ancestor_postfix == original:
                raise SystemExit(
                    "M3.12 self-test ancestor postfix comment anchor is missing"
                )
            metric_entry.write_text(
                commented_ancestor_postfix,
                encoding="utf-8",
            )
            verify(fixture, "production")
            metric_entry.write_text(original, encoding="utf-8")

            conditional_hidden_container = (
                original[:container_close_end]
                + "\n"
                + container_indentation
                + "#if true\n"
                + container_indentation
                + ".accessibilityHidden(true)\n"
                + container_indentation
                + "#endif"
                + original[container_close_end:]
            )
            metric_entry.write_text(
                conditional_hidden_container,
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "canonical BodyMetricEntryView must not use conditional compilation",
            )
            metric_entry.write_text(original, encoding="utf-8")

            exact_custom_fields = original[
                name_line_start:unit_identifier_end
            ]
            wrong_custom_fields = exact_custom_fields.replace(
                metric_name_label,
                '.accessibilityLabel(localized("metrics.entry.custom.value"))',
                1,
            )
            conditional_branch_swap = (
                original[:name_line_start]
                + name_indentation
                + "#if M312VerifierDecoy\n"
                + exact_custom_fields
                + "\n"
                + name_indentation
                + "#else\n"
                + wrong_custom_fields
                + "\n"
                + name_indentation
                + "#endif"
                + original[unit_identifier_end:]
            )
            metric_entry.write_text(conditional_branch_swap, encoding="utf-8")
            expect_failure(
                fixture,
                "production",
                "canonical BodyMetricEntryView must not use conditional compilation",
            )
            metric_entry.write_text(original, encoding="utf-8")

            directive_decoys = original.replace(
                "        HStack {\n",
                "        HStack {\n"
                "            // #if M312CommentDecoy\n"
                '            let directiveDecoy = "#if M312StringDecoy"\n',
                1,
            )
            if directive_decoys == original:
                raise SystemExit(
                    "M3.12 self-test conditional directive decoy anchor is missing"
                )
            metric_entry.write_text(directive_decoys, encoding="utf-8")
            verify(fixture, "production")
            metric_entry.write_text(original, encoding="utf-8")

            for escaped_modifier in (
                '.`accessibilityLabel`("Değer")',
                ".şüpheliEtiket()",
            ):
                mutated = original.replace(
                    metric_name_identifier,
                    metric_name_identifier
                    + "\n            "
                    + escaped_modifier,
                    1,
                )
                if escaped_modifier == ".şüpheliEtiket()":
                    mutated += (
                        "\nprivate extension View {\n"
                        "    func şüpheliEtiket() -> some View {\n"
                        "        accessibilityLabel(\"Değer\")\n"
                        "    }\n"
                        "}\n"
                    )
                metric_entry.write_text(mutated, encoding="utf-8")
                expect_failure(
                    fixture,
                    "production",
                    "contains an unparsed Swift modifier",
                )
            metric_entry.write_text(original, encoding="utf-8")

            metric_entry.write_text(
                original.replace(
                    metric_name_label,
                    ".accessibilityLabel(localized("
                    + "/* outer /* nested */ still outer */ "
                    + '"metrics.entry.custom.name"))',
                    1,
                ),
                encoding="utf-8",
            )
            verify(fixture, "production")
            metric_entry.write_text(original, encoding="utf-8")

            metric_entry.write_text(
                original.replace(
                    metric_name_label,
                    ".accessibilityLabel(localized(\n"
                    + "    /* outer /* inner */ "
                    + '"metrics.entry.custom.name" // */ '
                    + '"metrics.entry.custom.value"\n'
                    + "))",
                    1,
                ),
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "must bind its exact initializer, state, modifier order, label, and identifier",
            )
            metric_entry.write_text(original, encoding="utf-8")

            _, value_line_start, _ = field_source_positions(
                metric_value_identifier
            )
            _, unit_line_start, _ = field_source_positions(metric_unit_identifier)
            if not name_line_start < value_line_start < unit_line_start:
                raise SystemExit(
                    "M3.12 self-test custom-field order anchors are invalid"
                )
            reordered_custom_fields = (
                original[:name_line_start]
                + original[value_line_start:unit_line_start]
                + original[name_line_start:value_line_start]
                + original[unit_line_start:]
            )
            metric_entry.write_text(reordered_custom_fields, encoding="utf-8")
            verify(fixture, "production")
            metric_entry.write_text(original, encoding="utf-8")

            relocated_metric_modifier = original.replace(
                ".metricEntryTouchTarget()",
                "",
                1,
            ) + "\nText(\"decoy\").metricEntryTouchTarget()\n"
            if relocated_metric_modifier == original:
                raise SystemExit(
                    "M3.12 self-test metric modifier relocation source is missing"
                )
            metric_entry.write_text(
                relocated_metric_modifier,
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "must attach exactly one shared touch-target geometry modifier",
            )
            metric_entry.write_text(original, encoding="utf-8")

            metric_entry.write_text(
                original.replace(
                    ".contentShape(.interaction, Rectangle())",
                    ".contentShape(.accessibility, Rectangle())",
                    1,
                )
                + "\nfunc metricInteractionGeometryDecoy() -> some View { "
                + "EmptyView().contentShape(.interaction, Rectangle()) }\n",
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "touch-target helper must remain the exact direct frame and contentShape chain",
            )
            metric_entry.write_text(original, encoding="utf-8")

            dead_touch_target_geometry = original.replace(
                "    func metricEntryTouchTarget() -> some View {\n"
                "        frame(minHeight: 52)\n"
                "            .contentShape(.interaction, Rectangle())\n"
                "    }",
                "    @ViewBuilder\n"
                "    func metricEntryTouchTarget() -> some View {\n"
                "        if false {\n"
                "            frame(minHeight: 52)\n"
                "                .contentShape(.interaction, Rectangle())\n"
                "        } else {\n"
                "            self\n"
                "        }\n"
                "    }",
                1,
            )
            if dead_touch_target_geometry == original:
                raise SystemExit(
                    "M3.12 self-test dead touch-target anchor is missing"
                )
            metric_entry.write_text(
                dead_touch_target_geometry,
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "touch-target helper must have one plain declaration",
            )
            metric_entry.write_text(original, encoding="utf-8")

            commented_touch_target_geometry = original.replace(
                "frame(minHeight: 52)",
                "frame(/* outer /* nested */ still outer */ minHeight: 52)",
                1,
            )
            if commented_touch_target_geometry == original:
                raise SystemExit(
                    "M3.12 self-test touch-target comment anchor is missing"
                )
            metric_entry.write_text(
                commented_touch_target_geometry,
                encoding="utf-8",
            )
            verify(fixture, "production")
            metric_entry.write_text(original, encoding="utf-8")

            metric_entry.write_text(
                original.replace("!isSaving && !isSaved", "true", 1)
                + "\nfunc metricsDraftClosePolicyDecoy() { _ = !isSaving && !isSaved }\n",
                encoding="utf-8",
            )
            expect_failure(fixture, "production", "M3 Metrics draft-close policy")
            metric_entry.write_text(original, encoding="utf-8")

            metric_entry.write_text(
                original.replace(
                    "shouldOfferDraftClose && !dynamicTypeSize.isAccessibilitySize",
                    "shouldOfferDraftClose && dynamicTypeSize.isAccessibilitySize",
                    1,
                )
                + "\nfunc metricsInlineClosePlacementDecoy() -> Bool { "
                + "shouldOfferDraftClose && !dynamicTypeSize.isAccessibilitySize }\n",
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "M3 Metrics inline draft-close placement policy",
            )
            metric_entry.write_text(original, encoding="utf-8")

            metric_entry.write_text(
                original.replace(
                    "shouldOfferDraftClose && dynamicTypeSize.isAccessibilitySize",
                    "shouldOfferDraftClose && !dynamicTypeSize.isAccessibilitySize",
                    1,
                )
                + "\nfunc metricsAXClosePlacementDecoy() -> Bool { "
                + "shouldOfferDraftClose && dynamicTypeSize.isAccessibilitySize }\n",
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "M3 Metrics AX draft-close placement policy",
            )
            metric_entry.write_text(original, encoding="utf-8")

            metric_entry.write_text(
                original.replace(
                    'Button(localized("metrics.entry.close"), action: onClose)',
                    'Button(localized("metrics.entry.close"), action: {})',
                    1,
                )
                + '\nfunc metricsAXCloseActionDecoy() { '
                + 'Button(localized("metrics.entry.close"), action: onClose) }\n',
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "must remain a direct ViewBuilder expression in its exact container",
            )
            metric_entry.write_text(original, encoding="utf-8")

            metric_entry.write_text(
                original.replace(
                    '.accessibilityIdentifier("metrics.entry.close")',
                    '.accessibilityIdentifier("metrics.entry.detached")',
                    1,
                )
                + '\nfunc metricsAXCloseIdentifierDecoy() { '
                + 'EmptyView().accessibilityIdentifier("metrics.entry.close") }\n',
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "must remain a direct ViewBuilder expression in its exact container",
            )
            metric_entry.write_text(original, encoding="utf-8")

            metric_entry.write_text(
                original.replace(
                    'return "metrics.entry.close"',
                    'return "metrics.entry.detached"',
                    1,
                )
                + '\nfunc metricsDraftCloseIdentifierDecoy() -> String { '
                + 'return "metrics.entry.close" }\n',
                encoding="utf-8",
            )
            expect_failure(fixture, "production", "M3 Metrics draft-close identifier")
            metric_entry.write_text(original, encoding="utf-8")

            metric_entry.write_text(
                original.replace("return { onClose() }", "return {}", 1)
                + "\nfunc metricsDraftCloseActionDecoy() { onClose() }\n",
                encoding="utf-8",
            )
            expect_failure(fixture, "production", "M3 Metrics draft-close action")
            metric_entry.write_text(original, encoding="utf-8")

            lifestyle_entry = fixture / (
                "Packages/HealthTrackingModules/Sources/SleepMoodKit/Entry/"
                "LifestyleEntryView.swift"
            )
            original = lifestyle_entry.read_text(encoding="utf-8")
            lifestyle_entry.write_text(
                original.replace(
                    "guard !isSaving, !isSaved else { return nil }",
                    "guard true else { return nil }",
                    1,
                )
                + "\nfunc lifestyleDraftClosePolicyDecoy() { "
                + "guard !isSaving, !isSaved else { return } }\n",
                encoding="utf-8",
            )
            expect_failure(fixture, "production", "M3 Lifestyle draft-close title")
            lifestyle_entry.write_text(original, encoding="utf-8")

            lifestyle_entry.write_text(
                original.replace("return { onClose() }", "return {}", 1)
                + "\nfunc lifestyleDraftCloseActionDecoy() { onClose() }\n",
                encoding="utf-8",
            )
            expect_failure(fixture, "production", "M3 Lifestyle draft-close action")
            lifestyle_entry.write_text(original, encoding="utf-8")

            lifecycle = fixture / (
                "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/"
                "ProgressPhotoLifecycleView.swift"
            )
            original = mutate_once(
                lifecycle,
                "accessState: broaderPhotoLibraryAccessState",
                "removedAccessState: broaderPhotoLibraryAccessState",
            )
            expect_failure(fixture, "production", "accessState: broaderPhotoLibraryAccessState")
            lifecycle.write_text(original, encoding="utf-8")

            original = mutate_all(
                bundle,
                "broaderPhotoLibraryAccessState",
                "removedBroaderPhotoLibraryAccessState",
            )
            expect_failure(fixture, "production", "broaderPhotoLibraryAccessState")
            bundle.write_text(original, encoding="utf-8")

            picker = fixture / (
                "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Platform/"
                "SystemPhotosPickerView.swift"
            )
            policy_binding = (
                ".disabled(!SystemPhotoPickerAvailability.isEnabled(for: accessState))"
            )
            original = mutate_once(
                picker,
                policy_binding,
                ".disabled(false)\n"
                "        .onAppear { _ = SystemPhotoPickerAvailability.isEnabled(for: accessState) }",
            )
            expect_failure(fixture, "production", policy_binding)
            picker.write_text(original, encoding="utf-8")

            original = picker.read_text(encoding="utf-8")
            decoy_policy = original.replace(
                policy_binding,
                (
                    ".disabled(false)\n"
                    "        Color.clear.disabled("
                    "!SystemPhotoPickerAvailability.isEnabled(for: accessState))"
                ),
                1,
            )
            if decoy_policy == original:
                raise SystemExit("M3.12 self-test picker-policy decoy source is missing")
            picker.write_text(decoy_policy, encoding="utf-8")
            expect_failure(
                fixture,
                "production",
                "attach its exact access-state policy to PhotosPicker",
            )
            picker.write_text(original, encoding="utf-8")

            original = picker.read_text(encoding="utf-8")
            single_picker = (
                "        PhotosPicker()\n"
                '            .accessibilityIdentifier("photos.picker")\n'
                "            .disabled("
                "!SystemPhotoPickerAvailability.isEnabled(for: accessState))\n"
                "            .photoLibraryAccessEvidence(accessState)"
            )
            double_picker = (
                "        PhotosPicker()\n"
                "            .disabled("
                "!SystemPhotoPickerAvailability.isEnabled(for: accessState))\n"
                "        PhotosPicker()\n"
                '            .accessibilityIdentifier("photos.picker")\n'
                "            .disabled(false)\n"
                "            .photoLibraryAccessEvidence(accessState)"
            )
            if single_picker not in original:
                raise SystemExit("M3.12 self-test double-picker source is missing")
            picker.write_text(
                original.replace(single_picker, double_picker, 1),
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "exactly one active PhotosPicker",
            )
            picker.write_text(original, encoding="utf-8")

            hidden_picker_with_fake_button = (
                single_picker
                + "\n            .hidden()\n"
                + '        Button("Fake picker") {}\n'
                + '            .accessibilityIdentifier("photos.picker")\n'
                + "            .disabled(false)\n"
                + "            .photoLibraryAccessEvidence(accessState)"
            )
            picker.write_text(
                original.replace(
                    single_picker,
                    hidden_picker_with_fake_button,
                    1,
                ),
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "visibility-changing or unknown modifiers",
            )
            picker.write_text(original, encoding="utf-8")

            picker_with_trailing_button = (
                single_picker
                + "\n"
                + '        Button("Fake picker") {}\n'
                + '            .accessibilityIdentifier("photos.picker")'
            )
            picker.write_text(
                original.replace(single_picker, picker_with_trailing_button, 1),
                encoding="utf-8",
            )
            expect_failure(
                fixture,
                "production",
                "only its PhotosPicker chain",
            )
            picker.write_text(original, encoding="utf-8")

            original = mutate_once(
                picker,
                policy_binding,
                ".disabled(SystemPhotoPickerAvailability.isEnabled(for: accessState))",
            )
            expect_failure(fixture, "production", policy_binding)
            picker.write_text(original, encoding="utf-8")

            original = mutate_once(
                picker,
                "photoLibraryAccessEvidence(accessState)",
                "removedPhotoLibraryAccessEvidence(accessState)",
            )
            expect_failure(fixture, "production", "photoLibraryAccessEvidence")
            picker.write_text(original, encoding="utf-8")

            original = mutate_once(
                picker,
                "SystemPhotoPickerAvailability.isEnabled(for: accessState)",
                "true",
            )
            expect_failure(
                fixture,
                "production",
                "SystemPhotoPickerAvailability.isEnabled(for: accessState)",
            )
            picker.write_text(original, encoding="utf-8")

        exercise_production_contract_mutations()


try:
    if mode == "--self-test":
        self_test(root)
        print("M3 acceptance verifier self-tests passed.")
    elif mode == "--red":
        verify(root, "red")
        print("M3.12 RED acceptance verification passed.")
    elif mode == "":
        verify(root, "production")
        print("M3 acceptance verification passed.")
    else:
        raise SystemExit(
            "Usage: scripts/verify-m3-acceptance.sh [--red|--self-test]"
        )
except ValueError as error:
    raise SystemExit(str(error)) from error
PY
