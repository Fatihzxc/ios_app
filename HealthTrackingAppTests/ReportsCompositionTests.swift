@testable import DesignSystem
@testable import HealthTrackingApp
@testable import ReportsKit
import CoreModels
import Foundation
import HealthChecksKit
import MetricsKit
import ProgressPhotosKit
import SwiftData
import SwiftUI
import TrainingKit
import XCTest

@MainActor
final class ReportsCompositionTests: XCTestCase {
    func testUncachedFirstProgressPresentationConstructsOneRepositoryAndFetchesExactlyOnce() async throws {
        let reportsRepository = CompositionReportsRepositoryStub()
        var reportRepositoryConstructions = 0
        let runtime = AppBootstrapRuntime(
            resolveEnvironment: { .uiTesting },
            makeDependencies: { environment in
                try AppDependencies(
                    environment: environment,
                    makeReportsRepository: { _, _ in
                        reportRepositoryConstructions += 1
                        return reportsRepository
                    }
                )
            }
        )

        XCTAssertEqual(reportRepositoryConstructions, 0)
        await runtime.model.loadIfNeeded()
        XCTAssertEqual(runtime.model.state, .content)
        XCTAssertEqual(reportRepositoryConstructions, 0, "Bootstrap and initial content load must stay report-cold.")

        let dependencies = try XCTUnwrap(runtime.dependencies as? AppDependencies)
        _ = TodayView(
            viewModel: dependencies.todayViewModel,
            nutritionState: dependencies.todayNutritionViewModel.state
        )
        _ = makeRoot(dependencies)
        XCTAssertEqual(reportRepositoryConstructions, 0, "Today and root construction must not resolve Progress.")

        var firstSelectionPolicy = ProgressReportsLoadPolicy()
        XCTAssertEqual(
            firstSelectionPolicy.transition(
                from: .today,
                to: .training,
                routerIsResolved: false
            ),
            .none
        )
        XCTAssertTrue(firstSelectionPolicy.loadsReportsOnPresentation)
        XCTAssertEqual(
            firstSelectionPolicy.transition(
                from: .training,
                to: .progress,
                routerIsResolved: false
            ),
            .ensureRouter
        )
        XCTAssertTrue(firstSelectionPolicy.loadsReportsOnPresentation)

        let firstProgressRoute = dependencies.makeTrackerFeatureRouter()
        XCTAssertEqual(reportRepositoryConstructions, 1)
        let repeatedProgressRoute = dependencies.makeTrackerFeatureRouter()
        XCTAssertEqual(reportRepositoryConstructions, 1)
        XCTAssertTrue(firstProgressRoute === repeatedProgressRoute)

        let bundle = try XCTUnwrap(firstProgressRoute as? TrackerFeatureBundle)
        XCTAssertTrue((bundle.reportsRepository as AnyObject) === reportsRepository)
        await bundle.reportsDashboardViewModel.load(
            referenceDate: Date(timeIntervalSince1970: 1_706_745_600)
        )
        XCTAssertEqual(reportsRepository.dashboardFetchCount, 1)
        XCTAssertEqual(reportRepositoryConstructions, 1)

        _ = bundle.makeProgressView(
            onOpenBodyMetric: {},
            onOpenLifestyle: {},
            onOpenPosture: {},
            onOpenHealthChecks: {},
            onOpenBloodwork: {},
            onOpenProgressPhotos: {}
        )
        _ = bundle.makeProgressView(
            onOpenBodyMetric: {},
            onOpenLifestyle: {},
            onOpenPosture: {},
            onOpenHealthChecks: {},
            onOpenBloodwork: {},
            onOpenProgressPhotos: {}
        )
        XCTAssertEqual(reportRepositoryConstructions, 1, "SwiftUI rerenders must reuse the cached bundle capability.")
        XCTAssertEqual(
            reportsRepository.dashboardFetchCount,
            1,
            "Repeated Progress view construction must not itself trigger another report fetch."
        )
    }

