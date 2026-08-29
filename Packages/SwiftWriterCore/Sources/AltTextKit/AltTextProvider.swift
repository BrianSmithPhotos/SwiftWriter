import Foundation

/// The failure modes every backend maps its own errors onto, so the retry in `AltTextService`
/// behaves the same whichever one is in use. Ported from MacPhotoMaster's `AISuggestionError`,
/// where the same three cases proved to be the ones worth distinguishing: `timeout` and
/// `emptyResponse` are retried once, and `provider` - a missing model, a network failure, an HTTP
/// error - is surfaced as it is, because a second identical request will fail the same way.
public enum AltTextError: Error, LocalizedError, Equatable {
    case timeout
    case emptyResponse
    case provider(String)

    public var errorDescription: String? {
        switch self {
        case .timeout: "The model took too long to answer"
        case .emptyResponse: "The model answered with nothing usable"
        case .provider(let message): message
        }
    }
}

/// A backend that can look at one photograph and describe it.
///
/// One method, so adding Apple's on-device model, Ollama or a cloud model means writing one
/// conformance rather than touching the prompt, the parsing or the retry.
public protocol AltTextProvider: Sendable {
    /// Called before every request. Throws `.provider` when the model is missing, cannot accept an
    /// image, or - for the on-device model - when Apple Intelligence is not ready on this machine.
    /// Checking up front is what turns "it silently produced nothing" into a sentence the user can act on.
    func ensureAvailable(model: String) async throws

    /// - Parameter fast: ask for a lower-effort answer. Used only by the retry.
    func describe(
        model: String, instructions: String, prompt: String, imageJPEG: Data, fast: Bool
    ) async throws -> String
}
