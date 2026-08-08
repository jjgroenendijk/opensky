// The one place a condition asks "what is this actor's state right now?"
// (issue #375, roadmap item 15.8), mirroring `GlobalResolution` and
// `QuestResolution`.
//
// Shaped as a resolved snapshot rather than as a live handle for the reason the
// quest seam is: `ConditionContext` is a nonisolated value that a build thread
// may evaluate against, so it cannot reach into `WorldStateStore`,
// `ActorValueRuntime` or `CombatLoopRuntime`. The caller that *is* on the main
// actor builds one of these from all three and hands it over. Building one is a
// pass over the resident actors, which is the same pass the combat loop already
// makes each step.
//
// ## What one entry carries, and why each field is here
//
// Current values and maximums, because `GetActorValue`, `GetBaseActorValue` and
// `GetActorValuePercent` are the same read at three scalings and computing the
// fraction at the call site would let two of them disagree. Death, because
// `GetDead` is documented as the reliable answer where health is not. Hostility,
// because `GetCombatState` reads it. The weapon state, optional, because only
// the player has a graph that tracks one — an actor whose draw state nothing
// observes reports nil and the function says so rather than guessing sheathed.
// And the combat target, because CTDA run-on type 3 names it and it is per
// actor rather than per session.
//
// Documented in docs/formats/conditions.md and docs/engine/combat.md.

import Foundation

/// One actor's state as a condition sees it.
nonisolated struct ActorConditionState: Equatable, Sendable {
    /// Current health, magicka and stamina.
    var current: ActorValues
    /// Re-derived maximums, which is what `GetBaseActorValue` reports and what
    /// the percentage divides by.
    var maximums: ActorValues
    /// Whether `ActorDeathState` has latched.
    var isDead: Bool
    /// The actor's stored regard for the player.
    var hostility: ActorHostility
    /// Where this actor's weapon is, or nil when nothing in this session
    /// observes a draw state for it.
    var weaponDrawState: WeaponDrawState?
    /// Who this actor is fighting, or nil when it is fighting nobody.
    var combatTarget: ReferenceKey?

    init(
        current: ActorValues,
        maximums: ActorValues,
        isDead: Bool = false,
        hostility: ActorHostility = .neutral,
        weaponDrawState: WeaponDrawState? = nil,
        combatTarget: ReferenceKey? = nil
    ) {
        self.current = current
        self.maximums = maximums
        self.isDead = isDead
        self.hostility = hostility
        self.weaponDrawState = weaponDrawState
        self.combatTarget = combatTarget
    }

    /// This actor's combat state as `GetCombatState` spells it.
    ///
    /// Two of the three documented values are reachable. The Creation Kit wiki
    /// lists 0 "Not in combat", 1 "In combat" and 2 "Searching"; searching is a
    /// perception state, and perception is M16's, so no actor in this engine is
    /// ever in it. A dead actor is not in combat whatever its stored hostility
    /// says, which is the same rule `CombatLoopState.derive` applies.
    var combatStateValue: Float {
        !isDead && hostility == .hostile ? 1 : 0
    }

    /// This actor's `IsWeaponOut` value, or nil when no draw state is observed.
    ///
    /// The Creation Kit wiki documents three returns rather than a bool: 0 with
    /// nothing drawn, 1 with only fists out, and 2 with a weapon in either
    /// hand. OpenSky reports 0 and 2 and never 1, because the melee runtime
    /// tracks where the weapon is and not whether the actor is unarmed while it
    /// is out; an unarmed actor with its hands up therefore reads as 2. That is
    /// a stated deviation rather than a silent one — see
    /// docs/formats/conditions.md.
    var weaponOutValue: Float? {
        weaponDrawState.map { $0.isWeaponInHand ? 2 : 0 }
    }
}

/// Resolved actor state for a whole evaluation, keyed by reference.
///
/// A value type over a dictionary: cheap to build, cheap to copy, and unable to
/// go stale mid-evaluation the way a live read could.
nonisolated struct ActorStateResolution: Sendable {
    /// No actor state at all, which is what a context with no world running
    /// carries. Every actor function is then a reason-tagged false and a tally
    /// bucket.
    static let empty = ActorStateResolution()

    private let states: [ReferenceKey: ActorConditionState]

    init(states: [ReferenceKey: ActorConditionState] = [:]) {
        self.states = states
    }

    /// `states` with 15.7's two directions of one fight filled in: the player
    /// fights `playerTarget`, and every hostile living actor fights the player.
    ///
    /// That second half is not an assumption bolted on here — it is the whole
    /// of 15.7's model, where hostility means "this actor fights the player"
    /// and nothing else. Filling both directions is what lets a combat-target
    /// run-on evaluate from either side of a fight; leaving the NPC side out
    /// would make half the conditions in a vanilla combat package fail for a
    /// reason that has nothing to do with the package.
    ///
    /// A dead actor is given no target, matching `CombatLoopState.derive`: a
    /// corpse is not fighting anybody, whatever hostility it died carrying.
    static func fight(
        states: [ReferenceKey: ActorConditionState],
        playerKey: ReferenceKey,
        playerTarget: ReferenceKey?
    ) -> ActorStateResolution {
        var resolved = states
        for (key, state) in states {
            guard !state.isDead else { continue }
            if key == playerKey {
                resolved[key]?.combatTarget = playerTarget
            } else if state.hostility == .hostile {
                resolved[key]?.combatTarget = playerKey
            }
        }
        return ActorStateResolution(states: resolved)
    }

    /// `key`'s state, or nil when this resolution carries none for it.
    func state(for key: ReferenceKey) -> ActorConditionState? {
        states[key]
    }

    /// Who `key` is fighting, or nil when it is fighting nobody and when
    /// nothing is known about it.
    func combatTarget(of key: ReferenceKey) -> ReferenceKey? {
        states[key]?.combatTarget
    }

    /// Actors this resolution knows about.
    var count: Int {
        states.count
    }

    /// True when nothing was wired, which is what a context with no world
    /// running carries.
    var isEmpty: Bool {
        states.isEmpty
    }
}
