import CoreFoundation
import CryptoKit
import Foundation
@testable import ReportsKit
import XCTest

@MainActor
final class M4ExportRoundTripTests: XCTestCase {
    func testJSONNativeCellsRoundTripEveryRecordTypeToExactTables() throws {
        let snapshot = try makeSnapshot()
        let encoded = try JSONExportEncoderV1().encode(snapshot)
        let root = try jsonRoot(encoded)
        let tables = try dictionaryArray(root["tables"])
        var sawNull = false
        var sawText = false
        var sawInteger = false
        var sawDecimal = false
        var sawBoolean = false

        for table in tables {
            let columns = try dictionaryArray(table["columns"])
            let types = try Dictionary(uniqueKeysWithValues: columns.map { column in
                guard let name = column["name"] as? String,
                      let rawType = column["type"] as? String,
                      let type = ExportColumnTypeV1(rawValue: rawType) else {
                    throw RoundTripFailure.invalidJSON
                }
                return (name, type)
            })
            for row in try dictionaryArray(table["rows"]) {
                guard let cells = row["cells"] as? [String: Any] else {
                    throw RoundTripFailure.invalidJSON
                }
                for (name, type) in types {
                    guard let value = cells[name] else {
                        throw RoundTripFailure.invalidJSON
                    }
                    if value is NSNull {
                        sawNull = true
                        continue
                    }
                    switch type {
                    case .text, .timestamp, .uuid:
                        guard value is String else {
                            throw RoundTripFailure.invalidJSON
                        }
                        sawText = true
                    case .integer:
                        guard let number = value as? NSNumber,
                              CFGetTypeID(number) != CFBooleanGetTypeID() else {
                            throw RoundTripFailure.invalidJSON
                        }
                        sawInteger = true
                    case .decimal:
                        guard let number = value as? NSNumber,
                              CFGetTypeID(number) != CFBooleanGetTypeID() else {
                            throw RoundTripFailure.invalidJSON
                        }
                        sawDecimal = true
                    case .boolean:
                        guard let number = value as? NSNumber,
                              CFGetTypeID(number) == CFBooleanGetTypeID() else {
                            throw RoundTripFailure.invalidJSON
                        }
                        sawBoolean = true
                    }
                }
            }
        }

        XCTAssertTrue(sawNull)
        XCTAssertTrue(sawText)
        XCTAssertTrue(sawInteger)
        XCTAssertTrue(sawDecimal)
        XCTAssertTrue(sawBoolean)
        let decoded = try decodeJSONTables(encoded)
        XCTAssertEqual(decoded, snapshot.tables)
        XCTAssertEqual(recordTypes(in: decoded), Set(ExportRecordTypeV1.allCases))
    }

    func testCustomRFC4180DecoderRoundTripsAllTablesIncludingNullEmptyAndFormulaText() throws {
        let snapshot = try makeSnapshot()
        let decoded = try snapshot.tables.map { table in
            let encoded = try RFC4180CSVEncoder().encode(table)
            XCTAssertEqual(Array(encoded.suffix(2)), [0x0D, 0x0A])
            return try decodeCSVTable(encoded, module: table.module)
        }

        XCTAssertEqual(decoded, snapshot.tables)
        XCTAssertEqual(recordTypes(in: decoded), Set(ExportRecordTypeV1.allCases))
        let textValues = snapshot.tables.flatMap(\.rows).flatMap(\.cells).compactMap {
            if case let .text(value) = $0.value { return value }
            return nil
        }
        XCTAssertTrue(textValues.contains(""))
        XCTAssertTrue(textValues.contains { $0.hasPrefix("=") })
        XCTAssertTrue(snapshot.tables.flatMap(\.rows).flatMap(\.cells).contains {
            $0.value == .null
        })
        let parserWitness = try parseRFC4180(
            Data("başlık\r\n\"satır 1\r\nsatır 2\"\r\n".utf8)
        )
        XCTAssertEqual(parserWitness.count, 2)
        let embeddedCRLF = try XCTUnwrap(parserWitness.last?.first)
        XCTAssertTrue(embeddedCRLF.wasQuoted)
        XCTAssertEqual(embeddedCRLF.value, "satır 1\r\nsatır 2")
    }

