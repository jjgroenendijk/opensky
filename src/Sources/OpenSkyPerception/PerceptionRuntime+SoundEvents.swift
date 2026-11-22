// The last sound event of each target, and the check an observer runs on it when sight
// gives nothing. See docs/engine/detection-events.md.

public import OpenSkyFormatsESM
public import OpenSkyPerceptionInterface
import OpenSkyPhysics
import simd

/// An event with the observers that already reacted to it.
struct HeardSoundEvent {
    var event: DetectionSoundEvent
    var heardBy: Set<ReferenceKey> = []
}

extension PerceptionRuntime {
    /// `owner` made a sound of `level` at `position`. It replaces the owner's last event.
    public func noteSoundEvent(owner: ReferenceKey, level: Float, at position: SIMD3<Float>) {
        guard level.isFinite, level >= 0 else { return }
        soundEvents[owner] = HeardSoundEvent(
            event: DetectionSoundEvent(level: level, position: position)
        )
    }

    /// A summon is a loud sound of its caster at the place of the summon.
    public func noteSummon(by caster: ReferenceKey, at position: SIMD3<Float>) {
        noteSoundEvent(owner: caster, level: settings.actionSound(for: .loud), at: position)
    }

    /// The live event of `owner`.
    public func soundEvent(of owner: ReferenceKey) -> DetectionSoundEvent? {
        soundEvents[owner]?.event
    }

    /// A cast keeps its caster's event new for as long as it lasts. The observers that
    /// heard the cast do not react a second time.
    func noteCastingSounds() {
        for target in targets where target.traits.castingSound > 0 {
            let heardBy = soundEvents[target.key]?.heardBy ?? []
            noteSoundEvent(owner: target.key, level: target.traits.castingSound, at: target.feet)
            soundEvents[target.key]?.heardBy = heardBy
        }
    }

    func ageSoundEvents() {
        for key in Array(soundEvents.keys) {
            soundEvents[key]?.event.age += Self.fixedStepSeconds
        }
        soundEvents = soundEvents.filter { $0.value.event.age < DetectionEventRule.expireSeconds }
    }

    /// An aggressive observer that perceives nothing of the target checks the target's
    /// last event. A positive value makes it suspicious, with the event as the place to
    /// search, and makes the target's stealth points wait.
    func checkSoundEvent(
        key: DetectionPairKey, observer: PerceptionObserver, target: PerceptionTarget,
        inputs: DetectionInputs
    ) {
        guard
            observer.isAggressive, let heard = soundEvents[key.target], var pair = pairs[key],
            !pair.breakdown.isPerceiving, let world
        else { return }
        let event = heard.event
        // An observer that heard the event stays suspicious for as long as the event lasts.
        guard !heard.heardBy.contains(key.observer) else {
            pairs[key] = pair.suspicious(of: event.position, settings: settings)
            return
        }
        let distance = simd_distance(observer.feet, event.position)
        let reach = DetectionEventRule.hearingDistance(
            level: event.level, isPlayerSound: key.target == .player
        )
        guard distance <= reach else { return }
        lineOfSightQueryCount += 1
        let offset = SIMD2(event.position.x - observer.feet.x, event.position.y - observer.feet.y)
        let length = simd_length(offset)
        let sight = DetectionEventSight(
            distance: distance,
            hasLineOfSight: world.perceptionHasLineOfSight(
                from: observer.eye, to: event.position + (target.eye - target.feet)
            ),
            isInViewCone: length <= Float.ulpOfOne
                || simd_dot(offset / length, observer.heading) >= settings.viewConeCosine
        )
        let value = DetectionEventRule.value(
            of: event, sight: sight, inputs: inputs, settings: settings
        )
        guard value > 0 else { return }
        soundEvents[key.target]?.heardBy.insert(key.observer)
        var pool = pools[key.target] ?? StealthPointPool(settings: stealthPoints)
        pool.holdRefill(for: stealthPoints.detectedEventWait)
        pool.cap(at: CombatTargetTrack.eventPointCap)
        pools[key.target] = pool
        tracks[key.target, default: CombatTargetTrack()].addSearchPlace(event.position)
        pair = pair.suspicious(of: event.position, settings: settings)
        pairs[key] = pair
    }
}

extension DetectionPairState {
    /// At least suspicious, with `place` as the place to search.
    func suspicious(of place: SIMD3<Float>, settings: DetectionSettings) -> DetectionPairState {
        var pair = self
        pair.level = max(pair.level, settings.suspiciousLevel.value)
        if pair.state == .unaware {
            pair.state = .suspicious
        }
        if pair.levelState == .unaware {
            pair.levelState = .suspicious
        }
        pair.lastKnownPosition = place
        return pair
    }
}
