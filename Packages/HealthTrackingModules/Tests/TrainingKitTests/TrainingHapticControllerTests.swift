import Foundation
import TrainingKit
import XCTest

@MainActor
final class TrainingHapticControllerTests: XCTestCase {
    func testSemanticEventsMapToExactFeedbackAndConditionalSuccessStaysSilent() {
        let client = RecordingHapticClient()
        let store = HapticPreferenceStoreSpy(enabled: true)
        let controller = TrainingHapticController(client: client, preferenceStore: store)
        controller.loadPreference()

        controller.handle(.setSaved)
        controller.handle(.personalRecord(isNew: false))
        controller.handle(.personalRecord(isNew: true))
        controller.handle(.phaseTransition(isConfirmed: false))
        controller.handle(.phaseTransition(isConfirmed: true))
        controller.handle(.safetyStop)
        controller.handle(.deload)
        controller.handle(.validationError)
        controller.handle(.repositoryError)

        XCTAssertEqual(
            client.feedback,
            [
                .mediumImpact,
                .success,
                .success,
                .warning,
                .warning,
                .error,
                .error,
            ]
        )
    }

    func testSelectionUsesInjectedMonotonicClockAndOneHundredMillisecondThrottle() {
        let client = RecordingHapticClient()
        let store = HapticPreferenceStoreSpy(enabled: true)
        var uptime: TimeInterval = 10
        let controller = TrainingHapticController(
            client: client,
            preferenceStore: store,
            selectionThrottle: 0.1,
            uptime: { uptime }
        )
        controller.loadPreference()

        controller.handle(.stepperChanged)
        uptime = 10.05
        controller.handle(.stepperChanged)
        uptime = 10.11
        controller.handle(.stepperChanged)
        uptime = 10.15
        controller.handle(.stepperChanged)
        uptime = 10.22
        controller.handle(.stepperChanged)

        XCTAssertEqual(client.feedback, [.selection, .selection, .selection])
    }

    func testUnloadedOrPersistedDisabledPreferenceSuppressesEveryEvent() throws {
        let client = RecordingHapticClient()
        let store = HapticPreferenceStoreSpy(enabled: false)
        let controller = TrainingHapticController(client: client, preferenceStore: store)
        let everyEvent: [TrainingHapticEvent] = [
            .setSaved,
            .stepperChanged,
            .personalRecord(isNew: true),
            .phaseTransition(isConfirmed: true),
            .safetyStop,
            .deload,
            .validationError,
            .repositoryError,
        ]

        everyEvent.forEach(controller.handle)
        XCTAssertEqual(controller.preferenceState, .unloaded)
        XCTAssertTrue(client.feedback.isEmpty)

        controller.loadPreference()
        everyEvent.forEach(controller.handle)
        XCTAssertEqual(controller.preferenceState, .loaded)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertTrue(client.feedback.isEmpty)

        try controller.setEnabled(true)
        controller.handle(.setSaved)
        XCTAssertEqual(store.savedValues, [true])
        XCTAssertEqual(client.feedback, [.mediumImpact])
    }

    func testKillSwitchPersistsAcrossControllerReconstruction() throws {
        let store = HapticPreferenceStoreSpy(enabled: true)
        let firstClient = RecordingHapticClient()
        let first = TrainingHapticController(client: firstClient, preferenceStore: store)
        first.loadPreference()

        try first.setEnabled(false)
        first.handle(.setSaved)

        let relaunchedClient = RecordingHapticClient()
        let relaunched = TrainingHapticController(
            client: relaunchedClient,
            preferenceStore: store
        )
        relaunched.loadPreference()
        relaunched.handle(.repositoryError)

        XCTAssertEqual(store.savedValues, [false])
        XCTAssertFalse(relaunched.isEnabled)
        XCTAssertTrue(firstClient.feedback.isEmpty)
        XCTAssertTrue(relaunchedClient.feedback.isEmpty)
    }

    func testPreferenceSaveFailureFailsClosedAndNeverEmitsFeedback() {
        let client = RecordingHapticClient()
        let store = HapticPreferenceStoreSpy(enabled: true)
        let controller = TrainingHapticController(client: client, preferenceStore: store)
        controller.loadPreference()
        store.saveError = HapticPreferenceTestError.save

        XCTAssertThrowsError(try controller.setEnabled(false))
        controller.handle(.setSaved)

        XCTAssertEqual(controller.preferenceState, .failed)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertTrue(client.feedback.isEmpty)
    }
}

@MainActor
private final class RecordingHapticClient: TrainingHapticClient {
    private(set) var feedback: [TrainingHapticFeedback] = []

    func play(_ feedback: TrainingHapticFeedback) {
        self.feedback.append(feedback)
    }
}

@MainActor
private final class HapticPreferenceStoreSpy: TrainingHapticPreferenceStore {
    var enabled: Bool
    var loadError: Error?
    var saveError: Error?
    private(set) var savedValues: [Bool] = []

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func loadHapticsEnabled() throws -> Bool {
        if let loadError { throw loadError }
        return enabled
    }

    func saveHapticsEnabled(_ isEnabled: Bool) throws {
        if let saveError { throw saveError }
        enabled = isEnabled
        savedValues.append(isEnabled)
    }
}

private enum HapticPreferenceTestError: Error {
    case save
}
