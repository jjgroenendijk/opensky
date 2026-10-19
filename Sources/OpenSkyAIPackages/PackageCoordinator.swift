// The shell of the package domain: keeps the package selector's actors in step
// with the resident ACHRs and advances it on the game clock. The selection
// rules live in `ActorPackageRuntime`. See docs/engine/coordinators.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyNavigation
import OpenSkyPhysics
import OpenSkyWorldConditions
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
    /// How the actor moves now: sprint and sneak make a follower match it.
    func packageActorGait(_ actor: ReferenceKey) -> LocomotionGait?
    /// The world point a package location names, or nil when OpenSky cannot place it.
    func packagePlace(
        of location: Package.Location, actor: ReferenceKey, aliasQuest: FormID?
    ) -> PackagePlace?
    /// A `direct` move walks the straight line on the terrain, as a static-pathing
    /// patrol does.
    func movePackageActor(
        _ actor: ReferenceKey, to point: SIMD3<Float>, direct: Bool, gait: LocomotionGait?
    ) -> PackageMoveResult
    /// The packages each filled quest alias adds to its actor.
    func packageAliasStacks() -> [ReferenceKey: PackageAliasStack]
    /// The points a patrol walks, from its start marker along the linked references.
    func packagePatrolPath(
        from start: Package.Target, actor: ReferenceKey, aliasQuest: FormID?
    ) -> [SIMD3<Float>]?
    /// A free seat of the furniture, or nil when it has none or is not loaded.
    func packageSeat(in furniture: ReferenceKey, actor: ReferenceKey) -> PackageSeat?
    /// The actor sits down in `seat`, or leaves it and frees it.
    func seatPackageActor(_ actor: ReferenceKey, in seat: PackageSeat)
    func unseatPackageActor(_ actor: ReferenceKey, from seat: PackageSeat)
    /// A held package started, finished, or was left. Its fragments run here.
    func packageProcedure(_ event: PackageScriptEvent)
    /// Seats `rider` on its horse and returns the horse, or nil when it has none loaded.
    func mountPackageActor(_ rider: ReferenceKey) -> ReferenceKey?
    func dismountPackageActor(_ rider: ReferenceKey)
    /// True after `SetPlayerAIDriven(true)`: scene and alias packages move the player.
    var packageDrivesPlayer: Bool { get }
    /// The reference a target input names, or nil when OpenSky cannot find it.
    func packageReference(
        _ target: Package.Target, actor: ReferenceKey, aliasQuest: FormID?
    ) -> ReferenceKey?
    /// Does one act of a procedure, such as locking doors or casting a spell.
    func packageAction(_ action: PackageAction, actor: ReferenceKey) -> PackageActionResult
    /// The actor stops walking where it is.
    func stopPackageActor(_ actor: ReferenceKey)
    /// What keeps the actor from running its own package now, such as a fight.
    func packageActorActivity(_ actor: ReferenceKey) -> PackageActorActivity
    /// The code-driven behaviour each actor is in, which picks an override package list.
    /// One call for all, so the world scans its actors once.
    func packageSituations(of actors: [ReferenceKey]) -> [ReferenceKey: PackageSituation]
    /// False when every mover slot is taken and `actor` has none, so a move would wait.
    func packageMoverHasRoom(for actor: ReferenceKey) -> Bool
    /// True while the idle runtime holds an idle marker for the actor.
    func packageActorHoldsIdleMarker(_ actor: ReferenceKey) -> Bool
}

/// Whether an actor is free to run the package its schedule picked.
nonisolated public enum PackageActorActivity: Equatable, Sendable {
    case free
    case fighting
    case dead
}

extension PackageWorld {
    public func packageActorGait(_: ReferenceKey) -> LocomotionGait? {
        nil
    }

    public func packageAliasStacks() -> [ReferenceKey: PackageAliasStack] {
        [:]
    }

    public func packagePatrolPath(
        from _: Package.Target, actor _: ReferenceKey, aliasQuest _: FormID?
    ) -> [SIMD3<Float>]? {
        nil
    }

    public func packageSeat(in _: ReferenceKey, actor _: ReferenceKey) -> PackageSeat? {
        nil
    }

    public func seatPackageActor(_: ReferenceKey, in _: PackageSeat) {}

    public func unseatPackageActor(_: ReferenceKey, from _: PackageSeat) {}

