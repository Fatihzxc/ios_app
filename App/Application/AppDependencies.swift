import CoreModels
import Foundation
import PersistenceKit
import SettingsKit
import SwiftData
import TrainingKit

@MainActor
protocol AppDependencyLoading: AnyObject {
    func load() throws
}

@MainActor
final class AppDependencies: AppDependencyLoading {
    private let modelContainer: ModelContainer
    private let seedLoader: SwiftDataSeedLoader
    private let installUITestFixture: @MainActor () throws -> Void
    let trainingRepository: any TrainingRepository
    let foundationViewModel: FoundationProgramViewModel
    let makeSessionViewModel: @MainActor () -> SessionViewModel
    let shouldLoadFoundation: Bool
    let persistencePresentation: FoundationPersistencePresentation

    init(environment: AppEnvironment) throws {
        let persistenceMode: PersistenceMode
        switch environment {
        case .uiTesting:
            persistenceMode = .inMemory
            persistencePresentation = .uiTestingInMemory
        case let .local(storeURL):
            persistenceMode = .local(storeURL: storeURL)
            persistencePresentation = .localStore
        case let .cloud(containerIdentifier, storeURL):
            persistenceMode = .cloud(
                storeURL: storeURL,
                privateDatabaseIdentifier: containerIdentifier
            )
            persistencePresentation = .iCloudConfigured
        }

        let modelContainer = try ModelContainerFactory.make(for: persistenceMode)
        let mainContext = ModelContext(modelContainer)
        self.modelContainer = modelContainer
        seedLoader = SwiftDataSeedLoader(modelContext: mainContext)
        let repository = SwiftDataTrainingRepository(modelContext: mainContext)

        #if DEBUG
        if environment == .uiTesting,
           let launchConfiguration = AppUITestLaunchConfiguration.resolve() {
            switch launchConfiguration.scenario {
            case .emptyOnce:
                trainingRepository = UITestFoundationRepository(
                    repository: repository,
                    initialOutcome: .missingProgram
                )
                shouldLoadFoundation = true
            case .errorOnce:
                trainingRepository = UITestFoundationRepository(
                    repository: repository,
                    initialOutcome: .repositoryError
                )
                shouldLoadFoundation = true
            case .loading:
                trainingRepository = repository
                shouldLoadFoundation = false
            case .seeded, .fatalConfiguration, .sessionFlow, .sessionFamilies, .sessionResume,
                 .progressionMissingRIR, .weeklyPallof:
                trainingRepository = repository
                shouldLoadFoundation = true
            }
        } else {
            trainingRepository = repository
            shouldLoadFoundation = true
        }
        #else
        trainingRepository = repository
        shouldLoadFoundation = true
        #endif

        foundationViewModel = FoundationProgramViewModel(repository: trainingRepository)
        let sessionRepository = trainingRepository
        makeSessionViewModel = {
            SessionViewModel(repository: sessionRepository)
        }

        #if DEBUG
        let scenario = environment == .uiTesting
            ? AppUITestLaunchConfiguration.resolve()?.scenario
            : nil
        installUITestFixture = {
            guard let scenario else { return }
            try UITestSessionFixture.install(scenario: scenario, in: mainContext)
        }
        #else
        installUITestFixture = {}
        #endif
    }

    func load() throws {
        try seedLoader.seedIfNeeded(installedAt: .now)
        try installUITestFixture()
    }
}

#if DEBUG
@MainActor
private enum UITestSessionFixture {
    private static let familyDayID = uuid("00000000-0000-4000-8000-00000000f001")
    private static let familyWarmupID = uuid("00000000-0000-4000-8000-00000000f002")
    private static let familyCooldownID = uuid("00000000-0000-4000-8000-00000000f003")
    private static let resumeSessionID = uuid("00000000-0000-4000-8000-00000000f020")
    private static let resumeProgressID = uuid("00000000-0000-4000-8000-00000000f021")
    private static let progressionSessionID = uuid("00000000-0000-4000-8000-00000000f030")
    private static let weeklyPallofSessionID = uuid("00000000-0000-4000-8000-00000000f040")
    private static let weeklyPallofProgressID = uuid("00000000-0000-4000-8000-00000000f041")
    private static let installedAt = Date(timeIntervalSince1970: 1_700_000_000)

