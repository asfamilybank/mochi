import CoreGraphics

/// Mochi's brand mark: a plump rice-cake silhouette with a small window punched out of it.
///
/// It is the menu-bar tray glyph. The tray no longer borrows `GhostGlyph`, because the tray and
/// the app icon are meant to be one identity in two sizes rather than two mascots (ADR-0015);
/// the app-icon half of that is not built yet. The ghost stays in the product, serving in-UI
/// scenes like the empty page.
///
/// Drawn as a *single filled path* under the even-odd rule: the window is a subtractive subpath,
/// not a second shape in a second colour. That is a hard requirement rather than a style choice
/// — a menu-bar template image has to be pure monochrome for AppKit to re-tint it against light
/// and dark menu bars, so the "glass panel" of the full-colour app icon becomes a hole here.
/// Nothing is stroked, so unlike `GhostGlyph` the ink extent needs no stroke term.
///
/// Plotted on the same 24×24, y-down grid as `GhostGlyph` (SwiftUI `Path` convention; AppKit's
/// y-up drawing needs a flip). The body is only *just* wider than it is tall, which is less
/// squat than a real daifuku: `SymbolMetrics` turns the ink aspect ratio into the canvas width,
/// so a wider mochi draws a wider glyph than the menu-bar icons either side of it. At these
/// radii the canvas lands on 18×18 at the tray's 15pt — the same footprint the ghost had.
public enum MochiGlyph {
    /// The design grid the paths below are plotted on.
    public static let gridSize: Double = 24

    // Shape parameters, kept named so the silhouette stays adjustable without re-deriving the
    // path maths — the same convention `GhostGlyph` uses.
    private static let centerX: CGFloat = 12
    private static let centerY: CGFloat = 12
    private static let radiusX: CGFloat = 7.7
    private static let radiusY: CGFloat = 7.6
    /// Control-point reach along each half, as a fraction of the radii. ≈0.5523 draws a true
    /// ellipse; going above it pushes the curve out towards the corners and flattens that half.
    /// So: an elliptical dome on top, a squashed-down bottom — a rice cake settled on a surface.
    /// Both halves at the low value reads as a plain ellipse; both at a high one reads as a
    /// rounded square. The asymmetry is the whole shape.
    private static let topReach: CGFloat = 0.55
    private static let bottomReach: CGFloat = 0.72

    private static let windowWidth: CGFloat = 4.6
    private static let windowHeight: CGFloat = 3.4
    private static let windowCornerRadius: CGFloat = 1.0
    /// The window sits a touch below the body's midline, where the surface would face a viewer.
    private static let windowCenterY: CGFloat = 12.4

    /// The body outline on its own. Exposed for tests and for the ink extent; painting the glyph
    /// uses `path`, which carries the cutout with it.
    public static var silhouettePath: CGPath {
        let minX = centerX - radiusX
        let maxX = centerX + radiusX
        let minY = centerY - radiusY
        let maxY = centerY + radiusY
        let topSpread = radiusX * topReach
        let topRise = radiusY * topReach
        let bottomSpread = radiusX * bottomReach
        let bottomDrop = radiusY * bottomReach

        let path = CGMutablePath()
        path.move(to: CGPoint(x: centerX, y: minY))
        path.addCurve(to: CGPoint(x: maxX, y: centerY),
                      control1: CGPoint(x: centerX + topSpread, y: minY),
                      control2: CGPoint(x: maxX, y: centerY - topRise))
        path.addCurve(to: CGPoint(x: centerX, y: maxY),
                      control1: CGPoint(x: maxX, y: centerY + bottomDrop),
                      control2: CGPoint(x: centerX + bottomSpread, y: maxY))
        path.addCurve(to: CGPoint(x: minX, y: centerY),
                      control1: CGPoint(x: centerX - bottomSpread, y: maxY),
                      control2: CGPoint(x: minX, y: centerY + bottomDrop))
        path.addCurve(to: CGPoint(x: centerX, y: minY),
                      control1: CGPoint(x: minX, y: centerY - topRise),
                      control2: CGPoint(x: centerX - topSpread, y: minY))
        path.closeSubpath()
        return path
    }

    /// The window inset, as its own path. Never painted on its own — it is the hole.
    public static var windowPath: CGPath {
        CGPath(roundedRect: CGRect(x: centerX - windowWidth / 2,
                                   y: windowCenterY - windowHeight / 2,
                                   width: windowWidth, height: windowHeight),
               cornerWidth: windowCornerRadius, cornerHeight: windowCornerRadius,
               transform: nil)
    }

    /// The whole glyph: body then window, to be filled **with the even-odd rule** so the window
    /// comes out as a hole. Filling this with the non-zero rule paints a solid blob instead.
    public static var path: CGPath {
        let path = CGMutablePath()
        path.addPath(silhouettePath)
        path.addPath(windowPath)
        return path
    }

    /// The glyph's ink extent on the 24×24 grid — what has to be fitted into a symbol's canvas.
    /// Nothing is stroked, so this is just the body's bounds.
    public static var inkBounds: CGRect {
        silhouettePath.boundingBoxOfPath
    }
}
