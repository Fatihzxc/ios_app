@testable import ReportsKit
import Foundation
import XCTest

final class LifestylePhaseDatasetBuilderTests: XCTestCase {
    func testMissingLocalDaySplitsSeriesWhileStoredZeroRemainsObserved() throws {
        let calendar = try calendar("Europe/Istanbul")
        let interval = try interval("2024-03-30T21:00:00Z", "2024-04-04T21:00:00Z")
        let mood = [
            moodRecord(101, date: try date("2024-03-31T09:00:00Z"), score: 4),
            moodRecord(102, date: try date("2024-04-01T09:00:00Z"), score: 0),
            moodRecord(103, date: try date("2024-04-03T09:00:00Z"), score: 7),
        ]
        let posture = [
            postureRecord(201, date: try date("2024-03-31T10:00:00Z"), score: 2),
            postureRecord(202, date: try date("2024-04-01T10:00:00Z"), score: 0),
            postureRecord(203, date: try date("2024-04-03T10:00:00Z"), score: nil),
        ]

        let report = try LifestylePhaseDatasetBuilder.build(
            sleepRecords: [],
            moodRecords: Array(mood.reversed()),
            postureRecords: Array(posture.reversed()),
            phases: [],
            currentState: nil,
            transitions: [],
            interval: interval,
            calendar: calendar
        )

        XCTAssertEqual(report.moodScoreSeries.map { $0.points.map(\.value) }, [[4, 0], [7]])
        XCTAssertEqual(report.postureSymptomSeries.map { $0.points.map(\.value) }, [[2, 0]])
        XCTAssertEqual(report.moodCoverage.observedCount, 3)
        XCTAssertEqual(report.postureCoverage.observedCount, 2)
    }

    func testDSTGroupingUsesInjectedCalendarAndHalfOpenBoundsWithoutFixedDaySeconds() throws {
        let calendar = try calendar("America/Los_Angeles")
        let interval = try interval("2024-03-09T08:00:00Z", "2024-03-12T07:00:00Z")
        let records = [
            sleepRecord(301, date: interval.start.addingTimeInterval(-0.001), hours: 9),
            sleepRecord(302, date: interval.start, hours: 6),
            sleepRecord(303, date: try date("2024-03-10T09:30:00Z"), hours: 7),
            sleepRecord(304, date: try date("2024-03-11T08:00:00Z"), hours: 8),
            sleepRecord(305, date: interval.endExclusive, hours: 10),
        ]

        let report = try LifestylePhaseDatasetBuilder.build(
            sleepRecords: records,
            moodRecords: [],
            postureRecords: [],
            phases: [],
            currentState: nil,
            transitions: [],
            interval: interval,
            calendar: calendar
        )

        XCTAssertEqual(report.sleepDurationSeries.count, 1)
        XCTAssertEqual(report.sleepDurationSeries[0].points.map(\.value), [6, 7, 8])
        XCTAssertEqual(report.sleepDurationSeries[0].points.map(\.localDay), [
            calendar.startOfDay(for: records[1].date),
            calendar.startOfDay(for: records[2].date),
            calendar.startOfDay(for: records[3].date),
        ])
    }

    func testStableOrderingAndDuplicateLocalDayFailureUseDateCreatedAtThenIdentifier() throws {
        let calendar = try calendar("Europe/Istanbul")
        let interval = try interval("2024-03-31T21:00:00Z", "2024-04-02T21:00:00Z")
        let lowerID = uuid(401)
        let higherID = uuid(402)
        let duplicateDay = try date("2024-04-01T12:00:00Z")
        let records = [
            ReportMoodRecord(
                id: higherID,
                date: duplicateDay,
                createdAt: duplicateDay.addingTimeInterval(2),
                score: 2,
                energy: nil
            ),
            ReportMoodRecord(
                id: lowerID,
                date: duplicateDay.addingTimeInterval(-1),
                createdAt: duplicateDay.addingTimeInterval(1),
                score: 1,
                energy: nil
            ),
        ]

        for input in [records, Array(records.reversed())] {
            XCTAssertThrowsError(try LifestylePhaseDatasetBuilder.build(
                sleepRecords: [],
                moodRecords: Array(input),
                postureRecords: [],
                phases: [],
                currentState: nil,
                transitions: [],
                interval: interval,
                calendar: calendar
            )) { error in
                XCTAssertEqual(
                    error as? LifestylePhaseDatasetError,
                    .duplicateLocalDay(
                        kind: .mood,
                        localDay: calendar.startOfDay(for: duplicateDay),
                        recordIDs: [lowerID, higherID]
                    )
                )
            }
        }
    }

