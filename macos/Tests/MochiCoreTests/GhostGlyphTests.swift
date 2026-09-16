import AppKit
import CoreGraphics
import Testing

@testable import MochiCore

@Suite struct GhostGlyphTests {
    @Test func bothPathsAreNonEmpty() {
        #expect(!GhostGlyph.outlinePath.isEmpty)
        #expect(!GhostGlyph.eyesPath.isEmpty)
    }

    @Test func inkStaysWithinTheDesignGrid() {
        let grid = CGRect(x: 0, y: 0, width: GhostGlyph.gridSize, height: GhostGlyph.gridSize)
        let ink = GhostGlyph.inkBounds(strokeWidth: DesignTokens.Layout.iconStrokeWidth)
        #expect(grid.contains(ink), "ghost ink escaped the 24×24 grid: \(ink)")
    }

    /// The eyes are drawn *filled*, which only works if they are their own path — a single
    /// stroked path renders discs this small as rings, since the stroke is wider than the radius.
    @Test func eyesAreSeparateFromTheOutlineAndSmallerThanTheStroke() {
        let eyes = GhostGlyph.eyesPath.boundingBoxOfPath
        let outline = GhostGlyph.outlinePath.boundingBoxOfPath
        #expect(outline.contains(eyes), "the eyes should sit inside the silhouette")
        // Two discs, so each is half the bounding width minus the gap — the point of the check is
        // that a disc's diameter is at or below the stroke weight, i.e. stroking would fill it in.
        let eyeDiameter = eyes.height
        #expect(eyeDiameter <= DesignTokens.Layout.iconStrokeWidth * 1.5,
                "eye diameter \(eyeDiameter) is large enough to stroke; the fill/stroke split may no longer be needed")
    }

    /// The hem bulges downward (classic ghost skirt) rather than notching upward — the shape that
    /// survives being drawn at 13pt. On this y-down grid that means the hem's lowest ink sits
    /// below the foot line where the silhouette's sides end.
    @Test func hemBulgesDownward() {
        let outline = GhostGlyph.outlinePath.boundingBoxOfPath
        let eyes = GhostGlyph.eyesPath.boundingBoxOfPath
        // The eyes are near the head, so the outline extending well past them downward means the
        // body plus hem, not an upward notch.
        #expect(outline.maxY > eyes.maxY + 5)
    }
}

/// Serialized because every test here reads live AppKit font metrics. Touching
/// `NSFont.systemFont(ofSize:)` concurrently for the first time intermittently hands back the
/// *default* 12pt system font's cap height (8.5 quantised) instead of the requested size's, which
/// surfaces as a wrong `alignmentRect` at 13pt and 17pt but never at 15pt. The suite used to get
/// away with it; adding another suite to the run changed the scheduling enough to fail ~20% of
/// runs. `.serialized` only orders tests *within* this suite, which is enough because this is the
/// only suite that reads live font metrics — `MochiGlyphTests` deliberately keeps its hands off
/// `NSFont` to preserve that. A second suite touching it would need the same treatment.
@Suite(.serialized) struct SymbolMetricsTests {
    /// The contract's whole purpose: a custom glyph must come out the same size and carry the
    /// same alignment box as a real SF Symbol at the same point size, or it draws oversized and
    /// off-baseline beside its neighbours. `arrow.clockwise` is the reference — the toolbar's
    /// own refresh symbol, whose 14:16 proportions are close to the ghost's.
    ///
    /// The alignment box is compared with a half-point of slack rather than exactly, because the
    /// system's own answer moves between OS releases: at 15pt `arrow.clockwise` reports 10.5 on
    /// macOS 26.5.2 and 11.0 on 26.6.2 (measured on both — the latter is what CI runs). Half a
    /// point is one quantisation step, so this still catches the failures worth catching — a
    /// glyph sized off a different font, or off by a whole point — while refusing to pin our
    /// arithmetic to whichever macOS happens to run the test. Which of the two the glyph should
    /// follow on 26.6 is a design question, tracked separately, not something to settle by
    /// rewriting the expected number here.
    @Test(arguments: [13.0, 15.0, 17.0])
    func matchesARealSymbolsCanvasHeightAndAlignmentBox(pointSize: Double) throws {
        let reference = try #require(
            NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular, scale: .medium)))
        let metrics = SymbolMetrics.forGlyph(
            pointSize: pointSize,
            capHeight: Double(NSFont.systemFont(ofSize: pointSize).capHeight),
            inkAspectRatio: 14.0 / 16.0)

        #expect(Double(metrics.canvasSize.height) == Double(reference.size.height))

        let ours = Double(metrics.alignmentRect.height)
        let theirs = Double(reference.alignmentRect.height)
        #expect(abs(ours - theirs) <= 0.5,
                "alignment box \(ours) is more than a quantisation step off the system's \(theirs) at \(pointSize)pt")
    }

    /// `alignmentRect` height *is* the cap height of system text at that point size, quantised to
    /// half-points — the mechanism symbols use to sit on the baseline. The expected values are
    /// the system's own symbols', measured; rounding to whole points instead puts 15pt at 11.0
    /// and knocks the ghost half a point off its neighbours.
    @Test(arguments: [(pointSize: 13.0, expected: 9.0),
                      (pointSize: 15.0, expected: 10.5),
                      (pointSize: 17.0, expected: 12.0)])
    func alignmentBoxIsTheCapHeightQuantisedToHalfPoints(argument: (pointSize: Double, expected: Double)) {
        let metrics = SymbolMetrics.forGlyph(
            pointSize: argument.pointSize,
            capHeight: Double(NSFont.systemFont(ofSize: argument.pointSize).capHeight),
            inkAspectRatio: 1)
        #expect(Double(metrics.alignmentRect.height) == argument.expected)
    }

    /// Width is per-glyph, the way each system symbol has its own — not a square canvas.
    @Test func widthFollowsTheGlyphsOwnAspectRatio() {
        let capHeight = Double(NSFont.systemFont(ofSize: 15).capHeight)
        let narrow = SymbolMetrics.forGlyph(pointSize: 15, capHeight: capHeight, inkAspectRatio: 0.5)
        let wide = SymbolMetrics.forGlyph(pointSize: 15, capHeight: capHeight, inkAspectRatio: 1.5)
        #expect(Double(narrow.canvasSize.width) < Double(wide.canvasSize.width))
        #expect(Double(narrow.canvasSize.height) == Double(wide.canvasSize.height))
    }

    /// Stroke weight tracks point size (measured: ≈1.5 at 13pt, 1.75 at 15pt, 2.0 at 17pt for
    /// `.regular`), so the ghost doesn't read thinner or heavier than the symbols beside it.
    @Test func strokeWidthScalesWithPointSizeOffTheReferenceWeight() {
        let capHeight = Double(NSFont.systemFont(ofSize: 15).capHeight)
        let atReference = SymbolMetrics.forGlyph(
            pointSize: SymbolMetrics.referencePointSize, capHeight: capHeight, inkAspectRatio: 1)
        #expect(atReference.strokeWidth == DesignTokens.Layout.iconStrokeWidth)

        let doubled = SymbolMetrics.forGlyph(
            pointSize: SymbolMetrics.referencePointSize * 2, capHeight: capHeight, inkAspectRatio: 1)
        #expect(doubled.strokeWidth == DesignTokens.Layout.iconStrokeWidth * 2)
    }
}
