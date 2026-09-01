import CoreModels
import DesignSystem
import Foundation
import HealthChecksKit
import MetricsKit
import NotificationsKit
import PersistenceKit
import ProgressPhotosKit
import ReportsKit
import SleepMoodKit
import SwiftData
import SwiftUI

typealias TrackerReportsRepositoryFactory = @MainActor (
    _ modelContext: ModelContext,
    _ calendar: Calendar
) -> any ReportsRepository & ReportsExportRepository

@MainActor
struct HealthCheckListNotificationActions {
    private let controller: HealthCheckNotificationAuthorizationController

    init(controller: HealthCheckNotificationAuthorizationController) {
        self.controller = controller
    }

    var authorizationState: HealthCheckNotificationAuthorizationState {
        controller.state
    }

    func onPresentation() {
        controller.beginPresentation()
    }

    func onDismissal() {
        controller.dismiss()
    }

    func onRequestNotificationAuthorization() async -> Bool {
        #if DEBUG
        if AppUITestLaunchConfiguration.resolve()?.scenario == .m3HealthChecks {
            AppUITestLaunchConfiguration.recordNotificationAuthorizationRequest()
        }
        #endif
        await controller.requestFromExplicitUserAction()
        return controller.state == .failed
    }
}

@MainActor
final class TrackerFeatureBundle: TrackerFeatureRouting {
    let repository: any MetricsRepository
    let lifestyleRepository: any LifestyleRepository
    let healthChecksRepository: any HealthChecksRepository
    let bloodworkRepository: any BloodworkRepository
    let progressPhotoRepository: any ProgressPhotoRepository
    let reportsRepository: any ReportsRepository & ReportsExportRepository
    let progressPhotoAssetSynchronizer: any CloudPhotoAssetSynchronizing
    let healthCheckNotificationComposition: HealthCheckNotificationComposition
    let bodyMetricViewModel: BodyMetricViewModel
    let postureViewModel: PostureViewModel
    let lifestyleViewModel: LifestyleViewModel
    let healthChecksViewModel: HealthChecksViewModel
    let bloodworkViewModel: BloodworkViewModel
    let progressPhotoImportViewModel: ProgressPhotoImportViewModel
    let progressPhotoGalleryViewModel: ProgressPhotoGalleryViewModel
    let reportsDashboardViewModel: ReportsDashboardViewModel
    let reportExportViewModel: ReportExportViewModel
    private let reportExportCoordinator: ReportExportCoordinator
    private let calendar: Calendar
    private let now: @MainActor () -> Date
    private let progressPhotoFixtureData: Data?
    private let broaderPhotoLibraryAccessState: PhotoLibraryAccessState

