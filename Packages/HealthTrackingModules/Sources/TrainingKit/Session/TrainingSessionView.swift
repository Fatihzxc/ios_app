import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct TrainingSessionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Bindable private var viewModel: SessionViewModel
    private let workoutDayID: UUID
    private let onClose: @MainActor () -> Void

    public init(
        viewModel: SessionViewModel,
        workoutDayID: UUID,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.workoutDayID = workoutDayID
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    FeatureStateView(state: .loading)
                        .padding(AppSpacing.screenHorizontal)
                case let .active(presentation):
                    activeContent(presentation)
                case .failed:
                    FeatureStateView(
                        state: .error(message: localized("session.error.message")),
                        retry: retry
                    )
                    .padding(AppSpacing.screenHorizontal)
                case .dismissed:
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(localized("session.close"))
                    .accessibilityIdentifier("session.close")
                    .disabled(
                        viewModel.hasPendingCurrentOHPSymptomWrite
                            || viewModel.isSessionMutationInFlight
                            || viewModel.isSessionDeletionInFlight
                    )
                }
                if case .active = viewModel.state {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive, action: viewModel.requestDeletion) {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(localized("session.delete"))
                        .accessibilityIdentifier("session.delete")
                        .disabled(
                            viewModel.isCurrentOHPSymptomWriteSaving
                                || viewModel.isSessionRouteMutationInFlight
                                || viewModel.isSessionMutationInFlight
                                || viewModel.isSessionDeletionInFlight
                        )
                    }
                }
            }
        }
        .accessibilityIdentifier("session.root")
        .task {
            guard viewModel.state == .idle else { return }
            await viewModel.start(workoutDayID: workoutDayID)
        }
        .onChange(of: viewModel.state) { _, state in
            if state == .dismissed {
                onClose()
            }
        }
        .alert(
            localized("session.delete.confirm.title"),
            isPresented: Binding(
                get: { viewModel.isDeleteConfirmationPresented },
                set: { isPresented in
                    if !isPresented {
                        viewModel.cancelDeletion()
                    }
                }
            )
        ) {
            Button(localized("session.delete.confirm.cancel"), role: .cancel) {
                viewModel.cancelDeletion()
            }
            Button(localized("session.delete.confirm.action"), role: .destructive) {
                Task { await viewModel.confirmDeletion() }
            }
            .accessibilityIdentifier("session.delete.confirm.action")
            .disabled(
                viewModel.isSessionRouteMutationInFlight
                    || viewModel.isSessionMutationInFlight
                    || viewModel.isSessionDeletionInFlight
            )
        } message: {
            Text(localized("session.delete.confirm.message"))
        }
    }

    @ViewBuilder
    private func activeContent(_ presentation: SessionPresentation) -> some View {
        Group {
            if case .awaitingPreviousSessionResponse = viewModel.ohpSafetyState {
                OHPPriorSymptomQuestionView(
                    safetyPresentation: viewModel.symptomSafetyPresentation
                ) { response in
                    Task { await viewModel.answerPreviousOHPSymptom(response) }
                }
            } else if case let .recommendation(reason, trainingWeekIndex) =
                        viewModel.deloadState {
                DeloadRecommendationView(
                    reason: reason,
                    trainingWeekIndex: trainingWeekIndex
                ) { action in
                    Task { await viewModel.respondToDeload(action) }
                }
            } else {
                VStack(spacing: 0) {
                    if case .active = viewModel.deloadState {
                        DeloadActiveBanner()
                    }
                    switch presentation.progress.stage {
                    case .warmup:
                        WarmupStageView(
                            presentation: presentation,
                            toggleItem: { id in
                                Task { await viewModel.toggleWarmupItem(id: id) }
                            },
                            complete: {
                                Task { await viewModel.completeWarmup() }
                            },
                            skip: {
                                Task { await viewModel.skipWarmup() }
                            }
                        )
                    case .movement:
                        ExerciseStageView(viewModel: viewModel, presentation: presentation)
                    case .cooldown:
                        CooldownStageView(
                            presentation: presentation,
                            toggleItem: { id in
                                Task { await viewModel.toggleCooldownItem(id: id) }
                            },
                            goBack: {
                                Task { await viewModel.goBack() }
                            },
                            complete: {
                                Task { await viewModel.completeCooldown() }
                            },
                            skip: {
                                Task { await viewModel.skipCooldown() }
                            }
                        )
                    case .summary:
                        SessionSummaryView(viewModel: viewModel, presentation: presentation)
                    }
                }
            }
        }
        .id(activeContentIdentity(presentation))
        .transition(stageTransition)
        .animation(stageAnimation, value: activeContentIdentity(presentation))
        .disabled(viewModel.isSessionDeletionInFlight)
    }

    private func activeContentIdentity(_ presentation: SessionPresentation) -> String {
        if case .awaitingPreviousSessionResponse = viewModel.ohpSafetyState {
            return "ohp-question"
        }
        if case .recommendation = viewModel.deloadState {
            return "deload-recommendation"
        }
        return "\(presentation.progress.stage.rawValue)-\(presentation.currentExerciseIndex ?? -1)"
    }

    private var stageTransition: AnyTransition {
        if accessibilityReduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private var stageAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: 0.12)
            : .snappy(duration: 0.28)
    }

    private var navigationTitle: String {
        guard case let .active(presentation) = viewModel.state else {
            return localized("session.title")
        }
        return presentation.plan.name
    }

    private func retry() {
        Task { await viewModel.start(workoutDayID: workoutDayID) }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
