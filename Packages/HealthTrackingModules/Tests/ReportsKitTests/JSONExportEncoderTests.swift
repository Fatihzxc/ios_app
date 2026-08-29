import Foundation
@testable import ReportsKit
import XCTest

final class JSONExportEncoderTests: XCTestCase {
    func testEncodesExactVersionedNativeShapeAndCanonicalScalars() throws {
        let timestamp = Date(timeIntervalSince1970: 1_704_164_645.123)
        let id = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        let table = try metricsTable(
            id: id,
            timestamp: timestamp,
            customName: "=SUM(A1:A2), İstanbul 💪",
            value: -0.0
        )
        let snapshot = try ExportSnapshotV1(
            interval: interval(),
            selectedModules: [.metrics],
            tables: [table]
        )

        let bytes = try JSONExportEncoderV1().encode(snapshot)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )

        XCTAssertEqual(root["schemaVersion"] as? Int, 1)
        XCTAssertEqual(root["selectedModules"] as? [String], ["metrics"])
        let encodedInterval = try XCTUnwrap(root["interval"] as? [String: String])
        XCTAssertEqual(encodedInterval["start"], "2024-01-01T00:00:00.000000Z")
        XCTAssertEqual(encodedInterval["endExclusive"], "2024-02-01T00:00:00.000000Z")

        let tables = try XCTUnwrap(root["tables"] as? [[String: Any]])
        XCTAssertEqual(tables.count, 1)
        XCTAssertEqual(tables[0]["module"] as? String, "metrics")
        let columns = try XCTUnwrap(tables[0]["columns"] as? [[String: Any]])
        XCTAssertEqual(columns.map { $0["name"] as? String }, table.columns.map(\.name))
        XCTAssertEqual(columns.map { $0["type"] as? String }, table.columns.map(\.type.rawValue))
        XCTAssertEqual(columns.map { $0["isNullable"] as? Bool }, table.columns.map(\.isNullable))

