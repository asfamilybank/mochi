import Foundation

public enum WindowPlacement {
    public static let defaultWidth: Double = 1024
    public static let defaultHeight: Double = 768

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
}
