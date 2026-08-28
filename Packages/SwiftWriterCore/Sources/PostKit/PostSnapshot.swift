import Foundation

/// Where the bytes for one image come from when a package is written.
public enum ImageSource: Sendable, Equatable {
    /// New or edited pixels, held in memory until the next save.
    case data(Data)
    /// Already on disk under `Images/`. The existing file wrapper is reused, so saving a
    /// text edit to a post with forty photographs does not rewrite forty photographs.
    case existing(fileName: String)
}

/// The `Sendable` value that crosses between the main actor and disk.
///
/// `WritableDocument.snapshot(contentType:)` builds one on the main actor; `DocumentWriter`
/// then writes it off the main actor. It deliberately does not carry image bytes for images
/// that are already saved - see `ImageSource`.
public struct PostSnapshot: Sendable, Equatable {
    public var post: Post
    public var publishRecords: [PublishRecord]
    public var images: [ImageID: ImageSource]

    public init(
        post: Post,
        publishRecords: [PublishRecord] = [],
        images: [ImageID: ImageSource] = [:]
    ) {
        self.post = post
        self.publishRecords = publishRecords
        self.images = images
    }
}
