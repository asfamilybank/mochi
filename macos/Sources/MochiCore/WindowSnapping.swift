import Foundation

/// Pure geometry for magnetic edge/corner snapping (#6). Deliberately screen-only — v1 has
/// exactly one Widget window (ADR-0002), so there is no "other Widget" to snap to. Callers
/// (the AppKit window-move delegate) re-evaluate this on every drag step against the frame's
/// *current* position, which is what gives "drag past the threshold to release" its non-sticky
/// feel without any extra locked/unlocked state to track.
public enum WindowSnapping {
    /// The distance an edge snaps from. Deliberately a constant rather than a config field
    /// (ADR-0012): it is a number nobody can judge by feel, so exposing it only invites fiddling.
    /// Tuning it means editing this line and rebuilding — the privilege of an app you wrote for
    /// yourself.
    public static let snapThreshold: Double = 16

    public static func snappedFrame(
        _ frame: WindowFrame, toEdgesOf screens: [CGRect], threshold: Double = snapThreshold
    ) -> WindowFrame {
        guard let screen = screens.first(where: { $0.intersects(frame.cgRect) }) ?? screens.first else {
            return frame
        }

        var snapped = frame
        if abs(frame.x - screen.minX) <= threshold {
            snapped.x = screen.minX
        } else if abs((frame.x + frame.width) - screen.maxX) <= threshold {
            snapped.x = screen.maxX - frame.width
        }
        if abs(frame.y - screen.minY) <= threshold {
            snapped.y = screen.minY
        } else if abs((frame.y + frame.height) - screen.maxY) <= threshold {
            snapped.y = screen.maxY - frame.height
        }
        return snapped
    }
}
