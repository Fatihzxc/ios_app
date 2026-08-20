import CoreModels
@testable import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class M1SeedCatalogFixtureTests: XCTestCase {
    func testSeedPersistsExactM1TrainingFixture() throws {
        let installedAt = Date(timeIntervalSinceReferenceDate: 789_000)
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)

        try SwiftDataSeedLoader(modelContext: writer).seedIfNeeded(installedAt: installedAt)

        let reader = ModelContext(container)
        let exercises = try fetch(ExerciseTemplate.self, from: reader)
            .map(ExerciseFixture.init)
            .sorted(by: ExerciseFixture.orderedBefore)
        XCTAssertEqual(exercises, Self.expectedExercises)
        XCTAssertEqual(exercises.count, 27)
        XCTAssertEqual(
            Dictionary(grouping: exercises, by: \.dayName).mapValues(\.count),
            ["Gün A": 8, "Gün B": 9, "Gün C": 10]
        )

        let curl = try XCTUnwrap(exercises.first { $0.name == "Curl" })
        let triceps = try XCTUnwrap(exercises.first { $0.name == "Triceps" })
        XCTAssertEqual(curl.supersetGroupID, Self.curlTricepsSupersetID)
        XCTAssertEqual(curl.supersetGroupID, triceps.supersetGroupID)
        XCTAssertEqual(curl.supersetOrder, 1)
        XCTAssertEqual(triceps.supersetOrder, 2)

        XCTAssertEqual(
            try fetch(WarmupItem.self, from: reader)
                .map(WarmupFixture.init)
                .sorted(by: WarmupFixture.orderedBefore),
            Self.expectedWarmups
        )
        XCTAssertEqual(
            try fetch(CooldownItem.self, from: reader)
                .map(CooldownFixture.init)
                .sorted(by: CooldownFixture.orderedBefore),
            Self.expectedCooldowns
        )

        let reminders = try fetch(HealthCheckReminder.self, from: reader)
            .map(ReminderFixture.init)
            .sorted { $0.name < $1.name }
        XCTAssertEqual(
            reminders,
            [
                ReminderFixture(name: "D vitamini", dueDate: installedAt, recurrence: .none, status: .pending),
                ReminderFixture(
                    name: "Ferritin",
                    dueDate: try XCTUnwrap(Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: installedAt)),
                    recurrence: .none,
                    status: .pending
                ),
                ReminderFixture(name: "Genel check-up", dueDate: installedAt, recurrence: .yearly, status: .pending)
            ]
        )

        let states = try fetch(ProgramState.self, from: reader)
        let state = try XCTUnwrap(states.first)
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(state.programId, SeedIdentifiers.program)
        XCTAssertEqual(state.currentPhaseId, SeedIdentifiers.phase1)
        XCTAssertEqual(state.phaseStartedAt, installedAt)
        XCTAssertEqual(state.trainingWeekIndex, 1)
        XCTAssertEqual(state.deloadStatus, .none)
        XCTAssertNil(state.deloadReason)
        XCTAssertNil(state.deloadUpdatedAt)
        XCTAssertNil(state.lastDeloadSkippedAt)
        XCTAssertNil(state.lastDeloadAction)
        XCTAssertEqual(try markerValues(in: reader), ["2"])
    }

    func testVersionOneInstallUpgradesOnceAndVersionTwoDoesNotResurrectDeletedExercise() throws {
        let installedAt = Date(timeIntervalSinceReferenceDate: 50_000)
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let program = Program(id: SeedIdentifiers.program, name: "User edited", isActive: true)
        let phase = ProgramPhase(id: SeedIdentifiers.phase1, name: "User phase", program: program)
        let dayA = WorkoutDayTemplate(id: SeedIdentifiers.dayA, name: "Gün A", orderIndex: 1, program: program)
        let dayB = WorkoutDayTemplate(id: SeedIdentifiers.dayB, name: "Gün B", orderIndex: 2, program: program)
        let dayC = WorkoutDayTemplate(id: SeedIdentifiers.dayC, name: "Gün C", orderIndex: 3, program: program)
        context.insert(UserProfile(id: SeedIdentifiers.profile, displayName: "User"))
        context.insert(program)
        context.insert(phase)
        [dayA, dayB, dayC].forEach(context.insert)
        context.insert(AppSetting(key: "seed.catalog.version", value: "1"))
        try context.save()
        let loader = SwiftDataSeedLoader(modelContext: context)

        try loader.seedIfNeeded(installedAt: installedAt)

        XCTAssertEqual(try markerValues(in: context), ["2"])
        XCTAssertEqual(try fetch(ExerciseTemplate.self, from: context).count, 27)
        XCTAssertEqual(try fetch(WarmupItem.self, from: context).count, Self.expectedWarmups.count)
        XCTAssertEqual(try fetch(CooldownItem.self, from: context).count, Self.expectedCooldowns.count)
        XCTAssertEqual(try fetch(HealthCheckReminder.self, from: context).count, 3)
        XCTAssertEqual(try fetch(ProgramState.self, from: context).count, 1)
        XCTAssertEqual(try XCTUnwrap(try fetch(Program.self, from: context).first).name, "User edited")

        let deletedID = try XCTUnwrap(
            try fetch(ExerciseTemplate.self, from: context).first { $0.name == "Goblet Squat" }
        ).id
        context.delete(try XCTUnwrap(try fetch(ExerciseTemplate.self, from: context).first { $0.id == deletedID }))
        try context.save()

        try loader.seedIfNeeded(installedAt: installedAt.addingTimeInterval(1_000))

        let reader = ModelContext(container)
        XCTAssertEqual(try fetch(ExerciseTemplate.self, from: reader).count, 26)
        XCTAssertFalse(try fetch(ExerciseTemplate.self, from: reader).contains { $0.id == deletedID })
        XCTAssertEqual(try markerValues(in: reader), ["2"])
    }

    func testVersionOneUpgradeDoesNotResurrectFoundationRecordsDeletedByUser() throws {
        let installedAt = Date(timeIntervalSinceReferenceDate: 55_000)
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let program = Program(id: SeedIdentifiers.program, name: "User program", isActive: true)
        let retainedPhases = [
            ProgramPhase(id: SeedIdentifiers.phase1, name: "Temel", orderIndex: 1, program: program),
            ProgramPhase(id: SeedIdentifiers.phase3, name: "İlerleme", orderIndex: 3, program: program),
            ProgramPhase(id: SeedIdentifiers.phase4, name: "Konsolidasyon", orderIndex: 4, program: program)
        ]
        let retainedDays = [
            WorkoutDayTemplate(id: SeedIdentifiers.dayA, name: "Gün A", orderIndex: 1, program: program),
            WorkoutDayTemplate(id: SeedIdentifiers.dayC, name: "Gün C", orderIndex: 3, program: program)
        ]
        context.insert(
            UserProfile(
                id: SeedIdentifiers.profile,
                createdAt: installedAt,
                programStartDate: installedAt
            )
        )
        context.insert(program)
        retainedPhases.forEach(context.insert)
        retainedDays.forEach(context.insert)
        context.insert(AppSetting(key: "seed.catalog.version", value: "1"))
        try context.save()

        try SwiftDataSeedLoader(modelContext: context).seedIfNeeded(installedAt: .now)

        let reader = ModelContext(container)
        XCTAssertEqual(
            Set(try fetch(ProgramPhase.self, from: reader).map(\.id)),
            [SeedIdentifiers.phase1, SeedIdentifiers.phase3, SeedIdentifiers.phase4]
        )
        XCTAssertEqual(
            Set(try fetch(WorkoutDayTemplate.self, from: reader).map(\.id)),
            [SeedIdentifiers.dayA, SeedIdentifiers.dayC]
        )
        XCTAssertEqual(try fetch(ExerciseTemplate.self, from: reader).count, 18)
        XCTAssertEqual(try fetch(WarmupItem.self, from: reader).count, 18)
        XCTAssertEqual(try fetch(CooldownItem.self, from: reader).count, 6)
        XCTAssertEqual(try fetch(HealthCheckReminder.self, from: reader).count, 3)
        XCTAssertEqual(try fetch(ProgramState.self, from: reader).count, 1)
        XCTAssertEqual(try markerValues(in: reader), ["2"])
    }

    func testFreshM1InstallsUseTheSameStableIDs() throws {
        let installedAt = Date(timeIntervalSinceReferenceDate: 60_000)
        let firstContainer = try ModelContainerFactory.make(for: .inMemory)
        let secondContainer = try ModelContainerFactory.make(for: .inMemory)
        try SwiftDataSeedLoader(modelContext: ModelContext(firstContainer))
            .seedIfNeeded(installedAt: installedAt)
        try SwiftDataSeedLoader(modelContext: ModelContext(secondContainer))
            .seedIfNeeded(installedAt: installedAt)

        let first = try m1IDs(in: ModelContext(firstContainer))
        let second = try m1IDs(in: ModelContext(secondContainer))

        XCTAssertEqual(first.exercises.count, 27)
        XCTAssertEqual(first.warmups.count, Self.expectedWarmups.count)
        XCTAssertEqual(first.cooldowns.count, Self.expectedCooldowns.count)
        XCTAssertEqual(first.reminders.count, 3)
        XCTAssertEqual(first.programStates.count, 1)
        XCTAssertEqual(first, second)
    }

    func testSaveFailureRollsBackTheEntireM1Graph() throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        var sawCompleteGraphAtSaveBoundary = false
        var rollbackWasCalled = false
        let loader = SwiftDataSeedLoader(
            modelContext: writer,
            save: {
                let exerciseCount = try self.fetch(ExerciseTemplate.self, from: writer).count
                let warmupCount = try self.fetch(WarmupItem.self, from: writer).count
                let cooldownCount = try self.fetch(CooldownItem.self, from: writer).count
                let reminderCount = try self.fetch(HealthCheckReminder.self, from: writer).count
                let stateCount = try self.fetch(ProgramState.self, from: writer).count
                let markers = try self.markerValues(in: writer)
                sawCompleteGraphAtSaveBoundary =
                    exerciseCount == 27
                    && warmupCount == Self.expectedWarmups.count
                    && cooldownCount == Self.expectedCooldowns.count
                    && reminderCount == 3
                    && stateCount == 1
                    && markers == ["2"]
                throw ForcedSaveError.expected
            },
            rollback: {
                rollbackWasCalled = true
                writer.rollback()
            }
        )

        XCTAssertThrowsError(try loader.seedIfNeeded(installedAt: .now)) { error in
            XCTAssertEqual(error as? SeedLoadingError, .saveFailed)
        }
        XCTAssertTrue(sawCompleteGraphAtSaveBoundary)
        XCTAssertTrue(rollbackWasCalled)

        let reader = ModelContext(container)
        XCTAssertEqual(try fetch(AppSetting.self, from: reader).count, 0)
        XCTAssertEqual(try fetch(UserProfile.self, from: reader).count, 0)
        XCTAssertEqual(try fetch(Program.self, from: reader).count, 0)
        XCTAssertEqual(try fetch(ProgramPhase.self, from: reader).count, 0)
        XCTAssertEqual(try fetch(WorkoutDayTemplate.self, from: reader).count, 0)
        XCTAssertEqual(try fetch(ExerciseTemplate.self, from: reader).count, 0)
        XCTAssertEqual(try fetch(WarmupItem.self, from: reader).count, 0)
        XCTAssertEqual(try fetch(CooldownItem.self, from: reader).count, 0)
        XCTAssertEqual(try fetch(HealthCheckReminder.self, from: reader).count, 0)
        XCTAssertEqual(try fetch(ProgramState.self, from: reader).count, 0)
    }

    private func fetch<Model: PersistentModel>(
        _ type: Model.Type,
        from context: ModelContext
    ) throws -> [Model] {
        try context.fetch(FetchDescriptor<Model>())
    }

    private func markerValues(in context: ModelContext) throws -> [String] {
        try fetch(AppSetting.self, from: context)
            .filter { $0.key == "seed.catalog.version" }
            .map(\.value)
            .sorted()
    }

    private func m1IDs(in context: ModelContext) throws -> M1IDs {
        M1IDs(
            exercises: Set(try fetch(ExerciseTemplate.self, from: context).map(\.id)),
            warmups: Set(try fetch(WarmupItem.self, from: context).map(\.id)),
            cooldowns: Set(try fetch(CooldownItem.self, from: context).map(\.id)),
            reminders: Set(try fetch(HealthCheckReminder.self, from: context).map(\.id)),
            programStates: Set(try fetch(ProgramState.self, from: context).map(\.id))
        )
    }
}

