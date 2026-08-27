import Foundation
import PhotosUI
import SwiftUI

@MainActor
public struct SystemPhotosPickerView: View {
    @State private var selection: PhotosPickerItem?
    private let title: String
    private let onSelection: @MainActor ((any PhotoSelectionLoading)?) -> Void

    public init(
        title: String,
        onSelection: @escaping @MainActor ((any PhotoSelectionLoading)?) -> Void
    ) {
        self.title = title
        self.onSelection = onSelection
    }

    public var body: some View {
        PhotosPicker(
            selection: $selection,
            matching: .images
        ) {
            Label(title, systemImage: "photo.on.rectangle.angled")
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("photos.picker")
        .onChange(of: selection) { _, item in
            if let item {
                onSelection(PhotosPickerItemLoader(item: item))
            } else {
                onSelection(nil)
            }
        }
    }
}

@MainActor
private final class PhotosPickerItemLoader: PhotoSelectionLoading {
    private let item: PhotosPickerItem

    init(item: PhotosPickerItem) {
        self.item = item
    }

    func loadData() async throws -> Data? {
        try await item.loadTransferable(type: Data.self)
    }
}
