import SwiftUI
import UIKit
import XCTest
@testable import DesignSystem

@MainActor
final class GalleryScreenshotTests: XCTestCase {
    func testGalleryAttachesDeterministicLightAndDarkEvidence() throws {
        let light = try renderedGallery(scheme: .light)
        let dark = try renderedGallery(scheme: .dark)

        let lightData = try XCTUnwrap(light.pngData())
        let darkData = try XCTUnwrap(dark.pngData())
        XCTAssertNotEqual(lightData, darkData, "Light and dark gallery evidence must be visually distinct.")
        try assertRenderedGalleryStructure(light, appearance: "light")
        try assertRenderedGalleryStructure(dark, appearance: "dark")

        attach(light, name: "gallery-light")
        attach(dark, name: "gallery-dark")
    }

    private func renderedGallery(scheme: ColorScheme) throws -> UIImage {
        let galleryHeight = 2_600.0
        let renderer = ImageRenderer(
            content: ZStack(alignment: .top) {
                AppColors.color(.backgroundBase, scheme: scheme)
                GalleryContentView()
            }
            .environment(\.colorScheme, scheme)
            .frame(width: 390, height: galleryHeight, alignment: .top)
        )
        renderer.proposedSize = ProposedViewSize(width: 390, height: galleryHeight)
        renderer.scale = 3
        return try XCTUnwrap(renderer.uiImage)
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertRenderedGalleryStructure(_ image: UIImage, appearance: String) throws {
        let cgImage = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(cgImage.width, 1_170, "\(appearance) gallery width must be 390pt at 3x scale.")
        XCTAssertEqual(cgImage.height, 7_800, "\(appearance) gallery height must be 2600pt at 3x scale.")

        let width = cgImage.width
        let height = cgImage.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = try XCTUnwrap(
            CGContext(
                data: &rgba,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            )
        )
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        let sampleColumns = 24
        let sampleRows = 36
        var opaqueSamples = 0
        var distinctColors = Set<UInt32>()

        for row in 0..<sampleRows {
            let y = min(height - 1, ((row * 2 + 1) * height) / (sampleRows * 2))
            for column in 0..<sampleColumns {
                let x = min(width - 1, ((column * 2 + 1) * width) / (sampleColumns * 2))
                let offset = ((y * width) + x) * 4
                let color = (UInt32(rgba[offset]) << 24)
                    | (UInt32(rgba[offset + 1]) << 16)
                    | (UInt32(rgba[offset + 2]) << 8)
                    | UInt32(rgba[offset + 3])
                distinctColors.insert(color)
                if rgba[offset + 3] >= 250 {
                    opaqueSamples += 1
                }
            }
        }

        let totalSamples = sampleColumns * sampleRows
        XCTAssertGreaterThanOrEqual(
            Double(opaqueSamples) / Double(totalSamples),
            0.98,
            "\(appearance) gallery evidence must not be transparent."
        )
        XCTAssertGreaterThan(
            distinctColors.count,
            8,
            "\(appearance) gallery evidence must contain rendered structural content, not a solid frame."
        )
    }
}
