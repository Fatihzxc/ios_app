public protocol ReportsRepository: Sendable {
    @MainActor
    func fetchDashboardSource(in interval: ReportDateInterval) async throws -> ReportsDashboardSource
}
