import Foundation
@testable import TrainingKit
import XCTest

final class SymptomEventContractTests: XCTestCase {
    func testTrainingOwnedEventCarriesOnlyStableRoutingValues() {
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000471")!
        let occurredAt = Date(timeIntervalSinceReferenceDate: 31_000)
        let event = SymptomJournalEvent(
            id: id,
            occurredAt: occurredAt,
            source: .overheadPressCurrentSymptom
        )

        XCTAssertEqual(event.id, id)
        XCTAssertEqual(event.occurredAt, occurredAt)
        XCTAssertEqual(event.source, .overheadPressCurrentSymptom)
        XCTAssertEqual(
            Set(Mirror(reflecting: event).children.compactMap(\.label)),
            ["id", "occurredAt", "source"],
            "The cross-module event must not carry score, region, note, or another health payload."
        )
        assertEquatableSendable(event)
    }

    @MainActor
    func testNoOpClientAcceptsTheEventWithoutSideEffects() async throws {
        let event = SymptomJournalEvent(
            id: UUID(),
            occurredAt: Date(timeIntervalSinceReferenceDate: 31_100),
            source: .overheadPressCurrentSymptom
        )

        try await NoOpSymptomEventClient.shared.record(event)
    }

    private func assertEquatableSendable<T: Equatable & Sendable>(_ value: T) {
        XCTAssertEqual(value, value)
    }
}
