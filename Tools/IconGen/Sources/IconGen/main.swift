import Foundation
import IconForge

// Run from the repo root:
//
//   swift run --package-path Tools/IconGen IconGen app App/Assets.xcassets/AppIcon.appiconset
//   swift run --package-path Tools/IconGen IconGen doc App/Assets.xcassets/DocumentFill.appiconset
//   swift run --package-path Tools/IconGen IconGen sheet <dir>
//
// The tile - the teal, the squircle, the light and the shadow - comes from
// IconForge, which SwiftProj and MacPhotoMaster draw their icons with too. Only
// Page.swift belongs to this app, which is what makes them read as a family.

let args = CommandLine.arguments
guard args.count > 2, ["app", "doc", "sheet"].contains(args[1]) else {
    print("usage: IconGen app <AppIcon.appiconset> | doc <DocumentFill.appiconset> | sheet <dir>")
    exit(1)
}

let out = URL(fileURLWithPath: args[2])

switch args[1] {
case "app":
    try AssetCatalog.writeAppIconSet(at: out, palette: .teal, artwork: post)
    print("wrote the app icon to \(out.path)")

case "doc":
    try AssetCatalog.writeDocumentFillSet(at: out, palette: .teal, artwork: post)
    print("wrote the document fill to \(out.path)")

default:
    // A tile per variant, with the small sizes under each - which is where a
    // design either survives or does not.
    let entries = Variant.allCases.map {
        ContactSheet.Entry(name: $0.rawValue, artwork: artwork($0))
    }
    try Icon.writePNG(ContactSheet.render(entries, palette: .teal, columns: 2),
                      to: out.appendingPathComponent("icon-variants.png"))
    print("wrote icon-variants.png to \(out.path)")
}
