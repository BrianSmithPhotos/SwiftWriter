import Foundation
import PostKit

/// One image file turned into what a package needs: the record, and the bytes beside it.
public struct ImportedImage: Sendable, Equatable {
    /// The record, with a fresh id and everything the file itself could say.
    public var asset: ImageAsset
    /// The web derivative, ready to be held as `ImageSource.data`.
    public var data: Data

    public init(asset: ImageAsset, data: Data) {
        self.asset = asset
        self.data = data
    }
}

/// Turns photographs into post images.
///
/// This is the same three steps the corpus importer does - derivative, metadata, sidecar
/// fields - kept here so a photograph dropped onto an open post is indistinguishable from
/// one that came in with the WordPress export, and so the rules stay testable without a UI.
public enum ImageImport {
    /// Reads one image file's bytes into an asset and its web derivative.
    ///
    /// Alt text is deliberately left empty. An empty alt is a defect the editor shows, and
    /// inventing one here would hide the photographs that still need describing.
    public static func make(
        from data: Data,
        originalFileName: String? = nil,
        settings: DerivativeSettings = .default
    ) throws -> ImportedImage {
        let id = ImageID.makeUnique()
        let derivative = try WebDerivative.make(from: data, settings: settings)

        var asset = ImageAsset(
            id: id,
            fileName: "\(id.rawValue).\(derivative.fileExtension)",
            pixelWidth: derivative.pixelWidth,
            pixelHeight: derivative.pixelHeight,
            provenance: ImageProvenance(originalFileName: originalFileName)
        )

        // Metadata is read from the original, not the derivative: resizing drops most of it.
        if let facts = try? ImageMetadataReader.read(data: data) {
            asset.capture = facts.capture
            asset.credit = facts.credit
            // The photographer's IPTC caption is a better start than an empty field.
            if let embedded = facts.embeddedCaption, !embedded.isEmpty {
                asset.caption = .plain(embedded)
            }
        }

        return ImportedImage(asset: asset, data: derivative.data)
    }

    /// Orders photographs the way they were taken.
    ///
    /// Stable on purpose. A burst shares a capture time to the whole second, and two bodies
    /// drift apart, so equal timestamps keep the order they arrived in - which is the order
    /// the Finder handed over, usually filename order. Anything with no capture date sorts
    /// last rather than first: an undated file is a screenshot or an export, not the start
    /// of the day.
    public static func inCaptureOrder(_ images: [ImportedImage]) -> [ImportedImage] {
        images.enumerated().sorted { lhs, rhs in
            switch (lhs.element.asset.capture?.captureDate, rhs.element.asset.capture?.captureDate) {
            case let (left?, right?):
                left == right ? lhs.offset < rhs.offset : left < right
            case (_?, nil):
                true
            case (nil, _?):
                false
            case (nil, nil):
                lhs.offset < rhs.offset
            }
        }
        .map(\.element)
    }
}