    func testCachedBundleRefreshPublishesLatestSourceWithoutConstructingAnotherRepository() async throws {
        let firstSource = ReportsDashboardSource(
            coverage: ReportCoverage(
                observationDates: [Date(timeIntervalSince1970: 1_704_153_600)]
            )
        )
        let mutationSource = ReportsDashboardSource(
            coverage: ReportCoverage(
                observationDates: [Date(timeIntervalSince1970: 1_706_745_600)]
            )
        )
        let reentrySource = ReportsDashboardSource(
            coverage: ReportCoverage(
                observationDates: [Date(timeIntervalSince1970: 1_709_424_000)]
            )
        )
        let reportsRepository = CompositionReportsRepositoryStub(
            dashboardSources: [firstSource, mutationSource, reentrySource]
        )
        var reportRepositoryConstructions = 0
        let dependencies = try AppDependencies(
            environment: .uiTesting,
            makeReportsRepository: { _, _ in
                reportRepositoryConstructions += 1
                return reportsRepository
            }
        )

        _ = makeRoot(dependencies)
        XCTAssertEqual(reportRepositoryConstructions, 0)
        XCTAssertEqual(reportsRepository.dashboardFetchCount, 0)

        let firstProgressRoute = dependencies.makeTrackerFeatureRouter()
        let bundle = try XCTUnwrap(firstProgressRoute as? TrackerFeatureBundle)
        XCTAssertEqual(reportRepositoryConstructions, 1)
        XCTAssertEqual(
            reportsRepository.dashboardFetchCount,
            0,
            "Resolving the cached Progress bundle must not race its view task with an eager refresh."
        )

        var progressLoadPolicy = ProgressReportsLoadPolicy()
        XCTAssertEqual(
            progressLoadPolicy.transition(
                from: .today,
                to: .training,
                routerIsResolved: true
            ),
            .none
        )
        XCTAssertTrue(progressLoadPolicy.loadsReportsOnPresentation)
        XCTAssertEqual(
            progressLoadPolicy.transition(
                from: .training,
                to: .progress,
                routerIsResolved: true
            ),
            .ensureRouter,
            "A router cached from Today must not turn the first Progress presentation into an eager refresh."
        )
        XCTAssertTrue(progressLoadPolicy.loadsReportsOnPresentation)

        await bundle.reportsDashboardViewModel.load(
            referenceDate: Date(timeIntervalSince1970: 1_706_745_600)
        )
        XCTAssertEqual(reportsRepository.dashboardFetchCount, 1)
        XCTAssertEqual(bundle.reportsDashboardViewModel.source, firstSource)

        await firstProgressRoute.refreshReports()
        XCTAssertEqual(reportsRepository.dashboardFetchCount, 2)
        XCTAssertEqual(bundle.reportsDashboardViewModel.source, mutationSource)

        XCTAssertEqual(
            progressLoadPolicy.transition(
                from: .progress,
                to: .training,
                routerIsResolved: true
            ),
            .none
        )
        XCTAssertFalse(progressLoadPolicy.loadsReportsOnPresentation)
        XCTAssertEqual(
            progressLoadPolicy.transition(
                from: .training,
                to: .progress,
                routerIsResolved: true
            ),
            .refreshReports
        )
        XCTAssertFalse(progressLoadPolicy.loadsReportsOnPresentation)

        let reenteredProgressRoute = dependencies.makeTrackerFeatureRouter()
        XCTAssertTrue(firstProgressRoute === reenteredProgressRoute)
        await reenteredProgressRoute.refreshReports()
        XCTAssertEqual(reportsRepository.dashboardFetchCount, 3)
        XCTAssertEqual(bundle.reportsDashboardViewModel.source, reentrySource)
        XCTAssertEqual(reportRepositoryConstructions, 1)
        XCTAssertTrue((bundle.reportsRepository as AnyObject) === reportsRepository)
    }

