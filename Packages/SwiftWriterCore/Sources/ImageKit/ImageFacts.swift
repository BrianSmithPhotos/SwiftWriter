import Foundation
import ImageIO
import PostKit
import UniformTypeIdentifiers

/// What could be read out of an image file itself.
public struct ImageFacts: Sendable, Equatable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var capture: CaptureMetadata
    /// IPTC caption, when the photographer wrote one. A useful seed for the block caption.
    public var embeddedCaption: String?
    /// IPTC credit or TIFF artist.
    public var credit: String?
}

public enum ImageReadError: Error {
    case notAnImage
}

/// Reads capture metadata with ImageIO.
///
/// The file is the authority, not the blog's database: EXIF and IPTC survive the image being
/// re-uploaded, re-hosted or exported, which is exactly the case being handled here.
public enum ImageMetadataReader {
    public static func read(data: Data) throws -> ImageFacts {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw ImageReadError.notAnImage }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]

        var capture = CaptureMetadata()
        capture.captureDate = (exif[kCGImagePropertyExifDateTimeOriginal] as? String)
            .flatMap(parseEXIFDate)
        capture.camera = [tiff[kCGImagePropertyTIFFMake] as? String,
                          tiff[kCGImagePropertyTIFFModel] as? String]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfEmpty
        capture.lens = (exif[kCGImagePropertyExifLensModel] as? String)?.nilIfEmpty
        capture.focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
        capture.aperture = exif[kCGImagePropertyExifFNumber] as? Double
        capture.shutterSpeed = exif[kCGImagePropertyExifExposureTime] as? Double
        capture.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
        capture.keywords = (iptc[kCGImagePropertyIPTCKeywords] as? [String]) ?? []

        if let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
           let longitude = gps[kCGImagePropertyGPSLongitude] as? Double {
            // EXIF stores magnitude and hemisphere separately.
            let south = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S"
            let west = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W"
            capture.latitude = south ? -latitude : latitude
            capture.longitude = west ? -longitude : longitude
        }

        return ImageFacts(
            pixelWidth: properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
            pixelHeight: properties[kCGImagePropertyPixelHeight] as? Int ?? 0,
            capture: capture,
            embeddedCaption: (iptc[kCGImagePropertyIPTCCaptionAbstract] as? String)?.nilIfEmpty,
            credit: ((iptc[kCGImagePropertyIPTCCredit] as? String)
                ?? (tiff[kCGImagePropertyTIFFArtist] as? String))?.nilIfEmpty
        )
    }

    /// EXIF dates are `yyyy:MM:dd HH:mm:ss` in the camera's local time, with no offset.
    static func parseEXIFDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value)
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
