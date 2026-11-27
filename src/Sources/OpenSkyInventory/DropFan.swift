import simd

/// How drops in a row fan out around the dropper instead of piling up
/// (docs/engine/dropped-items.md).
nonisolated public enum DropFan {
    /// How far the next drop turns, in radians, after an item of 3D radius `radius`
    /// lands `distance` ahead: wide enough that the two items do not overlap.
    public static func step(radius: Float, distance: Float) -> Float {
        guard distance > 0, radius > 0 else { return 0 }
        return 2 * asin(min(radius / distance, 1))
    }

    /// `turn` plus `step`, wrapped at a full turn.
    public static func advance(_ turn: Float, by step: Float) -> Float {
        (turn + step).truncatingRemainder(dividingBy: 2 * .pi)
    }

    /// The flat drop direction: `forward` without its height, turned
    /// counter-clockwise by `turn`. Nil for a look straight up or down.
    public static func direction(forward: SIMD3<Float>, turn: Float) -> SIMD3<Float>? {
        let flat = SIMD2(forward.x, forward.y)
        let length = simd_length(flat)
        guard length > 1e-4 else { return nil }
        let unit = flat / length
        let cosine = cos(turn)
        let sine = sin(turn)
        return SIMD3(unit.x * cosine - unit.y * sine, unit.x * sine + unit.y * cosine, 0)
    }
}

/// How far a dropped item goes: `distance` ahead, short of a wall at `free`, for an item
/// of 3D radius `radius`.
nonisolated public struct DropReach: Equatable, Sendable {
    public var distance: Float
    public var radius: Float
    public var free: Float?

    public init(distance: Float, radius: Float, free: Float? = nil) {
        self.distance = distance
        self.radius = radius
        self.free = free
    }

    /// The sweep needs a sphere of some size even for an item with no bounds.
    public var sweepRadius: Float {
        max(radius, 1)
    }

    public var travel: Float {
        min(distance, max(free ?? distance, 0))
    }

    public func stopping(at wall: Float?) -> Self {
        var reach = self
        reach.free = wall
        return reach
    }
}
