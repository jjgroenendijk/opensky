// The Death & Ragdoll panel and the corpse search. The panel trigger goes
// through the same `RagdollRuntime.trigger(_:)` a death reaches, so the sidebar
// verifies that route rather than adding a second one.

import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

extension RagdollCoordinator: RagdollControlProviding {
    public var ragdollStatsSnapshot: RagdollStatsSnapshot {
        runtime?.world.statsSnapshot ?? RagdollStatsSnapshot()
    }

    /// False without a runtime, without a selected actor, or when its
    /// skeleton carries no bodies.
    @discardableResult
    public func triggerRagdoll() -> Bool {
        guard let runtime, let key = world?.selectedRagdollActor else { return false }
        return runtime.trigger(key)
    }

    public func setRagdollFrozen(_ frozen: Bool) {
        runtime?.isFrozen = frozen
    }

    public func setRagdollSelfCollision(_ enabled: Bool) {
        runtime?.isSelfCollisionEnabled = enabled
    }

    /// The deaths stand; only the simulated bodies go.
    public func clearRagdolls() {
        runtime?.reset()
        world?.publishedRagdollPoses.removeAll()
    }

    /// Opens the container menu over the nearest corpse. Nearest, not the
    /// crosshair target, because an ACHR carries no `PlacedInteraction`.
    /// - Returns: true when a corpse was nominated.
    @discardableResult
    public func searchNearestCorpse() -> Bool {
        guard
            let runtime,
            let world,
            let feet = world.playerFeetPosition,
            let nearest = world.ragdollResidents
                .filter({ runtime.opensAsCorpse($0.key) })
                .min(by: { first, second in
                    simd_length_squared(first.position - feet)
                        < simd_length_squared(second.position - feet)
                }),
            world.searchCorpse(nearest.key)
        else { return false }
        runtime.noteLooted(nearest.key)
        return true
    }
}
