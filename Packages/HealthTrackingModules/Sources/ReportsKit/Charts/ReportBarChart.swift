import Charts
import DesignSystem
import SwiftUI

public struct ReportBarChart: View {
    @Environment(\.colorScheme) private var colorScheme
    private let descriptor: ReportChartDescriptor

    public init(descriptor: ReportChartDescriptor) {
        self.descriptor = descriptor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            Chart {
                ForEach(descriptor.model.series) { series in
                    ForEach(series.observations) { observation in
                        BarMark(
                            x: .value(descriptor.model.xAxisTitle, observation.date),
                            y: .value(descriptor.model.yAxisTitle, observation.value)
                        )
                        .foregroundStyle(
                            AppColors.color(.accentAction, scheme: colorScheme)
                        )
                        .accessibilityLabel(series.name)
                        .accessibilityValue(
                            ReportChartDescriptor.valueDescription(
                                observation.value,
                                unit: descriptor.model.unit,
                                locale: descriptor.locale
                            )
                        )
                    }

                    if let final = series.observations.last {
                        PointMark(
                            x: .value(descriptor.model.xAxisTitle, final.date),
                            y: .value(descriptor.model.yAxisTitle, final.value)
                        )
                        .foregroundStyle(
                            AppColors.color(.inkPrimary, scheme: colorScheme)
                        )
                        .annotation(position: .top) {
                            Text(finalLabel(series: series, observation: final))
                                .font(AppTypography.micro)
                                .foregroundStyle(
                                    AppColors.color(.inkPrimary, scheme: colorScheme)
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .chartXAxisLabel(descriptor.model.xAxisTitle)
            .chartYAxisLabel(descriptor.model.yAxisTitle)
            .frame(minHeight: 180)
            .accessibilityChartDescriptor(descriptor)
            .accessibilityIdentifier("reports.chart.\(chartIdentifier)")

            ReportTextTable(descriptor: descriptor)
        }
    }

    private var chartIdentifier: String {
        descriptor.model.series.first?.id ?? "empty"
    }

    private func finalLabel(
        series: ReportChartSeries,
        observation: ReportChartObservation
    ) -> String {
        ReportChartDescriptor.finalValueDescription(
            seriesName: series.name,
            value: observation.value,
            unit: descriptor.model.unit,
            locale: descriptor.locale
        )
    }
}
