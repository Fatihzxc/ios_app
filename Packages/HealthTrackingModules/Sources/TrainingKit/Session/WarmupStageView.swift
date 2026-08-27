import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct WarmupStageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AccessibilityFocusState private var isHeadingFocused: Bool
    private let presentation: SessionPresentation
    private let toggleItem: (UUID) -> Void
    private let complete: () -> Void
    private let skip: () -> Void

    public init(
        presentation: SessionPresentation,
        toggleItem: @escaping (UUID) -> Void,
        complete: @escaping () -> Void,
        skip: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.toggleItem = toggleItem
        self.complete = complete
        self.skip = skip
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                stageHeading(
                    title: localized("session.warmup.title"),
                    detail: presentation.plan.focus
                )
                ForEach(Array(presentation.plan.warmupItems.enumerated()), id: \.element.id) {
                    index, item in
                    checklistRow(
                        item,
                        isCompleted: presentation.progress.completedWarmupItemIDs.contains(item.id),
                        identifier: "session.warmup.item.\(index)"
                    )
                }
                PrimaryActionButton(
                    title: localized("session.warmup.complete"),
                    accessibilityLabel: localized("session.warmup.complete"),
                    minimumHeight: 52,
                    action: complete
                )
                .accessibilityIdentifier("session.warmup.complete")
                Button(localized("session.warmup.skip"), action: skip)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .accessibilityIdentifier("session.warmup.skip")
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.large)
            .padding(.bottom, SessionStageLayout.bottomActionClearance)
        }
        .accessibilityIdentifier("session.stage.warmup")
        .task {
            isHeadingFocused = true
        }
    }

    private func checklistRow(
        _ item: SessionChecklistItemSnapshot,
        isCompleted: Bool,
        identifier: String
    ) -> some View {
        Button {
            toggleItem(item.id)
        } label: {
            AppCard {
                HStack(alignment: .top, spacing: AppSpacing.standard) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(
                            AppColors.color(
                                isCompleted ? .stateSuccess : .inkSecondary,
                                scheme: colorScheme
                            )
                        )
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text(item.title)
                            .font(AppTypography.label)
                            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                        Text(item.detail)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(isCompleted ? localized("session.checklist.completed") : "")
        .accessibilityIdentifier(identifier)
    }

    private func stageHeading(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(title)
                .font(AppTypography.titleLarge)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isHeadingFocused)
            Text(detail)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