    init(
        metricsRepository: any MetricsRepository,
        lifestyleRepository: any LifestyleRepository,
        healthChecksRepository: any HealthChecksRepository,
        bloodworkRepository: any BloodworkRepository,
        progressPhotoRepository: any ProgressPhotoRepository = NoOpProgressPhotoRepository.shared,
        progressPhotoAssetSynchronizer: any CloudPhotoAssetSynchronizing = NoOpCloudPhotoAssetCoordinator.shared,
        reportsRepository: (any ReportsRepository & ReportsExportRepository)? = nil,
        reportExportPhotoProvider: (any ReportExportPhotoByteProviding)? = nil,
        progressPhotoFixtureData: Data? = nil,
        broaderPhotoLibraryAccessState: PhotoLibraryAccessState = .authorized,
        notificationCenter: any NotificationCenterClient =
            SystemNotificationCenterAdapter(),
        healthCheckNotificationComposition: HealthCheckNotificationComposition? = nil,
        calendar: Calendar,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        repository = metricsRepository
        self.lifestyleRepository = lifestyleRepository
        let notificationComposition: HealthCheckNotificationComposition
        if let healthCheckNotificationComposition {
            notificationComposition = healthCheckNotificationComposition
        } else {
            let reconciler = HealthCheckNotificationReconciler(
                center: notificationCenter
            )
            let authorization = HealthCheckNotificationAuthorizationController(
                center: notificationCenter
            )
            notificationComposition = HealthCheckNotificationComposition(
                repository: healthChecksRepository,
                reconciler: reconciler,
                authorizationController: authorization,
                notificationCenter: notificationCenter
            )
        }
        self.healthCheckNotificationComposition = notificationComposition
        let lifecycleCoordinator: HealthCheckNotificationLifecycleCoordinator =
            notificationComposition.lifecycleCoordinator
        let notificationRepository: NotificationReconcilingHealthChecksRepository =
            notificationComposition.healthChecksRepository
        _ = lifecycleCoordinator
        let resolvedHealthChecksRepository: any HealthChecksRepository
        if ObjectIdentifier(healthChecksRepository)
            == ObjectIdentifier(notificationComposition.repository) {
            resolvedHealthChecksRepository = notificationRepository
        } else {
            resolvedHealthChecksRepository = healthChecksRepository
        }
        self.healthChecksRepository = resolvedHealthChecksRepository
        self.bloodworkRepository = bloodworkRepository
        self.progressPhotoRepository = progressPhotoRepository
        let resolvedReportsRepository = reportsRepository
            ?? EmptyTrackerReportsRepository.shared
        self.reportsRepository = resolvedReportsRepository
        self.progressPhotoAssetSynchronizer = progressPhotoAssetSynchronizer
        self.progressPhotoFixtureData = progressPhotoFixtureData
        self.broaderPhotoLibraryAccessState = broaderPhotoLibraryAccessState
        self.calendar = calendar
        self.now = now
        let reportsDashboardViewModel = ReportsDashboardViewModel(
            repository: resolvedReportsRepository,
            calendar: calendar
        )
        self.reportsDashboardViewModel = reportsDashboardViewModel
        bodyMetricViewModel = BodyMetricViewModel(
            repository: metricsRepository,
            onCommittedEdit: {
                await reportsDashboardViewModel.load(referenceDate: now())
            }
        )
        postureViewModel = PostureViewModel(repository: metricsRepository)
        lifestyleViewModel = LifestyleViewModel(repository: lifestyleRepository)
        let healthChecksRepository = resolvedHealthChecksRepository
        healthChecksViewModel = HealthChecksViewModel(repository: healthChecksRepository)
        bloodworkViewModel = BloodworkViewModel(repository: bloodworkRepository)
        progressPhotoImportViewModel = ProgressPhotoImportViewModel(
            repository: progressPhotoRepository,
            date: now()
        )
        progressPhotoGalleryViewModel = ProgressPhotoGalleryViewModel(
            repository: progressPhotoRepository
        )
        let reportExportCoordinator = ReportExportCoordinator(
            repository: resolvedReportsRepository,
            photoProvider: reportExportPhotoProvider
                ?? ProgressPhotoReportExportProvider(repository: progressPhotoRepository)
        )
        self.reportExportCoordinator = reportExportCoordinator
        reportExportViewModel = ReportExportViewModel(
            generator: reportExportCoordinator,
            calendar: calendar
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
        let notificationActions = makeHealthCheckListNotificationActions(
            onCommittedMutation
        )
        return AnyView(
            HealthCheckListView(
                viewModel: healthChecksViewModel,
                calendar: calendar,
                now: now,
                onCommittedMutation: onCommittedMutation,
                onNotificationPermissionPresentation:
                    notificationActions.onPresentation,
                onNotificationPermissionDismissal:
                    notificationActions.onDismissal,
                onRequestNotificationAuthorization:
                    notificationActions.onRequestNotificationAuthorization,
                onClose: onClose
            )
        )
    }

    func makeHealthCheckListNotificationActions(
        _ onCommittedMutation: @escaping @MainActor () -> Void
    ) -> HealthCheckListNotificationActions {
        _ = onCommittedMutation
        return HealthCheckListNotificationActions(
            controller: healthCheckNotificationComposition.authorizationController
        )
    }

    func reconcileHealthCheckNotificationsAfterFirstMeaningfulTodayContent() async throws {
        _ = try await healthCheckNotificationComposition.lifecycleCoordinator
            .reconcileAfterFirstMeaningfulTodayContent()
    }

    func reconcileHealthCheckNotificationsAfterCommittedMutation() async throws {
        try await healthCheckNotificationComposition.lifecycleCoordinator
            .reconcileAfterHealthCheckMutation()
    }

    func requestHealthCheckNotificationAuthorizationFromExplicitUserAction() async {
        await healthCheckNotificationComposition.authorizationController
            .requestFromExplicitUserAction()
    }

    func refreshReports() async {
        await reportsDashboardViewModel.load(referenceDate: now())
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
                broaderPhotoLibraryAccessState: broaderPhotoLibraryAccessState,
                onClose: onClose
            )
        )
    }

    func makeProgressView(
        onOpenBodyMetric: @escaping @MainActor () -> Void,
        onOpenLifestyle: @escaping @MainActor () -> Void,
        onOpenPosture: @escaping @MainActor () -> Void,
        onOpenHealthChecks: @escaping @MainActor () -> Void,
        onOpenBloodwork: @escaping @MainActor () -> Void,
        onOpenProgressPhotos: @escaping @MainActor () -> Void,
        loadsReportsOnPresentation: Bool
    ) -> AnyView {
        AnyView(
            BodyMetricProgressView(viewModel: bodyMetricViewModel) {
                VStack(alignment: .leading, spacing: 24) {
                    ProgressTrackerQuickActions(
                        onOpenBodyMetric: onOpenBodyMetric,
                        onOpenLifestyle: onOpenLifestyle,
                        onOpenPosture: onOpenPosture,
                        onOpenHealthChecks: onOpenHealthChecks,
                        onOpenBloodwork: onOpenBloodwork,
                        onOpenProgressPhotos: onOpenProgressPhotos
                    )
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
                    TrackerReportsDashboardCompositionView(
                        dashboardViewModel: reportsDashboardViewModel,
                        exportViewModel: reportExportViewModel,
                        calendar: calendar,
                        referenceDate: now,
                        loadsReportsOnPresentation: loadsReportsOnPresentation
                    )
                }
            }
        )
    }

    func makeProgressView(
        onOpenBodyMetric: @escaping @MainActor () -> Void,
        onOpenLifestyle: @escaping @MainActor () -> Void,
        onOpenPosture: @escaping @MainActor () -> Void,
        onOpenHealthChecks: @escaping @MainActor () -> Void,
        onOpenBloodwork: @escaping @MainActor () -> Void,
        onOpenProgressPhotos: @escaping @MainActor () -> Void
    ) -> AnyView {
        makeProgressView(
            onOpenBodyMetric: onOpenBodyMetric,
            onOpenLifestyle: onOpenLifestyle,
            onOpenPosture: onOpenPosture,
            onOpenHealthChecks: onOpenHealthChecks,
            onOpenBloodwork: onOpenBloodwork,
            onOpenProgressPhotos: onOpenProgressPhotos,
            loadsReportsOnPresentation: true
        )
    }

    @discardableResult
    func reportShareDidFinish(artifactID: UUID, completed: Bool) -> Bool {
        guard reportExportViewModel.token?.id == artifactID else { return false }
        reportExportViewModel.shareDidFinish(completed: completed)
        return true
    }
}

