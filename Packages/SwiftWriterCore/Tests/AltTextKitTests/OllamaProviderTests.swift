import Foundation
import Testing
@testable import AltTextKit
import PostKit

/// Ollama's own `/api/tags`, trimmed to the fields that are read.
private func tags(_ entries: (name: String, capabilities: [String])...) -> Data {
    let models = entries.map { entry in
        """
        {"name":"\(entry.name)","model":"\(entry.name)",
         "capabilities":[\(entry.capabilities.map { "\"\($0)\"" }.joined(separator: ","))]}
        """
    }
    return Data("{\"models\":[\(models.joined(separator: ","))]}".utf8)
}

@Suite("Checking an Ollama model before sending it a photograph")
struct OllamaAvailabilityTests {
    /// The real shape, copied from this machine's `curl localhost:11434/api/tags`.
    private let installed = tags(
        ("qwen3.8:27b-mlx", ["completion", "vision", "tools", "thinking"]),
        ("llama3.2:3b", ["completion", "tools"])
    )

    @Test("A vision-capable model that is pulled passes")
    func visionModelPasses() throws {
        try OllamaProvider.checkVision(tags: installed, model: "qwen3.8:27b-mlx")
    }

    @Test("A model that is not pulled is named, with the command that fixes it")
    func missingModelSaysHowToGetIt() {
        #expect(throws: AltTextError.provider("\"qwen3.8:80b\" is not pulled - run: ollama pull qwen3.8:80b")) {
            try OllamaProvider.checkVision(tags: installed, model: "qwen3.8:80b")
        }
    }

    /// Told apart from "not pulled" on purpose: pulling it again would not help.
    @Test("A text-only model is refused for a different reason")
    func textOnlyModelIsRefused() {
        #expect(throws: AltTextError.provider("\"llama3.2:3b\" cannot be sent an image")) {
            try OllamaProvider.checkVision(tags: installed, model: "llama3.2:3b")
        }
    }

    /// Ollama has added fields to this endpoint before; capabilities may simply be absent.
    @Test("A model listing with no capabilities at all is refused rather than assumed")
    func absentCapabilitiesAreNotAssumed() {
        let old = Data("{\"models\":[{\"name\":\"qwen3.8:27b-mlx\"}]}".utf8)
        #expect(throws: AltTextError.self) {
            try OllamaProvider.checkVision(tags: old, model: "qwen3.8:27b-mlx")
        }
    }

    @Test("Something that is not Ollama's model list is reported, not crashed on")
    func unreadableListing() {
        #expect(throws: AltTextError.provider("Could not read Ollama's model list")) {
            try OllamaProvider.checkVision(tags: Data("<html>404</html>".utf8), model: "any")
        }
    }
}

@Suite("The request Ollama is sent, and the answer read back")
struct OllamaPayloadTests {
    private func body(fast: Bool) throws -> [String: Any] {
        let data = try OllamaProvider.chatBody(
            model: "qwen3.8:27b-mlx", instructions: "You write alt text.", prompt: "Describe this.",
            imageJPEG: Data([0xFF, 0xD8, 0xFF]), fast: fast
        )
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("The image goes up base64 encoded, on the user message only")
    func imageRidesOnTheUserMessage() throws {
        let messages = try #require(try body(fast: false)["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[0]["images"] == nil)
        #expect(messages[1]["role"] as? String == "user")
        #expect(messages[1]["images"] as? [String] == [Data([0xFF, 0xD8, 0xFF]).base64EncodedString()])
    }

    @Test("Streaming and reasoning are both off, and the weights stay loaded between images")
    func settingsThatMakeARunOverAPostBearable() throws {
        let payload = try body(fast: false)
        #expect(payload["stream"] as? Bool == false)
        #expect(payload["think"] as? Bool == false)
        #expect(payload["keep_alive"] as? String == "15m")
        #expect((payload["options"] as? [String: Any])?["temperature"] as? Double == 0.2)
    }

    /// The retry has to be a different request, or it is just the same one sent twice.
    @Test("Only the retry caps the answer's length")
    func onlyTheRetryIsCapped() throws {
        #expect((try body(fast: false)["options"] as? [String: Any])?["num_predict"] == nil)
        #expect((try body(fast: true)["options"] as? [String: Any])?["num_predict"] as? Int == 160)
    }

    @Test("The answer is lifted out of the message")
    func readsTheAnswer() throws {
        let data = Data("{\"message\":{\"role\":\"assistant\",\"content\":\"  An osprey on a nest.  \"}}".utf8)
        #expect(try OllamaProvider.text(fromChat: data) == "An osprey on a nest.")
    }

    /// The service retries on this one, so it must not arrive as a generic provider failure.
    @Test("An empty answer is the kind of failure that gets retried")
    func emptyAnswerIsRetryable() {
        #expect(throws: AltTextError.emptyResponse) {
            try OllamaProvider.text(fromChat: Data("{\"message\":{\"content\":\"\"}}".utf8))
        }
        #expect(throws: AltTextError.emptyResponse) {
            try OllamaProvider.text(fromChat: Data("{}".utf8))
        }
    }
}

/// Set SWIFTWRITER_ALT_LIVE_IMAGE to a JPEG path to run this against the real local model.
@Suite(
    "Describing a real photograph with Ollama",
    .enabled(if: ProcessInfo.processInfo.environment["SWIFTWRITER_ALT_LIVE_IMAGE"] != nil)
)
struct LiveOllamaTests {
    @Test("The local model writes alt text for an actual image")
    func describesRealPhotograph() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["SWIFTWRITER_ALT_LIVE_IMAGE"])
        var asset = ImageAsset(id: .makeUnique(), fileName: (path as NSString).lastPathComponent)
        if let sidecarPath = ProcessInfo.processInfo.environment["SWIFTWRITER_ALT_LIVE_SIDECAR"],
           let sidecar = try? Data(contentsOf: URL(filePath: sidecarPath)) {
            asset = try PostPackage.makeDecoder().decode(ImageAsset.self, from: sidecar)
        }
        let text = try await AltTextService().altText(
            for: AltTextRequest(asset: asset),
            imageJPEG: try Data(contentsOf: URL(filePath: path)),
            provider: OllamaProvider(), model: OllamaProvider.defaultModel
        )
        print("\n--- ollama alt text ---\n\(text)\n--- \(text.split(separator: " ").count) words ---\n")
        #expect(!text.isEmpty)
    }
}
