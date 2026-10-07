// The shell of the package domain: keeps the package selector's actors in step
// with the resident ACHRs and advances it on the game clock. The selection
// rules live in `ActorPackageRuntime`. See docs/engine/coordinators.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyWorldState
import simd

/// What the package coordinator reads from the session.
@MainActor
public protocol PackageWorld: AnyObject {
    /// Nil when no cell is streamed or no renderer runs.
    func packageResidents() -> [RuntimeReferenceEntry]?
    /// Nil when no renderer runs.
    var packageClock: GameClock? { get }
    /// The live quest, actor, detection and reference state one selection reads.
    func packageConditionContext(clock: GameClock) -> ConditionContext
    /// Where the actor stands now. Nil when it is not loaded.
    func packageActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>?
    /// The world point a package location names, or nil when OpenSky cannot place it.
    func packagePlace(
        of location: Package.Location, actor: ReferenceKey, aliasQuest: FormID?
    ) -> PackagePlace?
    /// False when the move could not start.
    func movePackageActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> Bool
}

/// Which actors to drop from and add to the selector after a residency change.
nonisolated public struct PackageReconcile: Equatable, Sendable {
    public let departed: [ReferenceKey]
    /// Sorted by key, so registration order is deterministic.
    public let arrived: [PackageArrival]
}

nonisolated public struct PackageArrival: Equatable, Sendable {
    public let actor: ReferenceKey
    public let base: FormID
}

nonisolated public enum PackageCore {
    /// An actor whose base changed counts as arrived, so it re-registers.
    public static func reconcile(
        registered: [ReferenceKey: FormID],
        residents: [ReferenceKey: FormID]
    ) -> PackageReconcile {
        PackageReconcile(
            departed: registered.keys.filter { residents[$0] == nil }.sorted(),
            arrived: residents.keys.sorted().compactMap { actor in
                guard let base = residents[actor], registered[actor] != base else { return nil }
                return PackageArrival(actor: actor, base: base)
            }
        )
    }
}

/// Owns the package selector. Without game data the runtime stays nil and
/// every call is a no-op.
@MainActor
public final class PackageCoordinator {
    public private(set) var runtime: ActorPackageRuntime?
    /// Each simulated actor and the base it registered with.
    public private(set) var registeredActors: [ReferenceKey: FormID] = [:]
    /// The procedure of each actor a scene holds.
    public private(set) var executions: [ReferenceKey: PackageOverrideExecution] = [:]

    weak var world: (any PackageWorld)?

    public init() {}

    public func attach(world: any PackageWorld) {
        self.world = world
    }

    public func wire(store: PackageStore) {
        runtime = ActorPackageRuntime(store: store)
        registeredActors = [:]
    }

    /// Reconciles residency, then evaluates scheduled boundaries. An actor
    /// that leaves residency stops being simulated.
    public func advance(by delta: Float = 0) {
        guard
            var runtime,
            let world,
            let residents = world.packageResidents(),
            let clock = world.packageClock
        else { return }
        let change = PackageCore.reconcile(
            registered: registeredActors,
            residents: ActorPackageRuntime.residentBases(residents)
        )
        for actor in change.departed {
            runtime.unregister(actor: actor)
            registeredActors.removeValue(forKey: actor)
            executions.removeValue(forKey: actor)
        }
        for arrival in change.arrived {
            guard (try? runtime.register(actor: arrival.actor, base: arrival.base)) != nil else {
                continue
            }
            registeredActors[arrival.actor] = arrival.base
        }

        var context: ConditionContext?
        runtime.advance(clock: clock) { _ in
            if let context {
                return context
            }
            let live = world.packageConditionContext(clock: clock)
            context = live
            return live
        }
        self.runtime = runtime
        advanceOverrides(by: delta)
    }

    /// Holds `actor` out of scheduled selection, as a conversation does.
    public func suspend(_ actor: ReferenceKey) {
        runtime?.setSuspended(true, actor: actor)
    }

    /// Lifts the suspension and selects `actor`'s package for the current time
    /// now, because the world moved on while it was held.
    public func resume(_ actor: ReferenceKey) {
        runtime?.setSuspended(false, actor: actor)
        guard
            var runtime,
            let world,
            let clock = world.packageClock,
            registeredActors[actor] != nil
        else { return }
        runtime.forceReevaluate(
            actor: actor,
            clock: clock,
            context: world.packageConditionContext(clock: clock)
        )
        self.runtime = runtime
    }

    // MARK: - Scene packages

    /// Runs the packages ahead of the actor's schedule, or keeps them running.
    public func runOverride(
        _ override: PackageOverride, actor: ReferenceKey
    ) -> PackageOverrideProgress {
        guard var runtime, let world, let clock = world.packageClock else { return .notSimulated }
        guard
            runtime.setOverride(
                override, actor: actor, clock: clock,
                context: world.packageConditionContext(clock: clock)
            ) else { return .notSimulated }
        self.runtime = runtime
        syncExecution(actor)
        return executions[actor]?.isDone == true ? .done : .running
    }

    /// Hands the actor back to its schedule, when `owner` still holds it.
    public func clearOverride(owner: PackageOverrideOwner, actor: ReferenceKey) {
        guard
            var runtime, let world, let clock = world.packageClock,
            runtime.override(for: actor)?.owner == owner
        else { return }
        runtime.clearOverride(
            owner: owner, actor: actor, clock: clock,
            context: world.packageConditionContext(clock: clock)
        )
        self.runtime = runtime
        executions.removeValue(forKey: actor)
    }

    /// A move the procedure asked for ended.
    public func movementSettled(actor: ReferenceKey, reason: NPCMovementSettleReason) {
        let event: PackageProcedureEvent
        switch reason {
        case .arrival: event = .arrived
        case .giveUp: event = .movementFailed
        default: return
        }
        guard var execution = executions[actor] else { return }
        let commands = execution.handle(event)
        executions[actor] = execution
        apply(commands, actor: actor)
    }

    private func advanceOverrides(by delta: Float) {
        for actor in executions.keys.sorted() {
            syncExecution(actor)
            guard var execution = executions[actor] else { continue }
            let commands = execution.handle(.tick(delta))
            executions[actor] = execution
            apply(commands, actor: actor)
        }
    }

    /// Starts a machine for the actor's current override package when it changed.
    private func syncExecution(_ actor: ReferenceKey) {
        guard
            let runtime, let world,
            let override = runtime.override(for: actor),
            let current = runtime.currentPackage(for: actor)
        else {
            executions.removeValue(forKey: actor)
            return
        }
        guard executions[actor]?.package != current.package.formID else { return }
        guard let start = world.packageActorPosition(actor) else { return }
        let place = PackageOverrideExecution.location(of: current.package).flatMap {
            world.packagePlace(of: $0, actor: actor, aliasQuest: override.aliasQuest)
        }
        var execution = PackageOverrideExecution(package: current, start: start, place: place)
        let commands = execution.start()
        executions[actor] = execution
        apply(commands, actor: actor)
    }

    private func apply(_ commands: [PackageProcedureCommand], actor: ReferenceKey) {
        for command in commands {
            guard case let .move(point) = command else { continue }
            if world?.movePackageActor(actor, to: point) != true {
                movementSettled(actor: actor, reason: .giveUp)
            }
        }
    }

    public func readouts() -> [PackageActorReadout] {
        runtime?.readouts() ?? []
    }

    public func readout(for actor: ReferenceKey) -> PackageActorReadout? {
        readouts().first { $0.actor == actor }
    }
}
