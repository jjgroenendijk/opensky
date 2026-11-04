// The game's `[Display] fMeshLODLevel1FadeDist` and `fMeshLODLevel2FadeDist`: past
// each distance a `BSLODTriShape` draws its next coarser level.

import simd

nonisolated public struct MeshLODDistances: Equatable, Sendable {
    public static let off = Self(level1: 0, level2: 0)

    /// 0 never switches to that level.
    public let level1: Float
    public let level2: Float

    public init(level1: Double, level2: Double) {
        func distance(_ value: Double) -> Float {
            value.isFinite && value > 0 ? Float(min(value, 1e7)) : 0
        }
        self.level1 = distance(level1)
        self.level2 = distance(level2)
    }

    public var isOn: Bool {
        level1 > 0 || level2 > 0
    }

    /// 0 full detail, 1, or 2.
    public func level(distance: Float) -> Int {
        if level2 > 0, distance >= level2 {
            return 2
        }
        return level1 > 0 && distance >= level1 ? 1 : 0
    }
}
