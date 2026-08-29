import Foundation
import Observation

public enum ReportsDashboardLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

@MainActor
@Observable
public final class ReportsDashboardViewModel {
    public private(set) var selectedPreset: ReportDateRangePreset
    public private(set) var loadState: ReportsDashboardLoadState = .idle
    public private(set) var interval: ReportDateInterval?
    public private(set) var source: ReportsDashboardSource?
    public private(set) var failure: (any Error)?

    @ObservationIgnored private let repository: any ReportsRepository
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var activeLoadID: UUID?

    public init(
        repository: any ReportsRepository,
        calendar: Calendar,
        selectedPreset: ReportDateRangePreset = .oneMonth
    ) {
        self.repository = repository
        self.calendar = calendar
        self.selectedPreset = selectedPreset
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
        activeLoadID = loadID
        loadState = .loading
        interval = nil
        source = nil
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
            source = loadedSource
            loadState = .loaded
            activeLoadID = nil
        } catch is CancellationError {
            guard activeLoadID == loadID else { return }
            loadState = .idle
            activeLoadID = nil
        } catch {
            guard activeLoadID == loadID else { return }
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
