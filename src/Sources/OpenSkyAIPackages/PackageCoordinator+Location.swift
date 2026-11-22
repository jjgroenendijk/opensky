// Where an actor's current package wants it, for Papyrus `MoveToPackageLocation`
// (<https://ck.uesp.net/wiki/MoveToPackageLocation_-_Actor>).

public import OpenSkyFormatsESM
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension PackageCoordinator {
    /// The running procedure's destination or centre, else the first location input
    /// of the package the actor would run now. Nil when neither resolves.
    public func packageLocation(of actor: ReferenceKey) -> SIMD3<Float>? {
        if executions[actor]?.runner.running.isEmpty == false {
            return executions[actor]?.runningPlace
        }
        guard let world, let package = runtime?.currentPackage(for: actor) else { return nil }
        return world.firstLocation(of: package, actor: actor)
    }
}

extension PackageCoordinator {
    /// Runs the placement a new game or a rest asked for. An actor that fights, talks,
    /// rides, follows a command, or runs a scene's package keeps its place.
    func placeAtPackagePlaces() {
        guard
            placementDue, let world, let clock = world.packageClock,
            let offscreenWorld = world as? any OffscreenScheduleWorld
        else { return }
        placementDue = false
        offscreen.aliasStacks = world.packageAliasStacks()
        offscreen.place(
            offscreenWorld.offscreenActors().filter { !isBusy($0.key, world: world) },
            world: offscreenWorld, clock: clock, context: conditionContext(clock: clock)
        )
    }

    /// An actor of a cell that just loaded starts at its package's place, as an actor
    /// that rises to the loaded level does in the game (docs/engine/unloaded-actors.md).
    func placeArrivals(_ arrived: [ReferenceKey], clock: GameClock) {
        guard
            !arrived.isEmpty, let world,
            let offscreenWorld = world as? any OffscreenScheduleWorld
        else { return }
        let actors = arrived.filter { !isBusy($0, world: world) }
            .compactMap { offscreenWorld.offscreenArrival($0) }
        guard !actors.isEmpty else { return }
        offscreen.place(
            actors, world: offscreenWorld, clock: clock, context: conditionContext(clock: clock)
        )
    }

    private func isBusy(_ actor: ReferenceKey, world: any PackageWorld) -> Bool {
        guard actor != .player else { return true }
        guard registeredActors[actor] != nil else { return false }
        return commandedActors.contains(actor) || mounts[actor] != nil
            || runtime?.isSuspended(actor) == true || runtime?.override(for: actor) != nil
            || world.packageActorActivity(actor) != .free
    }
}
