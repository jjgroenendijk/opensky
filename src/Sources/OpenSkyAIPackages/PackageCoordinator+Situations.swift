// The situations that pick an override package list, the warnings guards give, and
// the script package slot. See docs/engine/package-schedules.md, "Package lists".

import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyWorldConditionFunctions
import OpenSkyWorldInterface
import OpenSkyWorldState

extension PackageCoordinator {
    /// The warnings each guard gave the intruder in its warn radius, for
    /// `GetTrespassWarningLevel`.
    public var trespassWarnings: [ReferenceKey: Int] {
        executions.reduce(into: [:]) { result, entry in
            let warned = entry.value.runner.running.values.map(\.machine.warnings).max() ?? 0
            if warned > 0 {
                result[entry.key] = warned
            }
        }
    }

    /// Only actors with an override list are asked, because the answer changes nothing
    /// for the others.
    func applySituations(
        to runtime: inout ActorPackageRuntime, clock: GameClock,
        context: () -> ConditionContext
    ) {
        guard let world else { return }
        let listed = runtime.actorsWithOverrideLists(among: registeredActors.keys.sorted())
        guard !listed.isEmpty else { return }
        runtime.setSituations(
            (listed, world.packageSituations(of: listed)), execution: { executions[$0] },
            clock: clock, context: context
        )
    }
}
