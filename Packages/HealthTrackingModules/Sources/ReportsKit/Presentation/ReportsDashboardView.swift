import DesignSystem
import Foundation
import SwiftUI

enum ProteinAdherencePresentationState: Equatable, Sendable {
    case computed(
        hitDayCount: Int,
        targetDayCount: Int,
        adherencePercent: Double,
        excludedTargetlessDayCount: Int
    )
    case noObservations
    case noEligibleTarget(
        observedDayCount: Int,
        excludedTargetlessDayCount: Int
    )
}

struct ProteinAdherencePresentation: Equatable, Sendable {
    let state: ProteinAdherencePresentationState
    let message: String

    static func make(
        report: ProteinAdherenceReport,
        locale: Locale
    ) -> ProteinAdherencePresentation {
        guard report.observedDayCount > 0 else {
            return ProteinAdherencePresentation(
                state: .noObservations,
                message: localized(
                    "reports.protein.no_observations",
                    locale: locale
                )
            )
        }
        guard let adherencePercent = report.adherencePercent else {
            return ProteinAdherencePresentation(
                state: .noEligibleTarget(
                    observedDayCount: report.observedDayCount,
                    excludedTargetlessDayCount: report.excludedTargetlessDayCount
                ),
                message: localizedFormat(
                    "reports.protein.no_eligible_target",
                    locale: locale,
                    report.observedDayCount
                )
            )
        }
        return ProteinAdherencePresentation(
            state: .computed(
                hitDayCount: report.hitDayCount,
                targetDayCount: report.targetDayCount,
                adherencePercent: adherencePercent,
                excludedTargetlessDayCount: report.excludedTargetlessDayCount
            ),
            message: localizedFormat(
                "reports.protein.summary",
                locale: locale,
                report.hitDayCount,
                report.targetDayCount,
                percentDescription(adherencePercent, locale: locale),
                report.excludedTargetlessDayCount
            )
        )
    }

    private static func localized(
        _ key: String.LocalizationValue,
        locale: Locale
    ) -> String {
        ReportsLocalization.string(key, locale: locale)
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

    private static func percentDescription(
        _ value: Double,
        locale: Locale
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let number = formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.1f", locale: locale, value)
        return localizedFormat(
            "reports.format.percent",
            locale: locale,
            number
        )
    }
}

@MainActor
public struct ReportsDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: ReportsDashboardViewModel
    @State private var selectedExerciseID: UUID?
    private let calendar: Calendar
    private let referenceDate: @MainActor () -> Date
    private let loadsOnPresentation: Bool
    private let onOpenExport: @MainActor () -> Void

    public init(
        viewModel: ReportsDashboardViewModel,
        calendar: Calendar,
        referenceDate: @escaping @MainActor () -> Date = { .now },
        loadsOnPresentation: Bool = true,
        onOpenExport: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.calendar = calendar
        self.referenceDate = referenceDate
        self.loadsOnPresentation = loadsOnPresentation
        self.onOpenExport = onOpenExport
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
            heading
            rangeSelector
            stateContent
            exportButton
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports.dashboard")
        .task {
            guard loadsOnPresentation else { return }
            await viewModel.load(referenceDate: referenceDate())
        }
        .onChange(of: viewModel.report) { _, report in
            reconcileExerciseSelection(report)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(localized("reports.dashboard.title"))
                .font(AppTypography.titleLarge)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .accessibilityAddTraits(.isHeader)
            Text(localized("reports.dashboard.subtitle"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rangeSelector: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 72), spacing: AppSpacing.compact),
                GridItem(.flexible(minimum: 72), spacing: AppSpacing.compact),
            ],
            spacing: AppSpacing.compact
        ) {
            rangeButton(.oneMonth, key: "reports.range.one_month", identifier: "one_month")
            rangeButton(.threeMonths, key: "reports.range.three_months", identifier: "three_months")
            rangeButton(.sixMonths, key: "reports.range.six_months", identifier: "six_months")
            rangeButton(.oneYear, key: "reports.range.one_year", identifier: "one_year")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports.range.selector")
    }