    static func install(scenario: AppUITestScenario, in modelContext: ModelContext) throws {
        switch scenario {
        case .sessionFamilies:
            try installMeasurementFamilies(in: modelContext)
        case .sessionResume:
            try installResumeProgress(in: modelContext)
        case .progressionMissingRIR:
            try installMissingRIRHistory(in: modelContext)
        case .weeklyPallof:
            try installWeeklyPallofProgress(in: modelContext)
        case .seeded, .emptyOnce, .errorOnce, .loading, .fatalConfiguration, .sessionFlow:
            return
        }
    }

    private static func installMeasurementFamilies(in modelContext: ModelContext) throws {
        let existingDays = try modelContext.fetch(FetchDescriptor<WorkoutDayTemplate>())
        guard !existingDays.contains(where: { $0.id == familyDayID }) else { return }
        guard let program = try modelContext.fetch(FetchDescriptor<Program>())
            .first(where: { $0.id == SeedIdentifiers.program }) else {
            throw UITestSessionFixtureError.missingSeededProgram
        }

        let day = WorkoutDayTemplate(
            id: familyDayID,
            createdAt: installedAt,
            updatedAt: installedAt,
            name: "Ölçüm aileleri",
            orderIndex: 0,
            focus: "Beş kayıt ailesinin gerçek akışı",
            program: program
        )
        modelContext.insert(day)

        modelContext.insert(
            WarmupItem(
                id: familyWarmupID,
                createdAt: installedAt,
                updatedAt: installedAt,
                phase: .raise,
                movement: "Hafif yürüyüş",
                dose: "2 dakika",
                orderIndex: 1,
                workoutDayTemplate: day
            )
        )

        let exerciseFixtures: [ExerciseFixture] = [
            .init(
                id: uuid("00000000-0000-4000-8000-00000000f010"),
                name: "Ağırlık + tekrar",
                orderIndex: 1,
                repTarget: 8,
                startingWeightKg: 10,
                measurementKind: .weightReps
            ),
            .init(
                id: uuid("00000000-0000-4000-8000-00000000f011"),
                name: "Tekrar",
                orderIndex: 2,
                repTarget: 10,
                startingWeightKg: nil,
                measurementKind: .reps
            ),
            .init(
                id: uuid("00000000-0000-4000-8000-00000000f012"),
                name: "Süre",
                orderIndex: 3,
                repTarget: 30,
                startingWeightKg: nil,
                measurementKind: .duration
            ),
            .init(
                id: uuid("00000000-0000-4000-8000-00000000f013"),
                name: "Adım",
                orderIndex: 4,
                repTarget: 40,
                startingWeightKg: 20,
                measurementKind: .steps
            ),
            .init(
                id: uuid("00000000-0000-4000-8000-00000000f014"),
                name: "Kalite",
                orderIndex: 5,
                repTarget: nil,
                startingWeightKg: nil,
                measurementKind: .quality
            ),
        ]
        for fixture in exerciseFixtures {
            modelContext.insert(
                ExerciseTemplate(
                    id: fixture.id,
                    createdAt: installedAt,
                    updatedAt: installedAt,
                    name: fixture.name,
                    orderIndex: fixture.orderIndex,
                    targetSets: 1,
                    repLow: fixture.repTarget,
                    repHigh: fixture.repTarget,
                    rirLow: 0,
                    rirHigh: 2,
                    category: .accessory,
                    allowFailure: false,
                    cues: "Kontrollü ve ağrısız uygula.",
                    safetyNote: "Güvenli tekniği koru.",
                    startingWeightKg: fixture.startingWeightKg,
                    progressionRule: .timeQuality,
                    measurementKind: fixture.measurementKind,
                    workoutDayTemplate: day
                )
            )
        }

        modelContext.insert(
            CooldownItem(
                id: familyCooldownID,
                createdAt: installedAt,
                updatedAt: installedAt,
                movement: "Rahat nefes",
                dose: "1 dakika",
                note: "Nabzın sakinleşsin.",
                orderIndex: 1,
                workoutDayTemplate: day
            )
        )
        try modelContext.save()
    }

