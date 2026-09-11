import Accessibility
import Foundation
@testable import ReportsKit
import XCTest

final class ReportChartDescriptorTests: XCTestCase {
    func testLineDescriptorAndTablePreserveObservedZeroDatesUnitsGapsAndFinalValues() throws {
        let calendar = try utcCalendar()
        let firstDate = try date("2024-01-01T09:00:00Z")
        let secondDate = try date("2024-01-02T09:00:00Z")
        let afterGapDate = try date("2024-01-05T09:00:00Z")
        let firstID = UUID(uuidString: "00000000-0000-4000-8000-000000000801")!
        let secondID = UUID(uuidString: "00000000-0000-4000-8000-000000000802")!
        let thirdID = UUID(uuidString: "00000000-0000-4000-8000-000000000803")!

        let chart = ReportChartDescriptorFactory.line(
            title: "Weight",
            summary: "3 observations from 1 Jan 2024 to 5 Jan 2024; one recording gap.",
            xAxisTitle: "Date",
            yAxisTitle: "Weight",
            unit: "kg",
            series: [
                ReportChartSeries(
                    id: "weight.segment.1",
                    name: "Weight — segment 1",
                    observations: [
                        .init(id: firstID, date: firstDate, value: 0),
                        .init(id: secondID, date: secondDate, value: 71.25),
                    ]
                ),
                ReportChartSeries(
                    id: "weight.segment.2",
                    name: "Weight — segment 2",
                    observations: [
                        .init(id: thirdID, date: afterGapDate, value: 72.5),
                    ]
                ),
            ],
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(chart.model.title, "Weight")
        XCTAssertEqual(chart.model.summary, "3 observations from 1 Jan 2024 to 5 Jan 2024; one recording gap.")
        XCTAssertEqual(chart.model.xAxisTitle, "Date")
        XCTAssertEqual(chart.model.yAxisTitle, "Weight")
        XCTAssertEqual(chart.model.unit, "kg")
        XCTAssertEqual(chart.model.series.map(\.id), ["weight.segment.1", "weight.segment.2"])
        XCTAssertEqual(
            chart.model.series.map { $0.observations.map(\.date) },
            [[firstDate, secondDate], [afterGapDate]],
            "A missing-day gap must remain two series rather than becoming a connecting line."
        )
        XCTAssertEqual(
            chart.model.series.map { $0.observations.map(\.value) },
            [[0, 71.25], [72.5]],
            "An observed zero is data and no zero placeholder may be injected for the gap."
        )
        XCTAssertEqual(chart.model.coverage.observedCount, 3)
        XCTAssertEqual(chart.model.coverage.firstObservationAt, firstDate)
        XCTAssertEqual(chart.model.coverage.lastObservationAt, afterGapDate)
        XCTAssertTrue(chart.model.isTrendEligible)
        XCTAssertEqual(
            chart.model.finalObservations,
            [
                .init(id: secondID, date: secondDate, value: 71.25),
                .init(id: thirdID, date: afterGapDate, value: 72.5),
            ]
        )
        XCTAssertEqual(
            chart.model.tableRows,
            [
                .init(seriesName: "Weight — segment 1", date: firstDate, value: 0, unit: "kg"),
                .init(seriesName: "Weight — segment 1", date: secondDate, value: 71.25, unit: "kg"),
                .init(seriesName: "Weight — segment 2", date: afterGapDate, value: 72.5, unit: "kg"),
            ],
            "The visible fallback table must derive from the same deterministic immutable observations."
        )

        let descriptor: AXChartDescriptor = chart.makeChartDescriptor()
        XCTAssertEqual(descriptor.title, "Weight")
        XCTAssertEqual(descriptor.summary, chart.model.summary)
        XCTAssertEqual(descriptor.xAxis.title, "Date")
        XCTAssertEqual(descriptor.yAxis?.title, "Weight")
        XCTAssertEqual(descriptor.series.map(\.name), ["Weight — segment 1", "Weight — segment 2"])
        XCTAssertEqual(descriptor.series.map(\.isContinuous), [true, true])
        XCTAssertEqual(
            descriptor.series.map { series in series.dataPoints.compactMap(\.label) },
            [
                ["Jan 1, 2024, 0 kg", "Jan 2, 2024, 71.25 kg"],
                ["Jan 5, 2024, 72.5 kg"],
            ],
            "The real AX descriptor must preserve each exact model point as an audio-graph label."
        )
        XCTAssertEqual(descriptor.yAxis?.valueDescriptionProvider(72.5), "72.5 kg")
        XCTAssertEqual(
            (descriptor.xAxis as? AXNumericDataAxisDescriptor)?
                .valueDescriptionProvider(firstDate.timeIntervalSinceReferenceDate),
            "Jan 1, 2024"
        )
    }

    func testBarDescriptorUsesObservedBarsAndDoesNotDescribeOneObservationAsATrend() throws {
        let observedAt = try date("2024-02-10T12:00:00Z")
        let chart = ReportChartDescriptorFactory.bar(
            title: "Protein adherence",
            summary: "2 of 3 eligible target days met; one observed day had no target.",
            xAxisTitle: "Date",
            yAxisTitle: "Adherence",
            unit: "%",
            series: [
                ReportChartSeries(
                    id: "protein",
                    name: "Protein target",
                    observations: [
                        .init(
                            id: UUID(uuidString: "00000000-0000-4000-8000-000000000804")!,
                            date: observedAt,
                            value: 66.6666666667
                        ),
                    ]
                ),
            ],
            calendar: try utcCalendar(),
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertFalse(chart.model.isTrendEligible)
        XCTAssertEqual(chart.model.coverage.observedCount, 1)
        XCTAssertEqual(chart.model.finalObservations.map(\.value), [66.6666666667])
        XCTAssertEqual(chart.model.tableRows.map(\.unit), ["%"])

        let descriptor = chart.makeChartDescriptor()
        XCTAssertEqual(descriptor.series.count, 1)
        XCTAssertEqual(descriptor.series[0].isContinuous, false)
        XCTAssertEqual(descriptor.series[0].dataPoints.count, 1)
        XCTAssertEqual(
            descriptor.series[0].dataPoints[0].label,
            "Feb 10, 2024, 66.67 %"
        )
    }

    func testCatalogBackedChartFormatsUseExactEnglishAndTurkishDateNumberOrdering() throws {
        let calendar = try utcCalendar()
        let observedAt = try date("2024-01-02T00:00:00Z")
        let english = Locale(identifier: "en_US")
        let turkish = Locale(identifier: "tr_TR")

        XCTAssertEqual(
            ReportChartDescriptor.dateDescription(
                observedAt,
                calendar: calendar,
                locale: english
            ),
            "Jan 2, 2024"
        )
        XCTAssertEqual(
            ReportChartDescriptor.dateDescription(
                observedAt,
                calendar: calendar,
                locale: turkish
            ),
            "2 Oca 2024"
        )
        XCTAssertEqual(
            ReportChartDescriptor.valueDescription(78.4, unit: "kg", locale: english),
            "78.4 kg"
        )
        XCTAssertEqual(
            ReportChartDescriptor.valueDescription(78.4, unit: "kg", locale: turkish),
            "78,4 kg"
        )
        XCTAssertEqual(
            ReportChartDescriptor.pointDescription(
                date: observedAt,
                value: 78.4,
                unit: "kg",
                calendar: calendar,
                locale: english
            ),
            "Jan 2, 2024, 78.4 kg"
        )
        XCTAssertEqual(
            ReportChartDescriptor.pointDescription(
                date: observedAt,
                value: 78.4,
                unit: "kg",
                calendar: calendar,
                locale: turkish
            ),
            "2 Oca 2024, 78,4 kg"
        )
        XCTAssertEqual(
            ReportChartDescriptor.finalValueDescription(
                seriesName: "Weight",
                value: 78.4,
                unit: "kg",
                locale: english
            ),
            "Weight: 78.4 kg"
        )
        XCTAssertEqual(
            ReportChartDescriptor.finalValueDescription(
                seriesName: "Kilo",
                value: 78.4,
                unit: "kg",
                locale: turkish
            ),
            "Kilo: 78,4 kg"
        )
        XCTAssertEqual(
            ReportChartDescriptor.tableRowDescription(
                date: observedAt,
                value: 78.4,
                unit: "kg",
                calendar: calendar,
                locale: english
            ),
            "Jan 2, 2024 — 78.4 kg"
        )
        XCTAssertEqual(
            ReportChartDescriptor.tableRowDescription(
                date: observedAt,
                value: 78.4,
                unit: "kg",
                calendar: calendar,
                locale: turkish
            ),
            "2 Oca 2024 — 78,4 kg"
        )
        XCTAssertEqual(
            ReportChartDescriptor.multiUnitTitle(
                title: "Weight",
                unit: "kg",
                locale: english
            ),
            "Weight (kg)"
        )
        XCTAssertEqual(
            ReportChartDescriptor.multiUnitTitle(
                title: "Kilo",
                unit: "kg",
                locale: turkish
            ),
            "Kilo (kg)"
        )
    }

    func testProteinPresentationIsUndatedAndDistinguishesBothMissingNextActions() {
        let computedReport = ProteinAdherenceReport(
            observedDayCount: 5,
            targetDayCount: 3,
            hitDayCount: 2,
            excludedTargetlessDayCount: 2,
            adherencePercent: 66.666_666_666_7,
            provenance: .currentProfileAppliedToObservedDays
        )
        let noObservationReport = ProteinAdherenceReport(
            observedDayCount: 0,
            targetDayCount: 0,
            hitDayCount: 0,
            excludedTargetlessDayCount: 0,
            adherencePercent: nil,
            provenance: .currentProfileAppliedToObservedDays
        )
        let targetlessReport = ProteinAdherenceReport(
            observedDayCount: 3,
            targetDayCount: 0,
            hitDayCount: 0,
            excludedTargetlessDayCount: 3,
            adherencePercent: nil,
            provenance: .currentProfileAppliedToObservedDays
        )

        let computedEnglish = ProteinAdherencePresentation.make(
            report: computedReport,
            locale: Locale(identifier: "en_US")
        )
        let computedTurkish = ProteinAdherencePresentation.make(
            report: computedReport,
            locale: Locale(identifier: "tr_TR")
        )
        XCTAssertEqual(
            computedEnglish.state,
            .computed(
                hitDayCount: 2,
                targetDayCount: 3,
                adherencePercent: 66.666_666_666_7,
                excludedTargetlessDayCount: 2
            )
        )
        XCTAssertEqual(
            computedEnglish.message,
            "2/3 eligible target days met (66.7%); 2 days without a target excluded."
        )
        XCTAssertEqual(
            computedTurkish.message,
            "2/3 uygun hedef günü karşılandı (%66,7); hedefsiz 2 gün dışlandı."
        )

        let noObservationEnglish = ProteinAdherencePresentation.make(
            report: noObservationReport,
            locale: Locale(identifier: "en_US")
        )
        let noObservationTurkish = ProteinAdherencePresentation.make(
            report: noObservationReport,
            locale: Locale(identifier: "tr_TR")
        )
        XCTAssertEqual(noObservationEnglish.state, .noObservations)
        XCTAssertEqual(noObservationTurkish.state, .noObservations)
        XCTAssertEqual(
            noObservationEnglish.message,
            "No nutrition observation is available in this range. Log a meal to begin this report."
        )
        XCTAssertEqual(
            noObservationTurkish.message,
            "Bu aralıkta beslenme gözlemi yok. Bu raporu başlatmak için bir öğün kaydedin."
        )

        let targetlessEnglish = ProteinAdherencePresentation.make(
            report: targetlessReport,
            locale: Locale(identifier: "en_US")
        )
        let targetlessTurkish = ProteinAdherencePresentation.make(
            report: targetlessReport,
            locale: Locale(identifier: "tr_TR")
        )
        XCTAssertEqual(
            targetlessEnglish.state,
            .noEligibleTarget(observedDayCount: 3, excludedTargetlessDayCount: 3)
        )
        XCTAssertEqual(
            targetlessTurkish.state,
            .noEligibleTarget(observedDayCount: 3, excludedTargetlessDayCount: 3)
        )
        XCTAssertEqual(
            targetlessEnglish.message,
            "3 observed days have no eligible protein target. Set a protein target to measure adherence."
        )
        XCTAssertEqual(
            targetlessTurkish.message,
            "Gözlenen 3 günün uygun protein hedefi yok. Uyumu ölçmek için protein hedefi belirleyin."
        )
        XCTAssertFalse(noObservationEnglish.message.contains("0%"))
        XCTAssertFalse(targetlessEnglish.message.contains("0%"))
    }

    func testDashboardBuilderDelegatesToAcceptedBuildersAndRetainsPartialPhaseProvenance() throws {
        let calendar = try utcCalendar()
        let interval = ReportDateInterval(
            start: try date("2024-01-01T00:00:00Z"),
            endExclusive: try date("2024-02-01T00:00:00Z")
        )
        let phaseID = UUID(uuidString: "00000000-0000-4000-8000-000000000811")!
        let programID = UUID(uuidString: "00000000-0000-4000-8000-000000000812")!
        let weightID = UUID(uuidString: "00000000-0000-4000-8000-000000000813")!
        let sleepID = UUID(uuidString: "00000000-0000-4000-8000-000000000814")!
        let source = ReportsDashboardSource(
            coverage: ReportCoverage(observationDates: [try date("2024-01-05T10:00:00Z")]),
            bodyMetricRecords: [
                .init(
                    id: weightID,
                    date: try date("2024-01-05T10:00:00Z"),
                    createdAt: try date("2024-01-05T10:01:00Z"),
                    kind: .weight,
                    customName: nil,
                    value: 78.4,
                    unit: "kg"
                ),
            ],
            nutritionDayRecords: [
                .init(
                    id: UUID(uuidString: "00000000-0000-4000-8000-000000000815")!,
                    date: try date("2024-01-06T00:00:00Z"),
                    createdAt: try date("2024-01-06T20:00:00Z"),
                    entryCount: 2,
                    proteinTotalG: 120,
                    proteinTargetG: 100
                ),
            ],
            sleepRecords: [
                .init(
                    id: sleepID,
                    date: try date("2024-01-07T08:00:00Z"),
                    createdAt: try date("2024-01-07T08:01:00Z"),
                    durationHours: 7.5,
                    quality: 8
                ),
            ],
            programPhases: [.init(id: phaseID, name: "Build", orderIndex: 0)],
            currentPhaseState: .init(
                programID: programID,
                phaseID: phaseID,
                phaseStartedAt: try date("2023-12-15T00:00:00Z")
            )
        )

        let dashboard = try ReportsDashboardBuilder.build(
            source: source,
            interval: interval,
            calendar: calendar
        )
        let acceptedBody = try BodyStrengthDatasetBuilder.build(
            bodyMetricRecords: source.bodyMetricRecords,
            exerciseSetRecords: source.exerciseSetRecords,
            interval: interval,
            calendar: calendar
        )
        let acceptedProtein = try ProteinAdherenceBuilder.build(days: source.nutritionDayRecords)
        let acceptedLifestyle = try LifestylePhaseDatasetBuilder.build(
            source: source,
            interval: interval,
            calendar: calendar
        )

        XCTAssertEqual(dashboard.interval, interval)
        XCTAssertEqual(dashboard.sourceCoverage, source.coverage)
        XCTAssertEqual(dashboard.bodyStrength, acceptedBody)
        XCTAssertEqual(dashboard.proteinAdherence, acceptedProtein)
        XCTAssertEqual(dashboard.lifestylePhase, acceptedLifestyle)
        XCTAssertEqual(dashboard.lifestylePhase.phaseTimelineProvenance, .partialCurrentState)
        assertEquatableSendable(ReportsDashboard.self)
    }

    func testDashboardBuilderPreservesEachAcceptedBuilderErrorType() throws {
        let calendar = try utcCalendar()
        let interval = ReportDateInterval(
            start: try date("2024-01-01T00:00:00Z"),
            endExclusive: try date("2024-02-01T00:00:00Z")
        )

        let invalidSetID = UUID(uuidString: "00000000-0000-4000-8000-000000000821")!
        XCTAssertThrowsError(
            try ReportsDashboardBuilder.build(
                source: ReportsDashboardSource(
                    exerciseSetRecords: [
                        .init(
                            id: invalidSetID,
                            createdAt: try date("2024-01-05T10:01:00Z"),
                            sessionID: UUID(uuidString: "00000000-0000-4000-8000-000000000822")!,
                            sessionDate: try date("2024-01-05T10:00:00Z"),
                            sessionCreatedAt: try date("2024-01-05T09:00:00Z"),
                            exerciseTemplateID: UUID(uuidString: "00000000-0000-4000-8000-000000000823")!,
                            exerciseName: "Squat",
                            setIndex: 0,
                            sessionCompleted: true,
                            isWarmup: false,
                            measurement: .weightedRepetitions,
                            weightKg: 80,
                            reps: Int.max,
                            durationSec: nil,
                            distanceSteps: nil
                        ),
                    ]
                ),
                interval: interval,
                calendar: calendar
            )
        ) { error in
            XCTAssertEqual(
                error as? BodyStrengthDatasetError,
                .invalidRepetitionRange(recordID: invalidSetID, reps: Int.max)
            )
        }

        let invalidNutritionID = UUID(uuidString: "00000000-0000-4000-8000-000000000824")!
        XCTAssertThrowsError(
            try ReportsDashboardBuilder.build(
                source: ReportsDashboardSource(
                    nutritionDayRecords: [
                        .init(
                            id: invalidNutritionID,
                            date: try date("2024-01-06T00:00:00Z"),
                            createdAt: try date("2024-01-06T20:00:00Z"),
                            entryCount: 1,
                            proteinTotalG: -1,
                            proteinTargetG: 100
                        ),
                    ]
                ),
                interval: interval,
                calendar: calendar
            )
        ) { error in
            XCTAssertEqual(
                error as? ProteinAdherenceBuilderError,
                .invalidObservedDay(id: invalidNutritionID)
            )
        }

        let invalidSleepID = UUID(uuidString: "00000000-0000-4000-8000-000000000825")!
        XCTAssertThrowsError(
            try ReportsDashboardBuilder.build(
                source: ReportsDashboardSource(
                    sleepRecords: [
                        .init(
                            id: invalidSleepID,
                            date: try date("2024-01-07T08:00:00Z"),
                            createdAt: try date("2024-01-07T08:01:00Z"),
                            durationHours: 0,
                            quality: 8
                        ),
                    ]
                ),
                interval: interval,
                calendar: calendar
            )
        ) { error in
            XCTAssertEqual(
                error as? LifestylePhaseDatasetError,
                .invalidRecord(kind: .sleep, id: invalidSleepID)
            )
        }
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}

    private func utcCalendar() throws -> Calendar {
        guard let timeZone = TimeZone(identifier: "UTC") else {
            throw FixtureFailure.invalidTimeZone
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw FixtureFailure.invalidDate
        }
        return date
    }

    private enum FixtureFailure: Error {
        case invalidDate
        case invalidTimeZone
    }
}
