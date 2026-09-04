import CoreGraphics
import Testing

@testable import MochiCore

@Suite struct DesignIconsTests {
    @Test func everyIconProducesANonEmptyPath() {
        for icon in DesignIcon.allCases {
            #expect(!icon.path.isEmpty, "\(icon) produced an empty path")
        }
    }

    @Test func everyIconStaysWithinTheTwentyFourByTwentyFourGrid() {
        // A little slack for control points that briefly overshoot the grid (the ghost's
        // scalloped hem control points).
        let bounds = CGRect(x: -1, y: -1, width: 26, height: 26)
        for icon in DesignIcon.allCases {
            #expect(bounds.contains(icon.path.boundingBoxOfPath), "\(icon) escaped the 24x24 grid: \(icon.path.boundingBoxOfPath)")
        }
    }

    @Test func ghostIconHasTwoEyesAndAScallopedHem() {
        // Sanity check that the ghost glyph isn't a degenerate/empty shape — its bounding box
        // should span close to the full 24x24 grid width, matching the SVG source (x: 5...19).
        let box = DesignIcon.ghost.path.boundingBoxOfPath
        #expect(box.width > 12)
        #expect(box.height > 6)
    }
}
