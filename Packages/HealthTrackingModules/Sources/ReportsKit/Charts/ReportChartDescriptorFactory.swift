import Accessibility
import Foundation
import SwiftUI

public struct ReportChartObservation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let value: Double

    public init(id: UUID, date: Date, value: Double) {
        self.id = id
        self.date = date
        self.value = value
    }
}

public struct ReportChartSeries: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let observations: [ReportChartObservation]

    public init(
        id: String,
        name: String,
        observations: [ReportChartObservation]
    ) {
        self.id = id
        self.name = name
        self.observations = observations.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
        }
    }
}

public struct ReportTextTableRow: Equatable, Sendable {
    public let seriesName: String
    public let date: Date
    public let value: Double
    public let unit: String

    public init(seriesName: String, date: Date, value: Double, unit: String) {
        self.seriesName = seriesName
        self.date = date
        self.value = value
        self.unit = unit
    }
}

public struct ReportChartModel: Equatable, Sendable {
    public let title: String
    public let summary: String
    public let xAxisTitle: String
    public let yAxisTitle: String
    public let unit: String
    public let series: [ReportChartSeries]
    public let coverage: ReportCoverage

    public init(
        title: String,
        summary: String,
        xAxisTitle: String,
        yAxisTitle: String,
        unit: String,
        series: [ReportChartSeries]
    ) {
        self.title = title
        self.summary = summary
        self.xAxisTitle = xAxisTitle
        self.yAxisTitle = yAxisTitle
        self.unit = unit
        self.series = series
        coverage = ReportCoverage(
            observationDates: series.flatMap { $0.observations.map(\.date) }
        )
    }

    public var isTrendEligible: Bool { coverage.observedCount >= 2 }

    public var finalObservations: [ReportChartObservation] {
        series.compactMap { $0.observations.last }
    }

    public var tableRows: [ReportTextTableRow] {
        series.flatMap { series in
            series.observations.map {
                ReportTextTableRow(
                    seriesName: series.name,
                    date: $0.date,
                    value: $0.value,
                    unit: unit
                )
            }
        }
    }
}

public enum ReportChartKind: Equatable, Sendable {
    case line
    case bar
}

public struct ReportChartDescriptor: AXChartDescriptorRepresentable {
    public let model: ReportChartModel
    public let kind: ReportChartKind
    public let calendar: Calendar
    public let locale: Locale

    public func makeChartDescriptor() -> AXChartDescriptor {
        let dates = model.series.flatMap { $0.observations.map(\.date) }
        let values = model.series.flatMap { $0.observations.map(\.value) }
        let xAxis = AXNumericDataAxisDescriptor(
            title: model.xAxisTitle,
            range: Self.dateAxisRange(dates),
            gridlinePositions: []
        ) { value in
            Self.dateDescription(
                Date(timeIntervalSinceReferenceDate: value),
                calendar: calendar,
                locale: locale
            )
        }
        let yAxis = AXNumericDataAxisDescriptor(
            title: model.yAxisTitle,
            range: Self.valueAxisRange(values),
            gridlinePositions: []
        ) { value in
            Self.valueDescription(value, unit: model.unit, locale: locale)
        }
        let dataSeries = model.series.map { series in
            AXDataSeriesDescriptor(
                name: series.name,
                isContinuous: kind == .line,
                dataPoints: series.observations.map { observation in
                    AXDataPoint(
                        x: observation.date.timeIntervalSinceReferenceDate,
                        y: observation.value,
                        label: Self.pointDescription(
                            date: observation.date,
                            value: observation.value,
                            unit: model.unit,
                            calendar: calendar,
                            locale: locale
                        )
                    )
                }
            )
        }
        return AXChartDescriptor(
            title: model.title,
            summary: model.summary,
            xAxis: xAxis,
            yAxis: yAxis,
            series: dataSeries
        )
    }

    private static func dateAxisRange(_ dates: [Date]) -> ClosedRange<Double> {
        guard let minimum = dates.min()?.timeIntervalSinceReferenceDate,
              let maximum = dates.max()?.timeIntervalSinceReferenceDate else {
            return 0...1
        }
        guard minimum == maximum else { return minimum...maximum }
        let halfDay: TimeInterval = 12 * 60 * 60
        return (minimum - halfDay)...(maximum + halfDay)
    }

    private static func valueAxisRange(_ values: [Double]) -> ClosedRange<Double> {
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }
        guard minimum == maximum else { return minimum...maximum }
        let padding = max(abs(minimum) * 0.05, 1)
        return (minimum - padding)...(maximum + padding)
    }

    static func dateDescription(
        _ date: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: date)
    }

    static func valueDescription(
        _ value: Double,
        unit: String,
        locale: Locale
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSNumber(value: value)) ?? String(value)
        guard !unit.isEmpty else { return number }
        return localizedFormat(
            "reports.format.value_unit",
            locale: locale,
            number,
            unit
        )
    }

    static func pointDescription(
        date: Date,
        value: Double,
        unit: String,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        localizedFormat(
            "reports.format.chart_point",
            locale: locale,
            dateDescription(date, calendar: calendar, locale: locale),
            valueDescription(value, unit: unit, locale: locale)
        )
    }

    static func finalValueDescription(
        seriesName: String,
        value: Double,
        unit: String,
        locale: Locale
    ) -> String {
        localizedFormat(
            "reports.format.series_value",
            locale: locale,
            seriesName,
            valueDescription(value, unit: unit, locale: locale)
        )
    }

    static func tableRowDescription(
        date: Date,
        value: Double,
        unit: String,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        localizedFormat(
            "reports.format.table_row",
            locale: locale,
            dateDescription(date, calendar: calendar, locale: locale),
            valueDescription(value, unit: unit, locale: locale)
        )
    }

    static func multiUnitTitle(
        title: String,
        unit: String,
        locale: Locale
    ) -> String {
        localizedFormat(
            "reports.format.multi_unit_title",
            locale: locale,
            title,
            unit
        )
    }

    private static func localizedFormat(
        _ key: String.LocalizationValue,
        locale: Locale,
        _ arguments: CVarArg...
    ) -> String {
        ReportsLocalization.format(
            key,
            locale: locale,
            arguments: arguments
        )
    }
}

public enum ReportChartDescriptorFactory {
    public static func line(
        title: String,
        summary: String,
        xAxisTitle: String,
        yAxisTitle: String,
        unit: String,
        series: [ReportChartSeries],
        calendar: Calendar,
        locale: Locale = .current
    ) -> ReportChartDescriptor {
        ReportChartDescriptor(
            model: ReportChartModel(
                title: title,
                summary: summary,
                xAxisTitle: xAxisTitle,
                yAxisTitle: yAxisTitle,
                unit: unit,
                series: series
            ),
            kind: .line,
            calendar: calendar,
            locale: locale
        )
    }

    public static func bar(
        title: String,
        summary: String,
        xAxisTitle: String,
        yAxisTitle: String,
        unit: String,
        series: [ReportChartSeries],
        calendar: Calendar,
        locale: Locale = .current
    ) -> ReportChartDescriptor {
        ReportChartDescriptor(
            model: ReportChartModel(
                title: title,
                summary: summary,
                xAxisTitle: xAxisTitle,
                yAxisTitle: yAxisTitle,
                unit: unit,
                series: series
            ),
            kind: .bar,
            calendar: calendar,
            locale: locale
        )
    }
}
