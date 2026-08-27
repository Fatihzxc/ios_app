import CoreModels
import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct ProgressPhotoAccessButton: View {
    private let action: @MainActor () -> Void

    public init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(localized("photos.title"), systemImage: "photo.stack")
                .font(AppTypography.label)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("photos.open")
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}

@MainActor
public struct ProgressPhotoLifecycleView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var viewModel: ProgressPhotoImportViewModel
    private let fixtureImageData: Data?
    private let onClose: @MainActor () -> Void
    @State private var pendingDelete: ProgressPhotoSnapshot?
    @State private var isConfirmingDelete = false

    public init(
        viewModel: ProgressPhotoImportViewModel,
        fixtureImageData: Data? = nil,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.fixtureImageData = fixtureImageData
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
                    Text(localized("photos.title"))
                        .font(AppTypography.titleLarge)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("photos.lifecycle.content")
                    Text(localized("photos.local-only.status"))
                        .font(AppTypography.caption)
                        .foregroundStyle(
                            AppColors.color(.inkSecondary, scheme: colorScheme)
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("photos.local-only.status")

                    DatePicker(
                        localized("photos.date"),
                        selection: $viewModel.date,
                        displayedComponents: .date
                    )
                    .frame(minHeight: 52)
                    .disabled(viewModel.isMutationInFlight)
                    .accessibilityIdentifier("photos.date")

                    Picker(localized("photos.pose"), selection: $viewModel.pose) {
                        ForEach(ProgressPhotoPose.allCases, id: \.self) { pose in
                            Text(poseTitle(pose)).tag(pose)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(viewModel.isMutationInFlight)
                    .accessibilityIdentifier("photos.pose")

                    TextField(localized("photos.note"), text: $viewModel.note)
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: 52)
                        .disabled(viewModel.isMutationInFlight)
                        .accessibilityIdentifier("photos.note")

                    SystemPhotosPickerView(title: localized("photos.picker")) { selection in
                        Task { await viewModel.importSelection(selection) }
                    }
                    .disabled(viewModel.isMutationInFlight)

                    if let fixtureImageData {
                        Button(localized("photos.import.fixture")) {
                            Task { await viewModel.importFixtureBytes(fixtureImageData) }
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 52)
                        .disabled(viewModel.isMutationInFlight)
                        .accessibilityIdentifier("photos.import.fixture")
                    }

                    importState
                    listState
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .navigationTitle(localized("photos.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized("photos.close"), action: onClose)
                        .accessibilityIdentifier("photos.close")
                }
            }
        }
        .interactiveDismissDisabled(viewModel.phase == .loading || viewModel.isDeleting)
        .task {
            if viewModel.listPhase == .idle {
                await viewModel.load()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.retryPendingAssetCleanup() }
        }
        .confirmationDialog(
            localized("photos.delete.confirmation"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(localized("photos.delete"), role: .destructive) {
                guard let pendingDelete else { return }
                Task {
                    if await viewModel.delete(pendingDelete) {
                        self.pendingDelete = nil
                    }
                }
            }
            .accessibilityIdentifier("photos.delete-confirm")
            Button(localized("photos.cancel"), role: .cancel) {
                pendingDelete = nil
            }
        }
    }

    @ViewBuilder
    private var importState: some View {
        switch viewModel.phase {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView(localized("photos.importing"))
                .accessibilityIdentifier("photos.import.loading")
        case .saved:
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(localized("photos.imported"))
                    .font(AppTypography.caption)
                    .foregroundStyle(
                        AppColors.color(.stateSuccess, scheme: colorScheme)
                    )
                    .accessibilityIdentifier("photos.import.saved")
                if viewModel.canUndoLastImport {
                    Button(localized("photos.import.undo")) {
                        Task { await viewModel.undoLastImport() }
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("photos.import.undo")
                }
            }
        case .failed:
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(localized("photos.import.error"))
                    .font(AppTypography.caption)
                    .foregroundStyle(
                        AppColors.color(.stateDanger, scheme: colorScheme)
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("photos.import.error")
                if viewModel.canRetryImport {
                    Button(localized("photos.import.retry")) {
                        Task { await viewModel.retryImport() }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("photos.import.retry")
                }
                if viewModel.canRetryUndo {
                    Button(localized("photos.import.retry.undo")) {
                        Task { await viewModel.retryUndo() }
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("photos.import.retry-undo")
                }
            }
        }
    }

    @ViewBuilder
    private var listState: some View {
        switch viewModel.listPhase {
        case .idle, .loading:
            FeatureStateView(state: .loading)
                .accessibilityIdentifier("photos.list.loading")
        case .failed:
            FeatureStateView(
                state: .error(message: localized("photos.load.error")),
                retry: { Task { await viewModel.load() } }
            )
            .accessibilityIdentifier("photos.list.error")
        case .loaded:
            if viewModel.snapshots.isEmpty {
                AppCard {
                    Text(localized("photos.empty"))
                        .font(AppTypography.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("photos.list.empty")
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.standard) {
                    Text(localized("photos.list"))
                        .font(AppTypography.titleMedium)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("photos.list.content")
                    ForEach(viewModel.snapshots) { snapshot in
                        AppCard {
                            VStack(alignment: .leading, spacing: AppSpacing.small) {
                                Text(poseTitle(snapshot.pose))
                                    .font(AppTypography.label)
                                Text(
                                    snapshot.date.formatted(
                                        date: .abbreviated,
                                        time: .omitted
                                    )
                                )
                                .font(AppTypography.body)
                                if let note = snapshot.note {
                                    Text(note)
                                        .font(AppTypography.caption)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Button(role: .destructive) {
                                    pendingDelete = snapshot
                                    isConfirmingDelete = true
                                } label: {
                                    Text(localized("photos.delete"))
                                        .frame(maxWidth: .infinity, minHeight: 52)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier(
                                    "photos.delete.\(snapshot.id.uuidString.lowercased())"
                                )
                            }
                        }
                        .accessibilityIdentifier(
                            "photos.row.\(snapshot.id.uuidString.lowercased())"
                        )

                        if viewModel.deleteFailureID == snapshot.id {
                            Text(localized("photos.delete.error"))
                                .font(AppTypography.caption)
                                .foregroundStyle(
                                    AppColors.color(.stateDanger, scheme: colorScheme)
                                )
                        }
                    }
                }
            }
        }
    }

    private func poseTitle(_ pose: ProgressPhotoPose) -> String {
        switch pose {
        case .front: localized("photos.pose.front")
        case .side: localized("photos.pose.side")
        case .back: localized("photos.pose.back")
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
