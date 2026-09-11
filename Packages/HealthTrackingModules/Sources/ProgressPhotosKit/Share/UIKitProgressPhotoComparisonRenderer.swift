import CoreGraphics
import CoreModels
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum ProgressPhotoComparisonImageValidation {
    static func validate(
        _ descriptor: ProgressPhotoComparisonShareDescriptor
    ) throws {
        try validate(descriptor.before.imageData)
        try validate(descriptor.after.imageData)
    }

    static func validate(_ data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) != nil else {
            throw ProgressPhotoComparisonShareError.corruptImage
        }
    }
}

enum JPEGPrivacySegmentSanitizer {
    static func sanitize(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xff, bytes[1] == 0xd8 else {
            throw ProgressPhotoComparisonShareError.renderingFailed
        }

        var output = Data([0xff, 0xd8])
        var cursor = 2
        while cursor < bytes.count {
            let markerStart = cursor
            guard bytes[cursor] == 0xff else {
                throw ProgressPhotoComparisonShareError.renderingFailed
            }
            while cursor < bytes.count, bytes[cursor] == 0xff {
                cursor += 1
            }
            guard cursor < bytes.count else {
                throw ProgressPhotoComparisonShareError.renderingFailed
            }
            let marker = bytes[cursor]
            cursor += 1
            guard marker != 0x00 else {
                throw ProgressPhotoComparisonShareError.renderingFailed
            }

            switch marker {
            case 0xda:
                let segmentEnd = try segmentEnd(
                    in: bytes,
                    lengthOffset: cursor
                )
                let scanEnd = try scanEnd(in: bytes, startingAt: segmentEnd)
                guard scanEnd == bytes.count else {
                    throw ProgressPhotoComparisonShareError.renderingFailed
                }
                output.append(contentsOf: bytes[markerStart..<scanEnd])
                return output
            case 0xd8, 0xd9, 0x01, 0xd0...0xd7:
                throw ProgressPhotoComparisonShareError.renderingFailed
            default:
                let segmentEnd = try segmentEnd(
                    in: bytes,
                    lengthOffset: cursor
                )
                if (0xe1...0xef).contains(marker) || marker == 0xfe {
                    cursor = segmentEnd
                    continue
                }
                output.append(contentsOf: bytes[markerStart..<segmentEnd])
                cursor = segmentEnd
            }
        }
        throw ProgressPhotoComparisonShareError.renderingFailed
    }

    private static func segmentEnd(
        in bytes: [UInt8],
        lengthOffset: Int
    ) throws -> Int {
        guard lengthOffset + 1 < bytes.count else {
            throw ProgressPhotoComparisonShareError.renderingFailed
        }
        let segmentLength =
            (Int(bytes[lengthOffset]) << 8) | Int(bytes[lengthOffset + 1])
        guard segmentLength >= 2 else {
            throw ProgressPhotoComparisonShareError.renderingFailed
        }
        let segmentEnd = lengthOffset + segmentLength
        guard segmentEnd <= bytes.count else {
            throw ProgressPhotoComparisonShareError.renderingFailed
        }
        return segmentEnd
    }

    private static func scanEnd(
        in bytes: [UInt8],
        startingAt start: Int
    ) throws -> Int {
        var cursor = start
        while cursor < bytes.count {
            guard bytes[cursor] == 0xff else {
                cursor += 1
                continue
            }
            cursor += 1
            while cursor < bytes.count, bytes[cursor] == 0xff {
                cursor += 1
            }
            guard cursor < bytes.count else {
                throw ProgressPhotoComparisonShareError.renderingFailed
            }
            switch bytes[cursor] {
            case 0x00, 0xd0...0xd7:
                cursor += 1
            case 0xd9:
                return cursor + 1
            default:
                throw ProgressPhotoComparisonShareError.renderingFailed
            }
        }
        throw ProgressPhotoComparisonShareError.renderingFailed
    }
}

