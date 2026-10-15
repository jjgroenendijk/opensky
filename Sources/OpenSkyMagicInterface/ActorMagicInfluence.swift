// What running magic effects make an actor do, read by the combat loop. Calm,
// Frenzy, Demoralize, Rally, Turn Undead, Paralysis, and Etherealize act through
// this, not through an actor value. See docs/engine/magic-archetypes.md.

import Foundation

/// The behaviour one actor's running effects force on it.
nonisolated public struct ActorMagicInfluence: Equatable, Sendable {
    /// Calm: the actor does not fight.
    public var isCalmed = false
    /// Frenzy: the actor attacks.
    public var isFrenzied = false
    /// Demoralize or Turn Undead: the actor runs away.
    public var isFrightened = false
    /// Rally: the actor does not run away.
    public var isRallied = false
    /// Paralysis: the actor cannot move or attack.
    public var isParalysed = false
    /// Etherealize: the actor deals and takes no damage.
    public var isEthereal = false

    public static let none = ActorMagicInfluence()

    public init(
        isCalmed: Bool = false,
        isFrenzied: Bool = false,
        isFrightened: Bool = false,
        isRallied: Bool = false,
        isParalysed: Bool = false,
        isEthereal: Bool = false
    ) {
        self.isCalmed = isCalmed
        self.isFrenzied = isFrenzied
        self.isFrightened = isFrightened
        self.isRallied = isRallied
        self.isParalysed = isParalysed
        self.isEthereal = isEthereal
    }

    /// Whether the actor flees. Rally wins over fear, because it sets the same
    /// confidence to its maximum.
    public var flees: Bool {
        isFrightened && !isRallied
    }

    /// Whether the actor refuses to fight. Frenzy raises the aggression Calm
    /// lowers, so the later effect would win in the game; OpenSky lets Calm win,
    /// because a calmed actor that attacks is the more harmful mistake.
    public var refusesCombat: Bool {
        isCalmed || isParalysed
    }

    /// Whether nothing forces any behaviour.
    public var isNone: Bool {
        self == .none
    }
}
