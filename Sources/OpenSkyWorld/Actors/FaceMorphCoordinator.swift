// The Face Morphs panel: reads and writes the expression weights of the actor
// the player is talking to. See docs/engine/coordinators.md.

import OpenSkyFormatsESM

/// What `FaceMorphCoordinator` reads from the running world.
public protocol FaceMorphWorld: AnyObject {
    /// The speaker, else the actor the Talk prompt targets.
    var faceMorphSubject: FormID? { get }
    func faceMorphPlayback(for actor: FormID) -> FaceMorphPlayback?
}

public final class FaceMorphCoordinator {
    weak var world: (any FaceMorphWorld)?

    public init() {}

    public func attach(world: any FaceMorphWorld) {
        self.world = world
    }

    private var selectedPlayback: FaceMorphPlayback? {
        guard let world, let actor = world.faceMorphSubject else { return nil }
        return world.faceMorphPlayback(for: actor)
    }
}

extension FaceMorphCoordinator: FaceMorphControlProviding {
    public var faceMorphSnapshot: FaceMorphControlSnapshot {
        guard let playback = selectedPlayback else { return .empty }
        return FaceMorphControlSnapshot(
            actor: playback.actor,
            targetNames: playback.targetNames,
            weights: playback.weights,
            pairedPaths: playback.pairedPaths,
            associationMisses: playback.misses.map { "\($0.headPart): \($0.reason)" },
            unknownTargetCount: playback.unknownTargetCount
        )
    }

    public func setFaceMorphWeight(_ weight: Float, target: String) {
        selectedPlayback?.setWeight(weight, for: target)
    }

    public func resetFaceMorphWeights() {
        selectedPlayback?.resetToBindPose()
    }
}