    func testGeneratedZIPPassesPureInspectorManifestHashesAndAttachesHostedArtifact() async throws {
        let snapshot = try makeSnapshot()
        let coordinator = ReportExportCoordinator(
            repository: M4RoundTripRepository(snapshot: snapshot)
        )
        let token = try await coordinator.generate(
            ReportExportRequest(
                interval: snapshot.interval,
                modules: Set(ExportModuleV1.allCases),
                format: .bothZip,
                includesPhotos: false
            )
        )
        defer { XCTAssertTrue(token.cleanup()) }
        let archiveURL = try XCTUnwrap(token.shareURLs.first)
        let archive = try Data(contentsOf: archiveURL)
        let entries = try M4StoredZIPInspector.inspect(archive)
        let expected = Set(
            ExportModuleV1.allCases.map { "csv/\($0.rawValue).csv" }
                + ["json/export.json", "manifest.json"]
        )
        XCTAssertEqual(Set(entries.keys), expected)
        XCTAssertEqual(
            try decodeJSONTables(try XCTUnwrap(entries["json/export.json"])),
            snapshot.tables
        )

        let manifest = try JSONDecoder().decode(
            ExportManifestV1.self,
            from: XCTUnwrap(entries["manifest.json"])
        )
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.selectedModules, ExportModuleV1.allCases.map(\.rawValue))
        XCTAssertEqual(manifest.payloads.count, ExportModuleV1.allCases.count + 1)
        for payload in manifest.payloads {
            let bytes = try XCTUnwrap(entries[payload.relativePath])
            XCTAssertEqual(payload.byteSize, UInt64(bytes.count))
            XCTAssertEqual(
                payload.sha256,
                SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            )
        }

        let attachment = XCTAttachment(
            data: archive,
            uniformTypeIdentifier: "public.zip-archive"
        )
        attachment.name = "m4-round-trip-export.zip"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeSnapshot() throws -> ExportSnapshotV1 {
        let interval = ReportDateInterval(
            start: Date(timeIntervalSince1970: 1_767_225_600),
            endExclusive: Date(timeIntervalSince1970: 1_798_761_600)
        )
        let tables = try ExportModuleV1.allCases.map { module in
            let rows = try ExportRecordTypeV1.allCases.enumerated().compactMap {
                index, recordType in
                recordType.module == module
                    ? try fixtureRow(recordType: recordType, index: index)
                    : nil
            }
            return try ExportTableV1(
                module: module,
                columns: ExportSchemaV1.columns(for: module),
                rows: rows
            )
        }
        return try ExportSnapshotV1(
            interval: interval,
            selectedModules: Set(ExportModuleV1.allCases),
            tables: tables
        )
    }

    private func fixtureRow(
        recordType: ExportRecordTypeV1,
        index: Int
    ) throws -> ExportRowV1 {
        let definition = ExportSchemaV1.definition(for: recordType)
        let primary = Date(timeIntervalSince1970: 1_780_000_000 + Double(index * 600))
        let columns = ExportSchemaV1.columns(for: recordType.module)
        let owned = Dictionary(uniqueKeysWithValues: definition.fields.map { ($0.name, $0) })
        let cells = columns.enumerated().map { columnIndex, column in
            let value: ExportCellV1
            switch column.name {
            case "record_type": value = .text(recordType.rawValue)
            case "id": value = .uuid(fixtureUUID(index + 1))
            case "created_at":
                value = .timestamp(
                    definition.primaryTimestampColumn == column.name
                        ? primary
                        : primary.addingTimeInterval(-120)
                )
            case "updated_at":
                value = .timestamp(
                    definition.primaryTimestampColumn == column.name
                        ? primary
                        : primary.addingTimeInterval(120)
                )
            case "config_scope":
                value = recordType.isConfiguration ? .text("selected") : .null
            default:
                guard let field = owned[column.name] else {
                    value = .null
                    return ExportNamedCellV1(columnName: column.name, value: value)
                }
                if field.isNullable, (index + columnIndex).isMultiple(of: 4) {
                    value = .null
                } else {
                    value = fixtureValue(
                        type: field.type,
                        seed: index + columnIndex,
                        timestamp: definition.primaryTimestampColumn == column.name
                            ? primary
                            : primary.addingTimeInterval(Double(columnIndex))
                    )
                }
            }
            return ExportNamedCellV1(columnName: column.name, value: value)
        }
        return try ExportRowV1(primaryTimestamp: primary, cells: cells)
    }

