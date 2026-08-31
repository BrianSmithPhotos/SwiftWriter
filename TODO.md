# TODO

What is known to be missing or unproven, roughly by what it would cost if ignored.

## Correctness and data

- **Save without re-reading the original package.** Images opened from disk stay as lazy
  references into the package, so every save reads them all back. Once saving no longer
  depends on the original, the network-share guard in `App/DocumentLocation.swift` can go.
- **Two machines, one package.** Untested, and the real risk now that the Mac and the iPad
  both publish. iCloud keeps conflict versions; what that does to a package is unknown.
  Until it is tested, close a post on one device before opening it on the other.
- **Offline save.** Every storage test so far had the network up. A cloud file that cannot
  be materialised should fail the save loudly - proved locally and on Google Drive, not
  proved with the network actually down.

## Editor

- **Real undo, with coalescing.** Typing currently registers one undo step per keystroke,
  so a single Undo takes back one character.
- Group a run of image blocks into a gallery.
- An editor design pass.

## Publishing

- Backdate the four live August 2026 posts to the day of their newest photograph.
- `update` revises a live post without `--yes`, while `schedule`, `backdate` and a `draft`
  over a live post all refuse without it. Decide whether that asymmetry is right.

## Import

- `SWIFTWRITER_ORIGINALS` in the import CLI, so `--originals` need not be typed each time.
- Images passed through unchanged keep the source's `.jpeg`; anything re-encoded is written
  `.jpg`, so one package holds both. Harmless - the sidecar records the name - but decide
  whether to normalise it.

## Housekeeping

- Rename `Corpus/untitled folder`.
- Two Apple Feedback reports are drafted but not filed: the `withTaskGroup` tuple
  miscompile at `-O` (with a reproducer), and iPadOS not drawing package document icons.

## Later

Phase 5 providers: Ghost, a static site over Git, Micro.blog via Micropub, and Squarespace
as a WXR export.