@MainActor
private struct TrackerReportsDashboardCompositionView: View {
    @Bindable private var dashboardViewModel: ReportsDashboardViewModel
    @Bindable private var exportViewModel: ReportExportViewModel
    @State private var isExportPresented = false
    private let calendar: Calendar
    private let referenceDate: @MainActor () -> Date
    private let loadsReportsOnPresentation: Bool

    init(
        dashboardViewModel: ReportsDashboardViewModel,
        exportViewModel: ReportExportViewModel,
        calendar: Calendar,
        referenceDate: @escaping @MainActor () -> Date,
        loadsReportsOnPresentation: Bool
    ) {
        self.dashboardViewModel = dashboardViewModel
        self.exportViewModel = exportViewModel
        self.calendar = calendar
        self.referenceDate = referenceDate
        self.loadsReportsOnPresentation = loadsReportsOnPresentation
    }

    var body: some View {
        ReportsDashboardView(
            viewModel: dashboardViewModel,
            calendar: calendar,
            referenceDate: referenceDate,
            loadsOnPresentation: loadsReportsOnPresentation,
            onOpenExport: { isExportPresented = true }
        )
        .sheet(isPresented: $isExportPresented) {
            TrackerReportExportHostView(
                viewModel: exportViewModel,
                referenceDate: referenceDate
            )
        }
    }
}

@MainActor
private struct TrackerReportExportHostView: View {
    @Bindable private var viewModel: ReportExportViewModel
    @State private var shareRequest: TrackerReportShareRequest?
    private let referenceDate: @MainActor () -> Date

    init(
        viewModel: ReportExportViewModel,
        referenceDate: @escaping @MainActor () -> Date
    ) {
        self.viewModel = viewModel
        self.referenceDate = referenceDate
    }

