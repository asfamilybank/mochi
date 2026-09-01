import Foundation

public struct WindowFrame: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

extension WindowFrame {
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    init(cgRect: CGRect) {
        self.init(x: cgRect.origin.x, y: cgRect.origin.y, width: cgRect.width, height: cgRect.height)
    }
}

public struct WindowState: Equatable {
    public var frame: WindowFrame
    public var zoom: Double

    public init(frame: WindowFrame, zoom: Double) {
        self.frame = frame
        self.zoom = zoom
    }
}
