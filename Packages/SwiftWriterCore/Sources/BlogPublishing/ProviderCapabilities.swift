import Foundation

/// What a provider can actually do.
///
/// Providers differ more than their APIs suggest: WordPress schedules, a static site
/// commits and lets a build decide, Squarespace cannot be written to at all. The editor
/// asks a provider what it supports rather than special-casing provider names, so adding
/// a provider never means editing the UI.
public struct ProviderCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Images can be uploaded to the provider and referenced by URL.
    public static let uploadMedia = ProviderCapabilities(rawValue: 1 << 0)
    /// An already-published post can be revised in place rather than re-created.
    public static let updateExisting = ProviderCapabilities(rawValue: 1 << 1)
    /// The provider will hold a post until a future date.
    public static let schedule = ProviderCapabilities(rawValue: 1 << 2)
    public static let categories = ProviderCapabilities(rawValue: 1 << 3)
    public static let tags = ProviderCapabilities(rawValue: 1 << 4)
    /// The slug can be chosen rather than derived from the title.
    public static let customSlug = ProviderCapabilities(rawValue: 1 << 5)
    /// A standfirst separate from the body - excerpt, meta description, card text.
    public static let summary = ProviderCapabilities(rawValue: 1 << 6)
    /// One image can be marked as the post's lead image.
    public static let heroImage = ProviderCapabilities(rawValue: 1 << 7)
    /// A live post's date can be changed after the fact.
    public static let backdate = ProviderCapabilities(rawValue: 1 << 8)

    /// Every capability, in declaration order, with a name for messages.
    static let named: [(ProviderCapabilities, String)] = [
        (.uploadMedia, "media upload"),
        (.updateExisting, "updating an existing post"),
        (.schedule, "scheduling"),
        (.categories, "categories"),
        (.tags, "tags"),
        (.customSlug, "a custom slug"),
        (.summary, "a summary"),
        (.heroImage, "a hero image"),
        (.backdate, "backdating"),
    ]

    /// A readable list, for a message that has to say what will be dropped.
    public var names: [String] {
        ProviderCapabilities.named.filter { contains($0.0) }.map(\.1)
    }
}
