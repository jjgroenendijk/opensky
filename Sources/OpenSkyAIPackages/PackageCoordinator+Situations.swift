// The situations that pick an override package list, the warnings guards give, and
// the script package slot. See docs/engine/package-schedules.md, "Package lists".

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyWorldConditions
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
        let listed = registeredActors.keys.sorted().filter {
            runtime.packageLists(for: $0)?.overrides.isEmpty == false
        }
        guard !listed.isEmpty else { return }
        let situations = world.packageSituations(of: listed)
        for actor in listed {
            let situation = guardWarnSituation(of: actor, runtime: runtime) ?? situations[actor]
            runtime.setSituation(situation, actor: actor, clock: clock, context: context)
        }
    }

    /// A guard warns while its machine has warned; a guard warn package then runs
    /// until its tree ends.
    private func guardWarnSituation(
        of actor: ReferenceKey, runtime: ActorPackageRuntime
    ) -> PackageSituation? {
        let execution = executions[actor]
        if execution?.runner.running.values.contains(where: \.machine.isWarning) == true {
            return .guardWarn
        }
        let holds = runtime.source(for: actor) == .situation(.guardWarn)
            && execution?.runner.outcome == nil
        return holds ? .guardWarn : nil
    }

    /// `AddScriptPackage`: the package outranks all others until it is done. Nil
    /// removes it, as `RemoveScriptPackage` does. False when the actor or package is unknown.
    @discardableResult
    public func setScriptPackage(_ package: FormID?, for actor: ReferenceKey) -> Bool {
        guard
            var runtime, let world, let clock = world.packageClock,
            registeredActors[actor] != nil
        else { return false }
        let applied = runtime.setScriptPackage(
            package, actor: actor, clock: clock,
            context: world.packageConditionContext(clock: clock)
        )
        self.runtime = runtime
        syncExecution(actor)
        return applied
    }
}
