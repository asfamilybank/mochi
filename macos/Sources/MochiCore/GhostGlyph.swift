import CoreGraphics

/// Mochi's only hand-drawn glyph. Every other icon the UI draws is a real SF Symbol now
/// (`chevron.left`/`chevron.right`, `arrow.clockwise`, `lock`, `magnifyingglass`, `ellipsis`,
/// `exclamationmark.triangle`) — SF Symbols has no ghost, so the mascot stays bespoke.
///
/// It is bespoke in *geometry only*: it still has to satisfy the same metric contract a system
/// symbol does, or it draws at the wrong size and sits off the baseline next to its neighbours.
/// `SymbolMetrics` below is that contract, derived by measuring the system's own symbols rather
/// than guessed — see its doc comment for the numbers.
///
/// Paths are plotted on a 24×24, y-down grid (the same convention as SwiftUI's `Path`; AppKit's
/// y-up `NSView` drawing needs a flip) and are split in two because they are painted
/// differently: the silhouette is stroked, the eyes are filled. A single stroked path — which is
/// what this used to be — renders discs this small as rings, because the stroke is wider than
/// the disc's radius.
public enum GhostGlyph {
    /// The design grid the paths below are plotted on.
    public static let gridSize: Double = 24

    // Shape parameters, kept named so the silhouette stays adjustable without re-deriving the
    // path maths. The hem bulges *downward* (`+y` on this y-down grid): a classic ghost skirt,
    // which survives being drawn at 13pt where the earlier upward-notched hem blurred into a
    // single ragged edge.
    private static let headRadius: CGFloat = 7.5
    private static let shoulderY: CGFloat = 11
    private static let footY: CGFloat = 17.5
    private static let hemBulge: CGFloat = 2.2
    private static let hemLobes = 4
    private static let eyeRadius: CGFloat = 1.05
    private static let eyeOffsetX: CGFloat = 2.7

    /// The silhouette: a rounded head arching over a scalloped hem. Stroked by the caller.
    public static var outlinePath: CGPath {
        let path = CGMutablePath()
        let leftX = 12 - headRadius
        let rightX = 12 + headRadius
        path.move(to: CGPoint(x: leftX, y: footY))
        path.addLine(to: CGPoint(x: leftX, y: shoulderY))
        path.addArc(center: CGPoint(x: 12, y: shoulderY), radius: headRadius,
                    startAngle: .pi, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: rightX, y: footY))
        let step = (rightX - leftX) / CGFloat(hemLobes)
        var current = CGPoint(x: rightX, y: footY)
        for _ in 0..<hemLobes {
            let next = CGPoint(x: current.x - step, y: footY)
            path.addQuadCurve(to: next, control: CGPoint(x: current.x - step / 2, y: footY + hemBulge))
            current = next
        }
        path.closeSubpath()
        return path
    }

    /// The two eyes. Filled by the caller, never stroked.
    public static var eyesPath: CGPath {
        let path = CGMutablePath()
        let eyeY = shoulderY + 0.5
        for centerX in [12 - eyeOffsetX, 12 + eyeOffsetX] {
            path.addEllipse(in: CGRect(x: centerX - eyeRadius, y: eyeY - eyeRadius,
                                       width: eyeRadius * 2, height: eyeRadius * 2))
        }
        return path
    }

    /// The glyph's ink extent on the 24×24 grid, stroke included — what has to be fitted into a
    /// symbol's canvas.
    public static func inkBounds(strokeWidth: Double) -> CGRect {
        outlinePath.boundingBoxOfPath
            .union(eyesPath.boundingBoxOfPath)
            .insetBy(dx: -strokeWidth / 2, dy: -strokeWidth / 2)
    }
}

/// The geometry a custom glyph must reproduce to sit correctly beside real SF Symbols, measured
/// off the system's own symbols at several point sizes and weights rather than assumed:
///
/// - **Canvas height is `pointSize + 3`.** `arrow.clockwise` is 16pt tall at 13pt, 18 at 15pt,
///   20 at 17pt.
/// - **`alignmentRect` height is the cap height of system text at the same point size** — this
///   is the mechanism symbols use to sit on the text baseline. Measured 9.0 / 10.5 / 12.0 at
///   13 / 15 / 17pt, against SF Pro's own cap heights of 9.16 / 10.57 / 11.98.
/// - **Width is per-glyph, not square.** `chevron.left` is 10×14, `ellipsis` 14×5,
///   `exclamationmark.triangle` 17×15. So width follows this glyph's own ink aspect ratio.
/// - **Ink is inset ~1pt from the canvas edge**, and the stroke weight tracks point size:
///   ≈1.5 at 13pt, 1.75 at 15pt, 2.0 at 17pt for `.regular`, i.e. linear in point size.
///
/// A 24×24 square canvas with a 24×24 `alignmentRect` — the shape this glyph used to have —
/// satisfies none of these, which is why the ghost used to draw oversized and off-baseline.
public struct SymbolMetrics: Equatable, Sendable {
    /// The image's own size, in points.
    public let canvasSize: CGSize
    /// The cap-height-tall box AppKit aligns the image by.
    public let alignmentRect: CGRect
    /// Stroke weight for the silhouette at this point size.
    public let strokeWidth: Double

    /// Padding between the canvas edge and the glyph's ink, matching what system symbols leave.
    public static let inkInset: Double = 1

    /// Stroke weight for `.regular` at the reference point size that
    /// `DesignTokens.Layout.iconStrokeWidth` is calibrated to.
    public static let referencePointSize: Double = 15

    /// - Parameters:
    ///   - pointSize: The symbol point size to match.
    ///   - capHeight: Cap height of system text at `pointSize`. Passed in rather than read here
    ///     so this stays a pure function of measurable numbers — the caller reads it from
    ///     `NSFont`, which this framework-agnostic type deliberately doesn't import.
    ///   - inkAspectRatio: The glyph's own ink width ÷ height, so width comes out per-glyph the
    ///     way each system symbol has its own.
    public static func forGlyph(pointSize: Double, capHeight: Double, inkAspectRatio: Double) -> SymbolMetrics {
        let height = (pointSize + 3).rounded()
        let width = (height * inkAspectRatio).rounded()
        // Quantised to half-points, not whole ones: the system's own symbols land on 9.0 / 10.5 /
        // 12.0 at 13 / 15 / 17pt, against SF Pro cap heights of 9.16 / 10.57 / 11.98. Rounding to
        // integers would put 15pt at 11.0 and leave the ghost half a point off its neighbours'
        // baseline.
        let alignmentHeight = (capHeight * 2).rounded() / 2
        return SymbolMetrics(
            canvasSize: CGSize(width: width, height: height),
            alignmentRect: CGRect(x: 0, y: (height - alignmentHeight) / 2,
                                  width: width, height: alignmentHeight),
            strokeWidth: DesignTokens.Layout.iconStrokeWidth * pointSize / referencePointSize
        )
    }
}
