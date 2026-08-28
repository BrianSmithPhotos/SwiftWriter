import Foundation
import os
import PostKit
import SwiftUI
import UniformTypeIdentifiers

/// The SwiftUI document adapter.
///
/// All of the format lives in `PostKit`, which is pure Foundation and fully tested from
/// the command line. This type does nothing but hold the editable state and hand the
/// codec to the reader and writer, so the app has no format logic of its own.
///
/// It is a class, not a struct, because `DocumentGroup` requires `Document: Observable`.
/// Temporary instrumentation for the Phase 3 save investigation. Read it with
/// `log stream --predicate 'subsystem == "photos.briansmith.SwiftWriter"'`.
let documentLog = Logger(subsystem: "photos.briansmith.SwiftWriter", category: "document")

@Observable
final class PostDocument: Document {
    var post: Post
    var publishRecords: [PublishRecord]

    /// Where each image currently lives. An image loaded from disk stays `.existing` until
    /// it is replaced, which is what lets the writer reuse its file wrapper instead of
    /// rewriting several hundred megabytes of photographs on every keystroke.
    var images: [ImageID: ImageSource]

    /// SwiftUI keeps this up to date as the document is saved or moved, so it is the only
    /// reliable way to find the package on disk - which is where images still marked
    /// `.existing` have to be read from.
    let configuration: URLDocumentConfiguration?

    init(
        post: Post = Post(title: ""),
        publishRecords: [PublishRecord] = [],
        images: [ImageID: ImageSource] = [:],
        configuration: URLDocumentConfiguration? = nil
    ) {
        self.post = post
        self.publishRecords = publishRecords
        self.images = images
        self.configuration = configuration
    }

    /// Where an image's bytes live right now: in memory if it was just added, otherwise
    /// in the saved package.
    @MainActor
    func location(of imageID: ImageID) -> ImageLocation? {
        switch images[imageID] {
        case .data(let data):
            .memory(data)
        case .existing(let fileName):
            configuration?.fileURL
                .map { .file($0.appending(path: PostPackage.imagesDirectoryName).appending(path: fileName)) }
        case nil:
            nil
        }
    }

    // MARK: - Reading

    static var readableContentTypes: [UTType] { [.swiftWriterPost] }

    func reader(configuration: sending ReadConfiguration) -> sending FileWrapperDocumentReader<PostSnapshot> {
        FileWrapperDocumentReader(configuration) { wrapper in
            try PostPackage.makeSnapshot(from: wrapper)
        }
    }

    @MainActor
    func apply(snapshot: sending PostSnapshot, previous: sending PostSnapshot?) async throws {
        documentLog.notice("apply: \(snapshot.post.title, privacy: .public), previous: \(previous == nil ? "none" : "some", privacy: .public), url: \(self.configuration?.fileURL?.lastPathComponent ?? "nil", privacy: .public)")
        post = snapshot.post
        publishRecords = snapshot.publishRecords
        images = snapshot.images
    }

    // MARK: - Writing

    static var writableContentTypes: [UTType] { [.swiftWriterPost] }

    func writer(configuration: sending WriteConfiguration) -> sending FileWrapperDocumentWriter<PostSnapshot> {
        documentLog.notice("writer requested for \(configuration.contentType.identifier, privacy: .public)")
        let urlConfiguration = self.configuration
        return FileWrapperDocumentWriter(configuration) { snapshot, previous in
            // Images read from disk stay `.existing` and carry no bytes, so writing needs
            // the package they came from. The framework supplies it when saving in place,
            // but not always - and without it every photograph would be missing, so the
            // codec refuses to write. Fall back to the package's own URL.
            var previous = previous
            if previous == nil, let url = await MainActor.run(body: { urlConfiguration?.fileURL }) {
                previous = try? FileWrapper(url: url)
            }
            let alt = snapshot.post.referencedImageIDs
                .compactMap { snapshot.post.assets[$0]?.altText }
                .count { !$0.isEmpty }
            documentLog.notice("writer: \(snapshot.post.assets.count, privacy: .public) assets, \(alt, privacy: .public) with alt text, previous: \(previous == nil ? "none" : "some", privacy: .public)")
            do {
                return try PostPackage.makeFileWrapper(from: snapshot, previous: previous)
            } catch {
                // SwiftUI can swallow a write failure, which is how a save looks like a
                // no-op rather than an error. Say so before rethrowing.
                documentLog.error("writer failed: \(String(describing: error), privacy: .public)")
                throw error
            }
        }
    }

    @MainActor
    func snapshot(contentType: UTType) async throws -> sending PostSnapshot {
        let alt = post.referencedImageIDs.compactMap { post.assets[$0]?.altText }.filter { !$0.isEmpty }
        documentLog.notice("snapshot: \(alt.count, privacy: .public) of \(self.post.assets.count, privacy: .public) assets have alt text")
        return PostSnapshot(post: post, publishRecords: publishRecords, images: images)
    }
}
