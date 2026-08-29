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

    @Test("A name WordPress had to number, because one of that name was already there")
    func uploadKeyStripsTheDuplicateSuffix() {
        // Two uploads of the same export in one month: the second arrives as "-1".
        let body = "october-03-2025-santabarbara-1742-08-12-fujifilm-x-t5-xf70-300mmf4-56-r-lm-ois-wr-dscf1742"
        #expect(OriginalsLibrary.uploadKey("\(body)_54857416226_o-large-1.jpeg") == body)
        #expect(OriginalsLibrary.uploadKey("\(body)_54857416226_o-large-12.jpeg") == body)
    }

    @Test("An abbreviated month is the same shoot as a spelled-out one")
    func abbreviatedMonthsMatch() {
        // The same folder of exports uses both spellings, so the key has to agree.
        #expect(
            OriginalsLibrary.key("Nov 06, 2025-SanRafael-3792-13-11-Fujifilm-X-T5-DSCF3792.jpg")
                == OriginalsLibrary.key("November 06, 2025-SanRafael-3792-13-11-Fujifilm-X-T5-DSCF3792.jpg")
        )
        // Only where a month opens the name and a day and year follow it.
        #expect(OriginalsLibrary.expandingMonth("dec-25-2025-x") == "december-25-2025-x")
        #expect(OriginalsLibrary.expandingMonth("marmot-lake-2025") == "marmot-lake-2025")
        #expect(OriginalsLibrary.expandingMonth("aug-2025-holiday") == "aug-2025-holiday")
    }

    @Test("Originals are found in subfolders, because Drive keeps a folder per shoot")
    func walksSubfolders() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let shoot = directory.appending(path: "SanRafael1125")
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = "Nov 06, 2025-SanRafael-3792-13-11-Fujifilm-X-T5-DSCF3792.jpg"
        try Data("pixels".utf8).write(to: shoot.appending(path: original))

        let library = try OriginalsLibrary(directory: directory)
        let found = library.original(forUploadedFileName:
            "november-06-2025-sanrafael-3792-13-11-fujifilm-x-t5-dscf3792_54906794381_o-large.jpeg")
        #expect(found?.lastPathComponent == original)
    }
}
