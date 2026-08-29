import Foundation
import BlogPublishing

/// Turns category and tag names into the term ids wp/v2 requires.
///
/// The older v1.1 endpoint took names and created what was missing. v2 takes ids, so this
/// looks each name up and creates the term when the site does not have it. A post must never
/// fail to publish because a tag is new.
struct TermResolver: Sendable {
    enum Taxonomy: String, Sendable {
        case categories
        case tags
    }

    let api: WordPressAPI

    private struct Term: Decodable {
        let id: Int
        let name: String
        let slug: String
    }

    /// Ids for `names`, in the order given. Names that differ only by case or surrounding
    /// space are treated as the same term, because WordPress treats them that way too.
    func ids(for names: [String], in taxonomy: Taxonomy) async throws -> [Int] {
        var ids: [Int] = []
        var seen: Set<String> = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            ids.append(try await id(for: trimmed, in: taxonomy))
        }
        return ids
    }

    private func id(for name: String, in taxonomy: Taxonomy) async throws -> Int {
        // `search` rather than `slug`: it does not require guessing how WordPress will
        // sanitise the name, and the exact match is confirmed here rather than assumed.
        let found: [Term] = try await api.get(
            taxonomy.rawValue,
            query: [URLQueryItem(name: "search", value: name), URLQueryItem(name: "per_page", value: "100")]
        )
        if let match = found.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return match.id
        }

        do {
            let created: Term = try await api.post(taxonomy.rawValue, json: ["name": name])
            return created.id
        } catch let error as PublishError {
            // Two posts published at once can race here, and a term whose name sanitises onto
            // an existing slug is rejected outright. WordPress hands back the id it clashed
            // with, so the clash answers the question rather than failing the publish.
            if case let .providerRefused(message) = error, let existing = Self.existingTermID(in: message) {
                return existing
            }
            throw error
        }
    }

    /// The `term_exists` reply carries the winner's id in `data.term_id`.
    static func existingTermID(in message: String) -> Int? {
        guard message.contains("term_exists") else { return nil }
        guard let match = message.firstMatch(of: /"term_id"\s*:\s*(\d+)/) else { return nil }
        return Int(match.1)
    }
}
