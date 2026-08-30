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
    /// True while a drop is being read, so the editor can say something is happening.
    private(set) var isImporting = false
    /// Files that could not be read, by name, so it is obvious which ones to look at.
    private(set) var refused: [String] = []

    func add(_ urls: [URL], to document: PostDocument) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }

        let batch = await Task.detached(priority: .userInitiated) { Self.read(urls) }.value
        refused = batch.refused
        guard !batch.images.isEmpty else { return }

        // Built as one value and assigned once. The editor registers an undo action on every
        // change to `post`, so appending in place would make a drop of seventy photographs
        // seventy separate undo steps.
        var post = document.post
        for image in batch.images {
            post.assets[image.asset.id] = image.asset
            post.blocks.append(Block(kind: .image(imageID: image.asset.id, layout: .full)))
            document.images[image.asset.id] = .data(image.data)
        }
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
                images.append(
                    try ImageImport.make(from: data, originalFileName: url.lastPathComponent)
                )
            } catch {
                refused.append(url.lastPathComponent)
            }
        }

        // Only this batch is sorted, and it is appended whole. A second drop lands after the
        // first rather than being merged into it - dropping more photographs should never
        // rearrange the post that has already been written.
        return Batch(images: ImageImport.inCaptureOrder(images), refused: refused)
    }
}
