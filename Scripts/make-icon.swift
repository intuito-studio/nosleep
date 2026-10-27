// Draws the two layers of Resources/AppIcon.icon from Sources/NoSleep/CatGlyph.swift:
// the cat's head, and its eyes above it, each white on a clear 1024 pt canvas.
// Run again only when the cat changes:
//
//   make icon
//
// Colour, glass and shadow live in AppIcon.icon/icon.json, so macOS 26 and
// later can render the layers as Liquid Glass and recolour them for dark,
// clear and tinted icons. Scripts/bundle.sh compiles the bundle with actool.
import AppKit

@main
struct MakeIcon {
    static func main() throws {
        let assets = URL(fileURLWithPath: CommandLine.arguments[1])
        try layer { rect in
            CatGlyph.awake.draw(in: rect, head: .white, eyes: .white)
        }
        .write(to: assets.appendingPathComponent("head.png"))
        // The eyes with the pupils cut out, so the head shows through them.
        try layer { rect in
            NSColor.white.setFill()
            let transform = CatGlyph.transform(to: rect)
            for eye in CatGlyph.eyes { transform.transform(NSBezierPath(ovalIn: eye)).fill() }
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            for eye in CatGlyph.eyes { transform.transform(CatGlyph.pupil(in: eye)).fill() }
        }
        .write(to: assets.appendingPathComponent("eyes.png"))
        print(assets.path)
    }

    /// The cat 620 pt wide, centred on the 1024 pt canvas.
    static func layer(_ draw: @escaping (NSRect) -> Void) throws -> Data {
        let pixels: CGFloat = 1024
        let width: CGFloat = 620
        let height = width * CatGlyph.size.height / CatGlyph.size.width
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(pixels), pixelsHigh: Int(pixels), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // CatGlyph draws top-down; a flipped image keeps it the right way up.
        let image = NSImage(size: NSSize(width: pixels, height: pixels), flipped: true) { _ in
            draw(NSRect(x: (pixels - width) / 2, y: (pixels - height) / 2 + 20, width: width, height: height))
            return true
        }
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
}
