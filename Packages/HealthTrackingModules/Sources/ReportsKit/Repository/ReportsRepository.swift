public protocol ReportsRepository: Sendable {
    func fetchDashboardSource(in interval: ReportDateInterval) async throws -> ReportsDashboardSource
}
