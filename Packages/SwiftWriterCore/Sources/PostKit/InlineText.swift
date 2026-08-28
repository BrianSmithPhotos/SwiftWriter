import Foundation

/// A run of text that may carry emphasis and links.
///
/// The value is stored as a deliberately small HTML subset - `<em>`, `<strong>`, `<a href>`
/// and `<br>` - rather than an archived `AttributedString`. That keeps `post.json` readable
/// and diffable in a plain text editor, and maps one-to-one onto every publishing target we
/// care about: Gutenberg, Ghost's Lexical, Markdown and static-site HTML.
public struct InlineText: Codable, Sendable, Equatable, ExpressibleByStringLiteral {
    /// The markup, restricted to the supported subset.
    public var html: String

    public init(html: String) { self.html = html }

    public init(stringLiteral value: String) { self.html = InlineText.escaping(value) }

    /// Builds inline text from plain text, escaping anything that would be read as markup.
    public static func plain(_ text: String) -> InlineText {
        InlineText(html: escaping(text))
    }

    public var isEmpty: Bool { plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The text with all markup removed and entities resolved. Used for summaries, search
    /// and for providers that cannot render inline formatting.
    public var plainText: String {
        var output = html.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        for (entity, character) in InlineText.entities {
            output = output.replacingOccurrences(of: entity, with: character)
        }
        return output
    }

    public init(from decoder: any Decoder) throws {
        html = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(html)
    }

    // `&amp;` must be replaced first on the way out so that an escaped ampersand in an
    // entity such as `&amp;lt;` does not get resolved twice.
    private static let entities: [(String, String)] = [
        ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#039;", "'"), ("&nbsp;", " "),
    ]

    static func escaping(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