    func testInvalidFiniteRangeAndCanonicalPhaseDataFailWithStableTypedErrors() throws {
        let interval = ReportDateInterval(start: date(0), endExclusive: date(1_000))
        let invalidSleep = sleepRecord(501, date: date(100), hours: .nan)
        let invalidMood = moodRecord(502, date: date(200), score: 11)
        let invalidPosture = postureRecord(503, date: date(300), score: -1)
        let invalidPhase = ReportProgramPhaseRecord(id: uuid(504), name: " Faz ", orderIndex: 1)

        assertBuilderError(.invalidRecord(kind: .sleep, id: invalidSleep.id), interval: interval) {
            try build(sleep: [invalidSleep], interval: interval)
        }
        assertBuilderError(.invalidRecord(kind: .mood, id: invalidMood.id), interval: interval) {
            try build(mood: [invalidMood], interval: interval)
        }
        assertBuilderError(.invalidRecord(kind: .posture, id: invalidPosture.id), interval: interval) {
            try build(posture: [invalidPosture], interval: interval)
        }
        assertBuilderError(.invalidPhase(id: invalidPhase.id), interval: interval) {
            try build(phases: [invalidPhase], interval: interval)
        }
    }

    func testLoneCurrentStateIsPartialEvidenceAndMonthMetadataNeverCreatesHistory() throws {
        let phase = ReportProgramPhaseRecord(id: uuid(601), name: "Temel", orderIndex: 1)
        let state = ReportCurrentPhaseStateRecord(
            programID: uuid(600),
            phaseID: phase.id,
            phaseStartedAt: date(200)
        )
        let interval = ReportDateInterval(start: date(100), endExclusive: date(500))

        let report = try build(phases: [phase], state: state, interval: interval)

        XCTAssertEqual(report.phaseTimelineProvenance, .partialCurrentState)
        XCTAssertEqual(report.phaseSegments, [
            ReportPhaseSegment(
                phaseID: phase.id,
                phaseName: "Temel",
                startedAt: date(200),
                endedAt: nil,
                visibleStart: date(200),
                visibleEndExclusive: date(500)
            )
        ])
        XCTAssertFalse(report.phaseTimelineProvenance == .actualTransitions)
    }

    func testActualLedgerTransitionsProduceClippedRealSegmentsWithExplicitProvenance() throws {
        let programID = uuid(700)
        let first = ReportProgramPhaseRecord(id: uuid(701), name: "Temel", orderIndex: 1)
        let second = ReportProgramPhaseRecord(id: uuid(702), name: "İnşa", orderIndex: 2)
        let third = ReportProgramPhaseRecord(id: uuid(703), name: "Sürdür", orderIndex: 3)
        let transitions = [
            transitionRecord(711, programID, first.id, second.id, date(100), date(300)),
            transitionRecord(712, programID, second.id, third.id, date(300), date(700)),
        ]
        let state = ReportCurrentPhaseStateRecord(
            programID: programID,
            phaseID: third.id,
            phaseStartedAt: date(700)
        )
        let interval = ReportDateInterval(start: date(250), endExclusive: date(800))

        let report = try build(
            phases: [third, first, second],
            state: state,
            transitions: Array(transitions.reversed()),
            interval: interval
        )

        XCTAssertEqual(report.phaseTimelineProvenance, .actualTransitions)
        XCTAssertEqual(report.phaseSegments.map(\.phaseID), [first.id, second.id, third.id])
        XCTAssertEqual(report.phaseSegments.map(\.startedAt), [date(100), date(300), date(700)])
        XCTAssertEqual(report.phaseSegments.map(\.endedAt), [date(300), date(700), nil])
        XCTAssertEqual(report.phaseSegments.map(\.visibleStart), [date(250), date(300), date(700)])
        XCTAssertEqual(report.phaseSegments.map(\.visibleEndExclusive), [date(300), date(700), date(800)])
    }

