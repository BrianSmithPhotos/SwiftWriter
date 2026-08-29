import Foundation
import BlogPublishing
import PostKit
import WordPressProvider

enum Commands {
    // MARK: - auth

    /// Authorises this machine and stores the token.
    ///
    /// The browser is opened by hand rather than driven: WordPress.com has no device flow,
    /// and the redirect goes to a custom scheme the CLI cannot receive. So the URL is
    /// printed, and whatever the browser ends up at is pasted back. The app will do the
    /// same exchange behind `ASWebAuthenticationSession`, sharing everything below.
    static func auth(environment: Environment, store: KeychainTokenStore, siteID: String) async throws {
        let flow = WordPressOAuth(
            clientID: try environment.require("WORDPRESS_CLIENT_ID"),
            clientSecret: try environment.require("WORDPRESS_CLIENT_SECRET"),
            redirectURI: try environment.require("WORDPRESS_REDIRECT_URI")
        )
        let state = WordPressOAuth.makeState()

        print("Open this in a browser and approve it:\n")
        print(flow.authorizationURL(state: state, blogID: siteID).absoluteString)
        print("""

        The browser will then try to open swiftwriter://oauth/wordpress?code=...
        It may show an error - that is fine, the address is what matters.
        Copy that whole address and paste it here.

        """)
        print("Redirect address: ", terminator: "")
        guard let line = readLine(strippingNewline: true), !line.isEmpty,
              let redirect = URL(string: line.trimmingCharacters(in: .whitespaces)) else {
            throw CLIError.message("No address pasted.")
        }

        let code = try flow.code(fromRedirect: redirect, expecting: state)
        let token = try await flow.exchange(code: code)

        // Catches a token granted for a different blog before anything is posted to it.
        if let granted = token.siteID, granted != siteID {
            throw CLIError.message("That token is for site \(granted), not \(siteID).")
        }
        try store.save(token, siteID: siteID)
        print("Stored a token for site \(siteID) in the Keychain.")
    }

    // MARK: - status

    static func status(package: URL, siteID: String, store: KeychainTokenStore) throws {
        let loaded = try Package.read(package)
        let post = loaded.snapshot.post

        print("\(post.title)")
        print("  slug          \(post.slug ?? "-")")
        print("  blocks        \(post.blocks.count), images \(post.referencedImageIDs.count)")
        let missing = post.imagesNeedingAltText.count
        print("  alt text      \(missing == 0 ? "complete" : "\(missing) image(s) missing")")
        print("  photographed  \(post.newestCaptureDate.map(Format.day) ?? "unknown")")
        print("  token         \((try? store.load(siteID: siteID)) .map { _ in "stored" } ?? "none - run auth")")

        let records = loaded.snapshot.publishRecords.filter { $0.siteID == siteID }
        if records.isEmpty {
            print("  published     never")
        }
        for record in records {
            print("  published     \(record.status.rawValue) as post \(record.remotePostID ?? "-")")
            if let url = record.remoteURL { print("                \(url.absoluteString)") }
            if let when = record.scheduledFor { print("                goes live \(Format.moment(when))") }
            if let when = record.publishedAt { print("                dated \(Format.moment(when))") }
        }

        let taken = Set(loaded.snapshot.publishRecords.compactMap { $0.scheduledFor ?? $0.publishedAt })
        if let next = ReleaseSchedule.tuesdaysAndThursdays().nextFreeSlot(after: .now, taken: taken) {
            print("  next slot     \(Format.moment(next))")
        }
    }

    // MARK: - draft

    static func draft(package: URL, site: WordPressSite, dryRun: Bool) async throws {
        try await send(
            package: package, site: site, status: .draft,
            scheduledFor: nil, displayDate: nil, dryRun: dryRun
        )
    }

    // MARK: - schedule

    static func schedule(
        package: URL, site: WordPressSite, at: String?, confirmed: Bool, dryRun: Bool
    ) async throws {
        let loaded = try Package.read(package)
        let when: Date
        if let at {
            guard let parsed = Format.parse(at) else {
                throw CLIError.message("Could not read --at \(at). Use 2026-09-01T08:00:00.")
            }
            when = parsed
        } else {
            // Slots already spoken for by this package. Other posts' slots are not visible
            // from here, so a run is checked against the blog before it is trusted.
            let taken = Set(loaded.snapshot.publishRecords.compactMap { $0.scheduledFor })
            guard let next = ReleaseSchedule.tuesdaysAndThursdays()
                .nextFreeSlot(after: .now, taken: taken) else {
                throw CLIError.message("No free slot found.")
            }
            when = next
        }
        guard when > .now else {
            throw CLIError.message("\(Format.moment(when)) is in the past.")
        }
        try confirm(confirmed, "This will make \"\(loaded.snapshot.post.title)\" go live at \(Format.moment(when)).")
        try await send(
            package: package, site: site, status: .scheduled,
            scheduledFor: when, displayDate: nil, dryRun: dryRun
        )
    }

