import Foundation
import PostKit

/// What one post looked like on the way in. Collected so the import can report on the
/// corpus as a whole rather than failing silently.
public struct PostImportReport: Sendable, Equatable {
    public var title: String = ""
    public var status: String = ""
    public var imageCount: Int = 0
    public var imagesWithoutAltText: Int = 0
    public var imagesWithCaptions: Int = 0
    public var hasHeroImage = false
    public var hasSummary = false
    public var unsupportedBlocks: [String] = []
    public var droppedInlineTags: [String] = []
    public var unresolvedImages: [String] = []
}

/// A post read out of the export, with its images still to fetch.
public struct ImportedPost: Sendable {
    public var post: Post
    /// Every image the post needs, hero first, in reading order.
    public var images: [ParsedImage]
    public var publishRecord: PublishRecord
    public var report: PostImportReport
}

public struct ImportOptions: Sendable {
    /// Only posts on or after this date are imported.
    public var since: Date?
    /// Statuses to accept. `trash` is excluded by default; the export holds trashed
    /// duplicates of posts that were later republished.
    public var statuses: Set<String>
    public var siteID: String

    public init(
        since: Date? = nil,
        statuses: Set<String> = ["publish", "future", "draft", "pending", "private"],
        siteID: String = ""
    ) {
        self.since = since
        self.statuses = statuses
        self.siteID = siteID
    }
}

public enum PostImporter {
    public static func selectPosts(from document: WXRDocument, options: ImportOptions) -> [WXRItem] {
        document.posts
            .filter { options.statuses.contains($0.status) }
            .filter { item in
                guard let since = options.since else { return true }
                guard let date = item.postDate else { return false }
                return date >= since
            }
            .sorted { ($0.postDate ?? .distantPast) < ($1.postDate ?? .distantPast) }
    }

    public static func makePost(
        from item: WXRItem,
        attachments: [String: WXRItem],
        options: ImportOptions
    ) -> ImportedPost {
        let parsed = GutenbergParser.parse(item.content)
        var images = parsed.images
        var report = PostImportReport(title: item.title, status: item.status)
        report.unsupportedBlocks = parsed.unsupportedBlocks
        report.droppedInlineTags = parsed.droppedInlineTags.sorted()

        // The hero image is postmeta, not part of the body, so it is resolved separately
        // through the attachment items the export carries.
        var heroImageID: ImageID?
        if let thumbnailID = item.meta["_thumbnail_id"] {
            if let attachment = attachments[thumbnailID],
               let urlString = attachment.attachmentURL,
               let url = URL(string: urlString) {
                let hero = ParsedImage(
                    id: .makeUnique(),
                    wordPressID: thumbnailID,
                    sourceURL: url,
                    altText: attachment.meta["_wp_attachment_image_alt"] ?? "",
                    caption: attachment.excerpt.nilIfEmpty.map { HTMLInline.inlineText(from: $0).text }
                )
                images.insert(hero, at: 0)
                heroImageID = hero.id
                report.hasHeroImage = true
            } else {
                report.unresolvedImages.append("hero \(thumbnailID)")
            }
        }

        // The body markup's src is what the theme requested (often ?w=1200) and can even
        // name a file that no longer exists. The attachment record is authoritative, so
        // prefer it, and take its alt text and caption when the body supplied none.
        images = images.map { image in
            guard let wordPressID = image.wordPressID,
                  let attachment = attachments[wordPressID] else { return image }
            var resolved = image
            if let urlString = attachment.attachmentURL, let url = URL(string: urlString) {
                resolved.sourceURL = url
            }
            if resolved.altText.isEmpty {
                resolved.altText = attachment.meta["_wp_attachment_image_alt"] ?? ""
            }
            if resolved.caption == nil {
                resolved.caption = attachment.excerpt.nilIfEmpty.map {
                    HTMLInline.inlineText(from: $0).text
                }
            }
            return resolved
        }

        // Images referenced by the body but with no usable URL cannot be fetched.
        let usable = images.filter { $0.sourceURL != nil }
        for missing in images where missing.sourceURL == nil {
            report.unresolvedImages.append(missing.wordPressID ?? "unknown")
        }
        let usableIDs = Set(usable.map(\.id))

        var post = Post(
            title: item.title,
            slug: item.slug.nilIfEmpty,
            summary: HTMLInline.inlineText(from: item.excerpt).text.plainText
                .trimmingCharacters(in: .whitespacesAndNewlines),
            heroImageID: heroImageID.flatMap { usableIDs.contains($0) ? $0 : nil },
            categories: item.categories,
            tags: item.tags,
            blocks: parsed.blocks.compactMap { pruning($0, keeping: usableIDs) },
            createdAt: item.postDate ?? .now,
            updatedAt: item.postDate ?? .now
        )

        for image in usable {
            let fileName = image.sourceURL?.lastPathComponent
            post.assets[image.id] = ImageAsset(
                id: image.id,
                // Corrected once the image is fetched and its real type is known.
                fileName: "\(image.id.rawValue).jpg",
                altText: image.altText,
                caption: image.caption,
                provenance: ImageProvenance(
                    originalFileName: fileName,
                    flickrPhotoID: fileName.flatMap(flickrPhotoID(inFileName:)),
                    sourceURL: image.sourceURL
                )
            )
        }

        report.imageCount = usable.count
        report.imagesWithoutAltText = usable.count { $0.altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        report.imagesWithCaptions = usable.count { $0.caption != nil }
        report.hasSummary = !post.summary.isEmpty

        return ImportedPost(
            post: post,
            images: usable,
            publishRecord: makeRecord(from: item, options: options, post: post),
            report: report
        )
    }

    /// Drops references to images that could not be resolved, so the package never points
    /// at an asset it does not hold.
    private static func pruning(_ block: Block, keeping usable: Set<ImageID>) -> Block? {
        switch block.kind {
        case let .image(imageID, _):
            return usable.contains(imageID) ? block : nil
        case let .gallery(imageIDs, columns):
            let kept = imageIDs.filter(usable.contains)
            guard !kept.isEmpty else { return nil }
            return Block(id: block.id, kind: .gallery(imageIDs: kept, columns: columns))
        default:
            return block
        }
    }

    private static func makeRecord(
        from item: WXRItem,
        options: ImportOptions,
        post: Post
    ) -> PublishRecord {
        let status: PublishStatus = switch item.status {
        case "publish", "private": .published
        case "future": .scheduled
        default: .draft
        }
        return PublishRecord(
            providerID: "wordpress",
            siteID: options.siteID,
            // Kept so an imported post can be updated in place rather than published anew.
            remotePostID: item.postID,
            remoteURL: URL(string: item.link),
            status: status,
            scheduledFor: status == .scheduled ? item.postDate : nil,
            uploadedAt: item.postDate,
            publishedAt: status == .published ? item.postDate : nil,
            lastSyncedAt: .now,
            contentHash: try? post.contentHash()
        )
    }

    /// WordPress filenames on this blog carry the Flickr photo id the image came from,
    /// as in `…-dscf4259_54928471321_o-large.jpeg`. It is a more durable handle back to the
    /// original than any local path.
    public static func flickrPhotoID(inFileName fileName: String) -> String? {
        guard let match = fileName.firstMatch(of: /_(\d{10,})_o/) else { return nil }
        return String(match.1)
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