private extension M1SeedCatalogFixtureTests {
    static let curlTricepsSupersetID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000599"
    )!

    static let expectedExercises: [ExerciseFixture] = [
        .init(dayName: "Gün A", dayOrder: 1, name: "Goblet Squat", order: 1, sets: 3, low: 15, high: 25, rirLow: 0, rirHigh: 1, category: .compound, allowsFailure: true, rule: .doubleProgression, measurement: .weightReps, startingWeight: nil, safety: "3sn eksantrik; topuk kalkarsa plaka"),
        .init(dayName: "Gün A", dayOrder: 1, name: "Chin-up", order: 2, sets: 3, low: 6, high: 12, rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false, rule: .bodyweightProgression, measurement: .reps, startingWeight: nil, safety: "faile gitme; boyun nötr"),
        .init(dayName: "Gün A", dayOrder: 1, name: "DB Floor Press", order: 3, sets: 4, low: 8, high: 12, rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false, rule: .doubleProgression, measurement: .weightReps, startingWeight: nil, safety: "dirsek 45°, yerde 1sn"),
        .init(dayName: "Gün A", dayOrder: 1, name: "DB Romanian Deadlift", order: 4, sets: 3, low: 10, high: 12, rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false, rule: .doubleProgression, measurement: .weightReps, startingWeight: nil, safety: "kalça menteşesi; bel değil hamstring"),
        .init(dayName: "Gün A", dayOrder: 1, name: "Prone Y-T-W", order: 5, sets: 2, low: 8, high: 8, rirLow: 0, rirHigh: 0, category: .accessory, allowsFailure: false, rule: .timeQuality, measurement: .reps, startingWeight: nil, safety: "ağırlıksız; tepede 2sn"),
        .init(dayName: "Gün A", dayOrder: 1, name: "Face Pull (bant)", order: 6, sets: 3, low: 15, high: 20, rirLow: 0, rirHigh: 1, category: .accessory, allowsFailure: false, rule: .timeQuality, measurement: .reps, startingWeight: nil, safety: "hafif; omuz yukarı kalkmasın"),
        .init(dayName: "Gün A", dayOrder: 1, name: "Tek Bacak Calf Raise", order: 7, sets: 2, low: 12, high: 20, rirLow: 0, rirHigh: 1, category: .accessory, allowsFailure: false, rule: .doubleProgression, measurement: .reps, startingWeight: nil, safety: "1.set düz diz, 2.set bükük"),
        .init(dayName: "Gün A", dayOrder: 1, name: "Plank / Pallof", order: 8, sets: 3, low: 30, high: 60, rirLow: 0, rirHigh: 0, category: .core, allowsFailure: false, rule: .timeQuality, measurement: .duration, startingWeight: nil, safety: "haftada 1 Pallof"),

        .init(dayName: "Gün B", dayOrder: 2, name: "DB RDL (çift)", order: 1, sets: 3, low: 10, high: 12, rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false, rule: .doubleProgression, measurement: .weightReps, startingWeight: nil, safety: "A'dan ağır; DB bacaktan uzaklaşmasın"),
        .init(dayName: "Gün B", dayOrder: 2, name: "Tek Kol DB Row", order: 2, sets: 4, low: 10, high: 12, rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false, rule: .doubleProgression, measurement: .weightReps, startingWeight: nil, safety: "gövde döndürme"),
        .init(dayName: "Gün B", dayOrder: 2, name: "Push-up", order: 3, sets: 2, low: 10, high: 20, rirLow: 0, rirHigh: 1, category: .compound, allowsFailure: true, rule: .bodyweightProgression, measurement: .reps, startingWeight: nil, safety: "kolaysa ayak yüksekte"),
        .init(dayName: "Gün B", dayOrder: 2, name: "DB Overhead Press", order: 4, sets: 3, low: 8, high: 12, rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false, rule: .gradedEntryOHP, measurement: .weightReps, startingWeight: 10, safety: "Sağ işaret parmağı uyuşursa kes → Half-Kneeling DB Press"),
        .init(dayName: "Gün B", dayOrder: 2, name: "Bulgarian Split Squat", order: 5, sets: 3, low: 8, high: 12, rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false, rule: .doubleProgression, measurement: .weightReps, startingWeight: nil, safety: "gövde dik/hafif öne"),
        .init(dayName: "Gün B", dayOrder: 2, name: "Glute Bridge / Hip Thrust", order: 6, sets: 3, low: 12, high: 20, rirLow: 0, rirHigh: 1, category: .accessory, allowsFailure: true, rule: .doubleProgression, measurement: .reps, startingWeight: nil, safety: "topuktan it; beli yaylandırma"),
        .init(dayName: "Gün B", dayOrder: 2, name: "Wall Slide", order: 7, sets: 2, low: 10, high: 12, rirLow: 0, rirHigh: 0, category: .accessory, allowsFailure: false, rule: .timeQuality, measurement: .reps, startingWeight: nil, safety: "temas kaybolmadan"),
        .init(dayName: "Gün B", dayOrder: 2, name: "Dead Bug", order: 8, sets: 2, low: 8, high: 10, rirLow: 0, rirHigh: 0, category: .core, allowsFailure: false, rule: .timeQuality, measurement: .reps, startingWeight: nil, safety: "bel yerden kalkmasın"),
        .init(dayName: "Gün B", dayOrder: 2, name: "Copenhagen Plank", order: 9, sets: 2, low: 15, high: 30, rirLow: 0, rirHigh: 0, category: .core, allowsFailure: false, rule: .timeQuality, measurement: .duration, startingWeight: nil, safety: "aşama: diz → ayak sehpada"),

        .init(dayName: "Gün C", dayOrder: 3, name: "Reverse Lunge (DB)", order: 1, sets: 3, low: 8, high: 12, rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false, rule: .doubleProgression, measurement: .weightReps, startingWeight: nil, safety: "ağırlık ön ayakta"),
        .init(dayName: "Gün C", dayOrder: 3, name: "Nordic Hamstring Curl", order: 2, sets: 2, low: 3, high: 5, rirLow: 0, rirHigh: 0, category: .compound, allowsFailure: false, rule: .timeQuality, measurement: .reps, startingWeight: nil, safety: "İlk 2 hafta 2×3'ü aşma (DOMS)"),
        .init(dayName: "Gün C", dayOrder: 3, name: "Pull-up / bantlı", order: 3, sets: 2, low: nil, high: nil, rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false, rule: .bodyweightProgression, measurement: .reps, startingWeight: nil, safety: "skapular set; zorsa bant"),
        .init(dayName: "Gün C", dayOrder: 3, name: "Bantlı / Tek Kol Row", order: 4, sets: 3, low: 12, high: 15, rirLow: 0, rirHigh: 1, category: .accessory, allowsFailure: false, rule: .doubleProgression, measurement: .reps, startingWeight: nil, safety: "bitişte en zor"),
        .init(dayName: "Gün C", dayOrder: 3, name: "Half-Kneeling DB Press", order: 5, sets: 3, low: 8, high: 10, rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false, rule: .doubleProgression, measurement: .weightReps, startingWeight: nil, safety: "OHP'de semptomda dönüş yeri"),
        .init(dayName: "Gün C", dayOrder: 3, name: "DB Lateral Raise", order: 6, sets: 3, low: 12, high: 20, rirLow: 0, rirHigh: 1, category: .accessory, allowsFailure: false, rule: .doubleProgression, measurement: .weightReps, startingWeight: nil, safety: "omuz hizasında dur"),
        .init(dayName: "Gün C", dayOrder: 3, name: "Farmer's Carry", order: 7, sets: 3, low: 30, high: 40, rirLow: 0, rirHigh: 0, category: .accessory, allowsFailure: false, rule: .timeQuality, measurement: .steps, startingWeight: nil, safety: "en ağır 2 DB"),
        .init(dayName: "Gün C", dayOrder: 3, name: "Curl", order: 8, sets: 2, low: 10, high: 15, rirLow: 0, rirHigh: 1, category: .accessory, allowsFailure: false, rule: .doubleProgression, measurement: .weightReps, startingWeight: 10, safety: "curl 10 kg başlangıç", supersetGroupID: curlTricepsSupersetID, supersetOrder: 1),
        .init(dayName: "Gün C", dayOrder: 3, name: "Triceps", order: 9, sets: 2, low: 10, high: 15, rirLow: 0, rirHigh: 1, category: .accessory, allowsFailure: false, rule: .doubleProgression, measurement: .reps, startingWeight: nil, safety: "başlangıç ağırlığını ilk kayıtta seç", supersetGroupID: curlTricepsSupersetID, supersetOrder: 2),
        .init(dayName: "Gün C", dayOrder: 3, name: "Side Plank / Pallof", order: 10, sets: 2, low: 20, high: 40, rirLow: 0, rirHigh: 0, category: .core, allowsFailure: false, rule: .timeQuality, measurement: .duration, startingWeight: nil, safety: "kalça düşerse bitti")
    ]

    static let expectedWarmups: [WarmupFixture] = [
        .init(dayName: "Gün A", dayOrder: 1, phase: .raise, movement: "İp / koşu", dose: "60–90 sn", order: 1),
        .init(dayName: "Gün A", dayOrder: 1, phase: .raise, movement: "Kol çevirme", dose: "10", order: 2),
        .init(dayName: "Gün A", dayOrder: 1, phase: .raise, movement: "Çömeliş-kalkış", dose: "8", order: 3),
        .init(dayName: "Gün A", dayOrder: 1, phase: .raise, movement: "Bacak sallama ön-arka", dose: "10/bacak", order: 4),
        .init(dayName: "Gün A", dayOrder: 1, phase: .activate, movement: "Knee-to-wall", dose: "10/taraf", order: 5),
        .init(dayName: "Gün A", dayOrder: 1, phase: .activate, movement: "90/90 kalça", dose: "8/yön", order: 6),
        .init(dayName: "Gün A", dayOrder: 1, phase: .activate, movement: "Band pull-apart", dose: "15", order: 7),
        .init(dayName: "Gün A", dayOrder: 1, phase: .potentiate, movement: "BW squat", dose: "8", order: 8),
        .init(dayName: "Gün A", dayOrder: 1, phase: .potentiate, movement: "DB squat rampa", dose: "~10 kg × 5", order: 9),

        .init(dayName: "Gün B", dayOrder: 2, phase: .raise, movement: "İp / koşu", dose: "60–90 sn", order: 1),
        .init(dayName: "Gün B", dayOrder: 2, phase: .raise, movement: "Kol çevirme", dose: "10", order: 2),
        .init(dayName: "Gün B", dayOrder: 2, phase: .raise, movement: "Çömeliş-kalkış", dose: "8", order: 3),
        .init(dayName: "Gün B", dayOrder: 2, phase: .raise, movement: "Bacak sallama ön-arka", dose: "10/bacak", order: 4),
        .init(dayName: "Gün B", dayOrder: 2, phase: .activate, movement: "Yarım diz kalça fleksörü", dose: "8/taraf", order: 5),
        .init(dayName: "Gün B", dayOrder: 2, phase: .activate, movement: "Bacak sallama yan + ön", dose: "10", order: 6),
        .init(dayName: "Gün B", dayOrder: 2, phase: .activate, movement: "Open book", dose: "8/taraf", order: 7),
        .init(dayName: "Gün B", dayOrder: 2, phase: .activate, movement: "Omuz dış rotasyon", dose: "15/kol", order: 8),
        .init(dayName: "Gün B", dayOrder: 2, phase: .activate, movement: "Wall slide", dose: "10", order: 9),
        .init(dayName: "Gün B", dayOrder: 2, phase: .potentiate, movement: "Boş hinge", dose: "8", order: 10),
        .init(dayName: "Gün B", dayOrder: 2, phase: .potentiate, movement: "Hafif hinge", dose: "5", order: 11),
        .init(dayName: "Gün B", dayOrder: 2, phase: .potentiate, movement: "OHP boş press", dose: "8", order: 12),

        .init(dayName: "Gün C", dayOrder: 3, phase: .raise, movement: "İp / koşu", dose: "60–90 sn", order: 1),
        .init(dayName: "Gün C", dayOrder: 3, phase: .raise, movement: "Kol çevirme", dose: "10", order: 2),
        .init(dayName: "Gün C", dayOrder: 3, phase: .raise, movement: "Çömeliş-kalkış", dose: "8", order: 3),
        .init(dayName: "Gün C", dayOrder: 3, phase: .raise, movement: "Bacak sallama ön-arka", dose: "10/bacak", order: 4),
        .init(dayName: "Gün C", dayOrder: 3, phase: .activate, movement: "Yarım diz kalça fleksörü", dose: "8/taraf", order: 5),
        .init(dayName: "Gün C", dayOrder: 3, phase: .activate, movement: "Wall slide", dose: "10", order: 6),
        .init(dayName: "Gün C", dayOrder: 3, phase: .activate, movement: "Omuz dış rotasyon", dose: "15/kol", order: 7),
        .init(dayName: "Gün C", dayOrder: 3, phase: .potentiate, movement: "BW lunge", dose: "5/bacak", order: 8),
        .init(dayName: "Gün C", dayOrder: 3, phase: .potentiate, movement: "Hafif lunge", dose: "3/bacak", order: 9)
    ]

    static let expectedCooldowns: [CooldownFixture] = [
        .init(dayName: "Gün A", dayOrder: 1, movement: "Pektoral germe", dose: "30 sn × 2/taraf", note: nil, order: 1),
        .init(dayName: "Gün A", dayOrder: 1, movement: "C6 nöral gliding", dose: "1 × 10", note: "Uyuşma dönerse dur", order: 2),
        .init(dayName: "Gün A", dayOrder: 1, movement: "Chin tuck", dose: "1 × 10", note: nil, order: 3),
        .init(dayName: "Gün B", dayOrder: 2, movement: "Pektoral germe", dose: "30 sn × 2/taraf", note: nil, order: 1),
        .init(dayName: "Gün B", dayOrder: 2, movement: "C6 nöral gliding", dose: "1 × 10", note: "Uyuşma dönerse dur", order: 2),
        .init(dayName: "Gün B", dayOrder: 2, movement: "Chin tuck", dose: "1 × 10", note: nil, order: 3),
        .init(dayName: "Gün C", dayOrder: 3, movement: "Pektoral germe", dose: "30 sn × 2/taraf", note: nil, order: 1),
        .init(dayName: "Gün C", dayOrder: 3, movement: "C6 nöral gliding", dose: "1 × 10", note: "Uyuşma dönerse dur", order: 2),
        .init(dayName: "Gün C", dayOrder: 3, movement: "Chin tuck", dose: "1 × 10", note: nil, order: 3)
    ]
}

