// Synthetic inputs for the perception tests (issue #202): a fake
// `PerceptionWorld` whose line of sight is a caller-supplied predicate, plus
// the observer and target literals the pass runs over.
//
// Built in code, never extracted from game data (AGENTS.md "Legal & IP
// boundary"). No renderer, no streamer, no window — the whole point of the
// `PerceptionWorld` seam.

@testable import opensky
import simd

/// A world whose geometry is one closure. `blocked` returns true for a segment
/// something stands in the way of, which is how "a target behind a wall" is
/// expressed without building a wall.
@MainActor
final class FakePerceptionWorld: PerceptionWorld {
    var observers: [PerceptionObserver]
    var targets: [PerceptionTarget]
    /// Segments this predicate answers true for are blocked.
    var blocked: (SIMD3<Float>, SIMD3<Float>) -> Bool
    /// Every line-of-sight query asked of this world, in order.
    private(set) var lineOfSightQueries: [(origin: SIMD3<Float>, destination: SIMD3<Float>)] = []

    init(
        observers: [PerceptionObserver] = [],
        targets: [PerceptionTarget] = [],
        blocked: @escaping (SIMD3<Float>, SIMD3<Float>) -> Bool = { _, _ in false }
    ) {
        self.observers = observers
        self.targets = targets
        self.blocked = blocked
    }

    func perceptionObservers() -> [PerceptionObserver] {
        observers
    }

    func perceptionTargets() -> [PerceptionTarget] {
        targets
    }

    func perceptionHasLineOfSight(
        from origin: SIMD3<Float>,
        to destination: SIMD3<Float>
    ) -> Bool {
        lineOfSightQueries.append((origin, destination))
        return !blocked(origin, destination)
    }
}

enum PerceptionFixture {
    static let guardKey = ReferenceKey.plugin(name: "perception.esm", objectID: 1)
    static let secondGuardKey = ReferenceKey.plugin(name: "perception.esm", objectID: 2)

    /// An observer standing at `feet` facing +X.
    static func observer(
        key: ReferenceKey = guardKey,
        feet: SIMD3<Float> = SIMD3(0, 0, 0),
        facing: Float = 0,
        isExterior: Bool = false,
        name: String = "Guard"
    ) -> PerceptionObserver {
        PerceptionObserver(
            key: key, feet: feet, facing: facing, isExterior: isExterior, name: name
        )
    }

    /// The player, at `feet`, moving at `gait`.
    static func target(
        feet: SIMD3<Float>,
        gait: LocomotionGait? = .walk,
        isSneaking: Bool = false
    ) -> PerceptionTarget {
        PerceptionTarget(
            key: .player,
            feet: feet,
            gait: gait,
            isSneaking: isSneaking,
            name: "Player"
        )
    }

    /// A vertical plane at `x`: any segment crossing it is blocked. The
    /// simplest thing that is genuinely a wall, and one whose behaviour a
    /// reader can check by eye.
    static func wall(atX x: Float) -> (SIMD3<Float>, SIMD3<Float>) -> Bool {
        { origin, destination in (origin.x - x) * (destination.x - x) < 0 }
    }
}
