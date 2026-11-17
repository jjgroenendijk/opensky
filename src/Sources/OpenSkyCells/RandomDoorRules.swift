// The random choices of a random door: the order it tries its destinations in,
// the door it picks, and where the player lands. See docs/engine/random-doors.md.

public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import simd

nonisolated public enum RandomDoorRules {
    /// The landing distance in front of a door with no teleport marker.
    public static let landingDistance: Float = 150

    /// `destinations` in a random order, each once.
    public static func tryOrder<Element>(
        _ destinations: [Element],
        using random: inout SplitMix64
    ) -> [Element] {
        var order = destinations
        guard order.count > 1 else { return order }
        for index in stride(from: order.count - 1, to: 0, by: -1) {
            let other = Int(random.next(upperBound: UInt64(index + 1)))
            order.swapAt(index, other)
        }
        return order
    }

    /// One of `candidates` at random; nil when there is none.
    public static func pick<Element>(
        _ candidates: [Element],
        using random: inout SplitMix64
    ) -> Element? {
        guard !candidates.isEmpty else { return nil }
        return candidates[Int(random.next(upperBound: UInt64(candidates.count)))]
    }

    /// In front of `door`, facing away from it. A record heading turns clockwise
    /// from +Y, so the front of a door at heading `z` is `(sin z, cos z)`.
    public static func landing(
        before door: PlacedReference.Placement
    ) -> PlacedReference.Placement {
        let heading = door.rotation.z
        let front = SIMD3<Float>(sinf(heading), cosf(heading), 0)
        return PlacedReference.Placement(
            position: door.position + front * landingDistance,
            rotation: SIMD3(0, 0, heading)
        )
    }

    /// The seed of one door use: the door and the world-state sequence, so a
    /// replay of the same game picks the same door.
    public static func seed(door: FormID, sequence: UInt64) -> UInt64 {
        UInt64(door.rawValue) &* SplitMix64.increment ^ sequence
    }
}
