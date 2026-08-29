import Foundation
@testable import ReportsKit
import XCTest

final class RFC4180CSVEncoderTests: XCTestCase {
    func testEncodesRFC4180EscapesUnicodeNullEmptyAndCanonicalScalars() throws {
        let timestamp = Date(timeIntervalSince1970: 1_704_164_645.123)
        let id = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        let columns = try baseColumns() + [
            ExportColumnV1(name: "comma", type: .text, isNullable: false),
            ExportColumnV1(name: "quote", type: .text, isNullable: false),
            ExportColumnV1(name: "line_breaks", type: .text, isNullable: false),
            ExportColumnV1(name: "turkish", type: .text, isNullable: false),
            ExportColumnV1(name: "empty_text", type: .text, isNullable: false),
            ExportColumnV1(name: "missing_text", type: .text, isNullable: true),
            ExportColumnV1(name: "count", type: .integer, isNullable: false),
            ExportColumnV1(name: "amount", type: .decimal, isNullable: false),
            ExportColumnV1(name: "negative_zero", type: .decimal, isNullable: false),
            ExportColumnV1(name: "enabled", type: .boolean, isNullable: false),
        ]
        let row = try ExportRowV1(primaryTimestamp: timestamp, cells: baseCells(
            recordType: "body_metric", id: id, timestamp: timestamp
        ) + [
            .init(columnName: "comma", value: .text("a,b")),
            .init(columnName: "quote", value: .text("a\"b")),
            .init(columnName: "line_breaks", value: .text("CR\rLF\nBOTH\r\n")),
            .init(columnName: "turkish", value: .text("İstanbul, ölçüm 💪")),
            .init(columnName: "empty_text", value: .text("")),
            .init(columnName: "missing_text", value: .null),
            .init(columnName: "count", value: .integer(-42)),
            .init(columnName: "amount", value: .decimal(12.5)),
            .init(columnName: "negative_zero", value: .decimal(-0.0)),
            .init(columnName: "enabled", value: .boolean(true)),
        ])
        let table = try ExportTableV1(module: .metrics, columns: columns, rows: [row])

        let encoded = String(decoding: try RFC4180CSVEncoder().encode(table), as: UTF8.self)

        let expectedHeader = "record_type,id,created_at,updated_at,comma,quote,"
            + "line_breaks,turkish,empty_text,missing_text,count,amount,negative_zero,enabled"
        let expectedRow = "body_metric,aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee,"
            + "2024-01-02T03:04:05.123000Z,2024-01-02T03:04:05.123000Z,"
            + "\"a,b\",\"a\"\"b\",\"CR\rLF\nBOTH\r\n\",\"İstanbul, ölçüm 💪\",\"\",,"
            + "-42,12.5,-0.0,true"
        let expected = [expectedHeader, expectedRow].joined(separator: "\r\n") + "\r\n"

        XCTAssertEqual(Array(encoded.utf8), Array(expected.utf8))
        XCTAssertEqual(Array(encoded.utf8.suffix(2)), [0x0d, 0x0a])
    }

    func testFormulaNeutralizationAndInverseAreUnambiguousForEveryLeadingScalar() {
        let cases: [(original: String, encoded: String)] = [
            ("=SUM(A1:A2)", "'=SUM(A1:A2)"),
            ("=\u{20DD}1", "'=\u{20DD}1"),
            ("+1", "'+1"),
            ("-1", "'-1"),
            ("@name", "'@name"),
            ("\tformula", "'\tformula"),
            ("\rformula", "'\rformula"),
            ("'literal", "''literal"),
            ("'\u{20DD}literal", "''\u{20DD}literal"),
            ("'=\u{20DD}formula", "''=\u{20DD}formula"),
            ("''literal", "'''literal"),
            ("\u{0301}=not-leading", "\u{0301}=not-leading"),
            ("ordinary", "ordinary"),
            ("", ""),
        ]

        for value in cases {
            XCTAssertEqual(CSVFormulaTextCodecV1.neutralize(value.original), value.encoded)
            XCTAssertEqual(CSVFormulaTextCodecV1.restore(value.encoded), value.original)
        }
        XCTAssertEqual(CSVFormulaTextCodecV1.restore("'ordinary"), "'ordinary")
    }

    func testRejectsEveryNonFiniteDecimalBeforeReturningBytes() throws {
        for value in [Double.nan, .infinity, -.infinity] {
            let table = try decimalTable(value)
            XCTAssertThrowsError(try RFC4180CSVEncoder().encode(table)) { error in
                XCTAssertEqual(error as? RFC4180CSVEncodingError, .nonFiniteDecimal)
            }
        }
    }

