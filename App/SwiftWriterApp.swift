import PostKit
import SwiftUI

@main
struct SwiftWriterApp: App {
    var body: some Scene {
        DocumentGroup { document in
            PostEditor(document: document)
        } makeDocument: { configuration, context in
            PostDocument()
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
