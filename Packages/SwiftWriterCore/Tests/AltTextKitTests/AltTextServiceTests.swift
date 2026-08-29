import Foundation
import Testing
@testable import AltTextKit
import PostKit

/// The osprey that is actually in the corpus, sidecar and all.
private func osprey() -> ImageAsset {
    var asset = ImageAsset(
        id: .makeUnique(), fileName: "osprey.jpeg",
        caption: InlineText.plain("Osprey, Pandion haliaetus"),
        pixelWidth: 1762, pixelHeight: 1383
    )
    asset.capture = CaptureMetadata(
        camera: "FUJIFILM X-T5",
        lens: "XF70-300mmF4-5.6 R LM OIS WR",
        keywords: [
            "70-300mm", "California", "China Camp", "FujiFilm", "Fujinon", "Marin",
            "Osprey", "Pandion haliaetus", "San Rafael", "X-T5",
        ]
    )
    return asset
}

private let pixels = Data("not really a jpeg".utf8)

@Suite("Alt text")
struct AltTextServiceTests {
    @Test("The camera and the lens are kept out of what the model is told")
    func gearIsDroppedFromKeywords() {
        let request = AltTextRequest(asset: osprey())
        #expect(request.caption == "Osprey, Pandion haliaetus")
        // Dropped because each appears inside the recorded camera or lens name.
        #expect(!request.keywords.contains("70-300mm"))
        #expect(!request.keywords.contains("FujiFilm"))
        #expect(!request.keywords.contains("X-T5"))
        // Kept: subject and place are the whole point of sending keywords at all.
        #expect(request.keywords.contains("Osprey"))
        #expect(request.keywords.contains("China Camp"))
        #expect(request.keywords.contains("San Rafael"))
    }

    @Test("A brand the rule cannot catch is caught by the prompt instead")
    func gearThatSurvivesIsForbiddenInWords() {
        // "Fujinon" is in neither the camera nor the lens string, so the filter keeps it.
        let request = AltTextRequest(asset: osprey())
        #expect(request.keywords.contains("Fujinon"))
        #expect(AltTextService.prompt(for: request).contains("Never mention the camera"))
    }

    @Test("The caption is given as identification, and as something not to repeat")
    func captionIsContextNotAnAnswer() {
        let prompt = AltTextService.prompt(for: AltTextRequest(asset: osprey()))
        #expect(prompt.contains("Osprey, Pandion haliaetus"))
        #expect(prompt.contains("do not "))
        #expect(prompt.contains("repeat it"))
    }

    @Test("An image with no caption and no metadata still gets a usable prompt")
    func bareAssetStillPrompts() {
        let request = AltTextRequest(asset: ImageAsset(id: .makeUnique(), fileName: "a.jpg"))
        let prompt = AltTextService.prompt(for: request)
        #expect(request.caption.isEmpty)
        #expect(request.keywords.isEmpty)
        #expect(prompt.contains("Write alt text for this photograph"))
        #expect(!prompt.contains("The photographer captioned it"))
        #expect(!prompt.contains("keywords"))
    }

    @Test("A clean answer comes back as it was written")
    func plainAnswerSurvives() async throws {
        let provider = StubProvider(answering: "An osprey grips a fish in both talons on a bare branch.")
        let text = try await AltTextService().altText(
            for: AltTextRequest(asset: osprey()), imageJPEG: pixels, provider: provider, model: "stub"
        )
        #expect(text == "An osprey grips a fish in both talons on a bare branch.")
        #expect(await provider.availabilityChecks == 1)
        #expect(await provider.fastFlags == [false])
    }

