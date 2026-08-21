import CoreModels
import DesignSystem
import SwiftUI

@MainActor
public struct SessionSummaryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AccessibilityFocusState private var isHeadingFocused: Bool
    @Bindable private var viewModel: SessionViewModel
    private let presentation: SessionPresentation

    public init(
        viewModel: SessionViewModel,
        presentation: SessionPresentation
    ) {
        self.viewModel = viewModel
        self.presentation = presentation
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Text(localized("session.summary.title"))
                    .font(AppTypography.titleLarge)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isHeadingFocused)

                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text(presentation.plan.name)
                            .font(AppTypography.titleMedium)
                            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                        Text(
                            String(
                                format: localized("session.summary.setCount"),
                                locale: .current,
                                Int64(presentation.setLogs.filter { !$0.isWarmupSet }.count)
                            )
                        )
                        .font(AppTypography.numericRow)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        checklistDispositionRow(
                            title: localized("session.summary.warmup"),
                            disposition: presentation.progress.warmupDisposition,
                            identifier: "session.summary.warmup"
                        )
                        checklistDispositionRow(
                            title: localized("session.summary.cooldown"),
                            disposition: presentation.progress.cooldownDisposition,
                            identifier: "session.summary.cooldown"
                        )
                    }
                }

                personalRecordsSection

                recoveryPicker

                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(localized("session.summary.note"))
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    TextEditor(
                        text: Binding(
                            get: { viewModel.summaryNote },
                            set: viewModel.updateSummaryNote
                        )
                    )
                    .frame(minHeight: 100)
                    .padding(AppSpacing.compact)
                    .background(AppColors.color(.backgroundRaised, scheme: colorScheme))
                    .clipShape(
                        RoundedRectangle(cornerRadius: AppRadius.sheet, style: .continuous)
                    )
                    .accessibilityIdentifier("session.summary.note")
                }

                PrimaryActionButton(
                    title: localized("session.summary.done"),
                    accessibilityLabel: localized("session.summary.done"),
                    minimumHeight: 52,
                    action: {
                        Task { await viewModel.saveSummary() }
                    }
                )
                .accessibilityIdentifier("session.summary.done")
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.large)
        }
        .accessibilityIdentifier("session.stage.summary")
        .task {
            isHeadingFocused = true
        }
    }

    @ViewBuilder
    private var personalRecordsSection: some View {
        if !presentation.personalRecords.records.isEmpty {
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    HStack(spacing: AppSpacing.compact) {
                        Image(systemName: "arrow.up.right")
                            .accessibilityHidden(true)
                        Text(localized("session.summary.personalRecord.title"))
                            .font(AppTypography.titleMedium)
                            .accessibilityIdentifier("session.summary.personalRecords")
                    }
                    .foregroundStyle(AppColors.color(.stateSuccess, scheme: colorScheme))

                    ForEach(presentation.personalRecords.records) { record in
                        VStack(alignment: .leading, spacing: AppSpacing.small) {
                            Text(record.exerciseName)
                                .font(AppTypography.label)
                                .foregroundStyle(
                                    AppColors.color(.inkPrimary, scheme: colorScheme)
                                )
                            Text(personalRecordValue(record))
                                .font(AppTypography.numericRow)
                                .foregroundStyle(
                                    AppColors.color(.inkSecondary, scheme: colorScheme)
                                )
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(
                            "session.summary.personalRecord.\(record.exerciseID.uuidString)"
                        )
                    }
                }
            }
        }
    }

    private var recoveryPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(localized("session.summary.recovery"))
                .font(AppTypography.label)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.compact) {
                    recoveryButton(value: nil, label: localized("session.summary.recovery.unset"))
                    ForEach(1...10, id: \.self) { value in
                        recoveryButton(value: value, label: String(value))
                    }
                }
            }
        }
    }

    private func recoveryButton(value: Int?, label: String) -> some View {
        let isSelected = viewModel.summaryRecovery == value
        return Button {
            viewModel.selectRecovery(value)
        } label: {
            Text(label)
                .font(AppTypography.label)
                .frame(minWidth: 52, minHeight: 52)
                .padding(.horizontal, AppSpacing.compact)
                .background(
                    AppColors.color(
                        isSelected ? .accentAction : .backgroundRaised,
                        scheme: colorScheme
                    )
                )
                .foregroundStyle(
                    AppColors.color(
                        isSelected ? .accentOnAction : .inkPrimary,
                        scheme: colorScheme
                    )
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? localized("session.selection.selected") : "")
        .accessibilityIdentifier(
            "session.summary.recovery.\(value.map { String($0) } ?? "unset")"
        )
    }

    private func checklistDispositionRow(
        title: String,
        disposition: WorkoutChecklistDisposition,
        identifier: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(dispositionText(disposition))
        }
        .font(AppTypography.caption)
        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func dispositionText(_ disposition: WorkoutChecklistDisposition) -> String {
        switch disposition {
        case .pending:
            localized("session.summary.checklist.pending")
        case .completed:
            localized("session.summary.checklist.completed")
        case .skipped:
            localized("session.summary.checklist.skipped")
        }
    }

    private func personalRecordValue(_ record: SessionPersonalRecordSummary) -> String {
        let previous = formatted(record.previousBest)
        let current = formatted(record.newBest)
        let key: String.LocalizationValue
        switch record.kind {
        case .weightedEstimatedOneRepMax:
            key = "session.summary.personalRecord.weighted"
        case .repetitions:
            key = "session.summary.personalRecord.repetitions"
        case .duration:
            key = "session.summary.personalRecord.duration"
        case .steps:
            key = "session.summary.personalRecord.steps"
        }
        return String(
            format: localized(key),
            locale: .current,
            previous,
            current
        )
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(
            .number
                .locale(.current)
                .precision(.fractionLength(0...2))
        )
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
