# SwiftWriter

A document-based blog composer for macOS 27 and iPadOS 27, built on the new SwiftUI
`Document` protocol. A nod to Windows Live Writer.

Each post is a real file on disk. It holds the title, summary, hero image, body, and the
images with their captions and alt text - and it remembers where it was published, when it
was uploaded, and when it went live.

## Status

The format, the corpus importer, the alt-text tools and WordPress publishing all work and
are covered by tests. The app composes posts: drop photographs in, reorder them, write
around them, choose a hero. It publishes too: sign in to WordPress.com from the inspector,
then upload a draft, publish, or update what is already live.

Posts arrive two ways. `swiftwriter-import` reads a whole-blog WXR export; `swiftwriter-publish
pull` reads a single post straight off the blog, for one written somewhere other than here.

Both the Mac and the iPad publish, each signing in to WordPress.com for itself: the token
is kept on the machine that signed in and is not shared between them.

## Requirements

- macOS 27 / iPadOS 27
- Xcode 27 (macOS 27 SDK), Swift 6.4
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the app project

`xcode-select` may point at an older Xcode. Command-line builds must set:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

## Layout

| Path | Contents |
| --- | --- |
| `Packages/SwiftWriterCore` | Document format, image pipeline, alt text, publishing providers, and the three CLIs |
| `App` | The SwiftUI app for Mac and iPad |
| `Tools/IconGen` | Draws the app icon and the document fill |
| `project.yml` | XcodeGen spec for the app target |

## Build and test

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift test --package-path Packages/SwiftWriterCore
cp Local.xcconfig.example Local.xcconfig   # once, then add your team id
xcodegen generate
```

## Command line

```sh
swiftwriter-import   --input export.xml --output Corpus/ --since 2025-01-01
swiftwriter-alt      <package or directory>... [--provider ollama|apple] [--write]
swiftwriter-publish  auth | status | draft | update | schedule | backdate  <package>
swiftwriter-publish  pull <post-id> --output <dir>
```

Each tool prints its full option list with `--help`. What follows is only what is easy to
get wrong.

`swiftwriter-alt` prints and stops unless `--write` is passed, and never touches the blog.
It is the only one that takes a batch: several packages, or a directory holding them.

`swiftwriter-publish` takes one package at a time, so a batch is a shell loop. `schedule`
and `backdate` refuse without `--yes`, and so does `draft` once the post is live. `update`
does not, on the grounds that it only revises a post already on the blog - worth knowing
before scripting it. `--dry-run` reports what a real run would send. `backdate` moves a
post that has gone live back to the day its newest photograph was taken; `pull` goes the
other way, reading a post off the blog into a new `.swiftpost`.

`swiftwriter-import` reads a whole export in one run. `--dry-run` parses and reports
without fetching or writing, `--verify` reads every written package back, and `--force`
overwrites packages that already exist, discarding edits made in the app.

## Document format

Posts are packages with the extension `.swiftpost`
(UTI `photos.briansmith.swiftwriter.post`):

```
Post Title.swiftpost/
  post.json          title, summary, slug, tags, hero image, ordered content blocks
  publishing.json    per-provider upload and publish history
  Images/
    <id>.jpg         web-ready derivative
    <id>.json        alt text, caption, capture metadata, provenance
```

Publishing state is kept separate from content so that recording an upload does not modify
the post itself.

Packages open from local disk, and from iCloud Drive or Google Drive - both tested, and a
save that cannot read a photograph fails and leaves the package intact rather than writing
a hole. Other cloud file providers open too, untested. A network share is refused: saving
re-reads the images out of the package on disk, and a save that fails partway over SMB can
unlink the original without landing its replacement, which is how a post was lost. Editing
one package from two machines at once is untested - close it on one before opening it on
the other.

## Publishing

The publishing layer is provider-neutral. WordPress.com is implemented first. Ghost,
Micro.blog (Micropub), and a static-site provider are planned. Squarespace has no blog write
API, so it is supported by export rather than direct publishing.

## Configuration

Copy `.env.example` to `.env` for the WordPress client id, secret, redirect and site id, and
`Local.xcconfig.example` to `Local.xcconfig` for the signing team. Neither is committed.

## Licence

MIT. See `LICENSE`.

## Icons

The app icon and the document-page fill are drawn in code by `Tools/IconGen`,
so the shape, the palette and the sizes stay one set of numbers rather than a
PNG nobody can adjust. The tile comes from
[IconForge](https://github.com/BrianSmithPhotos/IconForge), shared with SwiftProj
and MacPhotoMaster; only `Page.swift` belongs to this app.

    swift run --package-path Tools/IconGen IconGen app App/Assets.xcassets/AppIcon.appiconset
    swift run --package-path Tools/IconGen IconGen doc App/Assets.xcassets/DocumentFill.appiconset
    swift run --package-path Tools/IconGen IconGen sheet <dir>

`sheet` lays the variants side by side with 64, 32 and 16 under each, which is
where a design either survives or does not.

The document fill draws in the Finder and in the iPadOS Simulator. On a physical
iPad running iPadOS 27 it depends on where the file sits: `.swiftpost` packages
draw their fill over an SMB share, while the same package in On My iPad falls
back to a plain page with the extension lettered on it. iCloud Drive is untested.
Apple's own `.rtfd` draws no fill on device either, but that on its own proves
nothing - iPadOS may simply ship no artwork for RTFD. Re-test after an iPadOS
update.
