import Foundation
@testable import ReportsKit
import XCTest

@MainActor
final class ReportsLargeDatasetTests: XCTestCase {
    func testTenThousandTimeSeriesRowsReduceDeterministicallyToBoundedChartPoints() throws {
        let calendar = fixtureCalendar()
        let interval = fixtureInterval(calendar: calendar)
        let records = try makeBodyMetricRecords(calendar: calendar)
        XCTAssertEqual(records.count, 10_000)

        let startedAt = Date.timeIntervalSinceReferenceDate
        let forward = try BodyStrengthDatasetBuilder.build(
            bodyMetricRecords: records,
            exerciseSetRecords: [],
            interval: interval,
            calendar: calendar
        )
        let reverse = try BodyStrengthDatasetBuilder.build(
            bodyMetricRecords: Array(records.reversed()),
            exerciseSetRecords: [],
            interval: interval,
            calendar: calendar
        )
        let elapsed = Date.timeIntervalSinceReferenceDate - startedAt

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward.bodyMetricPoints.count, 365)
        XCTAssertLessThanOrEqual(forward.bodyMetricPoints.count, 366)
        XCTAssertLessThan(elapsed, 20)
    }

    func testFiveHundredPhotoMetadataRowsEncodeDeterministicallyWithinHostedCeiling() throws {
        let rows = try makePhotoRows()
        XCTAssertEqual(rows.count, 500)
        let interval = exportInterval()
        let startedAt = Date.timeIntervalSinceReferenceDate
        let forward = try photoSnapshot(rows: rows, interval: interval)
        let reverse = try photoSnapshot(rows: rows.reversed(), interval: interval)
        let first = try JSONExportEncoderV1().encode(forward)
        let second = try JSONExportEncoderV1().encode(reverse)
        let elapsed = Date.timeIntervalSinceReferenceDate - startedAt

        XCTAssertEqual(first, second)
        XCTAssertEqual(forward.tables.first?.rows.count, 500)
        XCTAssertLessThan(elapsed, 20)
    }

    func testFiveHundredPhotoZIPCancellationRespondsAndCleansOwnedWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "M4LargeCancellation-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try photoSnapshot(
            rows: makePhotoRows(),
            interval: exportInterval()
        )
        let provider = M4CancellationPhotoProvider()
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: FileManagerReportExportTemporaryFileSystem(),
            makeDirectoryID: {
                UUID(uuidString: "00000000-0000-4000-8000-00000000c901")!
            }
        )
        let coordinator = ReportExportCoordinator(
            repository: M4LargeExportRepository(snapshot: snapshot),
            photoProvider: provider,
            temporaryStore: store
        )
        let generation = Task {
            try await coordinator.generate(
                ReportExportRequest(
                    interval: snapshot.interval,
                    modules: [.photos],
                    format: .bothZip,
                    includesPhotos: true
                )
            )
        }

        try await provider.waitUntilStarted()
        let cancelledAt = Date.timeIntervalSinceReferenceDate
        generation.cancel()
        do {
            _ = try await generation.value
            XCTFail("Cancelled M4 generation unexpectedly returned an artifact.")
        } catch is CancellationError {
            // Expected cancellation is the public coordinator contract.
        }
        let elapsed = Date.timeIntervalSinceReferenceDate - cancelledAt
        XCTAssertLessThan(elapsed, 8)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: root.path),
            []
        )
    }

    private func makeBodyMetricRecords(
        calendar: Calendar
    ) throws -> [ReportBodyMetricRecord] {
        guard let start = calendar.date(
            from: DateComponents(year: 2025, month: 1, day: 1, hour: 12)
        ) else {
            throw LargeFixtureFailure.invalidDate
        }
        return try (0..<10_000).map { index in
            let dayOffset = index % 365
            let revision = index / 365
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: start),
                  let timestamp = calendar.date(
                    byAdding: .second,
                    value: revision,
                    to: day
                  ) else {
                throw LargeFixtureFailure.invalidDate
            }
            return ReportBodyMetricRecord(
                id: fixtureUUID(index + 1),
                date: timestamp,
                createdAt: timestamp,
                kind: .weight,
                customName: nil,
                value: 70 + Double(index % 100) / 10,
                unit: "kg"
            )
        }
    }

    private func makePhotoRows() throws -> [ExportRowV1] {
        try (0..<500).map { index in
            let timestamp = Date(
                timeIntervalSince1970: 1_780_000_000 + Double(index)
            )
            let cells = ExportSchemaV1.columns(for: .photos).map { column in
                let value: ExportCellV1
                switch column.name {
                case "record_type": value = .text(ExportRecordTypeV1.progressPhoto.rawValue)
                case "id": value = .uuid(fixtureUUID(index + 1))
                case "created_at", "updated_at", "progress_photo_date":
                    value = .timestamp(timestamp)
                case "config_scope", "progress_photo_note": value = .null
                case "progress_photo_image_available": value = .boolean(true)
                case "progress_photo_pose": value = .text(index.isMultiple(of: 2) ? "front" : "side")
                default: value = .null
                }
                return ExportNamedCellV1(columnName: column.name, value: value)
            }
            return try ExportRowV1(primaryTimestamp: timestamp, cells: cells)
        }
    }

    private func photoSnapshot<S: Sequence>(
        rows: S,
        interval: ReportDateInterval
    ) throws -> ExportSnapshotV1 where S.Element == ExportRowV1 {
        let table = try ExportTableV1(
            module: .photos,
            columns: ExportSchemaV1.columns(for: .photos),
            rows: Array(rows)
        )
        return try ExportSnapshotV1(
            interval: interval,
            selectedModules: [.photos],
            tables: [table]
        )
    }

    private func fixtureCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "tr_TR")
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private func fixtureInterval(calendar: Calendar) -> ReportDateInterval {
        ReportDateInterval(
            start: calendar.date(
                from: DateComponents(year: 2025, month: 1, day: 1)
            )!,
            endExclusive: calendar.date(
                from: DateComponents(year: 2026, month: 1, day: 1)
            )!
        )
    }

    private func exportInterval() -> ReportDateInterval {
        ReportDateInterval(
            start: Date(timeIntervalSince1970: 1_779_900_000),
            endExclusive: Date(timeIntervalSince1970: 1_781_000_000)
        )
    }

    private func fixtureUUID(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-4000-8000-%012llx",
                Int64(value)
            )
        )!
    }
}

private enum LargeFixtureFailure: Error {
    case invalidDate
    case timedOut
}

@MainActor
private final class M4LargeExportRepository: ReportsExportRepository {
    private let snapshot: ExportSnapshotV1

    init(snapshot: ExportSnapshotV1) {
        self.snapshot = snapshot
    }

    func fetchExportSnapshot(
        in interval: ReportDateInterval,
        modules: Set<ExportModuleV1>
    ) async throws -> ExportSnapshotV1 {
        guard interval == snapshot.interval, modules == [.photos] else {
            throw LargeFixtureFailure.invalidDate
        }
        return snapshot
    }
}

private actor M4CancellationPhotoProvider: ReportExportPhotoByteProviding {
    private var hasStarted = false

    func jpegData(for photoID: UUID) async throws -> ReportExportPhotoPayloadV1 {
        _ = photoID
        hasStarted = true
        try await Task.sleep(nanoseconds: 30_000_000_000)
        return .missing
    }

    func waitUntilStarted() async throws {
        for _ in 0..<200 {
            if hasStarted { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw LargeFixtureFailure.timedOut
    }
}