    public func packageProcedure(_: PackageScriptEvent) {}

    public func mountPackageActor(_: ReferenceKey) -> ReferenceKey? {
        nil
    }

    public func dismountPackageActor(_: ReferenceKey) {}

    public var packageDrivesPlayer: Bool {
        false
    }

    public func packageReference(
        _: Package.Target, actor _: ReferenceKey, aliasQuest _: FormID?
    ) -> ReferenceKey? {
        nil
    }

    public func packageAction(_: PackageAction, actor _: ReferenceKey) -> PackageActionResult {
        .failed
    }

    public func stopPackageActor(_: ReferenceKey) {}

    public func packageActorActivity(_: ReferenceKey) -> PackageActorActivity {
        .free
    }

    public func packageSituations(
        of actors: [ReferenceKey]
    ) -> [ReferenceKey: PackageSituation] {
        actors.reduce(into: [:]) { result, actor in
            if packageActorActivity(actor) == .fighting {
                result[actor] = .combat
            }
        }
    }

    public func packageMoverHasRoom(for _: ReferenceKey) -> Bool {
        true
    }

    public func packageActorHoldsIdleMarker(_: ReferenceKey) -> Bool {
        false
    }
}

/// The begin, end, or change of one actor's package, which runs the package's fragment.
/// A change is the actor leaving the package, whether it completed or not.
nonisolated public struct PackageScriptEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case begin
        case end
        case change
    }

    public let kind: Kind
    public let actor: ReferenceKey
    public let package: Package

    /// The PACK fragment flag: 0x01 begin, 0x02 end, 0x04 change (docs/formats/vmad.md).
    public var fragmentSlot: UInt32 {
        switch kind {
        case .begin: 0x01
        case .end: 0x02
        case .change: 0x04
        }
    }
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
    public internal(set) var runtime: ActorPackageRuntime?
    /// Each simulated actor and the base it registered with.
    public private(set) var registeredActors: [ReferenceKey: FormID] = [:]
    /// The procedure of each actor a scene holds.
    public internal(set) var executions: [ReferenceKey: PackageOverrideExecution] = [:]
    /// Each rider's horse, which walks the rider's package for it.
    public private(set) var mounts: [ReferenceKey: ReferenceKey] = [:]
    /// Walks that found no free mover slot, by actor.
    var waitingMoves: [ReferenceKey: PackagePendingMove] = [:]
    /// A follower's gait, which overrides its package's preferred speed.
    var paces: [ReferenceKey: LocomotionGait] = [:]
    var nextMoveTicket = 0
    public var seats = PackageSeatLedger()
    /// The newest move result per actor, for `state packages`.
    public private(set) var lastMoves: [ReferenceKey: NPCMoveCommandResult] = [:]

    weak let world: (any PackageWorld)?
    private(set) var store: PackageStore?
    /// Real seconds until the alias stacks are read again.
    private var aliasRefreshSeconds: Float = 0
    private static let aliasRefreshInterval: Float = 1
    /// A walking actor leaves residency for a few frames while it moves into the next
    /// cell. A shorter absence keeps its package and procedure.
    private static let departureGraceSeconds: Float = 1
    /// The `Player` `NPC_` record in `Skyrim.esm`.
    static let playerBase = FormID(0x7)
    private var absentSeconds: [ReferenceKey: Float] = [:]

    public init(world: (any PackageWorld)?) {
        self.world = world
    }

    public func wire(store: PackageStore) {
        self.store = store
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
        var bases = ActorPackageRuntime.residentBases(residents)
        if world.packageDrivesPlayer {
            bases[.player] = Self.playerBase
        }
        let change = PackageCore.reconcile(registered: registeredActors, residents: bases)
        absentSeconds = absentSeconds.filter { bases[$0.key] == nil }
        for actor in change.departed {
            let away = (absentSeconds[actor] ?? 0) + delta
            absentSeconds[actor] = away
            guard away >= Self.departureGraceSeconds else { continue }
            absentSeconds[actor] = nil
            runtime.unregister(actor: actor)
            registeredActors.removeValue(forKey: actor)
            executions.removeValue(forKey: actor)
            mounts.removeValue(forKey: actor)
            waitingMoves.removeValue(forKey: actor)
        }
        for arrival in change.arrived {
            guard (try? runtime.register(actor: arrival.actor, base: arrival.base)) != nil else {
                continue
            }
            registeredActors[arrival.actor] = arrival.base
        }

        var context: ConditionContext?
        let live = {
            if let context {
                return context
            }
            let fresh = world.packageConditionContext(clock: clock)
            context = fresh
            return fresh
        }
        aliasRefreshSeconds -= delta
        if aliasRefreshSeconds <= 0 || !change.arrived.isEmpty {
            aliasRefreshSeconds = Self.aliasRefreshInterval
            applyAliasStacks(world.packageAliasStacks(), to: &runtime, clock: clock)
        }
        applySituations(to: &runtime, clock: clock, context: live)
        runtime.advance(clock: clock) { _ in live() }
        self.runtime = runtime
        advanceTrees(by: delta)
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
        syncExecution(actor)
    }

    /// Picks `actor`'s package again now, as `EvaluatePackage` asks.
    public func evaluate(_ actor: ReferenceKey) {
        guard
            var runtime, let world, let clock = world.packageClock,
            registeredActors[actor] != nil
        else { return }
        applyAliasStacks(world.packageAliasStacks(), to: &runtime, clock: clock)
        runtime.forceReevaluate(
            actor: actor, clock: clock, context: world.packageConditionContext(clock: clock)
        )
        self.runtime = runtime
        syncExecution(actor)
    }

    private func applyAliasStacks(
        _ stacks: [ReferenceKey: PackageAliasStack],
        to runtime: inout ActorPackageRuntime,
        clock: GameClock
    ) {
        guard let world else { return }
        // The loop changes only this local runtime, so every actor reads one context.
        var shared: ConditionContext?
        for actor in registeredActors.keys.sorted() {
            runtime.setAliasStack(stacks[actor], actor: actor, clock: clock) {
                if let shared {
                    return shared
                }
                let live = world.packageConditionContext(clock: clock)
                shared = live
                return live
            }
        }
    }

    // MARK: - Scene and alias packages

    /// Runs the packages ahead of the actor's schedule, or keeps them running.
    public func runOverride(
        _ override: PackageOverride, actor: ReferenceKey
    ) -> PackageOverrideProgress {
        guard
            var runtime, let world, let clock = world.packageClock,
            registeredActors[actor] != nil else { return .notSimulated }
        // A scene asks every frame; only a new override needs the costly context.
        if runtime.override(for: actor) != override {
            guard
                runtime.setOverride(
                    override, actor: actor, clock: clock,
                    context: world.packageConditionContext(clock: clock)
                ) else { return .notSimulated }
            self.runtime = runtime
        }
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
        leaveExecution(of: actor)
        updateMount(actor, rides: false)
    }

    /// A move the procedure asked for ended.
    public func movementSettled(actor: ReferenceKey, reason: NPCMovementSettleReason) {
        let event: PackageProcedureEvent
        switch reason {
        case .arrival: event = .arrived
        case .giveUp: event = .movementFailed
        default: return
        }
        let rider = mounts.first { $0.value == actor }?.key ?? actor
        guard let mover = executions[rider]?.runner.mover else { return }
        step(rider, with: event, leaf: mover)
    }

    /// Runs the end fragment once for each time the package ended since `before`.
    func reportEnds(of actor: ReferenceKey, since before: Int) {
        guard
            let execution = executions[actor], execution.ends > before,
            let package = try? store?.resolve(execution.package).package
        else { return }
        world?.packageProcedure(PackageScriptEvent(kind: .end, actor: actor, package: package))
    }

    func updateMount(_ actor: ReferenceKey, rides: Bool) {
        guard let world else { return }
        if rides, mounts[actor] == nil, let horse = world.mountPackageActor(actor) {
            mounts[actor] = horse
        } else if !rides, mounts.removeValue(forKey: actor) != nil {
            world.dismountPackageActor(actor)
        }
    }

    public func readouts() -> [PackageActorReadout] {
        runtime?.readouts() ?? []
    }

    public func readout(for actor: ReferenceKey) -> PackageActorReadout? {
        readouts().first { $0.actor == actor }
    }
}

extension PackageCoordinator {
    /// The `PKCU` template of `package`, or nil for a package built without one.
    public func template(of package: FormID) -> FormID? {
        store?.package(package)?.template
    }
}

extension PackageCoordinator {
    public func recordMove(_ result: NPCMoveCommandResult, for actor: ReferenceKey) {
        lastMoves[actor] = result
    }
}