    @ViewBuilder
    private func rangeButton(
        _ preset: ReportDateRangePreset,
        key: String.LocalizationValue,
        identifier: String
    ) -> some View {
        let button = Button {
            Task {
                await viewModel.selectPreset(preset, referenceDate: referenceDate())
            }
        } label: {
            Text(localized(key))
                .font(AppTypography.label)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("reports.range.\(identifier)")

        if viewModel.selectedPreset == preset {
            button
                .buttonStyle(.borderedProminent)
                .tint(AppColors.color(.accentAction, scheme: colorScheme))
                .accessibilityAddTraits(.isSelected)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            AppCard {
                HStack(spacing: AppSpacing.compact) {
                    ProgressView().accessibilityHidden(true)
                    Text(localized("reports.dashboard.loading"))
                        .font(AppTypography.body)
                }
            }
            .accessibilityIdentifier("reports.dashboard.loading")
        case .failed:
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.standard) {
                    Text(localized("reports.dashboard.error"))
                        .font(AppTypography.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(localized("reports.dashboard.retry")) {
                        Task { await viewModel.load(referenceDate: referenceDate()) }
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("reports.dashboard.retry")
                }
            }
            .accessibilityIdentifier("reports.dashboard.error")
        case .loaded:
            if let report = viewModel.report {
                dashboard(report)
            } else {
                emptyCard(
                    title: localized("reports.dashboard.title"),
                    message: localized("reports.dashboard.error"),
                    identifier: "reports.dashboard.missing"
                )
            }
        }
    }

    private func dashboard(_ report: ReportsDashboard) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
            selectedRangeSummary(report)
            bodyMetricSection(report, kind: .weight)
            bodyMetricSection(report, kind: .waist)
            strengthSection(report)
            proteinSection(report)
            lifestyleSection(
                title: localized("reports.sleep.title"),
                emptyMessage: localized("reports.sleep.empty"),
                identifier: "sleep",
                unit: localized("reports.unit.hours"),
                series: report.lifestylePhase.sleepDurationSeries,
                coverage: report.lifestylePhase.sleepCoverage
            )
            lifestyleSection(
                title: localized("reports.mood.title"),
                emptyMessage: localized("reports.mood.empty"),
                identifier: "mood",
                unit: localized("reports.unit.score"),
                series: report.lifestylePhase.moodScoreSeries,
                coverage: report.lifestylePhase.moodCoverage
            )
            lifestyleSection(
                title: localized("reports.posture.title"),
                emptyMessage: localized("reports.posture.empty"),
                identifier: "posture",
                unit: localized("reports.unit.score"),
                series: report.lifestylePhase.postureSymptomSeries,
                coverage: report.lifestylePhase.postureCoverage
            )
            phaseSection(report.lifestylePhase)
        }
    }

    private func selectedRangeSummary(_ report: ReportsDashboard) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(localized("reports.summary.title"))
                    .font(AppTypography.titleMedium)
                    .accessibilityAddTraits(.isHeader)
                Text(coverageSummary(report.sourceCoverage))
                    .font(AppTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(proteinSummary(report.proteinAdherence))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text(phaseProvenance(report.lifestylePhase.phaseTimelineProvenance))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports.summary")
    }

    @ViewBuilder
    private func bodyMetricSection(
        _ report: ReportsDashboard,
        kind: ReportBodyMetricKind
    ) -> some View {
        let points = report.bodyStrength.bodyMetricPoints.filter { $0.kind == kind }
        let title = kind == .weight
            ? localized("reports.weight.title")
            : localized("reports.waist.title")
        let empty = kind == .weight
            ? localized("reports.weight.empty")
            : localized("reports.waist.empty")
        if points.isEmpty {
            emptyCard(title: title, message: empty, identifier: "reports.\(kind.rawValue).empty")
        } else {
            ForEach(bodyMetricDescriptors(points: points, title: title), id: \.model.unit) { descriptor in
                chartCard(title: descriptor.model.title, summary: descriptor.model.summary) {
                    ReportLineChart(descriptor: descriptor)
                }
            }
        }
    }

    @ViewBuilder
    private func strengthSection(_ report: ReportsDashboard) -> some View {
        let exercises = strengthExercises(report)
        if exercises.isEmpty {
            emptyCard(
                title: localized("reports.strength.title"),
                message: localized("reports.strength.empty"),
                identifier: "reports.strength.empty"
            )
        } else {
            let selection = exercises.first(where: { $0.id == selectedExerciseID }) ?? exercises[0]
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.standard) {
                    Text(localized("reports.strength.title"))
                        .font(AppTypography.titleMedium)
                        .accessibilityAddTraits(.isHeader)
                    Picker(
                        localized("reports.strength.exercise"),
                        selection: $selectedExerciseID
                    ) {
                        ForEach(exercises) { exercise in
                            Text(exercise.name).tag(Optional(exercise.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("reports.strength.exercise")

                    if let descriptor = strengthDescriptor(selection) {
                        Text(descriptor.model.summary)
                            .font(AppTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                        ReportLineChart(descriptor: descriptor)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("reports.strength")
        }
    }

    private func proteinSection(_ report: ReportsDashboard) -> some View {
        let presentation = ProteinAdherencePresentation.make(
            report: report.proteinAdherence,
            locale: .autoupdatingCurrent
        )
        return AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(localized("reports.protein.title"))
                    .font(AppTypography.titleMedium)
                    .accessibilityAddTraits(.isHeader)
                Text(presentation.message)
                    .font(AppTypography.body)
                    .foregroundStyle(
                        AppColors.color(.inkSecondary, scheme: colorScheme)
                    )
                    .fixedSize(horizontal: false, vertical: true)
                Text(proteinProvenance(report.proteinAdherence.provenance))
                    .font(AppTypography.caption)
                    .foregroundStyle(
                        AppColors.color(.inkSecondary, scheme: colorScheme)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(proteinIdentifier(presentation.state))
    }

    @ViewBuilder
    private func lifestyleSection(
        title: String,
        emptyMessage: String,
        identifier: String,
        unit: String,
        series: [ReportNumericSeries],
        coverage: ReportCoverage
    ) -> some View {
        if coverage.observedCount == 0 {
            emptyCard(
                title: title,
                message: emptyMessage,
                identifier: "reports.\(identifier).empty"
            )
        } else {
            let chartSeries = series.enumerated().map { index, segment in
                ReportChartSeries(
                    id: "\(identifier).segment.\(index + 1)",
                    name: seriesName(title: title, index: index, count: series.count),
                    observations: segment.points.map {
                        .init(id: $0.observationID, date: $0.date, value: $0.value)
                    }
                )
            }
            let descriptor = ReportChartDescriptorFactory.line(
                title: title,
                summary: gapAwareSummary(coverage: coverage, segmentCount: series.count),
                xAxisTitle: localized("reports.axis.date"),
                yAxisTitle: title,
                unit: unit,
                series: chartSeries,
                calendar: calendar,
                locale: .autoupdatingCurrent
            )
            chartCard(title: descriptor.model.title, summary: descriptor.model.summary) {
                ReportLineChart(descriptor: descriptor)
            }
        }
    }

    private func phaseSection(_ report: LifestylePhaseReport) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                Text(localized("reports.phase.title"))
                    .font(AppTypography.titleMedium)
                    .accessibilityAddTraits(.isHeader)
                Text(phaseProvenance(report.phaseTimelineProvenance))
                    .font(AppTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
                if report.phaseSegments.isEmpty {
                    Text(localized("reports.phase.empty"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(report.phaseSegments.enumerated()), id: \.offset) { _, segment in
                        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                            Text(segment.phaseName)
                                .font(AppTypography.label)
                            Text(phaseDates(segment))
                                .font(AppTypography.caption)
                                .foregroundStyle(
                                    AppColors.color(.inkSecondary, scheme: colorScheme)
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports.phase")
    }

    private var exportButton: some View {
        Button(action: onOpenExport) {
            Label(localized("reports.export.action"), systemImage: "square.and.arrow.up")
                .font(AppTypography.label)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("reports.export.open")
    }

    private func chartCard<Content: View>(
        title: String,
        summary: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                Text(title)
                    .font(AppTypography.titleMedium)
                    .accessibilityAddTraits(.isHeader)
                Text(summary)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
        }
    }

    private func emptyCard(
        title: String,
        message: String,
        identifier: String
    ) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(title)
                    .font(AppTypography.titleMedium)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier(identifier)
    }

    private func bodyMetricDescriptors(
        points: [ReportBodyMetricPoint],
        title: String
    ) -> [ReportChartDescriptor] {
        let grouped = Dictionary(grouping: points, by: \.unit)
        return grouped.keys.sorted().map { unit in
            let unitPoints = grouped[unit, default: []]
            let segments = splitAtMissingDays(
                unitPoints.map {
                    ReportChartObservation(id: $0.observationID, date: $0.date, value: $0.value)
                }
            )
            let series = segments.enumerated().map { index, observations in
                ReportChartSeries(
                    id: "body.\(unit).segment.\(index + 1)",
                    name: seriesName(title: title, index: index, count: segments.count),
                    observations: observations
                )
            }
            return ReportChartDescriptorFactory.line(
                title: grouped.count == 1
                    ? title
                    : ReportChartDescriptor.multiUnitTitle(
                        title: title,
                        unit: unit,
                        locale: .autoupdatingCurrent
                    ),
                summary: gapAwareSummary(
                    coverage: ReportCoverage(observationDates: unitPoints.map(\.date)),
                    segmentCount: segments.count
                ),
                xAxisTitle: localized("reports.axis.date"),
                yAxisTitle: title,
                unit: unit,
                series: series,
                calendar: calendar,
                locale: .autoupdatingCurrent
            )
        }
    }

    private func splitAtMissingDays(
        _ observations: [ReportChartObservation]
    ) -> [[ReportChartObservation]] {
        let ordered = observations.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
        }
        var segments: [[ReportChartObservation]] = []
        for observation in ordered {
            guard let previous = segments.last?.last else {
                segments.append([observation])
                continue
            }
            let previousDay = calendar.startOfDay(for: previous.date)
            let day = calendar.startOfDay(for: observation.date)
            if calendar.date(byAdding: .day, value: 1, to: previousDay) == day {
                segments[segments.count - 1].append(observation)
            } else {
                segments.append([observation])
            }
        }
        return segments
    }

    private func strengthExercises(_ report: ReportsDashboard) -> [StrengthExercise] {
        Dictionary(grouping: report.bodyStrength.strengthSessionPoints, by: \.exerciseTemplateID)
            .compactMap { id, points in
                let valid = points.filter {
                    $0.volumeKg != nil || $0.estimatedOneRepMaxKg != nil
                }
                guard let first = valid.first, !valid.isEmpty else { return nil }
                return StrengthExercise(
                    id: id,
                    name: first.exerciseName,
                    points: valid.sorted {
                        if $0.sessionDate != $1.sessionDate { return $0.sessionDate < $1.sessionDate }
                        return $0.sessionID.uuidString.lowercased()
                            < $1.sessionID.uuidString.lowercased()
                    }
                )
            }
            .sorted {
                if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
            }
    }

    private func strengthDescriptor(_ exercise: StrengthExercise) -> ReportChartDescriptor? {
        var series: [ReportChartSeries] = []
        series.append(contentsOf: optionalStrengthSeries(
            exercise: exercise,
            id: "strength.\(exercise.id.uuidString.lowercased()).volume",
            label: localizedFormat("reports.strength.volume.series", exercise.name),
            value: \.volumeKg
        ))
        series.append(contentsOf: optionalStrengthSeries(
            exercise: exercise,
            id: "strength.\(exercise.id.uuidString.lowercased()).e1rm",
            label: localizedFormat("reports.strength.e1rm.series", exercise.name),
            value: \.estimatedOneRepMaxKg
        ))
        guard !series.isEmpty else { return nil }
        let coverage = ReportCoverage(
            observationDates: series.flatMap { $0.observations.map(\.date) }
        )
        return ReportChartDescriptorFactory.line(
            title: exercise.name,
            summary: coverageSummary(coverage),
            xAxisTitle: localized("reports.axis.date"),
            yAxisTitle: localized("reports.strength.axis"),
            unit: localized("reports.unit.kilogram"),
            series: series,
            calendar: calendar,
            locale: .autoupdatingCurrent
        )
    }

    private func optionalStrengthSeries(
        exercise: StrengthExercise,
        id: String,
        label: String,
        value: KeyPath<ReportStrengthSessionPoint, Double?>
    ) -> [ReportChartSeries] {
        var segments: [[ReportChartObservation]] = []
        var current: [ReportChartObservation] = []
        for point in exercise.points {
            guard let observed = point[keyPath: value] else {
                if !current.isEmpty { segments.append(current); current = [] }
                continue
            }
            current.append(.init(id: point.sessionID, date: point.sessionDate, value: observed))
        }
        if !current.isEmpty { segments.append(current) }
        return segments.enumerated().map { index, observations in
            ReportChartSeries(
                id: "\(id).segment.\(index + 1)",
                name: seriesName(title: label, index: index, count: segments.count),
                observations: observations
            )
        }
    }

    private func reconcileExerciseSelection(_ report: ReportsDashboard?) {
        guard let report else { selectedExerciseID = nil; return }
        let exercises = strengthExercises(report)
        if let selectedExerciseID,
           exercises.contains(where: { $0.id == selectedExerciseID }) {
            return
        }
        selectedExerciseID = exercises.first?.id
    }

    private func coverageSummary(_ coverage: ReportCoverage) -> String {
        guard let first = coverage.firstObservationAt,
              let last = coverage.lastObservationAt else {
            return localized("reports.summary.empty")
        }
        if coverage.observedCount == 1 {
            return localizedFormat("reports.summary.one", formattedDate(first))
        }
        return localizedFormat(
            "reports.summary.many",
            coverage.observedCount,
            formattedDate(first),
            formattedDate(last)
        )
    }

    private func gapAwareSummary(
        coverage: ReportCoverage,
        segmentCount: Int
    ) -> String {
        let base = coverageSummary(coverage)
        guard segmentCount > 1 else { return base }
        return localizedFormat("reports.summary.with_gaps", base, segmentCount - 1)
    }

    private func proteinSummary(_ report: ProteinAdherenceReport) -> String {
        ProteinAdherencePresentation.make(
            report: report,
            locale: .autoupdatingCurrent
        ).message
    }

    private func proteinIdentifier(
        _ state: ProteinAdherencePresentationState
    ) -> String {
        switch state {
        case .computed: "reports.protein"
        case .noObservations, .noEligibleTarget: "reports.protein.missing"
        }
    }

    private func proteinProvenance(_ provenance: ProteinTargetProvenance) -> String {
        switch provenance {
        case .currentProfileAppliedToObservedDays:
            localized("reports.protein.provenance.current_profile")
        }
    }

    private func phaseProvenance(_ provenance: PhaseTimelineProvenance) -> String {
        switch provenance {
        case .unavailable: localized("reports.phase.provenance.unavailable")
        case .partialCurrentState: localized("reports.phase.provenance.partial")
        case .actualTransitions: localized("reports.phase.provenance.actual")
        }
    }

    private func phaseDates(_ segment: ReportPhaseSegment) -> String {
        if let endedAt = segment.endedAt {
            return localizedFormat(
                "reports.phase.dates.closed",
                formattedDate(segment.visibleStart),
                formattedDate(min(endedAt, segment.visibleEndExclusive))
            )
        }
        return localizedFormat(
            "reports.phase.dates.current",
            formattedDate(segment.visibleStart)
        )
    }

    private func seriesName(title: String, index: Int, count: Int) -> String {
        count == 1
            ? title
            : localizedFormat("reports.series.segment", title, index + 1)
    }

    private func formattedDate(_ date: Date) -> String {
        ReportChartDescriptor.dateDescription(
            date,
            calendar: calendar,
            locale: .autoupdatingCurrent
        )
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    private func localizedFormat(
        _ key: String.LocalizationValue,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: localized(key),
            locale: .autoupdatingCurrent,
            arguments: arguments
        )
    }
}

private struct StrengthExercise: Identifiable {
    let id: UUID
    let name: String
    let points: [ReportStrengthSessionPoint]
}
