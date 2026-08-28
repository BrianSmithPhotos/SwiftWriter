import Foundation
import Testing
@testable import PostKit

/// Exercises the read-edit-write-read cycle the app performs when you type alt text into a
/// document that was opened from disk. That case is different from a fresh save: the images
/// come back as `.existing` with no bytes, so the writer has to find them somewhere.
@Suite("Editing a package that was opened from disk")
struct SavedPackageEditTests {
    private let heroID = ImageID(rawValue: "hero01")!

    /// Writes a small package to a scratch directory and hands back its URL.
    private func makeSavedPackage() throws -> URL {
        var post = Post(title: "Mt Diablo State Park", heroImageID: heroID)
        post.assets[heroID] = ImageAsset(id: heroID, fileName: "\(heroID.rawValue).jpeg", altText: "")

        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "swiftwriter-\(UUID().uuidString).swiftpost")
        try PostPackage
            .makeFileWrapper(
                from: PostSnapshot(post: post, images: [heroID: .data(Data("pixels".utf8))]),
                previous: nil
            )
            .write(to: url, options: .atomic, originalContentsURL: nil)
        return url
    }

    @Test("Alt text typed into a saved package survives save and reopen")
    func altTextSurvivesRoundTrip() throws {
        let url = try makeSavedPackage()
        defer { try? FileManager.default.removeItem(at: url) }

        let onDisk = try FileWrapper(url: url, options: [.immediate])
        var snapshot = try PostPackage.makeSnapshot(from: onDisk)
        #expect(snapshot.images[heroID] == .existing(fileName: "\(heroID.rawValue).jpeg"))

        snapshot.post.assets[heroID]?.altText = "A view north from the summit"

        try PostPackage.makeFileWrapper(from: snapshot, previous: onDisk)
            .write(to: url, options: .atomic, originalContentsURL: nil)

        let reread = try PostPackage.makeSnapshot(from: try FileWrapper(url: url, options: [.immediate]))
        #expect(reread.post.assets[heroID]?.altText == "A view north from the summit")
        #expect(reread.images[heroID] != nil)
    }

    /// The app cannot assume the framework hands it the old package. Without it there is
    /// nowhere to read an `.existing` image from, and writing anyway would produce a post
    /// with missing photographs, so the codec refuses.
    @Test("Writing a package whose images are all on disk fails without the previous wrapper")
    func writingWithoutPreviousFails() throws {
        let url = try makeSavedPackage()
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = try PostPackage.makeSnapshot(from: try FileWrapper(url: url, options: [.immediate]))
        #expect(throws: PostPackageError.self) {
            _ = try PostPackage.makeFileWrapper(from: snapshot, previous: nil)
        }
    }
}
