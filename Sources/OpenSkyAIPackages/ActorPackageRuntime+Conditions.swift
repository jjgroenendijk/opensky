// The package facts conditions read, built from the packages actors run now.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldConditions

nonisolated extension ActorPackageRuntime {
    /// `isWithin` answers whether the actor stands inside one location input.
    public func conditionResolution(
        isWithin: (Package.Location, ReferenceKey) -> Bool
    ) -> PackageConditionResolution {
        var facts: [ReferenceKey: ActorPackageFacts] = [:]
        for readout in readouts() {
            guard let running = currentPackage(for: readout.actor) else { continue }
            var actorFacts = ActorPackageFacts(
                package: running.package.formID, procedure: running.procedure,
                flags: running.package.general.flags,
                interruptFlags: running.package.general.interruptFlags
            )
            for input in running.package.dataInputs {
                guard let index = input.index else { continue }
                actorFacts.dataInputs[index] = input.value
                if case let .location(location) = input.value, isWithin(location, readout.actor) {
                    actorFacts.withinLocations.insert(index)
                }
            }
            facts[readout.actor] = actorFacts
        }
        return PackageConditionResolution(facts: facts)
    }
}