    func testSortsRowsByRecordTypePrimaryTimestampUUIDAndProducesDeterministicBytes() throws {
        let firstDate = Date(timeIntervalSince1970: 1_000)
        let secondDate = Date(timeIntervalSince1970: 2_000)
        let lowerID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let higherID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let columns = try baseColumns()
        let rows = try [
            row(recordType: "z_record", id: lowerID, date: firstDate, columns: columns),
            row(recordType: "a_record", id: higherID, date: secondDate, columns: columns),
            row(recordType: "a_record", id: higherID, date: firstDate, columns: columns),
            row(recordType: "a_record", id: lowerID, date: firstDate, columns: columns),
        ]
        let tableA = try ExportTableV1(module: .metrics, columns: columns, rows: rows)
        let tableB = try ExportTableV1(
            module: .metrics,
            columns: columns,
            rows: Array(rows.reversed())
        )

        let bytesA = try RFC4180CSVEncoder().encode(tableA)
        let bytesB = try RFC4180CSVEncoder().encode(tableB)

        XCTAssertEqual(bytesA, bytesB)
        let records = String(decoding: bytesA, as: UTF8.self)
            .components(separatedBy: "\r\n")
            .dropFirst()
            .filter { !$0.isEmpty }
        XCTAssertEqual(records.map { $0.components(separatedBy: ",")[1] }, [
            lowerID.uuidString.lowercased(),
            higherID.uuidString.lowercased(),
            higherID.uuidString.lowercased(),
            lowerID.uuidString.lowercased(),
        ])
        XCTAssertEqual(records.map { $0.components(separatedBy: ",")[0] }, [
            "a_record", "a_record", "a_record", "z_record",
        ])
    }

    func testEmptyTableContainsStableHeaderAndFinalCRLF() throws {
        let table = try ExportTableV1(
            module: .health,
            columns: try baseColumns(),
            rows: []
        )
        let encoder = RFC4180CSVEncoder()

        let first = try encoder.encode(table)
        let second = try encoder.encode(table)

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            String(decoding: first, as: UTF8.self),
            "record_type,id,created_at,updated_at\r\n"
        )
    }

    func testDecimalScientificPolicyAndFinalTieBreakAreCanonical() throws {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let columns = try baseColumns() + [
            ExportColumnV1(name: "magnitude", type: .decimal, isNullable: false),
            ExportColumnV1(name: "derived", type: .text, isNullable: false),
        ]
        func tiedRow(_ magnitude: Double, _ derived: String) throws -> ExportRowV1 {
            try ExportRowV1(
                primaryTimestamp: timestamp,
                cells: baseCells(recordType: "body_metric", id: id, timestamp: timestamp) + [
                    .init(columnName: "magnitude", value: .decimal(magnitude)),
                    .init(columnName: "derived", value: .text(derived)),
                ]
            )
        }
        let table = try ExportTableV1(module: .metrics, columns: columns, rows: [
            tiedRow(1e-100, "z"), tiedRow(1e100, "a"), tiedRow(1e100, "a"),
        ])

        let first = try RFC4180CSVEncoder().encode(table)
        let secondTable = try ExportTableV1(
            module: .metrics,
            columns: columns,
            rows: Array(table.rows.reversed())
        )
        let second = try RFC4180CSVEncoder().encode(secondTable)

        XCTAssertEqual(first, second)
        let records = String(decoding: first, as: UTF8.self)
            .components(separatedBy: "\r\n").dropFirst().filter { !$0.isEmpty }
        XCTAssertEqual(records.map { $0.components(separatedBy: ",")[4] }, [
            "1e+100", "1e+100", "1e-100",
        ])
        XCTAssertEqual(records.map { $0.components(separatedBy: ",")[5] }, ["a", "a", "z"])
    }

    private func decimalTable(_ value: Double) throws -> ExportTableV1 {
        let timestamp = Date(timeIntervalSince1970: 0)
        let id = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        let columns = try baseColumns() + [
            ExportColumnV1(name: "amount", type: .decimal, isNullable: false),
        ]
        let row = try ExportRowV1(
            primaryTimestamp: timestamp,
            cells: baseCells(recordType: "body_metric", id: id, timestamp: timestamp) + [
                .init(columnName: "amount", value: .decimal(value)),
            ]
        )
        return try ExportTableV1(module: .metrics, columns: columns, rows: [row])
    }

    private func row(
        recordType: String,
        id: UUID,
        date: Date,
        columns: [ExportColumnV1]
    ) throws -> ExportRowV1 {
        XCTAssertEqual(columns.count, 4)
        return try ExportRowV1(
            primaryTimestamp: date,
            cells: baseCells(recordType: recordType, id: id, timestamp: date)
        )
    }

    private func baseColumns() throws -> [ExportColumnV1] {
        try [
            ExportColumnV1(name: "record_type", type: .text, isNullable: false),
            ExportColumnV1(name: "id", type: .uuid, isNullable: false),
            ExportColumnV1(name: "created_at", type: .timestamp, isNullable: false),
            ExportColumnV1(name: "updated_at", type: .timestamp, isNullable: false),
        ]
    }

    private func baseCells(recordType: String, id: UUID, timestamp: Date) -> [ExportNamedCellV1] {
        [
            .init(columnName: "record_type", value: .text(recordType)),
            .init(columnName: "id", value: .uuid(id)),
            .init(columnName: "created_at", value: .timestamp(timestamp)),
            .init(columnName: "updated_at", value: .timestamp(timestamp)),
        ]
    }
}
