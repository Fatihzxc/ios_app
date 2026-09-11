import Foundation
import Observation

public enum ReportsDashboardLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

public struct ReportsDashboard: Equatable, Sendable {
    public let interval: ReportDateInterval
    public let sourceCoverage: ReportCoverage
    public let bodyStrength: BodyStrengthReport
    public let proteinAdherence: ProteinAdherenceReport
    public let lifestylePhase: LifestylePhaseReport

    public init(
        interval: ReportDateInterval,
        sourceCoverage: ReportCoverage,
        bodyStrength: BodyStrengthReport,
        proteinAdherence: ProteinAdherenceReport,
        lifestylePhase: LifestylePhaseReport
    ) {
        self.interval = interval
        self.sourceCoverage = sourceCoverage
        self.bodyStrength = bodyStrength
        self.proteinAdherence = proteinAdherence
        self.lifestylePhase = lifestylePhase
    }
}

public enum ReportsDashboardBuilder {
    public static func build(
        source: ReportsDashboardSource,
        interval: ReportDateInterval,
        calendar: Calendar
    ) throws -> ReportsDashboard {
        let bodyStrength = try BodyStrengthDatasetBuilder.build(
            bodyMetricRecords: source.bodyMetricRecords,
            exerciseSetRecords: source.exerciseSetRecords,
            interval: interval,
            calendar: calendar
        )
        let proteinAdherence = try ProteinAdherenceBuilder.build(
            days: source.nutritionDayRecords.filter { interval.contains($0.date) }
        )
        let lifestylePhase = try LifestylePhaseDatasetBuilder.build(
            source: source,
            interval: interval,
            calendar: calendar
        )
        return ReportsDashboard(
            interval: interval,
            sourceCoverage: source.coverage,
            bodyStrength: bodyStrength,
            proteinAdherence: proteinAdherence,
            lifestylePhase: lifestylePhase
        )
    }
}

public typealias ReportsDashboardBuild = @Sendable (
    _ source: ReportsDashboardSource,
    _ interval: ReportDateInterval,
    _ calendar: Calendar
) throws -> ReportsDashboard

@MainActor
@Observable
public final class ReportsDashboardViewModel {
    public private(set) var selectedPreset: ReportDateRangePreset
    public private(set) var loadState: ReportsDashboardLoadState = .idle
    public private(set) var interval: ReportDateInterval?
    public private(set) var source: ReportsDashboardSource?
    public private(set) var report: ReportsDashboard?
    public private(set) var failure: (any Error)?

    @ObservationIgnored private let repository: any ReportsRepository
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let build: ReportsDashboardBuild
    @ObservationIgnored private var activeLoadID: UUID?
    @ObservationIgnored private var activeBuildTask: Task<ReportsDashboard, Error>?

    public init(
        repository: any ReportsRepository,
        calendar: Calendar,
        selectedPreset: ReportDateRangePreset = .oneMonth,
        build: @escaping ReportsDashboardBuild = ReportsDashboardBuilder.build
    ) {
        self.repository = repository
        self.calendar = calendar
        self.selectedPreset = selectedPreset
        self.build = build
    }

    public func selectPreset(
        _ preset: ReportDateRangePreset,
        referenceDate: Date
    ) async {
        selectedPreset = preset
        await load(referenceDate: referenceDate)
    }

    public func load(referenceDate: Date) async {
        let loadID = UUID()
        let supersededBuildTask = activeBuildTask
        activeBuildTask = nil
        activeLoadID = loadID
        supersededBuildTask?.cancel()
        loadState = .loading
        interval = nil
        source = nil
        report = nil
        failure = nil

        do {
            let resolvedInterval = try ReportDateRangeResolver.resolve(
                selectedPreset,
                referenceDate: referenceDate,
                calendar: calendar
            )
            interval = resolvedInterval
            let loadedSource = try await repository.fetchDashboardSource(in: resolvedInterval)
            try Task.checkCancellation()
            guard activeLoadID == loadID else { return }
            let build = self.build
            let buildCalendar = calendar
            let buildTask = Task.detached(priority: .userInitiated) {
                try build(loadedSource, resolvedInterval, buildCalendar)
            }
            activeBuildTask = buildTask
            let loadedReport = try await withTaskCancellationHandler {
                try await buildTask.value
            } onCancel: {
                buildTask.cancel()
            }
            try Task.checkCancellation()
            guard activeLoadID == loadID else { return }
            activeBuildTask = nil
            source = loadedSource
            report = loadedReport
            loadState = .loaded
            activeLoadID = nil
        } catch is CancellationError {
            guard activeLoadID == loadID else { return }
            activeBuildTask?.cancel()
            activeBuildTask = nil
            loadState = .idle
            activeLoadID = nil
        } catch {
            guard activeLoadID == loadID else { return }
            activeBuildTask = nil
            guard !Task.isCancelled else {
                loadState = .idle
                activeLoadID = nil
                return
            }
            failure = error
            loadState = .failed
            activeLoadID = nil
        }
    }
}
