import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct DerivativeSettings: Sendable {
    /// Longest edge in pixels. Images already at or below this are passed through untouched.
    public var maxLongEdge: Int
    public var quality: Double

    public init(maxLongEdge: Int = 2048, quality: Double = 0.82) {
        self.maxLongEdge = maxLongEdge
        self.quality = quality
    }

    public static let `default` = DerivativeSettings()
}

public struct Derivative: Sendable, Equatable {
    public var data: Data
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var fileExtension: String
    /// True when the source was already small enough and the original bytes were kept.
    public var passedThrough: Bool
}

public enum WebDerivative {
    /// Formats a browser can render without help. Anything else is re-encoded as JPEG even
    /// when it is already small enough, because size is not the only reason to convert.
    private static let webServable: [UTType] = [.jpeg, .png, .gif, .webP]

    /// Produces the web-ready copy that lives inside the package.
    ///
    /// A source that is already within `maxLongEdge` is returned byte for byte. Re-encoding
    /// an already-compressed JPEG only loses quality and gains nothing, and much of the
    /// existing blog is served at 1280px.
    public static func make(
        from data: Data,
        settings: DerivativeSettings = .default
    ) throws -> Derivative {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw ImageReadError.notAnImage }

        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let sourceType = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) }
        let sourceExtension = sourceType?.preferredFilenameExtension ?? "jpg"

        // Passing through is only right when a browser can be handed the file as it is.
        // A HEIC under the size limit is still a HEIC, and passing it through would put a
        // file most browsers cannot show into the package and then onto the blog.
        let servable = sourceType.map { type in webServable.contains(where: type.conforms(to:)) } ?? false

        if servable, max(width, height) <= settings.maxLongEdge {
            return Derivative(
                data: data,
                pixelWidth: width,
                pixelHeight: height,
                fileExtension: sourceExtension,
                passedThrough: true
            )
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: settings.maxLongEdge,
            // Honour the EXIF orientation flag so the derivative is the right way up.
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageReadError.notAnImage
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw ImageReadError.notAnImage }

        // Carry the source properties across. A photo blog's images are worth little
        // without their camera, lens and GPS, and CGImageDestination writes none of it
        // unless it is handed back explicitly. Orientation is dropped because the
        // thumbnail transform has already applied it - keeping the flag would rotate twice.
        var destinationProperties = properties
        destinationProperties[kCGImagePropertyOrientation] = nil
        if var tiff = destinationProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = nil
            destinationProperties[kCGImagePropertyTIFFDictionary] = tiff
        }
        destinationProperties[kCGImagePropertyPixelWidth] = scaled.width
        destinationProperties[kCGImagePropertyPixelHeight] = scaled.height
        destinationProperties[kCGImageDestinationLossyCompressionQuality] = settings.quality

        CGImageDestinationAddImage(destination, scaled, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageReadError.notAnImage }

        return Derivative(
            data: output as Data,
            pixelWidth: scaled.width,
            pixelHeight: scaled.height,
            fileExtension: "jpg",
            passedThrough: false
        )
    }
}
