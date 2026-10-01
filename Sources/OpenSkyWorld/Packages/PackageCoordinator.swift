// The shell of the package domain: keeps the package selector's actors in step
// with the resident ACHRs and advances it on the game clock. The selection
// rules live in `ActorPackageRuntime`. See docs/engine/coordinators.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyWorldState

/// What the package coordinator reads from the session.
@MainActor
public protocol PackageWorld: AnyObject {
    /// Nil when no cell is streamed or no renderer runs.
    func packageResidents() -> [RuntimeReferenceEntry]?
    /// Nil when no renderer runs.
    var packageClock: GameClock? { get }
    /// The live quest, actor, detection and reference state one selection reads.
    func packageConditionContext(clock: GameClock) -> ConditionContext
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
    public func advance() {
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

    public func readouts() -> [PackageActorReadout] {
        runtime?.readouts() ?? []
    }

    public func readout(for actor: ReferenceKey) -> PackageActorReadout? {
        readouts().first { $0.actor == actor }
    }
}
