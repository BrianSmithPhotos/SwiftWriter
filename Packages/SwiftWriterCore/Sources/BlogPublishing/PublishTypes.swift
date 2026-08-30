import Foundation
import PostKit

/// One image on its way to a provider.
///
/// Carries the bytes rather than a URL: the pixels live inside the package, and the
/// provider should not have to know how a `.swiftpost` is laid out.
public struct MediaUpload: Sendable, Equatable {
    public var imageID: ImageID
    public var fileName: String
    public var mimeType: String
    public var data: Data
    public var altText: String?
    public var caption: String?

    public init(
        imageID: ImageID,
        fileName: String,
        mimeType: String,
        data: Data,
        altText: String? = nil,
        caption: String? = nil
    ) {
        self.imageID = imageID
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
        self.altText = altText
        self.caption = caption
    }
}

/// Where an uploaded image ended up. The body cannot be rendered until every image the
/// post references has one of these, because the markup needs the remote URL.
public struct RemoteMedia: Sendable, Equatable {
    public var imageID: ImageID
    public var remoteID: String
    public var url: URL

    public init(imageID: ImageID, remoteID: String, url: URL) {
        self.imageID = imageID
        self.remoteID = remoteID
        self.url = url
    }
}

/// A complete request to put a post on a site.
public struct PublishRequest: Sendable {
    public var post: Post
    public var status: PublishStatus
    /// When the post should go live. Only meaningful when `status` is `.scheduled`.
    public var scheduledFor: Date?
    /// The date the post should carry once it is live, when that is not the moment it
    /// was released. Set to the newest capture date to file a catch-up post under the
    /// day it was photographed. Only meaningful when `status` is `.published`.
    public var displayDate: Date?
    /// Every image the post references, already uploaded.
    public var media: [ImageID: RemoteMedia]
    /// Set when revising a post the provider already holds.
    public var remotePostID: String?

    public init(
        post: Post,
        status: PublishStatus = .draft,
        scheduledFor: Date? = nil,
        displayDate: Date? = nil,
        media: [ImageID: RemoteMedia] = [:],
        remotePostID: String? = nil
    ) {
        self.post = post
        self.status = status
        self.scheduledFor = scheduledFor
        self.displayDate = displayDate
        self.media = media
        self.remotePostID = remotePostID
    }
}

/// What the provider did.
public struct PublishResult: Sendable, Equatable {
    public var remotePostID: String
    public var remoteURL: URL?
    public var status: PublishStatus
    public var publishedAt: Date?

    public init(
        remotePostID: String,
        remoteURL: URL? = nil,
        status: PublishStatus,
        publishedAt: Date? = nil
    ) {
        self.remotePostID = remotePostID
        self.remoteURL = remoteURL
        self.status = status
        self.publishedAt = publishedAt
    }
}

public enum PublishError: Error, Equatable {
    /// The request asks for something this provider does not do.
    case unsupported(ProviderCapabilities)
    /// A block references an image that was never uploaded, so the body cannot be rendered.
    case missingMedia(ImageID)
    /// `status` is `.scheduled` but no date was given, or the date is in the past.
    case invalidSchedule
    /// A display date was asked for on a post that is not live, where it would silently
    /// become the release date instead.
    case backdateNeedsPublished
    case notAuthenticated
    /// The provider says the thing being asked for is not there. Kept apart from
    /// `providerRefused` only so a caller can recognise it without reading the message.
    case notFound(String)
    /// The post an update names is no longer on the blog - trashed and emptied, or deleted.
    /// The record that named it is therefore stale in every part, media included.
    case remotePostMissing(String)
    /// The provider answered, but not with something we can use.
    case providerRefused(String)
}

/// One wording for both callers. The command line prints `"\(error)"` and the app shows
/// `localizedDescription`, and a publish failure the writer cannot act on is no use to
/// either of them.
extension PublishError: LocalizedError, CustomStringConvertible {
    public var description: String {
        switch self {
        case let .unsupported(what):
            "This blog cannot publish \(what.names.formatted(.list(type: .and)))."
        case let .missingMedia(imageID):
            "Image \(imageID.rawValue) has no sidecar, so the post cannot be rendered."
        case .invalidSchedule:
            "Scheduling needs a date in the future."
        case .backdateNeedsPublished:
            "Only a post that is already live can be given an earlier date."
        case .notAuthenticated:
            "Not signed in to this blog."
        case let .notFound(reason):
            reason
        case let .remotePostMissing(remoteID):
            "Post \(remoteID) is no longer on the blog."
        case let .providerRefused(reason):
            reason
        }
    }

    public var errorDescription: String? { description }
}
