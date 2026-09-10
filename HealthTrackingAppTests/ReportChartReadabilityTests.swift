import Charts
import ReportsKit
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class ReportChartReadabilityTests: XCTestCase {
    // These tests render the shipped chart, not a copied layout or an AX label.
    // Mutation caught: putting nearby endpoint labels back into overlapping
    // annotations makes their complete name/value text unreadable in the pixels.
    func testLineEndpointLabelsRemainReadableAtXXL() throws {
        try assertReadableEndpoints(kind: .line, size: .xxLarge, width: 361, name: "line-xxl")
    }

    func testLineEndpointLabelsRemainReadableAtAX3() throws {
        try assertReadableEndpoints(kind: .line, size: .accessibility3, width: 361, name: "line-ax3")
    }

    func testLineEndpointLabelsRemainReadableAtCompactAX5() throws {
        try assertReadableEndpoints(kind: .line, size: .accessibility5, width: 343, name: "line-compact-ax5")
    }

    func testBarEndpointLabelsRemainReadableAtCompactAX5() throws {
        try assertReadableEndpoints(kind: .bar, size: .accessibility5, width: 343, name: "bar-compact-ax5")
    }

    // Mutation caught: automatic date ticks can collapse to only an ellipsis
    // even when the plot and endpoint labels are readable. A reader must be
    // able to identify the displayed date range without opening the table.
    func testDateAxisRangeRemainsReadableAtAX3() throws {
        try assertReadableDateRange(kind: .line, size: .accessibility3, width: 361)
    }

    func testDateAxisRangeRemainsReadableAtCompactAX5() throws {
        for kind in [ReportChartKind.line, .bar] {
            try assertReadableDateRange(kind: kind, size: .accessibility5, width: 343)
        }
    }

    func testPixelTextReaderRecognizesFullDateRangeAtAX5() throws {
        let image = try render(
            VStack(alignment: .leading, spacing: 16) {
                ForEach(expectedDateRange, id: \.self) { date in
                    Text(date)
                        .font(.caption2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            },
            size: .accessibility5,
            width: 343
        )
        attach(image, name: "m4-chart-date-reader-calibration")
        let text = try recognizedText(in: image)
        for date in expectedDateRange {
            XCTAssertTrue(text.contains(normalized(date)), "Date OCR calibration missing \(date): \(text)")
        }
    }

    // Mutation caught: sizing the entire Chart instead of reserving real plot
    // space lets large axes/legend consume it. Read the real ChartProxy plot
    // geometry: tall text, symbols, or connectors cannot masquerade as the plot.
    func testPlotRetainsUsableHeightAtAX5() throws {
        for kind in [ReportChartKind.line, .bar] {
            let probe = PlotBoundsProbe()
            let image = try render(
                observingPlot(of: chart(kind: kind, wideValueRange: true), probe: probe),
                size: .accessibility5,
                width: 343
            )
            attach(image, name: "m4-chart-plot-\(kind)-ax5")
            let plot = try XCTUnwrap(probe.bounds, "Expected the shipped chart's actual plot frame.")
            XCTAssertGreaterThanOrEqual(
                plot.height,
                160,
                "The actual plot must retain at least 160pt of height, not collapse behind large axes/legend."
            )
        }
    }

    func testPlotProbeDoesNotCountTallNonDataGraphicsAsPlotSpace() throws {
        let probe = PlotBoundsProbe()
        let image = try render(
            observingPlot(
                of: Chart {
                    LineMark(x: .value("X", 0), y: .value("Y", 0))
                    LineMark(x: .value("X", 1), y: .value("Y", 1))
                }
                .chartPlotStyle { $0.frame(height: 24) }
                .overlay(alignment: .leading) {
                    Rectangle().fill(.orange).frame(width: 4, height: 300)
                }
                .padding(.vertical, 160),
                probe: probe
            ),
            size: .accessibility5,
            width: 343
        )
        attach(image, name: "m4-chart-plot-probe-calibration")
        let plot = try XCTUnwrap(probe.bounds)
        XCTAssertEqual(plot.height, 24, accuracy: 0.5)
        XCTAssertLessThan(plot.height, 160, "Tall non-data graphics must not satisfy the plot-height assertion.")
    }

    // Calibration distinguishes an unavailable/broken text-recognition harness
    // from the product defect. Expectations are literal, not formatter output.
    func testPixelTextReaderRecognizesSeparatedFullLabelsAtAX5() throws {
        let image = try render(
            VStack(alignment: .leading, spacing: 16) {
                ForEach(expectedLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            },
            size: .accessibility5,
            width: 343
        )
        attach(image, name: "m4-chart-text-reader-calibration")
        let text = try recognizedText(in: image)
        for label in expectedLabels {
            XCTAssertTrue(text.contains(normalized(label)), "OCR calibration missing \(label): \(text)")
        }
    }

    private let expectedLabels = [
        "Alpha: 79.4 kg", "Bravo: 79 kg", "Charlie: 82 kg", "Delta: 81 kg",
    ]

    // Independently read from the fixture: earliest Jan 1, latest Jan 8, 2024.
    private let expectedDateRange = ["Jan 1, 2024", "Jan 8, 2024"]

    private func assertReadableDateRange(
        kind: ReportChartKind,
        size: DynamicTypeSize,
        width: CGFloat
    ) throws {
        let image = try render(chart(kind: kind), size: size, width: width)
        attach(image, name: "m4-chart-date-range-\(kind)-\(size)")
        let text = try recognizedText(in: image)
        for date in expectedDateRange {
            XCTAssertTrue(
                text.contains(normalized(date)),
                "Rendered date range is missing or truncated: \(date). Recognized pixels: \(text)"
            )
        }
    }

    private func assertReadableEndpoints(
        kind: ReportChartKind,
        size: DynamicTypeSize,
        width: CGFloat,
        name: String
    ) throws {
        let image = try render(chart(kind: kind), size: size, width: width)
        attach(image, name: "m4-chart-readability-\(name)")
        let text = try recognizedText(in: image)
        for label in expectedLabels {
            XCTAssertTrue(
                text.contains(normalized(label)),
                "Rendered endpoint label is missing, clipped, or overlapped: \(label). Recognized pixels: \(text)"
            )
        }
    }

    private func chart(kind: ReportChartKind, wideValueRange: Bool = false) -> some View {
        let start = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 UTC
        let values: [Double] = wideValueRange ? [100, 80, 60, 40] : [79.4, 79, 82, 81]
        let names = ["Alpha", "Bravo", "Charlie", "Delta"]
        let series = names.enumerated().map { index, name in
            ReportChartSeries(
                id: name,
                name: name,
                observations: [
                    ReportChartObservation(
                        id: UUID(uuidString: "00000000-0000-4000-8000-00000000000\(index)")!,
                        date: start.addingTimeInterval(Double(index) * 86_400),
                        value: wideValueRange ? 0 : values[index] - 0.5
                    ),
                    ReportChartObservation(
                        id: UUID(uuidString: "00000000-0000-4000-8000-00000000001\(index)")!,
                        date: start.addingTimeInterval(Double(index + 4) * 86_400),
                        value: values[index]
                    ),
                ]
            )
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let descriptor = kind == .line
            ? ReportChartDescriptorFactory.line(
                title: "Weight", summary: "Eight observed measurements.",
                xAxisTitle: "Date", yAxisTitle: "Weight", unit: "kg",
                series: series, calendar: calendar, locale: Locale(identifier: "en_US")
            )
            : ReportChartDescriptorFactory.bar(
                title: "Weight", summary: "Eight observed measurements.",
                xAxisTitle: "Date", yAxisTitle: "Weight", unit: "kg",
                series: series, calendar: calendar, locale: Locale(identifier: "en_US")
            )
        return Group {
            if kind == .line {
                ReportLineChart(descriptor: descriptor)
            } else {
                ReportBarChart(descriptor: descriptor)
            }
        }
    }

    private func render<Content: View>(
        _ content: Content,
        size: DynamicTypeSize,
        width: CGFloat
    ) throws -> UIImage {
        let renderer = ImageRenderer(
            content: content
                .environment(\.dynamicTypeSize, size)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.colorScheme, .light)
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .background(Color.white)
        )
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage, "The real SwiftUI chart must render an image.")
        XCTAssertGreaterThan(image.size.height, 0)
        return image
    }

    private func recognizedText(in image: UIImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return normalized(lines.joined(separator: " "))
    }

    private func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }

    private func observingPlot<Content: View>(
        of content: Content,
        probe: PlotBoundsProbe
    ) -> some View {
        content.chartOverlay { proxy in
            GeometryReader { geometry in
                probe.observe(proxy.plotFrame.map { geometry[$0] })
            }
        }
    }

    private final class PlotBoundsProbe {
        var bounds: CGRect?

        // Test-only capture during synchronous rendering; no production hook,
        // SwiftUI state mutation, replacement data, or copied layout arithmetic.
        func observe(_ bounds: CGRect?) -> Color {
            self.bounds = bounds
            return .clear
        }
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
