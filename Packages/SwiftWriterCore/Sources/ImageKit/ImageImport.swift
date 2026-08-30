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
        bookmarkData: Data? = nil,
        settings: DerivativeSettings = .default
    ) throws -> ImportedImage {
        let id = ImageID.makeUnique()
        let derivative = try WebDerivative.make(from: data, settings: settings)

        var asset = ImageAsset(
            id: id,
            fileName: "\(id.rawValue).\(derivative.fileExtension)",
            pixelWidth: derivative.pixelWidth,
            pixelHeight: derivative.pixelHeight,
            provenance: ImageProvenance(
                originalFileName: originalFileName,
                bookmarkData: bookmarkData
            )
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

    /// A bookmark back to the full-resolution original.
    ///
    /// The package holds a 2048px derivative, so this is the only trail back to the file the
    /// camera wrote - and a bookmark, unlike a path, survives the original being moved or
    /// renamed. It is per-machine: it will not resolve on the iPad, and it goes stale when a
    /// cloud folder re-syncs, which is why `originalFileName` is kept beside it.
    ///
    /// Taken at drop time because that is when the security scope is open.
    public static func bookmark(for url: URL) -> Data? {
        #if os(macOS)
        // A security-scoped bookmark is only issued to a sandboxed app. This one is not
        // sandboxed, so an ordinary bookmark is what comes back, and it resolves the same.
        if let scoped = try? url.bookmarkData(options: .withSecurityScope) { return scoped }
        #endif
        return try? url.bookmarkData()
    }

    /// Orders photographs the way they were taken.
    ///
    /// Stable on purpose. A burst shares a capture time to the whole second, and two bodies
    /// drift apart, so equal timestamps keep the order they arrived in. Anything with no
    /// capture date sorts last rather than first: an undated file is a screenshot or an
    /// export, not the start of the day.
    ///
    /// Generic over what is being ordered because the same rule has to hold in two places -
    /// a freshly read batch, and the photographs already sitting at the end of a post that
    /// the batch is merged into.
    public static func inCaptureOrder<Item>(
        _ items: [Item],
        capturedAt: (Item) -> Date?
    ) -> [Item] {
        items.enumerated().sorted { lhs, rhs in
            switch (capturedAt(lhs.element), capturedAt(rhs.element)) {
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

    public static func inCaptureOrder(_ images: [ImportedImage]) -> [ImportedImage] {
        inCaptureOrder(images) { $0.asset.capture?.captureDate }
    }
}
