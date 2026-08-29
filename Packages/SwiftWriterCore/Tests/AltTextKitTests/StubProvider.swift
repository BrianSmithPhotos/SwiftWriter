import Foundation
@testable import AltTextKit

/// A backend that answers from a script instead of a model, so the prompting, the tidying and the
/// retry are testable with no network, no API key and no model on the machine.
actor StubProvider: AltTextProvider {
    /// One entry per call, in order. An `Error` is thrown rather than returned.
    private var answers: [Result<String, AltTextError>]
    private(set) var prompts: [String] = []
    private(set) var fastFlags: [Bool] = []
    private(set) var availabilityChecks = 0
    private var availability: AltTextError?

    init(answers: [Result<String, AltTextError>], availability: AltTextError? = nil) {
        self.answers = answers
        self.availability = availability
    }

    init(answering text: String) {
        self.answers = [.success(text)]
    }

    func ensureAvailable(model: String) async throws {
        availabilityChecks += 1
        if let availability { throw availability }
    }

    func describe(
        model: String, instructions: String, prompt: String, imageJPEG: Data, fast: Bool
    ) async throws -> String {
        prompts.append(prompt)
        fastFlags.append(fast)
        guard !answers.isEmpty else { return "" }
        switch answers.removeFirst() {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
}
