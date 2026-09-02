import CoreGraphics

/// Mochi's bespoke vector icon set. None of these are real SF Symbol names — several,
/// the ghost glyph especially, don't exist as system symbols — so they ship as hand-drawn
/// paths instead, geometrically matching SF Symbols' conventions (even stroke weight,
/// rounded line caps, a 24×24 grid) per docs/design-language.md.
///
/// Paths are plotted on the same 24×24, y-down coordinate grid as the SVGs in
/// `design/mochi/*.dc.html` — flip the y-axis when compositing into an AppKit (y-up)
/// context.
public enum DesignIcon: CaseIterable, Sendable {
    case chevronLeft
    case chevronRight
    case refresh
    case lock
    case search
    case pin
    case ghost
    case moreHorizontal

    /// The icon's outline as an unstroked/unfilled 24×24 path — the caller strokes or fills
    /// it using `DesignTokens`' icon colors.
    public var path: CGPath {
        switch self {
        case .chevronLeft: return Self.chevronPath(pointingLeft: true)
        case .chevronRight: return Self.chevronPath(pointingLeft: false)
        case .refresh: return Self.refreshPath()
        case .lock: return Self.lockPath()
        case .search: return Self.searchPath()
        case .pin: return Self.pinPath()
        case .ghost: return Self.ghostPath()
        case .moreHorizontal: return Self.moreHorizontalPath()
        }
    }

    private static func chevronPath(pointingLeft: Bool) -> CGPath {
        let path = CGMutablePath()
        let apexX: CGFloat = pointingLeft ? 9 : 15
        let baseX: CGFloat = pointingLeft ? 15 : 9
        path.move(to: CGPoint(x: baseX, y: 6))
        path.addLine(to: CGPoint(x: apexX, y: 12))
        path.addLine(to: CGPoint(x: baseX, y: 18))
        return path
    }

    private static func refreshPath() -> CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: 12, y: 12)
        // The open circular arrow body (a near-full circle, gap left for the arrowhead).
        path.addArc(center: center, radius: 8, startAngle: -.pi * 0.85, endAngle: .pi * 0.62, clockwise: false)
        // The arrowhead tail.
        path.move(to: CGPoint(x: 4, y: 13))
        path.addLine(to: CGPoint(x: 4, y: 17))
        path.addLine(to: CGPoint(x: 8, y: 17))
        return path
    }

    private static func lockPath() -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: 6, y: 10, width: 12, height: 9), cornerWidth: 2, cornerHeight: 2)
        path.move(to: CGPoint(x: 8.5, y: 10))
        path.addLine(to: CGPoint(x: 8.5, y: 7.5))
        path.addArc(center: CGPoint(x: 12, y: 7.5), radius: 3.5, startAngle: .pi, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: 15.5, y: 10))
        return path
    }

    private static func searchPath() -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: 11 - 6.5, y: 11 - 6.5, width: 13, height: 13))
        path.move(to: CGPoint(x: 15.8, y: 15.8))
        path.addLine(to: CGPoint(x: 20, y: 20))
        return path
    }

    private static func pinPath() -> CGPath {
        // A capsule "pin head" + straight point, rotated 45° around the icon's center —
        // matches the design canvas's `rotate(45 12 12)` transform.
        let transform = CGAffineTransform(translationX: 12, y: 12)
            .rotated(by: .pi / 4)
            .translatedBy(x: -12, y: -12)
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: 9, y: 3, width: 6, height: 9), cornerWidth: 3, cornerHeight: 3, transform: transform)
        path.move(to: CGPoint(x: 12, y: 12), transform: transform)
        path.addLine(to: CGPoint(x: 12, y: 21), transform: transform)
        return path
    }

    private static func ghostPath() -> CGPath {
        let path = CGMutablePath()
        // Head: a rounded arch from the left foot up and over to the right foot.
        path.move(to: CGPoint(x: 5, y: 19))
        path.addLine(to: CGPoint(x: 5, y: 11))
        path.addArc(center: CGPoint(x: 12, y: 11), radius: 7, startAngle: .pi, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: 19, y: 19))
        // Scalloped hem: four matching lobes walking back from the right foot to the left.
        var current = CGPoint(x: 19, y: 19)
        for _ in 0..<4 {
            let next = CGPoint(x: current.x - 3.5, y: 19)
            let control = CGPoint(x: current.x - 1.75, y: 19 - 2.5)
            path.addQuadCurve(to: next, control: control)
            current = next
        }
        path.closeSubpath()
        // Eyes.
        path.addEllipse(in: CGRect(x: 9.3 - 1, y: 11.5 - 1, width: 2, height: 2))
        path.addEllipse(in: CGRect(x: 14.7 - 1, y: 11.5 - 1, width: 2, height: 2))
        return path
    }

    private static func moreHorizontalPath() -> CGPath {
        let path = CGMutablePath()
        for cx: CGFloat in [6, 12, 18] {
            path.addEllipse(in: CGRect(x: cx - 1.6, y: 12 - 1.6, width: 3.2, height: 3.2))
        }
        return path
    }
}
