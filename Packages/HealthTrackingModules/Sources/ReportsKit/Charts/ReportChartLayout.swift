import Charts
import DesignSystem
import SwiftUI

/// Endpoint labels participate in normal text layout, not the plot's annotation budget.
/// Anchor preferences connect their resolved positions to the actual final observations.
struct ReportChartLayout<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var plotGrowth: CGFloat = 40
    @ScaledMetric(relativeTo: .caption2) private var symbolSize: CGFloat = 10

    let descriptor: ReportChartDescriptor
    let basePlotHeight: CGFloat
    @ViewBuilder let content: Content

    private let leaderGutter: CGFloat = 32

    var body: some View {
        let dates = dateBoundaries
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                ForEach(descriptor.model.series) { series in
                    if let final = series.observations.last {
                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                            Self.symbol(for: series.id, in: descriptor)
                                .fill(AppColors.color(.inkPrimary, scheme: colorScheme))
                                .frame(width: symbolSize, height: symbolSize)
                                .accessibilityHidden(true)
                            Text(ReportChartDescriptor.finalValueDescription(
                                seriesName: series.name,
                                value: final.value,
                                unit: descriptor.model.unit,
                                locale: descriptor.locale
                            ))
                            .font(AppTypography.micro)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                        .anchorPreference(key: EndpointAnchors.self, value: .bounds) {
                            [.label(series.id): $0]
                        }
                    }
                }

                Text(descriptor.model.yAxisTitle)
                    .font(AppTypography.micro)
                    .fixedSize(horizontal: false, vertical: true)

                content
                    .chartLegend(.hidden) // Full-size rows above provide the symbol/name/value key.
                    .chartSymbolScale(
                        domain: descriptor.model.series.map(\.id),
                        range: descriptor.model.series.map { Self.symbol(for: $0.id, in: descriptor) }
                    )
                    .chartPlotStyle { plot in
                        plot.frame(height: basePlotHeight + plotGrowth)
                    }
                    .chartXAxis {
                        AxisMarks(values: dates) {
                            AxisGridLine()
                            AxisTick()
                            // The full date labels flow below and connect to these ticks.
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: dynamicTypeSize.isAccessibilitySize ? 3 : 5))
                    }
                    .chartBackground { proxy in
                        GeometryReader { geometry in
                            if let plotFrame = proxy.plotFrame {
                                let plot = geometry[plotFrame]
                                ForEach(descriptor.model.series) { series in
                                    if let final = series.observations.last,
                                       let x = proxy.position(forX: final.date),
                                       let y = proxy.position(forY: final.value) {
                                        Color.clear
                                            .frame(width: 1, height: 1)
                                            .anchorPreference(key: EndpointAnchors.self, value: .bounds) {
                                                [.point(series.id): $0]
                                            }
                                            .position(x: plot.minX + x, y: plot.minY + y)
                                        Color.clear
                                            .frame(width: 1, height: 1)
                                            .anchorPreference(key: EndpointAnchors.self, value: .bounds) {
                                                [.plotTop(series.id): $0]
                                            }
                                            .position(x: plot.minX + x, y: plot.minY)
                                    }
                                }
                                ForEach(dates, id: \.self) { date in
                                    if let x = proxy.position(forX: date) {
                                        Color.clear
                                            .frame(width: 1, height: 1)
                                            .anchorPreference(key: EndpointAnchors.self, value: .bounds) {
                                                [.datePoint(date): $0]
                                            }
                                            .position(x: plot.minX + x, y: plot.maxY)
                                    }
                                }
                            }
                        }
                    }
                    .transformAnchorPreference(key: EndpointAnchors.self, value: .bounds) { anchors, bounds in
                        // Preserve the point anchors emitted by the chart's descendants.
                        anchors[.chartBounds] = bounds
                    }
                    .padding(.top, leaderGutter)

                if !dates.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.standard) {
                        ForEach(dates, id: \.self) { date in
                            Text(ReportChartDescriptor.dateDescription(
                                date,
                                calendar: descriptor.calendar,
                                locale: descriptor.locale
                            ))
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                            .multilineTextAlignment(date == dates.first ? .leading : .trailing)
                            .fixedSize(horizontal: false, vertical: true)
                            .anchorPreference(key: EndpointAnchors.self, value: .bounds) {
                                [.dateLabel(date): $0]
                            }
                            .frame(maxWidth: .infinity, alignment: date == dates.first ? .leading : .trailing)
                        }
                    }
                    .padding(.top, leaderGutter)
                    .padding(.trailing, leaderGutter)
                }

                Text(descriptor.model.xAxisTitle)
                    .font(AppTypography.micro)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .padding(.leading, leaderGutter)
            .overlayPreferenceValue(EndpointAnchors.self) { anchors in
                GeometryReader { geometry in
                    Path { path in
                        for (index, series) in descriptor.model.series.enumerated() {
                            guard let label = anchors[.label(series.id)],
                                  let point = anchors[.point(series.id)],
                                  let top = anchors[.plotTop(series.id)] else { continue }
                            let labelBounds = geometry[label]
                            let pointBounds = geometry[point]
                            let plotTop = geometry[top]
                            let lane = leaderGutter * CGFloat(index + 1)
                                / CGFloat(descriptor.model.series.count + 1)
                            path.move(to: CGPoint(x: pointBounds.midX, y: pointBounds.midY))
                            // Leave through the plot's top, then the reserved corridor.
                            // A horizontal exit through the y axis would strike its labels.
                            path.addLine(to: CGPoint(x: pointBounds.midX, y: plotTop.midY - lane))
                            path.addLine(to: CGPoint(x: lane, y: plotTop.midY - lane))
                            path.addLine(to: CGPoint(x: lane, y: labelBounds.midY))
                            path.addLine(to: CGPoint(x: labelBounds.minX - 4, y: labelBounds.midY))
                        }
                        if let chart = anchors[.chartBounds] {
                            let corridorY = geometry[chart].maxY + leaderGutter / 2
                            for date in dates {
                                guard let label = anchors[.dateLabel(date)],
                                      let point = anchors[.datePoint(date)] else { continue }
                                let labelBounds = geometry[label]
                                let pointBounds = geometry[point]
                                let isStart = date == dates.first
                                // Opposite gutters keep chronological date leaders from crossing.
                                let laneX = isStart ? leaderGutter / 2 : geometry.size.width - leaderGutter / 2
                                let labelX = isStart ? labelBounds.minX - 4 : labelBounds.maxX + 4
                                path.move(to: CGPoint(x: pointBounds.midX, y: pointBounds.midY))
                                path.addLine(to: CGPoint(x: pointBounds.midX, y: corridorY))
                                path.addLine(to: CGPoint(x: laneX, y: corridorY))
                                path.addLine(to: CGPoint(x: laneX, y: labelBounds.midY))
                                path.addLine(to: CGPoint(x: labelX, y: labelBounds.midY))
                            }
                        }
                    }
                    .stroke(
                        AppColors.color(.inkSecondary, scheme: colorScheme),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            ReportTextTable(descriptor: descriptor)
        }
    }

    private var dateBoundaries: [Date] {
        let dates = descriptor.model.series.flatMap { $0.observations.map(\.date) }
        guard let start = dates.min(), let end = dates.max() else { return [] }
        return start == end ? [start] : [start, end]
    }

    static func symbol(for seriesID: String, in descriptor: ReportChartDescriptor) -> BasicChartSymbolShape {
        let shapes: [BasicChartSymbolShape] = [.circle, .square, .triangle, .diamond]
        let index = descriptor.model.series.firstIndex { $0.id == seriesID } ?? 0
        return shapes[index % shapes.count]
    }
}

private enum EndpointAnchor: Hashable {
    case label(String)
    case point(String)
    case plotTop(String)
    case dateLabel(Date)
    case datePoint(Date)
    case chartBounds
}

private struct EndpointAnchors: PreferenceKey {
    static var defaultValue: [EndpointAnchor: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [EndpointAnchor: Anchor<CGRect>],
        nextValue: () -> [EndpointAnchor: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
