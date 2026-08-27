import CoreModels
import Foundation
import HealthChecksKit
import MetricsKit
import PersistenceKit
import ProgressPhotosKit
import SleepMoodKit
import SwiftData
import SwiftUI

@MainActor
final class TrackerFeatureBundle: TrackerFeatureRouting {
    let repository: any MetricsRepository
    let lifestyleRepository: any LifestyleRepository
    let healthChecksRepository: any HealthChecksRepository
    let bloodworkRepository: any BloodworkRepository
    let progressPhotoRepository: any ProgressPhotoRepository
    let progressPhotoAssetSynchronizer: any CloudPhotoAssetSynchronizing
    let bodyMetricViewModel: BodyMetricViewModel
    let postureViewModel: PostureViewModel
    let lifestyleViewModel: LifestyleViewModel
    let healthChecksViewModel: HealthChecksViewModel
    let bloodworkViewModel: BloodworkViewModel
    let progressPhotoImportViewModel: ProgressPhotoImportViewModel
    let progressPhotoGalleryViewModel: ProgressPhotoGalleryViewModel
    private let calendar: Calendar
    private let now: @MainActor () -> Date
    private let progressPhotoFixtureData: Data?

    init(
        metricsRepository: any MetricsRepository,
        lifestyleRepository: any LifestyleRepository,
        healthChecksRepository: any HealthChecksRepository,
        bloodworkRepository: any BloodworkRepository,
        progressPhotoRepository: any ProgressPhotoRepository = NoOpProgressPhotoRepository.shared,
        progressPhotoAssetSynchronizer: any CloudPhotoAssetSynchronizing = NoOpCloudPhotoAssetCoordinator.shared,
        progressPhotoFixtureData: Data? = nil,
        calendar: Calendar,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        repository = metricsRepository
        self.lifestyleRepository = lifestyleRepository
        self.healthChecksRepository = healthChecksRepository
        self.bloodworkRepository = bloodworkRepository
        self.progressPhotoRepository = progressPhotoRepository
        self.progressPhotoAssetSynchronizer = progressPhotoAssetSynchronizer
        self.progressPhotoFixtureData = progressPhotoFixtureData
        self.calendar = calendar
        self.now = now
        bodyMetricViewModel = BodyMetricViewModel(repository: metricsRepository)
        postureViewModel = PostureViewModel(repository: metricsRepository)
        lifestyleViewModel = LifestyleViewModel(repository: lifestyleRepository)
        healthChecksViewModel = HealthChecksViewModel(repository: healthChecksRepository)
        bloodworkViewModel = BloodworkViewModel(repository: bloodworkRepository)
        progressPhotoImportViewModel = ProgressPhotoImportViewModel(
            repository: progressPhotoRepository,
            date: now()
        )
        progressPhotoGalleryViewModel = ProgressPhotoGalleryViewModel(
            repository: progressPhotoRepository
        )
    }

    func makeBodyMetricEntryView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView {
        AnyView(
            BodyMetricEntryView(
                viewModel: bodyMetricViewModel,
                onClose: onClose
            )
        )
    }

    func makeLifestyleEntryView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView {
        AnyView(
            LifestyleEntryView(
                viewModel: lifestyleViewModel,
                initialDate: now(),
                onClose: onClose
            )
        )
    }

    func makePostureEntryView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView {
        AnyView(
            PostureEntryView(
                viewModel: postureViewModel,
                initialDate: now(),
                onClose: onClose
            )
        )
    }

