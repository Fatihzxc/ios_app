import CoreModels
import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct BodyMetricProgressView<AdditionalContent: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: BodyMetricViewModel
    @State private var editingSnapshot: BodyMetricSnapshot?
    private let additionalContent: AdditionalContent

    public init(
        viewModel: BodyMetricViewModel,
        @ViewBuilder additionalContent: () -> AdditionalContent
    ) {
        self.viewModel = viewModel
        self.additionalContent = additionalContent()
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
                    stateContent
                    additionalContent
                }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.vertical, AppSpacing.standard)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .navigationTitle(localized("metrics.progress.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("root.progress")
        .task {
            if viewModel.loadPhase == .idle {
                await viewModel.load()
            }
        }
        .sheet(item: $editingSnapshot) { snapshot in
            BodyMetricEntryView(
                viewModel: viewModel,
                editingSnapshot: snapshot,
                onClose: { editingSnapshot = nil }
            )
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.loadPhase {
        case .idle, .loading:
            FeatureStateView(state: .loading)
                .accessibilityIdentifier("metrics.history.loading")
        case .failed:
            FeatureStateView(
                state: .error(message: localized("metrics.history.error")),
                retry: { Task { await viewModel.load() } }
            )
            .accessibilityIdentifier("metrics.history.error")
        case .loaded:
            historyContent
        }
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.standard) {
                Text(localized("metrics.history.heading"))
                    .font(AppTypography.titleMedium)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("root.progress.content")
                Spacer(minLength: AppSpacing.small)
                Text(String(viewModel.snapshots.count))
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: true)
                    .accessibilityLabel(localized("metrics.history.heading"))
                    .accessibilityValue(String(viewModel.snapshots.count))
                    .accessibilityIdentifier("metrics.history.loaded")
            }
            if viewModel.snapshots.isEmpty {
                AppCard {
                    Text(localized("metrics.history.empty"))
                        .font(AppTypography.body)
                        .foregroundStyle(
                            AppColors.color(.inkSecondary, scheme: colorScheme)
                        )
                }
                .accessibilityIdentifier("metrics.history.empty")
            } else {
                ForEach(viewModel.snapshots) { snapshot in
                    metricRow(snapshot)
                }
            }
        }
    }

    private func metricRow(_ snapshot: BodyMetricSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Button {
                editingSnapshot = snapshot
            } label: {
                AppCard {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.standard) {
                        VStack(alignment: .leading, spacing: AppSpacing.small) {
                            Text(metricName(snapshot))
                                .font(AppTypography.label)
                                .foregroundStyle(
                                    AppColors.color(.inkPrimary, scheme: colorScheme)
                                )
                            Text(metricValue(snapshot))
                                .font(AppTypography.body)
                                .foregroundStyle(
                                    AppColors.color(.inkSecondary, scheme: colorScheme)
                                )
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(
                                AppColors.color(.accentAction, scheme: colorScheme)
                            )
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                format(
                    "metrics.history.accessibility.format",
                    metricName(snapshot),
                    metricValue(snapshot)
                )
            )
            .accessibilityHint(localized("metrics.history.edit.hint"))
            .accessibilityIdentifier(rowIdentifier(snapshot))

            deleteButton(snapshot)
        }
    }

    private func deleteButton(_ snapshot: BodyMetricSnapshot) -> some View {
        Button(role: .destructive) {
            Task { await viewModel.delete(snapshot) }
        } label: {
            Label(localized("metrics.history.delete"), systemImage: "trash")
                .font(AppTypography.label)
                .frame(minWidth: 52, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityHint(localized("metrics.history.delete.hint"))
        .accessibilityIdentifier(deleteIdentifier(snapshot))
    }

    private func metricName(_ snapshot: BodyMetricSnapshot) -> String {
        switch snapshot.type {
        case .weight:
            localized("metrics.type.weight")
        case .waist:
            localized("metrics.type.waist")
        case .custom:
            snapshot.customName ?? localized("metrics.type.custom")
        }
    }

    private func metricValue(_ snapshot: BodyMetricSnapshot) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        let value = formatter.string(from: NSNumber(value: snapshot.value))
            ?? String(snapshot.value)
        return "\(value) \(snapshot.unit)"
    }

    private func rowIdentifier(_ snapshot: BodyMetricSnapshot) -> String {
        "metrics.row.\(snapshot.type.rawValue).\(snapshot.id.uuidString.lowercased())"
    }

    private func deleteIdentifier(_ snapshot: BodyMetricSnapshot) -> String {
        "metrics.delete.\(snapshot.type.rawValue).\(snapshot.id.uuidString.lowercased())"
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    private func format(
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

public extension BodyMetricProgressView where AdditionalContent == EmptyView {
    init(viewModel: BodyMetricViewModel) {
        self.init(viewModel: viewModel) { EmptyView() }
    }
}
