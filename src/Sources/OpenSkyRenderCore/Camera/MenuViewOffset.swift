// A turn and a wider view that an open menu adds to the player's camera, as the Tween
// menu does. See docs/engine/tween-menu.md#camera.

/// Added to the player's view pose and field of view each frame; zero leaves them.
nonisolated public struct MenuViewOffset: Equatable, Sendable {
    public var yaw: Float
    public var pitch: Float
    /// Added to the horizontal field of view, as the game counts its field of view.
    public var horizontalFOVDegrees: Float

    public static let none = MenuViewOffset()

    public init(yaw: Float = 0, pitch: Float = 0, horizontalFOVDegrees: Float = 0) {
        self.yaw = yaw
        self.pitch = pitch
        self.horizontalFOVDegrees = horizontalFOVDegrees
    }
}