    private func fixtureValue(
        type: ExportColumnTypeV1,
        seed: Int,
        timestamp: Date
    ) -> ExportCellV1 {
        switch type {
        case .text:
            if seed.isMultiple(of: 5) { return .text("") }
            if seed.isMultiple(of: 3) { return .text("=M4,\"satır\"\r\n") }
            return .text("İstanbul-\(seed)")
        case .integer: return .integer(Int64(seed + 10))
        case .decimal: return .decimal(Double(seed) + 0.5)
        case .boolean: return .boolean(seed.isMultiple(of: 2))
        case .timestamp: return .timestamp(timestamp)
        case .uuid: return .uuid(fixtureUUID(seed + 1_000))
        }
    }

    private func fixtureUUID(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-4000-8000-%012llx",
                Int64(value)
            )
        )!
    }

    private func jsonRoot(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["schemaVersion"] as? Int == 1 else {
            throw RoundTripFailure.invalidJSON
        }
        return root
    }

    private func dictionaryArray(_ value: Any?) throws -> [[String: Any]] {
        guard let value = value as? [[String: Any]] else {
            throw RoundTripFailure.invalidJSON
        }
        return value
    }

    private func decodeJSONTables(_ data: Data) throws -> [ExportTableV1] {
        let root = try jsonRoot(data)
        return try dictionaryArray(root["tables"]).map { object in
            guard let rawModule = object["module"] as? String,
                  let module = ExportModuleV1(rawValue: rawModule) else {
                throw RoundTripFailure.invalidJSON
            }
            let columns = try dictionaryArray(object["columns"]).map { column in
                guard let name = column["name"] as? String,
                      let rawType = column["type"] as? String,
                      let type = ExportColumnTypeV1(rawValue: rawType),
                      let nullable = column["isNullable"] as? Bool else {
                    throw RoundTripFailure.invalidJSON
                }
                return try ExportColumnV1(
                    name: name,
                    type: type,
                    isNullable: nullable
                )
            }
            let rows = try dictionaryArray(object["rows"]).map { row in
                guard let rawPrimary = row["primaryTimestamp"] as? String,
                      let cellsObject = row["cells"] as? [String: Any] else {
                    throw RoundTripFailure.invalidJSON
                }
                let cells = try columns.map { column in
                    guard let object = cellsObject[column.name] else {
                        throw RoundTripFailure.invalidJSON
                    }
                    return ExportNamedCellV1(
                        columnName: column.name,
                        value: try decodeJSONCell(object, type: column.type)
                    )
                }
                return try ExportRowV1(
                    primaryTimestamp: try timestamp(rawPrimary),
                    cells: cells
                )
            }
            return try ExportTableV1(module: module, columns: columns, rows: rows)
        }
    }

    private func decodeJSONCell(
        _ object: Any,
        type: ExportColumnTypeV1
    ) throws -> ExportCellV1 {
        if object is NSNull { return .null }
        switch type {
        case .text:
            guard let value = object as? String else { throw RoundTripFailure.invalidJSON }
            return .text(value)
        case .integer:
            guard let value = object as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID() else {
                throw RoundTripFailure.invalidJSON
            }
            return .integer(value.int64Value)
        case .decimal:
            guard let value = object as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID() else {
                throw RoundTripFailure.invalidJSON
            }
            return .decimal(value.doubleValue)
        case .boolean:
            guard let value = object as? NSNumber,
                  CFGetTypeID(value) == CFBooleanGetTypeID() else {
                throw RoundTripFailure.invalidJSON
            }
            return .boolean(value.boolValue)
        case .timestamp:
            guard let value = object as? String else { throw RoundTripFailure.invalidJSON }
            return .timestamp(try timestamp(value))
        case .uuid:
            guard let value = object as? String,
                  let identifier = UUID(uuidString: value) else {
                throw RoundTripFailure.invalidJSON
            }
            return .uuid(identifier)
        }
    }

    private func decodeCSVTable(
        _ data: Data,
        module: ExportModuleV1
    ) throws -> ExportTableV1 {
        let records = try parseRFC4180(data)
        let columns = ExportSchemaV1.columns(for: module)
        guard let header = records.first,
              header.map(\.value) == columns.map(\.name) else {
            throw RoundTripFailure.invalidCSV
        }
        let rows = try records.dropFirst().map { fields in
            guard fields.count == columns.count else {
                throw RoundTripFailure.invalidCSV
            }
            let cells = try zip(fields, columns).map { field, column in
                ExportNamedCellV1(
                    columnName: column.name,
                    value: try decodeCSVCell(field, column: column)
                )
            }
            guard case let .text(rawType) = cells[0].value,
                  let type = ExportRecordTypeV1(rawValue: rawType),
                  let primary = cells.first(where: {
                      $0.columnName == ExportSchemaV1.definition(for: type)
                        .primaryTimestampColumn
                  }), case let .timestamp(primaryTimestamp) = primary.value else {
                throw RoundTripFailure.invalidCSV
            }
            return try ExportRowV1(primaryTimestamp: primaryTimestamp, cells: cells)
        }
        return try ExportTableV1(module: module, columns: columns, rows: rows)
    }

    private func decodeCSVCell(
        _ field: CSVField,
        column: ExportColumnV1
    ) throws -> ExportCellV1 {
        if field.value.isEmpty, !field.wasQuoted {
            guard column.isNullable else { throw RoundTripFailure.invalidCSV }
            return .null
        }
        switch column.type {
        case .text: return .text(CSVFormulaTextCodecV1.restore(field.value))
        case .integer:
            guard let value = Int64(field.value) else { throw RoundTripFailure.invalidCSV }
            return .integer(value)
        case .decimal:
            guard let value = Double(field.value), value.isFinite else {
                throw RoundTripFailure.invalidCSV
            }
            return .decimal(value)
        case .boolean:
            if field.value == "true" { return .boolean(true) }
            if field.value == "false" { return .boolean(false) }
            throw RoundTripFailure.invalidCSV
        case .timestamp: return .timestamp(try timestamp(field.value))
        case .uuid:
            guard let value = UUID(uuidString: field.value) else {
                throw RoundTripFailure.invalidCSV
            }
            return .uuid(value)
        }
    }

    private func parseRFC4180(_ data: Data) throws -> [[CSVField]] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw RoundTripFailure.invalidCSV
        }
        let scalars = Array(text.unicodeScalars)
        var records: [[CSVField]] = []
        var record: [CSVField] = []
        var value = ""
        var quoted = false
        var wasQuoted = false
        var index = 0

        func field() -> CSVField { CSVField(value: value, wasQuoted: wasQuoted) }
        while index < scalars.count {
            let scalar = scalars[index]
            if quoted {
                if scalar.value == 0x22 {
                    if index + 1 < scalars.count, scalars[index + 1].value == 0x22 {
                        value.unicodeScalars.append(scalar)
                        index += 1
                    } else {
                        quoted = false
                    }
                } else {
                    value.unicodeScalars.append(scalar)
                }
            } else if scalar.value == 0x22 {
                guard value.isEmpty, !wasQuoted else {
                    throw RoundTripFailure.invalidCSV
                }
                quoted = true
                wasQuoted = true
            } else if scalar.value == 0x2C {
                record.append(field())
                value = ""
                wasQuoted = false
            } else if scalar.value == 0x0D {
                guard index + 1 < scalars.count,
                      scalars[index + 1].value == 0x0A else {
                    throw RoundTripFailure.invalidCSV
                }
                record.append(field())
                records.append(record)
                record = []
                value = ""
                wasQuoted = false
                index += 1
            } else if scalar.value == 0x0A {
                throw RoundTripFailure.invalidCSV
            } else {
                value.unicodeScalars.append(scalar)
            }
            index += 1
        }
        guard !quoted, record.isEmpty, value.isEmpty, !records.isEmpty else {
            throw RoundTripFailure.invalidCSV
        }
        return records
    }

    private func timestamp(_ raw: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        guard let date = formatter.date(from: raw) else {
            throw RoundTripFailure.invalidTimestamp
        }
        return date
    }

    private func recordTypes(in tables: [ExportTableV1]) -> Set<ExportRecordTypeV1> {
        Set(tables.flatMap(\.rows).compactMap { row in
            guard case let .text(raw) = row.cells[0].value else { return nil }
            return ExportRecordTypeV1(rawValue: raw)
        })
    }
}

