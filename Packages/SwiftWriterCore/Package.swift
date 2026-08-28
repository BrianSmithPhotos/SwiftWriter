// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftWriterCore",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "PostKit", targets: ["PostKit"]),
    ],
    targets: [
        // PostKit is pure Foundation: the document format and its codec, with no SwiftUI
        // dependency, so the format can be tested from the command line.
        .target(name: "PostKit"),
        .testTarget(name: "PostKitTests", dependencies: ["PostKit"]),
    ]
)