    var body: some View {
        NavigationStack {
            ReportExportView(
                viewModel: viewModel,
                referenceDate: referenceDate,
                onShare: beginShare
            )
        }
        .sheet(item: $shareRequest) { request in
            SystemActivityView(
                activityItemURLs: request.urls,
                artifactID: request.id,
                accessibilityIdentifier: "reports.export.share.sheet"
            ) { artifactID, completed, _ in
                finishShare(artifactID: artifactID, completed: completed)
            } onPresentationFailure: { artifactID in
                finishShare(artifactID: artifactID, completed: false)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("reports.export.share.sheet")
        }
    }

    private func beginShare(_ urls: [URL]) {
        guard let token = viewModel.token,
              token.shareURLs == urls,
              !urls.isEmpty else {
            if let artifactID = viewModel.token?.id {
                finishShare(artifactID: artifactID, completed: false)
            }
            return
        }
        shareRequest = TrackerReportShareRequest(id: token.id, urls: urls)
    }

    private func finishShare(artifactID: UUID, completed: Bool) {
        guard viewModel.token?.id == artifactID else {
            if shareRequest?.id == artifactID { shareRequest = nil }
            return
        }
        viewModel.shareDidFinish(completed: completed)
        if shareRequest?.id == artifactID {
            shareRequest = nil
        }
    }
}

private struct TrackerReportShareRequest: Identifiable {
    let id: UUID
    let urls: [URL]
}

actor ProgressPhotoReportExportProvider: ReportExportPhotoByteProviding {
    private let repository: any ProgressPhotoRepository
    private var imageRefsByPhotoID: [UUID: String]?
    private var photoIDsMissingAfterRefresh: Set<UUID> = []

    init(repository: any ProgressPhotoRepository) {
        self.repository = repository
    }

    func jpegData(for photoID: UUID) async throws -> ReportExportPhotoPayloadV1 {
        guard let imageRef = try await imageRef(for: photoID) else {
            return .missing
        }
        switch try await repository.fullImage(assetID: imageRef) {
        case let .available(data): return .available(data)
        case .missing: return .missing
        case .corrupt: return .corrupt
        }
    }

    private func imageRef(for photoID: UUID) async throws -> String? {
        if let cached = imageRefsByPhotoID?[photoID] { return cached }
        if photoIDsMissingAfterRefresh.contains(photoID) { return nil }

        let index = try await fetchImageRefIndex()
        imageRefsByPhotoID = index
        guard let refreshed = index[photoID] else {
            photoIDsMissingAfterRefresh.insert(photoID)
            return nil
        }
        return refreshed
    }

    private func fetchImageRefIndex() async throws -> [UUID: String] {
        let photos = try await repository.fetchPhotos()
        return photos.reduce(into: [UUID: String]()) { index, photo in
            if index[photo.id] == nil { index[photo.id] = photo.imageRef }
        }
    }
}

@MainActor
private final class EmptyTrackerReportsRepository:
    ReportsRepository, ReportsExportRepository {
    static let shared = EmptyTrackerReportsRepository()

    private init() {}

    func fetchDashboardSource(
        in interval: ReportDateInterval
    ) async throws -> ReportsDashboardSource {
        _ = interval
        return ReportsDashboardSource()
    }

    func fetchExportSnapshot(
        in interval: ReportDateInterval,
        modules: Set<ExportModuleV1>
    ) async throws -> ExportSnapshotV1 {
        let tables = try ExportModuleV1.allCases.compactMap {
            module -> ExportTableV1? in
            guard modules.contains(module) else { return nil }
            return try ExportTableV1(
                module: module,
                columns: ExportSchemaV1.columns(for: module),
                rows: []
            )
        }
        return try ExportSnapshotV1(
            interval: interval,
            selectedModules: modules,
            tables: tables
        )
    }
}

@MainActor
private struct ProgressTrackerQuickActions: View {
    let onOpenBodyMetric: @MainActor () -> Void
    let onOpenLifestyle: @MainActor () -> Void
    let onOpenPosture: @MainActor () -> Void
    let onOpenHealthChecks: @MainActor () -> Void
    let onOpenBloodwork: @MainActor () -> Void
    let onOpenProgressPhotos: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            Text(localized("progress.quick-actions.heading"))
                .font(AppTypography.titleMedium)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            quickAction(
                "progress.metrics.action",
                systemImage: "scalemass",
                action: onOpenBodyMetric
            )
            .accessibilityIdentifier("progress.metrics.action")
            quickAction(
                "progress.lifestyle.action",
                systemImage: "bed.double",
                action: onOpenLifestyle
            )
            .accessibilityIdentifier("progress.lifestyle.action")
            quickAction(
                "progress.posture.action",
                systemImage: "figure.stand",
                action: onOpenPosture
            )
            .accessibilityIdentifier("progress.posture.action")
            quickAction(
                "progress.health-check.action",
                systemImage: "cross.case.fill",
                action: onOpenHealthChecks
            )
            .accessibilityIdentifier("progress.health-check.action")
            quickAction(
                "progress.bloodwork.action",
                systemImage: "testtube.2",
                action: onOpenBloodwork
            )
            .accessibilityIdentifier("progress.bloodwork.action")
            quickAction(
                "progress.photos.action",
                systemImage: "photo.stack",
                action: onOpenProgressPhotos
            )
            .accessibilityIdentifier("progress.photos.action")
        }
    }

    private func quickAction(
        _ titleKey: String.LocalizationValue,
        systemImage: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Label(localized(titleKey), systemImage: systemImage)
                .font(AppTypography.label)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }
}

