// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftWriterCore",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "PostKit", targets: ["PostKit"]),
        .library(name: "ImageKit", targets: ["ImageKit"]),
        .library(name: "WXRImport", targets: ["WXRImport"]),
        .library(name: "BlogPublishing", targets: ["BlogPublishing"]),
        .library(name: "WordPressProvider", targets: ["WordPressProvider"]),
        .executable(name: "swiftwriter-import", targets: ["swiftwriter-import"]),
        .executable(name: "swiftwriter-publish", targets: ["swiftwriter-publish"]),
    ],
    targets: [
        // PostKit is pure Foundation: the document format and its codec, with no SwiftUI
        // dependency, so the format can be tested from the command line.
        .target(name: "PostKit"),
        // ImageIO wrappers: read capture metadata, make web-ready derivatives.
        .target(name: "ImageKit", dependencies: ["PostKit"]),
        // Provider-neutral publishing: what a blog can do, and what happened when a post
        // met one. No networking and no provider here, so the rules are testable offline.
        .target(name: "BlogPublishing", dependencies: ["PostKit"]),
        // WordPress: renders blocks to Gutenberg markup, and talks to public-api.wordpress.com.
        .target(name: "WordPressProvider", dependencies: ["PostKit", "BlogPublishing"]),
        // Reads a WordPress WXR export into posts. Used to seed the test corpus.
        .target(name: "WXRImport", dependencies: ["PostKit"]),
        .executableTarget(
            name: "swiftwriter-import",
            dependencies: ["PostKit", "ImageKit", "WXRImport"]
        ),
        .executableTarget(
            name: "swiftwriter-publish",
            dependencies: ["PostKit", "BlogPublishing", "WordPressProvider"]
        ),
        .testTarget(name: "PostKitTests", dependencies: ["PostKit"]),
        .testTarget(name: "WXRImportTests", dependencies: ["WXRImport", "PostKit"]),
        .testTarget(name: "ImageKitTests", dependencies: ["ImageKit", "PostKit"]),
        .testTarget(name: "BlogPublishingTests", dependencies: ["BlogPublishing", "PostKit"]),
        // Depends on WXRImport so the renderer can be tested against the parser it inverts.
        .testTarget(
            name: "WordPressProviderTests",
            dependencies: ["WordPressProvider", "BlogPublishing", "PostKit", "WXRImport"]
        ),
    ]
)
