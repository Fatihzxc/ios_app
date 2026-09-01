import Foundation
import ProgressPhotosKit
import SwiftUI

#if DEBUG
@MainActor
final class NotificationAuthorizationUITestEvidence: ObservableObject {
    @Published private(set) var requestCount = 0

    func recordRequest() {
        requestCount += 1
    }
}

@MainActor
final class ReportsDashboardFetchUITestEvidence: ObservableObject {
    @Published private(set) var fetchCount = 0

    func recordFetch() {
        fetchCount += 1
    }
}

enum AppUITestScenario: String {
    case seeded
    case emptyOnce = "empty-once"
    case errorOnce = "error-once"
    case loading
    case fatalConfiguration = "fatal-configuration"
    case sessionFlow = "session-flow"
    case sessionFamilies = "session-families"
    case sessionResume = "session-resume"
    case progressionMissingRIR = "progression-missing-rir"
    case weeklyPallof = "weekly-pallof"
    case ohpSafety = "ohp-safety"
    case deloadScheduled = "deload-scheduled"
    case deloadReactive = "deload-reactive"
    case phaseTransition = "phase-transition"
    case trainingHistory = "training-history"
    case m1AcceptanceCatalog = "m1-acceptance-catalog"
    case m1PRBaseline = "m1-pr-baseline"
    case m1PRNew = "m1-pr-new"
    case todayTrain = "today-train"
    case todayRest = "today-rest"
    case todayResume = "today-resume"
    case todayDeload = "today-deload"
    case todayPhase = "today-phase"
    case todayReminder = "today-reminder"
    case todayPriority = "today-priority"
    case todayEmptyOnce = "today-empty-once"
    case todayErrorOnce = "today-error-once"
    case nutritionContent = "nutrition-content"
    case nutritionEmpty = "nutrition-empty"
    case nutritionErrorOnce = "nutrition-error-once"
    case nutritionDeleteErrorOnce = "nutrition-delete-error-once"
    case nutritionQuickAdd = "nutrition-quick-add"
    case m2Acceptance = "m2-acceptance"
    case m3BodyMetrics = "m3-body-metrics"
    case m3SleepMood = "m3-sleep-mood"
    case m3Posture = "m3-posture"
    case m3HealthChecks = "m3-health-checks"
    case m3Bloodwork = "m3-bloodwork"
    case m3ProgressPhotos = "m3-progress-photos"
    case m3PhotoGallery = "m3-photo-gallery"
}

struct AppUITestLaunchConfiguration {
    static let launchPerformanceEvidenceFlag = "-ui-test-launch-performance-evidence"
    static let medicalSafetyFirstUseEvidenceFlag =
        "-ui-test-medical-safety-first-use-evidence"
    static let notificationAuthorizationRequestCountIdentifier =
        "health-check.notifications.permission.request-count"
    static let photoLibraryAccessFlag = "-ui-test-photo-library-access"
    static let fixedNowFlag = "-ui-test-now"
    @MainActor static let notificationAuthorizationEvidence =
        NotificationAuthorizationUITestEvidence()
    @MainActor static let reportsDashboardFetchEvidence =
        ReportsDashboardFetchUITestEvidence()
    @MainActor static var notificationAuthorizationRequestCount: Int {
        notificationAuthorizationEvidence.requestCount
    }

    @MainActor
    static func recordNotificationAuthorizationRequest() {
        notificationAuthorizationEvidence.recordRequest()
    }

    @MainActor
    static func recordReportsDashboardFetch() {
        reportsDashboardFetchEvidence.recordFetch()
    }

    enum Appearance: String {
        case light
        case dark

        var colorScheme: ColorScheme {
            switch self {
            case .light: .light
            case .dark: .dark
            }
        }
    }

    let scenario: AppUITestScenario
    let appearance: Appearance
    let persistentStoreIdentifier: UUID?
    let exposesLaunchPerformanceEvidence: Bool
    let exposesMedicalSafetyFirstUseEvidence: Bool
    let broaderPhotoLibraryAccessState: PhotoLibraryAccessState
    let fixedNow: Date?

    static func resolve(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        guard arguments.filter({ $0 == "-ui-testing" }).count == 1,
              let scenarioValue = uniqueValue(after: "-ui-test-scenario", in: arguments),
              let scenario = AppUITestScenario(rawValue: scenarioValue),
              let appearanceValue = uniqueValue(after: "-ui-test-appearance", in: arguments),
              let appearance = Appearance(rawValue: appearanceValue),
              arguments.filter({ $0 == launchPerformanceEvidenceFlag }).count <= 1,
              arguments.filter({
                  $0 == medicalSafetyFirstUseEvidenceFlag
              }).count <= 1 else {
            return nil
        }

        let persistentStoreIdentifier: UUID?
        if arguments.contains("-ui-test-store-identifier") {
            guard let value = uniqueValue(after: "-ui-test-store-identifier", in: arguments),
                  let identifier = UUID(uuidString: value) else {
                return nil
            }
            persistentStoreIdentifier = identifier
        } else {
            persistentStoreIdentifier = nil
        }

        let broaderPhotoLibraryAccessState: PhotoLibraryAccessState
        if arguments.contains(photoLibraryAccessFlag) {
            guard let value = uniqueValue(after: photoLibraryAccessFlag, in: arguments),
                  let state = PhotoLibraryAccessState(rawValue: value) else {
                return nil
            }
            broaderPhotoLibraryAccessState = state
        } else {
            broaderPhotoLibraryAccessState = .authorized
        }

        let fixedNow: Date?
        if arguments.contains(fixedNowFlag) {
            guard let value = uniqueValue(after: fixedNowFlag, in: arguments),
                  let date = ISO8601DateFormatter().date(from: value) else {
                return nil
            }
            fixedNow = date
        } else {
            fixedNow = nil
        }

        return Self(
            scenario: scenario,
            appearance: appearance,
            persistentStoreIdentifier: persistentStoreIdentifier,
            exposesLaunchPerformanceEvidence: arguments.contains(
                launchPerformanceEvidenceFlag
            ),
            exposesMedicalSafetyFirstUseEvidence: arguments.contains(
                medicalSafetyFirstUseEvidenceFlag
            ),
            broaderPhotoLibraryAccessState: broaderPhotoLibraryAccessState,
            fixedNow: fixedNow
        )
    }

    private static func uniqueValue(after flag: String, in arguments: [String]) -> String? {
        let indexes = arguments.indices.filter { arguments[$0] == flag }
        guard indexes.count == 1,
              let index = indexes.first,
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

enum AppUITestConfigurationError: Error {
    case forcedFatalConfiguration
}
#endif

enum AppLaunchEnvironment {
    static func resolve() throws -> AppEnvironment {
        let environment = try AppEnvironment.resolve()

        #if DEBUG
        if environment == .uiTesting,
           AppUITestLaunchConfiguration.resolve()?.scenario == .fatalConfiguration {
            throw AppUITestConfigurationError.forcedFatalConfiguration
        }
        #endif

        return environment
    }
}