    func testPhaseRelationshipIdentityAndChainCorruptionFailDeterministically() throws {
        let programID = uuid(800)
        let phase = ReportProgramPhaseRecord(id: uuid(801), name: "Temel", orderIndex: 1)
        let missingID = uuid(899)
        let state = ReportCurrentPhaseStateRecord(
            programID: programID,
            phaseID: missingID,
            phaseStartedAt: date(100)
        )
        let interval = ReportDateInterval(start: date(0), endExclusive: date(500))

        assertBuilderError(.missingPhase(id: missingID), interval: interval) {
            try build(phases: [phase], state: state, interval: interval)
        }
    }

    func testDuplicateTransitionIdentifierFailsBeforeChainValidation() throws {
        let programID = uuid(900)
        let first = ReportProgramPhaseRecord(id: uuid(901), name: "Temel", orderIndex: 1)
        let second = ReportProgramPhaseRecord(id: uuid(902), name: "İnşa", orderIndex: 2)
        let third = ReportProgramPhaseRecord(id: uuid(903), name: "Sürdür", orderIndex: 3)
        let sharedID = uuid(911)
        let transitions = [
            transitionRecord(sharedID, programID, first.id, second.id, date(100), date(200)),
            transitionRecord(sharedID, programID, second.id, third.id, date(200), date(300)),
        ]
        let state = ReportCurrentPhaseStateRecord(
            programID: programID,
            phaseID: third.id,
            phaseStartedAt: date(300)
        )
        let interval = ReportDateInterval(start: date(0), endExclusive: date(500))

        for records in [transitions, Array(transitions.reversed())] {
            assertBuilderError(.duplicateTransitionID(id: sharedID), interval: interval) {
                try build(
                    phases: [first, second, third],
                    state: state,
                    transitions: records,
                    interval: interval
                )
            }
        }
    }

    func testDuplicateLogicalTransitionUsesStableSortedIDsBeforeTimestampAmbiguity() throws {
        let programID = uuid(920)
        let first = ReportProgramPhaseRecord(id: uuid(921), name: "Temel", orderIndex: 1)
        let second = ReportProgramPhaseRecord(id: uuid(922), name: "İnşa", orderIndex: 2)
        let lowerID = uuid(931)
        let higherID = uuid(932)
        let transitionedAt = date(300)
        let transitions = [
            transitionRecord(higherID, programID, first.id, second.id, date(100), transitionedAt),
            transitionRecord(lowerID, programID, first.id, second.id, date(100), transitionedAt),
        ]
        let state = ReportCurrentPhaseStateRecord(
            programID: programID,
            phaseID: second.id,
            phaseStartedAt: transitionedAt
        )
        let interval = ReportDateInterval(start: date(0), endExclusive: date(500))

        for records in [transitions, Array(transitions.reversed())] {
            assertBuilderError(
                .duplicateLogicalTransition(recordIDs: [lowerID, higherID]),
                interval: interval
            ) {
                try build(
                    phases: [first, second],
                    state: state,
                    transitions: records,
                    interval: interval
                )
            }
        }
    }

    func testEqualTransitionTimestampFailsWithStableIDsRegardlessOfIDOrInputOrder() throws {
        let programID = uuid(940)
        let first = ReportProgramPhaseRecord(id: uuid(941), name: "Temel", orderIndex: 1)
        let second = ReportProgramPhaseRecord(id: uuid(942), name: "İnşa", orderIndex: 2)
        let third = ReportProgramPhaseRecord(id: uuid(943), name: "Sürdür", orderIndex: 3)
        let lowerID = uuid(951)
        let higherID = uuid(952)
        let transitionedAt = date(300)
        let state = ReportCurrentPhaseStateRecord(
            programID: programID,
            phaseID: third.id,
            phaseStartedAt: transitionedAt
        )
        let interval = ReportDateInterval(start: date(0), endExclusive: date(500))

        for (firstID, secondID) in [(lowerID, higherID), (higherID, lowerID)] {
            let records = [
                transitionRecord(firstID, programID, first.id, second.id, date(100), transitionedAt),
                transitionRecord(
                    secondID,
                    programID,
                    second.id,
                    third.id,
                    transitionedAt,
                    transitionedAt
                ),
            ]
            for input in [records, Array(records.reversed())] {
                assertBuilderError(
                    .duplicateTransitionTimestamp(
                        transitionedAt: transitionedAt,
                        recordIDs: [lowerID, higherID]
                    ),
                    interval: interval
                ) {
                    try build(
                        phases: [first, second, third],
                        state: state,
                        transitions: input,
                        interval: interval
                    )
                }
            }
        }
    }

