import Foundation
import HealthChecksKit
import XCTest

final class BloodworkResultDomainTests: XCTestCase {
    func testInputTrimsMarkerUnitAndOptionalNote() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let input = try BloodworkResultInput(
            date: date,
            marker: "  Ferritin \n",
            value: 42.5,
            unit: " ng/mL  ",
            note: "  Sabah ölçümü  "
        )

        XCTAssertEqual(input.date, date)
        XCTAssertEqual(input.marker, "Ferritin")
        XCTAssertEqual(input.value, 42.5)
        XCTAssertEqual(input.unit, "ng/mL")
        XCTAssertEqual(input.note, "Sabah ölçümü")
    }

    func testInputRejectsBlankMarkerAndUnit() {
        XCTAssertThrowsError(
            try BloodworkResultInput(
                date: .now,
                marker: " \n ",
                value: 1,
                unit: "mg/L"
            )
        ) { error in
            XCTAssertEqual(error as? BloodworkResultInputError, .missingMarker)
        }

        XCTAssertThrowsError(
            try BloodworkResultInput(
                date: .now,
                marker: "Ferritin",
                value: 1,
                unit: "\t"
            )
        ) { error in
            XCTAssertEqual(error as? BloodworkResultInputError, .missingUnit)
        }
    }

    func testInputRequiresFiniteValueButPermitsNegativeReferenceValues() throws {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(
                try BloodworkResultInput(
                    date: .now,
                    marker: "İşaretleyici",
                    value: value,
                    unit: "birim"
                )
            ) { error in
                XCTAssertEqual(error as? BloodworkResultInputError, .nonFiniteValue)
            }
        }

        let negative = try BloodworkResultInput(
            date: .now,
            marker: "İşaretleyici",
            value: -3.25,
            unit: "birim"
        )
        XCTAssertEqual(negative.value, -3.25)
    }

    func testBlankOptionalNoteBecomesNil() throws {
        let input = try BloodworkResultInput(
            date: .now,
            marker: "Ferritin",
            value: 20,
            unit: "ng/mL",
            note: " \n "
        )

        XCTAssertNil(input.note)
    }

    func testOrderingUsesNewestDateThenStableUUID() {
        let earlier = snapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            date: Date(timeIntervalSince1970: 100)
        )
        let firstTie = snapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            date: Date(timeIntervalSince1970: 200)
        )
        let secondTie = snapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            date: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(
            [earlier, secondTie, firstTie]
                .sorted(by: BloodworkResultOrdering.newestFirst)
                .map(\.id),
            [firstTie.id, secondTie.id, earlier.id]
        )
    }

    private func snapshot(id: UUID, date: Date) -> BloodworkResultSnapshot {
        BloodworkResultSnapshot(
            id: id,
            createdAt: date,
            updatedAt: date,
            date: date,
            marker: "Ferritin",
            value: 20,
            unit: "ng/mL",
            note: nil
        )
    }
}
