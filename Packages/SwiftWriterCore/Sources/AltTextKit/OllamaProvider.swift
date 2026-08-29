import Foundation
import os

/// A model running locally under Ollama, talking plain HTTP to 127.0.0.1:11434.
///
/// The second backend, and the reason `AltTextProvider` exists: it is this one file, with no
/// change to the service, the prompt or the tidying. Ported from MacPhotoMaster's
/// `OllamaProvider`, including its dynamic vision check - Ollama's own `/api/tags` reports each
/// model's capabilities, so there is no list of known vision models to keep up to date here.
///
/// Where Apple's on-device model answers into a `@Generable` struct, Ollama answers with free
/// text and may wrap it in a preamble or quotes. That is exactly what `AltTextService.clean`
/// already handles, so nothing extra is needed for it.
public struct OllamaProvider: AltTextProvider {
    /// Brian's local model. Vision-capable and, at 27B, considerably larger than the on-device
    /// model, which is the point of having it: the corpus catch-up is a one-time run where the
    /// answer is read aloud to someone who cannot check it, so quality beats speed.
    public static let defaultModel = "qwen3.8:27b-mlx"

    /// A 27B model on this hardware is not quick, and a cold start is slower still.
    private static let timeoutSeconds: TimeInterval = 180
    /// Keeps the weights resident between images, so a run over a whole post pays the load once.
    private static let keepAlive = "15m"
    /// The retry's budget. Enough for a long sentence, not enough to ramble.
    private static let fastTokenLimit = 160

    private static let logger = Logger(subsystem: "photos.briansmith.swiftwriter", category: "AltText")

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func ensureAvailable(model: String) async throws {
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AltTextError.provider("No Ollama model was named") }

        var request = URLRequest(url: baseURL.appending(path: "api/tags"))
        request.timeoutInterval = Self.timeoutSeconds
        let data = try await send(request)
        try Self.checkVision(tags: data, model: name)
    }

    public func describe(
        model: String, instructions: String, prompt: String, imageJPEG: Data, fast: Bool
    ) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.timeoutSeconds
        request.httpBody = try Self.chatBody(
            model: model, instructions: instructions, prompt: prompt, imageJPEG: imageJPEG, fast: fast
        )

        let start = Date()
        let data = try await send(request)
        let elapsed = Date().timeIntervalSince(start)
        Self.logger.log(
            "Ollama alt text: model=\(model, privacy: .public) fast=\(fast, privacy: .public) elapsed=\(elapsed, privacy: .public)s"
        )
        return try Self.text(fromChat: data)
    }

    // MARK: - The parts worth testing, kept free of the network

    /// - Throws: `.provider` naming what to do about it - the model is not pulled, or it is pulled
    ///   but cannot be sent an image. Both are worth telling apart, because the fix differs.
    static func checkVision(tags data: Data, model: String) throws {
        let listed: TagsResponse
        do { listed = try JSONDecoder().decode(TagsResponse.self, from: data) } catch {
            throw AltTextError.provider("Could not read Ollama's model list")
        }
        guard let match = listed.models.first(where: { $0.name == model || $0.model == model }) else {
            throw AltTextError.provider("\"\(model)\" is not pulled - run: ollama pull \(model)")
        }
        guard (match.capabilities ?? []).contains(where: { $0.lowercased() == "vision" }) else {
            throw AltTextError.provider("\"\(model)\" cannot be sent an image")
        }
    }

    static func chatBody(
        model: String, instructions: String, prompt: String, imageJPEG: Data, fast: Bool
    ) throws -> Data {
        try JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: [
                    Message(role: "system", content: instructions, images: nil),
                    Message(role: "user", content: prompt, images: [imageJPEG.base64EncodedString()]),
                ],
                // A low temperature because this is description, not writing. The one thing alt
                // text must not do is get inventive about what is in the frame.
                options: Options(temperature: 0.2, numPredict: fast ? fastTokenLimit : nil),
                // Reasoning buys nothing here and costs minutes on a 27B model.
                think: false,
                keepAlive: keepAlive))
    }

    static func text(fromChat data: Data) throws -> String {
        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data) else {
            throw AltTextError.provider("Could not read Ollama's answer")
        }
        let content = (decoded.message?.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw AltTextError.emptyResponse }
        return content
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw AltTextError.timeout
        } catch {
            throw AltTextError.provider(
                "Could not reach Ollama at \(baseURL.host() ?? "127.0.0.1") - is it running? "
                    + "(\(error.localizedDescription))")
        }
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            throw AltTextError.provider("Ollama returned status \(http.statusCode)")
        }
        return data
    }
}

// Optionals so the synthesized encoding leaves them out entirely: Ollama treats an absent
// "images" differently from an empty one, and "num_predict" absent means no limit.
private struct ChatRequest: Encodable {
    var model: String
    var stream = false
    var messages: [Message]
    var options: Options
    var think: Bool?
    var keepAlive: String

    enum CodingKeys: String, CodingKey {
        case model, stream, messages, options, think
        case keepAlive = "keep_alive"
    }
}

private struct Message: Encodable {
    var role: String
    var content: String?
    var images: [String]?
}

private struct Options: Encodable {
    var temperature: Double
    var numPredict: Int?

    enum CodingKeys: String, CodingKey {
        case temperature
        case numPredict = "num_predict"
    }
}

/// Reading the reply is its own struct rather than reusing `Message`, which needs a role to send
/// but must not require one to read: a reply missing a field has to arrive as an empty answer, the
/// one failure the service retries, not as an unreadable one, which it gives up on.
private struct ChatResponse: Decodable {
    struct Reply: Decodable { var content: String? }
    var message: Reply?
}

private struct TagsResponse: Decodable {
    var models: [TagModel]
}

private struct TagModel: Decodable {
    var name: String?
    var model: String?
    var capabilities: [String]?
}
