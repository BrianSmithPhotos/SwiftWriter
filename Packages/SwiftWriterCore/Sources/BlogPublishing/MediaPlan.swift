import Foundation
import PostKit

/// What to do about one image that a post is about to be published with.
///
/// Pure, and kept out of the tool that drives it, because this is the decision that stops a
/// republish from filling the media library with duplicates - and getting it wrong is not
/// visible until a blog has four copies of every photograph.
public enum MediaAction: Equatable, Sendable {
    /// Not held yet, or the pixels have changed. Send the bytes.
    case upload
    /// Held, and nothing about it has changed. Send nothing.
    case reuse(UploadedMedia)
    /// Held, but the alt text or caption has been edited since. Send only those.
    case describe(UploadedMedia)

    /// - Parameter held: what the provider was last known to hold for this image.
    /// - Parameter contentHash: the hash of the bytes about to be published.
    public static func decide(
        held: UploadedMedia?,
        contentHash: String,
        altText: String?,
        caption: String?
    ) -> MediaAction {
        // A changed hash means a different photograph in the same slot, so the old
        // attachment is not the right one to describe - it needs a new upload.
        guard let held, held.contentHash == contentHash else { return .upload }
        if held.altText == altText, held.caption == caption { return .reuse(held) }
        return .describe(held)
    }
}
