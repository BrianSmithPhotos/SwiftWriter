import Foundation
import PostKit

/// One publish: from a post and its photographs to the record of what the blog now holds.
///
/// This lives here rather than in the tool that drives it because the app publishes exactly
/// the way the command line does. Two copies would be two answers to "does this photograph
/// need sending again", and the wrong answer is invisible until the blog holds four copies
/// of everything.
public enum PublishRun {
    /// The pixels for one image. The command line reads them out of the package on disk; the
    /// app usually has them in memory already.
    public typealias Bytes = (ImageID) throws -> Data

    /// What a publish would do, worked out before anything is sent, so a dry run reports
    /// exactly what the real thing goes on to do.
    public struct Plan {
        public struct Item {
            public let imageID: ImageID
            public let asset: ImageAsset
            public let hash: String
            public let altText: String?
            public let caption: String?
            public let action: MediaAction
        }

        public let items: [Item]
        /// Images with no alt text. Reported, never blocking: it is the writer's call.
        public let missingAltText: Int

        public var toUpload: Int { items.count { $0.action == .upload } }
        public var unchanged: Int {
            items.count { if case .reuse = $0.action { true } else { false } }
        }
        public var toDescribe: Int {
            items.count { if case .describe = $0.action { true } else { false } }
        }
    }

    /// The steps worth showing someone while a publish runs.
    public enum Step: Sendable {
        case uploaded(fileName: String, remoteID: String)
        case described(fileName: String, remoteID: String)
        case finished(PublishResult)
    }

    /// Decides what each photograph needs, sending nothing.
    ///
    /// - Parameter held: the record of what this site was last known to hold.
    public static func plan(post: Post, held: PublishRecord?, bytes: Bytes) throws -> Plan {
        var items: [Plan.Item] = []
        for imageID in post.referencedImageIDs {
            guard let asset = post.assets[imageID] else {
                throw PublishError.missingMedia(imageID)
            }
            let hash = UploadedMedia.hash(of: try bytes(imageID))
            let altText = asset.altText.isEmpty ? nil : asset.altText
            let caption = asset.caption?.html
            items.append(Plan.Item(
                imageID: imageID,
                asset: asset,
                hash: hash,
                altText: altText,
                caption: caption,
                action: MediaAction.decide(
                    held: held?.media[imageID], contentHash: hash,
                    altText: altText, caption: caption
                )
            ))
        }
        return Plan(items: items, missingAltText: post.imagesNeedingAltText.count)
    }

    /// Sends the media the plan calls for, then the post, and returns the record to keep.
    ///
    /// Media goes first because the body cannot be rendered until every image has a remote
    /// URL. Nothing is written to disk here: the caller decides where the record belongs.
    public static func send(
        _ plan: Plan,
        post: Post,
        to provider: some BlogProvider,
        status: PublishStatus,
        scheduledFor: Date? = nil,
        displayDate: Date? = nil,
        remotePostID: String? = nil,
        bytes: Bytes,
        step: (Step) -> Void = { _ in }
    ) async throws -> PublishRecord {
        try await provider.authenticate()

        var media: [ImageID: RemoteMedia] = [:]
        var uploads: [ImageID: UploadedMedia] = [:]

        for item in plan.items {
            let held: UploadedMedia
            switch item.action {
            case let .reuse(known):
                held = known

            case let .describe(known):
                // Empty rather than nil, so clearing alt text in the editor clears it on the
                // blog instead of leaving the old wording in place.
                try await provider.updateMediaDetails(
                    remoteID: known.remoteID,
                    altText: item.altText ?? "", caption: item.caption ?? ""
                )
                held = known
                step(.described(fileName: item.asset.fileName, remoteID: known.remoteID))

            case .upload:
                let uploaded = try await provider.uploadMedia(MediaUpload(
                    imageID: item.imageID,
                    fileName: item.asset.fileName,
                    mimeType: mimeType(for: item.asset.fileName),
                    data: try bytes(item.imageID),
                    altText: item.altText,
                    caption: item.caption
                ))
                held = UploadedMedia(
                    remoteID: uploaded.remoteID, url: uploaded.url, contentHash: item.hash
                )
                step(.uploaded(fileName: item.asset.fileName, remoteID: uploaded.remoteID))
            }

            media[item.imageID] = RemoteMedia(
                imageID: item.imageID, remoteID: held.remoteID, url: held.url
            )
            uploads[item.imageID] = UploadedMedia(
                remoteID: held.remoteID, url: held.url, contentHash: item.hash,
                altText: item.altText, caption: item.caption
            )
        }

        let result = try await provider.publish(PublishRequest(
            post: post, status: status, scheduledFor: scheduledFor, displayDate: displayDate,
            media: media, remotePostID: remotePostID
        ))
        step(.finished(result))

        return PublishRecord.make(
            from: result, providerID: provider.providerID, siteID: provider.siteID,
            contentHash: try post.contentHash(), scheduledFor: scheduledFor, media: uploads
        )
    }

    /// What the provider is told the bytes are. Derived from the name the package stores,
    /// which is the only thing that reliably says what was written.
    public static func mimeType(for fileName: String) -> String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "png": "image/png"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "heic": "image/heic"
        default: "image/jpeg"
        }
    }
}
