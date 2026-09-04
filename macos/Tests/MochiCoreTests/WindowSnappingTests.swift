import Foundation
import Testing

@testable import MochiCore

@Suite struct WindowSnappingTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func snapsToLeftEdgeWhenWithinThreshold() {
        let frame = WindowFrame(x: 5, y: 100, width: 800, height: 600)

        let snapped = WindowSnapping.snappedFrame(frame, toEdgesOf: [screen], threshold: 16)

        #expect(snapped.x == 0)
        #expect(snapped.y == 100)
    }

    @Test func snapsToRightEdgeWhenWithinThreshold() {
        let frame = WindowFrame(x: 635, y: 100, width: 800, height: 600)

        let snapped = WindowSnapping.snappedFrame(frame, toEdgesOf: [screen], threshold: 16)

        #expect(snapped.x == Double(screen.maxX) - frame.width)
    }

    @Test func snapsToTopEdgeWhenWithinThreshold() {
        let frame = WindowFrame(x: 100, y: 292, width: 800, height: 600)

        let snapped = WindowSnapping.snappedFrame(frame, toEdgesOf: [screen], threshold: 16)

        #expect(snapped.y == Double(screen.maxY) - frame.height)
    }

    @Test func snapsToBottomEdgeWhenWithinThreshold() {
        let frame = WindowFrame(x: 100, y: 5, width: 800, height: 600)

        let snapped = WindowSnapping.snappedFrame(frame, toEdgesOf: [screen], threshold: 16)

        #expect(snapped.y == 0)
    }

    @Test func snapsToCornerWhenBothEdgesAreWithinThreshold() {
        let frame = WindowFrame(x: 3, y: 4, width: 800, height: 600)

        let snapped = WindowSnapping.snappedFrame(frame, toEdgesOf: [screen], threshold: 16)

        #expect(snapped.x == 0)
        #expect(snapped.y == 0)
    }

    @Test func doesNotSnapWhenOutsideThreshold() {
        let frame = WindowFrame(x: 100, y: 100, width: 800, height: 600)

        let snapped = WindowSnapping.snappedFrame(frame, toEdgesOf: [screen], threshold: 16)

        #expect(snapped == frame)
    }

    @Test func releasesOnceDraggedBackBeyondThreshold() {
        let stillSnapped = WindowSnapping.snappedFrame(
            WindowFrame(x: 15, y: 100, width: 800, height: 600), toEdgesOf: [screen], threshold: 16)
        let released = WindowSnapping.snappedFrame(
            WindowFrame(x: 17, y: 100, width: 800, height: 600), toEdgesOf: [screen], threshold: 16)

        #expect(stillSnapped.x == 0)
        #expect(released.x == 17)
    }

    @Test func ignoresAScreenTheFrameIsNotNear() {
        // v1 has exactly one Widget window (ADR-0002); a second CGRect passed here is always
        // another screen, never another Widget — there is no "snap to other Widgets" concept.
        let farScreen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let frame = WindowFrame(x: 635, y: 100, width: 800, height: 600)

        let snapped = WindowSnapping.snappedFrame(frame, toEdgesOf: [screen, farScreen], threshold: 16)

        #expect(snapped.x == Double(screen.maxX) - frame.width)
    }

    @Test func usesScreenThatIntersectsTheFrameWhenMultipleScreensExist() {
        let secondScreen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let frame = WindowFrame(x: 1450, y: 5, width: 800, height: 600)

        let snapped = WindowSnapping.snappedFrame(frame, toEdgesOf: [screen, secondScreen], threshold: 16)

        #expect(snapped.y == Double(secondScreen.minY))
    }

    @Test func fallsBackToUnsnappedFrameWhenNoScreensAreReported() {
        let frame = WindowFrame(x: 5, y: 5, width: 800, height: 600)

        let snapped = WindowSnapping.snappedFrame(frame, toEdgesOf: [], threshold: 16)

        #expect(snapped == frame)
    }

    @Test func theSnapThresholdIsAPositiveValue() {
        #expect(WindowSnapping.snapThreshold > 0)
    }
}
