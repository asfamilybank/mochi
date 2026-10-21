import Foundation

/// Pure geometry for Float Mode's window (#149, ADR-0035), alongside `WindowSnapping` and
/// `WindowPlacement`.
///
/// The page holds still across the mode switch: Float Mode's window is Normal Mode's with the
/// toolbar row taken off the top, and Normal Mode's page already sat below that row, so its
/// visible height — and so the page's layout — doesn't change.
///
/// While floating, the window's top edge — the page's — keeps one title bar's height clear of the
/// visible area's top. That is where the title bar grows out to on hover (#151); without the room,
/// AppKit's own `constrainFrameRect` pushes the whole window down as it grows, and the page jumps
/// with it (measured). Like iPhone Mirroring, it can't be dragged flush against the top.
public enum FloatModeFrame {
    /// The native title bar's height, which the window grows by on hover (measured).
    public static let titlebarHeight: Double = 32

    /// Normal Mode's frame → Float Mode's: the toolbar row, `toolbarHeight` tall (measured live,
    /// 52pt as of macOS 26), comes off the top.
    public static func entering(from normalFrame: WindowFrame, toolbarHeight: Double) -> WindowFrame {
        var frame = normalFrame
        frame.height -= toolbarHeight
        return frame
    }

    /// Float Mode's frame → Normal Mode's: the toolbar row goes back on top. Also what is
    /// remembered of a floating window, so a restart lands its page where it was.
    public static func leaving(_ floatFrame: WindowFrame, toolbarHeight: Double) -> WindowFrame {
        var frame = floatFrame
        frame.height += toolbarHeight
        return frame
    }

    /// Where a floating window being dragged or resized may go, given the visible areas of every
    /// display. A move that would bring the top edge within `titlebarHeight` of the top is pushed
    /// back down whole; a resize gives up the excess height and keeps its bottom edge. A move also
    /// snaps when `snaps` (the one Snap setting Normal Mode uses), with the constrained top as its
    /// top target.
    public static func constrained(
        _ frame: WindowFrame, toVisibleAreas visibleAreas: [CGRect], isResizing: Bool, snaps: Bool,
        titlebarHeight: Double = titlebarHeight
    ) -> WindowFrame {
        let roomy = visibleAreas.map {
            CGRect(x: $0.minX, y: $0.minY, width: $0.width, height: max(0, $0.height - titlebarHeight))
        }
        var result = snaps && !isResizing ? WindowSnapping.snappedFrame(frame, toEdgesOf: roomy) : frame
        guard let area = roomy.first(where: { $0.intersects(result.cgRect) }) ?? roomy.first else { return result }
        let overflow = result.y + result.height - area.maxY
        if overflow > 0 {
            if isResizing {
                result.height -= overflow
            } else {
                result.y -= overflow
            }
        }
        return result
    }
}
