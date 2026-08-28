import DesignSystem
import Foundation
import HealthSafetyKit
import SwiftUI

@MainActor
public struct PostureProgressSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: PostureViewModel

    public init(viewModel: PostureViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        stateContent
            .task {
                if viewModel.loadPhase == .idle {
                    await viewModel.load()
                }
            }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.loadPhase {
        case .idle, .loading:
            FeatureStateView(state: .loading)
                .accessibilityIdentifier("posture.history.loading")
        case .failed:
            FeatureStateView(
                state: .error(message: localized("posture.history.error")),
                retry: { Task { await viewModel.load() } }
            )
            .accessibilityIdentifier("posture.history.error")
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.standard) {
                Text(localized("posture.history.heading"))
                    .font(AppTypography.titleMedium)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: AppSpacing.small)
                Text(String(viewModel.snapshots.count))
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .monospacedDigit()
                    .accessibilityLabel(localized("posture.history.heading"))
                    .accessibilityValue(String(viewModel.snapshots.count))
                    .accessibilityIdentifier("posture.history.loaded")
            }

            Text(MedicalDisclaimerPresentation.permanent.text)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("medical.disclaimer.l1")

            if viewModel.snapshots.isEmpty {
                AppCard {
                    Text(localized("posture.history.empty"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                }
            } else {
                ForEach(viewModel.snapshots) { snapshot in
                    postureRow(snapshot)
                }
            }
        }
    }

    private func postureRow(_ snapshot: PostureMetricSnapshot) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(snapshot.date.formatted(date: .abbreviated, time: .omitted))
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                ForEach(rowLines(snapshot), id: \.self) { line in
                    Text(line)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("posture.row.\(snapshot.id.uuidString.lowercased())")
    }

    private func rowLines(_ snapshot: PostureMetricSnapshot) -> [String] {
        var lines: [String] = []
        if let wallTestPass = snapshot.wallTestPass {
            lines.append(
                wallTestPass
                    ? localized("posture.history.wall.pass")
                    : localized("posture.history.wall.fail")
            )
        }
        if let score = snapshot.symptomScore {
            lines.append(
                String(
                    format: localized("posture.history.symptom.format"),
                    locale: .autoupdatingCurrent,
                    Int64(score)
                )
            )
        }
        if let region = snapshot.region {
            lines.append(
                String(
                    format: localized("posture.history.region.format"),
                    locale: .autoupdatingCurrent,
                    region
                )
            )
        }
        if let note = snapshot.note { lines.append(note) }
        return lines
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
