import PostKit
import SwiftUI

@main
struct SwiftWriterApp: App {
    /// One loader for the whole app. Its cache is keyed by image id, which is unique
    /// across documents, so open windows share decoded images rather than duplicating them.
    @State private var imageLoader = ImageLoader()
    @State private var altTextWriter = AltTextWriter()

    var body: some Scene {
        DocumentGroup { document in
            PostEditor(document: document)
                .environment(document)
                .environment(imageLoader)
                .environment(altTextWriter)
        } makeDocument: { configuration, context in
            // Checked before the package is read: a post on a network share cannot be saved
            // safely by the current write path. See DocumentLocation.
            try DocumentLocation.check(configuration.fileURL)
            // The configuration is retained so images still marked .existing can be read
            // back out of the saved package.
            return PostDocument(configuration: configuration)
        }

        // The iPad gets a document browser landing screen. There is no Mac equivalent -
        // DocumentGroupLaunchScene is unavailable on macOS, which opens the Finder instead.
        #if os(iOS)
        DocumentGroupLaunchScene("SwiftWriter") {
            NewDocumentButton("New Post")
        }
        #endif
    }
}
