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
nonisolated struct ActorConditionState: ActorValueReadable, Equatable, Sendable {
    /// Current health, magicka and stamina.
    var current: ActorValues
    /// Re-derived maximums, which is what `GetBaseActorValue` reports and what
    /// the percentage divides by.
    var maximums: ActorValues
    /// Whether `ActorDeathState` has latched.
    var isDead: Bool
    /// The actor's stored regard for the player.
    var hostility: ActorHostility
    /// What the actor is actually doing about a fight, which is what
    /// `GetCombatState` reports (issue #424). Hostility says how an actor feels;
    /// this says whether it is currently acting on it.
    var combatActivity: ActorCombatActivity
    /// Where this actor's weapon is, or nil when nothing in this session
    /// observes a draw state for it.
    var weaponDrawState: WeaponDrawState?
    /// Who this actor is fighting, or nil when it is fighting nobody.
    var combatTarget: ReferenceKey?
    /// Non-primary actor values this actor has moved off its baseline
    /// (issue #468), which is what lets `GetActorValue` answer for a resistance
    /// rather than tally a miss.
    var general: [Int32: ActorValueEntry]
    /// Non-primary base values this actor's records author.
    var generalBaseline: [Int32: Float]
    /// Whether this actor is the player, which is what the resistance cap
    /// depends on.
    var isPlayer: Bool

    init(
        current: ActorValues,
        maximums: ActorValues,
        isDead: Bool = false,
        hostility: ActorHostility = .neutral,
        combatActivity: ActorCombatActivity = .notFighting,
        weaponDrawState: WeaponDrawState? = nil,
        combatTarget: ReferenceKey? = nil,
        general: [Int32: ActorValueEntry] = [:],
        generalBaseline: [Int32: Float] = [:],
        isPlayer: Bool = false
    ) {
        self.current = current
        self.maximums = maximums
        self.isDead = isDead
        self.hostility = hostility
        self.combatActivity = combatActivity
        self.weaponDrawState = weaponDrawState
        self.combatTarget = combatTarget
        self.general = general
        self.generalBaseline = generalBaseline
        self.isPlayer = isPlayer
    }

    /// This actor's combat state as `GetCombatState` spells it.
    ///
    /// All three documented values are reachable as of 16.7. The Creation Kit
    /// wiki lists 0 "Not in combat", 1 "In combat" and 2 "Searching"; searching
    /// is the phase an actor enters when 16.6 detection loses the target it was
    /// fighting, and it is read *before* fighting because a searching actor is
    /// also engaged. A dead actor is not in combat whatever else it carries,
    /// which is the same rule `CombatLoopState.derive` applies.
    ///
    /// Read from the behavior phase rather than from stored hostility: an actor
    /// that hates the player but has not perceived them yet, and one that
    /// searched and gave up, are both hostile and neither is in a fight.
    var combatStateValue: Float {
        isDead ? 0 : Float(combatActivity.rawValue)
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

    /// `states` with both directions of one fight filled in: the player fights
    /// `playerTarget`, and every *engaged* living actor fights the player.
    ///
    /// That second half is not an assumption bolted on here — it is the whole
    /// of the engine's model, where a fight is against the player and nothing
    /// else. Filling both directions is what lets a combat-target run-on
    /// evaluate from either side of a fight; leaving the NPC side out would make
    /// half the conditions in a vanilla combat package fail for a reason that
    /// has nothing to do with the package.
    ///
    /// Engaged rather than hostile since 16.7: an actor that is angry but has
    /// not started fighting has no combat target, exactly as `GetCombatState`
    /// reports 0 for it.
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
            } else if state.combatActivity != .notFighting {
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
