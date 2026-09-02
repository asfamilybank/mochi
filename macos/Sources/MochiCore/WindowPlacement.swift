import Foundation

public enum WindowPlacement {
    public static let defaultWidth: Double = 1024
    public static let defaultHeight: Double = 768

    /// The smaller of the two sizes `togglingSize` (#12's 调整窗口尺寸 hotkey) cycles between.
    public static let compactWidth: Double = 480
    public static let compactHeight: Double = 360

    public static func resolve(persisted: WindowFrame?, visibleScreens: [CGRect]) -> WindowFrame {
        guard let primaryScreen = visibleScreens.first else {
            return WindowFrame(x: 0, y: 0, width: defaultWidth, height: defaultHeight)
        }
        if let persisted, isWithinBounds(persisted, of: visibleScreens) {
            return persisted
        }
        return safeDefault(in: primaryScreen)
    }

    public static func isWithinBounds(_ frame: WindowFrame, of visibleScreens: [CGRect]) -> Bool {
        visibleScreens.contains { $0.intersects(frame.cgRect) }
    }

    public static func safeDefault(in primaryScreen: CGRect) -> WindowFrame {
        let width = min(defaultWidth, primaryScreen.width)
        let height = min(defaultHeight, primaryScreen.height)
        let x = primaryScreen.minX + (primaryScreen.width - width) / 2
        let y = primaryScreen.minY + (primaryScreen.height - height) / 2
        return WindowFrame(x: x, y: y, width: width, height: height)
    }

    /// Cycles `current` between the default size and the smaller compact size (#12's 调整窗口
    /// 尺寸 hotkey) — keeps the frame's origin corner fixed rather than centering, so repeated
    /// presses don't relocate a window the user has deliberately positioned, and clamps to
    /// `screen` so the resized window never lands partly off-screen.
    public static func togglingSize(current: WindowFrame, in screen: CGRect) -> WindowFrame {
        let isCompact = abs(current.width - compactWidth) < 0.5 && abs(current.height - compactHeight) < 0.5
        let targetWidth = isCompact ? defaultWidth : compactWidth
        let targetHeight = isCompact ? defaultHeight : compactHeight
        let width = min(targetWidth, screen.width)
        let height = min(targetHeight, screen.height)
        let x = min(max(current.x, screen.minX), screen.maxX - width)
        let y = min(max(current.y, screen.minY), screen.maxY - height)
        return WindowFrame(x: x, y: y, width: width, height: height)
    }
}
