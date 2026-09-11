import Charts
import DesignSystem
import SwiftUI

public struct ReportLineChart: View {
    @Environment(\.colorScheme) private var colorScheme
    private let descriptor: ReportChartDescriptor

    public init(descriptor: ReportChartDescriptor) {
        self.descriptor = descriptor
    }

    public var body: some View {
        ReportChartLayout(descriptor: descriptor, basePlotHeight: 180) {
            Chart {
                ForEach(descriptor.model.series) { series in
                    ForEach(series.observations) { observation in
                        LineMark(
                            x: .value(descriptor.model.xAxisTitle, observation.date),
                            y: .value(descriptor.model.yAxisTitle, observation.value),
                            series: .value(
                                String(localized: "reports.chart.series", bundle: .module),
                                series.name
                            )
                        )
                        .foregroundStyle(
                            AppColors.color(.accentAction, scheme: colorScheme)
                        )
                        .symbol(by: .value(
                            String(localized: "reports.chart.series", bundle: .module),
                            series.id
                        ))
                    }

                    if let final = series.observations.last {
                        PointMark(
                            x: .value(descriptor.model.xAxisTitle, final.date),
                            y: .value(descriptor.model.yAxisTitle, final.value)
                        )
                        .foregroundStyle(
                            AppColors.color(.inkPrimary, scheme: colorScheme)
                        )
                        .symbol(by: .value(
                            String(localized: "reports.chart.series", bundle: .module),
                            series.id
                        ))
                    }
                }
            }
            .accessibilityChartDescriptor(descriptor)
            .accessibilityLabel(descriptor.model.title)
            .accessibilityIdentifier("reports.chart.\(chartIdentifier)")
        }
    }

    private var chartIdentifier: String {
        descriptor.model.series.first?.id ?? "empty"
    }
}