private struct CSVField {
    let value: String
    let wasQuoted: Bool
}

private enum RoundTripFailure: Error {
    case invalidJSON
    case invalidCSV
    case invalidTimestamp
    case invalidZIP
}

@MainActor
private final class M4RoundTripRepository: ReportsExportRepository {
    let snapshot: ExportSnapshotV1

    init(snapshot: ExportSnapshotV1) {
        self.snapshot = snapshot
    }

    func fetchExportSnapshot(
        in interval: ReportDateInterval,
        modules: Set<ExportModuleV1>
    ) async throws -> ExportSnapshotV1 {
        guard interval == snapshot.interval,
              modules == Set(snapshot.selectedModules) else {
            throw RoundTripFailure.invalidZIP
        }
        return snapshot
    }
}

private enum M4StoredZIPInspector {
    static func inspect(_ bytes: Data) throws -> [String: Data] {
        guard bytes.count >= 22 else { throw RoundTripFailure.invalidZIP }
        let minimum = max(0, bytes.count - 65_557)
        var endOffset = bytes.count - 22
        while endOffset >= minimum, try uint32(bytes, at: endOffset) != 0x0605_4b50 {
            endOffset -= 1
        }
        guard endOffset >= minimum,
              try uint32(bytes, at: endOffset) == 0x0605_4b50 else {
            throw RoundTripFailure.invalidZIP
        }
        let entryCount = Int(try uint16(bytes, at: endOffset + 10))
        let centralSize = Int(try uint32(bytes, at: endOffset + 12))
        let centralOffset = Int(try uint32(bytes, at: endOffset + 16))
        let commentLength = Int(try uint16(bytes, at: endOffset + 20))
        guard endOffset + 22 + commentLength == bytes.count,
              centralOffset + centralSize == endOffset else {
            throw RoundTripFailure.invalidZIP
        }

        var result: [String: Data] = [:]
        var cursor = centralOffset
        for _ in 0..<entryCount {
            guard try uint32(bytes, at: cursor) == 0x0201_4b50 else {
                throw RoundTripFailure.invalidZIP
            }
            let method = try uint16(bytes, at: cursor + 10)
            let checksum = try uint32(bytes, at: cursor + 16)
            let compressedSize = Int(try uint32(bytes, at: cursor + 20))
            let uncompressedSize = Int(try uint32(bytes, at: cursor + 24))
            let nameLength = Int(try uint16(bytes, at: cursor + 28))
            let extraLength = Int(try uint16(bytes, at: cursor + 30))
            let entryCommentLength = Int(try uint16(bytes, at: cursor + 32))
            let localOffset = Int(try uint32(bytes, at: cursor + 42))
            let nameStart = cursor + 46
            let name = try string(bytes, from: nameStart, count: nameLength)
            guard method == 0,
                  compressedSize == uncompressedSize,
                  !name.hasPrefix("/"),
                  !name.split(separator: "/").contains(".."),
                  result[name] == nil,
                  try uint32(bytes, at: localOffset) == 0x0403_4b50,
                  try uint16(bytes, at: localOffset + 8) == 0 else {
                throw RoundTripFailure.invalidZIP
            }
            let localNameLength = Int(try uint16(bytes, at: localOffset + 26))
            let localExtraLength = Int(try uint16(bytes, at: localOffset + 28))
            let localName = try string(
                bytes,
                from: localOffset + 30,
                count: localNameLength
            )
            guard localName == name else { throw RoundTripFailure.invalidZIP }
            let payloadStart = localOffset + 30 + localNameLength + localExtraLength
            let payloadEnd = payloadStart + uncompressedSize
            guard payloadEnd <= bytes.count else { throw RoundTripFailure.invalidZIP }
            let payload = bytes.subdata(in: payloadStart..<payloadEnd)
            guard crc32(payload) == checksum else { throw RoundTripFailure.invalidZIP }
            result[name] = payload
            cursor = nameStart + nameLength + extraLength + entryCommentLength
        }
        guard cursor == centralOffset + centralSize else {
            throw RoundTripFailure.invalidZIP
        }
        return result
    }

    private static func uint16(_ data: Data, at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else {
            throw RoundTripFailure.invalidZIP
        }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func uint32(_ data: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else {
            throw RoundTripFailure.invalidZIP
        }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func string(
        _ data: Data,
        from offset: Int,
        count: Int
    ) throws -> String {
        guard offset >= 0, count >= 0, offset + count <= data.count,
              let value = String(data: data.subdata(in: offset..<(offset + count)), encoding: .utf8) else {
            throw RoundTripFailure.invalidZIP
        }
        return value
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var checksum = UInt32.max
        for byte in data {
            checksum ^= UInt32(byte)
            for _ in 0..<8 {
                checksum = (checksum >> 1)
                    ^ (checksum & 1 == 1 ? 0xedb8_8320 : 0)
            }
        }
        return checksum ^ UInt32.max
    }
}
