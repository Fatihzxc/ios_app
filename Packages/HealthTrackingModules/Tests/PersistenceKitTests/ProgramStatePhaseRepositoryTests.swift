import CoreModels
import Foundation
@testable import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class ProgramStatePhaseRepositoryTests: XCTestCase {
    func testActivePhaseSelectionPersistsTheExactPhaseAndStartTimestamp() async throws {
        let fixture = try makeFixture()
        let changedAt = date(2026, 8, 20, 14)

        let updated = try await fixture.repository.setActiveProgramPhase(
            programID: fixture.program.id,
            phaseID: fixture.nextPhase.id,
            at: changedAt
        )

        XCTAssertEqual(updated.currentPhaseId, fixture.nextPhase.id)
        XCTAssertEqual(updated.phaseStartedAt, changedAt)
        XCTAssertEqual(updated.updatedAt, changedAt)

        let reopened = SwiftDataTrainingRepository(
            modelContext: ModelContext(fixture.container)
        )
        let fetched = try await reopened.fetchProgramState(programID: fixture.program.id)
        let persisted = try XCTUnwrap(fetched)
        XCTAssertEqual(persisted.currentPhaseId, fixture.nextPhase.id)
        XCTAssertEqual(persisted.phaseStartedAt, changedAt)
    }

    func testSelectionRejectsAPhaseOutsideTheProgramWithoutPartialMutation() async throws {
        let fixture = try makeFixture()
        let unrelatedProgram = Program(name: "Başka program")
        let unrelatedPhase = ProgramPhase(
            name: "Başka faz",
            orderIndex: 1,
            monthStart: 1,
            monthEnd: 2,
            program: unrelatedProgram
        )
        fixture.context.insert(unrelatedProgram)
        fixture.context.insert(unrelatedPhase)
        try fixture.context.save()
        let originalPhaseID = fixture.state.currentPhaseId
        let originalStartedAt = fixture.state.phaseStartedAt

        do {
            _ = try await fixture.repository.setActiveProgramPhase(
                programID: fixture.program.id,
                phaseID: unrelatedPhase.id,
                at: date(2026, 8, 20, 15)
            )
            XCTFail("A phase from another program must not become active.")
        } catch {
            XCTAssertEqual(
                error as? TrainingRepositoryMutationError,
                .phaseNotFound(
                    programID: fixture.program.id,
                    phaseID: unrelatedPhase.id
                )
            )
        }

        XCTAssertEqual(fixture.state.currentPhaseId, originalPhaseID)
        XCTAssertEqual(fixture.state.phaseStartedAt, originalStartedAt)
    }

    func testDuplicateProgramStatesRejectPhaseMutationWithoutPartialWrites() async throws {
        let fixture = try makeFixture()
        let duplicatePhaseID = fixture.state.currentPhaseId
        let duplicateStartedAt = fixture.state.phaseStartedAt
        fixture.context.insert(
            ProgramState(
                programId: fixture.program.id,
                currentPhaseId: duplicatePhaseID,
                phaseStartedAt: duplicateStartedAt
            )
        )
        try fixture.context.save()

        do {
            _ = try await fixture.repository.setActiveProgramPhase(
                programID: fixture.program.id,
                phaseID: fixture.nextPhase.id,
                at: date(2026, 8, 20, 16)
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
        XCTAssertEqual(states.count, 2)
        XCTAssertTrue(states.allSatisfy { $0.currentPhaseId == duplicatePhaseID })
        XCTAssertTrue(states.allSatisfy { $0.phaseStartedAt == duplicateStartedAt })
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let repository: SwiftDataTrainingRepository
        let program: Program
        let state: ProgramState
        let nextPhase: ProgramPhase
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let program = Program(name: "Faz programı", isActive: true)
        let currentPhase = ProgramPhase(
            name: "Temel",
            orderIndex: 1,
            monthStart: 1,
            monthEnd: 2,
            program: program
        )
        let nextPhase = ProgramPhase(
            name: "İnşa",
            orderIndex: 2,
            monthStart: 3,
            monthEnd: 6,
            milestone: "İnşa fazına hazır",
            entryCriteria: "Temel tamamlandı",
            program: program
        )
        let startedAt = date(2026, 6, 1, 9)
        let state = ProgramState(
            programId: program.id,
            currentPhaseId: currentPhase.id,
            phaseStartedAt: startedAt
        )
        context.insert(program)
        context.insert(currentPhase)
        context.insert(nextPhase)
        context.insert(state)
        try context.save()

        return Fixture(
            container: container,
            context: context,
            repository: SwiftDataTrainingRepository(modelContext: context),
            program: program,
            state: state,
            nextPhase: nextPhase
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }
}
