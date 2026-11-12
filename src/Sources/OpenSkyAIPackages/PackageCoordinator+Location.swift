// Where an actor's current package wants it, for Papyrus `MoveToPackageLocation`
// (<https://ck.uesp.net/wiki/MoveToPackageLocation_-_Actor>).

public import OpenSkyFormatsESM
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
