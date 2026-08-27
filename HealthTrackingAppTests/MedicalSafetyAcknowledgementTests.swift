@testable import HealthTrackingApp
import HealthSafetyKit
import XCTest

@MainActor
final class MedicalSafetyAcknowledgementTests: XCTestCase {
    // Mutation caught: keeping acknowledgement only in view state would show L0
    // again after recreation or let it suppress the independently permanent L1.
    func testSuccessfulAcknowledgementPersistsAcrossControllerRecreationWithoutChangingLevelOne() {
        let store = MedicalSafetyAcknowledgementStoreStub(isAcknowledged: false)
        let firstUse = MedicalSafetyAcknowledgementController(store: store)

        XCTAssertTrue(firstUse.isLevelZeroVisible)
        XCTAssertEqual(firstUse.levelOnePresentation, .permanent)
        XCTAssertTrue(firstUse.acknowledge())
        XCTAssertEqual(store.saveCallCount, 1)
        XCTAssertFalse(firstUse.isLevelZeroVisible)
        XCTAssertEqual(firstUse.levelOnePresentation, .permanent)

        let recreated = MedicalSafetyAcknowledgementController(store: store)

        XCTAssertFalse(recreated.isLevelZeroVisible)
        XCTAssertEqual(recreated.levelOnePresentation, .permanent)
        XCTAssertEqual(
            recreated.levelOnePresentation.text,
            "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."
        )
        XCTAssertTrue(recreated.levelOnePresentation.isAlwaysVisible)
    }

    // Mutation caught: updating in-memory state before a durable write succeeds
    // would falsely hide L0 after an acknowledgement persistence failure.
    func testFailedAcknowledgementWriteKeepsLevelZeroVisibleAndLevelOnePermanent() {
        let store = MedicalSafetyAcknowledgementStoreStub(
            isAcknowledged: false,
            saveError: .writeFailed
        )
        let controller = MedicalSafetyAcknowledgementController(store: store)

        XCTAssertFalse(controller.acknowledge())

        XCTAssertEqual(store.saveCallCount, 1)
        XCTAssertTrue(controller.isLevelZeroVisible)
        XCTAssertEqual(controller.levelOnePresentation, .permanent)
        XCTAssertEqual(
            controller.levelOnePresentation.text,
            "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."
        )
        XCTAssertTrue(controller.levelOnePresentation.isAlwaysVisible)
    }
}

@MainActor
private final class MedicalSafetyAcknowledgementStoreStub: MedicalSafetyAcknowledgementStore {
    private(set) var saveCallCount = 0
    private var isAcknowledged: Bool
    private let saveError: StoreFailure?

    init(isAcknowledged: Bool, saveError: StoreFailure? = nil) {
        self.isAcknowledged = isAcknowledged
        self.saveError = saveError
    }

    func loadAcknowledged() throws -> Bool {
        isAcknowledged
    }

    func saveAcknowledged() throws {
        saveCallCount += 1
        if let saveError { throw saveError }
        isAcknowledged = true
    }

    enum StoreFailure: Error {
        case writeFailed
    }
}