        let rows = try XCTUnwrap(tables[0]["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["primaryTimestamp"] as? String, "2024-01-02T03:04:05.123000Z")
        let cells = try XCTUnwrap(rows[0]["cells"] as? [String: Any])
        XCTAssertEqual(cells["record_type"] as? String, "body_metric")
        XCTAssertEqual(cells["id"] as? String, "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
        XCTAssertEqual(cells["body_metric_custom_name"] as? String, "=SUM(A1:A2), İstanbul 💪")
        XCTAssertEqual((cells["body_metric_value"] as? NSNumber)?.doubleValue, -0.0)
        XCTAssertTrue(cells["posture_metric_note"] is NSNull)
        XCTAssertEqual(cells.count, table.columns.count)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("'=SUM"))
    }

    func testPreservesNullVersusEmptyAndOriginalFormulaLikeUnicodeText() throws {
        let table = try metricsTable(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            timestamp: Date(timeIntervalSince1970: 1_000),
            customName: "",
            value: 12.5,
            unit: "=kg\nölçüm"
        )
        let snapshot = try ExportSnapshotV1(
            interval: interval(), selectedModules: [.metrics], tables: [table]
        )

        let bytes = try JSONExportEncoderV1().encode(snapshot)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let tables = try XCTUnwrap(root["tables"] as? [[String: Any]])
        let rows = try XCTUnwrap(tables[0]["rows"] as? [[String: Any]])
        let cells = try XCTUnwrap(rows[0]["cells"] as? [String: Any])

        XCTAssertEqual(cells["body_metric_custom_name"] as? String, "")
        XCTAssertEqual(cells["body_metric_unit"] as? String, "=kg\nölçüm")
        XCTAssertTrue(cells["posture_metric_region"] is NSNull)
    }

    func testOrdersModulesTablesRowsAndProducesDeterministicSortedKeyBytes() throws {
        let metrics = try ExportTableV1(
            module: .metrics,
            columns: ExportSchemaV1.columns(for: .metrics),
            rows: [
                metricsRow(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, timestamp: Date(timeIntervalSince1970: 2_000)),
                metricsRow(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, timestamp: Date(timeIntervalSince1970: 1_000)),
            ]
        )
        let photos = try ExportTableV1(
            module: .photos,
            columns: ExportSchemaV1.columns(for: .photos),
            rows: []
        )
        let forward = try ExportSnapshotV1(
            interval: interval(),
            selectedModules: [.photos, .metrics],
            tables: [photos, metrics]
        )
        let reverse = try ExportSnapshotV1(
            interval: interval(),
            selectedModules: [.metrics, .photos],
            tables: [metrics, photos]
        )

        let first = try JSONExportEncoderV1().encode(forward)
        let second = try JSONExportEncoderV1().encode(reverse)

        XCTAssertEqual(first, second)
        let text = String(decoding: first, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("{\"interval\":"), "JSON object keys must be sorted")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any])
        XCTAssertEqual(root["selectedModules"] as? [String], ["metrics", "photos"])
        let tables = try XCTUnwrap(root["tables"] as? [[String: Any]])
        XCTAssertEqual(tables.compactMap { $0["module"] as? String }, ["metrics", "photos"])
        let rows = try XCTUnwrap(tables[0]["rows"] as? [[String: Any]])
        let identifiers = try rows.map { row -> String in
            let cells = try XCTUnwrap(row["cells"] as? [String: Any])
            return try XCTUnwrap(cells["id"] as? String)
        }
        XCTAssertEqual(identifiers, [
            "00000000-0000-4000-8000-000000000001",
            "00000000-0000-4000-8000-000000000002",
        ])
    }

    func testRejectsEveryNonFiniteDecimalAndInvalidTimestampBeforeReturningBytes() throws {
        for value in [Double.nan, .infinity, -.infinity] {
            let table = try metricsTable(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
                timestamp: Date(timeIntervalSince1970: 1_000),
                customName: nil,
                value: value
            )
            let snapshot = try ExportSnapshotV1(
                interval: interval(), selectedModules: [.metrics], tables: [table]
            )
            XCTAssertThrowsError(try JSONExportEncoderV1().encode(snapshot)) { error in
                XCTAssertEqual(error as? JSONExportEncodingError, .nonFiniteDecimal)
            }
        }

        let invalidDate = Date(timeIntervalSinceReferenceDate: .infinity)
        let table = try metricsTable(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            timestamp: Date(timeIntervalSince1970: 1_000),
            customName: nil,
            value: 1,
            updatedAt: invalidDate
        )
        let snapshot = try ExportSnapshotV1(
            interval: interval(), selectedModules: [.metrics], tables: [table]
        )
        XCTAssertThrowsError(try JSONExportEncoderV1().encode(snapshot)) { error in
            XCTAssertEqual(error as? JSONExportEncodingError, .invalidTimestamp)
        }
    }

    private func interval() -> ReportDateInterval {
        ReportDateInterval(
            start: Date(timeIntervalSince1970: 1_704_067_200),
            endExclusive: Date(timeIntervalSince1970: 1_706_745_600)
        )
    }

    private func metricsTable(
        id: UUID,
        timestamp: Date,
        customName: String?,
        value: Double,
        unit: String = "kg",
        updatedAt: Date? = nil
    ) throws -> ExportTableV1 {
        try ExportTableV1(
            module: .metrics,
            columns: ExportSchemaV1.columns(for: .metrics),
            rows: [metricsRow(
                id: id,
                timestamp: timestamp,
                customName: customName,
                value: value,
                unit: unit,
                updatedAt: updatedAt
            )]
        )
    }

    private func metricsRow(
        id: UUID,
        timestamp: Date,
        customName: String? = nil,
        value: Double = 1,
        unit: String = "kg",
        updatedAt: Date? = nil
    ) throws -> ExportRowV1 {
        let cells = ExportSchemaV1.columns(for: .metrics).map { column -> ExportNamedCellV1 in
            let cell: ExportCellV1
            switch column.name {
            case "record_type": cell = .text("body_metric")
            case "id": cell = .uuid(id)
            case "created_at": cell = .timestamp(timestamp)
            case "updated_at": cell = .timestamp(updatedAt ?? timestamp)
            case "config_scope": cell = .null
            case "body_metric_date": cell = .timestamp(timestamp)
            case "body_metric_type": cell = .text("weight")
            case "body_metric_custom_name": cell = customName.map(ExportCellV1.text) ?? .null
            case "body_metric_value": cell = .decimal(value)
            case "body_metric_unit": cell = .text(unit)
            default: cell = .null
            }
            return .init(columnName: column.name, value: cell)
        }
        return try ExportRowV1(primaryTimestamp: timestamp, cells: cells)
    }
}
