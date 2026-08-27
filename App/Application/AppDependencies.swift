import CoreModels
import Foundation
import NotificationsKit
import NutritionKit
import PersistenceKit
import SettingsKit
import SwiftData
import TrainingKit

@MainActor
protocol AppDependencyLoading: AnyObject {
    func load() throws
    func loadInitialContent() async
}

extension AppDependencyLoading {
    func loadInitialContent() async {}
}

@MainActor
final class AppDependencies: AppDependencyLoading {
    private let modelContainer: ModelContainer
    private let mainContext: ModelContext
    private let seedLoader: SwiftDataSeedLoader
    private let installUITestFixture: @MainActor () throws -> Void
    private let injectedHapticClient: (any TrainingHapticClient)?
    private let hapticControllerReference: TrainingHapticControllerReference
    private var didLoad = false
    private let trackerFeatureBundleFactory:
        @MainActor (ModelContext) -> any TrackerFeatureRouting
    let healthCheckNotificationComposition: HealthCheckNotificationComposition
    private let notificationLaunchGate: HealthCheckNotificationLaunchGate
    let trainingRepository: any TrainingRepository
    let todayViewModel: TodayViewModel
    private lazy var deferredTrainingDependencies = DeferredTrainingDependencies(
        repository: trainingRepository,
        todayViewModel: todayViewModel,
        hapticControllerReference: hapticControllerReference,
        makeSymptomEventClient: { [unowned self] in
            self.trainingSymptomEventClient
        }
    )
    var foundationViewModel: FoundationProgramViewModel {
        deferredTrainingDependencies.foundationViewModel
    }
    var phaseTransitionViewModel: PhaseTransitionViewModel {
        deferredTrainingDependencies.phaseTransitionViewModel
    }
    var trainingHistoryViewModel: TrainingHistoryViewModel {
        deferredTrainingDependencies.trainingHistoryViewModel
    }
    var makeSessionViewModel: @MainActor () -> SessionViewModel {
        deferredTrainingDependencies.makeSessionViewModel
    }
    lazy var nutritionRepository: any NutritionRepository = SwiftDataNutritionRepository(
        modelContext: mainContext
    )
    private lazy var nutritionDayRepository: any NutritionDayViewRepository = {
        #if DEBUG
        switch AppUITestLaunchConfiguration.resolve()?.scenario {
        case .nutritionErrorOnce:
            return UITestNutritionDayRepository(
                repository: nutritionRepository,
                failsFirstLoad: true
            )
        case .nutritionDeleteErrorOnce:
            return UITestNutritionDayRepository(
                repository: nutritionRepository,
                failsFirstDelete: true
            )
        default:
            return nutritionRepository
        }
        #else
        return nutritionRepository
        #endif
    }()
    lazy var nutritionDayViewModel = NutritionDayViewModel(
        repository: nutritionDayRepository
    )
    lazy var foodLibraryViewModel = FoodLibraryViewModel(
        repository: nutritionRepository
    )
    lazy var recipeLibraryViewModel = RecipeLibraryViewModel(
        repository: nutritionRepository
    )
    lazy var nutritionQuickAddViewModel = NutritionQuickAddViewModel(
        repository: nutritionRepository,
        makeID: { Self.makeNutritionQuickAddRequestID() }
    )
    lazy var nutritionManualEntryViewModel = NutritionManualEntryViewModel(
        repository: nutritionRepository,
        foodRepository: nutritionRepository
    )
    lazy var todayNutritionViewModel = TodayNutritionViewModel(
        repository: nutritionRepository
    )
    private(set) var trackerFeatureRouterInstantiationCount = 0
    private lazy var trackerFeatureRouter: any TrackerFeatureRouting = {
        trackerFeatureRouterInstantiationCount += 1
        return trackerFeatureBundleFactory(mainContext)
    }()
    private lazy var trainingSymptomEventClient: any SymptomEventClient = {
        let adapter = DefaultTrainingSymptomEventFactory.make(
            modelContext: mainContext
        )
        #if DEBUG
        if AppUITestLaunchConfiguration.resolve()?.scenario == .ohpSafety {
            return UITestSymptomEventClient(
                client: adapter,
                failsFirstRecord: true
            )
        }
        #endif
        return adapter
    }()
    var makeTrackerFeatureRouter: @MainActor () -> any TrackerFeatureRouting {
        { self.trackerFeatureRouter }
    }
    private(set) var trainingHapticController: TrainingHapticController?
    let medicalSafetyAcknowledgementController: MedicalSafetyAcknowledgementController
    let shouldLoadFoundation: Bool
    let persistencePresentation: FoundationPersistencePresentation

    fileprivate struct PersistencePreparation: Sendable {
        let mode: PersistenceMode
        let presentation: FoundationPersistencePresentation
    }

    convenience init(
        environment: AppEnvironment,
        hapticClient: (any TrainingHapticClient)? = nil,
        makeTrackerFeatureBundle: (
            @MainActor (ModelContext) -> any TrackerFeatureRouting
        )? = nil,
        reconcileHealthCheckNotificationsAfterFirstMeaningfulTodayContent: (
            @MainActor () async throws -> Void
        )? = nil,
        healthCheckNotificationCenter: any NotificationCenterClient =
            SystemNotificationCenterAdapter(),
        healthCheckNotificationComposition: HealthCheckNotificationComposition? = nil
    ) throws {
        let persistence = try Self.persistencePreparation(for: environment)
        let modelContainer = try ModelContainerFactory.make(for: persistence.mode)
        AppLaunchPerformance.record(.container)
        self.init(
            environment: environment,
            persistence: persistence,
            modelContainer: modelContainer,
            hapticClient: hapticClient,
            makeTrackerFeatureBundle: makeTrackerFeatureBundle,
            reconcileHealthCheckNotificationsAfterFirstMeaningfulTodayContent:
                reconcileHealthCheckNotificationsAfterFirstMeaningfulTodayContent,
            healthCheckNotificationCenter: healthCheckNotificationCenter,
            healthCheckNotificationComposition: healthCheckNotificationComposition
        )
    }

