// What `PackageCoordinator` asks of the package runtime, a running procedure, and the
// world, kept on those values so the coordinator only routes.

import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyWorldConditionFunctions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension ActorPackageRuntime {
    /// True while the actor's current package has the Ignore Combat flag, or came from
    /// its combat override list, which runs in place of combat.
    func ignoresCombat(_ actor: ReferenceKey) -> Bool {
        let flags = currentPackage(for: actor)?.package.general.flags ?? []
        return flags.contains(.ignoreCombat) || source(for: actor) == .situation(.combat)
    }

    /// Whether a fighting actor keeps running `package`.
    func fights(_ actor: ReferenceKey, running package: ResolvedPackage) -> Bool {
        package.package.general.flags.contains(.ignoreCombat)
            || source(for: actor) == .situation(.combat)
    }

    func mustComplete(_ package: ResolvedPackage) -> Bool {
        package.package.general.flags.contains(.mustComplete)
    }

    /// An own package that ended lets the schedule pick again, for its "Must Complete"
    /// and "Once Per Day" flags.
    func releasesWhenEnded(_ actor: ReferenceKey) -> Bool {
        guard let package = currentPackage(for: actor)?.package else { return false }
        return completing(for: actor) == package.formID
            || package.general.flags.contains(.oncePerDay)
    }

    /// The actors with an override list. Only they are asked for their situation,
    /// because the answer changes nothing for the others.
    func actorsWithOverrideLists(among actors: [ReferenceKey]) -> [ReferenceKey] {
        actors.filter { packageLists(for: $0)?.overrides.isEmpty == false }
    }

    /// Sets each listed actor's situation. A guard warns while its machine has warned;
    /// a guard warn package then runs until its tree ends.
    mutating func setSituations(
        _ found: (actors: [ReferenceKey], situations: [ReferenceKey: PackageSituation]),
        execution: (ReferenceKey) -> PackageOverrideExecution?,
        clock: GameClock, context: () -> ConditionContext
    ) {
        for actor in found.actors {
            let running = execution(actor)
            let warns = running?.isWarning == true
                || (source(for: actor) == .situation(.guardWarn) && running?.runner.outcome == nil)
            let situation = warns ? .guardWarn : found.situations[actor]
            setSituation(situation, actor: actor, clock: clock, context: context)
        }
    }

    /// Sets each actor's alias stack. Every actor reads one context, because the loop
    /// changes only this runtime.
    mutating func setAliasStacks(
        _ stacks: [ReferenceKey: PackageAliasStack], actors: [ReferenceKey],
        clock: GameClock, context: () -> ConditionContext
    ) {
        var shared: ConditionContext?
        for actor in actors {
            setAliasStack(stacks[actor], actor: actor, clock: clock) {
                if let shared {
                    return shared
                }
                let live = context()
                shared = live
                return live
            }
        }
    }
}

extension PackageOverrideExecution {
    /// True while a running guard machine has warned.
    var isWarning: Bool {
        runner.running.values.contains(where: \.machine.isWarning)
    }

    /// The running procedure's destination or centre.
    var runningPlace: SIMD3<Float>? {
        guard let leaf = runner.running.min(by: { $0.key < $1.key })?.value else { return nil }
        return leaf.setup.setup.destination ?? leaf.setup.setup.center
    }

    /// The first running sandbox machine, if any.
    var sandboxMachine: PackageProcedureMachine? {
        runner.runningMachines.first { $0.kind == .sandbox }
    }

    /// The seat a sit command in `leaf` sits on.
    func seat(of leaf: Int) -> PackageSeat? {
        let running = runner.running[leaf]
        return running.map { $0.machine.sandbox.seat ?? $0.setup.seat }
            ?? runner.finishedSeats[leaf]
    }

    /// Whether a running procedure follows `leader`.
    func follows(_ leader: ReferenceKey) -> Bool {
        runner.running.values.contains { $0.machine.follows && $0.machine.setup.watched == leader }
    }

    /// A sandboxing leaf takes the idle runtime's marker as its next activity.
    func takesIdleMarkers(_ leaf: Int) -> Bool {
        let running = runner.running[leaf]
        return running?.leaf.kind == .sandbox
            && running?.setup.setup.sandbox?.usesIdleMarkers != false
    }
}

extension PackageProcedureMachine {
    var follows: Bool {
        kind == .follow || kind == .followTo
    }

    var isSandbox: Bool {
        kind == .sandbox
    }

    var isWandering: Bool {
        state == .sandboxing(.wandering)
    }

    /// The cylinder round the sandbox's place, with `fSandboxCylinderBottom` and
    /// `fSandboxCylinderTop` as its height.
    func idleArea(defaults: SandboxSettings) -> IdleSearchArea {
        let settings = setup.sandbox?.settings ?? defaults
        var area = IdleSearchArea(
            center: center, radius: radius,
            height: settings.cylinderBottom ... max(settings.cylinderBottom, settings.cylinderTop),
            minimumStep: settings.interMarkerMinDistance
        )
        area.allowsMarkers = setup.sandbox?.usesIdleMarkers ?? true
        return area
    }
}

extension PackageWorld {
    /// The first location input of `package` that resolves, for `actor`.
    func firstLocation(of package: ResolvedPackage, actor: ReferenceKey) -> SIMD3<Float>? {
        let values = PackageOverrideExecution(package: package).values
        for index in values.keys.sorted() {
            guard
                case let .location(location)? = values[index],
                let place = packagePlace(of: location, actor: actor, aliasQuest: nil)
            else { continue }
            return place.point
        }
        return nil
    }

    /// Runs the package's begin, change, or end fragment.
    func reportProcedure(
        _ kind: PackageScriptEvent.Kind, actor: ReferenceKey, package: Package
    ) {
        packageProcedure(PackageScriptEvent(kind: kind, actor: actor, package: package))
    }
}
