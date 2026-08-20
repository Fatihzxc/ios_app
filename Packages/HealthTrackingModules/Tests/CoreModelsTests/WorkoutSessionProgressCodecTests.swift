import CoreModels
import Foundation
import XCTest

final class WorkoutSessionProgressCodecTests: XCTestCase {
    func testEncodingIsSortedAndByteDeterministic() throws {
        let first = uuid("00000000-0000-0000-0000-000000000001")
        let second = uuid("00000000-0000-0000-0000-000000000002")

        let forward = try WorkoutSessionProgressCodec.encode([first, second])
        let reverse = try WorkoutSessionProgressCodec.encode([second, first])

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(
            String(decoding: forward, as: UTF8.self),
            #"{"ids":["00000000-0000-0000-0000-000000000001","00000000-0000-0000-0000-000000000002"],"schemaVersion":1}"#
        )
    }

    func testEmptyAndNonemptyIdentifierSetsRoundTrip() throws {
        let identifiers: Set<UUID> = [
            uuid("00000000-0000-0000-0000-000000000003"),
            uuid("00000000-0000-0000-0000-000000000004")
        ]

        XCTAssertEqual(
            try WorkoutSessionProgressCodec.decode(
                WorkoutSessionProgressCodec.encode(identifiers)
            ),
            identifiers
        )
        XCTAssertEqual(
            try WorkoutSessionProgressCodec.decode(
                WorkoutSessionProgressCodec.encode([])
            ),
            []
        )
    }

    func testMalformedUnknownVersionAndDuplicateIdentifiersFailWithTypedErrors() {
        assertDecodeError(.malformedPayload, json: "{")
        assertDecodeError(
            .unsupportedSchemaVersion(2),
            json: #"{"ids":[],"schemaVersion":2}"#
        )
        let duplicate = "00000000-0000-0000-0000-000000000005"
        assertDecodeError(
            .duplicateIdentifier(uuid(duplicate)),
            json: #"{"ids":["\#(duplicate)","\#(duplicate)"],"schemaVersion":1}"#
        )
    }

    func testPublicCodecValuesAreEquatableAndSendable() {
        assertEquatableSendable(WorkoutSessionProgressCodecError.malformedPayload)
        assertEquatableSendable(WorkoutSessionProgressStage.movement)
        assertEquatableSendable(WorkoutChecklistDisposition.skipped)
        XCTAssertEqual(
            WorkoutSessionProgressStage.allCases.map(\.rawValue),
            ["warmup", "movement", "cooldown", "summary"]
        )
        XCTAssertEqual(
            WorkoutChecklistDisposition.allCases.map(\.rawValue),
            ["pending", "completed", "skipped"]
        )
    }

    private func assertDecodeError(
        _ expected: WorkoutSessionProgressCodecError,
        json: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try WorkoutSessionProgressCodec.decode(Data(json.utf8))
            XCTFail("Expected decoding to fail", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? WorkoutSessionProgressCodecError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}