    func testLifestylePhaseContractsAreImmutableEquatableAndSendable() {
        assertEquatableSendable(ReportSleepRecord.self)
        assertEquatableSendable(ReportMoodRecord.self)
        assertEquatableSendable(ReportPostureRecord.self)
        assertEquatableSendable(ReportProgramPhaseRecord.self)
        assertEquatableSendable(ReportCurrentPhaseStateRecord.self)
        assertEquatableSendable(ReportPhaseTransitionRecord.self)
        assertEquatableSendable(ReportNumericPoint.self)
        assertEquatableSendable(ReportNumericSeries.self)
        assertEquatableSendable(ReportPhaseSegment.self)
        assertEquatableSendable(PhaseTimelineProvenance.self)
        assertEquatableSendable(LifestylePhaseReport.self)
        assertEquatableSendable(LifestylePhaseDatasetError.self)
    }

    private func build(
        sleep: [ReportSleepRecord] = [],
        mood: [ReportMoodRecord] = [],
        posture: [ReportPostureRecord] = [],
        phases: [ReportProgramPhaseRecord] = [],
        state: ReportCurrentPhaseStateRecord? = nil,
        transitions: [ReportPhaseTransitionRecord] = [],
        interval: ReportDateInterval
    ) throws -> LifestylePhaseReport {
        try LifestylePhaseDatasetBuilder.build(
            sleepRecords: sleep,
            moodRecords: mood,
            postureRecords: posture,
            phases: phases,
            currentState: state,
            transitions: transitions,
            interval: interval,
            calendar: try calendar("UTC")
        )
    }

    private func assertBuilderError(
        _ expected: LifestylePhaseDatasetError,
        interval _: ReportDateInterval,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation()) { error in
            XCTAssertEqual(error as? LifestylePhaseDatasetError, expected)
        }
    }

    private func sleepRecord(_ value: Int, date: Date, hours: Double) -> ReportSleepRecord {
        ReportSleepRecord(id: uuid(value), date: date, createdAt: date, durationHours: hours, quality: 7)
    }

    private func moodRecord(_ value: Int, date: Date, score: Int?) -> ReportMoodRecord {
        ReportMoodRecord(id: uuid(value), date: date, createdAt: date, score: score, energy: nil)
    }

    private func postureRecord(_ value: Int, date: Date, score: Int?) -> ReportPostureRecord {
        ReportPostureRecord(
            id: uuid(value),
            date: date,
            createdAt: date,
            symptomScore: score,
            wallTestPass: nil
        )
    }

    private func transitionRecord(
        _ value: Int,
        _ programID: UUID,
        _ from: UUID,
        _ to: UUID,
        _ started: Date,
        _ transitioned: Date
    ) -> ReportPhaseTransitionRecord {
        ReportPhaseTransitionRecord(
            id: uuid(value),
            programID: programID,
            fromPhaseID: from,
            toPhaseID: to,
            fromStartedAt: started,
            transitionedAt: transitioned
        )
    }

    private func transitionRecord(
        _ id: UUID,
        _ programID: UUID,
        _ from: UUID,
        _ to: UUID,
        _ started: Date,
        _ transitioned: Date
    ) -> ReportPhaseTransitionRecord {
        ReportPhaseTransitionRecord(
            id: id,
            programID: programID,
            fromPhaseID: from,
            toPhaseID: to,
            fromStartedAt: started,
            transitionedAt: transitioned
        )
    }

    private func interval(_ start: String, _ end: String) throws -> ReportDateInterval {
        ReportDateInterval(start: try date(start), endExclusive: try date(end))
    }

    private func date(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: value)
    }

    private func calendar(_ identifier: String) throws -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = try XCTUnwrap(TimeZone(identifier: identifier))
        return value
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}