    func testBundleReportRefreshUsesTheInjectedCurrentDateForEveryGeneration() async throws {
        let repository = CompositionReportsRepositoryStub()
        var referenceDate = Date(timeIntervalSince1970: 1_706_745_600)
        let calendar = try utcCalendar()
        let bundle = TrackerFeatureBundle(
            metricsRepository: TrackerMetricsRepositoryStub(),
            lifestyleRepository: TrackerLifestyleRepositoryStub(),
            healthChecksRepository: CompositionHealthChecksRepositoryStub(),
            bloodworkRepository: TrackerBloodworkRepositoryStub(),
            reportsRepository: repository,
            calendar: calendar,
            now: { referenceDate }
        )

        await bundle.refreshReports()
        referenceDate = Date(timeIntervalSince1970: 1_709_424_000)
        await bundle.refreshReports()

        XCTAssertEqual(
            repository.dashboardIntervals,
            [
                try ReportDateRangeResolver.resolve(
                    .oneMonth,
                    referenceDate: Date(timeIntervalSince1970: 1_706_745_600),
                    calendar: calendar
                ),
                try ReportDateRangeResolver.resolve(
                    .oneMonth,
                    referenceDate: Date(timeIntervalSince1970: 1_709_424_000),
                    calendar: calendar
                ),
            ]
        )
    }

    func testRealBodyMetricUpdateDeleteRefreshReportsWhileFailuresDoNot() async throws {
        let initialSource = ReportsDashboardSource(
            coverage: ReportCoverage(
                observationDates: [Date(timeIntervalSince1970: 1_704_153_600)]
            )
        )
        let editedSource = ReportsDashboardSource(
            coverage: ReportCoverage(
                observationDates: [Date(timeIntervalSince1970: 1_706_745_600)]
            )
        )
        let deletedSource = ReportsDashboardSource(
            coverage: ReportCoverage(
                observationDates: [Date(timeIntervalSince1970: 1_709_424_000)]
            )
        )
        let original = BodyMetricSnapshot(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000861")!,
            createdAt: Date(timeIntervalSince1970: 1_704_153_600),
            updatedAt: Date(timeIntervalSince1970: 1_704_153_700),
            date: Date(timeIntervalSince1970: 1_704_153_600),
            type: .weight,
            customName: nil,
            value: 80,
            unit: "kg"
        )
        let updated = BodyMetricSnapshot(
            id: original.id,
            createdAt: original.createdAt,
            updatedAt: Date(timeIntervalSince1970: 1_706_745_700),
            date: Date(timeIntervalSince1970: 1_706_745_600),
            type: .weight,
            customName: nil,
            value: 81,
            unit: "kg"
        )
        let metricsRepository = CompositionBodyMetricRepositoryStub(
            snapshots: [original],
            updatedSnapshot: updated
        )
        let repository = CompositionReportsRepositoryStub(
            dashboardSources: [initialSource, editedSource, deletedSource]
        )
        let bundle = TrackerFeatureBundle(
            metricsRepository: metricsRepository,
            lifestyleRepository: TrackerLifestyleRepositoryStub(),
            healthChecksRepository: CompositionHealthChecksRepositoryStub(),
            bloodworkRepository: TrackerBloodworkRepositoryStub(),
            reportsRepository: repository,
            calendar: try utcCalendar(),
            now: { Date(timeIntervalSince1970: 1_706_745_600) }
        )

        await bundle.bodyMetricViewModel.load()
        await bundle.refreshReports()
        XCTAssertEqual(repository.dashboardFetchCount, 1)
        XCTAssertEqual(bundle.reportsDashboardViewModel.source, initialSource)

        await bundle.bodyMetricViewModel.update(
            original,
            date: updated.date,
            value: try .weight(kilograms: updated.value)
        )
        XCTAssertEqual(bundle.bodyMetricViewModel.editPhase, .saved)
        XCTAssertEqual(repository.dashboardFetchCount, 2)
        XCTAssertEqual(bundle.reportsDashboardViewModel.source, editedSource)

        metricsRepository.shouldFailUpdate = true
        bundle.bodyMetricViewModel.prepareForEditing()
        await bundle.bodyMetricViewModel.update(
            updated,
            date: updated.date.addingTimeInterval(60),
            value: try .weight(kilograms: 82)
        )
        XCTAssertEqual(bundle.bodyMetricViewModel.editPhase, .failed)
        XCTAssertEqual(repository.dashboardFetchCount, 2)
        XCTAssertEqual(bundle.reportsDashboardViewModel.source, editedSource)

        metricsRepository.shouldFailDelete = true
        bundle.bodyMetricViewModel.prepareForEditing()
        await bundle.bodyMetricViewModel.delete(updated)
        XCTAssertEqual(bundle.bodyMetricViewModel.editPhase, .failed)
        XCTAssertEqual(repository.dashboardFetchCount, 2)

        metricsRepository.shouldFailDelete = false
        bundle.bodyMetricViewModel.prepareForEditing()
        await bundle.bodyMetricViewModel.delete(updated)
        XCTAssertEqual(bundle.bodyMetricViewModel.editPhase, .saved)
        XCTAssertEqual(repository.dashboardFetchCount, 3)
        XCTAssertEqual(bundle.reportsDashboardViewModel.source, deletedSource)
        XCTAssertEqual(metricsRepository.updateCallCount, 2)
        XCTAssertEqual(metricsRepository.deleteCallCount, 2)
    }