    fileprivate init(
        environment: AppEnvironment,
        persistence: PersistencePreparation,
        modelContainer: ModelContainer,
        hapticClient: (any TrainingHapticClient)?,
        makeTrackerFeatureBundle: (
            @MainActor (ModelContext) -> any TrackerFeatureRouting
        )?,
        reconcileHealthCheckNotificationsAfterFirstMeaningfulTodayContent: (
            @MainActor () async throws -> Void
        )?,
        healthCheckNotificationCenter: any NotificationCenterClient,
        healthCheckNotificationComposition: HealthCheckNotificationComposition?
    ) {
        AppLaunchPerformance.record(.dependencyEntry)
        let mainContext = ModelContext(modelContainer)
        AppLaunchPerformance.record(.dependencyContext)
        self.modelContainer = modelContainer
        self.mainContext = mainContext
        persistencePresentation = persistence.presentation
        injectedHapticClient = hapticClient
        trainingHapticController = nil
        let hapticControllerReference = TrainingHapticControllerReference()
        self.hapticControllerReference = hapticControllerReference
        let resolvedHealthCheckNotificationComposition =
            healthCheckNotificationComposition
            ?? DefaultHealthCheckNotificationFactory.make(
                modelContext: mainContext,
                notificationCenter: healthCheckNotificationCenter
            )
        self.healthCheckNotificationComposition =
            resolvedHealthCheckNotificationComposition
        let launchReconciliation: @MainActor () async throws -> Bool
        if let injectedLaunchReconciliation =
            reconcileHealthCheckNotificationsAfterFirstMeaningfulTodayContent {
            launchReconciliation = {
                try await injectedLaunchReconciliation()
                return true
            }
        } else {
            launchReconciliation = {
                try await resolvedHealthCheckNotificationComposition
                    .lifecycleCoordinator
                    .reconcileAfterFirstMeaningfulTodayContent()
            }
        }
        let notificationLaunchGate = HealthCheckNotificationLaunchGate(
            reconcile: launchReconciliation
        )
        self.notificationLaunchGate = notificationLaunchGate
        trackerFeatureBundleFactory = makeTrackerFeatureBundle ?? { modelContext in
            DefaultTrackerFeatureFactory.make(
                environment: environment,
                modelContext: modelContext,
                healthCheckNotificationCenter: healthCheckNotificationCenter,
                healthCheckNotificationComposition:
                    resolvedHealthCheckNotificationComposition
            )
        }
        seedLoader = SwiftDataSeedLoader(modelContext: mainContext)
        let repository = SwiftDataTrainingRepository(modelContext: mainContext)
        AppLaunchPerformance.record(.dependencyRepository)

        #if DEBUG
        if environment == .uiTesting,
           let launchConfiguration = AppUITestLaunchConfiguration.resolve() {
            switch launchConfiguration.scenario {
            case .emptyOnce:
                trainingRepository = UITestFoundationRepository(
                    repository: repository,
                    foundationInitialOutcome: .missingProgram
                )
                shouldLoadFoundation = true
            case .errorOnce:
                trainingRepository = UITestFoundationRepository(
                    repository: repository,
                    foundationInitialOutcome: .repositoryError
                )
                shouldLoadFoundation = true
            case .todayEmptyOnce:
                trainingRepository = UITestFoundationRepository(
                    repository: repository,
                    todayInitialOutcome: .missingProgram
                )
                shouldLoadFoundation = true
            case .todayErrorOnce:
                trainingRepository = UITestFoundationRepository(
                    repository: repository,
                    todayInitialOutcome: .repositoryError
                )
                shouldLoadFoundation = true
            case .loading:
                trainingRepository = repository
                shouldLoadFoundation = false
            case .ohpSafety:
                trainingRepository = UITestFoundationRepository(
                    repository: repository,
                    failsFirstCurrentOHPSymptomWrite: true,
                    failsFirstSessionDeletion: true
                )
                shouldLoadFoundation = true
            case .seeded, .fatalConfiguration, .sessionFlow, .sessionFamilies, .sessionResume,
                 .progressionMissingRIR, .weeklyPallof, .deloadScheduled,
                 .deloadReactive, .phaseTransition, .trainingHistory, .todayTrain,
                 .todayRest, .todayResume, .todayDeload, .todayPhase, .todayReminder,
                 .todayPriority, .m1AcceptanceCatalog, .m1PRBaseline, .m1PRNew,
                 .nutritionContent, .nutritionEmpty, .nutritionErrorOnce,
                 .nutritionDeleteErrorOnce, .nutritionQuickAdd, .m2Acceptance:
                trainingRepository = repository
                shouldLoadFoundation = true
            case .m3BodyMetrics, .m3SleepMood, .m3Posture, .m3HealthChecks,
                 .m3Bloodwork, .m3ProgressPhotos, .m3PhotoGallery:
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
        AppLaunchPerformance.record(.dependencyRouting)

        todayViewModel = TodayViewModel(
            repository: trainingRepository,
            calendar: AppDomainContext.makeCalendar(),
            now: { AppDomainContext.now() },
            launchStartedAt: AppLaunchPerformance.startedAt,
            onFirstMeaningfulContent: { elapsed in
                AppLaunchPerformance.finish(elapsed)
                notificationLaunchGate.markTodayContentMeaningful()
                Task { await notificationLaunchGate.reconcileIfNeeded() }
            }
        )
        AppLaunchPerformance.record(.dependencyViewModel)

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
        medicalSafetyAcknowledgementController = MedicalSafetyAcknowledgementController(
            store: SwiftDataMedicalSafetyAcknowledgementStore(modelContext: mainContext)
        )
        #if DEBUG
        if environment == .uiTesting,
           let launchConfiguration = AppUITestLaunchConfiguration.resolve(),
           !launchConfiguration.exposesMedicalSafetyFirstUseEvidence {
            _ = medicalSafetyAcknowledgementController.acknowledge()
        }
        #endif
        AppLaunchPerformance.record(.dependencies)
    }

    fileprivate static func persistencePreparation(
        for environment: AppEnvironment
    ) throws -> PersistencePreparation {
        let persistenceMode: PersistenceMode
        let persistencePresentation: FoundationPersistencePresentation
        switch environment {
        case .uiTesting:
            #if DEBUG
            if let identifier = AppUITestLaunchConfiguration.resolve()?
                .persistentStoreIdentifier {
                persistenceMode = .local(
                    storeURL: try Self.makeUITestStoreURL(identifier: identifier)
                )
            } else {
                persistenceMode = .inMemory
            }
            #else
            persistenceMode = .inMemory
            #endif
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
        return PersistencePreparation(
            mode: persistenceMode,
            presentation: persistencePresentation
        )
    }

    func load() throws {
        guard !didLoad else { return }
        try seedLoader.seedIfNeeded(installedAt: .now)
        try installUITestFixture()
        didLoad = true
        AppLaunchPerformance.record(.seed)
    }

    func loadInitialContent() async {
        if shouldLoadFoundation, todayViewModel.state == .loading {
            await todayViewModel.load()
        }
        await notificationLaunchGate.reconcileIfNeeded()
        let hapticController = ensureTrainingHapticController()
        hapticController.loadPreference()
    }

    func prepareInitialContentForLaunch() throws {
        try load()
        guard shouldLoadFoundation,
              todayViewModel.state == .loading,
              let synchronousRepository = trainingRepository
                as? any SynchronousTodaySnapshotRepository else {
            return
        }
        do {
            let snapshot = try synchronousRepository.fetchTodaySnapshotSynchronously()
            todayViewModel.applyInitialSnapshot(snapshot)
        } catch {
            // Preserve the existing async load path so a transient read failure can retry.
        }
    }

    private func ensureTrainingHapticController() -> TrainingHapticController {
        if let trainingHapticController {
            return trainingHapticController
        }
        let controller = TrainingHapticController(
            client: injectedHapticClient ?? UIKitTrainingHapticClient(),
            preferenceStore: SwiftDataTrainingHapticPreferenceStore(
                modelContext: mainContext
            )
        )
        trainingHapticController = controller
        hapticControllerReference.value = controller
        phaseTransitionViewModel.installHaptics(controller)
        return controller
    }

    private static func makeNutritionQuickAddRequestID() -> UUID {
        #if DEBUG
        if AppUITestLaunchConfiguration.resolve()?.scenario == .nutritionQuickAdd {
            return UUID(uuidString: "00000000-0000-4000-8000-00000000d201")!
        }
        #endif
        return UUID()
    }

    #if DEBUG
    private static func makeUITestStoreURL(identifier: UUID) throws -> URL {
        guard let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AppEnvironment.StorePathError.applicationSupportUnavailable
        }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppEnvironment.StorePathError.invalidBundleIdentifier
        }

        let directory = applicationSupportDirectory
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("UITestStores", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw AppEnvironment.StorePathError.directoryCreationFailed
        }
        return directory.appendingPathComponent(
            "HealthTracking-\(identifier.uuidString).sqlite"
        )
    }
    #endif
}

@MainActor
final class AppDependencyPrewarmer {
    private let environment: AppEnvironment
    private let buildDependencies: @MainActor (AppEnvironment) throws -> AppDependencies
    private var initialAttempt: Result<AppDependencies, Error>?