private struct ExerciseFixture: Equatable {
    let dayName: String
    let dayOrder: Int
    let name: String
    let order: Int
    let sets: Int
    let low: Int?
    let high: Int?
    let rirLow: Int
    let rirHigh: Int
    let category: ExerciseCategory
    let allowsFailure: Bool
    let rule: ProgressionRule
    let measurement: ExerciseMeasurementKind
    let startingWeight: Double?
    let safety: String?
    let supersetGroupID: UUID?
    let supersetOrder: Int?

    init(
        dayName: String,
        dayOrder: Int,
        name: String,
        order: Int,
        sets: Int,
        low: Int?,
        high: Int?,
        rirLow: Int,
        rirHigh: Int,
        category: ExerciseCategory,
        allowsFailure: Bool,
        rule: ProgressionRule,
        measurement: ExerciseMeasurementKind,
        startingWeight: Double?,
        safety: String?,
        supersetGroupID: UUID? = nil,
        supersetOrder: Int? = nil
    ) {
        self.dayName = dayName
        self.dayOrder = dayOrder
        self.name = name
        self.order = order
        self.sets = sets
        self.low = low
        self.high = high
        self.rirLow = rirLow
        self.rirHigh = rirHigh
        self.category = category
        self.allowsFailure = allowsFailure
        self.rule = rule
        self.measurement = measurement
        self.startingWeight = startingWeight
        self.safety = safety
        self.supersetGroupID = supersetGroupID
        self.supersetOrder = supersetOrder
    }

