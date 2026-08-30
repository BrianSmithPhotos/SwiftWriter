import BlogPublishing
import Foundation
import PostKit
import SwiftUI
import WordPressProvider

/// Publishes the open post, using the same rules as the command line.
///
/// Everything about what to send lives in `PublishRun`. What is here is what only the app
/// has: the document's images, somewhere to show progress, and the token in the Keychain.
@Observable
@MainActor
final class PostPublisher {
    enum State: Equatable {
        case idle
        case working(String)
        case failed(String)
        case done(String)
    }

    private(set) var state: State = .idle

    var isWorking: Bool { if case .working = state { true } else { false } }

    /// Which site to publish to.
    ///
    /// A post that has been published before answers for itself, so reopening an imported
    /// post never asks. Otherwise it is the site set in the inspector.
    static func siteID(for document: PostDocument, default fallback: String) -> String {
        document.publishRecords.first { $0.providerID == WordPressSite.providerID }?.siteID
            ?? fallback
    }

    func publish(
        _ document: PostDocument,
        siteID: String,
        status: PublishStatus,
        scheduledFor: Date? = nil
    ) async {
        state = .working("Preparing")
        do {
            let record = try await run(document, siteID: siteID, status: status, scheduledFor: scheduledFor)
            document.publishRecords = document.publishRecords.updating(with: record)
            // Written straight into the package rather than left for the next document save.
            // publishing.json is a separate file precisely so recording an upload does not
            // rewrite post.json and every photograph beside it - and so that a publish is on
            // disk before anything else can go wrong.
            try writeRecords(document)
            state = .done(record.remoteURL?.absoluteString ?? "Published")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func dismiss() { state = .idle }

    private func run(
        _ document: PostDocument, siteID: String, status: PublishStatus, scheduledFor: Date?
    ) async throws -> PublishRecord {
        guard !siteID.isEmpty else { throw PublisherError.noSite }
        guard document.url != nil else { throw PublisherError.unsaved }

        let store = KeychainTokenStore()
        guard let token = try store.load(siteID: siteID) else {
            throw PublisherError.noToken(siteID)
        }
        let site = WordPressSite(siteID: siteID) { token.accessToken }

        // Read on the main actor, where the document lives, before any of the sending starts.
        // The closure PublishRun calls has to be able to answer without awaiting.
        let bytes = try collectBytes(document)
        let held = document.publishRecords.first {
            $0.providerID == WordPressSite.providerID && $0.siteID == siteID
        }

        let plan = try PublishRun.plan(post: document.post, held: held) { id in
            guard let data = bytes[id] else { throw PublishError.missingMedia(id) }
            return data
        }
        state = .working(plan.toUpload == 1 ? "Uploading 1 photograph"
            : plan.toUpload > 1 ? "Uploading \(plan.toUpload) photographs"
            : "Sending the post")

        return try await PublishRun.send(
            plan, post: document.post, to: site, status: status,
            scheduledFor: scheduledFor, remotePostID: held?.remotePostID,
            bytes: { bytes[$0] ?? Data() }
        ) { step in
            // The one step that changes what is happening rather than reporting progress: the
            // post was gone, so a publish that promised to send nothing now sends everything.
            guard case .postMissing = step else { return }
            Task { @MainActor [weak self] in
                self?.state = .working("The post was gone from the blog - uploading it again")
            }
        }
    }

    /// Every referenced photograph, read once up front.
    ///
    /// A post is at most a few dozen web derivatives, so holding them briefly costs less
    /// than reading each one twice - `PublishRun` hashes the bytes and then sends them.
    private func collectBytes(_ document: PostDocument) throws -> [ImageID: Data] {
        var bytes: [ImageID: Data] = [:]
        for imageID in document.post.referencedImageIDs {
            guard let data = document.location(of: imageID)?.bytes() else {
                throw PublishError.missingMedia(imageID)
            }
            bytes[imageID] = data
        }
        return bytes
    }

    private func writeRecords(_ document: PostDocument) throws {
        guard let url = document.url else { throw PublisherError.unsaved }
        let data = try PostPackage.makeEncoder().encode(document.publishRecords)
        try data.write(
            to: url.appending(path: PostPackage.publishingFileName), options: .atomic
        )
    }
}

enum PublisherError: LocalizedError {
    case noSite
    case unsaved
    case noToken(String)

    var errorDescription: String? {
        switch self {
        case .noSite:
            "No site to publish to. Set the WordPress site id in the inspector."
        case .unsaved:
            "Save the post before publishing it, so there is somewhere to record what went out."
        case let .noToken(siteID):
            "Not signed in to site \(siteID). Use Sign In, above."
        }
    }
}