    init(
        environment: AppEnvironment,
        healthCheckNotificationCenter: any NotificationCenterClient =
            SystemNotificationCenterAdapter(),
        healthCheckNotificationComposition: HealthCheckNotificationComposition? = nil,
        buildDependencies: (@MainActor (AppEnvironment) throws -> AppDependencies)? = nil
    ) {
        let dependencyBuilder = buildDependencies ?? { environment in
            try Self.prepareDependencies(
                for: environment,
                healthCheckNotificationCenter: healthCheckNotificationCenter,
                healthCheckNotificationComposition: healthCheckNotificationComposition
            )
        }
        self.environment = environment
        self.buildDependencies = dependencyBuilder
        initialAttempt = Result {
            try dependencyBuilder(environment)
        }
    }

    func makeDependencies() async throws -> AppDependencies {
        if let initialAttempt {
            self.initialAttempt = nil
            return try initialAttempt.get()
        }
        return try buildDependencies(environment)
    }

    private static func prepareDependencies(
        for environment: AppEnvironment,
        healthCheckNotificationCenter: any NotificationCenterClient,
        healthCheckNotificationComposition: HealthCheckNotificationComposition?
    ) throws -> AppDependencies {
        let persistence = try AppDependencies.persistencePreparation(for: environment)
        let modelContainer = try ModelContainerFactory.make(for: persistence.mode)
        AppLaunchPerformance.record(.container)
        let dependencies = AppDependencies(
            environment: environment,
            persistence: persistence,
            modelContainer: modelContainer,
            hapticClient: nil,
            makeTrackerFeatureBundle: nil,
            reconcileHealthCheckNotificationsAfterFirstMeaningfulTodayContent: nil,
            healthCheckNotificationCenter: healthCheckNotificationCenter,
            healthCheckNotificationComposition: healthCheckNotificationComposition
        )
        try dependencies.prepareInitialContentForLaunch()
        return dependencies
    }
}

@MainActor
private final class TrainingHapticControllerReference {
    var value: TrainingHapticController?
}

@MainActor
private final class DeferredTrainingDependencies {
    let foundationViewModel: FoundationProgramViewModel
    let phaseTransitionViewModel: PhaseTransitionViewModel
    let trainingHistoryViewModel: TrainingHistoryViewModel
    let makeSessionViewModel: @MainActor () -> SessionViewModel

    init(
        repository: any TrainingRepository,
        todayViewModel: TodayViewModel,
        hapticControllerReference: TrainingHapticControllerReference,
        makeSymptomEventClient: @escaping @MainActor () -> any SymptomEventClient
    ) {
        let foundationViewModel = FoundationProgramViewModel(repository: repository)
        let phaseTransitionViewModel = PhaseTransitionViewModel(repository: repository)
        self.foundationViewModel = foundationViewModel
        self.phaseTransitionViewModel = phaseTransitionViewModel
        trainingHistoryViewModel = TrainingHistoryViewModel(
            repository: repository,
            onHistoryChanged: {
                [weak todayViewModel, weak foundationViewModel, weak phaseTransitionViewModel] in
                await todayViewModel?.load()
                await foundationViewModel?.load()
                await phaseTransitionViewModel?.load()
            }
        )
        makeSessionViewModel = {
            SessionViewModel(
                repository: repository,
                haptics: hapticControllerReference.value,
                symptomEventClient: makeSymptomEventClient(),
                symptomSafetyPresentationProvider: { context in
                    TrainingSymptomSafetyMapper.presentation(for: context)
                }
            )
        }
    }
}

#if DEBUG
@MainActor
private final class UITestSymptomEventClient: SymptomEventClient {
    private enum FixtureFailure: Error {
        case record
    }

