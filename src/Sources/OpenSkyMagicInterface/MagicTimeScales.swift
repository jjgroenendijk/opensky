import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

/// How fast the world and the player run, as shares of normal speed.
nonisolated public struct MagicTimeScales: Equatable, Sendable {
    public var world: Float
    public var player: Float

    public static let normal = Self(world: 1, player: 1)

    public init(world: Float, player: Float) {
        self.world = world
        self.player = player
    }

    public var isSlowed: Bool {
        world < 1 || player < 1
    }
}
