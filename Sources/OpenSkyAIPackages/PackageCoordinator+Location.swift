// Where an actor's current package wants it, for Papyrus `MoveToPackageLocation`
// (<https://ck.uesp.net/wiki/MoveToPackageLocation_-_Actor>).

import OpenSkyFormatsESM
import simd

extension PackageCoordinator {
    /// The running procedure's destination or centre, else the first location input
    /// of the package the actor would run now. Nil when neither resolves.
    public func packageLocation(of actor: ReferenceKey) -> SIMD3<Float>? {
        if
            let leaf = executions[actor]?.runner.running
                .min(by: { $0.key < $1.key })?.value
        {
            return leaf.setup.setup.destination ?? leaf.setup.setup.center
        }
        guard let world, let package = runtime?.currentPackage(for: actor) else { return nil }
        let values = PackageOverrideExecution(package: package).values
        for index in values.keys.sorted() {
            guard
                case let .location(location)? = values[index],
                let place = world.packagePlace(of: location, actor: actor, aliasQuest: nil)
            else { continue }
            return place.point
        }
        return nil
    }
}
