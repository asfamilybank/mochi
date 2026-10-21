import Foundation
import Testing

@testable import MochiCore

/// Float Mode's window geometry (ADR-0036): the window keeps a title bar's height of transparent
/// band above the page, so leaving Normal Mode takes off only what the toolbar row has beyond that,
/// and the page holds still across the switch.
@Suite struct FloatModeFrameTests {
    static let toolbar = 52.0
    static let titlebar = 32.0

    @Test(arguments: [
        (x: 100.0, y: 200.0, width: 800.0, height: 600.0),
        // Already against the visible area's top in Normal Mode.
        (x: 0.0, y: 275.0, width: 640.0, height: 600.0),
    ])
    func normalToFloatAndBackIsTheOriginalFrame(_ f: (x: Double, y: Double, width: Double, height: Double)) {
        let normal = WindowFrame(x: f.x, y: f.y, width: f.width, height: f.height)

        let float = FloatModeFrame.entering(from: normal, toolbarHeight: Self.toolbar, titlebarHeight: Self.titlebar)

        // 52 − 32 comes off the top; the bottom edge, and the page above it, stay put.
        #expect(float == WindowFrame(x: f.x, y: f.y, width: f.width, height: f.height - 20))
        #expect(FloatModeFrame.leaving(float, toolbarHeight: Self.toolbar, titlebarHeight: Self.titlebar) == normal)
    }

    /// The page starts below the band exactly where it started below the toolbar row.
    @Test func thePagesTopEdgeStaysWhereItWas() {
        let normal = WindowFrame(x: 100, y: 200, width: 800, height: 600)
        let float = FloatModeFrame.entering(from: normal, toolbarHeight: Self.toolbar, titlebarHeight: Self.titlebar)

        #expect(float.y + float.height - Self.titlebar == normal.y + normal.height - Self.toolbar)
    }

    /// Nothing to take off when there is no toolbar row taller than the band — a fullscreen
    /// window's frame is the screen's.
    @Test func aRowNoTallerThanTheBandChangesNothing() {
        let frame = WindowFrame(x: 0, y: 0, width: 800, height: 600)

        #expect(FloatModeFrame.entering(from: frame, toolbarHeight: 0, titlebarHeight: Self.titlebar) == frame)
        #expect(FloatModeFrame.leaving(frame, toolbarHeight: 0, titlebarHeight: Self.titlebar) == frame)
    }
}