    private let client: any SymptomEventClient
    private var failsNextRecord: Bool

    init(client: any SymptomEventClient, failsFirstRecord: Bool) {
        self.client = client
        failsNextRecord = failsFirstRecord
    }

    func record(_ event: SymptomJournalEvent) async throws {
        if failsNextRecord {
            failsNextRecord = false
            throw FixtureFailure.record
        }
        try await client.record(event)
    }
}

@MainActor
private final class UITestNutritionDayRepository: NutritionDayViewRepository {
    private enum FixtureFailure: Error {
        case load
        case delete
    }

    private let repository: any NutritionDayViewRepository
    private var failsNextLoad: Bool
    private var failsNextDelete: Bool

    init(
        repository: any NutritionDayViewRepository,
        failsFirstLoad: Bool = false,
        failsFirstDelete: Bool = false
    ) {
        self.repository = repository
        failsNextLoad = failsFirstLoad
        failsNextDelete = failsFirstDelete
    }

    func fetchNutritionTargets() async throws -> NutritionMacroTargets? {
        try await repository.fetchNutritionTargets()
    }

    func fetchNutritionDay(containing date: Date) async throws -> NutritionDaySnapshot? {
        try await repository.fetchNutritionDay(containing: date)
    }

    func fetchOrCreateNutritionDay(
        containing date: Date
    ) async throws -> NutritionDaySnapshot {
        try await repository.fetchOrCreateNutritionDay(containing: date)
    }

    func fetchNutritionDays() async throws -> [NutritionDaySnapshot] {
        try await repository.fetchNutritionDays()
    }

    func deleteNutritionDay(id: UUID) async throws {
        try await repository.deleteNutritionDay(id: id)
    }

    func fetchMealEntries(
        containing date: Date
    ) async throws -> NutritionDayEntriesSnapshot {
        if failsNextLoad {
            failsNextLoad = false
            throw FixtureFailure.load
        }
        return try await repository.fetchMealEntries(containing: date)
    }

    func createMealEntry(
        _ request: MealEntryCreateRequest
    ) async throws -> NutritionDayEntriesSnapshot {
        try await repository.createMealEntry(request)
    }

    func updateMealEntry(
        id: UUID,
        update: MealEntryUpdate
    ) async throws -> NutritionDayEntriesSnapshot {
        try await repository.updateMealEntry(id: id, update: update)
    }

