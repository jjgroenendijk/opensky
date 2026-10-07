// Schedule and condition package selection for resident actors. Event-driven: exact
// daily edges, a bounded game-time interval for other changes, and a panel seam.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

nonisolated public struct PackageActorReadout: Equatable, Sendable {
    public let actor: ReferenceKey
    public let actorBase: FormID
    public let currentPackage: FormID?
    public let editorID: String?
    public let schedule: Package.Schedule?
    public let procedure: PackageProcedureKind?
    public let lastEvaluationGameSeconds: Double?
    /// True while something outside the schedule holds this actor, such as a
    /// conversation. It keeps its package and is not re-evaluated until released.
    public var isSuspended = false
    /// The scene action whose packages run ahead of the schedule, if any.
    public var override: PackageOverrideOwner?

    public init(
        actor: ReferenceKey,
        actorBase: FormID,
        currentPackage: FormID?,
        editorID: String?,
        schedule: Package.Schedule?,
        procedure: PackageProcedureKind?,
        lastEvaluationGameSeconds: Double?,
        isSuspended: Bool = false,
        override: PackageOverrideOwner? = nil
    ) {
        self.actor = actor
        self.actorBase = actorBase
        self.currentPackage = currentPackage
        self.editorID = editorID
        self.schedule = schedule
        self.procedure = procedure
        self.lastEvaluationGameSeconds = lastEvaluationGameSeconds
        self.isSuspended = isSuspended
        self.override = override
    }
}

/// What holds an actor's packages ahead of its schedule: a scene action.
nonisolated public struct PackageOverrideOwner: Hashable, Sendable {
    public let source: FormID
    public let slot: UInt32

    public init(source: FormID, slot: UInt32) {
        self.source = source
        self.slot = slot
    }
}

/// Packages that override an actor's own stack, as a scene package action does
/// (<https://ck.uesp.net/wiki/Category:Scenes>, "Actors in Scenes").
nonisolated public struct PackageOverride: Equatable, Sendable {
    public let packages: [FormID]
    public let owner: PackageOverrideOwner
    /// The quest whose aliases the package locations name.
    public let aliasQuest: FormID?

    public init(packages: [FormID], owner: PackageOverrideOwner, aliasQuest: FormID?) {
        self.packages = packages
        self.owner = owner
        self.aliasQuest = aliasQuest
    }
}

