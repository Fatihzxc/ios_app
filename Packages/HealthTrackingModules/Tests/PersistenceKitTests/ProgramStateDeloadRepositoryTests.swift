import CoreModels
import Foundation
@testable import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class ProgramStateDeloadRepositoryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    func testTrainingWeekRecalculationCountsOnlyDistinctCompletedLocalWeeks() async throws {
        let fixture = try makeFixture()
        insertSession(in: fixture, date: date(2026, 8, 4), status: .completed)
        insertSession(in: fixture, date: date(2026, 8, 6), status: .completed)
        insertSession(in: fixture, date: date(2026, 8, 11), status: .completed)
        insertSession(in: fixture, date: date(2026, 8, 18), status: .inProgress)
        try fixture.context.save()

        var state = try await fixture.repository.recalculateProgramStateTrainingWeek(
            programID: fixture.program.id,
            programStartDate: date(2026, 8, 3),
            at: date(2026, 8, 18, 20)
        )
        XCTAssertEqual(state.trainingWeekIndex, 2)

        let inProgress = try fixture.context.fetch(FetchDescriptor<WorkoutSession>())
            .first(where: { $0.status == .inProgress })!
        inProgress.status = .completed
        try fixture.context.save()
        state = try await fixture.repository.recalculateProgramStateTrainingWeek(
            programID: fixture.program.id,
            programStartDate: date(2026, 8, 3),
            at: date(2026, 8, 18, 21)
        )

        XCTAssertEqual(state.trainingWeekIndex, 3)
        XCTAssertEqual(state.updatedAt, date(2026, 8, 18, 21))
    }

    func testProgramStartDateEditDeterministicallyRecalculatesTheCounter() async throws {
        let fixture = try makeFixture(trainingWeekIndex: 99)
        for completion in [date(2026, 8, 4), date(2026, 8, 11), date(2026, 8, 18)] {
            insertSession(in: fixture, date: completion, status: .completed)
        }
        try fixture.context.save()

        let original = try await fixture.repository.recalculateProgramStateTrainingWeek(
            programID: fixture.program.id,
            programStartDate: date(2026, 8, 3),
            at: date(2026, 8, 20)
        )
        let originalWeekIndex = original.trainingWeekIndex
        let edited = try await fixture.repository.recalculateProgramStateTrainingWeek(
            programID: fixture.program.id,
            programStartDate: date(2026, 8, 10),
            at: date(2026, 8, 21)
        )

        XCTAssertEqual(originalWeekIndex, 3)
        XCTAssertEqual(edited.trainingWeekIndex, 2)
    }

    func testCompletingASessionAtomicallyAdvancesWeekAndRollsDeloadState() async throws {
        let fixture = try makeFixture(
            trainingWeekIndex: 2,
            deloadStatus: .active,
            deloadReason: .scheduled,
            deloadUpdatedAt: date(2026, 8, 11),
            lastDeloadAction: .accepted
        )
        insertSession(in: fixture, date: date(2026, 8, 4), status: .completed)
        insertSession(in: fixture, date: date(2026, 8, 11), status: .completed)
        let completing = insertSession(
            in: fixture,
            date: date(2026, 8, 18),
            status: .inProgress
        )
        try fixture.context.save()

        _ = try await fixture.repository.transitionWorkoutSession(
            id: completing.id,
            to: .completed,
            at: date(2026, 8, 18, 20)
        )

        let fetched = try await fixture.repository.fetchProgramState(
            programID: fixture.program.id
        )
        let state = try XCTUnwrap(fetched)
        XCTAssertEqual(state.trainingWeekIndex, 3)
        XCTAssertEqual(state.deloadStatus, .none)
        XCTAssertNil(state.deloadReason)
        XCTAssertEqual(state.lastDeloadAction, .accepted)
        XCTAssertEqual(state.updatedAt, date(2026, 8, 18, 20))
    }

    func testNewCompletedWeekRollsActiveAndSkippedStateToNoneWithoutErasingAudit() async throws {
        for status in [DeloadStatus.active, .skipped] {
            let fixture = try makeFixture(
                trainingWeekIndex: 3,
                deloadStatus: status,
                deloadReason: .scheduled,
                deloadUpdatedAt: date(2026, 8, 18),
                lastDeloadSkippedAt: status == .skipped ? date(2026, 8, 18) : nil,
                lastDeloadAction: status == .active ? .accepted : .techniqueReview
            )
            for completion in [
                date(2026, 8, 4),
                date(2026, 8, 11),
                date(2026, 8, 18),
                date(2026, 8, 25),
            ] {
                insertSession(in: fixture, date: completion, status: .completed)
            }
            try fixture.context.save()

            let state = try await fixture.repository.recalculateProgramStateTrainingWeek(
                programID: fixture.program.id,
                programStartDate: date(2026, 8, 3),
                at: date(2026, 8, 25, 20)
            )

            XCTAssertEqual(state.trainingWeekIndex, 4)
            XCTAssertEqual(state.deloadStatus, .none)
            XCTAssertNil(state.deloadReason)
            XCTAssertEqual(
                state.lastDeloadAction,
                status == .active ? .accepted : .techniqueReview
            )
            XCTAssertEqual(
                state.lastDeloadSkippedAt,
                status == .skipped ? date(2026, 8, 18) : nil
            )
        }
    }

    func testExplicitDeloadActionsPersistAtomicallyWithStableMappings() async throws {
        let at = date(2026, 8, 18, 20)
        let cases: [(DeloadAction, DeloadStatus)] = [
            (.accepted, .active),
            (.stay, .skipped),
            (.techniqueReview, .skipped),
            (.skipped, .skipped),
        ]

        for (action, expectedStatus) in cases {
            let fixture = try makeFixture()
            let state = try await fixture.repository.applyDeloadAction(
                programID: fixture.program.id,
                reason: .reactive,
                action: action,
                at: at
            )

            XCTAssertEqual(state.deloadStatus, expectedStatus)
            XCTAssertEqual(state.deloadReason, .reactive)
            XCTAssertEqual(state.deloadUpdatedAt, at)
            XCTAssertEqual(state.lastDeloadAction, action)
            XCTAssertEqual(
                state.lastDeloadSkippedAt,
                action == .accepted ? nil : at
            )

            let reopened = SwiftDataTrainingRepository(
                modelContext: ModelContext(fixture.container),
                calendar: calendar
            )
            let persisted = try await reopened.fetchProgramState(
                programID: fixture.program.id
            )
            XCTAssertEqual(persisted?.deloadStatus, expectedStatus)
            XCTAssertEqual(persisted?.lastDeloadAction, action)
        }
    }

    func testDuplicateProgramStateRejectsMutationWithoutPartialWrites() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(ProgramState(programId: fixture.program.id))
        try fixture.context.save()

        do {
            _ = try await fixture.repository.applyDeloadAction(
                programID: fixture.program.id,
                reason: .scheduled,
                action: .accepted,
                at: date(2026, 8, 18)
            )
            XCTFail("Expected duplicate ProgramState integrity failure.")
        } catch {
            XCTAssertEqual(
                error as? TrainingRepositoryIntegrityError,
                .duplicateProgramStates(programID: fixture.program.id, count: 2)
            )
        }

        let states = try fixture.context.fetch(FetchDescriptor<ProgramState>())
            .filter { $0.programId == fixture.program.id }
        XCTAssertTrue(states.allSatisfy { $0.deloadStatus == .none })
        XCTAssertTrue(states.allSatisfy { $0.lastDeloadAction == nil })
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let repository: SwiftDataTrainingRepository
        let program: Program
        let day: WorkoutDayTemplate
    }

    private func makeFixture(
        trainingWeekIndex: Int = 1,
        deloadStatus: DeloadStatus = .none,
        deloadReason: DeloadReason? = nil,
        deloadUpdatedAt: Date? = nil,
        lastDeloadSkippedAt: Date? = nil,
        lastDeloadAction: DeloadAction? = nil
    ) throws -> Fixture {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let program = Program(name: "Deload programı", isActive: true)
        let day = WorkoutDayTemplate(
            name: "Gün A",
            orderIndex: 1,
            program: program
        )
        let state = ProgramState(
            programId: program.id,
            trainingWeekIndex: trainingWeekIndex,
            deloadStatus: deloadStatus,
            deloadReason: deloadReason,
            deloadUpdatedAt: deloadUpdatedAt,
            lastDeloadSkippedAt: lastDeloadSkippedAt,
            lastDeloadAction: lastDeloadAction
        )
        context.insert(program)
        context.insert(day)
        context.insert(state)
        context.insert(
            UserProfile(
                displayName: "Deload test profili",
                programStartDate: date(2026, 8, 3)
            )
        )
        try context.save()
        return Fixture(
            container: container,
            context: context,
            repository: SwiftDataTrainingRepository(
                modelContext: context,
                calendar: calendar
            ),
            program: program,
            day: day
        )
    }

    @discardableResult
    private func insertSession(
        in fixture: Fixture,
        date: Date,
        status: WorkoutSessionStatus
    ) -> WorkoutSession {
        let session = WorkoutSession(
            date: date,
            status: status,
            workoutDayTemplateId: fixture.day.id
        )
        fixture.context.insert(session)
        return session
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 18
    ) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }
}