    func deleteMealEntry(id: UUID) async throws -> NutritionDayEntriesSnapshot {
        if failsNextDelete {
            failsNextDelete = false
            throw FixtureFailure.delete
        }
        return try await repository.deleteMealEntry(id: id)
    }
}

@MainActor
private enum UITestSessionFixture {
    private static let familyDayID = uuid("00000000-0000-4000-8000-00000000f001")
    private static let familyWarmupID = uuid("00000000-0000-4000-8000-00000000f002")
    private static let familyCooldownID = uuid("00000000-0000-4000-8000-00000000f003")
    private static let resumeSessionID = uuid("00000000-0000-4000-8000-00000000f020")
    private static let resumeProgressID = uuid("00000000-0000-4000-8000-00000000f021")
    private static let progressionSessionID = uuid("00000000-0000-4000-8000-00000000f030")
    private static let progressionRotationSessionID = uuid(
        "00000000-0000-4000-8000-00000000f034"
    )
    private static let weeklyPallofSessionID = uuid("00000000-0000-4000-8000-00000000f040")
    private static let weeklyPallofProgressID = uuid("00000000-0000-4000-8000-00000000f041")
    private static let ohpPriorSessionID = uuid("00000000-0000-4000-8000-00000000f050")
    private static let ohpCurrentSessionID = uuid("00000000-0000-4000-8000-00000000f051")
    private static let ohpCurrentProgressID = uuid("00000000-0000-4000-8000-00000000f052")
    private static let historyNewestSessionID = uuid(
        "00000000-0000-4000-8000-00000000f070"
    )
    private static let historyNewestSetID = uuid(
        "00000000-0000-4000-8000-00000000f071"
    )
    private static let historyMissingSessionID = uuid(
        "00000000-0000-4000-8000-00000000f072"
    )
    private static let historyMissingSetID = uuid(
        "00000000-0000-4000-8000-00000000f073"
    )
    private static let historyMissingDayID = uuid(
        "00000000-0000-4000-8000-00000000f074"
    )
    private static let historyMissingExerciseID = uuid(
        "00000000-0000-4000-8000-00000000f075"
    )
    private static let deloadScheduledSessionID = uuid(
        "00000000-0000-4000-8000-00000000f060"
    )
    private static let deloadReactiveOlderSessionID = uuid(
        "00000000-0000-4000-8000-00000000f061"
    )
    private static let deloadReactiveNewerSessionID = uuid(
        "00000000-0000-4000-8000-00000000f062"
    )
    private static let todayRestSessionID = uuid(
        "00000000-0000-4000-8000-00000000f080"
    )
    private static let todayPrioritySessionID = uuid(
        "00000000-0000-4000-8000-00000000f081"
    )
    private static let todayMeasurementReminderID = uuid(
        "00000000-0000-4000-8000-00000000f082"
    )
    private static let m1PersonalRecordSessionID = uuid(
        "00000000-0000-4000-8000-00000000f090"
    )
    private static let m1PersonalRecordSetID = uuid(
        "00000000-0000-4000-8000-00000000f091"
    )
    private static let nutritionFoodID = uuid(
        "00000000-0000-4000-8000-00000000d001"
    )
    private static let nutritionDayID = uuid(
        "00000000-0000-4000-8000-00000000d100"
    )
    private static let nutritionBreakfastEntryID = uuid(
        "00000000-0000-4000-8000-00000000d101"
    )
    private static let nutritionCustomEntryID = uuid(
        "00000000-0000-4000-8000-00000000d102"
    )
    private static let nutritionQuickAddRecipeID = uuid(
        "00000000-0000-4000-8000-00000000d200"
    )
    private static let m2AcceptanceFoodID = uuid(
        "00000000-0000-4000-8000-00000000d300"
    )
    private static let m2AcceptanceRecipeID = uuid(
        "00000000-0000-4000-8000-00000000d301"
    )
    private static let familyWeightExerciseID = uuid(
        "00000000-0000-4000-8000-00000000f010"
    )
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
        case .ohpSafety:
            try installOHPSafety(in: modelContext)
        case .deloadScheduled:
            try installDeload(scheduled: true, in: modelContext)
        case .deloadReactive:
            try installDeload(scheduled: false, in: modelContext)
        case .phaseTransition:
            try installPhaseTransition(in: modelContext)
        case .trainingHistory:
            try installTrainingHistory(in: modelContext)
        case .m1AcceptanceCatalog:
            try installM1AcceptanceCatalog(in: modelContext)
        case .m1PRBaseline:
            try installMeasurementFamilies(in: modelContext)
        case .m1PRNew:
            try installMeasurementFamilies(in: modelContext)
            try installM1PersonalRecord(in: modelContext)
        case .todayTrain:
            try prepareTodayAlerts(in: modelContext, persistChanges: false)
        case .todayRest:
            try prepareTodayAlerts(in: modelContext)
            try installTodayRest(in: modelContext)
        case .todayResume:
            try prepareTodayAlerts(in: modelContext)
            try installResumeProgress(in: modelContext)
        case .todayDeload:
            try prepareTodayAlerts(in: modelContext)
            try installDeload(scheduled: true, in: modelContext)
        case .todayPhase:
            try prepareTodayAlerts(in: modelContext)
            try installPhaseTransition(in: modelContext)
        case .todayReminder:
            try prepareTodayReminder(in: modelContext)
        case .todayPriority:
            try installTodayPriority(in: modelContext)
        case .nutritionContent, .nutritionErrorOnce, .nutritionDeleteErrorOnce:
            try installNutritionContent(in: modelContext)
        case .nutritionQuickAdd:
            try installNutritionQuickAdd(in: modelContext)
        case .m2Acceptance:
            try installM2Acceptance(in: modelContext)
        case .m3Posture:
            try installM3Posture(in: modelContext)
        case .m3HealthChecks:
            try installM3HealthChecks(in: modelContext)
        case .seeded, .emptyOnce, .errorOnce, .loading, .fatalConfiguration, .sessionFlow,
             .todayEmptyOnce, .todayErrorOnce, .nutritionEmpty, .m3BodyMetrics,
             .m3SleepMood, .m3Bloodwork, .m3ProgressPhotos, .m3PhotoGallery:
            return
        }
    }

    private static func installM3HealthChecks(in modelContext: ModelContext) throws {
        let reminderID = SeedIdentifiers.generalCheckupReminder
        guard let reminder = try modelContext.fetch(
            FetchDescriptor<HealthCheckReminder>(
                predicate: #Predicate { $0.id == reminderID }
            )
        ).first,
        reminder.status == .pending else {
            return
        }
        reminder.dueDate = Date.now.addingTimeInterval(-60)
        reminder.updatedAt = Date.now
        try modelContext.save()
    }

    private static func installM3Posture(in modelContext: ModelContext) throws {
        let fixtureID = uuid("00000000-0000-4000-8000-00000000d401")
        let existing = try modelContext.fetch(
            FetchDescriptor<PostureMetric>(
                predicate: #Predicate { $0.id == fixtureID }
            )
        )
        guard existing.isEmpty else { return }
        let date = installedAt.addingTimeInterval(-7 * 24 * 60 * 60)
        modelContext.insert(
            PostureMetric(
                id: fixtureID,
                createdAt: date,
                updatedAt: date,
                date: date,
                wallTestPass: true,
                symptomScore: 2,
                region: "Boyun",
                note: "Haftalık başlangıç kaydı"
            )
        )
        try modelContext.save()
    }

    private static func installNutritionContent(
        in modelContext: ModelContext
    ) throws {
        let existingLogs = try modelContext.fetch(FetchDescriptor<DailyNutritionLog>())
        guard !existingLogs.contains(where: { $0.id == nutritionDayID }) else { return }

        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        guard let day = calendar.dateInterval(of: .day, for: now),
              let secondTimestamp = calendar.date(
                  byAdding: .minute,
                  value: 1,
                  to: day.start
              ) else {
            throw UITestSessionFixtureError.missingSeededProgram
        }
        let log = DailyNutritionLog(
            id: nutritionDayID,
            createdAt: day.start,
            updatedAt: secondTimestamp,
            date: day.start
        )
        let food = Food(
            id: nutritionFoodID,
            createdAt: day.start,
            updatedAt: day.start,
            name: "Yoğurt",
            brand: "Sentetik test",
            servingSize: 1,
            servingUnit: "kase",
            caloriesPerServing: 250,
            proteinG: 20,
            carbG: 30,
            fatG: 5,
            source: .userCreated
        )
        let breakfast = MealEntry(
            id: nutritionBreakfastEntryID,
            createdAt: day.start,
            updatedAt: day.start,
            category: try MealCategory(kind: .breakfast),
            foodId: food.id,
            quantity: 1,
            caloriesResolved: 250,
            proteinResolved: 20,
            carbResolved: 30,
            fatResolved: 5,
            loggedAt: day.start,
            dailyNutritionLog: log
        )
        let custom = MealEntry(
            id: nutritionCustomEntryID,
            createdAt: secondTimestamp,
            updatedAt: secondTimestamp,
            category: try MealCategory(
                kind: .custom,
                customName: "Antrenman sonrası"
            ),
            adhocName: "Sentetik shake",
            quantity: 1,
            caloriesResolved: 120,
            proteinResolved: 15,
            carbResolved: 10,
            fatResolved: 2,
            loggedAt: secondTimestamp,
            dailyNutritionLog: log
        )
        modelContext.insert(log)
        modelContext.insert(food)
        modelContext.insert(breakfast)
        modelContext.insert(custom)
        try modelContext.save()
    }

    private static func installNutritionQuickAdd(
        in modelContext: ModelContext
    ) throws {
        let recipes = try modelContext.fetch(FetchDescriptor<Recipe>())
        guard !recipes.contains(where: { $0.id == nutritionQuickAddRecipeID }) else {
            return
        }
        let now = Date.now
        modelContext.insert(
            Recipe(
                id: nutritionQuickAddRecipeID,
                createdAt: now,
                updatedAt: now,
                name: "Yulaf kasesi",
                category: try MealCategory(kind: .breakfast),
                servings: 1,
                isDirectMacros: true,
                caloriesTotal: 300,
                proteinTotalG: 25,
                carbTotalG: 35,
                fatTotalG: 8,
                note: "Sentetik hızlı ekleme testi"
            )
        )
        try modelContext.save()
    }

    private static func installM2Acceptance(
        in modelContext: ModelContext
    ) throws {
        let now = Date.now
        let foods = try modelContext.fetch(FetchDescriptor<Food>())
        if !foods.contains(where: { $0.id == m2AcceptanceFoodID }) {
            modelContext.insert(
                Food(
                    id: m2AcceptanceFoodID,
                    createdAt: now,
                    updatedAt: now,
                    name: "Erişilebilir yoğurt",
                    brand: "Sentetik M2 fixture",
                    servingSize: 1,
                    servingUnit: "porsiyon",
                    caloriesPerServing: 140,
                    proteinG: 14,
                    carbG: 12,
                    fatG: 4,
                    source: .userCreated
                )
            )
        }

        let recipes = try modelContext.fetch(FetchDescriptor<Recipe>())
        if !recipes.contains(where: { $0.id == m2AcceptanceRecipeID }) {
            modelContext.insert(
                Recipe(
                    id: m2AcceptanceRecipeID,
                    createdAt: now,
                    updatedAt: now,
                    name: "M2 fixture yulafı",
                    category: try MealCategory(kind: .breakfast),
                    servings: 1,
                    isDirectMacros: true,
                    caloriesTotal: 280,
                    proteinTotalG: 24,
                    carbTotalG: 34,
                    fatTotalG: 7,
                    note: "Sentetik acceptance fixture"
                )
            )
        }
        try modelContext.save()
    }

    private static func installM1AcceptanceCatalog(
        in modelContext: ModelContext
    ) throws {
        let exercises = try modelContext.fetch(FetchDescriptor<ExerciseTemplate>())
        guard exercises.count == 27 else {
            throw UITestSessionFixtureError.missingSeededProgram
        }
        for exercise in exercises {
            exercise.targetSets = 1
            exercise.updatedAt = .now
        }
        try modelContext.save()
    }

    private static func installM1PersonalRecord(
        in modelContext: ModelContext
    ) throws {
        let existingSessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        guard !existingSessions.contains(where: { $0.id == m1PersonalRecordSessionID }) else {
            return
        }
        guard let exercise = try modelContext.fetch(FetchDescriptor<ExerciseTemplate>())
            .first(where: { $0.id == familyWeightExerciseID }) else {
            throw UITestSessionFixtureError.missingSeededProgram
        }
        let completedAt = installedAt.addingTimeInterval(-3_600)
        let session = WorkoutSession(
            id: m1PersonalRecordSessionID,
            createdAt: completedAt,
            updatedAt: completedAt,
            date: completedAt,
            status: .completed,
            workoutDayTemplateId: familyDayID
        )
        modelContext.insert(session)
        modelContext.insert(
            SetLog(
                id: m1PersonalRecordSetID,
                createdAt: completedAt,
                updatedAt: completedAt,
                exerciseTemplateId: exercise.id,
                setIndex: 1,
                weightKg: 10,
                reps: 8,
                rir: 2,
                completedAt: completedAt,
                workoutSession: session
            )
        )
        try modelContext.save()
    }

    private static func prepareTodayAlerts(
        in modelContext: ModelContext,
        persistChanges: Bool = true
    ) throws {
        for reminder in try modelContext.fetch(FetchDescriptor<HealthCheckReminder>()) {
            reminder.status = .done
            reminder.updatedAt = .now
        }
        for reminder in try modelContext.fetch(FetchDescriptor<AppReminder>()) {
            reminder.isEnabled = false
            reminder.updatedAt = .now
        }
        if persistChanges {
            try modelContext.save()
        }
    }

    private static func prepareTodayReminder(in modelContext: ModelContext) throws {
        try prepareTodayAlerts(in: modelContext)
        guard let reminder = try modelContext.fetch(FetchDescriptor<HealthCheckReminder>())
            .sorted(by: { $0.id.uuidString < $1.id.uuidString })
            .first else {
            throw UITestSessionFixtureError.missingSeededProgram
        }
        reminder.status = .pending
        reminder.dueDate = .now.addingTimeInterval(-60)
        reminder.updatedAt = .now
        let now = Date.now
        modelContext.insert(
            AppReminder(
                id: todayMeasurementReminderID,
                createdAt: now,
                updatedAt: now,
                type: .measurement,
                schedule: "today-reminder-ui-test",
                message: "Bel ölçümünü kaydet",
                isEnabled: true
            )
        )
        try modelContext.save()
    }

    private static func installTodayRest(in modelContext: ModelContext) throws {
        modelContext.insert(
            WorkoutSession(
                id: todayRestSessionID,
                createdAt: .now,
                updatedAt: .now,
                date: .now,
                status: .completed,
                workoutDayTemplateId: SeedIdentifiers.dayA
            )
        )
        try modelContext.save()
    }

    private static func installTodayPriority(in modelContext: ModelContext) throws {
        try prepareTodayAlerts(in: modelContext)
        guard let profile = try modelContext.fetch(FetchDescriptor<UserProfile>()).first,
              let state = try modelContext.fetch(FetchDescriptor<ProgramState>())
                .first(where: { $0.programId == SeedIdentifiers.program }),
              let bloodwork = try modelContext.fetch(FetchDescriptor<HealthCheckReminder>())
                .sorted(by: { $0.id.uuidString < $1.id.uuidString })
                .first else {
            throw UITestSessionFixtureError.missingSeededProgram
        }
        let now = Date.now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        profile.programStartDate = calendar.date(byAdding: .month, value: -3, to: now)!
        profile.updatedAt = now
        state.currentPhaseId = SeedIdentifiers.phase1
        state.trainingWeekIndex = 5
        state.deloadStatus = .active
        state.deloadReason = .scheduled
        state.deloadUpdatedAt = now
        state.updatedAt = now
        bloodwork.status = .pending
        bloodwork.dueDate = now.addingTimeInterval(-60)
        bloodwork.updatedAt = now

        modelContext.insert(
            WorkoutSession(
                id: todayPrioritySessionID,
                createdAt: now,
                updatedAt: now,
                date: now,
                status: .inProgress,
                workoutDayTemplateId: SeedIdentifiers.dayB,
                ohpSymptomResponse: .symptomsPresent,
                ohpSymptomCheckedAt: now
            )
        )
        modelContext.insert(
            AppReminder(
                id: todayMeasurementReminderID,
                createdAt: now,
                updatedAt: now,
                type: .measurement,
                schedule: "today-ui-test",
                message: "Bel ölçümünü kaydet",
                isEnabled: true
            )
        )
        try modelContext.save()
    }

    private static func installTrainingHistory(in modelContext: ModelContext) throws {
        guard let gobletSquat = try modelContext.fetch(FetchDescriptor<ExerciseTemplate>())
            .first(where: { $0.id == SeedIdentifiers.gobletSquat }) else {
            throw UITestSessionFixtureError.missingSeededProgram
        }
        let newestDate = Date.now.addingTimeInterval(-3_600)
        let newest = WorkoutSession(
            id: historyNewestSessionID,
            createdAt: newestDate,
            updatedAt: newestDate,
            date: newestDate,
            status: .completed,
            workoutDayTemplateId: SeedIdentifiers.dayA,
            perceivedRecovery: 8,
            note: "Kontrollü tamamlandı"
        )
        modelContext.insert(newest)
        modelContext.insert(
            SetLog(
                id: historyNewestSetID,
                createdAt: newestDate,
                updatedAt: newestDate,
                exerciseTemplateId: gobletSquat.id,
                setIndex: 1,
                weightKg: 10,
                reps: 8,
                rir: 2,
                completedAt: newestDate,
                workoutSession: newest
            )
        )

        let missingDate = newestDate.addingTimeInterval(-86_400)
        let missing = WorkoutSession(
            id: historyMissingSessionID,
            createdAt: missingDate,
            updatedAt: missingDate,
            date: missingDate,
            status: .completed,
            workoutDayTemplateId: historyMissingDayID
        )
        modelContext.insert(missing)
        modelContext.insert(
            SetLog(
                id: historyMissingSetID,
                createdAt: missingDate,
                updatedAt: missingDate,
                exerciseTemplateId: historyMissingExerciseID,
                setIndex: 1,
                reps: 7,
                completedAt: missingDate,
                workoutSession: missing
            )
        )
        try modelContext.save()
    }

    private static func installPhaseTransition(in modelContext: ModelContext) throws {
        guard let profile = try modelContext.fetch(FetchDescriptor<UserProfile>()).first,
              let state = try modelContext.fetch(FetchDescriptor<ProgramState>())
                .first(where: { $0.programId == SeedIdentifiers.program }) else {
            throw UITestSessionFixtureError.missingSeededProgram
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let now = Date.now
        let programStartDate = calendar.date(byAdding: .month, value: -3, to: now)!
        profile.programStartDate = programStartDate
        profile.updatedAt = now
        state.currentPhaseId = SeedIdentifiers.phase1
        state.phaseStartedAt = programStartDate
        state.updatedAt = now
        try modelContext.save()
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
        if !existingSessions.contains(where: { $0.id == progressionSessionID }) {
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
        }

        if !existingSessions.contains(where: { $0.id == progressionRotationSessionID }) {
            modelContext.insert(
                WorkoutSession(
                    id: progressionRotationSessionID,
                    createdAt: installedAt.addingTimeInterval(1),
                    updatedAt: installedAt.addingTimeInterval(1),
                    date: installedAt.addingTimeInterval(1),
                    status: .completed,
                    workoutDayTemplateId: SeedIdentifiers.dayC
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

    private static func installOHPSafety(in modelContext: ModelContext) throws {
        let existingSessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        guard !existingSessions.contains(where: { $0.id == ohpCurrentSessionID }) else {
            return
        }
        guard let programState = try modelContext.fetch(FetchDescriptor<ProgramState>())
            .first(where: { $0.id == SeedIdentifiers.programState }) else {
            throw UITestSessionFixtureError.missingSeededProgram
        }
        programState.trainingWeekIndex = 3
        programState.updatedAt = installedAt

        let priorDate = installedAt.addingTimeInterval(-7 * 24 * 60 * 60)
        let prior = WorkoutSession(
            id: ohpPriorSessionID,
            createdAt: priorDate,
            updatedAt: priorDate,
            date: priorDate,
            status: .completed,
            workoutDayTemplateId: SeedIdentifiers.dayB,
            ohpSymptomResponse: .notAsked
        )
        modelContext.insert(prior)
        for offset in 0..<3 {
            modelContext.insert(
                SetLog(
                    id: uuid(
                        String(
                            format: "00000000-0000-4000-8000-%012d",
                            90_053 + offset
                        )
                    ),
                    createdAt: priorDate,
                    updatedAt: priorDate,
                    exerciseTemplateId: SeedIdentifiers.dbOverheadPress,
                    setIndex: offset + 1,
                    weightKg: 10,
                    reps: 12,
                    rir: 1,
                    isWarmupSet: false,
                    completedAt: priorDate,
                    workoutSession: prior
                )
            )
        }

        modelContext.insert(
            WorkoutSession(
                id: ohpCurrentSessionID,
                createdAt: installedAt,
                updatedAt: installedAt,
                date: installedAt,
                status: .inProgress,
                workoutDayTemplateId: SeedIdentifiers.dayB
            )
        )
        modelContext.insert(
            WorkoutSessionProgress(
                id: ohpCurrentProgressID,
                createdAt: installedAt,
                updatedAt: installedAt,
                workoutSessionId: ohpCurrentSessionID,
                stage: .warmup,
                completedWarmupItemIdsData: WorkoutSessionProgressCodec.emptyPayload,
                completedCooldownItemIdsData: WorkoutSessionProgressCodec.emptyPayload,
                warmupDisposition: .pending,
                cooldownDisposition: .pending
            )
        )
        try modelContext.save()
    }

    private static func installDeload(
        scheduled: Bool,
        in modelContext: ModelContext
    ) throws {
        let markerID = scheduled
            ? deloadScheduledSessionID
            : deloadReactiveNewerSessionID
        let existingSessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        guard !existingSessions.contains(where: { $0.id == markerID }) else { return }
        guard let programState = try modelContext.fetch(FetchDescriptor<ProgramState>())
            .first(where: { $0.id == SeedIdentifiers.programState }) else {
            throw UITestSessionFixtureError.missingSeededProgram
        }

        programState.trainingWeekIndex = scheduled ? 5 : 6
        programState.deloadStatus = .none
        programState.deloadReason = nil
        programState.deloadUpdatedAt = nil
        programState.lastDeloadSkippedAt = nil
        programState.lastDeloadAction = nil
        programState.updatedAt = installedAt

        if scheduled {
            insertDeloadHistory(
                sessionID: deloadScheduledSessionID,
                setIDBase: 90_063,
                date: installedAt.addingTimeInterval(-7 * 24 * 60 * 60),
                reps: [10, 10, 10],
                in: modelContext
            )
        } else {
            insertDeloadHistory(
                sessionID: deloadReactiveOlderSessionID,
                setIDBase: 90_066,
                date: installedAt.addingTimeInterval(-14 * 24 * 60 * 60),
                reps: [10, 10, 10],
                in: modelContext
            )
            insertDeloadHistory(
                sessionID: deloadReactiveNewerSessionID,
                setIDBase: 90_069,
                date: installedAt.addingTimeInterval(-7 * 24 * 60 * 60),
                reps: [9, 9, 9],
                in: modelContext
            )
        }
        try modelContext.save()
    }

    private static func insertDeloadHistory(
        sessionID: UUID,
        setIDBase: Int,
        date: Date,
        reps: [Int],
        in modelContext: ModelContext
    ) {
        let session = WorkoutSession(
            id: sessionID,
            createdAt: date,
            updatedAt: date,
            date: date,
            status: .completed,
            workoutDayTemplateId: SeedIdentifiers.dayA
        )
        modelContext.insert(session)
        for (offset, repetitionCount) in reps.enumerated() {
            modelContext.insert(
                SetLog(
                    id: uuid(
                        String(
                            format: "00000000-0000-4000-8000-%012d",
                            setIDBase + offset
                        )
                    ),
                    createdAt: date,
                    updatedAt: date,
                    exerciseTemplateId: SeedIdentifiers.gobletSquat,
                    setIndex: offset + 1,
                    weightKg: 10,
                    reps: repetitionCount,
                    rir: 2,
                    isWarmupSet: false,
                    completedAt: date,
                    workoutSession: session
                )
            )
        }
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
    private let foundationInitialOutcome: InitialOutcome?
    private let todayInitialOutcome: InitialOutcome?
    private var foundationLoadAttempt = 0
    private var todayLoadAttempt = 0
    private var failsNextCurrentOHPSymptomWrite: Bool
    private var failsNextSessionDeletion: Bool
    private var currentSessionID: UUID?

    init(
        repository: any TrainingRepository,
        foundationInitialOutcome: InitialOutcome? = nil,
        todayInitialOutcome: InitialOutcome? = nil,
        failsFirstCurrentOHPSymptomWrite: Bool = false,
        failsFirstSessionDeletion: Bool = false
    ) {
        self.repository = repository
        self.foundationInitialOutcome = foundationInitialOutcome
        self.todayInitialOutcome = todayInitialOutcome
        failsNextCurrentOHPSymptomWrite = failsFirstCurrentOHPSymptomWrite
        failsNextSessionDeletion = failsFirstSessionDeletion
    }

    func fetchTodaySnapshot() async throws -> TodayRepositorySnapshot? {
        guard let todayInitialOutcome else {
            return try await repository.fetchTodaySnapshot()
        }
        todayLoadAttempt += 1
        if todayLoadAttempt == 1 {
            switch todayInitialOutcome {
            case .missingProgram:
                return nil
            case .repositoryError:
                throw UITestFoundationRepositoryError.initialLoad
            }
        }
        return try await repository.fetchTodaySnapshot()
    }

    func fetchUserProfile() async throws -> UserProfile? {
        guard let foundationInitialOutcome else {
            return try await repository.fetchUserProfile()
        }
        foundationLoadAttempt += 1
        if foundationLoadAttempt > 1 {
            try await Task.sleep(nanoseconds: 2_500_000_000)
        }
        if foundationLoadAttempt == 1, foundationInitialOutcome == .repositoryError {
            throw UITestFoundationRepositoryError.initialLoad
        }
        return try await repository.fetchUserProfile()
    }

    func fetchActiveProgram() async throws -> Program? {
        if foundationLoadAttempt == 1, foundationInitialOutcome == .missingProgram {
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
        let session = try await repository.fetchInProgressWorkoutSession()
        currentSessionID = session?.id
        return session
    }

    func transitionWorkoutSession(
        id: UUID,
        to status: WorkoutSessionStatus,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        let session = try await repository.transitionWorkoutSession(
            id: id,
            to: status,
            at: date
        )
        if status == .inProgress {
            currentSessionID = session.id
        } else if currentSessionID == id {
            currentSessionID = nil
        }
        return session
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

    func fetchOHPSafeAlternative() async throws -> SessionExerciseSnapshot {
        try await repository.fetchOHPSafeAlternative()
    }

    func updateWorkoutSessionOHPSymptomResponse(
        id: UUID,
        response: OHPSymptomResponse,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        if failsNextCurrentOHPSymptomWrite,
           response == .symptomsPresent,
           id == currentSessionID {
            failsNextCurrentOHPSymptomWrite = false
            throw UITestFoundationRepositoryError.ohpSymptomWrite
        }
        return try await repository.updateWorkoutSessionOHPSymptomResponse(
            id: id,
            response: response,
            at: date
        )
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
        if failsNextSessionDeletion, id == currentSessionID {
            failsNextSessionDeletion = false
            throw UITestFoundationRepositoryError.sessionDeletion
        }
        try await repository.deleteWorkoutSession(id: id)
        if currentSessionID == id {
            currentSessionID = nil
        }
    }
}

private enum UITestFoundationRepositoryError: Error {
    case initialLoad
    case ohpSymptomWrite
    case sessionDeletion
}
#endif
