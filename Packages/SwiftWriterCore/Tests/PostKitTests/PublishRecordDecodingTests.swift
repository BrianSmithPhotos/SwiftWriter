import Foundation
import Testing
@testable import PostKit

@Suite("Reading publishing.json")
struct PublishRecordDecodingTests {
    /// Exactly what the 33 imported corpus packages hold: written before uploaded media
    /// was recorded, so there is no `media` key at all.
    static let beforeMediaWasRecorded = """
    [
      {
        "id" : "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
        "providerID" : "wordpress",
        "siteID" : "174606693",
        "remotePostID" : "19727",
        "status" : "scheduled"
      }
    ]
    """

    @Test("A record written before this version still reads, with no uploads remembered")
    func olderRecordStillReads() throws {
        let records = try PostPackage.makeDecoder()
            .decode([PublishRecord].self, from: Data(Self.beforeMediaWasRecorded.utf8))
        #expect(records.count == 1)
        #expect(records[0].remotePostID == "19727")
        #expect(records[0].media.isEmpty)
    }

    @Test("Uploaded media round-trips as an object keyed by image id")
    func mediaRoundTrips() throws {
        let imageID = ImageID.makeUnique()
        let record = PublishRecord(
            providerID: "wordpress", siteID: "174606693", remotePostID: "19727",
            media: [imageID: UploadedMedia(
                remoteID: "101",
                url: URL(string: "https://briansmith.photos/one.jpg")!,
                contentHash: UploadedMedia.hash(of: Data("pixels".utf8)),
                altText: "A barn at dawn"
            )]
        )
        let data = try PostPackage.makeEncoder().encode([record])
        // Keyed by the image id, not a flat array of alternating keys and values, so the
        // file stays readable and diffable.
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"\(imageID.rawValue)\" : {"))

        let decoded = try PostPackage.makeDecoder().decode([PublishRecord].self, from: data)
        #expect(decoded == [record])
    }

    @Test("The hash changes when the pixels do, and not when they do not")
    func hashTracksBytes() {
        #expect(UploadedMedia.hash(of: Data("one".utf8)) == UploadedMedia.hash(of: Data("one".utf8)))
        #expect(UploadedMedia.hash(of: Data("one".utf8)) != UploadedMedia.hash(of: Data("two".utf8)))
    }
}
