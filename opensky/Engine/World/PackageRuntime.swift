// Schedule/condition package selection for resident actors (issue #201).
// Evaluation is event-driven: exact daily schedule edges, a bounded game-time
// interval for calendar/condition changes, and an explicit panel seam.

import Foundation

nonisolated struct PackageActorReadout: Equatable, Sendable {
    let actor: ReferenceKey
    let actorBase: FormID
    let currentPackage: FormID?
    let editorID: String?
    let schedule: Package.Schedule?
    let procedure: PackageProcedureKind?
    let lastEvaluationGameSeconds: Double?
}

nonisolated struct ActorPackageRuntime {
    static let maximumReevaluationGameMinutes: Float = 15

    var onSelectionChanged: ((PackageActorReadout) -> Void)?

    private let store: PackageStore
    private var actors: [ReferenceKey: ActorState] = [:]

    init(store: PackageStore) {
        self.store = store
    }

    mutating func register(actor: ReferenceKey, base: FormID) throws {
        let stack = try store.packageStack(for: base).value
        actors[actor] = ActorState(base: base, stack: stack)
    }

    mutating func unregister(actor: ReferenceKey) {
        actors.removeValue(forKey: actor)
    }

    mutating func advance(
        clock: GameClock,
        context: (ReferenceKey) -> ConditionContext
    ) {
        for actor in actors.keys.sorted() {
            guard let state = actors[actor], state.needsEvaluation(at: clock) else { continue }
            reevaluate(actor: actor, clock: clock, context: context(actor))
        }
    }

    /// On-demand seam for the M16 gate panel.
    mutating func forceReevaluate(
        actor: ReferenceKey,
        clock: GameClock,
        context: ConditionContext
    ) {
        reevaluate(actor: actor, clock: clock, context: context)
    }

    func currentPackage(for actor: ReferenceKey) -> ResolvedPackage? {
        actors[actor]?.current
    }

    func readouts() -> [PackageActorReadout] {
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
                lastEvaluationGameSeconds: lastEvaluationGameSeconds
            )
        }
    }
}
