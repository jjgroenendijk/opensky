// Two games on one screen: OpenSky's window on the left half and the borderless reference
// window on the right, each showing a 16:9 picture of the same size, tops in line.

import CoreGraphics

nonisolated public struct ReferenceSideBySide: Equatable, Sendable {
    /// OpenSky's window content, in AppKit screen points (origin at the bottom left).
    public var openSkyContent: CGRect
    /// The reference window, in Wine's screen points (origin at the primary screen's top left).
    public var reference: ReferenceWindowFrame

    /// `visible` is the primary screen's area without the menu bar and the Dock, and
    /// `screenHeight` its full height; `titleBar` is the height OpenSky's title bar adds.
    public init(visible: CGRect, screenHeight: CGFloat, titleBar: CGFloat) {
        let half = (visible.width / 2).rounded(.down)
        var width = half
        var height = (width * 9 / 16).rounded(.down)
        let tallest = visible.height - titleBar
        if height > tallest {
            height = tallest.rounded(.down)
            width = (height * 16 / 9).rounded(.down)
        }
        let top = visible.maxY - titleBar
        openSkyContent = CGRect(
            x: visible.minX + half - width, y: top - height, width: width, height: height
        )
        reference = ReferenceWindowFrame(
            x: Int(visible.minX + half), y: Int(screenHeight - top),
            width: Int(width), height: Int(height)
        )
    }
}
