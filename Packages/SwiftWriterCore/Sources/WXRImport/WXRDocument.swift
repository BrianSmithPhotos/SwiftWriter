import Foundation
import PostKit

/// One `<item>` from a WordPress WXR export, in the shape the importer needs.
///
/// A WXR export mixes posts, pages, attachments, menu items and template parts into a
/// single flat list of items, distinguished by `postType`.
public struct WXRItem: Sendable, Equatable {
    public var postID: String = ""
    public var postType: String = ""
    public var status: String = ""
    public var title: String = ""
    public var slug: String = ""
    public var link: String = ""
    public var content: String = ""
    public var excerpt: String = ""
    public var postDate: Date?
    public var attachmentURL: String?
    public var categories: [String] = []
    public var tags: [String] = []
    public var meta: [String: String] = [:]
}

public struct WXRDocument: Sendable {
    public var items: [WXRItem]

    public var posts: [WXRItem] { items.filter { $0.postType == "post" } }

    /// Attachments keyed by their post id, which is what `wp:image` blocks reference.
    public var attachmentsByID: [String: WXRItem] {
        Dictionary(
            items.filter { $0.postType == "attachment" }.map { ($0.postID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

public enum WXRParseError: Error {
    case malformed(String)
}

/// Streaming reader for a WXR export.
///
/// `XMLParser` rather than `XMLDocument` because the export runs to tens of megabytes and
/// `XMLDocument` is macOS-only - this target should stay buildable for iOS.
public enum WXRReader {
    public static func read(contentsOf url: URL) throws -> WXRDocument {
        guard let parser = XMLParser(contentsOf: url) else {
            throw WXRParseError.malformed("Could not open \(url.lastPathComponent)")
        }
        let delegate = Delegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw WXRParseError.malformed(parser.parserError?.localizedDescription ?? "unknown error")
        }
        return WXRDocument(items: delegate.items)
    }

    public static func read(xml: String) throws -> WXRDocument {
        let parser = XMLParser(data: Data(xml.utf8))
        let delegate = Delegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw WXRParseError.malformed(parser.parserError?.localizedDescription ?? "unknown error")
        }
        return WXRDocument(items: delegate.items)
    }

    /// WXR writes dates as `yyyy-MM-dd HH:mm:ss` with no offset, so the zone comes from
    /// which element it was: `_gmt` is UTC, the plain one is site-local.
    static func parseDate(_ value: String, in timeZone: TimeZone) -> Date? {
        guard value != "0000-00-00 00:00:00" else { return nil }
        let strategy = Date.ParseStrategy.fixed(
            format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            timeZone: timeZone
        )
        return try? Date(value, strategy: strategy)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var items: [WXRItem] = []

        private var current: WXRItem?
        private var text = ""
        private var path: [String] = []
        private var categoryDomain: String?
        private var metaKey: String?
        /// Both date elements are collected because their order in the file is not
        /// guaranteed and the GMT one must win regardless of which arrives first.
        private var postDateGMT: Date?
        private var postDateLocal: Date?
        private var metaValue: String?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            path.append(elementName)
            text = ""
            switch elementName {
            case "item":
                current = WXRItem()
                postDateGMT = nil
                postDateLocal = nil
            case "category":
                categoryDomain = attributes["domain"]
            case "wp:postmeta":
                metaKey = nil
                metaValue = nil
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            text += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            defer {
                path.removeLast()
                text = ""
            }
            guard current != nil else { return }
            let value = text

            switch elementName {
            case "item":
                current!.postDate = postDateGMT ?? postDateLocal
                items.append(current!)
                current = nil
            case "title": current!.title = value
            case "link": current!.link = value
            case "content:encoded": current!.content = value
            case "excerpt:encoded": current!.excerpt = value
            case "wp:post_id": current!.postID = value
            case "wp:post_type": current!.postType = value
            case "wp:status": current!.status = value
            case "wp:post_name": current!.slug = value
            // post_date_gmt is unambiguous; post_date is site-local with no offset and is
            // only a fallback for drafts, where WordPress writes a zeroed GMT date.
            case "wp:post_date_gmt": postDateGMT = WXRReader.parseDate(value, in: .gmt)
            case "wp:post_date": postDateLocal = WXRReader.parseDate(value, in: .current)
            case "wp:attachment_url": current!.attachmentURL = value
            case "wp:meta_key": metaKey = value
            case "wp:meta_value": metaValue = value
            case "wp:postmeta":
                if let key = metaKey { current!.meta[key] = metaValue ?? "" }
            case "category":
                let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { break }
                if categoryDomain == "post_tag" {
                    current!.tags.append(name)
                } else if categoryDomain == "category" {
                    current!.categories.append(name)
                }
            default:
                break
            }
        }
    }
}
