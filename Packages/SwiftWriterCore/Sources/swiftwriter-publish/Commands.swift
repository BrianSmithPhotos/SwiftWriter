import Foundation
import BlogPublishing
import PostKit
import WordPressProvider
import WXRImport

enum Commands {
    // MARK: - auth

    /// Authorises this machine and stores the token.
    ///
    /// The browser is opened by hand rather than driven: WordPress.com has no device flow.
    /// Everything after that - the listener, the exchange, the check that the token is for
    /// the right blog - is `WordPressSignIn`, shared with the app so the two cannot drift.
    static func auth(environment: Environment, store: KeychainTokenStore, siteID: String) async throws {
        let credentials = WordPressCredentials(
            clientID: try environment.require("WORDPRESS_CLIENT_ID"),
            clientSecret: try environment.require("WORDPRESS_CLIENT_SECRET"),
            redirectURI: try environment.require("WORDPRESS_REDIRECT_URI"),
            siteID: siteID
        )

        // A redirect this tool cannot be listened for still has a way through: approve it and
        // paste whatever the browser ended up at. Kept because it is the only recovery when
        // the registered redirect is a custom scheme nothing on the machine handles.
        guard credentials.loopbackPort != nil else {
            try await authByPaste(credentials: credentials, store: store)
            return
        }

        _ = try await WordPressSignIn.run(credentials: credentials, store: store) { url in
            print("Open this in a browser and approve it:\n")
            print(url.absoluteString)
            print("\nWaiting for the browser on \(credentials.redirectURI) ...")
            fflush(stdout)
        }
        print("Stored a token for site \(siteID) in the Keychain.")
    }