    private static func installResumeProgress(in modelContext: ModelContext) throws {
        let existingSessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        guard !existingSessions.contains(where: { $0.id == resumeSessionID }) else { return }

        modelContext.insert(
            WorkoutSession(
                id: resumeSessionID,
                createdAt: installedAt,
                updatedAt: installedAt,
                date: installedAt,
                status: .inProgress,
                workoutDayTemplateId: SeedIdentifiers.dayA
            )
        )
        modelContext.insert(
            WorkoutSessionProgress(
                id: resumeProgressID,
                createdAt: installedAt,
                updatedAt: installedAt,
                workoutSessionId: resumeSessionID,
                stage: .movement,
                currentExerciseTemplateId: SeedIdentifiers.plankPallof,
                completedWarmupItemIdsData: WorkoutSessionProgressCodec.emptyPayload,
                completedCooldownItemIdsData: WorkoutSessionProgressCodec.emptyPayload,
                warmupDisposition: .completed,
                cooldownDisposition: .pending
            )
        )
        try modelContext.save()
    }

    private static func installMissingRIRHistory(in modelContext: ModelContext) throws {
        let existingSessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        guard !existingSessions.contains(where: { $0.id == progressionSessionID }) else {
            return
        }

        let session = WorkoutSession(
            id: progressionSessionID,
            createdAt: installedAt,
            updatedAt: installedAt,
            date: installedAt,
            status: .completed,
            workoutDayTemplateId: SeedIdentifiers.dayA
        )
        modelContext.insert(session)
        let setIDs = [
            uuid("00000000-0000-4000-8000-00000000f031"),
            uuid("00000000-0000-4000-8000-00000000f032"),
            uuid("00000000-0000-4000-8000-00000000f033"),
        ]
        let rirs: [Int?] = [0, nil, 0]
        for (offset, rir) in rirs.enumerated() {
            modelContext.insert(
                SetLog(
                    id: setIDs[offset],
                    createdAt: installedAt,
                    updatedAt: installedAt,
                    exerciseTemplateId: SeedIdentifiers.gobletSquat,
                    setIndex: offset + 1,
                    weightKg: 10,
                    reps: 25,
                    rir: rir,
                    isWarmupSet: false,
                    completedAt: installedAt,
                    workoutSession: session
                )
            )
        }
        try modelContext.save()
    }

    private static func installWeeklyPallofProgress(in modelContext: ModelContext) throws {
        let existingSessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        guard !existingSessions.contains(where: { $0.id == weeklyPallofSessionID }) else {
            return
        }

        modelContext.insert(
            WorkoutSession(
                id: weeklyPallofSessionID,
                createdAt: installedAt,
                updatedAt: installedAt,
                date: installedAt,
                status: .inProgress,
                workoutDayTemplateId: SeedIdentifiers.dayA
            )
        )
        modelContext.insert(
            WorkoutSessionProgress(
                id: weeklyPallofProgressID,
                createdAt: installedAt,
                updatedAt: installedAt,
                workoutSessionId: weeklyPallofSessionID,
                stage: .movement,
                currentExerciseTemplateId: SeedIdentifiers.plankPallof,
                completedWarmupItemIdsData: WorkoutSessionProgressCodec.emptyPayload,
                completedCooldownItemIdsData: WorkoutSessionProgressCodec.emptyPayload,
                warmupDisposition: .completed,
                cooldownDisposition: .pending
            )
        )
        try modelContext.save()
    }

    private static func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private struct ExerciseFixture {
        let id: UUID
        let name: String
        let orderIndex: Int
        let repTarget: Int?
        let startingWeightKg: Double?
        let measurementKind: ExerciseMeasurementKind
    }
}

private enum UITestSessionFixtureError: Error {
    case missingSeededProgram
}

@MainActor
private final class UITestFoundationRepository: TrainingRepository {
    enum InitialOutcome: Equatable {
        case missingProgram
        case repositoryError
    }

    private let repository: any TrainingRepository
    private let initialOutcome: InitialOutcome
    private var foundationLoadAttempt = 0

    init(repository: any TrainingRepository, initialOutcome: InitialOutcome) {
        self.repository = repository
        self.initialOutcome = initialOutcome
    }

