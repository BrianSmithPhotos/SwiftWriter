import Foundation

/// What the camera recorded. Read from the file with ImageIO on import, and used to seed
/// captions, to sort by capture time, and to answer "which lens was this?" later.
public struct CaptureMetadata: Codable, Sendable, Equatable {
    public var captureDate: Date?
    public var camera: String?
    public var lens: String?
    public var focalLength: Double?
    public var aperture: Double?
    public var shutterSpeed: Double?
    public var iso: Int?
    public var latitude: Double?
    public var longitude: Double?
    public var keywords: [String]

    public init(
        captureDate: Date? = nil,
        camera: String? = nil,
        lens: String? = nil,
        focalLength: Double? = nil,
        aperture: Double? = nil,
        shutterSpeed: Double? = nil,
        iso: Int? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        keywords: [String] = []
    ) {
        self.captureDate = captureDate
        self.camera = camera
        self.lens = lens
        self.focalLength = focalLength
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.iso = iso
        self.latitude = latitude
        self.longitude = longitude
        self.keywords = keywords
    }
}

/// Where the image in the package came from.
///
/// The package stores a web-ready derivative, not the original, so this is the trail back
/// to the full-resolution file. A bookmark survives the original being moved on disk; the
/// Flickr id and source URL survive the bookmark going stale, which it will on another
/// machine or on iPad.
public struct ImageProvenance: Codable, Sendable, Equatable {
    public var originalFileName: String?
    public var flickrPhotoID: String?
    public var sourceURL: URL?
    public var bookmarkData: Data?

    public init(
        originalFileName: String? = nil,
        flickrPhotoID: String? = nil,
        sourceURL: URL? = nil,
        bookmarkData: Data? = nil
    ) {
        self.originalFileName = originalFileName
        self.flickrPhotoID = flickrPhotoID
        self.sourceURL = sourceURL
        self.bookmarkData = bookmarkData
    }
}

/// An image in a post package: the record that sits beside the pixels.
public struct ImageAsset: Codable, Sendable, Equatable, Identifiable {
    public var id: ImageID
    /// Filename of the derivative inside `Images/`, extension included.
    public var fileName: String
    /// Describes the image for a reader who cannot see it. Empty is a defect, not a default.
    public var altText: String
    /// Shown beneath the image. Optional by design - not every photograph needs words.
    public var caption: InlineText?
    public var credit: String?
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var capture: CaptureMetadata?
    public var provenance: ImageProvenance

    public init(
        id: ImageID,
        fileName: String,
        altText: String = "",
        caption: InlineText? = nil,
        credit: String? = nil,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        capture: CaptureMetadata? = nil,
        provenance: ImageProvenance = .init()
    ) {
        self.id = id
        self.fileName = fileName
        self.altText = altText
        self.caption = caption
        self.credit = credit
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.capture = capture
        self.provenance = provenance
    }

    public var needsAltText: Bool {
        altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