    func makeHealthCheckListView(
        onCommittedMutation: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView {
        AnyView(
            HealthCheckListView(
                viewModel: healthChecksViewModel,
                calendar: calendar,
                now: now,
                onCommittedMutation: onCommittedMutation,
                onClose: onClose
            )
        )
    }

    func makeBloodworkListView(
        onCommittedMutation: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView {
        AnyView(
            BloodworkListView(
                viewModel: bloodworkViewModel,
                now: now,
                onCommittedMutation: onCommittedMutation,
                onClose: onClose
            )
        )
    }

    func makeProgressPhotoLifecycleView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView {
        AnyView(
            ProgressPhotoLifecycleView(
                viewModel: progressPhotoImportViewModel,
                galleryViewModel: progressPhotoGalleryViewModel,
                assetSynchronizer: progressPhotoAssetSynchronizer,
                fixtureImageData: progressPhotoFixtureData,
                onClose: onClose
            )
        )
    }

    func makeProgressView(
        onOpenBloodwork: @escaping @MainActor () -> Void,
        onOpenProgressPhotos: @escaping @MainActor () -> Void
    ) -> AnyView {
        AnyView(
            BodyMetricProgressView(viewModel: bodyMetricViewModel) {
                VStack(alignment: .leading, spacing: 24) {
                    ProgressPhotoAccessButton(action: onOpenProgressPhotos)
                    LifestyleProgressSection(
                        viewModel: lifestyleViewModel,
                        date: now()
                    )
                    PostureProgressSection(viewModel: postureViewModel)
                    HealthCheckProgressSection(
                        viewModel: healthChecksViewModel,
                        calendar: calendar,
                        now: now,
                        onOpenBloodwork: onOpenBloodwork
                    )
                }
            }
        )
    }
}

@MainActor
enum DefaultTrackerFeatureFactory {
    static func make(
        environment: AppEnvironment,
        modelContext: ModelContext
    ) -> any TrackerFeatureRouting {
        let calendar = AppDomainContext.makeCalendar()
        let now: @MainActor () -> Date = { AppDomainContext.now() }
        let metricsRepository = SwiftDataMetricsRepository(modelContext: modelContext)
        let lifestyleRepository = SwiftDataLifestyleRepository(modelContext: modelContext)
        let healthChecksRepository = SwiftDataHealthChecksRepository(
            modelContext: modelContext,
            calendar: calendar,
            now: now
        )
        let bloodworkRepository = SwiftDataBloodworkRepository(
            modelContext: modelContext,
            now: now
        )
        let progressPhotoAssetStore = LocalPhotoAssetStore(
            processor: ImageIOPhotoImageProcessor()
        )
        let progressPhotoCloudRoot: URL
        switch environment {
        case let .local(storeURL), let .cloud(_, storeURL):
            progressPhotoCloudRoot = storeURL.deletingLastPathComponent()
                .appendingPathComponent("ProgressPhotos", isDirectory: true)
                .appendingPathComponent("CloudSync", isDirectory: true)
        case .uiTesting:
            progressPhotoCloudRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "FOApp-ProgressPhotoCloudSync-\(ProcessInfo.processInfo.processIdentifier)",
                    isDirectory: true
                )
        }
        let cloudHandshakeStores: (
            deletion: any CloudPhotoAssetDeletionIntentStoring,
            inbound: any CloudPhotoAssetInboundJournaling
        ) = {
            guard case .cloud = environment else {
                return (
                    NoOpCloudPhotoAssetDeletionIntentStore.shared,
                    NoOpCloudPhotoAssetInboundJournal.shared
                )
            }
            let deletionIntentStore = FileCloudPhotoAssetDeletionIntentStore(
                fileURL: progressPhotoCloudRoot.appendingPathComponent("deletions.json")
            )
            let inboundAssetJournal = FileCloudPhotoAssetInboundJournal(
                fileURL: progressPhotoCloudRoot.appendingPathComponent("inbound.json")
            )
            return (deletionIntentStore, inboundAssetJournal)
        }()
        let deletionIntentStore = cloudHandshakeStores.deletion
        let inboundAssetJournal = cloudHandshakeStores.inbound
        let cloudPhotoAssetTransferStore = FileCloudPhotoAssetTemporaryStore(
            directory: progressPhotoCloudRoot.appendingPathComponent(
                "Transfers",
                isDirectory: true
            )
        )
        let progressPhotoRepository = SwiftDataProgressPhotoRepository(
            modelContext: modelContext,
            assetStore: progressPhotoAssetStore,
            cleanupJournal: FilePhotoAssetCleanupJournal(),
            deletionIntentStore: deletionIntentStore,
            inboundAssetJournal: inboundAssetJournal,
            inboundAssetStore: progressPhotoAssetStore,
            now: now
        )
        let progressPhotoAssetSynchronizer = makeProgressPhotoAssetSynchronizer(
            environment: environment,
            assetStore: progressPhotoAssetStore,
            progressPhotoRepository: progressPhotoRepository,
            cloudDeletionIntents: deletionIntentStore,
            transferStore: cloudPhotoAssetTransferStore
        )
        #if DEBUG
        if environment == .uiTesting,
           let scenario = AppUITestLaunchConfiguration.resolve()?.scenario {
            if scenario == .m3BodyMetrics {
                return TrackerFeatureBundle(
                    metricsRepository: UITestMetricsRepository(
                        repository: metricsRepository,
                        failsFirstCreate: true
                    ),
                    lifestyleRepository: lifestyleRepository,
                    healthChecksRepository: healthChecksRepository,
                    bloodworkRepository: bloodworkRepository,
                    calendar: calendar,
                    now: now
                )
            }
            if scenario == .m3SleepMood {
                return TrackerFeatureBundle(
                    metricsRepository: metricsRepository,
                    lifestyleRepository: UITestLifestyleRepository(
                        repository: lifestyleRepository,
                        failsFirstUpsert: true
                    ),
                    healthChecksRepository: healthChecksRepository,
                    bloodworkRepository: bloodworkRepository,
                    calendar: calendar,
                    now: now
                )
            }
            if scenario == .m3Posture {
                return TrackerFeatureBundle(
                    metricsRepository: UITestMetricsRepository(
                        repository: metricsRepository,
                        failsFirstCreate: false,
                        failsFirstPostureCreate: true
                    ),
                    lifestyleRepository: lifestyleRepository,
                    healthChecksRepository: healthChecksRepository,
                    bloodworkRepository: bloodworkRepository,
                    calendar: calendar,
                    now: now
                )
            }
            if scenario == .m3HealthChecks {
                return TrackerFeatureBundle(
                    metricsRepository: metricsRepository,
                    lifestyleRepository: lifestyleRepository,
                    healthChecksRepository: UITestHealthChecksRepository(
                        repository: healthChecksRepository,
                        failsFirstCompletion: true
                    ),
                    bloodworkRepository: bloodworkRepository,
                    calendar: calendar,
                    now: now
                )
            }
            if scenario == .m3Bloodwork {
                return TrackerFeatureBundle(
                    metricsRepository: metricsRepository,
                    lifestyleRepository: lifestyleRepository,
                    healthChecksRepository: UITestHealthChecksRepository(
                        repository: healthChecksRepository,
                        failsFirstLoad: true,
                        failsFirstCompletion: false
                    ),
                    bloodworkRepository: UITestBloodworkRepository(
                        repository: bloodworkRepository,
                        failsFirstLoad: true,
                        failsFirstCreate: true
                    ),
                    calendar: calendar,
                    now: now
                )
            }
            if scenario == .m3ProgressPhotos {
                return TrackerFeatureBundle(
                    metricsRepository: metricsRepository,
                    lifestyleRepository: lifestyleRepository,
                    healthChecksRepository: healthChecksRepository,
                    bloodworkRepository: bloodworkRepository,
                    progressPhotoRepository: progressPhotoRepository,
                    progressPhotoFixtureData: Data(
                        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2Z7sAAAAASUVORK5CYII="
                    ),
                    calendar: calendar,
                    now: now
                )
            }
            if scenario == .m3PhotoGallery {
                return TrackerFeatureBundle(
                    metricsRepository: metricsRepository,
                    lifestyleRepository: lifestyleRepository,
                    healthChecksRepository: healthChecksRepository,
                    bloodworkRepository: bloodworkRepository,
                    progressPhotoRepository: UITestProgressPhotoGalleryRepository(),
                    calendar: calendar,
                    now: now
                )
            }
        }
        #endif
        return TrackerFeatureBundle(
            metricsRepository: metricsRepository,
            lifestyleRepository: lifestyleRepository,
            healthChecksRepository: healthChecksRepository,
            bloodworkRepository: bloodworkRepository,
            progressPhotoRepository: progressPhotoRepository,
            progressPhotoAssetSynchronizer: progressPhotoAssetSynchronizer,
            calendar: calendar,
            now: now
        )
    }

    private static func makeProgressPhotoAssetSynchronizer(
        environment: AppEnvironment,
        assetStore: LocalPhotoAssetStore,
        progressPhotoRepository: any CloudPhotoAssetReferenceSnapshotProviding & CloudPhotoAssetInboundApplying,
        cloudDeletionIntents deletionIntentStore: any CloudPhotoAssetDeletionIntentStoring,
        transferStore cloudPhotoAssetTransferStore: FileCloudPhotoAssetTemporaryStore
    ) -> any CloudPhotoAssetSynchronizing {
        guard case let .cloud(containerIdentifier, storeURL) = environment else {
            return NoOpCloudPhotoAssetCoordinator.shared
        }
        let root = storeURL.deletingLastPathComponent()
            .appendingPathComponent("ProgressPhotos", isDirectory: true)
            .appendingPathComponent("CloudSync", isDirectory: true)
        return CloudPhotoAssetCoordinator(
            database: CloudKitPrivatePhotoAssetDatabase(
                containerIdentifier: containerIdentifier,
                downloadStore: cloudPhotoAssetTransferStore
            ),
            localStore: assetStore,
            stateStore: FileCloudPhotoAssetSyncStateStore(
                fileURL: root.appendingPathComponent("state.json")
            ),
            referenceSnapshotProvider: progressPhotoRepository,
            deletionIntentStore: deletionIntentStore,
            inboundAssetApplier: progressPhotoRepository,
            temporaryStore: cloudPhotoAssetTransferStore
        )
    }
}

#if DEBUG
@MainActor
private final class UITestProgressPhotoGalleryRepository:
    ProgressPhotoRepository {
    private enum FixtureFailure: Error {
        case unsupportedImport
    }

    private var photos: [ProgressPhotoSnapshot]
    private let thumbnails: [String: PhotoAssetLoadResult]

    var pendingAssetCleanupIDs: [String] { [] }

    init() {
        let availableBytes = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2Z7sAAAAASUVORK5CYII="
        )!
        let comparisonDate = Date(timeIntervalSince1970: 6_000)
        let missingDate = Date(timeIntervalSince1970: 5_000)
        let corruptDate = Date(timeIntervalSince1970: 4_000)
        photos = [
            Self.snapshot(
                id: "00000000-0000-0000-0000-000000000201",
                assetID: "00000000-0000-0000-0000-000000000301",
                date: comparisonDate,
                pose: .front
            ),
            Self.snapshot(
                id: "00000000-0000-0000-0000-000000000202",
                assetID: "00000000-0000-0000-0000-000000000302",
                date: comparisonDate,
                pose: .side
            ),
            Self.snapshot(
                id: "00000000-0000-0000-0000-000000000203",
                assetID: "00000000-0000-0000-0000-000000000303",
                date: comparisonDate,
                pose: .back
            ),
            Self.snapshot(
                id: "00000000-0000-0000-0000-000000000204",
                assetID: "00000000-0000-0000-0000-000000000304",
                date: missingDate,
                pose: .front
            ),
            Self.snapshot(
                id: "00000000-0000-0000-0000-000000000205",
                assetID: "00000000-0000-0000-0000-000000000305",
                date: corruptDate,
                pose: .side
            ),
        ]
        thumbnails = [
            "00000000-0000-0000-0000-000000000301": .available(availableBytes),
            "00000000-0000-0000-0000-000000000302": .available(availableBytes),
            "00000000-0000-0000-0000-000000000303": .available(availableBytes),
            "00000000-0000-0000-0000-000000000304": .missing,
            "00000000-0000-0000-0000-000000000305": .corrupt,
        ]
    }