    func fetchUserProfile() async throws -> UserProfile? {
        foundationLoadAttempt += 1
        if foundationLoadAttempt > 1 {
            try await Task.sleep(nanoseconds: 2_500_000_000)
        }
        if foundationLoadAttempt == 1, initialOutcome == .repositoryError {
            throw UITestFoundationRepositoryError.initialLoad
        }
        return try await repository.fetchUserProfile()
    }

    func fetchActiveProgram() async throws -> Program? {
        if foundationLoadAttempt == 1, initialOutcome == .missingProgram {
            return nil
        }
        return try await repository.fetchActiveProgram()
    }

    func fetchProgramPhases(programID: UUID) async throws -> [ProgramPhase] {
        try await repository.fetchProgramPhases(programID: programID)
    }

    func fetchWorkoutDays(programID: UUID) async throws -> [WorkoutDayTemplate] {
        try await repository.fetchWorkoutDays(programID: programID)
    }

    func fetchExerciseTemplates(workoutDayID: UUID) async throws -> [ExerciseTemplate] {
        try await repository.fetchExerciseTemplates(workoutDayID: workoutDayID)
    }

    func fetchWarmupItems(workoutDayID: UUID) async throws -> [WarmupItem] {
        try await repository.fetchWarmupItems(workoutDayID: workoutDayID)
    }

    func fetchCooldownItems(workoutDayID: UUID) async throws -> [CooldownItem] {
        try await repository.fetchCooldownItems(workoutDayID: workoutDayID)
    }

    func fetchHealthCheckReminders() async throws -> [HealthCheckReminder] {
        try await repository.fetchHealthCheckReminders()
    }

    func fetchProgramState(programID: UUID) async throws -> ProgramState? {
        try await repository.fetchProgramState(programID: programID)
    }

    func saveSet(_ request: SetLogSaveRequest) async throws -> SetLogSnapshot {
        try await repository.saveSet(request)
    }

    func createWorkoutSession(
        _ request: WorkoutSessionCreateRequest
    ) async throws -> WorkoutSessionSnapshot {
        try await repository.createWorkoutSession(request)
    }

    func fetchInProgressWorkoutSession() async throws -> WorkoutSessionSnapshot? {
        try await repository.fetchInProgressWorkoutSession()
    }

    func transitionWorkoutSession(
        id: UUID,
        to status: WorkoutSessionStatus,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        try await repository.transitionWorkoutSession(id: id, to: status, at: date)
    }

    func fetchWorkoutSessionProgress(
        sessionID: UUID
    ) async throws -> WorkoutSessionProgressSnapshot? {
        try await repository.fetchWorkoutSessionProgress(sessionID: sessionID)
    }

    func saveWorkoutSessionProgress(
        _ update: WorkoutSessionProgressUpdate
    ) async throws -> WorkoutSessionProgressSnapshot {
        try await repository.saveWorkoutSessionProgress(update)
    }

    func fetchSessionExercises(
        workoutDayID: UUID
    ) async throws -> [SessionExerciseSnapshot] {
        try await repository.fetchSessionExercises(workoutDayID: workoutDayID)
    }

    func fetchSessionPlan(
        workoutDayID: UUID
    ) async throws -> SessionWorkoutPlanSnapshot? {
        try await repository.fetchSessionPlan(workoutDayID: workoutDayID)
    }

    func fetchSetLogs(workoutSessionID: UUID) async throws -> [SetLogSnapshot] {
        try await repository.fetchSetLogs(workoutSessionID: workoutSessionID)
    }

    func fetchCompletedExerciseHistory(
        exerciseTemplateID: UUID
    ) async throws -> [CompletedExerciseHistorySnapshot] {
        try await repository.fetchCompletedExerciseHistory(
            exerciseTemplateID: exerciseTemplateID
        )
    }

    func fetchWeeklyPallofHistory() async throws -> WeeklyPallofHistorySnapshot {
        try await repository.fetchWeeklyPallofHistory()
    }

    func updateWorkoutSessionSummary(
        id: UUID,
        perceivedRecovery: Int?,
        note: String?,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        try await repository.updateWorkoutSessionSummary(
            id: id,
            perceivedRecovery: perceivedRecovery,
            note: note,
            at: date
        )
    }

    func deleteWorkoutSession(id: UUID) async throws {
        try await repository.deleteWorkoutSession(id: id)
    }
}

private enum UITestFoundationRepositoryError: Error {
    case initialLoad
}
#endif
