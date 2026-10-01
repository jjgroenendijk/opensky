// Cast input: held buttons become begin and release edges. A spell in the right hand
// takes the attack button, one in the left the block button, like `ArcheryIntent`; an
// empty hand leaves its button to melee. Held levels, because casting is a hold
// (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>). See docs/engine/spellcasting.md.

import Foundation
import OpenSkyGameData
import OpenSkyMagicInterface

/// One frame of cast intent, filled from the same drained camera input
/// `MeleeIntent` and `ArcheryIntent` are.
nonisolated public struct CastingIntent: Equatable, Sendable {
    /// Block button held, which the left hand takes when it holds a spell.
    public var leftHeld = false
    /// Attack button held, which the right hand takes when it holds a spell.
    public var rightHeld = false
    /// Seconds since the previous frame, for the charge and drain clocks.
    public var deltaTime: Float = 0

    public static let still = CastingIntent()

    public func isHeld(_ hand: SpellHand) -> Bool {
        switch hand {
        case .left: leftHeld
        case .right: rightHeld
        }
    }

    public init(leftHeld: Bool = false, rightHeld: Bool = false, deltaTime: Float = 0) {
        self.leftHeld = leftHeld
        self.rightHeld = rightHeld
        self.deltaTime = deltaTime
    }
}

extension CasterRuntime {
    /// Takes one frame of cast intent and advances both hands.
    ///
    /// Edges rather than levels: a button that went down begins a cast and one
    /// that came up releases it, so a held button does not restart the charge
    /// sixty times a second. A hand holding no spell is left alone entirely,
    /// which is what leaves its button to melee.
    public func acceptFrame(_ intent: CastingIntent, on caster: ActorValueHolder) {
        let readied = spellbook.state(of: caster)
        for hand in SpellHand.allCases {
            guard readied.spell(in: hand) != nil else {
                releaseIfHeld(hand, on: caster)
                continue
            }
            let held = intent.isHeld(hand)
            if held, !wasHeld(hand, on: caster.key) {
                begin(hand, on: caster)
            } else if !held, wasHeld(hand, on: caster.key) {
                release(hand, on: caster)
            }
            setHeld(hand, held, on: caster.key)
        }
        advance(delta: intent.deltaTime, on: caster)
    }

    /// Drops a cast whose hand no longer holds a spell — an unequip mid-cast,
    /// which is otherwise a charge nothing can ever release.
    private func releaseIfHeld(_ hand: SpellHand, on caster: ActorValueHolder) {
        guard wasHeld(hand, on: caster.key) || phase(of: hand, on: caster.key).isCasting
        else { return }
        cancel(hand, on: caster)
        setHeld(hand, false, on: caster.key)
    }
}
