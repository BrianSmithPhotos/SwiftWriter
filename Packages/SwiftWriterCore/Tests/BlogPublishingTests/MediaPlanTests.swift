import Foundation
import Testing
import PostKit
@testable import BlogPublishing

/// One held attachment, so each test varies only the thing it is about.
private func held(
    hash: String = "abc", alt: String? = "A barn at dawn", caption: String? = nil
) -> UploadedMedia {
    UploadedMedia(
        remoteID: "101",
        url: URL(string: "https://briansmith.photos/one.jpg")!,
        contentHash: hash,
        altText: alt,
        caption: caption
    )
}

@Suite("Media plan")
struct MediaPlanTests {
    @Test("An image the blog has never seen is uploaded")
    func firstTimeUploads() {
        #expect(MediaAction.decide(held: nil, contentHash: "abc", altText: nil, caption: nil) == .upload)
    }

    @Test("An unchanged image is reused, so republishing does not duplicate it")
    func unchangedReuses() {
        let known = held()
        #expect(
            MediaAction.decide(held: known, contentHash: "abc", altText: "A barn at dawn", caption: nil)
                == .reuse(known)
        )
    }

    @Test("Alt text added after publishing is sent on its own, not with the pixels again")
    func newAltDescribes() {
        let known = held(alt: nil)
        #expect(
            MediaAction.decide(held: known, contentHash: "abc", altText: "A barn at dawn", caption: nil)
                == .describe(known)
        )
    }

    @Test("Clearing the alt text is a change too, not a no-op")
    func clearedAltDescribes() {
        let known = held()
        #expect(
            MediaAction.decide(held: known, contentHash: "abc", altText: nil, caption: nil)
                == .describe(known)
        )
    }

    @Test("An edited caption alone is enough to describe")
    func changedCaptionDescribes() {
        let known = held(caption: "The barn")
        #expect(
            MediaAction.decide(
                held: known, contentHash: "abc", altText: "A barn at dawn", caption: "The barn, at dawn"
            ) == .describe(known)
        )
    }

    @Test("Different pixels in the same slot are uploaded rather than redescribed")
    func changedBytesUpload() {
        // Replacing the photograph must not leave the post pointing at the old attachment.
        #expect(
            MediaAction.decide(held: held(), contentHash: "def", altText: "A barn at dawn", caption: nil)
                == .upload
        )
    }
}
