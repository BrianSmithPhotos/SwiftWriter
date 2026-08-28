import Foundation

/// Stable identity for an image within a post package.
///
/// The raw value doubles as the base filename inside `Images/`, so it is restricted to
/// characters that are safe in a filename on every platform the app runs on.
public struct ImageID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// A fresh identifier. Lowercased UUID without dashes: short, unambiguous, filename safe.
    public static func makeUnique() -> ImageID {
        ImageID(rawValue: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())!
    }

    static func isValid(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 64
            && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let id = ImageID(rawValue: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Not a valid image id: \(raw)")
            )
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

/// Stable identity for a block, so SwiftUI lists keep their place across edits.
public struct BlockID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public static func makeUnique() -> BlockID {
        BlockID(rawValue: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}
