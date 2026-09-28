// The perception pass (issue #202, roadmap item 16.6): who looks at whom, how
// often, and what that costs.
//
// Main-actor, like the other directors, advanced from the same paused-aware
// world delta the actor-value runtime, the ragdolls and the combat loop take,
// and everything it touches the world with goes through `PerceptionWorld` — so
// the whole runtime is testable against a fake.
//
// ## Three bounds, all named
//
// Perception is the first subsystem in this engine whose cost is quadratic in
// the world rather than linear: every observer against every target. Left
// unbounded that is a line-of-sight raycast per pair per step, and the raycast
// is the expensive half. So:
//
//   * `maximumPairs` caps how many pairs exist at all. Past it the nearest
//     pairs win and the rest are dropped, and `droppedPairCount` says how many —
//     a silent truncation would read as "nothing else was nearby".
//   * `pairsPerStep` caps how many are re-evaluated per fixed step, round-robin
//     over a stable order. A pair evaluated every eighth step is advanced by
//     the elapsed time since it was last looked at, so slicing changes when a
//     level is recomputed and not what it converges to.
//   * `maximumStepsPerAdvance` caps how much simulated time one frame may
//     spend, exactly as `CombatLoopRuntime` and `ActorValueRuntime` cap theirs.
//
// ## Deterministic given the same inputs
//
// The roster is sorted by `ReferenceKey` before it is paired, the slice cursor
// advances by a fixed stride, and every accumulation is a pure function of the
// elapsed seconds. Two runs over the same recorded inputs produce the same
// levels, which is what the acceptance tests pin.
//
// Documented in docs/engine/detection.md.

import Foundation
import simd

/// One observer-target pair's identity.
nonisolated struct DetectionPairKey: Hashable, Comparable, Sendable {
    let observer: ReferenceKey
    let target: ReferenceKey

    static func < (lhs: DetectionPairKey, rhs: DetectionPairKey) -> Bool {
        (lhs.observer, lhs.target) < (rhs.observer, rhs.target)
    }
}

@MainActor
final class PerceptionRuntime {
    /// Step the pass advances on, matching the combat loop's and the
    /// actor-value runtime's so one frame drives all three the same way. 1/60 s.
    static let fixedStepSeconds: Float = 1.0 / 60

    /// Most whole steps one `advance(by:)` runs, so a multi-second stall cannot
    /// spend a minute of watching in a single frame.
    static let maximumStepsPerAdvance = 8

    /// Most pairs tracked at once. Eight movers is `NPCMovementRuntime`'s named
    /// crowd cap and a handful of targets is all 16.6 produces, so 64 leaves
    /// room above anything the milestone creates while still bounding the work.
    static let maximumPairs = 64

    /// Pairs re-evaluated per fixed step. At the cap this spreads a full sweep
    /// over eight steps, or about an eighth of a second — far below the time a
    /// detection level takes to cross a threshold.
    static let pairsPerStep = 8

    let settings: DetectionSettings

    /// Every tracked pair's state, keyed by the pair.
    private(set) var pairs: [DetectionPairKey: DetectionPairState] = [:]
    /// The observers the last roster refresh found, in evaluation order.
    private(set) var observers: [PerceptionObserver] = []
    /// The targets the last roster refresh found, in evaluation order.
    private(set) var targets: [PerceptionTarget] = []
    /// Pairs the cap dropped at the last roster refresh.
    private(set) var droppedPairCount = 0
    /// Line-of-sight rays cast since construction, cumulative. The pass's cost
    /// in the one unit that matters.
    private(set) var lineOfSightQueryCount = 0
    /// Whole fixed steps run since construction.
    private(set) var stepCount = 0

    private weak var world: (any PerceptionWorld)?
    private var accumulator: Double = 0
    /// Evaluation order, rebuilt per `advance(by:)`.
    private var order: [DetectionPairKey] = []
    /// Where the next slice starts in `order`.
    private var cursor = 0
    /// Step index each pair was last advanced at, so a sliced evaluation knows
    /// how much simulated time to charge it.
    private var lastEvaluatedStep: [DetectionPairKey: Int] = [:]

    init(settings: DetectionSettings, world: (any PerceptionWorld)? = nil) {
        self.settings = settings
        self.world = world
    }

    /// Attaches (or detaches) the world the pass runs over.
    func attach(world: (any PerceptionWorld)?) {
        self.world = world
        reset()
    }

    // MARK: - Reading

    /// `observer`'s regard for `target`, unaware when the pair is not tracked.
    func state(observer: ReferenceKey, target: ReferenceKey) -> DetectionPairState {
        pairs[DetectionPairKey(observer: observer, target: target)] ?? .unaware
    }

    /// The strongest state any observer holds about `target`, which is what a
    /// "am I detected?" question means from the target's side.
    func strongestState(of target: ReferenceKey) -> DetectionState {
        var strongest = DetectionState.unaware
        for (key, pair) in pairs where key.target == target {
            if pair.state == .detected {
                return .detected
            }
            if pair.state == .suspicious {
                strongest = .suspicious
            }
        }
        return strongest
    }

    /// Every observer that currently detects `target`, in ascending observer
    /// order.
    ///
    /// The witness list a crime is judged against (issue #504). Detection only:
    /// an observer that is merely suspicious has not seen anything, and the
    /// order is sorted rather than dictionary order so two runs over the same
    /// recorded inputs name the same witnesses in the same sequence.
    func observersDetecting(_ target: ReferenceKey) -> [ReferenceKey] {
        pairs
            .filter { $0.key.target == target && $0.value.state == .detected }
            .map(\.key.observer)
            .sorted()
    }

