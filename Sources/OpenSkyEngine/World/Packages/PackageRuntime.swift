// Schedule/condition package selection for resident actors (issue #201).
// Evaluation is event-driven: exact daily schedule edges, a bounded game-time
// interval for calendar/condition changes, and an explicit panel seam.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct PackageActorReadout: Equatable, Sendable {
    public let actor: ReferenceKey
    public let actorBase: FormID
    public let currentPackage: FormID?
    public let editorID: String?
    public let schedule: Package.Schedule?
    public let procedure: PackageProcedureKind?
    public let lastEvaluationGameSeconds: Double?
    /// True while something outside the schedule is holding this actor — a
    /// conversation, as of issue #427. A suspended actor keeps the package it
    /// had, so the readout can say what it will go back to, and is not
    /// re-evaluated until it is released.
    public var isSuspended = false

    public init(
        actor: ReferenceKey,
        actorBase: FormID,
        currentPackage: FormID?,
        editorID: String?,
        schedule: Package.Schedule?,
        procedure: PackageProcedureKind?,
        lastEvaluationGameSeconds: Double?,
        isSuspended: Bool = false
    ) {
        self.actor = actor
        self.actorBase = actorBase
        self.currentPackage = currentPackage
        self.editorID = editorID
        self.schedule = schedule
        self.procedure = procedure
        self.lastEvaluationGameSeconds = lastEvaluationGameSeconds
        self.isSuspended = isSuspended
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

    /// Holds one actor out of scheduled selection, or hands it back
    /// (issue #427).
    ///
    /// Suspension is a latch and not a saved procedure. An actor that spent a
    /// conversation standing still has had the world move on around it, so what
    /// it needs on release is the package the schedule names *now*, which is
    /// what `forceReevaluate(actor:clock:context:)` answers — the same
    /// reasoning combat's own resume follows.
    public mutating func setSuspended(_ suspended: Bool, actor: ReferenceKey) {
        actors[actor]?.isSuspended = suspended
    }

    public func isSuspended(_ actor: ReferenceKey) -> Bool {
        actors[actor]?.isSuspended ?? false
    }

    /// On-demand seam for the M16 gate panel.
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
        state.current = select(stack: state.stack, clock: clock, context: &evaluationContext)
        state.lastEvaluationGameSeconds = clock.totalGameSeconds
        state.nextEvaluationGameSeconds = nextEvaluation(after: clock, stack: state.stack)
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
                isSuspended: isSuspended
            )
        }
    }
}
