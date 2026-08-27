import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct CooldownStageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AccessibilityFocusState private var isHeadingFocused: Bool
    private let presentation: SessionPresentation
    private let toggleItem: (UUID) -> Void
    private let goBack: () -> Void
    private let complete: () -> Void
    private let skip: () -> Void

    public init(
        presentation: SessionPresentation,
        toggleItem: @escaping (UUID) -> Void,
        goBack: @escaping () -> Void,
        complete: @escaping () -> Void,
        skip: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.toggleItem = toggleItem
        self.goBack = goBack
        self.complete = complete
        self.skip = skip
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Text(localized("session.cooldown.title"))
                    .font(AppTypography.titleLarge)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isHeadingFocused)

                ForEach(Array(presentation.plan.cooldownItems.enumerated()), id: \.element.id) {
                    index, item in
                    checklistRow(
                        item,
                        isCompleted: presentation.progress.completedCooldownItemIDs.contains(item.id),
                        identifier: "session.cooldown.item.\(index)"
                    )
                }

                PrimaryActionButton(
                    title: localized("session.cooldown.complete"),
                    accessibilityLabel: localized("session.cooldown.complete"),
                    minimumHeight: 52,
                    action: complete
                )
                .accessibilityIdentifier("session.cooldown.complete")
                HStack(spacing: AppSpacing.standard) {
                    Button(localized("session.exercise.back"), action: goBack)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .accessibilityIdentifier("session.cooldown.back")
                    Button(localized("session.cooldown.skip"), action: skip)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .accessibilityIdentifier("session.cooldown.skip")
                }
                .font(AppTypography.label)
                .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.large)
            .padding(.bottom, SessionStageLayout.bottomActionClearance)
        }
        .accessibilityIdentifier("session.stage.cooldown")
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
                        if let note = item.note, !note.isEmpty {
                            Text(note)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.color(.stateWarning, scheme: colorScheme))
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(isCompleted ? localized("session.checklist.completed") : "")
        .accessibilityIdentifier(identifier)
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
