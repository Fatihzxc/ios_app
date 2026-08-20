import DesignSystem
import Foundation
import SwiftUI
import TrainingKit

@MainActor
struct FoundationTodayView: View {
    @Environment(\.colorScheme) private var colorScheme
    let viewModel: FoundationProgramViewModel
    let onOpenSession: @MainActor (UUID) -> Void

    init(
        viewModel: FoundationProgramViewModel,
        onOpenSession: @escaping @MainActor (UUID) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onOpenSession = onOpenSession
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    stateContent
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .navigationTitle(String(localized: "tab.today"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("root.today")
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .loading:
            FeatureStateView(state: .loading)
                .accessibilityIdentifier("foundation.state.loading")
        case let .content(snapshot):
            loadedContent(snapshot)
        case .empty:
            FeatureStateView(
                state: .empty(
                    message: String(localized: "foundation.empty.message"),
                    actionTitle: String(localized: "foundation.empty.action"),
                    actionAccessibilityLabel: String(localized: "foundation.empty.accessibility"),
                    action: reload
                )
            )
            .accessibilityRepresentation {
                Button(String(localized: "foundation.empty.accessibility"), action: reload)
                    .accessibilityIdentifier("foundation.state.empty")
                    .accessibilityHint(String(localized: "foundation.empty.hint"))
            }
        case .error:
            FeatureStateView(
                state: .error(message: String(localized: "foundation.error.message")),
                retry: reload
            )
            .accessibilityRepresentation {
                Button(String(localized: "foundation.error.accessibility"), action: reload)
                    .accessibilityIdentifier("foundation.state.error")
                    .accessibilityHint(String(localized: "foundation.error.hint"))
            }
        }
    }

    private func loadedContent(_ snapshot: FoundationProgramSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            sectionHeading(String(localized: "today.foundation.heading"))
                .accessibilityIdentifier("root.today.content")
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.standard) {
                    Text(snapshot.program.name)
                        .font(AppTypography.titleMedium)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(snapshot.profile.displayName)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    Text(profileProvenance(snapshot.profile))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    Text(inventoryText(snapshot))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let deload = snapshot.deload {
                deloadCard(deload)
            }

            if let workoutDay = snapshot.workoutDays.first {
                PrimaryActionButton(
                    title: String(localized: "today.session.open"),
                    accessibilityLabel: String(localized: "today.session.open")
                ) {
                    onOpenSession(workoutDay.id)
                }
                .accessibilityIdentifier("today.session.open")
                .accessibilityHint(String(localized: "today.session.open.hint"))
            }

            sectionHeading(String(localized: "today.soon.heading"))
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.standard) {
                    StatusPill(
                        text: String(localized: "today.soon.status"),
                        systemImage: "clock",
                        style: .info
                    )
                    Text(String(localized: "today.soon.message"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func deloadCard(_ deload: FoundationDeloadSummary) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                StatusPill(
                    text: deload.mode == .active
                        ? String(localized: "today.deload.active")
                        : String(localized: "today.deload.recommended"),
                    systemImage: "exclamationmark.triangle.fill",
                    style: .warning
                )
                Text(deloadMessage(deload))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.deload.message")
                Text(String(localized: "today.deload.load"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func deloadMessage(_ deload: FoundationDeloadSummary) -> String {
        switch deload.reason {
        case .scheduled:
            String(
                format: String(localized: "today.deload.scheduled"),
                locale: .current,
                Int64(deload.trainingWeekIndex)
            )
        case .reactive:
            String(localized: "today.deload.reactive")
        }
    }

    private func inventoryText(_ snapshot: FoundationProgramSnapshot) -> String {
        let phaseNames = snapshot.phases.map(\.name).joined(separator: String(localized: "list.separator"))
        let dayNames = snapshot.workoutDays.map(\.name).joined(separator: String(localized: "list.separator"))
        let format = String(localized: "today.inventory.format")
        return String(
            format: format,
            locale: .current,
            Int64(snapshot.phases.count),
            phaseNames,
            Int64(snapshot.workoutDays.count),
            dayNames
        )
    }

    private func profileProvenance(_ profile: FoundationProfileSummary) -> String {
        if profile.usesFallbackDisplayName {
            return String(localized: "today.profile.provenance.fallback")
        }
        return String(localized: "today.profile.provenance.user")
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.titleMedium)
            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            .accessibilityAddTraits(.isHeader)
    }

    private func reload() {
        Task { await viewModel.load() }
    }
}
