import Foundation
import Testing
@testable import PostKit

/// What saving does when a photograph in the package cannot be read.
///
/// The app opens the previous package lazily - `FileWrapper(url:)` with no `.immediate` -
/// so an `.existing` image is nothing but a filename until the moment of writing. Anything
/// that makes the file unreadable in between lands here: a network share that dropped, an
/// iCloud file that could not be materialised because the machine is offline, a permissions
/// change. That is the shape of the failure that lost the Castle Rock package over SMB.
///
/// Two things have to hold, and both are asserted below: the write must fail rather than
/// produce a package with a hole where a photograph was, and a failed save must leave what
/// was already on disk untouched.
@Suite("Saving when a photograph cannot be read")
struct UnreadableImageTests {
    private let heroID = ImageID(rawValue: "hero01")!
    private let pixels = Data(repeating: 0xAB, count: 5000)

    /// A saved package in its own scratch directory, and the image file inside it.
    private func makeSavedPackage() throws -> (directory: URL, package: URL, image: URL) {
        var post = Post(title: "Castle Rock State Park", heroImageID: heroID)
        post.assets[heroID] = ImageAsset(id: heroID, fileName: "\(heroID.rawValue).jpeg", altText: "")

        let directory = URL(filePath: NSTemporaryDirectory())
            .appending(path: "swiftwriter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let package = directory.appending(path: "post.swiftpost")
        try PostPackage
            .makeFileWrapper(
                from: PostSnapshot(post: post, images: [heroID: .data(pixels)]),
                previous: nil
            )
            .write(to: package, options: .atomic, originalContentsURL: nil)

        let image = package
            .appending(path: PostPackage.imagesDirectoryName)
            .appending(path: "\(heroID.rawValue).jpeg")
        return (directory, package, image)
    }

    /// Denies read access to the image, runs `body`, and restores access afterwards so the
    /// scratch directory can be cleaned up either way.
    private func withUnreadableImage(_ image: URL, _ body: () throws -> Void) rethrows {
        try? FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: image.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: image.path)
        }
        try body()
    }

    @Test("A photograph that cannot be read fails the save instead of writing a hole")
    func writeFailsRatherThanLosingThePhotograph() throws {
        let (directory, package, image) = try makeSavedPackage()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Lazy, exactly as the app reads the previous package: a filename, not the pixels.
        let onDisk = try FileWrapper(url: package)
        let snapshot = try PostPackage.makeSnapshot(from: onDisk)
        #expect(snapshot.images[heroID] == .existing(fileName: "\(heroID.rawValue).jpeg"))

        let destination = directory.appending(path: "saved-as.swiftpost")
        withUnreadableImage(image) {
            #expect(throws: (any Error).self) {
                try PostPackage.makeFileWrapper(from: snapshot, previous: onDisk)
                    .write(to: destination, options: .atomic, originalContentsURL: nil)
            }
        }

        // An atomic write that failed must leave nothing behind. A package here would be one
        // holding a post that references a photograph it does not contain.
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("A save that fails partway leaves the package already on disk intact")
    func failedSaveLeavesTheOriginalIntact() throws {
        let (directory, package, image) = try makeSavedPackage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let onDisk = try FileWrapper(url: package)
        var snapshot = try PostPackage.makeSnapshot(from: onDisk)
        snapshot.post.title = "Castle Rock, second visit"

        withUnreadableImage(image) {
            #expect(throws: (any Error).self) {
                try PostPackage.makeFileWrapper(from: snapshot, previous: onDisk)
                    .write(to: package, options: .atomic, originalContentsURL: nil)
            }
        }

        // The edit is lost, which is the correct trade. The photograph is not.
        let reread = try PostPackage.makeSnapshot(from: try FileWrapper(url: package, options: [.immediate]))
        #expect(reread.post.title == "Castle Rock State Park")
        #expect(try Data(contentsOf: image) == pixels)
    }

    /// The same failure by way of a missing file rather than a denied one, which is how a
    /// share that disappeared mid-edit presents.
    @Test("A photograph deleted from the package while it is open fails the save too")
    func deletedPhotographFailsTheSave() throws {
        let (directory, package, image) = try makeSavedPackage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let onDisk = try FileWrapper(url: package)
        let snapshot = try PostPackage.makeSnapshot(from: onDisk)
        try FileManager.default.removeItem(at: image)

        let destination = directory.appending(path: "saved-as.swiftpost")
        #expect(throws: (any Error).self) {
            try PostPackage.makeFileWrapper(from: snapshot, previous: onDisk)
                .write(to: destination, options: .atomic, originalContentsURL: nil)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