    init(_ model: ExerciseTemplate) {
        self.init(
            dayName: model.workoutDayTemplate?.name ?? "",
            dayOrder: model.workoutDayTemplate?.orderIndex ?? 0,
            name: model.name,
            order: model.orderIndex,
            sets: model.targetSets,
            low: model.repLow,
            high: model.repHigh,
            rirLow: model.rirLow,
            rirHigh: model.rirHigh,
            category: model.category,
            allowsFailure: model.allowFailure,
            rule: model.progressionRule,
            measurement: model.measurementKind,
            startingWeight: model.startingWeightKg,
            safety: model.safetyNote,
            supersetGroupID: model.supersetGroupId,
            supersetOrder: model.supersetOrder
        )
    }

    static func orderedBefore(_ lhs: Self, _ rhs: Self) -> Bool {
        (lhs.dayOrder, lhs.order, lhs.name) < (rhs.dayOrder, rhs.order, rhs.name)
    }
}

private struct WarmupFixture: Equatable {
    let dayName: String
    let dayOrder: Int
    let phase: WarmupPhase
    let movement: String
    let dose: String
    let order: Int

    init(dayName: String, dayOrder: Int, phase: WarmupPhase, movement: String, dose: String, order: Int) {
        self.dayName = dayName
        self.dayOrder = dayOrder
        self.phase = phase
        self.movement = movement
        self.dose = dose
        self.order = order
    }