@MainActor
public final class UIKitProgressPhotoComparisonRenderer:
    ProgressPhotoComparisonRendering {
    private struct CaptionLayout {
        let title: NSAttributedString
        let detail: NSAttributedString
        let titleHeight: CGFloat
        let detailHeight: CGFloat

        var height: CGFloat { titleHeight + 10 + detailHeight }
    }

    private let outputWidth: CGFloat
    private let maximumImageHeight: CGFloat
    private let jpegQuality: CGFloat
    private let traitCollection: UITraitCollection
    private let captionHorizontalInset: CGFloat = 20

    public init(
        outputWidth: CGFloat = 1_600,
        maximumImageHeight: CGFloat = 1_000,
        jpegQuality: CGFloat = 0.9,
        traitCollection: UITraitCollection? = nil
    ) {
        self.outputWidth = outputWidth
        self.maximumImageHeight = maximumImageHeight
        self.jpegQuality = jpegQuality
        self.traitCollection = traitCollection ?? UITraitCollection.current
    }

    public func render(
        _ descriptor: ProgressPhotoComparisonShareDescriptor
    ) async throws -> Data {
        let beforeImage = try decode(descriptor.before.imageData)
        let afterImage = try decode(descriptor.after.imageData)
        try Task.checkCancellation()

        let spacing: CGFloat = 32
        let outerPadding: CGFloat = 48
        let paneWidth = (outputWidth - (outerPadding * 2) - spacing) / 2
        guard paneWidth > captionHorizontalInset * 2 else {
            throw ProgressPhotoComparisonShareError.renderingFailed
        }
        let beforeCaption = captionLayout(
            item: descriptor.before,
            title: localized("photos.compare.before"),
            paneWidth: paneWidth - captionHorizontalInset * 2
        )
        let afterCaption = captionLayout(
            item: descriptor.after,
            title: localized("photos.compare.after"),
            paneWidth: paneWidth - captionHorizontalInset * 2
        )
        let captionHeight = max(beforeCaption.height, afterCaption.height)
        let imageSpacing: CGFloat = 24
        let imageHeight = min(
            maximumImageHeight,
            max(
                fittedHeight(for: beforeImage, width: paneWidth),
                fittedHeight(for: afterImage, width: paneWidth)
            )
        )
        let outputSize = CGSize(
            width: outputWidth,
            height: outerPadding
                + captionHeight
                + imageSpacing
                + imageHeight
                + outerPadding
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let composite = renderer.image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: outputSize))
            drawPane(
                image: beforeImage,
                caption: beforeCaption,
                originX: outerPadding,
                paneWidth: paneWidth,
                imageHeight: imageHeight,
                imageOriginY: outerPadding + captionHeight + imageSpacing
            )
            drawPane(
                image: afterImage,
                caption: afterCaption,
                originX: outerPadding + paneWidth + spacing,
                paneWidth: paneWidth,
                imageHeight: imageHeight,
                imageOriginY: outerPadding + captionHeight + imageSpacing
            )
        }
        try Task.checkCancellation()
        let encodedJPEG = try encodeMetadataFreeJPEG(composite)
        let sanitizedJPEG = try JPEGPrivacySegmentSanitizer.sanitize(encodedJPEG)
        try ProgressPhotoComparisonImageValidation.validate(sanitizedJPEG)
        return sanitizedJPEG
    }

    private func decode(_ data: Data) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else {
            throw ProgressPhotoComparisonShareError.corruptImage
        }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    private func drawPane(
        image: UIImage,
        caption: CaptionLayout,
        originX: CGFloat,
        paneWidth: CGFloat,
        imageHeight: CGFloat,
        imageOriginY: CGFloat
    ) {
        caption.title.draw(
            with: CGRect(
                x: originX + captionHorizontalInset,
                y: 48,
                width: paneWidth - captionHorizontalInset * 2,
                height: caption.titleHeight
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        caption.detail.draw(
            with: CGRect(
                x: originX + captionHorizontalInset,
                y: 48 + caption.titleHeight + 10,
                width: paneWidth - captionHorizontalInset * 2,
                height: caption.detailHeight
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        let imageBounds = CGRect(
            x: originX,
            y: imageOriginY,
            width: paneWidth,
            height: imageHeight
        )
        UIColor(red: 0.94, green: 0.94, blue: 0.95, alpha: 1).setFill()
        UIBezierPath(roundedRect: imageBounds, cornerRadius: 18).fill()
        let target = aspectFitRect(image.size, inside: imageBounds)
        image.draw(in: target)
    }

    private func captionLayout(
        item: ProgressPhotoShareItem,
        title: String,
        paneWidth: CGFloat
    ) -> CaptionLayout {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        let titleFont = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: UIFont.systemFont(ofSize: 32, weight: .semibold),
            compatibleWith: traitCollection
        )
        let detailFont = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 24, weight: .regular),
            compatibleWith: traitCollection
        )
        let titleText = NSAttributedString(
            string: title,
            attributes: [
                .font: titleFont,
                .foregroundColor: UIColor(
                    red: 0.07,
                    green: 0.08,
                    blue: 0.10,
                    alpha: 1
                ),
                .paragraphStyle: paragraph,
            ]
        )
        let detailText = NSAttributedString(
            string: "\(poseTitle(item.pose)) · \(dateTitle(item.date))",
            attributes: [
                .font: detailFont,
                .foregroundColor: UIColor(
                    red: 0.18,
                    green: 0.20,
                    blue: 0.23,
                    alpha: 1
                ),
                .paragraphStyle: paragraph,
            ]
        )
        return CaptionLayout(
            title: titleText,
            detail: detailText,
            titleHeight: measuredHeight(titleText, width: paneWidth),
            detailHeight: measuredHeight(detailText, width: paneWidth)
        )
    }

    private func measuredHeight(
        _ text: NSAttributedString,
        width: CGFloat
    ) -> CGFloat {
        ceil(
            text.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height
        ) + 2
    }

    private func fittedHeight(for image: UIImage, width: CGFloat) -> CGFloat {
        guard image.size.width > 0 else { return maximumImageHeight }
        return width * image.size.height / image.size.width
    }

    private func aspectFitRect(_ size: CGSize, inside bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: bounds.midX - targetSize.width / 2,
            y: bounds.midY - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )
    }

    private func encodeMetadataFreeJPEG(_ image: UIImage) throws -> Data {
        guard let image = image.cgImage else {
            throw ProgressPhotoComparisonShareError.renderingFailed
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ProgressPhotoComparisonShareError.renderingFailed
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ProgressPhotoComparisonShareError.renderingFailed
        }
        return Data(referencing: output)
    }

    private func dateTitle(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
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