    func testTrackerEntrySheetDismissalOwnsOneRefreshForChildCloseAndSwipeDismissal() async throws {
        let firstDismissalSource = ReportsDashboardSource(
            coverage: ReportCoverage(
                observationDates: [Date(timeIntervalSince1970: 1_704_153_600)]
            )
        )
        let secondDismissalSource = ReportsDashboardSource(
            coverage: ReportCoverage(
                observationDates: [Date(timeIntervalSince1970: 1_706_745_600)]
            )
        )
        let repository = CompositionReportsRepositoryStub(
            dashboardSources: [firstDismissalSource, secondDismissalSource]
        )
        let bundle = TrackerFeatureBundle(
            metricsRepository: TrackerMetricsRepositoryStub(),
            lifestyleRepository: TrackerLifestyleRepositoryStub(),
            healthChecksRepository: CompositionHealthChecksRepositoryStub(),
            bloodworkRepository: TrackerBloodworkRepositoryStub(),
            reportsRepository: repository,
            calendar: try utcCalendar(),
            now: { Date(timeIntervalSince1970: 1_706_745_600) }
        )
        let policy = TrackerEntryReportsRefreshPolicy()

        policy.beginPresentation()
        let childCloseShouldRefresh = policy.consumeSheetDismissal()
        XCTAssertTrue(childCloseShouldRefresh)
        XCTAssertFalse(
            policy.consumeSheetDismissal(),
            "A child-requested close and the resulting sheet dismissal must not both refresh."
        )

        policy.beginPresentation()
        let swipeDismissalShouldRefresh = policy.consumeSheetDismissal()
        XCTAssertTrue(
            swipeDismissalShouldRefresh,
            "A new presentation must remain refreshable before prior async refresh work runs."
        )
        XCTAssertFalse(
            policy.consumeSheetDismissal(),
            "A swipe dismissal must also refresh exactly once."
        )

        if childCloseShouldRefresh {
            await bundle.refreshReports()
        }
        XCTAssertEqual(repository.dashboardFetchCount, 1)
        XCTAssertEqual(bundle.reportsDashboardViewModel.source, firstDismissalSource)

        if swipeDismissalShouldRefresh {
            await bundle.refreshReports()
        }
        XCTAssertEqual(repository.dashboardFetchCount, 2)
        XCTAssertEqual(bundle.reportsDashboardViewModel.source, secondDismissalSource)
    }