    init(_ model: WarmupItem) {
        self.init(
            dayName: model.workoutDayTemplate?.name ?? "",
            dayOrder: model.workoutDayTemplate?.orderIndex ?? 0,
            phase: model.phase,
            movement: model.movement,
            dose: model.dose,
            order: model.orderIndex
        )
    }

    static func orderedBefore(_ lhs: Self, _ rhs: Self) -> Bool {
        (lhs.dayOrder, lhs.order, lhs.movement) < (rhs.dayOrder, rhs.order, rhs.movement)
    }
}

private struct CooldownFixture: Equatable {
    let dayName: String
    let dayOrder: Int
    let movement: String
    let dose: String
    let note: String?
    let order: Int

    init(dayName: String, dayOrder: Int, movement: String, dose: String, note: String?, order: Int) {
        self.dayName = dayName
        self.dayOrder = dayOrder
        self.movement = movement
        self.dose = dose
        self.note = note
        self.order = order
    }

    init(_ model: CooldownItem) {
        self.init(
            dayName: model.workoutDayTemplate?.name ?? "",
            dayOrder: model.workoutDayTemplate?.orderIndex ?? 0,
            movement: model.movement,
            dose: model.dose,
            note: model.note,
            order: model.orderIndex
        )
    }

    static func orderedBefore(_ lhs: Self, _ rhs: Self) -> Bool {
        (lhs.dayOrder, lhs.order, lhs.movement) < (rhs.dayOrder, rhs.order, rhs.movement)
    }
}

private struct ReminderFixture: Equatable {
    let name: String
    let dueDate: Date
    let recurrence: HealthCheckRecurrence
    let status: HealthCheckStatus

    init(name: String, dueDate: Date, recurrence: HealthCheckRecurrence, status: HealthCheckStatus) {
        self.name = name
        self.dueDate = dueDate
        self.recurrence = recurrence
        self.status = status
    }

    init(_ model: HealthCheckReminder) {
        self.init(
            name: model.name,
            dueDate: model.dueDate,
            recurrence: model.recurrence,
            status: model.status
        )
    }
}

private enum ForcedSaveError: Error {
    case expected
}

private struct M1IDs: Equatable {
    let exercises: Set<UUID>
    let warmups: Set<UUID>
    let cooldowns: Set<UUID>
    let reminders: Set<UUID>
    let programStates: Set<UUID>
}
