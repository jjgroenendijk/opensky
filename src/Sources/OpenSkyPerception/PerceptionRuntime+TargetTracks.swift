// Stealth points and the record of each target that hostile observers share. See
// docs/engine/detection.md#keeping-a-combat-target.

public import OpenSkyFormatsESM
public import OpenSkyPerceptionInterface
import OpenSkyPhysics
import simd

extension PerceptionRuntime {
    /// `target` struck a hostile observer: its pool waits
    /// `fCombatStealthPointRegenAttackedWaitTime` and holds at most 50 points, and the
    /// observers search where it stood.
    public func noteAttack(by target: ReferenceKey) {
        var pool = pools[target] ?? StealthPointPool(settings: stealthPoints)
        pool.holdRefill(for: stealthPoints.attackedWait)
        pool.cap(at: CombatTargetTrack.hitPointCap)
        pools[target] = pool
        if let position = targetIndex[target]?.feet {
            tracks[target, default: CombatTargetTrack()].addSearchPlace(position)
        }
    }

    /// A detection event of `owner` at `position`, such as a landed arrow (CK wiki
    /// "Category:Detection"). An aggressive observer within range makes the pool wait
    /// and turns alert: suspicious of the owner, with the event as the place to search.
    public func noteDetectionEvent(owner: ReferenceKey, at position: SIMD3<Float>) {
        let hearing = observers.filter { observer in
            observer.isAggressive && observer.key != owner
                && DetectionFormula.isInRange(
                    distance: simd_distance(observer.feet, position), settings: settings,
                    isExterior: observer.isExterior, isFlying: observer.isFlying
                )
        }
        guard !hearing.isEmpty else { return }
        var pool = pools[owner] ?? StealthPointPool(settings: stealthPoints)
        pool.holdRefill(for: stealthPoints.detectedEventWait)
        pool.cap(at: CombatTargetTrack.eventPointCap)
        pools[owner] = pool
        tracks[owner, default: CombatTargetTrack()].addSearchPlace(position)
        for observer in hearing {
            let key = DetectionPairKey(observer: observer.key, target: owner)
            var pair = pairs[key] ?? .unaware
            if pair.state == .unaware {
                pair.level = max(pair.level, settings.suspiciousLevel.value)
                pair.state = .suspicious
                pair.levelState = .suspicious
            }
            pair.lastKnownPosition = position
            pairs[key] = pair
        }
    }

    /// The record hostile observers share of `target`.
    public func targetTrack(of target: ReferenceKey) -> CombatTargetTrack {
        tracks[target] ?? CombatTargetTrack()
    }

    /// Drains or refills each target's pool from the highest detection value of an
    /// aggressive observer, then reads those pairs through the pool and the record.
    func updateStealthPoints(world: any PerceptionWorld) {
        detectedPairs = detectedPairs.filter { observerIndex[$0.observer]?.isAggressive == true }
        for target in targets {
            let keys = order.filter {
                $0.target == target.key && observerIndex[$0.observer]?.isAggressive == true
            }
            let values = keys.map { pairs[$0]?.breakdown.value ?? 0 }
            let highest = values.max() ?? 0
            let threshold = stealthPoints.threshold(isSneaking: target.isSneaking)
            var pool = pools[target.key] ?? StealthPointPool(settings: stealthPoints)
            var track = tracks[target.key] ?? CombatTargetTrack()
            let wasLost = track.phase == .lost
            let isOver = values.contains { $0 >= threshold }
            var sighting = CombatTargetSighting(
                value: highest, counts: isOver || (highest > 0 && pool.points <= 0),
                position: target.feet
            )
            fill(&sighting, keys: keys, target: target, world: world)
            if track.advance(sighting, by: Self.fixedStepSeconds) {
                pool = StealthPointPool(settings: stealthPoints)
            }
            if track.phase == .lost, !wasLost {
                pool.holdRefill(for: stealthPoints.refillWait)
            }
            pool.advance(
                highestValue: highest, overThreshold: isOver, by: Self.fixedStepSeconds,
                settings: stealthPoints, mayRefill: track.phase != .noticed
            )
            pools[target.key] = pool
            tracks[target.key] = track
            for key in keys {
                apply(track, threshold: threshold, to: key)
            }
        }
    }

    /// What the members see of the target and of its last known position.
    private func fill(
        _ sighting: inout CombatTargetSighting, keys: [DetectionPairKey],
        target: PerceptionTarget, world: any PerceptionWorld
    ) {
        sighting.isInvisible = target.traits.isInvisible
        sighting.memberSeesTarget = keys.contains {
            pairs[$0]?.hasLineOfSight == true && pairs[$0]?.isInViewCone == true
        }
        let engaged = keys.compactMap { observerIndex[$0.observer] }
            .filter { $0.combatTarget == target.key }
        sighting.hasEngagedMember = !engaged.isEmpty
        sighting.nearestMember = engaged.map { simd_distance($0.feet, target.feet) }.min()
            ?? .infinity
        guard
            sighting.value < 0, let track = tracks[target.key], track.isListed,
            track.phase != .noticed, let lastKnown = track.lastKnown
        else { return }
        let height = target.eye - target.feet
        for observer in keys.compactMap({ observerIndex[$0.observer] })
            where simd_distance(observer.feet, lastKnown) <= CombatTargetTrack.lastKnownCheckRadius
        {
            lineOfSightQueryCount += 1
            if world.perceptionHasLineOfSight(from: observer.eye, to: lastKnown + height) {
                sighting.memberSeesLastKnown = true
                return
            }
        }
    }

    /// One observer's state: detected over the threshold, or while the target is noticed
    /// and the observer perceives it or detected it before.
    private func apply(_ track: CombatTargetTrack, threshold: Float, to key: DetectionPairKey) {
        guard var pair = pairs[key] else { return }
        let value = pair.breakdown.value
        let keeps = track.phase == .noticed && (value > 0 || detectedPairs.contains(key))
        if value >= threshold || keeps {
            detectedPairs.insert(key)
            pair.state = .detected
        } else {
            detectedPairs.remove(key)
            pair.state = pair.levelState == .detected ? .suspicious : pair.levelState
        }
        if track.isListed, let lastKnown = track.lastKnown {
            pair.lastKnownPosition = lastKnown
        }
        pairs[key] = pair
    }
}
