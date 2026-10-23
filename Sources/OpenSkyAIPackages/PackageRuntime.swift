// Schedule and condition package selection for resident actors. Event-driven: exact
// daily edges, a bounded game-time interval for other changes, and a readout seam.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldConditions
import OpenSkyWorldInterface
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
    /// Which list the current package came from.
    public var source: PackageSource?
    public var situation: PackageSituation?
    public var scriptPackage: FormID?

    public init(
        actor: ReferenceKey,
        actorBase: FormID,
        currentPackage: FormID?,
        editorID: String?,
        schedule: Package.Schedule?,
        procedure: PackageProcedureKind?,
        lastEvaluationGameSeconds: Double?,
        isSuspended: Bool = false,
        override: PackageOverrideOwner? = nil,
        source: PackageSource? = nil,
        situation: PackageSituation? = nil,
        scriptPackage: FormID? = nil
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
        self.source = source
        self.situation = situation
        self.scriptPackage = scriptPackage
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

/// The packages a quest alias adds ahead of its actor's own stack, from the
/// highest-priority quest that holds the actor (<https://ck.uesp.net/wiki/Quest_Alias_Tab>).
nonisolated public struct PackageAliasStack: Equatable, Sendable {
    public let packages: [FormID]
    /// The quest whose aliases the package locations name.
    public let quest: FormID

    public init(packages: [FormID], quest: FormID) {
        self.packages = packages
        self.quest = quest
    }
}

nonisolated public struct PackageHold: Equatable, Sendable {
    /// The quest whose aliases the package locations name.
    public let aliasQuest: FormID?
}

nonisolated public struct ActorPackageRuntime {
    public static let maximumReevaluationGameMinutes: Float = 15

    public var onSelectionChanged: ((PackageActorReadout) -> Void)?

    let store: PackageStore
    var actors: [ReferenceKey: ActorState] = [:]

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
        actors[actor] = try ActorState(base: base, lists: store.packageLists(for: base))
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

    /// Keeps a "Must Complete" package current until its tree ends, whatever the schedule
    /// and conditions say (<https://ck.uesp.net/wiki/Package_Flags>). Nil lets it go.
    public mutating func setCompleting(_ package: FormID?, actor: ReferenceKey) {
        actors[actor]?.completing = package
    }

    public func completing(for actor: ReferenceKey) -> FormID? {
        actors[actor]?.completing
    }

    /// The actor's own package ended its tree: a "Must Complete" package lets go, and a
    /// "Once Per Day" package is not picked again within its day.
    public mutating func packageEnded(
        actor: ReferenceKey, clock: GameClock, context: ConditionContext
    ) {
        actors[actor]?.completing = nil
        if actors[actor]?.source == .script {
            actors[actor]?.scriptPackage = nil
        }
        reevaluate(actor: actor, clock: clock, context: context, keepsOncePerDay: false)
    }

    public func override(for actor: ReferenceKey) -> PackageOverride? {
        actors[actor]?.override
    }

    /// Puts `stack` ahead of the actor's own packages and picks one now when it changed.
    public mutating func setAliasStack(
        _ stack: PackageAliasStack?,
        actor: ReferenceKey,
        clock: GameClock,
        context: () -> ConditionContext
    ) {
        guard actors[actor] != nil, actors[actor]?.aliasStack != stack else { return }
        actors[actor]?.aliasStack = stack
        reevaluate(actor: actor, clock: clock, context: context())
    }

    /// Set when a scene or a quest alias gave the actor its current package, so its
    /// procedure runs. Nil for a package of the actor's own.
    public func hold(for actor: ReferenceKey) -> PackageHold? {
        guard let state = actors[actor], let current = state.current?.package.formID else {
            return nil
        }
        if let override = state.override {
            return PackageHold(aliasQuest: override.aliasQuest)
        }
        if let alias = state.aliasStack, state.source == .alias, alias.packages.contains(current) {
            return PackageHold(aliasQuest: alias.quest)
        }
        return nil
    }

    /// On-demand seam for the AI gate readout.
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

    mutating func reevaluate(
        actor: ReferenceKey,
        clock: GameClock,
        context: ConditionContext,
        keepsOncePerDay: Bool = true
    ) {
        guard var state = actors[actor] else { return }
        var evaluationContext = context
        evaluationContext.subject = actor
        evaluationContext.clock = clock
        let previous = state.current?.package.formID
        state.dropSpentScriptPackage()
        if state.override != nil || state.completing == nil || state.completing != previous {
            state.completing = nil
            let pick = choose(
                for: state, clock: clock, context: &evaluationContext,
                ranToday: state.ranToday(at: clock, except: keepsOncePerDay ? previous : nil)
            )
            state.current = pick?.package
            state.source = pick?.source
            if pick?.source == .script {
                state.scriptPackage?.isPicked = true
            }
            state.noteOncePerDay(state.current?.package, at: clock)
        }
        state.lastEvaluationGameSeconds = clock.totalGameSeconds
        state.nextEvaluationGameSeconds = nextEvaluation(after: clock, stack: state.allPackages)
        actors[actor] = state
        if previous != state.current?.package.formID {
            onSelectionChanged?(state.readout(actor: actor))
        }
    }

    func select(
        stack: [FormID],
        clock: GameClock,
        context: inout ConditionContext,
        ranToday: Set<FormID>
    ) -> ResolvedPackage? {
        for id in stack where !ranToday.contains(id) {
            guard let package = try? store.resolve(id) else { continue }
            guard package.package.schedule.matches(clock) else { continue }
            var evaluator = ConditionEvaluator(context: context)
            evaluator.context.formIDTranslation = store.translation(of: id)
            let outcome = evaluator.evaluate(package.package.conditions)
            evaluator.context.formIDTranslation = context.formIDTranslation
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

    struct ActorState {
        let base: FormID
        let lists: ActorPackageLists
        var current: ResolvedPackage?
        var source: PackageSource?
        var situation: PackageSituation?
        var scriptPackage: ScriptPackageSlot?
        var lastEvaluationGameSeconds: Double?
        var nextEvaluationGameSeconds: Double?
        var isSuspended = false
        var override: PackageOverride?
        var aliasStack: PackageAliasStack?
        var completing: FormID?
        /// When each "Once Per Day" package was first picked in its current 24-hour block.
        var oncePerDayStarts: [FormID: Double] = [:]

        /// "Once Per Day" packages picked less than a day ago, other than `current`.
        func ranToday(at clock: GameClock, except current: FormID?) -> Set<FormID> {
            Set(oncePerDayStarts.filter {
                $0.key != current && clock.totalGameSeconds >= $0.value
                    && clock.totalGameSeconds - $0.value < GameClock.secondsPerDay
            }.keys)
        }

        mutating func noteOncePerDay(_ package: Package?, at clock: GameClock) {
            guard let package, package.general.flags.contains(.oncePerDay) else { return }
            let start = oncePerDayStarts[package.formID]
            if
                let start, clock.totalGameSeconds >= start,
                clock.totalGameSeconds - start < GameClock.secondsPerDay
            {
                return
            }
            oncePerDayStarts[package.formID] = clock.totalGameSeconds
        }

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
                override: override?.owner,
                source: source,
                situation: situation,
                scriptPackage: scriptPackage?.package
            )
        }
    }
}
