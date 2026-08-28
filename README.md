# SwiftWriter

A document-based blog composer for macOS 27 and iPadOS 27, built on the new SwiftUI
`Document` protocol. A nod to Windows Live Writer.

Each post is a real file on disk. It holds the title, summary, hero image, body, and the
images with their captions and alt text - and it remembers where it was published, when it
was uploaded, and when it went live.

## Status

Early. See `docs/` for the format specification.

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
| `Packages/SwiftWriterCore` | Document format, image pipeline, publishing providers, import CLI |
| `App` | The SwiftUI app for Mac and iPad |
| `project.yml` | XcodeGen spec for the app target |

## Build and test

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift test --package-path Packages/SwiftWriterCore
xcodegen generate
```

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

## Publishing

The publishing layer is provider-neutral. WordPress.com is implemented first. Ghost,
Micro.blog (Micropub), and a static-site provider are planned. Squarespace has no blog write
API, so it is supported by export rather than direct publishing.

## Configuration

Copy `.env.example` to `.env` and fill it in. `.env` is never committed.

## Licence

MIT. See `LICENSE`.
