import CoreModels
@testable import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class SwiftDataSeedLoaderTests: XCTestCase {
    func testFirstRunPersistsExactFoundationGraphWithDeterministicIDs() throws {
        let container = try makeContainer()
        let writer = ModelContext(container)
        let installedAt = Date(timeIntervalSinceReferenceDate: 1_000)

        try SwiftDataSeedLoader(modelContext: writer).seedIfNeeded(installedAt: installedAt)

        let reader = ModelContext(container)
        let profiles = try fetch(UserProfile.self, from: reader)
        let programs = try fetch(Program.self, from: reader)
        let phases = try fetch(ProgramPhase.self, from: reader)
        let days = try fetch(WorkoutDayTemplate.self, from: reader)
        XCTAssertEqual(Set(profiles.map(\.id)), [SeedIdentifiers.profile])
        XCTAssertEqual(Set(programs.map(\.id)), [SeedIdentifiers.program])
        XCTAssertEqual(Set(phases.map(\.id)), [SeedIdentifiers.phase1, SeedIdentifiers.phase2, SeedIdentifiers.phase3, SeedIdentifiers.phase4])
        XCTAssertEqual(Set(days.map(\.id)), [SeedIdentifiers.dayA, SeedIdentifiers.dayB, SeedIdentifiers.dayC])
        XCTAssertEqual(try markerValues(in: reader), ["2"])

        let profile = try XCTUnwrap(profiles.first)
        XCTAssertEqual(profile.displayName, "")
        XCTAssertEqual(profile.heightCm, 185)
        XCTAssertEqual(profile.startWeightKg, 98)
        XCTAssertEqual(profile.targetWeightKg, 90)
        XCTAssertEqual(profile.proteinTargetG, 120)
        XCTAssertEqual(profile.unitsSystem, .metric)
        XCTAssertNil(profile.calorieTarget)
        XCTAssertNil(profile.carbTargetG)
        XCTAssertNil(profile.fatTargetG)
        XCTAssertEqual(profile.programStartDate, installedAt)
        XCTAssertEqual(profile.weeklyWorkoutTarget, 3)
        XCTAssertTrue(try XCTUnwrap(programs.first).isActive)
        XCTAssertTrue(phases.allSatisfy { $0.program?.id == SeedIdentifiers.program })
        XCTAssertEqual(days.sorted { $0.orderIndex < $1.orderIndex }.map(\.orderIndex), [1, 2, 3])
        XCTAssertTrue(days.allSatisfy { $0.program?.id == SeedIdentifiers.program })
    }

    func testRepeatedRunsPersistStableCountsAndIDsFromFreshContexts() throws {
        let container = try makeContainer()
        let writer = ModelContext(container)
        let loader = SwiftDataSeedLoader(modelContext: writer)

        try loader.seedIfNeeded(installedAt: Date(timeIntervalSinceReferenceDate: 1))
        let firstIDs = try allSeedIDs(in: ModelContext(container))
        try loader.seedIfNeeded(installedAt: Date(timeIntervalSinceReferenceDate: 2))
        let secondIDs = try allSeedIDs(in: ModelContext(container))
        try loader.seedIfNeeded(installedAt: Date(timeIntervalSinceReferenceDate: 3))
        let thirdReader = ModelContext(container)

        XCTAssertEqual(firstIDs, secondIDs)
        XCTAssertEqual(secondIDs, try allSeedIDs(in: thirdReader))
        XCTAssertEqual(try fetch(UserProfile.self, from: thirdReader).count, 1)
        XCTAssertEqual(try fetch(Program.self, from: thirdReader).count, 1)
        XCTAssertEqual(try fetch(ProgramPhase.self, from: thirdReader).count, 4)
        XCTAssertEqual(try fetch(WorkoutDayTemplate.self, from: thirdReader).count, 3)
    }

    func testValidMarkerPersistsUserEditsWithoutResettingThem() throws {
        let container = try makeContainer()
        let writer = ModelContext(container)
        let loader = SwiftDataSeedLoader(modelContext: writer)
        try loader.seedIfNeeded(installedAt: .now)
        let profile = try XCTUnwrap(try fetch(UserProfile.self, from: writer).first)
        profile.heightCm = 177
        profile.displayName = "Deniz"
        try writer.save()

        try loader.seedIfNeeded(installedAt: Date(timeIntervalSinceReferenceDate: 9_999))

        let reader = ModelContext(container)
        let persistedProfile = try XCTUnwrap(try fetch(UserProfile.self, from: reader).first)
        XCTAssertEqual(persistedProfile.heightCm, 177)
        XCTAssertEqual(persistedProfile.displayName, "Deniz")
        XCTAssertEqual(try fetch(UserProfile.self, from: reader).count, 1)
    }

    func testValidMarkerPersistsUserDeletionWithoutResurrectingSeedRecord() throws {
        let container = try makeContainer()
        let writer = ModelContext(container)
        let loader = SwiftDataSeedLoader(modelContext: writer)
        try loader.seedIfNeeded(installedAt: .now)
        writer.delete(try XCTUnwrap(try fetch(WorkoutDayTemplate.self, from: writer).first { $0.id == SeedIdentifiers.dayB }))
        try writer.save()

        try loader.seedIfNeeded(installedAt: .now)

        let reader = ModelContext(container)
        XCTAssertEqual(try fetch(WorkoutDayTemplate.self, from: reader).count, 2)
        XCTAssertFalse(try fetch(WorkoutDayTemplate.self, from: reader).contains { $0.id == SeedIdentifiers.dayB })
    }

    func testPreMarkerPartialGraphRepairsWrongProgramLinksWithoutChangingExistingScalars() throws {
        let container = try makeContainer()
        let writer = ModelContext(container)
        let foreignProgram = Program(name: "Foreign", descriptionText: "Foreign description", isActive: true)
        let editedProfile = UserProfile(id: SeedIdentifiers.profile, displayName: "Ada", heightCm: 171, startWeightKg: 81, targetWeightKg: 73, birthYear: 1990, unitsSystem: .imperial, proteinTargetG: 99, calorieTarget: 2_100, carbTargetG: 200, fatTargetG: 70, programStartDate: Date(timeIntervalSinceReferenceDate: 44), weeklyWorkoutTarget: 4)
        let editedProgram = Program(id: SeedIdentifiers.program, name: "Kullanıcının programı", descriptionText: "Kullanıcı açıklaması", isActive: false)
        let editedPhase = ProgramPhase(id: SeedIdentifiers.phase1, name: "Kullanıcının temel fazı", orderIndex: 77, monthStart: 77, monthEnd: 88, trainingFocus: "Kullanıcı odağı", nutritionFocus: "Kullanıcı beslenmesi", milestone: "Kullanıcı hedefi", entryCriteria: "Kullanıcı kriteri", program: foreignProgram)
        let editedDay = WorkoutDayTemplate(id: SeedIdentifiers.dayA, name: "Kullanıcının günü", orderIndex: 77, focus: "Kullanıcı odağı", program: foreignProgram)
        [foreignProgram, editedProgram].forEach(writer.insert)
        writer.insert(editedProfile)
        writer.insert(editedPhase)
        writer.insert(editedDay)
        try writer.save()

        try SwiftDataSeedLoader(modelContext: writer).seedIfNeeded(installedAt: .now)

        let reader = ModelContext(container)
        let profile = try XCTUnwrap(try fetch(UserProfile.self, from: reader).first { $0.id == SeedIdentifiers.profile })
        let program = try XCTUnwrap(try fetch(Program.self, from: reader).first { $0.id == SeedIdentifiers.program })
        let phase = try XCTUnwrap(try fetch(ProgramPhase.self, from: reader).first { $0.id == SeedIdentifiers.phase1 })
        let day = try XCTUnwrap(try fetch(WorkoutDayTemplate.self, from: reader).first { $0.id == SeedIdentifiers.dayA })
        XCTAssertEqual(profile.displayName, "Ada")
        XCTAssertEqual(profile.heightCm, 171)
        XCTAssertEqual(profile.startWeightKg, 81)
        XCTAssertEqual(profile.targetWeightKg, 73)
        XCTAssertEqual(profile.birthYear, 1990)
        XCTAssertEqual(profile.unitsSystem, .imperial)
        XCTAssertEqual(profile.proteinTargetG, 99)
        XCTAssertEqual(profile.calorieTarget, 2_100)
        XCTAssertEqual(profile.carbTargetG, 200)
        XCTAssertEqual(profile.fatTargetG, 70)
        XCTAssertEqual(profile.programStartDate, Date(timeIntervalSinceReferenceDate: 44))
        XCTAssertEqual(profile.weeklyWorkoutTarget, 4)
        XCTAssertEqual(program.name, "Kullanıcının programı")
        XCTAssertEqual(program.descriptionText, "Kullanıcı açıklaması")
        XCTAssertFalse(program.isActive)
        XCTAssertEqual(phase.name, "Kullanıcının temel fazı")
        XCTAssertEqual(phase.orderIndex, 77)
        XCTAssertEqual(phase.monthStart, 77)
        XCTAssertEqual(phase.monthEnd, 88)
        XCTAssertEqual(phase.trainingFocus, "Kullanıcı odağı")
        XCTAssertEqual(phase.nutritionFocus, "Kullanıcı beslenmesi")
        XCTAssertEqual(phase.milestone, "Kullanıcı hedefi")
        XCTAssertEqual(phase.entryCriteria, "Kullanıcı kriteri")
        XCTAssertEqual(day.name, "Kullanıcının günü")
        XCTAssertEqual(day.orderIndex, 77)
        XCTAssertEqual(day.focus, "Kullanıcı odağı")
        XCTAssertEqual(phase.program?.id, SeedIdentifiers.program)
        XCTAssertEqual(day.program?.id, SeedIdentifiers.program)
        XCTAssertEqual(try fetch(ProgramPhase.self, from: reader).count, 4)
        XCTAssertEqual(try fetch(WorkoutDayTemplate.self, from: reader).count, 3)
        XCTAssertEqual(try markerValues(in: reader), ["2"])
    }

    func testSingleStaleMarkerIsUpgradedInPlaceWithoutCreatingADuplicate() throws {
        let container = try makeContainer()
        let writer = ModelContext(container)
        writer.insert(AppSetting(key: "seed.catalog.version", value: "0"))
        try writer.save()

        try SwiftDataSeedLoader(modelContext: writer).seedIfNeeded(installedAt: .now)

        let reader = ModelContext(container)
        XCTAssertEqual(try markerValues(in: reader), ["2"])
        XCTAssertEqual(try fetch(AppSetting.self, from: reader).filter { $0.key == "seed.catalog.version" }.count, 1)
    }

    func testDuplicateMarkerRowsSurfaceTypedIntegrityError() throws {
        for markerValues in [["2", "2"], ["1", "1"], ["0", "0"], ["2", "1"]] {
            let container = try makeContainer()
            let writer = ModelContext(container)
            markerValues.forEach { writer.insert(AppSetting(key: "seed.catalog.version", value: $0)) }
            try writer.save()

            XCTAssertThrowsError(try SwiftDataSeedLoader(modelContext: writer).seedIfNeeded(installedAt: .now)) { error in
                XCTAssertEqual(error as? SeedLoadingError, .duplicateMarkers(count: 2))
            }
            let reader = ModelContext(container)
            XCTAssertEqual(try fetch(AppSetting.self, from: reader).filter { $0.key == "seed.catalog.version" }.count, 2)
            XCTAssertEqual(try fetch(UserProfile.self, from: reader).count, 0)
        }
    }

    func testSaveFailureRollsBackWithoutPersistingAnySeedDataInAFreshContext() throws {
        let container = try makeContainer()
        let writer = ModelContext(container)
        var observedPreparedGraphAtSaveBoundary = false
        var rollbackWasCalled = false
        let loader = SwiftDataSeedLoader(
            modelContext: writer,
            save: {
                let programs = try self.fetch(Program.self, from: writer)
                let phases = try self.fetch(ProgramPhase.self, from: writer)
                let days = try self.fetch(WorkoutDayTemplate.self, from: writer)
                let markers = try self.markerValues(in: writer)
                observedPreparedGraphAtSaveBoundary = programs.count == 1
                    && phases.count == 4
                    && days.count == 3
                    && markers == ["2"]
                throw TestSaveError.forced
            },
            rollback: {
                rollbackWasCalled = true
                writer.rollback()
            }
        )

        XCTAssertThrowsError(try loader.seedIfNeeded(installedAt: .now)) { error in
            XCTAssertEqual(error as? SeedLoadingError, .saveFailed)
        }
        XCTAssertTrue(observedPreparedGraphAtSaveBoundary)
        XCTAssertTrue(rollbackWasCalled)
        let reader = ModelContext(container)
        XCTAssertEqual(try fetch(AppSetting.self, from: reader).count, 0)
        XCTAssertEqual(try fetch(UserProfile.self, from: reader).count, 0)
        XCTAssertEqual(try fetch(Program.self, from: reader).count, 0)
        XCTAssertEqual(try fetch(ProgramPhase.self, from: reader).count, 0)
        XCTAssertEqual(try fetch(WorkoutDayTemplate.self, from: reader).count, 0)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.make(for: .inMemory)
    }

    private func fetch<Model: PersistentModel>(_ type: Model.Type, from context: ModelContext) throws -> [Model] {
        try context.fetch(FetchDescriptor<Model>())
    }

    private func markerValues(in context: ModelContext) throws -> [String] {
        try fetch(AppSetting.self, from: context)
            .filter { $0.key == "seed.catalog.version" }
            .map(\.value)
            .sorted()
    }

    private func allSeedIDs(in context: ModelContext) throws -> Set<UUID> {
        Set(try fetch(UserProfile.self, from: context).map(\.id))
            .union(try fetch(Program.self, from: context).map(\.id))
            .union(try fetch(ProgramPhase.self, from: context).map(\.id))
            .union(try fetch(WorkoutDayTemplate.self, from: context).map(\.id))
            .union(try fetch(AppSetting.self, from: context).map(\.id))
    }
}

private enum TestSaveError: Error {
    case forced
}
