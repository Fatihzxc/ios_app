import CoreModels
import DesignSystem
import SwiftUI

@MainActor
public struct OHPPriorSymptomQuestionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AccessibilityFocusState private var isQuestionFocused: Bool
    private let answer: (OHPSymptomResponse) -> Void

    public init(answer: @escaping (OHPSymptomResponse) -> Void) {
        self.answer = answer
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Text(localized("session.ohp.question.title"))
                    .font(AppTypography.titleLarge)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .accessibilityAddTraits(.isHeader)

                AppCard {
                    Text(localized("session.ohp.question.body"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("session.ohp.question.body")
                        .accessibilityFocused($isQuestionFocused)
                }

                VStack(spacing: AppSpacing.standard) {
                    responseButton(
                        title: localized("session.ohp.question.no"),
                        identifier: "session.ohp.prior.symptom-free",
                        response: .symptomFree,
                        prominent: true
                    )
                    responseButton(
                        title: localized("session.ohp.question.yes"),
                        identifier: "session.ohp.prior.symptoms-present",
                        response: .symptomsPresent,
                        prominent: false
                    )
                    responseButton(
                        title: localized("session.ohp.question.uncertain"),
                        identifier: "session.ohp.prior.uncertain",
                        response: .uncertain,
                        prominent: false
                    )
                }

                Text(localized("session.ohp.medicalDisclaimer"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.large)
        }
        .accessibilityIdentifier("session.ohp.question")
        .task {
            isQuestionFocused = true
        }
    }

    @ViewBuilder
    private func responseButton(
        title: String,
        identifier: String,
        response: OHPSymptomResponse,
        prominent: Bool
    ) -> some View {
        if prominent {
            PrimaryActionButton(
                title: title,
                accessibilityLabel: title,
                action: { answer(response) }
            )
            .frame(minHeight: 52)
            .accessibilityIdentifier(identifier)
        } else {
            Button(title) {
                answer(response)
            }
            .font(AppTypography.label)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(AppColors.color(.backgroundSunken, scheme: colorScheme))
            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier(identifier)
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
