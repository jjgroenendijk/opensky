// The perception pass: who looks at whom, and at what cost. Three named bounds:
// `maximumPairs` (nearest win; `droppedPairCount` counts the rest),
// `pairsPerStep` round-robin, and `maximumStepsPerAdvance`. The roster is sorted
// by `ReferenceKey`, so runs are deterministic. See docs/engine/detection.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyPerceptionInterface
import simd

@MainActor
public final class PerceptionRuntime {
    /// Step the pass advances on, matching the combat loop's and the
    /// actor-value runtime's so one frame drives all three the same way. 1/60 s.
    public static let fixedStepSeconds: Float = 1.0 / 60

    /// Most whole steps one `advance(by:)` runs, so a multi-second stall cannot
    /// spend a minute of watching in a single frame.
    public static let maximumStepsPerAdvance = 8

    /// Most pairs tracked at once. Eight movers is `NPCMovementRuntime`'s named
    /// crowd cap and a handful of targets is all 16.6 produces, so 64 leaves
    /// room above anything the milestone creates while still bounding the work.
    public static let maximumPairs = 64

    /// Pairs re-evaluated per fixed step. At the cap this spreads a full sweep
    /// over eight steps, or about an eighth of a second — far below the time a
    /// detection level takes to cross a threshold.
    public static let pairsPerStep = 8

    public let settings: DetectionSettings
    public let stealthPoints: StealthPointSettings
    /// Each target's stealth points.
    public private(set) var pools: [ReferenceKey: StealthPointPool] = [:]
    /// Pairs whose observer has the target detected through the pool.
    private var detectedPairs: Set<DetectionPairKey> = []

    /// Every tracked pair's state, keyed by the pair.
    public private(set) var pairs: [DetectionPairKey: DetectionPairState] = [:]
    /// The observers the last roster refresh found, in evaluation order.
    public private(set) var observers: [PerceptionObserver] = []
    /// The targets the last roster refresh found, in evaluation order.
    public private(set) var targets: [PerceptionTarget] = []
    /// Pairs the cap dropped at the last roster refresh.
    public private(set) var droppedPairCount = 0
    /// Line-of-sight rays cast since construction, cumulative. The pass's cost
    /// in the one unit that matters.
    public private(set) var lineOfSightQueryCount = 0
    /// Whole fixed steps run since construction.
    public private(set) var stepCount = 0

    private weak var world: (any PerceptionWorld)?
    private var accumulator: Double = 0
    /// The roster in key order, kept between frames while its members stay.
    private var observerOrder = ReferenceKeyOrder()
    private var targetOrder = ReferenceKeyOrder()
    /// Evaluation order. It is rebuilt only when the roster's members change, or
    /// when the cap applies and the nearest pairs can change.
    private var order: [DetectionPairKey] = []
    /// The roster keys `order` was built from.
    private var orderRoster: (observers: [ReferenceKey], targets: [ReferenceKey])?
    /// The roster by key, built once per frame for every step of that frame.
    private var observerIndex: [ReferenceKey: PerceptionObserver] = [:]
    private var targetIndex: [ReferenceKey: PerceptionTarget] = [:]
    /// Where the next slice starts in `order`.
    private var cursor = 0
    /// Step index each pair was last advanced at, so a sliced evaluation knows
    /// how much simulated time to charge it.
    private var lastEvaluatedStep: [DetectionPairKey: Int] = [:]

    public init(
        settings: DetectionSettings,
        stealthPoints: StealthPointSettings = .vanilla,
        world: (any PerceptionWorld)? = nil
    ) {
        self.settings = settings
        self.stealthPoints = stealthPoints
        self.world = world
    }

    // MARK: - Reading

    /// `observer`'s regard for `target`, unaware when the pair is not tracked.
    public func state(observer: ReferenceKey, target: ReferenceKey) -> DetectionPairState {
        pairs[DetectionPairKey(observer: observer, target: target)] ?? .unaware
    }

    /// Every observer that currently detects `target`, in ascending order: the
    /// witness list for a crime. Suspicion does not count.
    public func observersDetecting(_ target: ReferenceKey) -> [ReferenceKey] {
        pairs
            .filter { $0.key.target == target && $0.value.state == .detected }
            .map(\.key.observer)
            .sorted()
    }

    public func observersWitnessing(_ target: ReferenceKey) -> [ReferenceKey] {
        pairs
            .filter { $0.key.target == target && $0.value.levelState == .detected }
            .map(\.key.observer)
            .sorted()
    }

    // MARK: - Events

    /// `target` struck someone: its pool waits `fCombatStealthPointRegenAttackedWaitTime`.
    public func noteAttack(by target: ReferenceKey) {
        holdRefill(of: target, for: stealthPoints.attackedWait)
    }

    /// A detection event of `owner` at `position`, such as a landed arrow (CK wiki
    /// "Category:Detection"). An aggressive observer within range makes the pool wait.
    public func noteDetectionEvent(owner: ReferenceKey, at position: SIMD3<Float>) {
        let heard = observers.contains { observer in
            observer.isAggressive && observer.key != owner
                && DetectionFormula.isInRange(
                    distance: simd_distance(observer.feet, position), settings: settings,
                    isExterior: observer.isExterior, isFlying: observer.isFlying
                )
        }
        guard heard else { return }
        holdRefill(of: owner, for: stealthPoints.detectedEventWait)
    }

    private func holdRefill(of target: ReferenceKey, for seconds: Float) {
        var pool = pools[target] ?? StealthPointPool(settings: stealthPoints)
        pool.holdRefill(for: seconds)
        pools[target] = pool
    }

