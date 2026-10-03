// The one place a condition asks for an actor's current state, like
// `GlobalResolution` and `QuestResolution`. `ConditionContext` may run off the
// main actor, so the main-actor caller builds this snapshot from the world
// state, the actor values, and the combat loop. Weapon state is optional: only
// the player has a graph that tracks it. See docs/engine/condition-functions.md
// and docs/engine/combat.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

/// One actor's state as a condition sees it.
nonisolated public struct ActorConditionState: ActorValueReadable, Equatable, Sendable {
    /// Current health, magicka and stamina.
    public var current: ActorValues
    /// Re-derived maximums, which is what `GetBaseActorValue` reports and what
    /// the percentage divides by.
    public var maximums: ActorValues
    /// Whether `ActorDeathState` has latched.
    public var isDead: Bool
    /// What the actor is doing about a fight, which `GetCombatState` reports.
    /// Hostility says how an actor feels; this says whether it acts on it.
    public var combatActivity: ActorCombatActivity
    /// Where this actor's weapon is, or nil when nothing in this session
    /// observes a draw state for it.
    public var weaponDrawState: WeaponDrawState?
    /// Who this actor is fighting, or nil when it is fighting nobody.
    public var combatTarget: ReferenceKey?
    /// Non-primary actor values this actor has moved off its baseline, so
    /// `GetActorValue` can answer for a resistance.
    public var general: [Int32: ActorValueEntry]
    /// Non-primary base values this actor's records author.
    public var generalBaseline: [Int32: Float]
    /// The actor's level, which `GetLevel` reports: the derived level for an NPC,
    /// and the character level for the player.
    public var level: Int
    /// Whether the actor's race is a child race, which `IsChild` reports.
    public var isChild: Bool
    /// What the left hand holds out, or nil when nothing observes it.
    public var leftHandOut: ActorLeftHandOut?

    public init(
        current: ActorValues,
        maximums: ActorValues,
        isDead: Bool = false,
        combatActivity: ActorCombatActivity = .notFighting,
        weaponDrawState: WeaponDrawState? = nil,
        combatTarget: ReferenceKey? = nil,
        general: [Int32: ActorValueEntry] = [:],
        generalBaseline: [Int32: Float] = [:],
        level: Int = PlayerLevelSource.startingLevel,
        isChild: Bool = false,
        leftHandOut: ActorLeftHandOut? = nil
    ) {
        self.current = current
        self.maximums = maximums
        self.isDead = isDead
        self.combatActivity = combatActivity
        self.weaponDrawState = weaponDrawState
        self.combatTarget = combatTarget
        self.general = general
        self.generalBaseline = generalBaseline
        self.level = max(PlayerLevelSource.startingLevel, level)
        self.isChild = isChild
        self.leftHandOut = leftHandOut
    }

    /// This actor's combat state as `GetCombatState` spells it: 0 "Not in combat",
    /// 1 "In combat", 2 "Searching" (Creation Kit wiki). Searching is read first,
    /// because a searching actor is also engaged. A dead actor is never in combat.
    /// It reads the behavior phase, not stored hostility.
    public var combatStateValue: Float {
        isDead ? 0 : Float(combatActivity.rawValue)
    }

    /// This actor's `IsWeaponOut` value, or nil when no draw state is observed.
    /// OpenSky reports 0 and 2, never 1 (fists only), because the melee runtime does
    /// not track an unarmed draw. See docs/engine/condition-functions.md.
    public var weaponOutValue: Float? {
        weaponDrawState.map { $0.isWeaponInHand ? 2 : 0 }
    }
}

/// What an actor holds out in its left hand: `IsTorchOut` and `IsShieldOut`.
nonisolated public enum ActorLeftHandOut: Equatable, Sendable {
    case nothing
    case torch
    case shield
}

/// Resolved actor state for a whole evaluation, keyed by reference.
///
/// A value type over a dictionary: cheap to build, cheap to copy, and unable to
/// go stale mid-evaluation the way a live read could.
nonisolated public struct ActorStateResolution: Sendable {
    /// No actor state at all, which is what a context with no world running
    /// carries. Every actor function is then a reason-tagged false and a tally
    /// bucket.
    public static let empty = ActorStateResolution()

    private let states: [ReferenceKey: ActorConditionState]

    public init(states: [ReferenceKey: ActorConditionState] = [:]) {
        self.states = states
    }

    /// `states` with both sides of one fight filled in: the player fights
    /// `playerTarget`, and every engaged living actor fights the player. The engine
    /// models every fight as one against the player. An angry but not yet engaged
    /// actor has no target, and a dead actor has none, as in `CombatLoopState.derive`.
    public static func fight(
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
    public func state(for key: ReferenceKey) -> ActorConditionState? {
        states[key]
    }

    /// Who `key` is fighting, or nil when it is fighting nobody and when
    /// nothing is known about it.
    public func combatTarget(of key: ReferenceKey) -> ReferenceKey? {
        states[key]?.combatTarget
    }

    /// True when nothing was wired, which is what a context with no world
    /// running carries.
    public var isEmpty: Bool {
        states.isEmpty
    }
}

nonisolated extension ActorStateResolution: ConditionResolution, ConditionCombatTargetResolving {}

nonisolated extension ConditionContext {
    /// The one seam actor values, death, hostility and the combat target come
    /// through, shaped exactly like the two above. Empty in a
    /// context with no world running, which makes every actor function a
    /// reason-tagged false rather than a convincing zero.
    public var actors: ActorStateResolution {
        get { self[resolution: ActorStateResolution.self] }
        set {
            self[resolution: ActorStateResolution.self] = newValue
            combatTargetResolver = newValue
        }
    }
}