    func fetchPhotos() async throws -> [ProgressPhotoSnapshot] {
        photos
    }

    func importPhoto(
        _ input: ProgressPhotoInput,
        bytes: Data
    ) async throws -> ProgressPhotoSnapshot {
        _ = input
        _ = bytes
        throw FixtureFailure.unsupportedImport
    }

    func thumbnail(assetID: String) async throws -> PhotoAssetLoadResult {
        thumbnails[assetID] ?? .missing
    }

    func fullImage(assetID: String) async throws -> PhotoAssetLoadResult {
        thumbnails[assetID] ?? .missing
    }

    func deletePhoto(id: UUID, expectedUpdatedAt: Date) async throws {
        photos.removeAll { snapshot in
            snapshot.id == id && snapshot.updatedAt == expectedUpdatedAt
        }
    }

    func retryPendingAssetCleanup() async throws {}

    private static func snapshot(
        id: String,
        assetID: String,
        date: Date,
        pose: ProgressPhotoPose
    ) -> ProgressPhotoSnapshot {
        ProgressPhotoSnapshot(
            id: UUID(uuidString: id)!,
            createdAt: date,
            updatedAt: date,
            date: date,
            imageRef: assetID,
            pose: pose,
            note: nil
        )
    }
}
#endif

#if DEBUG
@MainActor
private final class UITestLifestyleRepository: LifestyleRepository {
    private enum FixtureFailure: Error {
        case upsert
    }