@MainActor
enum DefaultTrackerFeatureFactory {
    static func make(
        environment: AppEnvironment,
        modelContext: ModelContext,
        makeReportsRepository: TrackerReportsRepositoryFactory =
            DefaultTrackerFeatureFactory.defaultReportsRepository,
        healthCheckNotificationCenter: any NotificationCenterClient =
            SystemNotificationCenterAdapter(),
        healthCheckNotificationComposition: HealthCheckNotificationComposition? = nil
    ) -> any TrackerFeatureRouting {
        let calendar = AppDomainContext.makeCalendar()
        let now: @MainActor () -> Date = { AppDomainContext.now() }
        let metricsRepository = SwiftDataMetricsRepository(modelContext: modelContext)
        let lifestyleRepository = SwiftDataLifestyleRepository(modelContext: modelContext)
        let baseHealthChecksRepository = SwiftDataHealthChecksRepository(
            modelContext: modelContext,
            calendar: calendar,
            now: now
        )
        let resolvedHealthCheckNotificationComposition =
            healthCheckNotificationComposition
            ?? HealthCheckNotificationComposition(
                repository: baseHealthChecksRepository,
                notificationCenter: healthCheckNotificationCenter,
                now: { .now }
            )
        let healthChecksRepository = resolvedHealthCheckNotificationComposition
            .healthChecksRepository
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
        let reportsRepository = makeReportsRepository(modelContext, calendar)
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
                    reportsRepository: reportsRepository,
                    healthCheckNotificationComposition:
                        resolvedHealthCheckNotificationComposition,
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
                    reportsRepository: reportsRepository,
                    healthCheckNotificationComposition:
                        resolvedHealthCheckNotificationComposition,
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
                    reportsRepository: reportsRepository,
                    healthCheckNotificationComposition:
                        resolvedHealthCheckNotificationComposition,
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
                    reportsRepository: UITestReportsRepository(
                        repository: reportsRepository
                    ),
                    healthCheckNotificationComposition:
                        resolvedHealthCheckNotificationComposition,
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
                    reportsRepository: reportsRepository,
                    healthCheckNotificationComposition:
                        resolvedHealthCheckNotificationComposition,
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
                    reportsRepository: reportsRepository,
                    progressPhotoFixtureData: Data(
                        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2Z7sAAAAASUVORK5CYII="
                    ),
                    broaderPhotoLibraryAccessState:
                        AppUITestLaunchConfiguration.resolve()?
                            .broaderPhotoLibraryAccessState ?? .authorized,
                    healthCheckNotificationComposition:
                        resolvedHealthCheckNotificationComposition,
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
                    reportsRepository: reportsRepository,
                    healthCheckNotificationComposition:
                        resolvedHealthCheckNotificationComposition,
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
            reportsRepository: reportsRepository,
            healthCheckNotificationComposition:
                resolvedHealthCheckNotificationComposition,
            calendar: calendar,
            now: now
        )
    }

    static func defaultReportsRepository(
        modelContext: ModelContext,
        calendar: Calendar
    ) -> any ReportsRepository & ReportsExportRepository {
        SwiftDataReportsRepository(modelContext: modelContext, calendar: calendar)
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
private final class UITestReportsRepository:
    ReportsRepository, ReportsExportRepository {
    private let repository: any ReportsRepository & ReportsExportRepository

    init(repository: any ReportsRepository & ReportsExportRepository) {
        self.repository = repository
    }

    func fetchDashboardSource(
        in interval: ReportDateInterval
    ) async throws -> ReportsDashboardSource {
        AppUITestLaunchConfiguration.recordReportsDashboardFetch()
        return try await repository.fetchDashboardSource(in: interval)
    }

    func fetchExportSnapshot(
        in interval: ReportDateInterval,
        modules: Set<ExportModuleV1>
    ) async throws -> ExportSnapshotV1 {
        try await repository.fetchExportSnapshot(
            in: interval,
            modules: modules
        )
    }
}
#endif

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
