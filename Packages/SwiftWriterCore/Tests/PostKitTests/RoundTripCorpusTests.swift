import Foundation
import Testing
@testable import PostKit

/// Exercises the exact read-edit-write-read cycle the app performs when you type alt text
/// and press save. Uses a real package copied out of the corpus when one is present, so the
/// test sees the same shape of data the editor does.
@Suite("Editing a package on disk")
struct RoundTripCorpusTests {
    private static var corpusPackage: URL? {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()   // PostKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // SwiftWriterCore
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repository root
            .appending(path: "Corpus/Posts/mt-diablo-state-park.swiftpost")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @Test("Alt text typed into a saved package survives save and reopen")
    func altTextSurvivesRoundTrip() throws {
        let source = try #require(Self.corpusPackage, "corpus package not present")

        let wrapper = try FileWrapper(url: source, options: [.immediate])
        var snapshot = try PostPackage.makeSnapshot(from: wrapper)

        let heroID = try #require(snapshot.post.heroImageID)
        #expect(snapshot.post.assets[heroID]?.altText == "")

        snapshot.post.assets[heroID]?.altText = "A view north from the summit"

        let scratch = URL(filePath: NSTemporaryDirectory())
            .appending(path: "swiftwriter-roundtrip-\(UUID().uuidString).swiftpost")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let written = try PostPackage.makeFileWrapper(from: snapshot, previous: wrapper)
        try written.write(to: scratch, options: .atomic, originalContentsURL: nil)

        let reread = try PostPackage.makeSnapshot(
            from: try FileWrapper(url: scratch, options: [.immediate])
        )
        #expect(reread.post.assets[heroID]?.altText == "A view north from the summit")
    }

    /// The app cannot assume the framework hands it the old package. If it does not, every
    /// image in a document opened from disk is `.existing` with nowhere to read it from.
    @Test("Writing a package whose images are all on disk fails without the previous wrapper")
    func writingWithoutPreviousFails() throws {
        let source = try #require(Self.corpusPackage, "corpus package not present")
        let snapshot = try PostPackage.makeSnapshot(
            from: try FileWrapper(url: source, options: [.immediate])
        )
        #expect(throws: PostPackageError.self) {
            _ = try PostPackage.makeFileWrapper(from: snapshot, previous: nil)
        }
    }

    @Test("A package read and written unchanged keeps the hash its publish record holds")
    func recordedHashMatchesWhatIsOnDisk() throws {
        let source = try #require(Self.corpusPackage, "corpus package not present")
        let snapshot = try PostPackage.makeSnapshot(
            from: try FileWrapper(url: source, options: [.immediate])
        )
        let recorded = try #require(snapshot.publishRecords.first?.contentHash)
        #expect(try snapshot.post.contentHash() == recorded)
    }
}
