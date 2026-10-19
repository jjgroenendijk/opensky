// The lists ahead of and behind the actor's own stack: a script package, the
// override list of a code-driven situation, and the default list
// (<https://ck.uesp.net/wiki/AI_Packages_Tab>, <https://ck.uesp.net/wiki/AddScriptPackage>).

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyWorldConditions
import OpenSkyWorldState

/// Where an actor's current package came from, in the order selection tries them.
nonisolated public enum PackageSource: Equatable, Sendable {
    case scene
    case script
    case situation(PackageSituation)
    case alias
    case own
    case defaults
}

/// The one package `AddScriptPackage` gave the actor.
nonisolated struct ScriptPackageSlot: Equatable, Sendable {
    let package: FormID
    /// A package without "Must Complete" goes at the next evaluation after it was picked.
    let isConstrained: Bool
    var isPicked = false
}

nonisolated extension ActorPackageRuntime {
    /// Gives the actor a package that outranks all others until it is done. A second
    /// call replaces the first; nil removes it. False when the actor or package is unknown.
    @discardableResult
    public mutating func setScriptPackage(
        _ package: FormID?, actor: ReferenceKey, clock: GameClock, context: ConditionContext
    ) -> Bool {
        guard actors[actor] != nil else { return false }
        if let package {
            guard let resolved = try? store.resolve(package) else { return false }
            actors[actor]?.scriptPackage = ScriptPackageSlot(
                package: package,
                isConstrained: resolved.package.general.flags.contains(.mustComplete)
            )
            actors[actor]?.completing = nil
        } else {
            actors[actor]?.scriptPackage = nil
        }
        reevaluate(actor: actor, clock: clock, context: context)
        return true
    }

    public func scriptPackage(for actor: ReferenceKey) -> FormID? {
        actors[actor]?.scriptPackage?.package
    }

    /// Enters or leaves a code-driven situation. The actor picks again only when an
    /// override list could change its package.
    public mutating func setSituation(
        _ situation: PackageSituation?, actor: ReferenceKey, clock: GameClock,
        context: () -> ConditionContext
    ) {
        guard let state = actors[actor], state.situation != situation else { return }
        actors[actor]?.situation = situation
        let listed = [state.situation, situation].compactMap(\.self)
            .contains { state.lists.overrides[$0] != nil }
        if listed {
            reevaluate(actor: actor, clock: clock, context: context())
        }
    }

    public func situation(for actor: ReferenceKey) -> PackageSituation? {
        actors[actor]?.situation
    }

    public func source(for actor: ReferenceKey) -> PackageSource? {
        actors[actor]?.source
    }

    public func packageLists(for actor: ReferenceKey) -> ActorPackageLists? {
        actors[actor]?.lists
    }

    /// A scene override is all the actor may run. Otherwise the script package, the
    /// situation's list, the alias and own stack, then the default list.
    func choose(
        for state: ActorState, clock: GameClock, context: inout ConditionContext,
        ranToday: Set<FormID>
    ) -> (package: ResolvedPackage, source: PackageSource)? {
        if let override = state.override {
            return select(
                stack: override.packages, clock: clock, context: &context, ranToday: ranToday
            ).map { ($0, .scene) }
        }
        if let script = state.scriptPackage, let package = try? store.resolve(script.package) {
            return (package, .script)
        }
        var lists: [([FormID], PackageSource)] = []
        if let situation = state.situation, let list = state.lists.overrides[situation] {
            lists.append((list, .situation(situation)))
        }
        lists += [
            (state.aliasStack?.packages ?? [], .alias), (state.lists.own, .own),
            (state.lists.defaults, .defaults)
        ]
        for (list, source) in lists where !list.isEmpty {
            if
                let package = select(
                    stack: list, clock: clock, context: &context, ranToday: ranToday
                )
            {
                return (package, source)
            }
        }
        return nil
    }
}

nonisolated extension ActorPackageRuntime.ActorState {
    /// Every package the actor may pick, for the next schedule edge.
    var allPackages: [FormID] {
        (override?.packages ?? []) + (aliasStack?.packages ?? []) + lists.own + lists.defaults
            + (situation.flatMap { lists.overrides[$0] } ?? [])
    }

    /// An unconstrained script package lasts until the next evaluation after it was picked.
    mutating func dropSpentScriptPackage() {
        guard let script = scriptPackage, script.isPicked, !script.isConstrained else { return }
        scriptPackage = nil
    }
}
