import Foundation

/// How an image sits in the flow of the post. Providers map these onto their own
/// alignment vocabulary; a provider that has no equivalent falls back to `full`.
public enum ImageLayout: String, Codable, Sendable, CaseIterable {
    case full
    case wide
    case inline
}

/// One item in the body of a post.
///
/// A struct wrapping a `Kind` enum, rather than a bare enum, so every block carries a
/// stable `id`. SwiftUI list reordering and selection need that identity to survive edits.
public struct Block: Identifiable, Codable, Sendable, Equatable {
    public var id: BlockID
    public var kind: Kind

    public init(id: BlockID = .makeUnique(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    public enum Kind: Sendable, Equatable {
        case paragraph(InlineText)
        case heading(level: Int, text: InlineText)
        case image(imageID: ImageID, layout: ImageLayout)
        case gallery(imageIDs: [ImageID], columns: Int)
        case quote(InlineText, attribution: String?)
        case separator
        case embed(url: URL)
    }

    /// Every image this block displays, in order. Used to find orphaned assets and to
    /// decide which images a provider needs to upload.
    public var imageIDs: [ImageID] {
        switch kind {
        case let .image(imageID, _): [imageID]
        case let .gallery(imageIDs, _): imageIDs
        default: []
        }
    }

    // MARK: - Codable

    // Written by hand rather than synthesised. The compiler would emit `{"paragraph":{"_0":…}}`
    // for an enum with associated values; a `type` discriminator with flat keys keeps
    // post.json legible, which matters because the file format is the point of this app.
    private enum CodingKeys: String, CodingKey {
        case id, type, text, level, imageID, imageIDs, layout, columns, attribution, url
    }

    private enum Kinds: String, Codable {
        case paragraph, heading, image, gallery, quote, separator, embed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(BlockID.self, forKey: .id)
        switch try container.decode(Kinds.self, forKey: .type) {
        case .paragraph:
            kind = .paragraph(try container.decode(InlineText.self, forKey: .text))
        case .heading:
            kind = .heading(
                level: try container.decode(Int.self, forKey: .level),
                text: try container.decode(InlineText.self, forKey: .text)
            )
        case .image:
            kind = .image(
                imageID: try container.decode(ImageID.self, forKey: .imageID),
                layout: try container.decodeIfPresent(ImageLayout.self, forKey: .layout) ?? .full
            )
        case .gallery:
            kind = .gallery(
                imageIDs: try container.decode([ImageID].self, forKey: .imageIDs),
                columns: try container.decodeIfPresent(Int.self, forKey: .columns) ?? 3
            )
        case .quote:
            kind = .quote(
                try container.decode(InlineText.self, forKey: .text),
                attribution: try container.decodeIfPresent(String.self, forKey: .attribution)
            )
        case .separator:
            kind = .separator
        case .embed:
            kind = .embed(url: try container.decode(URL.self, forKey: .url))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        switch kind {
        case let .paragraph(text):
            try container.encode(Kinds.paragraph, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .heading(level, text):
            try container.encode(Kinds.heading, forKey: .type)
            try container.encode(level, forKey: .level)
            try container.encode(text, forKey: .text)
        case let .image(imageID, layout):
            try container.encode(Kinds.image, forKey: .type)
            try container.encode(imageID, forKey: .imageID)
            try container.encode(layout, forKey: .layout)
        case let .gallery(imageIDs, columns):
            try container.encode(Kinds.gallery, forKey: .type)
            try container.encode(imageIDs, forKey: .imageIDs)
            try container.encode(columns, forKey: .columns)
        case let .quote(text, attribution):
            try container.encode(Kinds.quote, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(attribution, forKey: .attribution)
        case .separator:
            try container.encode(Kinds.separator, forKey: .type)
        case let .embed(url):
            try container.encode(Kinds.embed, forKey: .type)
            try container.encode(url, forKey: .url)
        }
    }
}