    private let repository: any LifestyleRepository
    private var failsNextUpsert: Bool

    init(
        repository: any LifestyleRepository,
        failsFirstUpsert: Bool
    ) {
        self.repository = repository
        failsNextUpsert = failsFirstUpsert
    }

    func fetchLifestyleDay(containing date: Date) async throws -> LifestyleDaySnapshot {
        try await repository.fetchLifestyleDay(containing: date)
    }

    func upsertLifestyleDay(
        _ input: LifestyleDayInput,
        expected: LifestyleDaySnapshot
    ) async throws -> LifestyleDaySnapshot {
        if failsNextUpsert {
            failsNextUpsert = false
            throw FixtureFailure.upsert
        }
        return try await repository.upsertLifestyleDay(input, expected: expected)
    }
}
#endif

#if DEBUG
@MainActor
private final class UITestHealthChecksRepository: HealthChecksRepository {
    private enum FixtureFailure: Error {
        case load
        case completion
    }

    private let repository: any HealthChecksRepository
    private var failsNextLoad: Bool
    private var failsNextCompletion: Bool

    init(
        repository: any HealthChecksRepository,
        failsFirstLoad: Bool = false,
        failsFirstCompletion: Bool
    ) {
        self.repository = repository
        failsNextLoad = failsFirstLoad
        failsNextCompletion = failsFirstCompletion
    }

