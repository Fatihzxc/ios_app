import CoreModels
import DesignSystem
import SwiftUI

@MainActor
public struct OHPPriorSymptomQuestionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AccessibilityFocusState private var isQuestionFocused: Bool
    @AccessibilityFocusState private var levelTwoHeadingFocused: Bool
    private let safetyPresentation: TrainingSymptomSafetyPresentation?
    private let answer: (OHPSymptomResponse) -> Void

    public init(
        safetyPresentation: TrainingSymptomSafetyPresentation? = nil,
        answer: @escaping (OHPSymptomResponse) -> Void
    ) {
        self.safetyPresentation = safetyPresentation
        self.answer = answer
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                safetyContent

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
                if safetyPresentation == nil {
                    Text(localized("session.ohp.medicalDisclaimer"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.large)
            .padding(.bottom, SessionStageLayout.bottomActionClearance)
        }
        .accessibilityIdentifier("session.ohp.question")
        .task {
            isQuestionFocused = !isLevelTwoPresented
        }
        .onChange(of: isLevelTwoPresented) { _, isPresented in
            updateLevelTwoHeadingFocus(isPresented: isPresented)
        }
    }

    @ViewBuilder
    private var safetyContent: some View {
        if let safetyPresentation {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(safetyPresentation.disclaimer)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("medical.disclaimer.l1")
                Text(localized("medical.safety.l2.heading"))
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("medical.safety.l2.heading")
                    .accessibilityFocused($levelTwoHeadingFocused)
                Text(safetyPresentation.levelTwoMessage)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("medical.safety.l2")
            }
            .onAppear {
                updateLevelTwoHeadingFocus(isPresented: true)
            }
            .transition(levelTwoTransition)
        }
    }

    private var isLevelTwoPresented: Bool {
        safetyPresentation != nil
    }

    private var levelTwoTransition: AnyTransition {
        MedicalSafetyMotionPolicy.transition(
            reduceMotion: accessibilityReduceMotion,
            identity: .identity,
            opacity: .opacity
        )
    }

    private func updateLevelTwoHeadingFocus(isPresented: Bool) {
        levelTwoHeadingFocused = MedicalSafetyFocusPolicy.headingFocused(
            isLevelTwoPresented: isPresented
        )
        isQuestionFocused = !isPresented
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
                minimumHeight: 52,
                action: { answer(response) }
            )
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