    @Test("The model is asked whether it can answer before it is sent an image")
    func availabilityIsCheckedFirst() async {
        let provider = StubProvider(answers: [], availability: .provider("Apple Intelligence is not ready"))
        await #expect(throws: AltTextError.provider("Apple Intelligence is not ready")) {
            try await AltTextService().altText(
                for: AltTextRequest(asset: osprey()), imageJPEG: pixels, provider: provider, model: "stub"
            )
        }
        // Nothing was sent, so no image left the machine for a request that could not be answered.
        #expect(await provider.prompts.isEmpty)
    }

    @Test("A timeout is retried once, at lower effort")
    func retriesOnceAfterTimeout() async throws {
        let provider = StubProvider(answers: [.failure(.timeout), .success("A great blue heron stands in shallow water.")])
        let text = try await AltTextService().altText(
            for: AltTextRequest(asset: osprey()), imageJPEG: pixels, provider: provider, model: "stub"
        )
        #expect(text == "A great blue heron stands in shallow water.")
        #expect(await provider.fastFlags == [false, true])
        // The same prompt, so the retry is a lower-effort attempt at the job, not a different job.
        #expect(await provider.prompts.count == 2)
        #expect(await provider.prompts[0] == provider.prompts[1])
    }

    @Test("An answer that tidies away to nothing counts as empty, and is retried")
    func unusableAnswerIsRetried() async throws {
        let provider = StubProvider(answers: [.success("   \n  "), .success("Two sea otters float side by side.")])
        let text = try await AltTextService().altText(
            for: AltTextRequest(asset: osprey()), imageJPEG: pixels, provider: provider, model: "stub"
        )
        #expect(text == "Two sea otters float side by side.")
        #expect(await provider.fastFlags == [false, true])
    }

    @Test("A second failure is reported rather than retried again")
    func doesNotRetryTwice() async {
        let provider = StubProvider(answers: [.failure(.timeout), .failure(.timeout)])
        await #expect(throws: AltTextError.timeout) {
            try await AltTextService().altText(
                for: AltTextRequest(asset: osprey()), imageJPEG: pixels, provider: provider, model: "stub"
            )
        }
        #expect(await provider.prompts.count == 2)
    }

    @Test("A provider error is not retried, because the second request fails the same way")
    func providerErrorIsNotRetried() async {
        let provider = StubProvider(answers: [.failure(.provider("no such model")), .success("unreached")])
        await #expect(throws: AltTextError.provider("no such model")) {
            try await AltTextService().altText(
                for: AltTextRequest(asset: osprey()), imageJPEG: pixels, provider: provider, model: "stub"
            )
        }
        #expect(await provider.prompts.count == 1)
    }
}

@Suite("Tidying a model's answer")
struct AltTextCleaningTests {
    @Test("The habits models actually have", arguments: [
        ("```\nAn osprey lands on a post.\n```", "An osprey lands on a post."),
        ("Alt text: An osprey lands on a post.", "An osprey lands on a post."),
        ("Alt: An osprey lands on a post.", "An osprey lands on a post."),
        ("\"An osprey lands on a post.\"", "An osprey lands on a post."),
        ("A photo of an osprey landing on a post.", "An osprey landing on a post."),
        ("Image showing an osprey on a post.", "An osprey on a post."),
        ("An osprey\nlands   on a post.", "An osprey lands on a post."),
        ("  An osprey lands on a post.  ", "An osprey lands on a post."),
    ])
    func tidies(raw: String, expected: String) {
        #expect(AltTextService.clean(raw) == expected)
    }

    @Test("A quotation inside a sentence is left alone")
    func keepsInnerQuotes() {
        #expect(AltTextService.clean("A sign reads \"Keep Out\" beside the gate.")
            == "A sign reads \"Keep Out\" beside the gate.")
    }

    @Test("Nothing usable is nil, not an empty alt attribute")
    func emptyIsNil() {
        #expect(AltTextService.clean("") == nil)
        #expect(AltTextService.clean("  \n ") == nil)
        #expect(AltTextService.clean("```\n```") == nil)
    }

    @Test("A long answer is kept whole rather than cut mid-sentence")
    func doesNotTruncate() {
        let long = String(repeating: "word ", count: 60) + "end."
        let cleaned = AltTextService.clean(long)
        #expect(cleaned?.hasSuffix("end.") == true)
    }
}
