import Foundation
import os

/// Turns a photograph and what is already known about it into one line of alt text.
///
/// The prompting, the tidying and the retry live here rather than in any backend, so a second
/// backend is one new `AltTextProvider` conformance and nothing else. That split is taken from
/// MacPhotoMaster's `AISuggestionService`, which has carried four backends without changing.
///
/// What it asks for is deliberately not what MacPhotoMaster asks for. That app writes an IPTC
/// description: up to sixty words, Latin binomials, the field mark separating two look-alike
/// species. Useful in a photo library, wrong on a web page - alt text is read aloud in place of
/// the image, and it sits directly above a caption that already names the species.
public struct AltTextService: Sendable {
    public init() {}

    private static let logger = Logger(subsystem: "photos.briansmith.swiftwriter", category: "AltText")

    static let instructions =
        "You write alt text for photographs on a photography blog. You answer with the alt text "
        + "itself and nothing else: no preamble, no label, no quotation marks, no markdown."

    /// Asks once, and once more if the answer times out or comes back unusable.
    ///
    /// The retry asks for a lower-effort answer, which is a genuinely different request rather than
    /// the same one sent twice. MacPhotoMaster also shrinks the image on the retry; that is not
    /// copied here until there is a timeout to prove it is needed, since it costs an image pipeline
    /// in a target that is otherwise pure Foundation.
    public func altText(
        for request: AltTextRequest, imageJPEG: Data, provider: any AltTextProvider, model: String
    ) async throws -> String {
        try await provider.ensureAvailable(model: model)
        let prompt = Self.prompt(for: request)

        do {
            return try await ask(provider: provider, model: model, prompt: prompt, imageJPEG: imageJPEG, fast: false)
        } catch let error as AltTextError where error == .timeout || error == .emptyResponse {
            Self.logger.log("Retrying alt text at lower effort after \(error.localizedDescription, privacy: .public)")
            return try await ask(provider: provider, model: model, prompt: prompt, imageJPEG: imageJPEG, fast: true)
        }
    }

    private func ask(
        provider: any AltTextProvider, model: String, prompt: String, imageJPEG: Data, fast: Bool
    ) async throws -> String {
        let answer = try await provider.describe(
            model: model, instructions: Self.instructions, prompt: prompt, imageJPEG: imageJPEG, fast: fast
        )
        guard let cleaned = Self.clean(answer) else { throw AltTextError.emptyResponse }
        return cleaned
    }

    /// The word limit, not a character limit: a model honours "at most 25 words" and ignores "at
    /// most 125 characters". Twenty-five words is about the 125 characters screen reader guidance
    /// settles on.
    static let wordLimit = 25

    public static func prompt(for request: AltTextRequest) -> String {
        var lines = [
            "Write alt text for this photograph, for a reader who cannot see it.",
            "One sentence, at most \(wordLimit) words, plain English, no markdown.",
            "Describe what is actually visible: the subject, what it is doing, and where it is.",
            // The failure that matters. Given the caption "North Peak trail, Mt Diablo" on an empty
            // ridge above the fog, the model wrote "a small group of hikers walks along the trail" -
            // fluent, confident and untrue. Alt text is the one place a reader cannot check.
            "Never mention a person, animal or object that is not in the frame. If you cannot tell "
                + "what something is, describe how it looks rather than naming it.",
            // Screen readers announce that it is an image before reading the text, so the words are
            // spent twice over.
            "Do not begin with \"image of\", \"photo of\" or \"a photograph of\".",
            // Alt text is read in place of the image; the equipment is not in the image.
            "Never mention the camera, the lens or the exposure settings.",
        ]
        if !request.caption.isEmpty {
            // A caption on this blog is either the subject ("Osprey, Pandion haliaetus") or the
            // place ("North Peak trail, Mt Diablo"), and the two need opposite handling: name the
            // first, and treat the second as the setting only. Told to "name the subject"
            // regardless, the model invents one that would suit the place.
            lines.append(
                "The photographer captioned it: \(request.caption). That caption names either the "
                    + "subject or only the place. If it names a kind of bird, animal, plant or "
                    + "object and one of those is in the frame, you must call it by that name - it "
                    + "is the most useful word in the sentence, so never fall back to a vaguer word "
                    + "like \"bird\" or \"flower\". If it names only a place, describe whatever is "
                    + "actually in the frame and use the place as the setting, without assuming "
                    + "anything is happening there. Either way, do not restate the caption word for "
                    + "word and do not give a scientific name.")
        }
        if !request.keywords.isEmpty {
            lines.append(
                "The photographer's keywords, naming the subject and the place: "
                    + request.keywords.joined(separator: ", ")
                    + ". Use one only if you can see what it refers to.")
        }
        return lines.joined(separator: "\n")
    }

    /// Tidies what a model actually returns into something that can go straight into an alt
    /// attribute. Every rule here is a habit models have rather than a hypothetical: fencing the
    /// answer, labelling it, quoting it, and opening with the two words that alt text must not
    /// open with.
    ///
    /// It does not truncate an over-long answer. A sentence cut mid-clause is worse to hear read
    /// aloud than a long one, so length is left for a person to judge.
    public static func clean(_ raw: String) -> String? {
        var text = stripCodeFences(raw)
        text = text.replacing(/^\s*(alt|alt[ -]?text|description)\s*[:\-]\s*/.ignoresCase(), with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only a pair, so a quotation inside a kept sentence is left alone.
        if text.count > 1, let first = text.first, let last = text.last,
           first == last, "\"'".contains(first) {
            text = String(text.dropFirst().dropLast())
        }
        text = text.replacing(/^\s*(an?\s+)?(image|photo|photograph|picture)\s+(of|showing)\s+/.ignoresCase(), with: "")
        // A model that ignored "one sentence" returns paragraphs; an alt attribute is one line.
        text = text.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // Restore the capital the "photo of" strip may have eaten.
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Ported from MacPhotoMaster, where local models were observed fencing an answer they had been
    /// told to return bare.
    private static func stripCodeFences(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        trimmed.removeFirst(3)
        if let newline = trimmed.firstIndex(of: "\n") {
            trimmed = String(trimmed[trimmed.index(after: newline)...])
        }
        if trimmed.hasSuffix("```") { trimmed.removeLast(3) }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
