import CoreModels
import Foundation
import XCTest

final class PhaseTransitionLedgerTests: XCTestCase {
    func testKeyUsesExactVersionedPrefixAndLowercaseProgramIdentifier() {
        let programID = uuid("AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")

        XCTAssertEqual(
            PhaseTransitionLedgerV1.key(for: programID),
            "phase-transition-ledger.v1.aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        )
    }

    func testEncodingSortsByTransitionDateAndIsByteDeterministic() throws {
        let programID = uuid("00000000-0000-4000-8000-000000000001")
        let earlier = record(
            id: uuid("00000000-0000-4000-8000-000000000102"),
            programID: programID,
            from: uuid("00000000-0000-4000-8000-000000000201"),
            to: uuid("00000000-0000-4000-8000-000000000202"),
            started: date(100),
            transitioned: date(200)
        )
        let middleHighID = record(
            id: uuid("00000000-0000-4000-8000-000000000104"),
            programID: programID,
            from: earlier.toPhaseID,
            to: uuid("00000000-0000-4000-8000-000000000203"),
            started: date(200),
            transitioned: date(300)
        )
        let laterLowID = record(
            id: uuid("00000000-0000-4000-8000-000000000103"),
            programID: programID,
            from: middleHighID.toPhaseID,
            to: uuid("00000000-0000-4000-8000-000000000204"),
            started: date(300),
            transitioned: date(400)
        )

        let forward = try PhaseTransitionLedgerV1(
            records: [middleHighID, earlier, laterLowID]
        ).encoded(for: programID)
        let reverse = try PhaseTransitionLedgerV1(
            records: [laterLowID, earlier, middleHighID]
        ).encoded(for: programID)
        let decoded = try PhaseTransitionLedgerV1.decode(forward, for: programID)

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(decoded.records.map(\.id), [earlier.id, middleHighID.id, laterLowID.id])
        XCTAssertEqual(decoded.schemaVersion, PhaseTransitionLedgerV1.currentSchemaVersion)
    }

    func testMalformedAndUnknownSchemaPayloadsFailWithTypedErrors() {
        let programID = uuid("00000000-0000-4000-8000-000000000001")

        assertDecodeError(.malformedPayload, value: "{", programID: programID)
        assertDecodeError(
            .unsupportedSchemaVersion(2),
            value: #"{"records":[],"schemaVersion":2}"#,
            programID: programID
        )
    }

    func testDuplicateIdentifiersAndLogicalTransitionsFailDeterministically() {
        let programID = uuid("00000000-0000-4000-8000-000000000001")
        let lowerID = uuid("00000000-0000-4000-8000-000000000101")
        let higherID = uuid("00000000-0000-4000-8000-000000000102")
        let first = record(
            id: lowerID,
            programID: programID,
            from: uuid("00000000-0000-4000-8000-000000000201"),
            to: uuid("00000000-0000-4000-8000-000000000202"),
            started: date(100),
            transitioned: date(200)
        )
        let duplicateID = record(
            id: lowerID,
            programID: programID,
            from: first.toPhaseID,
            to: uuid("00000000-0000-4000-8000-000000000203"),
            started: date(200),
            transitioned: date(300)
        )
        let duplicateLogical = record(
            id: higherID,
            programID: programID,
            from: first.fromPhaseID,
            to: first.toPhaseID,
            started: first.fromStartedAt,
            transitioned: first.transitionedAt
        )

        XCTAssertThrowsError(
            try PhaseTransitionLedgerV1(records: [duplicateID, first]).validated(for: programID)
        ) { error in
            XCTAssertEqual(error as? PhaseTransitionLedgerError, .duplicateRecordID(lowerID))
        }
        for records in [[duplicateLogical, first], [first, duplicateLogical]] {
            XCTAssertThrowsError(
                try PhaseTransitionLedgerV1(records: records).validated(for: programID)
            ) { error in
                XCTAssertEqual(
                    error as? PhaseTransitionLedgerError,
                    .duplicateLogicalTransition(recordIDs: [lowerID, higherID])
                )
            }
        }
    }

    func testDuplicateLogicalGroupSelectionUsesProgramIDAcrossAllInputPermutations() {
        let lowerProgramID = uuid("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeee0001")
        let higherProgramID = uuid("BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFF0002")
        let fromPhaseID = uuid("00000000-0000-4000-8000-000000000201")
        let toPhaseID = uuid("00000000-0000-4000-8000-000000000202")
        let lowerRecordID = uuid("00000000-0000-4000-8000-000000000103")
        let lowerDuplicateID = uuid("00000000-0000-4000-8000-000000000104")
        let higherRecordID = uuid("00000000-0000-4000-8000-000000000101")
        let higherDuplicateID = uuid("00000000-0000-4000-8000-000000000102")

        XCTAssertEqual(
            lowerProgramID.uuidString,
            "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEE0001"
        )
        XCTAssertLessThan(lowerProgramID.uuidString, higherProgramID.uuidString)
        XCTAssertGreaterThan(lowerRecordID.uuidString, higherDuplicateID.uuidString)

        let inputs = permutations(of: [
            record(
                id: lowerRecordID,
                programID: lowerProgramID,
                from: fromPhaseID,
                to: toPhaseID,
                started: date(100),
                transitioned: date(200)
            ),
            record(
                id: lowerDuplicateID,
                programID: lowerProgramID,
                from: fromPhaseID,
                to: toPhaseID,
                started: date(100),
                transitioned: date(200)
            ),
            record(
                id: higherRecordID,
                programID: higherProgramID,
                from: fromPhaseID,
                to: toPhaseID,
                started: date(100),
                transitioned: date(200)
            ),
            record(
                id: higherDuplicateID,
                programID: higherProgramID,
                from: fromPhaseID,
                to: toPhaseID,
                started: date(100),
                transitioned: date(200)
            ),
        ])

        XCTAssertEqual(inputs.count, 24)
        for records in inputs {
            XCTAssertThrowsError(
                try PhaseTransitionLedgerV1(records: records).validated(for: lowerProgramID)
            ) { error in
                XCTAssertEqual(
                    error as? PhaseTransitionLedgerError,
                    .duplicateLogicalTransition(
                        recordIDs: [lowerRecordID, lowerDuplicateID]
                    )
                )
            }
        }
    }

    func testEqualTransitionTimestampsFailBeforeChainValidationRegardlessOfIDOrInputOrder() {
        let programID = uuid("00000000-0000-4000-8000-000000000001")
        let phaseA = uuid("00000000-0000-4000-8000-000000000201")
        let phaseB = uuid("00000000-0000-4000-8000-000000000202")
        let phaseC = uuid("00000000-0000-4000-8000-000000000203")
        let lowerID = uuid("00000000-0000-4000-8000-000000000101")
        let higherID = uuid("00000000-0000-4000-8000-000000000102")
        let transitionedAt = date(300)

        for (firstID, secondID) in [(lowerID, higherID), (higherID, lowerID)] {
            let first = record(
                id: firstID,
                programID: programID,
                from: phaseA,
                to: phaseB,
                started: date(100),
                transitioned: transitionedAt
            )
            let second = record(
                id: secondID,
                programID: programID,
                from: phaseB,
                to: phaseC,
                started: transitionedAt,
                transitioned: transitionedAt
            )
            for records in [[first, second], [second, first]] {
                XCTAssertThrowsError(
                    try PhaseTransitionLedgerV1(records: records).validated(for: programID)
                ) { error in
                    XCTAssertEqual(
                        error as? PhaseTransitionLedgerError,
                        .duplicateTransitionTimestamp(
                            transitionedAt: transitionedAt,
                            recordIDs: [lowerID, higherID]
                        )
                    )
                }
            }
        }
    }

    func testInvalidCrossProgramAndBrokenChainRecordsFailClosed() {
        let programID = uuid("00000000-0000-4000-8000-000000000001")
        let otherProgramID = uuid("00000000-0000-4000-8000-000000000002")
        let invalid = record(
            id: uuid("00000000-0000-4000-8000-000000000101"),
            programID: programID,
            from: uuid("00000000-0000-4000-8000-000000000201"),
            to: uuid("00000000-0000-4000-8000-000000000201"),
            started: date(300),
            transitioned: date(200)
        )
        let foreign = record(
            id: uuid("00000000-0000-4000-8000-000000000102"),
            programID: otherProgramID,
            from: uuid("00000000-0000-4000-8000-000000000202"),
            to: uuid("00000000-0000-4000-8000-000000000203"),
            started: date(100),
            transitioned: date(200)
        )
        let valid = record(
            id: uuid("00000000-0000-4000-8000-000000000103"),
            programID: programID,
            from: uuid("00000000-0000-4000-8000-000000000201"),
            to: uuid("00000000-0000-4000-8000-000000000202"),
            started: date(100),
            transitioned: date(200)
        )
        let broken = record(
            id: uuid("00000000-0000-4000-8000-000000000104"),
            programID: programID,
            from: uuid("00000000-0000-4000-8000-000000000299"),
            to: uuid("00000000-0000-4000-8000-000000000203"),
            started: date(200),
            transitioned: date(300)
        )

        XCTAssertThrowsError(try PhaseTransitionLedgerV1(records: [invalid]).validated(for: programID)) { error in
            XCTAssertEqual(error as? PhaseTransitionLedgerError, .invalidRecord(id: invalid.id))
        }
        XCTAssertThrowsError(try PhaseTransitionLedgerV1(records: [foreign]).validated(for: programID)) { error in
            XCTAssertEqual(
                error as? PhaseTransitionLedgerError,
                .crossProgramRecord(
                    recordID: foreign.id,
                    expectedProgramID: programID,
                    actualProgramID: otherProgramID
                )
            )
        }
        XCTAssertThrowsError(try PhaseTransitionLedgerV1(records: [valid, broken]).validated(for: programID)) { error in
            XCTAssertEqual(
                error as? PhaseTransitionLedgerError,
                .brokenTransitionChain(previousRecordID: valid.id, recordID: broken.id)
            )
        }
    }

    func testLedgerPublicContractsAreEquatableCodableAndSendable() {
        assertCodableEquatableSendable(PhaseTransitionRecord.self)
        assertCodableEquatableSendable(PhaseTransitionLedgerV1.self)
        assertEquatableSendable(PhaseTransitionLedgerError.self)
    }

    private func assertDecodeError(
        _ expected: PhaseTransitionLedgerError,
        value: String,
        programID: UUID
    ) {
        XCTAssertThrowsError(try PhaseTransitionLedgerV1.decode(value, for: programID)) { error in
            XCTAssertEqual(error as? PhaseTransitionLedgerError, expected)
        }
    }

    private func record(
        id: UUID,
        programID: UUID,
        from: UUID,
        to: UUID,
        started: Date,
        transitioned: Date
    ) -> PhaseTransitionRecord {
        PhaseTransitionRecord(
            id: id,
            programID: programID,
            fromPhaseID: from,
            toPhaseID: to,
            fromStartedAt: started,
            transitionedAt: transitioned
        )
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: value)
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func permutations<Value>(of values: [Value]) -> [[Value]] {
        guard !values.isEmpty else { return [[]] }
        return values.indices.flatMap { index in
            var remaining = values
            let first = remaining.remove(at: index)
            return permutations(of: remaining).map { [first] + $0 }
        }
    }

    private func assertCodableEquatableSendable<Value: Codable & Equatable & Sendable>(_: Value.Type) {}
    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}
