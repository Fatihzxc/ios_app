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
    let trainingRepository: any TrainingRepository
    let foundationViewModel: FoundationProgramViewModel
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
            case .seeded, .fatalConfiguration:
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
    }

    func load() throws {
        try seedLoader.seedIfNeeded(installedAt: .now)
    }
}

#if DEBUG
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
}

private enum UITestFoundationRepositoryError: Error {
    case initialLoad
}
#endif
