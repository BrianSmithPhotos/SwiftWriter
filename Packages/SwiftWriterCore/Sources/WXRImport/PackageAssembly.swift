import Foundation
import ImageKit
import PostKit

/// Turns an imported post and the pixels of its photographs into a package ready to write.
///
/// Shared by the whole-export importer and by pulling a single post off the blog. Every rule
/// here is one that is quiet when it is wrong: which images may be claimed as already
/// uploaded, when the content hash may be taken, and what happens to a photograph that could
/// not be downloaded. Two copies would be two sets of answers.
public enum PackageAssembly {
    public struct Assembled: Sendable {
        public var snapshot: PostSnapshot
        public var report: PostImportReport
        /// Images kept exactly as the blog serves them, against those rebuilt smaller.
        public var passedThrough = 0
        public var resized = 0
    }

    /// - Parameters:
    ///   - bytes: the pixels for each image. Anything missing was not downloadable, and is
    ///     pruned from the post rather than left as a hole in the package.
    ///   - fromOriginals: images read from camera originals rather than from the blog.
    ///   - settings: how the web derivative is built.
    public static func assemble(
        _ imported: ImportedPost,
        bytes: [ImageID: Data],
        fromOriginals: Set<ImageID> = [],
        settings: DerivativeSettings = .default
    ) throws -> Assembled {
        var imported = imported
        var result = Assembled(snapshot: PostSnapshot(post: imported.post), report: imported.report)

        var sources: [ImageID: ImageSource] = [:]
        // What the blog already holds, byte for byte, so the first publish updates the
        // existing attachment instead of uploading a second copy of a live photograph.
        var uploaded: [ImageID: UploadedMedia] = [:]

        for image in imported.images {
            guard var asset = imported.post.assets[image.id] else { continue }
            guard let data = bytes[image.id] else {
                imported.post.assets[image.id] = nil
                continue
            }

            let derivative = try WebDerivative.make(from: data, settings: settings)
            derivative.passedThrough ? (result.passedThrough += 1) : (result.resized += 1)

            asset.fileName = "\(image.id.rawValue).\(derivative.fileExtension)"
            asset.pixelWidth = derivative.pixelWidth
            asset.pixelHeight = derivative.pixelHeight

            if let facts = try? ImageMetadataReader.read(data: data) {
                asset.capture = facts.capture
                asset.credit = facts.credit
                // The photographer's IPTC caption is a better starting point than nothing, but
                // it never overrides a caption written into the post.
                if asset.caption == nil, let embedded = facts.embeddedCaption {
                    asset.caption = InlineText.plain(embedded)
                }
            }

            imported.post.assets[image.id] = asset
            sources[image.id] = .data(derivative.data)

            // Only an image taken from the blog and kept byte for byte can be claimed as held.
            // A derivative built from a camera original is a better picture than the one that
            // is live, and recording it here would claim the blog already had it - so the
            // larger image would never go up. Left out of the map, it uploads on the next
            // publish.
            //
            // The alt text and caption recorded are the blog's own, not the asset's: the asset
            // may since have taken an IPTC caption the attachment has never been told about,
            // and that difference is exactly what should be sent on the next publish.
            if !fromOriginals.contains(image.id), derivative.passedThrough,
               let remoteID = image.wordPressID, let sourceURL = image.sourceURL {
                uploaded[image.id] = UploadedMedia(
                    remoteID: remoteID,
                    url: sourceURL,
                    contentHash: UploadedMedia.hash(of: derivative.data),
                    altText: image.altText.isEmpty ? nil : image.altText,
                    caption: image.caption?.html
                )
            }
        }

        // Anything that failed to download is pruned, so the package never references an
        // asset it does not hold.
        let held = Set(imported.post.assets.keys)
        imported.post.blocks = imported.post.blocks.compactMap { pruned($0, keeping: held) }
        if let hero = imported.post.heroImageID, !held.contains(hero) {
            imported.post.heroImageID = nil
        }
        result.report.imageCount = imported.post.assets.count
        result.report.imagesWithoutAltText = imported.post.imagesNeedingAltText.count

        // The hash has to be taken here, not in the importer. Downloading each image rewrites
        // its asset - real file extension, pixel size, EXIF, an IPTC caption - and all of that
        // is inside the hash, so a hash taken before the fetch could never match the package
        // that ends up on disk, and every imported post would open looking edited.
        var record = imported.publishRecord
        record.contentHash = try? imported.post.contentHash()
        record.media = uploaded.filter { imported.post.assets[$0.key] != nil }

        result.snapshot = PostSnapshot(
            post: imported.post, publishRecords: [record], images: sources
        )
        return result
    }

    /// Drops references to images the package does not hold.
    static func pruned(_ block: Block, keeping held: Set<ImageID>) -> Block? {
        switch block.kind {
        case let .image(imageID, _):
            return held.contains(imageID) ? block : nil
        case let .gallery(imageIDs, columns):
            let kept = imageIDs.filter(held.contains)
            guard !kept.isEmpty else { return nil }
            return Block(id: block.id, kind: .gallery(imageIDs: kept, columns: columns))
        default:
            return block
        }
    }
}
