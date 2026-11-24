// What the agent's `state player` shows of the player's casting hands.

import Foundation
public import OpenSkyFormatsESM

/// One of the player's hands as the caster sees it this frame.
nonisolated public struct PlayerCastingHand: Equatable, Sendable {
    public let hand: SpellHand
    public let phase: SpellCastPhase
    /// The spell the hand casts, nil while idle.
    public let spell: ReferenceKey?
    /// The spell readied in the spellbook for this hand.
    public let readied: ReferenceKey?
    /// Whether the cast button reached the caster on the last frame.
    public let pressed: Bool
    /// Whether a press made while sheathed holds the hand until it is let go.
    public let heldBySheathedPress: Bool
    /// What the graph hears as `bWantCastLeft` or `bWantCastRight`.
    public let wantsCast: Bool

    public init(
        hand: SpellHand, phase: SpellCastPhase, spell: ReferenceKey?, readied: ReferenceKey?,
        pressed: Bool, heldBySheathedPress: Bool, wantsCast: Bool
    ) {
        self.hand = hand
        self.phase = phase
        self.spell = spell
        self.readied = readied
        self.pressed = pressed
        self.heldBySheathedPress = heldBySheathedPress
        self.wantsCast = wantsCast
    }
}

/// Both hands and the casting cue line.
nonisolated public struct PlayerCastingReadout: Equatable, Sendable {
    public let hands: [PlayerCastingHand]
    public let cues: String

    public init(hands: [PlayerCastingHand], cues: String) {
        self.hands = hands
        self.cues = cues
    }
}