    // MARK: - Frames

    /// Advances perception by a wall delta, running whole fixed steps only. A zero,
    /// negative, or non-finite delta runs nothing.
    /// - Returns: how many whole steps ran.
    @discardableResult
    public func advance(by delta: Float) -> Int {
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
    public func reset() {
        pairs = [:]
        pools = [:]
        detectedPairs = []
        observers = []
        targets = []
        order = []
        orderRoster = nil
        observerIndex = [:]
        targetIndex = [:]
        lastEvaluatedStep = [:]
        droppedPairCount = 0
        lineOfSightQueryCount = 0
        stepCount = 0
        cursor = 0
        accumulator = 0
    }

    // MARK: - Private

    /// Collects observers and targets with their current positions. The pair order
    /// stays while the same actors are present and every pair fits under the cap.
    private func refreshRoster(world: any PerceptionWorld) {
        observers = observerOrder.sorted(world.perceptionObservers(), by: \.key)
        targets = targetOrder.sorted(world.perceptionTargets(), by: \.key)
        observerIndex = Dictionary(observers.map { ($0.key, $0) }) { first, _ in first }
        targetIndex = Dictionary(targets.map { ($0.key, $0) }) { first, _ in first }
        let roster = (observers: observers.map(\.key), targets: targets.map(\.key))
        if
            droppedPairCount == 0,
            let orderRoster,
            orderRoster.observers == roster.observers,
            orderRoster.targets == roster.targets
        {
            return
        }
        orderRoster = roster
        rebuildOrder()
    }

    /// Builds the capped pair order and drops the state of every pair outside it.
    private func rebuildOrder() {
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
        // Under the cap the loops above already built key order, so nothing sorts.
        droppedPairCount = max(0, candidates.count - Self.maximumPairs)
        if droppedPairCount == 0 {
            order = candidates.map(\.key)
        } else {
            candidates.sort { ($0.distance, $0.key) < ($1.distance, $1.key) }
            order = candidates.prefix(Self.maximumPairs).map(\.key).sorted()
        }
        let live = Set(order)
        pairs = pairs.filter { live.contains($0.key) }
        lastEvaluatedStep = lastEvaluatedStep.filter { live.contains($0.key) }
        detectedPairs = detectedPairs.filter { live.contains($0) }
        if cursor >= order.count {
            cursor = 0
        }
    }

    /// One fixed step: advance the next slice of pairs.
    private func step(world: any PerceptionWorld) {
        stepCount += 1
        guard !order.isEmpty else { return }
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
        updateStealthPoints()
    }

    /// Drains or refills each target's pool from the highest detection value of an
    /// aggressive observer, then reads those pairs through the pool.
    private func updateStealthPoints() {
        detectedPairs = detectedPairs.filter { observerIndex[$0.observer]?.isAggressive == true }
        for target in targets {
            let keys = order.filter {
                $0.target == target.key && observerIndex[$0.observer]?.isAggressive == true
            }
            let values = keys.map { pairs[$0]?.breakdown.value ?? 0 }
            let threshold = stealthPoints.threshold(isSneaking: target.isSneaking)
            var pool = pools[target.key] ?? StealthPointPool(settings: stealthPoints)
            pool.advance(
                highestValue: values.max() ?? 0,
                overThreshold: values.contains { $0 >= threshold },
                by: Self.fixedStepSeconds,
                settings: stealthPoints
            )
            pools[target.key] = pool
            for key in keys {
                guard var pair = pairs[key] else { continue }
                let detected = pool.detects(
                    value: pair.breakdown.value, isSneaking: target.isSneaking,
                    wasDetected: detectedPairs.contains(key), settings: stealthPoints
                )
                if detected {
                    detectedPairs.insert(key)
                    pair.state = .detected
                } else {
                    detectedPairs.remove(key)
                    pair.state = pair.levelState == .detected ? .suspicious : pair.levelState
                }
                pairs[key] = pair
            }
        }
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
        let hasLineOfSight: Bool
        if
            DetectionFormula.isInRange(
                distance: distance, settings: settings, isExterior: observer.isExterior,
                isFlying: observer.isFlying
            )
        {
            lineOfSightQueryCount += 1
            hasLineOfSight = world.perceptionHasLineOfSight(from: observer.eye, to: target.eye)
        } else {
            hasLineOfSight = false
        }
        var inputs = DetectionInputs(
            distance: distance,
            hasLineOfSight: hasLineOfSight,
            isInViewCone: PerceptionSight.isInViewCone(
                observer: observer, target: target, cosine: settings.viewConeCosine
            ),
            isExterior: observer.isExterior,
            isSneaking: target.isSneaking,
            gait: target.gait,
            traits: target.traits,
            noticerSkill: observer.sneakSkill
        )
        inputs.observer = DetectionObserverState(
            isAlert: previous.state == .suspicious,
            isSleeping: observer.isSleeping,
            isFlying: observer.isFlying,
            blindness: observer.blindness,
            isFightingAnother: observer.combatTarget.map { $0 != target.key } ?? false
        )
        inputs.isPlayerTarget = target.key == .player
        pairs[key] = previous.advanced(
            inputs: inputs,
            targetPosition: target.feet,
            by: Float(elapsedSteps) * Self.fixedStepSeconds,
            settings: settings
        )
        lastEvaluatedStep[key] = stepCount
    }
}

extension PerceptionRuntime: DetectionObserving {}
