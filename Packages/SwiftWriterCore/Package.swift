// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftWriterCore",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "PostKit", targets: ["PostKit"]),
        .library(name: "ImageKit", targets: ["ImageKit"]),
        .library(name: "WXRImport", targets: ["WXRImport"]),
        .executable(name: "swiftwriter-import", targets: ["swiftwriter-import"]),
    ],
    targets: [
        // PostKit is pure Foundation: the document format and its codec, with no SwiftUI
        // dependency, so the format can be tested from the command line.
        .target(name: "PostKit"),
        // ImageIO wrappers: read capture metadata, make web-ready derivatives.
        .target(name: "ImageKit", dependencies: ["PostKit"]),
        // Reads a WordPress WXR export into posts. Used to seed the test corpus.
        .target(name: "WXRImport", dependencies: ["PostKit"]),
        .executableTarget(
            name: "swiftwriter-import",
            dependencies: ["PostKit", "ImageKit", "WXRImport"]
        ),
        .testTarget(name: "PostKitTests", dependencies: ["PostKit"]),
        .testTarget(name: "WXRImportTests", dependencies: ["WXRImport", "PostKit"]),
        .testTarget(name: "ImageKitTests", dependencies: ["ImageKit", "PostKit"]),
    ]
)