    // MARK: - Frames

    /// Advances perception by a wall delta, running whole fixed steps only.
    ///
    /// A zero delta advances nothing and is safe to call every frame — the
    /// established menu-pause rule. A negative or non-finite delta is treated
    /// the same way rather than run backwards.
    ///
    /// - Returns: how many whole steps ran.
    @discardableResult
    func advance(by delta: Float) -> Int {
        guard delta.isFinite, delta > 0, let world else { return 0 }
        accumulator += Double(delta)
        guard accumulator >= Double(Self.fixedStepSeconds) else { return 0 }
        // Once per frame, not once per step: the roster is a pass over resident
        // actors and re-collecting it eight times would cost eight times as much
        // for a world that moved by a fraction of a step.
        refreshRoster(world: world)
        var steps = 0
        while accumulator >= Double(Self.fixedStepSeconds), steps < Self.maximumStepsPerAdvance {
            accumulator -= Double(Self.fixedStepSeconds)
            step(world: world)
            steps += 1
        }
        accumulator = min(
            accumulator,
            Double(Self.fixedStepSeconds) * Double(Self.maximumStepsPerAdvance)
        )
        return steps
    }

    /// Forgets every tracked pair and every counter.
    func reset() {
        pairs = [:]
        observers = []
        targets = []
        order = []
        lastEvaluatedStep = [:]
        droppedPairCount = 0
        lineOfSightQueryCount = 0
        stepCount = 0
        cursor = 0
        accumulator = 0
    }

    // MARK: - Private

    /// Collects observers and targets, builds the capped pair order, and drops
    /// the state of every pair that no longer exists.
    private func refreshRoster(world: any PerceptionWorld) {
        observers = world.perceptionObservers().sorted { $0.key < $1.key }
        targets = world.perceptionTargets().sorted { $0.key < $1.key }
        var candidates: [(key: DetectionPairKey, distance: Float)] = []
        for observer in observers {
            for target in targets where target.key != observer.key {
                candidates.append((
                    DetectionPairKey(observer: observer.key, target: target.key),
                    PerceptionSight.distance(observer: observer, target: target)
                ))
            }
        }
        // Nearest first past the cap, then back to key order so evaluation stays
        // stable while actors move: a slice cursor over a distance-sorted list
        // would re-slice differently every frame.
        candidates.sort { ($0.distance, $0.key) < ($1.distance, $1.key) }
        droppedPairCount = max(0, candidates.count - Self.maximumPairs)
        order = candidates.prefix(Self.maximumPairs).map(\.key).sorted()
        let live = Set(order)
        pairs = pairs.filter { live.contains($0.key) }
        lastEvaluatedStep = lastEvaluatedStep.filter { live.contains($0.key) }
        if cursor >= order.count {
            cursor = 0
        }
    }

    /// One fixed step: advance the next slice of pairs.
    private func step(world: any PerceptionWorld) {
        stepCount += 1
        guard !order.isEmpty else { return }
        let observerIndex = Dictionary(
            uniqueKeysWithValues: observers.map { ($0.key, $0) }
        )
        let targetIndex = Dictionary(uniqueKeysWithValues: targets.map { ($0.key, $0) })
        let count = min(Self.pairsPerStep, order.count)
        for offset in 0 ..< count {
            let key = order[(cursor + offset) % order.count]
            guard
                let observer = observerIndex[key.observer],
                let target = targetIndex[key.target]
            else { continue }
            evaluate(key: key, observer: observer, target: target, world: world)
        }
        cursor = (cursor + count) % order.count
    }

    /// One pair, advanced by the simulated time since it was last looked at.
    private func evaluate(
        key: DetectionPairKey,
        observer: PerceptionObserver,
        target: PerceptionTarget,
        world: any PerceptionWorld
    ) {
        let previous = pairs[key] ?? .unaware
        let elapsedSteps = lastEvaluatedStep[key].map { stepCount - $0 } ?? 1
        let distance = PerceptionSight.distance(observer: observer, target: target)
        // The ray is the expensive half, so it is skipped outright for a pair
        // already past the range where either sense could reach. The formula
        // would multiply everything by a zero attenuation anyway.
        let maximum = DetectionFormula.maximumDistance(
            settings: settings, isExterior: observer.isExterior
        )
        let hasLineOfSight: Bool
        if distance < maximum {
            lineOfSightQueryCount += 1
            hasLineOfSight = world.perceptionHasLineOfSight(from: observer.eye, to: target.eye)
        } else {
            hasLineOfSight = false
        }
        let inputs = DetectionInputs(
            distance: distance,
            hasLineOfSight: hasLineOfSight,
            isInViewCone: PerceptionSight.isInViewCone(
                observer: observer, target: target, cosine: settings.viewConeCosine
            ),
            isExterior: observer.isExterior,
            isSneaking: target.isSneaking,
            gait: target.gait,
            equippedWeight: target.equippedWeight
        )
        pairs[key] = previous.advanced(
            inputs: inputs,
            targetPosition: target.feet,
            by: Float(elapsedSteps) * Self.fixedStepSeconds,
            settings: settings
        )
        lastEvaluatedStep[key] = stepCount
    }
}
