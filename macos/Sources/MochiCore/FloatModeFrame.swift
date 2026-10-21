import Foundation

/// Pure geometry for Float Mode's window (ADR-0036, replacing #149's), alongside `WindowSnapping`
/// and `WindowPlacement`.
///
/// Outside Normal Mode the window keeps a title bar's height of band above the page: transparent
/// until the pointer enters it, as iPhone Mirroring does. So leaving Normal Mode takes off only what
/// the toolbar row has beyond that band, and the page — which sat below the row and now sits below
/// the band — neither moves on screen nor changes height. Ghost Mode keeps the same band, never
/// shown, so switching between the two touches nothing.
///
/// The band being the window's own title bar, AppKit keeps it below the menu bar like any title
/// bar: the page can't be dragged flush against the top, with no constraint of Mochi's own.
public enum FloatModeFrame {
    /// The native title bar's height with no toolbar — the band's (measured).
    public static let titlebarHeight: Double = 32

    /// Normal Mode's frame → Float or Ghost Mode's: the toolbar row, `toolbarHeight` tall (measured
    /// live, 52pt as of macOS 26), gives way to the band.
    public static func entering(
        from normalFrame: WindowFrame, toolbarHeight: Double, titlebarHeight: Double = titlebarHeight
    ) -> WindowFrame {
        var frame = normalFrame
        frame.height -= max(0, toolbarHeight - titlebarHeight)
        return frame
    }

    /// Float or Ghost Mode's frame → Normal Mode's. Also what is remembered of a floating window, so
    /// a restart lands its page where it was.
    public static func leaving(
        _ floatFrame: WindowFrame, toolbarHeight: Double, titlebarHeight: Double = titlebarHeight
    ) -> WindowFrame {
        var frame = floatFrame
        frame.height += max(0, toolbarHeight - titlebarHeight)
        return frame
    }
}
