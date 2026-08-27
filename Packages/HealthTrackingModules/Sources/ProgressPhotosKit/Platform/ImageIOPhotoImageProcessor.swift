import Foundation
import ImageIO
import UniformTypeIdentifiers

public final class ImageIOPhotoImageProcessor:
    PhotoImageProcessing,
    @unchecked Sendable {
    public init() {}

    public func inspect(_ bytes: Data) throws -> PhotoImageMetadata {
        guard !bytes.isEmpty,
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  nil
              ) as NSDictionary?,
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0 else {
            throw PhotoImageProcessingError.corruptInput
        }
        let rawOrientation = (
            properties[kCGImagePropertyOrientation] as? NSNumber
        )?.intValue ?? PhotoImageOrientation.up.rawValue
        guard let orientation = PhotoImageOrientation(rawValue: rawOrientation) else {
            throw PhotoImageProcessingError.corruptInput
        }
        return PhotoImageMetadata(
            pixelWidth: width,
            pixelHeight: height,
            orientation: orientation
        )
    }

    public func normalize(
        _ bytes: Data,
        metadata: PhotoImageMetadata,
        policy: PhotoAssetPolicy
    ) throws -> PhotoNormalizedAsset {
        guard metadata.pixelWidth > 0,
              metadata.pixelHeight > 0,
              let source = CGImageSourceCreateWithData(bytes as CFData, nil) else {
            throw PhotoImageProcessingError.corruptInput
        }
        let full = try encodedThumbnail(
            from: source,
            maximumDimension: policy.fullMaximumDimension,
            quality: policy.encodingQuality
        )
        let thumbnail = try encodedThumbnail(
            from: source,
            maximumDimension: policy.thumbnailMaximumDimension,
            quality: policy.encodingQuality
        )
        return PhotoNormalizedAsset(full: full, thumbnail: thumbnail)
    }

    private func encodedThumbnail(
        from source: CGImageSource,
        maximumDimension: Int,
        quality: Double
    ) throws -> PhotoEncodedImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw PhotoImageProcessingError.corruptInput
        }

        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw PhotoImageProcessingError.encodingFailed
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyOrientation: PhotoImageOrientation.up.rawValue,
        ]
        CGImageDestinationAddImage(
            destination,
            image,
            properties as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoImageProcessingError.encodingFailed
        }
        return PhotoEncodedImage(
            bytes: Data(referencing: encoded),
            pixelWidth: image.width,
            pixelHeight: image.height,
            orientation: .up,
            containsMetadata: false
        )
    }
}
