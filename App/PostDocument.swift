import Foundation
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
@Observable
final class PostDocument: Document {
    var post: Post
    var publishRecords: [PublishRecord]

    /// Where each image currently lives. An image loaded from disk stays `.existing` until
    /// it is replaced, which is what lets the writer reuse its file wrapper instead of
    /// rewriting several hundred megabytes of photographs on every keystroke.
    var images: [ImageID: ImageSource]

    init(post: Post = Post(title: ""), publishRecords: [PublishRecord] = [], images: [ImageID: ImageSource] = [:]) {
        self.post = post
        self.publishRecords = publishRecords
        self.images = images
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
        post = snapshot.post
        publishRecords = snapshot.publishRecords
        images = snapshot.images
    }

    // MARK: - Writing

    static var writableContentTypes: [UTType] { [.swiftWriterPost] }

    func writer(configuration: sending WriteConfiguration) -> sending FileWrapperDocumentWriter<PostSnapshot> {
        FileWrapperDocumentWriter(configuration) { snapshot, previous in
            try PostPackage.makeFileWrapper(from: snapshot, previous: previous)
        }
    }

    @MainActor
    func snapshot(contentType: UTType) async throws -> sending PostSnapshot {
        PostSnapshot(post: post, publishRecords: publishRecords, images: images)
    }
}
