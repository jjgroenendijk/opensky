// A follower command takes the actor away from its packages, alias packages too, until
// the command ends. See docs/engine/follower-commands.md#flow.

public import OpenSkyFormatsESM

extension PackageCoordinator {
    public func holdCommanded(_ actor: ReferenceKey) {
        commandedActors.insert(actor)
        syncExecution(actor)
    }

    /// Picks the actor's package again, because the world moved on while it was held.
    public func releaseCommanded(_ actor: ReferenceKey) {
        guard commandedActors.remove(actor) != nil else { return }
        resume(actor)
    }
}
