import CryptoKit
import Foundation

/// The content of a blog post: everything a reader would see, and nothing about publishing.
public struct Post: Codable, Sendable, Equatable {
    /// Bumped when the on-disk shape changes in a way a reader has to know about.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var id: UUID
    public var title: String
    /// The URL slug. Nil means "let the provider derive one from the title".
    public var slug: String?
    /// Short standfirst. Providers map this onto excerpt, meta description, or card text.
    public var summary: String
    public var heroImageID: ImageID?
    public var categories: [String]
    public var tags: [String]
    public var blocks: [Block]
    /// Every image the package holds, keyed by id.
    ///
    /// Not part of `post.json`: each asset is written to its own `Images/<id>.json` sidecar
    /// so that retitling one photograph's alt text rewrites one small file, and so the
    /// package stays browsable in Finder. The default value is what lets the synthesised
    /// `Codable` skip the property.
    public var assets: [ImageID: ImageAsset] = [:]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        formatVersion: Int = Post.currentFormatVersion,
        id: UUID = UUID(),
        title: String = "",
        slug: String? = nil,
        summary: String = "",
        heroImageID: ImageID? = nil,
        categories: [String] = [],
        tags: [String] = [],
        blocks: [Block] = [],
        assets: [ImageID: ImageAsset] = [:],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.title = title
        self.slug = slug
        self.summary = summary
        self.heroImageID = heroImageID
        self.categories = categories
        self.tags = tags
        self.blocks = blocks
        self.assets = assets
        self.createdAt = createdAt.truncatedToSecond
        self.updatedAt = updatedAt.truncatedToSecond
    }

    /// Marks the post as edited now, at the precision the format stores.
    public mutating func touch() {
        updatedAt = Date.now.truncatedToSecond
    }

    /// Images referenced by the body, in reading order, plus the hero image first.
    public var referencedImageIDs: [ImageID] {
        var seen = Set<ImageID>()
        var ordered: [ImageID] = []
        for id in ([heroImageID].compactMap { $0 } + blocks.flatMap(\.imageIDs)) where seen.insert(id).inserted {
            ordered.append(id)
        }
        return ordered
    }

    /// When the photographs in this post were taken - the newest of them.
    ///
    /// This is the date a post is backdated to once it has gone live, so the archive reads
    /// as a record of when the walk happened rather than when it was written up. Defined as
    /// the newest capture rather than the last image in reading order: the two agree on all
    /// 33 posts in the corpus, and the newest one does not change when blocks are reordered.
    public var newestCaptureDate: Date? {
        referencedImageIDs.compactMap { assets[$0]?.capture?.captureDate }.max()
    }

    /// Assets held in the package that nothing points at any more.
    public var orphanedImageIDs: [ImageID] {
        let referenced = Set(referencedImageIDs)
        return assets.keys.filter { !referenced.contains($0) }.sorted { $0.rawValue < $1.rawValue }
    }

    /// Referenced images that are missing alt text. The editor surfaces this rather than
    /// letting it slip through silently, which is how a blog ends up with 975 bare images.
    public var imagesNeedingAltText: [ImageID] {
        referencedImageIDs.filter { assets[$0]?.needsAltText ?? false }
    }

    /// `assets` is deliberately absent: it lives in the `Images/` sidecars.
    private enum CodingKeys: String, CodingKey {
        case formatVersion, id, title, slug, summary, heroImageID
        case categories, tags, blocks, createdAt, updatedAt
    }

    /// A hash of the content as a provider would see it. Recorded at publish time so the
    /// app can tell "published" from "published, then edited".
    public func contentHash() throws -> String {
        var hashable = self
        // Timestamps are bookkeeping, not content: editing and saving without changing a
        // word must not make a published post look stale.
        hashable.createdAt = .distantPast
        hashable.updatedAt = .distantPast

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        var data = try encoder.encode(hashable)
        // Alt text and captions are content, so the assets go into the hash too - sorted
        // into an array because dictionary ordering is not stable.
        data += try encoder.encode(assets.values.sorted { $0.id.rawValue < $1.id.rawValue })

        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