    func testDashboardAndCSVExportUseTheSameRepositoryAndShareAllProducedURLsExactlyOnce() async throws {
        let repository = CompositionReportsRepositoryStub()
        let bundle = TrackerFeatureBundle(
            metricsRepository: TrackerMetricsRepositoryStub(),
            lifestyleRepository: TrackerLifestyleRepositoryStub(),
            healthChecksRepository: CompositionHealthChecksRepositoryStub(),
            bloodworkRepository: TrackerBloodworkRepositoryStub(),
            reportsRepository: repository,
            calendar: try utcCalendar(),
            now: { Date(timeIntervalSince1970: 1_706_745_600) }
        )

        await bundle.reportsDashboardViewModel.load(
            referenceDate: Date(timeIntervalSince1970: 1_706_745_600)
        )
        XCTAssertEqual(repository.dashboardFetchCount, 1)
        XCTAssertEqual(repository.exportFetchCount, 0)
        XCTAssertEqual(bundle.reportsDashboardViewModel.loadState, .loaded)

        bundle.reportExportViewModel.generate(
            referenceDate: Date(timeIntervalSince1970: 1_706_745_600)
        )
        await bundle.reportExportViewModel.waitForCurrentGeneration()

        XCTAssertEqual(repository.dashboardFetchCount, 1)
        XCTAssertEqual(repository.exportFetchCount, 1)
        XCTAssertEqual(bundle.reportExportViewModel.state, .ready)
        let token = try XCTUnwrap(bundle.reportExportViewModel.token)
        XCTAssertEqual(
            token.shareURLs.map(\.lastPathComponent),
            ExportModuleV1.allCases.map { "\($0.rawValue).csv" },
            "CSV export produces one share item per selected module; the UI must not drop any."
        )
        XCTAssertTrue(token.shareURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        var terminalCallbackCount = 0
        let activityView = SystemActivityView(
            activityItemURLs: token.shareURLs,
            artifactID: token.id,
            accessibilityIdentifier: "reports.export.share.sheet",
            onCompletion: { artifactID, completed, _ in
                terminalCallbackCount += 1
                bundle.reportShareDidFinish(artifactID: artifactID, completed: completed)
            },
            onPresentationFailure: { artifactID in
                terminalCallbackCount += 1
                bundle.reportShareDidFinish(artifactID: artifactID, completed: false)
            }
        )
        XCTAssertEqual(activityView.activityItemURLs, token.shareURLs)

        let coordinator = activityView.makeCoordinator()
        coordinator.complete(completed: false, error: nil)
        coordinator.complete(completed: true, error: nil)
        coordinator.presentationFailed()

        XCTAssertEqual(terminalCallbackCount, 1)
        XCTAssertEqual(token.cleanupCallCount, 1)
        XCTAssertEqual(bundle.reportExportViewModel.state, .idle)
        XCTAssertNil(bundle.reportExportViewModel.token)
        XCTAssertTrue(repository.mutationEvents.isEmpty)
    }

    func testStaleShareCompletionCannotCleanTheNewMatchingArtifact() async throws {
        let repository = CompositionReportsRepositoryStub()
        let bundle = TrackerFeatureBundle(
            metricsRepository: TrackerMetricsRepositoryStub(),
            lifestyleRepository: TrackerLifestyleRepositoryStub(),
            healthChecksRepository: CompositionHealthChecksRepositoryStub(),
            bloodworkRepository: TrackerBloodworkRepositoryStub(),
            reportsRepository: repository,
            calendar: try utcCalendar()
        )

        bundle.reportExportViewModel.generate(referenceDate: Date(timeIntervalSince1970: 1_706_745_600))
        await bundle.reportExportViewModel.waitForCurrentGeneration()
        let oldToken = try XCTUnwrap(bundle.reportExportViewModel.token)
        bundle.reportExportViewModel.setPreset(.threeMonths)
        XCTAssertEqual(oldToken.cleanupCallCount, 1)

        bundle.reportExportViewModel.generate(referenceDate: Date(timeIntervalSince1970: 1_706_745_600))
        await bundle.reportExportViewModel.waitForCurrentGeneration()
        let newToken = try XCTUnwrap(bundle.reportExportViewModel.token)
        XCTAssertNotEqual(oldToken.id, newToken.id)

        XCTAssertFalse(bundle.reportShareDidFinish(artifactID: oldToken.id, completed: true))
        XCTAssertEqual(bundle.reportExportViewModel.state, .ready)
        XCTAssertEqual(bundle.reportExportViewModel.token?.id, newToken.id)
        XCTAssertEqual(newToken.cleanupCallCount, 0)

        XCTAssertTrue(bundle.reportShareDidFinish(artifactID: newToken.id, completed: true))
        XCTAssertEqual(bundle.reportExportViewModel.state, .idle)
        XCTAssertNil(bundle.reportExportViewModel.token)
        XCTAssertEqual(newToken.cleanupCallCount, 1)
    }

    func testProgressPhotoExportAdapterMapsFullImageResultsWithoutLeakingReferencesOrMutating() async throws {
        let availableID = UUID(uuidString: "00000000-0000-4000-8000-000000000841")!
        let missingID = UUID(uuidString: "00000000-0000-4000-8000-000000000842")!
        let corruptID = UUID(uuidString: "00000000-0000-4000-8000-000000000843")!
        let laterID = UUID(uuidString: "00000000-0000-4000-8000-000000000844")!
        let unknownID = UUID(uuidString: "00000000-0000-4000-8000-000000000845")!
        let bytes = Data([0xff, 0xd8, 0x11, 0xff, 0xd9])
        let laterBytes = Data([0xff, 0xd8, 0x22, 0xff, 0xd9])
        let repository = CompositionProgressPhotoRepositoryStub(
            photos: [
                photo(id: availableID, assetID: "00000000-0000-4000-8000-000000000851"),
                photo(id: missingID, assetID: "00000000-0000-4000-8000-000000000852"),
                photo(id: corruptID, assetID: "00000000-0000-4000-8000-000000000853"),
            ],
            results: [
                "00000000-0000-4000-8000-000000000851": .available(bytes),
                "00000000-0000-4000-8000-000000000852": .missing,
                "00000000-0000-4000-8000-000000000853": .corrupt,
            ]
        )
        let adapter = ProgressPhotoReportExportProvider(repository: repository)

        let available = try await adapter.jpegData(for: availableID)
        let missing = try await adapter.jpegData(for: missingID)
        let corrupt = try await adapter.jpegData(for: corruptID)
        XCTAssertEqual(
            repository.fetchPhotosCount,
            1,
            "Known IDs must share one O(n) metadata index instead of rescanning a 500-photo fixture."
        )

        repository.append(
            photo: photo(
                id: laterID,
                assetID: "00000000-0000-4000-8000-000000000855"
            ),
            result: .available(laterBytes)
        )
        let later = try await adapter.jpegData(for: laterID)
        let unknown = try await adapter.jpegData(for: unknownID)
        let repeatedUnknown = try await adapter.jpegData(for: unknownID)

        assertPayload(available, contains: bytes)
        assertMissing(missing)
        assertCorrupt(corrupt)
        assertPayload(later, contains: laterBytes)
        assertMissing(unknown)
        assertMissing(repeatedUnknown)
        XCTAssertEqual(
            repository.fetchPhotosCount,
            3,
            "A post-snapshot ID and a genuinely unknown ID each refresh once; repeating that unknown ID stays bounded."
        )
        XCTAssertEqual(
            repository.fullImageAssetIDs,
            [
                "00000000-0000-4000-8000-000000000851",
                "00000000-0000-4000-8000-000000000852",
                "00000000-0000-4000-8000-000000000853",
                "00000000-0000-4000-8000-000000000855",
            ]
        )
        XCTAssertEqual(repository.mutationCount, 0)
    }

    private func makeRoot(_ dependencies: AppDependencies) -> AppRootView {
        AppRootView(
            todayViewModel: dependencies.todayViewModel,
            foundationViewModel: dependencies.foundationViewModel,
            phaseTransitionViewModel: dependencies.phaseTransitionViewModel,
            trainingHistoryViewModel: dependencies.trainingHistoryViewModel,
            todayNutritionViewModel: dependencies.todayNutritionViewModel,
            nutritionDayViewModel: dependencies.nutritionDayViewModel,
            foodLibraryViewModel: dependencies.foodLibraryViewModel,
            recipeLibraryViewModel: dependencies.recipeLibraryViewModel,
            nutritionQuickAddViewModel: dependencies.nutritionQuickAddViewModel,
            nutritionManualEntryViewModel: dependencies.nutritionManualEntryViewModel,
            makeSessionViewModel: dependencies.makeSessionViewModel,
            makeTrackerFeatureRouter: dependencies.makeTrackerFeatureRouter,
            trainingHapticController: dependencies.trainingHapticController,
            shouldLoadFoundation: dependencies.shouldLoadFoundation,
            persistencePresentation: dependencies.persistencePresentation
        )
    }

    private func utcCalendar() throws -> Calendar {
        guard let timeZone = TimeZone(identifier: "UTC") else {
            throw CompositionFixtureFailure.invalidTimeZone
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    private func photo(id: UUID, assetID: String) -> ProgressPhotoSnapshot {
        ProgressPhotoSnapshot(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            imageRef: assetID,
            pose: .front,
            note: nil
        )
    }

    private func assertPayload(
        _ payload: ReportExportPhotoPayloadV1,
        contains expected: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .available(actual) = payload else {
            return XCTFail("Expected an available photo payload.", file: file, line: line)
        }
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func assertMissing(
        _ payload: ReportExportPhotoPayloadV1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .missing = payload else {
            return XCTFail("Expected a missing photo payload.", file: file, line: line)
        }
    }

    private func assertCorrupt(
        _ payload: ReportExportPhotoPayloadV1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .corrupt = payload else {
            return XCTFail("Expected a corrupt photo payload.", file: file, line: line)
        }
    }
}

@MainActor
private final class CompositionBodyMetricRepositoryStub: MetricsRepository {
    private var snapshots: [BodyMetricSnapshot]
    private let updatedSnapshot: BodyMetricSnapshot
    var shouldFailUpdate = false
    var shouldFailDelete = false
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0

    init(
        snapshots: [BodyMetricSnapshot],
        updatedSnapshot: BodyMetricSnapshot
    ) {
        self.snapshots = snapshots
        self.updatedSnapshot = updatedSnapshot
    }

    func fetchPostureMetrics() async throws -> [PostureMetricSnapshot] { [] }

    func createPostureMetric(
        _ input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        throw StubFailure.unexpectedMutation
    }

    func updatePostureMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        throw StubFailure.unexpectedMutation
    }

    func deletePostureMetric(id: UUID, expectedUpdatedAt: Date) async throws {
        throw StubFailure.unexpectedMutation
    }

    func upsertPostureMetric(
        id: UUID,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        throw StubFailure.unexpectedMutation
    }

    func fetchBodyMetrics() async throws -> [BodyMetricSnapshot] {
        snapshots
    }

    func createBodyMetrics(
        _ input: BodyMetricBatchInput
    ) async throws -> BodyMetricCreationMutation {
        throw StubFailure.unexpectedMutation
    }

    func updateBodyMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        date: Date,
        value: BodyMetricValueInput
    ) async throws -> BodyMetricSnapshot {
        updateCallCount += 1
        if shouldFailUpdate {
            throw StubFailure.requestedFailure
        }
        snapshots = [updatedSnapshot]
        return updatedSnapshot
    }

    func deleteBodyMetric(id: UUID, expectedUpdatedAt: Date) async throws {
        deleteCallCount += 1
        if shouldFailDelete {
            throw StubFailure.requestedFailure
        }
        snapshots.removeAll { $0.id == id }
    }

    func undoBodyMetricCreation(_ token: BodyMetricCreationUndoToken) async throws {
        throw StubFailure.unexpectedMutation
    }

    private enum StubFailure: Error {
        case requestedFailure
        case unexpectedMutation
    }
}

@MainActor
private final class CompositionReportsRepositoryStub:
    ReportsRepository, ReportsExportRepository {
    private var dashboardSources: [ReportsDashboardSource]
    private(set) var dashboardFetchCount = 0
    private(set) var dashboardIntervals: [ReportDateInterval] = []
    private(set) var exportFetchCount = 0
    private(set) var mutationEvents: [String] = []

    init(dashboardSources: [ReportsDashboardSource] = [ReportsDashboardSource(coverage: .empty)]) {
        self.dashboardSources = dashboardSources
    }

    func fetchDashboardSource(in interval: ReportDateInterval) async throws -> ReportsDashboardSource {
        dashboardIntervals.append(interval)
        dashboardFetchCount += 1
        guard !dashboardSources.isEmpty else {
            return ReportsDashboardSource(coverage: .empty)
        }
        if dashboardSources.count == 1 {
            return dashboardSources[0]
        }
        return dashboardSources.removeFirst()
    }

    func fetchExportSnapshot(
        in interval: ReportDateInterval,
        modules: Set<ExportModuleV1>
    ) async throws -> ExportSnapshotV1 {
        exportFetchCount += 1
        let tables = try ExportModuleV1.allCases.compactMap { module -> ExportTableV1? in
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
private final class CompositionProgressPhotoRepositoryStub: ProgressPhotoRepository {
    let pendingAssetCleanupIDs: [String] = []
    private var photos: [ProgressPhotoSnapshot]
    private var results: [String: PhotoAssetLoadResult]
    private(set) var fetchPhotosCount = 0
    private(set) var fullImageAssetIDs: [String] = []
    private(set) var mutationCount = 0

    init(photos: [ProgressPhotoSnapshot], results: [String: PhotoAssetLoadResult]) {
        self.photos = photos
        self.results = results
    }

    func fetchPhotos() async throws -> [ProgressPhotoSnapshot] {
        fetchPhotosCount += 1
        return photos
    }

    func append(
        photo: ProgressPhotoSnapshot,
        result: PhotoAssetLoadResult
    ) {
        photos.append(photo)
        results[photo.imageRef] = result
    }

    func importPhoto(
        _ input: ProgressPhotoInput,
        bytes: Data
    ) async throws -> ProgressPhotoSnapshot {
        _ = (input, bytes)
        mutationCount += 1
        throw CompositionFixtureFailure.unexpectedMutation
    }

    func thumbnail(assetID: String) async throws -> PhotoAssetLoadResult {
        _ = assetID
        return .missing
    }

    func fullImage(assetID: String) async throws -> PhotoAssetLoadResult {
        fullImageAssetIDs.append(assetID)
        return results[assetID] ?? .missing
    }

    func deletePhoto(id: UUID, expectedUpdatedAt: Date) async throws {
        _ = (id, expectedUpdatedAt)
        mutationCount += 1
        throw CompositionFixtureFailure.unexpectedMutation
    }

    func retryPendingAssetCleanup() async throws {
        mutationCount += 1
        throw CompositionFixtureFailure.unexpectedMutation
    }
}

@MainActor
private final class CompositionHealthChecksRepositoryStub: HealthChecksRepository {
    func fetchReminders() async throws -> [HealthCheckReminderSnapshot] { [] }

    func createReminder(
        _ input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot {
        _ = input
        throw CompositionFixtureFailure.unexpectedMutation
    }

    func updateReminder(
        id: UUID,
        expectedUpdatedAt: Date,
        input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot {
        _ = (id, expectedUpdatedAt, input)
        throw CompositionFixtureFailure.unexpectedMutation
    }

    func deleteReminder(id: UUID, expectedUpdatedAt: Date) async throws {
        _ = (id, expectedUpdatedAt)
        throw CompositionFixtureFailure.unexpectedMutation
    }

    func completeReminder(
        id: UUID,
        expectedUpdatedAt: Date
    ) async throws -> HealthCheckCompletionMutation {
        _ = (id, expectedUpdatedAt)
        throw CompositionFixtureFailure.unexpectedMutation
    }

    func undoCompletion(
        _ token: HealthCheckCompletionUndoToken
    ) async throws -> HealthCheckReminderSnapshot {
        _ = token
        throw CompositionFixtureFailure.unexpectedMutation
    }
}

private enum CompositionFixtureFailure: Error {
    case invalidTimeZone
    case unexpectedMutation
}
