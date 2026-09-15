import AppKit
import CoreGraphics
import Testing

@testable import MochiCore

@Suite struct MochiGlyphTests {
    @Test func everyPathIsNonEmpty() {
        #expect(!MochiGlyph.silhouettePath.isEmpty)
        #expect(!MochiGlyph.windowPath.isEmpty)
        #expect(!MochiGlyph.path.isEmpty)
    }

    @Test func inkStaysWithinTheDesignGrid() {
        let grid = CGRect(x: 0, y: 0, width: MochiGlyph.gridSize, height: MochiGlyph.gridSize)
        #expect(grid.contains(MochiGlyph.inkBounds),
                "mochi ink escaped the 24×24 grid: \(MochiGlyph.inkBounds)")
    }

    /// The glyph is one filled path whose window is a *subtractive* subpath, so the combined
    /// path's extent is the silhouette's — a window drawn outside it would silently widen this.
    @Test func theCombinedPathIsBoundedByTheSilhouette() {
        let combined = MochiGlyph.path.boundingBoxOfPath
        let silhouette = MochiGlyph.silhouettePath.boundingBoxOfPath
        #expect(combined == silhouette)
    }

    /// Even-odd fill only reads as a cutout while the window sits strictly inside the body. The
    /// margin check is what stops the window from being nudged out to a spot where the rounded
    /// silhouette has already curved away, leaving a notch in the outline instead of a hole.
    @Test func theWindowSitsWellInsideTheSilhouette() {
        let window = MochiGlyph.windowPath.boundingBoxOfPath
        let silhouette = MochiGlyph.silhouettePath.boundingBoxOfPath
        #expect(silhouette.contains(window), "the window escaped the mochi body")
        let margin = 2.0
        #expect(Double(window.minX - silhouette.minX) >= margin)
        #expect(Double(silhouette.maxX - window.maxX) >= margin)
        #expect(Double(window.minY - silhouette.minY) >= margin)
        #expect(Double(silhouette.maxY - window.maxY) >= margin)
    }

    /// A status item draws its image at that image's own size inside a 22pt menu bar, so the
    /// canvas has to fit — the check ADR-0013 added after a 24×24 ghost overflowed it.
    ///
    /// The exact 18×18 is pinned on top of that. It is *not* a rule that glyph canvases are
    /// square — ADR-0013 is explicit that width follows each glyph's own ink aspect ratio, and
    /// the ghost's is 17×18. It is this glyph's specified footprint (#50), and pinning it means
    /// a shape edit that widens the body past the menu-bar icons either side of it has to come
    /// here and say so deliberately.
    @Test func trayMetricsFitTheMenuBar() {
        let metrics = trayMetrics()
        let menuBarThickness = Double(NSStatusBar.system.thickness)
        #expect(Double(metrics.canvasSize.height) <= menuBarThickness)
        #expect(Double(metrics.canvasSize.width) <= menuBarThickness)
        #expect(Double(metrics.canvasSize.height) == 18)
        #expect(Double(metrics.canvasSize.width) == 18)
    }

    /// The cutout has a band to stay in, not just a floor. Below roughly 3pt drawn it closes up
    /// into a smudge on a non-Retina display; above about a third of the body's width it stops
    /// reading as a detail set into a mochi and starts reading as a ring.
    @Test func theWindowStaysLegibleWithoutSwallowingTheBody() {
        let scale = trayMetrics().fitScale(forInk: MochiGlyph.inkBounds)
        let window = MochiGlyph.windowPath.boundingBoxOfPath
        #expect(Double(window.width) * scale >= 3)
        #expect(Double(window.height) * scale >= 3)

        let widthShare = Double(window.width) / Double(MochiGlyph.inkBounds.width)
        #expect(widthShare >= 0.25 && widthShare <= 0.32,
                "the window is \(widthShare) of the body's width; design-language.md asks for 25–30%")
    }

    /// The image has to carry a *cap-height* alignment box, not one the size of its canvas —
    /// that is the mechanism a glyph sits on the text baseline by, and the 24×24 box the ghost
    /// used to ship is exactly what ADR-0013 had to correct.
    @Test func trayMetricsCarryACapHeightAlignmentBox() {
        let metrics = trayMetrics()
        let box = metrics.alignmentRect
        #expect(Double(box.height) < Double(metrics.canvasSize.height))
        #expect(Double(box.minY) == (Double(metrics.canvasSize.height) - Double(box.height)) / 2,
                "the alignment box should sit centred in the canvas")
    }

    /// Cap height of 15pt system text, fed in as *input* — `SymbolMetricsTests` is what checks
    /// this is the system's real value, and nothing here asserts against it. It is a literal
    /// rather than an `NSFont` read on purpose: first-touching AppKit's font metrics from several
    /// suites at once, which Swift Testing runs in parallel, was observed handing back the
    /// default 12pt font's cap height, and keeping this suite off `NSFont` is what lets
    /// `SymbolMetricsTests` fix that flake with `.serialized` alone.
    private static let capHeightAt15pt = 10.5

    private func trayMetrics() -> SymbolMetrics {
        let ink = MochiGlyph.inkBounds
        return SymbolMetrics.forGlyph(
            pointSize: 15,
            capHeight: Self.capHeightAt15pt,
            inkAspectRatio: Double(ink.width / ink.height))
    }
}
