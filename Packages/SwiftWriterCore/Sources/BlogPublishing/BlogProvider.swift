import Foundation
import PostKit

/// One blog you can publish to.
///
/// Deliberately small. Everything a provider has in common lives here; everything it does
/// not do is declared in `capabilities` rather than by throwing at the last moment, so the
/// editor can grey a control out instead of failing after an upload has already happened.
public protocol BlogProvider: Sendable {
    /// Stable key written into `publishing.json`, for example `wordpress`.
    static var providerID: String { get }
    /// Which site within the provider. A WordPress.com blog id, a Ghost host, a repo URL.
    var siteID: String { get }
    var capabilities: ProviderCapabilities { get }

    func authenticate() async throws
    func uploadMedia(_ upload: MediaUpload) async throws -> RemoteMedia
    /// Revises the alt text and caption of media the provider already holds.
    ///
    /// Separate from `uploadMedia` because writing alt text for a post that is already
    /// published must not send the photographs again.
    func updateMediaDetails(remoteID: String, altText: String?, caption: String?) async throws
    func createPost(_ request: PublishRequest) async throws -> PublishResult
    /// `request.remotePostID` identifies the post to revise.
    func updatePost(_ request: PublishRequest) async throws -> PublishResult
}

public extension BlogProvider {
    var providerID: String { Self.providerID }

    /// Nothing to do for a provider that keeps no metadata beside the image itself -
    /// a static site, where the alt text lives only in the markup.
    func updateMediaDetails(remoteID: String, altText: String?, caption: String?) async throws {}

    /// Validates the request against what this provider can do, then creates or revises.
    ///
    /// Routing on `remotePostID` here rather than in each provider is what keeps
    /// "publish" a single call at the call site, and keeps the create/update split from
    /// leaking into the editor.
    func publish(_ request: PublishRequest) async throws -> PublishResult {
        try capabilities.check(request)
        if request.remotePostID == nil {
            return try await createPost(request)
        }
        return try await updatePost(request)
    }
}

public extension ProviderCapabilities {
    /// Throws if the request asks for something this provider does not support.
    ///
    /// Pure, and checked before any network call, so a post is never half-published
    /// because the provider turned out not to schedule.
    func check(_ request: PublishRequest) throws {
        if request.remotePostID != nil, !contains(.updateExisting) {
            throw PublishError.unsupported(.updateExisting)
        }
        if request.status == .scheduled {
            guard contains(.schedule) else { throw PublishError.unsupported(.schedule) }
            guard let date = request.scheduledFor, date > .now else {
                throw PublishError.invalidSchedule
            }
        }
        if request.displayDate != nil {
            guard contains(.backdate) else { throw PublishError.unsupported(.backdate) }
            // Dating a draft or a scheduled post achieves nothing: WordPress has one date
            // field, and for those two states it already means the release date.
            guard request.status == .published else { throw PublishError.backdateNeedsPublished }
        }
        if !request.post.categories.isEmpty, !contains(.categories) {
            throw PublishError.unsupported(.categories)
        }
        if !request.post.tags.isEmpty, !contains(.tags) {
            throw PublishError.unsupported(.tags)
        }
        if request.post.slug != nil, !contains(.customSlug) {
            throw PublishError.unsupported(.customSlug)
        }
        if !request.post.summary.isEmpty, !contains(.summary) {
            throw PublishError.unsupported(.summary)
        }
        if request.post.heroImageID != nil, !contains(.heroImage) {
            throw PublishError.unsupported(.heroImage)
        }
        // Every image in the body needs a remote URL before the markup can name it.
        for imageID in request.post.referencedImageIDs where request.media[imageID] == nil {
            throw PublishError.missingMedia(imageID)
        }
    }
}