    func fetchReminders() async throws -> [HealthCheckReminderSnapshot] {
        if failsNextLoad {
            failsNextLoad = false
            throw FixtureFailure.load
        }
        return try await repository.fetchReminders()
    }

    func createReminder(
        _ input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot {
        try await repository.createReminder(input)
    }

    func updateReminder(
        id: UUID,
        expectedUpdatedAt: Date,
        input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot {
        try await repository.updateReminder(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt,
            input: input
        )
    }

    func deleteReminder(id: UUID, expectedUpdatedAt: Date) async throws {
        try await repository.deleteReminder(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt
        )
    }

    func completeReminder(
        id: UUID,
        expectedUpdatedAt: Date
    ) async throws -> HealthCheckCompletionMutation {
        if failsNextCompletion {
            failsNextCompletion = false
            throw FixtureFailure.completion
        }
        return try await repository.completeReminder(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt
        )
    }

    func undoCompletion(
        _ token: HealthCheckCompletionUndoToken
    ) async throws -> HealthCheckReminderSnapshot {
        try await repository.undoCompletion(token)
    }
}
#endif

#if DEBUG
@MainActor
private final class UITestBloodworkRepository: BloodworkRepository {
    private enum FixtureFailure: Error {
        case load
        case create
    }

    private let repository: any BloodworkRepository
    private var failsNextLoad: Bool
    private var failsNextCreate: Bool

    init(
        repository: any BloodworkRepository,
        failsFirstLoad: Bool,
        failsFirstCreate: Bool
    ) {
        self.repository = repository
        failsNextLoad = failsFirstLoad
        failsNextCreate = failsFirstCreate
    }

    func fetchResults() async throws -> [BloodworkResultSnapshot] {
        if failsNextLoad {
            failsNextLoad = false
            throw FixtureFailure.load
        }
        return try await repository.fetchResults()
    }

    func createResult(
        _ input: BloodworkResultInput
    ) async throws -> BloodworkCreationMutation {
        if failsNextCreate {
            failsNextCreate = false
            throw FixtureFailure.create
        }
        return try await repository.createResult(input)
    }

    func updateResult(
        id: UUID,
        expectedUpdatedAt: Date,
        input: BloodworkResultInput
    ) async throws -> BloodworkResultSnapshot {
        try await repository.updateResult(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt,
            input: input
        )
    }

    func deleteResult(id: UUID, expectedUpdatedAt: Date) async throws {
        try await repository.deleteResult(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt
        )
    }

    func undoResultCreation(_ token: BloodworkCreationUndoToken) async throws {
        try await repository.undoResultCreation(token)
    }
}
#endif

#if DEBUG
@MainActor
private final class UITestMetricsRepository: MetricsRepository {
    private enum FixtureFailure: Error {
        case create
    }

    private let repository: any MetricsRepository
    private var failsNextCreate: Bool
    private var failsNextPostureCreate: Bool

    init(
        repository: any MetricsRepository,
        failsFirstCreate: Bool,
        failsFirstPostureCreate: Bool = false
    ) {
        self.repository = repository
        failsNextCreate = failsFirstCreate
        failsNextPostureCreate = failsFirstPostureCreate
    }

    func fetchPostureMetrics() async throws -> [PostureMetricSnapshot] {
        try await repository.fetchPostureMetrics()
    }

    func createPostureMetric(
        _ input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        if failsNextPostureCreate {
            failsNextPostureCreate = false
            throw FixtureFailure.create
        }
        return try await repository.createPostureMetric(input)
    }

    func updatePostureMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        try await repository.updatePostureMetric(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt,
            input: input
        )
    }

    func deletePostureMetric(id: UUID, expectedUpdatedAt: Date) async throws {
        try await repository.deletePostureMetric(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt
        )
    }

    func upsertPostureMetric(
        id: UUID,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        try await repository.upsertPostureMetric(id: id, input: input)
    }

    func fetchBodyMetrics() async throws -> [BodyMetricSnapshot] {
        try await repository.fetchBodyMetrics()
    }

    func createBodyMetrics(
        _ input: BodyMetricBatchInput
    ) async throws -> BodyMetricCreationMutation {
        if failsNextCreate {
            failsNextCreate = false
            throw FixtureFailure.create
        }
        return try await repository.createBodyMetrics(input)
    }

    func updateBodyMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        date: Date,
        value: BodyMetricValueInput
    ) async throws -> BodyMetricSnapshot {
        try await repository.updateBodyMetric(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt,
            date: date,
            value: value
        )
    }

    func deleteBodyMetric(id: UUID, expectedUpdatedAt: Date) async throws {
        try await repository.deleteBodyMetric(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt
        )
    }

    func undoBodyMetricCreation(
        _ token: BodyMetricCreationUndoToken
    ) async throws {
        try await repository.undoBodyMetricCreation(token)
    }
}
#endif
