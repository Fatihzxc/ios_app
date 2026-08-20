import CoreModels
import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct WorkoutSessionDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: TrainingHistoryViewModel
    private let sessionID: UUID
    @State private var isEditPresented = false

    public init(viewModel: TrainingHistoryViewModel, sessionID: UUID) {
        self.viewModel = viewModel
        self.sessionID = sessionID
    }

    public var body: some View {
        Group {
            if let session = viewModel.session(id: sessionID) {
                detail(session)
            } else if viewModel.state == .loading {
                FeatureStateView(state: .loading)
            } else {
                Text(localized("history.detail.missing"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .padding(AppSpacing.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.color(.backgroundBase, scheme: colorScheme))
        .navigationTitle(localized("history.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("training.history.detail")
        .sheet(isPresented: $isEditPresented) {
            EditSetView(viewModel: viewModel)
        }
        .alert(
            deletionTitle,
            isPresented: deletionBinding
        ) {
            Button(localized("history.delete.cancel"), role: .cancel) {
                viewModel.cancelDeletion()
            }
            Button(deletionActionTitle, role: .destructive) {
                let deletesSession: Bool
                if case .some(.session(_)) = viewModel.pendingDeletion {
                    deletesSession = true
                } else {
                    deletesSession = false
                }
                Task {
                    await viewModel.confirmDeletion()
                    if deletesSession, viewModel.session(id: sessionID) == nil {
                        dismiss()
                    }
                }
            }
        } message: {
            Text(deletionMessage)
        }
    }

    private func detail(
        _ session: TrainingHistorySessionPresentation
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                sessionHeader(session)

                if session.workoutDayName == nil ||
                    session.exercises.contains(where: { $0.exerciseName == nil }) {
                    AppCard {
                        Text(localized("history.missingTemplate"))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    }
                    .accessibilityIdentifier("training.history.missingTemplate")
                }

                ForEach(session.exercises) { exercise in
                    exerciseSection(exercise, in: session)
                }

                Button(role: .destructive) {
                    viewModel.requestSessionDeletion(id: session.id)
                } label: {
                    Text(localized("history.session.delete"))
                        .font(AppTypography.label)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("training.history.session.delete")
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.large)
        }
    }

    private func sessionHeader(
        _ session: TrainingHistorySessionPresentation
    ) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(session.workoutDayName ?? localized("history.missing.day"))
                    .font(AppTypography.titleLarge)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .accessibilityAddTraits(.isHeader)
                Text(session.session.date.formatted(date: .long, time: .shortened))
                    .font(AppTypography.numericRow)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                if let focus = session.workoutDayFocus, !focus.isEmpty {
                    Text(focus)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                }
                if let recovery = session.session.perceivedRecovery {
                    Text(
                        String(
                            format: localized("history.session.recovery"),
                            locale: .current,
                            Int64(recovery)
                        )
                    )
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                }
                if let note = session.session.note, !note.isEmpty {
                    Text(note)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                }
            }
        }
    }

    private func exerciseSection(
        _ exercise: TrainingHistoryExercisePresentation,
        in session: TrainingHistorySessionPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            Text(exercise.exerciseName ?? localized("history.missing.exercise"))
                .font(AppTypography.titleMedium)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .accessibilityAddTraits(.isHeader)

            ForEach(exercise.sets) { set in
                setCard(
                    set,
                    kind: exercise.measurementKind,
                    index: setIndex(set.id, in: session)
                )
            }
        }
    }

    private func setCard(
        _ set: TrainingHistorySetPresentation,
        kind: ExerciseMeasurementKind?,
        index: Int
    ) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                HStack(alignment: .firstTextBaseline) {
                    Text(
                        String(
                            format: localized("history.set.index"),
                            locale: .current,
                            Int64(set.setLog.setIndex)
                        )
                    )
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    Spacer()
                    if set.isPersonalRecord {
                        Text(localized("history.set.personalRecord"))
                            .font(AppTypography.caption)
                            .foregroundStyle(
                                AppColors.color(.stateSuccess, scheme: colorScheme)
                            )
                    }
                }
                Text(measurementText(set.setLog.measurement, kind: kind))
                    .font(AppTypography.numericRow)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .accessibilityLabel(
                        Text(
                            String(
                                format: localized("history.set.accessibility"),
                                locale: .current,
                                Int64(set.setLog.setIndex),
                                measurementText(set.setLog.measurement, kind: kind)
                            )
                        )
                    )
                    .accessibilityValue(
                        Text(measurementText(set.setLog.measurement, kind: kind))
                    )
                    .accessibilityAction(named: Text(localized("history.set.edit"))) {
                        viewModel.beginEditing(setID: set.id)
                        isEditPresented = viewModel.editingSet != nil
                    }
                    .accessibilityAction(named: Text(localized("history.set.delete"))) {
                        viewModel.requestSetDeletion(id: set.id)
                    }
                    .accessibilityIdentifier("training.history.set.\(index)")
                HStack(spacing: AppSpacing.standard) {
                    Button(localized("history.set.edit")) {
                        viewModel.beginEditing(setID: set.id)
                        isEditPresented = viewModel.editingSet != nil
                    }
                    .accessibilityIdentifier("training.history.set.edit.\(index)")
                    Spacer()
                    Button(localized("history.set.delete"), role: .destructive) {
                        viewModel.requestSetDeletion(id: set.id)
                    }
                    .accessibilityIdentifier("training.history.set.delete.\(index)")
                }
                .font(AppTypography.label)
            }
        }
    }

    private func setIndex(
        _ setID: UUID,
        in session: TrainingHistorySessionPresentation
    ) -> Int {
        session.exercises.flatMap(\.sets).firstIndex { $0.id == setID } ?? 0
    }

    private func measurementText(
        _ measurement: SetMeasurementInput,
        kind: ExerciseMeasurementKind?
    ) -> String {
        guard let kind else { return localized("history.measurement.unavailable") }
        switch kind {
        case .weightReps:
            return String(
                format: localized("history.measurement.weightReps"),
                locale: .current,
                formatMass(measurement.weightKg),
                formatInteger(measurement.reps)
            )
        case .reps:
            return String(
                format: localized("history.measurement.reps"),
                locale: .current,
                formatInteger(measurement.reps),
                measurement.performedVariant ?? localized("history.measurement.defaultVariant")
            )
        case .duration:
            return String(
                format: localized("history.measurement.duration"),
                locale: .current,
                formatDuration(measurement.durationSec),
                measurement.performedVariant ?? localized("history.measurement.defaultVariant")
            )
        case .steps:
            return String(
                format: localized("history.measurement.steps"),
                locale: .current,
                formatInteger(measurement.distanceSteps),
                formatMass(measurement.weightKg)
            )
        case .quality:
            if let reps = measurement.reps {
                return String(
                    format: localized("history.measurement.qualityReps"),
                    locale: .current,
                    formatInteger(reps)
                )
            }
            if let duration = measurement.durationSec {
                return String(
                    format: localized("history.measurement.qualityDuration"),
                    locale: .current,
                    formatDuration(duration)
                )
            }
            return localized("history.measurement.quality")
        }
    }

    private func formatMass(_ kilograms: Double?) -> String {
        guard let kilograms else { return localized("history.measurement.unset") }
        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 2
        return formatter.string(
            from: Measurement(value: kilograms, unit: UnitMass.kilograms)
        )
    }

    private func formatDuration(_ seconds: Int?) -> String {
        guard let seconds else { return localized("history.measurement.unset") }
        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        return formatter.string(
            from: Measurement(value: Double(seconds), unit: UnitDuration.seconds)
        )
    }

    private func formatInteger(_ value: Int?) -> String {
        guard let value else { return localized("history.measurement.unset") }
        return value.formatted(.number.locale(.current))
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingDeletion != nil },
            set: { _ in }
        )
    }

    private var deletionTitle: String {
        switch viewModel.pendingDeletion {
        case .some(.set(_)):
            localized("history.delete.set.title")
        case .some(.session(_)):
            localized("history.delete.session.title")
        case nil:
            localized("history.delete.set.title")
        }
    }

    private var deletionMessage: String {
        switch viewModel.pendingDeletion {
        case .some(.set(_)):
            localized("history.delete.set.message")
        case .some(.session(_)):
            localized("history.delete.session.message")
        case nil:
            ""
        }
    }

    private var deletionActionTitle: String {
        switch viewModel.pendingDeletion {
        case .some(.set(_)):
            localized("history.delete.set.action")
        case .some(.session(_)):
            localized("history.delete.session.action")
        case nil:
            localized("history.delete.set.action")
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
