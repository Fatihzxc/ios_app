import CoreModels
import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct ProgressPhotoGalleryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: ProgressPhotoGalleryViewModel
    private let deleteFailureID: UUID?
    private let accessibilityAnnouncer: any ProgressPhotoAccessibilityAnnouncing
    private let onRequestDelete: @MainActor (ProgressPhotoSnapshot) -> Void

    public init(
        viewModel: ProgressPhotoGalleryViewModel,
        deleteFailureID: UUID? = nil,
        accessibilityAnnouncer: any ProgressPhotoAccessibilityAnnouncing =
            SystemProgressPhotoAccessibilityAnnouncer(),
        onRequestDelete: @escaping @MainActor (ProgressPhotoSnapshot) -> Void
    ) {
        self.viewModel = viewModel
        self.deleteFailureID = deleteFailureID
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.onRequestDelete = onRequestDelete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            Text(localized("photos.list"))
                .font(AppTypography.caption)
                .foregroundStyle(
                    AppColors.color(.inkSecondary, scheme: colorScheme)
                )
                .accessibilityIdentifier("photos.list.content")
            Text(localized("photos.gallery.title"))
                .font(AppTypography.titleMedium)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("photos.gallery.content")
            Text(localized("photos.gallery.instructions"))
                .font(AppTypography.caption)
                .foregroundStyle(
                    AppColors.color(.inkSecondary, scheme: colorScheme)
                )
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: AppSpacing.standard)],
                spacing: AppSpacing.standard
            ) {
                ForEach(viewModel.items) { item in
                    galleryCard(item)
                }
            }

            if isReplacementNoticeVisible {
                Text(localized("photos.compare.replaced"))
                    .font(AppTypography.caption)
                    .foregroundStyle(
                        AppColors.color(.inkSecondary, scheme: colorScheme)
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("photos.compare.replaced")
            }

            if let comparison = viewModel.comparison {
                comparisonView(comparison)
            }
        }
        .task(id: viewModel.comparisonLoadID) {
            await viewModel.loadComparisonImages()
        }
    }

    private func galleryCard(_ item: ProgressPhotoGalleryItem) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                assetContent(item)
                Text(poseTitle(item.snapshot.pose))
                    .font(AppTypography.label)
                    .accessibilityIdentifier(
                        "photos.row.\(item.id.uuidString.lowercased())"
                    )
                Text(
                    item.snapshot.date.formatted(
                        date: .abbreviated,
                        time: .omitted
                    )
                )
                .font(AppTypography.body)
                if let note = item.snapshot.note {
                    Text(note)
                        .font(AppTypography.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if item.assetState.isAvailable {
                    let isSelected = viewModel.selectedPhotoIDs.contains(item.id)
                    Button {
                        let result = viewModel.toggleSelection(id: item.id)
                        if case .replacedOldest = result {
                            accessibilityAnnouncer.announce(
                                localized("photos.compare.replaced")
                            )
                        }
                    } label: {
                        Label(
                            localized(
                                isSelected
                                    ? "photos.gallery.deselect"
                                    : "photos.gallery.select"
                            ),
                            systemImage: isSelected ? "checkmark.circle.fill" : "circle"
                        )
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(
                        actionAccessibilityLabel(
                            key: isSelected
                                ? "photos.gallery.deselect"
                                : "photos.gallery.select",
                            item: item
                        )
                    )
                    .accessibilityIdentifier(
                        "photos.gallery.select.\(item.id.uuidString.lowercased())"
                    )
                    if isSelected {
                        Text(localized("photos.gallery.selected"))
                            .font(AppTypography.caption)
                            .accessibilityIdentifier(
                                "photos.gallery.selected.\(item.id.uuidString.lowercased())"
                            )
                    }
                }

                Button(role: .destructive) {
                    onRequestDelete(item.snapshot)
                } label: {
                    Text(localized("photos.delete"))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(
                    actionAccessibilityLabel(key: "photos.delete", item: item)
                )
                .accessibilityIdentifier(
                    "photos.delete.\(item.id.uuidString.lowercased())"
                )
                if deleteFailureID == item.id {
                    Text(localized("photos.delete.error"))
                        .font(AppTypography.caption)
                        .foregroundStyle(
                            AppColors.color(.stateDanger, scheme: colorScheme)
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task(id: item.thumbnailLoadID) {
            await viewModel.loadThumbnail(id: item.id)
        }
    }

    @ViewBuilder
    private func assetContent(_ item: ProgressPhotoGalleryItem) -> some View {
        switch item.assetState {
        case .unloaded, .loading:
            ProgressView(localized("photos.gallery.loading"))
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityIdentifier("photos.gallery.loading")
        case let .available(bytes):
            PhotoThumbnailView(data: bytes)
        case .missing:
            fallback(
                key: "photos.gallery.missing",
                systemImage: "photo.badge.questionmark"
            )
            .accessibilityIdentifier("photos.gallery.missing")
        case .corrupt:
            fallback(
                key: "photos.gallery.corrupt",
                systemImage: "photo.badge.exclamationmark"
            )
            .accessibilityIdentifier("photos.gallery.corrupt")
        case .unavailable:
            fallback(
                key: "photos.gallery.unavailable",
                systemImage: "lock.fill"
            )
            .accessibilityIdentifier("photos.gallery.unavailable")
        }
    }

    private func fallback(
        key: String.LocalizationValue,
        systemImage: String
    ) -> some View {
        Label(localized(key), systemImage: systemImage)
            .font(AppTypography.caption)
            .frame(maxWidth: .infinity, minHeight: 120)
            .multilineTextAlignment(.center)
            .foregroundStyle(
                AppColors.color(.inkSecondary, scheme: colorScheme)
            )
            .background(.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func comparisonView(_ comparison: ProgressPhotoComparison) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            Text(localized("photos.compare.title"))
                .font(AppTypography.titleMedium)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("photos.compare.content")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: AppSpacing.standard) {
                    comparisonPane(
                        item: comparison.before,
                        titleKey: "photos.compare.before",
                        identifier: "photos.compare.before"
                    )
                    comparisonPane(
                        item: comparison.after,
                        titleKey: "photos.compare.after",
                        identifier: "photos.compare.after"
                    )
                }
                VStack(alignment: .leading, spacing: AppSpacing.standard) {
                    comparisonPane(
                        item: comparison.before,
                        titleKey: "photos.compare.before",
                        identifier: "photos.compare.before"
                    )
                    comparisonPane(
                        item: comparison.after,
                        titleKey: "photos.compare.after",
                        identifier: "photos.compare.after"
                    )
                }
            }
        }
    }

    private func comparisonPane(
        item: ProgressPhotoGalleryItem,
        titleKey: String.LocalizationValue,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(localized(titleKey))
                .font(AppTypography.label)
            assetContent(item)
            Text(poseTitle(item.snapshot.pose))
                .font(AppTypography.caption)
            Text(
                item.snapshot.date.formatted(
                    date: .abbreviated,
                    time: .omitted
                )
            )
            .font(AppTypography.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func poseTitle(_ pose: ProgressPhotoPose) -> String {
        switch pose {
        case .front: localized("photos.pose.front")
        case .side: localized("photos.pose.side")
        case .back: localized("photos.pose.back")
        }
    }

    private func actionAccessibilityLabel(
        key: String.LocalizationValue,
        item: ProgressPhotoGalleryItem
    ) -> String {
        let date = item.snapshot.date.formatted(
            date: .abbreviated,
            time: .omitted
        )
        return "\(localized(key)), \(poseTitle(item.snapshot.pose)), \(date)"
    }

    private var isReplacementNoticeVisible: Bool {
        guard let notice = viewModel.selectionNotice else { return false }
        if case .replacedOldest = notice { return true }
        return false
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
