import ImageKit
import PostKit
import SwiftUI

/// Adds dropped photographs to an open post.
///
/// Reading a file - decode, resize, EXIF - is done off the main actor. Seventy frames at
/// 2048px is several seconds of work, and the editor has to stay live while it happens, so
/// only the finished records come back to be appended.
@Observable
@MainActor
final class ImageDropper {
    /// How many photographs are still being read, so the editor can say what is happening
    /// and it is obvious whether a drop arrived whole.
    private(set) var reading = 0
    /// Files that could not be read, by name, so it is obvious which ones to look at.
    private(set) var refused: [String] = []

    func add(_ urls: [URL], to document: PostDocument) async {
        guard !urls.isEmpty else { return }
        reading += urls.count
        defer { reading -= urls.count }

        let batch = await Task.detached(priority: .userInitiated) { Self.read(urls) }.value
        refused = batch.refused
        guard !batch.images.isEmpty else { return }

        // Built as one value and assigned once. The editor registers an undo action on every
        // change to `post`, so appending in place would make a drop of seventy photographs
        // seventy separate undo steps.
        var post = document.post
        for image in batch.images {
            post.assets[image.asset.id] = image.asset
            document.images[image.asset.id] = .data(image.data)
        }

        // The dropped photographs merge into the run of images already at the end of the
        // post, so several drops build one sequence in the order they were shot. Earlier
        // drafts had each drop simply appended, which meant grabbing photographs from the
        // Finder in a few goes left the post in the order they were grabbed.
        //
        // The merge stops at the first block that is not an image. Once there is a paragraph
        // or a heading between photographs, they have been placed deliberately, and a later
        // drop has no business moving them.
        var start = post.blocks.count
        while start > 0, case .image = post.blocks[start - 1].kind { start -= 1 }

        let existing = post.blocks[start...]
        let added = batch.images.map { Block(kind: .image(imageID: $0.asset.id, layout: .full)) }
        // Existing blocks come first, so a photograph already in the post keeps its place
        // against a new one sharing its capture second.
        let merged = ImageImport.inCaptureOrder(Array(existing) + added) { block in
            guard case let .image(imageID, _) = block.kind else { return nil }
            return post.assets[imageID]?.capture?.captureDate
        }
        post.blocks.replaceSubrange(start..., with: merged)

        document.post = post
    }

    private struct Batch: Sendable {
        var images: [ImportedImage]
        var refused: [String]
    }

    // nonisolated so the detached task can call it: the class is @MainActor, and nested
    // members inherit that isolation unless they opt out.
    private nonisolated static func read(_ urls: [URL]) -> Batch {
        var images: [ImportedImage] = []
        var refused: [String] = []

        for url in urls {
            // A dropped URL points outside the app's container. On iOS reading it needs the
            // security scope opened first; on macOS the call is harmless and returns false.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                images.append(try ImageImport.make(
                    from: data,
                    originalFileName: url.lastPathComponent,
                    bookmarkData: ImageImport.bookmark(for: url)
                ))
            } catch {
                refused.append(url.lastPathComponent)
            }
        }

        // Left in the order the Finder handed over. Ordering happens at the merge, where the
        // photographs already in the post can be taken into account too.
        return Batch(images: images, refused: refused)
    }
}
