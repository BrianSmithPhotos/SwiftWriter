import Foundation
import Testing
@testable import WXRImport

@Suite("Matching blog uploads back to the camera originals")
struct OriginalsLibraryTests {
    @Test("WordPress drops periods rather than hyphenating them",
          arguments: [
              ("November 10, 2025-CastleRock-4159-11-24-Fujifilm-X-T5-XF18mmF1.4 R LM WR-DSCF4159.jpg",
               "november-10-2025-castlerock-4159-11-24-fujifilm-x-t5-xf18mmf14-r-lm-wr-dscf4159"),
              ("Pixel 8 Pro back camera 18.0mm f-2.8.jpg",
               "pixel-8-pro-back-camera-180mm-f-28"),
          ])
    func slugMatchesWordPress(fileName: String, expected: String) {
        #expect(OriginalsLibrary.slug(fileName) == expected)
    }

    @Test("The Flickr tail and the featured prefix are not part of the key")
    func uploadKeyStripsWhatWordPressAdded() {
        // Both of these are the same photograph: the second is the post thumbnail.
        let body = "november-10-2025-castlerock-4159-11-24-fujifilm-x-t5-xf18mmf14-r-lm-wr-dscf4159"
        #expect(OriginalsLibrary.uploadKey("\(body)_54925434907_o-large.jpeg") == body)
        #expect(OriginalsLibrary.uploadKey("featured_\(body)_54925434907_o-large.jpeg") == body)
        #expect(OriginalsLibrary.uploadKey("\(body)_54925434907_o-scaled.jpeg") == body)
    }

    @Test("A folder of originals resolves an uploaded name back to the file")
    func resolvesFromDisk() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = "November 10, 2025-CastleRock-4159-11-24-Fujifilm-X-T5-XF18mmF1.4 R LM WR-DSCF4159.jpg"
        try Data("pixels".utf8).write(to: directory.appending(path: original))

        let library = try OriginalsLibrary(directory: directory)
        #expect(library.count == 1)
        let found = library.original(forUploadedFileName:
            "november-10-2025-castlerock-4159-11-24-fujifilm-x-t5-xf18mmf14-r-lm-wr-dscf4159_54925434907_o-large.jpeg")
        #expect(found?.lastPathComponent == original)
        #expect(library.original(forUploadedFileName: "something-else_1_o-large.jpeg") == nil)
    }
}
