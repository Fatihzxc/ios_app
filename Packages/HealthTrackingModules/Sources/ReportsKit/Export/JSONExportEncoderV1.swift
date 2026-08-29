import Foundation

public enum JSONExportEncodingError: Error, Equatable, Sendable {
    case nonFiniteDecimal
    case invalidTimestamp
    case invalidJSONObject
}

public struct JSONExportEncoderV1: Sendable {
    public init() {}

    public func encode(_ snapshot: ExportSnapshotV1) throws -> Data {
        let root: [String: Any] = [
            "schemaVersion": snapshot.schemaVersion,
            "interval": [
                "start": try timestamp(snapshot.interval.start),
                "endExclusive": try timestamp(snapshot.interval.endExclusive),
            ],
            "selectedModules": snapshot.selectedModules.map(\.rawValue),
            "tables": try snapshot.tables.map(encodeTable),
        ]
        guard JSONSerialization.isValidJSONObject(root) else {
            throw JSONExportEncodingError.invalidJSONObject
        }
        do {
            return try JSONSerialization.data(
                withJSONObject: root,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            throw JSONExportEncodingError.invalidJSONObject
        }
    }

    private func encodeTable(_ table: ExportTableV1) throws -> [String: Any] {
        [
            "module": table.module.rawValue,
            "columns": table.columns.map { column in
                [
                    "name": column.name,
                    "type": column.type.rawValue,
                    "isNullable": column.isNullable,
                ] as [String: Any]
            },
            "rows": try table.rows.map { row in
                var cells: [String: Any] = [:]
                cells.reserveCapacity(row.cells.count)
                for cell in row.cells {
                    cells[cell.columnName] = try encodeCell(cell.value)
                }
                return [
                    "primaryTimestamp": try timestamp(row.primaryTimestamp),
                    "cells": cells,
                ] as [String: Any]
            },
        ]
    }

    private func encodeCell(_ cell: ExportCellV1) throws -> Any {
        switch cell {
        case .null:
            return NSNull()
        case let .text(value):
            return value
        case let .integer(value):
            return NSNumber(value: value)
        case let .decimal(value):
            guard value.isFinite else { throw JSONExportEncodingError.nonFiniteDecimal }
            return NSNumber(value: value)
        case let .boolean(value):
            return NSNumber(value: value)
        case let .timestamp(value):
            return try timestamp(value)
        case let .uuid(value):
            return value.uuidString.lowercased()
        }
    }

    private func timestamp(_ value: Date) throws -> String {
        do {
            return try CanonicalExportScalarV1.timestamp(value)
        } catch RFC4180CSVEncodingError.invalidTimestamp {
            throw JSONExportEncodingError.invalidTimestamp
        } catch {
            throw JSONExportEncodingError.invalidTimestamp
        }
    }
}
