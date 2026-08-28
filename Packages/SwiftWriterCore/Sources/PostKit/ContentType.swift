import UniformTypeIdentifiers

public extension UTType {
    /// The `.swiftpost` package. Declared here so the codec and the app agree on one
    /// identifier; the app exports it in its Info.plist so the Finder knows about it.
    static let swiftWriterPost = UTType(
        exportedAs: PostPackage.contentTypeIdentifier,
        conformingTo: .package
    )
}