    // MARK: - backdate

    /// Moves a live post back to the day its newest photograph was taken.
    ///
    /// Only for a post that has actually gone live: while it is still scheduled, that same
    /// date field is the release date, and setting it back would publish the post at once.
    static func backdate(package: URL, site: WordPressSite, confirmed: Bool, dryRun: Bool) async throws {
        let loaded = try Package.read(package)
        let post = loaded.snapshot.post
        guard let record = loaded.snapshot.publishRecords.first(where: { $0.siteID == site.siteID }),
              let remotePostID = record.remotePostID else {
            throw CLIError.message("\"\(post.title)\" has not been published to site \(site.siteID).")
        }
        guard record.status == .published else {
            throw CLIError.message(
                "\"\(post.title)\" is \(record.status.rawValue), not live. "
                + "Backdating it now would set its release date instead. Wait until it has gone live."
            )
        }
        guard let shot = post.newestCaptureDate else {
            throw CLIError.message("\"\(post.title)\" has no photograph with a capture date.")
        }
        try confirm(confirmed, """
            This will date "\(post.title)" back to \(Format.moment(shot)).
            The blog dates its URLs, so the permalink moves. WordPress records the old date \
            and redirects the previous address, but the canonical URL changes.
            """)
        try await send(
            package: package, site: site, status: .published,
            scheduledFor: nil, displayDate: shot, dryRun: dryRun
        )
    }

    // MARK: - The shared path

    private static func send(
        package: URL, site: WordPressSite, status: PublishStatus,
        scheduledFor: Date?, displayDate: Date?, dryRun: Bool
    ) async throws {
        let loaded = try Package.read(package)
        let post = loaded.snapshot.post
        let existing = loaded.snapshot.publishRecords.first { $0.siteID == site.siteID }

        print("\(post.title)")
        print("  \(post.blocks.count) blocks, \(post.referencedImageIDs.count) images -> site \(site.siteID) as \(status.rawValue)")
        if let scheduledFor { print("  goes live \(Format.moment(scheduledFor))") }
        if let displayDate { print("  dated \(Format.moment(displayDate))") }
        let missing = post.imagesNeedingAltText.count
        if missing > 0 { print("  warning: \(missing) image(s) have no alt text") }

        if dryRun {
            print("  dry run - nothing sent")
            return
        }

        try await site.authenticate()

        // Media first: the body cannot be rendered until every image has a remote URL.
        var media: [ImageID: RemoteMedia] = [:]
        for imageID in post.referencedImageIDs {
            guard let asset = post.assets[imageID] else {
                throw CLIError.message("Image \(imageID.rawValue) has no sidecar.")
            }
            let data = try loaded.bytes(for: imageID)
            let uploaded = try await site.uploadMedia(MediaUpload(
                imageID: imageID,
                fileName: asset.fileName,
                mimeType: Package.mimeType(for: asset.fileName),
                data: data,
                altText: asset.altText.isEmpty ? nil : asset.altText,
                caption: asset.caption?.html
            ))
            media[imageID] = uploaded
            print("  uploaded \(asset.fileName) -> \(uploaded.remoteID)")
        }

        let result = try await site.publish(PublishRequest(
            post: post, status: status, scheduledFor: scheduledFor, displayDate: displayDate,
            media: media, remotePostID: existing?.remotePostID
        ))

        let record = PublishRecord.make(
            from: result, providerID: WordPressSite.providerID, siteID: site.siteID,
            contentHash: try post.contentHash(), scheduledFor: scheduledFor
        )
        try Package.writeRecords(
            loaded.snapshot.publishRecords.updating(with: record), into: package
        )

        print("  \(result.status.rawValue) as post \(result.remotePostID)")
        if let url = result.remoteURL { print("  \(url.absoluteString)") }
    }

    /// Refuses an action that changes the live blog unless it was asked for explicitly.
    private static func confirm(_ confirmed: Bool, _ what: String) throws {
        guard confirmed else {
            throw CLIError.message("\(what)\n\nRe-run with --yes if that is what you want.")
        }
    }
}
