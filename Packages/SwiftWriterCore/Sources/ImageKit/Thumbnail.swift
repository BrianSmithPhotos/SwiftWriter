import CoreGraphics
import Foundation
import ImageIO

public enum Thumbnail {
    /// Decodes a downsampled image straight from the file, without ever holding the
    /// full-size bitmap. A post can carry seventy images; decoding those at full size
    /// to draw them a few hundred points wide would cost hundreds of megabytes.
    public static func make(contentsOf url: URL, maxPixelSize: Int) throws -> CGImage {
        // .alwaysMapped keeps the file out of the heap; ImageIO reads what it needs.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageReadError.notAnImage
        }
        return try make(from: source, maxPixelSize: maxPixelSize)
    }

    public static func make(data: Data, maxPixelSize: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageReadError.notAnImage
        }
        return try make(from: source, maxPixelSize: maxPixelSize)
    }

    private static func make(from source: CGImageSource, maxPixelSize: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            // Apply the EXIF orientation, or portrait frames draw on their side.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageReadError.notAnImage
        }
        return image
    }
}
