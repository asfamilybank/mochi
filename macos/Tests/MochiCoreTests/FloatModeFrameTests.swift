import Foundation
import Testing

@testable import MochiCore

/// Float Mode's window geometry (#149, ADR-0035): the page holds still across the mode switch, and
/// while floating its top edge keeps a title bar's height clear of the visible area's top, so the
/// title bar grown on hover (#151) always has room.
@Suite struct FloatModeFrameTests {
    /// A 1440×900 display whose menu bar takes the top 25pt: visible area y 0…875.
    static let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
    static let toolbar = 52.0
    static let titlebar = 32.0

    @Test(arguments: [
        (x: 100.0, y: 200.0, width: 800.0, height: 600.0),
        // Already against the visible area's top in Normal Mode.
        (x: 0.0, y: 275.0, width: 640.0, height: 600.0),
    ])
    func normalToFloatAndBackIsTheOriginalFrame(_ f: (x: Double, y: Double, width: Double, height: Double)) {
        let normal = WindowFrame(x: f.x, y: f.y, width: f.width, height: f.height)

        let float = FloatModeFrame.entering(from: normal, toolbarHeight: Self.toolbar)

        // The toolbar row comes off the top; the page — everything below it — stays put.
        #expect(float == WindowFrame(x: f.x, y: f.y, width: f.width, height: f.height - 52))
        #expect(FloatModeFrame.leaving(float, toolbarHeight: Self.toolbar) == normal)
    }

    @Test func aNormalWindowAgainstTheTopAlreadyLeavesRoomOnceFloating() {
        let normal = WindowFrame(x: 0, y: 275, width: 640, height: 600)  // top at 875
        let float = FloatModeFrame.entering(from: normal, toolbarHeight: Self.toolbar)

        let constrained = FloatModeFrame.constrained(
            float, toVisibleAreas: [Self.visible], isResizing: false, snaps: false, titlebarHeight: Self.titlebar)

        #expect(constrained == float)
    }

    /// The top edge may come no higher than the visible top less a title bar; a move is pushed
    /// back down whole, a resize gives up the excess height and keeps its bottom edge.
    @Test(arguments: [
        // Within bounds: untouched.
        (y: 100.0, height: 600.0, isResizing: false, expectedY: 100.0, expectedHeight: 600.0),
        // Top exactly at 875 − 32: untouched.
        (y: 243.0, height: 600.0, isResizing: false, expectedY: 243.0, expectedHeight: 600.0),
        // Dragged 40pt past the limit: back down whole.
        (y: 283.0, height: 600.0, isResizing: false, expectedY: 243.0, expectedHeight: 600.0),
        // Top edge resized 40pt past the limit: shorter, same bottom.
        (y: 100.0, height: 783.0, isResizing: true, expectedY: 100.0, expectedHeight: 743.0),
    ])
    func dragConstraintKeepsATitlebarClearOfTheTop(
        _ row: (y: Double, height: Double, isResizing: Bool, expectedY: Double, expectedHeight: Double)
    ) {
        let frame = WindowFrame(x: 300, y: row.y, width: 800, height: row.height)

        let constrained = FloatModeFrame.constrained(
            frame, toVisibleAreas: [Self.visible], isResizing: row.isResizing, snaps: false, titlebarHeight: Self.titlebar)

        #expect(constrained == WindowFrame(x: 300, y: row.expectedY, width: 800, height: row.expectedHeight))
    }

    /// Snap's top target is the constrained top, not the visible area's own: a window dragged
    /// near the top settles a title bar below it.
    @Test(arguments: [
        // Top at 830, within snapping distance of 843 (875 − 32): snaps up to it.
        (x: 300.0, y: 230.0, snaps: true, expectedX: 300.0, expectedY: 243.0),
        // Snap turned off: stays where it was dropped.
        (x: 300.0, y: 230.0, snaps: false, expectedX: 300.0, expectedY: 230.0),
        // The other three edges snap as in Normal Mode.
        (x: 10.0, y: 10.0, snaps: true, expectedX: 0.0, expectedY: 0.0),
        (x: 630.0, y: 100.0, snaps: true, expectedX: 640.0, expectedY: 100.0),
        (x: 630.0, y: 100.0, snaps: false, expectedX: 630.0, expectedY: 100.0),
    ])
    func snapTargetsHonourTheConstraint(_ row: (x: Double, y: Double, snaps: Bool, expectedX: Double, expectedY: Double)) {
        let frame = WindowFrame(x: row.x, y: row.y, width: 800, height: 600)

        let constrained = FloatModeFrame.constrained(
            frame, toVisibleAreas: [Self.visible], isResizing: false, snaps: row.snaps, titlebarHeight: Self.titlebar)

        #expect(constrained == WindowFrame(x: row.expectedX, y: row.expectedY, width: 800, height: 600))
    }

    /// A resize never snaps, as in Normal Mode: adjusting the origin then would fight the edge the
    /// user is dragging.
    @Test func aResizeIsNotSnapped() {
        let frame = WindowFrame(x: 10, y: 10, width: 800, height: 600)

        let constrained = FloatModeFrame.constrained(
            frame, toVisibleAreas: [Self.visible], isResizing: true, snaps: true, titlebarHeight: Self.titlebar)

        #expect(constrained == frame)
    }

    /// With two displays, the limit is the one the window is on.
    @Test func theLimitIsTheTopOfTheDisplayTheWindowIsOn() {
        let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)  // no menu bar
        let frame = WindowFrame(x: 1600, y: 600, width: 800, height: 600)  // top at 1200

        let constrained = FloatModeFrame.constrained(
            frame, toVisibleAreas: [Self.visible, secondary], isResizing: false, snaps: false, titlebarHeight: Self.titlebar)

        #expect(Double(constrained.y) == 1080 - 32 - 600)
    }
}
