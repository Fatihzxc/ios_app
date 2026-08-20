import CoreModels
import DesignSystem
import SwiftUI

@MainActor
public struct SessionSummaryView: View {
    @Environment(\.colorScheme) private var colorScheme
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
                .frame(minWidth: 44, minHeight: 44)
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

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
