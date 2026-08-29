import Foundation
import BlogPublishing
import PostKit
import WordPressProvider

// swiftwriter-publish - put a .swiftpost on the blog.
//
// Deliberately explicit about what goes live: `draft` is the only command that needs no
// extra confirmation, and `publish` and `backdate` both refuse without --yes. Nothing here
// runs on a schedule; every post leaves the machine because someone asked.

let usage = """
swiftwriter-publish - publish a .swiftpost to WordPress

  auth                          authorise this machine and store a token in the Keychain
  status <package>              show what is stored for a package, and the next free slot
  draft <package>               upload the images and create or update a draft
  schedule <package> [--at <ISO8601>]
                                set the post to go live, by default at the next free
                                Tuesday or Thursday 08:00. Needs --yes
  backdate <package>            date a live post back to its newest photograph. Needs --yes

Options
  --site <id>                   site id (default: WORDPRESS_SITE_ID from .env)
  --at <date>                   an explicit slot, as 2026-09-01T08:00:00
  --yes                         confirm an action that changes the live blog
  --dry-run                     say what would be sent, send nothing
"""

// MARK: - Arguments

var positional: [String] = []
var options: [String: String] = [:]
var flags: Set<String> = []
var index = 1
let raw = CommandLine.arguments
while index < raw.count {
    let argument = raw[index]
    if argument.hasPrefix("--") {
        let name = String(argument.dropFirst(2))
        if ["yes", "dry-run", "help"].contains(name) {
            flags.insert(name)
            index += 1
        } else {
            guard index + 1 < raw.count else {
                FileHandle.standardError.write(Data("Missing value for --\(name)\n".utf8))
                exit(2)
            }
            options[name] = raw[index + 1]
            index += 2
        }
    } else {
        positional.append(argument)
        index += 1
    }
}

guard let command = positional.first, !flags.contains("help") else {
    print(usage)
    exit(flags.contains("help") ? 0 : 2)
}

let dryRun = flags.contains("dry-run")
let confirmed = flags.contains("yes")

// MARK: - Running

do {
    let environment = Environment(file: Environment.findFile())
    let store = KeychainTokenStore()

    /// The site every command works against.
    func siteID() throws -> String {
        if let given = options["site"] { return given }
        return try environment.require("WORDPRESS_SITE_ID")
    }

    /// The site, with the token looked up only when a request is actually made.
    ///
    /// Reading the Keychain lazily is what lets `--dry-run` work on a machine that has
    /// never been authorised, and means a token refreshed mid-run is picked up.
    func site() throws -> WordPressSite {
        let id = try siteID()
        return WordPressSite(siteID: id, token: {
            guard let stored = try store.load(siteID: id) else {
                throw CLIError.message("No token for site \(id). Run: swiftwriter-publish auth")
            }
            return stored.accessToken
        })
    }

    func package() throws -> URL {
        guard positional.count > 1 else {
            throw CLIError.message("Which package? Pass the path to a .swiftpost.")
        }
        let url = URL(filePath: positional[1]).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError.message("No such package: \(url.path)")
        }
        return url
    }

    switch command {
    case "auth":
        try await Commands.auth(environment: environment, store: store, siteID: try siteID())

    case "status":
        try Commands.status(package: try package(), siteID: try siteID(), store: store)

    case "draft":
        try await Commands.draft(
            package: try package(), site: try site(), dryRun: dryRun
        )

    case "schedule":
        try await Commands.schedule(
            package: try package(), site: try site(),
            at: options["at"], confirmed: confirmed, dryRun: dryRun
        )

    case "backdate":
        try await Commands.backdate(
            package: try package(), site: try site(),
            confirmed: confirmed, dryRun: dryRun
        )

    default:
        throw CLIError.message("Unknown command: \(command)\n\n\(usage)")
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
