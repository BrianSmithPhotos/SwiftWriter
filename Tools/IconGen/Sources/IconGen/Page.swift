import CoreGraphics
import IconForge

/// A post drawn as lines of text with a photograph set into the lower right.
/// That is what a SwiftWriter document is: writing with pictures in it.

/// The lines, in fractions of the artwork square. `w` is how far across the
/// square the line runs; the two that pass beside the photograph are cut short
/// so the text wraps around it the way it does on the page.
let lines: [(w: CGFloat, alpha: CGFloat)] = [
    (0.80, 0.84),
    (0.80, 0.84),
    (0.80, 0.84),
    (0.36, 0.84),
    (0.36, 0.84)
]

/// White at 84% throughout, so the gradient tints every part of the mark
/// equally and the whole thing reads as one object rather than a collage.
let inkAlpha: CGFloat = 0.84

enum Variant: String, CaseIterable {
    /// The block solid, which is what survives at 16 points.
    case plain
    /// A horizon cut out of the block in the dark end of the gradient, so the
    /// tile shows through and the block reads as a photograph rather than a slab.
    case photo
}

func roundedLine(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
}

func drawPage(_ ctx: CGContext, in rect: CGRect, palette: Palette, variant: Variant) {
    let lineHeight = rect.height * 0.082
    let pitch = rect.height * 0.158
    let left = rect.minX + rect.width * 0.10

    var bottom = rect.maxY - rect.height * 0.10 - lineHeight
    for line in lines {
        let frame = CGRect(x: left, y: bottom, width: rect.width * line.w, height: lineHeight)
        ctx.setFillColor(white(line.alpha))
        ctx.addPath(roundedLine(frame))
        ctx.fillPath()
        bottom -= pitch
    }

    // The photograph: a square in the lower right quadrant, sitting beside the
    // two short lines and clearing the bottom of the third.
    let side = rect.width * 0.38
    let block = CGRect(x: rect.minX + rect.width * 0.52, y: rect.minY + rect.height * 0.09,
                       width: side, height: side)
    ctx.setFillColor(white(inkAlpha))
    ctx.addPath(CGPath(roundedRect: block, cornerWidth: side * 0.14, cornerHeight: side * 0.14,
                       transform: nil))
    ctx.fillPath()

    if variant == .photo {
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: block, cornerWidth: side * 0.14, cornerHeight: side * 0.14,
                           transform: nil))
        ctx.clip()
        let hill = CGMutablePath()
        hill.move(to: CGPoint(x: block.minX, y: block.minY))
        hill.addLine(to: CGPoint(x: block.minX, y: block.minY + side * 0.30))
        hill.addLine(to: CGPoint(x: block.midX - side * 0.10, y: block.minY + side * 0.62))
        hill.addLine(to: CGPoint(x: block.midX + side * 0.14, y: block.minY + side * 0.34))
        hill.addLine(to: CGPoint(x: block.maxX, y: block.minY + side * 0.58))
        hill.addLine(to: CGPoint(x: block.maxX, y: block.minY))
        hill.closeSubpath()
        ctx.setFillColor(palette.bottom)
        ctx.addPath(hill)
        ctx.fillPath()
        ctx.restoreGState()
    }
}

func artwork(_ variant: Variant) -> Artwork {
    { ctx, rect, palette in drawPage(ctx, in: rect, palette: palette, variant: variant) }
}

/// What ships.
let post: Artwork = artwork(.photo)
