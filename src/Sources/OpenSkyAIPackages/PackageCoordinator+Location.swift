// Where an actor's current package wants it, for Papyrus `MoveToPackageLocation`
// (<https://ck.uesp.net/wiki/MoveToPackageLocation_-_Actor>).

public import OpenSkyFormatsESM
import OpenSkyWorldInterface
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
        let busy = registeredActors.keys.filter { actor in
            commandedActors.contains(actor) || mounts[actor] != nil
                || runtime?.isSuspended(actor) == true || runtime?.override(for: actor) != nil
                || world.packageActorActivity(actor) != .free
        }
        offscreen.placeAll(
            world: offscreenWorld, clock: clock, busy: Set(busy).union([.player]),
            context: conditionContext(clock: clock)
        )
    }
}