    /// The fallback for a redirect that cannot be received: print the URL, read the address back.
    private static func authByPaste(
        credentials: WordPressCredentials, store: KeychainTokenStore
    ) async throws {
        let flow = WordPressOAuth(
            clientID: credentials.clientID,
            clientSecret: credentials.clientSecret,
            redirectURI: credentials.redirectURI
        )
        let state = WordPressOAuth.makeState()
        print("Open this in a browser and approve it:\n")
        print(flow.authorizationURL(state: state, blogID: credentials.siteID).absoluteString)
        print("""

        The redirect goes to \(credentials.redirectURI), which this tool cannot receive.
        Approve it, then copy the address the browser ends up at and paste it here.
        If the browser stops without changing address, register a loopback redirect
        such as http://localhost:8722/callback instead.

        """)
        print("Redirect address: ", terminator: "")
        // stdout is fully buffered when it is not a terminal, so without this the prompt
        // sits unseen while readLine waits - which reads as a hang.
        fflush(stdout)
        guard let line = readLine(strippingNewline: true), !line.isEmpty,
              let pasted = URL(string: line.trimmingCharacters(in: .whitespaces)) else {
            throw CLIError.message("No address pasted.")
        }

        let code = try flow.code(fromRedirect: pasted, expecting: state)
        let token = try await flow.exchange(code: code)
        guard token.isUsable(forSiteID: credentials.siteID) else {
            throw CLIError.message("That token is for site \(token.siteID ?? "?"), not \(credentials.siteID).")
        }
        try store.save(token, siteID: credentials.siteID)
        print("Stored a token for site \(credentials.siteID) in the Keychain.")
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

    /// Saves the post as a draft on the blog.
    ///
    /// Refuses on a post that is already live unless it is asked for twice. An update always
    /// carries a status, so this would not merely record a draft - it would take a published
    /// post off the blog. `update` is the command for revising something live.
    static func draft(package: URL, site: WordPressSite, confirmed: Bool, dryRun: Bool) async throws {
        let loaded = try Package.read(package)
        let held = loaded.snapshot.publishRecords.first { $0.siteID == site.siteID }
        if held?.status == .published {
            try confirm(confirmed, """
                "\(loaded.snapshot.post.title)" is live. Saving it as a draft would take it \
                off the blog. To revise it in place, use: swiftwriter-publish update
                """)
        }
        try await send(
            package: package, site: site, status: .draft,
            scheduledFor: nil, displayDate: nil, dryRun: dryRun
        )
    }

    // MARK: - update

    /// Revises a post in the state it is already in.
    ///
    /// This is how alt text written after publishing reaches the blog: the photographs are
    /// unchanged, so only their descriptions are sent.
    static func update(package: URL, site: WordPressSite, dryRun: Bool) async throws {
        let loaded = try Package.read(package)
        guard let held = loaded.snapshot.publishRecords.first(where: { $0.siteID == site.siteID }),
              held.remotePostID != nil else {
            throw CLIError.message(
                "\"\(loaded.snapshot.post.title)\" has not been published to site \(site.siteID)."
            )
        }
        try await send(
            package: package, site: site, status: held.status,
            // Carried through, or updating a scheduled post would unschedule it.
            scheduledFor: held.status == .scheduled ? held.scheduledFor : nil,
            displayDate: nil, dryRun: dryRun
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
              record.remotePostID != nil else {
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

    // MARK: - pull

    /// Reads a post off the blog and writes it as a new `.swiftpost`.
    ///
    /// For a post that was written somewhere else - in wp-admin, or before this app existed -
    /// so it can be edited here from now on. The package comes back knowing its own post id,
    /// so the next `update` revises that post rather than creating a second copy of it.
    ///
    /// The conversion is the WXR importer's, reached through `RemotePostFetcher`, so a post
    /// pulled off the blog and the same post read from an export file land identically.
    static func pull(
        postID: String, fetcher: RemotePostFetcher, siteID: String,
        into directory: URL, force: Bool, dryRun: Bool
    ) async throws {
        let remote = try await fetcher.post(id: postID)
        var imported = PostImporter.makePost(
            from: remote.item, attachments: remote.attachments,
            options: ImportOptions(siteID: siteID)
        )
        let post = imported.post

        print("\(post.title)")
        print("  post \(postID) on site \(siteID), \(imported.report.status)")
        print("  \(post.blocks.count) blocks, \(imported.images.count) images")

        // A package is an editable document, so pulling over one that already exists would
        // discard whatever has been written in it. Overwriting has to be asked for.
        let name = packageName(for: post)
        let url = directory.appending(path: "\(name).\(PostPackage.fileExtension)")
        if !force, FileManager.default.fileExists(atPath: url.path) {
            throw CLIError.message(
                "\(url.lastPathComponent) already exists. Pass --force to replace it, "
                + "or use: swiftwriter-publish update \(url.lastPathComponent)"
            )
        }

        if dryRun {
            print("  dry run - would write \(url.path)")
            return
        }

        // Downloaded one at a time. A post is a few dozen photographs, and doing it in order
        // means the count on screen is the truth rather than whatever finished first.
        var fetched: [ImageID: Data] = [:]
        var failed: [String] = []
        let wanted = imported.images.compactMap { image in image.sourceURL.map { (image.id, $0) } }
        for (index, (imageID, source)) in wanted.enumerated() {
            do {
                fetched[imageID] = try await download(source)
                print("  downloaded \(index + 1)/\(wanted.count) \(source.lastPathComponent)")
            } catch {
                failed.append("\(source.lastPathComponent): \(error)")
            }
        }

        let assembled = try PackageAssembly.assemble(imported, bytes: fetched)
        imported.report = assembled.report

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PostPackage.makeFileWrapper(from: assembled.snapshot, previous: nil)
            .write(to: url, options: .atomic, originalContentsURL: nil)

        print("  wrote \(url.path)")
        print("  images \(imported.report.imageCount), \(assembled.passedThrough) kept as-is, \(assembled.resized) resized")
        if imported.report.imagesWithoutAltText > 0 {
            print("  warning: \(imported.report.imagesWithoutAltText) image(s) have no alt text")
        }
        if !imported.report.hasHeroImage { print("  warning: no hero image") }
        for failure in failed { print("  failed: \(failure)") }
    }

    /// The photograph as the blog serves it. No cache and no retry: this runs once, for one
    /// post, and a failure is reported rather than worked around.
    private static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            throw CLIError.message("HTTP \(http.statusCode)")
        }
        return data
    }

    /// What to call the file. The slug is the blog's own name for the post, so a pulled
    /// package sits beside an imported one under the same name.
    private static func packageName(for post: Post) -> String {
        if let slug = post.slug, !slug.isEmpty { return slug }
        let fromTitle = post.title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return fromTitle.isEmpty ? "untitled" : fromTitle
    }

    // MARK: - The shared path

    /// Everything the three publishing commands have in common.
    ///
    /// The decisions live in `PublishRun`, so the app publishes by the same rules. What is
    /// left here is what only a terminal does: reading the package off disk, printing
    /// progress, and writing the record back.
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

        // Every image is decided before anything is sent, so a dry run reports exactly what
        // a real one would do. Anything the blog already holds is reused: republishing is
        // the normal way to add alt text to a live post, and uploading thirty-four
        // photographs again each time would fill the media library with duplicates.
        let plan = try PublishRun.plan(post: post, held: existing) { try loaded.bytes(for: $0) }
        if plan.missingAltText > 0 {
            print("  warning: \(plan.missingAltText) image(s) have no alt text")
        }
        print("  images: \(plan.toUpload) to upload, \(plan.unchanged) unchanged, \(plan.toDescribe) to re-describe")

        if dryRun {
            print("  dry run - nothing sent")
            return
        }

        let record = try await PublishRun.send(
            plan, post: post, to: site, status: status,
            scheduledFor: scheduledFor, displayDate: displayDate,
            remotePostID: existing?.remotePostID,
            bytes: { try loaded.bytes(for: $0) }
        ) { step in
            switch step {
            case let .uploaded(fileName, remoteID): print("  uploaded \(fileName) -> \(remoteID)")
            case let .described(fileName, remoteID): print("  described \(fileName) -> \(remoteID)")
            case let .postMissing(remotePostID):
                print("  post \(remotePostID) is no longer on the blog - sending it again as a new post")
            case let .finished(result):
                print("  \(result.status.rawValue) as post \(result.remotePostID)")
                if let url = result.remoteURL { print("  \(url.absoluteString)") }
            }
        }

        try Package.writeRecords(
            loaded.snapshot.publishRecords.updating(with: record), into: package
        )
    }

    /// Refuses an action that changes the live blog unless it was asked for explicitly.
    private static func confirm(_ confirmed: Bool, _ what: String) throws {
        guard confirmed else {
            throw CLIError.message("\(what)\n\nRe-run with --yes if that is what you want.")
        }
    }
}
