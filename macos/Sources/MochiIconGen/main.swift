import AppKit
import CoreGraphics
import Foundation
import MochiCore

/// Renders the **placeholder** app-icon artwork from `MochiGlyph`, so the packaging chain has
/// something to carry while the real artwork is produced (ADR-0014: a generation model draws the
/// master, a person exports it through Icon Composer — neither step has a CLI).
///
/// It is not a one-shot script that gets deleted afterwards. The mochi outline will keep moving
/// as the real artwork settles, and this is what lets the placeholder and the menu-bar glyph be
/// re-derived from the same paths instead of redrawn by hand — which is the only mechanical part
/// of the tray-versus-icon consistency check ADR-0015 otherwise leaves to the eye.
///
/// Usage, from the `macos/` directory:
///
///     swift run MochiIconGen [output.png]
enum IconGen {
    /// Icon Composer masks and shades the artwork itself, so this draws the subject only: no
    /// rounded-rect background plate, no outer shadow, and enough padding that nothing lands near
    /// an edge the mask will round off.
    static let canvasSide: Double = 1024
    static let inkShareOfCanvas: Double = 0.72

    /// Placeholder-only, deliberately not a `DesignTokens` entry: these are artwork colours for a
    /// stand-in, not interface tokens, and the real values arrive as pixels in the master image.
    /// The warm cream comes from design-language.md's "soft neutral off-white / warm cream".
    static let bodyColor = NSColor(srgbRed: 0.964, green: 0.945, blue: 0.914, alpha: 1)
    /// The window, however, *is* a token: design-language.md pins it to the default accent.
    static let windowColor = NSColor(rgba: DesignTokens.defaultAccent.rgba)

    static func render() -> NSBitmapImageRep {
        let side = Int(canvasSide)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { fatalError("could not allocate a \(side)×\(side) bitmap") }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            fatalError("could not draw into the bitmap")
        }
        NSGraphicsContext.current = context

        // `MochiGlyph` is plotted y-down; flip so the dome ends up on top.
        let cg = context.cgContext
        cg.translateBy(x: 0, y: canvasSide)
        cg.scaleBy(x: 1, y: -1)

        let ink = MochiGlyph.inkBounds
        let scale = canvasSide * inkShareOfCanvas / max(Double(ink.width), Double(ink.height))
        cg.translateBy(x: (canvasSide - Double(ink.width) * scale) / 2,
                       y: (canvasSide - Double(ink.height) * scale) / 2)
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: -ink.minX, y: -ink.minY)

        // The body is solid here, not punched through: the tray glyph subtracts the window to
        // stay monochrome, but the app icon fills it with the accent instead.
        bodyColor.setFill()
        NSBezierPath(cgPath: MochiGlyph.silhouettePath).fill()
        windowColor.setFill()
        NSBezierPath(cgPath: MochiGlyph.windowPath).fill()

        return rep
    }
}

private extension NSColor {
    convenience init(rgba: DesignTokens.RGBA) {
        self.init(srgbRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
    }
}

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "App/Icon/mochi-placeholder-1024.png"

guard let data = IconGen.render().representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
do {
    try data.write(to: URL(fileURLWithPath: output))
    print("OK \(output)")
} catch {
    FileHandle.standardError.write(Data("failed to write \(output): \(error)\n".utf8))
    exit(1)
}