nonisolated public struct ActorPackageRuntime {
    public static let maximumReevaluationGameMinutes: Float = 15

    public var onSelectionChanged: ((PackageActorReadout) -> Void)?

    private let store: PackageStore
    private var actors: [ReferenceKey: ActorState] = [:]

    public init(store: PackageStore) {
        self.store = store
    }

    /// The base of each resident actor. A repeated key keeps its first entry,
    /// so the reconcile never traps on plugin data that places one actor twice.
    public static func residentBases(
        _ entries: [RuntimeReferenceEntry]
    ) -> [ReferenceKey: FormID] {
        var bases: [ReferenceKey: FormID] = [:]
        for entry in entries where bases[entry.key] == nil {
            if let actor = entry.placedActor {
                bases[entry.key] = actor.base
            }
        }
        return bases
    }

    public mutating func register(actor: ReferenceKey, base: FormID) throws {
        let stack = try store.packageStack(for: base).value
        actors[actor] = ActorState(base: base, stack: stack)
    }

    public mutating func unregister(actor: ReferenceKey) {
        actors.removeValue(forKey: actor)
    }

    public mutating func advance(
        clock: GameClock,
        context: (ReferenceKey) -> ConditionContext
    ) {
        for actor in actors.keys.sorted() {
            guard
                let state = actors[actor],
                !state.isSuspended,
                state.needsEvaluation(at: clock)
            else { continue }
            reevaluate(actor: actor, clock: clock, context: context(actor))
        }
    }

    /// Holds one actor out of scheduled selection, or releases it. A latch, not a saved
    /// procedure: on release the actor takes the package the schedule names now
    /// (`forceReevaluate(actor:clock:context:)`).
    public mutating func setSuspended(_ suspended: Bool, actor: ReferenceKey) {
        actors[actor]?.isSuspended = suspended
    }

    public func isSuspended(_ actor: ReferenceKey) -> Bool {
        actors[actor]?.isSuspended ?? false
    }

    /// Runs `override`'s packages ahead of the actor's stack and picks one now.
    /// False when the actor is not simulated.
    @discardableResult
    public mutating func setOverride(
        _ override: PackageOverride,
        actor: ReferenceKey,
        clock: GameClock,
        context: ConditionContext
    ) -> Bool {
        guard actors[actor] != nil else { return false }
        guard actors[actor]?.override != override else { return true }
        actors[actor]?.override = override
        reevaluate(actor: actor, clock: clock, context: context)
        return true
    }

    /// Hands the actor back to its stack, when `owner` still holds it.
    public mutating func clearOverride(
        owner: PackageOverrideOwner,
        actor: ReferenceKey,
        clock: GameClock,
        context: ConditionContext
    ) {
        guard actors[actor]?.override?.owner == owner else { return }
        actors[actor]?.override = nil
        reevaluate(actor: actor, clock: clock, context: context)
    }

    public func override(for actor: ReferenceKey) -> PackageOverride? {
        actors[actor]?.override
    }

    /// On-demand seam for the AI gate panel.
    public mutating func forceReevaluate(
        actor: ReferenceKey,
        clock: GameClock,
        context: ConditionContext
    ) {
        reevaluate(actor: actor, clock: clock, context: context)
    }

    public func currentPackage(for actor: ReferenceKey) -> ResolvedPackage? {
        actors[actor]?.current
    }

    public func readouts() -> [PackageActorReadout] {
        actors.keys.sorted().compactMap { actors[$0]?.readout(actor: $0) }
    }

    private mutating func reevaluate(
        actor: ReferenceKey,
        clock: GameClock,
        context: ConditionContext
    ) {
        guard var state = actors[actor] else { return }
        var evaluationContext = context
        evaluationContext.subject = actor
        evaluationContext.clock = clock
        let previous = state.current?.package.formID
        let stack = state.override?.packages ?? state.stack
        state.current = select(stack: stack, clock: clock, context: &evaluationContext)
        state.lastEvaluationGameSeconds = clock.totalGameSeconds
        state.nextEvaluationGameSeconds = nextEvaluation(after: clock, stack: stack)
        actors[actor] = state
        if previous != state.current?.package.formID {
            onSelectionChanged?(state.readout(actor: actor))
        }
    }

    private func select(
        stack: [FormID],
        clock: GameClock,
        context: inout ConditionContext
    ) -> ResolvedPackage? {
        for id in stack {
            guard let package = try? store.resolve(id) else { continue }
            guard package.package.schedule.matches(clock) else { continue }
            var evaluator = ConditionEvaluator(context: context)
            let outcome = evaluator.evaluate(package.package.conditions)
            context = evaluator.context
            if outcome.isTrue {
                return package
            }
        }
        return nil
    }

    private func nextEvaluation(after clock: GameClock, stack: [FormID]) -> Double {
        let interval = Self.maximumReevaluationGameMinutes
        let boundary = stack.compactMap { id in
            try? store.resolve(id).package.schedule.minutesUntilBoundary(after: clock)
        }.compactMap(\.self).min()
        let minutes = min(interval, boundary ?? interval)
        return clock.totalGameSeconds + Double(minutes * 60)
    }

    private struct ActorState {
        let base: FormID
        let stack: [FormID]
        var current: ResolvedPackage?
        var lastEvaluationGameSeconds: Double?
        var nextEvaluationGameSeconds: Double?
        var isSuspended = false
        var override: PackageOverride?

        func needsEvaluation(at clock: GameClock) -> Bool {
            guard
                let last = lastEvaluationGameSeconds,
                let next = nextEvaluationGameSeconds
            else { return true }
            return clock.totalGameSeconds < last || clock.totalGameSeconds >= next
        }

        func readout(actor: ReferenceKey) -> PackageActorReadout {
            PackageActorReadout(
                actor: actor,
                actorBase: base,
                currentPackage: current?.package.formID,
                editorID: current?.package.editorID,
                schedule: current?.package.schedule,
                procedure: current?.procedure,
                lastEvaluationGameSeconds: lastEvaluationGameSeconds,
                isSuspended: isSuspended,
                override: override?.owner
            )
        }
    }
}
