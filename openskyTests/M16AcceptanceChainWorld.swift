// The two world seams the M16 chain answers (issue #203), split out of
// `M16AcceptanceChain.swift` for the strict-lint type-length cap — the same
// split `M15AcceptanceChainWorld.swift` made one milestone earlier.
//
// Both conformances read the *same* stored state the mover writes, which is the
// point: the perception pass and the combat loop see the guard where the path
// follower actually put it, not where the route said it should be. A harness
// that answered these from literals would be testing two runtimes over a
// diorama rather than a chain.

@testable import opensky
import simd

extension M16AcceptanceChain: PerceptionWorld {
    /// The guard, and only while it is alive. The narrow definition the app
    /// uses — hostile, engaged, or keeping a package — is met here by the
    /// package, which the schedule selects before the fight ever starts.
    func perceptionObservers() -> [PerceptionObserver] {
        guard !guardIsDead else { return [] }
        return [PerceptionObserver(
            key: Self.guardKey,
            feet: guardFeet,
            facing: 0,
            isExterior: guardFeet.x < Self.innOrigin,
            name: "Guard"
        )]
    }

    /// The player, and nothing else, exactly as the app's seam answers.
    func perceptionTargets() -> [PerceptionTarget] {
        [PerceptionTarget(
            key: .player,
            feet: playerFeet,
            gait: playerGait,
            isSneaking: playerGait == .sneak,
            name: "Player"
        )]
    }

    func perceptionHasLineOfSight(
        from origin: SIMD3<Float>,
        to destination: SIMD3<Float>
    ) -> Bool {
        !sightBlocked(origin, destination)
    }
}

extension M16AcceptanceChain: CombatLoopWorld {
    var combatPlayer: MeleeAttacker {
        MeleeAttacker(key: .player, feet: playerFeet, facing: 0)
    }

    func combatActors() -> [CombatActorObservation] {
        [CombatActorObservation(
            key: Self.guardKey,
            feet: guardFeet,
            isDead: guardIsDead,
            name: "Guard"
        )]
    }

    func combatHostility(of key: ReferenceKey) -> ActorHostility {
        hostilityState[key] ?? .neutral
    }

    @discardableResult
    func setCombatHostility(_ value: ActorHostility, on key: ReferenceKey) -> Bool {
        guard hostilityState[key] != value else { return false }
        hostilityState[key] = value
        return true
    }

    @discardableResult
    func applyCombatDamage(_: Float, to _: ReferenceKey) -> Bool {
        // The player's health is not part of this gate's claim: M15 pinned the
        // damage formula and `M15AcceptanceTests` drives it through a real
        // swing. What matters here is that the machine reached the phase that
        // asks for damage at all, which `visitedPhases` records.
        true
    }

    func combatBlock(of _: ReferenceKey) -> MeleeBlockKind? {
        nil
    }

    /// The real perception state, projected as the combat layer takes it. This
    /// is the join the whole chain exists to prove: nothing here decides whether
    /// the guard can see the player, it asks the pass that worked it out.
    func combatAwareness(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> CombatAwareness {
        let pair = perception.state(observer: observer, target: target)
        return CombatAwareness(state: pair.state, lastKnownPosition: pair.lastKnownPosition)
    }

    func combatHealthFraction(of _: ReferenceKey) -> Float {
        guardHealth
    }

    func combatWeapon(of _: ReferenceKey) -> MeleeWeaponProfile {
        .unarmed
    }

    /// The combat machine's movement command, routed into the *same* mover the
    /// package's travel procedure uses. An approach and a walk to the inn are
    /// therefore the same kind of thing, which is what 16.7 claimed when it
    /// declined to give combat a mover of its own.
    @discardableResult
    func moveCombatActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        guard key == Self.guardKey else { return false }
        return moveGuard(to: point) == .started
    }

    func stopCombatMovement(of key: ReferenceKey) {
        movement.stop(key)
    }

    /// Pursuit ended, so the guard goes back to its schedule. Recorded and
    /// performed: the route asserts both that the hand-off happened and that the
    /// package runtime answered it with a live selection.
    func resumeCombatPackage(for key: ReferenceKey) {
        packageResumeLog.append(key)
        packages.forceReevaluate(
            actor: key, clock: clock, context: ConditionContext(clock: clock)
        )
    }

    @discardableResult
    func raiseCombatEvent(_: String, on _: ReferenceKey?) -> Bool {
        // No behavior graph is attached to an NPC in this engine, which item
        // 15.7 recorded and item 16.7 did not change. Answering false is the
        // honest answer and is what the app answers too.
        false
    }

    @discardableResult
    func playCombatClip(_: CombatActorClip, on _: ReferenceKey) -> Bool {
        true
    }

    func writeCombatVariable(_: BehaviorVariableValue, named _: String) {}

    var combatTransients: CombatTransientCounts {
        .none
    }

    @discardableResult
    func trimCombatTransients(to _: CombatTransientLimits) -> CombatTransientCounts {
        CombatTransientCounts()
    }

    func despawnCombatTransients() {}

    func setCombatMusicActive(_: Bool) {}
}
